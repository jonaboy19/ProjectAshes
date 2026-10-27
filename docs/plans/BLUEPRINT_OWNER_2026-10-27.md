# Rising Ashes — Full Game Blueprint (owner input, 2026-10-27)

Owner-supplied design blueprint (written with ChatGPT from 10 reference videos). The owner notes ChatGPT did **not** know our existing content — so this is a requirements list to be reconciled against what we already have (see `MASTER_BACKLOG.md` once produced). Do not lose any of it. Performance target correction from the owner still applies: **regular PC, possibly integrated graphics** (`project-min-spec`), not "16 GB + 8 GB VRAM".

## 0. Core principle
Everything connects through one persistent world simulation. Example chain: village grain → merchants → fortress → soldiers eat; bandits hit the caravan → fortress short → morale drops → enemy exploits it; player can escort, hunt bandits, trade, negotiate, or side with the invaders. The player can live an ordinary life (farm, hunt, craft, explore) or rise (merchant, soldier, founder, guild leader, noble, adventurer, ruler).

## 1. Reference videos → needs
| Video | Observed | Needs |
|---|---|---|
| Dungeons & Kingdoms | dungeon entrances, big settlements, mounted exploration, building presets | modular building, enterable cities, seamless exploration, functional structures |
| Large warfare | formations, mounted battles, castle assaults/climbing | commandable armies, formations, siege engines, destructible fortifications, vertical movement |
| Dark exploration | fog forests, ruined castles, mud, abandoned buildings | atmosphere, weather, environmental storytelling, discoverable interiors, believable ruins |
| Survival & settlements | camps, huts, NPC groups, villages, strange humanoids | autonomous NPC groups, camps, recruitment, survival, routines, creature societies |
| Settlement defence | gathering, snowy settlements, bandits, soldiers, fortification | seasonal survival, construction, NPC guards, raids, local economies |
| Survival/dynasty | wilderness, building, wooden structures, travel | homesteads, family, expansion, long-term progression |
| Medieval battle | first-person melee, assaults, siege objectives | weapon physics, readable attacks, objectives, squad AI |
| Historical melee | guards, counters, close strikes | directional defence, believable animation, stamina, physical reactions |
| Dark fantasy combat | brutal close combat, forest encounters, dungeons | heavy feedback, smart enemies, suspense, finishers |
| Technical dueling | dodges, counters, combos, footwork | advanced dueling, recovery timing, responsive hit detection |

## 2. Six pillars (all must interact)
Living NPC civilisation · Combat & warfare · Survival & construction · Kingdoms & politics · Exploration & dungeons (60-floor) · Fantasy & progression.

## 3. Movement & physical interaction
Walk/run (accel/decel/ground adaptation), sprint (stamina, equipment penalty), crouch (visibility/sound/posture), jump (takeoff/landing/momentum), climb (ladders, ropes, ledges, structures), vault (walls, windows, fences, debris), swim (surface, dive, underwater stamina, currents), fall (height injuries, landing, recovery), horse riding (mount/dismount, speed, turning, stamina, obstacles), carrying (crates, bodies, sacks, tools, injured NPCs), interaction (sit, sleep, doors, containers, machinery, furniture), combat movement (sidesteps, dodges, circling, backpedal, guard movement).
Animation: blending, turn-in-place, animation-timed combat, upper/lower body layering, hand placement, foot IK, hit reactions, context transitions; real hand/foot contact when climbing.
**Acceptance test:** run through a village, vault a fence, climb a ladder, enter a house, sit, draw sword, fight, pick up an object, mount a horse — no broken transitions.

