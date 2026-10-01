# NPC well activity: production slice contract

**Status:** implemented additively on the Codex PR branch as the first production activity slice; live-game/runtime validation is still pending. The current Codex branch also merges Claude published head `ddfd3797` and connects Villager to general `SmartObjects.Session` activities. This handoff remains specifically about water's separate `ActionRuntime` lease. The original implementation was based on Claude remote head `3177be61`.

## Why this is the first slice

The near NPC stack already has a `WATER` utility action, a persistent water need, a generated well landmark, a route graph that deliberately loops around the well, and water-gathering animation candidates. That makes a water-fetch visit the smallest real-world activity that can exercise selection, movement, contact, crowd capacity, animation, interruption and LOD without inventing a new inventory or production system.

It must reuse the live NPC stack. `UtilityBrain` chooses the need; `Villager` owns its route, collision, facing and animation; `WorldSim` owns coarse resident data and schedule; `ActionRuntime` provides water's short-lived reservation. Gameplay Villagers now also use `SmartObjects.Session` for accepted non-water activities; those sessions own only their activity-slot occupancy and presentation lifecycle. `LifeActor` remains QA/reference-only. Do not create another per-person node, brain, movement loop, need store, or station registry.

## Current behavior and gaps

- `UtilityBrain.plan_goal(Act.WATER, ...)` derives two deterministic approach candidates from the generated well and settles them through the existing street clearance helper. The generated water slots are cached per settlement. Plans without a well get an explicitly abstract plaza water-break fallback so thirst remains satisfiable; no visible vessel or item is created.
- `Villager` now reserves one slot plus its own actor channel through `Life.npc_activity_runtime` (backed by the shared `ActionRuntime`) before routing. The token is scoped to world seed, settlement row, source kind and person row; it expires after 180 real seconds.
- `Villager` keeps the existing `StreetGraph`, body collision, braking and facing owners. The reservation moves from `begun` to `working` only when the NPC has arrived, stopped close to its slot and faced the well. The existing water clip candidates play only in that working phase.
- `UtilityBrain.tick()` restores water only when the well lease is working at the use point. The activity produces no item, gold, XP, crafting or journal reward.
- Interruption, player-yield sidestep, act change, reset/time resync, save restore and body teardown release the exact token. Promotion recomputes from needs instead of restoring a transient lease.
- If both slots are occupied, a resident holds its current position and retries on its existing staggered decision tick. There is no explicit FIFO queue or fairness guarantee yet.
- `StreetGraph` already routes around the plaza well. Keep that obstacle and its collider/stand clearance; never solve an approach by snapping the NPC to the landmark center.
- `WorldSim` person indices are deterministic row handles for this generated world, not a general persistent actor-ID contract. Settlement IDs and world seed/version assumptions must be stated at the lease boundary.
- `ActionRuntime` supports atomic transient resource reservations and expiry, but has no lease renewal. A long-lived claim must either use bounded short work sessions or add a reviewed renewal contract; do not hold an unbounded claim.

## Implemented flow and remaining constraints

1. The existing utility scorer chooses `WATER`. No new scorer or per-frame decision is added.
2. Resolve a well site from the current settlement's generated `landmarks` entry with asset `well`. If no well exists, choose a valid plaza fallback and label the behavior as a brief thirst break; never return `Vector2.INF` or assume a missing landmark exists.
3. The current implementation assigns up to two slots derived from the generated well position and explicit ordinals. Identity keys use the deterministic world seed and settlement row; these are stable for the current generated plan, not guaranteed migration-safe across generator changes.
4. `Villager` atomically reserves its actor channel and selected well slot through the shared action runtime, then routes using its existing movement. A blocked route consumes a bounded lease and the lease expires if the actor cannot complete the approach.
5. Start the station-use phase only after the body is within the small authored contact tolerance, nearly stopped, and its facing is aligned. The marker/stand point is the source of truth; do not teleport or disable collision.
6. The current implementation uses existing water-related clip candidates (`G6_gathering`, `Chore_Pick_Up_Box`, `Interact`, `PickUp_Table`) without editing rigs/scenes. A future authored enter/loop/exit contract may replace this fallback after Claude confirms the markers.
7. Restore the existing water need only while the actor is genuinely at the use point and owns that slot. Keep the effect continuous and local to the need model; no item, gold, XP, crafting or journal reward is created by this slice.
8. On completion or interruption, blend to the authored exit/idle state while releasing the capacity lease exactly once. Urgent `FLEE`/`SHELTER`, player interaction, actor deletion and LOD demotion interrupt the activity. If the resident is promoted again, recompute intent from current needs rather than restoring a transient token.

## Identity and ownership rules

- Resource key format should be namespaced and deterministic, e.g. `world:<seed>:settlement:<sid>:well:<landmark_id>:slot:<ordinal>`. Confirm the site's actual stable `id`; do not derive a save identity from array position unless the world-plan version is part of the identity contract.
- Actor reference should be explicitly NPC-scoped, e.g. `npc-row:<world_id>:<person_index>`, and must not collide with `player` or another system's actor keys.
- Store the ActionRuntime token only on the active embodied `Villager`. It is transient, must never enter a save, and may never authorize an effect after expiry/replacement.
- A different NPC cannot own the same resource key concurrently. A resident cannot reserve several well slots while rerouting. Release compares the exact token so stale cleanup cannot unlock a successor.
- Keep station discovery/identity (`Crafting` / `station_identity`) separate from this generated outdoor activity unless the existing code owner confirms the well belongs in that registry. Player crafting stations and NPC chore capacity solve different questions.
- Exactly one authority owns movement, capacity and need effect respectively. `WorldSim` never writes an embodied body's position; a visual occupancy indicator never creates a lease.

## Mobile budget

- Keep cognition on existing staggered decision intervals. Do not add a per-frame world scan, raycast or timer per resident.
- Resolve and cache the settlement well descriptor once per resident or per settlement generation; invalidate it only when world generation changes.
- Bound the number of approach slots and simultaneous embodied leases. Distant residents remain data-only and should not create activity sessions.
- Add small counters for lease conflicts, approach timeouts and active well users before changing body/physics budgets. Do not raise `MAX_FULL` or `MAX_PHYSICS_CONTACT` for this feature.

## Acceptance still required

- Two residents can hold different slots and cannot reserve the same slot; a third resident holds position and retries at the existing decision cadence. Validate that this does not cause starvation or crowding.
- Every approach follows the existing route and cannot pass through the well, buildings or other colliders. Arrival is slow and aligned; blocked access expires without snapping.
- Changing to an urgent act, despawning, saving/loading, resetting or crossing the LOD boundary releases exactly the lease held by that body. Repeated cleanup is harmless.
- Water rises only during valid use; waiting, blocked movement, a dropped lease, an exit clip or an animation loop alone does not restore it.
- Promotion/demotion does not duplicate the brain or movement owner. Needs retain their saved values and age; the activity token is reconstructed from current state.
- Inspect the current Claude head and dirty files before implementation. Claude confirms the clip/marker/collider contract; Codex systems work owns the additive intent/lease adapter. Do not implement this brief against a stale source snapshot if the live files have changed.
- Validate in the actual Godot project with at least three nearby residents, forced interruption, repeated promotion/demotion, save/load, well/building collision, and a low-tier mobile crowd before calling the slice accepted.

## Explicit non-goals

This slice does not create water items, change economy or crafting, add a generic behavior-tree framework, build a new global object registry, solve all town navigation, modify the well mesh/collider, or claim RDR2-scale intelligence. Once this bounded path is verified, the same contract can support prayer points and simple workstations without copying the brain or movement system.
