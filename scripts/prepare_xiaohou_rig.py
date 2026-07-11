from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from PIL import Image


COMPONENT_NAMES = (
    "body",
    "tail",
    "front_upper",
    "front_lower",
    "front_paw",
    "rear_upper",
    "rear_lower",
    "rear_paw",
)
LOWER_SEGMENT_KEEP_RATIOS = {
    "front_lower": 0.70,
    "rear_lower": 0.70,
}
LOWER_SEGMENT_TAPER_PIXELS = 10


@dataclass(frozen=True)
class Component:
    pixels: tuple[int, ...]
    box: tuple[int, int, int, int]
    area: int


def remove_green(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, _ = pixels[x, y]
            score = green - max(red, blue)
            alpha = 0 if green > 220 and score > 100 else 255
            if 40 < score <= 100:
                alpha = round(255 * (100 - score) / 60)
            pixels[x, y] = (red, min(green, max(red, blue)), blue, alpha)
    return rgba


def find_components(image: Image.Image) -> list[Component]:
    width, height = image.size
    alpha = image.getchannel("A").tobytes()
    visited = bytearray(width * height)
    minimum_area = width * height * 0.0015
    components = []

    for start, value in enumerate(alpha):
        if value <= 32 or visited[start]:
            continue

        visited[start] = 1
        pixels = []
        stack = [start]
        left = right = start % width
        top = bottom = start // width
        while stack:
            index = stack.pop()
            pixels.append(index)
            x, y = index % width, index // width
            left = min(left, x)
            right = max(right, x)
            top = min(top, y)
            bottom = max(bottom, y)

            for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                row = neighbor_y * width
                for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = row + neighbor_x
                    if not visited[neighbor] and alpha[neighbor] > 32:
                        visited[neighbor] = 1
                        stack.append(neighbor)

        if len(pixels) >= minimum_area:
            components.append(Component(tuple(pixels), (left, top, right + 1, bottom + 1), len(pixels)))

    return components


def classify_components(components: list[Component]) -> dict[str, Component]:
    if len(components) != len(COMPONENT_NAMES):
        raise ValueError(f"expected 8 retained components, found {len(components)}")

    remaining = list(components)
    body = max(remaining, key=lambda component: component.area)
    remaining.remove(body)

    def aspect_ratio(component: Component) -> float:
        left, top, right, bottom = component.box
        return (right - left) / (bottom - top)

    tail = max(remaining, key=aspect_ratio)
    if aspect_ratio(tail) <= 2.5:
        raise ValueError(f"tail aspect ratio must exceed 2.5, found {aspect_ratio(tail):.2f}")
    remaining.remove(tail)

    def center_y(component: Component) -> float:
        return (component.box[1] + component.box[3]) / 2

    def center_x(component: Component) -> float:
        return (component.box[0] + component.box[2]) / 2

    remaining.sort(key=center_y)
    upper = sorted(remaining[:3], key=center_x)
    lower = sorted(remaining[3:], key=center_x)
    return dict(zip(COMPONENT_NAMES, [body, tail, *upper, *lower], strict=True))


def extract_component(sheet: Image.Image, component: Component, name: str) -> Image.Image:
    left, top, right, bottom = component.box
    padding = 8
    component_width = right - left
    keep_width = round(component_width * LOWER_SEGMENT_KEEP_RATIOS.get(name, 1.0))
    output = Image.new("RGBA", (keep_width + padding * 2, bottom - top + padding * 2))
    source_pixels = sheet.load()
    output_pixels = output.load()
    for index in component.pixels:
        x, y = index % sheet.width, index // sheet.width
        component_x = x - left
        if component_x >= keep_width:
            continue
        red, green, blue, alpha = source_pixels[x, y]
        if name in LOWER_SEGMENT_KEEP_RATIOS:
            taper = min(1.0, (keep_width - component_x) / LOWER_SEGMENT_TAPER_PIXELS)
            alpha = round(alpha * taper)
        output_pixels[component_x + padding, y - top + padding] = (red, green, blue, alpha)
    return output


def prepare_rig(sheet_path: Path, output_dir: Path) -> dict[str, Path]:
    sheet = remove_green(Image.open(sheet_path))
    components = classify_components(find_components(sheet))
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {}
    for name in COMPONENT_NAMES:
        output = output_dir / f"{name}.png"
        extract_component(sheet, components[name], name).save(output, optimize=True)
        outputs[name] = output
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sheet", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare_rig(args.sheet, args.output)


if __name__ == "__main__":
    main()
