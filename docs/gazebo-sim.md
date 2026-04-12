# Gazebo sim

This note captures one workable simulation architecture for WATERBOT when Zig
remains the orchestrator and Gazebo is used through ROS 2.

## Diagram

Open this in Mermaid Live Editor:

- https://mermaid.live/edit#pako:eJxtkkFr3DAQhf_KoHNDYY8hLHRLWQphAw7pYbvFjCWtrSJpjDR2shvy3ytZthNKfLE1eu_Tm5FfhSSlxa04W3qWHQaG--rkIT3H3ydxNC38eNFyYDPquyZ83ToToyEPllojp4okz4Hsh8ozsg7Gt6V0En8KcJeAu2BUW0iZzQTVwyM0NHiF4bJKqyTNGxs4pHhx0jeTFVBhn_ClxufN9I6cjoR-aKyJ3bIZKNbttS6-Fb1P6D1edUPwaNwk7LtLNLKYovaRVkBDDC4lsKv9kOwPPacRoJ2yfxuYPLlLcVt0NRPZhl7eEbUlidZcMdum8gHHzYp8ys3-MldIgRts4fv9T8iMOCnmy4CbGzgJ6VQ9agsUACUPyOlDknPoVVInzRZ287CLISdk6lN3EHUYjdQxO1OORT_fdlX00bj_gfslw36WTBMChYzwl4xnmKYfgRRls-d0wOf0s7Hp6rQqjtyFHrXnz6OX6Rdlp9FyB9TkJvBj_OOSroK7vD68H7iFp_nOloX4IpwODo0St6-CO-3yr6_0GQfL4u3tH8AO_aU=

## Core idea

In this model:

- `Zig` owns mission logic, watering policy, control decisions, and robot intent
- `ROS 2` owns the simulation-facing runtime, topic graph, TF, and Gazebo bridge
- `Gazebo` owns the simulated physical world and sensor outputs

The important point is that this does not create two sources of truth if the
state ownership is separated correctly.

Because the project started with some lower level functions being in the zig
side (such as motor control, video feed processing), we need a way to tell
gazebo when a signal is sent to the motor (so its effect can be simulated)
without going through ros2. For this we can use buildtime / comptime resolved
branching, so depending on the build config, the binary for simulation can be
built with Gpio that actually just broadcasts a message to motor control
component to either ros2 or directly to gz. 

## Source of truth

There should be one source of truth per kind of state.

`Zig` should be the source of truth for:

- mission state
- task state
- policy
- desired commands
- watering logic

`Gazebo` and `ROS 2` should be the source of truth for:

- actual robot pose
- odometry
- joint states
- sensor data
- collisions and contacts
- localization and map outputs

So Zig should not assume that a commanded motion already happened. Zig should
issue intent, then update its mission state from what the simulated robot
actually did.

The clean split is:

- `intent`: Zig-owned
- `observed physical state`: Gazebo and ROS-owned

That is the difference between:

- "drive forward at this velocity"
- "the robot is currently at this pose"

The first is a command. The second is an observation.

## Message flow

For this setup, the normal direction of traffic is:

- `Zig -> ROS`: commands or goals
- `ROS -> Gazebo`: simulation-facing commands
- `Gazebo -> ROS`: sensor data and physical state
- `ROS -> Zig`: observed state, status, and autonomy results

Examples of commands Zig may send:

- `geometry_msgs/msg/Twist` on `/cmd_vel`
- actuator-oriented command topics if you want Zig to own low-level motion
- higher-level actions such as `NavigateToPose` if ROS owns motion planning

Examples of state that should come back from Gazebo and ROS rather than Zig:

- `/odom`
- `/tf`
- `/joint_states`
- IMU, LiDAR, and camera topics

## Practical rule

Avoid this anti-pattern:

- Zig commands motion
- Zig immediately treats the command as accomplished

Prefer this loop:

1. Zig sends a command or goal.
2. Gazebo simulates the robot response.
3. ROS publishes the observed state.
4. Zig advances mission logic based on observation, not assumption.

That keeps the simulation honest and makes the same architecture usable later on
real hardware.
