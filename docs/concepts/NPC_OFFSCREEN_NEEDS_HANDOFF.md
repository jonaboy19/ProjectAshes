# Offscreen NPC need recovery — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: constant-time catch-up for the existing five utility needs when a villager has spent time unembodied or crossed a game-time resync.

## Change

`UtilityBrain.catch_up()` no longer treats the whole elapsed period as uninterrupted waking, hunger, thirst and fatigue. It uses a cumulative periodic sleep function and counts the three existing daily meal windows with three arithmetic operations. Sleep time restores rest and halves hunger drain. Each meal restores 0.75 food need and abstract hydration equal to one third of a day's existing water depletion. All five needs are clamped to 0..1, and no loop runs once per skipped hour or day.

The personal sleep window follows current `lazy` trait bounds (20:30–22:30 start; 05:30–06:42 wake). It uses `DailyRhythm.delay(person)` from the current day for the elapsed interval; the per-day historical delay jitter is intentionally averaged. A meal is counted at its existing `MEALS` time plus 0.5 game hour and the same personal delay. Hydration is a data-tier need approximation only: it does not claim the resident visited a physical well, take water from inventory, reserve a slot, or emit an activity event.

## Boundaries

- Save fields, need ordering and migration defaults are unchanged.
- Active, embodied need recovery still comes from the current act and physical activity lease. This catch-up runs where the existing promotion, restore and resync paths already call it.
- Social and faith continue their existing linear decay while unembodied. NPC conversation, prayer, work, wages, food inventory, water inventory and world production are not simulated by this slice.
- This is a deterministic approximation for distant lives, not an authoritative meal or sleep history. It does not advance an actor or make one Node per resident.
- The three meal checks and cumulative sleep calculation are bounded regardless of elapsed game time. Static source review and `git diff --check` only; no Godot parser, need-curve, save/load, behavior or phone-performance validation was run.

## Review / next extension

Claude should compare the meal and sleep assumptions with authored schedules, then review promotion after 1, 3 and many skipped days for plausible need ranges. Keep any future economy-backed offscreen meals in the owning household/economy simulator; this utility layer should consume outcomes rather than minting food items. If sleep or meal timings change, keep the constant-time integral and add versioned state only if a real persistent record is required.
