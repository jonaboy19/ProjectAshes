# Asset audit: unreferenced models and animation libraries

Handoff item 7 (`docs/LOCAL_SESSION_HANDOFF.md`, "2026-09-30 (cloud -> local)"). Audited 2026-09-30 against `origin/claude/focused-curie-m09hbd`: every `kingdom/assets/**/*.glb|*.gltf`, 5196 files, 1194.2 MB. The full per-file list of the unused ones is `docs/qa/asset_audit_unreferenced.csv` (path, bytes, status, shipped or not).

## How it was checked

Every `.gd`, `.tscn`, `.tres`, `.json`, `.cfg`, `.gdshader` and `project.godot` outside `addons/` was searched for each model's `res://` path; its `uid://` (from the `.import`); a string literal that is a path suffix of the file (how `Q + "..."` constants resolve); a `%s` / `%d` format literal that matches the path (for example `"res://assets/generated/%s.glb" % asset`); and the bare base name (LOD suffix removed) as a string token, including the part after `free:` / `r1:` / `gen:` and before `@` in the data tables (`free:market/stall_apples@3.2`). `tests/`, `tools/`, `tools_qa/` and `kingdom/tools/` were searched separately so a model named only by an asset sheet or build config is not counted as used.

| Status | Meaning | Confidence |
|---|---|---|
| used | full path or uid in runtime code or data | high |
| dynamic | only the base name matches a runtime string (table key, path-building code) | medium: a common word such as `barrel` can match by accident, so a few of these are really unused |
| TOOLS-ONLY | named only in tests, tools or QA sheets | high that nothing in the shipped game loads it |
| UNREF | no match anywhere | high |

"Unused by the game" below means UNREF plus TOOLS-ONLY. Files already matched by the `exclude_filter` in `kingdom/export_presets.cfg` are not in the APK/IPA, so they cost repo size only.

## Totals

| Status | Files | MB (source GLB/glTF) |
|---|--:|--:|
| used | 1294 | 331.3 |
| dynamic | 795 | 307.3 |
| TOOLS-ONLY | 275 | 142.5 |
| UNREF | 2832 | 413.1 |
| **all models** | 5196 | 1194.2 |

**Unreferenced (UNREF): 2832 files, 413.1 MB. Unused by the game (UNREF + TOOLS-ONLY): 3107 files, 555.6 MB, 47% of all model bytes.**

**APK impact.** 2976 of those files, 541.4 MB, are not matched by the current export `exclude_filter`, so they ship in the APK and IPA (`export_filter="all_resources"`). That is an upper bound in source bytes: Godot re-imports each GLB to a compressed `.scn` with VRAM-compressed textures, so the shipped size is smaller (estimate 40-80% of source, **not measured**; confirm with one test export before and after applying the list in section G). Another 14.1 MB of unused models is already excluded by `export_presets.cfg`.

Not covered: textures, audio and FBX/OBJ sources (several packs also carry large `Textures/` folders; `docs/OPEN_SOURCE_AUDIT.md` is the pack-level licence and size audit this complements).

## A. `meshy_free` packs (`assets/incoming/meshy_free/`)

331 LOD0/single models: 1 used by full path, 118 placed by name through `free:` entries, **5 UNREF and 207 TOOLS-ONLY** (47 of those under `maybe/`, parked by design in `docs/art/meshy_free_triage.md`). Optimized, catalogued and placed nowhere. Sizes include LOD1.

