import unittest
from pathlib import Path

from PIL import Image, ImageChops

from render_xiaohou_rotoscope import (
    fit_mask_to_canvas,
    reference_subject_mask,
    render_sequence,
    sample_reference_indices,
)


ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "xiaohou" / "example" / "IMG_5056.GIF"
MASTER = ROOT / "xiaohou" / "generated_sources" / "rotoscope" / "appearance_master.png"


class XiaohouRotoscopeTests(unittest.TestCase):
    def test_samples_24_unique_phases_and_keeps_cycle_endpoint(self) -> None:
        indices = sample_reference_indices(source_count=25, output_count=24)

        self.assertEqual(len(indices), 24)
        self.assertEqual(len(set(indices)), 24)
        self.assertEqual(indices[0], 0)
        self.assertEqual(indices[-1], 24)
        self.assertEqual(indices, sorted(indices))

    def test_rendered_sequence_preserves_reference_silhouettes(self) -> None:
        frames, source_indices = render_sequence(REFERENCE, MASTER, frame_count=24)

        self.assertEqual(len(frames), 24)
        self.assertEqual(len(source_indices), 24)
        self.assertTrue(all(frame.size == (256, 192) for frame in frames))
        with Image.open(REFERENCE) as reference:
            for frame, source_index in zip(frames, source_indices):
                reference.seek(source_index)
                expected = fit_mask_to_canvas(
                    reference_subject_mask(reference.convert("RGB")),
                    (256, 192),
                )
                actual = frame.getchannel("A").point(lambda value: 255 if value >= 96 else 0)
                difference = ImageChops.logical_xor(expected.convert("1"), actual.convert("1"))
                self.assertIsNone(difference.getbbox(), f"silhouette mismatch at source frame {source_index}")

    def test_rendered_sequence_has_no_green_spill_or_large_black_holes(self) -> None:
        frames, _ = render_sequence(REFERENCE, MASTER, frame_count=24)

        for index, frame in enumerate(frames, start=1):
            foreground = 0
            green_spill = 0
            near_black = 0
            for red, green, blue, alpha in frame.get_flattened_data():
                if alpha < 96:
                    continue
                foreground += 1
                green_spill += green > max(red, blue) + 18
                near_black += max(red, green, blue) < 24
            self.assertGreater(foreground, 12_000)
            self.assertLess(green_spill / foreground, 0.001, f"green spill in frame {index}")
            self.assertLess(near_black / foreground, 0.002, f"black artifact in frame {index}")


if __name__ == "__main__":
    unittest.main()
