# F12: object pooling and the cell streaming manager

Foundation plan item F12 (docs/design/FOUNDATION_PLAN.md). Code: `scripts/core/node_pool.gd`, `scripts/core/creature_pool.gd`,
`scripts/core/cell_streamer.gd`, `scripts/vfx/pooled_emitter.gd`. Tests: `tests/test_pooling_streaming.gd`.
Harness: `kingdom/tools_qa/pooling/walk_harness.tscn`.

## What is pooled

| Thing | Where | Notes |
|---|---|---|
| Wolves, boars, bears, rats, brutes | `wolf.gd` `reset()` / `on_release()`, spawners: ambient life, frontier packs, realm encounters, Thornfield wolf threat | one pool per (spawner, species/variant), cap 24, never steals a live body (over the cap it is a plain new/queue_free) |
| Camp monsters | `monster.gd` `reset()` / `recycle()`, `monster_camps.gd` | named (evolved) monsters are never pooled |
| Ambient critters | `critter.gd` `reset()`, `ambient_life.gd` | cap 96 per kind; rider-owned horses stay plain |
| VFX particle emitters | `vfx_kit.gd` `emit()` + `free_after()` via `pooled_emitter.gd` | cap 96, a generation counter makes a stale free timer harmless |
| Impact, ElementFX, telegraph rings, ragdoll slots, arrows, caster orbs | already pooled before F12 | unchanged |

A released body resets: health and max health (level re-rolled for monsters), state, den and home, AI timers, attack
tokens and telegraph, knockback, wind-up, `died` connections, extra groups and meta (`prey`, `thornfield_wolf`), scale (apex
and corrupted beasts are enlarged), death-squash tween, collision shape, the ragdoll (`revive()` plus `reset_bone_poses()`)
and the idle clip. Idle bodies live outside the tree, so they cost nothing per frame.

Not pooled, and why:
- Loot drops: there are no loot nodes. Monster, wolf and critter kills hand drops straight to the inventory
  (`Life.on_*_killed`, `Gathering.give_drops`). Corpse looting is an interaction kind, not a spawned drop.
- Technique projectile visuals from the VFX library (`_vfx(..., true)`): `Spells.missile` / `arm` bind the node's whole
  lifetime to `tree_exiting`, a self-flying tween and trail emitters parented elsewhere, so reusing the root would replay
  none of that. The caster's fallback orb is pooled already (`projectile_pool.gd`). Their trail emitters now come from the
  emitter pool. A proper missile pool needs the library's missiles rewritten (follow-up).
- Other `queue_free` VFX: impact, flipbook, toon and ground-decal helpers already return to their own pools. The remaining
  offenders were `K.free_after` (33 call sites, mostly particle emitters, now pooled), `vfx_spells`/`vfx_martial` one-off
  roots and lights (one-shot, unpooled).
- Apex bear (`frontier_presence`), story-director wolves and road-traffic riders keep `queue_free`.

## Cell streaming

`CellStreamer.shared()` (64 m cells, tiers UNLOADED / LOW / FULL, hysteresis). `main.gd` feeds it the focus each frame.
One table (`PROFILES`) holds full / load / hyst metres per profile; the terrain ring is Quality's `view_radius` (so the
settings screen's View Distance still works).

| Profile | full | load | free (load + hyst) | Read by |
|---|---|---|---|---|
| terrain | 64 (collision, grass) | view_radius x 64 (LOW 128, MED 192, HIGH 256, ULTRA 320) | + 64 | `main.gd` sets `terrain.view_radius`, `collision_radius`, `grass_radius`, `water.view_radius` |
| settlement | 70 (hero LOD) | 650 | 850 | `settlement_builder.gd` |
| dressing | 55 | 240 | 330 | `region_dressing.gd` |
| population | 45 | 220 | 230 | `population_lod.gd` |
| gather | 24 | 55 | 80 | `forage_nodes.gd` |
| ambient | 40 | 110 | 170 | `ambient_life.gd` groups are spawner sites |
| camps | 100 | 260 | 420 | `monster_camps.gd` camps are spawner sites |

Defaults equal the old hard-coded numbers, so behaviour is unchanged; `TerrainStreamer.new().view_radius` is still 4
(test_world_12km). Listeners: `watch(profile, cb)` for cell grids, `add_site(profile, id, pos, cb)` /
`spawner_tier()` for single positions. A spawner site sleeps (bodies handed back to their pool) when its tier is
UNLOADED. If the manager has not been fed the spawner's own focus (a standalone test, a cutscene camera), the spawner
falls back to its old distance check with the same numbers. Only the sites in the window around the focus plus the awake
ones are evaluated per update (the first version looked at all 830 ambient sites and cost 3 s over the walk).

