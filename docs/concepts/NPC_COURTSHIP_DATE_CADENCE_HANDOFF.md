# Courtship date cadence — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: limit successful player courtship dates to one per NPC per in-game day. No UI or relationship API changes.

## Behavior

- New courtships start with `last_date_day: -1`. A successful `Family.date()` records the current `WorldSim.day` after awarding its existing points and relationship modifier.
- Another date with that same NPC on the same in-game day returns an already-spent-time message before either reward is applied. Other NPCs have independent cadence records, and dating remains available on a later day.
- `courtships` is already deep-copied in `serialize()`, so the new field persists. `deserialize()` defaults older courtships that lack the field to `-1`, allowing the first post-load date.
- The menu option may remain visible until chosen; this slice guards the action, not menu presentation.

## Limits and verification

One successful date reward per NPC per in-game day is the only cadence modeled. The `at` venue and time cost remain abstract: the function still creates a short social modifier and awards courtship points without checking an actual venue, elapsed duration, travel, companion availability or schedule. Existing save structure/version and call paths are otherwise unchanged. Static source review and `git diff --check` only; no parser, runtime, save/load or UI test was run.
