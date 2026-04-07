# ROS adoption and Zig integration

This document captures the project-direction guidance around ROS, what should be
custom versus reused, and what the Zig <-> ROS interface could look like in
code.

## What ROS is

ROS, or Robot Operating System, is not an operating system in the normal sense.
It is a middleware and tooling ecosystem for robot software.

It gives you a standard vocabulary and runtime model for structuring robot
software.

The main building blocks are:

- `packages`: the unit of organization and distribution. A package usually
  contains source code, configuration, launch files, and sometimes URDF models
  or calibration data.
- `nodes`: long-running processes, or components within a process, that do one
  job. A camera driver, IMU driver, localization module, or motor controller
  would each typically be a node.
- `messages`: typed data structures passed between nodes. Examples include
  sensor readings, velocity commands, odometry, and maps.
- `topics`: named pub/sub channels used for streaming data. A camera node might
  publish images on one topic while a localization node subscribes to IMU and
  odometry topics.
- `services`: synchronous request/response APIs used for short operations. They
  are appropriate for commands like "clear costmap" or "save map".
- `actions`: goal-oriented interfaces for longer-running tasks with feedback and
  cancellation. Navigation is a typical action because it may take several
  seconds, produce progress updates, and may need to be canceled.
- `parameters`: configuration values attached to nodes. They are used for things
  like PID gains, topic names, frame IDs, device paths, and thresholds.
- `tf2`: the transform system that tracks coordinate frames such as `map`,
  `odom`, `base_link`, `camera_link`, and `laser`. This is how the rest of the
  stack understands where data is located relative to the robot and the world.
- `launch files`: startup descriptions that wire together multiple nodes,
  parameters, remappings, and runtime options into one runnable system.
- `tools`: visualization, recording, and debugging tools such as RViz, rosbag2,
  and command-line inspectors.

These pieces relate to each other in a specific way:

- a `package` contains one or more `nodes`
- a `node` publishes or subscribes to `topics`
- the data on a `topic` is a typed `message`
- a `node` may also expose a `service` for quick request/response operations
- a `node` may expose an `action` when the operation is long-running and needs
  feedback or cancellation
- `parameters` configure how the node behaves
- `tf2` provides the shared frame relationships so that messages from different
  nodes can be interpreted in the same coordinate system
- a `launch file` starts the relevant nodes with the required parameters and
  topic remappings

So instead of writing one giant robot program, you usually compose a robot as a
graph of nodes. For example:

- a camera driver node publishes image messages
- an IMU node publishes inertial messages
- a wheel odometry node publishes odometry
- a localization node subscribes to IMU and odometry, then publishes pose
- a navigation node sends velocity commands
- a motor controller node subscribes to those commands and drives the hardware

Those nodes are not just passing bytes around randomly. They are connected by
typed messages, coordinated by topic/service/action semantics, and anchored by a
shared transform tree.

So instead of writing one giant robot program, you usually compose a robot out
of nodes like:

- camera driver
- IMU driver
- motor controller
- localization
- planner
- mission logic

These nodes communicate over standard interfaces.

For your robot, ROS would mainly help with:

- integrating sensors like IMU, LiDAR, and camera
- using existing localization and navigation software
- avoiding writing SLAM and path planning from scratch
- structuring the system into clearer subsystems

The downside is that ROS adds a lot of complexity:

- more moving parts
- more setup
- more abstraction
- more concepts to learn

So the practical tradeoff is:

- If you want to build custom control software and understand everything end to
  end, staying outside ROS is reasonable for now.
- If your main goal is to get to localization/navigation faster and reuse mature
  software, ROS is often worth it.

A common pattern is:

- start without ROS for low-level motor and sensor understanding
- adopt ROS once you need SLAM, Nav2, multi-sensor integration, or a cleaner
  robotics architecture

That is why so many examples in the ecosystem are ROS-based: the ecosystem
already solved a lot of the problems you are about to run into.

## Should one person write everything?

Not really, if "everything" means all of:

- low-level motor control
- sensor drivers
- filtering and state estimation
- SLAM / relocalization
- path planning and obstacle avoidance
- perception / CV
- mission logic
- watering hardware control
- UI / telemetry / tooling
- testing and safety handling

One person can absolutely build a working robot. One person usually should not
write all of those layers from scratch.

The realistic path is:

- write the parts that are specific to your robot
- reuse the parts that are generic robotics infrastructure

For WATERBOT, I would strongly consider owning:

- hardware integration
- control architecture
- mission/state logic
- plant registry / watering policy
- calibration and tuning
- the glue between subsystems

And reusing:

- localization / SLAM
- navigation
- sensor fusion
- camera / LiDAR drivers
- visualization and debugging tools

That is still real learning. In practice, strong engineers do not prove
themselves by rebuilding the whole stack. They prove themselves by knowing what
to build, what to reuse, and how to integrate it cleanly.

So the honest answer is:

