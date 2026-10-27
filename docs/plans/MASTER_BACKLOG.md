# Rising Ashes — Master Backlog (blueprint reconciled with the code)

Planner pass, 2026-10-27, on `aaa/finish`. Source of requirements: `BLUEPRINT_OWNER_2026-10-27.md` (owner + ChatGPT, written without knowledge of our code). This file is **the single backlog every worker (local and cloud) executes from**. Status was checked by reading the code, not the docs. Line numbers are approximate anchors as of this commit.

**Performance target (owner, overrides the blueprint):** a regular PC, possibly **integrated graphics only**. Every WP lists its cost on three tiers: **iGPU-low / mid / high**.

Status key: **HAVE** = works end-to-end with tests · **PARTIAL** = core exists, part of the requirement missing or not wired to the player · **STUB** = data or skeleton only · **MISSING** = nothing found.

---

## 0. Headline

The blueprint mostly describes things we already have **as simulation** (≈100 realm modules, 68 sim modules, ~250 test files). Our real gaps are not breadth, they are:

1. **The player body**: climbing ladders/ledges works, but carrying, turn-in-place, sit/sleep for the player, fall injuries and the full §3 chain have never been tested as one sequence.
2. **Combat depth** beyond the hit resolver: directional lanes exist, but grappling, locational damage, bleeding/fractures, surrender/capture and weapon-specific movesets are thin.
3. **Making the sim visible and connected**: grain → caravan → garrison → morale (§0) exists in pieces (`caravans.gd`, `economy.gd`, `armies.gd`, `war_sim.gd`), but no single end-to-end chain test exists, and the player can't see most of it.
4. **Dungeons**: one procedural generator with 4 tiers (levels 1–60 range) and 7 themes, no persistent floor data, no inner worlds, no underground settlements.
5. **Streaming**: no threaded region loading (only audio uses `load_threaded_request`), so region transitions can stall.
6. **Integration tests**: no §3 movement acceptance run, no §17 stress scenario, no §21 story bot.

Rule 5 of the blueprint ("polish complete loops before adding territory") is the rule for this backlog: **the Vertical Slice (§3 below) comes first, everything else feeds it.**

---

## 1. Blueprint → code, section by section

### §0 / §2 Core principle and six pillars
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| One persistent world simulation | PARTIAL | `autoload/world_sim.gd` (people as data, `advance_hours`, `serialize`), `realm/realm_hub.gd` ORDER of ~45 realm modules, `world/world_state.gd` (object states + scheduler), `systems/world_event_log.gd` | Three parallel "worlds" (WorldSim people, realm `minds.gd` characters, `npc_world.gd` live slots) linked by `realm/registry.gd` aliases; no single tick owner doc; no end-to-end chain test |
| grain → merchants → fortress → soldiers eat; bandits hit caravan → shortage → morale | PARTIAL | `sim/caravans.gd` (risk by tier, guards, loss), `sim/economy.gd`, `realm/armies.gd` (hunger/supply, `carry_cap`), `army/morale.gd` | Caravan loss does not feed fortress stock → army morale → enemy decision. Needs a wired chain + test (WP-07) |
| Player can live ordinary or rise | HAVE | `sim/careers.gd`, `realm/work.gd`, `sim/lordship.gd`, `sim/nobility.gd`, `realm/founding.gd`, `sim/trade_ranks.gd` | Reachability polish only |

### §3 Movement & physical interaction (CRITICAL)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Walk/run accel/decel/ground adaptation | HAVE | `actors/player.gd`, `actors/ground_realism.gd`, `world/surface_query.gd` + `test_surface_query` | Slope speed tuning only |
| Sprint (stamina, equipment penalty) | HAVE | `sim/needs.gd` `stamina_cap`/`speed`/`load_label`, `menu_data.carry_weight` | Penalty values not tuned per armour weight class |
| Crouch (visibility, sound, posture) | HAVE | `player.gd:1079` crouch/stealth, `noise_radius()` :1095, `population/perception.gd` | — |
| Jump (takeoff/landing/momentum) | HAVE | `player.gd:1938 _land_jump` | — |
| Climb: ladders | HAVE | `interaction/kinds/ladder.gd`, `actors/traversal.gd` | Hand/foot contact IK on rungs not verified |
| Climb: ledges/structures | PARTIAL | `traversal.gd` MANTLE_LOW/HIGH/LEDGE, `data/movement/traversal.json`, `test_traversal` | No ledge shimmy, no rope, no free climb on structures |
| Vault (walls, windows, fences, debris) | PARTIAL | `traversal.gd` VAULT | Windows and debris not tagged as vaultable in kits |
| Swim (surface, dive, underwater stamina, currents) | PARTIAL | `player.gd:1049 _swim_vertical`, `:1060 _swim_stamina`, `test_water*` | No currents; dive animation set minimal |
| Fall injuries, landing, recovery | PARTIAL | `_land_jump(impact_speed)` | No injury from height into `sim/injuries.gd`, no hard-landing recovery clip |
| Horse riding | HAVE | `actors/mount_controller.gd`, `horses/*` (rider_ik, rider_sync, rein_follow) | Obstacle jumping on horse unverified |
| Carrying crates/bodies/sacks/injured NPCs | MISSING (player) | only NPC micro props (`population/micro_actor.gd`) | Player carry state, carry anims, drop/throw, carry injured follower |
| Interaction: sit, sleep, doors, containers, machinery | PARTIAL | `living_world/smart_objects.gd` (NPC sit, gold transitions), `interiors/bed_prop.gd`, `world/door_model.gd`, `world/home_chest.gd` | Player sitting on SmartObjects not wired; machinery (winch/lever) only in dungeon gates |
| Combat movement (sidestep, dodge, circle, backpedal) | HAVE | `player.gd:2024 dodge`, Souls_Roll (Equip W2), lock-on strafes | — |
| Animation: turn-in-place | MISSING | no `turn_in_place` anywhere | Needed for "no broken transitions" |
| Upper/lower layering, foot IK, hit reacts | HAVE | `actors/procedural_rig.gd` (jolt, holster pass), `living_world/contact_ik.gd`, `data/anim/golden_set.json` | — |
| **Acceptance test** (village→vault→ladder→house→sit→draw→fight→pick up→mount) | MISSING | none | WP-01 |

