# Player movement: report v1 (2026-09-28)

## The bug the user saw ("Space or back does a shadow dash with afterimages")
- `kingdom/autoload/game.gd` bound Space to the only `"dodge"` action.
- `Player._start_dodge()` always ran one code path: a 4→12 m/s burst that **always** called `VFX.afterimage(...)`. It was gated only by 15 stamina, with no cooldown.
- With no direction held (standing still, or backpedalling on S), it took the `backward` branch and played `Dodge_Backward` with the same trail. That's the "back triggers a shadow dash" the user saw.

## Fix (commit 0f4016cd)
| Input | Now |
|---|---|
| **Space** / HUD dodge button | Plain short roll, 3.2→7.0 m/s, **no VFX**, 15 stamina, 0.35 s i-frames |
| **R** / left shoulder / violet HUD button | **Shadow Dash ability**: 4→12 m/s, afterimage VFX, 30 stamina, **4 s cooldown** (the button dims and counts down) |
| **S / back** | Walks backwards: the character turns to face the travel direction at a bounded rate. No dash, no VFX |
- No jump was added: none exists, and the library's `Jump*` clip sinks 8–13 cm into the floor (`docs/qa/anim_qa_report.md`). This is a follow-up for Codex.
- Speeds are unchanged (WALK 2.4, RUN 6.5); Codex speed-matched the blend space to them.

## Verification: v1 was INVALID
The main session reviewed `docs/qa/movement/01_walk`–`04_turn180`. In walk, run and stop the player was pinned against a market stall, so the frames are identical and **nothing about walking or running was tested**. In `04_turn180` the camera clips into the character's head.
The re-test in open ground, and the camera fix / Phantom Camera evaluation, go in `docs/qa/movement/v2/`.
