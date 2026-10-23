# W5 QA: capture verdicts (every image read)

Setup: 1920x1080, `--profile=pc --quality=high --terrain_backend=terrain3d --world_macro=valencious`, `tools_qa/region1/look_capture.gd` via `tools_qa/world/run_w5_captures.sh`, weather pinned clear. Contact sheets of all images are in `docs/world/w5/` (JPG, 6 per sheet, labelled); full PNGs stay local. The machine was on battery for part of the run and shared with another agent's profiling run, so capture fps is not a measurement.

Read as 6-up sheets (640x360 per image); the fix shots were also read at full size. One line per image.

## Summary

- Best: `ref_gate_aerial`, `ref_gate_market_noon` (matches the owner reference), `ref_tuskridge_hut_camp_noon`, `grid_32` (Kingsreach + Ashford), `w04_silverrun_valley_ground_dawn`, `w02_northern_ridge_ground_noon`, `w07_ashen_scar_ground_noon`, `w09_westfen_marsh_ground_dawn`, `w06_rift_marches_ground_noon` (was unusable).
- Worst: aerial grid shots show hard-edged olive/ochre polygon patches in the mid-near field (Terrain3D two-layer control-map edges, W1 issue 1, NOT fixed), a flat rectangle under the capture camera (streamed ring), a flat green plane beyond the world rim, a pink polygon at the Rift in the `w06_*_aerial` shots, a dark flat plane in `w08_greywood_emberfall_aerial120`, dawn/dusk `ref_*` frames identical to noon (hour pin ignored near towns), Heartvale ground still the least green.
- Fixes verified in these images: Rift Marches ground + orbit, aerial fog (blue-violet, height scaled), sign fitting, far-field smoothing (4 grid shots re-taken after the horizon fix: far polygons gone, near-field patches remain).

## Aerial grid (36 at 600 m), reference spots, Rift orbit, signs

| image | verdict |
|---|---|
| grid_00 | NW corner: world rim wall reads (pink cliff band), ochre/olive polygon patches in the near field, hazy but not dusty |
| grid_01 | north-west highlands: rim ridge visible, hard-edged ochre litter polygons near camera |
| grid_02 | west: soft rolling relief, lake glint at left, flat olive rectangle under the camera (streamed ring) |
| grid_03 | west-centre: gentle hills, flat rectangle under camera; far field smooth after the horizon colour fix |
| grid_04 | south-west: rolling green hills, hard dark patches near camera |
| grid_05 | SW corner: rim ridge, river glint, lime pool field around the camera spot |
| grid_10 | north edge rim band, gold patches near camera: readable, patches hard-edged |
| grid_11 | Ironmarch/ridge belt: pink-brown rock hills with olive polygon cutouts: reads as highland, edges hard |
| grid_12 | west of Hollin: green rolling, rim ridge at top: good |
| grid_13 | Heartvale west: green hills, small fields, spire at horizon: good |
| grid_14 | south-west: lime field cluster, river line: ok |
| grid_15 | south: lime meadow patch at right: ok |
| grid_20 | north rim band, gold polygon patches near camera: ok, hard edges |
| grid_21 | northern ridge: pink/brown mass with olive polygon cut-outs: reads as highland but patchy |
| grid_22 | Heartvale + Hollin's Reach: fields, road, valley wall at right: best of the grid |
| grid_23 | Rift/Westfen area: lake, river, crater rim at left, dark patches at bottom: good |
| grid_24 | south: bright lime meadow, road: good, slightly flat |
| grid_25 | south: lime meadows, hard patches: ok |
| grid_30 | north rim: ok, gold polygons |
| grid_31 | Grimfen ridge: big pink massif with olive cut-outs and a sheer slope: reads as mountains |
| grid_32 | Kingsreach + Ashford ring with fields at left: very good |
| grid_33 | Rift Marches: dark violet scar patches near camera, fields at left: reads |
| grid_34 | south-east: lime meadow, dark violet patches at right (Scar influence): ok |
| grid_35 | south: lime/olive patches: ok |
| grid_40 | NE: eroded mesa shapes (Ironmarch) on gold ground: distinct and good |
| grid_41 | NE mesas with olive tops: good |
| grid_42 | Ironmarch: river, dark forest cut-outs: ok, hard edges |
| grid_43 | east: green rolling hills, bridge-tower spire at top left: ok |
| grid_44 | Ashen Scar: violet-brown badlands with glinting pools: distinct, slightly glossy |
| grid_45 | south-east: lime fields, road/river: ok |
| grid_50 | NE corner: mesas + rim cliff: good |
| grid_51 | east edge mesas with cliffs: good |
| grid_52 | east: mixed gold/green, cliff at right: ok |
| grid_53 | SE: violet scar patches near camera, rim ridge, flat green plane beyond the world edge (sky ground colour): ok, edge unfinished |
| grid_54 | SE: scar patches, rim: ok |
| grid_55 | SE corner: bright lime meadow, rim: ok |
| ref_gate_aerial | Kingsreach from 90 m: gatehouse, wall ring, red/blue roofs, green grass between houses: excellent |
| ref_gate_market_dawn | lighting identical to noon (hour pin did not take effect near a town); cobbles lime-yellow from the lush grade (bug, fixed afterwards) |
| ref_gate_market_noon | owner reference spot: gate towers, awnings, banners, stalls, trees; matches 00_MAIN in layout and density, cobbles too yellow-green (grade bug, fixed afterwards) |
| ref_gate_market_dusk | identical to noon (see dawn) |
| ref_tuskridge_aerial | Tuskridge from 60 m: palisade ring, meadow, soft green: reads as a hut camp |
| ref_tuskridge_hut_camp_dawn | same lighting as noon (hour pin); meadow, tall grass, palisade, distant spire and hills: the hut-camp look |
| ref_tuskridge_hut_camp_noon | best meadow shot: lush grass, bush, rock, flowers, palisade |
| ref_tuskridge_hut_camp_dusk | same as noon |
| rift_orbit_a_south | the Rift trench from the south, 6 m up: real gorge, olive floors, violet-black ash walls, Rift gate on the floor: correct |
| rift_orbit_b_east | from the east rim: boulders, bushes, ravine: correct |
| rift_orbit_c_north | from the north: trench and the Rift stone on the far side: correct |
| rift_orbit_d_west | west rim with palisade fence and camp: correct |
| sign_duskbriar_old_oak | sign board fits the title (two lines); sub line cut by the standing stone: ok |
| sign_mistwood_heart_tree | MISTWOOD / HEART-TREE inside the board; sub line slightly wider than the board (fitted afterwards, not re-shot) |

