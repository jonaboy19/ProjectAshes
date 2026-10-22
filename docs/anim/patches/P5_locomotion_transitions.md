# P5 - Start / stop / pivot / turn clips (FEEL_AUDIT F1, F2, F7): DELIVERED, wire them

**Status 2026-10-06: APPLIED by the local session (animation behaviour owner) and checked in the real game; sheets in `docs/anim/local_wiring/`, notes in `docs/STATUS_LOCAL.md`.**

Status: the clips exist. Library `kingdom/assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb` (20 clips, 30 fps, UAL skeleton, 0.68 MB)
plus sidecar `UAL_Loco_Transitions.glb.contacts.json` (foot contacts, root motion, loop hand-off phases, events). Frame sheets (side + front, every clip) are in
`docs/anim/free_library/frames/locomotion_v1/<clip>/`. Codex owns the wiring in `player.gd` / `character_animator.gd`; this note is the contract.
Loaded and checked in Godot 4.6.3 (`tools/anim/loco/verify_loco.gd`: 65 bones, 20 clips, 0 unresolved tracks, loops as expected).

## 0. Two things to do first

1. **Register the library BEFORE UAL1** in `Assets.UAL_FILES`. `_ual_for` keeps the first clip of a name and UAL1 already has `Jump_Start` and `Jump_Land`, so if UAL1 is first
   the new `Jump_Start` is silently dropped. Put `res://assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb` first in the list (the other new names are unique;
   `tools/anim/check_unique_clips.py` passes: 240 clips, 0 problems). Godot strips `_Loop`, so the loops are **`Jump_Rise`** and **`Jump_Fall`** in-game.
2. Play every clip through a `TimeScale` node at `rate = body_speed / clip.root.speed_in_mps` (stops) or `body_speed / speed_out_mps` (starts). Clip speeds are the
   natural mocap speeds; the UAL loops are `Walk_Loop` 0.80 m/s, `Jog_Fwd_Loop` 5.24 m/s, `Sprint_Loop` 5.89 m/s (measured from the stance foot, `reference_loops` in the sidecar).
   Distances do not change with rate, so the travel column is what the capsule should cover.

## 1. Clip table (exact names, natural durations, blend times)

`rate@` = the play rate that makes the clip agree with the capsule at the given speed. Blend in/out are AnimationTree fade times in seconds.

| Clip | Length | Root travel (fwd) | Speed in -> out (m/s) | Blend in / out | Use, and rate@ | Hand-off |
|---|---|---|---|---|---|---|
| `Loco_WalkStart_F` | 1.267 s (39 f) | 1.56 m | 0.7 -> 1.5 | 0.06 / 0.15 | stick pressed from idle below 1.0 m/s; rate@2.4 = 1.6 -> 0.79 s | ends on Walk_Loop phase 0.97 (R), err 16 |
| `Loco_RunStart_F` | 0.633 s (20 f) | 1.87 m | 2.1 -> 3.8 | 0.05 / 0.12 | stick pressed from idle to run; rate@6.5 = 1.7 -> 0.37 s | ends on Jog_Fwd_Loop phase 0.91 (R), err 24 |
| `Loco_RunStop_L` | 0.867 s (27 f) | 1.45 m | 3.1 -> 0.5 | 0.06 / 0.20 | stick released above 4 m/s **while the left foot is planted** (Jog phase < 0.5); rate@6.5 = 2.1 -> **0.41 s** | starts at Jog phase 0.09 (L); plant at frame 18 |
| `Loco_RunStop_R` | 0.800 s (25 f) | 1.74 m | 3.6 -> 0.9 | 0.06 / 0.20 | same, right foot planted (phase >= 0.5); rate@6.5 = 1.8 -> **0.44 s** | starts at Jog phase 0.55 (R) |
| `Loco_WalkStop` | 1.367 s (42 f) | 0.88 m | 1.1 -> 0.1 | 0.05 / 0.20 | stick released from 1.0-3.0 m/s; rate@2.4 = 2.2 -> 0.62 s; plant at frame 27 | starts at Walk_Loop phase 0.97 |
| `Loco_Sprint_Stop_Skid` | 0.900 s (28 f) | 2.65 m | 4.6 -> 1.2 | 0.05 / 0.20 | stop from sprint / dash; rate@8.5 = 1.85 -> 0.49 s; **skid (dust) frames 11-20** | starts at Sprint_Loop phase 0.38 (L) |
| `Loco_TurnInPlace_90_L` | 0.733 s (23 f) | 0.15 m | - | 0.05 / 0.12 | idle turn, heading change +80 deg over the clip | Idle -> Idle |
| `Loco_TurnInPlace_90_R` | 0.700 s (22 f) | 0.05 m | - | 0.05 / 0.12 | -84 deg | Idle -> Idle |
| `Loco_TurnInPlace_180` | 1.100 s (34 f) | 0.79 m | - | 0.05 / 0.15 | +173 deg (left), rate 1.5 -> 0.73 s | Idle -> Idle |
| `Loco_TurnInPlace_180_R` | 0.867 s (27 f) | 0.25 m | - | 0.05 / 0.15 | -160 deg (right), extra clip so both directions exist | Idle -> Idle |
| `Loco_Pivot180_Run_L` | 1.233 s (38 f) | 1.13 m **backwards**, yaw +189 | 1.9 -> 3.9 | 0.05 / 0.12 | reverse stick above 3 m/s, left foot planted; rate 1.7 -> 0.73 s (brake, turn, first strides back) | enters at Jog phase 0.14 (L), leaves at Jog phase 0.05 |
| `Loco_Pivot180_Run_R` | 1.367 s (42 f) | 0.64 m backwards, yaw -182 | 2.9 -> 3.9 | 0.05 / 0.12 | mirror image, right foot | enters at Jog phase 0.55 (R), leaves at 0.55 |

