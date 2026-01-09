defmodule BB.Example.SO101.Robot do
  use BB

  parameters do
    bridge(:robotis, {BB.Servo.Robotis.Bridge, controller: :dynamixel}, simulation: :mock)

    group :config do
      group :robotis do
        param(:device,
          type: :string,
          doc: "The serial device connected to the Robotis controller"
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
      :dynamixel,
      {BB.Servo.Robotis.Controller,
       port: param([:config, :robotis, :device]),
       baud_rate: param([:config, :robotis, :baud_rate]),
       control_table: Robotis.ControlTable,
       disarm_action: :hold},
      simulation: :mock
    )
  end

  topology do
    link :base_link do
      # Base plate visual
      visual do
        origin do
          z(~u(0.036 meter))
        end

        cylinder do
          radius(~u(0.04 meter))
          height(~u(0.072 meter))
        end

        material do
          name(:base_grey)

          color do
            red(0.3)
            green(0.3)
            blue(0.3)
            alpha(1.0)
          end
        end
      end

      # Waist joint - base rotation around Z axis
      joint :waist do
        type(:revolute)

        origin do
          z(~u(0.072 meter))
        end

        # Default axis is Z (0, 0, 1)

        limit do
          lower(~u(-180 degree))
          upper(~u(180 degree))
          effort(~u(8 newton_meter))
          velocity(~u(180 degree_per_second))
        end

        actuator(:waist_servo, {BB.Servo.Robotis.Actuator, servo_id: 1, controller: :dynamixel})

        link :shoulder_link do
          # Shoulder motor housing
          visual do
            origin do
              z(~u(0.019 meter))
            end

            box do
              x(~u(0.05 meter))
              y(~u(0.045 meter))
              z(~u(0.038 meter))
            end

            material do
              name(:shoulder_black)

              color do
                red(0.1)
                green(0.1)
                blue(0.1)
                alpha(1.0)
              end
            end
          end

          # Shoulder joint - pitch around Y axis
          # Note: Physical arm has dual servos (IDs 2 & 3) for torque.
          # Servo 3 should be configured in reverse shadow mode on the servo firmware.
          # We control via servo 2; servo 3 mirrors automatically.
          joint :shoulder do
            type(:revolute)

            origin do
              z(~u(0.03865 meter))
            end

            axis do
              roll(~u(90 degree))
            end

            limit do
              lower(~u(-108 degree))
              upper(~u(113 degree))
              effort(~u(18 newton_meter))
              velocity(~u(180 degree_per_second))
            end

            actuator(
              :shoulder_servo,
              {BB.Servo.Robotis.Actuator, servo_id: 2, controller: :dynamixel, reverse?: true}
            )

            link :upper_arm_link do
              # Upper arm segment (206mm from shoulder to elbow)
              visual do
                origin do
                  x(~u(0.025 meter))
                  z(~u(0.1 meter))
                end

                box do
                  x(~u(0.035 meter))
                  y(~u(0.035 meter))
                  z(~u(0.2 meter))
                end

                material do
                  name(:upper_arm_silver)

                  color do
                    red(0.7)
                    green(0.7)
                    blue(0.75)
                    alpha(1.0)
                  end
                end
              end

              # Elbow joint - pitch around Y axis
              joint :elbow do
                type(:revolute)

                origin do
                  x(~u(0.05 meter))
                  z(~u(0.2 meter))
                end

                axis do
                  roll(~u(90 degree))
                end

                limit do
                  lower(~u(-108 degree))
                  upper(~u(93 degree))
                  effort(~u(13 newton_meter))
                  velocity(~u(180 degree_per_second))
                end

                actuator(
                  :elbow_servo,
                  {BB.Servo.Robotis.Actuator, servo_id: 4, controller: :dynamixel}
                )

                link :forearm_link do
                  # Forearm segment (200mm from elbow to wrist)
                  visual do
                    origin do
                      x(~u(0.1 meter))
                    end

                    box do
                      x(~u(0.2 meter))
                      y(~u(0.035 meter))
                      z(~u(0.035 meter))
                    end

                    material do
                      name(:forearm_silver)

                      color do
                        red(0.7)
                        green(0.7)
                        blue(0.75)
                        alpha(1.0)
                      end
                    end
                  end

                  # Wrist angle joint - pitch around Y axis
                  joint :wrist_angle do
                    type(:revolute)

                    origin do
                      x(~u(0.2 meter))
                    end

                    axis do
                      roll(~u(90 degree))
                    end

                    limit do
                      lower(~u(-100 degree))
                      upper(~u(123 degree))
                      effort(~u(5 newton_meter))
                      velocity(~u(180 degree_per_second))
                    end

                    actuator(
                      :wrist_angle_servo,
                      {BB.Servo.Robotis.Actuator, servo_id: 5, controller: :dynamixel}
                    )

                    link :wrist_link do
                      # Wrist segment (65mm)
                      visual do
                        origin do
                          x(~u(0.0325 meter))
                        end

                        box do
                          x(~u(0.065 meter))
                          y(~u(0.035 meter))
                          z(~u(0.035 meter))
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

                      # Wrist rotate joint - roll around X axis
                      joint :wrist_rotate do
                        type(:revolute)

                        origin do
                          x(~u(0.065 meter))
                        end

                        axis do
                          pitch(~u(90 degree))
                        end

                        limit do
                          lower(~u(-180 degree))
                          upper(~u(180 degree))
                          effort(~u(1 newton_meter))
                          velocity(~u(180 degree_per_second))
                        end

                        actuator(
                          :wrist_rotate_servo,
                          {BB.Servo.Robotis.Actuator, servo_id: 6, controller: :dynamixel}
                        )

                        link :gripper_link do
                          # Gripper base
                          visual do
                            origin do
                              x(~u(0.02 meter))
                            end

                            box do
                              x(~u(0.04 meter))
                              y(~u(0.05 meter))
                              z(~u(0.025 meter))
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

                          # Gripper - left finger (prismatic)
                          # The gripper servo (ID 7) drives a linear mechanism
                          joint :gripper do
                            type(:prismatic)

                            origin do
                              x(~u(0.0415 meter))
                            end

                            axis do
                              pitch(~u(90 degree))
                            end

                            limit do
                              # Finger stroke: 15mm to 37mm from centre
                              lower(~u(0.015 meter))
                              upper(~u(0.037 meter))
                              effort(~u(5 newton))
                              velocity(~u(0.05 meter_per_second))
                            end

                            # Note: Gripper actuation requires custom handling
                            # as the servo rotation maps to linear finger motion.

                            link :left_finger_link do
                              # Finger
                              visual do
                                origin do
                                  x(~u(0.02 meter))
                                  y(~u(0.015 meter))
                                end

                                box do
                                  x(~u(0.04 meter))
                                  y(~u(0.01 meter))
                                  z(~u(0.02 meter))
                                end

                                material do
                                  name(:finger_grey)

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
                                  x(~u(0.0385 meter))
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
