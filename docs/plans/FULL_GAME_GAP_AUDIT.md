# Rising Ashes: full-game AAA gap audit (2026-10-26)

Measured against `GAME_VISION_OWNER_2026-10-26.md` and `READY_V1.md`.
Ratings: **Missing** = no code. **Stub** = sim or data only, no player entry point. **Works** = the player can do it end to end. **AAA** = shipping quality.
Method: code reading and grep (two read-only sweeps for C and D), headless gdUnit, and the windowed QA runs from this session (`docs/qa/mechanics/`). Paths are relative to `kingdom/scripts/` unless noted.
RAM note: free memory stayed at 0.2–0.9 GB (three other Godot instances), so the **windowed New-Game 10-minute playthrough is still pending**; see A.0.

## Summary table
| Area | Works | Stub | Missing | Verdict |
|---|---|---|---|---|
| A. New game / first hour | 12 | 1 | 1 | most of the flow is there; the playthrough screenshot pass is pending; no "demo" path |
| B. Survival loop | 11 | 1 | 0 | E2E after this session's fixes; balance tuned to the 12-minute day |
| C. Kingdom path | 6 | 8 | 3 | **the biggest hole**: camp to village growth, lordship, raids, laws, crown |
| D. Professions & ranks | 11 | 4 | 3 | 6 trades ranked; apprenticeships, adult Academy, element-by-place missing |
| E. Assets | — | — | ~14 items | most mechanics have assets; the list below is for the new loops |

## A. New game, demo, first hour
| Beat | Rating | Evidence | Gap |
|---|---|---|---|
| A.0 Windowed 10-min playthrough from New Game | **pending** | bot stages exist: `tools_qa/playtest_bot/playtest_bot.gd` (`boot,intro,menus,st_birth,st_a1`) | run when ≥ 4 GB RAM is free; screenshot each beat into `docs/qa/first_hour/` |
| Boot → splash → studio intro | Works | `ui/frontend/boot.gd`, `splash.gd`, `boot/studio_intro.gd`, `scenes/boot.tscn` (main scene) | — |
| Main menu, slots, continue | Works | `ui/frontend/main_menu.gd`, `slot_screen.gd`, `load_watcher.gd` | — |
| Settings (graphics, audio, PC rebinding) | Works | `ui/frontend/settings_screen.gd`, `settings_store.gd`; C11 landed (`tests/test_v1_pc_controls.gd`) | — |
| Character creator | Works | `ui/character_creation.gd` (813 lines), `ui/frontend/new_game.gd` | hero sheet defects tracked in S3.0 (a93/afc) |
| Opening cinematic (birth) | Works | `cinematic/birth_cutscene.gd`, `cutscene_player.gd`; `main.gd _play_birth` | BotW-style "leave the cave, see the vista" reveal is not the opening; `cinematic/discovery_vista.gd` exists and could be reused at the first adult step outdoors |
| Ashford birth village start | Works | `life.gd _begin_life` (real parents in a real house) | — |
| Tutorialisation / PC prompts | Works | `region1/tutorial_director.gd` (context prompts), `tutorial_prompt_view.gd`, `ui/input_glyphs.gd` | — |
| First quests | Works | `data/region1/quests/r1_main.json`, `region1/r1_story_director.gd` | Act 3 founding step (C3) missing, see C |
| Discovery banners / vistas | Works | `ui/discovery_banner.gd`, `discovery_vista.gd` | — |
| Loading screens | Works | `ui/frontend/loading_screen.gd`, `ui/world_loading.gd` | — |
| Death screen + respawn | Works (fixed) | `ui/frontend/death_screen.gd`, `main.gd _respawn_at_home`; **fixed this session: survival needs no longer respawn at zero (death loop)** | — |
| Credits | Works | `ui/credits_screen.gd` (CREDITS.md + addon licences) | — |
| Pause menu | Works | `ui/frontend/pause_menu.gd` | — |
| Vertical-slice "demo" path | Stub | `main.gd _run_demo` (`--demo`) exists for capture | no curated 20-minute demo route (start → first fight → camp → vista) |

