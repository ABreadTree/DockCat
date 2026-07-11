import unittest

from xiaohou_gait import (
    FRAME_COUNT,
    LIMB_ORDER,
    TOUCHDOWN_ORDER,
    body_offset_y,
    pose_for_frame,
    tail_angle_degrees,
)


class XiaohouGaitTests(unittest.TestCase):
    def test_touchdowns_are_four_separate_beats(self) -> None:
        contacts = []
        for frame in range(FRAME_COUNT):
            for limb in LIMB_ORDER:
                if pose_for_frame(frame, limb).state == "contact":
                    contacts.append((frame, limb))
        self.assertEqual(
            contacts,
            [(0, "right_rear"), (6, "right_front"), (12, "left_rear"), (18, "left_front")],
        )
        self.assertEqual(tuple(limb for _, limb in contacts), TOUCHDOWN_ORDER)

    def test_exactly_one_limb_swings_per_frame(self) -> None:
        for frame in range(FRAME_COUNT):
            swing_count = sum(not pose_for_frame(frame, limb).is_stance for limb in LIMB_ORDER)
            self.assertEqual(swing_count, 1, f"frame={frame + 1}")

    def test_stance_paws_are_grounded_and_swing_paws_move_forward(self) -> None:
        for limb in LIMB_ORDER:
            poses = [pose_for_frame(frame, limb) for frame in range(FRAME_COUNT)]
            self.assertTrue(all(pose.relative_y == 0 for pose in poses if pose.is_stance))
            swing = [pose for pose in poses if not pose.is_stance]
            self.assertTrue(any(pose.relative_y < 0 for pose in swing))
            self.assertEqual([pose.relative_x for pose in swing], sorted(pose.relative_x for pose in swing))

    def test_loop_and_secondary_motion_are_bounded(self) -> None:
        for limb in LIMB_ORDER:
            poses = [pose_for_frame(frame, limb) for frame in range(FRAME_COUNT)]
            looped = poses + [poses[0]]
            self.assertLessEqual(
                max(abs(b.relative_x - a.relative_x) for a, b in zip(looped, looped[1:])),
                8,
            )
        self.assertLessEqual(max(body_offset_y(frame) for frame in range(FRAME_COUNT)), 3)
        self.assertGreaterEqual(min(body_offset_y(frame) for frame in range(FRAME_COUNT)), 0)
        self.assertLessEqual(max(abs(tail_angle_degrees(frame)) for frame in range(FRAME_COUNT)), 2.0)


if __name__ == "__main__":
    unittest.main()