### §4 Combat (CRITICAL)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Light/heavy, combos | HAVE | `combat/combat_action.gd` (windup/active/recovery, cancel windows), `combat/combat_moves.gd`, `test_combat_actions` | — |
| Directional (horizontal/vertical/thrust) | PARTIAL | `combat_action.gd:23 lane` (Lane), `hit_resolver.gd LANE_MISS_BLOCK` | Player can't *choose* direction (lane is per move); no directional input mode |
| Block, parry, perfect counter | HAVE | `hit_resolver.gd` PERFECT_WINDOW 0.07, PARRY_WINDOW 0.18, BLOCK_CHIP | — |
| Dodge with limited i-frames | HAVE | `player.gd dodge` | — |
| Feints | PARTIAL | NPC only (`combat/npc_fighter.gd`) | Player feint input |
| Weapon clashes | HAVE | `hit_resolver` CLASHED, CLASH_WINDOW | — |
| Grappling (push, clinch, takedown) | PARTIAL | `player.gd:2276 _kick`, `combat/takedown.gd` (stealth) | Shove/clinch in open combat, kick into hazards |
| Guard break, poise, stagger | HAVE | `hit_resolver` GUARD_BROKEN, BROKEN_PARRY_RATIO, `knockdown_state.gd` | — |
| Locational damage + armour | MISSING | no hit-zone code in `combat_stats.gd` | Head/torso/arms/legs from bone hit, armour per slot |
| Injuries in combat (bleed, fracture) | PARTIAL | `sim/injuries.gd` TYPES (healer-treated, `tick_day`) | Not produced by combat hits; no bleed-over-time |
| Death / incapacitation / capture / surrender | PARTIAL | `test_death_reset`, follower Down/revive, monster yield (taming), `sim/arrest.gd` | Human enemy surrender + capture prisoners |
| Environmental combat | MISSING | — | Kick off ledge, into fire, elevation bonus |
| Weapon-specific movesets | PARTIAL | `combat/weapon_rules.gd`, `test_weapons` | Spear reach / axe commit / dagger exist as stats, few unique clips; bow posture partial |
| Enemy AI: tactical archetypes | PARTIAL | `npc_fighter.gd`, `army/formation.gd`, `realm/tactical_ai.gd`, `actors/creature_attack_tokens.gd` | Bandit panic/flee, veteran "punish predictability" (pattern memory) missing |
| Large creatures: telegraphs, weak points | PARTIAL | `combat/telegraph.gd`, `actors/soulbeast*.gd`, troll/wyvern in ecology | Weak points missing |
| Bot reaches its target | PARTIAL | AAA_PROGRESS Equip W2: bot steers straight into geometry | Bot nav-around (WP-01 dependency) |

### §5 NPCs (MOST IMPORTANT)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Identity, traits, social life | HAVE | `realm/registry.gd` (TRAITS, MEMORY_MAX 12, HISTORY_MAX 200), `realm/persona.gd`, `realm/psyche.gd`, `sim/npc_social_graph.gd`, `sim/relationships.gd` | — |
| Needs (eat, sleep, drink) | HAVE | `world_sim.gd person_needs`, `population/utility_brain.gd`, `sim/npc_need_rules.gd`, `test_utility_brain` | — |
| Skills, economy (money, property, job, income) | HAVE | `realm/minds.gd` PROFS, `sim/ownership.gd`, `sim/property.gd`, `realm/enterprise*.gd`, `realm/businesses.gd` | — |
| Loyalties, ambitions, beliefs | HAVE | `minds.gd` GOALS (wed, land, business, org_join, org_found, move, enlist…), `realm/faith.gd`, `realm/organizations.gd` | — |
| Memory, knowledge only from witness/rumour | PARTIAL | `population/witness.gd`, `realm/rumours.gd` (MEM_MAX 4, travel SPEED), `test_ni_memory_mood`, `test_witness` | NPC decisions do not consistently query "known facts" instead of global state; audit needed |
| Daily routine as a plan | HAVE | `population/schedule.gd`, `daily_rhythm.gd`, `world/street_routines.gd`, `test_town_schedule` | — |
| Layered AI needs→goal→plan→nav→memory | HAVE | `utility_core.gd`, `minds.gd`, `population/npc_world.gd` (16 live slots, DECIDE_PER_FRAME 3), `test_npc_decision_trace` | — |
| Deterministic core, no LLM | HAVE | seeded rngs throughout, `test_ni_divergence` | — |
| NPCs act without the player (jobs, move, marry, children, property, businesses, guilds, crime, death) | HAVE | `minds.gd`, `realm/dynasties.gd`, `realm/migration.gd`, `realm/emergence.gd`, `sim/theft.gd`, `test_lw_*` soak tests | Visibility to player (news/chronicle) is the gap, not the sim |
| Not everyone succeeds | HAVE | business failure in `enterprise_core.gd`, deaths in `world_sim.kill_person` | — |

### §6 Recruitment & companions
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Followers with contracts, pay | HAVE | `realm/followers.gd`, `realm/recruitment.gd`, `ui/recruitment_ui.gd`, `actors/follower_manager.gd` | — |
| Roles (combat, scout, hunter, quartermaster, builder, merchant, admin, commander, explorer) | PARTIAL | `follower_will.gd` ROLES (personal, military, economic, settlement, political, social), `sim/scouts.gd` | Independent dungeon expeditions missing; quartermaster role not mechanical |
| Delegation for rulers, accountability | PARTIAL | `realm/stewardship.gd`, `ui/lord_council.gd` | Steward reports/embezzlement not surfaced |
| Refuse illegal acts, demand pay, loyalty, resign, betray | HAVE | `follower_will.gd` ACTIONS (refuse_moral, consider_leaving, leak_to_enemy, organise_resistance), REQUESTS | — |

### §7 Survival & crafting
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Hunger, thirst, sleep, warmth | HAVE | `sim/needs.gd` (rates, `warmth_target(env)` wet/cold/shelter/fire), `test_needs_survival` | Food quality → nourishment; water contamination missing |
| Injuries (bandage, infection) | PARTIAL | `sim/injuries.gd` | No self-bandage, no infection chance |
| Disease, outbreaks, sanitation | STUB | only event flavour in `population/micro_events.gd`, `town_mood.gd` | Settlement disease model (WP-19) |
| Equipment wear/repair | PARTIAL | `sim/equipment.gd`, `crafting.gd` quality | Durability loss in combat + repair at smith not end-to-end |
| Encumbrance, carts, pack animals | PARTIAL | weight/capacity in `menu_data.gd`, `needs.load_label` | Carts/pack horse storage missing |
| Shelter/camping, fire (fuel, cook, spread) | PARTIAL | `world/campfire.gd`, `sim/homestead.gd`, fire danger in `npc_world.gd` | Fire spread to buildings not simulated |
| Production chains ore→smelt→forge | PARTIAL | `crafting.gd` stations/recipes, `world/ore_vein.gd`, `realm/work_jobs.gd` smelt | Workshop condition + fuel stock; delegated production to employees |
| Food spoilage | HAVE | `test_food_spoilage` | — |

