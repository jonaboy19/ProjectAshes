# Meshy download batch 3 (owner-downloaded, 2026-10-03/04), optimized

130 raw files (119 GLB + 11 rigged "biped" ZIPs, about 4 GB) from the owner's Meshy downloads. Raw files are NOT in git: they live in `C:\Users\Jonna\Documents\ProjectAshes_art_staging\meshy_raw3\` (moved, not copied). Index of raw number -> file name: `raw_index.tsv`.
Optimized output: `kingdom/assets/incoming/meshy_dl3/<category>/<name>_lod0.glb` (+ `_lod1.glb` for buildings, castles, creatures and static characters). 97 GLBs, 60 MB in total, largest file 1.8 MB.
Placed and triaged in the Style G pass of 2026-10-05, see the section "Style G triage and placement" at the end.

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


## Style G triage and placement (2026-10-05, cloud)
Method: contact sheets of every LOD0 with the game lighting and the Style G role materials plus `FillStyle` treatment (`kingdom/tools_qa/meshy3/triage_sheet.gd`), the batch's own triage sheets and this README. Rule: prefer reject over a model that fights the storybook palette. Data: `FillStyle.TREAT` / `DL3_REJECT` / `DL3_UNPLACED` in `kingdom/scripts/world/fill_style.gd` (keys `dl3/<cat>/<name>`), tests in `kingdom/tests/test_meshy3.gd` and `test_fill_style.gd`.

| class | models |
|---|---|
| **keep** (fits as is, 10 models + 7 re-rigged characters) | buildings: cottage_slate_timber, house_gable_porch_a, house_gable_porch_b, house_tudor_corner, house_tudor_stone_base, tavern_dark_roof; camp: tent_shop_conical; carts: wagon_canvas_a, wagon_canvas_lanterns; castle: castle_small_towers; the 7 re-rigged characters (below) |
| **treat** (desaturate / matte via `FillStyle.TREAT`, 21) | buildings: cottage_blue_roof (0.55), cottage_orange_roof (0.6), cottage_thatch_timber, house_orange_thatch (0.5), house_straw_thatch, tavern_red_roof (0.6); camp: tent_shop_canopy; carts: wagon_shields_covered; market: stall_rug_wood; castle: fortress_grey_blue; creatures: horse_saddled_brown, elemental_earth_golem; furniture: bench_lantern_posts, table_bench_set, table_long_wood; magic: rack_elixirs; props: chest_iron_banded, firewood_stack_oven, keg_big, shield_round_wood, swords_scabbards_trio |
| **reject** (19, never placed, excluded from the export) | buildings: cottage_straw_roof_a (burning-orange interior), cottage_straw_roof_b (ruin with lava glow), tavern_blue_porch (sky-blue toy roof), tavern_drunken_dragon (12 m, diorama base, 14k tris); castle: armory_keep (teal toy roof), tower_round_orange_roof (orange cone toy tower); camp: tent_hide_conical (flat ruin-like 9 m heap); creatures: elemental_fire, elemental_water (VFX-like flame and ice); magic: eggs_elemental_four (candy eggs), runestones_elemental_four (0.1 m flat tablets), sigils_elemental_eight and emblem_four_elements (flat UI icons), circle_elemental_platform (flat colour disc), potion_green_vine_base (neon toy potion); characters_static: knight_plate_shield (flat heraldic toy); characters_rigged: knight_plate_grey (untextured), noblewoman_cape and soldier_shield_sword (rig fit failed, see below) |
| **kept, unplaced** (no fitting spot yet, excluded from the export until used, 10) | churches/cathedral_romanesque (17.9 m, no cathedral in the Region 1 plan), characters_static/ser_duncan_knight and hobo_hooded_beggar (static, need a plinth or a rig), loot/coin_gold and coin_silver (0.3 m), props/door_round_wood, helmet_sentinel (0.3 m), pier_plain, pier_rope_rails, pier_stairs_bench (no water in the slice) |

