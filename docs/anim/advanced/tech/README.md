# Advanced runtime animation tech (Godot 4.6 built-ins) - DONE

Demo scene: `kingdom/tools_qa/anim_tech/anim_tech_demo.tscn` (keys 1-0 pick a technique, T toggles it, N/P next/prev, H hit).
Capture strips: `Godot --path kingdom --rendering-method mobile res://tools_qa/anim_tech/anim_tech_demo.tscn -- --capture=<abs dir> --tech=flinch,lean [--nosnap]`
(`--nosnap` = run the metrics at full speed without frame grabs; never use `--headless`, it renders black).
Perf: `... -- --bench=<abs json>` (results of the last run: `bench_results.json`).
Each technique is `techs/t_<id>.gd` (coroutine `run(d, my)`), reusable code is in `lib/`, perf in `bench.gd`.
Godot must be run from a project that already has its `.godot` import cache (a fresh worktree needs a ~7 GB import first).

**Measurement note (fixes an earlier mistake):** the IK / tree / physical-bone output is NOT visible through `Skeleton3D.get_bone_global_pose()` read from `_process`.
Read it inside the `Skeleton3D.skeleton_updated` signal (foot IK, flinch, lean, tree metrics) or from the `PhysicalBone3D` bodies (ragdoll). The first foot-IK numbers in the old README measured the un-IK'd animation.

## Status

| # | technique | result | strip | lib |
|---|---|---|---|---|
| 1 | foot IK on stairs / ramp | toe probe + instant rise: penetration >2 cm on stairs+ramp **0 %** of planted samples (raw clip 15 %, stock ProceduralRig 6 %; strict exact-under-ball measure 16 / 22 / 0 %). Trade-off: 17 % of samples hover >8 cm above the *lower* surface (the foot rests on the higher step edge) | `foot_ik_{off,rig,toe}.png` | `lib/foot_ik.gd` (extends ProceduralRig) |
| 2 | head look-at | working (see below) | `look_at.png` | `lib/look_at.gd` |
| 3 | cape spring bones | working | `springs.png` | `lib/cape.gd` |
| 4a | partial (upper-body) ragdoll | fixed: no snap; deviation from an un-hit twin is 0 in the first 70 ms (the hit only starts after 2 frames) and ramps to a 0.38 m peak; max body distance from hips 0.68 m (no explosion) | `ragdoll_partial.png` | `lib/partial_ragdoll.gd` |
| 4b | full ragdoll death | settled: pelvis moves max **1.0 mm** per frame (mean 0.2 mm) over 2.0-2.9 s (was mis-measured across the 3 s bake teleport) | `ragdoll_full.png` | `scripts/actors/ragdoll.gd` (unchanged) |
| 5 | additive flinch (OneShot blend -> Add2, 4 directions) | legs unaffected (foot offset 0.000 m vs the un-hit twin), chest recoil 1.4-3 cm; front / left / right from `Hit_Chest / Hit_A / Hit_Head`, back = inverted chest recoil (`Hit_B` is a full fall) | `flinch.png` | `lib/flinch.gd` |
| 6 | velocity lean + aim twist | lean into turns; aim twist follows a target within 14 deg (spring lag) at +-75 deg | `lean.png` | `lib/lean_aim.gd` |
| 7 | synced locomotion blend space (idle/walk/jog/sprint) | 1 s normalized timelines + measured foot-phase offsets; stride amplitude at mid speeds 0.97-1.04 of the neighbours (naive tree with `sync=true` is already 0.96-0.97, so the gain is small; the phase offsets matter mainly for clips that start on the other foot) | `blendtree.png` | `lib/loco_tree.gd` |
| 8 | root-motion attacks | travel 0.81 m (Karate_Oi_Zuki), 1.2 m (MA_Kick_Jump_R), 0.62 m (MA_Kick_JumpHigh_A); attacker closes 0.4-0.5 m more than the in-place clip at the hit frame | `rootmotion.png` | `lib/at_util.gd` (`enable_root_motion`, `apply_root_motion`) |
| 9 | hitstop + camera shake | freeze measured 83-89 ms for a 0.08 s local freeze (attacker + victim mixers, world keeps running); shake peak 0.059 m; hit frame taken from the hand-speed peak (frame 8 of `Sword_Regular_A`) | `impact.png` | `lib/hitstop.gd`, `lib/camera_shake.gd` |
| 10 | motion warping | lands within 0-6 cm of the stop point and 1-2 deg facing for targets at 1.0 / 2.4 / 3.4 m and 0 / 35 / -50 deg (raw root motion misses by 0.5-1.7 m); travel scale used 0-2.4 | `warp.png` | `lib/motion_warp.gd` |
| - | IK solver survey (CCD / FABRIK / Jacobian / Spline) | dropped: `TwoBoneIK3D` covers legs and arms, nothing else is needed for humanoids | - | - |

