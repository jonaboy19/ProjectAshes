# Optional inn routine guard — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: keep `DailyRhythm`'s optional evening inn stop consistent with each settlement's generated lots.

## Change

- `DailyRhythm.state()` assigns `State.INN` only after the existing home/evening conditions and deterministic `goes_to_inn()` 30% selection pass, then checks that the resident's settlement plan contains an `inn` lot. The lot scan therefore does not run for guards, non-selected residents, or outside the inn window. The seeded hash schedule is unchanged.
- `DailyRhythm.goal(State.INN)` preserves its existing spread of positions around a valid `graph.inn_door`. If the graph or inn door is unavailable, the fallback is the resident's home spot instead of an unrelated market target.

## Limits and verification

No new activity, route geometry, scoring, animation, UI, save data or schedule state is introduced. Static source review and `git diff --check` only; no parser, runtime settlement variants, route or mobile performance validation was run.