## B. Survival correctness
| Step | Rating | Evidence | Notes / fixes this session |
|---|---|---|---|
| Gathering (trees, rocks, plants, ore) | Works | `world/gather_run.gd`, `forage_nodes.gd`, `ore_vein.gd`, `realm/construction_data.gd` "Chop tree" | — |
| Hunting → skin → meat/pelt | Works | `interaction/kinds/corpse_loot.gd:66-79`, `tests/test_v1_hunting.gd` (C10 landed) | — |
| Fishing | Works | `world/fishing_spot.gd` | — |
| Inventory + weight | Works | GLoot; `needs.load_ratio` encumbrance (M2) | — |
| Crafting | Works | `sim/crafting.gd`, `ui/crafting_screen.gd` | — |
| Cooking | Works | recipes on `hearth`/`campfire` stations (`data/recipes.json`); **new: player campfire build piece**, finished construction campfires are now lit | — |
| Hunger / rest | Works | `sim/needs.gd` | — |
| Thirst | Works | M1; **tuned to 2.5/h (≈20 real min to parched)**; wells (Drink / Fill flask), drinks quench, wading drinks | — |
| Warmth | Works | M1; **rate tuned to 12/h**; shelter, fire (`fire_hazard` + `heat_source`), beds warm you | — |
| Sleep | Works (fixed) | `Life.sleep` → `needs.sleep`; **fixed: thirst now drains at half rate while asleep, and sleep warms you** | — |
| Injury / healing | Works | `sim/injuries.gd`, death injuries via `Life.apply_death_penalty` | no field dressing / bandage item loop (Stub) |
| Death / respawn | Works (fixed) | `needs.revive_floor()` | — |
| Balance | Works | 12 real min = 1 day; hunger empties in ~18 min, thirst ~20 min, cold night chills in ~1.5 min without fire/shelter | verify in the windowed bot with a full day |

## C. Kingdom path (camp → village → lordship → land → kingdom)
| Mechanic | Rating | Evidence | Gap |
|---|---|---|---|
| Found a camp | Works (basic) | `build/build_mode.gd:345-350` (confirm with no grid → `kit.claim`), via Build menu "Free build" | no "Found a camp" button or site card (`founding.evaluate_site` at `realm/founding.gd:219` is never called); C3 not landed |
| Land claim | Works (implicit) | `realm/build_kit.gd:43` → `land_claim.gd` | lease/purchase/grant options (`founding.gd:69 TITLE_COST`) not offered |
| Build kit (snapping, ghost, costs) | Works | `build/build_mode.gd`, `tests/test_build_kit.gd` | AAA polish pass pending |
| NPC builders | Works (partial) | `realm/construction.gd:757-784` assign_player/assign_follower | only construction jobs |
| Settlers/workers on stations and jobs | Missing | — | no assignment UI or job loop for your own settlement |
| Growth Camp → Hamlet → Village | Stub | `founding.stage_name` (`founding.gd:185`) | **no daily growth tick, no ledger (C4 not landed)** |
| Lordship grant | Stub | only `realm/enterprise_people.gd:506` (purchase) calls `lordship.grant` | no grant on reaching Village (C5); `nobility.grant_land_for_service` (`sim/nobility.gd:484`) has no caller |
| Lord hall + council + taxes | Works only for an existing lordship | `core/main.gd:188-192`, `world/lord_hall.gd:51`, `ui/lord_council.gd` | hall never spawns at the player's own settlement |
| Laws | Stub | `realm/governance.gd:1075 set_law_by_player` (no caller) | no law UI |
| Raids on your settlement + defence | Missing | no `realm/player_raids.gd` (C9) | no threat, so nothing is at stake |
| Rivals / diplomacy | Stub | `realm/armies.gd:157,256` | no player diplomacy |
| Rebellion | Stub | `realm/armies_data.gd:20` | — |
| Succession / dynasty | Stub | `realm/dynasties.gd:410`, `tests/test_lw_dynasties.gd` | no heir choice or death handover |
| War + military ranks | Works | `actors/captain.gd:44`, `ui/soldier_ui.gd`, `ui/war/war_map.gd` | — |
| Earning land by service | Stub | `nobility.grant_land_for_service` uncalled | rank never converts to land |
| Buy/rent property, houses | Works | `world/village_services.gd:485,532,534`, `tests/test_property.gd` | `realm/homes.gd` buy/rent unreachable (two systems) |
| Shops / workshops / businesses | Works | `ui/strategic/enterprise_screen.gd:555,691` | — |
| Kingdom / crown | Missing | text only (`realm/campaign.gd:3796`) | v1 "L" scope |

