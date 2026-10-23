# W4 landmarks and POIs (PA_plans/WORLD_BRIEF.md phase W4)

Branch `claude/world-w4` (from `claude/world-t3d`). Inventory: `PA_plans/W4_LANDMARK_INVENTORY.md` (316 yes / 18 partial / 9 no).
Legacy behaviour is unchanged with the W4 data present: every pre-existing site keeps its id, name and position (only the Scar Mouth
Arena and the Scar Mouth Orbs that stand on its point moved, on purpose; see below).

## What was added

| Piece | Where | Notes |
|---|---|---|
| 21 data-driven site kits (193 parts, 5 of them multi-post milestone lines) | `data/region1/world/w4_sites.json`, written by `tools/region1/gen_w4_sites.py`, planned by `scripts/world/region1_w4.gd` | Planned LAST (after `region1_fill`), so no existing id moves. Kinds `waystone` / `roadside` (not listed on the map: the lore places already are). Every part is an existing asset (meshy_free `free:`, region 1 `r1:`, generated `nature:` / `farm/` / `road/` / `props/`). |
| Emberglass East Landing dock, rowboat, lanterns, crates, signpost | `data/region1/landmarks.json` (`emberglass_ferry` parts, water-aware, via Region1Look) | The dock sits on the water level like the west landing. |
| 14 terrain stamps (7 features x 2 macro modes; the mines are 4 x 2) | `data/region1/terrain_stamps.json` + `data/region1/terrain/*_noise.res / *_valencious.res`, designs in `terrain/w4_designs.json`, baker `tools_qa/region1/bake_stamps.gd` | Deltas on whatever ground is there. `"mode"` filters the entry to one macro mode, `"late": true` keeps it out of site planning (see below). |
| Scar Mouth Arena at the canon point (2864.1, 2586.4) | `w4_sites.json` `relocate` | One record now. |
| Tests | `tests/test_region1_w4.gd` (9 cases) | Plus a one-line edit to `tests/test_world_macro.gd` (the arena's bible position). |

### Stamps

All stamps are deltas (`R` metres added, `B` tree keep, `A` rock face < 0.5 so the Hollin limestone kit is not laid on them). Where a delta depends on the
ground (a mine bench) it is baked once per macro mode. They fade to 0 around every flattened site pad, settlement and road, so pads and road beds keep their shape.
`Region1Terrain` loads only the entries whose `mode` equals `WorldMacro.mode()`, and switches `late` entries on in `activate_late()`, the last step of
`RegionSites.plan()`: no site, road or pad is planned on stamped ground, so nothing moves.

| Stamp | noise variant | valencious variant | Why different |
|---|---|---|---|
| `rift_trench` (1130, 1004) | 15 m deep jagged trench, ~600 m long, runs through the Rift site, 2.5 m lip | 7 m narrow inner cleft along the macro's own trench axis | the macro already carries a 15 m trench (`gen_valencious.py`) |
| `ashen_scar` (2700, 2513, the Rift Mouth) | main crater R 92 m / 11 m deep / 3.5 m rim + 9 satellite craters 14-38 m | R 84 m / 7 m + 8 satellites | the macro already has a 16 m basin (sigma 300) and a ring |
| `mine_greyseam / deepvein / coldseam / ironroot` | level bench in front of the portal (clamped to -4 / +6 m) and a 4.5 m headwall brow behind it | same, baked on the macro ground | slope differs per mode |
| `grimfen_pass_cut` (559, -3598) | 7 m deep, 30 m wide notch along the gate axis | 5 m | |

Re-bake: `Godot --headless --path kingdom -s res://tools_qa/region1/bake_stamps.gd -- --mode=noise|valencious [--only=id] [--preview=<dir>]`, then
`py -I kingdom/tools/region1/merge_stamp_index.py <bake logs>`. `tools_qa/region1/w4_hillshade.gd` prints a hillshade of any site's window.

## Inventory coverage (9 no + 18 partial)

| Inventory id | Result |
|---|---|
| `parchment:` (-700,-215) | `w4_elden_marker` (Elden Road Marker: pillar, squat stone, slab) beside the Shrine; the Elden Waymarks already run from the Shrine to the Elder Stone |
| `ashford_ring` | `w4_ashford_ring`: 8 stones (menhir / mossy runestone alternating) on r 8.5 m around (0,12), slab and flowers in the middle |
| `greenhollow_south_fields` | `w4_greenhollow_fields`: 15 wheat tiles, scarecrow, rail fence and gate (snapped to the nearest flat ground) |
| `proposed:silverford` | alias only: parchment proposal, the live Silverford is `settlement:ironmarch`. **Owner question (open)** |
| `rift_mouth` | `w4_rift_mouth`: Meshy rift landmark, snags, rocks, scar crystals, violet light, at the bottom of the Scar crater |
| 4 `edge:*` texts | `w4_edge_west/east/north/south`: border cairn (two pillars, menhir, banner, torches, label) 5.8 km out |
| `lore:duskbriar_wood`, `duskfen_wood`, `greywood`, `hollowfang_wood`, `mistwood`, `thornwold` | `w4_grove_*`: an old big tree (`tree_old_a/b/twisted` @12-14 m) with companion trees, a standing stone and a runestone marker, log, stump, ferns, label; per-forest extras (snags in the fen, limestone fangs in Hollowfang, thorn in Thornwold) |
| `site:Emberglass East Landing` | dock + rowboat + lanterns in `landmarks.json` (see above) |
| `exit:harrow_arch`, `exit:westfen_fen` | alias: the exit record is the landmark body 0.3 / 0.5 m away |
| `silverford_market` | `w4_silverford_market`: well, 8 stalls on a ring, crates, bunting, 4 lamp posts, 46 m off the Guild Hall |
| `site:Solkar Caravan Camp` | alias: summer-only by design (`sites.json` season gate) |
| `lore:ashrun_river`, `lore:silverrun_river` | `w4_ashrun_marker`, `w4_silverrun_marker`: bank stone, lantern post, rocks on the nearest dry bank |
| `lore:elden_road` | alias: Elden Waymarks + the marker above |
| `greenhollow_road`, `kings_ember_road` | `w4_milestones_*`: milestone posts every ~80 m along the road (3 and 6 placed) |
| `miller_stone` | `w4_millers_stone`: slab + rocks at the Old Mill Staff Yard |
| `greyseam_seam` | `w4_greyseam_seam`: scar crystals and slab 30 m up the seam from the Elder Stone |

### Scar Mouth Arena duplicate

`site:Scar Mouth Arena:2399:2468` (planner, searched 44-120 m from the Scar) and `scar_arena` (2864.1, 2586.4, `first_region.json`, the bible's canon) were two records 470 m apart.
The planner site is now moved to the canon point after the whole plan has run (moving it inside the plan shifted 18 caves that are planned later, so it is a post-pass in
`Region1W4._relocate`); the Scar Mouth Orbs on the old point go with it. `first_region.json` and `region1_places.gd` already pointed at the canon point.

## Owner questions still open

1. `proposed:silverford` (-640, 480): keep it as a parchment-only proposal (recommended) or plan a second town.
2. Disk: this phase was run with 4 worktrees of ~14 GB each on a 953 GB drive; the drive reached 0 bytes free once during the phase (other jobs).

## Captures

See the section "Capture reads" appended below (images in `docs/world/w4/`).

## Capture reads (images in `docs/world/w4/`)

Method: `tools_qa/region1/w4_lean_shots.gd` (WorldGen + TerrainStreamer + WaterStreamer + RegionDressing + Region1Look, no game boot), legacy terrain backend,
`--world_macro=valencious`, 1600x900, views from `tools_qa/region1/w4_views.json` (generated by `tools/region1/gen_w4_views.py`). Deviation from the brief
(`--terrain_backend=terrain3d`, PC profile high): the full-game `look_capture.gd` with Terrain3D crashes here (FSR2 + Terrain3D, signal 11, W1_W2_RESULTS) or, with
`--profile=mobile`, did not frame the cameras and ran at ~2 fps; the Godot editor MCP (http://127.0.0.1:8765/mcp) answered `load_skill` but refused
`execute_editor_script` twice ("Backend is not ready", no editor bridge), and its project is PA_wt_mcp, not this worktree. Stamps are plain height deltas, so the legacy
backend shows them exactly as Terrain3D would bake them; the hillshades (`hillshade_*.png`) are `WorldGen.height` itself (stamps included) on both macro modes.

| Image | What I see |
|---|---|
| `stamp_rift_lip.jpg` | A real ravine about 7 m deep with grass walls; the violet Rift object stands on its floor, Rift's Edge Camp keep on the rim at upper left. |
| `hillshade_rift_game_noise/valencious.png` | 600 m jagged trench zigzagging across the window on both modes; the road (red) crosses it as a causeway, nothing is cut under the camp pad. |
| `hillshade_scar_game_*.png` | Main crater with ~8-9 satellite craters of 14-38 m scattered around it, none on the road. |
| `stamp_scar_*.jpg` | Terrain patch is small and wooded, the craters read only in the hillshade; the rim shot is forest floor (weak). |
| `stamp_mine_greyseam/deepvein/coldseam/ironroot*.jpg` | The mine entrance mound stands against a raised headwall brow, with a level grassy bench, rails and the winch in front: reads as a portal cut into a slope. |
| `stamp_grimfen_front.jpg`, `hillshade_grimfen_game_*.png` | The snow gate sits at the end of a shallow notch through the ridge; subtle, reads as a gap rather than a canyon. |
| `site_grove_*.jpg` (6) | A 12-14 m old tree dominates a cleared opening with companion trees, a standing stone, a runestone, a log and ferns and a painted sign. The Greyseam shot below is the weak one. |
| `site_ashford_ring.jpg` | Ring of 8 stones with a sign on the village green (the lean scene has no houses). |
| `site_rift_mouth.jpg` | The Meshy rift landmark: violet fissure in a mossy rock arch with crystals, torches, gate planks and sign. |
| `site_silverford_market.jpg` | Well, 8 different stalls on a ring, lamp posts, bunting and sign; the Guild Hall house is on the hill to the right. |
| `site_greenhollow_fields.jpg` | Fenced wheat plot with scarecrow next to the farm. |
| `site_ashrun_marker.jpg`, `site_silverrun_marker.jpg` | Pillar, rocks, lantern and sign on the lake / river bank. |
| `site_emberglass_east_landing.jpg` | Pier, rowboat, lantern posts and crates on the east shore of the Mere. |
| `site_milestones_ember_1.jpg` | One milestone on the verge of the Ember Road, Kingsreach on the skyline. |
| `site_edge_*.jpg` | Two pillars, menhir, banner, torches and a sign on the rim slope (the west one stands under a grey mountain wall: the edge rim). |
| `site_scar_arena.jpg` | The Scar Mouth Arena at its canon point: pillar ring, purple crystals, lamp posts and the dark arch. |
| `site_greyseam_seam.jpg` | Weak: the crystals are hidden behind canopy (cyan and violet showing through the foliage); the site exists but needs a higher camera. |