Turn clips: the heading change is on the **`root` bone rotation** (`root.yaw_curve_deg` in the sidecar, every 3rd frame). The pelvis only keeps the residual twist.
Either enable root motion rotation (`root_motion_track = <skeleton>:root`) or leave the root track off and drive the player yaw with `yaw_curve_deg` while the clip plays;
do not play a turn clip with the root rotation disabled and the capsule yaw also turning, the body would turn twice. Numbers are measured, not the nominal 90 / 180.

Mirroring L/R: the L clips and R clips are different takes or mirrored takes (see the sidecar `source` / `mirrored`), both keep the foot that lands first consistent with the loop phase.

## 2. Wiring (unchanged from the proposal, now with real numbers)

* A `stop` OneShot between `loco` and `stance` in `CharacterAnimator`. Fire it when the stick is released with body speed > 4 m/s; pick `_L` when `_phase < 0.5`, else `_R`
  (the clip's first pose is the Jog pose at the phase in the table). Set `rate` as in section 0. The capsule keeps `STOP_BRAKE_RUN` (15 m/s2): 6.5 m/s stops in 0.43 s over 1.4 m, and the
  clip covers 1.45 / 1.74 m in 0.41 / 0.44 s at that rate, so the planted feet stay put. Use `events.plant_frame` (RunStop_L 18, WalkStop 27) as "the body may hand over to idle".
* Walk / run starts: fire from idle when the stick goes above the dead zone; keep `ACCEL_START` 17 m/s2. WalkStart lands on Walk_Loop phase 0.97, RunStart on Jog phase 0.91: seek the
  gait to that phase when the OneShot ends, or accept a 0.12 s blend (bone error 16-24 deg, same gait but a different actor).
* Pivot: fire `Loco_Pivot180_Run_*` from `player._steer` when `_pivoting` becomes true above 3 m/s. The clip includes the brake (first 0.3 s at rate 1), the turn and the first two
  strides in the new direction; while it plays let the capsule run `PIVOT_BRAKE`, then set the heading to +-180 deg and use root motion (or `ACCEL_START`) for the exit.
* Idle turn: `FACE_TURN_IDLE` 14 rad/s finishes 180 deg in 0.22 s, the clip needs 0.73 s at rate 1.5. Either drive the yaw from `yaw_curve_deg` (recommended) or keep the fast code turn and
  cross-fade a 0.12 s hip twist only. At 180 deg the feet take three steps.
* Sprint stop: `Loco_Sprint_Stop_Skid` frames 11-20 have the feet braking on the ground: spawn the dust puff there (`events.skid_frames`), one small puff per foot.

## 3. Verification (what was checked, evidence in `frames/locomotion_v1/`)

Read every sheet (12 fps, side left + front right, ruled floor, camera follows the pelvis):

| Check | Result |
|---|---|
| Feet planted, no sliding | planted feet drift at most 4.5 cm in every clip except `Jump_Land_Hard` (6.7 cm on the heel while the body settles). Measured on the real rig with a 3 cm touch height and a 0.5 m/s planted speed, root motion included |
| Weight shift into stops | RunStop_L/R and Skid show the knees bending and the torso leaning back over the braking foot at frames 4-10 before the plant |
| Lean into pivots | Pivot180 leans back into the plant, twists the chest ahead of the hips (frames 3-7 at 12 fps), then leans forward into the exit strides |
| No pops | read the sheets frame by frame: no snapping joints; the cross-fades of the Pivot composite (3 frames) sit at planted-feet poses. `motion.png` is stored next to every sheet for a second look |
| Loop / hand-off pose error | 16-31 deg mean bone error to the nearest UAL loop pose (different actor, same gait); blend over 0.1 s |

Known limitations (honest list): mocap style differs a little from the UAL loops (2.9-3.6 steps/s in the stops against 2.2 steps/s of the UAL jog); the pivot is a composite
(brake take + standing turn take + run-start take, 3-frame cross-fades) because none of the sources has a 180 on the run; the standing-turn takes carry a slightly bowed head.
