# Simulation hierarchy (mobile budget)

What is simulated when, so thousands of people, armies, settlements and wars run on an Android phone without a frame spike. The rule is that **nothing scales with world size per frame**. Per-frame cost scales only with what is near the player.

The world is 12 × 12 km (`WorldGen.WORLD_HALF = 6144`, 8 × 8 before), 30 settlements (the first 20 are the 8 km world, unchanged) and roughly 10,000 people (budget: ≤ 25,000). Streaming radius, LOD and memory are fixed by the 64 m chunk ring around the player, not by the map size. `WorldGen.height/color_at/forest_density/road_info/nearest_settlement` use a 128 m spatial index over roads, settlements, camps and site clearings, so a terrain vertex costs the same however many places exist. Site dressing, settlements, monster camps, runestones and dens are built or spawned by distance on 0.5–1 s timers. Realm travel speeds (`camps.TRAVEL_M_PER_HOUR` 1050, `strongholds.RAID_SPEED` 1260, `campaign.ARMY_SPEED/COURIER_SPEED` 180/540, `news.ROAD_SPEED` 750, `ecology_data.MARCH_M_PER_DAY` 675, caravans and family carts) went ×1.5 with the 12 km map so a cross-map trip takes the same in-game time. The far horizon (72 m ground grid), the Scar Tide (384² cells), the map textures and the War Map world field scale with the map; per-frame cost is still the ring around the player. World planning (`RegionSites._free`, the POI planner) buckets sites on a grid so planning 700 sites costs what 350 did (about 2.6 s headless).

Travel (`scripts/world/travel_rules.gd`): running drains stamina after 25 s, horses gallop 30 s then canter, camps and road events are paced by game hours and metres travelled, fast travel is a paid coach between discovered waystations. None of it runs per frame beyond one float add in `player.gd`.

## Frame budget (60 fps target, 30 fps minimum on LOW)

| Work | Budget per frame |
|---|---|
| Rendering (GPU) | whatever Quality tier allows |
| Near NPC AI and animation (population_lod, villager, utility_brain) | ≤ 2.0 ms |
| WorldSim slice (`UPDATES_PER_FRAME` rows of packed arrays) | ≤ 1.0 ms |
| Realm hub `pump()` (queued hour/day/week jobs) | ≤ 0.6 ms (`PUMP_BUDGET_USEC`) |
| Everything else in script | ≤ 1.5 ms |

## Tier 0: every frame (player bubble, about 40 m)

- The player, combat, projectiles, physics.
- **Near NPCs** (≤ 24 animated bodies): full utility AI, pathing, animation, conversation, witnesses for crime.
- Live battle squads (formation.gd/squad.gd): only when the player is at the battle.
- Nothing from `scripts/realm/` runs per frame except `realm.pump()`, which is time-boxed.

## Tier 1: sliced per frame (same settlement, 40–250 m)

- WorldSim rows: position toward the schedule target, phase changes. Sliced, 1500 rows a frame round-robin, O(1) math, no nodes.
- Distant bodies are impostors or MultiMesh; no AI.
- Rumours move between people in the same settlement only on the hour (tier 2), never per frame.

## Tier 2: every game hour (30 real seconds): realm `tick_hour`

Queued one module at a time through `pump()`. Each module's hour tick must stay under 0.3 ms.

- Settlement shops open or close; night districts switch (crime risk, guards on patrol).
- Followers summoned: the travel countdown advances.
- Courier orders advance along their route. Armies move one step along the road graph.
- Job shifts, inn room rental expiry, market prices (economy.tick_hour).
- Rumour propagation: each active rumour spreads to at most N settlements along roads.

## Tier 3: every game day (06:00): realm `tick_day`

