# Acts II-V headless playthrough (C12, `claude/v1-story-acts`)

Bot: `kingdom/tools_qa/playtest_bot/playtest_bot.gd`, stages `st_a2`..`st_a5`, chained with `st_load` / `st_save` (slot 5), headless, via `tools_qa/v1/run_v1.sh`.
Result of the final chain (birth -> a1 -> a2 -> a3 -> a4 -> a5, every act resumed from the previous act's save, an act re-run when it only hit the 1500 s stage deadline):

| Stage | Result | Runs needed |
|---|---|---|
| st_birth, st_a1 | story reaches `a1_after_blessing` | 1 + 1 |
| st_a2 | `a2_thief_truth` done | 1 |
| st_a3 | `a3_the_ledger` done | 2 (deadline) |
| st_a4 | `a4_five_hearts` done | 4 (deadline x2, one coach loop, then done) |
| st_a5 | 38 of 38 steps, `complete true`, flag `r1.complete` set, "Region 1 complete" | 1 |

## Blockers found and fixed
| Where | Blocker | Fix |
|---|---|---|
| `scripts/world/settlement_builder.gd` | `SCRIPT ERROR: Parameter "data.tree" is null` when a save load swapped the world while a town was spreading over frames (`await get_tree().process_frame` on a node no longer in the tree) | all spread-frame awaits use the main loop's SceneTree; the existing `is_instance_valid(root)` guards stop the build |
| `scripts/combat/combat_feedback.gd` | `frame_post_draw already connected` ERROR (hit flash re-armed before the frame drew) | connect only if not connected |
| `scripts/region1/tutorial_game_bridge.gd:85` | `Nonexistent 'String' constructor` on a null `verb` | `str()` |
| Act II `a2_duskbriar` | the bot died every time: the quest wakes the Ashen Hand camp with its full roster (5) for a 3-kill objective | `Region1Creatures.wake_camp(at, count)`: the camp wakes with at most the quest's kill count (`r1_story_director._spawn` passes it) |
| Act IV `a4_glade_trial` (parley) | the Antlered Warden parley prompt lost the E key to Idra beside the player; was forced by posting the event | bot steps away from a companion before the parley (a player does the same) |
| Act IV `a4_highwatch` (Rowan's ember) | the "Lay Rowan's ember to rest" row only exists on the talk sheet; the bot never used it and forced the event | bot clicks it, picks "Rest in a runestone" and a stone |
| Acts II/IV stones | an Elder Stone or the ashes beside it won the E prompt (`opened no stone menu`, `no Kneel option`) | bot steps onto the stone / ashes and presses E again |
| Acts II-V travel | a dead player (death screen pauses the game) was blamed on the stone; a coach ride that did not arrive was repeated forever (fare paid each time) | `ensure_alive` before E; one hooked teleport instead of the re-ride loop |

## `[HOOK]` counts
Counting every `[HOOK]` / `[HOOK-lite]` line the bot printed (all runs of an act, incl. re-runs after a deadline), first run on the merged base vs the final chain:

| Act | before (first run) | after (final chain) | forced events before -> after |
|---|---|---|---|
| I | 3 | 4 | 0 -> 0 |
| II | 7 (died at Duskbriar, never finished) | 32 | 0 -> 0 (+ the act now finishes) |
| III | 3 (died / deadline early) | 33 | 0 -> 0 |
| IV | 39 | 135 (incl. 46 coach calls and 21 fare top-ups, mostly from the endless re-ride loop fixed later in the chain) | 2 -> 0 |
| V | not reachable | 29 | 0 |

The raw totals are not comparable: the "before" runs stopped early at a blocker, the "after" runs play the whole act (and Act IV's 135 includes the loop). What did go to zero are the **forced story events** (the bot posting an objective's event because it could not play it): Warden parley and Rowan's ember are now played through the real UI.

## Hooks that remain (unavoidable headless)
- travel: teleport when the walk is blocked or no coach stop is near both ends; coach fare top-up (`gold` set) - a player earns the fare
- heal during fights (the bot is a weak fighter on a software renderer)
- Kindling Night festival signal, ageing 8 -> 12 (the years pass), carve via the canvas's glyph fallback (no mouse drawing headless)
- Act V: the Rift gate's power (soul tier, iron kit, level 12) - allowed by the plan because the requirement is shown to the player
- firewood top-up where a player gathers it at the woodpile; a wooden spear in hand before Act II

## Open
- `hooks_allowed.txt` still holds no entries; `V1_HOOKS_STRICT` stays off.
- Each act needs 1-4 bot runs because a software-rendered headless run plays ~1500 s per stage; `run_v1.sh` stages for the release gate should list `st_a3`, `st_a4` twice.
- The Act I wolf fight once froze both bodies at 11.0 m for the whole 1500 s in the very first run (player and wolf motionless, `hits 0`); it did not reproduce in four later runs. Watch for it.
