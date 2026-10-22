# Polish review: stop-motion re-read of kicks, defense, acrobatics, reactions and four KayKit libraries + traversal rebuild

Method: every clip GLB was put on the UAL mannequin in Blender (workbench, no Godot): `kingdom/tools/anim/polish/render_clips.py` renders side + front per frame
(camera follows the pelvis over a ruled floor, 1 m thick / 0.5 m thin lines) and writes metrics (planted-foot slide, floor clearance, loop gap, biggest joint jump, leg straightness, facing);
`make_sheets.sh` tiles them with `tools/qa/video_to_sheets.sh` (width 480 per tile, side | front). Sheets: `frames/polish/<library>/<clip>/`
(`before_sheet_00N.jpg` = before, `sheet_00N.jpg` / `final_sheet_00N.jpg` = after, `motion_sheet.jpg` = the single 8-9 fps sheet of an unchanged clip; JPEG q10 to keep the repo small, about 32 MB in total).
Fix tools (all under `kingdom/tools/anim/polish/`, `kingdom/tools/anim/traversal/`): `glb_fk.py` (numpy FK + two-bone leg IK), `cmu_fix.py` / `cmu_mesh_floor.py` (defense, reactions), `cmu_acro_*.py` (acrobatics),
`kaykit_polish.py` / `kaykit_straighten.py` (KayKit), `edits/kicks_edit.json` (kicks trims via `glb_edit_clips.py`), `author_traversal_v2.py` + helpers (traversal). Nothing in Godot was run, no `.import` file was touched.
Honesty notes: several sheet reads returned "request limit" and were re-read; for the defense libraries `MA_Block_L_A/B/C` the before-sheets were never seen, they were judged from the after-sheets and metrics. The KayKit agent read the after-sheets of the main changed clips, not every floor-only shift (those were checked through the metrics and the before-sheets).

## Totals

| library | clips before | pass unchanged | fixed (kept) | rejected / deleted | after |
|---|---:|---:|---:|---:|---:|
| animations_free/kicks | 11 | 8 | 3 (trim) | 0 | 11 |
| animations_free/defense | 8 | 4 | 3 trimmed + 1 floor (Guard_Boxing_Loop stays partial) | 0 | 8 |
| animations_free/acrobatics | 20 | 0 | 16 (1 partial: HandstandKicks) | 4 | 16 |
| animations_free/reactions | 9 | 0 | 9 (Fall_Slip_Back partial) | 0 | 9 |
| kaykit_combat_reactions | 14 | 7 | 7 | 0 | 14 |
| kaykit_movement_ext | 17 | 4 | 13 (1 rename) | 0 | 17 |
| kaykit_ranged | 14 | 6 | 8 | 0 | 14 |
| kaykit_undead | 9 | 0 | 7 (Collapse, Resurrect partial) | 2 | 7 |
| traversal_authored | 13 | 0 | 13 rebuilt (Ride_Trot partial) + 1 added (`Vault_Low_B`) | 0 | 14 |

## Renames and deletions (complete list, for the Codex handoff)

- RENAME `Kay_Crouch_Idle_Loop` -> `Kay_Crouch_Walk_Loop` (kaykit_movement_ext; it is a 1 m stride cycle). `tools/anim/build_handoff.py`, `tools/anim/free2/cfg_kk_movement_ext.json` and `HANDOFF_CODEX.md` still use the old name.
- DELETE `MA_Acro_Cartwheel_E`, `MA_Acro_Flip_A`, `MA_Acro_FrontHandFlip_A`, `MA_Acro_MonkeyBackflip` (animations_free/acrobatics; `clip_tables.md`, `make_free_cfgs.py`/`cfg_free_acrobatics.json`, HANDOFF still list them).
- DELETE `Kay_Undead_Awaken_Floor`, `Kay_Undead_Rise_Ground` (kaykit_undead).
- ADD `Vault_Low_B` (traversal_authored, mirrored right-side vault). No traversal clip was renamed.
- Length changes (sidecars updated; HANDOFF times/hit frames of these are stale): kicks `MA_Kick_JumpHigh_A` 2.70 -> 2.25 s, `MA_Kick_JumpHigh_B` 2.60 -> 1.85 s (start 0.75 s cut), `MA_Kick_Swing_R` 2.17 -> 1.15 s (start 0.35 s cut); defense and reactions trims, acrobatics trims, `Vault_Low` 1.4 -> 2.0 s, KayKit trims: see the per-library sections below.
- Traversal contract change: rung heights are 0.3k (hand rungs 1.5 / 1.8 m instead of 1.45), ledge hang pelvis 1.125 m.

## Vault before / after

Before: a floating pose with no run-up, hands never touched the box, legs crossed, no landing. After (`Vault_Low`, 2.0 s, 61 frames, root Y 2.7 m): run stride, crouch/gather, take-off plant, both palms on the box top (world-fixed f17-27), hip arc 0.3 m over the top, legs swing left, landing absorb, two recovery steps. Box penetration 0.0 cm on the solved rig, checked over three sheet iterations; caveats: stiff wide arms in the landing, one calf snaps 0.36 m in one frame at f30. Sheets: `frames/polish/traversal_authored/Vault_Low/` (`iter3_keyframes_closeup.jpg`).

## Kicks (animations_free/kicks/UAL_Free_Kicks.glb)

Sheets `frames/polish/kicks/<clip>/`. Knee note: n/a (CMU on UAL proportions, legs straight when planted, `leg_straight` 0.88-0.91).

| clip | before verdict | action | after verdict | notes |
|---|---|---|---|---|
| MA_Kick_Front_R_Low / _Mid / _High | pass: guard, chamber, snap, retract, back in guard; support foot pivots (metric slide 13-27 frames = the pivot) | none | pass | 1.8-2.2 s, feet on floor (min z 0.03-0.04), ends in guard, hips yaw drift up to 25 deg |
| MA_Kick_Front_L_Low / _Mid / _High | pass, same | none | pass | mirror behaviour; `L_High` first frame duplicated in the sheet only |
| MA_Kick_Jump_R / _L | pass with note: starts mid run stride, jump-kick at 0.4-0.5 s, lands side-on (hips yaw 78 deg to the run direction) | none | pass with note | 1.23 s, 1.2 m root travel -Z; trigger from a run, blend out 0.3 s, expect a side-on end pose |
| MA_Kick_JumpHigh_A | fail: 2.7 s, ends in a walk-away with the body turned 150 deg, 2.2 m travel | trim to 0-2.25 s (ends in the landing recovery) | pass with note | spin kick at 1.5 s; end pose faces about 150 deg away from the start, rotate the actor after it; 1.8 m travel |
| MA_Kick_JumpHigh_B | fail: 0.75 s frozen standing start, ends mid-crouch turned 180 deg | trim to 0.75-2.6 s | pass with note | anticipation step at 0.1 s, kick 0.9-1.0 s, ends in the landing crouch (pelvis low, back to the start direction), blend out 0.3 s |
| MA_Kick_Swing_R | fail: slouched, 0.4 s idle, ends in a 1 s frozen pose with the foot trailing | trim to 0.35-1.5 s | pass (slouched style) | wind-up 0.3 s, punt kick at 0.7 s, follow-through; head hangs forward (source style) |