## 4. Combat
Light/heavy, directional (horizontal/vertical/thrust), block (stability + stamina), parry (tight window), perfect counter, dodge (directional, limited i-frames), feints, weapon clashes, grappling (push, clinch, takedowns), guard break, poise/balance/stagger, locational damage (head/body/arms/legs + armour), injuries (bleeding, fractures, performance), death/incapacitation/capture/surrender, environmental combat (kick into hazards, cover, elevation). Weapon-specific movesets (sword combos, spear reach, axe commitment, dagger close, bow posture/distance, staves/magic). Controlled animation commitment — weighty but responsive.
Enemy AI: tactical (panicking bandits, disciplined soldiers holding formation, veterans punishing predictability); large creatures: distinct movement, telegraphs, weak points, aggression states, environment reactions.

## 5. NPCs (most important system)
Life model per persistent NPC: identity, social life, needs, skills, economy (money, property, inventory, job, income/expenses), loyalties, memory, ambitions, beliefs, autonomy, knowledge (witnessed/learned/inferred only), current plan. Daily routine is a plan, not a script (example blacksmith Tomas 06:00–21:00). Layered AI: needs/utility → goal selection → action planning → navigation/interaction → memory/consequences. Deterministic core + personality variation; **no LLM required** for ordinary decisions. NPCs act without the player: change jobs, relocate, marry, have children, recruit, buy/sell/rent/inherit property, found businesses/guilds, join factions, desert, commit crimes, train, explore, get ill/injured, die. Internally consistent; not everyone succeeds.

## 6. Recruitment & companions
Followers are people with contracts (obligations/permissions). Roles: combat companion, scout, hunter, quartermaster, builder, merchant, administrator, military commander, dungeon explorer (independent expeditions). Delegated responsibility for rulers (appointed NPCs manage and stay accountable). Companions can refuse illegal acts, demand pay, grow loyal, resign or betray.

## 7. Survival & crafting
Hunger (quality, nourishment), thirst (potable/contamination), sleep (safe locations), temperature (clothing, shelter, fire, weather), injuries (bandage, infection, recovery), disease (outbreaks, sanitation, medicine), equipment wear/repair, encumbrance (carts, pack animals), shelter/camping, fire (fuel, cooking, light, heat, spreading). Not endless meter management. Production chains (ore → smelt → forge → weapon) with supply, fuel, tools, skill, workshop condition; manual or delegated production.

## 8. Construction
Layers: land (ownership, permission, zoning, claims, trespass), placement (terrain checks, snapping, free placement, preview), foundations (levelling, stability), structures, interiors (furniture, storage, workstations, fireplaces), utilities (wells, drainage, fuel, sanitation, light), industry (mines, sawmills, mills, workshops, warehouses), agriculture (farms, fences, barns, orchards, animal shelters), defence (gates, towers, palisades, stone walls, traps, barracks), maintenance (repairs, deterioration). Three methods on one system: manual, blueprint, NPC-directed (assign workers/supervisors). Settlement progression homestead → hamlet → village → town → city → regional power (not forced; can decline/fragment; authority ≠ size).

## 9. Kingdoms, politics, careers
Keep Valencious canon (politically divided region, covert civil conflict, the Church as antagonist, 13-kingdom world). Laws, jurisdiction, courts, military authority, tax, nobility, inheritance, land ownership, permits, diplomacy; leaders evaluate food, loyalty, security, threats, finances; leaders differ (cautious, ambitious, cruel, pragmatic, corrupt, benevolent). Careers with join path and independent path: farmer, merchant, soldier (→ mercenary company), blacksmith, hunter, healer (clinic), scholar (school/library), administrator, adventurer (company), assassin (network), priest (permitted/forbidden movement), politician/noble. Each: skills, equipment, daily work, resources, income, risks, progression, colleagues, consequences. Career changes without restarting; rare mystical paths keep lore restrictions.

