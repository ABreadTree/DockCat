# Xiaohou Realistic Walk Redesign

## Goal

Replace the current distorted Xiaohou walk cycle with a coherent, realistic side-view animation based on Xiaohou's photos and the movement timing of `xiaohou/example/IMG_5056.GIF`.

The result must read as the same round-faced, short-haired blue-golden shaded cat at Dock scale, walk naturally in a seamless 24-frame loop, show exactly four anatomically plausible legs, and remain inexpensive to render in the macOS app.

## Chosen Approach

Use a layered realistic sprite rig.

Create one coherent side-view identity plate for the head, torso, and tail, then create four separately controlled limb layers: `left_front`, `right_front`, `left_rear`, and `right_rear`. The generator composes those layers into 24 transparent PNG frames using a deterministic gait plan.

This approach preserves identity and texture better than redrawing every frame independently, while avoiding the warped joints and duplicated paws caused by translating cropped regions from the existing flattened frames. Runtime playback remains a lightweight image sequence; no video decoder, skeletal animation engine, or model inference is added to DockCat.

## Visual Direction

Xiaohou's photos define identity and appearance:

- Round face, short muzzle, compact ears, and blue-golden shaded short fur.
- Realistic feline proportions and restrained photographic fur texture.
- A coherent side view facing right, with the whole body visible and no perspective mismatch between head, torso, and legs.
- Natural shoulder, hip, knee, hock, and paw shapes. Limbs must blend into the torso without pasted patches, hard seams, or stretched fur.
- Near limbs are slightly clearer and warmer; far limbs are subtly darker and partially occluded to preserve depth.

The example GIF defines only movement timing, silhouette readability, paw placement, and the order of leg motion. Its flat illustrated color, body proportions, face, and tail shape must not be copied.

The final frames use a transparent background and a 512 x 512 canvas to match the current app resources. The cat stays inside a stable shared bounding area with enough transparent margin to prevent clipping.

## Four-Limb Model

Every frame contains exactly these four legs and no detached or duplicate paw shapes:

| Limb | Screen position | Depth | Touchdown frame |
| --- | --- | --- | --- |
| `left_front` | Front, nearest viewer | Foreground | 19 |
| `right_front` | Front, far side | Behind torso/near front leg | 7 |
| `left_rear` | Rear, nearest viewer | Foreground | 13 |
| `right_rear` | Rear, far side | Behind torso/near rear leg | 1 |

The cycle uses a four-beat lateral-sequence walk, not a two-beat trot. The touchdown order is `right_rear`, `right_front`, `left_rear`, `left_front`, with six frames between contacts. Only one limb is in its main swing interval at a time; the other three provide visible support. Far-side legs remain visible enough to read as separate limbs but never appear attached to the wrong shoulder or hip.

Each limb passes continuously through five states:

1. Contact: paw lands ahead of its attachment point.
2. Support: paw remains visually planted while the body moves over it.
3. Push: paw trails behind and the limb extends without reversing its joints.
4. Lift: paw leaves the baseline with limited vertical travel.
5. Swing: paw moves forward in the air and prepares for the next contact.

There are no instantaneous pose changes between adjacent frames. A lifted paw moves forward, never backward. A supporting paw stays on the shared ground baseline and does not slide visibly.

## 24-Frame Timing

The animation is one second at 24 fps and loops from frame 24 back to frame 1. Each limb is in stance for approximately 18 frames and swing for approximately 6 frames. Touchdowns are separated by six frames so all four paws strike independently.

- Frame 1: `right_rear` touches down. Frames 1-6: `right_front` is the main lifted/swinging limb.
- Frame 7: `right_front` touches down. Frames 7-12: `left_rear` is the main lifted/swinging limb.
- Frame 13: `left_rear` touches down. Frames 13-18: `left_front` is the main lifted/swinging limb.
- Frame 19: `left_front` touches down. Frames 19-24: `right_rear` is the main lifted/swinging limb and returns to frame 1 contact.

