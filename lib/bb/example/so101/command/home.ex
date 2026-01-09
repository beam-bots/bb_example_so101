defmodule BB.Example.SO101.Command.Home do
  @moduledoc """
  Command handler to move all joints to their neutral (zero) positions.

  This command sends position 0 to all moveable joints, returning the robot
  to its home configuration.

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

    BB.Motion.send_positions(context, positions, delivery: :direct)

    {:stop, :normal, %{state | result: :homed}}
  end

  @impl BB.Command
  def result(%{result: result}), do: {:ok, result}
end
