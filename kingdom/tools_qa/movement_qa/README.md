# Movement QA bot

Boots the real game (`res://scenes/main.tscn`, instanced as a child, same pattern as
`tools_qa/autoplay`) on the real GPU and drives the player through real keyboard input
(`Input.parse_input_event` with the physical keycodes from `Game._setup_input` /
`Player._ensure_actions`), then screenshots a strip of frames for each movement
scenario so the result can be looked at, not just measured.

**v2 (2026-09-28):** v1 spawned at a fixed offset from the village plaza that happened
to land the player against a market stall, so walk/run/stop never actually displaced
(every frame identical) and the camera's own wall-avoidance ray pulled it into the
character's head on the 180 turn — the strips looked broken because nothing was being
tested, not because movement was broken. v2 finds real open ground along the village's
own gate/road direction, verified clear with a ring of raycasts (`_ground_clear`), and
asserts real displacement after every scenario (`assert_moved` / `assert_true`), logged
as PASS/FAIL in `log.txt`. Exit code is non-zero if any assertion fails.

## Run

```bash
kingdom/tools_qa/movement_qa/run_movement_qa.sh --out=docs/qa/movement/v2/after
```

Set `GODOT=/path/to/Godot_console.exe` if Godot isn't at the default path. Default output
is `docs/qa/movement/v2/after/`:

| Path | What |
|---|---|
| `01_walk/` … `11_ability_dash_r/` | JPG frame strips, one folder per scenario |
| `log.txt` | timestamped scenario markers, per-frame speed/position, and PASS/FAIL assertions |
| `godot_stdout.txt` / `errors.txt` | raw console output and SCRIPT ERROR / ERROR / WARNING lines |

## Scenarios

1. **Walk** — tap-and-hold `W`, no Shift: normal walking speed. Asserts displacement.
2. **Run** — `Shift+W`: sprint. Asserts displacement.
3. **Stop** — release both: should brake smoothly, no ice-skid. Asserts end speed < 0.5 m/s.
4. **Turn 180** — face one way, then reverse the stick: should turn at a bounded rate,
   not snap instantly. Asserts facing actually reversed.
5. **Backward** — hold `S` only: the character turns to face the direction of travel and
   walks "forward" in the new facing (camera-relative controls), not a moonwalk. Asserts displacement.
6. **Strafe** — hold block (`L`) + `D`: forces `_strafing`, so travel is sideways while
   facing holds. Asserts displacement at the blocking speed cap.
7. **Slope** — sprint toward the forest/camp road, which climbs and dips: watch for
   bouncing, clipping through the ground, or getting stuck on the incline. Asserts
   displacement and that the player is grounded (not launched/bounced) at the end.
8. **Wall collision** — sprint straight into the village wall: should stop cleanly, no
   jitter or bounce-back. Asserts the frame-to-frame speed doesn't oscillate once
   pressed against the wall.
9. **Crowd** — walk through villagers in the plaza: watch for getting stuck or shoved
   off course. Logged, not hard-asserted (NPCs aren't deterministic).
10. **Dodge (Space)** — the plain dodge-roll: short i-frame step, no afterimage VFX.
    Asserts displacement.
11. **Shadow Dash ability (R)** — the fast burst with the afterimage VFX, then an
    immediate second press to confirm the cooldown blocks it. Asserts displacement and
    that the second press is refused.

To add a scenario, add a block to `_run()` in `movement_qa.gd` using `key()`, `shot()`,
`begin_scenario()`, `hold_and_shoot()` and `assert_moved()` / `assert_true()`.
