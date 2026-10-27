# CC0 slice kit (Poly Haven + ambientCG) — 2026-10-27

This is a prop and material kit for the benchmark slice (`docs/plans/BENCHMARK_SLICE.md`): the Ashford market street and side street, the tavern/house interior, and the countryside road to the bandit camp. **Nothing here has been placed in any scene.** The towns and world workers own placement. Everything is CC0 1.0, and each folder has a `LICENSE.txt` with the source URL. The download log is in `docs/plans/DOWNLOADS.md` (section "CC0 slice kit").

Props the Meshy batch is making were skipped on purpose: handcart with sacks, well, barrel rack, crate stack, bench, horse trough, tavern sign, trestle table, hearth, rope bed, ladder, market stall and cobbler sign.

## Contact sheets (Godot 4.6.3 Forward+, GPU, windowed; sun + `belfast_open_field` HDRI, neutral grey ground)
- `docs/plans/cc0_lookdev/01_new_props.jpg`: the props downloaded in this pass, including the ones that were rejected.
- `docs/plans/cc0_lookdev/02_existing_props.jpg`: an inventory of the props already in `assets/incoming/polyhaven/models`.
- `docs/plans/cc0_lookdev/03_new_materials.jpg`: the materials downloaded in this pass (2 m tile, low sun).
- `docs/plans/cc0_lookdev/04_existing_materials.jpg`: an inventory of the materials already in `assets/incoming/polyhaven/textures`.
- Renderer: `res://assets/cc0/_lookdev/lookdev.gd`. Run it with `godot --path kingdom --windowed --resolution 640x480 -s res://assets/cc0/_lookdev/lookdev.gd -- --list=<txt of res:// paths> --out=<dir>`. It can resume, writes one PNG per item, and adds each item's size and triangle count to `dims.txt`.

**What the gate covers.** These verdicts are an **asset-level** check: is the asset in style, period-correct, free of broken textures, within the triangle and texture budget, and at a sane scale. They are **not** the full AAA gate. That still needs each asset seen in context, at gameplay distance, next to its neighbours, after the owning worker places it. The swatches render a little bright because the lookdev light is not the game's grade, so judge colour against the in-game grade.

Import settings: the glTF files use `meshes/generate_lods=true`, `ensure_tangents` and shadow meshes. JPGs use VRAM-compressed BPTC/S3TC with mipmaps, and normal maps are flagged with `compress/normal_map=1`. Props are 1K and materials are 2K. ARM maps pack the channels as R = AO, G = roughness, B = metallic.

## New props (`kingdom/assets/cc0/…`)
| res:// path | size / tris | use | slice placement | gate |
|---|---|---|---|---|
| `res://assets/cc0/props/painted_wooden_stool/painted_wooden_stool_1k.gltf` | 0.38×0.58×0.41 m, 676 | chipped white-painted stool | interior: by the hearth or table; tavern back room | PASS |
| `res://assets/cc0/props/planter_pot_clay/planter_pot_clay_1k.gltf` | 0.27×0.22×0.26 m, 3.1k | weathered terracotta pot | street: by doors and under windows, with flowers or herbs inside (ref 06/20 "plants by doors") | PASS |
| `res://assets/cc0/tools/cross_pein_hammer/cross_pein_hammer_1k.gltf` | 0.30 m, 2.1k | blacksmith hammer | side street workshop or smithy bench; interior tool wall | PASS |
| `res://assets/cc0/tools/picke_dirty_01/picke_dirty_01_1k.gltf` | 1.12 m, 6.2k | dirty pickaxe | countryside: leaning on the field wall; bandit camp spoil heap | PASS |
| `res://assets/cc0/nature/boulder_01/boulder_01_1k.gltf` | 1.28×1.01×1.84 m, 26.6k (decimated from 66k) + LODs | lichen boulder | countryside: roadside and wall ends, edge of the copse; scale 0.7–1.5 for variety | PASS (heavy for a prop; LODs required) |
| `res://assets/cc0/nature/dead_tree_trunk_02/dead_tree_trunk_02_1k.gltf` | 4.05 m long, 16k (decimated from 83k) | fallen dead trunk | copse floor; bandit camp seat log by the fire pit | PASS |
| `res://assets/cc0/nature/dry_branches_medium_01/dry_branches_medium_01_1k.gltf` | 1.3 m spread, 16.8k (3 meshes) | dry branches | copse floor clusters; firewood scatter at the camp; field-wall base | PASS (use as clusters, not an even scatter) |

