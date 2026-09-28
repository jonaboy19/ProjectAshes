# Movement QA bot

Boots the real game (`res://scenes/main.tscn`, instanced as a child, same pattern as
`tools_qa/autoplay`) on the real GPU and drives the player through real keyboard input
(`Input.parse_input_event` with the physical keycodes from `Game._setup_input` /
`Player._ensure_actions`), then screenshots a strip of frames for each movement
scenario so the result can be looked at, not just measured.

## Run

```bash
kingdom/tools_qa/movement_qa/run_movement_qa.sh
```

Set `GODOT=/path/to/Godot_console.exe` if Godot isn't at the default path. Output goes to
`docs/qa/movement/`:

| Path | What |
|---|---|
| `01_walk/`, `02_run/`, `03_stop/`, `04_turn180/`, `05_backward/`, `06_slope/`, `07_dodge_space/`, `08_ability_dash_r/` | JPG frame strips, one folder per scenario |
| `log.txt` | timestamped scenario markers and measured values (speed, invulnerable window, cooldown) |
| `godot_stdout.txt` / `errors.txt` | raw console output and SCRIPT ERROR / ERROR / WARNING lines |

## Scenarios

1. **Walk** — tap-and-hold `W`, no Shift: normal walking speed.
2. **Run** — `Shift+W`: sprint.
3. **Stop** — release both: should brake smoothly, no ice-skid.
4. **Turn 180** — face one way, then reverse the stick: should turn at a bounded rate,
   not snap instantly.
5. **Backward** — hold `S` only: the character turns to face the direction of travel and
   walks "forward" in the new facing (camera-relative controls), not a moonwalk.
6. **Slope** — sprint toward the forest/camp road, which climbs and dips: watch for
   bouncing, clipping through the ground, or getting stuck on the incline.
7. **Dodge (Space)** — the plain dodge-roll: short i-frame step, no afterimage VFX.
8. **Shadow Dash ability (R)** — the fast burst with the afterimage VFX, then an
   immediate second press to confirm the cooldown blocks it.

To add a scenario, add a block to `_run()` in `movement_qa.gd` using `key()`, `shot()`,
`begin_scenario()` and `hold_and_shoot()`.
