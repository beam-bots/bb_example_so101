# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.So101.Calibrate do
  @shortdoc "Calibrate servo range of motion and center points"
  @moduledoc """
  Calibrates servo range of motion by having the user manually move the arm
  through its full range while tracking min/max positions for all joints.

  ## Usage

      mix so101.calibrate PORT [OPTIONS]

  ## Arguments

    * `PORT` - Serial port (e.g., /dev/ttyUSB0 or /dev/ttyACM0)

  ## Options

    * `--baud-rate`, `-b` - Baud rate (default: 1000000)
    * `--dry-run`, `-n` - Show what would be done without writing offsets

  ## Process

  1. Disables torque on ALL servos so you can move the arm freely
  2. Move every joint through its FULL range of motion
  3. The display shows live min/max tracking for each joint
  4. Press Enter when done
  5. Calculates mechanical center for each joint
  6. Sets position_offset so center corresponds to 0 radians

  ## Example

      mix so101.calibrate /dev/ttyUSB0
      mix so101.calibrate /dev/ttyUSB0 --dry-run
  """

  use Mix.Task

  require Logger

  @switches [
    baud_rate: :integer,
    dry_run: :boolean
  ]

  @aliases [
    b: :baud_rate,
    n: :dry_run
  ]

  # Joints in order from base to gripper
  @joints [
    {:shoulder_pan, 1, "Base"},
    {:shoulder_lift, 2, "Shoulder"},
    {:elbow_flex, 3, "Elbow"},
    {:wrist_flex, 4, "Wrist"},
    {:wrist_roll, 5, "Roll"},
    {:gripper, 6, "Grip"}
  ]

  @steps_per_revolution 4096
  @center_position div(@steps_per_revolution, 2)
  @max_offset_magnitude 2047

  @impl Mix.Task
  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    case args do
      [port] ->
        calibrate_servos(port, opts)

      _ ->
        Mix.shell().error("Usage: mix so101.calibrate PORT [OPTIONS]")
        Mix.shell().error("Run `mix help so101.calibrate` for more information.")
        exit({:shutdown, 1})
    end
  end

  defp calibrate_servos(port, opts) do
    baud_rate = Keyword.get(opts, :baud_rate, 1_000_000)
    dry_run = Keyword.get(opts, :dry_run, false)

    print_header(dry_run)

    Mix.shell().info("Connecting to #{port} at #{format_baud(baud_rate)}...")

    case Feetech.start_link(port: port, baud_rate: baud_rate, timeout: 200) do
      {:ok, pid} ->
        try do
          run_calibration(pid, dry_run)
        after
          Feetech.stop(pid)
        end

      {:error, :enoent} ->
        Mix.shell().error("\nError: Port #{port} not found.")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("\nFailed to connect: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_header(dry_run) do
    mode = if dry_run, do: " (DRY RUN)", else: ""

    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║         SO-101 Manual Servo Calibration#{String.pad_trailing(mode, 14)}║
    ╚═══════════════════════════════════════════════════════════════╝

    This will disable torque on ALL servos so you can move the arm freely.

    Move EVERY joint through its FULL range of motion (to both limits).
    Press Enter when done to record the ranges and calculate offsets.

    """)
  end

  defp run_calibration(pid, dry_run) do
    # Verify all servos are present
    {found, missing} = check_servos(pid)

    if missing != [] do
      Mix.shell().error("Missing servos: #{inspect(Enum.map(missing, fn {_, id, _} -> id end))}")
      Mix.shell().info("Continue anyway? (y/n)")

      case IO.gets("") do
        data when is_binary(data) ->
          if String.trim(data) |> String.downcase() != "y" do
            Mix.shell().info("Calibration cancelled.")
            return_early()
          end

        _ ->
          return_early()
      end
    end

    if found == [] do
      Mix.shell().error("No servos found!")
      return_early()
    end

    Mix.shell().info(
      "Found #{length(found)} servo(s). Press Enter to disable torque and begin..."
    )

    case IO.gets("") do
      data when is_binary(data) ->
        if String.trim(data) |> String.downcase() == "q" do
          Mix.shell().info("Calibration cancelled.")
        else
          do_calibration(pid, found, dry_run)
        end

      _ ->
        Mix.shell().info("Calibration cancelled.")
    end
  end

  defp return_early, do: :ok

  defp check_servos(pid) do
    Enum.split_with(@joints, fn {_name, servo_id, _desc} ->
      case Feetech.ping(pid, servo_id) do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end

  defp do_calibration(pid, joints, dry_run) do
    # Reset position offsets and disable torque on all servos
    Mix.shell().info("\nPreparing servos...")

    for {_name, servo_id, _desc} <- joints do
      reset_position_offset(pid, servo_id)
      disable_torque(pid, servo_id)
    end

    Mix.shell().info("""

    ═══════════════════════════════════════════════════════════════
    Torque DISABLED on all servos. Move the arm freely now!

    Move each joint to BOTH of its mechanical limits.
    Press Enter when you've moved all joints through their full range.
    ═══════════════════════════════════════════════════════════════
    """)

    # Track all positions simultaneously
    results = track_all_positions(pid, joints)

    # Process results and apply offsets (torque still disabled)
    process_all_results(pid, joints, results, dry_run)

    Mix.shell().info("""

    ⚠️  Torque remains DISABLED on all servos.
    Manually power cycle or restart the robot to re-enable torque safely.
    """)
  end

  defp track_all_positions(pid, joints) do
    # Read initial positions - track both raw and unwrapped positions
    # Unwrapped positions handle the 0/4095 wraparound
    initial_state =
      for {name, servo_id, desc} <- joints, into: %{} do
        case Feetech.read_raw(pid, servo_id, :present_position) do
          {:ok, pos} ->
            {servo_id,
             %{
               name: name,
               desc: desc,
               raw: pos,
               unwrapped: pos,
               min_unwrapped: pos,
               max_unwrapped: pos
             }}

          _ ->
            {servo_id,
             %{name: name, desc: desc, raw: 0, unwrapped: 0, min_unwrapped: 0, max_unwrapped: 0}}
        end
      end

    # Print initial blank lines for the display (so cursor-up works)
    for _ <- joints, do: IO.puts("")

    # Start tracking loop
    tracker_pid = spawn_link(fn -> position_tracker_loop(pid, joints, initial_state) end)

    # Wait for user to press Enter
    IO.gets("")

    # Stop tracking and get results
    send(tracker_pid, {:get_results, self()})

    receive do
      {:results, state} -> state
    after
      1000 -> initial_state
    end
  end

  defp position_tracker_loop(pid, joints, state) do
    receive do
      {:get_results, caller} ->
        send(caller, {:results, state})
    after
      50 ->
        # Read all positions
        new_state =
          Enum.reduce(joints, state, fn {_name, servo_id, _desc}, acc ->
            case Feetech.read_raw(pid, servo_id, :present_position) do
              {:ok, raw_pos} ->
                update_in(acc, [servo_id], fn data ->
                  # Unwrap position to handle 0/4095 boundary crossing
                  unwrapped = unwrap_position(raw_pos, data.raw, data.unwrapped)

                  %{
                    data
                    | raw: raw_pos,
                      unwrapped: unwrapped,
                      min_unwrapped: min(data.min_unwrapped, unwrapped),
                      max_unwrapped: max(data.max_unwrapped, unwrapped)
                  }
                end)

              _ ->
                acc
            end
          end)

        # Display current state
        display_tracking_state(new_state, joints)

        position_tracker_loop(pid, joints, new_state)
    end
  end

  # Handle position wraparound at 0/4095 boundary
  defp unwrap_position(current_raw, last_raw, last_unwrapped) do
    delta = current_raw - last_raw

    cond do
      # Large positive jump means we wrapped backwards (e.g., 100 -> 4000)
      delta > 2048 ->
        last_unwrapped + delta - @steps_per_revolution

      # Large negative jump means we wrapped forwards (e.g., 4000 -> 100)
      delta < -2048 ->
        last_unwrapped + delta + @steps_per_revolution

      # Normal movement
      true ->
        last_unwrapped + delta
    end
  end

  @bar_width 30

  defp display_tracking_state(state, joints) do
    # Move cursor up to overwrite previous display (one line per joint)
    num_lines = length(joints)
    IO.write("\e[#{num_lines}A")

    for {_name, servo_id, desc} <- joints do
      data = state[servo_id]
      range = data.max_unwrapped - data.min_unwrapped

      bar =
        if range > 0 do
          # Calculate position within the range (0.0 to 1.0)
          pos_in_range = (data.unwrapped - data.min_unwrapped) / range
          filled = round(pos_in_range * @bar_width)
          filled = max(0, min(@bar_width, filled))

          # Build the bar with the position marker
          left = String.duplicate("█", filled)
          right = String.duplicate("░", @bar_width - filled)
          left <> right
        else
          String.duplicate("░", @bar_width)
        end

      # Format: "Base:     [████████░░░░░░░░] 1234 steps (108.5°)"
      label = String.pad_trailing(desc, 9)
      range_str = String.pad_leading("#{range}", 4)
      degrees = format_degrees(steps_to_degrees(range))

      IO.write("\r  #{label} [#{bar}] #{range_str} steps (#{degrees})\e[K\n")
    end
  end

  defp process_all_results(pid, joints, state, dry_run) do
    Mix.shell().info("""

    ════════════════════════════════════════════════════════════════
                         CALIBRATION RESULTS
    ════════════════════════════════════════════════════════════════
    """)

    results =
      for {name, servo_id, _desc} <- joints do
        data = state[servo_id]
        range = data.max_unwrapped - data.min_unwrapped

        if range > 10 do
          # Calculate center in unwrapped space, then convert to raw (0-4095)
          center_unwrapped = div(data.min_unwrapped + data.max_unwrapped, 2)
          center_raw = Integer.mod(center_unwrapped, @steps_per_revolution)

          # Firmware applies: Present_Position = Actual_Position - Offset
          # So: 2048 = center_raw - offset, therefore offset = center_raw - 2048
          # Clamp to ±2047 (sign_magnitude bit 11 limit).
          offset = center_raw - @center_position
          offset = max(-@max_offset_magnitude, min(@max_offset_magnitude, offset))

          Mix.shell().info("""
            #{format_joint(name)} (ID #{servo_id}):
              Range: #{range} steps (#{format_degrees(steps_to_degrees(range))})
              Center: #{center_raw} -> Offset: #{offset}
          """)

          if dry_run do
            {name, servo_id, {:ok, %{range: range, center: center_raw, offset: offset}}}
          else
            case apply_calibration(pid, servo_id, offset) do
              :ok -> {name, servo_id, {:ok, %{offset: offset}}}
              {:error, reason} -> {name, servo_id, {:error, reason}}
            end
          end
        else
          Mix.shell().info("  #{format_joint(name)} (ID #{servo_id}): Skipped (not moved enough)")
          {name, servo_id, {:error, :not_moved}}
        end
      end

    print_summary(results, dry_run)
  end

  defp reset_position_offset(pid, servo_id) do
    unlock_eeprom(pid, servo_id)

    case Feetech.write_raw(pid, servo_id, :position_offset, 0, await_response: true) do
      {:ok, _} ->
        :ok

      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to reset offset for servo #{servo_id}: #{inspect(reason)}")
    end

    lock_eeprom(pid, servo_id)

    # After resetting offset, update goal_position to match new present_position
    # Otherwise the servo will jump when torque is re-enabled
    case Feetech.read_raw(pid, servo_id, :present_position) do
      {:ok, pos} ->
        Feetech.write_raw(pid, servo_id, :goal_position, pos, await_response: true)

      _ ->
        :ok
    end

    :ok
  end

  defp disable_torque(pid, servo_id) do
    Feetech.write(pid, servo_id, :torque_enable, false, await_response: true)
    :ok
  end

  defp apply_calibration(pid, servo_id, offset) do
    with :ok <- unlock_eeprom(pid, servo_id),
         {:ok, _} <-
           Feetech.write(pid, servo_id, :position_offset, offset, await_response: true),
         :ok <- verify_offset(pid, servo_id, offset),
         {:ok, _} <-
           Feetech.write_raw(pid, servo_id, :min_angle_limit, 0, await_response: true),
         {:ok, _} <-
           Feetech.write_raw(pid, servo_id, :max_angle_limit, 4095, await_response: true),
         :ok <- lock_eeprom(pid, servo_id) do
      Feetech.write(pid, servo_id, :torque_enable, false, await_response: true)
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_offset(pid, servo_id, expected_offset) do
    case Feetech.read(pid, servo_id, :position_offset) do
      {:ok, actual_offset} ->
        if actual_offset == expected_offset do
          :ok
        else
          Logger.warning(
            "Servo #{servo_id}: offset mismatch! wrote #{expected_offset}, read back #{actual_offset}"
          )

          {:error, :offset_mismatch}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unlock_eeprom(pid, servo_id) do
    case Feetech.write_raw(pid, servo_id, :lock, 0, await_response: true) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp lock_eeprom(pid, servo_id) do
    case Feetech.write_raw(pid, servo_id, :lock, 1, await_response: true) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp print_summary(results, dry_run) do
    Mix.shell().info("")

    successful = Enum.count(results, fn {_, _, r} -> match?({:ok, _}, r) end)
    failed = length(results) - successful

    if dry_run do
      Mix.shell().info("DRY RUN: #{successful} joint(s) would be calibrated.")
      Mix.shell().info("Run without --dry-run to apply the offsets.")
    else
      Mix.shell().info("#{successful} joint(s) calibrated successfully.")

      if failed > 0 do
        Mix.shell().info("#{failed} joint(s) skipped or failed.")
      end
    end
  end

  defp format_joint(joint) do
    joint
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_baud(rate) when rate >= 1_000_000, do: "#{div(rate, 1_000_000)}M baud"
  defp format_baud(rate) when rate >= 1000, do: "#{div(rate, 1000)}k baud"
  defp format_baud(rate), do: "#{rate} baud"

  defp steps_to_degrees(steps), do: steps * 360.0 / @steps_per_revolution

  defp format_degrees(deg), do: "#{:erlang.float_to_binary(deg, decimals: 1)}°"
end
