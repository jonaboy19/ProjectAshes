# Locomotion speed review

**Source snapshot:** `docs/qa/anim_qa_report.md`, generated 2026-09-27 with the Godot 4.6 game-loader animation QA.  
**Purpose:** a quick implementation handoff for the most visible gait mismatch, with the complete actor table in the offline [filterable review board](LOCOMOTION_SPEED_REVIEW.html).

## What is wrong

The measured walk/run clip often covers a different distance per second than the character is moved by gameplay. The result is feet sliding or cycling faster than the ground travel. In this QA snapshot, **54 of 62 movement-speed cases fail**, one warns, and seven pass. The existing visual review found that the humanoid clips themselves mostly look natural; the biggest problem is how the game plays them.

The player issue is visible in the controller wiring: `CharacterAnimator` places the walk clip at half of the run-speed argument and the run clip at the full run speed. With `RUN = 7.0`, that means blend points at 3.5 and 7.0 m/s. At `WALK = 4.2`, the tree requests roughly 80% walk and 20% run; the game-loader QA measures that blend at 2.09 m/s. The [interactive blend-space audit](PLAYER_BLENDSPACE_AUDIT.html) compares those current points with candidate points near the measured clip speeds. It reports weights, not predicted motion, so the candidate still needs the existing posed-mesh QA and a foot-contact visual review.

| Case | Game speed | Measured clip speed | Ratio | Current read |
|---|---:|---:|---:|---|
| Player walk | 4.20 m/s | 2.09 m/s | 2.01× | Feet lag behind the character |
| Player block walk | 2.10 m/s | 0.63 m/s | 3.32× | Severe foot sliding |
| Villager walk | 1.60 m/s | 0.98 m/s | 1.64× | Feet lag behind |
| Villager catch-up | 4.80 m/s | 0.98 m/s | 4.91× | Walking clip while moving at catch-up speed |
| Wolf stalk | 3.50 m/s | 0.64 m/s | 5.49× | Walk cycle while moving too fast |
| Wolf attack run | 7.50 m/s | 2.63 m/s | 2.86× | Gallop still falls behind |
| Goblin run | 5.20 m/s | ~0 m/s | Undefined | Clip has no reliable ground-contact travel measurement |
| Orc walk | 1.30 m/s | 1.25 m/s | 1.04× | In band |

Small animals and birds need species-specific treatment: their short hop/waddle cycles can measure near-zero ground speed at the configured scale, so simply applying the human walk rate produces sliding. Some farm animal retargeted clips also stretch a front-foot bone. The board links four existing game-scale motion sheets so reviewers can compare measurements with the actual poses.

## What to change first

1. Keep player/gameplay movement responsive and tune locomotion playback to **resolved planar speed**, with rig/clip-specific ground-speed values. Do not use one global multiplier for every actor. In the current `CharacterAnimator`, the walk blend point is always `run_speed * 0.5` and the run point is `run_speed`. For the player those points are 3.5 and 7.0 m/s, while QA measured `Walking_A` at about 0.98 m/s and `Running_A` at 5.4–6.2 m/s on the in-game-height rigs. At the 4.2 m/s walk speed this therefore blends 80% walk and 20% run, and the resulting clip blend measures only 2.09 m/s. First evaluate per-rig blend points near each clip's measured ground speed, then remeasure the in-between blends at 1, 2, 3, 4.2, and 7 m/s. Do not simply set every clip's playback rate to `game_speed / clip_speed`; a large time-scale can make the cadence look frantic while the ratio improves.
2. Give villagers a distinct catch-up behavior: transition to a run clip or cap catch-up at a believable jog, and blend out at arrival. Do not play `Walking_A` at 4.8 m/s.
3. Separate wolf roam, stalk, chase, and flee gait thresholds. The stalk case is currently much faster than the walk clip can cover.
4. Treat creatures and animals as their own calibration groups. Reject zero-contact/zero-speed run clips for high-speed use until the clip/rig is repaired or replaced.
5. Preserve the 0.85–1.18× target band as a first-pass metric, then review each clip visually for planted-foot slip, heading, loop seam, pose pops, and floor contact. A ratio alone cannot prove natural motion.

For Godot-specific implementation, an `AnimationNodeBlendSpace1D` can place walk and run at calibrated speeds; `AnimationNodeTimeScale` adjusts the child animation rate when a small per-clip correction is needed. Godot also exposes root-motion deltas for an `AnimationTree`, which can be fed into `CharacterBody3D.move_and_slide()`. Root motion is an option for authored actions or a separately evaluated locomotion path; never let extracted animation displacement compete with a second independent movement controller.

The plan's Phase 4 covers ownership, blending, interrupts, combat timing, and full-rig review. The existing [knockback retarget board](HIT_KNOCKBACK_RETARGET_REVIEW.html) is a cautionary example: an apparent improvement on one Blender reference rig still left substantial failures across the 27 in-game avatar profiles.

Implementation references: [Godot 4.6 Using AnimationTree](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html), [AnimationNodeBlendSpace1D](https://docs.godotengine.org/en/4.6/classes/class_animationnodeblendspace1d.html), and [AnimationNodeTimeScale](https://docs.godotengine.org/en/4.6/classes/class_animationnodetimescale.html).

## Limits of this review

This board is a static view of the measured QA snapshot, not a live before/after gameplay capture. It identifies where actual game speed and clip ground speed disagree; it does not prove that a specific time-scale or retimed asset will look good. Verify any implementation on the game route with the player, a villager, a soldier, a wolf, and representative animal rigs before accepting the fix.
