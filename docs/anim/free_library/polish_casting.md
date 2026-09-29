# Elemental casting clips: Cast_<Element>_Charge / Cast_<Element>_Release

Library: `kingdom/assets/incoming/animations_free/casting/UAL_Free_CastingElements.glb` (+ `.clips.json`), 16 clips, 30 fps, UAL 65-bone skeleton, all in place
(no root travel, the `root` track is constant), about 0.5 MB. Existing clips are untouched. No `.import` file was added (Godot generates it).

Source: hand-authored (there is no spellcasting in the CMU set, so mocap would only give generic arm waves). Hands, feet, elbow/knee hints are world-space IK targets
keyed per pose in Blender 5.2, baked to plain FK quaternions (same recipe as `tools/anim/free2/author_traversal.py`). Feet are IK-pinned, so a planted foot cannot slide.
Reproduce: `tools/anim/casting/build_casting_elements.sh` (poses in `casting_clips.py`, framework in `author_casting_elements.py`, preview `run_preview.sh`).
Hands use two UAL finger poses (open = `A_TPose`, fist = `Punch_Jab`) blended per clip, so palms are really open where the gesture needs it.

Naming: the GLB stores loops as `Cast_<El>_Charge_Loop`; Godot strips `_Loop` on import and sets loop mode, so in game the names are `Cast_Fire_Charge` etc.
(same convention as `MA_Guard_Boxing_Loop`).

## Design rules shared by all pairs

* **Release frame 0 == Charge frame 0** (same base pose, measured gap 0.000 m on wrists, ankles, pelvis, head). Charge is a clean loop (last key == first key, gap 0.000 m).
  Charge loops have small amplitude, so a cut at any phase blends to the release start with 0.10 s.
* The **anticipation is the first part of the Release clip** (pull-back / coil / raise), so the charge loop itself stays a pure hold that the charge FX can sit on.
* **Release frame** = frame at which to spawn the projectile / impact / beam / aoe (limb fully extended, or the slam lands).
* Feet never move except the deliberate earth stomps (planted-foot drift measured 0 to 7 mm, min ball height 0.014 to 0.015 m = on the floor).
* The clip ends in a relaxed standing pose with the same foot placement as the charge; blend out to Idle with 0.20 s (the foot offset from the idle stance is at most 0.15 m).
* Character faces +Z of the glTF (`-Y` in the Blender armature space used below), left hand = `hand_l`.

## Clip table

| clip (in game) | s | frames | loop | release frame | notes |
|---|---:|---:|---|---|---|
| `Cast_Fire_Charge` | 1.20 | 37 | loop | - | wide lunge stance, two cupped hands at the chest that squeeze and swell (pulse 1x per loop) |
| `Cast_Fire_Release` | 1.33 | 41 | no | **11** (0.37 s) | coil back 7 frames, two-hand thrust, arms fully extended at f11, held to f14, recover |
| `Cast_Water_Charge` | 1.40 | 43 | loop | - | hands orbit an invisible orb (out of phase), body sways in a figure 8, soft open fingers |
| `Cast_Water_Release` | 1.40 | 43 | no | **12** (0.40 s) | right arm sweeps low-left, across the front (f12), up-right (f18), torso rotates with it, left arm counter-swings |
| `Cast_Earth_Charge` | 1.40 | 43 | loop | - | deep horse stance, hands lift a boulder, right foot stomps at 60 % of the loop (foot plants at about f25) |
| `Cast_Earth_Release` | 1.80 | 55 | no | **15** (0.50 s) | rise + fists overhead (apex f9-11, right foot lifted), stomp + slam to knee height at f15, hold to f32, slow rise |
| `Cast_Wind_Charge` | 1.40 | 43 | loop | - | arms sweep opposed horizontal circles at their own side, torso twists with them |
| `Cast_Wind_Release` | 1.40 | 43 | no | **12** (0.40 s) | torso wound to the right (f8), whip to face front at f12 (right arm forward, arc through wide out), on to +58 degrees left at f17-22, recover |
| `Cast_Lightning_Charge` | 1.20 | 37 | loop | - | right arm straight up to the sky, head back, left fist at the hip, stepped jitter (every 2-4 frames, zero at the loop point) |
| `Cast_Lightning_Release` | 1.33 | 41 | no | **9** (0.30 s) | arm cocks back/up (f5), snaps down to a pointed strike in 4 frames, decaying recoil jitter f9-18, recover |
| `Cast_Ice_Charge` | 1.20 | 37 | loop | - | rigid, feet parallel, forearms crossed at the chest, flat hands, shoulders raised, tiny frost tremor |
| `Cast_Ice_Release` | 1.33 | 41 | no | **9** (0.30 s) | arms draw in (f5, linear), burst out into a stiff two-palm push (linear, hard stop f9), frozen hold to f24, thaw |
| `Cast_Light_Charge` | 1.60 | 49 | loop | - | open palms raised in a V, chest lifted, head back, slow rise/fall swell |
| `Cast_Light_Release` | 1.60 | 49 | no | **17** (0.57 s) | palms rise together overhead (f9), sweep down/forward into a blessing push (arrive f17), hold to f30, lower |
| `Cast_Dark_Charge` | 1.40 | 43 | loop | - | hunched, low right hand clawing/creeping at the hip, left arm wrapped across the chest like a cloak, slow sway |
| `Cast_Dark_Release` | 1.53 | 47 | no | **12** (0.40 s) | claw hand coils back (f8), thrusts forward-low (f12), drags back to the hip (f12-28) while the left arm flares out wide (f20), recover |