### §8 Construction
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Land ownership, claims, trespass | HAVE | `realm/land.gd`, `land_claim.gd`, `land_law.gd`, `population/trespass.gd` | — |
| Placement preview, snapping, terrain checks | HAVE | `build/build_mode.gd`, `build/build_renderer.gd`, `data/build_kit/pieces.json`, `test_build_kit` | Foundation levelling/stability missing |
| Interiors, utilities, industry, agriculture, defence | PARTIAL | `realm/construction.gd` (1762 lines, holdings/tiers), `realm/farming*.gd`, `realm/towers.gd` | Wells/drainage/sanitation as functional; traps |
| Maintenance/deterioration | MISSING | — | Building condition decays, repair jobs |
| Manual / blueprint / NPC-directed | PARTIAL | manual (build_kit), NPC-directed (`construction.gd` workers) | Blueprint placement of a whole house preset |
| Progression homestead→city→power, can decline | PARTIAL | `founding.gd` tiers, `settlements.gd`, `civilization.gd`; READY_V1 notes two overlapping settlement systems | Unify founding/build_kit (READY_V1 item 7); decline/fragment |

### §9 Kingdoms, politics, careers
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Valencious canon, Church antagonist, 13 kingdoms | HAVE | `data/world/nations.json`, `factions.gd CHURCH`, `sim/world_lore.gd` | — |
| Laws, courts, tax, nobility, inheritance, permits, diplomacy | HAVE | `realm/governance.gd` (8 laws, G11), `courts.gd`, `nobility.gd`, `succession.gd` (G13), `diplomacy.gd`, `entry_law.gd` | — |
| Leaders evaluate food/loyalty/threats; differ in character | HAVE | `war_sim.gd`, `siege.gd PERS_STUBBORN`, `realm/war_advisors.gd` | — |
| Careers (farmer, merchant, soldier→mercenary co., smith, hunter, healer, scholar, admin, adventurer, assassin, priest, noble) | PARTIAL | `sim/careers.gd`, `career_ladders.gd`, `soldier_career.gd`, `adventurer_guild.gd`, `realm/career_trades.gd`, `trade_ranks.gd` (incl. thief) | Healer post not wired (G12 note); assassin network, priest (forbidden movement), scholar school missing as independent paths |
| Career change without restart | HAVE | `careers.resign/apply` | — |

### §10 Warfare & sieges (HIGH)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Hierarchy, recruitment, conscription | HAVE | `army/squad.gd`, `realm/armies.gd`, `realm/callups.gd`, `sim/military.gd`, `soldier_career.gd` ranks | — |
| Logistics (food, wages, depots) | PARTIAL | `armies.gd` supply/hunger, `campaign.gd` | Depots, carts as physical objects |
| Command, formations, morale | HAVE | `army/formation.gd`, `army/morale.gd`, `realm/tactical.gd`, `ui/war/*`, `test_formations`, `test_tactical` | Live-3D command UI for player as officer partial |
| Siege engines and approaches | PARTIAL (sim) | `realm/siege.gd` ENGINES (ladders…trebuchet), APPROACHES (starve, undermine, bribe, cut_water…), `test_siege` | 3D siege battle not playable |
| Destruction 3 levels, persists | PARTIAL | `world/breakable.gd`, `test_breakable`, `world_state.gd` | Gates/wall sections as damage states; owner v1 scope decision |
| Objectives battles, aftermath, refugees | PARTIAL | `campaign.gd`, `migration.gd` | Objective battle templates (convoy, bridge) |
| Scale: full AI near, group mid, aggregate off | HAVE | `soldier_aaa.gd`, `realm/war_units.gd`, `war_sim.gd` | Needs perf test on iGPU |

### §11 Wildlife & ecosystems (HIGH)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Species with habitat, predators/prey, dens, migration, seasons | HAVE (sim) | `realm/ecology.gd` (1430), `ecology_data.gd` SPECIES deer/boar/wolf/corrupted_wolf/bear/troll/wyvern, `sim/monster_ecology.gd` migration, `test_realm_ecology` | Only 7 species; no small fauna in the sim (critters are visual) |
| Emergent wolves→farms→hunters hired | PARTIAL | `monster_ecology.gd` LIVESTOCK_RANGE/CHANCE, `radiant_quests.gd` | Explicit "bounty posted" chain test |
| Taming/domestication | PARTIAL | `monster_bonds.gd`, followers taming | READY_V1 S item |
| Unique beasts once per save, consequences | PARTIAL | `soulbeast_director.gd`, `soulbeast_save.gd` | Political/ecological consequence on kill |

### §12 60-floor dungeons (HIGH)
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| 60 floors, guardians every 10 | STUB | `interiors/dungeon_gen.gd` TIER_LEVELS 1–60 in 4 tiers, 7 THEMES, gates (lever/plate/rune/collapse), `test_dungeons`; cloud branch `claude/dungeons` running | No persistent floor table, no guardian floors |
| Floor categories, inner worlds | MISSING | — | Data spec first (WP-12) |
| Safe underground cities | MISSING | — | Needed for §21 story (minimal: one trading post) |
| Elements as environmental forces | PARTIAL | `sim/element_places.gd` (elements by location), `test_element_places` | Physical effects (ice cracks under weight) |
| Secrets without markers; generator validates reachability | PARTIAL | `dungeon_gen` gates + `sim/hidden_triggers.gd`, `sim/discovery.gd` | Profession-based clue system |
| Non-combat goals | MISSING | — | |

### §13 Exploration & quests
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Discovery layers | HAVE | `realm/exploration.gd`, `world/region_pois.gd`, `real_landmarks.gd`, `sim/discovery.gd`, `ui/discovery_banner.gd` | — |
| Handcrafted + generated quests | HAVE | `quests/*`, quest_weaver addon, `sim/radiant_quests.gd`, `region1/story_quest.gd`, story Acts | Acts 2–5 bot hooks (READY_V1) |
| Multiple approaches, failure valid | PARTIAL | caravans can be lost (`caravans._resolve`) | Quests rarely offer steal/build/sabotage branches |

