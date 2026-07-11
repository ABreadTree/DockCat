#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageOps


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REFERENCE = ROOT / "xiaohou" / "example" / "IMG_5056.GIF"
DEFAULT_MASTER = ROOT / "xiaohou" / "generated_sources" / "rotoscope" / "appearance_master.png"
DEFAULT_OUTPUT = ROOT / "xiaohou" / "generated_sources" / "rotoscope" / "rendered"
OUTPUT_SIZE = (256, 192)
INSTALL_DIRS = (
    ROOT / "xiaohou" / "cat_pack" / "xiaohou" / "animations" / "walk",
    ROOT / "DockCatApp" / "DockCat" / "Resources" / "DefaultCat" / "animations" / "walk-xiaohou",
)


def sample_reference_indices(source_count: int, output_count: int) -> list[int]:
    if source_count < output_count:
        raise ValueError("reference must contain at least as many frames as the output")
    if output_count < 2:
        raise ValueError("output must contain at least two frames")
    return [round(index * (source_count - 1) / (output_count - 1)) for index in range(output_count)]


def _reference_alpha(frame: Image.Image) -> Image.Image:
    rgb = frame.convert("RGB")
    background = rgb.getpixel((0, 0))
    red, green, blue = rgb.split()
    background_red = Image.new("L", rgb.size, background[0])
    background_green = Image.new("L", rgb.size, background[1])
    background_blue = Image.new("L", rgb.size, background[2])
    delta = ImageChops.lighter(
        ImageChops.difference(red, background_red),
        ImageChops.lighter(
            ImageChops.difference(green, background_green),
            ImageChops.difference(blue, background_blue),
        ),
    )
    return delta.point(lambda value: max(0, min(255, round((value - 8) * 255 / 45))))


def reference_subject_mask(frame: Image.Image) -> Image.Image:
    return _reference_alpha(frame).point(lambda value: 255 if value >= 96 else 0)


