# Apex-migration radiant quest payload — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: consume the live pending-apex-hunt fields when constructing `apex_hunt` radiant quests, while retaining old fixture compatibility.

## Change

- The first `reach` stage targets `displaced_pos`, where the displaced den was vacated.
- The `kill_den` stage targets `apex_pos` and now identifies the apex with `apex_den_id`, matching MonsterEcology's live payload.
- Legacy fixtures with `pos` and `id` remain supported: `pos` supplies the apex location when `apex_pos` is absent, and `id` supplies the target den ID when `apex_den_id` is absent. Missing positions fall back safely to the quest's home location; species, reward, stage radii, RNG selection and other quest generation are unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime quest generation, ecology integration, save/load or gameplay check was run.
