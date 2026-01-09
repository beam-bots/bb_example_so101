# SPDX-FileCopyrightText: 2025 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule Mix.Tasks.So101.SetupServos do
  @shortdoc "Interactive wizard to configure servo IDs for SO-101 arm"
  @moduledoc """
  Interactive wizard to configure servo IDs for the SO-101 robot arm.

  This task guides you through connecting each servo one at a time and
  assigns the correct ID for each joint position. Servos typically ship
  with a default ID of 1, so this process ensures each servo gets a unique
  ID matching its position in the kinematic chain.

  ## Usage

      mix so101.setup_servos PORT [OPTIONS]

  ## Arguments

    * `PORT` - Serial port (e.g., /dev/ttyUSB0 or /dev/ttyACM0)

  ## Options

    * `--baud-rate`, `-b` - Baud rate (default: 1000000)

  ## Joint Configuration

  The SO-101 arm has 6 joints, each requiring a unique servo ID:

  | Joint          | Servo ID | Description                    |
  |----------------|----------|--------------------------------|
  | shoulder_pan   | 1        | Base rotation                  |
  | shoulder_lift  | 2        | Shoulder up/down               |
  | elbow_flex     | 3        | Elbow bend                     |
  | wrist_flex     | 4        | Wrist up/down                  |
  | wrist_roll     | 5        | Wrist rotation                 |
  | gripper        | 6        | Gripper open/close             |

  ## Process

  The wizard will:

  1. Ask you to connect only ONE servo at a time to the controller board
  2. Scan using broadcast ID to find the connected servo
  3. Set its ID to the correct value for that joint
  4. Verify the new ID works
  5. Repeat for each of the 6 joints

  ## Example

      mix so101.setup_servos /dev/ttyUSB0

  ## Tips

  - Start with all servos disconnected from the bus
  - Connect servos one at a time as prompted
  - Ensure the power supply is connected to the controller board
  - You can skip already-configured servos by pressing 's'
  """

  use Mix.Task

  @requirements ["app.start"]

  @switches [
    baud_rate: :integer
  ]

  @aliases [
    b: :baud_rate
  ]

  @joints [
    {:shoulder_pan, 1, "Base rotation (connects to controller board)"},
    {:shoulder_lift, 2, "Shoulder up/down"},
    {:elbow_flex, 3, "Elbow bend"},
    {:wrist_flex, 4, "Wrist up/down"},
    {:wrist_roll, 5, "Wrist rotation"},
    {:gripper, 6, "Gripper open/close"}
  ]

  @broadcast_id 0xFE

  @impl Mix.Task
  def run(args) do
    {opts, args} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)

    case args do
      [port] ->
        setup_servos(port, opts)

      _ ->
        Mix.shell().error("Usage: mix so101.setup_servos PORT [OPTIONS]")
        Mix.shell().error("Run `mix help so101.setup_servos` for more information.")
        exit({:shutdown, 1})
    end
  end

  defp setup_servos(port, opts) do
    baud_rate = Keyword.get(opts, :baud_rate, 1_000_000)

    print_header()
    print_joint_table()

    Mix.shell().info("\nConnecting to #{port} at #{format_baud(baud_rate)}...")

    case Feetech.start_link(port: port, baud_rate: baud_rate, timeout: 100) do
      {:ok, pid} ->
        try do
          run_wizard(pid)
        after
          Feetech.stop(pid)
        end

      {:error, :enoent} ->
        Mix.shell().error("\nError: Port #{port} not found.")
        Mix.shell().error("Check that the USB adapter is connected.")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("\nFailed to connect: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_header do
    Mix.shell().info("""

    ╔═══════════════════════════════════════════════════════════════╗
    ║              SO-101 Servo Configuration Wizard                ║
    ╚═══════════════════════════════════════════════════════════════╝

    This wizard will help you configure the servo IDs for your SO-101
    robot arm. You'll connect each servo one at a time so we can assign
    the correct ID.

    Before starting:
    - Disconnect all servos from the bus
    - Make sure the power supply is connected
    - Have the controller board connected via USB
    """)
  end

  defp print_joint_table do
    Mix.shell().info("Joint configuration:\n")
    Mix.shell().info("  ┌────────────────┬────┬───────────────────────────────────────┐")
    Mix.shell().info("  │ Joint          │ ID │ Description                           │")
    Mix.shell().info("  ├────────────────┼────┼───────────────────────────────────────┤")

    for {joint, id, desc} <- @joints do
      joint_str = joint |> to_string() |> String.pad_trailing(14)
      id_str = id |> to_string() |> String.pad_leading(2)
      desc_str = String.pad_trailing(desc, 37)
      Mix.shell().info("  │ #{joint_str} │ #{id_str} │ #{desc_str} │")
    end

    Mix.shell().info("  └────────────────┴────┴───────────────────────────────────────┘")
  end

  defp run_wizard(pid) do
    Mix.shell().info("\nPress Enter to begin, or 'q' to quit...")

    case prompt_continue() do
      :continue ->
        results = configure_joints(pid, @joints, [])
        print_summary(results)

      :quit ->
        Mix.shell().info("Setup cancelled.")
    end
  end

  defp configure_joints(_pid, [], results), do: Enum.reverse(results)

  defp configure_joints(pid, [{joint, target_id, desc} | rest], results) do
    Mix.shell().info("""

    ────────────────────────────────────────────────────────────────
    Joint #{length(@joints) - length(rest)} of #{length(@joints)}: #{format_joint(joint)}
    ────────────────────────────────────────────────────────────────

    Target ID: #{target_id}
    #{desc}

    Connect ONLY the #{format_joint(joint)} servo to the controller board.
    Make sure no other servos are connected to the bus.

    Press Enter when ready, 's' to skip, or 'q' to quit...
    """)

    case prompt_action() do
      :continue ->
        result = configure_single_servo(pid, joint, target_id)
        configure_joints(pid, rest, [{joint, target_id, result} | results])

      :skip ->
        Mix.shell().info("Skipping #{format_joint(joint)}...")
        configure_joints(pid, rest, [{joint, target_id, :skipped} | results])

      :quit ->
        Mix.shell().info("\nSetup cancelled.")
        Enum.reverse([{joint, target_id, :cancelled} | results])
    end
  end

  defp configure_single_servo(pid, joint, target_id) do
    Mix.shell().info("Scanning for servo...")

    case scan_for_single_servo(pid) do
      {:ok, found_id} when found_id == target_id ->
        Mix.shell().info("✓ Servo already has correct ID #{target_id}")
        verify_servo(pid, target_id)
        :already_configured

      {:ok, found_id} ->
        Mix.shell().info("Found servo with ID #{found_id}")
        set_servo_id(pid, found_id, target_id, joint)

      {:error, :no_servo} ->
        Mix.shell().error("✗ No servo found. Check the connection and try again.")
        retry_or_skip(pid, joint, target_id)

      {:error, :multiple_servos, ids} ->
        Mix.shell().error(
          "✗ Multiple servos found (IDs: #{Enum.join(ids, ", ")}). " <>
            "Please connect only ONE servo at a time."
        )

        retry_or_skip(pid, joint, target_id)
    end
  end

  defp scan_for_single_servo(pid) do
    case Feetech.ping(pid, @broadcast_id) do
      {:ok, _} ->
        found_ids = scan_all_ids(pid)

        case found_ids do
          [] -> {:error, :no_servo}
          [id] -> {:ok, id}
          ids -> {:error, :multiple_servos, ids}
        end

      {:error, :no_response} ->
        {:error, :no_servo}
    end
  end

  defp scan_all_ids(pid) do
    1..253
    |> Enum.filter(fn id ->
      case Feetech.ping(pid, id) do
        {:ok, _} -> true
        _ -> false
      end
    end)
  end

  defp set_servo_id(pid, current_id, target_id, joint) do
    Mix.shell().info("Setting ID from #{current_id} to #{target_id}...")

    with :ok <- unlock_eeprom(pid, current_id),
         :ok <- write_id(pid, current_id, target_id),
         :ok <- Process.sleep(50) || :ok,
         :ok <- lock_eeprom(pid, target_id),
         :ok <- verify_servo(pid, target_id) do
      Mix.shell().info("✓ #{format_joint(joint)} servo configured as ID #{target_id}")
      :configured
    else
      {:error, reason} ->
        Mix.shell().error("✗ Failed to configure servo: #{inspect(reason)}")
        :failed
    end
  end

  defp unlock_eeprom(pid, id) do
    case Feetech.write_raw(pid, id, :lock, 0) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:unlock_failed, reason}}
    end
  end

  defp write_id(pid, current_id, new_id) do
    case Feetech.write_raw(pid, current_id, :id, new_id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:write_id_failed, reason}}
    end
  end

  defp lock_eeprom(pid, id) do
    case Feetech.write_raw(pid, id, :lock, 1) do
      {:ok, _} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp verify_servo(pid, id) do
    case Feetech.ping(pid, id) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:verify_failed, reason}}
    end
  end

  defp retry_or_skip(pid, joint, target_id) do
    Mix.shell().info("\nPress Enter to retry, 's' to skip, or 'q' to quit...")

    case prompt_action() do
      :continue -> configure_single_servo(pid, joint, target_id)
      :skip -> :skipped
      :quit -> :cancelled
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

  defp prompt_action do
    case IO.gets("") do
      :eof ->
        :quit

      {:error, _} ->
        :quit

      data ->
        case String.trim(data) |> String.downcase() do
          "q" -> :quit
          "s" -> :skip
          _ -> :continue
        end
    end
  end

  defp print_summary(results) do
    Mix.shell().info("""

    ════════════════════════════════════════════════════════════════
                              SUMMARY
    ════════════════════════════════════════════════════════════════
    """)

    configured = Enum.count(results, fn {_, _, r} -> r in [:configured, :already_configured] end)
    skipped = Enum.count(results, fn {_, _, r} -> r == :skipped end)
    failed = Enum.count(results, fn {_, _, r} -> r == :failed end)
    cancelled = Enum.count(results, fn {_, _, r} -> r == :cancelled end)

    for {joint, id, result} <- results do
      status =
        case result do
          :configured -> "✓ Configured"
          :already_configured -> "✓ Already correct"
          :skipped -> "○ Skipped"
          :failed -> "✗ Failed"
          :cancelled -> "○ Cancelled"
        end

      Mix.shell().info("  #{format_joint(joint)} (ID #{id}): #{status}")
    end

    Mix.shell().info("")

    cond do
      cancelled > 0 ->
        Mix.shell().info("Setup was cancelled.")

      failed > 0 ->
        Mix.shell().error("#{failed} servo(s) failed to configure. Please retry those joints.")

      skipped > 0 and configured > 0 ->
        Mix.shell().info("#{configured} servo(s) configured successfully, #{skipped} skipped.")

      configured == length(@joints) ->
        Mix.shell().info("""
        All servos configured successfully!

        You can now daisy-chain the servos together:
        1. Connect shoulder_pan (ID 1) to the controller board
        2. Connect each subsequent servo to the previous one
        3. Power on and start the robot with: mix phx.server
        """)

      true ->
        Mix.shell().info("Setup complete.")
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
end
