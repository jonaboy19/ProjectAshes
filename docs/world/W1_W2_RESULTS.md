# World macro terrain: W1 + W2 results (2026-10-22)

Branch `claude/world-t3d` (merged into `claude/focused-curie-m09hbd`). Flags are **off by default**: `--world_macro=noise|valencious` (default noise) and `--terrain_backend=legacy|terrain3d` (default legacy). Legacy output is unchanged.

## What exists
- `kingdom/tools/world/gen_valencious.py` (+ `valencious_common.py`): deterministic numpy/scipy generator, `py -E -B kingdom/tools/world/gen_valencious.py [--verify]` (about 35 s; `--verify` passes byte-identical). Inputs: `docs/world/valencious_places.json`, `kingdom/data/world/valencious_regions.json` (12 sub-regions, 3 ridge spines + 2 spurs, plateau, mesa style), `kingdom/data/world/macro/raw_core.json` (WorldGen noise around Ashford/Kingsreach from `tools_qa/world/dump_raw_height.gd`).
- Outputs in `kingdom/data/world/macro/`: `height_16.png` (4097 px, 16-bit, 3 m/px, h = -20 + v/65535*320; filter-0 PNG so the game can inflate it without a PNG decoder), `biome_ids.png`, `splat_weights.png` (RGBA = meadow, farmland, marsh, rift ash), `preview.png`, `meta.json` (input sha256).
- `scripts/world/world_macro.gd` (`WorldMacro`): loads the PNG once in `WorldGen.setup` (about 0.33 s, 38.8 MB), `sample(x, z)` bilinear read-only. One hook in `WorldGen._raw_height` (`# Valencious macro hook`).
- **Positions never move.** `WorldGen.setup` runs the whole legacy setup (settlements, roads, camps, sites) with the macro suspended, then `_rebase_to_macro` re-seats settlement/camp/clearing `base_h`, the lake and rivers (levels follow the macro ground) and the Westfen pools. `tests/test_world_macro.gd` asserts all settlements, 869 sites, camps, road topology and all 343 bible positions are identical with the macro on.
- Terrain3D bridge: 10 texture slots (0-4 legacy; 5 meadow, 6 farmland, 7 marsh mud, 8 rift ash, 9 snow/scree) packed by `tools_qa/terrain3d/pack_ground_textures.gd` from existing Poly Haven sets only (graded offline). Control map reads `biome_ids`/`splat_weights` plus height/slope for snow; legacy control words are unchanged when the macro is off.

