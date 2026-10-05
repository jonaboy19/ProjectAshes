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
