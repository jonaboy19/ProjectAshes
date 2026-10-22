# Rising Ashes: Open-World Life RPG (project instructions)

> Source of truth for the Godot game. The engine work in `kingdom/` (streaming
> world, population simulation, cities, combat, armies, animation) is the
> foundation it's built on. The earlier linear prototype in `game/` is retired.

## Premise

A third-person open-world life, political, economic, military and
Rift-exploration RPG. You begin as an unknown person in a rural frontier village
protected by ancient **runestones**. There is no predetermined destiny. Through
work, combat, politics, trade, exploration, military service, ownership,
relationships, powers, beasts and Rift expeditions you can become almost anything
the world *realistically* allows. Becoming king is never a level-50 perk; there
must be an actual path.

**Design goal:** a world the player believes they genuinely live in, not the
largest map.

## First region (not the whole world)

- About **8 × 8 km of dense playable land**. Distant nations appear on the map but can't be reached yet.
- Contents:
  - the starting village
  - 6–10 other villages
  - 1 major city, far enough away that the journey is meaningful
  - 1–2 towns
  - 3–5 forts or outposts
  - noble estates, plus farms and mines
  - dangerous forests
  - one main safe road network and many trails
  - a border area
  - one major Rift entrance
  - hidden locations
- Travel is part of the simulation: caravans, checkpoints, patrols, weather, roadside inns, attacks and events.

## Systems (protect these especially)

| System | Rules |
|---|---|
| **Runestone network** | Each stone has power, condition, coverage, maintenance and control. It lowers monster aggression and spawning, and raises safety, land value and building viability. Stones can be damaged, sabotaged, overwhelmed, maintained, repaired or expanded, and their state has real consequences. |
| **Monster ecology** | No static level zones. Nests or groups have territory, population, food needs, aggression, migration pressure and threat. Danger is computed from events (migration, dead patrols, Rift instability, season, destroyed nests), so safe roads can become dangerous. |
| **Living transport** | Carriages and caravans move physically or abstractly along routes. "Simulated" journeys still roll events (for example, an ambush loads the scene at the event location). |
| **Careers with real vacancies** | Organisations have seats (for example, the guard has 1 captain, 2 sergeants and 16 guards). Applying needs requirements; promotion needs a vacancy and a decision-maker. |
| **Rank ≠ level** | Higher offices need competence, service record, trust, relationships, qualifications, political support and an open position. |
| **War Merit Ledger** | Records real deeds (defeats, rescues, objectives, orders followed, officers protected, captured leaders, notable acts such as "held East Gate 19 min"). These feed promotion, awards, access and titles, and people refer to them. |
| **Political access** | Audiences can be requested, sponsored, scheduled, delayed or refused. Court access is itself social advancement. |
| **Politics** | Offices, laws, taxes, appointments, land and inheritance rights, titles, succession, alliances, war and peace, factions, marriage, corruption, rebellion, merchant influence. Formal title and actual power are separate. |
| **Settlement ownership and building** | Leadership or purchase (land, houses, farmland, trade, tax and resource rights, debts, plus approvals; roughly 1.4M silver). Building needs money, workers, time, materials, land and legal authority, and happens physically over time. |
| **Branching settlement evolution** | Civic, military, trade or Rift-frontier paths. Hybrids are allowed. Classification comes from thresholds (population, defences, commerce, services, strategic role), not a settlement XP bar. |
| **Reactive population** | Housing, jobs, safety and taxes draw or repel residents. You create conditions; people decide to move. |
| **Emergent attacks** | Migration, war, bandits, Rift instability, retaliation and stampedes, with a real aftermath (dead, destroyed buildings, broken runestone, food and morale loss, repair cost). |
| **Rumour network** | News travels via travellers, merchants, soldiers, notices, messengers and nobles. It can be delayed, incomplete or wrong. |
| **Rift expeditions** | A separate career (porter → scout → fighter → specialist → officer → leader) that feels different from warfare. |
| **Beasts and Soulbeasts** | Living creatures with species, age, temperament, affinity, trust, fear, experience, bond, abilities and needs. Some are tameable, some become mounts or companions, some are untameable. Soulbeast bonding is a life milestone. |
| **Talents and origins** | Origin (farmer, hunter, merchant, soldier, craftsman, orphan, minor official) shapes the start only. Random affinities (for example, Wind: Exceptional) give potential, never a lock. |
| **Powers and Echoes** | Coexist with civilian life. You can become rich or powerful without being an elite fighter. |