## Numbers
| Item | Result |
|---|---|
| Height range | -12.6 to 300 m, p50 50 m, p95 143 m; 3.0 % of the world above the 180 m snow line |
| Hollin's Reach fit (W1c) | existing additive stamps fit the macro: wall relief 79-108 m vs 68-104 m on noise; river source 16.8 m, floor about 5 m lower; no re-bake needed (`tools_qa/world/fit_probe.gd`) |
| Runtime bake (W1e, headless) | worker maths 3-9 s per 384 m region (macro adds about 0.6 s); main-thread `add_region` 5 ms (first region 1.4 s one-off Terrain3D init); macro 38.8 MB RAM. **Decision: no offline bake** (hitch far below the 50 ms rule); `tools_qa/terrain3d/bake_world.gd` stays as the measurement tool |
| Rivers (W2) | 1,000+ samples every 16 m: centre always wet, shore gap p95 0.05 m, max 0.09 m (limit 0.3); macro does not change this |
| Roads (W2) | share of the 42.4 km of roads steeper than 12 %: 46.5 % on noise, 11.6 % raw macro, **7.3 % after generator road grading** (remaining: Hollin's Reach walls, town pad edges) |
| Pads (W2) | 242 flattened clearings: 8 off by more than 0.2 m at 0.6 r, worst 0.54 m (noise: 9, worst 2.81 m); the 25+ Region 1 landmark pads are within 0.6 m |
| Westfen pools | up to 8 fixed spots on genuinely low (<= 8 m) fen ground, skipped when near roads, settlements or site clearings; only with the macro on (`WorldGen.pools`) |

## Decisions and deviations (briefly)
- Road grading is done in the generator (cut/fill along each straight road to <= 8.5 % grade, valleys left alone) instead of switchback waypoints: roads are straight segments between settlement centres that traffic, gates and ward stones also use, so polylines would ripple through the game.
- Pool and river "one source": WorldGen's own polylines are dumped (`docs/world/dump_world_water.txt`, `valencious_places.json`) and the generator consumes them; the macro valley meanders +-80 m inside a 150 m half-width so WorldGen's fine channel always stays inside it.
- Ravenscar (913, -3304) sits on the main ridge at 203 m (above the snow line); the settlement pad is flat but the village is alpine. Not moved (positions are fixed).
- Westfen marsh is genuinely low only for z 1300-1600; further south the macro rises (15-27 m) because neighbouring bands blend in. Pools are placed only on the low part.
- Hold zone: raw noise terrain strictly within 300 m of Ashford and 350 m of Kingsreach, blended to a sigma 60 m smoothed copy out to 1600 m.
- The northern range is a continuous west-east spine through Grimfen Pass but still reads as a broad massif with one snow field, not sharp crests.

## Terrain3D on this machine (important)
- Terrain3D 1.0.2 on Godot 4.6.3 (Forward+, RTX 4070 Laptop) **crashes (signal 11) when texture assets and the first region are set in the frame the node enters the tree** (found by the first GPU captures; headless tests never saw it). Fix in `terrain3d_bridge.gd`: regions first, assets two frames later on a GPU (immediately when headless). Probe: `tools_qa/terrain3d/gpu_probe.gd --v=assets9late`.
- **FSR2 + Terrain3D also crashes** at startup ("Width must be equal or greater than 1 for all textures" then signal 11), so the PC tiers (high/medium use FSR2) cannot run the Terrain3D backend; captures were taken with `--profile=mobile --quality=high` (FSR1). `quality=ultra` ran out of memory / time on this 15 GB laptop. A QA option `--aa=` was added to `look_capture.gd`, but FSR2 is applied before it can take effect. A fix needs Terrain3D 1.1+ (not downloaded) or a Quality change (not my file).
- New texture `.import` files must copy the legacy ones (VRAM compression + mipmaps), otherwise Terrain3D complains that texture formats differ.

## Capture verdicts (24 world views, left = legacy + noise, right = terrain3d + valencious; `docs/world/captures_w1/*.jpg`)
Setup: 1920x1080, `--profile=mobile --quality=high` (FSR1; see the FSR2 crash above), battery status 2 (AC). The aerials at 400 m are buried in the capture's yellow dust haze on both sides, so they only show ground colour/patterns; fps is not meaningful for this and no perf number is claimed. Every pair was read.
| Sub-region | Ground view (right image) | Aerial (right image) |
|---|---|---|
| 1 Heartvale | first-view artefact: the first view of a run shows the Ashford market (player), the earlier run showed bare red-brown farmland soil with grass tufts; after the tint fix the soil is olive-brown with meadow/flowers | patchwork of farmland/meadow with a town ring and the Crownstead hill; field grid visible |
| 2 Northern ridge | gentle tan-green slope with Highwatch Keep in the distance; the pairing legacy view shows a big peak, the macro hills are lower and rounder at this spot | haze only; far rim visible; no sharp crests |
| 3 Ironmarch highlands | dense oak forest, darker brown litter floor, similar to legacy | broken tan/green patches |
| 4 Silverrun valley | wooded bank, the river/pond and wide valley floor with farmland visible, trees, ferns; reads as a valley | the Silverrun channel and its valley floor read clearly |
| 5 Duskbriar | woodland floor with leaf litter and flowers, open glade | patchy forest/meadow |
| 6 Rift marches | after the tint fix: ash/violet patches mixed with grass below the Rift gate; before: a solid violet floor (too strong, fixed by 0.6x ash weight and a less saturated grade) | violet-free haze, patch edges polygonal |
| 7 Ashen Scar | camp on dark violet ash soil with meadow flowers; reads as scarred ground | angular badland patches |
| 8 Greywood / Emberfall | flat lush meadow with bushes and a boulder on brown soil | broad patches |
| 9 Westfen marsh | dark muddy soil with grass tufts, woods and a path; pools not in view | pools visible as pale ovals among dark mud patches |
| 10 Mistwood | leaf-litter forest floor | haze |
| 11 Dunhallow uplands | high flat brown plain with rocks and sparse bushes: reads as a plateau but dry and bare (no grass) | polygon patches |
| 12 Harrowgate steppe | woodland edge with flowers and a sandy clearing; not yet a dry steppe look | hard-edged patches |
Overall: the macro gives distinctly different ground by region (farm soil, forest litter, marsh mud, ash, plateau) and the valleys/rivers read; open problems are (1) hard polygonal biome edges from the 12 m splat plus Terrain3D's two-layer control map, (2) the ground is browner/drier than the legacy lush green, (3) dry/bare highland and steppe ground has no texture of its own, (4) the northern ridge lacks sharp crests, (5) Terrain3D cannot run with FSR2 on this engine/addon pair. Texture dressing and the Terrain3D shader override are W3 (separate agent).
