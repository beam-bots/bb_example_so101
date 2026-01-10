# SPDX-FileCopyrightText: 2026 James Harton
#
# SPDX-License-Identifier: Apache-2.0

defmodule BB.Example.SO101.Robot do
  @moduledoc """
  Robot definition for the SO-101 arm from TheRobotStudio.

  The SO-101 is a 6-DOF robot arm using Feetech STS3215 serial bus servos.
  Kinematics derived from the official URDF (new calibration - zeros at joint midpoints).

  ## Joint Configuration

  | Joint | Servo ID | Type | Range |
  |-------|----------|------|-------|
  | shoulder_pan | 1 | revolute | ±110° |
  | shoulder_lift | 2 | revolute | ±100° |
  | elbow_flex | 3 | revolute | ±97° |
  | wrist_flex | 4 | revolute | ±95° |
  | wrist_roll | 5 | revolute | ±160° |
  | gripper | 6 | revolute | 10°-100° |

  ## Link Lengths

  - Base height: 62mm
  - Shoulder assembly: 54mm
  - Upper arm: 113mm
  - Forearm: 135mm
  - Wrist: 61mm
  - Gripper to EE: ~98mm
  """
  use BB

  parameters do
    bridge(:feetech, {BB.Servo.Feetech.Bridge, controller: :feetech}, simulation: :mock)

    group :config do
      group :feetech do
        param(:device,
          type: :string,
          doc: "The serial device connected to the Feetech servo bus"
        )

        param(:baud_rate,
          type: :integer,
          doc: "The communications speed for the serial port",
          default: 1_000_000
        )
      end
    end
  end

  commands do
    command :arm do
      handler(BB.Command.Arm)
      allowed_states([:disarmed])
    end

    command :disarm do
      handler(BB.Command.Disarm)
      allowed_states([:idle])
    end

    command :disable_torque do
      handler(BB.Example.SO101.Command.DisableTorque)
      allowed_states([:idle, :disarmed])
    end

    command :home do
      handler(BB.Example.SO101.Command.Home)
      allowed_states([:idle])
    end

    command :move_to_pose do
      handler(BB.Example.SO101.Command.MoveToPose)
      allowed_states([:idle])
    end

    command :demo_circle do
      handler(BB.Example.SO101.Command.DemoCircle)
      allowed_states([:idle])
    end
  end

  controllers do
    controller(
      :feetech,
      {BB.Servo.Feetech.Controller,
       port: param([:config, :feetech, :device]),
       baud_rate: param([:config, :feetech, :baud_rate]),
       control_table: Feetech.ControlTable.STS3215,
       disarm_action: :hold},
      simulation: :omit
    )
  end

  topology do
    link :base_link do
      visual do
        origin do
          z(~u(0.031 meter))
        end

        cylinder do
          radius(~u(0.035 meter))
          height(~u(0.062 meter))
        end

        material do
          name(:base_dark)

          color do
            red(0.15)
            green(0.15)
            blue(0.15)
            alpha(1.0)
          end
        end
      end

      joint :shoulder_pan do
        type(:revolute)

        origin do
          z(~u(0.062 meter))
        end

        limit do
          lower(~u(-110 degree))
          upper(~u(110 degree))
          effort(~u(2.5 newton_meter))
          velocity(~u(360 degree_per_second))
        end

        actuator(
          :shoulder_pan_servo,
          {BB.Servo.Feetech.Actuator, servo_id: 1, controller: :feetech}
        )

        link :shoulder_link do
          visual do
            origin do
              z(~u(0.027 meter))
            end

            box do
              x(~u(0.04 meter))
              y(~u(0.04 meter))
              z(~u(0.054 meter))
            end

            material do
              name(:servo_black)

              color do
                red(0.1)
                green(0.1)
                blue(0.1)
                alpha(1.0)
              end
            end
          end

          joint :shoulder_lift do
            type(:revolute)

            origin do
              z(~u(0.054 meter))
            end

            axis do
              roll(~u(90 degree))
            end

            limit do
              lower(~u(-100 degree))
              upper(~u(100 degree))
              effort(~u(2.5 newton_meter))
              velocity(~u(360 degree_per_second))
            end

            actuator(
              :shoulder_lift_servo,
              {BB.Servo.Feetech.Actuator, servo_id: 2, controller: :feetech}
            )

            link :upper_arm_link do
              visual do
                origin do
                  x(~u(0.0565 meter))
                end

                box do
                  x(~u(0.113 meter))
                  y(~u(0.03 meter))
                  z(~u(0.03 meter))
                end

                material do
                  name(:arm_white)

                  color do
                    red(0.9)
                    green(0.9)
                    blue(0.9)
                    alpha(1.0)
                  end
                end
              end

              joint :elbow_flex do
                type(:revolute)

                origin do
                  x(~u(0.113 meter))
                end

                axis do
                  roll(~u(90 degree))
                end

                limit do
                  lower(~u(-97 degree))
                  upper(~u(97 degree))
                  effort(~u(2.5 newton_meter))
                  velocity(~u(360 degree_per_second))
                end

                actuator(
                  :elbow_servo,
                  {BB.Servo.Feetech.Actuator, servo_id: 3, controller: :feetech}
                )

                link :forearm_link do
                  visual do
                    origin do
                      x(~u(0.0675 meter))
                    end

                    box do
                      x(~u(0.135 meter))
                      y(~u(0.025 meter))
                      z(~u(0.025 meter))
                    end

                    material do
                      name(:forearm_white)

                      color do
                        red(0.9)
                        green(0.9)
                        blue(0.9)
                        alpha(1.0)
                      end
                    end
                  end

                  joint :wrist_flex do
                    type(:revolute)

                    origin do
                      x(~u(0.135 meter))
                    end

                    axis do
                      roll(~u(90 degree))
                    end

                    limit do
                      lower(~u(-95 degree))
                      upper(~u(95 degree))
                      effort(~u(2.5 newton_meter))
                      velocity(~u(360 degree_per_second))
                    end

                    actuator(
                      :wrist_flex_servo,
                      {BB.Servo.Feetech.Actuator, servo_id: 4, controller: :feetech}
                    )

                    link :wrist_link do
                      visual do
                        origin do
                          x(~u(0.0305 meter))
                        end

                        box do
                          x(~u(0.061 meter))
                          y(~u(0.025 meter))
                          z(~u(0.025 meter))
                        end

                        material do
                          name(:wrist_black)

                          color do
                            red(0.1)
                            green(0.1)
                            blue(0.1)
                            alpha(1.0)
                          end
                        end
                      end

                      joint :wrist_roll do
                        type(:revolute)

                        origin do
                          x(~u(0.061 meter))
                        end

                        axis do
                          pitch(~u(90 degree))
                        end

                        limit do
                          lower(~u(-160 degree))
                          upper(~u(160 degree))
                          effort(~u(2.5 newton_meter))
                          velocity(~u(360 degree_per_second))
                        end

                        actuator(
                          :wrist_roll_servo,
                          {BB.Servo.Feetech.Actuator, servo_id: 5, controller: :feetech}
                        )

                        link :gripper_link do
                          visual do
                            origin do
                              x(~u(0.02 meter))
                            end

                            box do
                              x(~u(0.04 meter))
                              y(~u(0.04 meter))
                              z(~u(0.05 meter))
                            end

                            material do
                              name(:gripper_dark)

                              color do
                                red(0.2)
                                green(0.2)
                                blue(0.2)
                                alpha(1.0)
                              end
                            end
                          end

                          joint :gripper do
                            type(:revolute)

                            origin do
                              x(~u(0.04 meter))
                            end

                            axis do
                              roll(~u(90 degree))
                            end

                            limit do
                              lower(~u(10 degree))
                              upper(~u(100 degree))
                              effort(~u(2.5 newton_meter))
                              velocity(~u(360 degree_per_second))
                            end

                            actuator(
                              :gripper_servo,
                              {BB.Servo.Feetech.Actuator, servo_id: 6, controller: :feetech}
                            )

                            link :jaw_link do
                              visual do
                                origin do
                                  x(~u(0.029 meter))
                                end

                                box do
                                  x(~u(0.058 meter))
                                  y(~u(0.03 meter))
                                  z(~u(0.01 meter))
                                end

                                material do
                                  name(:jaw_grey)

                                  color do
                                    red(0.4)
                                    green(0.4)
                                    blue(0.4)
                                    alpha(1.0)
                                  end
                                end
                              end

                              joint :ee_fixed do
                                type(:fixed)

                                origin do
                                  x(~u(0.058 meter))
                                end

                                link(:ee_link)
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
