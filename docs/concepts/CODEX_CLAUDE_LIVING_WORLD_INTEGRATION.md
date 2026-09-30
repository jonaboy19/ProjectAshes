# Codex ↔ Claude living-world integration handoff

**Checked:** 2026-09-30  
**Codex systems source:** `gpt/locomotion-jump-integration` at `451edb64` (plus the bounded systems commits in its ancestry).  
**Latest Claude source observed:** `origin/claude/focused-curie-m09hbd` at `d163255f`, including `09febe67` (`Living world: crowd tech ... smart objects ...`).  
**Status:** source review and integration contract only. The branches were not merged in this handoff, and none of the new living-world demos are claimed to be integrated into the playable main scene.

This note keeps the systems work and Claude's new living-world work compatible. It is intentionally additive: preserve current `WorldSim`, `PopulationLOD`, `Villager`, `Life`, `Crafting`, `Station`, and save ownership. Reconcile interfaces at one narrow gameplay integration point instead of introducing a second owner for state already represented elsewhere.

## What each branch currently owns

| Concern | Codex systems branch | Latest Claude branch | Integration rule |
|---|---|---|---|
| Nearby resident identity and motion | `WorldSim` rows plus body-owned resolved movement; `PopulationLOD` transfers the owner; `StreetGraph` bounds near routes and route requests | `LifeActor` is a worked example with routine/session behavior and a separate light movement loop | Keep `Villager`/`WorldSim` authoritative in gameplay. Port behavior behind the existing villager controller; do not spawn a second actor for the same person. |
| Activity spots | `Crafting.station_identity` gives craft stations stable references, registration generations, and exact-station leases through `ActionRuntime` | `SmartObjects` gives typed spots, slots, stand/approach transforms, activity clips and `Session` phases | Converge on one claim/lease owner. `SmartObjects` may own activity selection and presentation data; exact effect commits must use the validated Codex action lease or a single equivalent shared lease, never parallel reservations. |
| Persistent facts | `WorldEventLog` in `Life` is bounded, saveable and cursor-readable; the optional `RegionEventBridge` adapts region module signals | `LivingEvents` is short-range transient sensory stimulus | Keep the distinction: nearby stimulus can prompt perception; it does not become a persistent fact or universal NPC knowledge unless a witness/knowledge rule records it. |
| Animation and props | Codex handoff leaves rig, animation, sockets and presentation with Claude | `LifeLibrary`, `LifeProps`, grip sidecars, crowd animation LOD, ambience and clips | Claude owns assets/clips/presentation. Systems supply the actor's activity intent, stable identity, interruption reason and one-time effect event. |
| Needs and saves | NPC needs persist across body LOD and save/load; unembodied rows advance in the existing time-sliced visit | Demo actor behavior and spot sessions | A visible activity can inform the existing brain, but only one owner advances needs and only the authoritative simulation/save owner persists them. |

The demo is useful as a reference for behavior and clip contracts. Its `LifeActor` directly moves its `Node3D` and may settle onto a spot transform; that is suitable for a demo, not proof of collision-safe gameplay integration. The existing player/NPC collision and `StreetGraph` routing still need to own the live actor's approach.

## Shared identity and lease contract

Use namespaced actor references at module boundaries. A bare integer is ambiguous because the active `WorldSim` resident row, `life_courses.people`, player, region modules and other registries do not share one ID space. Suggested forms: `worldsim:<row>`, `lifecourse:<id>`, `player:main`, and `region1:<module>:<id>`.

Give a smart-object slot a layout-derived stable reference, not its current array position. For generated settlement fixtures, derive it from settlement identity, building/lot identity, object type and slot. For a site object, use site ID, part index, type and slot. A generator/layout version should be included or migrated if those identities can be reassigned. Runtime spot indices remain convenient handles, but are not save identities.

A live claim needs `{actor_ref, object_ref, slot, generation, expires_at}`. Claim/renew/release must compare the generation so a deferred exit or stale session cannot release the next user's slot. `target_for()` currently claims without an explicit lease; give it a bounded lifetime or a clear owner-release path before relying on it for data-tier schedules. Claims are transient and should be rebuilt after load, not restored as occupied forever.

One authority owns movement for each person at a time:

| Tier | Position / route owner | Activity responsibility |
|---|---|---|
| Distant data row | `WorldSim` | Coarse goal/need progression; no `LifeActor`, path agent or per-person node |
| Visible route sprite | Existing `PopulationLOD` route owner while selected | Cheap route and presentation only; no duplicated schedule/need integration |
| Embodied villager | `Villager` physics/body owner, writing resolved position back to `WorldSim` | Existing utility brain plus one active activity session |

Promotion, demotion, death, interior teardown, fast travel, time skip and save restore must release or transfer the same claim exactly once. Do not let both a body and a data row advance its position. Do not hold a furniture/work slot across a world-time jump unless that activity explicitly survives it.