def _fit_to_canvas(
    image: Image.Image,
    size: tuple[int, int],
    resample: Image.Resampling,
) -> Image.Image:
    scale = min(size[0] / image.width, size[1] / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        resample,
    )
    fill = 0 if image.mode == "L" else (0, 0, 0, 0)
    canvas = Image.new(image.mode, size, fill)
    canvas.paste(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return canvas


def fit_mask_to_canvas(mask: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = _fit_to_canvas(mask.convert("L"), size, Image.Resampling.NEAREST)
    return fitted.point(lambda value: 255 if value >= 96 else 0)


def _reference_body_mask(frame: Image.Image, subject_alpha: Image.Image) -> Image.Image:
    rgb = frame.convert("RGB")
    red, green, _ = rgb.split()
    red_gate = red.point(lambda value: 255 if value >= 140 else 0)
    green_gate = green.point(lambda value: 255 if value >= 150 else 0)
    return ImageChops.darker(subject_alpha, ImageChops.darker(red_gate, green_gate))


def _key_master(master: Image.Image) -> Image.Image:
    rgba = master.convert("RGBA")
    red, green, blue, source_alpha = rgba.split()
    dominance = ImageChops.subtract(green, ImageChops.lighter(red, blue))
    keyed_alpha = dominance.point(
        lambda value: 0 if value >= 70 else (255 if value <= 18 else round((70 - value) * 255 / 52))
    )
    rgba.putalpha(ImageChops.darker(source_alpha, keyed_alpha))

    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red_value, green_value, blue_value, alpha_value = pixels[x, y]
            if alpha_value and green_value > max(red_value, blue_value):
                pixels[x, y] = (red_value, max(red_value, blue_value), blue_value, alpha_value)
    return rgba.crop(rgba.getchannel("A").getbbox())


def _coat_field(master: Image.Image, size: tuple[int, int]) -> Image.Image:
    width, height = master.size
    torso = master.crop(
        (round(width * 0.22), round(height * 0.43), round(width * 0.64), round(height * 0.72))
    ).convert("RGB")
    field = ImageOps.fit(torso, size, method=Image.Resampling.LANCZOS)
    field = ImageEnhance.Color(field).enhance(0.82)

    golden = Image.new("RGBA", size, (211, 178, 128, 0))
    golden_alpha = Image.new("L", size)
    golden_pixels = golden_alpha.load()
    for y in range(size[1]):
        normalized_y = y / max(1, size[1] - 1)
        amount = max(0.0, min(1.0, (normalized_y - 0.42) / 0.48))
        for x in range(size[0]):
            normalized_x = x / max(1, size[0] - 1)
            face_warmth = max(0.0, min(1.0, (normalized_x - 0.70) / 0.25))
            golden_pixels[x, y] = round(72 * max(amount, face_warmth * 0.65))
    golden.putalpha(golden_alpha)
    return Image.alpha_composite(field.convert("RGBA"), golden)


def _despill(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha and green > max(red, blue) + 8:
                pixels[x, y] = (red, max(red, blue) + 8, blue, alpha)
    return result


def render_frame(reference_frame: Image.Image, keyed_master: Image.Image) -> Image.Image:
    subject_alpha = _reference_alpha(reference_frame)
    subject_box = reference_subject_mask(reference_frame).getbbox()
    if subject_box is None:
        raise ValueError("reference frame has no subject")

    x0, y0, x1, y1 = subject_box
    mapped_master = keyed_master.resize((x1 - x0, y1 - y0), Image.Resampling.LANCZOS)
    mapped_layer = Image.new("RGBA", reference_frame.size, (0, 0, 0, 0))
    mapped_layer.alpha_composite(mapped_master, (x0, y0))

    field = _coat_field(keyed_master, reference_frame.size)
    canvas = Image.new("RGBA", reference_frame.size, (0, 0, 0, 0))
    canvas.paste(field, (0, 0), subject_alpha)

    body_mask = _reference_body_mask(reference_frame, subject_alpha)
    body_mask = ImageChops.darker(body_mask.filter(ImageFilter.GaussianBlur(5)), subject_alpha)
    body_alpha = ImageChops.darker(mapped_layer.getchannel("A"), body_mask)
    mapped_layer.putalpha(body_alpha)
    canvas = Image.alpha_composite(canvas, mapped_layer)

    far_limb_mask = ImageChops.subtract(subject_alpha, body_mask).filter(ImageFilter.GaussianBlur(1))
    depth = Image.new("RGBA", reference_frame.size, (67, 60, 52, 0))
    depth.putalpha(far_limb_mask.point(lambda value: round(value * 0.10)))
    canvas = Image.alpha_composite(canvas, depth)
    canvas.putalpha(subject_alpha)
    return _despill(canvas)


def render_sequence(
    reference_path: Path,
    master_path: Path,
    frame_count: int = 24,
    output_size: tuple[int, int] = OUTPUT_SIZE,
) -> tuple[list[Image.Image], list[int]]:
    keyed_master = _key_master(Image.open(master_path))
    frames: list[Image.Image] = []
    with Image.open(reference_path) as reference:
        source_indices = sample_reference_indices(reference.n_frames, frame_count)
        for source_index in source_indices:
            reference.seek(source_index)
            reference_frame = reference.convert("RGB")
            rendered = render_frame(reference_frame, keyed_master)
            fitted = _fit_to_canvas(rendered, output_size, Image.Resampling.LANCZOS)
            fitted.putalpha(fit_mask_to_canvas(reference_subject_mask(reference_frame), output_size))
            frames.append(fitted)
    return frames, source_indices


def save_frames(frames: list[Image.Image], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    for old_frame in output_dir.glob("walk_*.png"):
        old_frame.unlink()
    for index, frame in enumerate(frames, start=1):
        frame.save(output_dir / f"walk_{index:02d}.png", optimize=True)


def save_preview(frames: list[Image.Image], output_path: Path) -> None:
    paletted = []
    for frame in frames:
        converted = frame.convert("P", palette=Image.Palette.ADAPTIVE, colors=255)
        transparent = frame.getchannel("A").point(lambda value: 255 if value < 96 else 0)
        converted.paste(255, transparent)
        converted.info["transparency"] = 255
        paletted.append(converted)
    paletted[0].save(
        output_path,
        save_all=True,
        append_images=paletted[1:],
        duration=42,
        loop=0,
        disposal=2,
        transparency=255,
    )


def install_frames(output_dir: Path) -> None:
    names = [f"walk_{index:02d}.png" for index in range(1, 25)]
    for destination in INSTALL_DIRS:
        destination.mkdir(parents=True, exist_ok=True)
        for old_frame in destination.glob("walk_*.png"):
            old_frame.unlink()
        for name in names:
            shutil.copy2(output_dir / name, destination / name)


def main() -> None:
    parser = argparse.ArgumentParser(description="Render Xiaohou using the supplied reference gait")
    parser.add_argument("--reference", type=Path, default=DEFAULT_REFERENCE)
    parser.add_argument("--master", type=Path, default=DEFAULT_MASTER)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()

    frames, _ = render_sequence(args.reference, args.master)
    save_frames(frames, args.output)
    save_preview(frames, args.output / "xiaohou_walk_preview.gif")
    if args.install:
        install_frames(args.output)


if __name__ == "__main__":
    main()
