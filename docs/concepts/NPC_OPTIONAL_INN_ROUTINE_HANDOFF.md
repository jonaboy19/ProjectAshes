# Optional inn routine guard — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: keep `DailyRhythm`'s optional evening inn stop consistent with each settlement's generated lots.

## Change

- `DailyRhythm.state()` assigns `State.INN` only after the existing home/evening conditions and deterministic `goes_to_inn()` 30% selection pass, then checks a cached `settlement_id -> bool` lookup for an `inn` lot. Each immutable settlement plan is scanned at most once per process; invalid resident or settlement indices safely return false. The lot lookup does not run for guards, non-selected residents, or outside the inn window. The seeded hash schedule is unchanged.
- `DailyRhythm.has_inn_lot(person)` publicly exposes the same cached lookup. Real `UtilityBrain.context()` sets binary `inn_available` from it, and the `Act.INN` action has a binary gate so residents in settlements without an inn cannot plan the action. `make_context()` defaults `inn_available` to 1.0 so location-free scoring contexts keep their prior eligibility unless explicitly overridden.
- Offscreen `catch_up()` applies the expected 30% inn-hour social recovery only for a non-guard with a valid person index whose settlement has an inn. The separate generic public-hours social recovery still applies independently. This need approximation creates no visit, conversation, food or relationship event.
- `DailyRhythm.goal(State.INN)` preserves its existing spread of positions around a valid `graph.inn_door`. If the graph or inn door is unavailable, the fallback is the resident's home spot instead of an unrelated market target.

## Limits and verification

No new activity, route geometry, animation, UI, save data or persisted schedule state is introduced. The cache assumes the fixed-seed settlement plans remain immutable. Static source review and `git diff --check` only; no parser, runtime settlement variants, route, AI-choice or mobile performance validation was run.
