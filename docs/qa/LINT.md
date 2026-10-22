# GDScript lint report (gdlint, free, no Godot)

Run 2026-09-30 on `origin/claude/focused-curie-m09hbd`: 417 files (`kingdom/scripts` + `kingdom/tests`). Tool: gdtoolkit 4.5.0 (`gdlint`, MIT, PyPI) in a venv at `C:\Users\Jonna\Tools\gdtoolkit`. Nothing in the game code was changed or reformatted.

Run it: `bash tools/qa/lint.sh` (all files, about 2 minutes), `bash tools/qa/lint.sh kingdom/scripts/realm/war.gd` (only those files), `--strict` for the advisory lists. Config: `kingdom/.gdlintrc`. CI: job `lint` in `.github/workflows/tests.yml` (see `ashes-ci`).

## Result: no real bugs found by the error-class rules

With gdlint's default rules the code base gives about 8,600 findings, 98% of them style. The project's own conventions (long one-line dictionary literals, topic-grouped members, 1-4k line realm files, `T` / `S` table shorthands) are deliberate, so the rules are turned off in `.gdlintrc` with the counts recorded in the file:

| Rule | Findings | Why off |
|---|--:|---|
| max-line-length (100) | 7,439 | long literals on purpose |
| class-definitions-order | 757 | grouped by topic |
| max-returns / max-public-methods / max-file-lines | 61 / 60 / 25 | realm modules are big by design |
| function-argument-name, function-variable-name, class-variable-name, loop-variable-name, function-name, constant-name | 92 | `T`, `S`, `L`, `SPEED_T`, `Act` shorthands |
| unused-argument | 91 | signature-compatible callbacks (`ctx`, `day`, `pal`); still listed by `lint.sh --strict` |
| duplicated-load | 26 | repeated preload of one path (self-load for statics, HUD art) is intentional |
| mixed-tabs-and-spaces | 26 | false positive: continuation lines inside a dictionary literal (`tutorial_director.gd` 47-81) |
| no-elif-return, no-else-return | 6 | style |
| expression-not-assigned | 2 | `a.reparent() if x else a.queue_free()` (`discovery_vista.gd:232`, `test_realm_power_paths.gd:108`) is valid GDScript |

What the config keeps on (and stays green, so a new finding means a new problem): trailing whitespace, tab characters, unnecessary `pass`, comparison with itself, enum/signal/class naming, argument count, and gdlint's syntax errors.

gdlint has no duplicate-name or unused-variable check, so `tools/qa/gd_extra_lint.py` adds them on top of gdtoolkit's own parser:
- **duplicate-member** (two funcs, vars, consts or signals of one name in a class): 0 found.
- **duplicate-local** (a local declared twice in one block, which Godot rejects): 0 found.
- **unused-local** (advisory, never fails the run): 21 found, listed below.

## Parse failures: gdtoolkit grammar lag, not game bugs

Two files are valid Godot 4.6 (they run in the gdUnit suite) but the gdtoolkit grammar cannot parse them. They are listed in `SKIP` inside `lint.sh`; drop them when a newer gdtoolkit handles the syntax.
- `scripts/region1/rune_gesture.gd:97` `for s: Array in set:` (a variable named `set`, a soft keyword).
- `scripts/world/village_services.gd:801` a regular `"..."` string literal that spans lines.

## Advisory: unused locals (21)

Most are dead leftovers. A few are worth a human look because the unused value may be a dropped feature:

| Where | Local | Note |
|---|---|---|
| `scripts/realm/followers.gd:610` | `msgs` | `_follower_day()` returns the day's follower messages and the caller throws them away. If those lines (for example "X has left") should reach the player, they never do. |
| `scripts/realm/siege.gd:314` | `mult_eng` | declared `1.0` before the engine loop and never applied: an engine damage multiplier that was planned, or removable. |
| `scripts/realm/campaign.gd:3060` | `a` | `_army_of(u)` result unused in the post-battle loop. |
| `scripts/realm/education.gd:951` | `def` | `_def(inst)` fetched and unused in `_enroll`. |
| `scripts/world/settlement_builder.gd:425` | `tower_mesh` | the wall-tower mesh is loaded but towers are placed by name through `_lod_cells(root, "wall_tower", ...)`; harmless, and it costs one Assets lookup per wall ring. |
| `scripts/world/towers/floor_gen.gd:415, 424` | `info`, `alpha` | an unused info dictionary and a `MeshBuilder` that is created and never filled (no alpha surface gets built). |
| `scripts/interiors/dungeon_gen.gd:692` | `r` | room rect read in `_room_clutter`, unused. |
| `scripts/region1/r1_story_director.gd:703, 755` | `o` | `story.current_objective(id)` called twice per step and ignored. |
| `scripts/sim/monster_ecology.gd:207` | `sp` | species row fetched and unused in the den split. |
| `scripts/ui/war/siege_view.gd:553` | `cpos` | siege position computed, not drawn. |
| `scripts/world/exploration_director.gd:186`, `scripts/world/towers/tower_site.gd:307`, `scripts/cinematic/birth_cutscene.gd:119` | `pond`, `nb`, `bed` | placed or computed and dropped (`nb` is the notice board prop node). |
| tests | `g1`, `cash0`, `ri`, `lost`, `msgs`, `u` | in `test_enterprise.gd` (305, 340, 586), `test_war_influence.gd:525`, `test_realm_household.gd:184`, `test_war_map_data.gd:210`: set up but never asserted on; the test may assert less than it intends. |

## Limits

gdlint checks style and structure, not types: wrong calls, missing members and type mismatches still show up only in the gdUnit run (and in `tests/test_scripts_parse.gd`). Do not run `gdformat` over the tree; it would rewrite the long literals the project keeps on one line.
