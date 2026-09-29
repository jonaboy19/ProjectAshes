# Review results: stop-motion review of the free clip libraries (round 3)

Method: every clip was rendered as stop-motion frames on the game's own `Player` character (`tools/anim/preview_free_library.gd --stopmotion`,
side view; front view for the hook clips), tiled with `tools/qa/video_to_sheets.sh` (12 fps for the martial-arts/combo clips, 15 fps for the
KayKit clips and weapons, 8x3 frames per sheet) and read frame by frame. In addition the hand / foot paths were measured from the animation data
(`tools/anim/measure_events.gd`): strike speed, reach, path shape in the chest frame, pelvis offsets, lowest bone height. Trims, renames, deletions and the
pelvis fix are applied with `tools/anim/glb_edit_clips.py` (GLB + `*.clips.json`) and mirrored in the clip table `tools/anim/make_free_cfgs.py`, so a full rebuild
from the BVH sources gives the same result. Trimmed clips were re-rendered and read again.

Sheets of the important decisions: [frames/](frames/) (`MA_Punch_Hook_*`, trimmed combos, weapons, `REJECTED_*`), KayKit reactions:
[../advanced/preview/kaykit_combat_reactions/](../advanced/preview/kaykit_combat_reactions/), traversal: [../advanced/preview/trav/](../advanced/preview/trav/).

## Punch_Heavy: hook or uppercut?  Verdict: all ten are hooks (renamed `Punch_Hook`)

* Front view (`frames/MA_Punch_Hook_R_A_front.png`, `_R_D_front.png`, `_R_E_front.png`): the punching arm goes out to the side at shoulder height (elbow high,
  fully outside the body line), then sweeps across in front of the chest/face while the torso whips round. In no clip does the fist travel up the centre line with
  the palm up from hip to chin.
* Measured (fist path in the chest yaw frame, all 10 clips): lateral excursion 0.48-0.68 m from the torso centre line (an uppercut stays below about 0.15 m), path
  deviation from the straight start-end line 0.20-0.54 m, the fist rises about 0.5 m only because it starts pulled back at hip level and ends at head height across the body.
* `R_D` / `R_E` (labelled "uppercut" before) are the rising overhand variants of the same swing (`R_E` is the tightest, 0.48 m lateral); nothing is a true uppercut.
* Rename: `MA_Punch_Heavy_*` -> `MA_Punch_Hook_*` (same suffixes), `MA_Combo_HeavyJab/HeavyHeavy/HeavyStraight` -> `MA_Combo_HookJab/HookHook/HookStraight`
  (GLB, `*.clips.json`, `make_free_cfgs.py`, `cfg_free_*.json`, `clip_tables.md`).
* Side effect worth knowing: all boxing takes wind up with the torso yawed towards 90 degrees from the strike direction (back to the camera in side view), so pair them with a
  short turn-to-target and expect the visible hit at the frame listed in HANDOFF_CODEX.md.

## Decisions

Verdict codes: OK = kept unchanged, TRIM = kept and trimmed (window relative to the old clip), FIX = kept with a data fix, RENAME, REJECT = removed from GLB, tables and configs.

### animations_free/martial_arts_unarmed

| clip | verdict | fix / note |
|---|---|---|
| `MA_Punch_Cross_R_Head_A`, `MA_Punch_Cross_L_Head` | TRIM 0-1.6 s | 2.03 s clip ended with the start of a second punch; now ends in guard |
| `MA_Punch_Cross_R_Head_B` | TRIM 0.85-1.85 s | long foot shuffle before/after the punch removed |
| `MA_Punch_Cross_R_Head_C` | OK | |
| `MA_Punch_Cross_R_Body` | REJECT | torso yawed 90 degrees, hands up at the end, fist only reaches 0.15 m in front of the chest (others 0.4+) |
| `MA_Punch_Jab_L_Head_A`, `MA_Punch_Jab_R_Head`, `MA_Punch_Jab_L_Head_B` | OK | B has an open palm at the hit |
| `MA_Punch_Jab_L_Body` | OK (note) | head buried in the shoulder in the wind-up, hand scoops up after the hit; usable, not pretty |
| `MA_Punch_Heavy_R_A/B/C/D/E/Body`, `_L_A/B/C/D` (10) | RENAME -> `MA_Punch_Hook_*` | hooks, see above; no other change |
| `MA_Kick_Front_R_Quick` | OK | knee strike, starts mid-step (first 3 frames) |

### animations_free/combos  (13 -> 7)

| clip | verdict | fix / note |
|---|---|---|
| `MA_Combo_JabCross`, `MA_Combo_JabCross_Southpaw` | TRIM 0-1.45 s | feet crossed and slid in the last 0.3 s |
| `MA_Combo_CrossCross` | OK (note) | 0.4 s hold on the first cross, small rear-foot drag at 0.67-0.73 s: use foot IK |
| `MA_Combo_StraightStraight` | TRIM 0.55-1.95 s | started mid-step, ended in a second cycle |
| `MA_Combo_HeavyJab` | RENAME `MA_Combo_HookJab`, TRIM 0-1.33 s | ended in a step |
| `MA_Combo_HeavyHeavy` | RENAME `MA_Combo_HookHook`, TRIM 0-1.75 s | started a third strike at the end |
| `MA_Combo_HeavyStraight` | RENAME `MA_Combo_HookStraight`, TRIM 0-1.6 s | idle tail removed |
| `MA_Combo_StraightHeavy` | REJECT | second half is a walk-in; every trim ends mid-hook with the back to the camera (source has no recovery) |
| `MA_Combo_BodyHeadHead` | REJECT | feet together, arms only, 5 near-identical punches instead of 3, no body-height punch |
| `MA_Combo_HeavyStraightHeavy` | REJECT | 1.5 s spin with the back to the camera, T-pose arms, no readable strikes |
| `MA_Combo_Flurry_5Hit` | REJECT | feet together, arms low at the start and the end, 7 punches instead of 5 (`frames/REJECTED_MA_Combo_Flurry_5Hit.png`) |
| `MA_Combo_Flurry_Long` | REJECT | same posture problem for 5 s, ends mid-strike |
| `MA_Combo_PunchKick` | REJECT | dancer stance on tiptoes, 5 kicks instead of 1, ends off-facing (`frames/REJECTED_MA_Combo_PunchKick.png`) |

