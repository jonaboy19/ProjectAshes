# Vertical slice: Thornfield and its surroundings (user direction, 2026-10-01)

**Source:** the user watched the full 1:47 build (2340×1080, about 47 fps). Don't restart anything and don't chase higher graphics globally. **Perfect the basics**, and make the existing world coherent, alive and unmistakably Rising Ashes. Spend the performance headroom on NPC count, animation, ambient activity, weather and simulation, not on 4K textures.

**Slice scope:** Thornfield plus the village, forest and road around it, 30–60 minutes that feel like a real living place. It needs:
- one complete profession, Scribe, from clerk up to steward
- one combat route
- a few Soulbeasts
- NPC schedules
- economy, crime and reputation
- day and night consequences

Then the systems get replicated across Valencious.

## Priority board and owners
| P | Work | Owner |
|---|---|---|
| P0 | Terrain seams, dark square patches, road-to-grass blending, wheel ruts and foot traffic, building contact shadows, decals at doors, stalls, wells and stables, subtle elevation | **local** (visual judgment on the GPU); cloud fixes placement code on request |
| P0 | Player model proportions and locomotion (walk, run, idle variants, accel/decel, turns, foot placement, weapon hand, tired, injured and carrying gaits) | **local** model plus **Codex** animation |
| P0 | Clean exploration HUD: top shows location/time and a small minimap; bottom-left movement; bottom-right primary action plus context actions; hotbar only when relevant; the status panel collapses to a portrait; the combat HUD expands only in combat | cloud |
| P0 | Contextual interaction button showing the verb and target ("Talk: Roland Ward", "Enter: Golden Stag Inn", "Inspect: Notice Board", "Work: Blacksmith"), replacing "Tap to use" | cloud |
| P1 | Unified building and material pass (timber thickness, plaster, stone size, roofs, windows, doors, foundations, weathering, saturation), plus 20–30 modular detail props attached procedurally (chimney, flower boxes, firewood, sign, damaged plaster, shutters, barrels, laundry, fence) | **local** art; cloud does procedural attachment |
| P1 | Thornfield districts readable without the HUD: market, craft, poor quarter, administrative, inn and stables, military and gate | cloud (layout and props), local (look) |
| P1 | NPC schedules expanded: wake, eat, commute, work, shop, tavern, temple, train, socialise, home, sleep, rest days and festivals; reacting to weather, war, monsters, shortages, deaths and crime. Three simulation levels: near, same town, other towns | cloud |
| P1 | 50–100 reusable micro-events, e.g. cart passing, drunk thrown out, merchant argument, children chasing, guard questioning a traveller, thief running, funeral, noble carriage, adventurers, recruiters, performer, broken cart, market closing, gates closing, guard shift change | cloud |
| P1 | Rising Ashes identity outside the walls: runestones along maintained roads, a visible protected/unprotected boundary, damaged stones, monster warning posts, checkpoints, abandoned carts beyond protection, Soulbeast tracks, caravans waiting for escort, shrines, Rift traders, returning patrols | cloud (placement and sim) plus local (look) |
| P1 | Real careers. Scribe: copying, forgery detection, translation, tax records, clerk, steward, restricted records, noble secrets, estates, diplomacy. Also ladders for farmer, soldier, merchant and blacksmith | cloud |
| P2 | Weather and seasons visible in town; crime, law and economy reactions; larger population; deep relationships; combat and VFX | later |
