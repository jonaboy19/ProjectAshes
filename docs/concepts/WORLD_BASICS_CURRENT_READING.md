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

## Shared gathering ownership
GatherRun keeps a weak reference to the active panel. A valid new session cancels the previous panel before opening, so different resource managers cannot leave overlapping gather panels. Normal close clears ownership only for the matching panel; scene teardown does not retain the panel. The 5 Hz lifecycle guard also closes gathering when the player's existing HUD menu/dialogue check becomes true. No resource is marked empty merely because another manager had a session open. Runtime and tests remain unrun; pause-menu ordering and scene-teardown manager references still need review.

## Freed-panel recovery
Forage, construction-resource and fishing interaction guards now use is_instance_valid(_panel), so an unexpectedly freed panel does not permanently block reopening. Normal exactly-once completion callbacks remain the primary cleanup. No runtime or tests were run.

## Living-world reading continuation
Read LIVING_WORLD.md lines 1-379: persistent personal lives, journeys, physical accommodation/property, jobs and entry qualifications, promotions by accomplishments, employment failures and physical quest boards. This is partial document coverage, not a full reading or proof of gameplay completeness. Located existing sim/property.gd, sim/careers.gd, career_ladders.gd and realm/career_trades.gd; their end-to-end coverage still needs inspection.
Read life_library.gd in full. Fixed its installation flag being set before skeleton-path validation: it now marks completion only after a nonempty clip set is available. Shared-library installation and composite caching remain intact. Missing-resource cache behavior remains a separate concern. No runtime or tests were run.

## Property persistence source review
Read property.gd registration, daily rent/tax and storage/save paths. Saved state can exist before the lazily rebuilt property registry. Daily dues now ensure the saved lot's settlement registry exists and skip unresolved definitions rather than silently treating missing rent/tax as zero. Storage access/capacity use the same targeted restoration. Invalid settlement indices no longer become permanently registered. No save schema change or full-world registry rebuild was added. Catch-up of multiple overdue periods and stack-quality preservation remain separate open concerns. LIVING_WORLD reading now extends through line 504 (hidden careers, guild institutions and entry, politics and temporary teamwork introduction). No runtime or tests were run.