## Activity protocol for the first live slice

Use one smith at one real anvil as the first vertical slice after branch coordination. It proves navigation, slot capacity, clip timing, cancellation and real work effects without attempting a whole profession system.

1. Build smart-object spots from the live settlement plan, using stable source identities and the existing mesh/lot placement. Reconcile object coordinates with the actual generated building placement; do not invent a second layout.
2. Ask the existing utility brain for its current intent and use the data definitions to find a compatible activity. Keep schedule, personality and need scoring in their existing owners.
3. Resolve a free slot and obtain the single authoritative lease. Store the actor/object/slot/generation on the actor's current task.
4. Route to the approach point through the existing `StreetGraph`. If blocked or the approach placement is invalid, wait/reselect; do not pass through the wall or force-snap the body.
5. Let the existing `Villager` body brake and face into the usable tolerance. Only then start the entry clip. Reaching a timeout is a cancellation/fallback condition, not proof that the actor arrived.
6. During the loop, an animation marker may emit a work contact cue. It must not grant a complete item repeatedly for each visual loop. Finalize one explicitly bounded work unit through the existing crafting/economy owner and exact-station generation check.
7. On threat, player interaction, schedule change, missing object, body removal or room teardown, interrupt at a safe boundary, release held props and the claim, and return the resident to its still-valid goal. If the actor is near completion, rules must say whether the unit commits or cancels; never infer it from the current clip name.
8. Emit short-range sounds/attention from `LivingEvents` as sensory stimuli. Publish a persistent `WorldEventLog` fact only for a completed domain result. Later witness systems decide who learned it.

Keep the first live session small and local. Do not add global navigation agents, an always-on activity node per resident, or a new all-NPC timer. Reuse the two-route-per-physics-frame `StreetGraph` cap, existing decision staggering, and selected-body budget. Measure before increasing them.

## Source-review risks to close before live integration

These are integration risks in the latest Claude prototype, not claims that the current game is broken:

- `SmartObjects` tracks holders by integer `person`; use a namespaced stable actor reference across systems to avoid ID collisions.
- `SmartObjects.Session.ALIGN` can move on to `ENTER` after its 1.5-second timeout even when the body did not reach the stand transform. A blocked approach should cancel/replan, not enter and visually snap.
- `Session.update()` returns a `snap` transform during entry and work loops. `LifeActor` interpolates its global position to that transform without a physics sweep. The gameplay adapter must retain `move_and_slide()`/collision ownership and only correct tiny validated residuals.
- `LifeActor._end_session()` calls `session.interrupt()`, then immediately releases the slot and drops the session. When interrupt selects an exit clip, this frees the slot before that clip can run and then stops updating it. The gameplay adapter should keep an exiting session alive until its exit finishes (or explicitly use an immediate, non-animated cancel); don't release a shared slot while the previous actor is still occupying it.
- `target_for()` claims a slot as a schedule target. Define release/reselection on schedule change, failed path, time skip, actor demotion and unavailable activity; otherwise a distant resident can strand capacity.
- Current spot IDs are insertion-order array indices, and `_held`/holder arrays are not serialized. Keep these as transient handles and derive stable references separately.
- The prototype's session only returns an activity event once per session. A finished work unit still needs an explicit domain validation/commit path, with the existing exact station generation and recipe/material check.
- The new content lives in a demo/`living_world` package in the latest Claude source. It is not evidence that `main.tscn`, `WorldSim` or existing villagers use it yet.

## Acceptance gates for the shared branch

For two anvils, two residents can work in parallel; for one anvil, one wins and the other waits or chooses a valid alternate. A blocked approach does not snap through geometry or start the work clip. Schedule changes, threat interruption, LOD transfer, death, time skip, load and teardown cannot strand a claim or duplicate movement owner. Reopening/retrying an activity cannot grant duplicate materials, mastery, wages or persistent events. Exact station invalidation cancels the pending effect.

Capture one full approach → work → interruption/finish → resume sequence on the normal gameplay scene, with contact/route/session overlays. Record active bodies, sessions, path requests, sensory events, and frame-time p50/p95 on LOW and HIGH. The isolated Claude demo and parser checks are useful development evidence; they do not replace this live acceptance. No gameplay capture or phone cost is asserted by this note.

## Branch coordination

The latest Claude ref was fetched and inspected, but not merged into this Codex worktree because its new commit contains 7,500+ lines of presentation, asset and demo work and changes `life.gd`, which both tracks touch. Keep both refs intact. Once their owner lands or approves the smart-object package for shared integration, merge that ref into this branch, resolve `life.gd` by preserving both sets of narrow hooks, then implement only the `Villager` adapter above. Do not cherry-pick or re-create Claude's props, clips, demo actor, crowd LOD or scene wiring on the Codex branch.
