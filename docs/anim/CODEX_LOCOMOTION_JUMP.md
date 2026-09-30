# Codex handoff: locomotion and jump integration

Branch: `gpt/locomotion-jump-integration`  
Base: latest fetched `claude/focused-curie-m09hbd` (`f547198a` at integration time)

This patch integrates the authored jump set and the measured high-speed run-stop clips into the playable character. It does not alter scenes, `project.godot`, NPC schedules, or Claude's world systems. It is not yet runtime-verified in the game.

## Implemented

- `Assets.UAL_FILES` loads `UAL_Loco_Transitions.glb` before UAL1 so this library's `Jump_Start` wins the duplicate-name lookup. Root translation is disabled for these clips; root rotation is disabled because player heading is capsule-driven.
- Added a player-only whole-body air/transition state machine in `CharacterAnimator`; NPC/soldier animator instances keep their existing graph.
- Added buffered Space/mobile jump input, a distinct K dodge binding, a rebindable Jump action, and a touch button above Attack.
- Added coyote/buffer timing, standing and running take-off, variable jump height, rise/fall clips, soft/hard/running/roll landings, fall damage, small dust and haptic hooks, and landing camera dip/FOV response.
- A coyote jump launches immediately so the take-off anticipation cannot use up the ledge grace window. A jump buffered within 0.12 s of touchdown exits landing recovery on the first grounded tick.
- Wired `Loco_RunStop_L/R` on grounded input release above 4 m/s. Side is selected from shared gait phase; playback rate is entry speed divided by the authored 3.1/3.6 m/s entry speed. The existing 15 m/s² capsule brake remains in control. The clip duration is read from the loaded library, and combat, block, or jump cancels the stop overlay.

## Deliberately deferred

- Walk/run starts are not wired. Their authored clips enter at nonzero foot speed while the current capsule accelerates from rest; with root translation disabled, this needs a measured acceleration/phase handoff to avoid visible foot skating.
- Walk stop, sprint skid, pivots, and idle turns are not wired. They need capsule path/yaw and event timing hooked to the sidecar before enabling them.
- Contextual vault/climb, water landing splash, surface-specific jump effects, and fall camera pitch remain future integration work.

## Validation needed

1. Open the project in Godot 4.6.3 so the new GLB import is generated, then run `tools/anim/loco/verify_loco.gd`.
2. In a playable build, check standing jump, running jump, coyote/buffer behavior, fall-from-ledge, 5 m forward roll, damage beyond 6 m, water landing, and jump/button spam.
3. Confirm the RunStop_L/R side selection visually against the planted foot and verify the capsule covers approximately 1.4–1.7 m before reaching idle.
4. Check 16:9, portrait/mobile, and one-handed HUD layouts for Jump/Attack overlap and touch reach.
5. Tune anything that drifts on the actual player rig, then land this branch into Claude's active line.

## Environment caveat

The available checkout had an incomplete `.godot/imported` cache. The prior `verify_loco.gd` attempt failed because the imported scene cache was absent (and other project imports were also missing), not because the GLB had failed Claude's documented Godot 4.6.3 verification. Avoid a full cold import here; the repository notes that it can require about 30 minutes and 7 GB.
