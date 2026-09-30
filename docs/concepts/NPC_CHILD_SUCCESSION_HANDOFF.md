# Child-heir spouse reset — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: keep the outgoing spouse available for child parentage, then prevent that spouse record from carrying into the child's active life.

## Behavior

For child succession, `Family.succeed_to()` still archives the outgoing life first and captures the outgoing player and spouse in the heir's parent records, including the existing age-at-birth state. It now clears `spouse` only after those records are assembled and before `Life.life_path.begin()` starts the heir's life. The child therefore does not inherit the parent's marriage as their own active spouse. Spouse-successor selection retains its existing behavior; parent record structure and saved fields are unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime succession, relationship, save/load or gameplay validation was run.
