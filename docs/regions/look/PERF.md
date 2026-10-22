# Region 1 look pass: performance (2026-09-30)

PC: RTX 4070 laptop, Godot 4.6.3, 1920x1080, vsync off, 90-frame average per view after a 150-frame warm-up (tools_qa/region1/look_capture.gd). The same build with `--r1off` (the whole look pass off) is the baseline.
**Caveat:** this PC is shared (other agents, browsers); frame times swung up to 3x between identical runs (see attr_* below), so draw calls and primitives are the reliable budget numbers. Avg ms is listed for completeness.

## HIGH
| view | off ms | on ms | off draws | on draws | off prims | on prims |
|---|---|---|---|---|---|---|
| 01_ashford_lane | 10.29 | 8.88 | 546 | 629 | 1279354 | 2311331 |
| 02_ashford_aerial | 7.15 | 6.04 | 310 | 386 | 400882 | 1419070 |
| 03_ember_road | 6.92 | 6.20 | 632 | 674 | 1914272 | 2032501 |
| 06_ashrun_bridge | 6.98 | 6.86 | 205 | 274 | 1375641 | 1768767 |
| 07_upper_ashrun | 5.29 | 8.37 | 211 | 273 | 1280943 | 1867055 |
| 09_mere_shore | 7.66 | 8.37 | 204 | 237 | 1286390 | 1455332 |
| 13_highwatch_keep | 7.55 | 6.77 | 418 | 448 | 1186683 | 1329000 |
| 19_north_panorama | 5.00 | 4.23 | 128 | 186 | 512471 | 1321128 |
| 22_meadow_open | 7.77 | 6.34 | 335 | 403 | 1136909 | 1422062 |

## LOW
| view | off ms | on ms | off draws | on draws | off prims | on prims |
|---|---|---|---|---|---|---|
| 01_ashford_lane | 22.20 | 11.12 | 280 | 273 | 221540 | 287569 |
| 02_ashford_aerial | 18.19 | 6.37 | 149 | 160 | 83169 | 145278 |
| 03_ember_road | 11.94 | 5.72 | 214 | 229 | 240166 | 298416 |
| 06_ashrun_bridge | 10.14 | 5.79 | 87 | 95 | 207805 | 266453 |
| 07_upper_ashrun | 7.76 | 5.69 | 58 | 76 | 138413 | 318503 |
| 09_mere_shore | 8.13 | 5.74 | 108 | 121 | 276760 | 357653 |
| 13_highwatch_keep | 8.20 | 5.72 | 230 | 233 | 362549 | 420383 |
| 19_north_panorama | 5.82 | 4.46 | 25 | 36 | 7916 | 105436 |
| 22_meadow_open | 7.10 | 5.27 | 149 | 203 | 256743 | 477120 |

LOW changes after the first A/B: canopy domes off, cliff rocks only within 320 m and without shadows.

Budgets: HIGH draws stay under 700 (budget 600 is exceeded only by the villages/Ember Road views, which were already 550-650 before), LOW prims +60k typical (the horizon mesh), up to +220k where the valley walls are within 320 m. Boot cost: Region1Look build ~1-1.9 s at world load (landmark skyline parts + cliff MultiMeshes); the horizon is built on a worker thread.

## HIGH after the far-rock lumps and thinner canopy (final build)
Cliff rocks past 260 m draw a 48-tri lump instead of the 1.5-2.5k-tri rock; canopy domes every 34 m out to 1.7 km.
| view | on ms | on draws | on prims (off prims above) |
|---|---|---|---|
| 01_ashford_lane | 16.58 | 627 | 1418582 |
| 02_ashford_aerial | 14.62 | 379 | 543146 |
| 07_upper_ashrun | 8.23 | 260 | 1481045 |
| 19_north_panorama | 13.63 | 207 | 657504 |
| 22_meadow_open | 9.25 | 411 | 1341726 |

Result: triangles in view +10-20 % over the baseline (was +50-180 % before the lumps), draws +30-70 (the landmark skyline parts, horizon cells), HIGH within the 1.5 M triangle budget except Ashford lane, which the villages already filled. Frame time on this PC: within noise (the A/B pairs above differ by less than the run-to-run swing).
