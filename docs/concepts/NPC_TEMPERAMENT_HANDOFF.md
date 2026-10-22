# Villager temperament — Codex handoff

Date: 30 September 2026  
Branch: `gpt/living-world-integration`  
Scope: low-cost behavioral variation in how an existing villager brain responds to nearby danger and spectacle.

## Change

`UtilityBrain.personality()` now derives a fifth stable 0..1 `courage` trait from the same deterministic person seed as sociability, laziness, piety and greed. It is not a new save field or a class/job restriction. On utility decisions only, higher courage modestly lowers the FLEE score and raises the WATCH modifier; the midpoint preserves the prior multipliers. Guards still use their existing guard modifier, and all flee/watch decisions retain current danger/spectacle gates and interruption timing.

This gives nearby people a small difference in whether they look toward a commotion or make space. At the neutral midpoint, the previous flee/watch utility scores are unchanged. It does not make civilians attack, grant combat capability, identify a source or change damage/equipment. A scalar adjustment applies only after the existing action score; there is no extra per-frame work or scoring pass.

## Limits and review

- Courage is currently derived from the WorldSim person index. It inherits the project's fixed-seed/person-index identity limitation; generator migration must preserve or remap it if NPCs should retain temperament.
- Utility score differences remain subtle and deterministic. Personality is not visible to dialogue, biography or offscreen simulation yet.
- The neutral context default is 0.5 so QA/tools using `make_context()` retain the previous midpoint behavior.
- Static source review and `git diff --check` only; no Godot parser, behavioral tuning, crowd capture or mobile profile was run. Review a mixed crowd under the same sight/queue budget before tuning the ranges.
