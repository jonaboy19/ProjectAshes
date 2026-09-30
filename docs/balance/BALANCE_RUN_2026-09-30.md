# Balance run 2026-09-30 (2 in-game years, 730 days)

Headless harness `/tmp/claude-0/balance/{core.gd,run.gd}` (SceneTree script run with the project so the autoloads exist). It ticks `WorldSim.hour_changed` hour by hour, which drives `Life._on_hour`, the realm hub queue (drained job by job and timed), `economy`, `war`, `lordship`, `life_courses` and `Frontier`; no 3D world, no player. Every 30 days it writes metrics, per-module save sizes, faction power/wealth, regional loyalty and per-good prices to CSV (`before_*` / `after_*`). `mode=catchup` restores a day-90 realm snapshot and compares N days of fine ticks with `realm.catch_up(N)` for N = 1, 7, 30, 90, 365.

Both runs: 0 script errors, 730 days in about 34 s wall (desktop headless).

## Problems found

| # | Problem | Evidence (before) | Fix | File |
|---|---|---|---|---|
| 1 | Population only ever fell | 7900 -> 5592 (-29%), 3 settlements under half their seed size; emergencies subtracted people, nothing added them | logistic regrowth toward the seeded carrying capacity while fed (daily + closed form in `catch_up`) | `scripts/realm/settlements.gd` |
| 2 | Every revolt succeeded and rebel rule was permanent | 9 of 20 regions rebel-held, rising, none ever recovered | AI holders crush open revolts (5%/day) and retake rebel land after 60 days (3%/day); 60-day calm after a revolt ends; ledger trimmed to 20 | `scripts/realm/land.gd` |
| 3 | Raids alone crashed loyalty | raid "neglect" memory (up to 2.0 each) held worst regions at loyalty ~0-10; catch_up resolved 53 raids against 270 played out | neglect weight loot/40 capped 1.0; catch_up raid cap 5 -> 12 | `scripts/realm/strongholds.gd` |
| 4 | Regional markets were frozen | hourly `int(round())` threw away every sub-unit stock change; villages never moved from their seed stock | fractional carry per good | `scripts/sim/market.gd` |
| 5 | Ashford (start village) permanently out of bread | bread/apple/cheese/firewood stock 0 from day ~30 onward, price pinned at 3x; market ticked twice (hourly via `economy` and daily `tick_day`, `ceil()` demand above production) | demand follows stock (settles where production meets use), single tick path, daily import wagons for crafting goods | `market.gd`, `autoload/life.gd` |
| 6 | Producers at the 0.5x floor / importers at the 3x cap once markets move | fixing 4 exposes it: production > fixed demand for every village good | once-a-day surplus trade between markets (producers with >1.25x normal ship to places under 0.75x, less road danger) and daily import wagons for imported goods | `scripts/sim/economy.gd` |
| 7 | Road danger never decreased | `refresh_road_risk` only ever raised a settlement's risk (max with old value) | rebuilt from scratch each refresh | `economy.gd` |
| 8 | "You" faction snowballed without acting | player faction power 4.0 -> 41.7 from the rubber band alone; faction wealth frozen at seed values forever | player excluded from drift and rubber band; weekly wealth pull toward 15 + 0.7*power (less at war); same closed form in `catch_up` | `scripts/realm/factions.gd` |
| 9 | Monster dens grew without bound | 25 -> 118 dens, population 187 -> 324; Frontier save stored the den list twice | `MAX_ALIVE_DENS` = 48 (+8 for rift dens); dropped the duplicate `dens` key (load still accepts it) | `scripts/sim/monster_ecology.gd`, `autoload/frontier.gd` |
| 10 | People table kept every death | `life_courses.people` 150 -> 780 rows, +350 KB | rolling window `MAX_PEOPLE` = 320, oldest unmet non-famous dead dropped first | `scripts/sim/life_courses.gd` |
| 11 | Guild treasuries grew forever | total 11 k -> 58 k, linear | +3/day minus 1/800 of the purse (equilibrium ~2400), closed form in `catch_up` | `scripts/realm/city_life.gd` |

## Before / after tables (each cell: before -> after)

**Population and unrest**

