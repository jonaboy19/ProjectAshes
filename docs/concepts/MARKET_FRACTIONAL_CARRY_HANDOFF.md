# Market fractional carry save continuity — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: preserve sub-unit stock changes across market save/load.

## Behavior

`RAMarket.serialize()` now persists its `_carry` dictionary. `deserialize()` clears any existing carry first, then restores only entries whose good is registered in `stock` and whose value is numeric, finite, and in `[0, 1)`. A non-dictionary carry container and invalid, unknown-good, negative, or out-of-range entries are ignored. Older saves without a `carry` key load with empty carry and continue using the existing behavior. Stock, purse, modifiers, economy callers, and home-market rebinding are unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime economy, save/load or gameplay validation was run.
