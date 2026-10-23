# W3 - biome dressing (results)

Code: `scripts/world/world_biomes.gd` (tables + soft biome field), `scatter_chunk.gd` / `scatter_world_modifier.gd` (per-biome kinds, density, height caps, scar slot),
`grass_field.gd` (density + mix by biome, Quality `grass_mul`), `terrain_streamer.gd` (floor cards follow the biome), `terrain3d_look.gd` + `shaders/terrain3d_ground.gdshader`
(Terrain3D shader override: wetness, season, snow, Scar Tide), `terrain3d_bridge.gd` (soft control map + lush colour map), `tools/world/make_biome_soft.py`
(re-run after gen_valencious.py), slot 10 `highland` (`pack_ground_textures.gd`). Tests: `tests/test_world_biomes.gd` (7). Legacy (`--world_macro=noise`) is unchanged: every hook is gated by `WorldBiomes.active()`.

## Capture setup
`--profile=mobile --quality=high` (FSR2 + Terrain3D crashes on this engine, see W1_W2_RESULTS), `--grass_scale=1.5` (= PC_HIGH grass_mul), 1920x1080, AC power.
Views `tools_qa/world/world_views_w3.json` (ground 1.7 m, aerial 120 m). Images: `docs/world/w3/pairs/*_pair.jpg` (top ground, bottom aerial); full PNGs stay local in `docs/world/w3/`.

## Verdicts (every pair read)
| Region | Ground | Aerial |
|---|---|---|
| w01 Heartvale | olive litter-brown under tufts, still the muddiest ground (farmland patch at that spot; MIX_FARM lowered after the shot) | green-gold, soft biome edges, hills with hard polygon silhouettes (macro geometry) |
| w02 Northern ridge | best shot: flowers + tall grass meadow, hut-camp look | patchwork fields round the town read well |
| w03 Ironmarch | oak/beech wood, flowers, grass | brown-green, road visible |
| w04 Silverrun | lush tall grass, oaks + spruce, flowers | river + green/brown, soft |
| w05 Duskbriar | dense broadleaf woodland, flowers/ferns, dark oak | tree clumps on green |
| w06 Rift Marches | NOT USABLE: tilted purple plane and empty fog floor (Rift trench / missing ground, W1/W4 issue; same with warm 500) | dead snags on tan, roads |
| w07 Ashen Scar | violet-black ash, sparse tufts, camp: clearly distinct | brown flats, dead snags, lime plateau polygons |
| w08 Greywood | open meadow + flowers, distant tree line | tree belts on tan |
| w09 Westfen | tall reed-like grass, dead snags, dark mud | marsh/green mix, dark tree clumps |
| w10 Mistwood | grey-green gravel flat (rock texture dominates a flat spot), woodland edge | tree stands |
| w11 Dunhallow | sparse conifers, rocks, bushes, short green-brown highland | tan polygon patches (distant macro/horizon) |
| w12 Harrowgate | scrubby steppe, oaks, berry bushes | brown/olive with tree stands |

Remaining visual problems (not in W3 files): aerial shots are buried in the capture's dust haze; distant relief has hard polygon silhouettes and lime/tan plateau patches (macro heightmap / Region1Horizon, W1); w06 above; heartvale ground still brownish.

## Perf (Ashford -> Kingsreach, `tools_qa/perf/town_route.gd`, 2560x1440, forward_plus, mobile profile quality high, AC power (BatteryStatus 2, 86 %), RTX 4070 Laptop; other agents' Godot processes were running)
| backend | route p50 (route summary) | first 80 s window p50 | last 30 s |
|---|---|---|---|
| legacy + noise | 24.1 ms | 48-94 ms | 17 ms (44 fps) |
| terrain3d + valencious (W3) | 19.9-22.1 ms | 52-124 ms | 17 ms (42-46 fps) |
Both are CPU-bound while chunks stream (cpu 100-450 ms in the heavy windows, gpu 5-22 ms). PC tiers cannot be measured (FSR2 crash), so PC_HIGH fps is unmeasured.
Scatter maths (ScatterWorldModifier, main thread, per role per chunk, 80 candidates): 11.2 ms avg / 63 ms max before, **5.1 ms avg / 40.7 ms max** after the keep-roll reorder (identical output).
Per-chunk scatter wall time attach->finished is 21 s avg (ProtonScatter queue behind a 100 ms frame time), so the 4 roles x 5 ms = ~20 ms of main-thread maths per new chunk is the real cost; GrassField.plan runs on the worker.
