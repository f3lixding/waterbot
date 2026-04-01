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

As of March 31, 2026, and based on the current codebase being Zig-first with
custom GPIO, HTTP, channels, and an OpenCV bridge, the recommended approach is
a hybrid one:

- keep Zig for low-level control and your project-specific logic
- reuse ROS 2 packages as separate processes/nodes for the hard generic
  robotics pieces

That last part is an inference from the current codebase plus the current ROS
ecosystem, not a direct source claim.

### Recommended libraries

- `SLAM / localization`: [slam_toolbox](https://github.com/SteveMacenski/slam_toolbox).
  This is the best fit for the planned 2D LiDAR path and is already aligned
  with the project docs.
- `Navigation / planning / recovery`: [navigation2](https://github.com/ros-navigation/navigation2).
  If you want a smaller entry point, study and use
  [nav2_velocity_smoother](https://github.com/ros-navigation/navigation2/tree/main/nav2_velocity_smoother),
  [nav2_waypoint_follower](https://github.com/ros-navigation/navigation2/tree/main/nav2_waypoint_follower),
  and later
  [nav2_bt_navigator](https://github.com/ros-navigation/navigation2/tree/main/nav2_bt_navigator).
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

- Reuse now: `rplidar_ros`, `slam_toolbox`, `robot_localization`,
  `navigation2`, `tf2`, `rviz2`, `rosbag2`
- Reuse later: `micro_ros_espidf_component` if control is offloaded to ESP32-S3
- Maybe reuse: `usb_cam` + `cv_bridge` only if the camera pipeline should live
  inside ROS
- Keep custom: the Zig motor/control loop, watering logic, plant registry, and
  mission-specific behavior

### One important recommendation

Do not spend time hunting for a Zig ROS client library right now. The lower-risk
path is:

- Zig process for low-level/project-specific logic
- ROS packages for autonomy and tooling
- a narrow bridge between them

## What the Zig <-> ROS boundary should look like

With the current repo, the cleanest interface is:

- `ROS 2 side`: owns LiDAR, IMU, SLAM, localization, navigation
- `Zig side`: owns motors, watering hardware, and the custom control/runtime
- `Bridge`: a small ROS node that translates ROS topics/actions into the Zig
  socket protocol

That matches the existing code in:

- `pkgs/main_compute/src/protocol.zig`
- `pkgs/main_compute/src/main.zig`
- `pkgs/main_compute/src/Server.zig`

### Recommended boundary

Instead of trying to make Zig speak ROS directly, make the boundary very small:

- ROS sends `cmd_vel`, `water command`, `mode change`
- Zig sends back `odometry`, `motor status`, `watering status`, `faults`

A good mental model is:

`Nav2 / ROS -> bridge node -> Unix socket -> Zig control loop`

and

`Zig telemetry -> Unix socket -> bridge node -> ROS topics`

### What the protocol might look like

The current command protocol is directional. The suggested evolution is a narrow
robot API:

```zig
pub const Command = union(enum) {
    velocity: VelocityCmd,
    water: WaterCmd,
    estop,
};

pub const VelocityCmd = struct {
    linear_mps: f32,
    angular_rad_s: f32,
    valid_for_ms: u32 = 100,
};

pub const WaterCmd = struct {
    plant_id: u32,
    ml: f32,
};

pub const Telemetry = union(enum) {
    odom: Odom,
    status: Status,
    fault: Fault,
};

pub const Odom = struct {
    x: f32,
    y: f32,
    theta: f32,
    linear_mps: f32,
    angular_rad_s: f32,
};

pub const Status = struct {
    battery_v: f32,
    watering: bool,
};

pub const Fault = struct {
    code: []const u8,
};
```

## Zig side example

This is the side the repo already mostly has. The main change is that instead
of the browser/UI being the main client, a ROS bridge node becomes the client.

A control loop sketch in Zig would look like this:

```zig
fn controlLoop(rx: Rx, telemetry_tx: TelemetryTx) !void {
    var desired = VelocityCmd{
        .linear_mps = 0,
        .angular_rad_s = 0,
        .valid_for_ms = 100,
    };

    while (true) {
        const tick_deadline = try instantAfter(20 * std.time.ns_per_ms);

        while (rx.recvWithTimeout(tick_deadline)) |cmd| {
            switch (cmd) {
                .velocity => |v| desired = v,
                .water => |w| try watering.start(w),
                .estop => {
                    desired.linear_mps = 0;
                    desired.angular_rad_s = 0;
                    try motors.stop();
                },
            }
        } else |err| switch (err) {
            error.Timeout => {},
            error.Closed => return,
            else => return err,
        }

        const imu = try estimator.readImu();
        const odom = try estimator.update(imu);
        const motor_cmd = controller.compute(desired, odom);

        try motors.apply(motor_cmd);
        try telemetry_tx.send(.{ .odom = odom });
    }
}
```

That is the key idea:

- ROS does not tell Zig "left" or "right"
- ROS tells Zig the desired robot motion
- Zig owns the hardware-specific actuation and closed-loop correction

## ROS side example

The bridge node can be very small. A separate `C++` ROS node built with
`rclcpp` is a good fit here if you do not want to introduce a garbage-collected
runtime into the stack.

Example `rclcpp` bridge:

```cpp
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstring>
#include <string>

#include <geometry_msgs/msg/twist.hpp>
#include <nav_msgs/msg/odometry.hpp>
#include <nlohmann/json.hpp>
#include <rclcpp/rclcpp.hpp>

class WaterbotBridge : public rclcpp::Node {
public:
  WaterbotBridge() : Node("waterbot_bridge") {
    sock_fd_ = connect_unix_socket("/tmp/main_compute.sock");
    if (sock_fd_ < 0) {
      throw std::runtime_error("failed to connect to Zig backend");
    }

    cmd_sub_ = create_subscription<geometry_msgs::msg::Twist>(
        "/cmd_vel", 10,
        std::bind(&WaterbotBridge::on_cmd_vel, this, std::placeholders::_1));

    odom_pub_ = create_publisher<nav_msgs::msg::Odometry>("/waterbot/odom", 10);

    timer_ = create_wall_timer(
        std::chrono::milliseconds(20),
        std::bind(&WaterbotBridge::poll_backend, this));
  }

  ~WaterbotBridge() override {
    if (sock_fd_ >= 0) {
      close(sock_fd_);
    }
  }

private:
  static int connect_unix_socket(const char *path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, path, sizeof(addr.sun_path) - 1);

    if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
      close(fd);
      return -1;
    }

    return fd;
  }

  void on_cmd_vel(const geometry_msgs::msg::Twist::SharedPtr msg) {
    nlohmann::json payload = {
        {"velocity",
         {{"linear_mps", msg->linear.x},
          {"angular_rad_s", msg->angular.z},
          {"valid_for_ms", 100}}}};

    auto line = payload.dump() + "\n";
    ::send(sock_fd_, line.data(), line.size(), 0);
  }

  void poll_backend() {
    char buf[4096];
    const ssize_t n = ::recv(sock_fd_, buf, sizeof(buf), MSG_DONTWAIT);
    if (n <= 0) return;

    rx_buf_.append(buf, static_cast<size_t>(n));

    std::size_t pos = 0;
    while ((pos = rx_buf_.find('\n')) != std::string::npos) {
      std::string line = rx_buf_.substr(0, pos);
      rx_buf_.erase(0, pos + 1);
      handle_line(line);
    }
  }

  void handle_line(const std::string &line) {
    auto msg = nlohmann::json::parse(line, nullptr, false);
    if (msg.is_discarded()) return;
    if (!msg.contains("odom")) return;

    const auto &od = msg["odom"];

    nav_msgs::msg::Odometry out;
    out.pose.pose.position.x = od.value("x", 0.0);
    out.pose.pose.position.y = od.value("y", 0.0);
    out.twist.twist.linear.x = od.value("linear_mps", 0.0);
    out.twist.twist.angular.z = od.value("angular_rad_s", 0.0);

    odom_pub_->publish(out);
  }

  int sock_fd_{-1};
  std::string rx_buf_;

  rclcpp::Subscription<geometry_msgs::msg::Twist>::SharedPtr cmd_sub_;
  rclcpp::Publisher<nav_msgs::msg::Odometry>::SharedPtr odom_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char **argv) {
  rclcpp::init(argc, argv);
  auto node = std::make_shared<WaterbotBridge>();
  rclcpp::spin(node);
  rclcpp::shutdown();
  return 0;
}
```

That is the whole pattern:

- subscribe to ROS topic
- serialize to the Zig protocol
- send over UDS
- read telemetry back
- republish as ROS topics

## How this fits the current code

Most of the plumbing already exists:

- command decoding in `pkgs/main_compute/src/protocol.zig`
- dispatch into a channel in `pkgs/main_compute/src/main.zig`
- a socket-serving pattern in `pkgs/main_compute/src/Server.zig`

So the practical change is:

- keep the Zig daemon
- shrink or remove the browser-first server path
- add a ROS bridge node
- widen the protocol from `left/right/stop` to `velocity/status`

## Why this is a good first interface

- Zig stays in control of hardware
- ROS stays in control of autonomy
- the boundary is easy to debug with plain JSON
- you can test each side independently
- later, if JSON is replaced with protobuf or a binary format, the architecture
  still holds

## What not to do first

Do not try to:

- embed ROS directly inside Zig via low-level C bindings
- make Nav2 call the motors directly
- expose raw GPIO concepts to ROS

That is too much coupling too early.

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
