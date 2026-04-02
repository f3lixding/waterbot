# ROS simulation options

This note answers a practical question: how to learn ROS without first building
the full robot hardware.

## Short answer

Yes. Simulation is a normal way to learn ROS.

If starting fresh, use `ROS 2`, not `ROS 1`. ROS 1 Noetic reached end of life
on May 31, 2025, so new learning effort should target the current ROS 2
ecosystem.

## Recommended learning path

- Start with `turtlesim` to learn the ROS basics:
  nodes, topics, services, parameters, and CLI tools
- Then move to `Gazebo` with a standard robot model such as `TurtleBot3`
- Use `RViz2` alongside simulation to inspect topics, transforms, maps, and
  robot state
- Once that is comfortable, move on to `slam_toolbox`, `Nav2`, and sensor
  fusion packages

This sequence gives fast feedback without requiring motors, sensors, or a full
mechanical platform.

## Recommended simulators

### `turtlesim`

Best first step.

- Very lightweight
- Official ROS learning tool
- Good for understanding the ROS runtime model before dealing with full robot
  simulation

Use this first, but do not stop here because it does not model a real mobile
robot.

### `Gazebo`

Best general-purpose choice for learning ROS with a simulated robot.

- Strong ROS 2 integration through `ros_gz`
- Commonly used for robot navigation, mapping, and control workflows
- Good fit for learning `Nav2`, simulated sensors, and robot behavior in a 3D
  world

For a stable beginner path, use the officially supported pairing of
`Ubuntu 24.04 + ROS 2 Jazzy + Gazebo Harmonic`.

Avoid older tutorials based on `Gazebo Classic` unless there is a specific
reason to follow legacy material.

### `Webots`

Good alternative if a friendlier desktop simulator is preferred.

- Open source
- Cross-platform
- Supports ROS 2 integration
- Often easier to approach than heavier simulation stacks

### `Isaac Sim`

Good choice for perception-heavy work.

- Strong ROS 2 bridge support
- Better visuals and synthetic-data workflows
- Higher GPU and system requirements

This is usually not the best first simulator unless the main goal is cameras,
vision, or ML-heavy robotics work.

### `CoppeliaSim`

Useful if flexibility and scripting matter more than ecosystem popularity.

- ROS 2 topics, services, and actions support
- Good for experimentation and custom control setups
- Less common than Gazebo in general ROS beginner material

## Practical recommendation for WATERBOT

For this project, the most useful learning sequence is:

- `turtlesim` for ROS basics
- `Gazebo + RViz2 + TurtleBot3` for simulated mobile robot workflows
- `slam_toolbox` and `Nav2` once basic simulation is comfortable

That path gets closest to the eventual WATERBOT stack without forcing early
hardware work.

## Notes on ROS versions

As of April 2, 2026:

- `Kilted Kaiju` is the latest stable ROS 2 distribution
- `Jazzy Jalisco` remains a strong long-term-support choice for new projects
- Official Gazebo documentation recommends `ROS 2 Jazzy` with `Gazebo Harmonic`
  for new users on Ubuntu 24.04

For learning, prioritize current ROS 2 material and avoid spending time on ROS
1 unless maintaining legacy systems.

## References

- [ROS 1 Noetic end of life](https://www.ros.org/blog/noetic-eol/)
- [ROS 2 distributions](https://docs.ros.org/en/kilted/Releases.html)
- [Using turtlesim, ros2, and rqt](https://docs.ros.org/en/rolling/Tutorials/Beginner-CLI-Tools/Introducing-Turtlesim/Introducing-Turtlesim.html)
- [Gazebo ROS 2 overview](https://gazebosim.org/docs/latest/ros2_overview/)
- [Installing Gazebo with ROS](https://gazebosim.org/docs/harmonic/ros_installation/)
- [Nav2 getting started](https://docs.nav2.org/getting_started/)
- [Webots ROS 2 tutorial](https://docs.ros.org/en/rolling/Tutorials/Advanced/Simulators/Webots/Simulation-Webots.html)
- [Webots](https://www.cyberbotics.com/)
- [Isaac Sim ROS 2 docs](https://docs.isaacsim.omniverse.nvidia.com/latest/ros2_tutorials/ros2_landing_page.html)
- [CoppeliaSim ROS 2 interface](https://manual.coppeliarobotics.com/en/ros2Interface.htm)
