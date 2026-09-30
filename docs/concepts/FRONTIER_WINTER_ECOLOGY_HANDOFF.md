# Seasonal winter input for frontier ecology — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: pass the current season into the existing once-daily monster ecology update.

## Change

`Frontier.advance_day()` now passes `WorldSim.season == "winter"` as the existing third `MonsterEcology.tick_day()` argument instead of hardcoding `false`. Winter food pressure, wolf pressure and migration behavior already implemented by MonsterEcology can now respond to the live season. Runestone coverage, Rift instability, call timing and all other daily wiring are unchanged.

## Limits and verification

This is a data wiring change only; it does not add new winter rules or change the ecology formulas. Static source review and `git diff --check` only. No parser, runtime season transition, save/load or gameplay behavior check was run.
