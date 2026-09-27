# Locomotion speed review

**Source snapshot:** `docs/qa/anim_qa_report.md`, generated 2026-09-27 with the Godot 4.6 game-loader animation QA.  
**Purpose:** a quick implementation handoff for the most visible gait mismatch, with the complete actor table in the offline [filterable review board](LOCOMOTION_SPEED_REVIEW.html).

## What is wrong

The measured walk/run clip often covers a different distance per second than the character is moved by gameplay. The result is feet sliding or cycling faster than the ground travel. In this QA snapshot, **54 of 62 movement-speed cases fail**, one warns, and seven pass. The existing visual review found that the humanoid clips themselves mostly look natural; the biggest problem is how the game plays them.

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

1. Keep player/gameplay movement responsive and tune locomotion playback to **resolved planar speed**, with rig/clip-specific ground-speed values. Do not use one global multiplier for every actor.
2. Give villagers a distinct catch-up behavior: transition to a run clip or cap catch-up at a believable jog, and blend out at arrival. Do not play `Walking_A` at 4.8 m/s.
3. Separate wolf roam, stalk, chase, and flee gait thresholds. The stalk case is currently much faster than the walk clip can cover.
4. Treat creatures and animals as their own calibration groups. Reject zero-contact/zero-speed run clips for high-speed use until the clip/rig is repaired or replaced.
5. Preserve the 0.85–1.18× target band as a first-pass metric, then review each clip visually for planted-foot slip, heading, loop seam, pose pops, and floor contact. A ratio alone cannot prove natural motion.

The plan's Phase 4 covers ownership, blending, interrupts, combat timing, and full-rig review. The existing [knockback retarget board](HIT_KNOCKBACK_RETARGET_REVIEW.html) is a cautionary example: an apparent improvement on one Blender reference rig still left substantial failures across the 27 in-game avatar profiles.

## Limits of this review

This board is a static view of the measured QA snapshot, not a live before/after gameplay capture. It identifies where actual game speed and clip ground speed disagree; it does not prove that a specific time-scale or retimed asset will look good. Verify any implementation on the game route with the player, a villager, a soldier, a wolf, and representative animal rigs before accepting the fix.
