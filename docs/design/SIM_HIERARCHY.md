# Simulation hierarchy (mobile budget)

What is simulated when, so thousands of people, armies, settlements and wars run on an Android phone without a frame spike. The rule is that **nothing scales with world size per frame**. Per-frame cost scales only with what is near the player.

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
