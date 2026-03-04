# Relocalization

How robots relocalize after being moved — formally known as the
**"kidnapped robot" problem**.

## Core approaches

### Feature matching against a known map

The robot takes sensor readings (camera, LiDAR) of its current
surroundings and tries to match distinctive features (landmarks,
corners, textures) against its previously built map. Once enough
features match, it can determine where it is.

### Monte Carlo localization (particle filters)

The robot scatters many hypothetical positions ("particles") across the
map, then progressively eliminates unlikely ones as sensor readings come
in. After enough observations, the particles converge on the true
position.

### Build a new local map, then merge

If the robot can't immediately relocalize, it starts mapping from
scratch and later merges the new map with the old one once it recognizes
an overlapping area. This is common in "lifelong SLAM" systems.

### Sensor fusion

Combining multiple sensor types (IMU, wheel odometry, GPS, visual,
LiDAR) makes localization more robust. Outdoors, even a rough GPS fix
can narrow the search space dramatically.

## Relevance to WATERBOT

For an outdoor garden robot, we are in a somewhat easier position than
indoor robots:

- **GPS** can give a coarse initial position (within a few meters)
- **Visual landmarks** (fences, structures, large plants) can refine
  from there
- **Fiducial markers** (e.g. ArUco tags) placed at known positions in
  the garden serve as cheap, reliable reference points

## Frameworks and tools

- [SLAM Toolbox](https://github.com/SteveMacenski/slam_toolbox) — ROS
  package for lifelong mapping and localization
- [Cartographer](https://github.com/cartographer-project/cartographer)
  — real-time SLAM by Google
- [RTAB-Map](http://introlab.github.io/rtabmap/) — RGB-D, stereo, and
  LiDAR SLAM

## References

- [Relocalization — Computer Science Wiki](https://computersciencewiki.org/index.php/Relocalization)
- [SLAM — Wikipedia](https://en.wikipedia.org/wiki/Simultaneous_localization_and_mapping)
- [What is SLAM — MATLAB & Simulink](https://www.mathworks.com/discovery/slam.html)
- [Understanding SLAM — Flyability](https://www.flyability.com/blog/simultaneous-localization-and-mapping)
