# NPC social graph — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: bounded NPC-to-NPC familiarity recorded from completed, embodied villager chats. This does not replace player-facing `Relationships`, UtilityBrain's live chat pair owner, or Claude's dialogue/presentation work.

## What changed

- Added `kingdom/scripts/sim/npc_social_graph.gd`, a pure-data sparse graph with a hard 2,048-edge cap, canonical undirected pairs, coalescing within six in-game hours, bounded conversation counts, small familiarity affinity, deep-copy reads, and atomic optional-section restore validation.
- When a valid conversation resumes after the six-hour coalescing window, its existing affinity is attenuated by `min(0.5, elapsed_game_days * 0.0025)` before the usual `+2` familiarity increment and 60-point cap. This is linear, deterministic decay: about 7.5% after 30 days, 25% after 100 days, and capped at 50% after 200 days. Rejected input and callbacks still inside the coalescing window return before decay; a new pair still starts at 2.0; `first_day`, lifetime `conversations`, pair key, and serialized fields are unchanged. The fade is deliberately partial so it cools the plaza-pairing familiarity signal without erasing identity or friendship history.
- `Life` owns, resets, saves and restores the graph. Older saves with no graph start empty; malformed graph data is rejected without affecting the other Life modules.
- A Villager records a tie only when it is in the existing SOCIAL act, has arrived, spent at least `MIN_PERFORM` at the spot, remains paired, and is within three metres of its partner. The lower current person index is the single writer, and graph-level coalescing protects against repeat callbacks and same-day LOD promotion.
- UtilityBrain's plaza waiting area is now a queue of at most eight embodied candidates per settlement. It allows a 1.2-second gathering window, then lightly favors known ties; time waiting can offset the full familiarity bonus. A resident with no partner retries only on its existing staggered decision tick. Unregister/LOD release removes that person's wait entry or pair; new game and save restore clear transient pair queues.
- Current identities are explicitly namespaced as `worldsim:<seed>:<person-index>`; current world generation has fixed seed `1066`.

## Limits and follow-up

- Person indices are stable only for the current deterministic WorldSim population layout. A future variable seed, settlement reordering, population changes or generator migration needs a canonical person-identity mapping before saves can safely retain these edges. Do not silently reinterpret old indexes.
- The graph records modest familiarity and biases selection only among a small set of already-waiting social candidates. It does not change dialogue or opinions, propagate rumors, infer beliefs, or simulate distant conversations. NPC-to-NPC data is not merged into player-facing `Relationships`.
- The first producer covers the embodied Villager chat pair only. It is not evidence of friendship or agreement: affinity is just a bounded familiarity signal. Do not use it as crime witness confidence or a factual rumor.
- Existing body ownership, movement, pairing, animation and LOD remain authoritative. No pathing or new per-NPC node was added.
- Static source review only. No Godot parser, live gameplay, save/load, behavior, or mobile performance check was run for this slice.

## Claude integration notes

Use `Life.npc_social_graph.link(a, b)` or `.affinity(a, b)` as optional input to later pair selection/dialogue systems. Keep player opinions in `Life.relationships`. If a canonical identity resolver replaces WorldSim index IDs, add a migration or discard/rebuild the graph deliberately; don't map old links by display name. A future offscreen social producer should update this same graph through bounded batch operations rather than instantiate NPCs.