## Sub-region views (12 regions: ground 1.7 m, dawn/dusk for 6 of them, aerial 120 m and 400 m)

| image | verdict |
|---|---|
| w01_heartvale_aerial120_noon | town ring on a hill, fields, spire: good, soft blue haze |
| w01_heartvale_aerial400_noon | Heartvale overview: town, fields, road, hills: very good |
| w01_heartvale_ground_dawn | olive-brown leaf ground, dim: still brownish |
| w01_heartvale_ground_dusk | dark olive: brownish |
| w01_heartvale_ground_noon | yellow-olive ground with tufts: richer than W3 but not lush green (grade strengthened afterwards) |
| w02_northern_ridge_aerial120_noon | Highwatch ring, fields: good |
| w02_northern_ridge_aerial400_noon | fields + dark olive polygon forest cut-outs: ok |
| w02_northern_ridge_ground_dawn | flower meadow, keep on the hill, violet dawn sky: very good |
| w02_northern_ridge_ground_dusk | same framing as dawn, light close to it: good |
| w02_northern_ridge_ground_noon | flower meadow with cattle, keep: very good |
| w03_ironmarch_highlands_aerial120_noon | road through green-gold highlands, misty: good |
| w03_ironmarch_highlands_aerial400_noon | mesa shapes and patches: ok |
| w03_ironmarch_highlands_ground_noon | oak wood, trunks, flowers: good |
| w04_silverrun_valley_aerial120_noon | river and green valley, hazy: good |
| w04_silverrun_valley_aerial400_noon | river valley, fields: good |
| w04_silverrun_valley_ground_dawn | bridge, tall grass, trees, violet dawn: very good |
| w04_silverrun_valley_ground_dusk | near identical to dawn: good |
| w04_silverrun_valley_ground_noon | saturated lime grass, bridge, river: very good (a touch neon) |
| w05_duskbriar_wood_aerial120_noon | tree clumps on lime, camp: ok |
| w05_duskbriar_wood_aerial400_noon | patchy: ok |
| w05_duskbriar_wood_ground_noon | dense oaks, flowers, ferns: good |
| w06_rift_marches_aerial120_noon | violet-grey scarred plain, road, pink polygon near the Rift: the pink polygon is wrong |
| w06_rift_marches_aerial400_noon | violet scar region with lime outer fields, pink blob at the Rift: pink blob wrong |
| w06_rift_marches_ground_dawn | FIXED: trench floor and walls render, Rift at the far end: good |
| w06_rift_marches_ground_dusk | good, violet dusk |
| w06_rift_marches_ground_noon | FIXED: gorge reads correctly |
| w07_ashen_scar_aerial120_noon | violet ash plain with ring craters, misty: reads as a scar |
| w07_ashen_scar_aerial400_noon | violet badlands, crater rings: good |
| w07_ashen_scar_ground_dawn | camp on violet ash, tents, palisade: very good |
| w07_ashen_scar_ground_dusk | like dawn: good |
| w07_ashen_scar_ground_noon | camp on violet ash with moss and grass: very good |
| w08_greywood_emberfall_aerial120_noon | dark flat plane among tree belts: odd flat dark area |
| w08_greywood_emberfall_aerial400_noon | olive patchwork, river at left: ok |
| w08_greywood_emberfall_ground_noon | lush meadow with flowers, tree line: very good |
| w09_westfen_marsh_aerial120_noon | dark green flat marsh field with pools: reads as fen |
| w09_westfen_marsh_aerial400_noon | marsh slab with pools, dashed road: ok, big flat dark rectangle |
| w09_westfen_marsh_ground_dawn | tall reed grass, snag, violet dawn: very good |
| w09_westfen_marsh_ground_dusk | good |
| w09_westfen_marsh_ground_noon | tall grass marsh with dead trees: good |
| w10_mistwood_west_aerial120_noon | olive plain with tree clusters: flat but ok |
| w10_mistwood_west_aerial400_noon | olive/green patches: ok |
| w10_mistwood_west_ground_noon | flowers, old tree, oak wood, forest floor: very good |
| w11_dunhallow_uplands_aerial120_noon | peach highland polygons + conifers: highland reads, hard polygons |
| w11_dunhallow_uplands_aerial400_noon | peach/olive polygons: hard-edged patches |
| w11_dunhallow_uplands_ground_noon | dark green plateau, rocks, ferns, conifers: good |
| w12_harrowgate_steppe_aerial120_noon | lime steppe with tree clumps, big shadow: good |
| w12_harrowgate_steppe_aerial400_noon | lime steppe: ok |
| w12_harrowgate_steppe_ground_noon | oak, tall grass, berry bush: very good |