| Path (`assets/incoming/meshy_free/`) | Models | MB | Status | Proposed use | Owner |
|---|--:|--:|---|---|---|
| `banners/` | 6 | 1.7 | TOOLS-ONLY | Highwatch Keep parapet, Greywatch Spear Hall yard, Scar Mouth Arena (region1 `sites.json` parts, `free:banners/<name>@h`); the stands as Eastern Gate queue markers. Models: banner_spear_top, banner_spiked_base, banner_stand_chains, banner_stand_hanging_chains, banner_stand_iron_frame, banner_stand_spiked_base. | cloud |
| `buildings/` | 8 | 12.6 | TOOLS-ONLY | Filler houses for towns in `settlements.json` that still reuse the generated `village_house_*` set: house_* for Brackenmoor, Westfen, Dunhallow, Harrowgate; blacksmith_* for Highcliff Armoury and Ironmarch; butcher_house for the Wolfsend market street (house lists in `region_dressing.gd`). Models: blacksmith_thatch_stone, blacksmith_timber_thatch, butcher_house, house_cottage_chimney, house_dark_roof, house_ivy_damaged, house_two_story_shingle, house_two_story_tall_timber. | cloud |
| `castle/` | 9 | 15.0 | TOOLS-ONLY | castle_sandstone_a/b and keep_small_on_plinth: Crownstead estate and Kingsreach outer ward; gate_*: Eastern Gate queue site and Dunhallow; tower_* and wall_battlement_block: Greywatch wall ring. tower_round duplicates the Highwatch kit (section F). Models: castle_sandstone_a, castle_sandstone_b, gate_dark_towers, gate_twin_towers_blue, gate_wall_ivy, keep_small_on_plinth, tower_octagon_wall, tower_pink_flag, wall_battlement_block. | cloud |
| `churches/` | 9 | 13.5 | TOOLS-ONLY | Dawn Chapel site (chapel_stone_small, church_white_red_spire); church_gothic_red and church_dark_small for Harrowgate and Emberfall; chapel_island_small and church_stone_island on the Emberglass Mere islets by the Drowned Bell. Models: chapel_island_small, chapel_stone_small, church_dark_small, church_gothic_red, church_old_brick, church_spire_small, church_spire_tan, church_stone_island, church_white_red_spire. | cloud |
| `creatures/` | 11 | 5.0 | TOOLS-ONLY | goblin_*: goblin-warren dens and camp_default in `region1_creatures.gd`; wolf_brown, wolf_ghost: Wolfsend dens and the Rift ghost wolf; spirit_fox_blue: Hidden Vale ambient critter; treant_forest: Stagborn Glade; dragon_*: static Frostcrown and Emberfall statues (not rigged). Models: dragon_fire_small, dragon_green_armored, goblin_a, goblin_armored, goblin_b, goblin_knife, goblin_ragged, spirit_fox_blue, treant_forest, wolf_brown, wolf_ghost. | cloud |
| `farm/` | 15 | 5.8 | TOOLS-ONLY, 5 UNREF | hay_bale_*, sheds, chicken_coop_fenced: Crownstead Mill Hill, Oakvale (Pennick Farm), Eastmere Dairy. The 5 `rigged/` cows and chickens are the UNREF files: wire into `ambient_life.gd` critters at Oakvale and Eastmere, or delete. Models: chicken_coop_fenced, chicken_hen, chicken_rooster, hay_bale_lowpoly, hay_bale_rect_a, hay_bale_round, hay_bale_yellow_large, chicken_hen_rigged, chicken_rooster_rigged, cow_brown_a_rigged, cow_brown_b_rigged, cow_spotted_rigged, shed_plank_low, shed_thatch_small, shed_wood_shingle. | cloud |
| `fences/` | 9 | 2.5 | TOOLS-ONLY | Field and paddock lines at Oakvale, Eastmere Dairy, Millbrook; wall_stone_railing at the Stonehollow Quarry edge. Models: fence_board_gate, fence_broken_rail, fence_gate_rail, fence_picket_low, fence_picket_tall, fence_plank_panel, fence_rail_grass_a, fence_rail_grass_b, wall_stone_railing. | cloud |
| `flora/` | 3 | 0.8 | TOOLS-ONLY | Hidden Vale herb patch and Ashford gardens (`vale_look.gd` dressing list). Models: bouquet_wild, bush_raspberry, mushroom_glow_brown. | cloud |
| `furniture/` | 17 | 5.9 | TOOLS-ONLY | throne_*, lectern_desk: Crownstead Steward's Hall and the Kingsreach hall (`lord_hall.gd`); chair_*, table_*, tavern_set: inn interior and the `interior_room.gd` furnishing pool. Models: chair_armchair_wood, chair_gothic_tall, chair_high_back, chair_ornate_red, chair_simple_a, chair_simple_b, lectern_desk, table_barrel_top, table_tavern_thick, table_tavern_trestle, tavern_set_barrels_b, throne_carved_wood, throne_dark_red_studded, throne_gold_red, throne_gothic_gold, throne_leather_cushion, throne_red_gothic. | cloud |
| `interior/` | 7 | 3.1 | TOOLS-ONLY | bookshelf_*, bed_canopy_red, tapestry_hunt, wall_shield_*: Steward's Hall, Highwatch Keep hall, Academy (`interior_room.gd`). Models: bed_canopy_red, bookshelf_glass_cabinet, bookshelf_tall_rustic, bookshelf_wide_low, tapestry_hunt, wall_shield_heater, wall_shield_iron_studded. | cloud |
| `lighting/` | 16 | 4.6 | TOOLS-ONLY | street_lamp_*, street_lantern_*: Kingsreach gate market and Crownstead; lantern_hanging_*: Emberglass Ferry landing for Kindling Night; sconce_*, torch_*: dungeon and cave interiors (`dungeon_kit.gd`, `region_caves_view.gd`). Models: lamp_post_purple_bracket, lamp_post_timber_cross, lantern_hanging_blue, lantern_hanging_green, lantern_post_purple, lantern_wall_iron, lantern_wall_scroll, sconce_torch_bracket, sconce_torch_ornate, sconce_wall_bowl_a, sconce_wall_bowl_b, street_lamp_twin_gold, street_lantern_gothic, street_lantern_whimsical, torch_dungeon_cage, torch_hand_silver. | cloud |
| `loot/` | 2 | 0.3 | TOOLS-ONLY | Coin piles in `dungeon_items.gd` boss-chest rewards. Models: coin_gold_big, coin_silver_big. | cloud |
| `magic/` | 11 | 4.5 | TOOLS-ONLY | crystal_*_pedestal: elder-stone and ward-stone sites (Stone Gap, Hollin Falls); portal_*: tower entrances (`tower_site.gd`) and Hidden Vale; orb_purple_roots: Rift sites. Models: crystal_blue_pedestal, crystal_cyan_pedestal, crystal_egg_purple, crystal_green_pedestal_a, crystal_green_pedestal_b, crystal_green_pedestal_c, orb_purple_roots, portal_blue_arch, portal_elf_mound, portal_ice_arch, portal_vine_arch. | cloud |
| `market/` | 4 | 2.7 | TOOLS-ONLY | Kingsreach gate market stalls (stall_meat_shingle, stall_potatoes, stall_open_roof, shed_striped_awning). Models: shed_striped_awning, stall_meat_shingle, stall_open_roof, stall_potatoes. | cloud |
| `nature/` | 3 | 1.8 | TOOLS-ONLY | tree_cartoon_green_a/b for Ashford meadows, tree_pine for Grimfen Pass slopes (region nature lists). Models: tree_cartoon_green_a, tree_cartoon_green_b, tree_pine. | cloud |
| `props/` | 13 | 3.2 | TOOLS-ONLY | chest_*: dungeon and cave loot (`dungeon_items.gd`); well_*: Ashford, Oakvale, Westfen village centres. Models: axe_long_handle, chest_blue_iron, chest_copper_lock, chest_gold, chest_metal_wood, chest_orange_metal, chest_orange_riveted, chest_pink, chest_red_black, chest_silver_lock, well_covered_planks, well_stone_roofed, well_stone_shingle. | cloud |
| `ruins/` | 4 | 2.4 | TOOLS-ONLY | Hollin's Reach Ruins and Stagborn Glade landmark parts. Models: arch_dark_pedestal, ruin_arch_side, ruin_arch_wall, ruin_pergola. | cloud |
| `signs/` | 3 | 0.9 | TOOLS-ONLY | Shop signs at the Kingsreach gate market through `region1_extras.gd` sign bodies. Models: sign_blank_bracket, sign_blank_rope, sign_shop_lion. | cloud |
| `water/` | 15 | 7.7 | TOOLS-ONLY | bridge_*: the `BRIDGE_DECK` table in `region_dressing.gd` for Ashrun crossings and the Old Span; boat_* and dock_circular_wood: Emberglass Ferry and Saltwick harbour. Models: boat_longship_sail, boat_rowing, bridge_arch_pale, bridge_garden_vines, bridge_mossy_small, bridge_old_stone_blue, bridge_serenity_steps, bridge_stone_arched_rail, bridge_stone_dark_long, bridge_stone_passage, bridge_stone_rustic_a, bridge_stone_rustic_b, bridge_stone_rustic_c, bridge_stone_wood_deck, dock_circular_wood. | cloud |
| `maybe/banners/` | 1 | 0.3 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: banner_drow_purple. | local |
| `maybe/buildings/` | 9 | 16.6 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: hut_hunter_base, hut_mossy_ruined_a, hut_mossy_ruined_b, village_block_a, village_block_b.... | local |
| `maybe/camp/` | 1 | 0.3 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: tent_white_thin. | local |
| `maybe/castle/` | 1 | 0.6 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: arch_door_on_tile. | local |
| `maybe/creatures/` | 15 | 6.5 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: brute_horned_a, brute_horned_b, brute_skull_shoulders, dragon_crystal_lying, dragon_grey_small.... | local |
| `maybe/fences/` | 1 | 0.3 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: fence_picket_thin_long. | local |
| `maybe/furniture/` | 1 | 0.2 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: table_dining_walnut. | local |
| `maybe/interior/` | 4 | 1.8 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: armour_knight_sword_static, bookshelf_nook_corner, wall_shield_tall_dark, weapon_rack_round_shield. | local |
| `maybe/lighting/` | 1 | 0.3 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: street_lamp_victorian. | local |
| `maybe/magic/` | 7 | 3.1 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: portal_heart_glow, portal_victorian_scifi, relic_crystal_ornament, relic_purple_mirror, relic_red_brooch_flat.... | local |
| `maybe/nature/` | 3 | 2.3 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: tree_old_grass_disc, tree_old_orange_disc, tree_old_sparse. | local |
| `maybe/props/` | 2 | 0.5 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: mace_iron, wheel_barrels_pile. | local |
| `maybe/water/` | 1 | 0.7 | TOOLS-ONLY | Parked. Exclude `meshy_free/maybe/*` from export; revisit only for: bridge_arch_long_rocks. | local |

