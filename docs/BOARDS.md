# Boards and modules

Hardware components needed for WATERBOT, organized by purpose and
broken down into incremental project phases.

## Full component table

| Purpose | Chip / module | Price (approx.) | Where to buy |
|---|---|---|---|
| Main compute | Raspberry Pi 5 (4 GB) | ~$75 | CanaKit, PiShop, Adafruit |
| Motor driver (dual H-bridge) | L298N | ~$5 | Amazon, SunFounder |
| Chassis (2WD, 22 × 17.5 cm, w/ speed encoders) | DIYables 2WD Car Chassis Kit | ~$20 | DIYables, Amazon |
| LiDAR (360° mapping for SLAM) | Slamtec RPLIDAR A1 | ~$100 | Adafruit, Amazon, Waveshare |
| Real-time co-processor (motor PWM, sensor I/O) | ESP32-S3 | ~$7–15 | Amazon, AliExpress |
| Plant camera (visual ID, health) | ESP32-S3-CAM w/ OV2640 | ~$15–17 | Amazon, LILYGO |
| Soil moisture sensor (per-plant, I2C) | Adafruit STEMMA Soil Sensor | ~$7.50 each | Adafruit, Amazon |
| GPS (coarse outdoor localization) | u-blox NEO-M8N | ~$10–15 | Amazon, RobotShop |

## Project phases

Each phase builds on the previous one. Only buy what you need for the
current phase.

### Phase 1 — Remote-controlled driving (~$100)

Goal: Control the car via keyboard input from a laptop, sending
commands over Wi-Fi to a server running on the Pi.

| Component | Why |
|---|---|
| Raspberry Pi 5 (4 GB) | Hosts the control server, drives GPIO |
| L298N motor driver | Translates Pi GPIO signals into motor power |
| DIYables 2WD Car Chassis Kit | Wheels, motors, frame |

What you'll learn: GPIO motor control, basic networking (WebSocket or
UDP server on Pi, client on laptop), PWM speed control, power
management.

### Phase 2 — Mapping / SLAM (~$100 additional)

Goal: Mount a LiDAR on the Phase 1 car, run SLAM Toolbox on the Pi
to build a 2D map of the environment while driving manually.

| Component | Why |
|---|---|
| Slamtec RPLIDAR A1 | 360° laser scans for SLAM |

What you'll learn: ROS2 basics, SLAM Toolbox integration, reading
and visualizing occupancy grid maps, coordinate frames (tf2).

### Phase 3 — Autonomous navigation (~$0 additional hardware)

Goal: Given the map from Phase 2, the car plans a path and drives
itself to a target coordinate. Colocation (knowing where it is on
the map) is solved here.

| Component | Why |
|---|---|
| (no new hardware) | Nav2 stack runs on the Pi using existing LiDAR |

What you'll learn: Nav2 (path planning, obstacle avoidance),
localization (AMCL), odometry from wheel encoders.

### Phase 4 — Plant identification (~$15–17 additional)

Goal: Mount a camera, identify plants visually, and register them in
a database with their map coordinates.

| Component | Why |
|---|---|
| ESP32-S3-CAM w/ OV2640 | Captures plant images for classification |

What you'll learn: Image capture and streaming, plant classification
(on-device or via Pi), database design for plant registry.

### Phase 5 — Soil sensing and watering (~$7.50+ additional)

Goal: Read soil moisture per-plant, decide watering amount, and
deliver water.

| Component | Why |
|---|---|
| Adafruit STEMMA Soil Sensor (one per plant) | Capacitive moisture reading over I2C |

What you'll learn: I2C sensor wiring, decision logic for irrigation,
water delivery mechanism (pump/valve — TBD).

### Phase 6 — Outdoor and real-time hardening (~$17–30 additional)

Goal: Move outdoors. Add GPS for coarse localization and an ESP32 for
real-time motor control if Pi GPIO jitter becomes a problem.

| Component | Why |
|---|---|
| u-blox NEO-M8N | GPS for outdoor relocalization |
| ESP32-S3 (optional) | Offload real-time motor/sensor I/O from Pi |

What you'll learn: GPS integration, micro-ROS, outdoor SLAM
challenges, sensor fusion.

## ESP32-S3 ↔ Raspberry Pi communication

Relevant from Phase 6 onward, if/when a real-time co-processor is
needed.

Two supported methods:

- **Serial/UART** — Wire ESP32 TX/RX to Pi GPIO UART (3 wires: TX,
  RX, GND). Lowest latency, simplest setup. Default for micro-ROS.
- **Wi-Fi/UDP** — ESP32 joins the same network as the Pi and
  communicates via micro-ROS over UDP. No wires, slightly higher
  latency.

In both cases the ESP32 runs micro-ROS firmware and appears as a
standard ROS2 node.

A ready-made option is the [Yahboom MicroROS expansion board](https://category.yahboom.net/products/microros-board),
which sits on a Pi 5 and integrates an ESP32-S3, motor drivers, IMU,
and a LiDAR port — all pre-flashed with micro-ROS.

## References

- [Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/)
- [ESP32-S3](https://www.espressif.com/en/products/socs/esp32-s3)
- [RPLIDAR A1](https://www.slamtec.com/en/lidar/a1)
- [Adafruit STEMMA Soil Sensor](https://www.adafruit.com/product/4026)
- [L298N motor driver](https://www.amazon.com/l298n/s?k=l298n)
- [u-blox NEO-M8N](https://www.u-blox.com/en/product/neo-m8-series)
- [SLAM Toolbox (ROS2)](https://github.com/SteveMacenski/slam_toolbox)
- [Nav2](https://docs.nav2.org/)
- [micro-ROS on ESP32](https://micro.ros.org/)
- [DIYables 2WD Car Chassis Kit](https://diyables.io/products/rc-2wd-car-chassis-kit-with-motor-speed-encoder)
- [Yahboom MicroROS expansion board](https://category.yahboom.net/products/microros-board)