## NPC architecture

A person is **not** a CharacterBody3D.

```
WORLD            ~100,000 conceptual inhabitants (data)
FIRST REGION     5,000–15,000 represented
LOCAL AREA       200–500 actively simulated
VISIBLE          50–100 physical characters
VERY CLOSE       20–40 full AI (behaviour trees, perception, navigation)
```

**Decision pipeline:** personality → needs → beliefs → relationships → memory →
role → long-term goals → options → utility evaluation → action. NPCs may fail:
bad investments, bad marriages, bankruptcy, being killed or betrayed.

Strategic decisions run in simulation. Nearby embodied behaviour uses LimboAI
(or equivalent).

## War participation

You're always your character. Command authority grows with real rank:

```
soldier #317 → squad leader (12) → captain (85) → commander (430) → general (4,700)
```

## Technical foundation

- **Engine:** Godot **4.6.x** (matches the dev PC). Jolt physics is built in.
- **Dependencies:** evaluate before adopting. Check licence, engine compatibility, maintenance and integration cost, confirm it saves real time, and wrap it behind project interfaces.

| Candidate | Licence | Status here |
|---|---|---|
| LimboAI 1.8.1 (behaviour trees and state machines) | MIT | GDExtension build for 4.6 available; to adopt for near-player NPC AI |
| Dialogue Manager 4.x | MIT | to adopt for conversations |
| Expresso Inventory System | MIT | to evaluate for items, equipment and crafting |
| QuestSystem 2.x | MIT | to evaluate for jobs and quests |
| Phantom Camera | MIT | optional (current camera is custom) |
| Terrain3D 1.0.2 | MIT | later: our procedural streamed terrain works; migrate when hand-sculpting is needed |
| ProtonScatter | MIT | editor-time scattering; our runtime scatter already works |
| Dungeon Crawler 3D | MIT | later: Rift interiors |

## Development order

1. **Vertical slice: the starting village** (build this first; see below).
2. Surrounding wilderness.
3. Neighbouring village.
4. Carriage travel.
5. First military post.
6. First town.
7. Major city.
8. Politics.
9. Warfare.
10. Settlement ownership.
11. Rift.

### Vertical slice scope

- **World:**
  - the starting village with 10–20 buildings
  - a runestone perimeter
  - a small forest
  - a short safe-road section
  - one combat area
- **30–50 physical NPCs** who work, sleep, eat, travel, own money, have jobs and remember basic events.
- **Player systems:**
  - locomotion and camera
  - interaction
  - inventory and equipment
  - money, buying and selling
  - employment and wages
  - time, day/night, sleep and food
  - save/load
  - melee combat
  - skills and small jobs
  - leaving protected land to fight one monster type, then returning home
- **World systems:**
  - runestone protection logic
  - danger calculation
  - weather
  - economy
  - a world-event framework

The player must be able to live several meaningful in-game days, and the village
must feel like it functions without them.

#### Slice progress

