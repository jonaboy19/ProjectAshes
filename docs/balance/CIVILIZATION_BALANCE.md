# Living-world balance: 15 years, all modules together

Harness: `docs/balance/data/world15_sim.gd` (run from `kingdom/`:
`godot --headless --path . -s /home/user/ProjectAshes/docs/balance/data/world15_sim.gd -- seeds=1066,2024 years=15 verbose=1`).
It drives every realm module through `realm_hub` (hour ticks + day chunks, drained job by job), with a scripted war in years 7-8 and a 365-day year.
Seeds are WorldGen seeds (`WorldSim.SEED` is a const, so module RNG streams are shared; the two worlds differ in settlement layout).
Debug switches: `watch=s1 every=30`, `probe=<sid> probe_from=<day>` (who drains a settlement's grain), `kinds=wave,arrival`.

## Targets vs actuals (final run)

| Target | Seed 1066 | Seed 2024 | OK |
|---|---|---|---|
| Camps founded gradually, ~0-2/yr, not all 12 in 5 y | 11 in 15 y: 1,1,1,1,1,1,1,2,0,0,1,1,0,0,0 | 10 in 15 y: 0,0,2,2,0,1,1,0,1,0,1,0,1,0,1 | yes |
| A few camps fail | 2 failed to ruin | 5 failed | yes |
| Kingsreach stable-to-growing | 1600 -> ~1420-1620 (peak 1818; war dip to 1260 in y8) | 1600 -> 1857 (peak 1915; war dip 1291) | yes (war dip recovers; y15 value varies by run) |
| Famines <= 1-2 / 15 y region-wide | 3 (was 54) | 0 (was 69) | borderline / yes |
| Migration waves 10-40/yr | 27.5/yr (war y7-8 ~220/yr, ~8/yr otherwise) | 24/yr | yes (was ~135/yr) |
| Named quarters by y15 | 6-7 | 6 | slightly high |
| Successions (80-88 institutions) | 72 (tenure ~16 y) | 91 (~14 y) | yes |
| Law changes | 39 (about 2 per settlement) | 39 | yes (was 182) |
| Delegations <= 2/yr, embassies 1-3 | 21 (1.4/yr), 2 | 21, 2 | yes (was 111) |
| Revolts 0-2, none in y1 | 1, y2+ | 0 | yes |
| Ecology varied | no species extinct; trolls slain by adventurers return | same | yes |
| Whole-realm save < 1 MB | 0.72 MB | 0.73 MB | yes |
| Pump job median < 0.6 ms | day-chunk medians 10-125 us; worst `land` ~0.57-0.62 ms under two parallel runs | similar (0.51-0.56) | yes (land is an old module, borderline) |

Before tuning (same harness): 12 camps in 5 y with no failures, 54-69 famines (Kingsreach starved every winter, 1600 -> ~800-1250), 135 waves/yr, 31 quarters, 111 delegations, 182 laws.

## What was changed (constants)

- settlements.gd: winter farm yield 0.1 -> 0.35 (spring 0.7, autumn 1.7), stock cap 4000 -> 12000, starting stocks in days of food (a capital began with 1.5 days and starved on day 10), fire chance 1.0% -> 0.25% a day (an unanswered fire halved the grain store every ~3 months), winter plague band narrowed.
- civilization.gd: static food capacity uses what a chain farm really feeds (68, not 40) and farmsteads / irrigation now add real farm chains in settlements; founding `FOUND_P` 0.06/week, from day 120, 75 days between foundings (notables share the pace); `CAMP_FAIL_P` makes young camps fail (more when ecology danger is high); ecology `monster_pressure` and `adventurer_economy` feed safety and attraction.
- migration.gd: pull waves rarer and larger (`PULL_P`, `PULL_MIN`), outside-boom waves rarer, quarters need more sustained inflow, governance `emigration_pressure` adds push (cause "harsh rule").
- governance.gd: law changes need an angry bloc and a 2000-day cooldown, petitions respect it, 300-day grace before revolts, higher re-election odds.
- news.gd: delegation chance 0.15 -> 0.035 a week; routine flows (migration waves/arrivals, mag < 0.5) stay out of the gossip ring.

## Chronicle excerpt (seed 2024)

```
Y01 d008  [ecol] The Grimtusk host raided Ravenscar and got away with food and plunder.
Y01 d029  [civi] Iron has struck Eastmere; word is spreading along the roads.
Y01 d132  [migr] Weapon-Master Hale Vell has settled in Westfen.
Y01 d297  [nota] Renel Ember opens the Ember School of Letters at Cindermoor.
Y02 d027  [gove] Gildan Fallow elected guildmaster of Smiths' Guild of Millbrook after the guildmaster stepped down.
Y03 d000  [civi] A prospector and her crew have raised a camp at Amberhollow.
Y03 d046  [ecol] Adventurers have slain the bear that haunted Brackenmoor.
Y03 d207  [ecol] A troll has moved into the hills above Westfen.
Y04 d139  [civi] A prospector and her crew have raised a camp at Copperford.
Y04 d226  [nota] Nobody stopped the trouble at Brackenmoor. The damage is done.
Y05 d325  [civi] Amberhollow has grown into a village.
Y06 d115  [civi] Rift Crystal has struck Emberfall; word is spreading along the roads.
Y06 d225  [gove] Elmund Nettle elected headman of Greywatch after the headman died.
Y06 d291  [civi] A merchant's guild have raised a camp at Ambermere.
Y07 d124  [civi] Copperford is abandoned. Its empty streets remain as a ruin.
```
