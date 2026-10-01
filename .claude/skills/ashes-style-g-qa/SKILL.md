---
name: ashes-style-g-qa
description: Scorecard and tools to judge any Rising Ashes screenshot against Style G / target 03 (gate market) - side-by-side compare with objective metrics, weighted checklist, minimum score to ship, and fixes for the usual failures (grey, flat, empty, cool light, neon ivy, orange goods). Use after every visual change and before telling the owner a scene "matches".
---

# Style G QA scorecard

Target: `docs/art/reference/03_TARGET_gate_market_detailed.webp`. Recipe: skill `ashes-style-g`. Assets: `ashes-style-g-assets`.

## 1. Render the same four views every time
`/tmp/claude-0/styleg/render.sh <log> <out-prefix> [high|medium|low]` (copy of the Style Lab renderer; waits for >8500 MB free; xvfb + vulkan,
`--quality=high -- --shot=style_lab --box=G --tier=T --out=P`). Writes `P_G_over|close|facade|gate|stall.png` and `P_stats.json`
(draw_calls, primitives, shadow_*). If the script is gone, the command is:
`xvfb-run -a -s "-screen 0 1280x720x24" godot --path kingdom --rendering-driver vulkan --quality=high -- --shot=style_lab --box=G --tier=high --out=/tmp/claude-0/styleg/pN`
Never `pkill -f`; read the log for `style_lab G over ->` and `EXIT 0` (a render takes about 8 min).
For a game scene (not the lab) use `ashes-visual-qa` to get a gameplay-camera shot, then score it the same way.

## 2. Compare
```
python3 kingdom/tools_qa/style_lab/make_compare.py <render.png> docs/art/reference/03_TARGET_gate_market_detailed.webp <sheet.png> "G pass N" "Target 03"
```
Writes the 2-up sheet AND prints metrics (render vs target 03): `warmth` R/B mean (1.34), `sat` (0.40), `contrast` luminance std (0.23),
`detail` edge density (0.071), `green` foliage fraction (0.017), `shadow_b` B-R in darkest 20% (-0.06). Read the sheet with Read, then score.
Metrics that are off by more than 25% name the failure (section 5).

## 3. Scorecard (100 points)
| Category (weight) | Full marks when |
|---|---|
| Composition (20) | Hero at bottom centre seen from behind, street converges on ONE landmark (gatehouse) in the upper-middle third, buildings frame both sides, sky visible above the towers, camera low (1.95 m) |
| Light warmth (15) | Warm golden key from behind-left, crisp but soft shadows falling forward-right, golden bounce visible on cobbles/undersides, shadows slightly cool not black or orange mud, warm haze at depth; `warmth` 1.25-1.45 and `shadow_b` -0.10..0.0 |
| Material richness (15) | Stone and cobbles show real relief, plaster is weathered not flat, timber has grain, roofs have tile rhythm; `detail` >= 0.06 |
| Density (15) | No bare facade: ivy + flower boxes + signs; stalls crammed (2 rows of goods + hanging goods); props along both street edges; `green` >= 0.012 |
| Crowd (10) | 20-26 people at all depth bands, varied clothes and poses (walk and talk), guards at the gate and stalls |
| Hero (10) | Brown-haired traveller: green tunic, brown hooded leather vest, satchel, bracers, boots; readable at 1.8 m, not a grey mannequin |
| Colour (10) | Saturated but not neon: blue sky and slate, red/gold banners, striped awnings, golden stone; ivy a deep leaf green; nothing orange-glowing; `sat` 0.34-0.48 |
| Gate (5) | Pointed arch with visible voussoir ring, raised portcullis, banners, crenellations, conical turret roofs, ivy on the tower foot |

Score each 0-10, multiply by weight/10. **Ship minimum: 75 total and no category below 5/10.** Report the number, the sheet path and the
three lowest categories. G pass history: baseline 55-60 %, kit pass 3 about 72 % (just under the bar: hero 4/10, material richness 6/10; see `ashes-style-g` log).

## 4. Budgets checked with the same run (from `P_stats.json`, "over" camera, per tier)
HIGH: <= 200 draws, <= 600k tris (G now 164 / 565k). MEDIUM: <= 170 draws, <= 450k. LOW: <= 150 draws, <= 300k visible tris, 2 shadow splits (G now 134 / 379k: tris still over).
Failing a budget fails the pass even if the picture is perfect.

## 5. Failure -> fix
| Symptom (metric) | Fix |
|---|---|
| Too grey (`sat` < 0.30, warmth < 1.2) | `adjustment_saturation` 1.22+, sun colour `ffd6a0` x2.7, wall `value_gain`/`warm_tint` in `StyleG._polished`, check the Environment was not overwritten by `Quality` autoload (re-apply after it) |
| Too flat (`contrast` < 0.19) | `adjustment_contrast` 1.22, SSAO intensity 2.8 (HIGH), `ao_strength` 0.5 and `ao_height` 1.6 on houses, shadow splits >= 2 |
| Too empty (`detail` < 0.055, `green` < 0.01) | Run ivy + flower boxes + tubs + baskets + stall dressing (`lab_gate_extra.gd`), more crowd, banner every 12 m |
| Cool light (warmth < 1.2, blue cobbles) | Fog `ecdcbc`, bounce light `ffb870` 0.4, `ground_bounce (1.0,0.70,0.36)`, ambient `aab8ee` not deeper blue |
| Muddy orange (`shadow_b` < -0.12, orange barrels) | Lower `bounce` (0.3 on wood/goods), saturation 1.12 on wood/goods, bounce light energy <= 0.4 |
| Neon ivy | ivy shader saturation 0.95, value_gain 0.78, vertex greens `3a6a22..6f9e30`, instance colour hsv(0.24-0.31, 0.55-0.8, 0.7-0.95) |
| Brown gate stone | Do not warm `atlas_color` of `gate_stone` (castle_wall_slates turns brown); keep (0.95,0.94,0.92); trim blocks use the polished limestone `dccfb4` |
| Draw calls over budget | Merge static props per material (`lab_gate.gd _bake_static`), MultiMesh repeats, LOD1/2 houses, `lod1` characters beyond 24 m, tier low drops folk to 14 |
| Black characters | Never use the SSS pass; `lab_char` shader only; G6 `human_*` meshes ignore vertex colour |