## Codex handoff paragraph (all libraries)

All changed GLBs keep their file names, clip names (except the list above) and the `*.clips.json` schema; `seconds`/`frames` in the sidecars are current. Play the CMU kicks / acrobatics as one-shots with 0.15-0.2 s blend-in and 0.2-0.3 s blend-out; jump kicks and cartwheels end turned relative to the start (rotate the actor). Falls end lying with the mesh on the floor, get-ups end in the UAL idle stance (no blend-out needed). KayKit loops are in place (match the animation speed to the ground speed), one-shots list their blend-out in the tables, the skeleton clips are for undead enemies only, and squats keep their knee bend by design. Traversal: use the new rung / hang heights above, `Vault_Low` carries 2.7 m on `root`. Re-check the Codex tables (`clip_tables.md`, HANDOFF times, hit frames) for every changed length and for the deleted / renamed clips listed above. Measured hit / release frames of the kicks in HANDOFF are still valid for the unchanged clips; for the three trimmed kicks subtract the trim start (JumpHigh_B 0.75 s, Swing_R 0.35 s).


# Per-library detail (from the reviewers)

## Defense + reactions (CMU, UAL skeleton) - stop-motion re-review

Sheets: `frames/polish/defense/<clip>/` and `frames/polish/reactions/<clip>/` (`before_sheet_00N.jpg` = state before, `sheet_00N.jpg` = after; each tile = side | front view, 480 px wide, floor grid 1 m thick / 0.5 m thin).
Scripts: `kingdom/tools/anim/polish/cmu_fix.py` (trim, root re-zero, idle blend, floor fix), `cmu_mesh_floor.py` (skinned-mesh lowest point per frame), `cmu_run_all.sh` (rebuild from pristine GLBs + render), `cmu_sheets.sh`.
"Floor" below = the skinned mannequin mesh (not only the bones); before the fix it dipped up to 6-10 cm under z=0 in falls / get-ups, after the fix `min z >= -0.001 m` in every clip.
Fixes were done with three operations only: trim to the useful window, raise the pelvis per frame (smoothed, never lowering) so the mesh stays on the floor, and (get-ups) append 0.9 s that blends the last pose into the UAL `Idle_Loop` stance with two-bone leg IK on both feet.
Foot pinning of the planted feet during the get-up crawl was NOT done (slide frames remain, see notes).

### defense (8 clips, 0 renamed, 0 deleted)

| clip | before | action | after | notes |
|---|---|---|---|---|
| MA_Block_L_A | pass (end 4 deg yaw, small stance shift) | none | pass | 1.17 s, arm comes up and is HELD at the end (no recovery); needs a blend-out |
| MA_Block_L_B | pass | none | pass | 0.80 s, starts in the block, relaxes to guard: use as "block release" or reverse in code |
| MA_Block_L_C | pass (end 1 deg) | none | pass | 1.03 s, high block held at the end, blend-out needed |
| MA_Block_R_A | pass with 0.3 s static stand before the block | trim to 0.25-1.13 s | pass | 0.88 s, block held at the end; hip ends 24 deg off (mirrored stance), acceptable |
| MA_Block_R_B | pass (long, two-arm guard weave) | none | pass | 1.53 s, start and end in guard with raised right arm, feet shuffle 15 slide frames but under 0.15 m of drift |
| MA_Guard_Boxing_Loop | FAIL: deep crouch (pelvis 0.74, legs 0.66 straight), 33/32 slide frames, mesh 2.4 cm below floor | floor lift only (max 2.4 cm) | PARTIAL: loop is closed (gap 0.00), floor ok, but still a low bouncing boxing stance | kept as a "combat stance" not a general idle; footwork bounce cannot be pinned without rebuilding the steps |
| MA_Dodge_Duck | FAIL-ish: 3.4 s with 0.7 s static crouch first | trim to 0.55-3.40 s | pass | 2.85 s: anticipation 0.4 s, duck to pelvis 0.47 (0.4-1.6 s hold, head covered), recovery to a low guard; ends low (pelvis 0.89) |
| MA_Evade_AttackerCover | FAIL-ish: 0.6 s idle first, shuffle | trim to 0.45-2.30 s | pass | 1.85 s, cover the head then shuffle away, ends in a guard with 0.4 m root travel (root track) |

### reactions (9 clips, 0 renamed, 0 deleted)

