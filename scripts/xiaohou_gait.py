from __future__ import annotations

import math
from dataclasses import dataclass

FRAME_COUNT = 24
FPS = 24
LIMB_ORDER = ("left_front", "right_front", "left_rear", "right_rear")
TOUCHDOWN_ORDER = ("right_rear", "right_front", "left_rear", "left_front")
TOUCHDOWN_FRAMES = {
    "right_rear": 0,
    "right_front": 6,
    "left_rear": 12,
    "left_front": 18,
}


@dataclass(frozen=True)
class LimbSpec:
    stride: int
    lift: int


@dataclass(frozen=True)
class LimbPose:
    name: str
    state: str
    relative_x: int
    relative_y: int
    is_stance: bool


LIMB_SPECS = {
    "left_front": LimbSpec(stride=42, lift=14),
    "right_front": LimbSpec(stride=40, lift=13),
    "left_rear": LimbSpec(stride=46, lift=16),
    "right_rear": LimbSpec(stride=44, lift=15),
}


def pose_for_frame(frame_index: int, limb_name: str) -> LimbPose:
    if limb_name not in LIMB_SPECS:
        raise KeyError(f"Unknown limb: {limb_name}")
    frame = frame_index % FRAME_COUNT
    age = (frame - TOUCHDOWN_FRAMES[limb_name]) % FRAME_COUNT
    spec = LIMB_SPECS[limb_name]
    forward = spec.stride / 2.0
    backward = -forward
    if age < 18:
        progress = age / 18.0
        relative_x = round(forward + (backward - forward) * progress)
        state = "contact" if age == 0 else "support" if age < 13 else "push"
        return LimbPose(limb_name, state, relative_x, 0, True)
    progress = (age - 17) / 6.0
    relative_x = round(backward + (forward - backward) * progress)
    relative_y = round(-spec.lift * math.sin(math.pi * progress))
    state = "lift" if age < 20 else "swing"
    return LimbPose(limb_name, state, relative_x, relative_y, False)


def body_offset_y(frame_index: int) -> int:
    phase = 4.0 * math.pi * (frame_index % FRAME_COUNT) / FRAME_COUNT
    return round(1.5 - 1.5 * math.cos(phase))


def tail_angle_degrees(frame_index: int) -> float:
    phase = 2.0 * math.pi * (frame_index % FRAME_COUNT) / FRAME_COUNT
    return 2.0 * math.sin(phase)
