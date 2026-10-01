---
name: ashes-style-g
description: The master recipe for Rising Ashes' chosen look, Style G (Kingsreach gate market, target 03) - exact Environment, sun, fill, shadow tiers, hex palettes, shader and parameters per material role, camera, composition and density rules, per-tier differences, budgets, and how to apply it to any game scene via scripts/style_g.gd and resources/style_g. Use for any lighting, material, post-processing, scene dressing or camera work.
---

# Style G: recreate it exactly

Chosen by the owner ("by far the best"). Target image: `docs/art/reference/03_TARGET_gate_market_detailed.webp` (also `00_MAIN_...`).
Judge with `ashes-style-g-qa`; build assets with `ashes-style-g-assets`. Older `ashes-art-style` is the general mood; where it differs, G wins.

## 0. Where the truth lives (do not retype numbers from this file into code)
- `kingdom/scripts/style_g.gd` (no class_name; `const StyleG := preload("res://scripts/style_g.gd")`):
  `apply_environment(env, tier)`, `make_environment(tier)`, `apply_sun(sun, tier)`, `make_sun(tier)`, `make_fill()`, `material_for(role, orig_material, skin_kind, tier, use_vcol)`,
  `double_sided(mat)`, `PALETTE`, `SHADOW`, `TIERS`.
- `kingdom/resources/style_g/`: baked `env_high|medium|low.tres` and `mat_ground|gate_stone|gate_trim|iron|banner|flag.tres`.
  Re-bake after editing style_g.gd: `godot --headless --path kingdom -s tools_qa/style_lab/bake_style_g.gd`.
- Lab scene: `scripts/style_lab/lab_gate.gd` (+ `lab_gate_extra.gd` dressing kit, `lab_style.gd` G path delegates to StyleG), shaders `shaders/style_lab/`.
- Reproduce the lab: `godot --path kingdom --rendering-driver vulkan --quality=high -- --shot=style_lab --box=G --tier=high|medium|low --out=PREFIX`.

## 1. Environment (HIGH; exact values in style_g.gd `apply_environment`)
| Item | Value |
|---|---|
| Sky | `lab_sky.gdshader`: top `2563d8`, horizon `d8e6ff`, ground `8a9a6a`, cloud `ffffff`, cloud shade `b4c4e8`, cover 0.55, soft 0.14, sun_glow 0.5, radiance 32 |
| Ambient | source COLOR `aab8ee`, energy 0.66 (sky colour, never grey) |
| Tonemap | FILMIC, exposure 0.92, white 5.5 |
| SSAO (HIGH, Forward+/Mobile only) | radius 1.6, intensity 2.8, light_affect 0.2 |
| Glow (not LOW) | intensity 0.5, bloom 0.1, hdr_threshold 1.0, SOFTLIGHT |
| Fog | on, colour `ecdcbc` (slightly warm), density 0.0030, aerial_perspective 0.5, sky_affect 0 |
| Adjustments (not LOW) | saturation 1.22, contrast 1.3, colour-correction LUT 64 px: shadow `0a1240`, mid `8a88a4`, high `fff0d0` |

## 2. Lights
- **Sun**: colour `ffd6a0`, energy 2.7, direction (0.55,-0.62,-0.55) (from behind-left; shadows fall forward-right), blur 1.0, angular distance 0.35.
- **Bounce fill (fake GI)** `make_fill()`: shadowless DirectionalLight3D travelling UP (direction (-0.45, 0.55, 0.45)), colour `ffb870`, energy 0.3, specular 0. Fills jetty undersides and awnings.
- **Hemispheric bounce in `lab_polished`**: `ground_bounce (1.0,0.70,0.36)`, `sky_bounce (0.55,0.66,0.98)`, `bounce` 0.36 (0.3 on wood/goods/props, 0.25 ivy), rim 0.5.
- Do not add omni lights except one lantern; the glow sprite is the cheap version.

## 3. Shadows per tier (`StyleG.SHADOW`)
| Tier | Splits | Max distance | Notes |
|---|---|---|---|
| HIGH | 4 | 110 m | SSAO on |
| MEDIUM | 2 | 70 m | no SSAO |
| LOW (Compatibility) | 2 | 45 m | no SSAO, no glow, no adjustment pass; atlas 2048 (phone project setting), `lab_polished_lite` |

## 4. Palette (hex, `StyleG.PALETTE`)
stone `c9bfa8` (shadow `8f8aa0`), cobble `c8b48a`, timber `4a3220` / light `7a5330`, plaster `efe3c8`, roof slate `5d7391`, roof terracotta `b4532f`,
awning red `c8281e` / white `f4ecd8` / green `3f8a3c`, banner red `c71a17` + gold `f2bd38`, foliage `5f9a2e` (rim `b7d44a`), ivy `3f7a24`,
flowers red `d8342b`, pink `e8789a`, yellow `f5c93a`, purple `8a62c8`, iron `2a2827`, crate wood `9a6a38`, sack `d9c28f`, hero tunic `4d7538`, hero vest `5c381f`.
Rule: no pure black, white or grey. Shadows slightly cool-violet, lights golden.

