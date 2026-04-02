# TODO

## Direction

`main_compute` should become the low-level robot daemon.

It should own:

- motor actuation
- safety stop / watchdog behavior
- IMU-driven heading stabilization
- watering actuator control
- a narrow socket protocol for commands and telemetry

It should not try to own:

- SLAM
- Nav2
- ROS-native localization
- high-level autonomy frameworks

Those should live outside this package and talk to `main_compute` through a
small interface.

## Current priority

Work on mobility and control first.

Do not spend time on plant classification, mapping, or full mission logic until
the robot can do the following reliably:

- accept a velocity-style command
- stop safely on timeout
- turn to a heading
- drive straight while holding heading

## Milestone 1: turn `main_compute` into a proper low-level daemon

- [ ] Replace direction-only commands with a clearer control protocol
- [ ] Add `velocity`, `water`, and `estop` command variants
- [ ] Add telemetry variants such as `odom`, `status`, and `fault`
- [ ] Keep the Unix domain socket as the main external interface
- [ ] Treat the browser server as temporary debug tooling, not the long-term API
- [ ] Keep `mainLoop` focused on low-level actuation and safety
- [ ] Add watchdog stop / timeout handling for stale commands
- [ ] Carry command payload values all the way to motor output

## Milestone 2: refactor the control loop around fixed-rate ticks

- [ ] Stop thinking of `mainLoop` as a blocking "wait for command forever" loop
- [ ] Use a fixed-rate control loop that drains new commands and still ticks on time
- [ ] Keep actuation as one narrow part of that control loop
- [ ] Separate desired motion from applied motor output
- [ ] Introduce a top-level control state struct for current robot state
- [ ] Introduce a top-level mission / behavior enum for mode tracking
- [ ] Add clear safety behavior for estop, stale command, and sensor failure

## Milestone 3: add closed-loop mobility

- [ ] Integrate IMU reading into `main_compute`
- [ ] Add heading estimation
- [ ] Add a heading controller
- [ ] Implement `turn to heading`
- [ ] Implement `drive straight while holding heading`
- [ ] Define the minimum odometry struct even if only heading is trustworthy at first
- [ ] Add wheel encoder integration later if and when encoder hardware is available

## Milestone 4: decouple perception from actuation

- [ ] Stop letting perception directly imply motor behavior
- [ ] Make the perception pipeline publish observations instead
- [ ] Define an observation type for target visibility / offset / confidence
- [ ] Keep perception as an input to control logic, not the controller itself
- [ ] Preserve the current bottlecap targeting path as a debug aid while refactoring

## Milestone 5: define the Zig <-> ROS boundary

- [ ] Keep ROS out of `main_compute` itself
- [ ] Finalize a socket protocol that can support a ROS bridge
- [ ] Model ROS-side commands around `cmd_vel`-style motion, not left/right/stop
- [ ] Emit telemetry in a form that a ROS bridge can republish as topics
- [ ] Design for a separate `rclcpp` bridge process rather than direct ROS bindings in Zig
- [ ] Document the protocol fields well enough that the bridge can be built independently

## Milestone 6: improve testability on the PC

- [ ] Conditional compilation to assist testing on the PC
- [ ] Conditionally substitute the GPIO dependency
- [ ] Conditionally substitute the camera dependency
- [ ] Add fake IMU / fake actuator paths where useful
- [ ] Add tests for the control loop state transitions
- [ ] Add tests for stale-command timeout behavior
- [ ] Decide whether logging level should stay runtime-derived or be baked in

## After the above is stable

- [ ] Add a small mission controller / state machine above low-level control
- [ ] Add watering commands: target, duration, and dose
- [ ] Add watering verification feedback
- [ ] Add plant registry hooks once pose / map coordinates are available
- [ ] Add localization inputs once the ROS side is ready

## Explicitly not next

- [ ] Do not put SLAM or Nav2 logic into `main_compute`
- [ ] Do not over-invest in the browser control path
- [ ] Do not spend major time on plant ID before motion control is reliable
- [ ] Do not tightly couple perception code to motor actuation again

## Suggested implementation order

- [ ] 1. Evolve the command / telemetry protocol
- [ ] 2. Convert `mainLoop` into a fixed-rate control loop with watchdog behavior
- [ ] 3. Add IMU integration and heading stabilization
- [ ] 4. Refactor perception into observations instead of commands
- [ ] 5. Freeze the Zig <-> ROS socket boundary
- [ ] 6. Build higher-level behavior only after the low-level daemon is stable
