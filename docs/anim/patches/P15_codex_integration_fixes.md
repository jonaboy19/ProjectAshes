# P15: fixes made while landing `gpt/locomotion-jump-integration` (for Codex)

Landed into `claude/focused-curie-m09hbd` on 2026-10-01. Review: [CODEX_INTEGRATION_REVIEW.md](../CODEX_INTEGRATION_REVIEW.md).
Both fixes are already applied on the Claude branch. Please pull them in rather than re-implementing.

## 1. Dodge lane probe did not compile (blocked the whole game)
`Player._dodge_obstruction()` passed a `PhysicsTestMotionResult3D` to `CharacterBody3D.test_move()`, but that argument must be a
`KinematicCollision3D`. That was a parse error in `player.gd`, which cascaded through `quality.gd` and `terrain_streamer.gd`, so nothing could boot.
```gdscript
var result := KinematicCollision3D.new()
if test_move(global_transform, direction * distance, result):
    return result.get_collider() as Node3D
```
Lesson: run at least `godot --headless --path kingdom --import` (it parses every script) before handing off a branch.

## 2. A tapped jump gave a 0.23 m hop
The variable-height cut (`velocity.y *= 0.45` when Jump is released) ran on the first air frame. A tap is released during the
0.13–0.15 s take-off wind-up, so every tap was cut, and that includes every normal touch-button press. Measured in game: apex +0.23 m, 10 air frames.
Fix: the cut can only happen after `JUMP_CUT_MIN_AGE = 0.1` s of air time, and it scales by `JUMP_CUT_SCALE = 0.6`.
Measured after the fix: tap = +0.78 m, 16 air frames (0.53 s). A held press still reaches the full 1.10/1.25 m.

## 3. Harness and controls follow-ups
- `tools_qa/feel_capture` now taps K for dodge (Space is Jump since your split). It also has new scenarios: 19 jumps, 20 falls, 21 parry,
  22 directional and heavy hits plus guard break, and 23 companions follow/stop/fight.
- Merge decision: Skills moved from K to **F2** as you intended, and Claude's Cultivation tab stays.
- HUD (Claude's new layout): Jump is posed at `_at(168, 300)` above Attack and hides while the small combat Interact uses that slot.
  Please confirm one-handed reach on the S22.

## Open items for Codex (not fixed here)
- **Run stop:** the capsule stops in about 0.4 s (1.3 m from 6.4 m/s). The stop clip then blends to idle with a small sword-arm pop
  around +0.4 s. The 1.4–1.7 m target in your handoff is not reached, so consider easing the brake while `Loco_RunStop_*` plays.
- **Block facing after a parry knock-down:** the player re-faces away from the downed orc. The nearest-threat query probably skips downed enemies.
  Keep the last facing instead of falling back to the camera heading.
- **Companions:** after the player stops, the knights keep running for about 1 s while they swing round to their slots (sheet frames #60–69), then they leave frame.
  Their own stop-to-idle was not framed closely enough to judge. A close capture is needed, and probably a stop transition in `soldier.gd`.
- Still deferred from your list: walk/run starts, walk stop, sprint skid, pivots, idle turns (P5), P6 NPC foot-IK cost tiers, and P9 attack layering.
