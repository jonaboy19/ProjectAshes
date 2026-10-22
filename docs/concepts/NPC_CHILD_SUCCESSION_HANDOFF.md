# Child-heir spouse reset — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: preserve correct child parentage while ensuring either successor starts without the outgoing player's active spouse record.

## Behavior

For child succession, `Family.succeed_to()` still archives the outgoing life first and captures the outgoing player and spouse in the heir's parent records, including the existing age-at-birth state. It clears `spouse` only after those records are assembled and before `Life.life_path.begin()` starts the heir's life. For spouse succession, it first copies the spouse's traits, affinity, age, sex and name into the successor values, then clears the active spouse record before the new life begins. Both paths therefore begin without an inherited active marriage. Existing children are not cleared on spouse succession; parent record structure and saved fields are unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime succession, relationship, save/load or gameplay validation was run.
