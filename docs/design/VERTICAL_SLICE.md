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

## Detail prop keys (house detailing hooks, cloud session 2026-10-01)

Every house lot gets 2-6 attachments chosen by district + wealth + the lot's own seed (`scripts/world/house_details.gd`, placed by
`scripts/world/district_props.gd`, called from `SettlementBuilder._build`). There are 29 keys. **Each key is a hook for the local
session:** drop a GLB at `kingdom/assets/generated/details/<key>.glb` and it replaces the stand-in everywhere (first match wins, no code
change; merged per material, one MultiMesh per key per 40 m cell). Convention: real metres, +Y up, **origin on the ground** for floor
items and **on the wall plane at the middle of the item, +Z out of the wall** for wall items (window boxes, signs, shutters, lanterns,
awnings, banners, plaster patches), one material per key where possible (each key is one draw call).

| Key | Slots (wall_a/wall_b = front wall left/right of the door, door_a/door_b = floor beside the door, side, yard, post, roof) | Stand-in today |
|---|---|---|
| `chimney_stack` | side | procedural (`house_details.gd` `_proc("chimney")`) |
| `flower_box` | wall_a,wall_b | existing `Assets.building_mesh("planter_box")` |
| `flower_planter` | door_a,door_b | existing `Assets.building_mesh("flower_planter")` |
| `firewood_stack` | side,door_a,door_b,yard | existing `Assets.building_mesh("woodpile")` |
| `shop_sign` | wall_a,wall_b | existing `Assets.building_mesh("shop_sign")` |
| `damaged_plaster` | wall_a,wall_b | procedural (`house_details.gd` `_proc("plaster_patch")`) |
| `shutters_open` | wall_a,wall_b | procedural (`house_details.gd` `_proc("shutters_open")`) |
| `shutters_closed` | wall_a,wall_b | procedural (`house_details.gd` `_proc("shutters_closed")`) |
| `shutters_painted` | wall_a,wall_b | procedural (`house_details.gd` `_proc("shutters_painted")`) |
| `barrel_pair` | door_a,door_b,side | existing `Assets.building_mesh("barrel_cluster")` |
| `rain_barrel` | side,door_a,door_b | existing `Assets.building_mesh("barrel")` |
| `laundry_line` | yard | existing `Assets.building_mesh("washing_line")` |
| `fence_run` | yard,door_a,door_b | existing `Assets.building_mesh("fence")` |
| `hanging_lantern` | wall_a,wall_b | procedural (`house_details.gd` `_proc("lantern")`) |
| `bench` | door_a,door_b | existing `Assets.building_mesh("bench")` |
| `hand_cart` | yard,door_a,door_b | existing `Assets.building_mesh("hand_cart")` |
| `market_cart` | yard | existing `Assets.building_mesh("cart")` |
| `lamp_post` | post | existing `Assets.building_mesh("lamp_post")` |
| `crate_stack` | door_a,door_b,side | existing `Assets.building_mesh("crate_stack")` |
| `sack_pile` | door_a,door_b,side | existing `Assets.building_mesh("sack_pile")` |
| `hay_bale` | yard,side | existing `Assets.building_mesh("hay")` |
| `striped_awning` | wall_a,wall_b | procedural (`house_details.gd` `_proc("awning")`) |
| `wall_banner` | wall_a,wall_b | existing `Assets.building_mesh("wall_banner")` |
| `drying_rack` | yard | procedural (`house_details.gd` `_proc("drying_rack")`) |
| `weapon_rack` | door_a,door_b,yard | existing `Assets.building_mesh("weapon_rack")` |
| `anvil` | door_a,door_b,yard | existing `Assets.building_mesh("anvil_stump")` |
| `roof_patch` | roof | TownDecals `plaster` (downward roof projector) |
| `flower_bed` | yard,door_a,door_b | existing `Assets.building_mesh("flower_bed")` |
| `water_trough` | yard,door_a,door_b | existing `Assets.building_mesh("water_trough")` |

Wall-mounted keys are named `hanging_*` in the scene so the world lint knows they hang on purpose. The `roof_patch` decal is capped at 8 per
town (the Mobile renderer applies 8 decals per mesh). District street furniture (`district_props.gd` `SETS`) uses existing assets only.

## Districts and outside-the-walls identity (cloud session 2026-10-01)

- `scripts/world/districts.gd`: six districts per town (market, craft, poor, admin, inn, military) from weighted anchors; `CityPlanner.plan`
  writes `plan["district_anchors"]`, `lot["district"]`, `lot["wealth"]`, `lot["seed"]`, and swaps plain houses for district variants.
  **`Districts.district_at(pos) -> String`** (any world point; "" in the countryside), `Districts.locate(pos)`, `CityPlanner.district_at(plan, pos)`.
  After a town is built `plan["marks"]` holds `{yard, wells[], boards[]}` (drill yard centre, communal wells, notice boards) for NPC schedules.
- `scripts/world/outer_identity.gd` plans ward markers, checkpoints, shrines, warning posts, cracked runestones, abandoned carts, waiting
  caravans (`escort: true`) and Rift traders (`rift_trader: true`) as `roadside` sites with an `ident` tag; `outer_identity_view.gd` draws the
  ash ground tint beyond the wards and Soulbeast tracks around live ecology dens.