## 10. Warfare & sieges
Hierarchy soldier → squad → company → officer → commander → strategic leadership; player can be any level. Systems: recruitment (volunteers, professionals, mercenaries, conscription, legal limits), training, equipment (procurement, durability, ammo, armour, horses), logistics (food, water, medicine, carts, wages, depots), command (orders, waypoints, formations, delegation), morale, formations (shield wall, spear, skirmish, cavalry charge, reserves), siege (ladders, rams, towers, artillery, sapping, blockade), defence (gates, chokepoints, reserves, evacuation, counterattack), casualties (wounded, prisoners, treatment), campaigns (marching, scouting, intelligence, territory, negotiation), aftermath (occupation, reconstruction, loot, legal consequences, refugees). Battles need objectives (convoy, bridge, gate, captives, siege engines, road), not just "kill all". NPC commanders act independently and can make mistakes. Destruction in 3 levels: fully interactive pieces (gates, barricades, engines, selected wall sections), predefined destruction states (towers, walls, roofs), visual damage; damage persists until repaired. Battle scale by tested performance: full AI near, group AI mid, aggregate sim off-screen.

## 11. Wildlife & ecosystems
Per-species: habitat, diet, territory, activity/sleep/feeding/drinking, predators/prey, breeding, migration, fear/aggression/injury, social structure, seasons, settlement interaction, taming/domestication/coexistence. Emergent events (wolves follow deer; scarce deer → wolves near farms → patrols/hunters hired). Unique fantasy beasts: ancient territorial guardians, subterranean titans that reshape caves, intelligent beast societies, Rift-transformed creatures; some exist once per save and killing them has ecological/political consequences.

## 12. 60-floor dungeons
See `DUNGEON_VISION.md`. Additions: floor categories compact / extended labyrinth / wilderness / inhabited / elemental / inner world; guardians at 10–60; inner worlds 8–9 … 58–59; several dungeons, only the first built initially; sealed future dungeons exist in lore/data. Safe cities (walls, families, food, water, housing, jobs, trade; people born underground; player can settle, rent, own, join, marry, found businesses; runs without player; crime/corruption/crises possible). Elements as environmental forces: fire, water, ice, lightning, wind, earth, nature, shadow, light, Rift (e.g. frozen lake holds a light character, cracks under a heavy beast; ground ancient machines in storms). Secret generation + discovery: no glow/markers/objectives (e.g. mismatched masonry, scholar recognises older construction, hollow sound, air current); generator validates required paths reachable and secrets optional; no universal secret detector — professions/knowledge/tools give clues. Non-combat dungeon goals: transport networks, restore water, translate languages, diplomatic contact; abandoned labs, working mines, religious communities, rival expeditions.

## 13. Exploration & quests
Discovery layers: visible landmarks, environmental clues, historical evidence, dynamic discoveries, legendary mysteries. Quests: handcrafted (main story, key NPCs, Church conflict, arcs) + simulation-generated from real conditions; multiple approaches (negotiate, fight, steal, trade, build, discover, sabotage, refuse); failure is a valid outcome (caravans can be lost without waiting for the player).

## 14. Progression & childhood
Keep ages 4, 8, 12, 16 + adulthood (family/observation → learning/early skills → apprenticeship/education → independence/employment/travel → property/careers/leadership/family/expeditions). Early choices don't lock you in. Skill/experience-based; no rigid classes for mundane professions. Social consequences of reputation (accomplished smith, notorious mercenary).

## 15. Visuals, atmosphere, sound
Combine bright everyday world, darkness & danger, rare mystical places, living atmosphere — consistently. Regional architecture/clothing by culture. Production areas: terrain (transitions, erosion, cliffs, rivers, roads), vegetation (regional species, seasons), buildings (kits + local variation), characters (proportions, layered clothing, faces), animals (skeletons, anatomy), lighting (interior/exterior exposure, day/night, magic light), weather (rain, snow, wind, fog, puddles), VFX, audio (material footsteps, wildlife, voices, crowds, weather, combat), music (regional, dynamic). Sound as gameplay: noise by material/movement, NPCs hear fights, storms mask noise, tunnels echo. Dynamic music by situation.

## 16. UI
Contextual UI; deeper management on demand. Screens: character, inventory, world map, journal, NPC interaction, companions, settlement, economy, factions, military, dungeon maps. No omniscience: intel comes from observation, reports, messengers, maps (news of a distant attack arrives later by messenger).

