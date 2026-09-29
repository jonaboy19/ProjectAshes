# Village stuck check

"The player gets stuck between village buildings." Reproduced, root-caused and fixed in
`kingdom/scripts/world/settlement_builder.gd`.

## Tool

`kingdom/tools_qa/stuck_check/run_stuck_check.sh [--out=name] [--towns=Ashford,Kingsreach] [--scale=4]`
(headless is fine, it is a pure simulation). It boots the real game and walks the real player input
path at full run speed along every main street (centre line and both kerb lanes, both directions)
and every front-door footpath. A stuck event is less than 0.2 m of progress in 2 s. Each event logs
the position and every collider within 2.5 m. It also audits the gap between every pair of lots.
`shots.tscn` renders the fixed spots (needs a renderer, run with `-- --out=after --skipintro`).
Output goes to `docs/qa/stuck_check/<out>/` (`log.txt`, `stuck.json`, screenshots).

## Results

| | before | after |
|---|---|---|
| routes walked (Ashford + Kingsreach) | 632 | 632 |
| clean routes | 570 | 630 |
| stuck events | 70 (61 real, 9 villager-blocked) | 2 (0 villager-blocked) |
| street-lane events | 17 | 2 |
| door-path events | 53 | 0 |
| narrow lot gaps (<1.4 m) or overlaps | 12 (8 gaps + 4 overlaps) | 0 open, 13 closed with fillers |

Remaining 2 events: Kingsreach gate road, lane +0.0, both directions, at (432, -324). A roadside
Waystone (`region_sites.gd`, a cylinder on the road axis) is hit head-on by the walker that runs
exactly on the centre line. There is 6 m clear on each side, so a real player just steers round it.
It is outside the files this task may edit and is not a trap.

## Stuck spots and root causes

1. **Market stalls and barrel clusters across townhouse doors (most of the 53 door-path events).**
   `_gate_market` placed stalls (box 3.15 x 2.54 x 2.28) and barrels (1.66 x 0.80 x 1.51) with a
   collider each, in a strip that overlapped the footpath from a door to the street, and next to
   each other with slits under 0.7 m (the capsule width).
2. **Gate opening not centred on the street.** `_wall_ring` used a uniform ring, so the opening
   could be up to half a section off the road. The road's kerb lanes (+-4.3 m) ran into the 1.8 m
   wall collider. The 8 m section collider was also the full section length with no jamb clearance.
3. **Inner wall closed on the market streets.** The inner ring only had `gates[0]`, so the other
   main streets ran into solid wall.
4. **Wedge gaps between lots.** House colliders 0.7 to 1.4 m apart, and touching or overlapping lots,
   leave slots the player can walk into but not out of.

## Fixes

- `_wall_ring`: laid out from the gates. Each gate opening is centred exactly on its street axis, the
  spans between gates are divided evenly (scale within a few percent of the old one), wall colliders
  next to a gate stop `GATE_JAMB` (0.9 m) short, so the opening is 8 m + 2 x 0.9 m. The inner ring now
  has a gate on every street.
- `_gate_market`: every solid prop (stall, barrel cluster) keeps a 2 m corridor (1 m half width) from
  each front door to the street and straight out from it, and 1.4 m to the next solid prop. A prop is
  slid up to 4.5 m along the street to the nearest spot that satisfies both. If none exists it stays
  as scenery and gets no walk collider (`no_collide`). Stalls and barrels otherwise keep box colliders.
- `_seal_gaps`: any gap under `MIN_LOT_GAP` (1.4 m) between two lots' wall colliders is closed with a
  6 m tall `GapSeal` box across the facing walls, so every passage is at least 1.4 m or shut.
- Camera blockers are unchanged: layer `1 << 9`, mask 0, never in the player's mask (reviewed).
  Decorative props (flower strips, bunting, wall banners, banner poles) still have no collider.

## Review notes

Diff reviewed for bugs. Nothing needed changing. Worth knowing: scenery stalls keep their camera
blocker, and `no_collide` compares transforms by value (unique per placed instance, so fine).
The 100 orphans in the test summary are pre-existing.

## Screenshots (`docs/qa/stuck_check/after/`)

`door_path_6.jpg`, `door_path_10.jpg` (townhouse door paths, clear), `inner_gate_0..2.jpg` (inner wall
gates on the market streets), `gap_sealed.jpg`, `outer_gate.jpg`. The gate market render
(`--shot=gate --hour=15`) is at `/tmp/claude-0/shots/stuck_gate.png` and looks the same as the
reference: stalls, bunting and banners along the street, gatehouse centred.

## Tests

`gdUnit4 res://tests`: 435 cases, 0 errors, 0 failures.
