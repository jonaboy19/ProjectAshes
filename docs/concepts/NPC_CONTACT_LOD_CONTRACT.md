# NPC contact and LOD movement contract

Implementation handoff for Claude. The original audit was at `e3563fc4`; substantial movement and ownership work has since landed on `gpt/living-world-integration`. Re-read current `PopulationLOD`, `Villager`, `WorldSim`, the player collision mask and streamed building colliders before implementation. Current behavior below is source-verified, not runtime-validated.

## Current implementation and remaining contact gap

`PopulationLOD.refresh()` runs every 0.25 seconds, selects embodied residents from the 45 m region under quality limits, can fast-track the closest 9 m residents up to its near cap, and creates at most three bodies per refresh. `Villager` is now a `CharacterBody3D` with a capsule. It turns that capsule on within 14 m of the player and leaves it enabled until beyond 17 m. Villagers are on collision layer 2 and collide with world layer 1; the player mask includes layers 1, 2 and 4.

- `physics_active` is a separate cap: at most the nearest eight embodied villagers are selected. When one is in player contact range, it uses `move_and_slide()` to resolve world collision. Other embodied villagers, and selected villagers outside contact range, use direct kinematic transforms. Their `StreetGraph` route and local steering are expected to avoid obstacles; direct movement has no final physics collision check.
- Villager capsules do not collide with other villager capsules: their mask is world layer 1, not actor layer 2. Crowd spacing is steering-based. The player's capsule does collide with enabled villager capsules.
- The body ownership handoff is implemented with a `WorldSim` instance token, resolved-position write-back and time-skip preservation. It does not preserve velocity, route cursor or a migration-safe goal ID; schedule and route intent are reconstructed.
- The highest-priority remaining question is whether a non-physics-active embodied villager, or a missing/inaccurate `StreetGraph` obstacle, can move through a streamed building's actual collider. Source review does not prove that the reported Meshy pass-through reproduces on current content.
- If more than eight physical movers approach the player, measure wall blocking, sprint contact, crowd intersection and frame cost before changing the cap. Do not add invisible proxies or raise the cap based on desktop intuition.

The earlier life-loop proposal below remains useful for overflow handling and acceptance, but predates the current body and position-owner implementation.

## Separate presentation from contact eligibility

Keep expensive skeletons and full models capped. Define a contact zone around the player and other gameplay-relevant actors separately from the render budget. Every resident visibly occupying that zone needs a physical representation with a stable person ID and consistent position, or must remain outside the zone through a reachable crowd-density policy.

If the eight-body physics selection still permits visible pass-through, compare two measured fixes: inexpensive world-only collision checks for every embodied actor inside the contact radius, or a reachable density policy that holds overflow outside the immediate zone. Any proxy must correspond to a visible person at the same resolved position; never add invisible blockers or let a sprite move independently through its own proxy.

Choose the contact activation margin using player/actor speed, worst measured activation delay, body radius, and stopping distance. Promote contact before the player can reach the resident. Repeatedly test approach at sprint speed, not only a stationary crowd. Include doorway and queue occupancy in density handling so an overloaded market cannot trap the player.

## One movement owner for each person

| Representation | Movement owner | Simulation responsibility |
|---|---|---|
| Distant data | `WorldSim` row step | Schedule, phase, coarse target and approximate position; movement is straight-line toward the target |
| Visible sprite outside contact | `WorldSim` row step | MultiMesh reads the coarse position and target heading; `PopulationLOD` may push the rendered point out of a nearby footprint, but does not route the trip |
| Embodied villager, physics active or direct-steer fallback | Villager body | Schedule and goal intent; `WorldSim` skips row integration and receives resolved position |
| Indoor embodied actor | `Villager` body until its planned indoor arrival, then hidden | Schedule remains in `WorldSim`; indoor occupancy is still abstract and has no full room simulation |

If a lighter contact representation is proposed later, keep the same person identity and resolved position. Contact removal and transfer back to coarse movement are separate operations. Never free the body merely because its model lost a distance-ranking slot while it still touches the player or occupies an interaction anchor.

## Transfer at a physics boundary

Use an explicit handoff record: person ID, ownership generation, position, resolved velocity, heading, goal ID/version, route cursor, activity/anchor reservation, and last integration time. The generation distinguishes stale queued callbacks from the current owner.

Promotion sequence:

1. Mark the row as pending physical ownership and stop its coarse position integration. Schedule/goal decisions may continue.
2. Obtain a route-valid, non-overlapping placement near its last stored position. Being on a `StreetGraph` waypoint does not prove that a capsule fits. If placement fails, keep the actor pending at a valid waiting point; do not silently teleport through the wall.
3. Initialize the body and presentation from the same handoff record at a physics boundary. Transfer ownership once and start resolved-velocity animation input.
4. Publish the body position for population queries and sprite/model visibility. Exclude that person from duplicate sprite rendering.

Demotion sequence:

1. Require the actor to leave the contact zone plus an exit margin for a short hold period. Defer demotion during dialogue, attack, doorway occupancy, or player contact.
2. At a physics boundary, store its final position, velocity/heading, goal version, route cursor, reservation status, and timestamp.
3. Resume coarse integration from that record without applying elapsed time already integrated by the body. Clear or transfer reservations deliberately.
4. Disable the body and switch presentation coherently. Reject pending path/avoidance callbacks from its old ownership generation.

`WorldSim.is_indoors()` still uses data-position proximity to the current target, while embodied `Villager` hides after its planned indoor goal is reached. Audit callers around schedule changes so a changed target cannot hide or move a body through a portal before physical arrival. Apply the same ownership rules to sleep, load, fast travel, and settlement unload: inspect any bulk `pos = target` operation so it cannot advance a still-visible physical actor through a building.

## Required review before expanding the population

Capture a stable crowd of 6, 12, 13, and 24 residents at LOW and HIGH, then approach at walk and sprint speed. Log each person's render tier, contact tier, owner/generation, spawn wait, body position, simulation position, goal version, and resolved velocity. Show the physical capsules and retain a paired normal camera capture.

Acceptance requires no close visible ghost person, no invisible blocking proxy, no duplicate person, no ownership-induced snap, and no extra simulation integration while a body owns motion. Include budget-boundary shuffling, promotion while the destination is behind a wall, schedule change during promotion, load/fast travel, and demotion while the player is touching the resident. Compare frame-time p50/p95 and active body/model/avoidance counts on the same quiet-machine route.

Related handoffs: [life loop](NPC_LIFE_LOOP_DESIGN.md), [motion pipeline](NPC_MOTION_PIPELINE_REVIEW.html), [follower/gait inspector](NPC_FOLLOWER_ANIMATION_REVIEW.html), and [Godot navigation notes](NPC_NAVIGATION_GODOT46_NOTES.md). This contract specifies an implementation proposal and source-derived risks; live captures are still required to confirm behavior and cost.
