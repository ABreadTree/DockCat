#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageEnhance

from xiaohou_gait import FRAME_COUNT as GAIT_FRAME_COUNT
from xiaohou_gait import FPS as GAIT_FPS
from xiaohou_gait import LIMB_ORDER, body_offset_y, pose_for_frame, tail_angle_degrees


ROOT = Path(__file__).resolve().parents[1]
RIG_DIR = ROOT / "xiaohou" / "generated_sources" / "realistic_rig"
RENDERED_DIR = RIG_DIR / "rendered"
PACK_WALK_DIR = ROOT / "xiaohou" / "cat_pack" / "xiaohou" / "animations" / "walk"
APP_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk"
APP_XIAOHOU_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou"
STANDARD_WALK_FRAME_NAMES = [f"walk_{index:02d}.png" for index in range(1, GAIT_FRAME_COUNT + 1)]
PART_NAMES = (
    "body",
    "tail",
    "front_upper",
    "front_lower",
    "front_paw",
    "rear_upper",
    "rear_lower",
    "rear_paw",
)
MASK_IDS = {"left_front": 1, "right_front": 2, "left_rear": 3, "right_rear": 4}
RENDER_ORDER = ("right_rear", "right_front", "left_rear", "left_front")


def solve_two_bone(
    root: tuple[float, float],
    target: tuple[float, float],
    upper_length: float,
    lower_length: float,
    bend_sign: int,
) -> tuple[float, float]:
    dx = target[0] - root[0]
    dy = target[1] - root[1]
    distance = max(0.001, math.hypot(dx, dy))
    reachable = min(
        upper_length + lower_length - 0.001,
        max(abs(upper_length - lower_length) + 0.001, distance),
    )
    unit_x = dx / distance
    unit_y = dy / distance
    along = (
        upper_length * upper_length - lower_length * lower_length + reachable * reachable
    ) / (2.0 * reachable)
    height = math.sqrt(max(0.0, upper_length * upper_length - along * along))
    middle_x = root[0] + unit_x * along
    middle_y = root[1] + unit_y * along
    return (
        middle_x - unit_y * height * bend_sign,
        middle_y + unit_x * height * bend_sign,
    )


def _brightness(asset: Image.Image, brightness: float) -> Image.Image:
    rgba = asset.convert("RGBA")
    if brightness == 1.0:
        return rgba
    alpha = rgba.getchannel("A")
    adjusted = ImageEnhance.Brightness(rgba.convert("RGB")).enhance(brightness).convert("RGBA")
    adjusted.putalpha(alpha)
    return adjusted


def _segment_layer(
    asset: Image.Image,
    start: tuple[float, float],
    end: tuple[float, float],
    brightness: float,
) -> tuple[Image.Image, tuple[int, int]]:
    distance = math.dist(start, end)
    width = max(1, round(distance) + 8)
    height = max(1, round(asset.height * width / asset.width))
    resized = _brightness(asset, brightness).resize((width, height), Image.Resampling.LANCZOS)
    angle = math.degrees(math.atan2(end[1] - start[1], end[0] - start[0]))
    rotated = resized.rotate(-angle, resample=Image.Resampling.BICUBIC, expand=True)
    midpoint = ((start[0] + end[0]) / 2.0, (start[1] + end[1]) / 2.0)
    origin = (round(midpoint[0] - rotated.width / 2), round(midpoint[1] - rotated.height / 2))
    return rotated, origin


def place_segment(
    canvas: Image.Image,
    asset: Image.Image,
    start: tuple[float, float],
    end: tuple[float, float],
    brightness: float = 1.0,
) -> tuple[Image.Image, tuple[int, int]]:
    layer, origin = _segment_layer(asset, start, end, brightness)
    canvas.alpha_composite(layer, origin)
    return layer, origin


def place_paw(
    canvas: Image.Image,
    asset: Image.Image,
    target: tuple[float, float],
    size: tuple[int, int],
    brightness: float = 1.0,
) -> tuple[Image.Image, tuple[int, int]]:
    paw = _brightness(asset, brightness).resize(size, Image.Resampling.LANCZOS)
    origin = (round(target[0] - size[0] / 2), round(target[1] - size[1] / 2))
    canvas.alpha_composite(paw, origin)
    return paw, origin


def _paint_mask(mask: Image.Image, layer: Image.Image, origin: tuple[int, int], mask_id: int) -> None:
    solid = Image.new("L", layer.size, mask_id)
    mask.paste(solid, origin, layer.getchannel("A"))


def _far_asset(asset: Image.Image, scale: float) -> Image.Image:
    height = max(1, round(asset.height * scale))
    return asset.resize((asset.width, height), Image.Resampling.LANCZOS)


def _pose_metadata(pose: object) -> dict[str, object]:
    return {
        "state": pose.state,
        "relative_x": pose.relative_x,
        "relative_y": pose.relative_y,
        "is_stance": pose.is_stance,
    }


