# Elemental casting clips v2: Cast_<Element>_Charge / Cast_<Element>_Release (+ Cast_AoE_Slam, Cast_Channel_Beam)

Library: `kingdom/assets/incoming/animations_free/casting/UAL_Free_CastingElements.glb` (+ `.clips.json`, which also carries the release frame and the extra events of every clip),
**18 clips**, 30 fps, UAL 65-bone skeleton, all in place (no root travel, the `root` track is constant), 0.67 MB. Existing clips are untouched.
v1 (2026-09-29 morning) was reviewed by the owner: "casting clips look like punches, not magic" (no anticipation, one straight arm push, almost no body, nothing reads from the front).
v2 replaces all 16 v1 clips (same names) and adds the two shared clips. **Release frames changed** (they moved later because the anticipation is now part of the clip): use the tables below.

## Source survey (what was checked before authoring)

| candidate | licence | verdict |
|---|---|---|
| UAL1 `Spell_Simple_Enter / Idle_Loop / Shoot / Exit` (already in the game) | CC0 | one generic one-hand point, no per-element personality, small body motion: same problem as v1, kept as a fallback only |
| KayKit `Ranged_Magic_*` / `Spellcast_*` (in `UAL_Free_CastingKaykit.glb`: `Cast_Raise_Charge`, `Cast_Shoot_1H`, `Cast_Spell_Short/Long`, `Cast_Summon`) | CC0 | rendered `Cast_Spell_Long` (7 sheets): slow, arms stay low and close to the body, reads as a idle mutter. Useful as generic filler, not as a base for 8 different gestures |
| Mesh2Motion `Spell_Simple_*`, souls-cat `Magic_Cast_L/R`, `Magic_Attack_1/2` | CC0 | same family as the UAL clips: one-hand |
| System G6 `G6_cast_unarmed_magic(_2)`, `G6_channel_unarmed_magic_Loop` (CC0) | CC0 | rendered: a low crouch with one flat palm forward, 0.4 s; no wind-up, no twist; the channel loop is a crouched static hold |
| CMU mocap | free | no spellcasting takes (verified in round 3) |
| Kenney | CC0 | no humanoid animation packs |

Result: nothing existing has an anticipation + twist + overshoot structure or per-element character, and retargeted generic clips would still need most of the pose work. So the clips stay hand-authored on the UAL skeleton
(IK key poses baked to FK), now with real animation structure. The KayKit / G6 clips were used as timing references (release around 0.5 to 0.8 s after the start of the gesture).

## How it is built

Poses are world-space IK targets (hands, feet, elbow / knee hints) plus spine / hip / head angles, keyed per pose in Blender 5.2 and baked to plain FK quaternions.
Reproduce: `kingdom/tools/anim/casting/build_casting_elements.sh` (poses in `casting_clips.py`, framework in `author_casting_elements.py`, previews with `run_preview.sh`, numbers with `measure_casting.py`).
Framework additions in v2: `_bow` (an arc offset on a key segment, so hands travel on curves), `step=(a, b, k)` (hold poses on Ks: crystalline ice feel), automatic-elbow blending (no elbow pops), hip-leads-shoulders yaw split,
recovery step to the idle stance, tremor / decaying recoil helpers. `render_preview.py` now renders side | 3/4 | front.

Every Release follows one skeleton (visible in the sheets):

1. **anticipation** 8-12 frames, slow in: weight shifts back / down, torso coils, hands are drawn in on an arc (a 2-3 frame squash precedes the pull in fire);
2. **loaded hold** 1-3 frames with a tremor (this is what "gathering energy" looks like);
3. **snap** 3-4 frames, accelerating (`in` / `in2` easing), hips lead the shoulders, a foot steps or the body drops;
4. **release frame** = fastest, most extended pose (the VFX spawn frame);
5. **overshoot** 2-4 frames past the release pose, then follow-through (hands lag / ripple / drift, recoil jitter that decays) and a settle;
6. a **recovery step** brings both feet back near the idle stance over the last 10-14 frames (small foot arc, no sliding), arms relax; blend out to Idle with 0.20 s.