Owner cloud = add the `free:<cat>/<name>@<height>` entries to the region data and dressing lists; local = check scale and placement in the GPU build and fix part y-offsets.

## B. Animation libraries

The runtime loads clips through `Assets.UAL_FILES` (UAL1, UAL2, the three `UAL_Extra_*`, `souls_cat`, `cmu_mocap`, `combat/UAL_Combat.glb`: all used), `LifeLibrary` and `ash_ghost_clips.gd` (weapons, combat_reactions, life_sim). The libraries below are outputs of `kingdom/tools/anim/` (Codex) or raw sources and are not loaded by the game.

| Path (`assets/incoming/`) | MB | Status | Proposed use | Owner |
|---|--:|---|---|---|
| `animations_free/acrobatics/UAL_Free_Acrobatics.glb` | 0.9 | TOOLS-ONLY | Add to `UAL_FILES` for climb/vault clips (Stone Gap climb, tower floors). | Codex |
| `animations_free/casting/UAL_Free_Casting.glb` | 0.3 | TOOLS-ONLY | Spell clips for `technique_caster.gd` (VFX already in `vfx_spells.gd`); add to `UAL_FILES`. | Codex |
| `animations_free/casting/UAL_Free_CastingElements.glb` | 0.6 | UNREF | UNREF output of `tools/anim/casting/build_casting_elements.sh`: wire with the casting set or delete. | Codex |
| `animations_free/casting/UAL_Free_CastingKaykit.glb` | 0.2 | TOOLS-ONLY | Overlaps UAL_Free_Casting: merge, then delete one. | Codex |
| `animations_free/combos/UAL_Free_Combos.glb` | 0.3 | TOOLS-ONLY | Superseded by `combat/UAL_Combat.glb`; keep as build source, exclude from export. | Codex |
| `animations_free/defense/UAL_Free_Defense.glb` | 0.3 | TOOLS-ONLY | Block/parry, superseded by UAL_Combat; source only. | Codex |
| `animations_free/kicks/UAL_Free_Kicks.glb` | 0.4 | TOOLS-ONLY | Unarmed technique set (martial path in `power_paths.gd`). | Codex |
| `animations_free/martial_arts_unarmed/UAL_Free_MartialArtsUnarmed.glb` | 0.7 | TOOLS-ONLY | Same unarmed technique set as kicks. | Codex |
| `animations_free/reactions/UAL_Free_Reactions.glb` | 0.6 | TOOLS-ONLY | Hit reactions for villagers and bandits (`character_animator.gd`). | Codex |
| `animations_free2/kaykit_movement_ext/UAL_Kay_movement_ext.glb` | 0.5 | TOOLS-ONLY | Movement extras for followers and retinue (`followers.gd`). | Codex |
| `animations_free2/kaykit_ranged/UAL_Kay_ranged.glb` | 0.4 | TOOLS-ONLY | Archer and crossbow clips for army `soldier.gd` and the Greywatch garrison. | Codex |
| `animations_free2/kaykit_undead/UAL_Kay_undead.glb` | 0.2 | TOOLS-ONLY | Skeleton and ghoul clips for crypt dungeons (`dungeon_creature.gd`). | Codex |
| `animations_free2/loco_transitions/UAL_Loco_Transitions.glb` | 0.6 | TOOLS-ONLY | Start/stop/turn transitions for the foot-slide work. | Codex |
| `animations_free2/traversal_authored/UAL_Authored_Traversal.glb` | 0.6 | UNREF | UNREF authored climb/vault: wire for the Stone Gap and Hollin Falls climbs, or fold into UAL_Combat. | Codex |
| `animations_video/Test_Walk/UAL_Video_Test_Walk.glb` | 0.4 | UNREF | Video-to-animation experiment. Delete. | local |
| `ai3d/animations/hit_knockback_floor_contact.glb` | 0.6 | UNREF | Experiment clip: fold into UAL_Combat or delete. | Codex |
| `characters/_library/UAL_Extra_100STYLE.glb` | 1.5 | UNREF | 100STYLE locomotion styles: personality walks in `life_actor.gd`, or exclude. | Codex |
| `characters/mesh2motion/horse-animations.glb` | 1.0 | UNREF | Horse clips for `mount_controller.gd`; keep with the horse rig. | Codex |
| `characters/mesh2motion/human-base-animations.glb` | 5.4 | UNREF | Superseded by UAL1/UAL2. Exclude. | local |
| `characters/mesh2motion/model-human.glb` | 0.3 | UNREF | Mesh2Motion export source. Exclude. | local |
| `characters/mesh2motion/rig-horse.glb` | 0.0 | UNREF | Rig reference. Exclude. | local |
| `characters/mesh2motion/rig-human.glb` | 0.0 | UNREF | Rig reference. Exclude. | local |
| `quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard_RM.glb` | 7.3 | UNREF | Root-motion variant of UAL1; the code strips root motion itself. Exclude. | local |
| `quaternius/universal-animation-library-2/Unreal-Godot/UAL2_Standard_RM.glb` | 7.7 | UNREF | Root-motion variant of UAL2. Exclude. | local |
| `quaternius/universal-animation-library-2/Female Mannequin/Unreal-Godot/Mannequin_F.glb` | 1.4 | UNREF | Already in the export filter; reference only. | local |
| `kaykit/character-animations/Mannequin Character/characters/Mannequin_Large.glb` | 0.5 | UNREF | Mannequin source. Exclude. | local |
| `kaykit/character-animations/Mannequin Character/characters/Mannequin_Medium.glb` | 0.4 | TOOLS-ONLY | Mannequin source. Exclude. | local |
| `kaykit/character-animations/Animations/gltf/Rig_Medium/*` (8), `Rig_Large/*` (6) | 11.0 | UNREF (Large), TOOLS-ONLY (Medium) | The clips are merged into the `UAL_Kay_*` libraries above; these per-rig files are the source. Exclude from export. | Codex |

