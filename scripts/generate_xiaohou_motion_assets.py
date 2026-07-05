#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from statistics import median
from pathlib import Path

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
PACK_WALK_DIR = ROOT / "xiaohou" / "cat_pack" / "xiaohou" / "animations" / "walk"
APP_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk"
APP_XIAOHOU_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou"
OUTPUT_DIR = ROOT / "xiaohou" / "generated_sources" / "greenscreen"
KEY_COLOR = (0, 255, 0)


def ping_pong(paths: list[Path]) -> list[Path]:
    if len(paths) <= 2:
        return paths
    return paths + list(reversed(paths[1:-1]))


def resized_frame(path: Path, size: int) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    return image.resize((size, size), Image.Resampling.LANCZOS)


def green_frame(subject: Image.Image) -> Image.Image:
    frame = Image.new("RGBA", subject.size, KEY_COLOR + (255,))
    frame.alpha_composite(subject)
    return frame.convert("RGB")


def extract_subject(frame: Image.Image) -> Image.Image:
    rgba = frame.convert("RGB").convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, _ = pixels[x, y]
            green_score = g - max(r, b)
            if g > 160 and green_score > 50:
                alpha = 0 if g > 230 and green_score > 120 else max(0, min(255, int((120 - green_score) * 2.4)))
                pixels[x, y] = (r, g, b, alpha)
    return rgba


def trim_green_fringe(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                pixels[x, y] = (0, 0, 0, 0)
            elif a < 255 and g > max(r, b):
                pixels[x, y] = (r, max(r, b), b, a)
    return rgba


def subject_coverage(image: Image.Image) -> float:
    alpha = image.getchannel("A")
    opaque = ImageChops.lighter(alpha.point(lambda value: 255 if value > 8 else 0), Image.new("L", alpha.size, 0))
    return opaque.histogram()[255] / (alpha.width * alpha.height)


def subject_center_x(image: Image.Image) -> float:
    alpha = image.getchannel("A")
    pixels = alpha.load()
    weighted_x = 0
    total = 0
    for y in range(alpha.height):
        for x in range(alpha.width):
            value = pixels[x, y]
            if value > 16:
                weighted_x += x * value
                total += value
    if total == 0:
        return image.width / 2
    return weighted_x / total


def translated(image: Image.Image, dx: int, dy: int) -> Image.Image:
    output = Image.new("RGBA", image.size, (0, 0, 0, 0))
    width, height = image.size
    source_x = max(0, -dx)
    source_y = max(0, -dy)
    dest_x = max(0, dx)
    dest_y = max(0, dy)
    copy_width = min(width - source_x, width - dest_x)
    copy_height = min(height - source_y, height - dest_y)
    if copy_width <= 0 or copy_height <= 0:
        return output
    crop = image.crop((source_x, source_y, source_x + copy_width, source_y + copy_height))
    output.alpha_composite(crop, (dest_x, dest_y))
    return output


def normalize_subject_anchor(image: Image.Image, target_bottom: int, target_center_x: float) -> Image.Image:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        return image
    center_x = subject_center_x(image)
    dx = round(target_center_x - center_x)
    dy = target_bottom - bbox[3]
    dx = max(-bbox[0], min(image.width - bbox[2], dx))
    dy = max(-bbox[1], min(image.height - bbox[3], dy))
    return translated(image, dx, dy)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def install_frames(extracted_dir: Path) -> None:
    APP_XIAOHOU_WALK_DIR.mkdir(parents=True, exist_ok=True)
    for index in range(1, 5):
        name = f"walk_{index:02d}.png"
        source = extracted_dir / name
        shutil.copy2(source, PACK_WALK_DIR / name)
        shutil.copy2(source, APP_WALK_DIR / name)
        shutil.copy2(source, APP_XIAOHOU_WALK_DIR / name)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Xiaohou green-screen motion preview and extracted walk sprites.")
    parser.add_argument("--canvas-size", type=int, default=512)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()

    walk_paths = sorted(PACK_WALK_DIR.glob("walk_*.png"))
    if len(walk_paths) < 4:
        raise SystemExit(f"Expected at least 4 walk frames in {PACK_WALK_DIR}")

    extracted_subjects: list[Image.Image] = []
    for path in walk_paths[:4]:
        extracted_subjects.append(trim_green_fringe(extract_subject(green_frame(resized_frame(path, args.canvas_size)))))

    bboxes = [subject.getchannel("A").getbbox() for subject in extracted_subjects]
    if any(bbox is None for bbox in bboxes):
        raise SystemExit("Extraction failed: one or more walk frames are fully transparent")
    target_bottom = max(bbox[3] for bbox in bboxes if bbox is not None)
    target_center_x = median(subject_center_x(subject) for subject in extracted_subjects)
    normalized_subjects = [
        normalize_subject_anchor(subject, target_bottom=target_bottom, target_center_x=target_center_x)
        for subject in extracted_subjects
    ]

    green_frames_dir = OUTPUT_DIR / "green_frames"
    extracted_sequence_dir = OUTPUT_DIR / "extracted_sequence"
    extracted_unique_dir = OUTPUT_DIR / "extracted_unique"
    for directory in [green_frames_dir, extracted_sequence_dir, extracted_unique_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    green_sequence: list[Image.Image] = []
    for sequence_index, subject in enumerate(ping_pong(normalized_subjects), start=1):
        green = green_frame(subject)
        green_sequence.append(green)
        green.save(green_frames_dir / f"frame_{sequence_index:03d}.png", optimize=True)
        save_png(subject, extracted_sequence_dir / f"frame_{sequence_index:03d}.png")

    duration_ms = max(1, int(1000 / max(1, args.fps)))
    green_sequence[0].save(
        OUTPUT_DIR / "xiaohou_walk_green.gif",
        save_all=True,
        append_images=green_sequence[1:],
        duration=duration_ms,
        loop=0,
        optimize=True,
    )

    for index, extracted in enumerate(normalized_subjects, start=1):
        bounds = extracted.getchannel("A").getbbox()
        coverage = subject_coverage(extracted)
        if bounds is None or coverage < 0.05:
            raise SystemExit(f"Extraction failed for walk_{index:02d}.png: bounds={bounds} coverage={coverage:.3f}")
        output_path = extracted_unique_dir / f"walk_{index:02d}.png"
        save_png(extracted, output_path)
        print(f"{output_path.name}: coverage={coverage:.3f}, bounds={bounds}")

    if args.install:
        install_frames(extracted_unique_dir)

    print(f"green_gif={OUTPUT_DIR / 'xiaohou_walk_green.gif'}")
    print(f"green_frames={green_frames_dir}")
    print(f"extracted_sequence={extracted_sequence_dir}")
    print(f"extracted_unique={extracted_unique_dir}")
    print(f"target_bottom={target_bottom}")
    print(f"target_center_x={target_center_x:.1f}")
    print("installed=true" if args.install else "installed=false")


if __name__ == "__main__":
    main()
