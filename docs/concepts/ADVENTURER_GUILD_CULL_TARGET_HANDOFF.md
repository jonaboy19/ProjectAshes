# Adventurer Guild cull target attribution — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: count kills for cull commissions only when the kill is attributed to the contract's target den.

## Behavior

`AdventurerGuild.on_kill(who, species, den_id)` now requires a nonnegative `den_id`, matching target den ID, and matching species before progressing a cull commission. Unknown-den ambient or camp kills do not count toward den-specific contracts. The implementation does not infer a den or change kill callers; Life and caller species behavior are outside this slice. Other commission types and progress handling are unchanged.

## Ownership and validation

The Codex worktree file was compared with local and published Claude refs at merge-base `1d5b8d2e`; neither ref has changes to this file. Static source review and `git diff --check` only. No parser, runtime kill attribution, commission or gameplay validation was run.
