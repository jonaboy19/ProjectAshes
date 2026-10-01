---
name: ashes-world-lint
description: Headless visual-bug detector for the Rising Ashes world - finds floating, sunken, clipping, overlapping and road-blocking props and per-site draw-budget overruns without rendering or screenshots (no OOM). Use after changing any world placement code (region_dressing, settlement_builder, region1_look, vale_look, hidden_valley, region_caves_view, towers, site plans), before asking for a screenshot review, or when a prop looks like it floats or clips.
---

# ashes-world-lint

Builds every site's dressing exactly like the game does (RegionDressing, Region1Look landmarks, Hidden Vale ValeLook, caves, dungeon tower spire + camp, all 30 settlements through SettlementBuilder) under the dummy renderer, then checks every placed mesh and every MultiMesh instance against `WorldGen`. About 50 s for the whole world, about 1 GB RAM, no GPU, no xvfb.

## Run it
From `kingdom/` (Godot is `/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64`):

```
G=/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64
$G --headless --path . -s res://tools_qa/lint_world/world_lint.gd -- [--seed=1066] [--sites=all|kind,...] [--out=/tmp/x/report.json] > /tmp/x/lint.log 2>&1
```
- Always redirect to a file and run it with a timeout. A `-s` script that fails to compile leaves Godot idling forever.
- `--sites`: `all`, or site kinds (`farm, waystation, waystone, bandit_camp, watchfort, fort, bridge, hidden_vale, tower_ruin, mine ...`; `WorldGen.sites[*].kind`) and pseudo groups `settlement` (or one town name, lower case), `r1look` (Region1Look landmarks + cliff rocks), `vale` (ValeLook + cliff boulders), `caves`, `tower`.
- `--seed`: default 1066 (the game seed). Hand-placed Region 1 landmarks keep their coordinates across seeds, so use other seeds only for procedural sites (farms, roadside, mines, settlements).
- Output: JSON at `--out` (default `user://world_lint_report.json`), readable summary next to it as `.txt`, also printed. **Exit code 1 if any non-allowlisted SEVERE issue.** (A compile or engine crash also gives a non-zero code: read the log.)
- Regression test: `tests/test_world_lint.gd` (28 s): `timeout 900 $G --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add res://tests/test_world_lint.gd --ignoreHeadlessMode`.

## Read the report
The text summary has: totals; a per site-kind table (severe / major / minor, groups over the draw budget); the top 15 issues; the worst draw-budget sites; then each site with its issues. The JSON has `issues` (sorted worst first), `allowlisted`, `groups` (props, draws, budget, builder file) and `by_kind`.

Each issue: `type`, `severity`, `site` / `site_id` / `site_kind`, `path` (node path; MultiMesh instances are `...#index`), `builder` (the file:function that placed it), `asset` (part asset key when known), `what` (node/mesh names and mesh size), `pos` [x, y(base), z], `metric` and a `detail` sentence with the numbers.

| type | meaning | severe when |
|---|---|---|
| float | base above the LOWEST ground sample under the footprint (centre + corners at 80 %); the game snaps to the lowest corner, so a bigger gap = wrong snap. Stacked props (roof on tower, prop on plinth) and things on water are exempt. Boulders are judged by ~200 mesh vertices against the rendered terrain triangles (nothing touching = hovering) | gap > 1 m (foliage never above minor) |
| sunken / buried | > 40 % of the height under the ground at the centre (rocks 65 %); buried = top below ground | never (major for buried/very deep) |
| water | standing in `WorldGen.is_water` outside wet sites | never (major when solid and deep) |
| overlap | two large props (buildings, walls, stalls, tents, carts, volume >= 30 m3) share > 25 % of the smaller volume, oriented footprints | both are buildings |
| road | solid prop within the road half-width (`WorldGen.road_info`) | centre inside the road and the prop >= 1.5 m |
| draws | distinct mesh+material surfaces drawn near (LOD0) per site vs budget 32 (settlement 500) | never (minor) |

Only the first ~12 issues per site are printed in the text; the JSON has all of them. Units are the direct children of a site root (all near-LOD meshes merged) or single MultiMesh instances; far LODs (`visibility_range_begin > 0`) are skipped.

## Fix a finding
1. Open the `builder` file:function and find how the prop is snapped. The usual bug is `WorldGen.height(x, z)` at the centre for something wider than ~2 m: use the corner snap (`SettlementBuilder._ground_snap`, `RegionDressing._footprint_ground`, `Region1Look._footprint_ground`).
2. Re-run with `--sites=<that kind>`; the issue must be gone. Keep fixes minimal.
3. If it is a layout problem (planner overlaps, fields on cliffs, stall rings), do not hack it: allowlist with a TODO (below) and log it.

## Allowlist rules (`tools_qa/lint_world/lint_config.gd`)
- `ALLOW` entries: `{"type": "float|sunken|buried|water|overlap|road|draws|*", "site": site kind / group id / name / "*", "match": substring (case-insensitive) of "node path | asset | builder | mesh names", "reason": "...", "todo": true}`. Overlaps match against both props. Matched issues move to `allowlisted` in the report and never fail the exit code or the test.
- Every entry needs a reason. Use `todo: true` (and a `# TODO(owner-file)` comment) for real bugs left for later; leave `todo` off only for intentional designs.
- Prefer tag lists over single allowlist entries for designed things: `FLOAT_OK` (banners, hanging lanterns, sails), `WET_OK`, `WET_SITE_KINDS`, `ROAD_OK`, `ROAD_SITE_KINDS`, `BURIED_OK` / `SINK_OK`, `OVERLAP_SKIP`, `OVERLAP_PAIR_OK` (wall+gate, stall+cart...), `KIT_PARENT_TOKENS` (designed kits). They match lower-case substrings of the asset/node/mesh names.
- Never allowlist to silence a fixable one-line snap bug. Thresholds (0.25 m float tolerance, 1 m severe, 25 % overlap, 40 % sink) are constants at the top of the same file.
- A new builder that batches with `MultiMesh.set_instance_transform` must be added to `PATCH_SCRIPTS`, otherwise its props are invisible to the linter (the dummy renderer forgets instance transforms; `mm_shim.gd` records them). The report's `untracked_multimeshes` lists any that slipped through and should stay empty.

## Gotchas
- `-s` scripts compile before autoloads exist: never name autoload-dependent classes in `world_lint.gd`; the core is loaded at runtime (`lint_core.gd`).
- The linter rewrites builder sources in memory and restores them at the end (`restore()`); a test that calls it must call `restore()` in `after()`.
- Other seeds change terrain under fixed-coordinate landmarks; a severe on seed != 1066 in `r1look` is not a game bug.
- Headless numbers say where something is wrong, not how it looks: for a final look ask the local PC session for a render (`ashes-handoff`).
