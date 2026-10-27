# Real-world terrain (W6, owner decision 2026-10-26)

Mock-up: `C:\Users\Jonna\Documents\PA_plans\terrain_candidates\mockup_biomes.png` (re-render: `py -E -B kingdom/tools/world/real_layout.py`).

## Choice and why
- **Base: English Lake District**, Ashford = Lorton Vale between Loweswater and Crummock Water (54.5773 N, 3.3407 W).
- **Mirrored north-south**: game north (-z) = real south. The Scafell / Wasdale / Great Gable massif (the highest ground in England) becomes the snowy game north
  (Northern Ridge, Ironmarch, outer Frostcrown Holds); game south = the Derwent / Cockermouth lowland and Solway plain (Harrowgate steppe, Solkar Marches).
- **x1.3 horizontal compression** (1 game m = 1.3 real m) so the coast (Whitehaven-Workington = Tideclad Sea, ports Saltwick/Blackwater), the lake valleys
  (Ennerdale, Loweswater, Crummock, Buttermere, Bassenthwaite) and the fells fit in 32 km; it also steepens slopes (fantasy drama).
- **Vertical**: x1.15 overall, plus a northern Highland-style uplift (relief up to x1.6 and +40 m toward the north edge). Range -40..1252 m.
- **Valencious** = 16 x 16 km box x [-12000, 4000], z [-7000, 9000] (metres from Ashford): coast in the SW, Heartvale lake valley, fells and Ennerdale-type lake in the north.
  Outside is region-locked: Frostcrown Holds (N, snow realm), Aurelis marches (E, forest/fell), Solkar Marches (S, steppe), Tideclad Sea (W).

## Data (kingdom/data/world/real/)
| file | what |
|---|---|
| height_16.png | 4097^2 16-bit, 8 m/px, corner registration x = -16384 + 8 i, h = -40 + v/65535*1540 (same filter-0 layout WorldMacro decodes) |
| water.png | 1024^2, 32 m/px: 0 land 1 sea 2 lake 3 river (priority-flood + D8, catchment > 4 km2); rivers carved 1.5-3 m into height_16 |
| biome_ids.png | 1024^2 WorldMacro biome ids (sub-regions warped, terrain rules, farmland round towns, snow by altitude + latitude, outer realm biomes) |
| anchors.json | hand-picked old->new anchors per sub-region, box, kinds (castle on river plain, port by sea, keep on ridge) |
| layout.json | all 343 places of valencious_places.json, old -> new x/z (ids unchanged; roads keep ids/topology); 24 outer-ring places land outside the box |
| meta.json | source, projection, lakes (19), stats |
8 m/px justification: the source is ~11 m/px (30 m true SRTM detail); 4097^2 uint16 = 34 MB RAM (same as the current macro), sub-30 m detail stays procedural in
WorldGen (`_detail` noise) and the Terrain3D bake keeps its 1.5 m vertex spacing per streamed region, so a 16 GB laptop is unaffected.

## Tools
`real_terrain_fetch.py` (download, cached) -> `gen_real_world.py` (~6 min; reprojection, sea, lakes, uplift, detail, rivers) -> `real_layout.py` (~1 min; re-anchoring, biomes, mock-up).

