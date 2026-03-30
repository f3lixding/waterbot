//! A collection of states to be used by different loops

const std = @import("std");

pub const TopLevelState = struct {
    system_state: SystemState,
    mission_state: MissionState,
};

// Subject to change
// TODO: research on system control to see what should be here
pub const SystemState = struct {
    desired_heading_deg: f32,
    current_heading_deg: f32,
    target_visible: bool,
    target_offset_x: f32,
    estop: bool,
};

pub const MissionState = enum {
    Idle,
    ManualControl,
    SearchTarget,
    ApproachTarget,
    Watering,
    Error,
};
