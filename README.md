<!--
SPDX-FileCopyrightText: 2026 James Harton

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
- Feetech URT-1 USB adapter or compatible TTL serial adapter
- 6-7.4V DC power supply for the servos

## Quick Start (Simulation)

No hardware required:

```bash
mix setup
SIMULATE=1 mix phx.server
```

Visit [localhost:4000](http://localhost:4000) to access the robot dashboard.

## Hardware Setup

### What You Need

- **SO-101 arm** fully assembled with 6x Feetech STS3215 servos
- **USB serial adapter** (Feetech URT-1 or any 5V TTL serial adapter)
- **Power supply** 6-7.4V DC, connected to the servo bus
- **USB cable** connecting the adapter to your computer

The serial adapter connects to the servo bus (the same daisy-chain cable
that connects all the servos). On Linux, it typically appears as
`/dev/ttyUSB0` or `/dev/ttyACM0`.

### Step 1: Assign Servo IDs

STS3215 servos ship with a default ID of 1. Each servo in the arm needs
a unique ID. The setup wizard walks you through connecting each servo
one at a time and assigning the correct ID.

```bash
mix so101.setup_servos /dev/ttyUSB0
```

The wizard will prompt you to connect each servo individually:

| Joint          | Servo ID | Description              |
|----------------|----------|--------------------------|
| shoulder_pan   | 1        | Base rotation            |
| shoulder_lift  | 2        | Shoulder up/down         |
| elbow_flex     | 3        | Elbow bend               |
| wrist_flex     | 4        | Wrist up/down            |
| wrist_roll     | 5        | Wrist rotation           |
| gripper        | 6        | Gripper open/close       |

After assigning IDs, daisy-chain all servos together and reconnect to
the controller board.

### Step 2: Calibrate

With all servos connected and powered, run the calibration task:

```bash
mix so101.calibrate /dev/ttyUSB0
```

This will:

1. Disable torque on all servos so you can move the arm freely
2. Prompt you to move **every joint** through its **full range of motion**
   (push each joint to both mechanical limits)
3. Track the min/max positions for each joint in real time
4. When you press Enter, calculate the mechanical centre of each joint
5. Write a position offset to each servo so that the centre corresponds
   to 0 radians

You can preview the results without writing to the servos:

```bash
mix so101.calibrate /dev/ttyUSB0 --dry-run
```

Calibration only needs to be done once - the offsets are stored in the
servo's EEPROM and persist across power cycles. Re-run it if you
physically reposition a servo on its bracket.

### Step 3: Run

```bash
mix phx.server
```

Visit [localhost:4000](http://localhost:4000). Use the dashboard to arm
the robot, then send commands.

### Serial Port Configuration

By default the application connects to `/dev/ttyUSB0` at 1Mbaud. To use
a different port, edit `lib/bb_example_so101/application.ex`:

```elixir
defp robot_opts do
  [params: [config: [feetech: [device: "/dev/ttyACM0"]]]]
end
```

## Commands

| Command | Description | Allowed States |
|---------|-------------|----------------|
| `arm` | Enable torque and prepare for motion | `[:disarmed]` |
| `disarm` | Disable torque safely | `[:idle]` |
| `home` | Move all joints to zero position | `[:idle]` |
| `demo_circle` | Execute circular motion demo | `[:idle]` |
| `disable_torque` | Disable servo torque | `[:idle, :disarmed]` |
| `move_to_pose` | Move end effector to target position | `[:idle]` |

Execute commands via the web dashboard or programmatically:

```elixir
{:ok, cmd} = BB.Example.SO101.Robot.arm()
{:ok, :armed} = BB.Command.await(cmd)

{:ok, cmd} = BB.Example.SO101.Robot.home()
{:ok, :homed} = BB.Command.await(cmd)
```

## Kinematic Structure

Derived from the official [SO-ARM100 URDF](https://github.com/TheRobotStudio/SO-ARM100/tree/main/Simulation/SO101):

| Joint | Range | Link Length |
|-------|-------|-------------|
| shoulder_pan | ±110° | 62mm (base) |
| shoulder_lift | -10° to 190° | 54mm |
| elbow_flex | -187° to 7° | 113mm (upper arm) |
| wrist_flex | ±95° | 135mm (forearm) |
| wrist_roll | ±160° | 61mm (wrist) |
| gripper | -10° to 100° | ~98mm to EE |

Total reach: ~350mm

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
├── bb_example_so101/
│   └── application.ex        # Supervision tree
├── bb_example_so101_web/     # Phoenix web layer
│   ├── router.ex             # Mounts bb_dashboard
│   └── ...
└── mix/tasks/
    ├── so101.setup_servos.ex # Servo ID assignment wizard
    └── so101.calibrate.ex    # Servo calibration
```

## Development

```bash
SIMULATE=1 mix phx.server       # Run in simulation mode
mix test                         # Run tests
mix check --no-retry             # Run all checks
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