### Where things stand (31 models placed, 67 LOD0 models in all = 31 placed + 19 reject + 10 unplaced + 7 re-rigged)
Yards (`kingdom/data/region1/world/meshy3_sites.json`, generated by `kingdom/tools/region1/gen_meshy3_sites.py`, laid out by `region1_fill.gd`, `kind roadside`, snapped to the lowest footprint ground, yaw only, clear of roads, water, settlements and every earlier site; A/B flag `--meshy3off`):
| site | town | models |
|---|---|---|
| `m3_thornfield_lane` Millers' Lane | Thornfield | cottage_thatch_timber, house_gable_porch_a, cottage_slate_timber, picket fence, firewood_stack_oven, 2 kegs, lantern bench |
| `m3_thornfield_carters` Carters' Yard | Thornfield | 2 canvas wagons, rug stall, shop canopy tent, table with the elixir rack, table and benches, 2 horses, kegs, banded chest |
| `m3_thornfield_wayhouse` The Hanged Thorn Wayhouse | Thornfield | tavern_dark_roof, 2 table sets, lantern bench, 3 kegs, a horse, firewood |
| `m3_ashford_lane` | Ashford | house_tudor_stone_base, house_gable_porch_b, fence, lantern bench |
| `m3_redwater_dyers` | Redwater | cottage_blue_roof, cottage_orange_roof, rug stall (cloth), kegs (vats), table |
| `m3_highcliff_stable` | Highcliff ("Steel and horses") | 3 horses, shield wagon, weapon trio, 2 round shields, conical tent, kegs, table, fence |
| `m3_greywatch_spearhall` | Greywatch (plan: Spear Hall) | fortress_grey_blue keep, 2 weapon trios, 2 shields, 2 conical tents |
| `m3_blackwater_gate` | Blackwater (ferry garrison) | castle_small_towers gatehouse, shield wagon, canopy tent, kegs |
| `m3_marrowick_row` | Marrowick | house_tudor_corner, house_straw_thatch, firewood oven, fence |
| `m3_amberley_hives` | Amberley | house_orange_thatch, house_straw_thatch, keg, table, fence |
| `m3_longmeadow_fair` | Longmeadow | tavern_red_roof, 3 rug stalls, canopy and conical tents, canvas wagon, 2 table sets, keg |
Wilds ("extras" in `thornfield_wilds.json`, built by `Props.model` in `wilds_props.gd`): **Watch Post** (quartermaster rug stall, shield wagon, horse, kegs, firewood, weapon trio and shield by the rack, table and lantern bench at the fire), **Ash Hand camp** (looted canvas wagon, kegs, table set, a tethered horse), **Rift mouth** (earth-golem effigy beside the cleft). No keep or castle was placed where the plan has none; Highwatch Keep keeps its own kit. Contact sheet: `docs/art/meshy_dl3/placements_meshy3.png`.

### Rigged bipeds (UAL)
The 10 skins carry Meshy's 23-24 bone Mixamo-style skeleton (Hips, Spine, Spine01, Spine02, neck, Head, Left/RightArm...), **not** the UAL skeleton, so the game's clip libraries (`Assets._ual_for`, bone names pelvis, spine_01, upperarm_l ...) do not play on them as is (a BoneMap retarget would need an AnimationTree per character and breaks the merged-NPC path). Instead they are **re-rigged onto the 65-bone UAL skeleton** exactly like the armored humanoids (`kingdom/assets/incoming/ai3d/meshy/armored/README.md`): `tools/meshy/armored_rig/meshy3_rerig.py` bakes the rest-pose mesh out of the skin, then runs `armored_rig.py` (landmarks, bone-heat weights, UAL fit, LOD0 4-7k tris and LOD1 2.9k tris, 1024/512 px). Results in `kingdom/assets/incoming/meshy_dl3/characters_ual/` (reports in `docs/art/meshy_dl3/ual_rig/`). Verified in Godot through `Assets.mh_character`: 65 bones (merchant_cloaked: +1 `neutral_bone` for 22 stray vertices), Head rest y 1.57-1.58 like the villagers, Walk / Idle / Sword_Regular_A / Death01 / Sit_Floor_Idle play (`kingdom/tools_qa/meshy3/rig_sheet.gd` pose sheets, `tests/test_meshy3.gd`).
- **Pass (7):** guardian_hooded, knight_plate_a, merchant_cloaked, peasant_hooded, villager_green_vest, villager_hat, villager_white_shirt. Looks: `Meshy_Villager` (green vest, white shirt, hat, hooded peasant), `Meshy_Traveller` (guardian, merchant: the hooded stranger at the Thornfield barn), `Meshy_Knight` (knight_plate_a); also extra picks in `Rogue_Hooded` (all four villagers), `Barbarian` (hat, hooded peasant), `Hunter` (guardian), `Trader` (merchant), `Bandit` (guardian: the Ash Hand and road bandits), `Plate_Knight` (knight_plate_a). The Thornfield roster picks bodies per row, so its named residents get these through `Rogue_Hooded`/`Barbarian`.
- **Fail (2):** noblewoman_cape (the cape and a sword confuse the arm landmark fit: arms stay raised, cape spreads) and soldier_shield_sword (shield and sword mesh are stretched by the arm weights). They need hand-placed landmarks (`overrides` in the config: `arm_fit_range`, shoulder) or a Blender weight clean-up; their outputs were discarded. knight_plate_grey is untextured grey and needs painting first.
- Height note: the helmets and hats sit above the head bone; pass the report's `mh_character_height_param` (in `ual_rig/*_report.json`) when a look must hit an exact height. Callers use the nominal height for now (within about 5-10 cm).

### Export
`kingdom/export_presets.cfg` (both presets) excludes every model of the batch except the 31 placed ones and the `characters_ual` rerigs; rejects, unplaced models and the Mixamo-skeleton originals (`characters_rigged/`) stay out of the APK. `test_meshy3.test_rejects_and_unplaced_do_not_ship_placed_do` pins this (it also caught that `loot/coin_*` had not been excluded; fixed).
