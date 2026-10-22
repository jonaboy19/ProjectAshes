---
name: ashes-region-content
description: How to add places to the Rising Ashes world (sites, landmarks, caves, dungeons, POIs, secret places, towers) without breaking ids, tests or the map - RegionSites plan hooks, own RNG streams, Discovery, map icons, dressing and budgets. Use for any new location, dungeon entrance, point of interest or hidden area.
---

# Adding places to the region

- **Planning:** `scripts/world/region_sites.gd` `plan(seed)` builds `WorldGen.sites`. Every package appends in a separate planner file with ONE hook line near the end (`out.append_array(preload(...).sites(seed, out))`). Ids are reassigned by index at the end, so **append after everything**; never insert. Earlier ids must not move.
- **RNG:** each planner uses its own stream (`hash([seed, "caves"])`), so adding one package never reshuffles another.
- **Placement:** pass `out` so you can avoid existing sites, roads and water. Check `WorldGen.is_water`, `forest_density` and `nearest_settlement`. The 128 m spatial index keeps these queries O(1).
- **Tests that bite:** `test_region_sites` (sites are dry and treeless unless tagged, e.g. `region1`), `test_world_8km` and `test_dungeons` (never assert "mine is last"), `test_discovery` (poster names via `Discovery.display_name`). Tag wet or forested sites instead of loosening the whole check.
- **Secret places:** mark them `{"secret": true}` and keep them out of the `places` list until found. Reveal with `Discovery.reveal_site(id)`. Give leads through text: rumours (`village_services._pick_rumour`, villager gossip), NPCs, notes and fragments. No glowing markers; the user wants exploration.
- **Map:** add labels in `discovery.gd` and icons in `scripts/ui/map_icons.gd`. Unmapped kinds fall back to the ruin icon.
- **Visuals:** dress the site from `region_dressing.gd` (built by distance on a timer, in MultiMesh cells). Put Node-heavy views in a separate file added in `RegionDressing._ready`, so `WorldGen.setup` doesn't preload `Life`/`InteriorDoor`.
- **Interiors:** use an `InteriorDoor` subclass and override `_can_enter()` / `_make_interior()` for code-built rooms (see `dungeon_door.gd`).
- **State:** found, looted and killed state goes in the `exploration` realm module, not in nodes.
- **Budgets:** at most 32 draw calls of dressing per site in view, and at most 150 total in view on LOW. Measure with standalone captures.
- **Bosses and danger:** tier comes from distance to Kingsreach (tier 1 = Lv 1-12 up to tier 4 = Lv 40-60). Big creatures are optional and never block progress.