## 5. Material by role (one place: `StyleG.material_for`)
| Role | Shader | Key parameters |
|---|---|---|
| ground (cobbles/mud/grass, vertex-colour splat R=mud B=cobble) | `lab_ground` mode 1 | Poly Haven `cobblestone_floor_01`, `brown_mud_02`, `leafy_grass` (diff, nor_gl, arm); tile 3.2; cobble_tint (1.04,0.95,0.84); mud_tint (1.15,0.95,0.78); grass_tint (0.85,1.15,0.5); saturation 1.0; puddles 0 |
| gate_stone (towers, walls) | `lab_grounded` (cull_disabled copy) | `castle_wall_slates`, tile 4/4, detail 1, chroma_keep 0, saturation 0.8, grime 0.35, moss 0.12, atlas_color (0.95,0.94,0.92) |
| gate_trim (voussoirs, quoins) | `lab_polished` | albedo `dccfb4`, saturation 0.8 |
| house | `lab_polished` | saturation 1.0, value_gain 0.9, warm_tint (1,0.97,0.9), ao_height 1.6, ao_strength 0.5 |
| stall | `lab_polished` | saturation 1.0, ao 0.4 |
| wood / goods / lamp | `lab_polished` | saturation 1.12, ao 0.35, bounce 0.3 |
| tree | `lab_polished` | saturation 1.15, ao 0, roughness 0.9, rim 0.35 |
| ivy / flowers | `lab_polished` + vertex colour (+ instance colour), double sided | ivy sat 0.95, value_gain 0.78; flowers sat 1.15 |
| hero_new / villager / guard | `lab_char` | kind 0 skin, 1 cloth, 2 hair, 3 leather; saturation 1.3; G6 `human_*` ignore vertex colour |
| iron | StandardMaterial3D | `2a2827`, metallic 0.7, roughness 0.5 |
| banner / flag | StandardMaterial3D double sided | lion texture (red + gold crest), flag `c71a17` |
Atlas roles keep the asset's own albedo atlas (no re-export). Phones: Poly Haven textures at 1K (`StyleG.ph(set, kind, "1k")`).

## 6. Camera
| Use | Position (hero at origin facing -Z) | Look at | FOV (vertical) |
|---|---|---|---|
| Gameplay and QA "over" | (0, 1.95, 2.8) | (0, 4.2, -30) | 52 |
| QA close | (2.4, 1.55, 3.0) | (0, 1.25, -1) | 40 |
| QA facade | (1, 2.2, -4) | (-8.5, 4, -13) | 55 |
| QA gate | (0, 2.5, -4) | (0, 14, -40) | 62 |
| QA stall | (1.5, 1.7, -2) | (-6.7, 1.2, -5) | 55 |
Camera sits 2.8 m behind and 0.17 m above the hero's head height, pitched about +4 degrees; sky and tower tops must stay in frame.

## 7. Composition and density rules
- One focal landmark (twin-tower gatehouse) at the vanishing point, upper-middle third, 38 m down a 14.4 m wide cobbled street; houses both sides (6.6 m pitch, x = +-12.2, scale 0.8, facade at |x| 8.45).
- Hero bottom centre from behind, walking. Foreground left/right: barrels, crates, flower tubs filling the screen edge.
- Prop density per 10 m of street edge (each side): 1.5 stalls (every other house) with >= 25 goods pieces each, 3 barrel/crate/sack clusters, 2 flower tubs, 2 baskets, 0.6 lamp or banner pole, 1.5 hanging shop signs.
- Facade per house: 5 ivy vines (clump every 0.19 m, height 2.8-6.4 m), 4 flower boxes (heights 3.5 m and 5.9 m), tubs/baskets at the foot, signs. No bare wall.
- Crowd per depth band: 0-12 m 8 people (talking/idle near stalls), 12-26 m 9 (walking both ways), 26-45 m 9 (LOD1 models), 2 guards at stalls + 2 at the gate. 26 total on HIGH.
- Gatehouse: pointed arch (r = 1.3 x half-width, springing 5.4 m), voussoir ring with keystone, raised portcullis, 3 red lion banners, 5 flags, turret roofs, ivy on tower feet.

