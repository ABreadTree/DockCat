#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from statistics import median
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
PACK_WALK_DIR = ROOT / "xiaohou" / "cat_pack" / "xiaohou" / "animations" / "walk"
SOURCE_WALK_DIR = ROOT / "xiaohou" / "cat_pack" / "xiaohou" / "source_walk"
APP_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk"
APP_XIAOHOU_WALK_DIR = ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou"
OUTPUT_DIR = ROOT / "xiaohou" / "generated_sources" / "greenscreen"
KEY_COLOR = (0, 255, 0)


def ping_pong(paths: list[Path]) -> list[Path]:
    if len(paths) <= 2:
        return paths
    return paths + list(reversed(paths[1:-1]))


def source_walk_paths() -> list[Path]:
    source_paths = sorted(SOURCE_WALK_DIR.glob("walk_*.png"))
    if len(source_paths) >= 4:
        return source_paths
    return sorted(PACK_WALK_DIR.glob("walk_*.png"))


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


def lower_body_mask(size: tuple[int, int], y0: int = 292, y1: int = 338) -> Image.Image:
    width, height = size
    mask = Image.new("L", size, 0)
    pixels = mask.load()
    for y in range(height):
        if y <= y0:
            value = 0
        elif y >= y1:
            value = 255
        else:
            t = (y - y0) / (y1 - y0)
            value = round(255 * t * t * (3 - 2 * t))
        for x in range(width):
            pixels[x, y] = value
    return mask


def combine_upper_body_with_moving_legs(base: Image.Image, legs: Image.Image) -> Image.Image:
    mask = lower_body_mask(base.size)
    inverse_mask = Image.eval(mask, lambda value: 255 - value)
    zero = Image.new("L", base.size, 0)

    upper = base.copy()
    upper.putalpha(Image.composite(base.getchannel("A"), zero, inverse_mask))

    lower = legs.copy()
    lower.putalpha(Image.composite(legs.getchannel("A"), zero, mask))

    upper.alpha_composite(lower)
    return upper


def rectangular_soft_mask(
    size: tuple[int, int],
    box: tuple[int, int, int, int],
    feather: int = 4,
    top_ramp: int = 0,
) -> Image.Image:
    width, height = size
    x0, y0, x1, y1 = box
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rectangle(box, fill=255)
    if feather > 0:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))

    pixels = mask.load()
    margin = feather * 2
    for y in range(height):
        for x in range(width):
            if x < x0 - margin or x > x1 + margin or y < y0 - margin or y > y1 + margin:
                pixels[x, y] = 0
            elif top_ramp > 0 and y < y0 + top_ramp:
                scale = max(0.0, min(1.0, (y - y0 + margin) / (top_ramp + margin)))
                pixels[x, y] = round(pixels[x, y] * scale)
    return mask


def clear_region(
    image: Image.Image,
    box: tuple[int, int, int, int],
    feather: int = 4,
    top_ramp: int = 0,
    strength: float = 1.0,
) -> Image.Image:
    output = image.copy()
    alpha = output.getchannel("A")
    mask = rectangular_soft_mask(image.size, box, feather=feather, top_ramp=top_ramp)
    alpha_pixels = alpha.load()
    mask_pixels = mask.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            cut = (mask_pixels[x, y] / 255.0) * strength
            if cut > 0:
                alpha_pixels[x, y] = round(alpha_pixels[x, y] * (1 - cut))
    output.putalpha(alpha)
    return output


def row_warp_crop(
    image: Image.Image,
    box: tuple[int, int, int, int],
    top_dx: int = 0,
    bottom_dx: int = 0,
    dy: int = 0,
) -> Image.Image:
    x0, y0, x1, y1 = box
    crop = image.crop(box)
    width, height = crop.size
    output = Image.new("RGBA", image.size, (0, 0, 0, 0))
    crop_pixels = crop.load()
    for y in range(height):
        t = y / (height - 1) if height > 1 else 0
        smooth = t * t * (3 - 2 * t)
        dx = round(top_dx * (1 - smooth) + bottom_dx * smooth)
        row = Image.new("RGBA", (width, 1), (0, 0, 0, 0))
        row_pixels = row.load()
        for x in range(width):
            row_pixels[x, 0] = crop_pixels[x, y]
        output.alpha_composite(row, (x0 + dx, y0 + y + dy))
    return output


