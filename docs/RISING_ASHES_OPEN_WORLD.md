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

**Emotional payoff:** the starting village grows with you: home, then known
there, then influential, then leader, then owner, then fortified trade city,
then territorial capital. The old house is still there.