## 8. Tiers: what to drop
| | HIGH | MEDIUM | LOW |
|---|---|---|---|
| Environment | all | no SSAO | no SSAO/glow/adjustments; saturation baked in materials |
| Shadows | 4 splits 110 m | 2 / 70 m | 2 / 45 m |
| Houses LOD | 0 near, 1, 2 far | 1 near, 2 far | 1 up to 20 m, else 2 |
| Crowd | 26 | 20 | 14 |
| Ivy vines per house | 5 | 4 | 3 |
| Stall dressing density | 1.0 | 0.8 | 0.5 |
| Shader | lab_polished | lab_polished | lab_polished_lite |

## 9. Budgets (measured, "over" camera, xvfb; see QA skill for the gate)
| Tier | Draws | Visible tris | Shadow draws / tris | Status |
|---|---|---|---|---|
| Baseline G (before dressing) | 143 | 334k | 534 / 1.14M | at the edge |
| HIGH (pass 3) | 164 | 565k | 471 / 1.80M | within HIGH budget (200 / 600k) |
| LOW (pass 5, 12 folk, LOD1/2 houses, 2 vines, half-leaf ivy, 0.3 dressing) | 134 | 379k | 153 / 470k | draws OK (<= 150); tris 26 % over 300k: next levers are the 6 stalls (2.7k each) + goods layouts, 4 LOD1 houses (4.5k), tower cylinders, hero/guards; use LOD2 for all houses beyond 8 m or merge stalls into LOD |
Draw-call levers used: static props merged per material (`_bake_static`), MultiMesh for ivy/flower boxes/tubs/baskets (about 8 draws for ~1500 instances), one merged goods mesh per street side, `lod1` characters beyond 24 m, LOD1/2 houses. Textures: 1K on phone (4x less memory than the 2K lab).

## 10. Apply G to a game scene
1. Environment: `StyleG.apply_environment(world_env.environment, tier)` in `main.gd _build_environment()` (keep `_update_daylight()` scaling sun energy/colour and ambient energy multiplicatively), or `world_env.environment = load("res://resources/style_g/env_%s.tres" % tier)`.
2. Lights: `sun := StyleG.make_sun(tier)`; add `StyleG.make_fill()` once; re-apply after the `Quality` autoload (it overrides env/sun/shadows; see `lab_style.finalize`).
3. Materials by role, in ONE place (`Assets.building_mesh`, `merged_mesh`, `MarketGoods.material()`): for each mesh surface `mesh.surface_set_material(i, StyleG.material_for(role, mesh.surface_get_material(i), 1, tier))`; cache per source material; MultiMesh instances then share it. Terrain: `material_for("ground")` plus the vertex-colour splat.
4. Characters: role hero_new/villager/guard with `skin_kind` from the mesh name (hair 2, head/hands/body/skin/face/eye 0, boot/glove/shoe/belt 3, else 1).
5. Dressing: copy the pattern of `lab_gate_extra.gd` (ivy, flower boxes, tubs, baskets, stall dressing) into the settlement builder; bake static props per material.
6. Check with `ashes-style-g-qa` (>= 75 and budgets) and `ashes-performance`.

## 11. Log of what worked (G passes)
- Baseline (g3) about 55-60 % of target 03. Pass 1 (kit added): ivy and boxes fit the facades, but ivy neon, goods orange, voussoirs brown. Pass 2: ivy darkened (sat 0.95, value 0.78), wood/goods saturation 1.12, bounce 0.36, gate_stone atlas_color back to neutral, trim blocks as polished limestone. Pass 3: exposure 0.92, contrast 1.3, cooler LUT shadow `0a1240`, fill 0.3: contrast and shadow colour improved (metrics: warmth 1.29, sat 0.34, contrast 0.18, detail 0.05, green 0.04, shadow_b -0.02 vs target 1.34 / 0.40 / 0.23 / 0.07 / 0.02 / -0.06). Estimated score 72/100 (hero 4/10, material richness 6/10 are the gaps).
- What worked: facade dressing by MultiMesh (about 1100 ivy clumps + 40 boxes + tubs + baskets = about 10 draws); warm bounce as a shadowless upward directional light plus warm `ground_bounce`; warm fog; pointed arch + voussoir ring (instantly reads as "castle gate"); 26 folk with random clip phases; merging stall goods per street side.
- What did not: warm-tinting `gate_stone` (turns brown); `bounce` 0.42 + fill 0.55 (orange barrels, muddy shadows); `_bake_static` merging per material saves nothing for the houses because every house has its own atlas material (only worth it for shared-material props); the lab "stall" camera is not useful (stands outside the street).
- Still to do for 85+: bespoke hero (hooded vest, bracers, shaggy hair), real weathered plaster/timber textures instead of the flat Meshy atlases, awning cloth drape, shelves of jars behind counters, more flowers/grass at wall feet, LOW triangle budget.
