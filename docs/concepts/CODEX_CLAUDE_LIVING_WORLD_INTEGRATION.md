# Living-world systems and presentation integration

**Purpose:** coordinate Codex-owned simulation/action systems with Claude-owned game presentation, animation, models, scenes and active gameplay files. This is an additive integration contract. It does not replace `WorldSim`, `Villager`, `UtilityBrain`, `StreetGraph`, `PopulationLOD`, `Station`, crafting, or Claude's animation work.

## Current source map

**Current integration update — 1 October 2026:** the snapshot descriptions below are historical and predate the merge of Claude published head `ddfd3797`. Gameplay `Villager` now consumes `SmartObjects.Session` for accepted activities, while movement and collision remain Villager-owned. SIT/PLAY/CHORE activities remain available. Social pairing is owned by the reciprocal bounded UtilityBrain pair system; water continues through the single `ActionRuntime` lease. WorldSim persists five needs; the additional breath need is only active-body state, does not advance in offscreen catch-up, and is reseeded when the brain is recreated. See the top of `docs/SYSTEMS_CONTINUATION.md` for the current merged checkpoint.

The code integration baseline is the fetched remote Claude branch head `3177be61` (30 September 2026); this Codex branch also merges Claude's later docs-only commit `0ea3d579`. Earlier notes below distinguish source observations made against `d163255f`; recheck the actual PC checkout before applying anything because local changes may be newer.

| Responsibility | Current owner/source | Integration rule |
|---|---|---|
| Population rows, schedule clock, distant movement | `kingdom/autoload/world_sim.gd` | Remains authoritative for unembodied residents; never create one Node per distant person. An instance-tokened owner guard now pauses row movement while a body owns it. |
| Near bodies, movement and resolved collision | `kingdom/scripts/population/villager.gd` | `Villager` remains the only movement/physics owner while embodied. It is a `CharacterBody3D`, routes via `StreetGraph`, and publishes resolved position through the instance-tokened `WorldSim` handoff. |
| Near behavior and needs | `kingdom/scripts/population/utility_brain.gd` | Keep cognition on staggered decision ticks and reuse existing need state; don't create a second always-on brain. |
| Embodiment and animation/physics budgets | `kingdom/scripts/population/population_lod.gd` | Preserve the existing caps and handoff rules. A new action must survive promotion/demotion without duplicate movers or leases. |
| Player actions, crafting and transient action tokens | `kingdom/scripts/systems/action_runtime.gd`, `kingdom/scripts/sim/crafting.gd` | Reuse the existing validation/commit path for real effects. A visual activity animation must never award a second effect. |
| Brief embodied NPC activities | `kingdom/scripts/systems/npc_activity_runtime.gd`; `Life.action_runtime`; `Villager` | The well-water slice uses the shared action lease authority and existing near-body route/animation path. Keep tokens transient; do not add a parallel station or effect owner. |
| Crafting station identity and player occupancy | `kingdom/scripts/systems/station_identity.gd`, `kingdom/scripts/sim/crafting.gd`, `Life` | Exact generated station references and registration generations are used by player crafting. This is not a generic NPC `WorkSpots` bridge; don't add a second station registry. |
| Experimental activity definitions/sessions and demo actor | `kingdom/scripts/living_world/smart_objects.gd`, `life_actor.gd`, `kingdom/tools_qa/living_world/` | `SmartObjects.Session` is now consumed by the gameplay population for accepted activities. `LifeActor` remains QA/reference-only, moves directly and is not a replacement for `Villager` physics. |
| Animation clips, props, contact points and scene wiring | Claude | Systems may request a named clip/marker/socket contract; do not edit or replace the active animation, model, scene or project wiring without coordination. |

The 30 September source inventory below found `SmartObjects` session use in the living-world QA demo only. That statement is superseded by the 1 October integration update above: `Villager` now consumes accepted sessions. `LifeActor` remains QA/reference-only.

## Changes in this handoff branch