- Settlement production and consumption through supply chains, with road condition modifiers.
- Growth, identity drift and emergencies (fire, plague, famine, raid, strike).
- Land: taxes, loyalty, unrest, rebellion checks, and a territory memory decay step.
- Factions: diplomacy drift, marriages, church influence, sect activity, succession.
- Campaign: army supply, attrition, sieges, strategic battle resolution when the player is absent, intel ageing (known information goes stale).
- City life: job openings, quest boards refresh per district, guild politics, NPC goals advance one step.
- Society: relationships decay or grow, courtship, crime investigations (evidence ageing), bounties.

## Tier 4: every game week (day % 7 == 0): realm `tick_week`

- Faraway statistical resolution: regions the player hasn't visited resolve population, wealth and war results as aggregates (no per-person rows).
- Generational steps: NPC ageing, heirs, dynasties (life_courses already does its own).
- Faction power rebalancing, new sects, independent powers rising.

## Catch-up (sleep, fast travel, load, absence)

`catch_up(days, ctx)` must be **O(entities)**, never O(days × entities). Apply closed-form or expected-value results (for example `loyalty += drift * days`, battle outcome by strength ratio), then emit a digest ("While you were away…"). This is how "the realm keeps running while you're away" works without simulating it.

## Data rules

- Realm modules are RefCounted and pure data: no Node, no scene tree, no `get_tree()`.
- Entities are Dictionaries with int ids, or packed arrays when counts go above about 500 (people).
- Anything spatial uses `WorldGen.settlements` / `WorldGen.sites` ids and the road graph, never physics.
- Deterministic: seed RNG from `hash([WorldSim.SEED, tag, day, id])` so tests are stable and saves round-trip.
- All state serialises to JSON-safe Dictionaries (ints, floats, strings, arrays, dicts).

## Presentation LOD (the visible side)

- A city is built from MultiMesh cells (`_multimesh_cells`, 40 m) and shared materials. There's one draw call per mesh per cell, and cells are culled by visibility range.
- Strongholds, camps and faction banners are placed by the world builders from realm data, using the same cell batching.
- UI screens (War Room map, diplomacy, quest board) read module getters and never tick anything.
- City target on LOW: ≤ 150 draw calls visible, ≤ 250k triangles, ≤ 24 skinned characters.

## Schedules and street life across the three levels (`scripts/population/`)

One timetable, `schedule.gd`, serves every level: HOME, WORK, MARKET, INN, TEMPLE, TRAIN, SOCIAL, bent by a flag mask from `town_mood.gd`
(rest day = every 7th day, festivals from `sim/seasons.gd`, war from `Life.war` and nearby armies, monster raids, food shortages from
`realm/settlements.gd`, recent deaths, the law's curfew, crime heat, plague, fire).

| Level | Where | What runs |
|---|---|---|
| Near (≤ 24 bodies) | `villager.gd` + `utility_brain.gd` | Full utility AI: the table is its baseline `sched_*` inputs; TownMood adds inputs (holiday, festive, curfew, scarce, queue, mourn, train) and the acts TRAIN, MOURN, FESTIVE, QUEUE; poorer meals, bread queues, grumbling barks, funerals, drills, wake-up stretch |
| Same settlement, far | `WorldSim` rows | `Schedule.phase(job, hour, flags, person, day)` picks the row's target phase, `Schedule.spot()` its point (inn door, temple front, drill yard, plaza ring). Flags are refreshed one settlement per frame after each hour change. Same code path as before, still sliced |
| Other settlements | realm numbers | No rows: `Schedule.mix()` / `street_activity()` turn the same table into shares of the population (at the inn, at drill, on the street) from the realm state alone |

`micro_events.gd` (child of PopulationLOD) runs at most two short street scenes at a time near the player (pool: `micro_catalog.gd`, 69 entries;
staging: `micro_scene.gd`; extra bodies: `micro_actor.gd`). Weights depend on hour, district, weather and the town's circumstances; cooldowns and
a seeded draw keep it deterministic; the cast is budgeted against `Quality.npc_full`.