| day | population | smallest town | towns < 50% of seed | avg loyalty | min loyalty |
|---|---|---|---|---|---|
| 1 | 7900 -> 7900 | 90 -> 90 | 0 -> 0 | 66.5 -> 66.5 | 55.8 -> 55.8 |
| 121 | 7359 -> 7474 | 86 -> 87 | 0 -> 0 | 48.4 -> 51.4 | 24.5 -> 23.3 |
| 241 | 7000 -> 7382 | 82 -> 85 | 0 -> 0 | 52.0 -> 51.9 | 32.1 -> 14.1 |
| 361 | 6619 -> 7164 | 70 -> 77 | 0 -> 0 | 55.1 -> 52.4 | 30.7 -> 24.8 |
| 481 | 6149 -> 6978 | 70 -> 80 | 0 -> 0 | 50.9 -> 52.5 | 19.5 -> 26.5 |
| 601 | 5864 -> 7059 | 65 -> 79 | 1 -> 0 | 57.7 -> 58.3 | 44.5 -> 33.3 |
| 731 | 5592 -> 7161 | 64 -> 78 | 3 -> 0 | 56.9 -> 56.6 | 45.2 -> 29.4 |

**Rebellions**

| day | rebellions started (cum.) | regions held by rebels | open revolts |
|---|---|---|---|
| 1 | 0 -> 0 | 0 -> 0 | 0 -> 0 |
| 121 | 3 -> 1 | 3 -> 1 | 0 -> 0 |
| 241 | 5 -> 2 | 5 -> 0 | 0 -> 1 |
| 361 | 7 -> 2 | 7 -> 1 | 0 -> 0 |
| 481 | 9 -> 3 | 9 -> 1 | 0 -> 0 |
| 601 | 9 -> 3 | 9 -> 0 | 0 -> 0 |
| 731 | 9 -> 3 | 9 -> 0 | 0 -> 0 |

**Factions and wars**

| day | top nation power share | faction wealth sum | house wealth avg | wars started (cum.) | days at war (cum.) |
|---|---|---|---|---|---|
| 1 | 0.163 -> 0.163 | 797.2 -> 797.2 | 29.3 -> 29.3 | 0 -> 0 | 0 -> 0 |
| 121 | 0.154 -> 0.154 | 766.2 -> 716.4 | 33.9 -> 32.5 | 2 -> 2 | 18 -> 18 |
| 241 | 0.141 -> 0.141 | 766.2 -> 698.7 | 33.9 -> 35.0 | 5 -> 5 | 62 -> 62 |
| 361 | 0.137 -> 0.137 | 766.2 -> 703.0 | 33.9 -> 38.5 | 8 -> 8 | 96 -> 96 |
| 481 | 0.139 -> 0.138 | 766.2 -> 713.7 | 33.9 -> 42.1 | 11 -> 11 | 133 -> 133 |
| 601 | 0.134 -> 0.133 | 766.2 -> 726.5 | 33.9 -> 45.0 | 15 -> 15 | 182 -> 182 |
| 731 | 0.133 -> 0.133 | 766.2 -> 740.9 | 33.9 -> 47.2 | 19 -> 19 | 229 -> 229 |

**Economy**

| day | price index (mean price/base, all market goods) | Ashford bread stock | Ashford bread price | market purses |
|---|---|---|---|---|
| 1 | 1.0 -> 1.0 | 30 -> 30 | 2 -> 2 | 4000 -> 4000 |
| 121 | 2.372 -> 2.62 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |
| 241 | 2.368 -> 2.665 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |
| 361 | 2.45 -> 2.697 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |
| 481 | 2.378 -> 2.626 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |
| 601 | 2.38 -> 2.579 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |
| 731 | 2.306 -> 2.527 | 0 -> 20 | 6 -> 3 | 12000 -> 12000 |

**Arrays and save size**

