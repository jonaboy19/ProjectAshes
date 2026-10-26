# W4 Landmark Inventory

Read-only audit of the Rising Ashes Godot project, worktree `C:\Users\Jonna\Documents\PA_wt_audit`. Nothing in the worktree was edited, no Godot run, no git commands.

Source of places: `docs/world/valencious_places.json` (343 entries; 30 settlements, 1 parchment pin, 266 `site`, 27 `lore`, 12 `camp`, 2 `exit`, 1 `proposed`, 4 `edge`).

## Method and limits

- File paths in the builder column are relative to `kingdom/` (the Godot project root), with `l.N` as the line number. Asset paths are `res://` paths under `kingdom/assets/`.

- **Physical = yes** means the place is planned by code (RegionSites, Region1World, Region1Look landmarks, settlements, camps, caves, towers) and that planner attaches authored parts or procedural geometry. **partial** means only a marker, a gate record, a season-gated body, a water channel, a biome zone, or a road surface. **no** means a label, a parchment pin, a proposal, or a story anchor with no object within reach.
- The discovery list the dump reads is WorldGen.sites plus settlements, camps, and the lore places in `data/world/first_region.json`. Lore entries therefore have no body unless a site or landmark sits on the same point.
- This is a code trace, not a runtime check. Streaming distance, season, quest gates, and frame budget are not evaluated. Builder names are the generator function that emits that kind; I traced the named landmarks and canon sites to their exact part lists, and the generic kinds to their generator.
- Asset existence was checked on disk for every `res://` path referenced by the landmark, canon-site, settlement, extra-site, and placement scripts. Kit paths were chosen by me from existing assets, and each was verified present on disk.
- The brief named `kingdom/scripts/region1/region1_world.gd`. That file does not exist. The actual file is `kingdom/scripts/world/region1_world.gd`.

## Counts

- yes: 316
- partial: 18
- no: 9

## Requested named places

| Place | Physical | Builder (file:function line) | Notes |
|---|---|---|---|
| Hollin Falls | yes | `region1_look.gd` `_build_waterfall` l.586 (landmark `hollins_reach` waterfall, pool built by `_build_fishing` l.424) | Ribbon hugs the `hollins_reach` cliff stamp. The plunge-pool fishing spot is built by the same function. |
| The Wyrm's Ribs | yes | `region1_look.gd` `_build_parts` l.209 (landmark `wyrms_ribs`: `r1:landmarks/giant_skull`, tusks, rib pieces, spine segments) | Terrain: `wyrm_ridge` stamp exists. |
| Grimfen Pass | yes | `region1_world.gd` plan() l.40-45 (`sites.json` `grimfen_pass`, 33 parts; locked exit in `data/world/regions.json`) | Two dump records at the same point (see Data issues). |
| The Eastern Gate | yes | `region1_world.gd` plan() l.40-45 (`sites.json` `eastern_gate`, 38 parts; locked exit) plus `_extra_sites` l.236 for `eastern_gate_outer` | |
| Harrow Arch | yes (body); exit partial | `region1_world.gd` plan() l.49-67 (Harrowgate town landmark "Harrow Arch and Caravan Stage", 18 parts) | `exit:harrow_arch` is a gate record in `data/world/regions.json`, not a body. |
| The Rift | yes, terrain missing | `region_sites.gd` `_rift` l.669 (`meshy:landmark_rift@10`, dead snags, rocks) | Bible section 8 says the Rift is a shallow depression, stamp W4. No such stamp exists. |
| The Ashen Scar | yes, terrain missing | `region_sites.gd` `_outer_sites` l.864 -> `_rift` l.669 | Bible says a broken crater field, `scar_mask` is W3. No stamp exists. |
| Stagborn Glade | yes | `region1_look.gd` `_build_parts` l.209 (landmark `stagborn_glade`: elder stone, runestones in a ring, arch, treant, rock set) | |
| Elder Stone: Highwatch | yes | `region1_world.gd` plan() l.40-45 (`sites.json` `elder_highwatch`, 5 parts) | Keep site stands 120,-1673; stone 105,-1650. |
| Elder Stone: Greyseam | yes | `region1_world.gd` plan() l.40-45 (`sites.json` `elder_greyseam`, 8 parts) | Story place `greyseam_seam` is a marker on it. |
| Elder Stone: Elden | yes | `region1_world.gd` plan() l.40-45 (`sites.json` `elder_elden`, 9 parts) | Elden Road waymarks: `_elden_road` l.211. |
| Elder Stone: Crownstead | yes | `region1_look.gd` `_build_parts` l.209 (`r1:stones/elder_stone` on landmark `crownstead_mill_hill`) | Same point as Crownstead Mill Hill. |
| Elder Stone: Glade | yes | `region1_look.gd` `_build_parts` l.209 (`r1:stones/elder_stone` on `stagborn_glade`) | |
| Tower ruins (13 `tower_ruin` entries) | yes | `region_sites.gd` `_collapsed_tower` l.471 or `_far_ruin` l.1111 (via `_outer_sites` l.843); part `generated/region/ruins/collapsed_tower.glb` | Ashen Watch, Broken Watch, Cracked Obelisk, Drowned Keep, Fallen Beacon, The Hollow Crown, Hollow Keep, Last Beacon, The Old Beacon, Old Watchtower, Sundered Tower, The Weeping Arch, Thornwatch. Same kit for all. |
| Mines (4 `mine`) | yes | `region_sites.gd` `_mine` l.496 (Greyseam) or `_far_mine` l.1135 (others, via `_outer_sites` l.854) | Greyseam, Coldseam, Deepvein, Ironroot Mine. Mine entrance sits on a slope (`flatten` false). |
| Old mines / caves (`old_mine`, cave, crypt, warren, hideout) | yes (procedural mouths) | `region_caves.gd` plan l.86 / `_make` l.121 -> `region_caves_view.gd` `_build` l.110, `_mouth` l.292 | Ironroot Workings, Kestrel's Folly, Redtusk Mine are `old_mine`. |
| Named forests (Duskbriar, Duskfen, Greywood, Hollowfang, Mistwood, Thornwold) | partial | `world_gen.gd` `forest_density` l.871 (tree density zone), `DUSKBRIAR_POS` l.939 | No landmark body. Duskbriar has a bandit camp and a warren, both with bodies. |

## Terrain height stamps still needed

Current stamps: `hollins_reach`, `crownstead_hill`, `wyrm_ridge` (`kingdom/data/region1/terrain_stamps.json`).

1. The Rift (1130, 1004): shallow scarred depression. Bible section 8 calls for stamp W4.
2. The Ashen Scar (2509, 2468), with Scar Watch (2470, 2420) and Scar Mouth Arena: broken crater field. Bible calls for `scar_mask` ground tint (W3) and a crater shape.
3. Mine entrances on slopes: Greyseam Mine (-150, -470), Deepvein Mine (-739, -2564), Coldseam Mine (2783, -5622), Ironroot Mine (-4048, 1305). Candidate cut or trench at each portal. The spec is not written down, so this is a recommendation.
4. Grimfen Pass (560, -3598): candidate trench only if the snow-line pass needs a cut. No spec found.