Release frame 0 == Charge frame 0 (same BASE dict; measured gap 0.000 m on wrists, ankles, pelvis and head for all eight pairs); Charge loops are clean (last key == first, gap 0.000 m).
The charge loops carry more body than v1 (breathing, weight shifts, figure-8 sway) so the gather is visible at phone size.

Naming: the GLB stores loops as `Cast_<El>_Charge_Loop` and `Cast_Channel_Beam_Loop`; Godot strips `_Loop` on import and sets loop mode (in game: `Cast_Fire_Charge`, `Cast_Channel_Beam`).

## Clip table (frames at 30 fps; release frame = spawn frame of the effect)

| clip (in game) | s | frames | loop | release | other events | personality / notes |
|---|---:|---:|---|---:|---|---|
| `Cast_Fire_Charge` | 1.20 | 37 | loop | - | | lunge stance, cupped hands squeeze and swell (+-0.08 m), torso pumps, weight rocks back |
| `Cast_Fire_Release` | 1.60 | 49 | no | **17** (0.57 s) | wind-up peak f11, hold f11-13, left foot lands f17, overshoot f20 | aggressive two-hand thrust: squash, coil -42 deg with both hands drawn to the right hip, hips lead, left foot steps, hands blast out at chest height (18 m/s), lean + drop, hands held up to f28, recovery |
| `Cast_Water_Charge` | 1.40 | 43 | loop | - | | hands orbit an invisible orb, body sways in a figure 8 (weight rocks foot to foot), soft fingers |
| `Cast_Water_Release` | 1.87 | 57 | no | **18** (0.60 s) | wind-up peak f11, wave crest f24, ripples f34 / f42 | flowing wave: sink low right, arms dip and draw back on an arc, then a rising S-wave of both arms through the front (release) to high-left (crest), left hand lags the right, two decaying ripples |
| `Cast_Earth_Charge` | 1.40 | 43 | loop | - | | deep horse stance, hands heave a boulder, weight moves left, right foot stomps at 66 % of the loop |
| `Cast_Earth_Release` | 2.27 | 69 | no | **18** (0.60 s) = stomp impact | wind-up peak f12 (right knee up, fists at the shoulders), lift peak f36 (hands overhead), tremor hang to f46 | heavy stomp and lift: weight on the left leg, knee hauled up, STOMP with pelvis squash + head rattle, slow heavy scoop-lift of both hands from the ground to overhead, hang, slow lower |
| `Cast_Wind_Charge` | 1.40 | 43 | loop | - | | arms orbit at chest height in opposite phases, torso and hips twist with them |
| `Cast_Wind_Release` | 1.73 | 53 | no | **15** (0.50 s) | wind-up peak f10, overshoot f21 | spinning sweep: crouch + coil -80 deg with both arms wide behind, hips lead the unwind, right arm whips through the front (arms in a wide line, 32 m/s), the body spins on to +80 deg with the feet pivoting, unwind |
| `Cast_Lightning_Charge` | 1.20 | 37 | loop | - | | right arm to the sky, jitter (stepped noise, zero at the loop point), body shudders |
| `Cast_Lightning_Release` | 1.60 | 49 | no | **19** (0.63 s) | compress f5, sky call f9 (tiptoe, both arms up, tremor hold to f14) | sharp skyward call then point: crouch, spring up on the toes with both arms flung skyward, tremor, arm snaps down in 4 frames into a lunging point, left arm thrown back, decaying recoil jitter |
| `Cast_Ice_Charge` | 1.20 | 37 | loop | - | | rigid, crossed forearms, flat hands, raised shoulders, frost tremor, slow chest breath |
| `Cast_Ice_Release` | 1.67 | 51 | no | **17** (0.57 s) | wind-up peak f10 (X guard at the face), frozen hold f17-34 (poses held on 3s) | crystalline precise push: forearms lift to an X guard on straight lines, rigid hold, 4-frame linear snap into a wide two-palm stop-push, left foot steps, frozen hold, thaw |
| `Cast_Light_Charge` | 1.60 | 49 | loop | - | | open palms in a V, chest lifted, slow swell |
| `Cast_Light_Release` | 2.13 | 65 | no | **23** (0.77 s) | gather peak f11, overshoot f27, floating hang to f36 | rising open-arm blessing: arms sweep down and cross low with a bowed head, knees bend, then both arms open in a rising arc into a wide V on tiptoe (release), overshoot, floating hang, arms lower with palms up |
| `Cast_Dark_Charge` | 1.40 | 43 | loop | - | | hunched, low claw creeping, left arm wrapped across the chest, slow predatory sway |
| `Cast_Dark_Release` | 1.93 | 59 | no | **27** (0.90 s) | claw reaches out f9, pull ends f21 (clench + shake f21-24), overshoot f30 | claw pulled inward then released: spread claw reaches out, slow-in pull to the chest with the body folding back, clench and shake, then a burst - both arms flung wide, chest snaps open |
| `Cast_AoE_Slam` (shared) | 2.20 | 67 | no | **27** (0.90 s) = fists hit the ground | crouch f8, takeoff f11, apex hang f17-21, rise f40 | deep crouch with fists swung back, leap with both fists overhead, apex hang, slam down into a deep knee-bend on landing with a shockwave shake; use for any element's ground nova |
| `Cast_Channel_Beam` (shared, loop) | 1.20 | 37 | loop | - | | braced lunge, right arm thrust at the target at eye level with strain vibration, left arm hauled back (archer silhouette, reads from the front), chest breathing; hold while the beam FX runs |

