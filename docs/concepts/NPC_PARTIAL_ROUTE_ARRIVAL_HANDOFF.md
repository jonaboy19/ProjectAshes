# NPC partial-route arrival risk — Claude handoff

## Observation to verify

`StreetGraph.route()` may return its closest reachable partial path and set `last_route_partial = true`. `Villager._plan_route()` appears not to consume that flag, while `_steer()` marks `_arrived = true` when it reaches the returned path endpoint. If both observations hold in the live path, the NPC may treat the end of a partial route as arrival at its requested activity slot.

This is a route/LOD risk, not a confirmed runtime bug. Its frequency and gameplay impact are unknown.

## Reproduction and owner handoff

Ask Claude to reproduce a villager with an unreachable work or activity-slot target. Capture and log all three values together:

- requested goal position;
- returned path endpoint;
- `last_route_partial` value.

Check whether the NPC actually marks the requested activity as reached at the partial endpoint. After confirming behavior, decide with the existing route-budget and population-LOD owner whether a partial path should be treated as failed approach, released, or replanned. Do not add route retries until their interaction with the current route budget/LOD policy is understood.

No patch is proposed here: `street_graph` has unpublished Claude work, and Villager/population LOD files overlap active work. No runtime validation was performed for this handoff.
