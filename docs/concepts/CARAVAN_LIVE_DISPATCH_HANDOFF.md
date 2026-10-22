# Live caravan dispatch — design handoff

## Current evidence

`Economy.tick_hour()` calls `caravans.tick()` to process arrivals. Repository search finds `Caravans.send()` only in tests and no live dispatch producer or owner. This is a dormant feature/design gap, not a confirmed runtime bug; no live caravan activity is promised by this note.

## Decisions needed before implementation

- Who funds each dispatch and selects its cargo?
- What gameplay system creates real dispatch requests?
- Who owns stock removal and receipt: should dispatch transfer inventory, or remain distinct from the current abstract market imports and surplus trade?
- What arrival receipt/event should players and other systems receive?
- What dispatch state must survive save/load, and how are duplicate arrivals prevented?
- What coarse deterministic cadence and per-tick budget fit mobile simulation?

Economy has unpublished Claude changes. Claude should fetch and review the current Economy/caravan ownership before implementation. This handoff adds no code or dispatch policy; no parser, runtime, or test validation was performed.
