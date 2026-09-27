# NPC movement: Godot 4.6 implementation notes

**Audience:** Claude's gameplay branch `claude/focused-curie-m09hbd`

**Purpose:** turn the broad NPC and collision plan into a Godot-specific movement contract.
**Reviewed game source:** `claude/focused-curie-m09hbd` at `e3563fc4`; refresh before implementing. This branch contains documentation and review artifacts only.

## Current movement ownership in the inspected source

The current project has a useful near/far split, but a nearby resident does not take over physical movement from the world simulation:

- `kingdom/autoload/world_sim.gd` owns packed position and target arrays for roughly 20,000 people. It slices updates at 1,500 rows per rendered frame and moves those data positions at 1.3 m/s.
- `kingdom/scripts/population/villager.gd` is a `Node3D`. In `_process`, it reads the current simulated position, moves toward that point directly, and chooses `Walking_A` whenever the gap exceeds 0.15 m. It uses 1.6 m/s normally and triples that when more than 4 m behind. It has no body capsule, path agent, or obstacle query.
- `kingdom/scripts/actors/critter.gd`, `wolf.gd`, and `monster.gd` also move by writing a new transform from a straight-line direction. Critter documents that it has no physics or navigation. Their `_physics_process` callbacks do not make the actors physical by themselves; the nodes do not inherit `CharacterBody3D` or call `move_and_slide()`.
- `PopulationLOD` already bounds the expensive population: at most 24 full resident models, including a near-player allowance of 12. That is a natural starting boundary for embodied collision and route following. Profile it before changing the cap.
- The existing static route audit flags 203 of 318 resident target segments longer than 12 m crossing current fitted building footprints. This is a geometric warning, not a live navigation or collision count.

This combination explains why adding a `NavigationAgent3D` by itself would not solve pass-through: Godot supplies paths and optional avoidance, while the game script still owns movement and physics collision.

## Movement contract

Use one owner for each layer of movement:

| Layer | Owns | Must not do |
|---|---|---|
| `WorldSim` | Persistent identity, schedule, intent, stable destination/anchor | Continuously overwrite the transform of a visible physical actor |
| Local route follower | Reachable path to a validated goal, waypoint progress, stuck/repath policy | Treat target direction as a route through buildings |
| Local steering | Yielding and short-horizon spacing around moving nearby agents | Replace static obstacle pathfinding or final physical collision |
| Physical actor | Resolved movement through `CharacterBody3D.move_and_slide()` and a fitted capsule | Teleport through walls to catch up with stale simulation data |
| Animation | Pose and gait from resolved body velocity, facing, and actor state | Infer that a body is walking solely because a distant goal exists |
| LOD handoff | Transfer the same world position and intent between data, impostor, and embodied tiers | Reset a travelling actor to a stale target position on promotion/demotion |

The data row remains authoritative about **what the person intends**. While embodied, the physics body is authoritative about **where it actually is**. At a handoff, write the resolved actor position back to the simulation and preserve the destination identity. Promote close actors before they reach the player; keep distant records and impostors cheap.

## Godot 4.6 details that prevent false fixes

