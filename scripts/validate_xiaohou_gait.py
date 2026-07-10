#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
from statistics import median

from PIL import Image, ImageChops

from generate_xiaohou_motion_assets import (
    GAIT_FRAME_COUNT,
    LIMB_ORDER,
    extract_subject,
    green_frame,
    limb_pose_for_frame,
    normalize_subject_anchor,
    resized_frame,
    source_walk_paths,
    subject_center_x,
    trim_green_fringe,
)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou"
MAX_UPPER_ATTACHMENT_ALPHA_LOSS = 0.03


def ping_pong_indices(count: int) -> list[int]:
    if count <= 2:
        return list(range(count))
    return list(range(count)) + list(range(count - 2, 0, -1))


def playback_indices(count: int) -> list[int]:
    if count >= 12:
        return list(range(count))
    return ping_pong_indices(count)


def foot_center_x(image: Image.Image, x_range: range, y_range: range) -> float:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    weighted_x = 0
    total = 0
    for y in y_range:
        for x in x_range:
            value = pixels[x, y]
            if value > 24:
                weighted_x += x * value
                total += value
    if total == 0:
        raise ValueError("No foot pixels found in gait metric zone")
    return weighted_x / total


def max_adjacent_delta(values: list[float], indices: list[int]) -> float:
    sequence = [values[index] for index in indices]
    looped = sequence + [sequence[0]]
    return max(abs(b - a) for a, b in zip(looped, looped[1:]))


def foot_component_count(image: Image.Image) -> int:
    alpha = image.getchannel("A")
    alpha_pixels = alpha.load()
    width, _ = image.size
    pixels = {
        (x, y)
        for y in range(372, 430)
        for x in range(width)
        if alpha_pixels[x, y] > 32
    }
    seen: set[tuple[int, int]] = set()
    count = 0
    for point in list(pixels):
        if point in seen:
            continue
        stack = [point]
        seen.add(point)
        size = 0
        while stack:
            x, y = stack.pop()
            size += 1
            for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbor in pixels and neighbor not in seen:
                    seen.add(neighbor)
                    stack.append(neighbor)
        if size >= 30:
            count += 1
    return count


def normalized_reference_subject(canvas_size: int) -> Image.Image:
    subjects = [
        trim_green_fringe(extract_subject(green_frame(resized_frame(path, canvas_size))))
        for path in source_walk_paths()[:4]
    ]
    bboxes = [subject.getchannel("A").getbbox() for subject in subjects]
    if any(bbox is None for bbox in bboxes):
        raise SystemExit("Reference subject contains a fully transparent frame")
    target_bottom = max(bbox[3] for bbox in bboxes if bbox is not None)
    target_center_x = median(subject_center_x(subject) for subject in subjects)
    return normalize_subject_anchor(subjects[0], target_bottom, target_center_x)


def upper_attachment_alpha_loss(frame: Image.Image, reference: Image.Image) -> float:
    frame_alpha = frame.getchannel("A")
    reference_alpha = reference.getchannel("A")
    frame_pixels = frame_alpha.load()
    reference_pixels = reference_alpha.load()
    retained_source_alpha = 0
    lost_alpha = 0
    for y in range(285, 315):
        for x in range(40, min(510, frame.width)):
            source_value = reference_pixels[x, y]
            if source_value <= 64:
                continue
            retained_source_alpha += source_value
            lost_alpha += max(0, source_value - frame_pixels[x, y])
    if retained_source_alpha == 0:
        raise SystemExit("Reference subject has no attachment pixels in the validation zone")
    return lost_alpha / retained_source_alpha