### Rejected this pass (kept only in staging)
| id | reason |
|---|---|
| planter_box_01 | Black plastic liner shows inside: reads as modern. |
| wooden_cutting_board | Varnished butcher board with a juice groove: reads as a modern kitchen. |
| handsaw_wood | Modern D-handle Western panel saw. Off-period. |
| rock_07 | A 0.3 m glossy red "ironstone" with 14.8k tris. Looks polished and is off-palette. |
| rock_09 | A 7 cm pebble with 12.4k tris. Wasteful and useless at gameplay distance. |
| ThatchedRoof001A (ambientCG) | Tiny uniform grain that reads as brushed fabric, not straw. |
| plaster_stone_wall_01 | Near-white with blotches that read as footprints in snow. |
| painted_wooden_table | Not imported: the trestle table is on the Meshy list. |

## New materials (`res://assets/cc0/textures/<id>/<id>_{diff,nor_gl,arm}_2k.jpg`)
| id | use | slice placement | gate |
|---|---|---|---|
| cobblestone_floor_04 | irregular setts with grass in the joints | market square main paving | PASS |
| mossy_cobblestone | small setts with moss lines | shaded side street, near walls | PASS |
| cobblestone_large_01 | dusty setts with grass breakup | square edges, transition to the dirt road | PASS |
| cobblestone_05 | worn rounded setts | side street | PASS |
| cobblestone_floor_08 | old rounded cobbles, pale blue-grey | lanes, wet look under the night lamps | PASS with tint: too clean and white raw; darken albedo about 20% and warm it |
| cobblestone_floor_13 | cobbles sinking into mud | **blend layer** where cobbles break up into dirt (ref 20, "ground reads worn") | PASS |
| muddy_tracks | rutted clay with wheel tracks | countryside cart road (ref 01 ruts) | PASS with tint: the raw colour is red clay; shift it toward brown, or blend with mud_forest |
| mud_forest | dark wet soil with leaf bits | road shoulders, the copse, the camp | PASS |
| brown_mud_03 | wet, puddled mud | puddles and low spots on the road and at the camp | PASS |
| brown_mud_rocks_01 | stony dirt | road crown, camp ground | PASS |
| forest_floor | soil with autumn leaves | copse floor | PASS |
| forrest_ground_01 | grass and twigs on dirt | field edge, copse margins | PASS |
| leaves_forest_ground | dense leaf litter | under the tree groups in the copse | PASS |
| worn_mossy_plasterwall | dirty plaster with moss staining | timber-frame infill on the street (lower storeys) | PASS |
| rough_plaster_03 | coarse earthen plaster | interior walls; poorer houses | PASS |
| old_planks_02 | grey weathered boards | shutters, sheds, stall backs | PASS |
| weathered_brown_planks | brown boards | interior floor and walls, tavern | PASS |
| old_wood_floor | dark worn floorboards | tavern and house floor | PASS |
| rough_wood | grey split timber | posts, beams, fence rails, camp palisade | PASS |
| old_stone_wall | rubble masonry | house plinths, the field wall | PASS |
| rustic_stone_wall | coursed warm stone | street ground floors, landmark base | PASS |
| stacked_stone_wall | dry-stack flat stones | **field wall** on the countryside route | PASS |
| stone_wall_04 | pale ashlar with dark joints | town wall, gate, landmark that closes the street view | PASS |
| roof_slates_02 | grey stone slates | better street houses | PASS |
| reed_roof_03 | reed thatch with courses | thatched cottages at the town edge | PASS conditional: the visible course bands need UVs aligned to the roof slope or they tile visibly |

HDRIs for lookdev only, not for in-game skies: `res://assets/cc0/hdri/belfast_open_field/belfast_open_field_2k.hdr` (overcast) and `res://assets/cc0/hdri/barnaslingan_02/barnaslingan_02_2k.hdr` (partly cloudy).

## Existing `incoming/polyhaven` assets (inventory and gate; not re-downloaded)
Paths are `res://assets/incoming/polyhaven/models/<id>/<id>_1k.gltf`, apart from the table.

