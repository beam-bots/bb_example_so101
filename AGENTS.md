# AGENTS.md

This file provides guidance to AI coding assistants when working with code in this repository.

## Overview

Example Phoenix application demonstrating the BB (Beam Bots) robotics framework with a SO-101 robot arm from TheRobotStudio. This project integrates `bb_liveview` to provide a real-time web dashboard for robot control and 3D visualisation.

The SO-101 is a 6-DOF desktop robot arm using Feetech STS3215 serial bus servos.

## Commands

```bash
mix setup              # Install deps and build assets
SIMULATE=1 mix phx.server  # Start in simulation mode (no hardware)
mix phx.server         # Start with real hardware
iex -S mix phx.server  # Start with IEx shell
mix test               # Run all tests
mix test path:42       # Run single test at line
mix check --no-retry   # Run all checks (compile, format, credo, dialyzer)
```

### Hardware Mix Tasks

```bash
mix so101.setup_servos /dev/ttyUSB0   # Assign servo IDs (one at a time)
mix so101.calibrate /dev/ttyUSB0      # Calibrate centre offsets
mix so101.calibrate /dev/ttyUSB0 -n   # Dry run (show offsets without writing)
```

## Architecture

### Robot Definition (`lib/bb/example/so101/robot.ex`)

The robot is defined using BB's Spark DSL with four main sections:

- **parameters** - Configures bridges (servo communication adapters) and runtime config
- **commands** - Defines available robot commands with state machine constraints
- **controllers** - Hardware communication (Feetech STS3215 via serial)
- **topology** - URDF-like kinematic chain with joints, links, visuals, and actuators

The robot starts as a supervised child in `application.ex` and exposes commands like `BB.Example.SO101.Robot.home()`.

### Kinematic Structure

Derived from the official SO-ARM100 URDF:

| Joint | Servo ID | Type | Range | Link Length |
|-------|----------|------|-------|-------------|
| shoulder_pan | 1 | revolute | ±110° | 62mm (base height) |
| shoulder_lift | 2 | revolute | -10° to 190° | 54mm |
| elbow_flex | 3 | revolute | -187° to 7° | 113mm (upper arm) |
| wrist_flex | 4 | revolute | ±95° | 135mm (forearm) |
| wrist_roll | 5 | revolute | ±160° | 61mm (wrist) |
| gripper | 6 | revolute | -10° to 100° | ~98mm to EE |

### Mix Tasks (`lib/mix/tasks/`)

- **`so101.setup_servos`** - Interactive wizard for assigning servo IDs. Guides the user through connecting each servo one at a time and setting IDs 1-6.
- **`so101.calibrate`** - Calibrates servo centre offsets. Disables torque, tracks min/max positions as the user moves each joint through its full range, then writes position offsets so the mechanical centre maps to 0 radians.

### Web Dashboard

The router mounts `bb_dashboard("/", robot: BB.Example.SO101.Robot)` from `bb_liveview`, providing:
- Real-time joint state visualisation
- 3D robot model rendering
- Command execution interface
- Safety controls (arm/disarm)

### Command Handlers (`lib/bb/example/so101/command/`)

Commands implement `BB.Command` behaviour with `handle_command/2`. They receive a context containing the compiled robot struct and can send motion commands via `BB.Motion`.

## Physical Units

BB uses the `~u` sigil for physical quantities throughout the DSL:

```elixir
~u(0.1 meter)
~u(90 degree)
~u(360 degree_per_second)
~u(2.5 newton_meter)
```

## Simulation Mode

Set `SIMULATE=1` to run without hardware. In simulation mode:
- Controllers and bridges are omitted/mocked
- `BB.Sim.Actuator` publishes simulated motion messages
- Joint positions are estimated via `OpenLoopPositionEstimator`

## Hardware Configuration

The serial port defaults to `/dev/ttyUSB0` at 1Mbaud. To change it, edit
`lib/bb_example_so101/application.ex` in the `robot_opts/0` function.

## Dependencies

Local path dependencies to sibling BB repositories:
- `bb` - Core framework
- `bb_liveview` - Phoenix LiveView dashboard
- `bb_servo_feetech` - Feetech STS servo driver
- `bb_ik_dls` - Damped Least Squares inverse kinematics
- `feetech` - Feetech serial protocol
