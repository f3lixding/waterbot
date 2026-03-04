# MentorPi comparison

The [Hiwonder MentorPi](https://www.hiwonder.com/products/mentorpi-m1)
is a commercial ROS2 robot car powered by a Raspberry Pi 5. It does
most of what WATERBOT aims to do (minus the watering). This doc
compares its hardware and capabilities against our parts list in
[BOARDS.md](BOARDS.md).

## Hardware side-by-side

| Concern | MentorPi | WATERBOT | Notes |
|---|---|---|---|
| Main compute | Raspberry Pi 5 | Raspberry Pi 5 | Same |
| Real-time co-processor | RRC Lite (STM32F407) | ESP32-S3 (Phase 6) | Same role, different chip |
| LiDAR | STL-19P TOF | Slamtec RPLIDAR A1 | Both 2D 360°; A1 has longer range |
| Camera | 3D depth (IR + RGB, 0.2–4 m) | ESP32-S3-CAM (2D RGB) | Theirs adds depth sensing |
| Motor control | STM32 on RRC board + closed-loop encoders | L298N + encoder motors | Same approach; they use a dedicated board |
| IMU | Built into RRC board | **Not yet listed** | Gap — add MPU6050 (~$3) |
| SLAM software | slam_toolbox, RTAB-VSLAM | slam_toolbox | Same |
| Navigation | Nav2 (AMCL, DWA) | Nav2 | Same |
| Chassis | Mecanum or Ackermann | 2WD differential | Simpler, fine for starting |

## Capability comparison

### Fully achievable with our parts

- **Mapping / SLAM** — RPLIDAR A1 is well-supported in ROS2 and has
  longer range than MentorPi's STL-19P.
- **Autonomous navigation** — Nav2 stack is identical. Wheel encoders
  provide odometry.
- **Remote control** — Pi hosts a server; laptop sends commands. Same
  principle as MentorPi's app control.
- **Color/object tracking** — OpenCV runs on the Pi; ESP32-S3-CAM
  streams frames. Sufficient for plant ID.

### Achievable with small additions

- **Better odometry** — MentorPi includes an IMU (inertial
  measurement unit) on its RRC board for fusing wheel encoder data
  with gyroscope/accelerometer readings. Adding an MPU6050 (~$3) to
  our build closes this gap. Relevant from Phase 3 onward.
- **Depth-based obstacle avoidance** — MentorPi's 3D depth camera
  provides point-cloud data for obstacle detection and 3D SLAM. Our
  2D RGB camera cannot do this. An OAK-D Lite (~$50–80) would be an
  optional upgrade if depth sensing is needed later.

### What we have that MentorPi does not

- Soil moisture sensing (STEMMA sensors)
- GPS for outdoor relocalization
- Plant registry and watering decision logic
- Irrigation delivery mechanism (pump/valve — TBD)

## Gaps to address

| Gap | Fix | Cost | When |
|---|---|---|---|
| No IMU | Add MPU6050 (I2C, 6-axis) | ~$3 | Phase 3 (autonomous nav) |
| No depth camera | Optional: add OAK-D Lite | ~$50–80 | If 3D obstacle avoidance is needed |

## Takeaway

Our parts list is validated by MentorPi's architecture. The same
software stack (ROS2, slam_toolbox, Nav2) runs on the same main
compute (Pi 5). The main structural difference is their dedicated
STM32 real-time board vs our plan to start with direct GPIO and add
an ESP32 later. The phased approach in BOARDS.md remains sound.

## References

- [MentorPi product page](https://www.hiwonder.com/products/mentorpi-m1)
- [MentorPi documentation](https://docs.hiwonder.com/projects/MentorPi/en/latest/)
- [MentorPi on CNX Software](https://www.cnx-software.com/2024/10/23/mentorpi-is-a-ros2-compatible-raspberry-pi-5-based-robot-car-with-mecanum-or-ackermann-chassis/)
- [MPU6050 (SparkFun)](https://www.sparkfun.com/products/11028)
- [OAK-D Lite (Luxonis)](https://shop.luxonis.com/products/oak-d-lite-1)