| clip | before | action | after | notes |
|---|---|---|---|---|
| Fall_Forward_Knockdown | mesh 6 cm below floor, hip flips 168 deg | floor lift (max 6 cm) | pass | 2.0 s, trip, fall on the face, lies on the floor at 1.5 s (pelvis 0.25 m = body thickness); ends prone |
| Fall_Slip_Back | FAIL: 4 s, 1.7 m of walking before the slip, 1 s frozen legs-in-air tail, mesh 10 cm below floor | trim 0.8-3.0 s, floor lift (max 10 cm) | PARTIAL pass | 2.2 s (run-step, slip at 1.0 s, feet up, land); ends with legs still in the air, torso on the floor (pelvis 0.30), not fully flat; 1.5 m root travel |
| Fall_RugPull_Back | FAIL: no foot planted, lying frozen from 0.9 s, mesh 4 cm below floor | trim 0-1.2 s, floor lift (max 4 cm) | pass | 1.2 s, legs swept forward, lands on the back at 0.5 s and lies on the floor, ends lying (pelvis 0.11) |
| Fall_BackflipTwist | FAIL: 1.7 s of standing / arm swing before the flip, mesh 6 cm below floor | trim 1.7-3.5 s, floor lift (max 6 cm) | pass | 1.8 s, crouch, back flip, lands on the ground at 1.4 s in a rolled-out lying pose (pelvis 0.22); 0.5 m root travel |
| GetUp_FaceDown_A | pass except 1.4 s hunched wait at the end, mesh 3 cm below floor, ends 0.80 hunched | trim 0-3.4 s, floor lift, 0.9 s idle blend | pass | 4.3 s, push-up, crawl, kneel, stand, ends in the UAL idle stance (pelvis 0.87), 0.87 m root travel; 27 slide frames |
| GetUp_FaceDown_B | same, mesh 4.6 cm below floor | trim 0-3.0 s, floor lift, idle blend | pass | 3.9 s, faster version, ends in idle, 0.63 m travel; slide frames 64 (crawl feet + blend steps), most under 0.3 m/s |
| GetUp_Side | 6.5 s, hunched wait at the end, mesh 7 cm below floor | trim 0-4.8 s, floor lift, idle blend | pass | 5.7 s (long): sit up, squat, stand; ends in idle, 0.51 m travel |
| GetUp_Back_A | 6.27 s, hunched wait at the end, mesh 4.5 cm below floor | trim 0-4.2 s, floor lift, idle blend | pass | 5.1 s, ends in idle, 0.68 m travel |
| GetUp_Back_B | 5.57 s, hunched wait at the end, mesh 3 cm below floor | trim 0-3.8 s, floor lift, idle blend | pass | 4.7 s, ends in idle, 0.68 m travel |

Counts: defense 7 pass (4 unchanged, 3 trimmed) + 1 partial (Guard_Boxing_Loop), 0 rejected; reactions 8 pass + 1 partial (Fall_Slip_Back), 0 rejected.

### Renames / deletions
None. Every clip keeps its name; only lengths changed (sidecars updated: `seconds`, `frames`, `idle_blend_s`, `trimmed_from_s`).

### Known limits
- Get-up crawl steps still slide (foot pinning was not applied); the 0.9 s idle blend steps the feet with IK, so slide frames rose for GetUp_FaceDown_B.
- Root travel of the get-ups (0.5-0.9 m) is on the `root` track; falls: Slip_Back 1.5 m, BackflipTwist 0.5 m.
- Fall clips end lying, not in the same pose family: none is guaranteed to line up with a specific get-up, blend over 0.3-0.5 s.

### Codex handoff (defense + reactions)
Play `MA_Block_*` as one-shot hit-block reactions (0.8-1.5 s, block pose held at the end of L_A, L_C, R_A: cross-fade back to idle over 0.2 s; L_B is the release). `MA_Guard_Boxing_Loop` is a low boxing stance (looping, pelvis 0.74), use only while in a fight-ready state, not as the default idle. `MA_Dodge_Duck` (2.85 s) and `MA_Evade_AttackerCover` (1.85 s) are long for a dodge: consider speed 1.4-1.6 and blend out at 60 % of the clip. Falls are one-shots that end lying on the floor with the mesh at z 0 (the pelvis joint is 0.11-0.30 m above the floor): freeze on the last frame (or use the ragdoll) and start a get-up: `GetUp_Back_*` after `Fall_RugPull_Back` / `Fall_Slip_Back`, `GetUp_FaceDown_*` after `Fall_Forward_Knockdown` / `Fall_BackflipTwist`, `GetUp_Side` for any sideways lying pose. All five GetUp clips start lying and END in the UAL idle stance (feet under the hips, pelvis 0.87 m), so they need no blend-out, only a blend-in of 0.2 s. They carry 0.5-0.9 m of root travel on the `root` track (enable root motion or the character teleports back by that amount); falls carry 0.5-1.5 m (`Fall_Slip_Back` 1.5 m, `Fall_BackflipTwist` 0.5 m).

## Acrobatics (UAL_Free_Acrobatics.glb) - stop-motion re-review

Method: every before-sheet and every final sheet was read (3x4 tiles, side | front, sheets in `frames/polish/acrobatics/<clip>/`: `before_sheet_001.jpg`, `sheet_00N.jpg`).
Fix script: `kingdom/tools/anim/polish/cmu_acro_fix.py` (run from the git HEAD GLB; it is NOT idempotent, re-run only with `--src <original> --dst <out>`), helpers `cmu_acro_lib.py`, `cmu_acro_ik.py` (two-bone leg/arm IK), `cmu_acro_splice.py` (HandstandKicks close-out), `cmu_acro_analyze.py` (floor / contact audit), `cmu_acro_sheets.sh`.
Common fixes: trim to a clean start/end, root rebased to the origin, toe bones that curled 40-70 degrees below the floor straightened (the -4..-7 cm "dips" were toes), per-frame vertical offset from the planted sole/palm points (floor clearance now >= -1 cm everywhere, no float during contact), planted-segment IK pinning of soles/palms.
Unchanged by design: 30 fps keys, skeleton, no clip renamed.

