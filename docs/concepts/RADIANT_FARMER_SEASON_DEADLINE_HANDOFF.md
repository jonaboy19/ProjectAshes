# Farmer grain quest season deadline — Codex handoff

Date: 30 September 2026
Branch: `gpt/living-world-integration`
Scope: make `farmer_deliver_grain` deadlines refer to the current season end from the offer date, not from acceptance.

## Behavior

- `VillageServices.world_from_game()` provides inclusive `days_left_in_season` using the live season day and `SeasonsScript.DAYS_PER_SEASON`. Thus season day 28 reports one day remaining.
- A generated farmer grain offer stores `deadline = offered_day + days - 1`. An offer posted on season day 28 is due on that same absolute calendar day.
- Board upkeep removes farmer offers once `day > deadline`, while retaining the existing `OFFER_DAYS` expiry for every offer.
- Accepting an expired farmer offer removes it and returns an expiry message. A valid farmer offer keeps its original absolute deadline when accepted. Other quest kinds continue to receive `day + days` at acceptance.
- For legacy saved farmer offers with no usable deadline, the deadline is derived as `offered_day + days - 1` both for expiry decisions and acceptance. The save shape is unchanged.

## Verification and limits

Static source review and `git diff --check` only. No parser, runtime calendar boundary, quest board, acceptance, save/load or gameplay validation was run.