### §14 Progression & childhood
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Ages 4/8/12/16 + adult | HAVE | `sim/childhood_events.gd`, `life_path.gd`, `life_courses.gd`, `realm/education.gd`, `ui/academy_view`, `apprentice_view`, tests | — |
| Skill-based, no classes | HAVE | `sim/skills.gd`, `mastery.gd`, `skill_evolution.gd` | — |
| Reputation consequences | HAVE | `realm/reputation.gd`, `news.gd` fame/NICK_AT, `sim/titles.gd` | — |

### §15 Visuals, atmosphere, sound
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Terrain/rivers/roads | PARTIAL | `world/world_gen.gd`, `terrain3d_bridge.gd`, W6 real-world data (`docs/world/REAL_WORLD.md`) | Real-world terrain in engine behind --world_macro=real (W6.2/W6.3: re-anchored layout, real lakes/sea/rivers, 768 m Terrain3D regions at 3 m, region lock + warden camps, slice camp/cave pinned); default flip pending look/iGPU sign-off |
| Vegetation, seasons | PARTIAL | `terrain_streamer.gd`, `sim/seasons.gd`, `test_seasons` | Seasonal foliage colour |
| Buildings: kits + variation | HAVE | `world/town_kit/*`, `town_identity.gd`, TOWNS_MEDIEVAL_PASS | — |
| Characters, faces, layered clothing | PARTIAL | `hero_outfit.gd`, `npc_face_card.gd`, MakeHuman | Art direction decision (owner) |
| Weather (rain, snow, fog, puddles) | PARTIAL | `world/weather.gd`, `test_weather` | Puddles/wetness shader |
| Sound as gameplay (noise, NPCs hear fights) | PARTIAL | `player.noise_radius`, `npc_world` CRIME_HEARING 40, `population/alert_net.gd` | Storm masking, tunnel echo |
| Dynamic music | HAVE | `audio/adaptive_music.gd`, `music_bank.gd` | — |

### §16 UI
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Character, inventory, map, journal, NPC, companions, settlement, economy, factions, military | HAVE | `ui/gamemenu/*`, `ui/affairs/*`, `ui/war/*`, `quest_journal.gd`, `world_map.gd`, `farm_ledger.gd` | Dungeon map screen missing |
| No omniscience; news by messenger | HAVE | `realm/news.gd` ROAD_SPEED/COURIER_SPEED, `rumours.gd`, `sighting_report.gd`, `war_intel.gd` | Ensure UI panels read from news, not truth (audit in WP-08) |

### §17 Technical
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Sim data separate from rendering | HAVE (people, realm) / PARTIAL (dungeons) | see §2 below | Dungeons are regenerated, not persisted |
| Threaded loading | MISSING | `load_threaded_request` only in audio | WP-05 |
| Mesh LOD, crowd LOD, impostors | HAVE | `population/population_lod.gd`, `living_world/vat_*`, `core/impostor_baker.gd`, `distance_cull.gd` | VAT edge fade (S3.pop) |
| Chunked navmesh | PARTIAL | `realm/construction_nav.gd`, `population/street_graph.gd` (graph, not navmesh) | Region nav chunks |
| Occlusion for interiors/dungeons | PARTIAL | interiors are separate scenes | OccluderInstance3D in town kit |
| Saves: identities, seeds, inventories, relationships, modified state | HAVE | `sim/save_manager.gd` SCHEMA_VERSION 4, compression, slots, `realm/save_codec.gd`, `test_save_manager`, `test_autosave` | Late-game round-trip (READY_V1 M12) |
| Stress scenario (village+caravan+fire+attack+dungeon load) | MISSING | `test_lw_society_soak`, `test_aura_soak` are sim-only | WP-06 |
| Perf targets incl. iGPU low preset | PARTIAL | `core/quality.gd`, `test_quality_pc`, `world/low_budget.gd`, `test_low_budget` | No measured iGPU number yet (all recent fps runs invalid due to shared machine) |

### §18 Asset pipeline
| Requirement | Status | Evidence | Gap |
|---|---|---|---|
| Meshy → clean → rig → optimise → integrate | PARTIAL | `test_meshy3`, `assets/incoming/*`, `world/assets.gd` | Written pipeline checklist with LOD/collision gate |
| Gameplay metadata on assets (sit points, worker spots, door ownership) | HAVE | `data/living_world/smart_objects.json`, `world/work_spots.gd`, `world/locks.gd`, `world/station.gd` | Forge inputs/outputs/fuel metadata |
| Licence verification | PARTIAL | — | Licence register (owner) |

### §19 Distinctive features
| Feature | Status | Evidence |
|---|---|---|
| World remembers (abandoned farms, broken bridges) | PARTIAL | `world_state.gd`, `settlement_ledger.gd`, `realm/ledger.gd`; no terrain-visible decay |
| Information travels physically | HAVE | `news.gd`, `rumours.gd` |
| Discoverable civilisations | MISSING | needs underground settlement (WP-13) |
| Knowledge is progression (languages, cartography, lore) | PARTIAL | `sim/lore_terms.gd`, `runestone_network.gd`, `scribe.gd` |
| Institutional memory | HAVE | `realm/settlement_ledger.gd`, `chronicle_screen.gd`, `dynasties.gd` |

### §20 Build order / §22 five rules
| Rule | Status | Note |
|---|---|---|
| 1 major NPCs are persistent people | HAVE | registry + minds + WorldSim |
| 2 join/create organisations, no class | HAVE | `organizations.gd` (3112 lines), careers |
| 3 every major action has consequences | PARTIAL | reputation/news yes; combat injuries and building decay no |
| 4 scale backed by streaming, sim LOD, perf tests | PARTIAL | sim LOD yes; threaded streaming + iGPU tests missing |
| 5 polish loops before territory | ADOPTED | Vertical Slice gates all territory work (W6 real-world terrain stays limited to the slice box) |

---

## 2. Architecture mapping (§17)

