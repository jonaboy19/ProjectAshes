# Talk target obstruction basics

Date: 2026-10-05
Branch: gpt/character-feel-finish

TalkTarget selected the nearest visible villager within 3 m by distance alone. It now checks the chosen candidate's chest-height segment against world collision layer 1, excluding the player's own collision RID, before exposing the Talk prompt. At most one ray is added per existing 0.2-second scan; an obstructed nearest candidate yields no target rather than scanning/raycasting every villager. Existing service/door priority remains intact.

The menu-held target guard also requires is_instance_valid(current), allowing retarget/cleanup when a selected actor is freed rather than retaining a stale reference indefinitely.

Source inspected: talk_target, dialogue UI, HUD menu visibility and villager movement. Actor movement is not automatically paused by this target holder; a reliable conversation begin/end/interruption contract remains required before safely implementing stopping and resuming routines. This patch addresses target eligibility only. It does not change dialogue content, camera or NPC schedules.

Limits: a blocked nearest actor can hide a farther clear actor until the selection changes; world-layer configuration and content collision determine visibility. No tests or runtime run. Pending acceptance: wall-separated actor has no prompt, open-door/clear actor does, player capsule does not self-block, and freeing a menu target clears its stale station target. Claude's checkout was not edited.
