# Xiaohou Realistic Walk Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Xiaohou's distorted walk frames with a realistic, anatomically coherent, four-beat 24-frame loop and ship the validated low-resource animation in the macOS app and Xiaohou resource pack.

**Architecture:** A pure Python gait module owns the four-limb timing and foot trajectories. A Pillow-based offline renderer loads a photo-constrained realistic rig sheet, extracts named body/limb parts, solves two-bone limb joints, and writes transparent frames plus diagnostic masks and previews. The existing DockCat runtime remains unchanged and continues loading 24 optimized 512 x 512 PNG files at 24 fps.

**Tech Stack:** Python 3 standard library, Pillow, `unittest`, Codex image generation for the offline rig sheet, Swift/Xcode macOS build, existing `PackUp.command` packaging.

## Global Constraints

- Output exactly 24 transparent 512 x 512 PNG files named `walk_01.png` through `walk_24.png`.
- Play at exactly 24 fps through the existing DockCat manifest and `SpriteAnimator`.
- Use a four-beat touchdown order: `right_rear`, `right_front`, `left_rear`, `left_front`, spaced six frames apart.
- Render exactly four named limbs: `left_front`, `right_front`, `left_rear`, `right_rear`.
- Keep the shared ground baseline spread at or below 3 px and torso vertical travel at or below 3 px.
- Preserve Xiaohou's round face, compact ears, short muzzle, blue-golden shaded short fur, and realistic proportions from `xiaohou/photo`.
- Use `xiaohou/example/IMG_5056.GIF` for motion timing and silhouette readability only, never for appearance.
- Add no runtime video, model inference, third-party animation framework, background worker, or polling behavior.
- Install byte-identical output frames in all three shipping animation directories.
- Do not package source photos, rig sheets, green-screen frames, masks, or diagnostic previews inside `DockCat.app`.
- Preserve unrelated untracked ZIP files, `scripts/__pycache__`, and `xiaohou/example` worktree contents.

## File Map

- Create `scripts/xiaohou_gait.py`: pure four-beat gait timing and body/tail secondary-motion values.
- Create `scripts/test_xiaohou_gait.py`: deterministic gait unit tests.
- Create `scripts/prepare_xiaohou_rig.py`: chroma extraction and fixed-layout rig component preparation.
- Create `scripts/test_prepare_xiaohou_rig.py`: synthetic rig-sheet extraction tests.
- Modify `scripts/generate_xiaohou_motion_assets.py`: replace flattened-frame row warping with articulated named-part rendering, frame masks, metadata, contact sheet, and GIF previews.
- Create `scripts/test_generate_xiaohou_motion_assets.py`: inverse-kinematics and four-layer rendering tests.
- Modify `scripts/validate_xiaohou_gait.py`: validate four-beat metadata, named masks, continuity, canvas, alpha, baseline, torso motion, and install parity.
- Create `scripts/test_validate_xiaohou_gait.py`: validator regression tests using temporary synthetic frames and masks.
- Modify `CustomizationGuide/图片生成提示词.md`: replace the inaccurate paired-leg frame instructions with the approved realistic four-beat prompt.
- Create `xiaohou/generated_sources/realistic_rig/source/xiaohou_rig_sheet.png`: photo-constrained offline source sheet.
- Create `xiaohou/generated_sources/realistic_rig/rig.json`: fixed render anchors, lengths, depth, and source-cell layout.
- Create `xiaohou/generated_sources/realistic_rig/parts/*.png`: extracted body, tail, front-leg, rear-leg, and paw layers.
- Create `xiaohou/generated_sources/realistic_rig/previews/xiaohou_walk_contact_sheet.png`: 6 x 4 full-cycle review sheet.
- Create `xiaohou/generated_sources/realistic_rig/previews/xiaohou_walk_24fps.gif`: normal-speed loop.
- Create `xiaohou/generated_sources/realistic_rig/previews/xiaohou_walk_diagnostic_8fps.gif`: slow continuity review.
- Replace the 24 PNG files in `DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou`.
- Replace the 24 PNG files in `DockCatApp/DockCat/Resources/DefaultCat/animations/walk`.
- Replace the 24 PNG files in `xiaohou/cat_pack/xiaohou/animations/walk`.

---

### Task 1: Four-Beat Gait Model