### animations_free/weapons  (21, KayKit CC0, no weapon prop in the preview)

| clip | verdict | note |
|---|---|---|
| `Weapon_1H_Chop` | OK (verify with the prop) | hand stays below the shoulder (max +0.0 m), arm ends behind the hip: reads as a low forward chop |
| `Weapon_1H_Chop_Jump` | OK | plunge attack, 0.11 m root travel, lands in a crouch (blend out) |
| `Weapon_1H_Slice_Diagonal`, `Weapon_1H_Slice_Horizontal` | OK (verify with the prop) | compressed arcs: hand reaches only 0.16-0.23 m in front of the chest; hit frame is the fastest hand |
| `Weapon_1H_Stab`, `Weapon_2H_Stab`, `Weapon_DW_Stab` | OK | hold of about 0.3 s after the thrust, trim in code if too slow |
| `Weapon_2H_Chop` | OK | 0.3 s ready hold at the start |
| `Weapon_2H_Slice` | OK | |
| `Weapon_2H_Spin` | OK | full turn, feet pivot: foot IK optional |
| `Weapon_2H_Spinning` | OK | 0.67 s, ends with the arms forward, not loopable |
| `Weapon_Block`, `Weapon_Block_Attack` | OK | |
| `Weapon_Block_Hit` | OK (weak) | very small recoil, scale it up with a procedural push |
| `Weapon_DW_Chop` | OK (note) | both feet lift 10-15 cm at the strikes |
| `Weapon_DW_Slice` | OK (note) | extreme forward lean after the hit |
| `MA_KK_Kick` | OK | one-frame rear-foot pop at f1-f2 |
| `MA_KK_Punch` | OK | 0.09 m step-through |
| `MA_KK_Idle_Loop_Loop`, `Hit_KK_A`, `Hit_KK_B` | OK | `Hit_KK_B` has a mild rear-foot pop at recoil |

### animations_free2/kaykit_combat_reactions  (15 -> 14; first preview sheet: `../advanced/preview/kaykit_combat_reactions/`)

| clip | verdict | fix / note |
|---|---|---|
| `Kay_Death_Fall_A` | REJECT | falls as a rigid plank, hips stay 0.36 m above the floor at the end (propped on the heels) |
| `Kay_Death_Fall_B` | TRIM 0-2.1 s | frozen tail removed (2.63 s -> 2.10 s); body lies on the ground from f49 (1.63 s); skirt dips slightly below the floor |
| `Kay_Dodge_Fwd/Back/L/R` | FIX | pelvis carried the travel a second time (start offset 0.74-0.97 m, the character started outside the cell): pelvis sway only now, travel stays on `root`. Still 0.4 s bursts that end mid-motion: blend out over 0.15 s |
| `Kay_Attack_2H_Spin_Long` | TRIM 0.3-1.9 s | static ready pose and settle removed |
| `Kay_Hit_React_A/B`, `Kay_Block_*`, `Kay_Stance_*` | OK | recoil small (Block_Impact 0.13 m), scale in code if needed |

### animations_free2/traversal_authored  (13, hand-authored)

| clip | verdict | fix / note |
|---|---|---|
| `Ladder_Climb_Up_Loop`, `Ladder_Climb_Down_Loop` | FIX (rebuilt) | legs were tucked at hip height. Now: cross pattern, feet land on rungs 0.3/0.6 m and lift when the leg is nearly straight, hands on rungs 1.8/2.1 m, elbows out, knees out, 0.6 m rise per 1.2 s loop (2 rungs) |
| `Wall_Climb_Up_Loop` | FIX (rebuilt) | same rebuild (0.5 m rise per 1.4 s, wider stance) |
| `Ledge_Hang_Idle_Loop`, `Ledge_Shimmy_L/R_Loop`, `Vault_Low`, `Ride_*` | OK (placeholder) | read cleanly in the strips |
| `Ride_Lean_L/R_Loop` | FIX | were a 0.03 s loop, now 1.0 s (Godot handles a loop this short badly) |

### Not re-reviewed in this round (reviewed earlier, see the notes in README.md)

kicks 11, defense 9, acrobatics 19, reactions 9, casting 6 + 6, KayKit life_sim 33, movement_ext 17, ranged 14, undead 9. `measure_events.gd` numbers for them are in HANDOFF_CODEX.md.
Flags from the measurements: `Kay_Undead_Collapse` has 4.65 m of root travel (use it with a ground clamp, no root motion); `MA_Kick_Jump_R/L` and `MA_Acro_Handspring` start with the pelvis 0.55 m / 1.15 m off the root (run-up, by design); `MA_Kick_JumpHigh_A` has 2.2 m of travel on x.