## D. Professions, ranks, Academy, recruiting
| Feature | Rating | Evidence | Gap |
|---|---|---|---|
| Rank ladders + career screen | Works | `ui/career_screen.gd:138-149`, `village_services.gd:635` | one main career tracked; promotions have no ceremony |
| Trade minigames (scribe, farmer, soldier, merchant, blacksmith, wardwright) | Works | `ui/career_tasks.gd:21-22,460,946` | — |
| Farmer / fisher / miner / woodcutter / hunter actions | Works | `farm_work_spot.gd:63`, `fishing_spot.gd:67`, `ore_vein.gd:32`, `construction_data.gd:61`, `corpse_loot.gd` | **fisher, miner, woodcutter, hunter have no rank ladder** (actions don't promote) |
| Healer / herbalist | Stub | `village_services.gd:805-807` radiant jobs | no trade or ranks |
| Cook | Missing | — | cooking skill exists (crafting) but there's no cook trade at the inn |
| Mage | Works (via Academy/awakening) | `realm/education.gd:51-73`, `sim/awakening.gd` | no mage job ladder as an adult |
| Thief / assassin | Stub | `sim/theft.gd`, `pickpocket.gd`, `village_services.gd:97` | no guild, contracts or ranks |
| Soldier + adventurer guild | Works | `ui/soldier_ui.gd`, guild board `village_services.gd:421,438` | — |
| Academy entry + path choice | Works (child only) | scout test `world/realm_encounters.gd:170-181,755`, graduation `:820-827` | **no adult enrolment / exam / path choice** |
| Path teachers | Stub | `realm/education.gd:1035 learn_from_path_teacher` (no caller) | — |
| Apprenticeship to an NPC master | Stub | `realm/society.gd:1413 apply_apprenticeship` (no caller) | **no dialogue option** |
| Player takes apprentices | Missing | — | — |
| Element growth by location | Missing | `realm/cultivation.gd:12` (density only), `realm/power_paths.gd:15` (awakening only) | **time-in-place does not grow affinity** |
| Recruiting | Works | `realm/recruitment.gd`, `ui/recruitment_ui.gd`, `village_services.gd:1456` | not per profession ("hire a smith for my forge") |
| Companions: combat, Down, revive | Works | C6 landed, `tests/test_v1_companions.gd` (13) | — |
| Companion stories, loyalty | Works | C7 landed, `tests/test_v1_companion_content.gd` (12), `ui/affairs/followers_will_panel.gd:38` | — |

## E. Asset needs for the mechanics (do NOT spend Meshy credits without the owner's OK)
Already on disk and usable (no generation needed): campfire (`assets/generated/region/ruins/campfire.glb`, now used by the build piece), campfire with spit, bedroll, bell/command/pavilion tents, goblin tent (`assets/incoming/3dassets-dev-ai/...`), cooking pots / cauldron, wooden and metal buckets, pickaxe, peg rack, banners and banner poles, iron crown (opengameart CC0 `.blend`, needs a GLB export), all 81 other build-kit pieces have meshes.

| Need (mechanic) | Source | Meshy prompt (text-to-3D, low-poly stylised, ≤ 5k tris, PBR) | Est. credits |
|---|---|---|---|
| Water flask / waterskin (wells, thirst) – held + icon | Meshy | "medieval leather waterskin with cork stopper and shoulder strap, stylised hand-painted, game prop, 30 cm" | 20 (preview 5 + refine 15) |
| Well bucket on rope (drink anim prop) | CC0 on disk (`Bucket_Wooden_1.gltf`) | — | 0 |
| Tanning / hide-stretching rack (hunting → leather station) | Meshy | "medieval wooden hide tanning frame with stretched deer hide, stylised, game prop, 2 m" | 20 |
| Drying / smoking rack (construction "drying_rack" uses a ruins asset) | CC0 on disk | — | 0 |
| Settlement ledger board / town notice board (C4 ledger UI in world) | CC0 on disk (notice board in towns) | — | 0 |
| Lord hall banner set in the player's colours | on disk (banner poles) + shader tint | — | 0 |
| Academy gate / lecture hall (adult enrolment) | Meshy | "medieval stone academy entrance with arched gate, two towers, blue slate roofs, stylised game building, 20 m" | 30 |
| Apprentice tools: anvil tongs, mortar & pestle, quill desk | Meshy ×3 | "blacksmith tongs and hammer on a small wooden stand, stylised prop" / "stone mortar and pestle with herbs, stylised prop" / "slanted scribe desk with quill and inkpot, stylised prop" | 60 |
| Healer's cot + herb shelf (healer trade) | Meshy | "medieval infirmary cot with wool blanket and a herb shelf with jars, stylised game prop set" | 20 |
| Thieves' guild hideout marker (lantern + trapdoor) | CC0 (Kenney / KayKit dungeon pieces on disk) | — | 0 |
| Raid war-horn + signal fire (C9 warning) | Meshy | "medieval curved ox-horn war horn with leather strap, stylised prop" | 20 |
| Crown + regalia (kingdom tier) | CC0 on disk (iron crown `.blend` → GLB via Blender) | — | 0 |
| Footprint / mud decal textures | procedural (`surface_feedback.gd`) | — | 0 |
| Creature gait replacements (sheep/pig/horse/fox/dog) | CC0 Quaternius animals (staged) | see AAA_FINISH_PLAN A2 | 0 |
| Total Meshy if all approved | | | **≈ 190 credits** (about one month's allowance) |

## Prioritised build order (player impact first)
1. **C4 settlement growth tick + ledger** (camp → hamlet → village with food, housing, contentment). Unblocks C5, C9 and the whole kingdom path. *Mine (realm files, no owner conflict).*
2. **C5 lordship on reaching Village** + lord hall at the player's settlement + council/taxes there.
3. **C3 "Found a camp" button + site card** (`founding.evaluate_site`), Act 3 step.
4. **C9 raids on the player settlement** (14-day grace, defenders = followers).
5. **Apprenticeship dialogue** → `society.apply_apprenticeship`, daily progress into career rank; rank ladders for hunter/fisher/miner/woodcutter so the actions promote.
6. **Element growth by location** (time per biome/element feeds affinity).
7. **Adult Academy enrolment + path teachers** (`education.learn_from_path_teacher`).
8. **Settler job assignment** to stations (farm, smithy, kitchen) in your settlement.
9. **Laws UI** (`governance.set_law_by_player`), **earning land by service** (`grant_land_for_service`), succession heir choice.
10. Player apprentices, thieves' guild ranks, cook/healer trades, demo route, then the crown.

## Built this session for this audit
- B fixes: respawn needs floor, sleep thirst/warmth, rates tuned (commit "B: survival fixes").
- Campfire: build piece uses the real model; construction campfires light up and warm (commit e4a598b1).
