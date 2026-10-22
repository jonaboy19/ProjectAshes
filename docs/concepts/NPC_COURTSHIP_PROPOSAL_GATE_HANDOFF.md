# Courtship proposal gate — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: separate earned courtship points from the player's explicit proposal action. No changes to `can_marry()`, save data, UI, or marriage consequences.

## Behavior

- The existing 20-point `interested` → `courting` transition remains automatic.
- Earning 50 points no longer changes the stage to `betrothed`. `can_propose()` now requires stage `courting`, at least `COURT_POINTS_BETROTHED` (50) points, and the existing marriage-home prerequisite.
- Only a successful `propose()` changes stage to `betrothed` and sets the existing `engaged` flag. `can_marry()` is unchanged and still requires betrothed status and a home.

## Limits and verification

This prevents point accumulation from silently engaging the player; it does not alter the proposal UI or broader courtship pacing. Static source review and `git diff --check` only. No parser, runtime courtship, save/load or behavior test was run.
