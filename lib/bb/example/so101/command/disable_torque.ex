# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101.Command.DisableTorque do
  @moduledoc """
  Command handler to disable holding torque on all Feetech servos.

  This command writes `torque_enable: false` to all servos registered
  with the Feetech controller, allowing them to be moved freely by hand.

  ## Usage

      commands do
        command :disable_torque do
          handler BB.Example.SO101.Command.DisableTorque
          allowed_states [:idle]
        end
      end

  Then execute:

      {:ok, cmd} = BB.Example.SO101.Robot.disable_torque()
      {:ok, :torque_disabled} = BB.Command.await(cmd)

  """
  use BB.Command

  @controller :feetech_controller

  @impl BB.Command
  def handle_command(_goal, context, state) do
    robot = context.robot_module

    result =
      with {:ok, servo_ids} <- BB.Process.call(robot, @controller, :list_servos),
           :ok <- disable_all_servos(robot, servo_ids) do
        :torque_disabled
      end

    {:stop, :normal, %{state | result: result}}
  end

  @impl BB.Command
  def result(%{result: {:error, _} = error}), do: error
  def result(%{result: result}), do: {:ok, result}

  defp disable_all_servos(robot, servo_ids) do
    results =
      Enum.map(servo_ids, fn servo_id ->
        BB.Process.call(robot, @controller, {:write, servo_id, :torque_enable, false})
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      error -> error
    end
  end
end