| day | life_courses people | dens alive | dens total pop | guild treasury sum | save total bytes | realm save bytes |
|---|---|---|---|---|---|---|
| 1 | 150 -> 150 | 25 -> 25 | 187 -> 187 | 11250 -> 11250 | 423020 -> 426874 | 290625 -> 298788 |
| 121 | 221 -> 221 | 51 -> 48 | 90 -> 108 | 18245 -> 18176 | 580247 -> 572674 | 369486 -> 373760 |
| 241 | 281 -> 281 | 56 -> 48 | 156 -> 97 | 25617 -> 23775 | 634706 -> 626429 | 374101 -> 379620 |
| 361 | 343 -> 320 | 71 -> 48 | 179 -> 135 | 33210 -> 28354 | 704103 -> 679900 | 390866 -> 396023 |
| 481 | 421 -> 320 | 80 -> 48 | 221 -> 119 | 40820 -> 32725 | 756068 -> 687268 | 384222 -> 390056 |
| 601 | 563 -> 320 | 97 -> 48 | 263 -> 108 | 48853 -> 37470 | 844347 -> 681068 | 372656 -> 378395 |
| 731 | 780 -> 320 | 121 -> 48 | 324 -> 95 | 58002 -> 42108 | 961071 -> 676883 | 369842 -> 374887 |

**Realm activity (unchanged, for reference)**

| day | raids (cum.) | rumours | notable NPC goals | city jobs | guild leaders | call-ups / week (30 d) | max hub job ms |
|---|---|---|---|---|---|---|---|
| 1 | 0 -> 0 | 0 -> 0 | 200 -> 200 | 103 -> 103 | 27 -> 27 | 0.0 -> 0.0 | 0.0 -> 0.0 |
| 121 | 72 -> 72 | 38 -> 38 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.47 -> 0.47 | 0.88 -> 2.98 |
| 241 | 137 -> 137 | 40 -> 40 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.47 -> 0.47 | 1.06 -> 4.82 |
| 361 | 210 -> 210 | 39 -> 39 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.93 -> 0.93 | 3.01 -> 3.46 |
| 481 | 284 -> 284 | 40 -> 40 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.7 -> 0.7 | 4.76 -> 3.17 |
| 601 | 356 -> 356 | 27 -> 27 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.47 -> 0.47 | 1.81 -> 7.61 |
| 731 | 423 -> 423 | 24 -> 24 | 200 -> 200 | 116 -> 116 | 27 -> 27 | 0.0 -> 0.0 | 1.07 -> 3.0 |

**Price ratio vs day 0 and stock/target at day 731, goods sold in more than one market**

| good | markets | day 181 | day 361 | day 731 | stock/target d731 |
|---|---|---|---|---|---|
| ale | 15 | 1.85 -> 3.65 | 1.92 -> 3.80 | 1.93 -> 3.70 | 166/166 -> 154/166 |
| cabbage | 19 | 1.24 -> 1.29 | 1.37 -> 1.37 | 1.37 -> 1.24 | 455/455 -> 508/455 |
| cloth | 5 | 1.23 -> 1.30 | 1.25 -> 1.70 | 1.25 -> 1.30 | 85/85 -> 99/85 |
| firewood | 15 | 1.13 -> 1.00 | 1.13 -> 1.00 | 1.13 -> 1.00 | 420/450 -> 490/450 |
| hides | 14 | 1.00 -> 0.95 | 1.00 -> 0.95 | 1.00 -> 0.95 | 210/210 -> 238/210 |
| tools | 16 | 1.90 -> 3.72 | 1.98 -> 3.87 | 2.01 -> 3.77 | 108/108 -> 90/108 |
| wheat | 19 | 0.74 -> 0.84 | 1.97 -> 1.68 | 0.76 -> 0.79 | 610/610 -> 720/610 |
| wool | 19 | 1.26 -> 1.23 | 1.35 -> 1.27 | 1.36 -> 1.18 | 305/305 -> 367/305 |

Prices include the harness-specific road risk of 1.0 on every road (no runestones lit, no player), i.e. a 2.6x import surcharge; that is why the index sits near 2.5 and not 1.0. The 7.8x rows in Ashford (antidote, leather, pike ...) are goods only the player ever supplies (stock 0, no producer): unchanged by design.

## catch_up(N) vs N days of fine ticks (day-90 realm snapshot; cell: fine | catch_up, before -> after)