## Measurement

`godot --headless --fixed-fps 20 res://tools_qa/pooling/walk_harness.tscn -- --quality=high --pool=on|off --cells=on|off`
A player walks 2005 m from Thornfield along the most forested heading (6.5 m/s, 308 s) with the real AmbientLife,
MonsterCamps and FrontierPresence spawners, one kill every 12 s and two VFX bursts every 2 s. "Before" is
`--pool=off --cells=off` (plain new/queue_free, old distance checks), "after" is `--pool=on --cells=on`. Runs are not
bit-identical (kills and wolf timing vary), so the table shows three before runs and two after runs.

| Metric | Before | After |
|---|---|---|
| Bodies and emitters allocated, whole walk | 660, 663, 670 | 220, 221 |
| Allocated after the first 20 s (steady state) | 471, 474, 481 | 52, 53 |
| Peak allocations in one second, whole walk | 166 | 166 (the town's first fill, a load-time cost) |
| Peak allocations in one second after 20 s | 16 | 6 |
| Peak nodes in the tree | 1289 | 1289 |
| Average nodes in the tree | 573 to 578 | 571 to 572 |
| Node count at the end | about 1090 to 1140 | about 1090 to 1140 |
| Creature pools (after) | none | 29 pools, 221 created, 655 acquires, 562 releases, 428 reuses, 0 steals, about 130 idle, about 90 live |
| Emitter pool (after) | 306 emitters created | 2 created, 306 acquires, 306 releases, 304 reuses |
| Cell manager (after) | n/a | 617 recomputes, 215 tier notifications, 830 ambient + 12 camp sites |
| Harness wall time (6200 frames) | 15.1 to 18.0 s | 16.3 to 16.7 s |

Reading it: allocation churn drops by two thirds overall and by 89 percent once the town is filled, and the VFX emitter
allocation goes from one per effect to two for the whole walk. Node count in the tree does not move (the spawners
already despawned at distance); the gain is allocation and GC pressure, not resident nodes. The first-second spike
(166) is the first fill of the town's critters, which pooling cannot remove without prewarming at load
(`NodePool.prewarm`, not wired yet).

## Notes
- `test_thornfield` exits 101 (27 orphan nodes, no failures): `clear_ambush()` now hands wolves back to the pool and gdUnit
  counts idle pooled bodies as orphans. Run `NodePool.clear_all()` in a test's `after_test` to free them.
- Idle pooled nodes are freed at tree exit (`NodePool` hooks `root.tree_exiting`).
- The harness's stand-in player is a bare `Node3D`, so wolf attack code logs one `bool()` script error that is the same
  with pooling off (it needs the real Player's properties).

## Teleport memory

Playtest: a run grew to about 12 GB and teleport streaming "never freed caches". Harness:
`godot --headless --fixed-fps 20 res://tools_qa/pooling/teleport_harness.tscn -- [--points=5] [--cycles=N] [--only=terrain|settlements|region|camps|ambient|population] [--pingpong] [--out=file.json]`.
It runs the real TerrainStreamer, WaterStreamer, SettlementBuilder, RegionDressing, MonsterCamps and AmbientLife on a focus that jumps
across the five towns farthest from each other (Ashford, then (-5006, 5360), (-3365, -3405), (3014, -3610), (616, 4546)) and back to
Ashford, settles about 90 frames after each jump, and prints `Performance` OBJECT_COUNT / NODE / RESOURCE / ORPHAN, MEMORY_STATIC,
process RSS, the static caches, the idle pooled bodies and each streamer's live count. Headless uses the dummy renderer, so
`RENDER_TEXTURE_MEM_USED`, `RENDER_BUFFER_MEM_USED` and `RENDER_VIDEO_MEM_USED` read 0 there; the GPU side was not measurable and
the 12 GB itself was not reproduced (the main scene alone is about 11 GB in xvfb on software Vulkan, so a few hundred MB of growth
is a small part of that, but it is the part that scales with how far the player has been).

**Where it grew** (bisected with `--only=` and `--pingpong`, two points visited six times each):
- Terrain: chunk nodes, plans and collision are freed (81 chunks and 0 pending plans at every point); no growth.
- Settlement builder: towns are freed beyond 850 m; ping-pong between two towns is flat after the first rebuild. It keeps shared
  caches (`TownIdentity` colour-variant meshes, `Assets` building meshes) that grow only with the number of distinct towns seen.
- Region dressing: `_bake_cache` (the merged ArrayMesh of every site that was ever built, "so a rebuilt site costs no merge") was
  never released. It is the one cache that grew without bound and held mesh buffers (and their GPU copies) for sites 5 km behind.
- Pooled creatures: `NodePool` keeps idle bodies forever (up to the pool cap, 24 to 96 per species and spawner), outside the tree. After
  a teleport the pools of the place you left kept their high-water mark: 455 idle bodies (the "orphans" column) with their skeletons,
  meshes and animation libraries.
- Population: sprite atlas and `_sprite_cache` are bounded (the cache clears at 4000); flat.

**Fix, on the cell streamer tiers:**
- `CellStreamer.update()` detects a jump of more than `TELEPORT_JUMP` (400 m in one update; a horse moves well under 1 m per frame),
  counts it (`teleports`), emits `teleported(from, to)` and calls `NodePool.trim_all(IDLE_KEEP_AFTER_TELEPORT = 4)`.
- `NodePool.trim_idle(keep)` / `trim_all(keep)` free the oldest idle bodies down to `keep` per pool; live bodies are never touched.
- `RegionDressing.trim_bake_cache()` (run from its 0.75 s loop) drops the cached merged meshes of freed sites once they are more than
  `BAKE_KEEP_FACTOR` (2) x the "dressing" free distance (330 m, so 660 m) from the focus. Walking back and forth across a site's edge
  still never re-merges; a standing site always keeps its entry.
- `CellStreamer.beyond(profile, pos, factor)` is the helper for "out of range for good".

**Before / after** (same five far points, MEMORY_STATIC in MB; before = the code without the three changes above):

| Point | Objects before / after | Nodes | Resources | Orphans before / after | MEMORY_STATIC MB before / after | Bake cache entries before / after |
|---|---|---|---|---|---|---|
| boot | 6797 / 6797 | 421 / 421 | 2328 / 2328 | 0 / 0 | 442.8 / 442.8 | 0 / 0 |
| 1 Ashford (0,0) | 24920 / 24918 | 8996 / 8995 | 4289 / 4289 | 0 / 0 | 1100.9 / 1101.0 | 2 / 2 |
| 2 (-5006,5360) | 18534 / 18519 | 4733 / 4733 | 4440 / 4440 | 14 / 14 | 1112.2 / 1108.8 | 3 / 1 |
| 3 (-3365,-3405) | 18151 / 18130 | 4225 / 4226 | 4443 / 4443 | 252 / 252 | 1120.5 / 1115.0 | 5 / 2 |
| 4 (3014,-3610) | 17766 / 17649 | 3616 / 3616 | 4492 / 4492 | 448 / 378 | 1152.4 / 1143.0 | 6 / 1 |
| 5 (616,4546) | 18890 / 18621 | 4099 / 4099 | 4527 / 4527 | 476 / 280 | 1195.9 / 1183.8 | 9 / 3 |
| 6 back to Ashford | 26473 / 26344 | 9015 / 9015 | 4527 / 4527 | 455 / 385 | 1239.5 / 1227.4 | 9 / 2 |

(OBJECT_COUNT includes every Node, Resource and RefCounted; the RENDER_* monitors are 0 headless.) The drop is smaller than the
12 GB report suggests: the bake cache and idle pools were real, unbounded and are now bounded (bake cache 9 -> 2 entries, idle
bodies at most 4 per pool right after a jump), but most of the remaining growth is shared first-visit caches (the mesh and prop caches
in `Assets`, `TownIdentity`'s colour variants) that are bounded by the number of distinct models and towns.

**It does not keep growing.** Three laps over three far points (`--points=3 --cycles=3`): Ashford at lap 1 / 2 / 3 =
1101.0 / 1159.8 / 1160.5 MB MEMORY_STATIC, process RSS 1222 / 1442 / 1443 MB; the other two points are flat to within 1 MB from lap 2
on. The lap 1 -> 2 step is the one-off cache fill of the towns and props visited; after it a teleport costs nothing that stays.

Tests: `tests/test_pooling_streaming.gd` (`test_trim_idle_*`, `test_a_teleport_trims_every_pools_idle_bodies`,
`test_the_dressing_bake_cache_lets_far_sites_go`).
