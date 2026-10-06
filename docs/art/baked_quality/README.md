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
