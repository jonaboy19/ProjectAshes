# Traversal v2.1 - handoff for Codex (ledge, mantle, vault landing, rising trot, pivot 180)

Library: `res://assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb` (19 clips, was 14; 30 fps; UAL skeleton) and the pivot clips of
`res://assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb` (only `Loco_Pivot180_Run_L/R` changed, every other clip of that file is identical).
Sidecar: `UAL_Authored_Traversal.glb.clips.json` has, per clip, `frames`, `seconds`, `loop`, `root_delta_m`, `events` (frame numbers) and `contacts` (world-locked hand / foot windows).
Rebuild, geometry contract and checks: `kingdom/tools/anim/traversal/README.md`. Numbers, before / after: `docs/anim/free_library/frames/traversal_v2/METRICS.txt`. Sheets: same folder.

Conventions (as in `docs/anim/free_library/HANDOFF_CODEX.md`): the `_Loop` suffix is stripped by Godot's importer (use `Ledge_Hang_Idle`, not `Ledge_Hang_Idle_Loop`); the character faces +Z
after import (Blender -Y); the `root` bone position track is the root motion. The new library must load like the existing traversal one (it is already in the `UAL_FREE2_DIR` list; the
`root_motion_lib` line of `_ual_for` already covers `animations_free2/`, so root tracks are disabled by default). For every clip marked **root motion: yes** duplicate the Animation, re-enable
`<skeleton>:root` and set `AnimationPlayer.root_motion_track` while it plays (recipe: `assets/incoming/animations/README.md`, "Root motion"). Geometry: ledge top = 2.12 m above the
floor the hang capsule stands on, face 0.20 m in front of the character origin; low wall 1.0 m; high wall 1.8 m; vault box 0.92 m.

## 1. New clips and which state plays them

| clip (in-game name) | s (frames) | state | blend in / out (s) | root motion | start pose -> end pose | events (30 fps frame) |
|---|---:|---|---|---|---|---|
| `Ledge_Grab` | 1.33 (41) | `LEDGE_GRAB`: jump / reach at a ledge whose top is 1.9-2.2 m above the floor (contextual jump button) | 0.05 / 0.10 into `Ledge_Hang_Idle` | **no** (the pelvis carries the jump, the capsule stays; snap it under the ledge at f15) | stand facing the wall 0.2 m from the face -> exactly frame 0 of `Ledge_Hang_Idle` (hands world-fixed on the top from f15) | crouch low f8, toe-off f12, **hands contact f15** (attach / stop gravity here), pendulum peak f19, settled f34, chain to hang idle f40 |
| `Ledge_Hang_Idle` (loop, existing, re-checked) | 2.00 (61) | `LEDGE_HANG` | 0.10 / 0.15 | no | frame 0 == last frame (loop gap under 1 cm) | - |
| `Ledge_Shimmy_L` / `_R` (loop, existing, re-checked) | 1.00 (31) | `LEDGE_SHIMMY` | 0.10 / 0.10 | **yes**, 0.5 m sideways per loop | hang -> hang | - |
| `Ledge_Climb_Up` | 1.73 (53) | `LEDGE_CLIMB`: up while hanging | 0.10 / 0.15 into `Idle_Loop` | **yes**: 2.12 m up, 0.5 m forward (see the note below) | hang pose (frame 0 = hang idle) -> relaxed idle stand on the ledge top, feet on z 2.12 | pull start f7, chin over the ledge f17, chest over the lip f24, **right foot on the ledge f28**, hands release f29, left foot up f41, stand f46, settled f52 |
| `Ledge_Drop_Down` | 1.07 (33) | `LEDGE_DROP`: down / jump-back while hanging | 0.08 / 0.15 | **yes**, 0.36 m backwards (away from the wall), no vertical travel (the hang feet are 0.2 m above the floor) | hang pose -> relaxed stand on the floor | **release f6** (enable gravity), **touch-down f11** (dust `dash(&"wind", ...)`), absorb low point f15, settled f28 |
| `Mantle_Low` | 1.47 (45) | `MANTLE_LOW`: run / step into a wall 0.8-1.2 m high (contextual jump button, same trigger family as the vault) | 0.10 / 0.15 into locomotion | **yes**: 1.27 m forward, 1.0 m up | run-ready stance 0.85 m before the wall -> relaxed stand on the wall top | hands on the top f12, R foot leaves the floor f14, **left foot on the top f23**, hands release f19-22, stand f40, settled f44 |
| `Mantle_High` | 1.97 (60) | `MANTLE_HIGH`: jump at a wall 1.5-2.0 m high | 0.08 / 0.15 into `Idle_Loop` | **yes**: 0.9 m forward, 1.8 m up | run-ready stance 0.6 m before the wall -> relaxed stand on the wall top | jump f9, **hands contact f12**, pull start f14, chest over f29, **right foot on the top f35**, hands release f39, stand f59 |
| `Vault_Low` / `Vault_Low_B` (rebuilt landing) | 2.00 (61) | `VAULT` (unchanged: obstacle 0.4-1.0 m, `_B` = right-side variant) | 0.10 / 0.15 | **yes**, 2.7 m forward | run stride -> run-ready stance (staggered feet, elbows bent) | takeoff foot plant f7, toe-off f14, hands on the box f17, apex f24, push-off end f27, **touch-down f33** (dust), low point f36, settled f56-60 (may hand over to run from f50) |
| `Ride_Trot` (loop, rebuilt) | 0.67 (21) | riding: trot gait | 0.20 / 0.20 | no | frame 0 == last frame | diagonal A lands f0 (rider starts rising), rider at the top f5, **diagonal B lands f10 (rider back in the saddle)**, second beat + suspension f10-20 seated |
| `Loco_Pivot180_Run_L` / `_R` (loco library, rebuilt middle) | 1.23 / 1.40 (38 / 42) | `PIVOT_180` (unchanged usage) | unchanged | **yes** (root track and yaw unchanged: 1.17 m / 0.71 m, 188 / -182 degrees) | run -> run in the opposite direction (start and end poses unchanged) | pivot foot planted f7-19 (L) / f13-23 (R); push-off foot lands f21 / f23 and pushes f26 / f29 |

