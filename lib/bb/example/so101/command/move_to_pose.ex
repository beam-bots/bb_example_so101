defmodule BB.Example.SO101.Command.MoveToPose do
  @moduledoc """
  Command to move the end effector to a target position using IK.

  ## Goal Parameters

  Required:
  - `target` - A `BB.Math.Vec3` target position

  ## Usage

      target = BB.Math.Vec3.new(0.25, 0.0, 0.2)
      {:ok, cmd} = BB.Example.SO101.Robot.move_to_pose(%{target: target})
      {:ok, :reached} = BB.Command.await(cmd, 10_000)
  """
  use BB.Command

  alias BB.IK.DLS.Motion
  alias BB.Math.Vec3

  @impl BB.Command
  def handle_command(%{target: %Vec3{} = target}, context, state) do
    ik_opts = [delivery: :direct, exclude_joints: [:gripper]]

    case Motion.move_to(context, :ee_link, target, ik_opts) do
      {:ok, _meta} ->
        {:stop, :normal, %{state | result: :reached}}

      {:error, reason, _meta} ->
        {:stop, :normal, %{state | result: {:error, {:ik_failed, reason}}}}
    end
  end

  def handle_command(_goal, _context, state) do
    {:stop, :normal, %{state | result: {:error, :missing_target}}}
  end

  @impl BB.Command
  def result(%{result: {:error, _} = error}), do: error
  def result(%{result: result}), do: {:ok, result}
end