1. **Navigation does not move the actor.** `NavigationAgent3D` returns a route point. The actor script must move its parent. For a physical NPC, set `CharacterBody3D.velocity` and call `move_and_slide()` in `_physics_process`; do not use `global_position += direction * speed * delta` as a substitute.
2. **Advance the path in the physics loop.** While a route is active, call `get_next_path_position()` once each physics step and stop querying when `is_navigation_finished()` is true. Set a new target when the intent changes or a real re-path condition occurs, not every frame. Over-frequent target/path updates can make agents dance between points.
3. **Wait for map synchronization.** A path requested before navigation regions have synchronized may be empty. Defer the first target until after a physics frame or wait for the navigation map changed/synchronized signal. Do the same when streamed regions are attached.
4. **Avoidance is steering, not a wall collider.** When enabled, connect `velocity_computed`, submit wanted velocity, and move using the returned safe velocity. Avoidance only considers participating agents/obstacles in its avoidance simulation; it does not alter the path and it has no knowledge of physics collision.
5. **Navigation obstacles do not carve routes.** Godot's `NavigationObstacle3D` affects avoidance. Static geometry that should change the route must be represented in the baked/updated navigation mesh. The actor capsule still needs physics collision so small path/bake errors do not permit penetration.
6. **Bake the walkable world deliberately.** Use the same approved static collision intent as the building profiles: walls and foundations excluded from the walk mesh; usable streets, yards, and doorway approaches included. Do not infer walkable interiors from a render mesh or put a nav polygon across a visually open door that a collider seals.
7. **Match navigation tolerances to the actor.** Set avoidance radius/height, path desired distance, target desired distance, max speed, and prediction horizon for the body size and speed. Too-small desired distances can make a fast actor overshoot a waypoint and backtrack; excessively large avoidance horizons can make crowds slow down too early.
8. **Design for failures.** A disconnected chunk, target outside the navmesh, occupied service point, or jammed doorway needs a defined response: wait briefly, validate an alternate approach point, retry after a relevant world change, then expose a stuck state for QA. Do not fall back to straight-line movement through the obstacle.

These details follow the Godot 4.6 [3D navigation overview](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_introduction_3d.html), [NavigationAgent guide](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationagents.html), [obstacle guide](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationobstacles.html), and [navigation debug tools](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_debug_tools.html). The overview explicitly separates `NavigationAgent3D` path assistance from actor movement and says avoidance obstacles do not affect pathfinding. The detailed guide specifies physics-frame path advancement, avoidance callbacks, synchronization, and common overshoot/repath problems.

## Recommended build sequence

1. **Keep the fitted collision profile as the source of truth.** Finish player doorway/corner/cart checks for a small representative asset set. The existing collision audits identify where single-box building proxies disagree with doors and facades.
2. **Bake and inspect one test nav region.** Use one Ashford block with one closed wall, one verified open entrance, one stall row, and a destination on the far side. The nav debug view must show a continuous safe path that uses the entrance/road instead of the wall interior.
3. **Convert one near villager.** Give only this prototype a capsule body and physics movement owner. Its simulated goal is an anchor; its visible transform is never overwritten by the row during the trip. Compare direct target and routed target in the same capture.
4. **Exercise contact and yielding.** Add capped local avoidance for actors that can actually meet. Keep the capsule active. Run head-on, following, player approaches, queues, and narrow door cases. Use deterministic side preference/priority and an escalation from slow → wait → reachable sidestep → re-path.
5. **Handle transitions.** Promote/demote an actor mid-route, stream its next navigation region, and change its target while moving. Log actor ID, LOD tier, simulation position, body position, goal ID, path state, desired/safe/resolved velocity, capsule, avoidance radius, and animation speed.
6. **Reuse the validated movement owner.** Apply it to other near NPCs and animals according to their gameplay needs. Hostile chase/flee needs target refresh and encounter behavior; grazing wildlife can use a cheap home-area route. Keep distant actors inexpensive.
7. **Profile and review.** Compare repeated LOW/HIGH captures with identical route and crowd setup. Track frame-time p50/p95, body count, active avoidance count, path requests, stuck recoveries, wall contacts, and visual gait. Use Claude's current animation QA for clip/stride calibration rather than creating a competing asset retarget pass.

## Review links

- [Interactive NPC route audit](NPC_ROUTE_AUDIT.html) — exact static Ashford segments crossing fitted collider footprints.
- [Collision visual audit](COLLISION_VISUAL_AUDIT.html) and [facade review](COLLISION_FACADE_REVIEW.html) — collision proxy fit and entrances.
- [Current playtest visual review](CURRENT_RUN_VISUAL_REVIEW.md) — what the saved market screenshot proves, and the moving captures still needed.
- [Natural world plan](NATURAL_WORLD_FEEL_PLAN.md) — full phased plan and acceptance list.
- [Open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md) — architecture references, license caveats, and why there is no drop-in retired AAA world to import.
