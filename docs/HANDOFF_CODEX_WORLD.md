# Handoff: Codex (the world)

Written 2026-10-21 by the cloud Claude session. **Codex owns the world: terrain, towns, dressing, environment and the world's VFX.** Animation moved to Antigravity (`docs/HANDOFF_ANTIGRAVITY.md`). Read `docs/PROJECT_BIBLE.md` first for the project map. Paths are relative to the repo root; the Godot project is `kingdom/`.

## Rules

1. **Do not change simulation code** (`kingdom/scripts/realm/*`, `scripts/sim/*`, `autoload/*`, `scripts/population/*` rules, saves). Read simulation state only through the read APIs below. Need a new hook or field? Add a dated line under "Open world requests" at the bottom; the cloud session answers in that line and documents the API.
2. World data must stay **deterministic** (pure functions of the seed, no `randf()`; `WorldGen` is the only height truth) and **saves must not depend on scene nodes** (interactive object state is keyed by stable ids in `scripts/world/world_state.gd`).
3. Every placement change: run the world linter (section 6), keep LOW and ram8 budgets green (section 8), and prove the look with a Style G comparison (skill `ashes-style-g-qa`). The cloud box cannot render reliably; GPU judgement goes through the local PC session.
4. Commit only your own paths; merge before push (skill `ashes-collab`). Shared files get a dated line in `docs/LOCAL_SESSION_HANDOFF.md` first.

## 1. Terrain3D + ProtonScatter backend

Full write-up (what exists, how to look, parameters to tune, known limits, decision) is the first section of `docs/LOCAL_SESSION_HANDOFF.md`. Summary:

- Addons: `kingdom/addons/terrain_3d` (Terrain3D 1.0.2, GDExtension) and `kingdom/addons/proton_scatter` (4.2.0), both MIT, credited in `kingdom/CREDITS.md`.
- **Flag:** `kingdom/scripts/world/terrain_backend.gd` (`TerrainBackend`). Default **`legacy`**. Switch with `-- --terrain_backend=terrain3d`, env `ASHES_TERRAIN_BACKEND=terrain3d`, or `[world] terrain_backend` in `user://settings.cfg` (`TerrainBackend.set_mode`). Missing extension means legacy.
- Files: `scripts/world/terrain3d_bridge.gd` (bakes `WorldGen.height` and `WorldGen.color_at` into 384 m regions, 1.5 m spacing, on `WorkerThreadPool`, one region per frame), `scatter_chunk.gd` (four ProtonScatter nodes per 64 m chunk: trees, undergrowth, meadow plants, rocks), `scatter_world_modifier.gd`, `scatter_exclusion.gd` (nothing grows on roads, streets, settlement discs, clearings, water, build-kit grids, founded settlements). Textures: `assets/terrain3d/ground/` packed by `tools_qa/terrain3d/pack_ground_textures.gd`. Test: `tests/test_terrain3d_bridge.gd`.
- Collision still comes from `TerrainStreamer`'s per-chunk trimesh; Terrain3D collision is disabled. **`WorldGen.height` stays the single truth.**

**Checklist before `terrain3d` can become the default (owner decision, PC-first):**
1. [ ] Compare the capture views e01 to e08 and p01 to p06 (`kingdom/tools_qa/environment/env_views.json`, harness in the LOCAL handoff) on a GPU against `legacy`; judge with `ashes-style-g-qa` against target 03.
2. [ ] Ground detail and tiling at eye level and on the command camera; check `Terrain3DBridge.UV_SCALE`, `SLOT_LOOK`, `GRASS_TINT`; normal direction (the packer inverts green; flip `INVERT_GREEN` if relief looks lit from the wrong side).
3. [ ] Path/cobble edges in Ashford, Kingsreach and village squares (old shader had mud shoulders and gate aprons).
4. [ ] Region seams every 384 m: no hairline cracks or texture pops while running; no hitch when a region is added (`MAX_IN_FLIGHT`).
5. [ ] Trees and rocks stand on the ground; none in streets, roads, plazas, build-kit grids or founded settlements (build and found a few, rebuild).
6. [ ] `GrassField` colour melt against the new ground (it samples the legacy ground material).
7. [ ] Port the legacy shader globals Terrain3D's shader does not read: rain wetness, seasons, snow, scar mask, Region 1 biome patchwork (use `Terrain3DMaterial.shader_override`). Also the `Region1Horizon` ring.
8. [ ] Ground decals (ruts, puddles) still project (`TownDecals.GROUND_LAYER` is in the Terrain3D `render_layers`).
9. [ ] Frame time on HIGH vs legacy (Terrain3D clipmap + MultiMesh trees); ram8 memory with 5 textures at 1024 px (25 MB).
10. [ ] Tree kinds: legacy picks pine by altitude; consider two scatters (lowland, highland).
11. [ ] When the phone build returns: exclude `addons/terrain_3d/*` for Android/iOS/web presets or keep `legacy` there.
12. [ ] Owner agrees; then change `TerrainBackend._resolve()` default.