Notes on the states:
* **Ledge climb root motion**: the contract puts the ledge top 2.12 m above the floor the hang capsule stands on (hands on the top at 2.14), so the root moves 2.12 m up and 0.5 m forward,
  not 1.05 m: with a 1.05 m root travel the character would end 1.07 m inside the ledge. If your hang state parks the capsule at another height use
  `root_up = ledge_top_y - capsule_hang_y` and scale the `root` Y track; the pelvis local motion does not change.
* Turn off the capsule collision against the ledge / wall from the moment the hands release the top (f29 climb, f22 low mantle, f39 high mantle) until the clip ends, then re-enable.
* `Ledge_Grab -> Ledge_Hang_Idle`: the last frame of the grab equals frame 0 of the idle, no pop. The hang pose now sits 5 cm farther from the wall (the chest used to clip the ledge face by 4 cm).
* Ledge climb / drop / mantle clips all end in the same relaxed idle stand: feet 0.22 m apart (shoulder width), arms hanging with soft elbows. Blend into `Idle_Loop` / locomotion with 0.15 s.
* Mirroring: `Ledge_Climb_Up` / `Mantle_*` start with the same foot (right foot leads onto the ledge, left onto the wall top); no left / right variants ship. Flip the whole
  character in X (scale -1) if you need the mirrored version, or ask for `_B` clips in the next round.
* `Vault_Low`: the landing was rebuilt (see section 2); the stiff-arm landing is gone: touch-down f33-34, torso dips and the knees absorb to f36, arms swing forward-down then opposite-arm
  swing with the two recovery steps, bent-elbow run carry from f53.

## 2. What changed in the existing clips (fixes)

* **Vault calf snap**: a calf jumped 0.36 m in one frame at f30. Cause: (1) the right-shoulder anchor that keeps the planted arm reachable released 0.5 m of pelvis travel in three frames
  (the pelvis path is now continuous), (2) the knee pole direction changed too fast while the foot extended for the landing, (3) the extension itself took only 5 frames. Fixed at the source
  in `clips_vault.py` / `trav_lib.py`; numbers in METRICS.txt.
* Vault_Low landing arms: see above. Hand orientations are now slerped (a lerp of finger / palm vectors flipped the wrist 100+ degrees in one frame at the plant and at the release).
* `Ledge_Hang_Idle` / `Ledge_Shimmy_L/R`: pelvis moved 5 cm away from the wall (chest clipped the ledge face), checked frame by frame at 30 fps, loop points measured (see METRICS.txt).
* `Ride_Trot`: rising / posting trot: the pelvis rises 0.116 m (top f5) and sits from f10 to f20 (2-beat rhythm: diagonal A pushes the rider up, diagonal B seats him), the torso hinges
  forward 7 degrees at the top, hands follow 60 % of the rise (rein stays taut, a few mm of give), heels 18 degrees down, knees soft, no pop at the loop point.
  Timing to the horse: start the rider at the frame where the horse's left-fore + right-hind diagonal lands; if the horse trot loop has another length, set `speed_scale = horse_len / 0.667`.
* `Loco_Pivot180_Run_L/R`: middle rebuilt by `kingdom/tools/anim/loco/pivot180_rebuild.py` (pure numpy on the GLB, other clips untouched): pivot (outside) foot world-locked with the foot yaw
  following the body (slip 6.7 / 2.3 cm -> 0.0 cm), the push-off foot lands directly on its final spot and stays locked until the push (slide 14 / 14 cm -> 0.0), hips lead the heading
  by up to 26 degrees while the spine counter-rotates (shoulders lag), 11 degrees lean into the turn, head looks ahead, 13 degrees forward pitch into the run. Root motion, clip names, start
  and end poses are unchanged, so the handover to `Jog_Fwd_Loop` is the same as before.

## 3. Unique names

`python tools/anim/check_unique_clips.py` (run from `kingdom/`): 245 clips, 0 problems (`Ledge_Grab`, `Ledge_Climb_Up`, `Ledge_Drop_Down`, `Mantle_Low`, `Mantle_High` are new and unique).

## 4. Open issues

See the last section of METRICS.txt (remaining frames above the 0.12 m / 35 degree limit and the reasons, penetration of the legs into the wall while tucking on the mantles, no mirrored ledge
climb, hand orientation while gripping is a flat palm with curled fingers, no finger IK).
