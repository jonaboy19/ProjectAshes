# Awakening culture identity — Claude handoff

## Confirmed mismatch

Character creation records a selected culture as the persisted `culture:<id>` flag in `life_path.flags`. `Life._run_awakening()` currently assigns the literal `caldric` to its culture argument before calling `awakening.roll()`. `Awakening.CULTURE_ELEMENT` multiplies the matching element weight, so every character currently receives Caldric's earth bias regardless of their selected culture.

## Correct owner and bounded fix

The correction belongs in `Life`: read a validated culture ID from the persisted culture flag or authoritative identity source, and pass that value to `Awakening.roll()`. Preserve the deterministic seed/name/day arguments and change only the culture input. Do not alter `Awakening`'s culture-element mapping or weighting formula.

No game code was changed in this handoff. `Life` overlaps the current Codex PR, and the visible Claude checkout has unpublished Life changes; Claude should fetch and review its current version before integrating the fix.

## Suggested manual checks

- Check characters from each culture and confirm the intended culture bias is used.
- Check missing/legacy culture identity and confirm a deliberate safe fallback.
- Confirm a culture's Awakening result is deterministic across save/load for the same character and world inputs.

No tests, parser or runtime validation were run for this handoff.
