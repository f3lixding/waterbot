# Control architecture

This document captures a practical control architecture for WATERBOT.

The main point is:

- A loop is a logical responsibility.
- A thread is only one way to schedule work.

These are not the same thing, and they should not be mapped 1:1 by default.

## Why this matters

It is easy to imagine the system as "one loop per thread" with queues between
everything. That can work, but it is usually not the best default for a small
robot.

Too many threads tend to create:

- Timing nondeterminism
- Queue backlogs
- Stale control data
- Locking complexity
- Harder debugging

For robotics work, the common pattern is to keep the timing-sensitive control
path small and deterministic, and isolate blocking or heavy work elsewhere.

## Recommended model

WATERBOT should use a hybrid model:

- One fixed-rate control thread for timing-sensitive behavior
- Separate threads for blocking or heavy work such as camera and networking
- A small number of communication patterns chosen by data type

This is a better fit than creating one thread for every conceptual loop.

## Logical loops

These are the loops the robot will eventually need. They are logical
responsibilities, not a thread plan.

### Ingress loop

Purpose:

- Receive manual commands
- Receive mission requests
- Trigger testing or debug actions

Notes:

- This is naturally event-driven
- This is already partially present in the server layer

### Actuator loop

Purpose:

- Apply motor direction and PWM
- Apply braking
- Enforce safe stop behavior
- Enforce stale-command timeouts

Notes:

- This should be the narrow responsibility of `commandActuatorLoop`
- This loop should stay simple and deterministic

### Perception loop

Purpose:

- Read camera frames
- Run CV processing
- Emit observations such as target-left, target-right, centered, or not found

Notes:

- This is already partially present in the current pipeline
- Perception should report observations, not directly own behavior

### State-estimation loop

Purpose:

- Read IMU
- Later read wheel encoders
- Maintain heading and pose estimates

Notes:

- With only an IMU, heading estimation is still useful
- IMU alone is not enough for accurate long-term position tracking

### Heading-control loop

Purpose:

- Keep the robot pointed at a target heading
- Correct left and right motor output while driving

Notes:

- This is useful even before full localization exists
- It enables "turn to heading" and "drive straight while holding heading"

### Mission or supervisor loop

Purpose:

- Decide what the robot is trying to do next
- Sequence behaviors such as search, approach, water, verify, and recover

Notes:

- This is where the high-level robot state machine should live

### Localization and navigation loop

Purpose:

- Match the robot against a known map
- Plan paths to plant coordinates
- Recover after drift or being moved

Notes:

- This can start simple with landmarks or fiducials
- LiDAR becomes valuable if marker-based relocalization is not robust enough

### Watering loop

Purpose:

- Run the pump or valve
- Time or meter the dose
- Verify that watering actually happened

Notes:

- This is control logic, not just hardware switching

### Safety or watchdog loop

Purpose:

- Stop on stale commands
- Stop on sensor failure
- Stop on actuator fault or abnormal motion

Notes:

- This can live inside the actuator loop instead of being its own thread

## Threads to start with

For the current project stage, a small thread model is enough:

- Control thread
- Perception thread
- Server or UI thread

### Control thread

Responsibilities:

- Actuator loop
- State estimation from current sensors
- Heading control
- Safety timeout handling
- Mission logic at a lower internal rate

This thread should run at a fixed rate.

### Perception thread

esponsibilities:

- Camera capture
- CV processing
- Update latest target observation

This thread may run at the camera frame rate or lower.

### Server or UI thread

Responsibilities:

- Receive user commands
- Receive mission requests
- Send discrete events into the system

This thread is naturally event-driven.

## Communication patterns

Different data types should use different communication patterns.

### Queue or message passing

Good for:

- Start mission
- Stop mission
- Emergency stop
- Begin watering plant N

Use this for discrete events and commands.

### Latest-value shared state

Good for:

- Latest IMU reading
- Latest heading estimate
- Latest target observation
- Latest plant pose estimate

Use this for fast-changing state where only the newest value matters.

This is often better than queueing control data because old values become stale
quickly.

### Ring buffer

Good for:

- Camera frames
- Other high-rate streams where short history is useful

### Atomic flag

Good for:

- Emergency stop
- Shutdown requested
- Sensor health flags

## Why queues are not enough

Message passing is useful, but it is not the answer to every communication
problem.

For example, heading corrections should usually not be queued. If a queue
stores many old corrections, the robot acts on stale information. In that case,
the controller usually wants the newest sensor state, not the entire history.

That is why robotics systems often mix:

- Queues for events
- Shared snapshots for state
- Special high-priority paths for safety

## Recommended responsibility split

The system should look roughly like this:

`mission loop -> desired motion`

`state estimation + perception -> observations`

`heading or navigation controller -> motor setpoints`

`commandActuatorLoop -> GPIO or PWM output`

This keeps the low-level motor path clean while allowing higher-level logic to
grow without overloading `commandActuatorLoop`.

## What `commandActuatorLoop` should be

`commandActuatorLoop` should remain close to hardware:

- Apply motor outputs
- Brake safely
- Enforce timeouts
- Accept small correction inputs from controllers

`commandActuatorLoop` should not become the place for:

- Plant identity logic
- CV policy
- Map-level navigation
- Mission sequencing

Those belong above the actuator layer.

## Initial implementation order

Given the current state of the project, the next practical order is:

1. Keep `commandActuatorLoop` as a low-level actuator loop
2. Add IMU-based heading estimation
3. Add a heading controller
4. Make perception publish observations instead of directly driving behavior
5. Add a small mission controller or state machine
6. Add localization and navigation once closed-loop motion is reliable

## First working capability target

Before full localization or watering, the architecture should support:

- Turn to a target heading
- Drive straight while holding heading
- Search for a visual target
- Approach the target
- Stop safely on timeout or loss of target

That is a reasonable first closed-loop milestone for WATERBOT.