Class check (Godot 4.6.3): TwoBoneIK3D, CCDIK3D, FABRIK3D, JacobianIK3D, SplineIK3D, ChainIK3D, IterateIK3D, LookAtModifier3D, SpringBoneSimulator3D (+collisions), PhysicalBoneSimulator3D, RetargetModifier3D, BoneTwistDisperser3D exist. `LimbSolver3D` does not.

Learned the hard way:
- **AnimationTree additive values are rest-relative.** The mixer stores each skeleton track as `rest^-1 * value`, so an additive clip must be written as `rest * delta` (`U.make_additive(anim, ref_time, bones, sk)`). Without the skeleton the character lies on the floor.
- `AnimationTree` has no `speed_scale`: hitstop freezes a tree by switching it inactive (`lib/hitstop.gd`).
- Ragdoll partial hit: creating the bodies then waiting two frames (process + physics) before `physical_bones_start_simulation` is what fixed the wrong-pose snap.

## Performance (`bench.gd`, PC RTX laptop, mobile renderer; phone ~ x5, see `ashes-performance`)
CPU ms per character per frame for animation + technique only. Method: mixers and skeleton modifier stacks are put in MANUAL mode and advanced inside a microsecond timer (plus the rig's ray code), N = 10 / 25 / 50 characters walking on circles; wall-clock frame time drifted +-30 % between runs, more than these costs. Ragdolls need the physics server, so they use the wall-clock slope (N <= 3, the cap is 3 live).

| technique | + ms / char (PC) | phone (x5) |
|---|---:|---:|
| plain clip (AnimationPlayer + skeleton, baseline) | 0.053 | 0.27 |
| lean + aim twist | +0.006 | +0.03 |
| head look-at (2 modifiers) | +0.005 | +0.03 |
| cape springs (12 bones) | +0.006 | +0.03 |
| foot IK + toe probe (2 TwoBoneIK3D, 6 rays / tick) | +0.056 | +0.28 |
| root motion + warp step | +0.074 | +0.37 |
| synced locomotion tree (AnimationTree) | +0.095 | +0.48 |
| additive flinch tree, idle | +0.095 | +0.48 |
| additive flinch tree, hit every 0.6 s | +0.123 | +0.62 |
| partial ragdoll (hit every 1 s, wall slope) | ~+0.37 | ~+1.9 |
| full ragdoll simulating (wall slope, noisy) | <= +0.02 | <= +0.1 |

An `AnimationTree` costs about twice a plain `AnimationPlayer` clip: use trees for the nearest characters only.

**Quality tiers** (bundle measured together; character budget = 40 % of the frame CPU budget in `ashes-performance`: 6 ms LOW, 3 ms MEDIUM/HIGH on PC):

| tier | what runs per character | ms / char PC | phone | characters that fit |
|---|---|---:|---:|---:|
| LOW | plain clip | 0.058 | 0.29 | **41** |
| MEDIUM | synced loco tree + lean/aim + flinch tree | 0.218 | 1.09 | **5** |
| HIGH | MEDIUM + foot IK + look-at + cape | 0.290 | 1.45 | **4** |

Rule that follows: full techniques (HIGH) for the 3-4 nearest characters, MEDIUM for the next 4-5, everyone else on the plain clip (LOW) or the sprite impostor. `ProceduralRig` already ranks by camera distance and gates by `Quality.rig_budget`; use the same ranking for the trees and modifiers.

## HANDOFF for Codex (behaviour)
All libs are `RefCounted`/`SkeletonModifier3D` scripts, no autoloads, no `class_name`; `preload` them. None of this touches `assets.gd` or `procedural_rig.gd`.

| want | call | notes |
|---|---|---|
| stair-safe foot IK | `FootIK.attach_toe(model, body, is_player)` from `lib/foot_ik.gd` (same contract as `ProceduralRig.attach`; `set_state`, `set_paused`) | drop-in for `ProceduralRig.attach`. Two changes worth folding into `procedural_rig.gd`: (a) also ray under the animated ball of each foot and use `max(ankle_hit, ball_hit)`; (b) follow a RISING ground instantly (`_ground[i] = max(_ground[i], d)` before the lerp), smooth only falling ground |
| additive flinch | `var f := Flinch.attach(model, base_clip)`; `f.set_base(clip)`; `f.hit(Vector2(right, front), amount)`; `f.is_flinching()` | replaces the AnimationPlayer as pose driver: fold the OneShot(blend) -> Add2 (filtered to spine_01..03, neck, head, clavicles, upper arms) into `CharacterAnimator`'s tree instead of using a second tree. Fade 0.03 in / 0.16 out |
| lean + aim twist | `var m := LeanAim.attach(model, actor_node)`; `m.aim_target = node`; `m.aim_weight`, `m.lean_weight` 0..1 | SkeletonModifier3D under the Skeleton3D, put it before the springs. LOD: `m.active = false` |
| locomotion | `Loco.attach(model, Loco.SYNC_PHASE)`; `set_speed(m_per_s)` each frame | `CharacterAnimator` already normalizes gait timelines; add the per-clip `start_offset` (`Loco.offsets`, left foot forward at phase 0) and a sprint point |
| hit stop | `d.hitstop.freeze_local([attacker_player, victim_player_or_tree], 0.06..0.10)`; `freeze_global(0.12)` for finishers | light 0.04-0.06 s, heavy 0.08-0.10 s, kill 0.12-0.18 s. Trigger on the hit frame (see `docs/anim/free_library/HANDOFF_CODEX.md` for per-clip hit frames), pair with `ElementFX.play` on the same frame |
| camera shake | `CameraShake` node with `camera = cam`; `add_trauma(0.35 light .. 0.8 heavy, Vector2(1,0))` | writes only `h_offset / v_offset / fov`, composes with any follow camera; `strength = 0` for "reduce screen shake" |
| root motion attack | `U.own_copy(ap, clip, true)` (or `U.import_clips(..., root_motion=true)`), `U.enable_root_motion(ap, sk, anim)`, then each frame `U.apply_root_motion(ap, sk, actor)` | the stock `root` track is disabled by `_ual_for`; use a per-player copy |
| motion warp | `var w := MotionWarp.new(); w.begin(ap, sk, actor, clip, target_node_or_pos, stop_dist)`; each frame after the player advanced `w.step(delta)`; `w.done` | window auto-detected (10-95 % of the root travel); turn rate 12/s, scale clamp 0.35-2.4; use `stop_dist` = weapon reach |
| partial ragdoll | `PartialRagdoll.attach_partial(actor, model, [player_or_tree])`; `hit_react(push_dir, 3.0)` | counts against `Ragdoll.MAX_LIVE`; ~12 bodies per hit |
| LOD | modifiers/trees: `active = false` beyond ~25 m or when out of the tier's budget; cape: `cape.active = false` | measured costs above |
