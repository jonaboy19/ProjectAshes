# Hitch pass results (2026-10-23)

Interleaved A/B on one build (`--perf-legacy` = before), 2 runs each, medians, steady window. Laptop on DC power for part of the session, other Godot processes 2-4; see raw/context.txt. 'dens' = after + NPC density rows.

| scenario | build | runs | fps (median) | p50 ms | p95 ms | p99 ms | max ms | >33ms /min | >50ms /min | >100ms /min |
|---|---|---|---|---|---|---|---|---|---|---|
| A_stand_1440 | after | 2 | 23.9 | 41.2 | 55.1 | 60.8 | 65 | 1222 | 237 | 0 |
| A_stand_1440 | after | 2 | 21.9 | 45.6 | 57.5 | 63.0 | 66 | 1282 | 351 | 0 |
| A_stand_1440 | before | 2 | 8.5 | 123.3 | 141.5 | 145.9 | 149 | 510 | 504 | 407 |
| B_walk_1440 | after | 2 | 25.7 | 40.3 | 58.2 | 62.1 | 65 | 996 | 350 | 0 |
| B_walk_1440 | before | 2 | 15.9 | 47.2 | 134.8 | 143.9 | 148 | 679 | 451 | 203 |
| C_stand_1080 | after | 2 | 22.0 | 45.1 | 58.6 | 62.1 | 65 | 1210 | 417 | 0 |
| C_stand_1080 | before | 2 | 11.1 | 94.7 | 133.5 | 140.9 | 146 | 658 | 592 | 274 |
| D_t3d_stand_1440 | after | 2 | 21.3 | 46.9 | 59.1 | 62.9 | 65 | 1258 | 429 | 0 |
| D_t3d_stand_1440 | before | 2 | 9.3 | 112.6 | 140.0 | 146.9 | 148 | 561 | 560 | 348 |