| id | tris | use / placement | gate |
|---|---|---|---|
| wooden_bucket_01, wooden_bucket_02 | 5.1k / 7.3k | by the well, doorways, interior | PASS |
| wicker_basket_01, wicker_basket_02 | 22.3k / 17.9k | market goods, interior | PASS look; **tris high for small props**: decimate to about 5k |
| ceramic_pot | 3.6k | interior shelf, hearth | PASS |
| wooden_lantern_01 | 8.3k | door lamps, hanging shop lamps (ref 09) | PASS |
| treasure_chest | **103k** | interior chest | PASS look, **FAIL budget**: decimate to about 10k before use |
| wooden_stool_02 | 11.1k | interior, tavern | PASS |
| wooden_stool_01 | 10.9k | interior | PASS (turned legs, slightly late-period) |
| folding_wooden_stool | 6.3k | — | FAIL: modern slatted camp stool |
| tree_stump_01, tree_stump_02 | 41k / 62k | copse, camp, field edge | PASS look; decimate to about 10k |
| rock_moss_set_01, rock_moss_set_02 | 63k / 58k (sets of 7–8 rocks) | road edges, wall base, copse | PASS; split into single rocks for placement |
| wine_barrel_01 | 10.8k | street and tavern barrels | PASS |
| wooden_barrels_01 | 33k (broken staves set) | bandit camp debris | PASS |
| wooden_crate_01 | 6.6k | street and interior | PASS |
| wooden_crate_02 | 5.2k | interior | PASS (faint stencilled letters; keep to the background) |
| wooden_axe | 3.3k | chopping block, camp | PASS |
| rusted_spade_01 | 11.4k | field, garden | PASS |
| wooden_hammer_01 | 3.6k | interior bench | borderline (modern steel claw hammer); background only |
| wooden_bowl_01 | 14.1k | table dressing | PASS look; tris high |
| carved_wooden_plate | 2.1k | table dressing | PASS |
| stone_fire_pit | 3.9k | bandit camp centrepiece | PASS |
| dead_tree_trunk | **102k** | copse | PASS look; **decimate** (dead_tree_trunk_02 above is the light alternative) |
| spinning_wheel_01 | 52k | house interior hero prop | PASS (hero only, LODs) |
| painted_wooden_bench | 0.6k | tavern settle | PASS |
| Barrel_02 | 2.7k | — | **FAIL: blue plastic drum. Never use.** |
| jug_01 | 5.8k | — | FAIL: white porcelain jug with floral print |
| hatchet | 5.3k | — | FAIL: modern rubber grip |
| sledgehammer_01 | 2.6k | — | FAIL: yellow fibreglass handle |
| wooden_broom | 14.3k | — | FAIL: synthetic push broom, taped handle |
| wooden_candlestick | **213k** | — | FAIL budget (decimate to about 3k if wanted) |
| root_cluster_01 | **225k** | — | FAIL budget |
| round_wooden_table_01 | 8.6k | — | FAIL: varnished Victorian pedestal table |
| WoodenTable_03 (`WoodenTable_03_1k.gltf`) | 2.3k | — | FAIL: chest of drawers with modern metal trim |

Existing materials (`res://assets/incoming/polyhaven/textures/<id>/`):
- PASS: brown_mud_02, castle_brick_07 (red brick, sparing use), castle_wall_slates, clay_roof_tiles, cobblestone_floor_01, damaged_plaster, dirt, forest_ground_04, forest_leaves_02, grass_path_2, grassy_cobblestone, leafy_grass, medieval_blocks_02, medieval_wood, mossy_stone_wall, rock_face, rocky_terrain_02, sparse_grass, thatch_roof_angled.
- Conditional: clay_plaster is flat and uniform, so layer it with dirt or AO. reed_roof_04 has course bands, the same as reed_roof_03.
- FAIL: brown_planks_05 is bleached near-white and reads as new decking. red_slate_roof_tiles_01 has lime-green moss and a white ridge band, which is off-palette.

## Gaps (not on Poly Haven or ambientCG as CC0 medieval assets)
Wheelbarrow or cart, sacks, hay bales and loose hay, wattle or post-and-rail fences, a firewood stack, and medieval pottery jugs. Meshy or Blender kits should cover these (the handcart with sacks is already on the Meshy list).