**Files:**
- Create: `scripts/xiaohou_gait.py`
- Create: `scripts/test_xiaohou_gait.py`
- Modify: `scripts/generate_xiaohou_motion_assets.py:21-109`
- Modify: `scripts/validate_xiaohou_gait.py:10-155`

**Interfaces:**
- Produces: `FRAME_COUNT`, `FPS`, `LIMB_ORDER`, `TOUCHDOWN_ORDER`, `TOUCHDOWN_FRAMES`, `LimbPose`, `pose_for_frame(frame_index, limb_name)`, `body_offset_y(frame_index)`, and `tail_angle_degrees(frame_index)`.
- Consumed by: the renderer and validator in Tasks 3 and 4.

- [ ] **Step 1: Write the failing gait tests**

Create `scripts/test_xiaohou_gait.py` with these assertions:

```python
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
```

- [ ] **Step 2: Run the test and verify the missing module failure**

Run:

```bash
python3 scripts/test_xiaohou_gait.py -v
```

Expected: FAIL with `ModuleNotFoundError: No module named 'xiaohou_gait'`.

- [ ] **Step 3: Implement the pure gait module**

Create `scripts/xiaohou_gait.py` with this public model:

```python
from __future__ import annotations

import math
from dataclasses import dataclass

FRAME_COUNT = 24
FPS = 24
LIMB_ORDER = ("left_front", "right_front", "left_rear", "right_rear")
TOUCHDOWN_ORDER = ("right_rear", "right_front", "left_rear", "left_front")
TOUCHDOWN_FRAMES = {
    "right_rear": 0,
    "right_front": 6,
    "left_rear": 12,
    "left_front": 18,
}


@dataclass(frozen=True)
class LimbSpec:
    stride: int
    lift: int


@dataclass(frozen=True)
class LimbPose:
    name: str
    state: str
    relative_x: int
    relative_y: int
    is_stance: bool


LIMB_SPECS = {
    "left_front": LimbSpec(stride=42, lift=14),
    "right_front": LimbSpec(stride=40, lift=13),
    "left_rear": LimbSpec(stride=46, lift=16),
    "right_rear": LimbSpec(stride=44, lift=15),
}


def _smoothstep(value: float) -> float:
    return value * value * (3.0 - 2.0 * value)


def pose_for_frame(frame_index: int, limb_name: str) -> LimbPose:
    if limb_name not in LIMB_SPECS:
        raise KeyError(f"Unknown limb: {limb_name}")
    frame = frame_index % FRAME_COUNT
    age = (frame - TOUCHDOWN_FRAMES[limb_name]) % FRAME_COUNT
    spec = LIMB_SPECS[limb_name]
    forward = spec.stride / 2.0
    backward = -forward
    if age < 18:
        progress = age / 18.0
        relative_x = round(forward + (backward - forward) * progress)
        state = "contact" if age == 0 else "support" if age < 13 else "push"
        return LimbPose(limb_name, state, relative_x, 0, True)
    progress = (age - 17) / 6.0
    eased = _smoothstep(progress)
    relative_x = round(backward + (forward - backward) * eased)
    relative_y = round(-spec.lift * math.sin(math.pi * progress))
    state = "lift" if age < 20 else "swing"
    return LimbPose(limb_name, state, relative_x, relative_y, False)


def body_offset_y(frame_index: int) -> int:
    phase = 4.0 * math.pi * (frame_index % FRAME_COUNT) / FRAME_COUNT
    return round(1.5 - 1.5 * math.cos(phase))


def tail_angle_degrees(frame_index: int) -> float:
    phase = 2.0 * math.pi * (frame_index % FRAME_COUNT) / FRAME_COUNT
    return 2.0 * math.sin(phase)
```

- [ ] **Step 4: Replace old sinusoidal pose imports and run tests**

Remove the old `LimbSpec`, `LimbPose`, `LIMB_SPECS`, and `limb_pose_for_frame` definitions from the generator. Import the Task 1 interfaces instead. Update the validator to call `pose_for_frame`.

Run:

```bash
python3 scripts/test_xiaohou_gait.py -v
python3 -m py_compile scripts/xiaohou_gait.py scripts/generate_xiaohou_motion_assets.py scripts/validate_xiaohou_gait.py
```

Expected: four unit tests pass and compilation exits with code 0.

