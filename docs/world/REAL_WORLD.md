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

## Not done yet (engine integration, step 4/5)
WorldMacro mode `real` (HALF 16384, MPP 8), WorldGen settlement positions from layout.json behind the flag + world version bump, Terrain3D region size
for 32 km, water planes for lakes/rivers, region-lock border, fly-over captures. See AAA_PROGRESS.md.