| clip | before | action | after | notes |
|---|---|---|---|---|
| MA_Acro_HandSpinKick | fail: 0.4 s static hold, sole 4-10 cm below floor, right foot skids 14 frames | trimmed 3.8 -> 3.4 s, ground, pin | pass | starts standing, ends in a neutral walk stance turned 18 deg; 2.25 m travel +X (kick/spin sideways), drifts to the right |
| MA_Acro_Cartwheel_A | fail: palms/feet float 3-8 cm, 0.4 s dead tail, ends turned -114 | trimmed 2.77 -> 2.53 s, ground, pin | pass with note | wheel goes forward (+Z 2.1 m); the run-in is a fighting stance and it ends turned about -113 deg (facing the right side) in a guard stance: readable but not neutral |
| MA_Acro_Cartwheel_B | fail: as A | trimmed 2.63 -> 2.40 s, ground, pin | pass with note | same as A, ends -118 deg |
| MA_Acro_Cartwheel_C | fail: as A, left foot slides 2 frames | trimmed 2.9 -> 2.6 s, ground, pin | pass with note | same as A, ends -114 deg |
| MA_Acro_Cartwheel_D | fail: hands float 3-5 cm, long slow lead-in | trimmed 3.6 -> 3.4 s (0.2 s off the start), ground, pin | pass | cleanest cartwheel: ends 19 deg turned in a stance; 2.6 m forward |
| MA_Acro_Cartwheel_E | fail: 8 m/s foot skating in the run-in, pelvis dips to 0.38 m, wobbly wheel | REJECTED (deleted) | - | not fixable by trimming |
| MA_Acro_Backflip_A | fail: toe 7 cm under floor, feet unplanted 0.33 | ground, toe fix, pin | pass | 1.47 s; clean squat -> flip -> landing absorb; ends upright, slightly forward lean; 0.46 m travel |
| MA_Acro_Backflip_B | fail: 8 frames of hold, ends yawed -37 | trimmed 1.53 -> 1.27 s, unwound the yaw (pelvis pivot) | pass | ends facing forward; lands with a sloppy stumble step (0.3 s), settle before chaining |
| MA_Acro_Backflip_C | fail: hold, toe -7 cm | trimmed 1.4 -> 1.20 s, ground | pass | ends standing with a slight forward reach, 1.2 m travel |
| MA_Acro_Somersault_Back | fail: pelvis 0.15 m, head -2 cm, toes -7 cm, skids 3.9 m/s | trimmed 3.5 -> 3.3 s, ground, pin | pass with note | long forward roll (ground roll, 1.9 m), ends upright; a foot still swaps quickly at 2.4-2.9 s |
| MA_Acro_Handspring | fail: frame 1 pop (2 m jump, hip yaw -116 at frame 0) | dropped first frame, ground, pin | pass | 1.37 s; starts mid-run-up (pelvis about 1 m off root, by design), hands plant, lands in a jog. Use as a run-in flip only |
| MA_Acro_FrontHandFlip_A | fail: truncated, ends inverted with no landing | REJECTED (deleted) | - | FrontHandFlip_B is the complete take |
| MA_Acro_FrontHandFlip_B | fail: 1 s static hold, toes -2 cm | trimmed 3.0 -> 2.0 s, ground, pin | pass | arms up -> handspring flip -> lands with arms up (celebration pose at both ends) |
| MA_Acro_SideFlip | fail: 0.6 s static hold, toe -5 cm, 5 m/s slide | trimmed 2.3 -> 1.67 s, ground, pin | pass with note | ends turned -25 deg, weight shift after landing; 1.2 m diagonal travel |
| MA_Acro_FlipForward_Hands | fail: toe -4 cm, sliding feet | ground, pin | pass | 1.5 s, clean, ends standing in a neutral pose; only 0.2 m travel |
| MA_Acro_BackflipBackOnHands | fail: pelvis 0.38 m, hands and feet not planted | trimmed 2.1 -> 2.0 s, ground, pin | pass with note | actually a hands-down twisting aerial, name misleading; ends in a fighting stance |
| MA_Acro_HandstandKicks | fail: 9.5 s, ends in handstand, 19/28 slide frames | rebuilt: stand -> handstand -> kick cycles (frames 0-131) then the entry played backwards after a pose-matched cross-fade (0.84 pose distance) | partial pass | 7.1 s, starts AND ends in the same standing pose; handstand section is good (hands planted, 0.2 m drift); the stand-in/out shuffle still has foot skate up to 0.5-0.7 m (feet are not pinned there) - use the handstand section, hide the shuffle |
| MA_Acro_KickFlip | fail: 4 cm dips, stumbling landing | ground, pin | pass with note | kick -> flip -> sit-up landing (pelvis 0.10 m, sitting) -> stand, ends in a guard stance |
| MA_Acro_Flip_A | fail: 5.5 s idle + stumble + twisting aerial, ends turned 75 deg mid-stagger | REJECTED (deleted) | - | |
| MA_Acro_MonkeyBackflip | fail: crawl then a backflip that ends inverted on the hands, 4.9 m/s skating | REJECTED (deleted) | - | |

Counts: 16 kept and all changed (8 pass, 7 pass with a note, 1 partial pass = HandstandKicks), 4 rejected and deleted, 0 renamed.
Deleted clips (sidecar updated): `MA_Acro_Cartwheel_E`, `MA_Acro_Flip_A`, `MA_Acro_FrontHandFlip_A`, `MA_Acro_MonkeyBackflip`.

### Codex handoff
Use the library as one-shot "special" moves (dodge-flip / evade / finisher), not looping locomotion. Blend in 0.15-0.2 s from idle/guard and out 0.2-0.3 s (0.3 s after Backflip_B, SideFlip). Root travel is carried on the `root` track (all clips start at the origin): Backflip_A/B/C travel 0.5/1.4/1.2 m back (-Z), Cartwheel_A..D 2.0-2.6 m forward (A-C also drift 0.5-1.1 m sideways and end turned about 115 deg, so rotate the character after them), Handspring 2.7 m and FrontHandFlip_B 1.6 m forward, Somersault_Back 1.9 m back, SideFlip about 1.2 m diagonal, FlipForward_Hands 0.2 m. Use root motion, or a ground clamp; the pelvis dips are intentional in the roll/sit-up clips. End poses: standing/neutral for FlipForward_Hands, Backflip_A/C, Handspring (jog); guard stance for Cartwheel_A-C, BackflipBackOnHands, KickFlip; arms-up for FrontHandFlip_B; HandstandKicks starts and ends in the same stand pose.

## KayKit clip libraries (UAL skeleton) - stop-motion re-review