| System | State | Where |
|---|---|---|
| Locomotion, camera, melee (combo, block, dodge) | done | `scripts/actors/player.gd` |
| Runestone protection, danger readout, wolf ecology, wolves | done | `scripts/sim/runestone_network.gd`, `monster_ecology.gd`, `threat_map.gd`, `actors/wolf.gd` |
| Careers with real vacancies (Guard, Smithy, Inn, Woodcutters), rank = seat + merit, shift attendance, wages, strikes/dismissal, seniority back-fill, NPC hiring | done | `scripts/sim/careers.gd`, `autoload/life.gd` |
| Hunger and fatigue (affect stamina, speed; starvation hurts), eating, inn bed / sleeping rough with time skip | done | `scripts/sim/needs.gd`, `WorldSim.advance_hours` |
| Inventory (GLoot, `data/items.json`), market with stock-driven prices and a merchant purse, wolf pelts/meat loot | done | `scripts/sim/market.gd`, `autoload/life.gd` |
| Save/load (JSON, F5/F9 or Pack menu): world clock, money, careers, needs, market, inventory, frontier | done | `Life.snapshot/restore` |
| Stations: trader, inn, notice board, Captain's menu | done | `scripts/world/village_services.gd` |
| Born in Ashford: birth cutscene, play from age 6, body grows with age, parents are real villagers | done | `sim/life_path.gd`, `cinematic/*`, `Life._begin_life` |
| Titles, achievements, build archetypes from what you do, hidden age/place triggers (age-8 shrine) | done | `sim/titles.gd`, `archetypes.gd`, `hidden_triggers.gd` |
| Adventurer Guild F–S: board from real vacancies, dens, shortages; accept/turn in/fail/debt | done | `sim/adventurer_guild.gd`, `VillageServices.guild_menu` |
| Magicules, naming (cost, level loss, Fractured Core), injuries, herbalist; talent scouts (very rare) | done | `sim/magicules.gd`, `naming.gd`, `injuries.gd`, `scouts.gd` |
| Goblin warren and orc village; beaten monsters yield and can be named into subordinates | done | `actors/monster.gd` (CampMonster), `world/monster_camps.gd` |
| World lore: races, cultures, nations (incl. shinobi/samurai divisions), sects, bloodlines, military ladder | done (data) | `data/world/*.json`, `sim/world_lore.gd`, `sim/military.gd`, `docs/WORLD_LORE.md` |
| VFX: sword arcs, sparks, elemental bursts, shockwaves, qi aura | done | `scripts/vfx/vfx.gd` |
| Modern mobile HUD (round icon buttons, glass cards, themed menus) | done, palette pending | `scripts/ui/ui_theme.gd` |
| Water (lake, river), region buildings from Blender | in progress | agents |
| NPC relationships, weather and equipment slots | implemented base (29 Sep audit) | `sim/relationships.gd` opinion/factions/gifts; `world/weather.gd` schedule/rain/snow/noise; `sim/equipment.gd` slots/stats/durability/buffs |
| Parent quest depth, persistent NPC perception/memory, LimboAI near-NPC wiring, sects/academies fully in play | partial / needs integration | `population/utility_brain.gd` provides local utility AI; `sim/scouts.gd` and world data supply offers/lore, not proof of complete academy play. See `docs/SYSTEMS_MASTERPLAN.md` |

**Emotional payoff:** the starting village grows with you: home, then known
there, then influential, then leader, then owner, then fortified trade city,
then territorial capital. The old house is still there.

## Brief addendum (user, round 4)

Tone and inspiration: Tensura (naming, magicules, monster evolution), Soul Land
(soul beasts, sects, academies), donghua/xianxia, Naruto (much of it expressed as
martial arts), Avatar: The Last Airbender (cultures bound to elements, bending as
martial art). Must look current, never "2010": no lazy placeholders.

**Life from birth**
- You are born a human child in the first village. Birth cutscene. You grow up
  there; parents give quests. Childhood choices and the places you go shape
  your build, titles and later outcomes.
