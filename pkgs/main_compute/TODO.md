# TODO

## Immediate next steps

- [ ] Keep `mainLoop` focused on low-level actuation and safety only
- [ ] Add a mission controller / state machine above `mainLoop`
- [ ] Turn motor control into closed-loop control instead of a passthrough
- [ ] Wire in wheel encoder odometry
- [ ] Add watchdog stop / timeout handling for stale commands

## Control loop and orchestration

- [ ] Define robot states: idle, localize, navigate, acquire target, water, verify, error
- [ ] Split perception results from motor commands
- [ ] Make the pipeline report observations, not directly drive behavior
- [ ] Carry command payload speed through to motor output instead of ignoring it
- [ ] Add recovery paths for target-not-found, obstacle, and actuator failure cases

## Localization and navigation

- [ ] Choose a first localization strategy
- [ ] Start with encoders + IMU + fixed landmarks / fiducials if LiDAR is deferred
- [ ] Add LiDAR only if marker-based relocalization is not robust enough
- [ ] Represent plant positions in map coordinates
- [ ] Prove basic closed-loop motion primitives: drive straight and rotate in place

## Plant identity and watering

- [ ] Separate plant classification from plant identity persistence
- [ ] Register plants by stable ID and map position
- [ ] Add moisture sensor integration and nearest-sensor lookup
- [ ] Define watering commands: target, duration, and dose
- [ ] Add verification that water was actually dispensed

## Pipeline and runtime quality

- [ ] Refine pipeline logic
- [ ] Conditional compilation to assist testing on the PC
- [ ] Conditionally substitute GPIO dependency
- [ ] Conditionally substitute camera dependency
- [ ] Decide whether logging level should stay runtime-derived or be baked in

## Suggested implementation order

- [ ] 1. Closed-loop drive and turn primitives
- [ ] 2. Odometry + IMU integration
- [ ] 3. Localization strategy prototype
- [ ] 4. Mission controller / state machine
- [ ] 5. Plant registry and identity model
- [ ] 6. Watering actuator and moisture sensor integration