Animation libraries unused by the game: 41 files, 44.3 MB. The two `_RM` UAL files plus `human-base-animations.glb` alone are 20.4 MB of clear export savings.

## C. Region 1 kits (`incoming/region1/`: stones, highwatch, silverford, rift, landmarks)

53 models: 33 used by full path, 20 placed by `r1:` name, **0 unused**. The kits are fully wired, so there is nothing to place. Related: `ai3d/meshy/landmark_rift_*` and `landmark_watchfort_*` (5.9 MB together) match only by name (`dynamic`); confirm the Watchfort (4.8 MB LOD0, over the hero budget for an unlit prop) is really placed and compare it with `region1/highwatch/tower_round` and `watchtower`, which duplicate it in part (section F). Owner: local (LOD check).

## D. Creatures and characters

| Path (`assets/incoming/`) | Files | MB | Proposed use | Owner |
|---|--:|--:|---|---|
| `quaternius/ultimate-animated-character/` | 43 | 81.9 | Legacy NPC and monster characters. `Goblin_Male` etc. stay (`goblin_uac` fallback in `creature_models.gd`); the other 42 are old villager designs replaced by the modular UAL characters. Exclude or delete. | local |
| `quaternius/ultimate-modular-men/` | 7 | 21.7 | Replaced by `modular-character-outfits-fantasy` plus Universal Base Characters. Exclude. | local |
| `quaternius/ultimate-modular-women/` | 3 | 9.1 | As above. | local |
| `kaykit/character-pack-skeletons/` | 17 | 18.4 | Skeleton warriors, mages, rogues (17 x ~1 MB): the natural crypt-dungeon enemies (`dungeon_creature.gd`, crypt theme) and the Grimfen barrow; clips from `UAL_Kay_undead`. Place, or exclude. | cloud |
| `quaternius/ultimate-animated-animals/` | 3 | 9.1 | Horse_White: a second horse colour at the Crownstead stables (`ambient_life.gd`); Husky: Grimfen Pass; ShibaInu: delete. | cloud |
| `quaternius/ultimate-monsters/` | 2 | 1.8 | MushroomKing: fungal boss for the Hidden Vale caves; Ghost_Skull: Rift wraith variant. | cloud |
| `kenney/mini-characters/` | 26 | 3.3 | Off-style. Exclude. | local |
| `kenney/cube-pets/` | 24 | 3.2 | Off-style. Exclude. | local |
| `styloo/the-company/` | 22 | 8.7 | Named adventurer NPCs: use only if the guild hall needs them; otherwise exclude. | local |
| `creatus/knight-pack-1/` | 62 | 9.4 | 62 props and models: barrel, table, campfire for interiors, or exclude. | local |
| `armor/` (quaternius, polypizza, opengameart, kaykit) | 149 | 21.4 | Source copies of `items/armor/*.glb`, which is what the game loads (exact duplicates, section F). Quaternius and KayKit are already excluded from export; add `polypizza` and `opengameart`. | local |

