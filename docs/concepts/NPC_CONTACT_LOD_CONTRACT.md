# NPC contact and LOD movement contract

Implementation and review handoff for Claude. The original proposal below was written against `e3563fc4`; source has since changed substantially. The dated current-state section supersedes any conflicting source claims below. Refresh `PopulationLOD`, `Villager`, and `WorldSim` before applying any remaining proposal.

## Current implementation snapshot (2026-09-30)

`PopulationLOD.refresh()` runs every 0.25 seconds. It selects full models within 45 m subject to the `Quality` budget, permits a 9 m near override up to 12 total models, caps normal full models at 24, and spawns at most three new models per refresh. Sprites are within 220 m with a combined ceiling of 140, narrowed by `Quality`. A non-full resident closer than 20 m is suppressed rather than rendered as a close flat sprite.

- A full model is a `Villager` `CharacterBody3D` with a capsule enabled inside a 14 m contact radius and disabled again after 17 m. It is on the local-actor layer, and its mask includes world geometry. The player's mask includes the local-actor layer.
- The nearest eight full models are allowed to use `move_and_slide()` while in contact range. Other embodied residents retain steering and animation but use direct kinematic movement; NPC-to-NPC spacing is steering, not universal capsule resolution. Confirm contact behavior in-game at crowd budget boundaries.
- Near villagers route over `StreetGraph` using settlement roads, door paths, and fitted lot footprints. The route is stored on the body and recomputed when needed; it is not a `NavigationAgent3D` route shared with data-only residents.
- `WorldSim._step()` still owns schedules, wages, and market transactions for everyone. Its external-position-owner instance token skips data-position integration while either an embodied `Villager` or a temporarily routed sprite owns movement. Releases are accepted only from the current token, so delayed `_exit_tree()` calls from replaced bodies cannot overwrite a newer sprite/body owner. Bodies transfer resolved position on writeback/removal; selected sprites within their home settlement use a capped `StreetGraph` route when the direct segment is blocked. The graph includes settlement buildings/stalls and now synchronizes the actual plaza-cart placements after settlement dressing is built. A time skip drops temporary sprite routes without overwriting the explicit time-skip destinations and asks embodied bodies to resync.
- Sprite routes exist only while the sprite is selected for display and near its home settlement. Data-only residents, field/forest travel beyond that local graph, and routes that fail validation still use the cheaper direct mover. The route cursor is presentation-LOD state, not persistent citizen state.

The 9 m override is not an absolute maximum model count on HIGH; it supplements the quality-limited 45 m selection only while the total stays under 12. The current three-spawn-per-refresh limit gives a nominal batch delay when several residents suddenly need models; measure actual latency instead of assuming it is exactly one second. Far-sprite route planning shares `StreetGraph`'s two-route-per-physics-frame budget with embodied route requests; unplanned blocked sprites wait at their current safe point. The original claims below that full models have no body collision and no near-body hysteresis are obsolete.

## Historical contract proposal (some source claims are obsolete)

`PopulationLOD.refresh()` runs every 0.25 seconds. It selects full models within 45 m up to the quality budget, allows a near override within 9 m while the selected count is below 12, and creates at most three new models per refresh. The normal budget can still select up to 24 models; 12 is the near override limit, not an absolute limit on HIGH. Remaining residents become sprites.

Consequences to capture in game:

- A LOW crowd with more than 12 close residents can retain close sprites despite the source comment saying they should never be sprites there.
- Selecting 12 new residents requires four refreshes at the current spawn budget. This is a nominal roughly one-second batch window, not a guarantee of measured latency; frame time and refresh phase affect it.
- Ranking solely by current distance can repeatedly replace residents near the budget boundary. There is no explicit promotion/demotion distance hysteresis in this selection.
- Current full models have no physics body, so being selected as full does not currently grant contact. Adding capsules only to full models would still leave the overflow case unresolved.

The earlier life-loop plan's capped near-body tier therefore needs the following explicit contract.

## Separate presentation from contact eligibility

Keep expensive skeletons and full models capped. Define a contact zone around the player and other gameplay-relevant actors separately from the render budget. Every resident visibly occupying that zone needs a physical representation with a stable person ID and consistent position, or must remain outside the zone through a reachable crowd-density policy.

