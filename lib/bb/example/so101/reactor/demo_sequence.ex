defmodule BB.Example.SO101.Reactor.DemoSequence do
  @moduledoc """
  Demonstration reactor that executes a sequence of robot commands.

  This reactor:
  1. Waits for the robot to be in idle state
  2. Homes the robot
  3. Executes the demo circle
  4. Returns to home position

  ## Usage

      # Run the reactor
      {:ok, :homed} = Reactor.run(
        BB.Example.SO101.Reactor.DemoSequence,
        %{},
        context: %{private: %{bb_robot: BB.Example.SO101.Robot}}
      )
  """
  use Reactor, extensions: [BB.Reactor]

  wait_for_state :ready do
    states([:idle])
    timeout(5000)
  end

  command :go_home do
    command(:home)
    wait_for(:ready)
  end

  command :trace_circle do
    command(:demo_circle)
    wait_for(:go_home)
  end

  command :return_home do
    command(:home)
    wait_for(:trace_circle)
  end

  return(:return_home)
end