- [ ] **Step 5: Commit the gait model**

```bash
git add scripts/xiaohou_gait.py scripts/test_xiaohou_gait.py scripts/generate_xiaohou_motion_assets.py scripts/validate_xiaohou_gait.py
git commit -m "Model Xiaohou four-beat walk gait"
```

### Task 2: Realistic Rig Sheet And Named Parts

**Files:**
- Create: `scripts/prepare_xiaohou_rig.py`
- Create: `scripts/test_prepare_xiaohou_rig.py`
- Create: `xiaohou/generated_sources/realistic_rig/source/xiaohou_rig_sheet.png`
- Create: `xiaohou/generated_sources/realistic_rig/rig.json`
- Create: `xiaohou/generated_sources/realistic_rig/parts/body.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/tail.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/front_upper.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/front_lower.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/front_paw.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/rear_upper.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/rear_lower.png`
- Create: `xiaohou/generated_sources/realistic_rig/parts/rear_paw.png`

**Interfaces:**
- Consumes: the five photos in `xiaohou/photo`.
- Produces: `extract_component(sheet, box) -> Image.Image`, `prepare_rig(sheet_path, output_dir) -> dict[str, Path]`, eight transparent named PNG parts, and `rig.json` consumed by Task 3.

- [ ] **Step 1: Write the failing synthetic extraction test**

Create `scripts/test_prepare_xiaohou_rig.py`:

```python
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from prepare_xiaohou_rig import RIG_CELLS, prepare_rig


class PrepareXiaohouRigTests(unittest.TestCase):
    def test_extracts_all_named_cells_and_removes_green(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sheet = Image.new("RGB", (1536, 1536), (0, 255, 0))
            draw = ImageDraw.Draw(sheet)
            for index, box in enumerate(RIG_CELLS.values(), start=1):
                x0, y0, x1, y1 = box
                draw.rounded_rectangle((x0 + 40, y0 + 40, x1 - 40, y1 - 40), 20, fill=(80 + index, 70, 60))
            source = root / "sheet.png"
            sheet.save(source)
            outputs = prepare_rig(source, root / "parts")
            self.assertEqual(set(outputs), set(RIG_CELLS))
            for path in outputs.values():
                image = Image.open(path).convert("RGBA")
                self.assertIsNotNone(image.getchannel("A").getbbox())
                self.assertEqual(image.getpixel((0, 0))[3], 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify the missing module failure**

Run `python3 scripts/test_prepare_xiaohou_rig.py -v`.

Expected: FAIL with `ModuleNotFoundError: No module named 'prepare_xiaohou_rig'`.

- [ ] **Step 3: Implement fixed-cell extraction**

Create `scripts/prepare_xiaohou_rig.py` with these exact cells and entry points:

```python
from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

RIG_CELLS = {
    "body": (0, 0, 1152, 512),
    "tail": (1152, 0, 1536, 512),
    "front_upper": (0, 512, 384, 1024),
    "front_lower": (384, 512, 768, 1024),
    "front_paw": (768, 512, 1152, 1024),
    "rear_upper": (0, 1024, 384, 1536),
    "rear_lower": (384, 1024, 768, 1536),
    "rear_paw": (768, 1024, 1152, 1536),
}


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


def extract_component(sheet: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    component = remove_green(sheet.crop(box))
    bounds = component.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"Rig cell is empty: {box}")
    left = max(0, bounds[0] - 8)
    top = max(0, bounds[1] - 8)
    right = min(component.width, bounds[2] + 8)
    bottom = min(component.height, bounds[3] + 8)
    return component.crop((left, top, right, bottom))


def prepare_rig(sheet_path: Path, output_dir: Path) -> dict[str, Path]:
    sheet = Image.open(sheet_path).convert("RGB").resize((1536, 1536), Image.Resampling.LANCZOS)
    output_dir.mkdir(parents=True, exist_ok=True)
    outputs = {}
    for name, box in RIG_CELLS.items():
        output = output_dir / f"{name}.png"
        extract_component(sheet, box).save(output, optimize=True)
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
```

- [ ] **Step 4: Generate the source rig sheet using Xiaohou's photos**

Invoke the `imagegen` skill and provide all five files under `xiaohou/photo` as references. Save the selected output as `xiaohou/generated_sources/realistic_rig/source/xiaohou_rig_sheet.png`. Use this prompt verbatim:

```text
Create a production-ready photorealistic 2D game-sprite rig sheet for the exact same cat shown in all reference photos: Xiaohou, a compact round-faced short-haired blue-golden shaded cat with green eyes, small upright ears, a short muzzle, dense plush fur, warm golden cheeks and chest, and cool gray shading along the crown and back.