## Engine integration (W6.2, flag `--world_macro=real`, env ASHES_WORLD_MACRO=real, settings [world] macro=real)
| piece | where |
|---|---|
| macro data, 8 m / +-16384 m | `WorldMacro` REAL mode (`is_real()`; `wants()` is true for both macro modes) |
| re-anchoring | `RealWorld` (scripts/world/real_world.gd): `remap(old)` = exact table hit by old position, else thin-plate warp; `place(id)`; `box()`; `in_realm()` |
| settlements / sites / clearings / hidden vale / city plans | `WorldGen._relocate_real` after planning (ids, names, road topology unchanged), then the usual macro re-base |
| lore, discovery, quest anchors, camps, ecology, creature dens | positions read from JSON go through `RealWorld.remap` (world_lore, discovery, region1_places, region1_creatures, ecology_factions, WorldGen camps) |
| water | `WorldGen.water_level_at` -> real lakes + sea (`lake_ids.png`); rivers = traced D8 courses fed to `_add_river` (widths 4-22 m by catchment); WaterStreamer draws them as before; Emberglass Mere = lake nearest Ashford |
| stamps (Rift trench, Scar craters, Hollin cliffs, mines, Wyrm's Ribs) and trails | valencious deltas translated to the remapped centre (`Region1Terrain.setup`) |
| biomes | `biome_ids.png` + `biome_soft_{a,b}.png` (32 km); scar boost sites remapped |
| Terrain3D | 512 px x 1.5 m = 768 m regions (32 x 32 locations cover +-12.3 km = the box); LOW / iGPU preset: 256 px x 3 m (same 768 m, 1/4 cost); ring radius 1 (2.3 km); horizon mesh 160 m grid over all 32 km |
| snow | `Terrain3DBridge.snow_line(z)`: 620 m in the south, 440 m at the north border, 200 m at the far north edge |
| region lock | `region_lock.gd`: warden posts (pole, red bar, lantern) every 400 m on the border; crossing turns the player back with a warden line; `--unlock_outer` / [world] unlock_outer |
| fantasy set pieces | `real_landmarks.gd`: Wyrm's Ribs bone arcs, Rift violet glow + floating shards, Ashen Scar ember glow, Sleeping Flame, Mistwood giant trees + glowing undergrowth, frost crystals, waterfalls on steep river steps |
| saves | key `world_version` (3 in the real world); an older save in the real world remaps the player position and shows a toast |
| dungeon anchors (DUNGEON_VISION.md) | Dunhallow/Deepdark, Ironmarch + Coldseam/Redtusk mines, Rift ruins are all in layout.json (ids unchanged) |
Outer-ring places that fell outside the box were pulled 300 m inside it; the Eastern Gate stands on the east border; the four map-edge labels stay in the locked realms.
Tests: `tests/test_world_real.gd`. Probe: `tools_qa/world/real_probe.gd`. Fly-over views: `tools_qa/world/w6_views_real.json` (`tools/world/gen_w6_views.py`).

## Look pass (W6.3, owner review of the first shots)
- Fog: Weather.region_fog_mul; the real world runs the depth/volumetric fog at 0.2x (km-scale views) times a per-biome factor (marsh 2.2, rift 1.8, forest 1.25, highland 0.8), eased with the per-biome grade in real_landmarks.gd.
- Ground: Terrain3DBridge.real_layers - grass/meadow on valley floors, green fell sides with bracken-brown litter, pale highland only in the alpine band, crag/scree rock on steep faces, snow above a noise-broken line; color_at rock (tuned for the 0-300 m world) is ignored in the real world. The far horizon mesh uses the same layering and sits on the lowest ground of its 160 m cell (no poke-through).
- Snow albedo lifted cool-white in the real world.
- Field walls and hedgerows (with bushes) round every settlement on a worker thread, nearest Ashford first, one settlement at a time.
- look_capture hides popups inside the game layer and re-clears overlays before each save.
- Bounds: WorldGen.in_bounds(p, margin) (box in the real world) for towers / realm presence / creatures / outer identity; WorldGen.map_half() (12 288 m in the real world) for the world map, minimap, strategic and war maps.
- Region lock: warden camps (tent, brazier, two wardens) where the old exits meet the border.
- Vertical slice: Bandit Camp and Kestrel\'s Folly (mine theme, dungeon floor 1) pinned to layout.json slice anchors (551, 196) and (790, -1155).
- WP-05 (cloud/wp05-threaded-regions) touches cell_streamer / threaded_loader / interior doors only: no overlap with the Terrain3D bake.

## Gaps
Ground transitions still show 6 m control-lattice steps from the air; field walls are plain boxes (no kit mesh yet); grass/flower density is the existing GrassField; snow reads warm under the noon grade; the parchment/region data of the world map are still old-coordinate.