def pronounced_gait_subjects(subjects: list[Image.Image]) -> list[Image.Image]:
    base = subjects[0]
    output: list[Image.Image] = []
    for index, subject in enumerate(subjects):
        legs = subject.copy()
        if index == 0:
            legs = clear_region(legs, (72, 318, 230, 430), feather=5, top_ramp=10, strength=0.35)
            legs.alpha_composite(row_warp_crop(subject, (70, 305, 235, 425), bottom_dx=-24))
            legs.alpha_composite(row_warp_crop(subject, (335, 285, 512, 430), bottom_dx=8))
        elif index == 1:
            legs = clear_region(legs, (350, 296, 512, 430), feather=5, top_ramp=26)
            legs = clear_region(legs, (392, 318, 512, 430), feather=3)
            legs.alpha_composite(row_warp_crop(subject, (330, 285, 512, 430), top_dx=-3, bottom_dx=-86))
            legs = clear_region(legs, (75, 318, 250, 430), feather=5, top_ramp=12, strength=0.40)
            legs.alpha_composite(row_warp_crop(subject, (72, 305, 250, 425), top_dx=2, bottom_dx=30))
        elif index == 2:
            legs = clear_region(legs, (320, 302, 512, 430), feather=5, top_ramp=18, strength=0.35)
            legs.alpha_composite(row_warp_crop(subject, (320, 285, 512, 430), top_dx=1, bottom_dx=18))
            legs = clear_region(legs, (75, 318, 260, 430), feather=5, top_ramp=12, strength=0.42)
            legs.alpha_composite(row_warp_crop(subject, (75, 305, 260, 425), bottom_dx=45))
        else:
            legs = clear_region(legs, (342, 296, 512, 430), feather=5, top_ramp=26)
            legs = clear_region(legs, (392, 318, 512, 430), feather=3)
            legs.alpha_composite(row_warp_crop(subject, (330, 285, 512, 430), top_dx=-5, bottom_dx=-74))
            legs = clear_region(legs, (75, 318, 250, 430), feather=5, top_ramp=12, strength=0.36)
            legs.alpha_composite(row_warp_crop(subject, (75, 305, 250, 425), bottom_dx=-32))
        output.append(combine_upper_body_with_moving_legs(base, legs))
    return output


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


def validate_gait(subjects: list[Image.Image]) -> tuple[list[float], list[float]]:
    bboxes = [subject.getchannel("A").getbbox() for subject in subjects]
    if any(bbox is None for bbox in bboxes):
        raise SystemExit("Gait validation failed: one or more frames are fully transparent")
    bottoms = [bbox[3] for bbox in bboxes if bbox is not None]
    if max(bottoms) - min(bottoms) > 2:
        raise SystemExit(f"Gait validation failed: unstable foot baseline bottoms={bottoms}")
    clipped_right = [index + 1 for index, bbox in enumerate(bboxes) if bbox is not None and bbox[2] >= subjects[index].width]
    if clipped_right:
        raise SystemExit(f"Gait validation failed: right edge clipped in frames={clipped_right}")

    rear_centers = [foot_center_x(subject, range(50, 300), range(350, 430)) for subject in subjects]
    front_centers = [foot_center_x(subject, range(300, subjects[0].width), range(350, 430)) for subject in subjects]
    rear_stride = max(rear_centers) - min(rear_centers)
    front_stride = max(front_centers) - min(front_centers)
    if rear_stride < 24 or front_stride < 34:
        raise SystemExit(
            "Gait validation failed: stride too small "
            f"rear={rear_stride:.1f} front={front_stride:.1f}"
        )
    return rear_centers, front_centers


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

    walk_paths = source_walk_paths()
    if len(walk_paths) < 4:
        raise SystemExit(f"Expected at least 4 walk frames in {SOURCE_WALK_DIR} or {PACK_WALK_DIR}")

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
    gait_subjects = pronounced_gait_subjects(normalized_subjects)
    rear_centers, front_centers = validate_gait(gait_subjects)

    green_frames_dir = OUTPUT_DIR / "green_frames"
    extracted_sequence_dir = OUTPUT_DIR / "extracted_sequence"
    extracted_unique_dir = OUTPUT_DIR / "extracted_unique"
    for directory in [green_frames_dir, extracted_sequence_dir, extracted_unique_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    green_sequence: list[Image.Image] = []
    for sequence_index, subject in enumerate(ping_pong(gait_subjects), start=1):
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

    for index, extracted in enumerate(gait_subjects, start=1):
        bounds = extracted.getchannel("A").getbbox()
        coverage = subject_coverage(extracted)
        if bounds is None or coverage < 0.05:
            raise SystemExit(f"Extraction failed for walk_{index:02d}.png: bounds={bounds} coverage={coverage:.3f}")
        output_path = extracted_unique_dir / f"walk_{index:02d}.png"
        save_png(extracted, output_path)
        print(f"{output_path.name}: coverage={coverage:.3f}, bounds={bounds}")

    if args.install:
        install_frames(extracted_unique_dir)

    print(f"source_frames={walk_paths[0].parent}")
    print(f"green_gif={OUTPUT_DIR / 'xiaohou_walk_green.gif'}")
    print(f"green_frames={green_frames_dir}")
    print(f"extracted_sequence={extracted_sequence_dir}")
    print(f"extracted_unique={extracted_unique_dir}")
    print(f"target_bottom={target_bottom}")
    print(f"target_center_x={target_center_x:.1f}")
    print(f"rear_foot_x={[round(value, 1) for value in rear_centers]}")
    print(f"front_foot_x={[round(value, 1) for value in front_centers]}")
    print("installed=true" if args.install else "installed=false")


if __name__ == "__main__":
    main()