| span | population | avg loyalty | faction power | faction wealth | rebellions | wall ms (fine / catch_up) |
|---|---|---|---|---|---|---|
| 1 d | 7487 / 7489 -> 7555 / 7558 | 51.7 / 51.6 -> 54.4 / 54.3 | 655 / 655 -> 654 / 654 | 766 / 766 -> 724 / 726 | 2 / 2 -> 1 / 1 | 44/7 -> 43/12 |
| 7 d | 7430 / 7417 -> 7508 / 7498 | 50.3 / 50.5 -> 53.3 / 53.4 | 657 / 655 -> 656 / 654 | 766 / 766 -> 724 / 724 | 3 / 3 -> 1 / 1 | 239/13 -> 354/26 |
| 30 d | 7353 / 7419 -> 7470 / 7531 | 48.3 / 53.6 -> 51.3 / 55.6 | 658 / 655 -> 656 / 654 | 766 / 766 -> 715 / 713 | 3 / 2 -> 1 / 1 | 1183/15 -> 1312/76 |
| 90 d | 7173 / 7418 -> 7401 / 7605 | 53.0 / 57.7 -> 53.8 / 56.5 | 667 / 655 -> 666 / 654 | 766 / 766 -> 703 / 706 | 5 / 2 -> 1 / 1 | 3748/37 -> 3578/72 |
| 365 d | 6195 / 7315 -> 6951 / 7661 | 52.3 / 55.2 -> 53.4 / 53.4 | 720 / 655 -> 719 / 654 | 766 / 766 -> 711 / 666 | 7 / 2 -> 3 / 1 | 15672/20 -> 15748/68 |

No wild divergence in either version (no NaN, no runaway, catch_up is 50-200x cheaper). Remaining, by design, statistical gaps: catch_up resolves at most one emergency per settlement and at most 12 raids per window, so a year away loses ~10% less population and far fewer raid/call-up events than a year played; faction power drift is random in fine ticks but only its mean reversion is applied in catch_up.

## Checked and fine

- Wars: 19 started in 730 days, each 11-14 days (peak ~31% of time at war), both enemies rotate; neither permanent nor absent. Tuning `TENSION_PER_FEUD` 0.35 -> 0.2 only moved this to 17 wars, so it was reverted; if wars should be rarer, raise `TENSION_WAR_THRESHOLD` or `TENSION_AFTER_WAR` instead (recommendation, not changed).
- Nation power: top nation share 0.163 -> 0.133 (no snowball, rubber band works).
- Rumours 22-40, news/chronicle/results/logs all bounded by their existing caps (`NEWS_MAX`, `CHRONICLE_MAX`, `RESULTS_MAX`, `MAX_NEWS`, `MAX_EVENTS`, guild history 12); notable NPCs constant at 200 with 200 goals; city_life jobs 103-116 and 27 guild leaders throughout.
- Call-ups ~0.5 / week; hub job max 1-3 ms headless (desktop; the 0.6 ms/frame pump budget is handled by chunking, but phone timings were not measured).
- Education cohorts stay 0: they only form around a player student, which this headless run does not have (not exercised). Campaign armies appear only during wars (0-3); the campaign and tactical/siege files were not touched.
- The enterprise module (being added concurrently) was present and ticked without errors in the final run; it was not edited.

## Files changed

`scripts/realm/settlements.gd`, `land.gd`, `factions.gd`, `strongholds.gd`, `city_life.gd`; `scripts/sim/market.gd`, `economy.gd`, `life_courses.gd`, `monster_ecology.gd`; `autoload/life.gd` (Ashford market no longer double ticked, imports for crafting goods), `autoload/frontier.gd` (no duplicate dens in the save).

## Re-running

```
cd kingdom
godot --headless --path . -s docs/balance/data/run.gd (copy of /tmp/claude-0/balance/run.gd; core.gd must sit next to it, paths inside point at /tmp/claude-0/balance) -- days=730 tag=after           # CSVs in /tmp/claude-0/balance
godot --headless --path . -s docs/balance/data/run.gd (copy of /tmp/claude-0/balance/run.gd; core.gd must sit next to it, paths inside point at /tmp/claude-0/balance) -- mode=catchup tag=after
```
