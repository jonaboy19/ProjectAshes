# NPC dialogue topic memory — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: use existing saved player-to-NPC memory and recent relationship events for small factual dialogue reactions. No dialogue runner, relationship schema, UI, or NPC identity changes.

## What changed

- `kingdom/dialogue/villager.json` and `kingdom/dialogue/innkeeper.json` each have two repeat-aware lines in their existing `gossip` node.
- The lines require the existing `discussed:<file>:gossip` event emitted from that participant's saved recent-topic memory. The normal first-visit gossip lines remain unchanged.
- When `{rumour}` is available, the line uses the current dynamically selected token and acknowledges only that gossip was discussed before. It does not assert that the NPC remembers a specific rumor or that the rumor is new.
- When no `{rumour}` is available, the repeat line acknowledges that there is nothing to add right now.
- The villager greeting now has a priority-4 line for `gifted_recently`: “I remember the gift you brought me.” This event means the recipient has a gift modifier from the player within the last game day. A successfully accepted but disliked item can still produce the event, so the line deliberately does not say the NPC liked, used, or appreciated the gift, nor identify the item. Priority 4 lets the existing priority-5/6 hostile and priority-6 insult reactions take precedence.
- The villager and innkeeper greetings each have a 50% repeat-topic acknowledgement for `discussed:villager:crown` and `discussed:innkeeper:food`, respectively. These remember only that the dialogue node was entered: the villager recalls the Crown as a subject, while the innkeeper recalls going over the menu. They do not claim to remember the exact line, a specific opinion, or a chosen food item. Wording says the subject came up already, so it remains natural when the player returns to `greet` during the same conversation as well as in a later visit.

## Existing memory contract

`VillageServices._enter()` records the dialogue file/node topic after choosing a line. `_recent_events()` exposes current participant-local topics as `discussed:<file>:<node>`. `Relationships` bounds saved topic memory to 128 NPC records, 8 topics each and 30 game days. This change only consumes that existing event through DialogueRunner's `event` condition; it adds no fields, writes, or new memory lifetime.

`gifted_recently` is recipient-specific: it is derived from that NPC's gift modifier, which is set for a successful gift whether the item was liked or disliked, and expires after one game day. `quest_done` is less local: alongside the recipient quest modifier it can be raised by the global recent-quest timestamp. Dialogue conditioned on `quest_done` must not imply that this specific NPC witnessed or personally remembers the player's quest.

## Limits

- The stored topic is only the node name (`gossip`), not the rumor text or its source. Keep dialogue wording at the subject level unless a future fact-specific memory system is implemented.
- Fresh rumor availability still comes from the existing `_pick_rumour()` path; it is not derived from this topic memory.
- This is dialogue data source review only. No parser, in-game dialogue, save/load or localization check was run.