## 2. Town kit and settlements

- **Layout (data):** `kingdom/scripts/world/city_planner.gd` plans streets, lots, walls, gates, landmarks from the settlement and seed (pure, computed once). `districts.gd` adds six districts (market, craft, poor, admin, inn, military) by weighted Voronoi; `district_at(pos)` is the query. `district_props.gd`, `house_details.gd` dress them.
- **Builder:** `scripts/world/settlement_builder.gd` (buildings and greenery batched per model per LOD cell; Meshy hero buildings swap to light LOD at a distance), then `g_dressing.gd` (Style G ivy, flower boxes, tubs), `town_decals.gd`, `lamp_glow.gd` / `lamp_node.gd` / `torch_props.gd`, `market_goods.gd`, `building_profiles.gd` (front doors, interiors, compound colliders; the single source of "where is this building's door").
- **Town kit (the vertical-slice town):** `scripts/world/town_kit/` (`town_hub.gd`, `town_data.gd`, `town_lots.gd`, `town_ground.gd`, `town_places.gd`, `town_roster.gd`, `town_clues.gd`, `town_livestock.gd`, `town_special.gd`, `town_talk.gd`). Thornfield: `scripts/world/thornfield/` (`hub.gd`, `slice_town.gd`, `sites.gd`, `wilds*.gd`, `outpost.gd`, `rift_*.gd`). Tests: `tests/test_town_kit.gd`, `test_town_kit_scale.gd`.
- **Identity:** `town_identity.gd` (visual profile per settlement: architecture, clothing, industries) and `town_identity_view.gd` (walls, yards, industry props), `village_features.gd` (hamlet signatures), `region1_identity.gd` (trade, landmark, NPC, rumour set for each of the 20 Region 1 settlements, data `kingdom/data/region1/world/settlements.json`).
- **Benchmark street:** `scripts/world/street_benchmark.gd` and `street_routines.gd` (Ashford gate street; "polish one street until finished, then every settlement copies the standard", `docs/art/AAA_PRESENTATION_REVIEW.md`).
- **Interiors and doors:** `kingdom/scripts/interiors/` (`interior_door.gd`), `scripts/world/door_model.gd`, `door_pass.gd`, `locks.gd`, skill `ashes-world-interaction`.

## 3. Region data

- `kingdom/data/region1/` (see its `README.md`): `towns/*.json` (20 settlements), `world/`, `landmarks.json`, `terrain/`, `terrain_stamps.json`, `wardlines.json`, `scar_tide.json`, `ember_legacy.json`, `modules.json`. Plan and look: `docs/regions/REGION_1_PLAN.md`, `WORLD_R1.md`, `LOOK_R1.md`, `CAST_R1.md`.
- `kingdom/data/world/` (`nations.json`, `regions.json`, `first_region.json` with goblin warrens and orc villages, `cultures.json`, `races.json`, `sects.json`).
- Placement code: `scripts/world/region_sites.gd` (plans farmsteads, bridges, waystones, waystation), `region1_world.gd` (packages C1, C2, C10), `region_dressing.gd` (gives planned sites bodies near the player, LOD1 swap), `region1_fill.gd`, `region1_extras.gd`, `region_caves*.gd`, `region_pois.gd` (56 POIs), `hidden_valley.gd` + `vale_look.gd`, `towers/*`, `monster_camps.gd`. Skill `ashes-region-content` is the recipe (RegionSites plan hooks, own RNG streams, Discovery, map icons, budgets).
- Placement-only rule: creature *placement* is `region1_creatures.gd`; behaviour is not yours.

## 4. Districts: the read API (`kingdom/scripts/realm/district_values.gd`)

Hidden per-quarter values the world can *show* (dirty streets, shuttered stalls, patrols). Reach the module with `Life.realm.mod("districts")`. Quarters per settlement kind: village merchant/other; town and frontier_town merchant/other/poor/military; castle adds noble (`QUARTERS_BY_KIND`). Note these are the simulation's five quarters; the six visual districts in `districts.gd` map onto them (market = merchant, craft/inn/admin = other, poor, military; castle noble).

Read calls (all take settlement id `sid` and quarter `q`; day ticks move them, so reading is cheap, do not poll per frame):
- `quarters_of(sid) -> Array`, `has_quarter(sid, q) -> bool`
- `values(sid, q) -> Dictionary` with keys `prosperity, population, unemployment, housing_cost, food_security, safety, corruption, political_support, culture_mix, tension` (each 0..1)
- `mood(sid, q)`, `guard_density(sid, q)`, `etiquette(sid, q)`, `price_mult(sid, q)`, `rent_mult(sid, q)`, `crime_opportunity(sid, q, who := {})`

