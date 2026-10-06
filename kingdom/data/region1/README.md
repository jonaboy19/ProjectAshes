# Region 1 data and scaffold (Valencious, the Ashford Vale)

Plan: `docs/regions/REGION_1_PLAN.md`. Hooks for the cloud session: `docs/regions/HOOKS_FOR_CLOUD.md`.

## Layout
| Path | What |
|---|---|
| `scripts/region1/region1_sim.gd` | `Region1Sim`: base class for pure `RefCounted` sims |
| `scripts/region1/region1_state.gd` | `Region1State`: static save registry and live-sim list (hook H2) |
| `scripts/region1/region1_root.gd` | `Region1Root` (`Node3D`): low-frequency ticker and presenter refresh (hook H1) |
| `scripts/region1/demo_sim.gd` | `Region1DemoSim`: reference module. Copy it to start a new one |
| `data/region1/modules.json` | manifest: one row per module the root creates in the game |
| `scripts/region1/wardlines.gd` | `Wardlines` (L7): Elder budgets, routing graph, glyphs, coverage for hook H3. Tuning: `data/region1/wardlines.json` |
| `scripts/region1/rune_gesture.gd` | `RuneGesture` (L8): finger-stroke recognizer for ward / lure / alarm / bless. Shapes: `data/region1/glyphs.json` |
| `data/region1/*.json` | module data (glyphs, mutation tables, stone budgets, ...) |
| `data/region1/progression_spine.json` | **C13**: the end-of-region targets (soul tier 3-4, career rank 4-5, gear tier 2, level 13+, first house <= 25 days, top rank not before day 60) and the Rift gate (`scripts/region1/progression_spine.gd`; story step `a5_rifts_edge` carries it as an `if` condition) |
| `tools_qa/region1/balance_run.tscn` | **L18**: 100 headless game days per archetype through the real systems (`balance_sim.gd`, probes in `balance_probe.gd`), CSV per run; report `docs/regions/BALANCE_R1.md`, test `tests/test_balance_r1.gd` |
| `tools_qa/region1/region1_sandbox.tscn` | headless runner (below) |
| `tools_qa/region1/wardlines_demo.gd` | headless story board: coverage PNGs of cut / carve / decay (`samples/`) |
| `tools_qa/region1/rune_canvas.tscn` | windowed rune canvas: glowing trail, confidence, practice mode, `--demo` scripted strokes |
| `tests/test_region1_*.gd` | gdUnit4 tests |

## Writing a module (packages L7 to L16)
1. `scripts/region1/<name>.gd` with `extends Region1Sim`. In `_init()` set `module_name = &"<name>"` (same as the file name, so the sandbox finds it) and `state_version`.
2. Sim rules: no scene tree or autoloads, no `randf()` (use `rng`), advance in `_step(dt_days)`, report with `emit_event(kind, data)`, keep a tick under 2 ms, allocate nothing big per tick.
3. Persist through `_save_state()` / `_load_state()`. JSON-safe only: no `Vector2`/`Color`, no int dictionary keys, no 64-bit ints (store them as `String`). When the saved shape changes, bump `state_version` and add the `from_version -> +1` step in `migrate()`. `Region1State` calls `migrate()` step by step.
4. Draw a debug picture in `debug_image()` if you can: the sandbox saves it as PNG.
5. Go live: add a row to `modules.json`: `{"name": "<name>", "script": "res://scripts/region1/<name>.gd", "enabled": true}`. The root creates it (seeded with `WorldSim.SEED`), registers it and ticks it. A missing script is skipped silently.
6. Presenters (small `Node3D`s that show a sim): add the node to group `region1_presenter` and implement `region1_present(root: Region1Root)`. It is called after each batch of ticks, not per frame. Read sims with `Region1State.sim(&"<name>")`.
7. Modules that are not `Region1Sim` (like a gesture recognizer with no time axis) can still save: `Region1State.register(&"name", snapshot_cb, restore_cb, version, migrate_cb)`.
8. Tests: `tests/test_region1_<name>.gd`. Always cover determinism by seed, and a save/restore round trip through `JSON.stringify`/`parse_string`.

## Save shape (under `region1` in Life's snapshot)
```
{"version": 1, "modules": {"<name>": {"v": <state_version>, "data": <Region1Sim.serialize()>}}}
```
Unknown modules' data is kept and written back. A module missing from a save gets `restore({})`.

## Time
The root reads the fractional game day (`WorldSim.day + time_of_day / 24`) once per second (a `Timer`, no per-frame work), slices it into chunks of at most 1 day and runs at most 4 chunks per timer tick, so a long sleep catches up over a few seconds without a hitch. Loading a save re-anchors the clock (sims keep their own `day_f`).

## Sandbox
```
Godot --headless --path kingdom res://tools_qa/region1/region1_sandbox.tscn -- ^
    --module=demo_sim --days=60 --seed=1 --step=0.5 --png-every=20 --log-every=10 --out=<dir>
```
Writes `<module>.log`, `<module>_dayNNN.png` (from `debug_image()`), `summary.json`. Runs a determinism check (same seed and steps, same digest) and a save/JSON/restore round trip that must continue identically; exit code 0 means OK. Default `--out` is `user://region1_sandbox/<module>`. Renders needing a GPU (frame sheets of ghosts, glyph canvas) belong in a windowed sandbox variant; do not use `--headless` for those.

## Tests
```
Godot --headless --path kingdom -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/test_region1_scaffold.gd -c --ignoreHeadlessMode
```

## Wardlines and rune canvas (L7, L8)
```
Godot --headless --path kingdom res://tools_qa/region1/region1_sandbox.tscn -- --module=wardlines --days=150 --png-every=50
Godot --headless --path kingdom -s res://tools_qa/region1/wardlines_demo.gd -- --out=<dir>
Godot --path kingdom --write-movie <dir>/frame.png --fixed-fps 30 --quit-after 1400 --resolution 1280x720 res://tools_qa/region1/rune_canvas.tscn -- --demo   # windowed, never --headless
```
Wardlines is not in `modules.json` yet: it goes live with C3 (see hook H3 in `docs/regions/HOOKS_FOR_CLOUD.md`). Test classes by `preload` if the editor class cache is stale.