Already covered by existing stamps: Hollin Falls cliff and Stone Gap (`hollins_reach`), The Wyrm's Ribs (`wyrm_ridge`), Crownstead Mill Hill (`crownstead_hill`). Emberglass Mere is a procedural carve in `world_gen.gd` l.274-277, so it needs no stamp.

## Data issues found

- Duplicate records for the same physical thing (same point or same name), all present in the dump:
  - `site:Crownstead Steward's Hall:621:-80` and `site:crownstead_estate`
  - `site:Grimfen Pass:559:-3598` and `site:grimfen_pass`
  - `site:Highcliff Armoury:187:-1371` and `site:landmark_highcliff`
  - `site:Highwatch Elder Stone:105:-1650` and `site:elder_highwatch`
  - `site:Royal Tourney Lists:323:-322` and `site:landmark_kingsreach`
  - `exit:harrow_arch` and `site:Harrow Arch and Caravan Stage` (0.3 m apart; exit is a record, not a second body)
  - `exit:westfen_fen` and `site:Westfen Herb Walk` (0.5 m apart)
- Scar Mouth Arena has two records 470 m apart: `site:Scar Mouth Arena:2399:2468` (r1id `scar_arena`) and `scar_arena` at (2864.1, 2586.4). The bible's canon is (2864, 2586). Verify which one the planner actually keeps before relying on the arena's location.
- `proposed:silverford` (-640, 480) is a parchment proposal with no planner code.
- `parchment:` (unnamed elder pin at -700, -215) has no planned site.
- Solkar Caravan Camp is summer-only (`sites.json` season gate), so it is partial for the current autumn date.
- Emberglass East Landing (-322, 300) has no dock or boat within 96 m. The dock sits at the west landing (-532, 300).
- Story places in `region1_places.gd` are registry anchors. They resolve to an existing site when one is nearby, otherwise they stay as markers.

## Kits for partial and no entries

Each kit lists only existing repo assets. Full per-row kits are in the table below. Summary of the non-trivial ones:

- Ashford runestone circle (`ashford_ring`, no): three `res://assets/incoming/region1/stones/road_stone_b_menhir_lod0.glb` on a ring of about 21 m, plus `res://assets/incoming/meshy_free/magic/runestone_face_moss_lod0.glb` (same ring pattern as Stagborn Glade).
- The Rift Mouth (`rift_mouth`, no): `res://assets/incoming/ai3d/meshy/landmark_rift_lod0.glb` at 10 m, two `res://assets/generated/region/nature/dead_snag.glb`, and `res://assets/generated/region/nature/rock_cluster.glb`.
- Emberglass East Landing (partial): `res://assets/incoming/meshy_free/water/dock_weathered_pier_lod0.glb` at (-322, 300), `res://assets/generated/rowboat.glb`, and `res://assets/incoming/meshy_free/lighting/lantern_post_wood_lod0.glb`.
- Greenhollow's south fields (no): `res://assets/generated/region/farm/crop_wheat.glb` on a 4.1 m grid, `res://assets/generated/region/farm/fence_rail.glb`, `res://assets/generated/region/farm/scarecrow.glb`.
- Silverford market (partial): stalls from the Guild Hall kit, `res://assets/incoming/meshy_free/market/stall_small_workshop_lod0.glb` and `res://assets/incoming/meshy_free/market/stall_potion_lod0.glb`, and `res://assets/generated/props/crate_stack.glb`.
- Road stretches (Greenhollow road, King's Ember Road): `res://assets/generated/region/road/milestone.glb` about every 80 m.
- Named forests: `res://assets/generated/region/nature/oak_a.glb` and `dark_oak.glb` for tree planting only. No landmark kit is needed.
- Harrow Arch and Westfen fen exits, Solkar camp, lakes, rivers, and map-edge labels need no kit. Their bodies are the landmarks or the terrain already built.

## Full inventory (343 places)

Columns: id, display name, kind, x, z, physical, builder (file:function line), and kit for partial or no entries. The builder cell for partial and no rows also gives the reason.

| id | display name | kind | x | z | physical | builder | kit |
|---|---|---|---|---|---|---|---|
| `settlement:amberley` | Amberley | village | 2042.4 | 3359 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:ashford` | Ashford | village | 0 | 0 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:blackwater` | Blackwater | frontier_town | -5006.2 | 5359.8 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:brackenmoor` | Brackenmoor | frontier_town | 377.7 | 1144.6 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:cindermoor` | Cindermoor | village | -2786.9 | 857.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:coldharbor` | Coldharbor | village | 3014.2 | -3609.6 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:dunhallow` | Dunhallow | village | -1834.4 | -2200.2 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:duskwater` | Duskwater | village | -1395.6 | 4392.3 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:eastmere` | Eastmere | village | 921.1 | 1361.9 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:emberfall` | Emberfall | village | -1791.9 | 2464.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:frostmere` | Frostmere | village | -3963.3 | -1283 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:greywatch` | Greywatch | village | 1449.5 | 1561.9 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:harrowgate` | Harrowgate | village | -85.5 | 2935.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:highcliff` | Highcliff | town | -20.7 | -1457.2 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:hollowmere` | Hollowmere | village | 3892.1 | -1278.5 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:ironmarch` | Ironmarch | town | 2092.4 | -2007.3 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:kingsreach` | Kingsreach | castle | 560 | -420 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:longmeadow` | Longmeadow | town | 3896.7 | 2380.6 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:marrowick` | Marrowick | village | -3364.6 | -3405.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:millbrook` | Millbrook | village | 1050.8 | 816.4 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:oakvale` | Oakvale | village | -942.1 | -633.4 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:ravenscar` | Ravenscar | village | 913.2 | -3304.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:redwater` | Redwater | town | 810.8 | -1387.8 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:saltwick` | Saltwick | frontier_town | -3516.6 | 3351.6 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:skarholm` | Skarholm | village | -1618.7 | -4190 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:stonehollow` | Stonehollow | village | -453.7 | 1156.4 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:thistledown` | Thistledown | village | 616.4 | 4545.6 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:thornfield` | Thornfield | town | 1499.4 | -211.4 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:westfen` | Westfen | frontier_town | 34.5 | 1136 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `settlement:wolfsend` | Wolfsend | village | 3288.1 | 370.1 | **yes** | world_gen.gd settlements -> scripts/world/settlement_builder.gd _build l.183 (+_build_co l.187) |  |
| `parchment:` | (no display name) | elder | -700 | -215 | **no** | none: region1_parchment.json elder pin only (no site planned) | data pin only | none |
| `site:Amberley Apiary:2016:3459` | Amberley Apiary | landmark | 2015.6 | 3458.7 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Amberley Coach Inn:2184:3343` | Amberley Coach Inn | waystation | 2184 | 3343.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Amberley Farm:1990:3265` | Amberley Farm | farm | 1989.6 | 3264.8 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Amberley Lookout:1879:3541` | Amberley Lookout | watchfort | 1879 | 3540.9 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Ashen Hand Hideout:310:-1507` | Ashen Hand Hideout | hideout | 310.1 | -1507.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 |  |
| `site:Ashen Watch:4240:-3138` | Ashen Watch | tower_ruin | 4240.1 | -3137.6 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Ashford Coach Inn:133:-122` | Ashford Coach Inn | waystation | 133.2 | -122.4 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Ashford Farm:-105:26` | Ashford Farm | farm | -104.9 | 25.8 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:ashford_garden` | Ashford Gardens | roadside | -103.9 | 103.9 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `ashford_ring` | Ashford runestone circle | story_place | 0 | 12 | **no** | none: region1_places.gd registry anchor; nearest body is Ashford settlement 12 m away | no ring object in code | res://assets/incoming/region1/stones/road_stone_b_menhir_lod0.glb x3 on a ring r~21 m (as Stagborn Glade); res://assets/incoming/meshy_free/magic/runestone_face_moss_lod0.glb |
| `site:Ashrun Bridge:-313:-211` | Ashrun Bridge | bridge | -313.3 | -210.6 | **yes** | scripts/world/region_sites.gd _bridges l.257; body scripts/world/region_dressing.gd _build_bridge l.731 |  |
| `site:Ashtooth Camp:-5666:-757` | Ashtooth Camp | bandit_camp | -5665.8 | -757.2 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Bandit Camp:490:612` | Bandit Camp | bandit_camp | 489.6 | 612 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Black Rill Grotto:3246:3109` | Black Rill Grotto | cave | 3245.8 | 3108.8 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Blackthorn Camp:1416:2203` | Blackthorn Camp | bandit_camp | 1415.6 | 2202.7 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Blackthorn Hideout:3297:128` | Blackthorn Hideout | hideout | 3297.4 | 128.1 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 |  |
| `site:Blackwater Bastion:-5081:5614` | Blackwater Bastion | fort | -5080.7 | 5613.7 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Blackwater Coach Inn:-4812:5128` | Blackwater Coach Inn | waystation | -4811.5 | 5127.6 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Blackwater Farm:-5043:5482` | Blackwater Farm | farm | -5042.8 | 5481.9 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Blackwater Ford Post:-4864:5322` | Blackwater Ford Post | landmark | -4864 | 5321.7 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Blackwater Wayside Inn:-4694:4969` | Blackwater Wayside Inn | waystation | -4693.8 | 4968.9 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Brackenmoor Coach Inn:574:1161` | Brackenmoor Coach Inn | waystation | 573.5 | 1161.3 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:brackenmoor_row` | Brackenmoor Cottage Row | roadside | 220 | 1102.3 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Brackenmoor Farm:413:1022` | Brackenmoor Farm | farm | 413.3 | 1022.1 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Bramblewick Burrow:1199:-732` | Bramblewick Burrow | cave | 1199.2 | -732.3 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Broken Watch:-3002:-2234` | Broken Watch | tower_ruin | -3002.1 | -2234.3 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Chapel of the Dawn Throne:840:-410` | Chapel of the Dawn Throne | chapel | 839.8 | -409.5 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json dawn_chapel, 14 parts) |  |
| `camp:cinderhollow_warren` | Cinderhollow Warren | goblin_warren | 4961 | -1276 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Cindermoor Coach Inn:-2707:1020` | Cindermoor Coach Inn | waystation | -2707.4 | 1019.6 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Cindermoor Farm:-2895:850` | Cindermoor Farm | farm | -2894.6 | 849.6 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Cindermoor Kilns:-2928:776` | Cindermoor Kilns | landmark | -2928 | 775.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Cindermoor Lookout:-2827:1059` | Cindermoor Lookout | watchfort | -2827.3 | 1058.6 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Cinderpost Waystation:277:-213` | Cinderpost Waystation | waystation | 277.2 | -213.4 | **yes** | scripts/world/region_sites.gd plan() l.40-41 -> _waystation l.332 |  |
| `site:Coldharbor Farm:3010:-3525` | Coldharbor Farm | farm | 3009.7 | -3525.1 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Coldharbor Roadhouse:2399:-2577` | Coldharbor Roadhouse | waystation | 2399.4 | -2577.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Coldharbor Slip:2879:-3573` | Coldharbor Slip | landmark | 2878.7 | -3573.3 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Coldseam Mine:2783:-5622` | Coldseam Mine | mine | 2782.7 | -5622.3 | **yes** | scripts/world/region_sites.gd _mine l.496 or _far_mine l.1135 (via _outer_sites l.854) |  |
| `site:Cracked Obelisk:2579:2326` | Cracked Obelisk | tower_ruin | 2578.8 | 2326.3 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Cragmouth Hideout:-401:3404` | Cragmouth Hideout | hideout | -400.7 | 3403.6 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 |  |
| `crownstead` | Crownstead | estate | 430 | -190 | **yes** | alias of Crownstead Mill Hill landmark (scripts/region1/region1_look.gd _build_parts l.209) at the same point |  |
| `elder_crownstead` | Crownstead Elder Stone | elder_stone | 430 | -192 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (r1:stones/elder_stone) |  |
| `site:Crownstead Mill Hill:430:-190` | Crownstead Mill Hill | windmill_hill | 430 | -190 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (gen:farm/windmill x3, elder stone, banners); _build_scatter l.368 |  |
| `site:Crownstead Steward's Hall:621:-80` | Crownstead Steward's Hall | estate | 620.5 | -80 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json crownstead_estate, 44 parts) |  |
| `site:crownstead_estate` | Crownstead Steward's Hall | estate | 620.5 | -80 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json crownstead_estate, 44 parts) |  |
| `camp:deepdark_warren` | Deepdark Warren | goblin_warren | -3191 | -1605 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Deepvein Mine:-739:-2564` | Deepvein Mine | mine | -738.5 | -2563.7 | **yes** | scripts/world/region_sites.gd _mine l.496 or _far_mine l.1135 (via _outer_sites l.854) |  |
| `site:Drowned Keep:-426:3982` | Drowned Keep | tower_ruin | -425.6 | 3982.3 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Dunhallow Coach Inn:-1761:-2035` | Dunhallow Coach Inn | waystation | -1761 | -2034.9 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Dunhallow Farm:-1776:-2291` | Dunhallow Farm | farm | -1775.7 | -2290.9 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:dunhallow_gate` | Dunhallow Gatehouse Yard | roadside | -1696.6 | -2182.1 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Dunhallow Lookout:-2153:-2205` | Dunhallow Lookout | watchfort | -2153.2 | -2204.6 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Dunhallow Wagon Yard:-1848:-2094` | Dunhallow Wagon Yard | landmark | -1848.4 | -2093.9 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `lore:duskbriar_wood` | Duskbriar Wood | forest | 380 | 480 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb; res://assets/generated/region/nature/bush_dark.glb (tree planting only) |
| `lore:duskfen_wood` | Duskfen Wood | forest | -768 | -4106 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb (tree planting only) |
| `site:Duskwater Farm:-1471:4430` | Duskwater Farm | farm | -1471.4 | 4429.9 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Duskwater Lamp Pier:-1322:4383` | Duskwater Lamp Pier | landmark | -1321.9 | 4382.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Duskwater Roadhouse:-832:3792` | Duskwater Roadhouse | waystation | -832 | 3792.3 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:eastern_gate_outer` | Eastern Gate Outer Towers | roadside | 3797.1 | 386.7 | **yes** | scripts/world/region1_world.gd _extra_sites() l.236 (meshy_extra.json eastern_gate_outer) |  |
| `site:Eastmere Coach Inn:1096:1409` | Eastmere Coach Inn | waystation | 1095.8 | 1408.8 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Eastmere Dairy:885:1274` | Eastmere Dairy | landmark | 884.7 | 1274.2 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:eastmere_dairy` | Eastmere Dairy Barns | roadside | 1009.4 | 1310.9 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Eastmere Farm:948:1467` | Eastmere Farm | farm | 947.8 | 1466.6 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Eastwatch Post:-2580:5311` | Eastwatch Post | watchfort | -2579.6 | 5311 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Elden Elder Stone:-1200:-91` | Elden Elder Stone | elder_stone | -1199.6 | -91.3 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json elder_elden, 9 parts) |  |
| `site:elden_waymark_6` | Elden Waymark | waystone | -1129.4 | -110 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:elden_waymark_5` | Elden Waymark | waystone | -1055.6 | -102 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:elden_waymark_4` | Elden Waymark | waystone | -986.7 | -129.6 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:elden_waymark_3` | Elden Waymark | waystone | -912.9 | -121.6 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:elden_waymark_2` | Elden Waymark | waystone | -844 | -149.3 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:elden_waymark_1` | Elden Waymark | waystone | -770.1 | -141.3 | **yes** | scripts/world/region1_world.gd _elden_road l.211 (road_stone_* about every 70 m) |  |
| `site:Ember Watch:39:272` | Ember Watch | watchfort | 39.2 | 271.9 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Emberfall Bridge:-2212:1785` | Emberfall Bridge | bridge | -2212.2 | 1785.2 | **yes** | scripts/world/region_sites.gd _bridges l.257; body scripts/world/region_dressing.gd _build_bridge l.731 |  |
| `site:Emberfall Farm:-1727:2410` | Emberfall Farm | farm | -1727.1 | 2409.6 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Emberfall Glass Kiln:-1792:2382` | Emberfall Glass Kiln | landmark | -1791.9 | 2381.5 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:emberfall_minster` | Emberfall Minster Yard | roadside | -1923.6 | 2428.8 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Emberfall Roadhouse:-807:2755` | Emberfall Roadhouse | waystation | -807 | 2754.6 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Emberglass East Landing:-322:300` | Emberglass East Landing | ferry | -322 | 300 | **partial** | scripts/region1/region1_landmarks.gd sites() l.20 (site marker only) | no dock or boat part within 96 m | res://assets/incoming/meshy_free/water/dock_weathered_pier_lod0.glb at -322,300 (water); res://assets/generated/rowboat.glb; res://assets/incoming/meshy_free/lighting/lantern_post_wood_lod0.glb |
| `site:Emberglass Ferry:-552:300` | Emberglass Ferry | ferry | -552 | 300 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (emberglass_ferry: dock, hut, lanterns, boat) |  |
| `lore:emberglass_mere` | Emberglass Mere | lake | -420 | 300 | **yes** | scripts/world/world_gen.gd lake carve l.274-277 (LAKE_* l.52-69); lakeside.gd (pier, rowboat, hut) |  |
| `site:Fallen Beacon:-1802:-3324` | Fallen Beacon | tower_ruin | -1801.9 | -3323.8 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Farsight Post:-4633:2753` | Farsight Post | watchfort | -4633.1 | 2752.6 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Farwatch Bastion:256:803` | Farwatch Bastion | fort | 256 | 803.2 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Fenwick Burrows:-1277:-618` | Fenwick Burrows | warren_tunnels | -1277.2 | -618.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Frostmere Coach Inn:-3796:-1278` | Frostmere Coach Inn | waystation | -3795.9 | -1278.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Frostmere Farm:-3872:-1226` | Frostmere Farm | farm | -3871.5 | -1226 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Frostmere Lookout:-3685:-1433` | Frostmere Lookout | watchfort | -3685 | -1432.9 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Frostmere Smokehouse:-3990:-1383` | Frostmere Smokehouse | landmark | -3990 | -1382.7 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Gallows Camp:4628:-678` | Gallows Camp | bandit_camp | 4627.8 | -677.9 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Gallows Hideout:-3700:-1940` | Gallows Hideout | hideout | -3699.9 | -1940.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 |  |
| `elder_glade` | Glade Elder Stone | elder_stone | -1345 | -1060 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (r1:stones/elder_stone on stagborn_glade) |  |
| `site:Gloamreach Cavern:-1709:-3166` | Gloamreach Cavern | cave | -1709.2 | -3165.9 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `camp:gnawbone_warren` | Gnawbone Warren | goblin_warren | 4604 | 1014 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `greenhollow` | Greenhollow | village | -942 | -633 | **yes** | alias of settlement:oakvale (settlement_builder.gd _build l.183) |  |
| `greenhollow_south_fields` | Greenhollow's south fields | story_place | -842.5 | -612.9 | **no** | none: region1_places.gd registry anchor; no field parts planned here (Oakvale Coach Inn 41 m away) | no fields planned | res://assets/generated/region/farm/crop_wheat.glb grid (4.1 m step); res://assets/generated/region/farm/fence_rail.glb; res://assets/generated/region/farm/scarecrow.glb |
| `site:Greyfell Post:812:5487` | Greyfell Post | watchfort | 811.5 | 5486.6 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Greyseam Elder Stone:-188:-499` | Greyseam Elder Stone | elder_stone | -188.1 | -499.2 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json elder_greyseam, 8 parts) |  |
| `site:Greyseam Mine:-150:-470` | Greyseam Mine | mine | -150 | -470 | **yes** | scripts/world/region_sites.gd _mine l.496 or _far_mine l.1135 (via _outer_sites l.854) |  |
| `site:Greywatch Coach Inn:1736:1545` | Greywatch Coach Inn | waystation | 1735.9 | 1545 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Greywatch Farm:1355:1613` | Greywatch Farm | farm | 1354.6 | 1613.4 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Greywatch Spear Hall:1432:1693` | Greywatch Spear Hall | landmark | 1432.3 | 1692.7 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:greywatch_ring` | Greywatch Wall Ring | roadside | 1490.8 | 1661.7 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Greywater Caverns:3008:1951` | Greywater Caverns | cave | 3008 | 1951.1 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `lore:greywood` | Greywood | forest | -1494 | 1789 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb (tree planting only) |
| `site:Grimfen Pass:559:-3598` | Grimfen Pass | pass | 559.5 | -3597.8 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json grimfen_pass, 33 parts; locked exit) |  |
| `site:grimfen_pass` | Grimfen Pass | pass | 559.5 | -3597.8 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json grimfen_pass, 33 parts; locked exit) |  |
| `camp:grimtusk_hold` | Grimtusk Hold | orc_village | -1294 | 2292 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Hangman's Rest:-3089:2321` | Hangman's Rest | bandit_camp | -3088.8 | 2321.1 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `exit:harrow_arch` | Harrow Arch | exit | -198 | 2823 | **partial** | data/world/regions.json (locked exit to site landmark_harrowgate); body = Harrow Arch and Caravan Stage landmark | gate record; the arch is the landmark | none |
| `site:Harrow Arch and Caravan Stage:-198:2823` | Harrow Arch and Caravan Stage | landmark | -197.8 | 2822.8 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Harrowgate landmark, 18 parts) |  |
| `site:harrowgate_church` | Harrowgate Chapel Close | roadside | -189.9 | 2978.3 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Harrowgate Coach Inn:-264:2905` | Harrowgate Coach Inn | waystation | -263.8 | 2904.5 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Harrowgate Farm:-136:2839` | Harrowgate Farm | farm | -135.7 | 2839.5 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Harrowgate Lookout:58:2840` | Harrowgate Lookout | watchfort | 57.8 | 2839.9 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Harrowgate Roadhouse:-17:2181` | Harrowgate Roadhouse | waystation | -17.2 | 2180.7 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Highcliff Armoury:187:-1371` | Highcliff Armoury | landmark | 186.5 | -1371.3 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark parts) |  |
| `site:landmark_highcliff` | Highcliff Armoury | landmark | 186.5 | -1371.3 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Highcliff Coach Inn:239:-1417` | Highcliff Coach Inn | waystation | 239.4 | -1417.4 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Highcliff Farm:-171:-1555` | Highcliff Farm | farm | -171.4 | -1554.7 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:highcliff_forge` | Highcliff Forge Yard | roadside | -175.2 | -1393.2 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Highwatch Elder Stone:105:-1650` | Highwatch Elder Stone | elder_stone | 105.5 | -1650.1 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json elder_highwatch, 5 parts) |  |
| `site:elder_highwatch` | Highwatch Elder Stone | elder_stone | 105.5 | -1650.1 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json elder_highwatch, 5 parts) |  |
| `site:Highwatch Keep:120:-1673` | Highwatch Keep | keep | 120.3 | -1672.7 | **yes** | scripts/world/region1_world.gd plan() l.40-45 -> _place l.110 (sites.json highwatch_keep, 34 parts incl. r1:highwatch/gate); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:highwatch_standards` | Highwatch Standards Yard | roadside | 157.3 | -1608.6 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `highwatch_gate` | Highwatch north gate | story_place | 110.8 | -1658.2 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (highwatch_keep parts include r1:highwatch/gate) |  |
| `site:Hollin Falls:-146:-915` | Hollin Falls | waterfall | -146 | -915 | **yes** | scripts/region1/region1_landmarks.gd sites() l.20 (sub-site hollin_falls); scripts/region1/region1_look.gd _build_waterfall l.586 |  |
| `site:Hollin Watch:-275:-784` | Hollin Watch | lookout | -275 | -784 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (watchtower_stone_small at the site) |  |
| `site:Hollin's Reach:-205:-660` | Hollin's Reach | valley | -205 | -660 | **yes** | scripts/region1/region1_landmarks.gd sites() l.20; scripts/region1/region1_look.gd _build_parts l.209 (hollins_reach parts) + _build_scatter l.368 |  |
| `site:Hollin's Reach Ruins:-138:-478` | Hollin's Reach Ruins | ruins | -138 | -478 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (ruin walls, chapel, well) |  |
| `site:Hollow Keep:3340:3500` | Hollow Keep | tower_ruin | 3340 | 3500.2 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `lore:hollowfang_wood` | Hollowfang Wood | forest | 1422 | 3959 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb (tree planting only) |
| `site:Hollowmere Farm:3919:-1359` | Hollowmere Farm | farm | 3918.8 | -1358.8 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:hollowmere_ruins` | Hollowmere Old Arches | roadside | 3984.2 | -1370.7 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Hollowmere Reed Cutters:3939:-1166` | Hollowmere Reed Cutters | landmark | 3938.7 | -1166 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Hollowmere Roadhouse:3622:-592` | Hollowmere Roadhouse | waystation | 3621.5 | -592.3 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Hunters' Lodge:236:1253` | Hunters' Lodge | landmark | 236.3 | 1253.1 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Hushwater Hollows:3486:3429` | Hushwater Hollows | cave | 3486.3 | 3429 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Ironmarch Bastion:2421:-2294` | Ironmarch Bastion | fort | 2421.5 | -2294.3 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Ironmarch Bridge:2486:-2692` | Ironmarch Bridge | bridge | 2486.4 | -2692.1 | **yes** | scripts/world/region_sites.gd _bridges l.257; body scripts/world/region_dressing.gd _build_bridge l.731 |  |
| `site:Ironmarch Coach Inn:1812:-1892` | Ironmarch Coach Inn | waystation | 1812.3 | -1891.9 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Ironmarch Farm:1914:-2022` | Ironmarch Farm | farm | 1913.5 | -2022 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Ironroot Mine:-4048:1305` | Ironroot Mine | mine | -4047.9 | 1304.6 | **yes** | scripts/world/region_sites.gd _mine l.496 or _far_mine l.1135 (via _outer_sites l.854) |  |
| `site:Ironroot Workings:-2557:117` | Ironroot Workings | old_mine | -2557.2 | 117 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 (procedural mouth) |  |
| `site:Kestrel's Folly:-665:-1133` | Kestrel's Folly | old_mine | -665.4 | -1133.1 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 (procedural mouth) |  |
| `site:Kingsreach Academy of Arms and Arts:241:-288` | Kingsreach Academy of Arms and Arts | academy | 241.3 | -288 | **yes** | scripts/world/region_sites.gd _academy l.711 (ACADEMY_PARTS l.693) |  |
| `site:Kingsreach Coach Inn:879:-368` | Kingsreach Coach Inn | waystation | 878.7 | -367.7 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Kingsreach Farm:453:-654` | Kingsreach Farm | farm | 453.4 | -654.4 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Kingsreach Farm:611:-168` | Kingsreach Farm | farm | 610.7 | -167.5 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Kingsreach Farm:810:-480` | Kingsreach Farm | farm | 810.5 | -479.7 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:kingsreach_fair` | Kingsreach Gate Fair | roadside | 699.6 | -238.1 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:kingsreach_ward` | Kingsreach Outer Ward | roadside | 336.9 | -591.2 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Kingsroad Bastion:1018:-757` | Kingsroad Bastion | fort | 1017.7 | -757 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Last Beacon:4767:-2995` | Last Beacon | tower_ruin | 4767.3 | -2994.9 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Longmeadow Bastion:4292:2474` | Longmeadow Bastion | fort | 4292.1 | 2473.7 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Longmeadow Bridge:3099:2802` | Longmeadow Bridge | bridge | 3098.8 | 2801.6 | **yes** | scripts/world/region_sites.gd _bridges l.257; body scripts/world/region_dressing.gd _build_bridge l.731 |  |
| `site:Longmeadow Coach Inn:3663:2484` | Longmeadow Coach Inn | waystation | 3662.8 | 2483.7 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Longmeadow Fair Green:3765:2552` | Longmeadow Fair Green | landmark | 3765.1 | 2552.2 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Longmeadow Farm:4070:2385` | Longmeadow Farm | farm | 4069.7 | 2385.3 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Marrowick Coach Inn:-3208:-3495` | Marrowick Coach Inn | waystation | -3207.8 | -3495.4 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Marrowick Farm:-3469:-3434` | Marrowick Farm | farm | -3468.8 | -3433.6 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Marrowick Lookout:-3264:-3570` | Marrowick Lookout | watchfort | -3263.7 | -3569.7 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Marrowick Roadhouse:-3557:-2657` | Marrowick Roadhouse | waystation | -3556.8 | -2657.5 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Marrowick Tannery:-3301:-3516` | Marrowick Tannery | landmark | -3300.6 | -3516 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Marrowick Wayside Inn:-3485:-2912` | Marrowick Wayside Inn | waystation | -3485 | -2912.2 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `silverford_guild_hall` | Masons' and Runecarvers' Guild hall | story_place | 2065.4 | -1801.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (Silverford Guild Hall landmark, 0 m) |  |
| `site:Mereside Hollows:-247:-405` | Mereside Hollows | cave | -247.1 | -404.6 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Millbrook Coach Inn:1127:686` | Millbrook Coach Inn | waystation | 1127.3 | 686.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Millbrook Farm:943:811` | Millbrook Farm | farm | 943 | 811 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Millbrook Great Mill:1033:681` | Millbrook Great Mill | landmark | 1033.1 | 681.3 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `lore:mistwood` | Mistwood | forest | -3221 | -614 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb (tree planting only) |
| `camp:mossfang_warren` | Mossfang Warren | goblin_warren | 560 | 250 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Moth-Eaten Crypt:-3062:-2372` | Moth-Eaten Crypt | crypt | -3062.1 | -2372.3 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `camp:mudtooth_burrow` | Mudtooth Burrow | goblin_warren | 1088 | -4699 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Mudtooth Tunnels:2242:-4358` | Mudtooth Tunnels | warren_tunnels | 2242.2 | -4358.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Northreach Post:-2849:-5718` | Northreach Post | watchfort | -2849.4 | -5717.9 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Oakvale Coach Inn:-802:-618` | Oakvale Coach Inn | waystation | -802.2 | -618.5 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Oakvale Farm:-934:-741` | Oakvale Farm | farm | -934 | -741.1 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Old Mill Staff Yard:126:0` | Old Mill Staff Yard | landmark | 126 | 0 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Ashford landmark, 29 parts) |  |
| `site:Old Watchtower:-255:-40` | Old Watchtower | tower_ruin | -255 | -40.2 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:Owlgrave Warren:5291:2777` | Owlgrave Warren | warren_tunnels | 5291.4 | 2777.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:oakvale_farm` | Pennick Farm Yard | roadside | -834.9 | -662.1 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Pennick Farm, Greenhollow:-927:-519` | Pennick Farm, Greenhollow | landmark | -927 | -518.9 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Oakvale landmark, 37 parts) |  |
| `greenhollow_farm` | Pennick farm, Greenhollow | story_place | -927 | -518.9 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (Pennick Farm, Greenhollow landmark) |  |
| `site:Ratfang Tunnels:740:-1901` | Ratfang Tunnels | warren_tunnels | 739.9 | -1900.9 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `camp:ratfang_warren` | Ratfang Warren | goblin_warren | -1370 | 35 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Ravenfoot Camp:2608:-4707` | Ravenfoot Camp | bandit_camp | 2607.8 | -4707 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Ravenscar Farm:843:-3351` | Ravenscar Farm | farm | 842.8 | -3350.9 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:ravenscar_warren` | Ravenscar Goblin Warren | roadside | 834.7 | -3283 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Ravenscar Raven Tower:1004:-3304` | Ravenscar Raven Tower | landmark | 1004 | -3304.1 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Ravenscar Roadhouse:1313:-2838` | Ravenscar Roadhouse | waystation | 1312.6 | -2838.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Red Hand Camp:-617:-2050` | Red Hand Camp | bandit_camp | -617.2 | -2050.2 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `camp:redtusk_camp` | Redtusk Camp | orc_village | -4667 | -1290 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Redtusk Mine:5460:2271` | Redtusk Mine | old_mine | 5459.8 | 2270.7 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 (procedural mouth) |  |
| `site:Redwater Coach Inn:735:-1167` | Redwater Coach Inn | waystation | 735.1 | -1167.2 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Redwater Dye Works:838:-1182` | Redwater Dye Works | landmark | 838 | -1181.8 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Redwater Farm:965:-1296` | Redwater Farm | farm | 964.9 | -1295.7 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Rift's Edge Camp:1069:991` | Rift's Edge Camp | rift_outpost | 1069.2 | 991.1 | **yes** | scripts/world/region_sites.gd _rift_outpost l.640 |  |
| `site:Riftglass Cavern:1178:1295` | Riftglass Cavern | cave | 1178.2 | 1295 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `camp:rotspine_warren` | Rotspine Warren | goblin_warren | -4719 | 1057 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Royal Tourney Lists:323:-322` | Royal Tourney Lists | landmark | 323.5 | -322 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Kingsreach landmark, 34 parts) |  |
| `site:landmark_kingsreach` | Royal Tourney Lists | landmark | 323.5 | -322 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Kingsreach landmark, 34 parts) |  |
| `site:Saltmarch Post:-2548:3860` | Saltmarch Post | watchfort | -2548.2 | 3859.8 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Saltwick Bastion:-3777:3435` | Saltwick Bastion | fort | -3776.7 | 3434.6 | **yes** | scripts/world/region_sites.gd _fort l.601 (via _forts l.563 or _outer_sites l.827) |  |
| `site:Saltwick Coach Inn:-3623:3525` | Saltwick Coach Inn | waystation | -3622.8 | 3525 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Saltwick Farm:-3642:3374` | Saltwick Farm | farm | -3642.2 | 3373.6 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:saltwick_harbour` | Saltwick Landing | roadside | -3534.2 | 3484.7 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Saltwick Roadhouse:-2784:2995` | Saltwick Roadhouse | waystation | -2784 | 2994.8 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Saltwick Salt Works:-3412:3488` | Saltwick Salt Works | landmark | -3411.9 | 3488 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Saltwick Wayside Inn:-3800:3764` | Saltwick Wayside Inn | waystation | -3800.1 | 3764 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Scar Mouth Arena:2399:2468` | Scar Mouth Arena | scar_arena | 2398.8 | 2468.2 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json scar_arena, 29 parts); a second record exists (see notes) |  |
| `scar_arena` | Scar Mouth Arena | scar_arena | 2864.1 | 2586.4 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json scar_arena, 29 parts); a second record exists (see notes) |  |
| `site:Scar Watch:2470:2420` | Scar Watch | rift_outpost | 2469.9 | 2419.7 | **yes** | scripts/world/region_sites.gd _outer_sites l.866 -> _rift_outpost l.640 |  |
| `site:Shrine of the Sleeping Flame:-700:-160` | Shrine of the Sleeping Flame | shrine | -700 | -160 | **yes** | scripts/world/region_sites.gd _shrine l.411 |  |
| `silverford` | Silverford | town | 2092 | -2007 | **yes** | alias of settlement:ironmarch (settlement_builder.gd _build l.183) |  |
| `proposed:silverford` | Silverford (parchment proposal) | town | -640 | 480 | **no** | none: parchment proposal, not planned in code (live Silverford = settlement:ironmarch) | proposal only | none |
| `site:Silverford Guild Hall:2065:-1802` | Silverford Guild Hall | landmark | 2065.4 | -1801.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json Ironmarch landmark, 16 parts) |  |
| `silverford_market` | Silverford market | story_place | 2066.2 | -1807.5 | **partial** | region1_places.gd registry anchor; stalls in Silverford Guild Hall landmark (settlements.json Ironmarch), 6 m away | stalls exist at the Guild Hall, no market square | res://assets/incoming/meshy_free/market/stall_small_workshop_lod0.glb; res://assets/incoming/meshy_free/market/stall_potion_lod0.glb; res://assets/generated/props/crate_stack.glb |
| `site:Silverrun Bridge:2697:178` | Silverrun Bridge | bridge | 2696.7 | 177.8 | **yes** | scripts/world/region_sites.gd _bridges l.257; body scripts/world/region_dressing.gd _build_bridge l.731 |  |
| `site:Skarholm Coach Inn:-1881:-4092` | Skarholm Coach Inn | waystation | -1881.4 | -4091.6 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Skarholm Farm:-1645:-4295` | Skarholm Farm | farm | -1645.2 | -4294.7 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Skarholm Lookout:-1554:-4008` | Skarholm Lookout | watchfort | -1554.3 | -4008.4 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Skarholm Ore Yard:-1597:-4354` | Skarholm Ore Yard | landmark | -1597.1 | -4353.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `camp:skullmarch_hold` | Skullmarch Hold | orc_village | -1716 | 5053 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Skullpick Undercroft:3395:506` | Skullpick Undercroft | warren_tunnels | 3394.8 | 505.6 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `camp:skullpick_warren` | Skullpick Warren | goblin_warren | 2098 | -2663 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:Solkar Caravan Camp:1991:-1831` | Solkar Caravan Camp | caravan_camp | 1990.9 | -1831.4 | **partial** | scripts/world/region1_world.gd plan() l.40-45 (sites.json solkar_camp; season summer gate in scripts/world/region_dressing.gd _in_season l.206) | built only in summer | none |
| `site:Stagborn Glade:-1345:-1062` | Stagborn Glade | glade | -1345 | -1062 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (landmarks.json stagborn_glade: elder stone, runestones, arch, treant) |  |
| `site:Stonehollow Coach Inn:-313:1417` | Stonehollow Coach Inn | waystation | -313 | 1416.9 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Stonehollow Farm:-507:1062` | Stonehollow Farm | farm | -507 | 1062.4 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Stonehollow Quarry:-454:1035` | Stonehollow Quarry | landmark | -453.7 | 1034.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Stonewatch Cave:1776:-3455` | Stonewatch Cave | cave | 1775.5 | -3455 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:Sundered Tower:197:1992` | Sundered Tower | tower_ruin | 197.1 | 1991.8 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:The Ashen Scar:2509:2468` | The Ashen Scar | rift | 2509.3 | 2468.2 | **yes** | scripts/world/region_sites.gd _outer_sites l.864 -> _rift l.669 (meshy:landmark_rift@10 + snags, rocks) |  |
| `site:The Ashfall Spire:2288:-548` | The Ashfall Spire | dungeon_tower | 2287.6 | -548 | **yes** | scripts/world/towers/tower_planner.gd sites(); scripts/world/towers/tower_site.gd _build_exterior l.83 |  |
| `lore:ashrun_river` | The Ashrun | river | -400 | 220 | **partial** | scripts/world/world_gen.gd _place_water l.420 (channel carved; water only) | water channel only, no objects | none |
| `site:The Drowned Bell:-446:318` | The Drowned Bell | sunken_chapel | -446 | 318 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (church_spire_tan in the mere; emberglass_ferry sub-site) |  |
| `site:The Drowned Chapel:3228:3579` | The Drowned Chapel | crypt | 3227.9 | 3579.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `site:The Eastern Gate:3772:481` | The Eastern Gate | border_gate | 3771.9 | 480.8 | **yes** | scripts/world/region1_world.gd plan() l.40-45 (sites.json eastern_gate, 38 parts; locked exit) |  |
| `lore:elden_road` | The Elden Road | road | -950 | -120 | **partial** | scripts/world/world_gen.gd road network (road tiers); no road object | road surface only | none |
| `greenhollow_road` | The Greenhollow road | story_place | -471 | -317 | **partial** | region1_places.gd registry anchor; WorldGen road network (world_gen.gd road tiers); Wayshrine 7 m away | road surface only | res://assets/generated/region/road/milestone.glb every ~80 m |
| `site:The Hollow Crown:-5446:-608` | The Hollow Crown | tower_ruin | -5445.7 | -607.7 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `kings_ember_road` | The King's Ember Road | road | 280 | -210 | **partial** | WorldGen road network (world_gen.gd road tiers); Cinderpost Waystation 4 m away | road surface only | res://assets/generated/region/road/milestone.glb every ~80 m |
| `miller_stone` | The Miller's Stone | story_place | 123 | -14 | **partial** | region1_places.gd registry anchor; nearest body is the Old Mill Staff Yard menhir (r1:stones/road_stone_b_menhir), 14 m away | marker on the Old Mill menhir area | res://assets/incoming/region1/stones/road_stone_a_slab_lod0.glb (one slab at 123,-14) |
| `site:The Old Beacon:2083:2084` | The Old Beacon | tower_ruin | 2082.9 | 2083.5 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:The Old Span:-259:-463` | The Old Span | old_bridge | -259 | -463 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (bridge_serenity_steps at the site) |  |
| `site:The Rift:1130:1004` | The Rift | rift | 1130.2 | 1004.4 | **yes** | scripts/world/region_sites.gd _rift l.669 (meshy:landmark_rift@10 + snags, rocks) |  |
| `rift_mouth` | The Rift Mouth | story_place | 2699.9 | 2513.4 | **no** | none: region1_places.gd registry anchor; nearest body is The Ashen Scar rift, 196 m away | no mouth object | res://assets/incoming/ai3d/meshy/landmark_rift_lod0.glb @10 m; res://assets/generated/region/nature/dead_snag.glb x2; res://assets/generated/region/nature/rock_cluster.glb |
| `lore:silverrun_river` | The Silverrun | river | 2640 | 336 | **partial** | scripts/world/world_gen.gd _place_water l.420 (channel carved; water only) | water channel only, no objects | none |
| `site:The Stone Gap:-87:-656` | The Stone Gap | standing_stones | -87 | -656 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (menhirs, crystal pedestals; sub-site of hollins_reach) |  |
| `site:The Weeping Arch:-5420:851` | The Weeping Arch | tower_ruin | -5420.2 | 850.9 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `site:The Weeping Crypt:-503:3895` | The Weeping Crypt | crypt | -502.6 | 3895.2 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
| `edge:the_western_reaches` | The Western Reaches | map_edge_text | -6000 | 0 | **no** | none: map-edge label text | map label only | none |
| `site:The Wyrm's Ribs:-60:-1700` | The Wyrm's Ribs | bones | -60 | -1700 | **yes** | scripts/region1/region1_look.gd _build_parts l.209 (landmarks.json wyrms_ribs: skull, tusks, ribs, spine) |  |
| `greyseam_seam` | The rift seam, lower Greyseam | story_place | -188.1 | -499.2 | **partial** | region1_places.gd registry anchor on the Greyseam Elder Stone (0 m) | marker on the elder stone | none |
| `site:Thistle Gap Hideout:-2495:1420` | Thistle Gap Hideout | hideout | -2495.3 | 1420.1 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 |  |
| `site:Thistledown Coach Inn:774:4391` | Thistledown Coach Inn | waystation | 774 | 4391.1 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Thistledown Farm:640:4651` | Thistledown Farm | farm | 640.4 | 4650.9 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Thistledown Fold:515:4468` | Thistledown Fold | landmark | 514.9 | 4467.7 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Thistledown Lookout:333:4790` | Thistledown Lookout | watchfort | 333.3 | 4789.7 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Thistledown Roadhouse:226:3604` | Thistledown Roadhouse | waystation | 225.8 | 3604.3 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Thistledown Roadhouse:1204:4033` | Thistledown Roadhouse | waystation | 1203.8 | 4033.4 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Thornfield Brewery:1306:-211` | Thornfield Brewery | landmark | 1306.1 | -211.4 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Thornfield Coach Inn:1411:36` | Thornfield Coach Inn | waystation | 1410.9 | 36.4 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Thornfield Farm:1514:-390` | Thornfield Farm | farm | 1513.7 | -390.4 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Thornwatch:-4584:789` | Thornwatch | tower_ruin | -4584 | 789.3 | **yes** | scripts/world/region_sites.gd _collapsed_tower l.471 or _far_ruin l.1111 (via _outer_sites l.843) |  |
| `lore:thornwold` | Thornwold | forest | 2908 | -1820 | **partial** | scripts/world/world_gen.gd forest_density l.871 (tree density zone; DUSKBRIAR_POS l.939) | biome zone, no landmark body | res://assets/generated/region/nature/oak_a.glb; res://assets/generated/region/nature/dark_oak.glb (tree planting only) |
| `edge:to_the_aurelis_patriarchate` | To the Aurelis Patriarchate | map_edge_text | 6050 | 0 | **no** | none: map-edge label text | map label only | none |
| `edge:to_the_frostcrown_holds` | To the Frostcrown Holds | map_edge_text | 0 | -6050 | **no** | none: map-edge label text | map label only | none |
| `edge:to_the_solkar_dominion` | To the Solkar Dominion | map_edge_text | 0 | 6050 | **no** | none: map-edge label text | map label only | none |
| `camp:tuskridge_hold` | Tuskridge Hold | orc_village | 300 | 930 | **yes** | scripts/world/monster_camps.gd _build l.84 (camp from WorldGen.camp_grounds) |  |
| `site:ward_glade` | Ward-Stone Glade | roadside | -495.4 | 1257.1 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Wayshrine:-4267:4352` | Wayshrine | wayshrine | -4267 | 4351.5 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-3671:-2346` | Wayshrine | wayshrine | -3670.7 | -2345.9 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-2657:2902` | Wayshrine | wayshrine | -2657.5 | 2901.6 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-2595:-2808` | Wayshrine | wayshrine | -2595.2 | -2808.2 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-2489:-3791` | Wayshrine | wayshrine | -2488.8 | -3791.2 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-2283:1657` | Wayshrine | wayshrine | -2283.4 | 1656.9 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-1382:-1420` | Wayshrine | wayshrine | -1382.2 | -1420.3 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-937:2693` | Wayshrine | wayshrine | -936.9 | 2692.8 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-746:3659` | Wayshrine | wayshrine | -745.8 | 3659 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-467:-323` | Wayshrine | wayshrine | -467.1 | -322.5 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-210:1139` | Wayshrine | wayshrine | -209.9 | 1139.2 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:-33:2035` | Wayshrine | wayshrine | -32.5 | 2035.1 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:259:3743` | Wayshrine | wayshrine | 259 | 3743.2 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:284:-204` | Wayshrine | wayshrine | 284.2 | -204.4 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:396:-1429` | Wayshrine | wayshrine | 395.7 | -1429.4 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:652:1247` | Wayshrine | wayshrine | 652 | 1246.7 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:692:-902` | Wayshrine | wayshrine | 692.2 | -902.1 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:979:1088` | Wayshrine | wayshrine | 979.1 | 1087.5 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1028:-309` | Wayshrine | wayshrine | 1028.2 | -308.9 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1183:1468` | Wayshrine | wayshrine | 1182.8 | 1468.5 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1269:300` | Wayshrine | wayshrine | 1268.7 | 299.7 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1334:3958` | Wayshrine | wayshrine | 1333.9 | 3957.7 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1455:-1691` | Wayshrine | wayshrine | 1454.7 | -1691.2 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:1508:-2660` | Wayshrine | wayshrine | 1508 | -2660.4 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:2392:86` | Wayshrine | wayshrine | 2391.6 | 86 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:2559:-2805` | Wayshrine | wayshrine | 2559.4 | -2805 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:2973:2876` | Wayshrine | wayshrine | 2972.8 | 2876 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Wayshrine:3597:-452` | Wayshrine | wayshrine | 3596.7 | -451.8 | **yes** | scripts/world/region_sites.gd _waystones l.360 (wayshrine part l.386) |  |
| `site:Westerly Post:4200:-2357` | Westerly Post | watchfort | 4199.8 | -2357.3 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Westfen Coach Inn:183:1240` | Westfen Coach Inn | waystation | 183.4 | 1240.2 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:Westfen Farm:-58:1223` | Westfen Farm | farm | -58.4 | 1223.3 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Westfen Herb Walk:34:999` | Westfen Herb Walk | landmark | 34.5 | 999 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:westfen_row` | Westfen Stilt Row | roadside | -88.7 | 1064.8 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `exit:westfen_fen` | Westfen fen exit | exit | 34 | 999 | **partial** | data/world/regions.json (locked exit to site landmark_westfen); body = Westfen Herb Walk landmark | gate record; body is the landmark | none |
| `site:Whisper Hollow:-560:520` | Whisper Hollow | hollow | -560 | 520 | **yes** | scripts/world/region_sites.gd _hollow l.427 |  |
| `site:Wolf-Howl Camp:-2758:4989` | Wolf-Howl Camp | bandit_camp | -2757.5 | 4989.1 | **yes** | scripts/world/region_sites.gd _bandit_camp l.444 (or _outer_sites l.862) |  |
| `site:Wolfsend Coach Inn:3551:364` | Wolfsend Coach Inn | waystation | 3551.2 | 363.9 | **yes** | scripts/world/region_sites.gd _waystation l.332 via _coach_stops l.879 or _outer_sites l.818 |  |
| `site:wolfsend_den` | Wolfsend Den | roadside | 3380.3 | 358 | **yes** | scripts/world/region1_world.gd _extra_sites l.236 (meshy_extra.json) or scripts/world/region_sites.gd _roadside_site l.976 |  |
| `site:Wolfsend Farm:3306:477` | Wolfsend Farm | farm | 3305.8 | 476.7 | **yes** | scripts/world/region_sites.gd _farmstead l.207 (or _outer_sites l.791); body scripts/world/region_dressing.gd _build_part_node l.255 |  |
| `site:Wolfsend Lookout:2954:460` | Wolfsend Lookout | watchfort | 2953.7 | 459.7 | **yes** | scripts/world/region_sites.gd _watchfort l.532 or _far_lookout l.1087 / _lookout l.1064 |  |
| `site:Wolfsend Watch Post:3233:504` | Wolfsend Watch Post | landmark | 3232.8 | 503.6 | **yes** | scripts/world/region1_world.gd plan() l.49-67 (settlements.json landmark) |  |
| `site:Wyrmbone Cavern:4797:1377` | Wyrmbone Cavern | cave | 4797 | 1376.6 | **yes** | scripts/world/region_caves.gd plan l.86 / _make l.121 -> scripts/world/region_caves_view.gd _build l.110 + _mouth l.292 |  |
