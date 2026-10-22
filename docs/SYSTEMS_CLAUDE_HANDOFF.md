# Systems handoff to Claude

> Current delivery: start at **Latest continuation checkpoint** in [SYSTEMS_CONTINUATION.md](SYSTEMS_CONTINUATION.md). The current Codex branch is `gpt/living-world-integration`, tracked in [draft PR #5](https://github.com/jonaboy19/ProjectAshes/pull/5). Source-presence is not in-game acceptance; runtime and mobile checks remain outstanding.

For the fetched Claude living-world prototype (`d163255f`), read [Codex ↔ Claude living-world integration handoff](concepts/CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md) before wiring `SmartObjects` or `LifeActor` into live villagers. It documents how to unify slot leases and station generations, preserve movement and persistence owners, and avoid copying the demo's direct movement into gameplay.

Baseline: main 4e03e000, 29 September 2026. Read [SYSTEMS_MASTERPLAN.md](SYSTEMS_MASTERPLAN.md) for the staged plan and evidence. This handoff separates intended work from delivered verification; update the delivery section only after inspecting the actual patch.
For the current systems-to-presentation ownership map and living-world integration contract, also read [CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md](concepts/CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md). It distinguishes Claude's demo/reference activity code from the live `WorldSim`/`Villager` path and records the narrow first integration slice.

This handoff contains historical delivery notes from earlier source baselines. Read [SYSTEMS_MASTERPLAN.md](SYSTEMS_MASTERPLAN.md) for the current staged plan and source-reviewed status, then verify the branch and active PC checkout before applying anything. This file separates intended work from delivered verification; update delivery evidence only after inspecting the actual patch.

## Current Codex additions — 30 September 2026

- NPC familiarity is saved separately from player relationships and grows only after a completed nearby villager conversation. Pairing uses a bounded queue and modest affinity/wait-time scoring; ties do not yet alter dialogue or offscreen behavior. See [NPC_SOCIAL_GRAPH_HANDOFF.md](concepts/NPC_SOCIAL_GRAPH_HANDOFF.md).
- Shared hostile sight checks rotate through each villager's four nearest candidates over successive decision ticks. The four-rays-per-500-ms global budget and one-request-per-observer queue remain unchanged; fair service and detection delay still need measurement.
- Unembodied need catch-up now approximates the person's daily sleep and meal windows in constant time, including need-level food and hydration recovery. It does not mint food, simulate jobs, or recover social/faith needs. See [NPC_OFFSCREEN_NEEDS_HANDOFF.md](concepts/NPC_OFFSCREEN_NEEDS_HANDOFF.md).
- Villagers now have a deterministic courage trait that modestly varies flee/watch utility without changing combat capability. It is derived from the existing person index and shares its identity caveat. See [NPC_TEMPERAMENT_HANDOFF.md](concepts/NPC_TEMPERAMENT_HANDOFF.md).
- Near villagers can react to moving-player noise and selected resolved combat/work sounds. It remains anonymous and short-lived; existing town footprint/wall geometry now damps the strongest sound cues without per-NPC physics raycasts. This is approximate interest, not witness evidence. See [NPC_MOVEMENT_HEARING_HANDOFF.md](concepts/NPC_MOVEMENT_HEARING_HANDOFF.md).
- Near-ring schedule targets now include semantic Guard posts and capped woodcutter spots. An embodied act change releases an obsolete work/shop slot before replanning. This remains destination/lease metadata; it does not add a new work animation or physical station interaction. See [WORLDSIM_SMART_OBJECT_TARGETS_HANDOFF.md](concepts/WORLDSIM_SMART_OBJECT_TARGETS_HANDOFF.md).
- These recent additions received static source review and `git diff --check`; they have not received Godot parser, live behavior, save/load, occlusion-quality or phone-performance validation. Claude's branch and local unpublished work were not edited.

## Ownership

Claude cloud and PC workers retain models, environment, player presentation, animation and existing active files. Codex systems changes belong on the isolated `gpt/living-world-integration` branch. Preserve current signals, inventories, progression, clock, saves and population ownership. Before merging, re-read current Life and other touched files because concurrent branches may have evolved.

## First integrated slice

A new RefCounted event history is wired to successful player Life.record and crafting.crafted producers, then saved/restored through Life. Existing consumers continue to operate. This journal is not an event bus: no subscriber dispatch or gameplay consequence routing is implemented in this first patch. Event logging is a foundation and diagnostic API, not an implemented crime/social/scenario brain.

Implemented contract (runtime verification pending):

- publish(type, actor_ref, target_ref, game_hour, payload, cause_id=0) returns success/id/error.
- since(after_id, limit=32, type_filter="") returns deep-copied records; window_info(after_id) exposes retention bounds and cursor gaps so callers can reconcile expired history.
- serialize/deserialize preserve version, sequence and bounded history. JSON-parsed whole-valued numbers must normalize to integer IDs/schema fields; fractional/nonfinite identifiers remain invalid. Plain JSON roundtrip is a required regression check.
- Valid payloads contain JSON-compatible finite scalar/array/dictionary values under depth/size limits; reject Nodes, Resources, callables and malformed references.
- Missing event state in an old save starts an empty log; loading cannot retain the previous run's events.
- IDs increase after loading. Consumers detect retention gaps. Facts remain local knowledge until a future witness/rumour adapter explicitly shares them.

Life.record emits life_action_recorded after existing life/mastery/tendency/soul updates; item_crafted records only explicitly selected scalar recipe/item/skill/quality/xp/count fields present in the current crafting result. Do not record failed crafting attempts as completed work. Do not add a second mastery reward from consuming these events.

## Identity caveat

WorldSim people are array indices. life_courses.people uses its own positive IDs; its career-seat adapter uses CAREERS_ID_BASE=-1000000. Player and relationship keys use further conventions. Never treat a bare integer as universal identity. Use domain-prefixed references and add mappings only when verified. An event's player reference does not require unifying all person systems in this patch.

## Next collaboration point

Agree on one physical interaction vertical slice before changing Station/TalkTarget/door or animation files. Systems supplies reservations, eligibility, phases, interruption, commit and actual world effects. Claude supplies approach motion, contact markers, sockets and physical object presentation. Shared protocol must support both NPC and player, close-range and abstract operation, and exactly one effect commit.

## Review checklist

1. Inspect actual diff for additive changes and unchanged current signal effects.
2. Verify one existing Life.record producer produces one event; a successful craft produces one event and retains its existing XP/reward.
3. Verify failed crafting produces none.
4. Save/load restores log and next ID; loading legacy state clears it.
5. Exercise malformed state, invalid payloads, capacity wrap, cursor gaps and mutation isolation.
6. Measure sustained publication/query costs and bounded memory; avoid claiming device performance from a desktop unit harness.
7. Record actual tests/runtime evidence in the PR. No visual naturalism claim follows from a data log.

## Work still planned

Action/reservation runtime; contextual activities/work orders; budgeted perception and memory; sparse NPC social edges; law and rumour evidence; authored state-cast scenarios; transport continuity; settlement/economy/logistics coupling; ability/status interfaces. These require implementation and game/device verification. The masterplan explicitly preserves existing features rather than replacing them.

## Delivery evidence, 29 September

Sol prepared the audit and sequence; Luna implemented the first source patch; Codex reviewed its persistence and bounds. Changed runtime files: `kingdom/scripts/systems/world_event_log.gd` and the narrow producers/query/snapshot hooks in `kingdom/autoload/life.gd`. The journal stores up to 256 facts, each with an 8 KiB payload ceiling, depth limit 8 and traversal limit 512 values. Schema version 2 normalizes exact JSON integer IDs and rejects invalid saves atomically. Capacity eviction is visible through `window_info` and `Life.world_event_window`.

Godot 4.6.3 isolated script parser verification is recorded separately from gameplay verification. No full-game execution, save roundtrip, failed/successful crafting playtest, soak, or mobile profile is claimed in this delivery. The implementation is a reviewable foundation: it does not yet improve NPC decisions on its own. Existing biome, asset, animation, streaming, population, physics and quality files remain outside this patch.

JSON numbers do not preserve Godot integer types; see the [official JSON reference](https://docs.godotengine.org/en/4.6/classes/class_json.html). Integer IDs are therefore accepted only as finite whole numbers in the exact interoperable range; actor identity remains domain-specific.


## Current delivery status (working tree, review pending)

Continue from [SYSTEMS_CONTINUATION.md](SYSTEMS_CONTINUATION.md), including exact ownership, QA gate and remaining systems. Event journal integration exists. Craft action start/commit/cancel and UI lifecycle glue are present; reservations cover the actor work channel only, not physical station objects. NPC sight and crafting slices are committed; live integration is still unverified. Shared visibility is capped at 4 rays per 500 ms with 3-second anonymous danger memory. No FOV/hearing/permanent NPC memory is implemented. Isolated new-module parser checks do not establish full-game integration; behavioral/device validation is still required. Do not mark latest review fixes accepted without inspecting the final patch and evidence. Next: verify live integration, then stable shared station IDs/reservations, then significant evidence-based memory.