## Hand positions for `ElementFX.attach(element, &"charge", hand_node)`

Attach to the **`hand_r` bone** (`BoneAttachment3D` bone_name = `hand_r`; the wrist/hand-bone head is at the wrist, the palm centre is about 0.05 m further along the fingers).
For the two-hand clips (fire, ice, light) the hands are close together, so **one** charge effect on `hand_r` with a local offset toward the other hand looks right, or attach one to each hand
with `scale 0.6`. Wrist target positions of frame 0 (armature space, +X = character's left, -Y = forward, metres; palm centre is about 0.05 m further along the fingers):

| element | charge FX anchor | palm_l (frame 0) | palm_r (frame 0) | suggested `offset` on `hand_r` (bone-local, m) |
|---|---|---|---|---|
| fire | between the two hands, chest height | (0.10, -0.33, 1.20) | (-0.10, -0.33, 1.20) | `Vector3(0.0, 0.05, 0.10)` toward the left hand (or attach to both) |
| water | orb between the hands | (0.14, -0.30, 0.94) | (-0.16, -0.22, 1.28) | attach to `hand_r`, offset (0, 0.05, 0) |
| earth | in the lifting hands | (0.30, -0.22, 0.80) | (-0.30, -0.22, 0.80) | attach to both hands (boulder rises 0.36 m per loop) |
| wind | one swirl per hand | orbit x 0.22..0.46, y -0.07..-0.41, z 1.15..1.41 | mirrored | both hands, small scale |
| lightning | above the raised hand | (0.24, -0.10, 0.98) fist | (-0.13, -0.02, 1.90) | `hand_r`, offset (0, 0.10, 0) so the crackle sits above the palm |
| ice | in front of the crossed forearms | (-0.12, -0.22, 1.30) | (0.12, -0.30, 1.30) | attach to both hands, forearms cross |
| light | above each raised palm | (0.44, -0.04, 1.86) | (-0.44, -0.04, 1.86) | both hands, offset (0, 0.08, 0) |
| dark | the low claw | (-0.14, -0.24, 1.24) left forearm | (-0.30, -0.26, 0.92) | `hand_r` only (offset (0, 0.05, 0)) |

## Spawn positions at the release frame (measured, armature space; add the character transform)

| element | release frame | palm_l | palm_r | mid point of the palms | ElementFX call at that frame |
|---|---:|---|---|---|---|
| fire | 11 | (0.10, -0.72, 1.32) | (-0.10, -0.72, 1.32) | (0.00, -0.72, 1.32) | `ElementFX.stop(charge_fx)`; `ElementFX.projectile(&"fire", mid, target, 16.0)` (fireball speed in `vfx_spells.gd` is 16 m/s, `ElementFX.projectile` default 18); impact plays 1.0 s |
| water | 12 | (0.59, -0.04, 1.31) | (-0.20, -0.61, 1.14) | use `palm_r` | `VFX.water_whip(parent, palm_r, target)` (lash 0.22 s = the follow-through to f18, impact at ~f19) or `ElementFX.beam(&"water", palm_r, target, 1.0, 0.3)` |
| earth | 15 | (0.17, -0.48, 0.64) | (-0.17, -0.48, 0.64) | (0.00, -0.48, 0.64), ground point ahead | `ElementFX.aoe(&"earth", ground_pos, r)` or `VFX.earth_spike(parent, feet_pos, target)`; spike line 1.7 s and aoe 1.9 s, the clip holds the crouch f15-32 (0.57 s) then rises |
| wind | 12 | (0.58, 0.07, 1.26) | (-0.16, -0.54, 1.37) | use `palm_r` | `VFX.wind_blade(parent, palm_r, target, 1.0, 22.0)` (speed 22 m/s); `ElementFX.aoe(&"wind", pos)` lasts 2.5 s |
| lightning | 9 | (0.58, 0.13, 1.20) | (-0.09, -0.71, 1.23) | use `palm_r` | `ElementFX.beam(&"lightning", palm_r, target, 1.0, 0.3)` then `ElementFX.chain(...)` (0.07 s per hop); impact 0.7 s; recoil jitter runs to f18 |
| ice | 9 | (0.20, -0.54, 1.36) | (-0.20, -0.54, 1.36) | (0.00, -0.54, 1.36) | `ElementFX.projectile(&"ice", mid, target)` or `aoe(&"ice", ...)` (impact 1.0 s, aoe 2.0 s); the frozen hold lasts f9-24 (0.5 s) |
| light | 17 | (0.20, -0.52, 1.52) | (-0.20, -0.52, 1.52) | (0.00, -0.52, 1.52) | `ElementFX.beam(&"light", mid, target, 1.0, 1.0)` or `aoe(&"light", ...)`; hold f17-30 (0.43 s) |
| dark | 12 | (0.40, -0.10, 1.20) | (-0.20, -0.67, 0.95) | use `palm_r` | `ElementFX.projectile(&"dark", palm_r, target)` / `aoe(&"dark", ...)`; the drag-back f12-28 sells the pull |

In game the charge FX has no fixed length (`begin(el, "charge", 0.0)`: loops until `stop()`), so gameplay owns how long the Charge clip loops. Recommended: start the charge FX when the
Charge clip starts, `stop(fx, 0.2)` on the release frame and play the release FX on the same frame. If the FX must have its build-up visible before release, hold the Charge loop for at
least 1 loop (1.2 to 1.6 s).

## Blend times (seconds)

| transition | blend |
|---|---|
| Idle / Combat idle -> `Cast_<El>_Charge` | 0.20 (0.15 for lightning / ice) |
| `Cast_<El>_Charge` -> `Cast_<El>_Release` | 0.05 (frame 0 poses are identical; use 0.0 at the loop boundary) |
| `Cast_<El>_Release` -> Idle | 0.20 |
| cancel Charge (interrupted) -> Idle | 0.15 |

Root motion: none (`root` track constant). Play in place (`Assets._ual_for` already disables the root track for the `animations_free` directory if the one-line fix in `HANDOFF_CODEX.md` is applied).

## State -> clip table for Codex (paste)

```gdscript
const CAST_ELEMENT_CLIPS := {
	&"fire":      {"charge": &"Cast_Fire_Charge",      "release": &"Cast_Fire_Release",      "release_frame": 11, "length": 1.333},
	&"water":     {"charge": &"Cast_Water_Charge",     "release": &"Cast_Water_Release",     "release_frame": 12, "length": 1.400},
	&"earth":     {"charge": &"Cast_Earth_Charge",     "release": &"Cast_Earth_Release",     "release_frame": 15, "length": 1.800},
	&"wind":      {"charge": &"Cast_Wind_Charge",      "release": &"Cast_Wind_Release",      "release_frame": 12, "length": 1.400},
	&"lightning": {"charge": &"Cast_Lightning_Charge", "release": &"Cast_Lightning_Release", "release_frame": 9,  "length": 1.333},
	&"ice":       {"charge": &"Cast_Ice_Charge",       "release": &"Cast_Ice_Release",       "release_frame": 9,  "length": 1.333},
	&"light":     {"charge": &"Cast_Light_Charge",     "release": &"Cast_Light_Release",     "release_frame": 17, "length": 1.600},
	&"dark":      {"charge": &"Cast_Dark_Charge",      "release": &"Cast_Dark_Release",      "release_frame": 12, "length": 1.533},
}
# start: play(charge, 0.2 blend) + ElementFX.attach(el, &"charge", hand_r_attachment)
# fire: play(release, 0.05); after release_frame / 30.0 s: ElementFX.stop(charge_fx, 0.2); spawn projectile / beam / aoe from the palm position
```

`UAL_FILES` line (append after the existing casting lines, `UAL_FREE_DIR` as in `HANDOFF_CODEX.md`):

```gdscript
	UAL_FREE_DIR + "casting/UAL_Free_CastingElements.glb",
```

Better than a timer: add a method-call track at `release_frame / 30.0` on the duplicated Animation so the event follows `speed_scale` and the blend.

## Verification (stop-motion, side | front, Blender workbench, UAL mannequin)

Sheets: `docs/anim/free_library/frames/casting_elements/<clip>/sheet_00N.png` (width 440 tiles, 3x4; releases sampled at 10 fps, charges at 8 fps; the full 30 fps frames were checked while
iterating). Every sheet was read. Measured from the baked bones: loop gap 0.000 m, charge->release gap 0.000 m, planted ankle drift 0 to 7 mm, ball height on the floor.

| clip | feet planted | facing | loop / hand-over | anticipation -> release | wrists / hands | mesh intersection | verdict |
|---|---|---|---|---|---|---|---|
| Fire Charge / Release | pass | pass | pass | pass (coil 7 f, thrust 4 f) | pass | pass | pass |
| Water Charge / Release | pass | pass | pass | pass | pass | pass | pass (release arms look slightly stiff at the far end of the sweep) |
| Earth Charge / Release | pass (stomp foot replants at the same spot, 5-7 mm) | pass | pass | pass | pass | knees/hands touch at the slam (hands stop at knee height, they do not reach the ground: UAL arm length) | pass |
| Wind Charge / Release | pass | pass | pass | pass | pass | pass | pass with a caveat: in the hold (f17-22) the left arm is held straight out behind, wing-like |
| Lightning Charge / Release | pass | pass | pass | pass (snap is 4 frames) | pass (raised arm 5-7 cm short of the target = fully straight, intended) | pass | pass |
| Ice Charge / Release | pass | pass | pass | pass | pass | crossed forearms touch (intended) | pass |
| Light Charge / Release | pass | pass | pass | pass | pass | pass | pass |
| Dark Charge / Release | pass | pass | pass | pass | pass | pass | pass (claw thrust is only about 0.3 m forward-low, a small gesture) |

Known limits (honest list):

* Poses are authored from IK targets, not captured, so the secondary motion (weight shift, overlap) is simple; a mocap or hand-polish pass could improve the water and wind arcs.
* The charge loops are deliberately low amplitude; at phone size the swell/orbit reads mostly through the VFX. Lightning jitter is a 2-4 frame stepped noise, visible at 30 fps, not at 8 fps sheets.
* The mannequin used for the sheets has blocky hands; the open/fist finger poses were verified on close-up renders, the exact look on the game's character meshes was not.
* Godot was not run (another session was importing the project), so import, loop flags and `_Loop` stripping are unverified in engine; the GLB follows the same export path as `UAL_Authored_Traversal.glb`.