| Blueprint module | Existing owner(s) | Missing / refactor |
|---|---|---|
| WorldState | `world/world_state.gd` (object state + scheduler), `autoload/game.gd` | Fine. Add a one-page `docs/tech/SIM_MAP.md` (which tick owns what) — doc only |
| TimeSystem | `autoload/life.gd` (clock, `hour_changed`), `sim/seasons.gd`, `sim/shop_hours.gd` | Fine |
| EventSystem | `systems/world_event_log.gd`, `realm/events.gd`, `quests/quest_bus.gd`, `systems/region_event_bridge.gd` | Three buses; no rewrite, but chain tests (WP-07) must go through `world_event_log` |
| RegionManager | `core/cell_streamer.gd`, `world/terrain_streamer.gd`, `world/region_lock.gd`, `world/water_streamer.gd` | **Threaded load** missing (WP-05) |
| NPCSimulation | `autoload/world_sim.gd` (people as data), `realm/minds.gd` (MIND_MAX 960, cadence by distance), `population/npc_world.gd` (16 live slots), `population_lod.gd` | Fine. Data/visual split holds |
| RelationshipSystem | `sim/relationships.gd`, `npc_social_graph.gd`, `realm/bonds.gd` | Fine |
| FactionSystem | `realm/factions.gd`, `organizations.gd`, `diplomacy.gd`, `politics_data.gd` | Fine |
| EconomySystem | `sim/economy.gd`, `market.gd`, `caravans.gd`, `realm/enterprise*.gd`, `businesses.gd` | Link caravan losses to settlement stock (WP-07) |
| CombatSystem | `combat/*`, `actors/player.gd`, `procedural_rig.gd` | Locational damage + injury output (WP-03) |
| WarSimulation | `sim/war_sim.gd`, `realm/armies.gd`, `campaign.gd`, `siege.gd`, `tactical*.gd` | Fine (sim); 3D siege later |
| BuildSystem | `build/*`, `realm/build_kit.gd`, `construction.gd`, `founding.gd` | Unify founding + build_kit (WP-10) |
| EcologySystem | `realm/ecology.gd`, `sim/monster_ecology.gd` | Two ecologies: keep, document which owns dens |
| DungeonManager | `interiors/dungeon_gen.gd`, `dungeon_root.gd` | **Persistent floor registry** (WP-12) |
| QuestSystem | `quests/*`, quest_weaver, `radiant_quests.gd` | Fine |
| SaveManager | `sim/save_manager.gd`, `realm/save_codec.gd` | Fine; add dungeon floor state |
| DebugTools | `core/perf_overlay.gd`, `perf_probe.gd`, DebugMenu addon, `tools_qa/*`, `--pop-log`, `test_npc_decision_trace` | Add a sim inspector for one NPC (WP-08, small) |

**Rule "simulation data separate from rendered objects":**
- Towns/settlements: **holds** (`realm/settlements.gd`, `civilization.gd`, `settlement_ledger.gd` exist without scenes).
- NPCs: **holds** (WorldSim people indices + minds records; bodies are pooled slots/VAT/impostors).
- Armies: **holds** (`armies.gd` aggregate; `soldier_aaa` near).
- Dungeon floors: **does not hold** — a floor is generated from seed on entry and its state (loot taken, doors opened, creatures killed, residents) is not stored. WP-12.
- Buildings the player builds: holds via `construction.gd` holdings + `world_state`.

No rewrites recommended. The two refactors that pay off: WP-10 (one settlement pipeline) and WP-12 (dungeon floor registry).

---

## 3. Vertical slice (§20) on our world

**Area:** the Heartvale section of Valencious around Ashford (Lorton Vale, `REAL_WORLD.md` origin) → road → Kingsreach, about 4 × 3 km.

| Slice element | Concrete content (existing where possible) |
|---|---|
| Living village | **Ashford** (tutorial village, town kit, schedules, smithy, inn, chapel) |
| Town / market | **Kingsreach** gate market (perf route `tools_qa/perf/town_route.gd`) |
| Trade route | Ashford ↔ Kingsreach road, `sim/caravans.gd` tier "rural", `world/road_traffic.gd` |
| Bandit site | One `world/monster_camps.gd` / `realm/camps.gd` bandit camp on the road midway, raids caravans via caravan risk |
| Dungeon entrance | An existing `world/region_caves.gd` cave in the fells above Ashford → dungeon floor 1 (`dungeon_gen` theme `mine`) |
| Neighbouring faction | A rival house from `nobility.gd` (lords of Kingsreach) vs the Church (`factions.CHURCH`) as the opposing pair |
| 20–30 persistent NPCs | Promote 24 registry characters to "upgraded" (`registry.upgrade`): Ashford — smith Tomas + apprentice, innkeeper, 2 farmers + families (6), herbalist (healer), priest, reeve, guard ×2, hunter; Kingsreach — merchant, caravan master, captain of the guard, lord's steward, 2 guards, fence (thief guild contact); bandit chief + 2 bandits; companion |
| 3 career paths | **Blacksmith** (smithy org, crafting chain), **Merchant/caravan** (caravans + market), **Soldier** (`soldier_career.gd` guard of Kingsreach) |
| 2 opposing factions | Kingsreach crown house vs the Church (plus bandits as a non-faction threat) |
| 1 companion | One recruitable (`followers.gd`) hunter-scout, with refuse/pay behaviour |
| 1 dungeon floor | Floor 1 "mine": iron vein, small underground trading post (seed for §21) |
| 4–6 species | deer, boar, wolf, bear (+ corrupted wolf near the cave) |
| 1 settlement project | `founding.gd` camp → hamlet on a claim between Ashford and the cave |

### Acceptance scenario A — §3 movement chain (WP-01)
Bot script `tools_qa/acceptance/movement_chain.gd`, headless-capable for logic, windowed for the visual strip:
1. Spawn Ashford plaza, run 60 m along the street (no stuck > 1 s).
2. Vault the field fence (traversal state VAULT entered and left).
3. Climb the hayloft ladder and back down.
4. Open a house door, enter interior (interior load < 500 ms, no fall-through).
5. Sit on a chair (player SmartObject sit, stand up).
6. Draw sword, fight a training dummy/bandit for 3 exchanges (block, parry, hit).
7. Pick up an object (sack) and carry it 10 m, drop it.
8. Mount a horse, ride 50 m, dismount.
Pass: every step logs `OK`, no `SCRIPT ERROR`, no T-pose / bind-pose frame (pose sanity check from S3.pop), state transitions all have a clip mapped. Windowed strip saved under `docs/qa/golden/acceptance/`.

### Acceptance scenario B — §21 blacksmith/iron/caravan/underground trade (WP-14)
Headless scripted bot `tools_qa/acceptance/story21.gd` over ~40 in-game days with `advance_hours`:
1. Player applies to the Ashford smithy (`careers.apply`), works 5 shifts, gets paid (`pay_day`).
2. Rents a house (`sim/property.gd` rent).
3. Bandit camp raises caravan risk → ≥ 1 iron caravan lost (`caravans._resolve`) → Ashford iron price up ≥ 30 % (`market.gd`) → guard equipment stock falls (`armies` / town guard).
4. Player branch (test each in a sub-case): (a) guards a caravan and it arrives; (b) clears the bandit camp → risk falls; (c) finds the cave and the underground post.
5. Underground post trades iron for surface food; route becomes a registered trade route; prices settle back.
6. A faction (rival house) attempts to seize the route (`war_influence` / `campaign`) → player options exposed: hire guards, found merchant guild (`organizations.gd` org_found), petition lord (`audiences.gd`), walk away.
Pass: every link changes a measurable value, and the world proceeds if the player does nothing (caravans keep being lost, prices stay high).