Solid pure chroma green RGB 0,255,0 background. Square 1536 x 1536 image. No shadows, labels, grid lines, text, props, scenery, or duplicate pieces. Soft even studio lighting. Crisp realistic fur edges. Every component fully visible and separated from every other component.

Fixed layout:
- Top-left three quarters of the first row: one coherent right-facing side-view head and torso plate, realistic feline proportions, from rump through round face, belly ending cleanly, with no visible legs and no tail.
- Top-right quarter: one isolated tail, horizontal, root at left and tip at right.
- Second row, first three equal cells: isolated front upper leg, isolated front lower leg, isolated front paw. Each points horizontally from attachment at left to distal end at right. Fourth cell empty green.
- Third row, first three equal cells: isolated rear upper leg, isolated rear lower leg, isolated rear paw. Each points horizontally from attachment at left to distal end at right. Fourth cell empty green.

The isolated parts must match the torso's fur color, lighting, scale, and photographic texture. Anatomically realistic cat limbs, rounded natural joints, no human anatomy, no extra paws, no fused pieces, no motion blur, no illustration, no cartoon styling.
```

Reject a candidate when the body is not right-facing, the face does not resemble Xiaohou, any cell contains multiple pieces, any required piece crosses a cell boundary, or green is visible inside fur. Generate at most three candidates and select the first one meeting all conditions.

- [ ] **Step 5: Add the fixed rig manifest and extract parts**

Create `xiaohou/generated_sources/realistic_rig/rig.json`:

```json
{
  "canvas": [512, 512],
  "ground_y": 425,
  "body": {"origin": [56, 128], "size": [404, 228]},
  "tail": {"root": [88, 220], "length": 150},
  "roots": {
    "left_front": [365, 290],
    "right_front": [344, 294],
    "left_rear": [166, 291],
    "right_rear": [146, 295]
  },
  "front_lengths": [56, 80],
  "rear_lengths": [74, 82],
  "paw_sizes": {"front": [38, 20], "rear": [42, 22]},
  "far_scale": 0.94,
  "far_brightness": 0.86
}
```

Run:

```bash
python3 scripts/prepare_xiaohou_rig.py xiaohou/generated_sources/realistic_rig/source/xiaohou_rig_sheet.png xiaohou/generated_sources/realistic_rig/parts
python3 scripts/test_prepare_xiaohou_rig.py -v
```

Expected: eight non-empty transparent parts are written and the test passes.

- [ ] **Step 6: Visually inspect the source and parts, then commit**

Use `view_image` on the rig sheet, `body.png`, `front_upper.png`, and `rear_upper.png`. Reject and regenerate the source when there is a cartoon outline, texture mismatch, extra anatomy, missing fur, or component overlap.

```bash
git add scripts/prepare_xiaohou_rig.py scripts/test_prepare_xiaohou_rig.py xiaohou/generated_sources/realistic_rig
git commit -m "Add realistic Xiaohou rig source"
```

### Task 3: Articulated Four-Limb Renderer

**Files:**
- Modify: `scripts/generate_xiaohou_motion_assets.py`
- Create: `scripts/test_generate_xiaohou_motion_assets.py`

**Interfaces:**
- Consumes: `pose_for_frame`, `body_offset_y`, `tail_angle_degrees`, `rig.json`, and named rig parts.
- Produces: `solve_two_bone(root, target, upper_length, lower_length, bend_sign)`, `render_frame(frame_index, rig, parts) -> tuple[Image.Image, Image.Image, dict]`, and the 24-frame render output.

- [ ] **Step 1: Write failing IK and limb-mask tests**

Create tests that assert a solved joint stays within 0.75 px of both requested bone lengths, a synthetic frame contains mask IDs `{1, 2, 3, 4}`, and the four IDs map to `LIMB_ORDER` without duplicates:

```python
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
        self.assertEqual(set(mask.getdata()) - {0}, set(MASK_IDS.values()))
        self.assertEqual(set(metadata["limbs"]), set(MASK_IDS))