`SmartObjects` now keeps a person's currently held matching slot eligible and gives it a small selection hysteresis. Reclaiming the same slot is idempotent, so repeated data-tier target refreshes neither walk the resident around a queue nor invalidate its active session token. Each new claim receives a monotonically increasing runtime token. A stale `Session` detects replacement and stops emitting activity clips/events; completion releases only the claim token it owns, so an old session cannot release a newer claim for the same person index.

The live population position handoff now uses the owning body instance ID. `WorldSim` continues schedule changes and target selection but skips data-row movement while a `Villager` body owns that resident. Promotion, periodic resolved-position write-back and demotion pass through the same token check; reset/replacement bodies cannot be released or overwritten by stale queued cleanup. Time skips settle data-only residents immediately while embodied residents retain their resolved position and follow the updated target. Five utility needs plus their last simulated hour persist in packed world rows and save data; promotion catches them up in constant time. Offline activity restoration is not inferred, and activity leases still are not LOD-persistent.

The first live activity adapter now uses the existing `WATER` action. It provides up to two deterministic approach slots at a settlement well, with abstract plaza water-break points for generated settlements that have no well, and atomically reserves both the NPC actor channel and one source slot in `Life.action_runtime`. `Villager` routes with its existing body, starts the working phase only after arriving/stopping/facing, and gates the existing water-need recovery and animation on that phase. Interruption, time resync, demotion, restore and teardown release the token. Contended residents wait in place and retry on their staggered decision interval; there is no FIFO fairness guarantee. The 180-second lease, route/collider fit and two-user behavior still need real-game validation. Details and limitations are in [NPC_WELL_ACTIVITY_HANDOFF.md](NPC_WELL_ACTIVITY_HANDOFF.md).

Generated settlement placements now receive a semantic identity derived from settlement, placement kind/index/position, asset and authored activity ordinal. Their in-memory integer handles remain transient; `slot_resource_key()` exposes a stable key only for generated placements. Hand-placed QA demo spots intentionally return no persistent resource key. This is a starting identity contract for a fixed deterministic world plan, not yet a migration-safe ID across changes to `CityPlanner` ordering.

Alignment now has a bounded failure path: if the body does not reach the authored stand point within 1.5 seconds, the session releases its own claim and ends. It does not enter the contact animation and snap from a visibly incorrect location. `LifeActor` queues one replacement order through the old session's exit clip; actor removal releases the lease immediately because no animation can finish after despawn. The session layer is now connected to gameplay Villagers for accepted activities. Its slot claim remains the capacity owner for those activities; water uses the separate `ActionRuntime` lease, and no work/production effect is awarded by an animation session.

No runtime or device validation is claimed in this handoff.

## Non-negotiable integration invariants

1. **One identity mapping.** `WorldSim` person indices are array positions, not universal NPC identity. Use a domain-prefixed actor reference at system boundaries and explicitly map it to a persistent identity only where the current save model supports that mapping. Never use a slot array index as a persisted station ID.
2. **One movement owner.** While embodied, `Villager` owns approach, route following, collision, floor height and resolved position. `WorldSim` owns the coarse target. Smart-object code returns an intent/stand target; it must not move a second actor or write directly over a live body's position.
3. **One reservation authority.** Extend `ActionRuntime` or adapt the existing station/work-spot owner. Do not independently reserve the same station in `ActionRuntime`, `SmartObjects`, and `Station`. A visual occupancy mirror can read the authoritative lease but cannot create another lease.
4. **One effect commit.** Needs, inventory, wages, crafting, mastery, crime, events and relationship effects happen only through an idempotent domain commit after prerequisites are rechecked. Animation loop/cycle markers are presentation cues, not permission to grant repeated resources.
5. **A complete interruption path.** Define who owns the lease through approach, entry, work, exit, save/load, death, despawn, time skip and LOD transfer. A slot becomes available only when its authoritative lease is released; a visual exit clip may continue after gameplay cancellation without retaining a stale effect token.
6. **Budgeted work.** Keep near cognition staggered and distant simulation data-only. Bound route queries, candidate searches, ray tests, body counts, catch-up work and per-frame event handling. Add counters before increasing caps.

## Important integration hazards found

