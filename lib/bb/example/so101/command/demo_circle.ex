# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101.Command.DemoCircle do
  @moduledoc """
  Demo command that traces a circle using DLS IK.

  First moves to a safe starting position, then traces a small circle
  in the XZ plane (vertical plane in front of the robot).

  Each waypoint waits for the end-effector to actually arrive (within
  `settle_tolerance_m`) before commanding the next one, so the traced path
  stays faithful to the planned circle.

  ## Goal Parameters

  Optional:
  - `radius` - Circle radius in metres (default: `0.03`)
  - `points` - Number of points around the circle (default: `16`)
  - `settle_tolerance_m` - EE distance from target to consider arrived (default: `5.0e-3`)
  - `settle_timeout_ms` - Max wait per waypoint before continuing (default: `1500`)

  ## Usage

      {:ok, cmd} = BB.Example.SO101.Robot.demo_circle()
      {:ok, :complete} = BB.Command.await(cmd, 30_000)
  """
  use BB.Command

  alias BB.IK.DLS
  alias BB.IK.DLS.Motion
  alias BB.Math.Vec3
  alias BB.Motion, as: BBMotion
  alias BB.Robot.Kinematics
  alias BB.Robot.State, as: RobotState

  # Safe starting position - comfortably within SO101 workspace.
  # At all-zero joints the EE rests at (0.407, 0, 0.116); this point is
  # well within the joint-limited reachable workspace.
  @start_x 0.25
  @start_y 0.0
  @start_z 0.30

  @default_radius 0.03
  @default_points 16
  @default_settle_tolerance_m 5.0e-3
  @default_settle_timeout_ms 1500

  # Loose IK tolerance/large step/low damping/few iterations let the warm-started
  # solver converge in 1-3 iterations per waypoint. Tighter values just waste FK
  # calls when the settle tolerance is 5mm anyway.
  @ik_tolerance 2.0e-3
  @ik_step_size 0.3
  @ik_lambda 0.1
  @ik_max_iterations 15

  # Motion.move_to/4 can return errors at runtime but dialyzer can't see
  # through :telemetry.span/3 and thinks it always returns {:ok, meta}
  @dialyzer {:no_match, [handle_command: 3, execute_path: 5]}

  @impl BB.Command
  def handle_command(goal, context, state) do
    radius = Map.get(goal, :radius, @default_radius)
    points = Map.get(goal, :points, @default_points)
    tolerance = Map.get(goal, :settle_tolerance_m, @default_settle_tolerance_m)
    timeout = Map.get(goal, :settle_timeout_ms, @default_settle_timeout_ms)

    start_position = Vec3.new(@start_x, @start_y, @start_z)

    ik_opts = [
      delivery: :direct,
      exclude_joints: [:gripper],
      tolerance: @ik_tolerance,
      step_size: @ik_step_size,
      lambda: @ik_lambda,
      max_iterations: @ik_max_iterations
    ]

    case Motion.move_to(context, :ee_link, start_position, ik_opts) do
      {:ok, _meta} ->
        wait_for_arrival(context, start_position, tolerance, timeout)
        targets = generate_circle_points(@start_x, @start_y, @start_z, radius, points)

        case execute_path(context, targets, tolerance, timeout, ik_opts) do
          :ok ->
            Motion.move_to(context, :ee_link, start_position, ik_opts)
            wait_for_arrival(context, start_position, tolerance, timeout)
            {:stop, :normal, %{state | result: :complete}}

          {:error, reason} ->
            {:stop, :normal, %{state | result: {:error, reason}}}
        end

      error ->
        {:stop, :normal, %{state | result: {:error, {:failed_to_reach_start, error}}}}
    end
  end

  @impl BB.Command
  def result(%{result: {:error, _} = error}), do: error
  def result(%{result: result}), do: {:ok, result}

  defp generate_circle_points(cx, cy, cz, radius, num_points) do
    for i <- 0..num_points do
      angle = 2 * :math.pi() * i / num_points
      x = cx + radius * :math.cos(angle)
      z = cz + radius * :math.sin(angle)
      Vec3.new(x, cy, z)
    end
  end

  # Solves each waypoint warm-starting from the previous IK solution rather
  # than from robot_state, which the position estimator overwrites during arm
  # motion. With consecutive waypoints ~3° apart in joint space, IK converges
  # in 1-3 iterations instead of the ~15-25 it takes from a cold start.
  defp execute_path(context, targets, tolerance, timeout, ik_opts) do
    seed_positions = RobotState.get_all_positions(context.robot_state)
    solver_opts = Keyword.delete(ik_opts, :delivery)

    targets
    |> Enum.reduce_while({:ok, seed_positions}, fn target, {:ok, positions} ->
      case DLS.solve(context.robot, positions, :ee_link, target, solver_opts) do
        {:ok, new_positions, _meta} ->
          BBMotion.send_positions(context, new_positions, delivery: :direct)
          wait_for_arrival(context, target, tolerance, timeout)
          {:cont, {:ok, new_positions}}

        {:error, _} = error ->
          {:halt, {:error, {:ik_failed, target, error}}}
      end
    end)
    |> case do
      {:ok, _last_positions} -> :ok
      {:error, _} = error -> error
    end
  end

  # Poll the position estimator until the EE is within `tolerance` of `target`
  # or `timeout_ms` elapses. Motion.move_to/send_positions writes its target
  # into robot_state immediately, so we sleep one estimator tick (~20 ms) first
  # to let the actual interpolated position arrive.
  defp wait_for_arrival(context, target, tolerance, timeout_ms) do
    Process.sleep(25)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_arrival(context, target, tolerance, deadline)
  end

  defp do_wait_for_arrival(context, target, tolerance, deadline) do
    distance = current_ee_distance(context, target)

    cond do
      distance <= tolerance ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        :timeout

      true ->
        Process.sleep(20)
        do_wait_for_arrival(context, target, tolerance, deadline)
    end
  end

  defp current_ee_distance(context, target) do
    positions = RobotState.get_all_positions(context.robot_state)
    {x, y, z} = Kinematics.link_position(context.robot, positions, :ee_link)

    :math.sqrt(
      :math.pow(x - Vec3.x(target), 2) +
        :math.pow(y - Vec3.y(target), 2) +
        :math.pow(z - Vec3.z(target), 2)
    )
  end
end