```

The test has no dependency on generated binary assets.

- [ ] **Step 2: Run tests and verify missing renderer interfaces**

Run `python3 scripts/test_generate_xiaohou_motion_assets.py -v`.

Expected: FAIL because `MASK_IDS`, `render_frame`, and `solve_two_bone` do not exist.

- [ ] **Step 3: Implement clamped two-bone inverse kinematics**

Add this solver to the generator:

```python
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
    reachable = min(upper_length + lower_length - 0.001, max(abs(upper_length - lower_length) + 0.001, distance))
    unit_x = dx / distance
    unit_y = dy / distance
    along = (upper_length * upper_length - lower_length * lower_length + reachable * reachable) / (2.0 * reachable)
    height = math.sqrt(max(0.0, upper_length * upper_length - along * along))
    middle_x = root[0] + unit_x * along
    middle_y = root[1] + unit_y * along
    return (
        middle_x - unit_y * height * bend_sign,
        middle_y + unit_x * height * bend_sign,
    )
```

Use bend sign `+1` for front elbows so they flex rearward and `-1` for rear joints so they flex forward.

- [ ] **Step 4: Implement segment placement and depth order**

Implement `place_segment(canvas, asset, start, end, brightness=1.0)` by resizing the horizontal source asset to `round(math.dist(start, end)) + 8` pixels long, rotating it to `atan2(dy, dx)`, and alpha-compositing with an 8 px joint overlap. Implement `place_paw` as a separately resized, unrotated part centered on each foot target.

Render in this exact order:

```python
MASK_IDS = {"left_front": 1, "right_front": 2, "left_rear": 3, "right_rear": 4}
RENDER_ORDER = ("right_rear", "right_front", "left_rear", "left_front")
```

For each frame:

1. Compute the four `LimbPose` values.
2. Shift all four roots down by `body_offset_y(frame_index)`.
3. Set each target to `(root_x + pose.relative_x, ground_y + pose.relative_y)`.
4. Render far limbs at `far_scale` and `far_brightness`.
5. Render tail behind the torso with `tail_angle_degrees(frame_index)`.
6. Render all four upper/lower/paw layers and write the corresponding mask ID.
7. Composite the body plate last so its belly hides the joint overlaps.
8. Return metadata containing frame number, body offset, tail angle, and all four named poses and foot targets.

- [ ] **Step 5: Replace the old flattened-frame pipeline**

Remove `source_walk_paths`, `smooth_gait_subjects`, `row_warp_layer`, rectangular limb crops, and the old four-source-frame normalization path. Load the rig parts and JSON from `xiaohou/generated_sources/realistic_rig`, call `render_frame` for frame indices 0 through 23, and keep the existing `--install` behavior.

Write `walk_01.png` through `walk_24.png` under both `xiaohou/generated_sources/realistic_rig/rendered/frames` and `xiaohou/generated_sources/realistic_rig/rendered/masks`, plus `xiaohou/generated_sources/realistic_rig/rendered/gait_metadata.json`.

- [ ] **Step 6: Run renderer tests and commit**

```bash
python3 scripts/test_xiaohou_gait.py -v
python3 scripts/test_prepare_xiaohou_rig.py -v
python3 scripts/test_generate_xiaohou_motion_assets.py -v
python3 -m py_compile scripts/xiaohou_gait.py scripts/prepare_xiaohou_rig.py scripts/generate_xiaohou_motion_assets.py
git add scripts/generate_xiaohou_motion_assets.py scripts/test_generate_xiaohou_motion_assets.py
git commit -m "Render articulated Xiaohou walk frames"
```

Expected: all tests pass and compilation exits with code 0.

### Task 4: Gait Validation And Visual Diagnostics

**Files:**
- Modify: `scripts/validate_xiaohou_gait.py`
- Create: `scripts/test_validate_xiaohou_gait.py`
- Modify: `scripts/generate_xiaohou_motion_assets.py`

**Interfaces:**
- Consumes: rendered frames, masks, `gait_metadata.json`, and the gait model.
- Produces: `validate_frame_set(walk_dir, mask_dir, metadata_path) -> ValidationReport`, contact sheet, 24 fps GIF, and 8 fps diagnostic GIF.

- [ ] **Step 1: Write validator regression tests**

Use this temporary 24-frame fixture and test cases:

```python
import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from generate_xiaohou_motion_assets import MASK_IDS
from validate_xiaohou_gait import validate_frame_set
from xiaohou_gait import LIMB_ORDER, body_offset_y, pose_for_frame


class XiaohouValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.walk_dir = self.root / "frames"
        self.mask_dir = self.root / "masks"
        self.walk_dir.mkdir()
        self.mask_dir.mkdir()
        metadata_frames = []
        for frame_index in range(24):
            frame_name = f"walk_{frame_index + 1:02d}.png"
            frame = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
            ImageDraw.Draw(frame).rounded_rectangle((70, 120, 450, 425), 24, fill=(120, 96, 68, 255))
            frame.save(self.walk_dir / frame_name)

            mask = Image.new("L", (512, 512), 0)
            mask_draw = ImageDraw.Draw(mask)
            for limb_index, limb_name in enumerate(LIMB_ORDER):
                x0 = 90 + limb_index * 90
                mask_draw.rectangle((x0, 340, x0 + 24, 424), fill=MASK_IDS[limb_name])
            mask.save(self.mask_dir / frame_name)

            limb_metadata = {}
            for limb_name in LIMB_ORDER:
                pose = pose_for_frame(frame_index, limb_name)
                limb_metadata[limb_name] = {
                    "state": pose.state,
                    "is_stance": pose.is_stance,
                    "foot_target": [200 + pose.relative_x, 425 + pose.relative_y],
                }
            metadata_frames.append(
                {
                    "frame": frame_index + 1,
                    "body_offset_y": body_offset_y(frame_index),
                    "limbs": limb_metadata,
                }
            )
        self.metadata_path = self.root / "gait_metadata.json"
        self.metadata_path.write_text(
            json.dumps({"ground_y": 425, "frames": metadata_frames}),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_valid_four_beat_fixture_passes(self) -> None:
        report = validate_frame_set(self.walk_dir, self.mask_dir, self.metadata_path)
        self.assertEqual(report.frame_count, 24)
        self.assertLessEqual(report.baseline_spread, 3)

    def test_missing_named_limb_mask_fails(self) -> None:
        mask_path = self.mask_dir / "walk_08.png"
        mask = Image.open(mask_path).convert("L")
        mask.putdata([0 if value == MASK_IDS["left_rear"] else value for value in mask.getdata()])
        mask.save(mask_path)
        with self.assertRaisesRegex(ValueError, "left_rear"):
            validate_frame_set(self.walk_dir, self.mask_dir, self.metadata_path)

    def test_wrong_canvas_fails(self) -> None:
        Image.new("RGBA", (256, 256)).save(self.walk_dir / "walk_03.png")
        with self.assertRaisesRegex(ValueError, "512 x 512"):
            validate_frame_set(self.walk_dir, self.mask_dir, self.metadata_path)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests and verify the missing validation interface**

Run `python3 scripts/test_validate_xiaohou_gait.py -v`.

Expected: FAIL because `ValidationReport` and `validate_frame_set` do not exist.

- [ ] **Step 3: Refactor validator around a report**

Add:

```python
@dataclass(frozen=True)
class ValidationReport:
    frame_count: int
    baseline_spread: int
    torso_spread: int
    max_landmark_step: float
    named_limb_areas: dict[str, list[int]]
```

`validate_frame_set` must enforce:

- Exactly 24 expected filenames and no extras.
- Every image is RGBA-capable and 512 x 512.
- Every mask contains each ID in `MASK_IDS` with at least 80 visible pixels.
- Metadata contains each named limb once per frame.
- Contact frames are exactly 1, 7, 13, and 19 in `right_rear`, `right_front`, `left_rear`, `left_front` order.
- Supporting paw target Y equals `ground_y`; only one limb is in swing per frame.
- Bounding-box bottom spread is at most 3 px.
- Metadata body-offset spread is at most 3 px.
- Maximum adjacent foot-target movement, including frame 24 to frame 1, is at most 8 px per axis.
- No subject alpha touches the left, top, or right canvas edge.

The CLI prints the report fields and exits nonzero with the first precise failure.

- [ ] **Step 4: Generate contact sheet and two GIF speeds**

Add `save_previews(frames, preview_dir)` to the generator. The contact sheet uses a 6-column by 4-row grid with each frame scaled to 256 x 256 and a small `01` through `24` label outside the subject bounds. Write GIFs with frame durations of 42 ms for 24 fps and 125 ms for 8 fps. Both loop forever and use the same frame order without ping-pong playback.

- [ ] **Step 5: Run the full Python verification and commit**

```bash
python3 scripts/test_xiaohou_gait.py -v
python3 scripts/test_prepare_xiaohou_rig.py -v
python3 scripts/test_generate_xiaohou_motion_assets.py -v
python3 scripts/test_validate_xiaohou_gait.py -v
python3 -m py_compile scripts/xiaohou_gait.py scripts/prepare_xiaohou_rig.py scripts/generate_xiaohou_motion_assets.py scripts/validate_xiaohou_gait.py
git add scripts/generate_xiaohou_motion_assets.py scripts/validate_xiaohou_gait.py scripts/test_validate_xiaohou_gait.py
git commit -m "Validate Xiaohou walk continuity"
```

Expected: all Python tests pass.

### Task 5: Prompt Correction, Final Generation, And Installation

**Files:**
- Modify: `CustomizationGuide/图片生成提示词.md:148-342`
- Replace: `DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou/walk_01.png` through `walk_24.png`
- Replace: `DockCatApp/DockCat/Resources/DefaultCat/animations/walk/walk_01.png` through `walk_24.png`
- Replace: `xiaohou/cat_pack/xiaohou/animations/walk/walk_01.png` through `walk_24.png`
- Create: generated frames, masks, metadata, and previews under `xiaohou/generated_sources/realistic_rig`

**Interfaces:**
- Consumes: the completed rig, renderer, and validator.
- Produces: reviewed app-ready PNGs and corrected user-facing generation instructions.

- [ ] **Step 1: Record the existing resource footprint**

Run:

```bash
du -sk DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou
```

Record the KiB value in the task notes. The replacement directory must remain within 125 percent of this value.

- [ ] **Step 2: Replace the inaccurate prompt section**

Keep the approved visual identity and strict four-limb prohibitions, but replace the old simultaneous paired-leg frame descriptions with the exact four-beat schedule:

- Frame 01 `right_rear` contact; frames 01-06 `right_front` lift/swing.
- Frame 07 `right_front` contact; frames 07-12 `left_rear` lift/swing.
- Frame 13 `left_rear` contact; frames 13-18 `left_front` lift/swing.
- Frame 19 `left_front` contact; frames 19-24 `right_rear` lift/swing and return to frame 01.

For every frame, list all four named limbs. The one swing limb progresses from lift to forward swing; the three stance limbs remain planted and move from forward contact through support to rear push. State explicitly that diagonal simultaneous touchdown is forbidden because it changes the motion into a trot.

- [ ] **Step 3: Generate without installing and validate**

```bash
python3 scripts/generate_xiaohou_motion_assets.py
python3 scripts/validate_xiaohou_gait.py \
  --walk-dir xiaohou/generated_sources/realistic_rig/rendered/frames \
  --mask-dir xiaohou/generated_sources/realistic_rig/rendered/masks \
  --metadata xiaohou/generated_sources/realistic_rig/rendered/gait_metadata.json
```

Expected: 24 frames, 24 masks, four named limbs in every frame, four separate touchdown events, baseline spread no more than 3 px, torso spread no more than 3 px, and no adjacent landmark jump above 8 px.

- [ ] **Step 4: Perform visual rejection review**

Use `view_image` on the contact sheet and the key frames 01, 04, 07, 10, 13, 16, 19, and 22. View both GIF loops. Reject the render if any of these is visible:

- More or fewer than four legs or paws.
- A front leg attached to the hip or a rear leg attached to the shoulder.
- Reversed elbows, knees, or hocks.
- Pasted rectangular texture, hard seams, green fringe, or mismatched lighting.
- Sliding stance paws, body pumping, head jitter, tail flicker, or frame-24 reset.
- Cartoon proportions or loss of Xiaohou's round face and blue-golden shaded fur.

When rejection is caused by geometry, adjust only `rig.json` roots, lengths, and sizes, regenerate, and rerun validation. When rejection is caused by appearance, regenerate the rig sheet, re-extract, regenerate, and rerun validation. Do not install a rejected result.

- [ ] **Step 5: Install and verify directory parity**

```bash
python3 scripts/generate_xiaohou_motion_assets.py --install
python3 scripts/validate_xiaohou_gait.py
diff -qr DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou DockCatApp/DockCat/Resources/DefaultCat/animations/walk
diff -qr DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou xiaohou/cat_pack/xiaohou/animations/walk
du -sk DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou
```

Expected: validator passes, both `diff` commands produce no output, and the new KiB value is no more than 125 percent of the Step 1 value.

- [ ] **Step 6: Commit the reviewed asset set**

```bash
git add 'CustomizationGuide/图片生成提示词.md' \
  DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou \
  DockCatApp/DockCat/Resources/DefaultCat/animations/walk \
  xiaohou/cat_pack/xiaohou/animations/walk \
  xiaohou/generated_sources/realistic_rig
git commit -m "Replace Xiaohou walk with realistic four-beat motion"
```

### Task 6: macOS Verification, Packaging, Review, And Push

**Files:**
- Verify: `DockCatApp/DockCat/Resources/DefaultCat/manifest.json`
- Generate: `DockCatApp/DerivedDataRelease/Build/Products/Release/DockCat.app`
- Generate: `DockCat.zip`

**Interfaces:**
- Consumes: validated shipping frames and the existing packaging script.
- Produces: a tested universal macOS app, clean distribution ZIP, reviewed commits, and updated `fork/main`.

- [ ] **Step 1: Verify manifests and run all non-Xcode checks**

```bash
python3 scripts/test_xiaohou_gait.py -v
python3 scripts/test_prepare_xiaohou_rig.py -v
python3 scripts/test_generate_xiaohou_motion_assets.py -v
python3 scripts/test_validate_xiaohou_gait.py -v
python3 scripts/validate_xiaohou_gait.py
python3 -m json.tool DockCatApp/DockCat/Resources/DefaultCat/manifest.json >/dev/null
git diff --check
```

Expected: all tests and validation pass; JSON parsing and diff check exit with code 0.

- [ ] **Step 2: Run the macOS test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project DockCatApp/DockCat.xcodeproj -scheme DockCat \
  -configuration Debug -destination 'platform=macOS' test
```

Expected: all `DockCatTests` pass. If Xcode hangs during initialization again, capture the last output and report packaging as blocked; do not claim success.

- [ ] **Step 3: Build and package the universal Release app**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer ./PackUp.command
lipo -archs DockCatApp/DerivedDataRelease/Build/Products/Release/DockCat.app/Contents/MacOS/DockCat
unzip -l DockCat.zip | rg 'DockCat.app|CustomizationGuide|README|LICENSE'
```

Expected: `PackUp.command` exits with code 0, `lipo` reports both `arm64` and `x86_64`, and the ZIP includes the app and documentation without tests, DerivedData, source photos, rig sheets, masks, or previews.

- [ ] **Step 4: Launch and inspect Dock-scale playback**

Launch the Release app, trigger walking, and watch at least three complete cycles. Confirm the cat moves right while the sprite faces right, the four-beat paw sequence is readable, the body stays calm, and frame 24 returns invisibly to frame 1.

Use Activity Monitor or `ps` after one minute of walking. Accept when DockCat remains below 5 percent average CPU and 150 MB resident memory on the test Mac. No Swift runtime code should differ from the pre-redesign commit.

- [ ] **Step 5: Request code and visual review**

Invoke `superpowers:requesting-code-review`. Review the diff against `docs/superpowers/specs/2026-07-11-xiaohou-realistic-walk-redesign.md`, the contact sheet, and both GIF previews. Address every High or Medium finding and rerun Steps 1-4 after changes.

- [ ] **Step 6: Final commit if verification changed tracked files**

```bash
git status --short
git add DockCat.zip
git commit -m "Package realistic Xiaohou DockCat app"
```

Skip the commit only when `DockCat.zip` is byte-identical and no tracked file changed.

- [ ] **Step 7: Verify fork target and push main**

```bash
git remote get-url fork
git status --short --branch
git log --oneline fork/main..main
git push fork main
```

Expected: the fork URL is `git@github.com:ABreadTree/DockCat.git`, only the known unrelated untracked files remain, and `main` pushes successfully to `fork/main`.
