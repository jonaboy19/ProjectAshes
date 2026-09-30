# NPC well activity: production slice contract

**Status:** implementation brief for the next coordinated systems change. The current branch does not implement this behavior.

## Why this is the first slice

The near NPC stack already has a `WATER` utility action, a persistent water need, a generated well landmark, a route graph that deliberately loops around the well, and water-gathering animation candidates. That makes a water-fetch visit the smallest real-world activity that can exercise selection, movement, contact, crowd capacity, animation, interruption and LOD without inventing a new inventory or production system.

It must reuse the live NPC stack. `UtilityBrain` chooses the need; `Villager` owns its route, collision, facing and animation; `WorldSim` owns coarse resident data and schedule; `ActionRuntime` can provide a short-lived reservation. `LifeActor` and `SmartObjects` remain QA/reference-only. Do not create another per-person node, brain, movement loop, need store, or station registry.

## Current behavior and gaps

- `UtilityBrain.plan_goal(Act.WATER, ...)` derives a well point from the settlement plan, then chooses an offset around it. The offset has no capacity claim or stable slot identity.
- `Villager` follows the goal through `StreetGraph`; its movement and collision remain authoritative. When it arrives, the existing activity selector may play a water-related clip, but no station-use phase begins and no queue/occupancy is represented.
- `UtilityBrain.tick()` restores water while `Act.WATER` is considered performed. This is a continuous need effect, not an idempotent work-cycle commit.
- `StreetGraph` already routes around the plaza well. Keep that obstacle and its collider/stand clearance; never solve an approach by snapping the NPC to the landmark center.
- `WorldSim` person indices are deterministic row handles for this generated world, not a general persistent actor-ID contract. Settlement IDs and world seed/version assumptions must be stated at the lease boundary.
- `ActionRuntime` supports atomic transient resource reservations and expiry, but has no lease renewal. A long-lived claim must either use bounded short work sessions or add a reviewed renewal contract; do not hold an unbounded claim.

## Proposed flow

1. The existing utility scorer chooses `WATER`. No new scorer or per-frame decision is added.
2. Resolve a well site from the current settlement's generated `landmarks` entry with asset `well`. If no well exists, choose a valid plaza fallback and label the behavior as a brief thirst break; never return `Vector2.INF` or assume a missing landmark exists.
3. Assign one of a small number of approach slots around the well. Derive slots from the generated site's stable identity and an explicit ordinal, then run each candidate through the existing settlement-route clearance helper. The slot center must be outside the well collider and face the use point.
4. Let `Villager` route to the selected approach slot using its existing movement. Acquire capacity before committing to the approach or use a short queue intent that is not a physical lease; if the lease is acquired early, release it on route failure, timeout, act change, interruption, demotion, reset and teardown.
5. Start the station-use phase only after the body is within the small authored contact tolerance, nearly stopped, and its facing is aligned. The marker/stand point is the source of truth; do not teleport or disable collision.
6. Use a named animation contract supplied by Claude (suggested semantic names: `water_fetch_enter`, `water_fetch_loop`, `water_fetch_exit`, or a documented existing clip mapping). Systems code requests phases; it does not edit rigs/scenes or treat an animation cycle as permission for an unrelated reward.
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

## Acceptance and pickup

- Two residents can use different slots and cannot occupy the same slot; a third resident waits, selects another valid stand point, or chooses a different act without jittering every decision tick.
- Every approach follows the existing route and cannot pass through the well, buildings or other colliders. Arrival is slow and aligned; blocked access times out without snapping.
- Changing to an urgent act, despawning, saving/loading, resetting or crossing the LOD boundary releases exactly the lease held by that body. Repeated cleanup is harmless.
- Water rises only during valid use; waiting, blocked movement, a dropped lease, an exit clip or an animation loop alone does not restore it.
- Promotion/demotion does not duplicate the brain or movement owner. Needs retain their saved values and age; the activity token is reconstructed from current state.
- Inspect the current Claude head and dirty files before implementation. Claude confirms the clip/marker/collider contract; Codex systems work owns the additive intent/lease adapter. Do not implement this brief against a stale source snapshot if the live files have changed.
- Validate in the actual Godot project with at least two nearby residents, forced interruption, repeated promotion/demotion, save/load, and a low-tier mobile crowd before calling the slice accepted.

## Explicit non-goals

This slice does not create water items, change economy or crafting, add a generic behavior-tree framework, build a new global object registry, solve all town navigation, modify the well mesh/collider, or claim RDR2-scale intelligence. Once this bounded path is verified, the same contract can support prayer points and simple workstations without copying the brain or movement system.