---

## 4. Prioritised work packages

Order = blueprint priority (critical first) × dependency. **Lane:** LOCAL-GPU needs windowed Godot; CLOUD = code + headless tests. **Perf** = cost on iGPU-low / mid / high.

### Critical — movement & animation
**WP-01 §3 movement acceptance chain** — L — LOCAL-GPU (bot logic part CLOUD)
Goal: scenario A passes. Adds player carry state, player sit on SmartObjects, fall injury, turn-in-place, bot nav-around-obstacle.
Files: `actors/player.gd`, `actors/traversal.gd`, `living_world/smart_objects.gd`, `sim/injuries.gd`, `tools_qa/acceptance/movement_chain.gd`, playtest bot.
Tests: `test_traversal` extended, new `test_player_carry`, `test_fall_injury`, scenario A.
Perf: negligible / negligible / negligible.

**WP-02 Turn-in-place + transition audit** — M — LOCAL-GPU
Goal: no foot-sliding on <90° and 180° turns; list every state pair in `character_animator.gd` without a mapped transition and fill from the golden set. Perf: 0.

### Critical — combat
**WP-03 Locational damage + combat injuries** — M — CLOUD
Goal: hit bone → zone (head/torso/arms/legs) → armour slot reduction → injury chance (bleed, fracture) in `sim/injuries.gd`; bleed ticks; injuries reduce stats.
Files: `combat/combat_stats.gd`, `combat/hit_resolver.gd`, `sim/injuries.gd`, new `combat/hit_zones.gd`. Tests: `test_hit_zones`, `test_injuries_combat`. Perf: 0.

**WP-04 Enemy behaviour archetypes** — M — CLOUD (tuning LOCAL)
Goal: bandit panic/flee/surrender at low morale, soldier holds formation, veteran tracks player's last 5 attacks and counters repeats; human surrender → capture/bind/ransom via `sim/arrest.gd`.
Files: `combat/npc_fighter.gd`, `army/morale.gd`, `sim/arrest.gd`. Tests: `test_npc_fighter` extended, `test_surrender`. Perf: 0.

**WP-04b Player grapple/shove/directional input + environmental kicks** — M — LOCAL-GPU. Perf 0.

### Critical — persistence & world simulation
**WP-05 Threaded region loading** — M — CLOUD (verify LOCAL)
Goal: interiors, dungeon floors, town chunks load via `ResourceLoader.load_threaded_request`; no frame > 50 ms on region entry. Files: `core/cell_streamer.gd`, `interiors/dungeon_root.gd`, `world/terrain_streamer.gd`. Tests: `test_pooling_streaming` + new `test_threaded_region`. Perf: improves all tiers, most on iGPU-low.

**WP-06 Stress scenario** — M — CLOUD (headless sim) + LOCAL (frame time)
Goal: `tools_qa/stress/stress_all.gd`: working village + caravan + fire + faction attack + dungeon load at once; headless asserts sim budget (< 4 ms/frame sim), windowed records frametime on low preset. Perf: measurement only.

**WP-07 The §0 chain wired and tested** — M — CLOUD
Goal: grain harvest → caravan → garrison stock → army morale → `war_sim` opportunity, through `world_event_log`. Files: `sim/caravans.gd`, `sim/economy.gd`, `realm/armies.gd`, `army/morale.gd`, `sim/war_sim.gd`. Test: `test_chain_grain_to_war`. Perf 0.

**WP-08 Knowledge audit + NPC inspector** — S/M — CLOUD
Goal: list decisions in `minds.gd`/`war_sim.gd`/UI that read global truth instead of `rumours`/`news`/witness; fix the top 5; small debug panel showing one NPC's needs/goal/plan/memories. Tests: `test_knowledge_gating`. Perf 0.

**WP-09 Late-game save round-trip** — S — CLOUD (READY_V1 M12) — save after 2 in-game years with followers, settlement, war; reload; diff. Test: `test_save_late_game`. Perf 0.

### Critical — jobs, resources, economy, property, settlement
**WP-10 One settlement pipeline** — L — CLOUD
Goal: a build_kit claim becomes a `settlements.gd` row with `founding.gd` tiers; maintenance/decay added (buildings lose condition, repair jobs). Files: `realm/founding.gd`, `build_kit.gd`, `settlements.gd`, `civilization.gd`, `construction.gd`. Tests: `test_founding`, `test_build_kit`, new `test_settlement_unify_decay`. Perf 0.

**WP-11 Production chain with workshop state + delegation** — M — CLOUD
Goal: ore→smelt→forge needs fuel stock and workshop condition; player can employ an NPC to run production (`enterprise_people.gd`). Tests: `test_crafting`, `test_enterprise`. Perf 0.

### High — dungeons, factions, war, ecology
**WP-12 Dungeon floor registry (60 floors as data)** — M — CLOUD (coordinate with `claude/dungeons`)
Goal: `data/dungeons/first_dungeon.json`: 60 floors, category, theme, guardian every 10, inner-world slots 8–9…58–59, sealed future dungeons; `DungeonManager` stores per-floor state (seed, cleared, loot taken, opened gates, residents) in saves. Tests: `test_dungeon_registry`, save round-trip. Perf 0.

**WP-13 Underground trading post (floor 1)** — M — CLOUD + LOCAL visual
Goal: a small settlement row underground (`settlements.gd` kind `underground`), 6 NPCs, iron for food trade; discoverable by the player only. Needed by WP-14. Perf: small interior, low.

**WP-14 §21 story bot** — M — CLOUD. Scenario B. Depends on WP-07, WP-11, WP-13.

**WP-15 Dungeon floor 1 playable + secrets by clues** — L — LOCAL-GPU + CLOUD generator validation (reachability already partially in `dungeon_gen`).

**WP-16 Healer, scholar, priest, assassin careers** — M — CLOUD. Wire healer post (G12 gap), scholar via `education.gd`, priest via `faith.gd` (permitted/forbidden), assassin via thief guild. Tests per career. Perf 0.

**WP-17 Ecology chain "wolves follow deer → farm attacks → bounty"** — S — CLOUD. Test `test_ecology_bounty_chain`.

