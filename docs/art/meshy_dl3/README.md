# Meshy download batch 3 (owner-downloaded, 2026-10-03/04), optimized

130 raw files (119 GLB + 11 rigged "biped" ZIPs, about 4 GB) from the owner's Meshy downloads. Raw files are NOT in git: they live in `C:\Users\Jonna\Documents\ProjectAshes_art_staging\meshy_raw3\` (moved, not copied). Index of raw number -> file name: `raw_index.tsv`.
Optimized output: `kingdom/assets/incoming/meshy_dl3/<category>/<name>_lod0.glb` (+ `_lod1.glb` for buildings, castles, creatures and static characters). 97 GLBs, 60 MB in total, largest file 1.8 MB.
Not placed in any level yet.

## Licence and provenance
File names carry no Meshy model id, so the public API check from `docs/art/meshy_free_shortlist.md` could not be run. All 130 are recorded as **owner-downloaded, licence per owner's Meshy plan** (see `kingdom/assets/incoming/meshy_dl3/CREDITS.md`). If any came from the community library, check its `license` field before shipping.

## Pipeline
- Statics: `tools/meshy/optimize_free.py` through `tools/meshy/free_batch/run_dl3.py` + `spec_dl3.py` (voxel remesh + decimate + Cycles diffuse bake, metallic 0 / roughness 0.9, 512 or 1024 px JPEG, Y-up, origin bottom-centre, real-world scale). Budgets: props 1.5-3k tris, buildings 8-15k, creatures and characters 6.5-7k.
- Shredded results (first voxel pass tore thin roofs, tents, wagons, stalls) were redone: `dec` variant (no remesh) for the already low-poly sources 001, 083, 069, 028, 099, 101, and a finer `solid` voxel pass (`across` 320) for 041, 105, 106, 111, 112, 047. Proof: `before_after/ba_dl3_fixes.jpg` (raw | first pass | fixed).
- Rigged biped ZIPs: `tools/meshy/optimize_rigged.py` (decimates the skinned mesh, keeps weights, UVs, armature and the baked clip, texture to 1024 px). Only the Walking/Running skin GLB of each ZIP was processed; the other animation GLBs (attacks, dances, idles, up to 17 MB each) stay in staging.
- Contact sheets of the raw set: `contact_sheets/raw3_1.jpg` .. `raw3_7.jpg`. Before/after (raw left, LOD0 right): `before_after/ba_dl3_1.jpg` .. `ba_dl3_6.jpg`.

## Triage totals (130 files)
| category | keep (optimized) | maybe | reject |
|---|---:|---:|---:|
| buildings / city / castle / church | 21 | 9 (village blocks, row houses, arena, city diorama, ruins on island base) | 4 (pagoda, pantheon, tycoon room, floating island) + 1 mini village |
| characters, rigged | 10 | 0 | 2 dup ZIPs |
| characters, static (T-pose or posed, unrigged) | 3 | 30 (guards, warriors, maidens, assassins, trader, ranger, soldiers) | 5 (3 empty garments, 1 anime swordsman, 1 dup pair) |
| horse and elemental creatures | 4 | 4 (aqua, storm, sage, sorcerer) | 0 |
| props, furniture, carts, camp, market, loot | 22 | 2 (ship, campfire scene: raw GLB fails to import in Blender) | 1 dup bench |
| magic items (eggs, runes, sigils, circle, elixirs, emblem, potion) | 7 | 1 (nexus platform) | 3 (white untextured eggs, untextured champions, black harmony disc) + 1 anime orb hero |
| total | 67 | 46 | 17 |

Most of the set is realistic PBR, brighter and more detailed than Style G; they read as props/NPC placeholders and want the usual warm grade. Duplicates: 045/046 (duo), 048/049 (garb), 089/090 (bench), 125/126 (age biped ZIPs identical), 105/106 and 107/108 and 82/83 are colour or layout variants (kept).

## Keep table and proposed placement
| group | models (tris LOD0) | placement |
|---|---|---|
| buildings | house_tudor_stone_base, house_tudor_corner, cottage_orange_roof, cottage_thatch_timber, cottage_slate_timber, cottage_blue_roof, tavern_blue_porch, tavern_red_roof, tavern_dark_roof, tavern_drunken_dragon, house_gable_porch_a/b, house_orange_thatch, house_straw_thatch, cottage_straw_roof_a/b (6-14k) | town fillers / houses for the towns work (3D town agent), wide 6-12 m footprints; tavern_* as inns |
| castle, church | tower_round_orange_roof, fortress_grey_blue, armory_keep, castle_small_towers, cathedral_romanesque | Region 1 keeps, landmarks |
| characters_rigged | guardian_hooded, knight_plate_a, knight_plate_grey (untextured grey, needs paint), peasant_hooded, villager_green_vest, villager_white_shirt, villager_hat, merchant_cloaked, noblewoman_cape, soldier_shield_sword (4-7k) | NPC villagers, guards, merchant |
| characters_static | ser_duncan_knight, knight_plate_shield, hobo_hooded_beggar | story NPC statues or hero NPC (rig later) |
| creatures | horse_saddled_brown (static), elemental_earth_golem, elemental_fire, elemental_water (7k, on round bases) | horse: see below; elementals as boss/shrine figures |
| magic | eggs_elemental_four, circle_elemental_platform, rack_elixirs, runestones_elemental_four, sigils_elemental_eight, emblem_four_elements, potion_green_vine_base | element shrine, alchemist, UI icons |
| props / furniture / loot | door_round_wood, keg_big, table_long_wood, table_bench_set, bench_lantern_posts, firewood_stack_oven, chest_iron_banded, helmet_sentinel, shield_round_wood, swords_scabbards_trio, pier_* (3), coin_gold, coin_silver | interiors, docks, loot |
| market, carts, camp | stall_rug_wood, wagon_canvas_a, wagon_canvas_lanterns, wagon_shields_covered, tent_shop_conical, tent_shop_canopy, tent_hide_conical | market square, caravans, camps |

## Rigs, retargeting, horse
- Rigged characters carry the Meshy biped skeleton: 21-24 Mixamo-style bones (Hips, Spine, Spine01, Spine02, neck, Head, Left/RightShoulder/Arm/ForeArm/Hand, Left/RightUpLeg/Leg/Foot/ToeBase). Names match the Godot humanoid BoneMap auto-profile, so they can be retargeted to the UAL animation set with a BoneMap (no finger bones; UAL hand bones are dropped). Not verified in Godot playback yet. Each file includes one baked clip (Running or Walking).
- Horse: `creatures/horse_saddled_brown` is a **static mesh with no skeleton**, so it cannot be used by the local-wip/horses rig work as is; it can serve as a mesh/texture reference or be rigged (Meshy rig, or Blender skinning to the horses skeleton). Not checked against the horses branch.
- Build kit: nothing was added to `kingdom/data/build_kit/pieces.json`. These are one-piece buildings, not 2 m grid walls/roofs/foundations, and a town agent is working in that area. If a piece is wanted, `door_round_wood` (2.6 m) and `stall_rug_wood` fit as free (0.5 m) props; add them append-only with `meshy_` ids.

## Known limits
Baked diffuse only (no emissive for lanterns/fire elemental); some pieces keep a baked ground base (houses, taverns); elemental figures stand on round bases; coin and sigil pieces are very small and flat.
