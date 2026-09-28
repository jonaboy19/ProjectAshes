# World schedule rhythm review for Rising Ashes

**Status:** source-grounded behavior design for Claude; no simulation code changed.  
**Baseline inspected:** `claude/focused-curie-m09hbd` at `e3563fc4`; refresh this before implementation.

Open [WORLD_DAILY_RHYTHM_REVIEW.html](WORLD_DAILY_RHYTHM_REVIEW.html) to scrub or play a full in-game day. The bands are calculated from the current `WorldSim._current_phase()` rules for all six job groups.

## Current schedule from source

The normal day is 720 real seconds, so one in-game hour passes in 30 real seconds. The current activity changes are group-wide clock boundaries:

| In-game time | Farmers | Blacksmiths | Merchants | Guards | Laborers | Woodcutters |
|---|---|---|---|---|---|---|
| 00:00–06:00 | Home | Home | Home | Home | Home | Home |
| 06:00–12:00 | Work | Work | Work | Work | Work | Work |
| 12:00–13:00 | Work | Work | Work | Work | Market | Work |
| 13:00–17:00 | Work | Work | Work | Work | Work | Work |
| 17:00–19:30 | Market | Market | Market | Work | Market | Market |
| 19:30–21:00 | Home | Home | Home | Work | Home | Home |
| 21:00–24:00 | Home | Home | Home | Home | Home | Home |

`WorldSim._on_phase_change()` assigns the new target immediately. `_simulate_slice()` scans up to 1,500 population rows per frame; with the source's approximate 20,000-person scale, it reaches the last resident in about 14 process frames after a boundary. Movement paths and trip lengths differ, but the decision to leave a phase remains synchronized by job and clock time. `WorldSim._spot()` also reuses home/work spots and changes market spots by day rather than by moment-to-moment need.

This is a plausible source of visible surges and repeated daily choreography, not proof that every play session shows an ugly crowd wave. The timeline makes the schedule rules visible; a runtime capture is still needed to judge how obvious those waves look from the market route.

## Natural variation without breaking the simulation

Do not add frame-level randomness to target selection. Give each person a stable, saved-or-reproducible schedule identity and introduce bounded variation around transitions, then let route length and arrival behavior create additional natural spread.

- Stagger departure/arrival timing by resident, household, role, and day with a deterministic hash or saved offset. Keep the offset stable when a game is saved and loaded.
- Keep economic/accounting transitions coherent with when work actually starts and ends. Do not show someone off to market while silently paying wages for an incompatible phase unless the design explicitly models that abstraction.
- Use schedule windows and role rules: guards must maintain posts, shops must have service coverage, and households should not all empty at once. A market can fill gradually and clear gradually.
- Store goal identity separately from the current route. A near actor should finish, interrupt, wait, or replan a trip explicitly; it should not have its target reset on every frame or teleport because the next time boundary arrived.
- Mix daily intent with local conditions later: weather, safety, fatigue, inventory, household needs, social ties, and festivals can select an activity from reachable anchors. Add these after travel, arrival, occupancy, and collision work, so richer intent does not make actors walk through buildings.
- Keep the near embodied actor's resolved position and the data simulation's position synchronized at explicit handoffs. Staggering intent must not reintroduce two movement authorities.

## Implementation path

1. **Measure the wave:** record the same market route around 06:00, 12:00, 17:00, 19:30, and 21:00. Count visible departures/arrivals over the 30 real seconds around each boundary. Confirm whether the design problem is a visual burst, repeated route, blocked destination, or merely an in-game clock presentation.
2. **Choose an event model:** specify transition window widths for each role and state which economic effects follow the start or completion of work. Identify posts and services that require continuous staffing.
3. **Stagger deterministically:** spread phase/departure requests over a bounded window by stable resident identity. Preserve save/load behavior and offline time skipping; do not call `randf()` each frame to select goals.
4. **Pair transitions with anchors/routes:** use arrival, service occupancy, waiting, leave, and fallback states from [the NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md). Dispatch the next task only when it can be reached and when the previous reservation is handled.
5. **Review the same captures:** retain the timeline view of intended schedule plus in-game before/after clips. Compare crowd departures, stalls, stuck agents, and LOW/HIGH performance.

## Acceptance checks

- Residents with the same job no longer all begin the same journey on one frame/short burst unless a deliberately shared event calls for it.
- Work coverage remains credible across each shop/guard post, and wages/market transactions occur once at consistent schedule events.
- A person travelling at a phase boundary keeps a valid route and arrives, waits, cancels, or replans explicitly; no target teleport or route through a wall.
- Households keep believable occupancy while some members leave; near NPCs do not all disappear at one transition.
- Fixed IDs reproduce the same variation after reload, and market scenes remain within LOW/HIGH actor and frame-time budgets.

## Source map

- `kingdom/autoload/world_sim.gd`: `DAY_LENGTH`, `WALK_SPEED`, `UPDATES_PER_FRAME`, `_current_phase()`, `_simulate_slice()`, `_on_phase_change()`, `_spot()`, and `advance_hours()`.
- `kingdom/scripts/population/population_lod.gd`: near/sprite/data representation and visible actor budget.
- `kingdom/scripts/population/villager.gd`: current near-villager response to simulation positions.
