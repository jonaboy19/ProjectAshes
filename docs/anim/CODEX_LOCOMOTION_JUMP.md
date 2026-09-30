# Codex handoff: locomotion and jump integration

Branch: `gpt/locomotion-jump-integration`  
Base: latest fetched `claude/focused-curie-m09hbd` (`f547198a` at integration time)

This patch integrates the authored jump set and the measured high-speed run-stop clips into the playable character, plus narrowly scoped feel fixes. It does not alter scenes, `project.godot`, NPC schedules, or unrelated world systems. It is not yet runtime-verified in the game.

The latest Claude base already contains the ragdoll pose-hold get-up blend from the prior feel audit, so that change was left untouched.

## Implemented

- `Assets.UAL_FILES` loads `UAL_Loco_Transitions.glb` before UAL1 so this library's `Jump_Start` wins the duplicate-name lookup. Root translation is disabled for these clips; root rotation is disabled because player heading is capsule-driven.
- Added a player-only whole-body air/transition state machine in `CharacterAnimator`; NPC/soldier animator instances keep their existing graph.
- Added buffered Space/mobile jump input, a distinct K dodge binding, a rebindable Jump action, and a touch button above Attack.
- Added coyote/buffer timing, standing and running take-off, variable jump height, rise/fall clips, soft/hard/running/roll landings, fall damage, small dust and haptic hooks, water splashes on landing/swim entry, and landing camera dip/FOV response.
- A coyote jump launches immediately so the take-off anticipation cannot use up the ledge grace window. A jump buffered within 0.12 s of touchdown exits landing recovery on the first grounded tick.
- Wired `Loco_RunStop_L/R` on grounded input release above 4 m/s. Side is selected from shared gait phase; playback rate is entry speed divided by the authored 3.1/3.6 m/s entry speed. The existing 15 m/s² capsule brake remains in control. The clip duration is read from the loaded library, and combat, block, or jump cancels the stop overlay.
- Applied two still-open feel-audit fixes from the earlier handoff: third-person block now faces the nearest enemy within 6 m (camera heading remains the fallback), and wolves turn with frame-rate-independent yaw plus forward-biased, turn-scaled travel to reduce sideways crab-walking.
- Replaced the global time-scale freeze on ordinary 50 ms sword hits with a local pause on only the player's and struck actors' animation mixers. Parry and finisher slow-motion retain the existing global effect. The local pause restores prior mixer state and does not freeze physics, camera, particles, or unrelated NPCs.
- Added restrained outward FOV pulses on successful parries and finisher hits, and routed combat positional shake through the same Screen Shake access setting (Off = none, Reduced = half, Full = full). FOV pulses cap at 6 degrees and decay independently from landing FOV and positional shake. The preference is read only when an impact occurs.
- Contact sparks use the sampled sword tip when it is within 0.6 m of the confirmed target contact point; otherwise they keep the reliable target-side fallback position. This uses the existing WeaponTrail skeleton sample at hit time.
- Wired the existing directional reaction clips for player and soldiers. Player hits select Light/Heavy and Front/Back/Left/Right (heavy at 12% max health or 4 m/s knockback); heavy reactions are full body on foot and upper body while swimming or mounted. Soldier hits use directional Light clips or directional Heavy clips above 4 m/s unless the existing ragdoll knockdown path takes over. Player guard break uses `Stagger_Back` and a small backward capsule impulse.
- Changed humanoid-monster and animal attack playback to two phases: scale anticipation to the same authored contact deadline, then restore the clip to 1x for its final 0.2 s. A brief orange flash marks that snap. Damage range/line-of-sight checks, wind-up duration, and cooldowns are unchanged.
- Added the missing camera-only proxy over settlement wells, eased camera pull-in only for camera-layer props such as awnings, and fade the linked well mesh when it hides the lens; solid world walls keep their immediate response.

## Cost notes

- The camera change reuses the player's existing obstruction ray. A settlement creates only one extra static camera-only box per well; there is no new per-frame scene search.
- Block-facing enemy lookup runs at 12.5 Hz while guarding. Hit-stop discovers mixers only for actors actually struck by a non-finisher hit.
- Impact camera feedback adds no scene queries or per-NPC work; the existing access preference controls both positional shake and the FOV pulse.
- Blade spark placement adds one tip sample per confirmed swing resolution and no new physics query.
- Directional hit selection is a handful of vector dot products per received hit; clip choice adds no ongoing AI or per-frame work. Soldier ragdolls remain governed by their existing heavy-hit cap.
- Enemy wind-up adds one float comparison per active strike; the cue is emitted once per attack-token holder. The attack token budget continues to cap simultaneous cue effects.
- Run-stop playback adds no NPC work; the optional state graph is created only for the player animator.

## Deliberately deferred

- Walk/run starts are not wired. Their authored clips enter at nonzero foot speed while the current capsule accelerates from rest; with root translation disabled, this needs a measured acceleration/phase handoff to avoid visible foot skating.
- Walk stop, sprint skid, pivots, and idle turns are not wired. They need capsule path/yaw and event timing hooked to the sidecar before enabling them.
- Market-stall MultiMesh batches are eased but not faded; fading a shared batch would hide unrelated stalls. A future per-instance material or visibility solution should be benchmarked before adding more camera-driven effects.
- Contextual vault/climb, surface-specific grass/leaf jump effects, and fall camera pitch remain future integration work.

## Validation needed

1. Open the project in Godot 4.6.3 so the new GLB import is generated, then run `tools/anim/loco/verify_loco.gd`.
2. In a playable build, check standing jump, running jump, coyote/buffer behavior, fall-from-ledge, 5 m forward roll, damage beyond 6 m, water landing, and jump/button spam.
3. Confirm the RunStop_L/R side selection visually against the planted foot and verify the capsule covers approximately 1.4–1.7 m before reaching idle.
4. Orbit the camera around the plaza well and market awnings; verify camera-layer canopies ease the pull-in while solid walls still pull in immediately, and that the well proxy does not affect player movement.
5. Check 16:9, portrait/mobile, and one-handed HUD layouts for Jump/Attack overlap and touch reach.
6. Tune anything that drifts on the actual player rig, then land this branch into Claude's active line.
7. Check each wolf, goblin, orc, troll and other creature attack in a playable build: animation contact must still coincide with the unchanged gameplay hit frame after the snap-speed change.

## Environment caveat

The available checkout had an incomplete `.godot/imported` cache. The prior `verify_loco.gd` attempt failed because the imported scene cache was absent (and other project imports were also missing), not because the GLB had failed Claude's documented Godot 4.6.3 verification. Avoid a full cold import here; the repository notes that it can require about 30 minutes and 7 GB.
