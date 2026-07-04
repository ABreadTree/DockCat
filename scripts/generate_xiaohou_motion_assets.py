#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
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

    green_frames_dir = OUTPUT_DIR / "green_frames"
    extracted_sequence_dir = OUTPUT_DIR / "extracted_sequence"
    extracted_unique_dir = OUTPUT_DIR / "extracted_unique"
    for directory in [green_frames_dir, extracted_sequence_dir, extracted_unique_dir]:
        directory.mkdir(parents=True, exist_ok=True)

    green_sequence: list[Image.Image] = []
    for sequence_index, path in enumerate(ping_pong(walk_paths), start=1):
        green = green_frame(resized_frame(path, args.canvas_size))
        green_sequence.append(green)
        green.save(green_frames_dir / f"frame_{sequence_index:03d}.png", optimize=True)
        save_png(trim_green_fringe(extract_subject(green)), extracted_sequence_dir / f"frame_{sequence_index:03d}.png")

    duration_ms = max(1, int(1000 / max(1, args.fps)))
    green_sequence[0].save(
        OUTPUT_DIR / "xiaohou_walk_green.gif",
        save_all=True,
        append_images=green_sequence[1:],
        duration=duration_ms,
        loop=0,
        optimize=True,
    )

    for index, path in enumerate(walk_paths[:4], start=1):
        extracted = trim_green_fringe(extract_subject(green_frame(resized_frame(path, args.canvas_size))))
        bounds = extracted.getchannel("A").getbbox()
        coverage = subject_coverage(extracted)
        if bounds is None or coverage < 0.05:
            raise SystemExit(f"Extraction failed for {path.name}: bounds={bounds} coverage={coverage:.3f}")
        output_path = extracted_unique_dir / f"walk_{index:02d}.png"
        save_png(extracted, output_path)
        print(f"{output_path.name}: coverage={coverage:.3f}, bounds={bounds}")

    if args.install:
        install_frames(extracted_unique_dir)

    print(f"green_gif={OUTPUT_DIR / 'xiaohou_walk_green.gif'}")
    print(f"green_frames={green_frames_dir}")
    print(f"extracted_sequence={extracted_sequence_dir}")
    print(f"extracted_unique={extracted_unique_dir}")
    print("installed=true" if args.install else "installed=false")


if __name__ == "__main__":
    main()
