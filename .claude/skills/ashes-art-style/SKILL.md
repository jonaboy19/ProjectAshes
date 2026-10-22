---
name: ashes-art-style
description: The ONE visual style of Rising Ashes: Style G (gate market, target 03), see ashes-style-g, ashes-style-g-assets, ashes-style-g-qa. Use for any visual work — new assets (Blender, Meshy, open-source packs), materials, lighting, post-processing, village/city dressing, UI art, store screenshots — and to judge whether a screenshot matches the target look.
---

> **DECISION: Style G is THE game style** (Style Lab box G, the owner: "by far the best"; target `docs/art/reference/03_TARGET_gate_market_detailed.webp`).
> Use these three skills for any visual work, they hold exact values and override anything below that differs:
> - `ashes-style-g`: master recipe (Environment, lights, palettes, materials by role, camera, composition, tiers, budgets, how to apply). Code: `kingdom/scripts/style_g.gd`, baked `kingdom/resources/style_g/`.
> - `ashes-style-g-assets`: how to make or adapt assets, characters (hooded traveller hero, townsfolk, guards), Blender steps.
> - `ashes-style-g-qa`: scorecard (ship at >= 75/100), compare tool `kingdom/tools_qa/style_lab/make_compare.py`, failure fixes.
> The text below is the general mood of the style and the original reference notes.

# Rising Ashes art style: "sunny storybook medieval"

**Main reference:** `docs/art/reference/00_MAIN_kingsreach_gate_market.webp` (Kingsreach gate market).
The user will add more references under `docs/art/reference/` (numbered `01_...`, `02_...`). **All of them must be in THIS style only.**
If a new image clashes with the main one, the main one wins; ask the user.
Before any visual task, open the main reference with Read and compare your result side by side.

## The look in one line
Warm, saturated, hand-painted stylized fantasy (in the spirit of stylized mobile RPGs and painterly concept art).
Chunky readable shapes, a clean sunny day, lived-in and dense, never gritty or realistic-PBR.

## Palette and light
- **Key light:** warm golden sun (around 5200-5600 K, slightly orange), high and from one side. Crisp but soft-edged shadows.
- **Shadows** are tinted **cool blue-violet**, never black or grey. Plenty of warm bounce light (strong ambient, SSIL/GI feel).
- **Sky:** bright saturated blue with soft white cumulus. Distance fades into light blue haze (aerial perspective), not grey fog.
- **Saturation** is high but not neon: red and gold banners, royal blue roofs, green foliage with yellow highlights, warm tan and beige stone and cobbles.
- **Accents:** heraldic red plus gold (crown, lion) repeated on banners and shields; striped red/white and green/white market awnings.
- **Post:** gentle bloom on highlights, slight warm grade, mild vignette, no heavy chromatic aberration, no film grain.

## Materials (hand-painted, not photo-scanned)
- Painted albedo with baked-in AO and edge highlights: stone blocks with light chipped edges, wood with visible painted grain.
- Low-to-medium roughness variation. Metals are simple (dull iron, gold trim). No realistic scanned textures (Polyhaven/Megascans) unless repainted or tinted to match.
- Stone walls: light warm grey/tan blocks with irregular sizes. Roofs: royal blue slate or terracotta tiles, chunky.
- Cobblestone: warm beige, rounded stones, with grass and flowers in the gaps.

## Shapes and proportions
- Stylized, slightly exaggerated: thick timber frames, big round towers with conical blue roofs, chunky crenellations, oversized lanterns and signs.
- Characters: stylized but not chibi (about 6.5-7 heads tall), clean readable silhouettes, simple clothing colours (blue dress, green tunic, red tabard with gold crest), leather satchels and belts.
- Buildings: half-timbered (white plaster plus dark wood beams), stone ground floors, flower boxes, hanging signs.

## Density and set dressing (what makes it "not fake")
- **Nothing sits on bare flat ground:** every building base and wall foot gets flowers, grass tufts, stones, barrels or crates.
- Markets: stalls packed with goods (fruit crates, pottery, bread), barrels and sacks, hanging lanterns, bunting and banners on poles.
- Streets: people walking in both directions at different depths, guards with spears at gates, banners every few metres on walls.
- Foliage: round leafy trees with bright yellow-green rims, and white/yellow daisies everywhere at path edges.
- Layered depth: foreground props (fence, flowers), mid-ground action, background gate and towers, far background city through the gate.

## Mobile budget (keep 60 fps; see `ashes-performance`)
- Get the look from **lighting, colour grading, textures and dressing density**, not from polycount: impostors and MultiMesh for flowers, grass and clutter; atlas textures; LOD.
- Cheap wins, in order: warm sun plus blue ambient/sky colours → tonemap (ACES or AgX) with saturation about 1.1-1.2 and slight warmth → bloom → hand-painted texture swaps → dressing density (MultiMesh) → SSAO/SSIL on HIGH+ only.
- Per tier: LOW keeps the palette and grading but drops SSAO, bloom and density. The *colours* must look right on every tier.

## Checklist before calling a visual task done
1. Take a screenshot at the same kind of view (tools/qa/perf_visual or store screenshots) and Read it next to the main reference.
2. Check: warm sun ✔ blue shadows ✔ saturated banners and roofs ✔ flowers at bases ✔ dense props ✔ haze in distance ✔ no grey/realistic textures ✔ fps unchanged ✔.
3. Show the user the before/after PNG.

## Sources that fit this style (free, commercial OK; see `ashes-open-source-sourcing`)
KayKit (CC0: medieval, characters), Quaternius (CC0: stylized nature/props/characters), Kenney (CC0), and Meshy output retextured with a
"hand-painted stylized, warm sunny, storybook medieval" prompt. Avoid photo-scanned assets unless repainted.