- Hidden age-gated triggers: e.g. go to a specific spot outside the village at
  age 8 (most players won't) and a quest grants an ability or class.
- Titles, achievements, hidden triggers shape your archetype (villager, hunter,
  assassin, merchant, scholar, martial artist... many more), chosen by what you
  do, not a menu.
- Transformation paths later: monsters evolve; blood replacement and other means
  alter race.
- Cinematic cutscenes per quest (camera angles). Quests and cutscene content come
  **last**; build the framework now if cheap.

**Society**
- **Adventurer Guild**: ranks, commissions, jobs and vacancies posted there too.
- Jobs everywhere: farmer, trader, guard, hire others as you grow rich.
- **Merchants and traders** who move goods between places.
- **Scouts** (military/academy/sect talent scouts) appear in real scenarios and
  can recruit people; scouting must be really rare.
- **Military** with real rank structures (Chinese-style depth: squads,
  divisions, officer grades); some nations have special divisions (ninja,
  samurai, etc.).
- Many countries, cultures, tribes, bloodlines, sects and martial-arts schools.
  Kingdoms have distinct cities and villages; eventually everything can be owned
  (endgame, not now).
- Races: humans plus orcs and other monster races with their own villages.
- **Naming** (Tensura): name a monster to make it a subordinate with a class.
  Costs **magicules**; risks losing levels and permanent injuries that must be
  treated at a **healer**.
- **Soulbeasts** are very rare: obtained via a kingdom academy or a sect allowed
  to travel to **Xiava's Lake** (land of soulbeasts; a later region).

**Systems & feel**
- Stamina system (exists), VFX for magic and martial arts, abilities later.
- Mechanics many games don't have. Easy options for becoming whatever you want.
- The region needs water (lakes, rivers, coast).
- Balanced economy; you can buy things.
- UI: modern, responsive, mobile-first; colours to match the "Total Showdown"
  palette (reference screenshot requested from the user).

**Order now**: basics and the first region, perfect and integrated, using open
source where licences allow and the pushed asset packs; Blender work in parallel.

## Art direction rule (user, round 6)

**More detailed appearance ≠ more polygons.** Polish, don't bloat. Preserve or improve FPS on mobile.

- Keep the current ground/terrain style; it works (texture variation, dirt/grass breakup, irregularity).
- Put the effort into buildings, market stalls, props and characters:
  - Buildings: small bevels on timber, roof thickness, window frames, foundation edges, chimneys, doors seated in walls, slight material imperfections.
  - Stalls: better cloth shapes, wood texture, ropes and supports, item placement, material variation.
  - NPCs: one coherent character style that matches the environment.
- Make things feel grounded: ambient and contact shadowing under barrels, boxes, carts and stalls.
- Build 5–8 strong modular kits and vary them procedurally (roofs, walls, signs, extensions, windows, clutter) rather than many unique heavy houses.
- Distance: LODs, HLOD or impostors, aggressive culling, instancing, texture atlases. Distant decoration uses simplified meshes.
- Avoid: blindly raising poly counts, unnecessary dynamic lights, excessive transparency, very high-resolution textures, thousands of tiny objects.
- Asset workflow: Meshy (fast generation, on the user's PC) → Blender cleanup, decimation and LODs (here) → Godot.
- **Never use Higgsfield** (user rule), for any asset, image, audio or video.

## Target look (user reference, round 6)

References: `docs/art_reference/village_target_1.png` and `village_target_2.png`. Keep the existing village **layout**; change the **look**.

- **Style:** cosy, hand-painted stylised fantasy (think polished stylised RPG), not photoreal.
  - Chunky, characterful proportions.
  - Crisp readable silhouettes.
  - Painterly textures with visible stone blocks, planks and slates.
- **Light:** warm golden sun, clear blue sky, saturated but not garish colour, soft bloom. Windows glow warm. Chimneys smoke.
- **Greenery everywhere:**
  - lush bright-green grass
  - flower beds and planters at house fronts
  - bushes hugging walls and fences
  - trees between buildings
  - wildflowers along fences
- **Ground:**
  - cobblestone plaza edges and rings
  - pebbly, sandy dirt paths
  - low stone walls and wooden fences
- **Clutter with purpose:** crates, barrels, sacks, lanterns on posts, hanging signs, goods on stalls, carts.
- **Buildings:**
  - weathered stone bases
  - timber framing
  - blue, red and green slate roofs with colour variation
  - dormers, balconies
  - banners in faction colours
- **Characters:** small, stylised-realistic, readable at distance, warm clothing colours.

### Building concept sheets (user)

Each sheet shows front, side and back views plus detail close-ups. The Blender generators should match them.
- `concept_healer.png`: green slate roof, green-cross sign on a bracket with a lantern, herb stall under a canvas awning, ivy, flower boxes and potted plants, stone steps, a chalkboard.
- `concept_inn.png`: red tile roof, two storeys with a wraparound balcony and flower boxes, a hanging tankard sign, many warm glowing windows, a striped awning over outdoor tables, three chimneys with smoke.
- `concept_blacksmith.png`: dark slate roof, stone ground floor, an open forge wing with a glowing hearth and anvil, a grindstone, weapon racks, fence, anvil sign, a big stone chimney.
- `concept_guild.png`: blue slate roof with dormers, stone base with a raised terrace and steps, an arched double door, blue banners with a gold compass-star emblem, a quest board, lanterns.