Sheets: `frames/polish/kaykit_<library>/<clip>/` (`before_sheet_00N.jpg` = before, `sheet_00N.jpg` = after or, for clips left alone, the ONE motion sheet at 9 fps; short clips (<= 0.7 s) use the 15 fps sheet; each tile = side | front view, 480 px wide, floor grid 1 m thick / 0.5 m thin; JPEG q5 to keep the repo small). `REJECTED_*` folders hold only the before sheets of the deleted clips.
Scripts: `kingdom/tools/anim/polish/kaykit_polish.py` (per-clip table, restores the four GLBs from git HEAD first, so it is reproducible), `kaykit_straighten.py` (floor fix + pelvis raise with pinned ankles and two-bone leg IK), `render_clips.py` / `make_sheets.sh` (review renders; render_clips now resets bones a clip has no track for, so clips no longer inherit the previous clip's pose).
Knee metric = hip-ankle distance / leg length, median over frames where a foot is planted (1.0 = straight, < 0.85 visibly bent). Before the fixes most KayKit clips already stood at 0.90-0.99 (the retarget `hip_scale` 3.12 does its job); the bent ones were the fighting-fist stance (0.81) and the skeleton clips (0.58-0.81), plus deep squats that are the pose itself (jump landings, sneak, crouch, taunt wind-up).
What could NOT be fixed: raising the pelvis cannot open the knees of a squat without changing the pose, so squats, sneaks and the skeleton hunch keep their bend (documented per clip); the foot skid of the two undead death clips remains.

### kaykit_combat_reactions (14 clips before, 14 after)

| clip | before verdict | action | after verdict | knee note and recommended usage |
|---|---|---|---|---|
| Kay_Hit_React_A | pass (feet 1 cm above the floor) | floor -1 cm | pass | legs planted 0.96 -> 0.96 (all-frame mean 0.96). 0.67 s one-shot, in place, recoil 5 cm; blend out 0.1 s |
| Kay_Hit_React_B | pass (feet 1.8 cm under the floor) | floor +1.8 cm | pass | legs planted 0.94 -> 0.95 (all-frame mean 0.86). 0.87 s one-shot, staggers back 0.11 m on `root`; blend out 0.15 s |
| Kay_Death_Fall_B | FAIL: on the ground the hips stay 0.32 m up, the corpse hovers over the floor (2.1 s) | drop: pelvis lowered 0.15 m between 1.1 and 1.9 s with ankle-pinned leg IK, floor +2 cm | pass: lies flat, hips 0.17 m (body thickness), lowest sole on z=0 | legs planted 0.85 -> 0.84 (all-frame mean 0.84). 0.77 m root travel backwards, then keep the last pose (no loop); play once |
| Kay_Block_Raise | pass | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.94). 1.07 s, block raised then held at the end: chain into `Block_Hold_Loop` |
| Kay_Block_Hold_Loop | pass (loop gap 0.000) | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.93). loop, in place; upper-body guard, the arm reaches out (shield side) |
| Kay_Block_Impact | pass (0.1 m recoil) | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.94). 1.07 s one-shot from the hold pose, returns to the hold pose |
| Kay_Block_Counter | FAIL-minor: the lunge floats 5.6 cm above the floor for the whole clip | floor -5.6 cm | pass | legs planted - -> 0.94 (all-frame mean 0.88). 1.07 s lunge attack; 0.04 m root travel; the feet step during the lunge (metric slide 3 m/s) |
| Kay_Stance_2H_Idle_Loop | pass (1.2 cm floating) | floor -1.2 cm | pass | legs planted 0.93 -> 0.92 (all-frame mean 0.90). loop, in place, two-handed ready stance |
| Kay_Stance_Fists_Idle_Loop | FAIL-minor: deep lunge stance, knees 0.81, feet 1.6 cm under the floor | straighten (pelvis +0.11 m with pinned ankles, target 0.92) + floor | pass: stance keeps its shape, legs 0.92, no slide | legs planted 0.81 -> 0.92 (all-frame mean 0.89). loop, in place, boxing stance; still a wide staggered stance by design |
| Kay_Dodge_Fwd | pass (feet 1.6 cm under the floor) | floor +1.6 cm | pass | legs planted 0.95 -> 0.97 (all-frame mean 0.72). 0.4 s forward hop, 0.49 m on `root`; ends mid-motion, blend out 0.15 s |
| Kay_Dodge_Back | pass: back-hop, airborne the whole clip (feet 8-12 cm above the floor) | none (a floor fix would sink the take-off) | pass | legs planted - -> - (all-frame mean 0.86). 0.4 s, 1.22 m on `root`, flight phase by design; blend out 0.15 s |
| Kay_Dodge_L | pass (side step, 1.03 m; the metric slide 3.8 m/s is the push-off dash) | none | pass | legs planted 0.93 -> 0.93 (all-frame mean 0.83). 0.4 s, 1.03 m on `root` (+x); blend out 0.15 s |
| Kay_Dodge_R | pass (mirror of L) | none | pass | legs planted 0.93 -> 0.93 (all-frame mean 0.83). 0.4 s, -1.03 m on `root`; blend out 0.15 s |
| Kay_Attack_2H_Spin_Long | pass (360 spin, the feet pivot: slide flags are the pivot) | none | pass | legs planted 0.90 -> 0.90 (all-frame mean 0.91). 1.6 s, ends facing forward again; 0.13 m root travel; blend out 0.2 s |

### kaykit_movement_ext (17 clips before, 17 after)

