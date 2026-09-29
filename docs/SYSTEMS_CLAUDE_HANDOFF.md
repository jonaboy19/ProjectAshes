# Systems handoff to Claude

Baseline: main 4e03e000, 29 September 2026. Read [SYSTEMS_MASTERPLAN.md](SYSTEMS_MASTERPLAN.md) for the staged plan and evidence. This handoff separates intended work from delivered verification; update the delivery section only after inspecting the actual patch.

## Ownership

Claude cloud and PC workers retain models, environment, player presentation, animation and existing active files. Codex systems changes belong on the isolated gpt/living-systems branch. Preserve current signals, inventories, progression, clock, saves and population ownership. Before merging, re-read current Life and other touched files because concurrent branches may have evolved.

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