Rule: crime and wealth come from individual need and `values`, never from the quarter's name; do not hard-code "poor quarter = crime" in dressing. Use `values` to drive *signals* (more litter and broken fences when `prosperity` is low, more guards and banners when `guard_density` is high, closed stalls when `unemployment` or `tension` is high).

## 5. Settlement founding and the build kit

- **Founding** (`scripts/realm/founding.gd`, module `founding`; `civilization.gd`, `camps.gd`, `migration.gd` feed it): `evaluate_site(pos)`, `begin(pos, name, who, founder)`, `occupy(fid)`, `abandon(fid)`, `get_founding(fid)`, `stage_name(fid)`, `land_status_at(pos)`. Stages: scouting, occupation, survival, production, recruitment, infrastructure, government, recognition. Scale classes: camp, hamlet, village, town, city, regional stronghold. Player and NPC founders use the same flow; the player founds at most 3 (`BuildKit.MAX_GRIDS`). A founded settlement registers a 56 m exclusion disc (+24 m for trees) with `ScatterExclusion`.
- **World bodies for it:** `scripts/world/construction_view.gd` (site slab, building revealed from the ground up by progress), `homestead_view.gd`, `scripts/build/*` (build mode), `build_resources.gd` (trees, quarry, clay, reed), `data/build_kit/pieces.json`, assets `assets/incoming/build_kit`. Skill `ashes-build-kit`; art notes `docs/art/build_kit/`.
- **Build kit** (`scripts/realm/build_kit.gd`): 2 m cell / 3 m storey grid, snapping sockets, support rules, tiers and costs, one grid per player settlement. Read-only for you: `catalog()`, `def(kind)`, `kinds_in(cat)`, `mesh_path(kind, lod)`, `level_y(level)`, `grid_at(world)`, `snap_world(...)`. Adding a piece means a mesh plus a `pieces.json` row; the cloud owns the rules.
- `scripts/world/low_budget.gd` and `static_merge.gd` apply to founded/built content too.

## 6. World lint tools

- `kingdom/tools_qa/lint_world/world_lint.gd` finds floating (> 1 m is SEVERE), sunken, clipping, overlapping and road-blocking props, and per-site draw-budget overruns, **without rendering**. Command (headless):
  `godot --headless --path kingdom -s res://tools_qa/lint_world/world_lint.gd -- [--seed=N] [--sites=all|kind,...] [--out=/path/report.json]`
  Exit 1 on any non-allowlisted SEVERE issue. Tunables and allowlist: `lint_config.gd`; logic `lint_core.gd`; kit lint `kit_lint.gd` / `kit_lint_cli.gd`. Test: `tests/test_world_lint.gd`. Skill `ashes-world-lint`; report format in `docs/qa/`.
- Others: `tools/qa/grounding/` (grounding_check, debug_floaters, shots), `kingdom/tools_qa/districts/` (district build profile and shots), `tools/qa/asset_audit.py`, `tools/qa/texture_vram.py`, `kingdom/tools_qa/baked_quality/` (VAO and atlas bakes, skill `ashes-baked-quality`), `tools_qa/lint_world`, `tools_qa/stuck_check`, `tools_qa/collision_preview`.

## 7. Style G skills (the one look)

`ashes-art-style` (index), `ashes-style-g` (master recipe: Environment, sun, fill, shadow tiers, palettes, shaders per material role, camera, composition, density; applied via `kingdom/scripts/style_g.gd` and `resources/style_g`), `ashes-style-g-assets` (proportions, silhouettes, texture rules, tri and texture budgets, LODs, role names, bpy steps), `ashes-style-g-qa` (scorecard and compare tool against target 03), `ashes-environment-look` (ground, grass, paths, rocks, cave rock, fixed capture views), `ashes-baked-quality` (baked AO and painterly light for LOW richness), `ashes-asset-pipeline`, `ashes-open-source-sourcing`, `ashes-visual-qa`, `ashes-region-content`, `ashes-world-lint`. Art references: `docs/art/style_g/`, `docs/art_reference/`.

## 8. Presets: LOW and 8 GB

