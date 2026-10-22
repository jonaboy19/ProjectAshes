# Offscreen NPC need recovery — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: constant-time catch-up for the existing five utility needs when a villager has spent time unembodied or crossed a game-time resync.

## Change

`UtilityBrain.catch_up()` no longer treats the whole elapsed period as uninterrupted waking, hunger, thirst and fatigue. It uses cumulative periodic schedule windows and counts the three existing daily meal windows with three arithmetic operations. Sleep time restores rest and halves hunger drain. Each meal restores 0.75 food need and abstract hydration equal to one third of a day's existing water depletion. Social and faith decay continue, with bounded expected recovery from existing public/inn/daytime/weekly holy-day schedule windows. All five needs are clamped to 0..1, and no loop runs once per skipped hour or day.

The personal sleep window follows current `lazy` trait bounds (20:30–22:30 start; 05:30–06:42 wake). It uses `DailyRhythm.delay(person)` from the current day for the elapsed interval; the per-day historical delay jitter is intentionally averaged. A meal is counted at its existing `MEALS` time plus 0.5 game hour and the same personal delay. Hydration is a data-tier need approximation only: it does not claim the resident visited a physical well, take water from inventory, reserve a slot, or emit an activity event.

Social recovery treats 17:00–19:30 as the existing shared market/public window, with expected exposure of 0.4–1.3 hours per day for non-guards and 0.45–1.2 for guards, scaled by the `sociable` trait. The existing `DailyRhythm.INN_SHARE` (30% of non-guards) is applied as an expected share of the 19:30–22:30 inn window. This is only anonymous need arithmetic; it does not assert that a person talked to anyone or create social-graph edges. Faith recovery treats 06:00–17:00 as daytime availability, with an expected `1.2 * pious` prayer-hours per day (0–1.2 hours) plus a small weekly holy-day allowance. The holy-day window covers the first 24 hours of each 168-hour cycle, matching the existing `WorldSim.day % 7 == 0` flag when absolute catch-up time is `day * 24`. This is a tuning approximation, not a simulated prayer routine. Before that weekly bonus, a full day changes faith by `-0.48 + 0.72 * pious` need points: piety 0 declines 0.48/day, piety 0.5 declines 0.12/day, and piety 1 gains 0.24/day. The holy-day allowance adds up to `0.4 * pious` points on its one day each week; final values still clamp to 0..1. Neither allowance creates a prayer event. The historical per-day delay and stochastic inn attendance are averaged over long skips; schedule/weather/companions are not reconstructed. The helper computes repeating-window exposure arithmetically in O(1), not by iterating days.

## Boundaries

- Save fields, need ordering and migration defaults are unchanged.
- Active, embodied need recovery still comes from the current act and physical activity lease. This catch-up runs where the existing promotion, restore and resync paths already call it.
- NPC conversation, prayer, work, wages, food inventory, water inventory and world production are not simulated by this slice. Social and faith may still reach zero where decay exceeds these deliberately coarse expected recoveries; this avoids inventing guaranteed events or relationships.
- This is a deterministic approximation for distant lives, not an authoritative meal or sleep history. It does not advance an actor or make one Node per resident.
- The three meal checks and cumulative sleep calculation are bounded regardless of elapsed game time. Static source review and `git diff --check` only; no Godot parser, need-curve, save/load, behavior or phone-performance validation was run.

## Review / next extension

Claude should compare the meal, sleep, social and faith assumptions with authored schedules, then review promotion after 1, 3 and many skipped days for plausible need ranges. In particular, tune the expected public/prayer exposure against playtest behavior without turning these allowances into fabricated histories. Keep any future economy-backed offscreen meals in the owning household/economy simulator; this utility layer should consume outcomes rather than minting food items. If schedule timings change, keep the constant-time integral and add versioned state only if a real persistent record is required.
