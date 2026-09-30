# Feel audit: animation and movement in the real game (2026-09-29)

Animation director pass, local session. Every finding comes from the real game (`main.tscn`),
not a demo. It was captured with Godot Movie Maker at a fixed 30 fps, on the Mobile renderer
at the HIGH tier, 1280×720.

## How it was captured

The harness is `kingdom/tools_qa/feel_capture/`:
- `feel_capture.gd` plays 18 scenarios through the real input path and waits in rendered frames, so a run is deterministic.
- Every frame carries an overlay with the scenario, frame, body speed, animation speed, loco blend, gait rate and facing.
- `telemetry.csv` holds the same values per frame, plus the rendered (interpolated) camera distance.

Commands:

```bash
kingdom/tools_qa/feel_capture/run_feel_capture.sh <out_dir> high [--only=01,02]
FRAME_OFFSET=-1 CROP=440:420:420:240 bash tools/qa/feel_sheets.sh <out_dir> <sheets_dir> 15 6 4 300
# Strike timing of the attack clips on the player rig (headless is fine):
Godot --headless --path kingdom res://tools_qa/feel_capture/measure_hits.tscn
```

- Sheets are sampled at 15 fps. `#n` on a sheet is sample n, which is movie frame 2n inside the scenario.
- Evidence images are in `docs/anim/feel/before/` and `docs/anim/feel/after/`.
- The raw AVIs, about 300 MB each, are kept outside the repo.

## Scorecard (1 = broken … 5 = AAA)

Before and after scores are from the same scenario on the same HIGH tier.

| # | Situation | Foot slide | Pops | Blend | Response | Antic/impact | Weight | Camera | Facing/turn | Crowd | Ground | Before → after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01 | Walk start/stop | 3 | 4 | 4 | 5 (1 frame) | – | 2 → 3 | 5 | 4 | – | 4 | 3.0 → 3.5 |
| 02 | Run start/stop | 3 | **2** → 4 | 3 | 5 | – | **2** → 4 | 5 | 4 | – | 4 | 2.5 → 3.8 |
| 03 | Turn in place | 3 | 3 | 3 | 5 | – | 2 → 3 | 5 | **2** → 3 | – | 4 | 2.8 → 3.3 |
| 04 | 180° pivot from a run | 4 | 4 | 4 | 5 | – | 4 | 5 | 4 | – | 4 | 4.0 |
| 05/06 | Walk↔run, curved run (lean) | 4 | 4 | 4 | 5 | – | 4 | 5 | 4 | – | 4 | 4.0 |
| 07 | Slope up/down (3 m rise over 25 m) | 4 | 5 | – | – | – | 4 | 5 | – | – | 4 (player foot IK) | 4.0 |
| 08/15 | Camera orbit and occlusion | – | **2** | – | – | – | – | **2** | – | – | – | 2.0 (→ P4) |
| 09 | 4-hit combo in the air | – | 4 | 4 | 5 | **2** → 4 | 3 | 5 | 4 | – | – | 3.2 → 4.0 |
| 10 | Combo on an orc | – | 3 | 4 | 5 | **2** → 4 | 3 → 4 | 4 | 4 | – | – | 3.0 → 4.0 |
| 11 | Block | – | 4 | 4 | 5 | 3 | 3 | 4 | **2** (faces the camera, not the threat) | – | – | 3.0 (→ P1) |
| 12 | Dodge rolls | – | 4 | 4 | 5 | 4 | 4 | 4 | 4 | – | – | 4.0 (rolls pass through enemies) |
| 13 | Hit, knock-down, get-up | – | **1** (get-up pop) | 2 | – | 3 | 3 | 4 | – | – | – | 2.2 (→ P3) |
| 14 | Talk to an NPC | – | 3 (hard cut) | – | 5 | – | – | **2** (camera inside the NPC or cart) | 4 | – | – | 3.0 |
| 15 | Crowd in the plaza | 4 | 4 | 4 | – | – | – | – | – | **2** → 3.5 | 3 | 3.0 → 3.5 |
| 16 | Wolves chase and attack | 3 | 4 | 3 | – | 3 | 3 | 4 | 3 (crab-walk, P2) | – | 3 | 3.0 (and **readability**, F14) |
| 17 | Horse ride and gallop | 3 | 4 | 3 | 4 | – | 3 | 5 (distance steady at 7.8 m) | 4 | – | 3 | 3.6 |
| 18 | Swim (wading) | 4 | 4 | – | 4 | – | 4 | 5 | 4 | – | – | 4.0 (did not reach swim depth) |