def validate_motion_plan() -> None:
    expected_order = ["left_front", "right_front", "left_rear", "right_rear"]
    if list(LIMB_ORDER) != expected_order:
        raise SystemExit(f"Unexpected limb order: {LIMB_ORDER}")

    frame_01 = {name: limb_pose_for_frame(0, name) for name in LIMB_ORDER}
    if frame_01["left_front"].dx <= 0:
        raise SystemExit("Frame 01 left_front should be forward")
    if frame_01["left_rear"].dx >= 0:
        raise SystemExit("Frame 01 left_rear should be back")
    if frame_01["right_front"].alpha_scale >= frame_01["left_front"].alpha_scale:
        raise SystemExit("Right/front far leg should render subtler than left/front near leg")

    for frame_index in range(GAIT_FRAME_COUNT):
        poses = [limb_pose_for_frame(frame_index, name) for name in LIMB_ORDER]
        if len({pose.name for pose in poses}) != 4:
            raise SystemExit(f"Frame {frame_index + 1:02d} does not have four named limbs")
        if max(abs(pose.dx) for pose in poses) > 36:
            raise SystemExit(f"Frame {frame_index + 1:02d} limb stride is too extreme: {poses}")
        if min(pose.lift for pose in poses) < -12:
            raise SystemExit(f"Frame {frame_index + 1:02d} limb lift is too extreme: {poses}")

    for name in LIMB_ORDER:
        poses = [limb_pose_for_frame(frame_index, name) for frame_index in range(GAIT_FRAME_COUNT)]
        lifted_indices = [index for index, pose in enumerate(poses) if pose.lift < 0]
        if not lifted_indices:
            raise SystemExit(f"{name} never leaves the ground during the walk cycle")
        for index in lifted_indices:
            next_pose = poses[(index + 1) % GAIT_FRAME_COUNT]
            if next_pose.dx < poses[index].dx - 1:
                raise SystemExit(f"{name} moves backward while lifted at frame {index + 1:02d}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Xiaohou walk frames for smooth visible gait.")
    parser.add_argument("--walk-dir", type=Path, default=DEFAULT_WALK_DIR)
    parser.add_argument("--min-frames", type=int, default=24)
    parser.add_argument("--max-front-step", type=float, default=8)
    parser.add_argument("--max-rear-step", type=float, default=8)
    parser.add_argument("--min-front-stride", type=float, default=18)
    parser.add_argument("--min-rear-stride", type=float, default=14)
    args = parser.parse_args()

    validate_motion_plan()

    expected_names = [f"walk_{index:02d}.png" for index in range(1, args.min_frames + 1)]
    expected_paths = [args.walk_dir / name for name in expected_names]
    missing_names = [path.name for path in expected_paths if not path.exists()]
    extra_names = sorted(
        path.name
        for path in args.walk_dir.glob("walk_*.png")
        if path.name not in expected_names
    )
    if missing_names or extra_names:
        raise SystemExit(
            f"Expected exactly {args.min_frames} standard walk frames in {args.walk_dir}; "
            f"missing={missing_names} extra={extra_names}"
        )
    paths = expected_paths

    frames = [Image.open(path).convert("RGBA") for path in paths]
    reference = normalized_reference_subject(frames[0].width)
    attachment_losses = [upper_attachment_alpha_loss(frame, reference) for frame in frames]
    if max(attachment_losses) > MAX_UPPER_ATTACHMENT_ALPHA_LOSS:
        raise SystemExit(
            "Upper leg attachment loses too much torso alpha: "
            f"losses={[round(value, 3) for value in attachment_losses]}"
        )
    bboxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(bbox is None for bbox in bboxes):
        raise SystemExit("One or more walk frames are fully transparent")

    bottoms = [bbox[3] for bbox in bboxes if bbox is not None]
    right_edges = [bbox[2] for bbox in bboxes if bbox is not None]
    if max(bottoms) - min(bottoms) > 4:
        raise SystemExit(f"Foot baseline is unstable: bottoms={bottoms}")
    upper_body = frames[0].crop((0, 0, frames[0].width, 285))
    moving_upper_frames = [
        index + 1
        for index, frame in enumerate(frames)
        if ImageChops.difference(upper_body, frame.crop((0, 0, frame.width, 285))).getbbox() is not None
    ]
    if moving_upper_frames:
        raise SystemExit(f"Upper body anchor moves in frames: {moving_upper_frames}")
    if max(right_edges) >= frames[0].width:
        raise SystemExit(f"Frame is clipped at the right edge: right_edges={right_edges}")

    rear_centers = [foot_center_x(frame, range(50, 300), range(350, 430)) for frame in frames]
    front_centers = [foot_center_x(frame, range(300, frame.width), range(350, 430)) for frame in frames]
    foot_counts = [foot_component_count(frame) for frame in frames]
    indices = playback_indices(len(frames))

    rear_stride = max(rear_centers) - min(rear_centers)
    front_stride = max(front_centers) - min(front_centers)
    max_rear_step = max_adjacent_delta(rear_centers, indices)
    max_front_step = max_adjacent_delta(front_centers, indices)

    print(f"frames={len(frames)}")
    print(f"bottoms={bottoms} bottom_spread={max(bottoms) - min(bottoms)}")
    print(f"right_edges={right_edges} max_right={max(right_edges)}")
    print(f"foot_components={foot_counts} max_feet={max(foot_counts)}")
    print(f"upper_attachment_alpha_loss={[round(value, 3) for value in attachment_losses]}")
    print(f"rear_foot_x={[round(value, 1) for value in rear_centers]} rear_stride={rear_stride:.1f} max_step={max_rear_step:.1f}")
    print(f"front_foot_x={[round(value, 1) for value in front_centers]} front_stride={front_stride:.1f} max_step={max_front_step:.1f}")

    if max(foot_counts) > 4:
        raise SystemExit(f"Too many visible foot components: {foot_counts}")
    if rear_stride < args.min_rear_stride:
        raise SystemExit(f"Rear leg stride too small: {rear_stride:.1f}px")
    if front_stride < args.min_front_stride:
        raise SystemExit(f"Front leg stride too small: {front_stride:.1f}px")
    if max_rear_step > args.max_rear_step:
        raise SystemExit(f"Rear leg step is too jumpy: {max_rear_step:.1f}px")
    if max_front_step > args.max_front_step:
        raise SystemExit(f"Front leg step is too jumpy: {max_front_step:.1f}px")


if __name__ == "__main__":
    main()
