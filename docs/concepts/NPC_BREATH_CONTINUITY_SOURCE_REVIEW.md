# NPC breath continuity — source review

5 October 2026, `gpt/character-feel-finish`. No runtime validation or population code change.

The systems continuation warns that breath is reseeded when a brain is recreated. Current source confirms this: `UtilityBrain.seed_needs()` assigns breath, `tick()` drains/restores it, and utility context uses `1 - breath` as winded. `export_needs()` and `import_needs()` contain only food, rest, social, faith and water. `catch_up()` never advances breath. WorldSim serializes five need columns under schema version 2 and validates that exact byte count.

This creates a continuity gap for sitting/winded behavior across brain recreation, even though the five other needs persist. It is not evidence of a measured on-screen failure.

## Coordinated implementation contract

- Preserve the existing WorldSim row/save owner and promotion/demotion hooks; do not add a separate fatigue save store.
- Add breath as a sixth column through a new schema version and audit every stride, allocation, row read/write and validation. Updating UtilityBrain alone would break the existing import contract.
- Migrate versions 1/2 by retaining their five values and timestamp precision behavior. Initialize missing breath through a documented deterministic legacy fallback.
- Define offscreen breath recovery separately from long-term rest. Reuse scheduled sleep/home/rest availability with constant-time arithmetic; do not claim a physical sitting visit or mint activity effects.
- Ensure load, resync, time skip and repeated near/far transitions keep a single need owner. Invalid rows must retain the existing safe fallback.
- Review actual winded choices before tuning rates. Save round trips, legacy migration, large skips and phone costs remain acceptance work.

Population hotpaths overlap Claude's work; this review records the complete migration boundary for coordination rather than applying an incomplete column change.