| clip | before verdict | action | after verdict | knee note and recommended usage |
|---|---|---|---|---|
| Kay_Crouch_Walk_Loop | FAIL: named idle but it is a crouched STRIDE cycle (1 m stride), and the soles are 9.4 cm under the floor | rename Crouch_Idle_Loop -> Crouch_Walk_Loop + floor +9.4 cm | pass: clean loop (gap 0.007), feet on the floor | legs planted 0.83 -> 0.77 (all-frame mean 0.76). in-place cycle; the 1.0 m stride needs about 1.9 m/s ground speed to not skate; knees bent by design (crouch) |
| Kay_Sneak_Walk_Loop | pass: low sneak stride, knees bent by design | none | pass | legs planted 0.89 -> 0.89 (all-frame mean 0.77). 2.13 s in-place loop, ~1.1 m/s ground speed; not a normal walk |
| Kay_Walk_Back_Loop | pass (soles 4 cm under the floor) | floor +4.2 cm | pass | legs planted 0.98 -> 1.00 (all-frame mean 0.80). 1.07 s loop, ~1.3 m/s backwards |
| Kay_Run_Strafe_L_Loop | pass (2 cm under the floor; one calf whip 43 deg/frame) | floor +2 cm | pass | legs planted 0.98 -> 0.98 (all-frame mean 0.78). 0.8 s loop, ~2 m/s sideways (-x) |
| Kay_Run_Strafe_R_Loop | pass (mirror) | floor +2 cm | pass | legs planted 0.97 -> 0.97 (all-frame mean 0.78). 0.8 s loop, ~2 m/s sideways (+x) |
| Kay_Walk_Kay_A_Loop | pass, but it is a JOG with high knee lift (2.4 cm under the floor, calf snap 60 deg/frame) | floor +2.4 cm | pass | legs planted 0.98 -> 0.99 (all-frame mean 0.72). 1.07 s loop, ~1.3 m/s |
| Kay_Walk_Kay_B_Loop | pass | none | pass | legs planted 0.99 -> 0.99 (all-frame mean 0.76). 1.07 s loop, ~1.5 m/s |
| Kay_Walk_Kay_C_Casual_Loop | pass (3.3 cm under the floor) | floor +3.3 cm | pass | legs planted 0.95 -> 1.00 (all-frame mean 0.74). 1.6 s relaxed walk loop, ~0.8 m/s |
| Kay_Run_Kay_A_Loop | pass (nearly straight legs) | floor +0.9 cm | pass | legs planted 1.00 -> 1.00 (all-frame mean 0.83). 0.8 s run loop, ~3.1 m/s; best of the three runs |
| Kay_Run_Kay_B_Loop | pass-with-note: fast run, the trailing calf whips 90 deg in ONE frame (0.2 s and 0.55 s), 2 cm under the floor | floor +2 cm | pass-with-note (the whip is in the source; Godot interpolates it) | legs planted 0.71 -> 0.71 (all-frame mean 0.80). 0.8 s loop, ~2.7 m/s; prefer Run_A |
| Kay_Jump_Start_Kay | pass (crouch launch, floats 2.7 cm) | floor -2.7 cm | pass | legs planted - -> 0.95 (all-frame mean 0.73). 0.6 s one-shot, ends airborne; chain into Jump_Air |
| Kay_Jump_Air_Kay_Loop | pass (airborne loop, gap 0.000) | none | pass | legs planted - -> - (all-frame mean 0.69). 1.07 s loop, tucked legs (0.69 by design, in the air) |
| Kay_Jump_Land_Kay | pass (floats 2 cm) | floor -2 cm | pass | legs planted 0.96 -> 0.96 (all-frame mean 0.69). 0.67 s one-shot, absorbs the landing and stands up |
| Kay_Jump_Short_Kay | pass (floats 3 cm) | floor -3 cm | pass | legs planted - -> 0.95 (all-frame mean 0.71). 1.17 s full hop, in place (0 root travel): move the body in code |
| Kay_Jump_Long_Kay | pass (2 cm under the floor; deep landing squat, legs 0.52 by design) | floor +2 cm | pass | legs planted 0.74 -> 0.63 (all-frame mean 0.70). 2.33 s full leap with a 0.4 s squat, in place; Start/Air/Land in one |
| Kay_Idle_Kay_A_Loop | pass: near-static idle (breathing only) | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.95). 1.07 s loop |
| Kay_Idle_Kay_B_Loop | pass (2.6 cm floating); contains two identical 1.07 s cycles | floor -2.6 cm | pass | legs planted - -> 0.97 (all-frame mean 0.90). 2.13 s idle loop, gap 0.000 |

### kaykit_ranged (14 clips before, 14 after)

| clip | before verdict | action | after verdict | knee note and recommended usage |
|---|---|---|---|---|
| Kay_Bow_Idle_Loop | pass | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.95). 1.57 s loop, body turned about 33 deg (archer stance): rotate the actor toward the target side |
| Kay_Bow_Aim_Idle_Loop | pass (1 cm under the floor) | floor +2.6 cm | pass | legs planted 0.94 -> 0.94 (all-frame mean 0.95). 1.83 s loop, body yaw about -40 deg, breathing |
| Kay_Bow_Draw | pass, but 5 frozen frames at the end | trim to 1.2 s | pass | legs planted 0.94 -> 0.95 (all-frame mean 0.94). 1.2 s, ends at full draw: hold the last pose, then Bow_Release; 0.18 m root travel |
| Kay_Bow_Release | pass (release + recovery) | none | pass | legs planted 0.95 -> 0.95 (all-frame mean 0.92). 1.33 s one-shot, starts at full draw |
| Kay_Bow_Draw_Up | pass, but 12 frozen frames at the end | trim to 1.03 s | pass | legs planted 0.96 -> 0.96 (all-frame mean 0.96). 1.03 s, aiming up (arrow arc); hold the last pose |
| Kay_Bow_Release_Up | pass (2 cm under the floor) | floor +2.1 cm | pass | legs planted 0.88 -> 0.88 (all-frame mean 0.90). 1.37 s, release aiming up |
| Kay_Run_Holding_Bow_Loop | pass-with-note (same legs as Run_B: calf whip) | floor +2 cm | pass-with-note | legs planted 0.71 -> 0.71 (all-frame mean 0.80). 0.8 s loop, ~2.7 m/s; bow held low |
| Kay_Pistol_Aim_Loop | FAIL: loop gap 0.575 m (0.37 s raise from the ready pose, then a frozen hold), 0.2 m root drift | trim 0.37-1.07 s + 4 frame loop blend | pass: loop gap 0.000, static hold (no breathing: add procedural sway) | legs planted 0.99 -> 1.00 (all-frame mean 0.97). 0.7 s loop; body yaw about 35 deg; the raise now only exists in `Pistol_Shoot` |
| Kay_Pistol_Shoot | pass with a caveat: starts in the neutral pose and turns into the aim pose in 0.3 s, no visible recoil | none | pass-with-note | legs planted 0.99 -> 0.99 (all-frame mean 0.97). 1.07 s; use it from idle (draw + fire), NOT from the aim loop: cross-fade 0.3 s or start it at 0.3 s |
| Kay_Pistol_Reload | pass | none | pass | legs planted 0.97 -> 0.97 (all-frame mean 0.97). 1.17 s one-shot from the aim pose |
| Kay_Rifle_Aim_Loop | FAIL: loop gap 0.77 m (0.27 s raise, then a breathing hold) | trim 0.27-1.6 s + 4 frame loop blend | pass: loop gap 0.000, 1.33 s of breathing | legs planted 0.97 -> 0.97 (all-frame mean 0.97). loop; body yaw about -46 deg |
| Kay_Rifle_Shoot | pass with the same caveat as Pistol_Shoot (starts neutral, aims in 0.3 s) | none | pass-with-note | legs planted 0.98 -> 0.98 (all-frame mean 0.98). 1.07 s; use from idle or start at 0.3 s |
| Kay_Rifle_Reload | pass | none | pass | legs planted 0.98 -> 0.98 (all-frame mean 0.98). 1.6 s one-shot from the aim pose |
| Kay_Run_Holding_Rifle_Loop | pass-with-note (Run_B legs) | floor +2 cm | pass-with-note | legs planted 0.71 -> 0.71 (all-frame mean 0.80). 0.8 s loop, ~2.7 m/s |

### kaykit_undead (9 clips before, 7 after)