## E. Props, buildings and the remaining packs

| Path | Files | MB | Proposed use | Owner |
|---|--:|--:|---|---|
| `generated/scan/` | 22 | 28.4 | Decimated Poly Haven scans nothing loads (dandelion, fern, nettle, stumps, root cluster, fire pit, 13 mossy rocks). Place through the `scan/<name>` key (`assets.gd` ~line 927) in Stagborn Glade, Hollin's Reach and the Hidden Vale, or delete. They are 2-3 MB each, so decimate before placing. | local (decimate), cloud (place) |
| `generated/nature/` | 7 | 2.0 | Older tree set (birch_a, pine_a/b, dead_tree, bushes, sapling), superseded by `generated/region/nature/*`. Delete. | local |
| `generated/village_inn|smithy|stall(_2)` | 6 | 4.2 | Older village kit; `village_services.gd` builds inn and smithy from the Meshy versions. Delete, or keep as an Ashford fallback. | local |
| `generated/fence_section.glb` | 1 | 0.0 | Superseded by meshy_free fences. Delete. | local |
| `opengameart/models/` | 81 | 45.1 | Docks, prop packs, units. WoodenDockSet fits the Emberglass Ferry landing (note it is stored twice); the prop packs duplicate Quaternius and Creatus props. Pick the docks, exclude the rest. | cloud (docks), local |
| `opengameart/cc-by/` | 24 | 1.5 | simple-market-stall and catapult duplicate Kenney equivalents. Exclude. | local |
| `quaternius/ultimate-fantasy-rts/` | 122 | 36.1 | RTS units and buildings; off-style, the war map uses 2D tokens. Exclude or delete. | local |
| `quaternius/pirate-kit/` | 72 | 21.1 | Only useful for Saltwick harbour or the Ravenscar coast; otherwise exclude. | cloud (Saltwick), local |
| `polypizza/ (cc-by, cc0)` | 76 | 19.8 | CC-BY models with credit obligations and no use, plus CC0. Exclude or delete. | local |
| `kaykit/dungeon-remastered/` | 202 | 8.6 | The dungeon generator uses procedural `dungeon_kit.gd` rooms; these pieces could dress crypt dungeons, otherwise exclude. | cloud |
| `kenney/ (all other kits)` | 925 | 23.0 | About 1,000 tiny low-poly props; the flat-shaded style does not match. Exclude (graveyard-kit only if the Hollin's Reach graves need it). | local |
| `kaykit/ (restaurant, resource, furniture, forest bits)` | 369 | 1.1 | Inn props at most. Exclude. | local |
| `quaternius/medieval-village-megakit/` | 176 | 0.6 | Chairs, carts, fences: Brackenmoor / Westfen filler, or exclude. | cloud |
| `quaternius/fantasy-props-megakit/` | 46 | 0.2 | Already the source of `market_goods`. Keep as source. | local |
| `chilly-durango/retro-medieval-building-kit/` | 55 | 0.5 | Off-style. Exclude. | local |
| `cc0gameassets/swordtember2022/` | 30 | 0.9 | Weapon art candidates for `items/weapons`. Exclude until used. | local |
| `polyhaven/models/` | 62 | 0.4 | Already excluded from export; the 164 MB of sources could leave the working tree. | local |

## F. Duplicates and near-duplicates

### Exact duplicates (identical git blob)

141 groups, 142 redundant copies, **7.5 MB**. Nearly all are `items/armor/*.glb` (the copy the game loads) next to its source under `incoming/armor/**`. Delete the source copies (repo size) or exclude them (APK; only `polypizza` and `opengameart` are not excluded yet).

| Keep | Redundant copy | MB |
|---|---|--:|
| `incoming/opengameart/models/modular-wooden-docks/Glb/WoodenDockSet.glb` | `incoming/opengameart/models/modular-wooden-docks/LoafbrrAssets/WoodenDockSet/Glb/WoodenDockSet.glb` | 1.30 |
| `items/armor/shield_tower.glb` | `incoming/armor/opengameart/cc-by/tower-shield/tower_shield.glb` | 0.81 |
| `items/armor/shield_kite.glb` | `incoming/armor/opengameart/cc0/great-kite-shield/kite_shield.glb` | 0.56 |
| `items/armor/crown_jewelled.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/crown_jewelled.glb` | 0.21 |
| `items/armor/cape_fur.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/cape_fur_mantle.glb` | 0.21 |
| `items/armor/quiver.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/quiver_back.glb` | 0.19 |
| `items/armor/helm_anglo4.glb` | `incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm4.glb` | 0.19 |
| `items/armor/helm_anglo5.glb` | `incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm5.glb` | 0.19 |
| `items/armor/helm_anglo6.glb` | `incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm6.glb` | 0.19 |
| `items/armor/hat_straw.glb` | `incoming/armor/opengameart/cc0/hats-clothing-props/straw_hat.glb` | 0.19 |
| `items/armor/helm_anglo3.glb` | `incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm3.glb` | 0.19 |
| `items/armor/helm_anglo2.glb` | `incoming/armor/opengameart/cc-by/anglo-saxon-helmets/anglo_saxon_helm2.glb` | 0.16 |
| `items/armor/backpack.glb` | `incoming/armor/quaternius/items/Backpack.glb` | 0.13 |
| `items/armor/greave_straps.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/greave_leather_straps.glb` | 0.13 |
| `items/armor/greave_leather.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/greave_leather_b.glb` | 0.13 |
| `items/armor/bracer_leather.glb` | `incoming/armor/polypizza/cc-by/knights-character-kit/bracer_leather.glb` | 0.12 |

The other 133 groups have the same shape. `incoming/opengameart/models/modular-wooden-docks` also stores `WoodenDockSet.glb` twice (1.3 MB).

### Near-duplicates (same model name, different file)

| Name | Copies | Proposal |
|---|--:|---|
| `tower_round` | 4 | `meshy_free/castle/tower_round_*` vs `region1/highwatch/tower_round_*`. The Highwatch one is the tuned copy; drop the other or place only one. |
| `watchtower` | 3 | `region1/highwatch/watchtower_*` is the placed one; the 3dassets-dev-ai copy is already excluded. |
| `windmill` | 7 | Five windmills (`generated/region/farm`, `meshy_free/buildings`, 3dassets, Kenney, region kit). `generated/region/farm/windmill` is the placed one; delete or exclude the others. |
| `oak_a` | 4 | `generated/nature/oak_a` (old) vs `generated/region/nature/oak_a` (placed). Delete the old one; same for oak_b. |
| `oak_b` | 4 | As oak_a. |
| `guard` | 4 | `generated/characters/guard` vs `ai3d/meshy/armored/guard`: confirm which the guard spawn loads and delete the other. |
| `knight` | 3 | `kaykit/characters/Knight.glb` (3.5 MB) vs `ai3d/meshy/armored/knight*`: the KayKit one is a fallback only. |
| `rogue` | 2 | `kaykit/characters/Rogue.glb` (3.5 MB) vs `quaternius/rpg-characters` Rogue: same role. |
| `donkey` | 2 | `animals/quaternius/donkey.glb` (0.8 MB, placed) vs `ultimate-animated-animals/Donkey.gltf` (3.4 MB, source). |
| `blacksmith` | 5 | `ai3d/meshy/blacksmith_lod0..3` (placed) vs a tiny RTS block (excluded). |
| `woodpile` | 3 | `generated/woodpile.glb` and `generated/props/woodpile.glb`: keep `props/`. |
| `notice_board` | 2 | `generated/notice_board.glb` and `generated/props/notice_board.glb`: keep one. |
| `signpost` | 3 | `generated/signpost.glb` and `generated/props/signpost.glb`: keep one. |
| `crown_poly_by_google_0seq0m` | 2 | Same crown in two folders: delete one. |

168 same-name groups in all. The rest are mostly generic props (`bench`, `barrel`, `crate`, `stool`, `table`) that exist as different models in Kenney, KayKit, Quaternius, OpenGameArt and Creatus: choose one house style per prop and exclude the rest. The `modular-outfits-fantasy` parts also exist twice (`armor/quaternius/modular-outfits-fantasy/*.glb`, 0.3-0.7 MB each, and the `.gltf` set in `quaternius/modular-character-outfits-fantasy`, which is what the game loads).

## G. Recommended actions and savings

| Action | Source MB no longer shipped | Owner |
|---|--:|---|
| Safe now: exclude `res://assets/incoming/meshy_free/maybe/*` (all 58 TOOLS-ONLY) | 33.5 | cloud |
| Safe now: exclude `kaykit/character-animations/*` (no file used), `characters/mesh2motion/*` UNREF files, the two `_RM` UAL files | 33.8 | cloud |
| Safe now: exclude `cc0gameassets/*` (30 UNREF, 0 dynamic hits) | 0.9 | cloud |
| **Subtotal, safe now** | **68.2** | |
| After checking the "dynamic" hits: legacy character and RTS packs (`ultimate-animated-character`, `ultimate-modular-men/women`, `ultimate-fantasy-rts`, `kenney/mini-characters`, `kenney/cube-pets`); only the UNREF files go, keep the few dynamic ones (for example `Goblin_Male`) | 155.2 | local |
| After checking: off-style packs with no planned use (`kenney`, `polypizza`, `styloo`, `creatus`, `chilly-durango`, `pirate-kit`, KayKit bits and dungeon-remastered, `opengameart`); UNREF files only | 148.3 | local |
| Delete superseded `generated/nature`, `generated/scan` (or decimate first), old `generated/village_*` | 34.5 | local |
| **Total** | **406.1** (about 162-325 MB in the APK at 40-80% of source; unmeasured) | |

What stays unused after that is the `meshy_free` placements (section A, about 93.9 MB) and the animation libraries worth wiring (section B). Placing them is content work for the cloud session (`sites.json`, `settlements.json`, the `region_dressing.gd` parts lists) and does not need to block the exclude list.

Safe `exclude_filter` additions for both the Android and iOS presets (68.2 MB of source):

```
res://assets/incoming/meshy_free/maybe/*, res://assets/incoming/kaykit/character-animations/*, res://assets/incoming/cc0gameassets/*, res://assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard_RM.glb, res://assets/incoming/quaternius/universal-animation-library-2/Unreal-Godot/UAL2_Standard_RM.glb, res://assets/incoming/characters/mesh2motion/human-base-animations.glb, res://assets/incoming/characters/mesh2motion/model-human.glb, res://assets/incoming/characters/mesh2motion/rig-human.glb, res://assets/incoming/characters/mesh2motion/rig-horse.glb
```

Do not exclude whole `kenney/`, `polypizza/`, `pirate-kit/` or `ultimate-*` directories: each holds a few files the game does load by name (see the `dynamic` rows). Move the UNREF files out to a `_sources/` folder (already excluded by `*/_sources/*`) or list them per file from the CSV. `horse-animations.glb` stays (mount clips). Then run the gdUnit suite and `tools/qa/anim_qa/run.sh --no-strips`. Nothing was deleted or excluded by this audit.

## Caveats

- Matching is text-based. A model loaded through a path built from data the scan cannot see (names read from a resource at runtime) would show as UNREF. The 5 UNREF `meshy_free/farm/rigged` files and the `generated/scan` files were spot-checked by hand.
- "dynamic" files (795, 307.3 MB) are counted as used. Some are false positives (a common word matched), so the true unused total is somewhat higher.
- Sizes are source GLB/glTF bytes from git, not imported sizes.
- The scan script is not committed; the method above reproduces it.
