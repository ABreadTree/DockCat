import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from prepare_xiaohou_rig import COMPONENT_NAMES, prepare_rig


FRONT_PAW_COLOR = (150, 105, 65)
REAR_PAW_COLOR = (195, 135, 80)
LOWER_PAW_COLORS = {
    "front_lower": FRONT_PAW_COLOR,
    "rear_lower": REAR_PAW_COLOR,
}

SHAPES = {
    "body": ((40, 60, 730, 550), (90, 65, 45)),
    "tail": ((800, 430, 1210, 545), (105, 75, 50)),
    "front_upper": ((55, 670, 340, 820), (120, 85, 55)),
    "front_lower": ((420, 690, 690, 820), (135, 95, 60)),
    "front_paw": ((770, 710, 940, 815), FRONT_PAW_COLOR),
    "rear_upper": ((55, 930, 340, 1140), (165, 115, 70)),
    "rear_lower": ((420, 960, 710, 1140), (180, 125, 75)),
    "rear_paw": ((780, 1000, 960, 1135), REAR_PAW_COLOR),
}


def write_sheet(path: Path, shapes: dict[str, tuple[tuple[int, int, int, int], tuple[int, int, int]]]) -> None:
    sheet = Image.new("RGB", (1254, 1254), (0, 255, 0))
    draw = ImageDraw.Draw(sheet)
    for name, (box, color) in shapes.items():
        draw.rounded_rectangle(box, radius=24, fill=color)
        if name in LOWER_PAW_COLORS:
            x0, y0, x1, y1 = box
            start = x0 + round((x1 - x0) * 0.75)
            mask = Image.new("L", sheet.size)
            ImageDraw.Draw(mask).rounded_rectangle(box, radius=24, fill=255)
            sheet.paste(LOWER_PAW_COLORS[name], (start, y0), mask.crop((start, y0, x1, y1)))
    sheet.save(path)


def contains_color(image: Image.Image, color: tuple[int, int, int]) -> bool:
    pixels = image.load()
    return any(
        pixels[x, y][:3] == color and pixels[x, y][3] > 0
        for y in range(image.height)
        for x in range(image.width)
    )


class PrepareXiaohouRigTests(unittest.TestCase):
    def test_extracts_crossing_components_into_named_transparent_parts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "sheet.png"
            write_sheet(source, SHAPES)

            outputs = prepare_rig(source, root / "parts")

            self.assertEqual(tuple(outputs), COMPONENT_NAMES)
            opaque_areas = {}
            for name, path in outputs.items():
                image = Image.open(path).convert("RGBA")
                alpha = image.getchannel("A")
                self.assertIsNotNone(alpha.getbbox())
                self.assertEqual(image.getpixel((0, 0))[3], 0)
                self.assertEqual(image.getpixel((image.width // 2, image.height // 2))[:3], SHAPES[name][1])
                opaque_areas[name] = sum(alpha.histogram()[1:])

            self.assertEqual(max(opaque_areas, key=opaque_areas.get), "body")
            with Image.open(outputs["tail"]) as tail:
                self.assertGreater(tail.width / tail.height, 2.5)
            self.assertFalse(contains_color(Image.open(outputs["front_lower"]), FRONT_PAW_COLOR))
            self.assertFalse(contains_color(Image.open(outputs["rear_lower"]), REAR_PAW_COLOR))
            self.assertTrue(contains_color(Image.open(outputs["front_paw"]), FRONT_PAW_COLOR))
            self.assertTrue(contains_color(Image.open(outputs["rear_paw"]), REAR_PAW_COLOR))

    def test_rejects_sheet_without_eight_retained_components(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "seven-shapes.png"
            write_sheet(source, dict(list(SHAPES.items())[:-1]))

            with self.assertRaisesRegex(ValueError, "expected 8"):
                prepare_rig(source, root / "parts")


if __name__ == "__main__":
    unittest.main()