Prototype lightweight body proxies for contact-eligible residents whose skeleton/model slot is unavailable. A proxy must correspond to a visible person and share its resolved position; avoid invisible blocking capsules and visible sprites that continue moving through their own proxy. If a sprite at arm's length remains visually unacceptable, reserve full-model capacity for the closest contact actors and keep excess arrivals at reachable waiting anchors outside the immediate zone. A hard proxy budget also requires a density/queue fallback; another cap alone does not guarantee contact.

Choose the contact activation margin using player/actor speed, worst measured activation delay, body radius, and stopping distance. Promote contact before the player can reach the resident. Repeatedly test approach at sprint speed, not only a stationary crowd. Include doorway and queue occupancy in density handling so an overloaded market cannot trap the player.

## One movement owner for each person

| Representation | Movement owner | Simulation responsibility |
|---|---|---|
| Distant data | Coarse route simulation | Schedule, goal, route cursor, position |
| Visible sprite outside contact | Coarse route simulation | Route-constrained position and heading; presentation reads samples |
| Contact proxy or full near body | Physics actor | Schedule and goal intent; read back resolved position without integrating it again |
| Indoor abstract actor | Indoor/activity simulation after verified portal arrival | Occupancy, schedule, activity, and valid exit anchor |

Changing full model to proxy is a presentation change; keep the same body and person identity where possible. Contact removal and transfer back to coarse movement are separate operations. Never free the body merely because its model lost a distance-ranking slot while it still touches the player or occupies an interaction anchor.

## Transfer at a physics boundary

Use an explicit handoff record: person ID, ownership generation, position, resolved velocity, heading, goal ID/version, route cursor, activity/anchor reservation, and last integration time. The generation distinguishes stale queued callbacks from the current owner.

Promotion sequence:

1. Mark the row as pending physical ownership and stop its coarse position integration. Schedule/goal decisions may continue.
2. Obtain a route-valid, non-overlapping placement near its last stored position. Being on a navmesh does not prove that a capsule fits. If placement fails, keep the actor pending at a valid waiting point; do not silently teleport through the wall.
3. Initialize the body and presentation from the same handoff record at a physics boundary. Transfer ownership once and start resolved-velocity animation input.
4. Publish the body position for population queries and sprite/model visibility. Exclude that person from duplicate sprite rendering.

Demotion sequence:

1. Require the actor to leave the contact zone plus an exit margin for a short hold period. Defer demotion during dialogue, attack, doorway occupancy, or player contact.
2. At a physics boundary, store its final position, velocity/heading, goal version, route cursor, reservation status, and timestamp.
3. Resume coarse integration from that record without applying elapsed time already integrated by the body. Clear or transfer reservations deliberately.
4. Disable the body and switch presentation coherently. Reject pending path/avoidance callbacks from its old ownership generation.

`WorldSim.is_indoors()` currently derives hidden state from proximity to a target. It must not hide an embodied resident merely because its schedule target was replaced. Use verified portal/activity arrival for the physical tier. Apply the same ownership rules to sleep, load, fast travel, and settlement unload: inspect any bulk `pos = target` operation so it cannot advance a still-visible physical actor through a building.

## Required review before expanding the population

Capture a stable crowd of 6, 12, 13, and 24 residents at LOW and HIGH, then approach at walk and sprint speed. Log each person's render tier, contact tier, owner/generation, spawn wait, body position, simulation position, goal version, and resolved velocity. Show the physical capsules and retain a paired normal camera capture.

Acceptance requires no close visible ghost person, no invisible blocking proxy, no duplicate person, no ownership-induced snap, and no extra simulation integration while a body owns motion. Include budget-boundary shuffling, promotion while the destination is behind a wall, schedule change during promotion, load/fast travel, and demotion while the player is touching the resident. Compare frame-time p50/p95 and active body/model/avoidance counts on the same quiet-machine route.

Related handoffs: [life loop](NPC_LIFE_LOOP_DESIGN.md), [motion pipeline](NPC_MOTION_PIPELINE_REVIEW.html), [follower/gait inspector](NPC_FOLLOWER_ANIMATION_REVIEW.html), and [Godot navigation notes](NPC_NAVIGATION_GODOT46_NOTES.md). This contract specifies an implementation proposal and source-derived risks; live captures are still required to confirm behavior and cost.