- There is no jump in the game, so jump/land and landing squash do not apply.

## Issues, ranked

| Rank | ID | Issue | Evidence | Sev | Cause | Owner / status |
|---|---|---|---|---|---|---|
| 1 | F1 | The run stops dead: 6.4 → 0 m/s in 7 frames (0.23 s), and the pose snaps from a run stride to idle in about 4 frames, with no deceleration steps | `feel/before/02_run_stop_sheet3.jpg` #48→#49; telemetry f393-400 | High | Code tuning: one `MOVE_BRAKE` = 30 m/s² for everything | **Fixed** (local): speed-dependent stop brake. Now 12 frames (0.40 s), and the feet take 2-3 decelerating steps (`feel/after/02_run_stop_sheet3.jpg` #48-#51) |
| 2 | F3 | Combo timing does not match the blade. The horizontal slice dealt damage and hitstop at 0.20 s, but its blade peaks at 0.29 s at the old playback (0.642 s of clip time). The slash arc spawned at 55 % of the hit time, while the sword was still going up | `feel/before/09_combo_sheet1.jpg` #8, #14; `09_combo_sheet2.jpg` #21 vs #24 | High | Hit table was guessed | **Fixed** (local, COMBO tuning): hit times come from `measure_hits.gd` (0.15 / 0.16 / 0.29 / 0.29 s), the slice plays at 2.2×, the arc leads the hit by 0.07 s, and tired 0.7× swings delay the hit to match. `feel/after/09_combo_sheet2.jpg` #21-#23 |
| 3 | F4 | The attack lunge (a fixed 3 m/s kick, 0.375 m) drives the player into an enemy already in reach, and the bodies interpenetrate | `feel/before/10_orc_combo_sheet1.jpg` #3-#6, #20-#23 | High | Code | **Fixed** (local): the lunge is sized to stop at a 1.3 m standoff from the assisted target. `feel/after/10_orc_combo_sheet1.jpg` |
| 4 | F5 | Enemy knockback is an instant teleport of 0.12 m per unit of knockback, so a 0.84 m pop on the finisher | `wolf.gd`/`monster.gd` `take_damage` | High | Code bug | **Fixed** (local): the same distance now plays as a 0.1 s exponential slide with collision. `feel/after/10_orc_combo_sheet1.jpg` #18-#21 |
| 5 | F11 | Ragdoll knock-down to stand-up pops upright within about 1 sample | `feel/before/13_knockdown_getup_sheet1.jpg` #15→#17 | High | Code (no pose blend on the hand-back) | Codex: `docs/anim/patches/P3_getup_pop.md` |
| 6 | F12 | The chase camera sits behind the well's roof for about 0.2 s, then snaps about 3 m closer | `feel/before/15_camera_well_roof_sheet4.jpg` #66-#70 | High | Content (no camera blocker on thin canopies) and camera code | Cloud (blockers) + Codex: `patches/P4_camera_occluders.md` |
| 7 | F2 | Walk start: the body reached full walk speed in 2 frames while the gait was still at 0.4 m/s, so the feet slid on the first step | telemetry `01` f184-186 | Med | Code tuning (`ACCEL_START` 34) | **Fixed** (local): 17 m/s². Full speed at f188, and the first input still moves the body on the next frame |
| 8 | F7 | Idle turn is 20 rad/s: a 90° spin in 0.13 s reads as a snap, and the stop after a short tap freezes mid-stride, then slides into idle | `feel/before/03_turn_sheet1.jpg` #8→#10, #12-#16 | Med | Tuning, plus no turn/stop clips | Tuned to 14 rad/s (local). Clips: `patches/P5_locomotion_transitions.md` |
| 9 | F6 | Block faces the camera heading, not the attacker. From the side, the guard points 57° away | `feel/before/11_block_sheet1.jpg` | Med | Code | Codex: `patches/P1_block_faces_threat.diff` |
| 10 | F9 | Villager idles all start at frame 0 and play at rate 1.0, so people who stop together sway in unison | `villager.gd _play/_update_activity` | Med | Code | **Fixed** (local): per-person entry phase and a stable 0.9-1.1 rate |
| 11 | F10 | NPC feet ignore slopes: `ProceduralRig` was player-only, and the villager `_attach_components` hook was empty | code survey; bench | Med | Code + perf | Tried and **reverted**: attaching the rig to villagers cost 14-22 fps on HIGH (see Performance). Proposal: `patches/P6_npc_foot_ik_cost.md` (a pooled rig for the N nearest) |
| 12 | F8 | Wolves and monsters crab-walk: velocity turns instantly while yaw lerps at 6/s (frame-rate dependent) | `wolf.gd`/`monster.gd` movement | Med | Code | Codex: `patches/P2_quadruped_no_crab_walk.diff` |
| 13 | F13 | Talk: the camera ends inside the NPC or a cart, and the portrait is a hard cut | `feel/before/14_talk_sheet1.jpg` #1-#14; `feel/after/14_talk_sheet2.jpg` | Med | Camera (villagers are excluded from `CAMERA_MASK`) | **Partial (local):** dialogue shade/UI and bust now ease in over 0.25 s; Claude: frame the speaker in a talk shot and address camera obstruction |
| 14 | F14 | Wolves read as small grey dogs and vanish in the tall grass at 10-15 m, so the chase has no threat | `feel/before/16_wolves_tiny_in_grass.jpg` | Med | Content (wolf model scale, grass height) | Local assets: scale the `wolf2` model about 1.3× and check it against the player |
| 15 | F15 | Rolls pass through enemies' bodies | `feel/before/12_dodge_sheet1.jpg` #19-#23 | Low | Design (i-frames) | **Local:** when a swept roll path hits a hostile capsule, choose the nearest clear 10° lane up to 50° around it; world walls still block normally |
| 16 | F16 | Hitstop sets the global `Engine.time_scale` to 0.05, which freezes camera shake, VFX and every NPC | `player._hit_stop` | Low | Design | Keep global for finishers; use `lib/hitstop.gd` local freezes for light hits (Codex) |
| 17 | F17 | A guard walks through the market cart | `feel/after/15_crowd_sheet1.jpg` #2-#8 | Low | Route or prop collision | Cloud (street graph vs cart footprint) |

