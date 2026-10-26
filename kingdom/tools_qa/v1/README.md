# v1 headless release harness

`run_v1.sh [stages]` is the release gate from `docs/plans/READY_V1.md`, runnable with no GPU:

1. `godot --headless --import` (twice, to settle the class cache)
2. the whole gdUnit suite (`res://tests`; exit 0 and 101 count as pass)
3. `tools_qa/playtest_bot/playtest_bot.gd` headless with `PLAYTEST_STAGES=<stages>` and `PLAYTEST_OUT=$OUT`
4. `verdict.py` reads the bot's `summary.json` + stdout

Default stages: `boot,intro,menus,st_birth,st_a1`. Full gate sequence: see "Release gate" in the plan.

```
export GODOT=/path/to/Godot_v4.6.3-stable_linux.x86_64   # 4.6.3-stable from godotengine/godot releases
OUT=/tmp/v1_out kingdom/tools_qa/v1/run_v1.sh boot,intro,menus,st_birth,st_a1
```

Env: `OUT`, `V1_SKIP_IMPORT=1`, `V1_SKIP_GDUNIT=1`, `V1_GDUNIT_TARGET` (one test file or dir), `V1_GDUNIT_TIMEOUT`,
`V1_BOT_TIMEOUT`, `V1_HOOKS_STRICT=1`, `PLAYTEST_ARGS`.

## Exit codes
`0` green, `1` gdUnit failed, `2` bot failed, `3` setup problem (no Godot binary).

The bot fails the run on: any failed CHECK, any `SCRIPT ERROR` / `ERROR` / `SHADER ERROR` / parse error, a stage that
hit its deadline or logged "no progress" (stuck), a requested stage that never ran, or no `summary.json`.
Warnings are printed, not failing.

## Headless bot
When `DisplayServer.get_name() == "headless"` the bot skips screenshots (`shot()` only dismisses popups and waits),
fps / draw-call sampling and the "world barely renders" check. CHECKs, engine-error capture and stuck detection are unchanged.
Reports show fps/draws as 0 in headless runs: that is expected.

## Hooks
`[HOOK]` lines are the places the bot cheats. `verdict.py` normalises them (numbers -> `N`) and compares with
`hooks_allowed.txt`. Not enforced by default (the list is empty until the owner approves one); `V1_HOOKS_STRICT=1` enforces it.

## Boot wiring patch
`docs/platform/boot_wiring_wip.patch` is NOT applied on this branch (neither forward nor reverse applies cleanly:
`main.gd`, `quality.gd`, `hud.gd`, `ui_theme.gd`, `virtual_joystick.gd` have drifted). Left alone, per the plan.
