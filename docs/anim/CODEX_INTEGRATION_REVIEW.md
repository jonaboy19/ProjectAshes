# Codex animation integration review (2026-10-01)

**Merged into `claude/focused-curie-m09hbd`:**
- `gpt/locomotion-jump-integration`: local only, 32 commits; it carries the animation and feel work.
- `gpt/living-world-integration`: local tip `83535327`. The 8 commits on origin's older tip are in it as equivalent rebased patches. It carries the NPC activity runtime, needs and item hooks.

Codex handoffs: [CODEX_LOCOMOTION_JUMP.md](CODEX_LOCOMOTION_JUMP.md) and `docs/concepts/CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md`. Fixes and open items for Codex: [patches/P15](patches/P15_codex_integration_fixes.md).

## How it was checked
- **Capture:** the real game under Godot Movie Maker at 30 fps (1280x720, mobile renderer, quality High), using `kingdom/tools_qa/feel_capture` (`run_feel_capture.sh <out> high --only=...`). It drives the real input path.
- **New scenarios:** 19 jumps, 20 falls, 21 parry, 22 directional hits plus guard break, 23 companions.
- **Sheets:** `tools/qa/feel_sheets.sh`, run full-frame and with `CROP=400:400:440:180` on the body. Sheets cited below were read frame by frame. Rows marked *(telemetry)* were judged from per-frame telemetry only. Telemetry is in `telemetry.csv`, one row per frame.
- **Clip check:** `tools/anim/loco/verify_loco.gd` reports `LOCOVERIFY OK`. All 16 loco/jump clips resolve, with 55 tracks and 0 unresolved.
- **Full captures:** kept outside the repo in `C:\Users\Jonna\Documents\PA_codexint_cap\` (`run1`, `run2`, `sheets`, `crop`, `sheets2`, `crop2`). Key sheets are copied to `docs/anim/codex_integration/frames/`.

## Player (Knight-rig hero, current look)
| Action | Result | Evidence |
|---|---|---|
| Walk start/stop | PASS *(telemetry)*: speed ramps without spikes; the start clip is still not wired (Codex deferred it) | crop/01 |
| Run start/stop | PASS with note: the capsule brakes 6.4 to 0 m/s in 0.4 s (about 1.3 m, below the 1.4–1.7 m target), and there is a small sword-arm pop as the stop blends to idle at about +0.4 s | frames/02_run_stop.jpg |
| Turn in place, 180° pivot | **FAIL (known, deferred P5):** the body snaps 180° in about 2 frames (#34–36) because no pivot or turn clip is wired | crop/04 sheet 2 |
| Sprint (walk-run-walk) | PASS *(telemetry)* plus the sprint legs in the 02/23 sheets | crop/05 |
| Standing jump | **FAIL, then FIXED.** A tap gave a 0.23 m hop because the jump-cut fired during take-off. Now 0.78 m with 0.53 s of air; anticipation #9–10, rise, clear shadow separation, dust landing #19 | frames/19_jump_standing_before_fix.jpg, frames/19_jump_standing_after_fix.jpg |
| Running jump, jump spam (buffer) | PASS: buffered re-jumps fire on touchdown, with no stuck state | sheets/19, telemetry |
| Fall 2.5 m / 7 m / running 4 m | PASS: fall pose with arms out; hard land/roll with dust #13–17, then recovery | frames/20_fall_7m.jpg |
| 4-hit combo, heavy (finisher) | PASS: trails line up with the blade, impact sparks on the orc, finisher shows radial lines and the FOV pulse | frames/10_combo_orc.jpg, sheets2/23_companions_fight |
| Block | PASS: the shield faces the orc for the whole hold; the orc wind-up orange cue shows at #17–19 | crop/11 sheet 1 |
| Parry | PASS: ring flash #2–3, contact spark, riposte, orc knocked down. Note: afterwards the player re-faces away from the downed orc | frames/21_parry.jpg |
| Dodge (K: back, side, forward) | PASS: the roll reads and recovers into a run | frames/12_dodge.jpg |
| Hit reactions light/heavy x 4 sides, guard break | PASS: a small flinch for light hits; a heavy stagger with backward push and recovery | frames/22_hit_light_heavy.jpg, crop/22 sheets 1–8 |
| Talk / idle | INCONCLUSIVE: the harness opened the Steward's Post sign rather than a villager, so the NPC bust and talk idle were not exercised. Idle between actions looks clean | sheets/14 |

## Companions (player's Knight squad, `main.army`)
| Action | Result | Evidence |
|---|---|---|
| Follow at walk and sprint | PASS: 4 knights keep a loose column and the run cycle matches their speed | frames/23_companions_follow.jpg |
| Stop | PASS with note: the knights finish 4.3–5.0 m from the player. They keep running for about 1 s while turning to their slots; their own stop-to-idle needs a closer capture | sheets2/23 sheet 4 |
| Fight beside the player | PASS: they close on the orc and swing; directional soldier hits play | frames/23_companions_fight.jpg |

There are no other named companion characters in the current build. The army squad is the only follower system that has bodies.

## Fixes made in this integration
1. `Player._dodge_obstruction`: `test_move` needs a `KinematicCollision3D`. The wrong type was a parse error that stopped the player and quality scripts from loading.
2. Variable jump cut: it now waits `JUMP_CUT_MIN_AGE = 0.1` s and scales by 0.6, which makes tapped jumps readable on touch.
3. `UtilityBrain` catch-up: `floor()` changed to `floorf()`, because inferring a Variant is an error in this project.
4. `Villager._decide_act`: the merge had produced two `heard` variables; Claude's scream alarm is renamed to `scream`.
5. Harness: dodge moved to K (Space is Jump now), plus scenarios 19–23 and `anim_cost.gd`.

## Patches P1–P14: what Codex applied
| Patch | Status |
|---|---|
| P1 block faces threat | Applied (12.5 Hz nearest enemy within 6 m) |
| P2/P2b quadruped crab-walk, wolf turn | Turn and forward-biased travel applied; pack clips not checked here |
| P3 get-up pop | Already in the Claude base |
| P4 camera occluders | Applied for wells and canopies; market MultiMesh fading deferred |
| P5 locomotion transitions | Partial: only RunStop_L/R. Starts, walk stop, skid, pivots and idle turns are deferred |
| P6 NPC foot-IK cost | Not applied |
| P7 jump | Applied (fixed here, see above) |
| P9 attack layering | Not applied |
| P10 directional hit reactions | Applied (player and soldiers) |
| P11 enemy wind-up | Applied (two-phase snap, orange cue) |
| P12 hit-stop, FOV | Applied (local mixer pause and FOV pulses that respect the Screen Shake setting) |
| P13 life libraries, VAT, smart objects | Smart objects and activity runtime came in through living-world; VAT/LOD libraries not in these branches |
| P14 horses | Not Codex (Claude landed it) |

## Performance
- `tools_qa/feel_capture/anim_cost.gd` measures CharacterAnimator on PC CPU, 20 characters, manual advance:
  - NPC/companion graph: **0.36 ms per character per frame**, about 1.8 ms on the phone (x5).
  - Player graph with Codex's air state machine: **0.45 ms**, about 2.3 ms on the phone.
  - The air graph adds about 0.09 ms, on the player only.
  - These are upper bounds, because a gdUnit run was going at the same time.
- Movie Maker frame times are not real-time, so they are not reported as fps.
- **Phone fps: NOT MEASURED.** The S22 (R5CT849XNVF) was not attached (`adb devices` was empty), so the scrcpy session is still to do.

## Tests
- Parse/import: clean after the fixes.
- Boot flow (`tools_qa/boot_flow/boot_flow.gd`, `BOOT_FLOW_SKIP=1`): **BOOTFLOW OK**.
- gdUnit: see the commit message and the STATUS_LOCAL entry for the final count.
- Environment note: in this worktree a few `meshy_free` GLBs (fence_rail_rustic, hut_long_thatch, well_wood_roof) failed to load from the copied import cache. That produced null errors in RegionDressing and region1_look. Neither Codex branch touches these files.

## Remaining issues (priority order)
1. Phone pass on the S22: fps, Jump/Attack touch reach, and the one-handed layout. Jump shares a slot with the combat Interact button.
2. Run-stop distance and the idle-blend sword pop (Codex, P15).
3. Starts, pivots, idle turns, walk stop and skid are still unwired (P5). This is the biggest remaining gap in locomotion polish.
4. Companion stop-to-idle needs a close capture, and probably a stop transition in `soldier.gd`.
5. Talk/idle needs a capture against a villager: the harness should pick villagers only.
6. Block facing after a parry knock-down.
7. P6 and P9 have not been started.
8. Style G hero: these clips were reviewed on the current hero. The Style G agent should re-check the new outfit on jump, roll and heavy-hit poses (cloth and satchel clipping).