## What changed (local, surgical)

Each change is small and noted here as required.

| File | Change | Why |
|---|---|---|
| `scripts/actors/player.gd` | `ACCEL_START` 34 → 17; new `STOP_BRAKE_WALK` 16 and `STOP_BRAKE_RUN` 15, used when the stick is released (`MOVE_BRAKE` 30 kept for sprint → walk); `FACE_TURN_IDLE` 20 → 14 | F1, F2, F7 |
| `scripts/actors/player.gd` | COMBO `hit`/`lock`/`speed` from the measured blade timing; `SLASH_LEAD` 0.07 s; tired swings scale their hit time; lunge limited by `LUNGE_STANDOFF` 1.3 m | F3, F4 |
| `scripts/actors/wolf.gd`, `monster.gd` | `_knock` slide (`KNOCK_TAU` 0.1 s, same 0.12 m per unit of knockback) instead of the `global_position +=` teleport | F5 |
| `scripts/population/villager.gd` | Idle entry phase and per-person rate (the NPC rig hook was tried and reverted, P6) | F9 |
| `scripts/actors/procedural_rig.gd` | A rig whose `_model` is null removes itself. The dialogue portrait duplicates NPC models, and after F10 it spammed `_check_range` errors | Stability |

## Performance

Village scene, Mobile renderer, `bench.gd --uncapped`. It ran on a shared, loaded PC with about 10 other Godot and Blender jobs running, so treat about ±20 % as noise.

| Build | HIGH fps (runs) | LOW fps (runs) |
|---|---|---|
| Before (origin code) | 53.7, 51.2, 51.6, 23.6*, 66.0 | 73.6, 57.6, 51.0, 21.4*, 75.6 |
| With the NPC-rig attempt (F10, reverted) | 52.6, 44.2, 37.3, 29.5 | 58.7, 67.9, 56.4, 52.3 |
| **Final (player + NPC tuning, no NPC rigs)** | 44.5, 59.7 | 30.3*, 84.9 |

* = runs made while another agent's heavy job was running (every build dropped at once).

- The final changes add no per-frame work. They are constants, one extra `sqrt` per swing, and a knockback slide that only runs while `_knock` is non-zero. Paired runs sit within noise, on both HIGH and LOW.
- The NPC foot-IK attempt was a clear HIGH regression, 7-15 ms per frame on PC, so it was reverted (P6).
- Raw lines are in `docs/qa/bench_results_feel.jsonl`.

## QA boot test

`tools_qa/boot_flow/boot_flow.gd` with `BOOT_FLOW_SKIP=1`: **BOOTFLOW OK** on the merged branch, with these changes applied. The branch before the merge failed at "world veil never appeared", with or without this pass; the upstream character-creation fix resolved it.

The feel captures boot the real game through `main.tscn` with zero script errors after the `procedural_rig` guard.
