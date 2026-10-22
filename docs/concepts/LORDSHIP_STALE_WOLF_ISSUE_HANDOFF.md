# Stale lordship wolf issue — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: prevent a resolved or empty wolf den from producing a misleading lordship decision.

## Behavior

Before computing choices for an open `wolves` issue, `Lordship.decide()` checks `issue.data.den_id` against `Frontier.ecology.dens`. The ID must be nonnegative, and a matching den must still be alive with population greater than zero. If no such den exists, the issue is erased, `village_changed(settlement_idx)` is emitted, and the call returns success with “The wolf threat has already been resolved.” No choice effects are applied: treasury, loyalty, food, population, reputation, follow-ups and quest effects remain untouched. Existing behavior for a live wolf den and all other issue kinds is unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime den lifecycle, signal/UI, quest or gameplay validation was run.
