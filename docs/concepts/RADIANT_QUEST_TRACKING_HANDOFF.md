# Radiant quest tracking after failure — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: keep compass tracking pointed at an active quest when its tracked quest expires.

## Change

During `RadiantQuests.tick_day()`, an overdue quest still fails through the existing `active.duplicate()` iteration, counters, state update and failure event. If that quest was tracked, tracking now immediately switches to the first remaining quest whose state is `active`, or to the empty string when none remain. The following board refill and all other failure behavior are unchanged.

## Limits and verification

This changes only the tracker ID; it does not alter quest deadlines, failure rewards, completion, or the compass/UI contract. Static source review and `git diff --check` only. No parser, runtime quest-flow, save/load or UI validation was run.