- `SmartObjects.populate_settlement()` still returns transient sequential spot indices for array lookup. Do not serialize those indices. Generated placements now expose a semantic key, but it depends on current settlement IDs and deterministic lot/landmark ordering; planner changes need explicit ID migration or a stronger authored placement identity before old saves depend on it.
- The chance filter in `populate_settlement()` is derived from a hash of position and type. Keep generated placements deterministic, but do not mistake determinism for a collision-free unique identity.
- The `LifeActor` deferred-command behavior is QA/reference-only. If this state machine is later wired into `Villager`, cancellation and leases must instead follow the authoritative gameplay action/station owner; do not copy the demo actor lifecycle wholesale.
- The demo `LifeActor` is a `Node3D` that translates its transform directly. Gameplay actors require `CharacterBody3D`/`move_and_slide()` and the game's collision masks, or the known wall/building pass-through returns.
- `SmartObjects.target_for()` currently makes a transient soft claim while returning only a 2D point. Its caller must release or replace the claim when the schedule target changes, and the return value must still pass through the same routed movement/collision authority as other goals.
- `ActionRuntime` is bound to the near-body well-water activity through a seed/settlement/slot key. Player crafting still uses its existing generation-qualified `Station` registry; there is no generic bridge to `WorkSpots`, service stations or arbitrary SmartObjects, and no persistent activity lease.
- The `WorldSim` position owner prevents concurrent data/body movement, and utility needs now persist across LOD promotion/demotion and save/load. Activity leases remain transient and do not yet survive LOD changes.

## First production slice: well-water

The Codex branch implements the narrow vertical slice using existing `WATER` need/action, generated well landmark, route loop and water-gathering clip candidates, with no item/economy output. Review the current diff against Claude's local work, then validate collision, two-slot contention, interruption and LOD/save continuity in the actual game before expanding to another activity. [NPC_WELL_ACTIVITY_HANDOFF.md](NPC_WELL_ACTIVITY_HANDOFF.md) records the implementation, identity caveats and acceptance conditions.

1. Recheck the branch against Claude's actual local source and collision work.
2. Capture two and three residents contending for the slots; measure arrival, separation, wait fairness and lease expiry.
3. Exercise yield, combat interruption, save/load, time skip, demotion and promotion; confirm each path releases one token and water only recovers while actually working.
4. Measure route queries, actor lease counts, physics time and frame-time on LOW mobile hardware before expanding the cap or adding a third slot.
5. Ask Claude to supply authored contact/enter/exit markers if the existing clip mapping does not align convincingly; do not alter Claude-owned rigs/scenes from this systems branch.
6. After acceptance, reuse this contract for prayer points or a simple workstation without duplicating movement, brain, lease or effect ownership.

## What Claude should review on pickup

- Read this file alongside `docs/SYSTEMS_MASTERPLAN.md` and `docs/SYSTEMS_CONTINUATION.md`.
- Read [NPC_WELL_ACTIVITY_HANDOFF.md](NPC_WELL_ACTIVITY_HANDOFF.md) before wiring the first NPC activity; it describes the verified published-source seam and does not claim implementation is already present.
- Confirm current branch head and active/dirty files before cherry-picking or merging. This work is based on published `d163255f`; local Claude changes may be newer and must remain untouched until committed or deliberately shared.
- Decide the first production slice and identify its authoritative station/slot owner.
- Supply clip names/markers and collision/approach constraints for that slice; Codex systems work should consume those contracts rather than modify the animation pipeline.
- Review `smart_objects.gd` claim-token changes as QA/reference code only; do not interpret them as gameplay wiring or as validated mobile performance.

## Acceptance for production wiring

- Two residents requesting one slot cannot both own it; repeated schedule refresh by one resident keeps its slot; a stale session cannot play or commit after lease replacement.
- Failure to reach the stand point releases cleanly without snapping, clipping, or granting effects.
- The player and nearby residents cannot pass through the station/building collider; the intended approach/door remains open.
- Promotion/demotion preserves one route owner and one action owner; urgent interruption releases capacity according to the shared contract.
- Save/load, time advance, despawn and repeated commit requests do not duplicate rewards or strand a slot.
- The representative settlement route is captured in the actual game, and low-tier mobile performance is measured before actor, route or sensor caps are raised.
