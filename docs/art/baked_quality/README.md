# Baked quality - gate market (bench "city"), 2026-10-06

Images: `before_city_low|high.png`, `after_city_low|high.png`, side by side `cmp_low|high.png` (left before, right after). Target: `docs/art/reference/00_MAIN_kingsreach_gate_market.webp`.

| PC Mobile renderer | LOW before | LOW after | HIGH before | HIGH after |
|---|---|---|---|---|
| draw calls | 161 | 171 | 557 | 701 |
| primitives | 509k | 518k | 1.97M | 2.09M |
| VRAM MB | 1047 | 1094 | 1455 | 1467 |

Caveats: laptop on battery (18 %), fps 5-8 in all runs = invalid; NPCs/stalls differ per run (after-HIGH shows extra stalls and people).
The HIGH draw rise is partly real (material duplicates per baked surface, see skill next step 1). Phone: S22 not connected.

Honest score vs target (0-10): LOW 3 before -> 3.5 after; HIGH 4 -> 4.5. Baked AO/warm-cool gives walls and houses depth, but the gap is
composition and dressing (no timber-framed street fronts, awnings, foliage, crowd, banners density, painterly textures), not lighting.

## Phase 2 (2026-10-06, laptop on charger, PC Mobile renderer)
Images: `p2_city_low.png`, `p2_city_high.png` (target: docs/art/reference/00_MAIN_kingsreach_gate_market.webp).
| | LOW before | LOW after | HIGH before | HIGH after |
|---|---|---|---|---|
| draws | 172 | 131 | ~700 | ~530 |
| primitives | 519k | 448k | 2.09M | 1.80M |
| VRAM MB | 1110 | 1165 | 1460 | 1464 |
fps unchanged within noise (LOW ~96-110, HIGH ~55-58, CPU-bound by NPCs).
Findings: (1) the 557->701 "regression" was NOT the baked-AO material copies (they are cached per source material): with baking off HIGH measured 684.
Shadow passes are ~290 of HIGH's draws (no-shadow run: 414); town-hidden floor is 65 (LOW) / 167 (HIGH).
Done: surface collapse now also on HIGH (lit windows kept on LOD0), HIGH shadow_min 1.0->2.5 and dist 100->60, far-stage texture atlas (41 stages, one 2048 page)
+ StaticMerge of those stages per 40 m cell on LOW. Targets NOT met: LOW <120 (131), HIGH <300 (~530).
Dead ends: merging plain props (black wall-window patches, 7 draws); merging on HIGH (+90 MB, +1 s CPU for 4 %).
Not done: gatehouse/wall bake, fog haze + skyline impostors.
Honest score vs target: LOW 3.5, HIGH 4.5 (unchanged; geometry/dressing gap, not lighting).