## ElementFX wiring (timing compatible with `scripts/vfx/element_fx.gd`)

Charge FX have no fixed length (`attach(el, &"charge", hand)` loops until `stop()`), one-shots and projectiles start on the release frame. The release frame is the VFX spawn frame (`t = release / 30.0` s after the clip starts).
Palm positions at the release frame are measured from the shipped GLB (armature space, +X = character's left, -Y = forward, metres, `tools/anim/casting/measure_casting.py`).

| clip | release f | palm_l | palm_r | ElementFX call at that frame |
|---|---:|---|---|---|
| Fire | 17 | (0.25, -0.82, 1.26) | (0.01, -0.85, 1.27) | `stop(charge_fx, 0.2)`; `ElementFX.projectile(&"fire", mid of the palms, target, 18.0)` (impact plays itself); the hands stay extended to f28 |
| Water | 18 | (0.28, -0.48, 1.02) | (0.03, -0.63, 1.27) | `ElementFX.beam(&"water", palm_r, target, 1.0, 0.6)` or `projectile`; the wave crest at f24 can drive a second `aoe(&"water", ...)` |
| Earth | 18 (stomp) | (0.31, -0.42, 0.71) | (-0.31, -0.42, 0.71) | `ElementFX.aoe(&"earth", ground_pos_ahead, r)` on the stomp; optional `play(&"earth", &"impact", pos)` at the lift peak f36 |
| Wind | 15 | (0.66, 0.20, 1.42) | (-0.18, -0.65, 1.36) | `ElementFX.projectile(&"wind", palm_r, target, 22.0)` (crescent) or `aoe(&"wind", pos)` (tornado); the sweep keeps rotating to f21 |
| Lightning | 19 | (0.51, 0.22, 1.18) | (-0.12, -0.83, 1.25) | at the sky call (f9) `aoe(&"lightning", target_ground)` telegraphs (0.28 s ring), at f19 `beam(&"lightning", palm_r, target, 1.0, 0.3)` then `chain(...)` |
| Ice | 17 | (0.34, -0.62, 1.52) | (-0.34, -0.62, 1.52) | `projectile(&"ice", mid, target)` or `aoe(&"ice", ...)`; frozen hold to f34 |
| Light | 23 | (0.67, 0.00, 1.79) | (-0.67, 0.00, 1.79) | `aoe(&"light", character_pos, r)` / `attach(&"light", &"aura", character)` (radiates from the body, not a projectile); hang to f36 |
| Dark | 27 | (0.76, 0.07, 1.17) | (-0.77, -0.05, 1.18) | `aoe(&"dark", pos)` or a burst `play(&"dark", &"impact", character_pos)`; the claw pull f11-21 is the moment to run an inward-sucking `charge` FX |
| AoE slam | 27 | (0.26, -0.71, 0.27) | (-0.26, -0.71, 0.27) | `ElementFX.aoe(el, ground_pos, radius)` on the contact frame; camera shake 0.3 s |
| Channel beam (loop) | - | - | - | `attach(el, &"charge", hand_r)` + `ElementFX.beam(el, hand_r_pos, target, width, seconds)` while the loop plays; `stop()` when leaving |

Attach charge FX to `hand_r` (`BoneAttachment3D` bone_name = `hand_r`); the palm centre is about 0.05 m further along the fingers. Two-hand clips (fire, ice, light, earth) can use one FX at the mid point or one per hand at scale 0.6.
Combined timing sheet (cast + ElementFX): `docs/anim/free_library/frames/casting_elements_v2/combined_Cast_Fire_Release_with_ElementFX.png`. **Honest note:** the bottom row is the existing ElementFX fire capture from
`docs/art/vfx_elements/frames/seq_fire.png` (placeholder character, Godot Movie Maker), composited by timing under the Blender frames; it is not a live engine render of the new clip (Godot was not imported in the tools worktree).

## Blend times (seconds)

| transition | blend |
|---|---|
| Idle / Combat idle -> `Cast_<El>_Charge` | 0.20 (0.15 for lightning / ice) |
| `Cast_<El>_Charge` -> `Cast_<El>_Release` | 0.05 (frame 0 poses are identical; use 0.0 at the loop boundary) |
| `Cast_<El>_Release` -> Idle | 0.20 |
| any `Cast_<El>_Charge` -> `Cast_Channel_Beam` | 0.15 |
| `Cast_AoE_Slam` in / out | 0.10 / 0.25 |
| cancel Charge (interrupted) -> Idle | 0.15 |

Root motion: none. Play in place (`Assets._ual_for` already disables the root track for the `animations_free` directory if the one-line fix in `HANDOFF_CODEX.md` is applied).
Hit-stop is not needed on casts; for the earth stomp and the AoE slam a 0.05 s freeze of the character on the release frame plus a short camera shake sells the weight.

## State -> clip table for Codex (paste)

```gdscript
const CAST_ELEMENT_CLIPS := {
	&"fire":      {"charge": &"Cast_Fire_Charge",      "release": &"Cast_Fire_Release",      "release_frame": 17, "length": 1.600},
	&"water":     {"charge": &"Cast_Water_Charge",     "release": &"Cast_Water_Release",     "release_frame": 18, "length": 1.867},
	&"earth":     {"charge": &"Cast_Earth_Charge",     "release": &"Cast_Earth_Release",     "release_frame": 18, "length": 2.267},
	&"wind":      {"charge": &"Cast_Wind_Charge",      "release": &"Cast_Wind_Release",      "release_frame": 15, "length": 1.733},
	&"lightning": {"charge": &"Cast_Lightning_Charge", "release": &"Cast_Lightning_Release", "release_frame": 19, "length": 1.600},
	&"ice":       {"charge": &"Cast_Ice_Charge",       "release": &"Cast_Ice_Release",       "release_frame": 17, "length": 1.667},
	&"light":     {"charge": &"Cast_Light_Charge",     "release": &"Cast_Light_Release",     "release_frame": 23, "length": 2.133},
	&"dark":      {"charge": &"Cast_Dark_Charge",      "release": &"Cast_Dark_Release",      "release_frame": 27, "length": 1.933},
}
const CAST_SHARED_CLIPS := {
	&"aoe_slam":     {"clip": &"Cast_AoE_Slam", "release_frame": 27, "length": 2.200},
	&"channel_beam": {"clip": &"Cast_Channel_Beam", "loop": true},
}
# start: play(charge, 0.2 blend) + ElementFX.attach(el, &"charge", hand_r_attachment)
# release: play(release, 0.05); after release_frame / 30.0 s: ElementFX.stop(charge_fx, 0.2); spawn projectile / beam / aoe (table above)
```

`UAL_FILES` line (`UAL_FREE_DIR` as in `HANDOFF_CODEX.md`): `UAL_FREE_DIR + "casting/UAL_Free_CastingElements.glb",`.
Better than a timer: add a method-call track at `release_frame / 30.0` on the duplicated Animation so the event follows `speed_scale` and the blend.

## Verification (stop-motion; side | 3/4 | front, Blender workbench, UAL mannequin, every clip read)

Sheets: `docs/anim/free_library/frames/casting_elements_v2/<clip>/sheet_00N.jpg` (2x4 tiles, sampled at 15 fps: **tile #N is frame 2N**, the time label is N/15 s; each tile is side | 3/4 | front, so the silhouette can be judged from three angles).
`motion.png` next to each is the frame-difference strip. Rendered from the shipped (key-reduced) GLB. Numbers: `measure_casting.py` (loop gap 0.000 m and hand-over gap 0.000 m for all eight pairs, lowest toe ball -0.009 m to +0.014 m).
The v1 sheets in `frames/casting_elements/` are kept for comparison.

| clip | read as magic with weight | anticipation -> release -> follow-through | silhouette (front / side / 3/4) | feet | verdict |
|---|---|---|---|---|---|
| Fire | yes: coil, tremor, drop-and-lunge, arms blast out | 11 f coil, 4 f snap, overshoot, held | side + 3/4 strong; the thrust foreshortens from the front but the coil, elbows and lean read | pass (left foot steps, recovers) | PASS |
| Water | yes: dip, S-wave, ripples | 11 f sink, wave crest f24, two ripples | wave arm sweeps across the face from the front (intended, reads as a wave); side / 3/4 good | pass | PASS |
| Earth | yes: knee-up, stomp squash, slow lift | clear and heavy; long low hold f18-28 is deliberate | front and 3/4 strong (wide legs, arms overhead) | pass (stomp foot replants) | PASS |
| Wind | yes: full-body spin, arms in a wide line | coil -80 -> whip -> +80 -> unwind | front reads as a rotating T; side shows the back at the crest | pass (feet pivot) | PASS |
| Lightning | yes: sky call on tiptoe, snap, lunge | compress, spring, tremor, 4 f snap, recoil | front + 3/4 strong (arm up, then left arm thrown back) | pass (heels lift) | PASS |
| Ice | yes: X guard, hard stop-push, frozen hold on 3s | rigid, precise, very different timing from the others | front strong (palms out), side + 3/4 fine | pass | PASS |
| Light | yes: bow, rising arc into a wide V on tiptoe | gather, rise, overshoot, floating hang | front strongest of all (open arms V), side leans back | pass | PASS |
| Dark | yes: reach, pull, clench, burst | claw reach f9, pull to f21, shake, burst f27 | front burst is a wide T, side folds hunched | pass | PASS (head throw-back at the burst is large, tune if the mesh chin clips) |
| AoE slam | yes: leap, hang, crash | crouch f8, apex f18, land f27 | strong from all three views | feet leave the ground f11-24, plant on landing | PASS (fists end 0.27 m above the ground at the slam: UAL arm length) |
| Channel beam | yes: lunge with strain vibration | loop | archer silhouette reads from the front | pass | PASS |

Known limits (honest list):

* Poses are authored from IK targets, not captured: secondary motion is procedural (overlap by lag, tremor and decaying jitter), not mocap. A polish pass on the game's character meshes may want hand / wrist tweaks.
* Arms reach 5-22 cm short of a few targets (overhead, wide-open and floor-contact poses): the arm is then fully straight, which is the intended read; the numbers are in the build log (`REACHWARN`).
* Fire: the thrust points 8 deg left of straight ahead (the torso ends its yaw at +8); aim by rotating the character, the FX direction is target - palm anyway.
* Godot was not run for this pass: the GLB follows the same export path as v1 and the traversal library; import, `_Loop` stripping and the `check_unique_clips.py` guard (clean: 220 clips, 0 problems) are the only checks.
* Wrist / finger poses were verified on the blocky mannequin only.