- `No`, it is not realistic to write the entire autonomy stack yourself and
  finish in a reasonable time.
- `Yes`, it is realistic for one person to build the robot if you are selective
  about what you own.

## Recommended libraries to reuse

Based on the current codebase being Zig-first with custom GPIO, channels, and
an OpenCV bridge, the recommended approach is a hybrid one:

- keep Zig for the robot-specific executive, safety policy, low-level motor
  control, watering logic, and plant registry
- reuse ROS 2 packages as separate nodes for the hard generic robotics pieces

This is a design recommendation for WATERBOT. It is not a claim that ROS
requires this split.

### Recommended libraries

- `SLAM / localization`: [slam_toolbox](https://github.com/SteveMacenski/slam_toolbox).
  This is the best fit for the planned 2D LiDAR path and is already aligned
  with the project docs.
- `Navigation / planning / recovery`: [navigation2](https://github.com/ros-navigation/navigation2).
  Treat this as a subsystem you can call into, not necessarily as the owner of
  the whole robot.
- `Sensor fusion`: [robot_localization](https://github.com/cra-ros-pkg/robot_localization).
  Use this to fuse wheel odometry, IMU, and later GPS.
- `IMU preprocessing`: [imu_tools](https://github.com/CCNYRoboticsLab/imu_tools).
  Useful if the IMU gives raw gyro/accel and you want a filtered orientation
  before or alongside EKF.
- `Transforms / coordinate frames`: [geometry2 / tf2](https://github.com/ros2/geometry2).
  If you adopt ROS navigation, this is not optional.
- `LiDAR driver`: [rplidar_ros](https://github.com/Slamtec/rplidar_ros).
  This matches the RPLIDAR A1 already documented for the project.
- `LiDAR cleanup, if needed`: [laser_filters](https://github.com/ros-perception/laser_filters).
  Good for removing bad ranges or self-hits.
- `Camera driver, if you move camera into ROS`: [usb_cam](https://github.com/ros-drivers/usb_cam),
  plus [image_common / image_transport](https://github.com/ros-perception/image_common)
  and [vision_opencv / cv_bridge](https://github.com/ros-perception/vision_opencv).
- `Visualization`: [RViz2](https://github.com/ros2/rviz).
- `Recording / replay / debugging`: [rosbag2](https://github.com/ros2/rosbag2).
- `ESP32-S3 co-processor integration`: [micro_ros_espidf_component](https://github.com/micro-ROS/micro_ros_espidf_component)
  on the ESP32 side, and [micro_ros_setup](https://github.com/micro-ROS/micro_ros_setup)
  on the host side.
- `ROS client library, if you write your own ROS-side nodes`: [rclcpp](https://github.com/ros2/rclcpp)
  on the Pi, [rclc](https://github.com/ros2/rclc) on embedded / micro-ROS style
  code.

### What to actually choose for WATERBOT

- Reuse now: `rplidar_ros`, `slam_toolbox`, `robot_localization`, `tf2`,
  `rviz2`, `rosbag2`
- Reuse once autonomous movement is in scope: `navigation2`
- Maybe reuse: `usb_cam` + `cv_bridge` only if the camera pipeline should live
  inside ROS
- Reuse later: `micro_ros_espidf_component` if control is offloaded to ESP32-S3
- Keep custom: Zig mission executive, motor/control loop, watering logic,
  plant registry, fault handling, and robot-specific behavior

### One important recommendation

Do not spend time hunting for a Zig ROS client library right now. The lower-risk
path is:

- Zig processes for executive logic and hardware control
- ROS packages for autonomy and tooling
- a narrow bridge between them

## What the Zig <-> ROS boundary should look like

There are two different boundaries worth separating. Mixing them together is
what makes ROS architecture discussions feel confusing.

### 1. Mission boundary

This is the boundary that matches the current WATERBOT direction and should be
the primary architecture for the project.

- `Zig side`: mission executive, task sequencing, watering policy, plant
  registry, safety policy, hardware ownership
- `ROS 2 side`: sensor drivers where useful, `tf2`, SLAM, localization,
  perception, path planning, navigation, RViz, rosbag
- `Bridge`: a small interface that lets Zig ask ROS for autonomy services and
  lets ROS publish results back

Typical traffic at this layer:

- `Zig -> ROS`: start mapping, stop mapping, set initial pose, navigate to
  pose, cancel navigation, inspect target
- `ROS -> Zig`: current pose, localization health, map status, navigation
  status, detections, obstacle information

A good mental model is:

`Zig mission executive -> bridge -> ROS autonomy services`

In this model, Zig is still the orchestrator of robot behavior. ROS is the
runtime where reusable autonomy modules talk to each other.

### 2. Drive boundary

If you later adopt Nav2 or another ROS controller, there is usually a second,
lower boundary for motion execution:

- ROS planning/controller nodes produce `cmd_vel`
- Zig consumes that desired motion, applies hardware-specific control, and
  enforces safety
- Zig publishes odometry, drive status, and faults back into ROS

A good mental model is:

`Nav2 / ROS -> bridge node -> Unix socket -> Zig control loop`

and

`Zig telemetry -> Unix socket -> bridge node -> ROS topics`

This narrower boundary does not make ROS the top-level brain. It only means ROS
is allowed to request robot motion while Zig keeps the final say over actuation
and safety.

### Recommended boundary

Start with the mission boundary as the project-level architecture. Add the drive
boundary only when you want ROS navigation to actively command motion.

That gives you clean layering:

- Zig decides goals, modes, and watering behavior
- ROS computes map, pose, path, and perception outputs
- Zig either uses those results directly or delegates moment-to-moment motion
  execution to Nav2

## What the protocol might look like

At the mission boundary, a narrow API could look like:

```zig
pub const MissionRequest = union(enum) {
    start_mapping,
    stop_mapping,
    set_initial_pose: Pose2,
    navigate_to_pose: Pose2,
    cancel_navigation,
    inspect_plant: u32,
};

pub const MissionEvent = union(enum) {
    pose: Pose2,
    localization: LocalizationState,
    navigation: NavigationState,
    detection: PlantDetection,
    fault: Fault,
};

pub const Pose2 = struct {
    x: f32,
    y: f32,
    theta: f32,
};
```

If you later add a drive boundary for Nav2, keep that lower-level API even
smaller:

```zig
pub const DriveCommand = union(enum) {
    velocity: VelocityCmd,
    estop,
};

pub const VelocityCmd = struct {
    linear_mps: f32,
    angular_rad_s: f32,
    valid_for_ms: u32 = 100,
};

pub const DriveTelemetry = union(enum) {
    odom: Odom,
    status: DriveStatus,
    fault: Fault,
};

pub const Odom = struct {
    x: f32,
    y: f32,
    theta: f32,
    linear_mps: f32,
    angular_rad_s: f32,
};
```

Notice the difference:

- the mission boundary is about goals and status
- the drive boundary is about immediate motion requests and feedback

## Zig side example

A Zig mission loop might look like this:

```zig
fn missionLoop(ros: RosClient, registry: *Registry) !void {
    while (true) {
        const plant = try registry.nextNeedingWater() orelse continue;

        try ros.send(.{ .navigate_to_pose = plant.pose });
        const nav = try ros.waitForNavigation();

        if (nav != .succeeded) continue;
        try watering.waterPlant(plant.id);
    }
}
```

If you later let Nav2 execute motion, the existing control-loop idea still
applies below that layer:

- ROS does not drive GPIO directly
- ROS requests robot motion through `cmd_vel`
- Zig owns hardware-specific actuation and closed-loop correction

## How this fits the current code

The current `pkgs/main_compute` code mostly lines up with the lower,
hardware-facing side of this split:

- `pkgs/main_compute/src/protocol.zig`
- `pkgs/main_compute/src/main.zig`
- `pkgs/main_compute/src/Server.zig`

Those pieces are best thought of as the robot runtime and bridge substrate, not
as proof that ROS must own the whole autonomy stack.

## Why this is a good first interface

- Zig stays in control of robot-specific behavior and safety
- ROS stays focused on reusable autonomy modules and tooling
- the boundary is easy to debug with plain messages
- you can test each side independently
- you can adopt Nav2 later without rewriting the project-level executive

## What not to do first

Do not try to:

- embed ROS directly inside Zig via low-level C bindings
- expose raw GPIO concepts to ROS
- force watering policy into ROS packages
- assume there can only be one "orchestrator" in the whole system

Different layers can orchestrate different concerns. For WATERBOT, Zig should
own mission behavior while ROS owns reusable autonomy subsystems.

## Source links

These are the main upstream projects referenced in the recommendations:

- [slam_toolbox](https://github.com/SteveMacenski/slam_toolbox)
- [navigation2](https://github.com/ros-navigation/navigation2)
- [robot_localization](https://github.com/cra-ros-pkg/robot_localization)
- [imu_tools](https://github.com/CCNYRoboticsLab/imu_tools)
- [geometry2 / tf2](https://github.com/ros2/geometry2)
- [rplidar_ros](https://github.com/Slamtec/rplidar_ros)
- [laser_filters](https://github.com/ros-perception/laser_filters)
- [usb_cam](https://github.com/ros-drivers/usb_cam)
- [image_common](https://github.com/ros-perception/image_common)
- [vision_opencv](https://github.com/ros-perception/vision_opencv)
- [RViz2](https://github.com/ros2/rviz)
- [rosbag2](https://github.com/ros2/rosbag2)
- [micro_ros_espidf_component](https://github.com/micro-ROS/micro_ros_espidf_component)
- [micro_ros_setup](https://github.com/micro-ROS/micro_ros_setup)
- [rclcpp](https://github.com/ros2/rclcpp)
- [rclc](https://github.com/ros2/rclc)