| clip | before verdict | action | after verdict | knee note and recommended usage |
|---|---|---|---|---|
| Kay_Undead_Idle_Loop | FAIL-minor: permanent deep knee bend (legs 0.76), soles 1.5 cm under the floor | straighten (pelvis +0.14 m, pinned ankles, target 0.92) + floor | pass: legs 0.90, still hunched (torso pitch 25 deg = the skeleton look) | legs planted 0.76 -> 0.90 (all-frame mean 0.75). 4.27 s loop, in place, gap 0.000 |
| Kay_Undead_Walk_Loop | FAIL-minor: legs 0.81, soles under the floor | straighten (pelvis +0.12 m) + floor | pass: legs 0.89, gap 0.000; the feet skid ~3 m/s at push-off frames | legs planted 0.81 -> 0.89 (all-frame mean 0.74). 1.6 s loop, ~1 m/s |
| Kay_Undead_Taunt | pass-with-note: crouch, then a 0.7 m leap in place (pelvis 0.48-1.7), 0.05 m travel | straighten +0.12 m at the planted frames + floor | pass-with-note: the crouch-launch stays at 0.58-0.66 (the deep squat is the wind-up) | legs planted 0.58 -> 0.66 (all-frame mean 0.80). 1.03 s one-shot, ends crouched; blend out 0.2 s |
| Kay_Undead_Taunt_Long | pass-with-note (same crouch / leap, 3 s) | straighten +0.12 m at the planted frames + floor | pass-with-note | legs planted 0.74 -> 0.86 (all-frame mean 0.87). 3.0 s one-shot |
| Kay_Undead_Awaken_Stand | pass-with-note: jumps up 1 m from a squat and lands 1.35 m forward (root); squat legs 0.52 | floor +2 cm | pass-with-note | legs planted 0.61 -> 0.62 (all-frame mean 0.72). 1.0 s one-shot, 1.35 m root travel forward (do not add it twice in code) |
| Kay_Undead_Awaken_Floor | REJECT: crawl to stand with a 133 deg thigh snap and a 0.69 m pelvis pop at 0.47 s, 12 m/s foot slide, ends 0.48 m off the origin | deleted | - | use UAL `Sitting_*` / a CMU get-up |
| Kay_Undead_Collapse | FAIL: hurled 4.65 m backwards over 2 s (feet skid) | root + pelvis travel scaled by 0.21 (0.98 m), floor +2 cm | PARTIAL: reads as a knock-back death, lies flat at 1.6 s (hips 0.07 m); the standing foot still skids for ~0.4 s | legs planted 0.88 -> 0.93 (all-frame mean 0.84). 2.0 s one-shot, 0.98 m root travel backwards, keep the last pose |
| Kay_Undead_Resurrect | FAIL: 5.65 m of travel, 10 frozen frames at the end | trim to 2.4 s, travel scaled by 0.21 (1.19 m), floor +2 cm | PARTIAL: rises from lying via a one-leg kick to a crouched stand; the foot skids during the flip | legs planted 0.74 -> 0.73 (all-frame mean 0.79). 2.4 s one-shot, 1.19 m root travel forward, ends in a crouch: blend into Undead_Idle |
| Kay_Undead_Rise_Ground | REJECT: floats 1-1.9 m above the ground (climb-out pose, pelvis 0.43-1.97, feet 0.5-1.4 m up, root drift) | deleted | - | make a spawn as a code-driven emerge (translate from below the floor) plus the Idle clip |

### Renames and deletions (complete list)

| library | change | reason |
|---|---|---|
| kaykit_movement_ext | RENAME `Kay_Crouch_Idle_Loop` -> `Kay_Crouch_Walk_Loop` (sidecar `Kay_Crouch_Idle` -> `Kay_Crouch_Walk`, `renamed_from` recorded) | it is a 1 m stride crouch walk cycle, not an idle; anything that referenced the old name must change (`tools/anim/build_handoff.py`, `free2/cfg_kk_movement_ext.json`, `HANDOFF_CODEX.md` still list the old name) |
| kaykit_undead | DELETE `Kay_Undead_Awaken_Floor` | 133 deg thigh snap, 0.69 m pelvis pop, 12 m/s foot slide |
| kaykit_undead | DELETE `Kay_Undead_Rise_Ground` | floats 1-1.9 m above the ground, no ground contact |

No other clip was renamed or deleted. Trimmed: `Kay_Bow_Draw` 1.33 -> 1.2 s, `Kay_Bow_Draw_Up` 1.33 -> 1.03 s, `Kay_Pistol_Aim_Loop` 1.07 -> 0.7 s, `Kay_Rifle_Aim_Loop` 1.6 -> 1.33 s, `Kay_Undead_Resurrect` 2.7 -> 2.4 s. Loop names still end in `_Loop`.

### Codex handoff (KayKit libraries)

- **Loops (in place, drive the speed in code):** Idle A/B, Stance 2H / Fists, Block_Hold, Bow_Idle, Bow_Aim_Idle, Pistol/Rifle_Aim (0.7 s / 1.33 s, closed to 0.000), Undead_Idle / Undead_Walk, Jump_Air. Walk / run loops carry NO root motion: match the animation speed to the ground speed. Approx. ground speed the strides were authored for (estimated from the ankle stride, expect +-20 %): Walk_A 1.3, Walk_B 1.5, Walk_C 0.8, Walk_Back 1.3 (backwards), Sneak 1.1, Crouch_Walk 1.9, Run_A 3.1, Run_B and Run_Holding_* 2.7, Strafe 2.0 m/s, Undead_Walk 1.0 m/s.
- **One-shots that need a blend-out (they end mid-motion or mid-pose):** Dodge_Fwd/Back/L/R (0.4 s bursts, 0.15 s), hit reactions (0.1-0.15 s), Attack_2H_Spin (0.2 s), Bow_Release / Reload clips (blend to the matching aim loop), Undead_Taunt (0.2 s) and Undead_Resurrect (blend into Undead_Idle).
- **Hold the last pose:** Death_Fall_B, Undead_Collapse, Bow_Draw / Bow_Draw_Up (full draw), Block_Raise (block held).
- **Root travel on the `root` track (use it or clamp it, do not add it twice):** Dodge_Fwd +0.49 m, Back -1.22, L +1.03, R -1.03; Death_Fall_B 0.77 m back; Undead_Collapse 0.98 m back; Undead_Resurrect 1.19 m forward; Undead_Awaken_Stand 1.35 m forward (it leaps); Bow_Draw ~0.18 m. Everything else is in place.
- **Facing:** the bow / rifle / pistol clips turn the body 33-46 deg off the actor forward (archer / aiming stance): rotate the actor accordingly, or cross-fade 0.2 s from idle. The Shoot clips start in a neutral pose, so use them from idle or start at t = 0.3 s when coming from the aim loop.
- **Knees:** legs are straight enough (>= 0.90 when planted) everywhere except the poses that are squats by design (Sneak, Crouch_Walk, Jump_Long landing, Undead_Taunt wind-up, Undead_Awaken_Stand). The skeleton (Undead_*) is a hunched, slightly bent-kneed character by design: use it for undead enemies only.
- **Not usable:** Undead_Awaken_Floor and Undead_Rise_Ground were removed; for spawn / get-up use the CMU get-ups or a code-driven emerge. Undead_Collapse / Resurrect are usable but skid one foot (partial).
- KayKit arms are long relative to the UAL body (retarget note in `docs/anim/advanced/README.md`): hand-held props (bow, rifle, pistol) may sit 5-10 cm off the palm, tune the attachment offset, not the clip.