## 17. Technical architecture (proposed responsibilities — map onto existing code, don't duplicate)
WorldState, TimeSystem, EventSystem, RegionManager, NPCSimulation, RelationshipSystem, FactionSystem, EconomySystem, CombatSystem, WarSimulation, BuildSystem, EcologySystem, DungeonManager, QuestSystem, SaveManager, DebugTools. Rule: separate simulation data from rendered objects (towns/dungeon floors exist as data; scenes load and sync on arrival, drop back to cheap sim on leave). Streaming: threaded loading, mesh LOD, chunked navmesh baking, occlusion for interiors/dungeons. Saves: identities, seeds, inventories, relationships, modified state. Automated stress scenarios (working village + caravan + fire spreading + faction attack + dungeon region loading at once).
Performance targets (corrected): 60 fps ordinary exploration at medium on mid PCs; a playable low preset on integrated graphics; no lost state on save/load; no stalls or missing collision on region transitions; consistent combat input; battle size scaled to tested hardware.

## 18. Asset pipeline (Meshy / Blender / Godot)
Define → generate/model → clean (topology, UVs, textures) → rig/animate → optimise (LODs, materials, texture sizes, collision, instancing) → integrate (interaction + simulation metadata) → validate (visual, collision, perf, gameplay). Important assets carry metadata (chair: sit point; forge: worker spots, inputs/outputs, fuel; door: ownership, lock, damage, navigation). Verify commercial licences for third-party and AI-generated content.

## 19. Distinctive features
The world remembers (wealth/poverty after wars, wild abandoned farmland, broken bridges reroute trade). Information travels physically (rumours via merchants/travellers/soldiers/messengers). Civilisations can be discovered (unknown dungeon communities). Knowledge is progression (languages, cartography, medicine, architecture, creature lore, history reveal opportunities). Settlements have institutional memory (founders, saviours, traitors, benefactors across generations).

## 20. Build order
Vertical slice first: one section of Valencious with a living village, wilderness, trade route, bandit site, dungeon entrance, neighbouring faction. Test targets: 1 living village, 20–30 persistent NPCs, 3 career paths, 2 opposing factions, 1 recruitable companion, 1 playable dungeon floor, 4–6 wildlife species, 1 small settlement project. Phases: (1) foundation & movement — controller/locomotion/interaction, inventory/survival/time/weather, character & animation framework, persistent saves + region loading, debug/logging/tests; (2) first living settlement; (3) combat & wilderness; (4) player-driven progression; (5) first complete dungeon; (6) advanced warfare & expansion. Design all 60 floors as data early; produce content only after the first floor types prove fun and performant.

## 21. Example story (target experience)
Ordinary player works for the blacksmith → rents a house → bandits raise iron prices, guard equipment and food deliveries suffer → options: caravan guard, trader, new iron source, negotiate safer route → finds a cave → underground settlement with iron that needs surface food → player brokers trade, caravans grow, both prosper → a faction tries to seize the route → hire guards, found a merchant guild, seek a lord's protection, join the council, or walk away. No forced warrior/ruler path.

## 22. Priorities and five rules
Critical: movement & animation; NPC lives & decisions; persistence & world simulation; combat & enemy AI; jobs/resources/economy; property & settlement building. High: factions/politics; dungeons & secrets; warfare & sieges; wildlife/ecosystems; inner worlds (later production). Lore-dependent: mystical powers. Optional scaling: thousands of soldiers; extra 60-floor dungeons (long-term).
Rules: (1) major NPCs are persistent people, not quest dispensers; (2) join or create organisations, work for others or go independent, no permanent class; (3) every major action has consequences; (4) scale is backed by streaming, sim LOD, consistent data and perf tests; (5) polish complete loops before adding territory — one believable village beats several empty kingdoms. The foundation to invest in most: the persistent world simulation connecting everything.
