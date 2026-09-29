# Advanced runtime animation tech (task B) - PARTIAL, work in progress

Demo scene: `kingdom/tools_qa/anim_tech/anim_tech_demo.tscn` (keys 1-0 pick a technique, T toggles it, N/P next/prev).
Capture PNG strips: `Godot --path kingdom --rendering-method mobile res://tools_qa/anim_tech/anim_tech_demo.tscn -- --capture=<abs dir> --tech=foot_ik,look_at,springs,ragdoll`
Each technique is `techs/t_<id>.gd` (coroutine `run(d, my)`), reusable code is in `lib/`.

## Status

| # | technique | state | preview | lib |
|---|---|---|---|---|
| 1 | foot IK on stairs/ramp (TwoBoneIK3D) | working, visually checked | `foot_ik_off.png`, `foot_ik_rig.png`, `foot_ik_toe.png` | `lib/foot_ik.gd` (extends ProceduralRig, adds a toe-ball probe) |
| 2 | LookAtModifier3D head/neck | working, visually checked | `look_at.png` | `lib/look_at.gd` |
| 3 | SpringBoneSimulator3D cape | working, visually checked | `springs.png` | `lib/cape.gd` |
| 4 | ragdoll | full death via existing `ragdoll.gd` works (`ragdoll_full.png`); PARTIAL upper-body hit reaction NOT working yet (`lib/partial_ragdoll.gd`, see below) | `ragdoll_*.png` | `lib/partial_ragdoll.gd` |
| 9 | hitstop + camera shake | code written, not yet demoed | - | `lib/hitstop.gd`, `lib/camera_shake.gd` |
| 5,6,7,8,10,11 | additive flinch, lean/aim twist, synced blend tree, root motion, motion warp, IK survey | NOT started (listed in `anim_tech_demo.gd` TECHS, scripts missing) | - | - |
| perf | ms/char table (`bench.gd`) | NOT started | - | - |

Class check (Godot 4.6.3): TwoBoneIK3D, CCDIK3D, FABRIK3D, JacobianIK3D, SplineIK3D, ChainIK3D, IterateIK3D, LookAtModifier3D, SpringBoneSimulator3D (+SpringBoneCollision*), PhysicalBoneSimulator3D, RetargetModifier3D, BoneTwistDisperser3D exist. `LimbSolver3D` does not.

## Findings so far
- Foot IK: the existing `ProceduralRig` already lifts feet on 17 cm stairs and 22 degree ramps; raw clip sinks feet into steps. Toe-in-surface (>2 cm) planted-foot samples on stairs+ramp: off 12 %, ProceduralRig 10 %, with toe probe 8 %. Suggested patch for Codex: in `ProceduralRig._physics_process` also ray under the animated ball of each foot and use `max(ankle_hit_y, ball_hit_y)` (see `lib/foot_ik.gd`).
- LookAt: two chained modifiers (neck_01 28 deg, Head 55 deg). Beyond the limit the built-in modifier clamps and pitches oddly, so `lib/look_at.gd` fades `influence` out when the target is more than ~105 deg off the facing (interest cone).
- Cape: UAL has no cloth bones, `lib/cape.gd` adds 3x4 bones + a skinned quad mesh + spring simulator + back capsule collider at runtime; ON trails/swings, OFF is a rigid plank.
- Partial ragdoll: with hips/legs kinematic and chest/head/arms simulated the upper body snaps to a wrong pose within 70 ms (arms in rest pose, torso stretched). Suspected cause: joints are created at `physical_bones_start_simulation` while the fresh bodies are not yet placed on the animated pose. Last attempt (await a frame before starting) was untested. Alternative: simulate the whole body at low influence, or a procedural spring recoil on spine bones.

## Addon evaluation (research only, nothing installed; licences read from GitHub on 2026-09-29)
| addon | licence | verdict |
|---|---|---|
| GuilhermeGSousa/godot-motion-matching | MIT | only serious motion-matching candidate; C++ GDExtension, Godot 4.4+, no Android/iOS release binaries (needs own build + profiling), needs root motion on all clips. Not installed. |
| Remi123/MotionMatching, V-Sekai/motion_matching, theroeberry | MIT | stale / module / unverified 4.6: skip |
| SeaKrill/Godot-Foot-IK | MIT | reference only (already superseded by TwoBoneIK3D, see procedural_rig.gd) |
| monxa/GodotIK | MIT | GDExtension without mobile binaries: skip, built-in IK covers it |
| Godot 4.6 built-in IK (TwoBone, CCD, FABRIK, Jacobian, Spline) + BoneMap/RetargetModifier3D | engine MIT | use these |
| godot-demo-projects 3d/ragdoll_physics | MIT | reference for partial ragdoll |
| Manik2607/auto-ragdoll, winstonthebaker/simple-ragdoll-wizard | MIT | editor-only generators, optional |
| ywmaa/Advanced-Movement-System-Godot | MIT | only community source with stride/orientation warping, incomplete |
| Eneskp3441/Shaker, ramokz/phantom-camera | MIT | camera shake/framework; own `lib/camera_shake.gd` is enough |
| AVOID | RaidTheory Mixamo retargeter (GPL-3), MrMinimal godot-camera-shake (AGPL-3), catprisbrey OpenAnimationLibraries (no licence), godot-motion-matching-demo (no licence) | do not use |

## Remaining work (usage limit hit)
1. Fix or replace partial ragdoll (see above); re-run `--tech=ragdoll`; fix full-ragdoll jitter metric (measure only 2.0-2.9 s, the 3 s bake teleports the root).
2. Write `techs/t_flinch.gd` (OneShot ADD + Blend2 amplitude + BlendSpace2D of additive clips from `U.make_additive`; verify the additive delta convention), `t_lean.gd`, `t_blendtree.gd`, `t_rootmotion.gd`, `t_warp.gd`, `t_impact.gd`, `t_ik_survey.gd` and their libs.
3. `bench.gd` (referenced by `anim_tech_demo.gd --bench=`) measuring ms/char at N=1/10/25/50 per technique, then the phone table (x5) and LOD tiers. Note modifiers run inside the skeleton update; LOD by `active = false`.
4. HANDOFF section for Codex (node names, properties, one-liners, LOD rule) and merge into `docs/anim/advanced/README.md` by the lead.