### animations_free2/traversal_authored  (13 clips rebuilt + 1 added; `tools/anim/traversal/`)

Sheets: `frames/polish/traversal_authored/<clip>/` (`before_sheet_00N.jpg`, `sheet_00N.jpg`; vault also `iter1/iter2_sheet_001.jpg` and `iter3_keyframes_closeup.jpg`). Side view (character faces screen-right, cut-away at x = -0.6 for props) + front/back view, ruled floor. Props: `tools/anim/traversal/render_clips_trav.py` (copy of the polish renderer, props matched to the authored geometry).

| clip | before verdict | action | after verdict | notes |
|---|---|---|---|---|
| `Vault_Low` | FAIL: floating pose, no run-up, hands never touch the box, legs cross, no landing | rebuilt: run stride, gather/crouch, takeoff plant, both palms on the top (world-fixed f17-18), left hand lifts, right hand pushes to f27, hips 0.3 m over the top, legs swing left, landing absorb, two recovery steps, settle. 61 frames, root Y 2.7 m | PASS (with caveats) | box penetration 0.0 cm (validated on the solved rig), IK reach ok. Caveats: arms swing wide and stiff during the landing, calf snaps 0.36 m in one frame at f30 (fast leg swing), slide_max 2.1 m/s is the recovery steps' toe-off near the floor |
| `Vault_Low_B` (new) | - | mirror of `Vault_Low` (right side, pivot on the left hand) | PASS (same caveats) | same box check |
| `Ladder_Climb_Up_Loop` | PASS-ish (limb cycle ok, contacts between rungs, no secondary motion) | feet/hands now on rungs at 0.3k (hand rungs 1.5/1.8), grip opens/closes around each step, hip sway, chest twist, look up, knees out | PASS | 1.2 s, root Z +0.6; loop gap = the 0.6 m rise only; wide knees look a bit frog-like |
| `Ladder_Climb_Down_Loop` | PASS-ish (same) | same cycle played backwards, root Z -0.6, head looks down | PASS | min foot z is negative by design (descends) |
| `Wall_Climb_Up_Loop` | PASS-ish (hands/feet floated off the prop holds) | holds on four limb lines every 0.5 m, contacts exact, twist and look | PASS | 1.4 s, root Z +0.5 |
| `Ledge_Hang_Idle_Loop` | FAIL: hands 10 cm short of the ledge (unreachable), static | pelvis 1.125 m so the arms reach the top, hands fixed on the ledge, pendulum sway, feet lag, breathing, glance | PASS | 2.0 s, clean loop |
| `Ledge_Shimmy_L/R_Loop` | FAIL: hands crossed and collided, unreachable | four 0.25 m hand steps per cycle (lead, trail, lead, trail), hands lift 2 cm and place, feet drag, lean into the move; root X 0.5 m | PASS (minor) | R variant twists the chest a lot at f6-10; reach misses 2.5-3.3 cm at one frame |
| `Ride_Idle_Loop` | PASS-ish (rigid) | breathing, small pelvis rock, head look, rein hands follow a slow head nod | PASS | feet in stirrups (0.37, -0.10, 0.665), pelvis 1.205 |
| `Ride_Walk_Loop` | PASS-ish | pelvis rock (roll/yaw once, pitch twice per stride), spine counter-rotation, hands follow head nod | PASS | subtle by design (the horse anim carries the big motion) |
| `Ride_Trot_Loop` | FAIL: torso leaning back, arms straight, feet not in stirrups | posting trot (rise 10 cm per stride), forward torso, heels down | PARTIAL | rise reads weakly at 10 fps sheets; reach miss 2.9 cm at f15 |
| `Ride_Gallop_Loop` | FAIL: leaned BACK (sign bug), standing on toes | half-seat (pelvis +11.5 cm, torso 30 deg forward), hands on the neck, rocking with the stride | PASS (minor) | reach miss 3 cm at f4 |
| `Ride_Lean_L/R_Loop` | FAIL: static pose | 17 deg lean into the turn, head turned, hands offset, walk-rhythm rocking so it never freezes | PASS | reach miss 4.4 cm at one frame |

Common finding: on the previous clips hands/feet did not reach their targets (IK short by up to 10 cm) and nothing was checked against the props; the new build reports IK misses and box penetration per clip.

Changes
- New `tools/anim/traversal/` (`author_traversal_v2.py`, `trav_lib.py`, `clips_vault.py`, `clips_climb.py`, `clips_ride.py`, `render_clips_trav.py`, `README.md`). Rebuild: `blender -b -P author_traversal_v2.py -- out.glb`, then `glb_reduce_anim.py --rot-deg 0.08 --pos-m 0.0005`.
- `UAL_Authored_Traversal.glb` (0.44 MB after the reducer, was 1.78 MB) + `.clips.json` rewritten in place: 14 clips, all 13 original names kept (loops end in `_Loop`), `Vault_Low_B` added. Ladder/wall/shimmy/vault frame counts and seconds unchanged (vault 1.4 s -> 2.0 s, 61 frames).
- Contract notes: rungs now at z = 0.3k (hand rungs 1.5/1.8 m, handoff said ~1.45); hang pelvis 1.125 m; vault root travel still 2.7 m.
- Renderer copy differs from `polish/render_clips.py` in the props (rungs, wall holds, stirrups, horse barrel 0.52 wide with the saddle top at 1.12) and hides the wall/ledge/horse head in the front view.

