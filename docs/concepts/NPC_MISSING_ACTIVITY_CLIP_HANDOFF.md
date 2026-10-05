# NPC missing activity animation recovery

Date: 2026-10-05
Branch: gpt/character-feel-finish

SmartObject sessions depend on clip completion to leave ENTER/BETWEEN/EXIT and to progress loop cycles. Villager._so_apply previously ignored an unavailable clip while retaining the session, so completion could never arrive and a claim could remain occupied indefinitely. LOOP output could also emit a work sound despite no matching animation being played.

The body now detects a nonempty requested clip that its AnimationPlayer cannot play (including no player). It cancels through existing token-safe release, marks the activity ended, clears arrival and returns before props/events. The existing bounded failed-spot cooldown prevents immediate repeated selection of that object; ordinary utility decisions replan. Existing clips and empty movement/alignment outputs are unaffected. No generated or replacement animation is added.

Limit: exclusion temporarily covers the whole object, even when another random loop variant might be available. This conservative behavior reveals incomplete rig/library content rather than faking successful use. The cooldown helper's existing name refers to unreachable spots but now also covers unplayable activity contracts; neither is danger memory. Missing animation repair remains asset-owner work.

Source review only; no tests or game runtime run. Pending acceptance: remove an entry, loop, between or exit clip from a representative rig and verify release/replan/no false event; verify intact sessions still progress. Claude's shared checkout unchanged.
