# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.So101.Calibrate do
  @shortdoc "Calibrate servo range of motion and center points"
  @moduledoc """
  Calibrates servo range of motion by moving each joint until it stalls,
  then calculates and sets the center point offset.

  ## Usage

      mix so101.calibrate PORT [OPTIONS]

  ## Arguments

    * `PORT` - Serial port (e.g., /dev/ttyUSB0 or /dev/ttyACM0)

  ## Options

    * `--baud-rate`, `-b` - Baud rate (default: 1000000)
    * `--torque`, `-t` - Torque limit during calibration as percentage (default: 30)
    * `--speed`, `-s` - Movement speed in degrees/sec (default: 30)
    * `--load-threshold`, `-l` - Load threshold for stall detection as percentage (default: 50)
    * `--servo`, `-S` - Calibrate only specific servo ID (can be repeated)
    * `--dry-run`, `-n` - Show what would be done without writing offsets

  ## Process

  For each servo, the calibration:

  1. Reduces torque limit for safety
  2. Commands movement toward one mechanical limit
  3. Monitors load until stall is detected
  4. Records the stall position
  5. Commands movement toward opposite limit
  6. Records that stall position
  7. Calculates the mechanical center
  8. Sets position_offset so center corresponds to 0 radians

  ## Safety

  The servo will move with reduced torque during calibration. Ensure
  the robot is in a safe position and nothing will obstruct movement.

  ## Example

      # Calibrate all servos
      mix so101.calibrate /dev/ttyUSB0

      # Calibrate with lower torque
      mix so101.calibrate /dev/ttyUSB0 --torque 20

      # Calibrate specific servos only
      mix so101.calibrate /dev/ttyUSB0 --servo 1 --servo 2

      # Dry run to see calculations without applying
      mix so101.calibrate /dev/ttyUSB0 --dry-run
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [
    baud_rate: :integer,
    torque: :integer,
    speed: :integer,
    load_threshold: :integer,
    servo: [:integer, :keep],
    dry_run: :boolean
  ]

  @aliases [
    b: :baud_rate,
    t: :torque,
    s: :speed,
    l: :load_threshold,
    S: :servo,
    n: :dry_run
  ]

  @joints [
    {:shoulder_pan, 1},
    {:shoulder_lift, 2},
    {:elbow_flex, 3},
    {:wrist_flex, 4},
    {:wrist_roll, 5},
    {:gripper, 6}
  ]

  @steps_per_revolution 4096
  @center_position div(@steps_per_revolution, 2)

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
    torque_percent = Keyword.get(opts, :torque, 30)
    speed_dps = Keyword.get(opts, :speed, 30)
    load_threshold = Keyword.get(opts, :load_threshold, 50)
    servo_filter = Keyword.get_values(opts, :servo)
    dry_run = Keyword.get(opts, :dry_run, false)

    config = %{
      torque_limit: torque_percent / 100.0,
      speed: degrees_to_rad_per_sec(speed_dps),
      load_threshold: load_threshold,
      dry_run: dry_run
    }

    joints_to_calibrate =
      if servo_filter == [] do
        @joints
      else
        Enum.filter(@joints, fn {_name, id} -> id in servo_filter end)
      end

    print_header(config, dry_run)

    Mix.shell().info("Connecting to #{port} at #{format_baud(baud_rate)}...")

    case Feetech.start_link(port: port, baud_rate: baud_rate, timeout: 200) do
      {:ok, pid} ->
        try do
          run_calibration(pid, joints_to_calibrate, config)
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

  defp print_header(config, dry_run) do
    mode = if dry_run, do: " (DRY RUN)", else: ""

    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║              SO-101 Servo Calibration#{String.pad_trailing(mode, 18)}║
    ╚═══════════════════════════════════════════════════════════════╝

    Configuration:
      Torque limit: #{round(config.torque_limit * 100)}%
      Speed: #{round(rad_to_degrees(config.speed))}/sec
      Load threshold: #{config.load_threshold}%

    ⚠️  WARNING: Servos will move during calibration!
    Ensure the robot is in a safe position with no obstructions.
    """)
  end

  defp run_calibration(pid, joints, config) do
    Mix.shell().info("Press Enter to begin calibration, or 'q' to quit...")

    case prompt_continue() do
      :continue ->
        results = calibrate_joints(pid, joints, config, [])
        print_summary(results, config.dry_run)

      :quit ->
        Mix.shell().info("Calibration cancelled.")
    end
  end

  defp calibrate_joints(_pid, [], _config, results), do: Enum.reverse(results)

  defp calibrate_joints(pid, [{joint, servo_id} | rest], config, results) do
    Mix.shell().info("""

    ────────────────────────────────────────────────────────────────
    Calibrating: #{format_joint(joint)} (Servo ID #{servo_id})
    ────────────────────────────────────────────────────────────────
    """)

    case ping_servo(pid, servo_id) do
      :ok ->
        result = calibrate_single_servo(pid, servo_id, joint, config)
        calibrate_joints(pid, rest, config, [{joint, servo_id, result} | results])

      {:error, reason} ->
        Mix.shell().error("Servo #{servo_id} not responding: #{inspect(reason)}")
        Mix.shell().info("Press Enter to skip, or 'q' to quit...")

        case prompt_continue() do
          :continue ->
            calibrate_joints(pid, rest, config, [{joint, servo_id, :not_found} | results])

          :quit ->
            Enum.reverse([{joint, servo_id, :cancelled} | results])
        end
    end
  end

  defp calibrate_single_servo(pid, servo_id, joint, config) do
    with :ok <- save_original_settings(pid, servo_id),
         :ok <- apply_calibration_settings(pid, servo_id, config),
         {:ok, low_pos} <- find_limit(pid, servo_id, :low, config),
         {:ok, high_pos} <- find_limit(pid, servo_id, :high, config),
         :ok <- restore_torque(pid, servo_id) do
      process_calibration_result(pid, servo_id, joint, low_pos, high_pos, config)
    else
      {:error, reason} ->
        Mix.shell().error("Calibration failed: #{inspect(reason)}")
        restore_torque(pid, servo_id)
        {:error, reason}
    end
  end

  defp save_original_settings(pid, servo_id) do
    case Feetech.read(pid, servo_id, :torque_limit) do
      {:ok, _limit} -> :ok
      {:error, reason} -> {:error, {:read_settings, reason}}
    end
  end

  defp apply_calibration_settings(pid, servo_id, config) do
    Mix.shell().info("Setting torque limit to #{round(config.torque_limit * 100)}%...")

    with {:ok, _} <- Feetech.write(pid, servo_id, :torque_enable, true, await_response: true),
         {:ok, _} <-
           Feetech.write(pid, servo_id, :torque_limit, config.torque_limit, await_response: true) do
      :ok
    else
      {:error, reason} -> {:error, {:apply_settings, reason}}
    end
  end

  defp restore_torque(pid, servo_id) do
    Feetech.write(pid, servo_id, :torque_limit, 1.0)
    :ok
  end

  defp find_limit(pid, servo_id, direction, config) do
    target =
      case direction do
        :low -> 0
        :high -> @steps_per_revolution - 1
      end

    dir_label = if direction == :low, do: "minimum", else: "maximum"
    Mix.shell().info("Moving toward #{dir_label} position...")

    Feetech.write(pid, servo_id, :goal_speed, config.speed)
    Feetech.write_raw(pid, servo_id, :goal_position, target)

    wait_for_stall(pid, servo_id, config.load_threshold, direction)
  end

  defp wait_for_stall(pid, servo_id, load_threshold, direction) do
    Process.sleep(100)
    do_wait_for_stall(pid, servo_id, load_threshold, direction, 0, nil)
  end

  defp do_wait_for_stall(pid, servo_id, load_threshold, direction, stable_count, last_pos) do
    case read_servo_state(pid, servo_id) do
      {:ok, state} ->
        load_magnitude = abs(state.load)
        moving = state.moving
        current_pos = state.position_raw

        progress_char = progress_indicator(load_magnitude, load_threshold)

        IO.write(
          "\r  Load: #{String.pad_leading("#{round(load_magnitude)}%", 4)} #{progress_char}  "
        )

        cond do
          load_magnitude >= load_threshold ->
            IO.write("\n")
            Mix.shell().info("Stall detected at load #{round(load_magnitude)}%")
            {:ok, current_pos}

          not moving and last_pos != nil and abs(current_pos - last_pos) < 5 ->
            new_stable = stable_count + 1

            if new_stable > 10 do
              IO.write("\n")
              Mix.shell().info("Movement stopped (position stable)")
              {:ok, current_pos}
            else
              Process.sleep(50)
              do_wait_for_stall(pid, servo_id, load_threshold, direction, new_stable, current_pos)
            end

          true ->
            Process.sleep(50)
            do_wait_for_stall(pid, servo_id, load_threshold, direction, 0, current_pos)
        end

      {:error, reason} ->
        {:error, {:read_state, reason}}
    end
  end

  defp read_servo_state(pid, servo_id) do
    with {:ok, position_raw} <- Feetech.read_raw(pid, servo_id, :present_position),
         {:ok, load} <- Feetech.read(pid, servo_id, :present_load),
         {:ok, moving} <- Feetech.read(pid, servo_id, :moving) do
      {:ok, %{position_raw: position_raw, load: load, moving: moving}}
    end
  end

  defp progress_indicator(load, threshold) do
    filled = round(load / threshold * 10) |> min(10)
    empty = 10 - filled
    "[#{String.duplicate("█", filled)}#{String.duplicate("░", empty)}]"
  end

  defp process_calibration_result(pid, servo_id, joint, low_pos, high_pos, config) do
    range_steps = high_pos - low_pos
    range_degrees = steps_to_degrees(range_steps)
    mechanical_center = div(low_pos + high_pos, 2)
    offset = @center_position - mechanical_center

    Mix.shell().info("""

    Calibration results for #{format_joint(joint)}:
      Low limit:  #{low_pos} steps (#{format_degrees(steps_to_degrees(low_pos))})
      High limit: #{high_pos} steps (#{format_degrees(steps_to_degrees(high_pos))})
      Range:      #{range_steps} steps (#{format_degrees(range_degrees)})
      Mechanical center: #{mechanical_center} steps
      Required offset:   #{offset} steps
    """)

    if config.dry_run do
      Mix.shell().info("(Dry run - offset not applied)")
      {:ok, %{low: low_pos, high: high_pos, center: mechanical_center, offset: offset}}
    else
      apply_offset(pid, servo_id, offset)
    end
  end

  defp apply_offset(pid, servo_id, offset) do
    Mix.shell().info("Applying position offset...")

    with :ok <- unlock_eeprom(pid, servo_id),
         {:ok, _} <- Feetech.write_raw(pid, servo_id, :position_offset, clamp_offset(offset)),
         :ok <- lock_eeprom(pid, servo_id) do
      Mix.shell().info("✓ Offset applied successfully")
      {:ok, %{offset: offset}}
    else
      {:error, reason} ->
        Mix.shell().error("Failed to apply offset: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp clamp_offset(offset) do
    offset
    |> max(-2048)
    |> min(2047)
    |> then(fn o -> if o < 0, do: o + 65536, else: o end)
  end

  defp unlock_eeprom(pid, servo_id) do
    case Feetech.write_raw(pid, servo_id, :lock, 0) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp lock_eeprom(pid, servo_id) do
    case Feetech.write_raw(pid, servo_id, :lock, 1) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp ping_servo(pid, servo_id) do
    case Feetech.ping(pid, servo_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp print_summary(results, dry_run) do
    Mix.shell().info("""

    ════════════════════════════════════════════════════════════════
                         CALIBRATION SUMMARY
    ════════════════════════════════════════════════════════════════
    """)

    for {joint, servo_id, result} <- results do
      status =
        case result do
          {:ok, data} when is_map(data) ->
            offset = Map.get(data, :offset, "?")
            "✓ Offset: #{offset} steps"

          :not_found ->
            "○ Not found"

          :cancelled ->
            "○ Cancelled"

          {:error, reason} ->
            "✗ Error: #{inspect(reason)}"
        end

      Mix.shell().info("  #{format_joint(joint)} (ID #{servo_id}): #{status}")
    end

    Mix.shell().info("")

    if dry_run do
      Mix.shell().info("This was a dry run. No changes were written to the servos.")
      Mix.shell().info("Run without --dry-run to apply the offsets.")
    else
      successful = Enum.count(results, fn {_, _, r} -> match?({:ok, _}, r) end)
      Mix.shell().info("#{successful} servo(s) calibrated successfully.")
    end
  end

  defp prompt_continue do
    case IO.gets("") do
      :eof ->
        :quit

      {:error, _} ->
        :quit

      data ->
        case String.trim(data) |> String.downcase() do
          "q" -> :quit
          _ -> :continue
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

  defp degrees_to_rad_per_sec(dps), do: dps * :math.pi() / 180.0

  defp rad_to_degrees(rad), do: rad * 180.0 / :math.pi()

  defp steps_to_degrees(steps), do: steps * 360.0 / @steps_per_revolution

  defp format_degrees(deg), do: "#{:erlang.float_to_binary(deg, decimals: 1)}°"
end
