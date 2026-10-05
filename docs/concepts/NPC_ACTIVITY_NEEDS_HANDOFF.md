# NPC needs require actual activity

Date: 2026-10-05
Branch: gpt/character-feel-finish

The body previously passed its chosen action to UtilityBrain.tick as soon as the route marked arrival, even during SmartObject APPROACH/ALIGN/ENTER/EXIT. Performed-time commitment similarly advanced before use began. A blocked alignment could briefly restore needs without the activity actually running.

A shared _activity_is_performing predicate now gates both needs ticking and performed-time advancement. Outdoor actors need arrival, no active yielding, no ended activity awaiting replanning, and LOOP/BETWEEN when a SmartObject Session exists. WATER retains its existing arrival/facing/lease check. Indoor coarse activity and ordinary non-SmartObject activities keep their prior behavior. It reads live Session.phase, so a graceful interrupt into EXIT immediately stops recovery. No new timers or world queries.

Changes: villager.gd only. Source review only; no tests/runtime run. Claude's checkout untouched. Pending acceptance: blocked alignment must not restore needs; entry/exit must not advance performance; a valid loop must restore the intended need; normal indoor sleep/eating, water fetching and non-SmartObject acts must still work. Timings and mobile cost remain unmeasured.
