# Living-world systems and presentation integration

**Purpose:** coordinate Codex-owned simulation/action systems with Claude-owned game presentation, animation, models, scenes and active gameplay files. This is an additive integration contract. It does not replace `WorldSim`, `Villager`, `UtilityBrain`, `StreetGraph`, `PopulationLOD`, `Station`, crafting, or Claude's animation work.

## Current source map

The latest published Claude snapshot inspected for this handoff is `d163255f`.

| Responsibility | Current owner/source | Integration rule |
|---|---|---|
| Population rows, schedule clock, distant movement | `kingdom/autoload/world_sim.gd` | Remains authoritative for unembodied residents; never create one Node per distant person. |
| Near bodies, movement and resolved collision | `kingdom/scripts/population/villager.gd` | `Villager` remains the only movement/physics owner while embodied. It is a `CharacterBody3D`, routes via `StreetGraph`, and writes the physical result back through the current population flow. |
| Near behavior and needs | `kingdom/scripts/population/utility_brain.gd` | Keep cognition on staggered decision ticks and reuse existing need state; don't create a second always-on brain. |
| Embodiment and animation/physics budgets | `kingdom/scripts/population/population_lod.gd` | Preserve the existing caps and handoff rules. A new action must survive promotion/demotion without duplicate movers or leases. |
| Player actions, crafting and transient action tokens | `kingdom/scripts/systems/action_runtime.gd`, `kingdom/scripts/sim/crafting.gd` | Reuse the existing validation/commit path for real effects. A visual activity animation must never award a second effect. |
| Physical NPC stations and persistent station identity | `kingdom/scripts/world/work_spots.gd`, `kingdom/scripts/world/station.gd` | Audit and adapt these before introducing another station registry. |
| Experimental activity definitions/sessions and demo actor | `kingdom/scripts/living_world/smart_objects.gd`, `life_actor.gd`, `kingdom/tools_qa/living_world/` | Reference implementation only. The gameplay population does not currently call this API. `LifeActor` moves directly and is not a replacement for `Villager` physics. |
| Animation clips, props, contact points and scene wiring | Claude | Systems may request a named clip/marker/socket contract; do not edit or replace the active animation, model, scene or project wiring without coordination. |

`rg` over the current snapshot found `SmartObjects` construction and session use in the living-world QA demo only. No `WorldSim`, `Villager`, `PopulationLOD`, crafting or production-world caller was found. Therefore the demo is not evidence of live-game integration.

## Changes in this handoff branch

`SmartObjects` now keeps a person's currently held matching slot eligible and gives it a small selection hysteresis. Reclaiming the same slot is idempotent, so repeated data-tier target refreshes neither walk the resident around a queue nor invalidate its active session token. Each new claim receives a monotonically increasing runtime token. A stale `Session` detects replacement and stops emitting activity clips/events; completion releases only the claim token it owns, so an old session cannot release a newer claim for the same person index.

Alignment now has a bounded failure path: if the body does not reach the authored stand point within 1.5 seconds, the session releases its own claim and ends. It does not enter the contact animation and snap from a visibly incorrect location. This is a reference-layer safety fix; it does not wire smart objects into gameplay.

No runtime or device validation is claimed in this handoff.

## Non-negotiable integration invariants

1. **One identity mapping.** `WorldSim` person indices are array positions, not universal NPC identity. Use a domain-prefixed actor reference at system boundaries and explicitly map it to a persistent identity only where the current save model supports that mapping. Never use a slot array index as a persisted station ID.
2. **One movement owner.** While embodied, `Villager` owns approach, route following, collision, floor height and resolved position. `WorldSim` owns the coarse target. Smart-object code returns an intent/stand target; it must not move a second actor or write directly over a live body's position.
3. **One reservation authority.** Extend `ActionRuntime` or adapt the existing station/work-spot owner. Do not independently reserve the same station in `ActionRuntime`, `SmartObjects`, and `Station`. A visual occupancy mirror can read the authoritative lease but cannot create another lease.
4. **One effect commit.** Needs, inventory, wages, crafting, mastery, crime, events and relationship effects happen only through an idempotent domain commit after prerequisites are rechecked. Animation loop/cycle markers are presentation cues, not permission to grant repeated resources.
5. **A complete interruption path.** Define who owns the lease through approach, entry, work, exit, save/load, death, despawn, time skip and LOD transfer. A slot becomes available only when its authoritative lease is released; a visual exit clip may continue after gameplay cancellation without retaining a stale effect token.
6. **Budgeted work.** Keep near cognition staggered and distant simulation data-only. Bound route queries, candidate searches, ray tests, body counts, catch-up work and per-frame event handling. Add counters before increasing caps.

## Important integration hazards found

- `SmartObjects.populate_settlement()` generates transient sequential spot IDs. Those IDs depend on population order and must not be serialized or used as long-lived resource keys. Introduce a stable key from settlement identity, lot/landmark identity, activity type and authored ordinal before persisting ownership or saved schedules.
- The chance filter in `populate_settlement()` is derived from a hash of position and type. Keep generated placements deterministic, but do not mistake determinism for a collision-free unique identity.
- `LifeActor._end_session()` calls `interrupt()`, then releases the person and clears the session immediately. That bypasses its modeled exit phase. Correct this when the reference actor gets a proper deferred-command/interruption API; do not copy this helper into `Villager` integration.
- The demo `LifeActor` is a `Node3D` that translates its transform directly. Gameplay actors require `CharacterBody3D`/`move_and_slide()` and the game's collision masks, or the known wall/building pass-through returns.
- `SmartObjects.target_for()` currently makes a transient soft claim while returning only a 2D point. Its caller must release or replace the claim when the schedule target changes, and the return value must still pass through the same routed movement/collision authority as other goals.
- `ActionRuntime` reserves actor/resource keys but currently has no proven binding to `Station`/work spots or a resident's near-body activity. The binding, stable key scheme, persistence/restore semantics and actor mapping remain unimplemented.

## Recommended first production slice

Use one **well-water chore** or one **blacksmith work order** as a deliberately narrow vertical slice. Before choosing, inspect current `WorkSpots`, `Station`, utility needs and crafting effects on Claude's current branch. Prefer the well if it can reuse the existing villager water need without changing player crafting or item semantics; prefer the smith only if its real material/output contract is already explicit.

1. Map the existing destination and activity data; write down the current owner and persistence boundary for every field touched.
2. Give the station a stable semantic identity and a slot key. Bind the action lease to that key and a domain-prefixed actor reference. Keep the current station system authoritative.
3. Let the existing utility choice request the action. The schedule/data tier gets a coarse semantic destination; an embodied villager gets the same destination through `StreetGraph` and its existing `CharacterBody3D` path.
4. Approach outside the contact point, slow and align with a bounded timeout, and retain collision. No direct transform snap through a wall or Meshy collider.
5. Claude supplies or confirms the enter/loop/exit clips, contact marker and hand/prop alignment. Systems advances phases but does not fabricate animation completion.
6. Commit the real need/work result exactly once after validation. A canceled or blocked approach has no effect. Keep existing player UI, crafting, mastery, wages and event signals intact.
7. Define promotion/demotion, interruption and save behavior. Active transient tokens are reconstructed or cancelled deliberately; never serialize an in-memory lease token as a permanent ownership fact.
8. Only then expand the same contract to market customers, laundry, cooking, prayer, social groups and guard posts.

## What Claude should review on pickup

- Read this file alongside `docs/SYSTEMS_MASTERPLAN.md` and `docs/SYSTEMS_CONTINUATION.md`.
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
