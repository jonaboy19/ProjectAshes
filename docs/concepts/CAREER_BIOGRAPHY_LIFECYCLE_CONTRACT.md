# Career and biography lifecycle — Claude handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Status: source-audited contract proposal; no implementation changes

## Purpose

Keep employment, career progression and the player's biography consistent across application, resignation, dismissal, promotion, rehire and save/load. These are related but distinct state: `Careers` owns an active seat; `Life` owns the career-ladder path and rank; `Biography` owns dated life chapters. Do not merge them into one field or replace the existing systems.

## Current source observations

- `Careers.apply()` vacates an old seat if needed, installs the new player seat, then emits `player_changed` once. `Life` listens and calls `_on_career_post_changed()`.
- `Careers.resign()` clears the seat and emits `player_changed`; Life's callback immediately returns when the player is no longer employed, so the open biography chapter is not closed.
- `Careers.pay_day()` clears the player seat on dismissal but emits no `player_changed` signal. `Life.employment_changed` and its biography reconciliation therefore do not observe that transition.
- `Life._on_career_post_changed()` starts a biography chapter only when an employed seat maps to a different `career_id`. It does not close a chapter on leaving employment. The `career_id`, `career_rank`, and `career_since_day` fields are serialized independently of `Careers.player`.
- `_career_daily()` checks a nonempty `career_id` without checking active employment, so ladder promotion can continue after resignation or dismissal.
- `Biography.start_chapter()` treats a matching role and organization as a no-op even when that chapter has already ended. `Biography.promote()` exists, but the daily ladder-promotion path currently updates `career_rank` without calling it.
- Save state already stores career employment, ladder fields, and biography separately. Restore should reconcile these fields without replaying player-facing messages or opening duplicate chapters.

## Proposed ownership and transition contract

| Transition | Authoritative owner | Required result |
|---|---|---|
| Apply to a post | `Careers` changes the seat; `Life` reconciles career path and biography | Old seat is vacated once, new seat filled once, current chapter is closed/reopened only when its role or organization changes; same-day switch cannot create duplicate open chapters. |
| Resign | `Careers` finalizes the empty employment state and emits one transition; `Life` closes the active employment chapter | The biography records the end day. Ladder rank/progress policy is decided separately from employment. |
| Dismissal | `Careers.pay_day()` finalizes the empty employment state and publishes the same transition contract as resignation, with dismissal reason | One notification and one chapter close; no wage, merit, or promotion side effect is duplicated. |
| Promotion | `Life`/career-ladder owner changes rank; `Biography` records that change | Update the active chapter rank and add one promotion highlight. Keep seat vacancy/promotion logic in `Careers` where applicable. |
| Rehire | `Careers` installs employment; `Life` reconciles the ladder and biography | A previously closed chapter must not suppress the new employment chapter. Preserve, reset or restore ladder rank according to the explicit progression rule below. |
| Save/load | `Life` coordinates serialized module state after `Careers` and `Biography` restore | Restore is silent and idempotent; a valid employed player has one matching open chapter, while an unemployed player has no open employment chapter. Do not infer historical transitions from stale UI callbacks. |

## Decision required before implementation

Decide whether ladder progression is a **career-history credential** that survives leaving a job, or an **active-employment rank** that pauses/resets on exit. The current code preserves `career_id` and `career_rank` after resign/dismissal and continues daily promotion checks. Do not change this implicitly while fixing chapter closure.

Recommended separation: retain earned rank/history as data, but only evaluate promotions while the matching ladder career is actively employed. Rehire then resumes the earned rank if the returning seat is compatible; a different career starts at its own first rank. Confirm this policy with the game owner before changing it.

## Exactly-once requirements

- Finalize the new `Careers.player` state before emitting the lifecycle signal.
- Emit one employment transition for application, resignation and dismissal; listeners read current authoritative state and do not reconstruct it from message text.
- Keep user-facing text separate from machine-readable transition reason/previous/new seat data, or define a stable typed payload. Avoid parsing `Game.say()` strings.
- Promotion, chapter close, UI notification and save restore must not each independently award the same progress or append the same biography highlight.
- Same-day apply/resign/reapply and save immediately before/after a transition must remain deterministic and leave no duplicate open chapter.

## Scope and verification gates

Likely integration touches are `kingdom/scripts/sim/careers.gd`, `kingdom/autoload/life.gd`, and `kingdom/scripts/sim/biography.gd`, plus a focused lifecycle check. These files have cross-system state ownership and may overlap Claude's work; coordinate and re-read their current versions before implementation. Do not change chapter schema or employment progression until the policy above is agreed.

Cover apply to a different post, resign, three-strike dismissal, same-ladder rehire, different-ladder rehire, promotion, save/load while employed, save/load while unemployed, and repeated transition callbacks. This handoff is a source review only; no parser, gameplay, save/load, or regression validation was run.