**WP-18 Siege v1 decision + objective battles** — L — OWNER DECISION, then LOCAL-GPU. Objective templates (convoy, bridge, gate) are CLOUD-able as sim.

**WP-19 Disease & sanitation** — M — CLOUD. Settlement disease from wells/sanitation/density, healer treatment. Perf 0.

**WP-20 Water contamination + food quality** — S — CLOUD.

**WP-21 Carts / pack animals** — M — LOCAL-GPU.

**WP-22 Building damage states (gates, walls, roofs)** — M — LOCAL-GPU. Perf: mid (extra meshes), keep to 2 states on iGPU-low.

### Performance & visuals (gate for everything)
**WP-23 iGPU low preset measured** — M — LOCAL-GPU, on an idle machine (no other Godot instances). Goal: 30 fps iGPU-low on town_route, 60 fps mid. Files: `core/quality.gd`, `world/low_budget.gd`. Blocked on the machine being free.

**WP-24 VAT edge fade + full-body promotion handoff** — M — LOCAL-GPU (S3.pop remainder).

**WP-25 W6 real-world terrain limited to slice box** — L — LOCAL-GPU (world/terrain worker).

**WP-26 Sound as gameplay** — S — CLOUD: storm masks noise (`weather` → `noise_radius` multiplier), tunnel echo bus in dungeons.

**WP-27 Asset pipeline checklist + licence register** — S — CLOUD (doc + `tools/asset_lint` for LOD/collision presence).

### Owner decisions needed
- **D1 Art style:** photoreal-leaning (current Polyhaven + MakeHuman) vs stylised. Affects WP-23 budget heavily on iGPU.
- **D2 Paid tools / Meshy credits:** budget for creature + building generation.
- **D3 v1 scope of siege, boats, bloodline/crown:** recommendation — siege as sim + one scripted gate assault, no boats, bloodline as already shipped (G13), crown later.
- **D4 Unarmed state:** fists item vs sheathe-to-unarmed (Equip W2 note).

---

## 5. Assignments

| Worker | Id | Next WPs (in order) |
|---|---|---|
| Player / equipment | ac9ce37598979cd3b | Finish Equip items 4–8 → **WP-01** (carry, player sit, fall injury) → WP-02 → WP-04b |
| NPC anim / crowd | afc210eb996e31e33 | **WP-24** → player-sit clips for WP-01 → WP-13 visuals (underground post residents) |
| Towns | a0e10b18748948e00 | Slice dressing: Ashford hayloft ladder + vaultable fence + house for scenario A; bandit camp on the Kingsreach road; WP-22 later |
| World / terrain | a0a0773e4f9271595 | **WP-25** restricted to the slice box; cave entrance above Ashford for WP-15; then WP-05 verification |
| Mechanics (idle) | a8eeb64d3615352a0 | **WP-07** → WP-10 → WP-11 (local, headless only; or hand to cloud) |
| Cloud: dungeons | `claude/dungeons` | Continue; then take **WP-12** on top |
| Cloud: S8a C3–C5, S8c C12/C14 | `claude/focused-curie-m09hbd` | Finish; then rebase onto `aaa/finish` |
| Machine idle window | anyone | **WP-23** perf measurement (no other Godot running) |

### Cloud-ready routine prompts
Each prompt below is self-contained. Shared header (prepend to every prompt):

> Repo `github.com/jonaboy19/ProjectAshes`. `git clone --depth 1 --single-branch -b aaa/finish https://github.com/jonaboy19/ProjectAshes.git && cd ProjectAshes && git checkout -b <BRANCH>`. Godot 4.6.3 headless only: `godot --headless --path kingdom --import`, then gdUnit `godot --headless --path kingdom -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/<file> --ignoreHeadlessMode`. **Do not edit hot files:** `kingdom/scripts/actors/player.gd`, `actors/character_animator.gd`, `actors/procedural_rig.gd`, `population/villager.gd`, `army/soldier.gd`, `actors/monster.gd`, `actors/wolf.gd`, `actors/mount_controller.gd`, `actors/critter.gd`, `world/world_gen.gd`, `world/world_macro.gd`, `world/terrain_streamer.gd`, `core/main.gd`, anything under `world/town_kit/`. If you need a hook there, add a static function in your own file and describe the one-line call in the PR. Run the whole suite before and after; no new failures. Add one line to `docs/plans/AAA_PROGRESS.md`. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Open a PR into `aaa/finish`; the description ends with "🤖 Generated with [Claude Code](https://claude.com/claude-code)".

**CLOUD-03 (WP-03) branch `cloud/wp03-hit-zones`**
> Read `docs/plans/MASTER_BACKLOG.md` WP-03. Add `kingdom/scripts/combat/hit_zones.gd` mapping hit position/bone to head/torso/arms/legs with damage multipliers, armour reduction per equipment slot (`sim/equipment.gd`), and an injury roll that calls `sim/injuries.gd add()` (new types `bleeding` with per-hour damage until bandaged, `fracture` lowering speed or attack). Integrate in `combat/hit_resolver.gd` result only (pure data, no animation). Tests `tests/test_hit_zones.gd`, `tests/test_injuries_combat.gd`.

**CLOUD-04 (WP-04) branch `cloud/wp04-enemy-archetypes`**
> Read WP-04. In `combat/npc_fighter.gd` add archetype profiles (bandit, soldier, veteran, beast): bandits flee or surrender below a morale threshold (`army/morale.gd`), veterans keep a ring buffer of the target's last 5 attack ids and prefer the counter when a repeat is seen. Surrendered humans can be captured through `sim/arrest.gd` (bind, take to guard, ransom). Tests `test_surrender.gd`, extend `test_npc_fighter.gd`.

**CLOUD-05 (WP-05) branch `cloud/wp05-threaded-regions`**
> Read WP-05. Add `kingdom/scripts/core/threaded_loader.gd` (queue over `ResourceLoader.load_threaded_request`, budgeted polling, callbacks) and use it in `interiors/dungeon_root.gd` and interior door transitions (`interiors/interior_door.gd`) and `core/cell_streamer.gd` spawners. Do not touch `terrain_streamer.gd`. Test `test_threaded_region.gd` (load 3 interiors headless, assert no synchronous load call path remains).

**CLOUD-06 (WP-06, sim half) branch `cloud/wp06-stress-sim`**
> Read WP-06. Add `kingdom/tools_qa/stress/stress_all.gd` that boots the sim headless, starts a caravan Ashford→Kingsreach, sets a building fire, triggers a faction raid (`realm/player_raids.gd` / `war_sim`), and loads a dungeon floor, then advances 48 in-game hours and records per-module tick ms. Assert total sim < 4 ms per frame average and 0 SCRIPT ERROR. Test wrapper `tests/test_stress_sim.gd`.

