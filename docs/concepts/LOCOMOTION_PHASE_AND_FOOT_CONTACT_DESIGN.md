# Locomotion phase and foot contact for Rising Ashes

**Audience:** Claude's gameplay branch `claude/focused-curie-m09hbd`

**Purpose:** a measured follow-up for walk/run blend phase and uneven-ground foot contact. It does not change gameplay code or Blender assets. Refresh source and the active Claude animation QA before implementation.

## Why evaluate this after the current animation QA

The reviewed `kingdom/scripts/actors/character_animator.gd` creates one `AnimationNodeBlendSpace1D` with Idle at 0, Walking_A at half of run speed, and Running_A at full run speed. It does not set a synchronization mode. The current working-copy animation QA already identifies larger problems first: locomotion playback speed mismatches across many rigs, selected skinning/retarget defects, and unaligned wolf/goblin walk/run cycles.

Do not change animation timing or add IK until the current clip, retarget, and speed corrections have been compared by Claude. Phase synchronization cannot make the body travel at the correct speed, and foot IK cannot repair bad weights, a malformed stride, or a clip with no usable contact phase.

## Godot 4.6 phase sync: a controlled experiment, not a blanket toggle

Godot's `AnimationNodeBlendSpace1D` supports synchronization modes. `Cyclic Mutable` time-scales blended clips to align their phases and computes a shared cycle from the blend weights; a lone clip still plays at its normal speed. The documented use case is a set of animations with the same logical repeating cycle. Cyclic modes require finite, immutable `AnimationNodeAnimation` inputs. TimeSeek on the output can break this synchronization.

That does **not** mean Idle, Walk, and Run should automatically be phase-locked in the current three-point blend. Idle is not a gait cycle. Test phase sync first on only a compatible Walk/Run pair. If the same `BlendSpace1D` also needs Idle, compare a design with Idle-to-moving handled by a separate state/crossfade and a Walk/Run synchronized subgraph. Keep the current graph if the split adds complexity without a visible improvement.

### A/B review protocol

For each compatible rig family, compare the same captured playback at the same actual body velocity:

1. Current unsynchronized graph at speed ratios 0.85, 1.0, and 1.18 of measured clip ground speed.
2. Walk/Run-only `Cyclic Mutable` phase-sync candidate at the same ratios.
3. Idle-to-walk start, walk-to-run, run-to-walk, stop, 90-degree turn, backward/strafe if supported, attack overlay, and dodge recovery.
4. Repeat on LOW and HIGH and at render caps supported by the project; keep the physics rate fixed and record it.

Review heel/toe contact, planted-foot drift, hip bounce, knee direction, phase pop, and whether either clip appears to speed up unnaturally as blend weights change. A green metric cannot overrule an ugly pose. Promote the candidate only if the feet stay better phased through transitions and the measured body speed still matches the weighted clip travel.

Godot's blend nodes and AnimationTree state transitions are explained in the official [AnimationTree guide](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html) and the `BlendSpace1D` class reference. The guide distinguishes `None`, `Independent`, `Cyclic Mutable`, and `Cyclic Constant`; only the cyclic modes align phases, and those are for compatible cycle inputs.

## Foot contact on uneven ground: targeted near-actor IK

Once stride speed and base rig deformation are accepted, a limited foot-placement pass may help feet settle on slopes, shallow ruts, and irregular stones. Godot 4.6 includes `TwoBoneIK3D`, a `SkeletonModifier3D` that solves a root/middle/end chain toward a target using a pole target. Skeleton modifiers process after the `AnimationMixer`, making them suitable for a post-animation correction layer.

Keep the correction physically and visually bounded:

- Sample the intended ground beneath each foot with a filtered downward query. Use collision surfaces that represent the walkable floor; exclude the actor, triggers, foliage, and decorative surfaces that should not support a foot.
- Apply the target only during a credible stance/contact window. Let the animated foot swing freely; blending the foot to terrain while airborne creates a sticky shuffle.
- Smooth target entry/exit and limit vertical correction, pitch, reach, and pelvis compensation. If the target is outside leg reach or requires a large pose change, reduce IK influence and let the authored animation win.
- Keep the CharacterBody3D capsule, root motion, and resolved movement as the movement authority. Bone IK changes the visible pose; it does not move the actor or solve route/collision defects.
- Configure per skeleton family. Verify root/middle/end chain hierarchy, bone rest axes, pole direction, foot/toe orientation, retarget rest pose, and skin weights in Blender and the Godot game-loader preview. Do not assume matching bone names mean matching axes or proportions.
- Limit runtime work to the hero and selected nearby embodied actors after profiling. Do not run per-foot terrain queries and modifiers for every resident or impostor.

### Blender and engine review strip

For an accepted rig family, export a small checkerboard scene/pose review containing: standing rest pose, in-place walk and run loops, blend weights 0/25/50/75/100%, a slow planted turn, a short slope, a cross-slope, and a one-step height change. Show sole contact markers, foot target, pelvis height, knee pole, and the unmodified animation ghost alongside the IK result. Blender is useful for inspecting rest pose, weights, and contact timing. Accept final playback only from the game's own Godot loader, scale, AnimationTree, modifiers, and controller because Blender alone does not reproduce that blend or import path.

The current Claude checkout already has an active game-loader animation report and visual asset/rig QA. Use its next accepted baseline and extend its sheet for this specific A/B; do not create a competing clip-speed or retarget report.

## Acceptance evidence

- A table identifies which rigs have a valid two-bone leg chain and which are excluded, with reasons.
- The unsynchronized and candidate-synchronized clips use the same body speed, physics tick, frame cap, blend weights, and camera.
- On flat ground, IK stays near zero correction and does not distort the calibrated gait.
- On slopes and a small step, stance feet show less measured penetration/slip without knee flips, toe twisting, pelvis pumping, cloth distortion, or planted-foot skating.
- The foot releases cleanly for swing, turn, attack, dodge, hit reaction, death, and LOD transitions.
- Report body/clip speed ratio, planted-foot slip, maximum floor penetration, target reach clamping, modifier/active rig count, and frame-time p50/p95 for LOW and HIGH.
- Keep a normal gameplay capture next to the debug sheet. The debug view explains a pose; it does not prove that the movement feels natural at gameplay camera distance.

## References

- Godot 4.6 [AnimationTree guide](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html) — sync modes and blend/state graph behavior.
- Godot 4.6 [AnimationNodeBlendSpace1D](https://docs.godotengine.org/en/4.6/classes/class_animationnodeblendspace1d.html) — blend space inputs and sync property.
- Godot 4.6 [TwoBoneIK3D](https://docs.godotengine.org/en/4.6/classes/class_twoboneik3d.html) — root/middle/end chain, target, and required pole target.
- Godot 4.6 [SkeletonModifier3D](https://docs.godotengine.org/en/4.6/classes/class_skeletonmodifier3d.html) — modifiers execute after AnimationMixer playback.
- Current project evidence: [Claude animation QA context](CURRENT_RUN_VISUAL_REVIEW.md#relationship-to-ongoing-work), [locomotion speed review](LOCOMOTION_SPEED_REVIEW.md), and [natural-world implementation plan](NATURAL_WORLD_FEEL_PLAN.md).
