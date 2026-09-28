# Outdoor grounding report (2026-09-28)

Tool: `tools/qa/grounding/grounding_check.gd` (new). It boots the real game, teleports
to 4 outdoor locations (village_plaza, village_edge, forest, camp -- all near
Ashford/the first bandit camp; region sites are excluded, see "What wasn't
scanned" below), builds everything in range, and for every placed
MeshInstance3D/MultiMeshInstance3D within 150 m and every player/villager/combatant,
compares its lowest point against `WorldGen.height()` at its footprint corners.
Raw data: `docs/qa/grounding/raw.tsv` (27,457 samples), `good.tsv` (25,562 after
dropping scanner artefacts sitting at exactly world origin).

**Getting a clean run took repeated fixes to the tool itself** (documented in
`grounding_check.gd`'s comments): a `get_root()` name collision with `SceneTree`,
a GDScript type-inference error, then discovering `RegionDressing.build_all_now()`
free/rebuild-cycles sites as focus jumps between far-apart QA waypoints (each
rebuild is slow -- see "What wasn't scanned"), then a batch of
`!is_inside_tree()` errors from scanning nodes mid-deletion. All fixed; the
scanner now also writes its report incrementally after every location so a
killed run still leaves usable data.

## Characters: no grounding issue

Player, villagers and combatants are essentially perfectly grounded -- gaps of a
few millimetres to ~4 cm across all 66 character samples. No fix needed.

## Real finding #1: forest scatter doesn't adapt to slope (FIXED)

`prop`/`instance:Chunk_*` entries (trees, rocks, undergrowth placed by
`TerrainStreamer._plan_forest`) are the largest and most consistent source of
both floating and buried results -- up to +5.6 m floating and -2.4 m buried at
the extremes, with dozens in the tens-of-cm range. Cause: `_plan_forest` sank
every instance by a flat `-0.15 m` from a single height sample at its own x/z,
with no regard for the slope under its footprint -- fine on flat ground, visibly
wrong on the steeper forest terrain (a wide tree canopy/root spread or a scaled
rock ends up floating on its uphill edge or buried on its downhill edge).

**Fixed** in `kingdom/scripts/world/terrain_streamer.gd` (`_plan_forest`):
the sink now scales with local slope (two extra `WorldGen.height()` samples per
instance, still on the worker thread `_plan_forest` already runs on -- no
per-frame or main-thread cost):

    var slope := absf(WorldGen.height(x + 0.6, z) - h) + absf(WorldGen.height(x, z + 0.6) - h)
    var sink := 0.15 + minf(slope * 0.7, 0.55)

**Not re-verified with a fresh numeric scan** -- see "Run budget" below. Verify
visually: `docs/qa/perf_visual/high_village_forest/` (forest-route frames
taken after this fix) vs. the earlier real-input capture from before it.

## Real finding #2: village props/buildings float more than expected (not fixed this pass)

`instance:Ashford` (every MultiMesh batch parented directly under the settlement
root -- buildings, market stalls, street clutter, lamp posts, homestead clutter,
front-garden bits all share this one parent name) has 1,084 floating samples
> 10 cm, **median 29 cm, max 1.9 m**. That's large enough to see in normal play,
not just at the threshold.

**Not fixed or broken down by asset type in this pass** -- `_owner_name()` in the
scanner labels every settlement batch by its shared parent, so I can't tell from
this data alone whether it's buildings, stalls, or street clutter driving the
median. Likely candidate from reading `settlement_builder.gd`: `_multimesh_cells()`
batches (homesteads, walls) use one MultiMesh per 40-150 m cell with a single
`visibility_range`, not per-instance ground snapping like
`RegionDressing._footprint_ground()` does for region-site buildings -- so a
building batch spanning uneven ground would show exactly this pattern.
**Follow-up:** give `settlement_builder.gd`'s building/stall placement the same
per-footprint-corner snap `region_dressing.gd` already has (`_footprint_ground()`),
and re-run this scanner with per-kind labels (tag the owner as `asset:kind`
instead of parent name) to confirm which batch is responsible before changing
placement code further.

## Scanner false positives (tool limitation, not a game bug)

The scanner recurses into every child of every built node, so it also "checks"
named sub-meshes of a single composite model as if each were independently
placed -- these are not real grounding bugs:
- `mesh:Roof`, `mesh:Roof_001`, `mesh:Ridge`, `mesh:FrameTop` (+1.9 to +2.7 m
  "floating"): these are roof/frame sub-meshes of one Blender house near the
  player's home, correctly sitting high up on the building. The scanner checked
  them against the ground directly below instead of only the building's base.
- `mesh:sword_1handed` (+2.6 to +3.0 m "floating"): an NPC's held weapon,
  attached to a hand bone -- correctly up in the air, not placed on the ground.
- `mesh:windmill_sails`/`windmill_sails_lod1` (+3.2 m "floating"): correctly
  mounted ~10 m up the windmill tower.

If this tool is re-run, it should only check a placed object's root node
(one check per building/prop instance) rather than recursing into every named
sub-mesh, and skip anything under a bone attachment.

## What wasn't scanned: region sites (farms, mines, bandit camp, bridges, wayshrines)

`RegionDressing.build_all_now()` (needed to build every farm/mine/camp/bridge for
the scan) reliably ran past a 240 s budget. Cause, found while debugging: every
GLB in `kingdom/assets/generated/region/**` has an invalid embedded resource UID
(`WARNING: ... invalid UID: 'uid://...' - using text path instead`, one warning
per external resource per load), so every single load falls back to slow
text-path re-resolution instead of the fast UID cache. Building every region site
in the world serially like this is measurably slow -- worth a real fix
(`godot --editor --headless --reimport` once, or regenerating the `.import`
files, should bake valid UIDs), but it's a separate asset-pipeline bug from
grounding and out of scope for this pass.

Region-site grounding was instead checked by code review:
`RegionDressing._build_part()` already calls `_footprint_ground()`, which snaps
every part to the lowest of its footprint's 4 corners (not just its centre),
exactly the fix building placement needs (see finding #2) -- so region-site
buildings should already be well-grounded; this wasn't empirically re-confirmed.
Spot-checked by eye in the existing `docs/qa/perf_visual/high_to_capital` and
`high_village_forest` frames (farmstead, windmill, wayshrines visible at a
distance) -- nothing looked obviously wrong.

## Run budget

Per the coordinator's instruction to stop retrying blindly, the scanner tool was
allowed at most 2 more runs after the initial debugging pass; the last clean run
(the numbers in this report) used one of them, and a follow-up bug in my own
last edit (a GDScript type-inference error) burned the final one without
producing data. The `_plan_forest` slope-sink fix above and the
`settlement_builder`/`region_dressing` dirt-ring and base-clutter fixes are
therefore code-reviewed and visually spot-checked, not re-confirmed with a
fresh numeric scan. Re-run `tools/qa/grounding/grounding_check.gd` (now
hardened: incremental report writes, `is_inside_tree()`/`is_queued_for_deletion()`
guards, no region-site build) to get after numbers when convenient.

## Worst 30 floating (from good.tsv; includes the false positives above)

| gap (m) | asset | location | pos |
|---|---|---|---|
| +11.22 | mesh:@MeshInstance3D@1455 | forest | (190.0, 24.2, 120.0) |
| +5.86 | mesh:@MeshInstance3D@1454 | forest | (190.0, 12.7, 120.0) |
| +5.56 | instance:Chunk_-3_0 | village_plaza | (-131.0, 27.2, 27.2) |
| +5.24 | instance:Chunk_-3_0 | village_plaza | (-133.5, 27.1, 26.9) |
| +4.61 | mesh:@MeshInstance3D@1455 | camp | (188.3, 17.4, 120.6) |
| +4.44 | instance:Chunk_-3_0 | village_plaza | (-132.8, 27.0, 14.1) |
| +4.44 | instance:Chunk_-3_0 | village_plaza | (-132.8, 27.0, 14.1) |
| +3.88 | instance:Chunk_-3_0 | village_plaza | (-131.0, 27.2, 27.2) |
| +3.68 | instance:Chunk_-3_0 | village_plaza | (-133.5, 27.1, 26.9) |
| +3.31 | instance:Chunk_-3_0 | village_plaza | (-129.7, 26.9, 3.2) |
| +3.28 | instance:Chunk_-3_0 | village_plaza | (-129.7, 26.9, 3.2) |
| +3.24 | mesh:windmill_sails | village_plaza | (-99.9, 30.7, 66.3) |
| +3.24 | mesh:windmill_sails_lod1 | village_plaza | (-99.9, 30.7, 66.3) |
| +2.96 | mesh:sword_1handed | camp | (165.3, 14.5, 132.8) |
| +2.92 | mesh:sword_1handed | forest | (95.3, 13.4, 64.8) |
| +2.72 | mesh:Roof | forest | (3.6, 21.2, -3.2) |
| +2.72 | mesh:Roof | village_edge | (3.6, 21.2, -3.2) |
| +2.72 | mesh:Roof | village_plaza | (3.6, 21.2, -3.2) |
| +2.72 | mesh:Roof_001 | forest | (3.4, 21.2, -2.8) |
| +2.72 | mesh:Roof_001 | village_edge | (3.4, 21.2, -2.8) |
| +2.72 | mesh:Roof_001 | village_plaza | (3.4, 21.2, -2.8) |
| +2.71 | mesh:Ridge | forest | (3.5, 21.3, -3.0) |
| +2.71 | mesh:Ridge | village_edge | (3.5, 21.3, -3.0) |
| +2.71 | mesh:Ridge | village_plaza | (3.5, 21.3, -3.0) |
| +2.69 | mesh:sword_1handed | village_edge | (60.3, 21.5, 34.9) |
| +2.57 | mesh:sword_1handed | village_plaza | (0.3, 21.2, 6.3) |
| +2.38 | mesh:@MeshInstance3D@1454 | camp | (188.3, 12.7, 120.6) |
| +1.96 | mesh:FrameTop | forest | (3.5, 20.6, -2.9) |
| +1.96 | mesh:FrameTop | village_edge | (3.5, 20.6, -2.9) |
| +1.96 | mesh:FrameTop | village_plaza | (3.5, 20.6, -2.9) |

`@MeshInstance3D@14xx` (unnamed, forest/camp, ~190,~15-24,~120) recurs at large
values and wasn't identified in the time available -- worth a look (grep for an
anonymous `MeshInstance3D.new()` near the first bandit camp; `army/squad.gd` or
`region_sites.gd`'s camp furniture are the likeliest owners).

## Worst 30 buried (all instance:Chunk_* forest scatter -- see finding #1)

| gap (m) | asset | location | pos |
|---|---|---|---|
| -2.37 | instance:Chunk_0_2 | forest | (0.5, 18.3, 169.3) |
| -2.37 | instance:Chunk_1_0 | camp | (87.2, 16.4, 14.6) |
| -2.37 | instance:Chunk_1_0 | forest | (87.2, 16.4, 14.6) |
| -2.37 | instance:Chunk_1_0 | village_edge | (87.2, 16.4, 14.6) |
| -2.37 | instance:Chunk_1_0 | village_plaza | (87.2, 16.4, 14.6) |
| -2.36 | instance:Chunk_3_2 | camp | (239.5, 14.1, 180.9) |
| -2.35 | instance:Chunk_3_2 | camp | (200.1, 13.6, 147.1) |
| -2.35 | instance:Chunk_3_2 | forest | (200.1, 13.6, 147.1) |
| -2.35 | instance:Chunk_0_1 | camp | (50.9, 14.1, 98.9) |
| -2.35 | instance:Chunk_0_1 | forest | (50.9, 14.1, 98.9) |
| -2.35 | instance:Chunk_0_1 | village_edge | (50.9, 14.1, 98.9) |
| -2.35 | instance:Chunk_0_1 | village_plaza | (50.9, 14.1, 98.9) |
| -2.33 | instance:Chunk_-2_-1 | village_plaza | (-124.0, 26.1, -64.0) |
| -2.33 | instance:Chunk_0_1 | camp | (44.1, 17.2, 75.9) |
| -2.33 | instance:Chunk_0_1 | forest | (44.1, 17.2, 75.9) |
| -2.33 | instance:Chunk_0_1 | village_edge | (44.1, 17.2, 75.9) |
| -2.33 | instance:Chunk_0_1 | village_plaza | (44.1, 17.2, 75.9) |
| -2.31 | instance:Chunk_-2_-1 | village_plaza | (-122.6, 23.6, -23.1) |
| -2.31 | instance:Chunk_1_0 | camp | (90.3, 11.1, 59.9) |
| -2.31 | instance:Chunk_1_0 | forest | (90.3, 11.1, 59.9) |
| -2.31 | instance:Chunk_1_0 | village_edge | (90.3, 11.1, 59.9) |
| -2.31 | instance:Chunk_1_0 | village_plaza | (90.3, 11.1, 59.9) |
| -2.30 | instance:Chunk_2_2 | camp | (177.2, 11.7, 149.3) |
| -2.30 | instance:Chunk_2_2 | camp | (185.1, 12.4, 142.4) |
| -2.30 | instance:Chunk_2_2 | forest | (177.2, 11.7, 149.3) |
| -2.30 | instance:Chunk_2_2 | forest | (185.1, 12.4, 142.4) |
| -2.30 | instance:Chunk_4_2 | camp | (300.5, 11.5, 131.8) |
| -2.30 | instance:Chunk_1_-2 | village_edge | (119.4, 11.1, -101.9) |
| -2.28 | instance:Chunk_-1_2 | forest | (-5.9, 18.8, 150.1) |
| -2.28 | instance:Chunk_-1_2 | village_edge | (-5.9, 18.8, 150.1) |

Note: the same physical instance often appears at several locations (it's within
150 m of more than one QA waypoint), so the unique-issue count is smaller than
the raw row count -- e.g. instance:Chunk_1_0 at (87.2, 16.4, 14.6) is 1 real
prop, not 4.

## Counts by asset type (floating + buried, > threshold)

| type | bad count |
|---|---|
| prop (buildings/props/forest scatter, all non-character placed geometry) | 4,791 |
| character (player/villager/combatant) | 0 |

(`kind` in the scanner only distinguishes "prop" vs. character group name; see
finding #2 for why per-building/per-prop-type breakdown needs a scanner
improvement, not just more runs.)
