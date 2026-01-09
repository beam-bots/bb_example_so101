defmodule BB.Example.SO101.Reactor.PickAndPlace do
  @moduledoc """
  Demonstration pick-and-place reactor using BB.Reactor DSL.

  This reactor demonstrates a typical pick-and-place operation:
  1. Wait for robot to be ready
  2. Move to pick position
  3. Simulate gripping (delay)
  4. Move to place position (with compensation to return home on failure)
  5. Simulate releasing
  6. Return to home

  ## Usage

      pick_pose = BB.Math.Vec3.new(0.25, 0.05, 0.15)
      place_pose = BB.Math.Vec3.new(0.25, -0.05, 0.15)

      {:ok, result} = Reactor.run(
        BB.Example.SO101.Reactor.PickAndPlace,
        %{pick_pose: pick_pose, place_pose: place_pose},
        context: %{private: %{bb_robot: BB.Example.SO101.Robot}}
      )

  ## Safety

  Add the Safety middleware if you want reactor errors to trigger the
  robot's safety system:

      middlewares do
        middleware BB.Reactor.Middleware.Safety
      end
  """
  use Reactor, extensions: [BB.Reactor]

  input(:pick_pose)
  input(:place_pose)

  wait_for_state :ready do
    states([:idle])
    timeout(5000)
  end

  command :approach_pick do
    command(:move_to_pose)
    argument(:target, input(:pick_pose))
    wait_for(:ready)
  end

  step :simulate_grip do
    argument(:_prev, result(:approach_pick))

    run(fn _args, _context ->
      Process.sleep(500)
      {:ok, :gripped}
    end)
  end

  command :approach_place do
    command(:move_to_pose)
    argument(:target, input(:place_pose))
    wait_for(:simulate_grip)
    compensate(:home)
  end

  step :simulate_release do
    argument(:_prev, result(:approach_place))

    run(fn _args, _context ->
      Process.sleep(500)
      {:ok, :released}
    end)
  end

  command :return_home do
    command(:home)
    wait_for(:simulate_release)
  end

  return(:return_home)
end
