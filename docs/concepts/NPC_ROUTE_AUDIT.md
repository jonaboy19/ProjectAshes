# Ashford NPC direct-route audit

**Snapshot:** seed 1066, Ashford; 320 simulated residents; first work-schedule phase after startup.

## Result

The current data mover selects destination positions and moves directly toward them. Of 318 residents whose current position and target were more than 12 m apart, **203 (63.8%)** had a direct segment that crossed at least one building collider footprint in this static snapshot. The audit included 32 fitted lots and 50 authored street/path segments.

Job distribution among intersecting route candidates: Farmer 102; Blacksmith 16; Merchant 21; Guard 8; Laborer 29; Woodcutter 27.

[Open the interactive route map](NPC_ROUTE_AUDIT.html) to filter by job/building and highlight individual crossings.

## Method

- Ran the Godot project with its actual global classes and imported assets. WorldSim initializes seed 1066, builds Ashford's simulation, and updates the current positions and targets.
- Read the fitted building mesh bounds through Assets.building_mesh(asset), the same fitted asset mesh used by settlement construction.
- Reproduced the current static lot collider footprint: 80% of fitted mesh width and depth, oriented by lot yaw. Expanded its footprint by a 0.35 m agent radius.
- Tested the straight current-position-to-target segment against each expanded oriented box. Excluded intersections confined to the final 16% of the route (the target is a work destination) and grazes shorter than 3.5% of route length.
- Recorded all 203 intersecting routes in the page data. The map includes roads and authored door paths for context.

## Limits

This is a reproducible geometric route-risk audit, not a captured live collision count. It does not simulate runtime navigation, body motion, terrain height, local avoidance, door/yard approach behavior, or LOD handoffs. A route line can intersect a box footprint even if a future path planner would choose a safe street route. Conversely, the box proxy may not match an irregular wall or actual opening. Use the board to select deterministic playtest cases and to prioritize replacing direct target chasing with route-following.

The process loads project assets in headless mode and reports renderer resource cleanup warnings on exit; route sampling completes and outputs all 203 records. This warning is separate from the geometric calculation.

**Related:** [natural-world implementation plan](NATURAL_WORLD_FEEL_PLAN.md), [collision visual audit](COLLISION_VISUAL_AUDIT.html), [locomotion speed review](LOCOMOTION_SPEED_REVIEW.html).