def render_frame(
    frame_index: int,
    rig: dict,
    parts: dict[str, Image.Image],
) -> tuple[Image.Image, Image.Image, dict]:
    canvas_size = tuple(rig["canvas"])
    frame = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    mask = Image.new("L", canvas_size, 0)
    body_offset = body_offset_y(frame_index)
    tail_angle = tail_angle_degrees(frame_index)
    ground_y = rig["ground_y"]

    poses = {name: pose_for_frame(frame_index, name) for name in LIMB_ORDER}
    limb_geometry: dict[str, dict[str, object]] = {}
    for name in LIMB_ORDER:
        pose = poses[name]
        root_x, root_y = rig["roots"][name]
        root = (float(root_x), float(root_y + body_offset))
        target = (float(root_x + pose.relative_x), float(ground_y + pose.relative_y))
        family = "front" if name.endswith("front") else "rear"
        upper_length, lower_length = rig[f"{family}_lengths"]
        bend_sign = 1 if family == "front" else -1
        joint = solve_two_bone(root, target, upper_length, lower_length, bend_sign)
        limb_geometry[name] = {
            "pose": _pose_metadata(pose),
            "root": root,
            "joint": joint,
            "foot_target": target,
        }

    tail_root = (float(rig["tail"]["root"][0]), float(rig["tail"]["root"][1] + body_offset))
    tail_radians = math.radians(tail_angle)
    tail_end = (
        tail_root[0] - rig["tail"]["length"] * math.cos(tail_radians),
        tail_root[1] + rig["tail"]["length"] * math.sin(tail_radians),
    )
    place_segment(frame, parts["tail"], tail_root, tail_end)

    for name in RENDER_ORDER:
        geometry = limb_geometry[name]
        root = geometry["root"]
        joint = geometry["joint"]
        target = geometry["foot_target"]
        family = "front" if name.endswith("front") else "rear"
        is_far = name.startswith("right_")
        scale = rig["far_scale"] if is_far else 1.0
        brightness = rig["far_brightness"] if is_far else 1.0
        upper = _far_asset(parts[f"{family}_upper"], scale) if is_far else parts[f"{family}_upper"]
        lower = _far_asset(parts[f"{family}_lower"], scale) if is_far else parts[f"{family}_lower"]
        paw_asset = parts[f"{family}_paw"]
        paw_size = tuple(max(1, round(value * scale)) for value in rig["paw_sizes"][family])
        mask_id = MASK_IDS[name]

        layer, origin = place_segment(frame, upper, root, joint, brightness)
        _paint_mask(mask, layer, origin, mask_id)
        layer, origin = place_segment(frame, lower, joint, target, brightness)
        _paint_mask(mask, layer, origin, mask_id)
        layer, origin = place_paw(frame, paw_asset, target, paw_size, brightness)
        _paint_mask(mask, layer, origin, mask_id)

    body_origin = (
        rig["body"]["origin"][0],
        rig["body"]["origin"][1] + body_offset,
    )
    body = parts["body"].resize(tuple(rig["body"]["size"]), Image.Resampling.LANCZOS)
    frame.alpha_composite(body, body_origin)

    metadata = {
        "frame": frame_index + 1,
        "body_offset_y": body_offset,
        "tail_angle_degrees": tail_angle,
        "limbs": limb_geometry,
    }
    return frame, mask, metadata


def load_rig() -> tuple[dict, dict[str, Image.Image]]:
    with (RIG_DIR / "rig.json").open(encoding="utf-8") as handle:
        rig = json.load(handle)
    parts = {
        name: Image.open(RIG_DIR / "parts" / f"{name}.png").convert("RGBA")
        for name in PART_NAMES
    }
    return rig, parts


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def install_frames(frames_dir: Path) -> None:
    frame_paths = [frames_dir / name for name in STANDARD_WALK_FRAME_NAMES]
    missing = [path.name for path in frame_paths if not path.exists()]
    if missing:
        raise SystemExit(f"Cannot install walk frames, missing generated files: {missing}")
    allowed_names = set(STANDARD_WALK_FRAME_NAMES)
    for destination in [PACK_WALK_DIR, APP_WALK_DIR, APP_XIAOHOU_WALK_DIR]:
        destination.mkdir(parents=True, exist_ok=True)
        for old_frame in destination.glob("walk_*.png"):
            old_frame.unlink()
        for source in frame_paths:
            shutil.copy2(source, destination / source.name)
        for leftover in destination.glob("walk_*.png"):
            if leftover.name not in allowed_names:
                leftover.unlink()


def generate_rendered_walk() -> tuple[Path, Path, Path]:
    rig, parts = load_rig()
    frames_dir = RENDERED_DIR / "frames"
    masks_dir = RENDERED_DIR / "masks"
    metadata_path = RENDERED_DIR / "gait_metadata.json"
    metadata = {
        "frame_count": GAIT_FRAME_COUNT,
        "fps": GAIT_FPS,
        "limb_order": list(LIMB_ORDER),
        "mask_ids": MASK_IDS,
        "frames": [],
    }
    for frame_index in range(GAIT_FRAME_COUNT):
        frame, mask, frame_metadata = render_frame(frame_index, rig, parts)
        name = STANDARD_WALK_FRAME_NAMES[frame_index]
        save_png(frame, frames_dir / name)
        save_png(mask, masks_dir / name)
        metadata["frames"].append(frame_metadata)
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return frames_dir, masks_dir, metadata_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the articulated Xiaohou walk rig.")
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()

    frames_dir, masks_dir, metadata_path = generate_rendered_walk()
    if args.install:
        install_frames(frames_dir)
    print(f"frames={frames_dir}")
    print(f"masks={masks_dir}")
    print(f"metadata={metadata_path}")
    print("installed=true" if args.install else "installed=false")


if __name__ == "__main__":
    main()
