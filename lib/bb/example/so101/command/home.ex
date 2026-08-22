# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101.Command.Home do
  @moduledoc """
  Command handler to move all joints to their neutral (zero) positions.

  This command sends position 0 to all moveable joints, returning the robot
  to its home configuration. It waits for every actuator to accept its
  command, so a refusal is reported rather than reported as `:homed`.

  ## Usage

      commands do
        command :home do
          handler BB.Example.SO101.Command.Home
          allowed_states [:idle]
        end
      end

  Then execute:

      {:ok, cmd} = BB.Example.SO101.Robot.home()
      {:ok, :homed} = BB.Command.await(cmd)

  """
  use BB.Command

  alias BB.Robot.Joint

  @impl BB.Command
  def handle_command(_goal, context, state) do
    positions =
      context.robot.joints
      |> Enum.filter(fn {_name, joint} -> Joint.movable?(joint) end)
      |> Map.new(fn {name, _joint} -> {name, 0.0} end)

    result =
      case BB.Motion.send_positions(context, positions) do
        :ok -> :homed
        {:error, _} = error -> error
      end

    {:stop, :normal, %{state | result: result}}
  end

  @impl BB.Command
  def result(%{result: {:error, _} = error}), do: error
  def result(%{result: result}), do: {:ok, result}
end
