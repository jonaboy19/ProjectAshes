# NPC dialogue topic memory — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: use existing saved player-to-NPC conversation-topic memory to vary repeat gossip acknowledgement. No dialogue runner, relationship schema, UI, or NPC identity changes.

## What changed

- `kingdom/dialogue/villager.json` and `kingdom/dialogue/innkeeper.json` each have two repeat-aware lines in their existing `gossip` node.
- The lines require the existing `discussed:<file>:gossip` event emitted from that participant's saved recent-topic memory. The normal first-visit gossip lines remain unchanged.
- When `{rumour}` is available, the line uses the current dynamically selected token and acknowledges only that gossip was discussed before. It does not assert that the NPC remembers a specific rumor or that the rumor is new.
- When no `{rumour}` is available, the repeat line acknowledges that there is nothing to add right now.

## Existing memory contract

`VillageServices._enter()` records the dialogue file/node topic after choosing a line. `_recent_events()` exposes current participant-local topics as `discussed:<file>:<node>`. `Relationships` bounds saved topic memory to 128 NPC records, 8 topics each and 30 game days. This change only consumes that existing event through DialogueRunner's `event` condition; it adds no fields, writes, or new memory lifetime.

## Limits

- The stored topic is only the node name (`gossip`), not the rumor text or its source. Keep dialogue wording at the subject level unless a future fact-specific memory system is implemented.
- Fresh rumor availability still comes from the existing `_pick_rumour()` path; it is not derived from this topic memory.
- This is dialogue data source review only. No parser, in-game dialogue, save/load or localization check was run.