## Performance (PC_HIGH 2560x1440, RTX 4070 Laptop, `--profile=pc --quality=high`)
**Conditions (read before using any number):** the laptop was on BATTERY (BatteryStatus 1, 55-69 %), not AC, and another agent's 2560x1440 town-route profiling run (PA_wt_audit) was running at the same time; the Godot editor MCP was down. Frame times came out at a constant 133 ms (7.5 fps) with Terrain3D+macro and 129 ms (8.1 fps) legacy+noise, independent of draw count (flight: 87-147 draws, same 133 ms), i.e. a power/shared-GPU cap, not the renderer. **Treat fps and p50/p1 as invalid; re-run on AC with nothing else running** (`tools_qa/perf/town_route.gd --seconds=100`, `tools_qa/perf/aerial_flight.gd`).
| run | result |
|---|---|
| town route, terrain3d + valencious (60 s) | p50 133.1 ms, p95 143.8, p99 147.0 (p1 fps ~6.8); avg 2026 draws, 6.0 M prims (max 2617 / 8.0 M); VRAM 3077 MB (textures 2443, buffers 527); static mem 1252 MB; 22 399 nodes |
| town route, legacy + noise (60 s) | p50 129.0 ms, p95 143.4, p99 147.3; avg 2289 draws, 5.7 M prims (max 3378 / 7.7 M); VRAM 3111 MB; static 1066 MB; 16 282 nodes |
| aerial flight 9 km at 70 m/s, 400 m up, terrain3d + valencious | p50 133.3 ms, p99 145.8; draws 81-147, 0.26-0.3 M prims; VRAM 3162 MB; 159 Terrain3D regions added; **region bake hitch (main thread add_region): avg 15.4 ms, worst 77.4 ms** (inflated by the loaded machine; headless W1e measured 5 ms); static 1185 MB; process RAM not sampled (OS reports 15.6 GB physical) |
| aerial flight, legacy + noise | did not finish (run ended without FLIGHT_SUM; first windows p50 124 / 75 ms) |
Take-aways that are not fps: Terrain3D + macro costs about +190 MB static memory and +6 000 nodes (ProtonScatter) in town; draw count is lower than legacy at the same spot; VRAM equal.
