# NPC observed-event memory — Claude handoff

Date: 30 September 2026
Codex branch: `gpt/living-world-integration`
Status: source-audited implementation contract; no code changes

## The missing link

The project has both a bounded world-fact journal and local perception cues, but no trustworthy event-to-observer receipt:

- `Life.world_events` stores up to 256 facts with monotonic IDs, game hours, payloads and optional causes. Its current action producers include `life_action_recorded` and `item_crafted`; facts are serialized by `Life`.
- `TechniqueCaster._resolve()` emits spectacle and acoustic cues for resolved techniques. The sound cue is deliberately anonymous and currently has no journal event ID.
- `UtilityBrain` applies local weather and settlement-geometry attenuation, coalesces nearby sounds, and keeps only a short anonymous last-heard point. Threat sight tests hostile combatants and returns visible/last-known positions and observation time, not durable observer beliefs.
- `Villager._decide_act()` uses these cues for immediate WATCH/FLEE decisions. It does not persist who heard or saw a logged event.

Therefore, a journal row does not prove that any NPC perceived it. Do not query the journal and broadcast its contents to residents.

## First vertical slice: anonymous hearing of a resolved technique

When `TechniqueCaster._resolve()` accepts a spectacle-shaped action, publish one bounded `technique_resolved` fact and carry its receipt into the existing local acoustic cue. Each embodied villager may receive a hearing observation only through the existing staggered `audible_event_at()` query after distance, weather and current coarse settlement-geometry attenuation. The cue must expire with its normal lifetime.

The resulting belief says only that the observer heard a nearby technique-like sound at an approximate point and time. It does **not** identify the caster, target, technique owner, victim, intent, combat outcome or a legal offence. A sound behind a wall remains a muffled cue under current geometry rules; terrain, doors and interiors still are not modeled.

### Event receipt and cue coalescing

- Publish only after `_resolve()` validates the live caster and begins the resolved action; never publish for a cancelled/unresolved cast.
- Keep the journal event ID as provenance. Copy a small safe event snapshot into the transient sound cue when it is emitted so a later journal eviction cannot erase a cue that is still audible.
- Current `sound_notice()` merges events inside a 1.5 m radius. If event-linked cues remain coalesced, retain a bounded list of receipts and report overflow; never silently attribute a merged sound to only one arbitrary event. Alternatively, keep event-linked receipts in a separate equally bounded cue queue while preserving the existing ambient sound path.
- Receipt data may include a coarse event class, event game hour, cue origin and short expiry. It must not expose actor/target references to the NPC-memory API. The memory consumer uses only its perception receipt, not a later journal query to discover hidden identity.
- Unknown, dropped, expired, inaudible or evicted receipts create no belief. They do not count as evidence that nothing happened.

## Persistent memory boundary

Use a pure-data, optional `Life`-owned module or another explicitly coordinated save owner. Keep world facts in `WorldEventLog`; keep observer beliefs separate. Store a copied observation snapshot so journal retention cannot delete an NPC's memory. A memory row needs only a namespaced observer ID, event reference if still available, event class snapshot, modality (`heard`), approximate point, event/observation game time, confidence/salience and expiry. Do not store Node references, resources, callables, exact hidden positions or an identified actor.

For current embodied villagers, `worldsim:<seed>:<person-index>` is the available namespaced observer identity. It is only stable for the current deterministic population layout; a population/generator migration requires a canonical identity map or a deliberate discard/migration policy. Do not join unrelated `WorldSim` rows and `LifeCourses` people by display name.

Suggested starting caps from the systems masterplan are at most 128 observers, 16 memories per observer and 1,024 memories globally. Treat these as initial ceilings to measure, not phone-performance guarantees. Coalesce repeated copies by observer/event/modality, decay salience, evict stale low-salience memories first, and expose counters for cap/queue drops. Validate optional restore atomically; older saves start with empty memory. Near/far promotion and demotion must preserve the data record without giving distant NPCs physical brains.

## Budget and acceptance gates

- Reuse staggered villager decisions and the current acoustic query; add no all-NPC scan, ray, per-resident node or per-frame journal poll.
- The current hostile sight budget is four rays per 500 ms and the acoustic event queue caps at 32. This first hearing slice must add no rays; profile memory insertion and queue work on target LOW-tier hardware before raising any cap.
- Verify one resolved cast produces one fact/receipt; cancelled casts produce none; only listeners inside attenuated range record it; outdoor/wall cases obey current limitations; no listener learns the caster/target; receipt merge/overflow/expiry are deterministic; journal eviction does not erase a copied memory; and save/load, LOD handoff and time skip neither duplicate nor invent observations.
- Measure queue drops, observer wait, retained memory count, allocations and frame-time at crowded resident counts. Existing desktop animation measurements do not prove this sensor/memory path fits a phone.

## Ownership and scope

The smallest likely integration spans `TechniqueCaster`, `UtilityBrain`/`Villager`, the event journal, an optional memory module and `Life` save hooks. `Life` and `street_graph.gd` have new Claude-published changes on `c30ad754`; fetch and inspect current versions before any integration. Coordinate `TechniqueCaster` ownership before editing. Do not alter sight/facing/animation behavior in this slice. Crime, culprit identification, witness reports, rumor propagation and dialogue claims require later verified evidence producers and are explicitly out of scope.

This document is a source review only. No parser, runtime, save/load, behavior, visual or mobile check was run.
