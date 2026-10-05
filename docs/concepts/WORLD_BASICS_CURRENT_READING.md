# Current world basics reading checkpoint

2026-10-05, current branch includes Claude f4c86b40. MINING_COMBAT_WORLD sections 3-7 were read, but older missing-system descriptions are not current implementation evidence.

Source findings:
- world/deposits.gd already implements finite quantities and closed-form daily regrowth in WorldState overlays.
- sim/gather_session.gd and world/gather_run.gd already provide prospect/extract/care/take and quality-bearing results.
- sim/save_manager.gd already includes dirty tracking, lifecycle saves and atomic-save machinery; end-to-end persistence acceptance has not been checked here.
- ui/gather_panel.gd exposes cancel() but had no visible cancellation control. Added a 54-pixel Leave gathering button using that existing cancellation result, which reports zero count and consumption. It stays below rebuilt choices.

Remaining gathering lifecycle concerns: walking away, player death and menu transitions need source review; no timeout/proximity policy was added. No game run or tests were performed. Do not rebuild the existing deposit/session/save systems from the old research gap list.

## Gathering lifecycle follow-up
Shared GatherRun now starts a 5 Hz timer owned by the panel. It cancels when the initiating player is freed/replaced, dies, or moves more than 4 metres from the player's session-start position. The timer is freed with the panel; callback validity is checked before delivery. GatherPanel handles unconsumed ui_cancel input through its existing exactly-once close path. Menu-opening cancellation and multiple managers opening panels concurrently still require review. No runtime or tests were run.