- Tiers in `kingdom/scripts/core/quality.gd`: phone LOW / MEDIUM / HIGH / ULTRA and PC_LOW / PC_MED / PC_HIGH / PC_ULTRA. Per-group overrides (view, shadows, textures, effects) from the settings screen.
- **ram8** (8 GB RAM PCs): opt-in with `-- --ram8` or `Quality.ram8 = true` before the world builds. Caps: view radius 3, full NPC bodies 10, sprite NPCs 40, scatter share 0.7, shadow distance 90 m; floors: texture bias 1.0, LOD threshold 1.5; SDFGI and SSIL off. Anything you add that scales with view radius or texture size must respect these.
- LOW budgets (draw calls, tris) live in `scripts/world/low_budget.gd` (`low()`, `skip_part`, `skip_extra`, `lod_distance`, `proxy_for`); drawing less on LOW is done with `surface_collapse.gd`, `static_merge.gd`, `character_merge.gd`, `town_atlas.gd`. Rules in skill `ashes-performance`; audits in `docs/qa/PERFORMANCE.md`, `docs/perf/`.
- Terrain3D and ProtonScatter are PC tiers only for now.

## 9. Open world requests (cloud -> Codex, and Codex -> cloud)

Format: `YYYY-MM-DD who: request -> status/answer`.

- 2026-10-21 cloud: **Empty markets and closed shutters for the aura release** (`docs/design/AURA_RELEASE.md`, being written). When a high-aura figure walks a town, or fear/tension rises, stalls empty, shutters close, doors bar, streets thin. Needed: (a) a shutter-closed state for house windows and shopfronts (swap mesh or MultiMesh variant, cheap); (b) a "market emptied" state for stalls (hide goods, awnings stay); (c) a world-side hook that reads `Life.realm.mod("districts").values(sid, q)` (`tension`, `safety`, `prosperity`) or a boolean the cloud will publish, and flips them. Cloud will add a read call such as `fear_state(sid)`; tell us the signature you prefer. -> open.
- 2026-10-21 cloud: **Monster districts.** Monster settlements (goblin warrens, orc villages in `data/world/first_region.json`, `monster_camps.gd`) and future monster civilizations (`MONSTER_NAMING_AND_STATUS.md`) need district-like zoning (den, hall, workshop, food store, trophy ground) with props, plus a clear threshold between wild ground and their territory. The ecology side (`realm/ecology_factions.gd`) will expose clan intent and size; you decide the layout and dressing. -> open.
- 2026-10-21 cloud: **`private_home` door metas.** `scripts/interiors/interior_door.gd` already reports a trespass stimulus when the player enters a door that has meta `private_home` (`has_meta("private_home")`), but **nothing sets that meta yet**. Please set it on the interior doors of residential lots (houses with a resident owner, via `scripts/sim/ownership.gd` `is_private_home(owner, player)` once you have the owner string) and not on shops, inns, temples, guild halls. Keep public buildings meta-free. -> open.
- 2026-10-21 cloud: **Battlefield scene build** from `Armies.battlefield_snapshot(sid, at_hour := -1)` (`scripts/realm/armies.gd`, data only: phase, `t`, lost/engaged/waiting men per side conserved to the resolved result, destroyed defences monotone, reserves by hour; empty Dictionary when no battle; `{"phase": "not_started"}` before it begins). Needed: a scene builder that turns the snapshot into a plausible field (formations, dead, broken gates and walls, siege engines, smoke and fire) when the player arrives mid-battle, with LOW budgets and a cleanup path. Do not simulate the fight in the scene; the snapshot is the truth. -> open.
- 2026-10-21 cloud: Terrain3D checklist (section 1) needs a GPU run by the local PC session and a decision from the owner. -> open.
- 2026-10-21 cloud: **Answer to the empty-markets request: the hook exists.** `Life.realm.mod("aura_fallout").fear_state(sid, subject := "i:player")` returns `{level, shutters, market_empty, curfew, people_out, dread, awe, vendors_refuse}` (level -1 = awe flipped it, people come out; 0 calm; 1 stares; 2 `shutters` true; 3 `market_empty` true; 4 `curfew`). Poll it at most every few seconds per visible town (cheap dictionary); flip shutter variants, stall goods and doors from it, with a roughly 20 s rolling delay per house so it spreads. Also read-only: `price_mult(sid)`, `vendor_refuses(sid, vendor)`, `bill_due(subject, sid)`. Still needed from Codex (AR-13/14): five aura signatures (`warm_gold`, `cold_white`, `dark_swirl`, `red_flicker`, `living_green`; the key is `aura_view.signature` on the player node, `AuraDriver.state_name()` gives the state), reach ring decal (`aura_view.reach_m`, `cone` 60 or 360), candle/lantern gutter at emit >= 0.6, grass ring and wilting at >= 0.7, glass cracks >= 0.85, covered/abandoned stalls, overturned cart, wanted posters at ladder step 5, ward stones (set `AuraState.warded` on sanctified ground). Thresholds: `kingdom/data/aura/aura_curve.json` `effects`. -> open (Codex).
