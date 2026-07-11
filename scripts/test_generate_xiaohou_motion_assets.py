import math
import unittest

from PIL import Image

from generate_xiaohou_motion_assets import MASK_IDS, render_frame, solve_two_bone


def make_synthetic_parts() -> dict[str, Image.Image]:
    sizes = {
        "body": (404, 228),
        "tail": (150, 28),
        "front_upper": (64, 28),
        "front_lower": (88, 24),
        "front_paw": (38, 20),
        "rear_upper": (82, 42),
        "rear_lower": (88, 28),
        "rear_paw": (42, 22),
    }
    return {
        name: Image.new("RGBA", size, (126, 104, 72, 255))
        for name, size in sizes.items()
    }


def synthetic_rig() -> dict:
    return {
        "canvas": [512, 512],
        "ground_y": 425,
        "body": {"origin": [56, 128], "size": [404, 228]},
        "tail": {"root": [88, 220], "length": 150},
        "roots": {
            "left_front": [365, 290],
            "right_front": [344, 294],
            "left_rear": [166, 291],
            "right_rear": [146, 295],
        },
        "front_lengths": [56, 80],
        "rear_lengths": [74, 82],
        "paw_sizes": {"front": [38, 20], "rear": [42, 22]},
        "far_scale": 0.94,
        "far_brightness": 0.86,
    }


class XiaohouRendererTests(unittest.TestCase):
    def test_two_bone_solver_preserves_lengths(self) -> None:
        root = (120.0, 180.0)
        target = (150.0, 300.0)
        joint = solve_two_bone(root, target, 60.0, 75.0, 1)
        self.assertAlmostEqual(math.dist(root, joint), 60.0, delta=0.75)
        self.assertAlmostEqual(math.dist(joint, target), 75.0, delta=0.75)

    def test_render_frame_keeps_four_named_limb_ids(self) -> None:
        parts = make_synthetic_parts()
        frame, mask, metadata = render_frame(0, synthetic_rig(), parts)
        self.assertEqual(frame.size, (512, 512))
        self.assertEqual(set(mask.get_flattened_data()) - {0}, set(MASK_IDS.values()))
        self.assertEqual(set(metadata["limbs"]), set(MASK_IDS))


if __name__ == "__main__":
    unittest.main()
