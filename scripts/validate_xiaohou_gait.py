#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou"


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
    weighted_x = 0
    total = 0
    for y in y_range:
        for x in x_range:
            value = alpha.getpixel((x, y))
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
    width, _ = image.size
    pixels = {
        (x, y)
        for y in range(372, 430)
        for x in range(width)
        if alpha.getpixel((x, y)) > 32
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


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Xiaohou walk frames for smooth visible gait.")
    parser.add_argument("--walk-dir", type=Path, default=DEFAULT_WALK_DIR)
    parser.add_argument("--min-frames", type=int, default=24)
    parser.add_argument("--max-front-step", type=float, default=8)
    parser.add_argument("--max-rear-step", type=float, default=8)
    parser.add_argument("--min-front-stride", type=float, default=18)
    parser.add_argument("--min-rear-stride", type=float, default=14)
    args = parser.parse_args()

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
    bboxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(bbox is None for bbox in bboxes):
        raise SystemExit("One or more walk frames are fully transparent")

    bottoms = [bbox[3] for bbox in bboxes if bbox is not None]
    right_edges = [bbox[2] for bbox in bboxes if bbox is not None]
    if max(bottoms) - min(bottoms) > 2:
        raise SystemExit(f"Foot baseline is unstable: bottoms={bottoms}")
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