**CLOUD-07 (WP-07) branch `cloud/wp07-grain-chain`**
> Read WP-07 and §0 of `docs/plans/BLUEPRINT_OWNER_2026-10-27.md`. Wire: settlement grain stock → `sim/caravans.gd` deliveries → garrison food in `realm/armies.gd` → `army/morale.gd` → `sim/war_sim.gd` opportunity score for a hostile neighbour. Lost caravans must reduce the stock. Publish each step through `systems/world_event_log.gd`. Test `tests/test_chain_grain_to_war.gd` asserting each link moves.

**CLOUD-08 (WP-08) branch `cloud/wp08-knowledge-gating`**
> Read WP-08. Audit `realm/minds.gd`, `sim/war_sim.gd`, `realm/war_intel.gd` and `ui/affairs/*` for decisions/panels that read true world state about distant events. Route the top 5 through `realm/news.gd` / `realm/rumours.gd` known facts. Add a small debug inspector `scripts/ui/npc_inspector.gd` (needs, goal, plan, memories of one registry character). Write findings in the PR. Test `tests/test_knowledge_gating.gd`.

**CLOUD-09 (WP-09) branch `cloud/wp09-late-save`**
> Read WP-09. Build a headless late-game state (advance 2 in-game years; recruit 3 followers; found a settlement; start a war) and save/load through `sim/save_manager.gd`; deep-diff every module's serialize() output. Fix any drift. Test `tests/test_save_late_game.gd`.

**CLOUD-10 (WP-10) branch `cloud/wp10-settlement-unify`**
> Read WP-10 and READY_V1 item 7. Make a `realm/build_kit.gd` claim create/update a `realm/settlements.gd` row with `realm/founding.gd` tiers (Camp→Hamlet→Village), and add building condition decay + repair jobs in `realm/construction.gd`. Tests `test_founding`, `test_build_kit`, new `test_settlement_unify_decay.gd`.

**CLOUD-11 (WP-11) branch `cloud/wp11-production`**
> Read WP-11. In `sim/crafting.gd` and `realm/work_jobs.gd`, require fuel stock and workshop condition for smelt/forge; let the player employ an NPC (`realm/enterprise_people.gd`) to run a station producing on the day tick. Tests extend `test_crafting.gd`, `test_enterprise.gd`.

**CLOUD-12 (WP-12) branch `cloud/wp12-dungeon-registry`** (coordinate: rebase on `claude/dungeons` if merged)
> Read WP-12 and `docs/plans/DUNGEON_VISION.md`. Add `kingdom/data/dungeons/first_dungeon.json` (60 floors: category compact/labyrinth/wilderness/inhabited/elemental/inner_world, theme, element, guardian every 10, inner worlds 8–9…58–59) plus sealed future dungeons, and `kingdom/scripts/interiors/dungeon_manager.gd` storing per-floor state (seed, cleared, loot taken, gates opened, residents) with serialize/deserialize registered in `sim/save_manager.gd`. `dungeon_gen.gd` reads floor data. Tests `test_dungeon_registry.gd`.

**CLOUD-13 (WP-13, sim half) branch `cloud/wp13-underground-post`**
> Read WP-13. Add an `underground` settlement kind in `realm/settlements.gd` attached to dungeon floor 1, 6 registry characters, a market that sells iron and buys food, hidden from the map until discovered (`realm/exploration.gd`). Test `test_underground_post.gd`.

**CLOUD-14 (WP-14) branch `cloud/wp14-story21-bot`** (after 07, 11, 13)
> Read section 3 scenario B in `docs/plans/MASTER_BACKLOG.md`. Implement `kingdom/tools_qa/acceptance/story21.gd` and `tests/test_story21.gd` with sub-cases (a) escort, (b) clear camp, (c) underground trade, and (d) do nothing. Assert measurable value changes per link.

**CLOUD-16 (WP-16) branch `cloud/wp16-careers`**
> Read WP-16. Wire the healer post (village herbalist org in `sim/careers.gd` + `sim/injuries.gd healer_menu`), scholar via `realm/education.gd`, priest via `realm/faith.gd` (permitted and forbidden orders), assassin contracts via the thief ladder in `sim/trade_ranks.gd`. Each with join + independent path. Tests per career.

**CLOUD-17 (WP-17) branch `cloud/wp17-ecology-bounty`**
> Read WP-17. Deer scarcity → wolf pressure near farms (`sim/monster_ecology.gd`, `realm/ecology.gd`) → settlement posts a bounty via `sim/radiant_quests.gd` and hires a hunter NPC if the player ignores it. Test `test_ecology_bounty_chain.gd`.

**CLOUD-19 (WP-19+20) branch `cloud/wp19-disease`**
> Read WP-19/20. Settlement disease model (density, wells, sanitation buildings, season) in a new `realm/health.gd` registered in `realm/realm_hub.gd`; outbreaks reduce labour; healers treat. Water contamination flag on wells (`interaction/kinds/well.gd` data only) and food quality → nourishment in `sim/needs.gd`. Tests `test_health.gd`, extend `test_needs_survival.gd`.

**CLOUD-26 (WP-26) branch `cloud/wp26-sound-gameplay`**
> Read WP-26. Add a weather noise-mask multiplier consumed by `population/perception.gd` (do not touch player.gd; read `noise_radius()` and scale at the listener) and a dungeon reverb bus switch in `scripts/audio/`. Test `test_noise_mask.gd`.

**CLOUD-27 (WP-27) branch `cloud/wp27-asset-lint`**
> Read WP-27. Write `docs/pipeline/ASSET_PIPELINE.md` (§18 checklist) and `kingdom/tools_qa/asset_lint.gd` (headless: every scene under `assets/` used by towns has LOD or is < 5k tris, has collision, textures ≤ 2k for iGPU-low). Report only, no asset edits.

---

## 6. Top 10 WPs
1. WP-01 movement acceptance chain
2. WP-07 §0 grain→war chain
3. WP-05 threaded region loading
4. WP-23 iGPU low preset measured
5. WP-03 locational damage + combat injuries
6. WP-10 one settlement pipeline + decay
7. WP-12 dungeon floor registry
8. WP-04 enemy archetypes + surrender
9. WP-14 §21 story bot (with WP-11, WP-13)
10. WP-06 stress scenario
