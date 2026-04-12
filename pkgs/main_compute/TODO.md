# TODO

## Direction

The most immediate milestone is no longer to finish `main_compute` as a
hardware-first low-level daemon.

The most immediate milestone is to replicate a simple scene with a simple car
in `Gazebo`, run it through `ROS 2`, and prove that WATERBOT code can command
the simulated vehicle and observe what actually happened.

`main_compute` still matters in this milestone, but mainly as the place where
the actuation boundary gets cleaned up so the same control path can target:

- real GPIO on hardware
- a simulation transport for Gazebo work

The short-term goal is not a final hardware architecture. The short-term goal
is to get a fast, honest simulation loop working end to end.

## Immediate success criteria

We have reached the milestone when all of the following are true:

- [ ] A reproducible launch starts a Gazebo world with a simple wheeled robot
- [ ] The robot can be driven from project code, not only from the Gazebo UI
- [ ] The robot visibly moves, stops, and turns in the simulation
- [ ] ROS 2 exposes observed state such as `/odom`, `/tf`, and `/joint_states`
- [ ] Zig updates its logic from observed state rather than assuming commands
      succeeded
- [ ] The same high-level actuation path can be built for hardware or
      simulation

## Build-time simulation rule

Because some lower-level behavior already lives in Zig, simulation should not
require rewriting the control path around ROS-only code.

For simulation builds:

- [ ] Keep Zig responsible for issuing motor or motion intent
- [ ] Introduce build-time / comptime selection of the actuation backend
- [ ] Keep the hardware build using real `Gpio`
- [ ] Add a simulation-side implementation that broadcasts actuation intent
      instead of toggling pins
- [ ] Allow that simulation implementation to target `ROS 2` or `Gazebo`
      transport, whichever is simpler to get working first
- [ ] Keep the rest of `main_compute` unaware of whether it is talking to
      hardware or simulation

## Milestone 1: stand up the minimum ROS 2 + Gazebo scene

- [ ] Choose one known-good environment and document the exact bring-up path
- [ ] Pick the simplest car or differential-drive robot model that can accept
      commands
- [ ] Start with a flat world and one or two reference objects
- [ ] Do not model the full garden yet
- [ ] Create or capture the launch sequence for Gazebo, the robot model, and
      required bridge nodes
- [ ] Verify the robot can be driven manually from the ROS 2 CLI before
      involving Zig
- [ ] Record the exact topics, frame names, and message types used by the sim

## Milestone 2: make `main_compute` simulation-aware

- [ ] Define the narrow actuation interface that current control code calls
      into
- [ ] Refactor `Gpio` usage behind that interface instead of reaching for GPIO
      directly
- [ ] Add a simulation backend that emits motor or motion intent
- [ ] Add build config that selects hardware vs simulation backend
- [ ] Keep the simulation backend simple enough to support `forward`, `stop`,
      and `turn` before chasing a perfect protocol
- [ ] Preserve the option to send intent through `ROS 2` first, then tighten
      the motor-level interface later if needed

## Milestone 3: close the observation loop

- [ ] Consume observed state from ROS 2 instead of inferring it from commands
- [ ] Define the minimum observation type needed for the first sim milestone
- [ ] Feed back pose, heading, or odometry into Zig as observations
- [ ] Log commanded vs observed behavior for debugging
- [ ] Do not advance mission logic on "command sent"
- [ ] Advance mission logic on "motion observed"

## Milestone 4: stabilize the workflow

- [ ] Make the sim bring-up repeatable from the repo
- [ ] Write down the launch and debug checklist in docs
- [ ] Capture one smoke-test path: launch, drive forward, turn, stop, inspect
      topics
- [ ] Keep the first workflow small enough that it can run before touching
      perception or watering work

## After this sim milestone works

- [ ] Resume the broader `main_compute` daemon refactor
- [ ] Add watchdog or stale-command safety behavior
- [ ] Add fixed-rate control loop cleanup
- [ ] Revisit IMU integration and heading control
- [ ] Revisit the Zig <-> ROS boundary with a clearer picture of what the sim
      actually needs
- [ ] Only then return to perception-driven behavior, watering logic, and
      higher-level autonomy

## Explicitly not next

- [ ] Do not spend time on plant classification for this milestone
- [ ] Do not jump straight to SLAM or Nav2
- [ ] Do not require the first sim robot to match the final WATERBOT hardware
- [ ] Do not lock the design to ROS-only or Gazebo-only transport before the
      actuation abstraction exists
- [ ] Do not assume commanded motion is the same as observed motion

## Suggested implementation order

- [ ] 1. Bring up a simple Gazebo car scene and drive it manually
- [ ] 2. Record the ROS 2 topics, frames, and command path that make it work
- [ ] 3. Add a build-selected simulation actuation backend in `main_compute`
- [ ] 4. Send drive, stop, and turn intent from Zig into the sim
- [ ] 5. Feed observed state back into Zig
- [ ] 6. Resume lower-level daemon work only after that loop is proven
