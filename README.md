<!--
SPDX-FileCopyrightText: 2025 James Harton

SPDX-License-Identifier: Apache-2.0
-->

<img src="https://github.com/beam-bots/bb/blob/main/logos/beam_bots_logo.png?raw=true" alt="Beam Bots Logo" width="250" />

# BB Example: SO-101

Example Phoenix application demonstrating the [Beam Bots](https://github.com/beam-bots/bb) robotics framework with a [SO-101 robot arm](https://github.com/TheRobotStudio/SO-ARM100) from TheRobotStudio.

## Features

- **Complete robot definition** - 6-DOF arm with gripper using the BB DSL
- **Web dashboard** - Real-time control and 3D visualisation via `bb_liveview`
- **Feetech integration** - Hardware control via `bb_servo_feetech` for STS3215 servos
- **Custom commands** - Home position, demo circle, and torque control
- **Simulation mode** - Run without hardware for development and testing

## Requirements

- Elixir ~> 1.15
- SO-101 robot arm with Feetech STS3215 servos (or run in simulation mode)
- USB serial adapter connected to servo bus

## Quick Start

```bash
# Install dependencies and build assets
mix setup

# Start in simulation mode (no hardware required)
SIMULATE=1 mix phx.server

# Or start with real hardware
mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to access the robot dashboard.

## Hardware Setup

### Servo Configuration

The SO-101 uses 6 Feetech STS3215 servos with IDs 1-6:

| Servo ID | Joint |
|----------|-------|
| 1 | Shoulder Pan |
| 2 | Shoulder Lift |
| 3 | Elbow Flex |
| 4 | Wrist Flex |
| 5 | Wrist Roll |
| 6 | Gripper |

### Serial Connection

Configure your serial device in `config/runtime.exs`:

```elixir
config :bb_example_so101, BB.Example.SO101.Robot,
  config: [
    feetech: [
      device: "/dev/ttyUSB0",  # Adjust for your system
      baud_rate: 1_000_000
    ]
  ]
```

## Robot Definition

The robot is defined in `lib/bb/example/so101/robot.ex` using the BB DSL:

```elixir
defmodule BB.Example.SO101.Robot do
  use BB

  parameters do
    bridge(:feetech, {BB.Servo.Feetech.Bridge, controller: :feetech})
  end

  commands do
    command :home do
      handler(BB.Example.SO101.Command.Home)
      allowed_states([:idle])
    end
    # ... additional commands
  end

  controllers do
    controller(:feetech, {BB.Servo.Feetech.Controller,
      port: param([:config, :feetech, :device]),
      baud_rate: param([:config, :feetech, :baud_rate]),
      control_table: Feetech.ControlTable.STS3215
    })
  end

  topology do
    link :base_link do
      joint :shoulder_pan do
        # ... joint definition with actuator
        link :shoulder_link do
          # ... nested kinematic chain
        end
      end
    end
  end
end
```

## Kinematic Structure

Derived from the official [SO-ARM100 URDF](https://github.com/TheRobotStudio/SO-ARM100/tree/main/Simulation/SO101):

| Joint | Range | Link Length |
|-------|-------|-------------|
| shoulder_pan | ±110° | 62mm (base) |
| shoulder_lift | ±100° | 54mm |
| elbow_flex | ±97° | 113mm (upper arm) |
| wrist_flex | ±95° | 135mm (forearm) |
| wrist_roll | ±160° | 61mm (wrist) |
| gripper | 10°-100° | ~98mm to EE |

Total reach: ~350mm

## Commands

| Command | Description | Allowed States |
|---------|-------------|----------------|
| `arm` | Enable torque and prepare for motion | `[:disarmed]` |
| `disarm` | Disable torque safely | `[:idle]` |
| `home` | Move all joints to zero position | `[:idle]` |
| `demo_circle` | Execute circular motion demo | `[:idle]` |
| `disable_torque` | Disable servo torque without state change | `[:idle, :disarmed]` |
| `move_to_pose` | Move end effector to target position | `[:idle]` |

Execute commands via the web dashboard or programmatically:

```elixir
# Arm the robot first
{:ok, cmd} = BB.Example.SO101.Robot.arm()
{:ok, :armed} = BB.Command.await(cmd)

# Move to home position
{:ok, cmd} = BB.Example.SO101.Robot.home()
{:ok, :homed} = BB.Command.await(cmd)

# Run demo circle
{:ok, cmd} = BB.Example.SO101.Robot.demo_circle()
{:ok, :complete} = BB.Command.await(cmd, 30_000)
```

## Project Structure

```
lib/
├── bb/example/so101/
│   ├── robot.ex              # Robot DSL definition
│   └── command/              # Custom command handlers
│       ├── home.ex
│       ├── demo_circle.ex
│       ├── move_to_pose.ex
│       └── disable_torque.ex
├── bb_example_so101.ex       # Application context
├── bb_example_so101/
│   └── application.ex        # Supervision tree
└── bb_example_so101_web/     # Phoenix web layer
    ├── router.ex             # Mounts bb_dashboard
    └── ...
```

## Development

```bash
# Run in simulation mode
SIMULATE=1 mix phx.server

# Run tests
mix test
mix test path/to/test.exs:42  # Single test at line

# Run all checks
mix check --no-retry
```

## Related Packages

- [bb](https://github.com/beam-bots/bb) - Core framework
- [bb_liveview](https://github.com/beam-bots/bb_liveview) - Phoenix LiveView dashboard
- [bb_servo_feetech](https://github.com/beam-bots/bb_servo_feetech) - Feetech STS servo driver
- [bb_ik_dls](https://github.com/beam-bots/bb_ik_dls) - Damped Least Squares inverse kinematics
- [feetech](https://github.com/beam-bots/feetech) - Feetech serial protocol

## Acknowledgements

- [TheRobotStudio](https://github.com/TheRobotStudio) for the SO-ARM100 design and URDF
- [Feetech](https://www.feetechrc.com/) for the STS series servos