The torso has only a subtle, low-frequency vertical motion of at most 3 px across the cycle. The head remains visually stable relative to the torso. The tail follows with a slow secondary arc and must not flick independently frame by frame. The loop boundary must have the same continuity limits as every other adjacent-frame transition.

## Asset Pipeline

The implementation produces and keeps the following reviewable sources:

- A realistic identity plate derived from the Xiaohou photos.
- Four named limb layers and their attachment metadata.
- A deterministic 24-frame gait definition.
- A generated 24-frame transparent PNG sequence.
- A contact sheet showing all frames and a 24 fps GIF preview for visual review.

Only validated outputs are copied into the three shipping locations:

- `DockCatApp/DockCat/Resources/DefaultCat/animations/walk-xiaohou`
- `DockCatApp/DockCat/Resources/DefaultCat/animations/walk`
- `xiaohou/cat_pack/xiaohou/animations/walk`

The three directories must be byte-identical after generation. Frame names remain `walk_01.png` through `walk_24.png`, and the existing manifest continues to play them at 24 fps.

## Validation

Automated validation must fail before installation when any of these conditions is present:

- The frame set is not exactly 24 transparent 512 x 512 PNG files.
- A frame has more than four lower-body connected paw/leg components or loses one of the four named limb layers.
- A limb skips a gait state, reverses while lifted, or exceeds the configured stride/lift limits.
- Two paws touch down on the same frame or the four touchdown events are not spaced six frames apart.
- The ground baseline varies by more than 3 px.
- Torso translation exceeds 3 px or the head-to-torso anchor changes unexpectedly.
- An adjacent-frame landmark jump, including frame 24 to frame 1, exceeds the continuity threshold.
- Subject alpha, bounding box, or right-facing orientation is clipped or unstable.
- The three installed animation directories differ.

Visual review is also required because anatomy, texture coherence, and perceived twitching cannot be proven by pixel metrics alone. Review the contact sheet at full size and the loop at both 24 fps and a slower diagnostic speed. Reject the result if it shows extra limbs, joint reversal, pasted texture, foot skating, body pumping, identity drift, or a visible loop reset.

## App Integration And Resource Budget

DockCat continues to load the existing 24 PNG paths through the current manifest and `SpriteAnimator`. No runtime code change is required unless verification finds that the current timer cannot sustain smooth 24 fps playback.

The implementation must not add a runtime video, neural model, third-party animation dependency, background worker, or new polling behavior. PNGs should be optimized without reducing edge quality or introducing green fringe. CPU and memory behavior are checked while the app plays the walk cycle; the redesign must not materially exceed the existing 24-frame playback cost.

## Delivery

After asset and gait validation:

1. Generate the final contact sheet and GIF preview.
2. Install identical frames into the app and Xiaohou resource pack.
3. Run script validation, relevant Swift tests, and a Release build.
4. Launch the built macOS app and visually verify the walk loop at Dock scale.
5. Package the app and complete resource bundle without including temporary previews or source photos in the app bundle.
6. Commit the reviewed changes and push `main` to the user's fork.

If the local Xcode toolchain still hangs during build initialization, asset work may be committed only after all non-Xcode checks pass, but packaging must be reported as blocked rather than claimed complete.

## Out Of Scope

- Replacing non-walk Xiaohou poses.
- Runtime procedural limb animation.
- Adding more than four legs or using motion-blur duplicates as extra silhouettes.
- Copying the example GIF's illustrated appearance.
- Shipping green-screen video or source photos inside the macOS app.

## Biomechanics References

- [Passive Dynamics Explain Quadrupedal Walking, Trotting, and Tolting](https://pmc.ncbi.nlm.nih.gov/articles/PMC4844082/) defines walking as a symmetrical four-beat gait with the touchdown sequence right hind, right fore, left hind, left fore.
- [The Use of Triaxial Accelerometers and Machine Learning Algorithms for Behavioural Identification in Domestic Cats](https://pmc.ncbi.nlm.nih.gov/articles/PMC10458840/) describes domestic-cat walking as four-beat sequential limb movement, with three or four feet supporting during a slow walk.
