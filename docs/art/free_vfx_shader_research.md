# Free VFX / Shader / Content Research for Rising Ashes (Godot 4.6)

Research date: 2026-09-29. Web only, nothing downloaded or installed.
Target look: `.claude/skills/ashes-art-style/SKILL.md` (sunny hand-painted storybook, warm sun, blue-violet shadows, saturated banners/roofs, round leafy trees).
Licence policy: CC0, MIT, BSD, Apache-2.0, Zlib, OFL, CC-BY only. NC, ND, GPL/LGPL, unclear = SKIP.

**Verification caveat.** Licence text below was read from each source's own page (Kenney, Quaternius, godotshaders.com, GitHub README/LICENSE, itch, OGA, Godot docs), but through a page-summarising fetch tool, not by opening every LICENSE file byte-for-byte. Before importing anything into the repo, open the actual LICENSE / page once and copy the licence + author into `docs/art/CREDITS.md` (do this even for CC0; it also protects you if a page changes later). godotshaders.com: every shader states its licence on its page and the page text usually adds "Images and videos, and assets depicted in those, do not fall under this license", so only the shader code is covered, never the preview screenshots.

Fit score: 1-5 for our sunny storybook style. Mobile cost: L = cheap, M = medium, H = desktop only.

---

## TOP 15 OVERALL (ranked)

| # | Item | Licence | Fit | Mobile | Use it for |
|---|------|---------|-----|--------|-----------|
| 1 | Quaternius **Stylized Nature MegaKit** | CC0 | 5 | L (low poly, few textures) | Trees, bushes, flowers, rocks, grass in the Ghibli-ish look; replaces KayKit nature |
| 2 | Godot Shaders **Stylized Fluffy Tree Leaves** (Miu) | CC0 | 5 | L (alpha cutout billboard) | Round leafy trees with fresnel rim + wind; pair with #1 |
| 3 | Quaternius **Medieval Village MegaKit** (free Standard tier) | CC0 | 4 | L | Modular walls, roofs, floors, doors; best free modular medieval kit found |
| 4 | Kenney **Particle Pack** | CC0 | 4 | L | 80 particle textures (smoke, fire, sparks, magic, flares, rings) for GPUParticles3D billboards |
| 5 | RPicster **Godot-particle-and-vfx-textures** | CC0 | 4 | L | Lens flares, glows, soft particles, 1024/256/64 px, made for Godot |
| 6 | **Stylized Multimesh Grass Shader** (Malido) | CC0 | 4 | L-M (vertex wind, MultiMesh) | Wind sway + player push on MultiMesh grass/flowers |
| 7 | **Stylized Sky Shader With Clouds** (axilirate) | CC0 | 4 | M (3 noise samples; reduce layers on LOW) | Blue sky, white cumulus, sun/horizon glow, day-night |
| 8 | **Water Shader 3D (Godot 4.3)** (Lesus) or **Stylized Water for Godot 4.x** (MinhCreatorVN) | CC0 / MIT | 4 | M-H (screen+depth texture) | Water with depth colour, shoreline foam, caustics |
| 9 | **Flame FX** (binbun3d, free version) | CC0 | 4 | L-M | Stylized 3D flame shader + one preset, torches/campfires; Godot 4 |
| 10 | **SimplestGodRay3D** (Re_Lo) / **Fake Godrays** (CC0) | MIT / CC0 | 4 | L (one quad or cone, additive) | Cheap god rays through gate/trees; no volumetric fog needed |
| 11 | **Terrain3D** (TokisanGames) | MIT | 4 | M; Mobile/Android "experimental" | Editable terrain, 32 textures, LOD, MultiMesh foliage instancer |
| 12 | **ProtonScatter** (HungryProton) | MIT | 4 | Editor-time only (bakes to MultiMesh) | Density dressing: flowers/rocks/grass at wall feet, paths |
| 13 | Quaternius **Fantasy Props MegaKit** | CC0 | 3-4 | L (4 texture sets total) | 200+ props: barrels, crates, weapons, potions, furniture |
| 14 | **GODOT-VFX-LIBRARY** (haowg) | MIT (repo); asset provenance not listed | 3 | mixed; test | 35+ ready particle scenes (torch, fireflies, falling leaves, rain, snow, portal, sparks, dust) and 17+ shaders (dissolve, flash, frozen, burning, energy barrier); use as scene starting points, restyle to our palette |
| 15 | **Kuwahara** (innerdev CC0 / Firerabbit generalized, MIT) | CC0 / MIT | 3 (painterly), 2 on mobile | H | Optional painterly post on HIGH tier only |

Honourable mentions: Kenney Fantasy Town Kit / Castle Kit (CC0, flat colour, fit 2-3), TCA_Weather_System (MIT, very young), Sky3D (MIT), Godot Octahedral Impostors (MIT, version support unverified).

---

## 1. VFX / particles

### 1.1 Texture packs

**Kenney Particle Pack** - https://kenney.nl/assets/particle-pack
- Licence: "Creative Commons CC0 (public domain dedication)". 80 files, 512 px tiles.
- Good for: smoke puffs, fire, sparks, star/flare, magic circles, slashes as billboard textures. Style: neutral white/black masks, so we tint them (fits, since colour comes from the particle material).
- Godot 4: plain PNG, use in StandardMaterial3D billboard + GPUParticles3D, or CPUParticles3D on LOW tier.
- Mobile: L. Fit 4.

**RPicster Godot-particle-and-vfx-textures** - https://github.com/RPicster/Godot-particle-and-vfx-textures
- Licence: CC0, quote: "use the information and textures however you please. No attribution is required!" (repo README). Includes Blender source files and a Godot demo.
- Good for: lens flares, glows, soft light sprites, particle masks (1024/256/64 px, B/W and alpha versions).
- Mobile: L (use 256 px or 64 px). Fit 4.

**Unity Labs CC0 VFX flipbooks** - https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks
- Licence: "we release some of these sequences under CC0 license so you can use them in your projects." Pre-assembled flipbook sheets (smoke, fire, explosions), EXR/TGA sequences.
- Not restricted to Unity by the text, but it is hosted in a Unity context and only "some" sequences are CC0, so check each downloaded file's readme before use. Realistic rather than stylized; fit 2. Low priority. Treat as "SKIP unless per-file CC0 confirmed".

**OpenGameArt / itch CC0 fire packs** - e.g. https://itch.io/game-assets/free/tag-fire ; many are 2D pixel or cartoon sprite sheets, licence varies per pack (some CC0, some CC-BY, some "free for commercial" with custom terms). Only use ones that state CC0 or CC-BY; record per pack. Fit 2-3.

### 1.2 Godot projects / addons

**haowg/GODOT-VFX-LIBRARY** - https://github.com/haowg/GODOT-VFX-LIBRARY
- Licence: MIT ("MIT License, Copyright (c) 2024 Godot VFX Library"). 322 stars. Godot 4.5+ per README.
- Contents: 35+ particle effects (blood splash, energy burst, shield break, sparks, portal vortex, lightning chain, ice frost, fireball trails, torch fire, fireflies, steam, water splash, falling leaves, rain, snow, dash trails, jump dust) and 17+ shaders (flash white, dissolve, frozen, poison, burning, petrify, water surface, heat distortion, energy barrier, outline glow, radial blur).
- Doubts: README lists no third-party credits, and it describes itself as "inspired by classic Metroidvania and action games", so a lot may be 2D. Textures inside `addons/vfx_library/` have no stated separate licence. Action: open the repo, confirm every texture is generated in-repo or has a stated licence before shipping. Until then use it for scene structure and parameters only. Fit 3 (needs restyle). Mobile: check each; particle counts are the risk.

**GDQuest godot-4-VFX-assets** - https://github.com/gdquest-demos/godot-4-VFX-assets
- Licence quote: source code (scripts, scenes, shaders, Godot resources) MIT; "image textures and 3D models" CC-BY-NC-SA 4.0.
- **SKIP the textures and meshes (NC + SA).** The MIT shader/scene code alone is usable, but the effects depend on the NC textures, so it is only a reference for how to build things.

**GDQuest godot-4-stylized-sky** - https://github.com/gdquest-demos/godot-4-stylized-sky
- Same dual licence (MIT code, CC-BY-NC-SA art assets). **SKIP assets.** Shader code idea only; prefer axilirate's CC0 sky.

**GDQuest godot-visual-effects (2D course effects)** - https://github.com/gdquest-demos/godot-visual-effects
- Licence file could not be read (404 on the raw URL I tried). 2D only. **SKIP** (licence unverified, and 2D).

**Godot Shaders "Procedural Torch & Candle Shader (Fire + Smoke + Sparks)"** - https://godotshaders.com/shader/procedural-torch-candle-shader-fire-smoke-sparks/
- Licence: code CC0 (per search result summary). canvas_item, so it is 2D/UI or a quad with a SubViewport; not a native 3D shader. Fit 3.

**Flame FX (binbun3d)** - https://binbun3d.itch.io/flame-fx (also Godot forum thread https://forum.godotengine.org/t/stylized-flame-vfx-cc0/136648)
- Licence quote: "You're free to use all versions of this pack for personal, educational and commercial projects with no attribution required." Listed as CC0 v1.0.
- Free version: all shaders and scripts, 1 flame particle preset, 1 overlay material preset. Full version (34 presets) is pay-what-you-want from $5.94; also CC0.
- Godot 4.x, 3D. Mobile: L-M; a few overdraw quads per flame. Fit 4 (stylized wobble flame suits storybook).

**Godot Shaders "Stylized fire (3D)" (GDQuest)** - https://godotshaders.com/shader/stylized-fire-3d/ : MIT; billboard flame from noise textures. Use with your own noise (do not take GDQuest demo textures without checking). Fit 3-4.

**Godot Shaders "Stylized lava"** - https://godotshaders.com/shader/stylized-lava/ : code CC0. Fit 3.

**God rays**
- SimplestGodRay3D - https://godotengine.org/asset-library/asset/4146 - licence MIT, author Re_Lo, Godot 4.4, one QuadMesh + shader. Mobile L. Fit 4.
- Fake Godrays (Godot 4.x) - https://godotshaders.com/shader/fake-godrays-godot-4-2/ - "under CC0 license"; CSGCylinder (replace with a baked cone MeshInstance for mobile). Fit 4.

**Portals / shields**
- Energy Shield with Impact Effect (Dan) - https://godotshaders.com/shader/energy-shield-with-impact-effect/ - MIT, fresnel + ripple. Fit 3, mobile L-M (alpha blend).
- Swirl Shader (spatial, uses screen texture) - https://godotshaders.com/shader/swirl-shader/ - licence not checked; **verify before use**.
- 2D Swirling Vortex Portal - https://godotshaders.com/shader/2d-swirling-vortex-portal/ - licence not checked; 2D.
- For a 3D rift portal, the cheap approach is a quad/torus with a scrolling polar-UV noise shader (the GODOT-VFX-LIBRARY "portal vortex" is the closest ready example).

**Hit flash / dissolve**
- Dissolve (Godot 4.x) by KitsuneKotta - https://godotshaders.com/shader/dissolve-godot-4-x/ - MIT (images excluded). Spatial. Mobile L. Fit 3.
- Hit Flash shaders - https://godotshaders.com/shader/hit-flash-effect-shader/ - canvas_item; for 3D just add an emissive "flash" uniform to our character material or use `next_pass`. Licence not checked.

**Effects that need no add-on (do in Godot)**: torch flicker (OmniLight energy noise + GPUParticles3D flame/smoke with Kenney textures), sword trails (Trail via ribbon-mode GPUParticles3D or mesh with scrolling alpha), footstep dust (CPUParticles3D 8-12 particles), fireflies (GPUParticles3D, 20-40 particles, additive), falling leaves (one emitter attached to camera, 30 particles), snow/rain (camera-following emitter, plus a splash sub-emitter only on HIGH tier), fog wisps (a few soft billboard sprites, not volumetric fog).

**Mobile VFX rules**: cap overdraw (large additive quads are the killer on Adreno/Mali), keep particle counts under about 30 per emitter, CPUParticles3D fallback on LOW, use 64-256 px textures, and do not use SCREEN_TEXTURE distortion in effects on LOW tier.

---

## 2. Shaders

| Shader | URL | Licence | Godot / mobile | Fit |
|--------|-----|---------|----------------|-----|
| Kuwahara Shader (innerdev) | https://godotshaders.com/shader/kuwahara-shader-godot-4/ | CC0 | canvas_item, radius 1-20; full-screen multi-tap, HIGH/desktop only | 3 |
| Generalized Kuwahara (Firerabbit, ported from Acerola) | https://godotshaders.com/shader/generalized-kuwahara/ | MIT | canvas_item full-screen; kernel 2-20; heavy; desktop only | 3 |
| Stylized Water for Godot 4.x (MinhCreatorVN) | https://godotshaders.com/shader/stylized-water-for-godot-4-x/ | MIT ("The shader code and all code snippets in this post are under MIT license") | 4.3; DEPTH + SCREEN texture; edge foam, depth fade | 4 |
| Water Shader 3D (Godot 4.3) (Lesus) | https://godotshaders.com/shader/water-shader-3d-godot-4-3/ | CC0 | Gerstner waves, caustics, foam; SCREEN + DEPTH texture, M-H | 4 |
| Absorption Based Stylized Water | https://godotshaders.com/shader/absorption-based-stylized-water/ | not checked - verify | screen texture | - |
| Stylized Multimesh Grass (Malido) | https://godotshaders.com/shader/stylized-multimesh-grass-shader/ | CC0 | 4.x MultiMesh, wind + player push; keep wind direction non-zero (grass vanishes otherwise); L | 4 |
| Stylized grass with wind and deformation (GDQuest) | https://godotshaders.com/shader/stylized-grass-with-wind-and-deformation/ | MIT | written for Godot 3.2, users report porting issues; single deformer only | 2-3 |
| Stylized Fluffy Tree Leaves (Miu) | https://godotshaders.com/shader/stylized-fluffy-tree-leaves/ | CC0 (code only; images excluded) | Godot 4 spatial, billboard + wind + fresnel; L | 5 |
| Stylized Sky Shader With Clouds (axilirate) | https://godotshaders.com/shader/stylized-sky-shader-with-clouds/ | CC0 | Godot 4 sky shader; driven by DirectionalLight3D rotation; needs 3 noise textures; M | 4 |
| Terrain Mesh Blending / Mesh-Terrain Blending (kmitt91) | https://godotshaders.com/shader/mesh-terrain-blending/ | MIT (images excluded) | Godot 4.0+, triplanar; L-M | 3 |
| Triplanar Stochastic Terrain (DevUndead) | https://godotshaders.com/shader/triplanar-stochastic-terrain-shader/ | MIT | slope-based 3-layer triplanar; a comment reports about 30-35 % slower than non-stochastic, so avoid on mobile | 3 (desktop) |
| Inverted-Hull Outline with Group Merge (42atomys) | https://godotshaders.com/shader/inverted-hull-outline-with-group-merge/ | CC0 | cull_front second pass; merge feature uses depth texture (skip that on mobile); simple inverted hull is L | 3 (our style has few hard outlines) |
| Dissolve (Godot 4.x) | https://godotshaders.com/shader/dissolve-godot-4-x/ | MIT | L | 3 |
| Simulating Cloud Shadows Analytically (ShaderError) | https://godotshaders.com/shader/simulating-cloud-shadows-analytically/ | MIT | **needs a modified Godot shader pipeline / custom built-in** - impractical, **SKIP** | - |
| Energy Shield with Impact Effect | https://godotshaders.com/shader/energy-shield-with-impact-effect/ | MIT | L-M | 3 |
| Fake Godrays | https://godotshaders.com/shader/fake-godrays-godot-4-2/ | CC0 | L | 4 |

**Cloud shadows (practical route)**: instead of the analytical shader, add a large ground-projected Decal or a second UV-scrolling multiply layer in the terrain/ground shader using a low-res noise texture, or slowly modulate the DirectionalLight energy. Cheap and mobile-safe. Nothing off-the-shelf with a verified licence was found for a Decal version.

**Painterly reality check**: Kuwahara at full screen on a mid-range phone will not hold 60 fps. Get the storybook look from hand-painted textures, warm tonemap and bloom, blue shadows and dressing density. Offer Kuwahara only as an optional HIGH/desktop toggle. Godot 4.6 made glow much faster on mobile (per release coverage), so bloom is fine on MID tier.

---

## 3. Free stylized 3D content (better than KayKit)

### Recommended

**Quaternius Stylized Nature MegaKit** - https://quaternius.com/packs/stylizednaturemegakit.html
- Licence: CC0 ("free to use in personal, educational and commercial projects"). 116 models: 40 trees, 35 plants/flowers, 27 rocks, grass, bushes. FBX/OBJ/glTF. Ghibli-inspired.
- Tiers: Standard (about 60-70 %, free), Pro (rest, paid), Source (paid; adds Blend files, a 7-variant leaf shader, wind grass shader, and Godot 4.3+ integration). The free tier is CC0 but the paid tiers are the paid product; only use what you actually downloaded free.
- Fit 5. Mobile L (low poly). Best direct upgrade for foliage.

**Quaternius Medieval Village MegaKit** - https://quaternius.com/packs/medievalvillagemegakit.html
- Licence: CC0. 300+ modular grid-snapping pieces (walls, floors, stairs, roofs, doors, windows, vines). Standard free tier is roughly 60-70 % of pieces; Pro and Source are paid. Source has "custom shaders enabling customizable wear colors" and Godot 4.3+ project.
- Fit 4 (hand-painted feel, but modular grey/warm palette; retint roofs blue/terracotta). Mobile L-M (many pieces; use MultiMesh or merged meshes per building).

**Quaternius Fantasy Props MegaKit** - https://quaternius.com/packs/fantasypropsmegakit.html
- Licence: CC0. 200+ models (furniture, tools, weapons, books, potions, breakables) sharing 4 texture sets. Fit 3-4. Mobile L (excellent atlas count).

**Quaternius Medieval Village Pack (older, 39 models)** - https://quaternius.com/packs/medievalvillage.html ; Poly Pizza mirror https://poly.pizza/bundle/Medieval-Village-Pack-NsHhjhlrfY - Public Domain (CC0), houses, blacksmith, mill, inn, bell tower. Fit 3 (older, simpler). Handy for hero buildings.

**Quaternius Ultimate Stylized Nature Pack** - https://quaternius.com/packs/ultimatestylizednature.html - CC0, 63 models, seamless textures + normal maps. Fit 4 (smaller sibling of #1).

**Other Quaternius packs listed on the site worth a look** (CC0 per the site's general terms; the site's front page did not show a licence line, so confirm on each pack page): Modular Medieval Building Pack, Ultimate RPG Pack, RPG Essentials, Fantasy RTS (**geometry only, untextured** per its page), Stylized Tree Pack, Ultimate Nature Pack, Animated Knight Pack, Universal Base Characters, Modular Character Outfits - Fantasy, Farm Animal Pack, Ultimate Animated Animal Pack.

**Kenney Fantasy Town Kit 2.0** - https://kenney.nl/assets/fantasy-town-kit - CC0, 160 variations. Flat-colour block style; fit 2-3 (clean, but flatter than the reference). **Kenney Castle Kit 2.0** - https://kenney.nl/assets/castle-kit - CC0, 75 files. **Kenney Nature Kit** - https://kenney.nl/assets/nature-kit - CC0, 330 files, simple stylized; fit 3. Kenney is best for prototyping and filler.

**Poly Pizza** - https://poly.pizza/ - hosts Quaternius (1400+ models) and Kenney (450+). Per-model licence: "Most models on Poly Pizza are CC-BY (credit the creator), with some CC0". CC-BY is allowed, but you must keep an attribution ledger. Fit varies.

**Sketchfab** (download needs a free account; licence is per model, check the badge on each)
- Lowpoly Medieval Village by Mirosh - https://sketchfab.com/3d-models/lowpoly-medieval-village-ec3ce59116e741388a5d49c2f7fd113c - shown as CC Attribution 4.0, downloadable, 33 k tris, flat colours no textures. Usable with credit; fit 2 (flat colour, needs repaint).
- Modular Stylized Village Pack by vchiliaridis - hand-painted, but **paid** and licence not stated. **SKIP.**
- Other hits in the search (assetfactory, AlexFerrart3D, Booba Booba, Bento NPR pack) - licence not verified; check the licence panel per model. CC0/CC-BY only.

### Hand-painted textures (CC0)
- OpenGameArt "Handpainted tileable textures 512x512" by DeadKir - https://opengameart.org/content/handpainted-tileable-textures-512%D1%85512 - CC0; metal plates, wood, slime (3 textures). Small but real hand-painted CC0.
- OpenGameArt curated collection "Assets: Stylized Hand-Painted" - https://opengameart.org/content/assets-stylized-hand-painted - mixed licences per item; take only CC0/CC-BY entries. Also "Handpainted Tileable wall", "Seamless Wood Textures", "Tileable Dirt Textures", "Seamless Snow Texture" (all reported as CC0 in search results; confirm on each page).
- ambientCG - https://ambientcg.com/ - CC0, thousands of PBR materials; **photoreal**, so per our art-style rule only use after tinting/painting over (or use as a base for Meshy retexture prompts). Poly Haven likewise CC0 and photoreal.
- Best route for a consistent hand-painted look remains: Quaternius atlases + own painted trim sheets + Meshy retexture.

---

## 4. Advanced / performance

**Terrain3D** - https://github.com/TokisanGames/Terrain3D - MIT. C++ GDExtension; up to 32 textures, up to 10 mesh LODs, sizes 64 m to 65.5 km, sculpt/paint/import heightmaps, Terrain3DInstancer for MultiMesh foliage with LOD and shadow impostors. Docs list Godot 4.4-4.6+, Windows/Linux/macOS supported, **mobile and web "experimental"** (Android reported working since 0.9.1; use PNG/TGA textures not DDS on Android). Recommendation: prototype early on a real device before committing; fall back to a baked terrain mesh + our own splat shader if the frame budget fails. Fit 4.

**ProtonScatter** - https://github.com/HungryProton/scatter - MIT, Godot 4 (separate v3 branch). Modifier-stack scatter (grid, random, edge, path/box/sphere domains). Editor-time, so runtime mobile cost is only the resulting MultiMesh. Ideal for the "nothing on bare flat ground" rule. Fit 4.

**Sky3D** - https://github.com/TokisanGames/Sky3D - MIT (star map asset needs acknowledgment per its bundled licence file, and we do not need stars). Godot 4.3+, Forward/Mobile/Compatibility, day/night, sun/moon, clouds, fog. Heavier than one CC0 sky shader; fit 3. Consider only if a full day/night cycle is planned.

**TCA_Weather_System** - https://github.com/kS222138/TCA_Weather_System - MIT ("Free for commercial & personal use"), Godot 4.6+, mobile "Low Quality" preset, volumetric clouds, water, wind, seasons, rain/snow, terrain wetness, fog. Very young (35 stars, 21 commits, v1.4.0) and third-party credits unclear ("inspired by UE5..."). Fit 3. Read the code, borrow ideas, do not depend on it. Flag: **licence OK, maturity doubtful; SKIP as a dependency.**

**Godot Octahedral Impostors** - https://github.com/wojtekpil/Godot-Octahedral-Impostors - MIT (licence file present), 311 stars; the README points at a "v2.0-new-baker" branch and does not state supported Godot version or mobile support. Test on 4.6 Mobile before relying on it. Fit 3 (for distant trees/buildings). Godot 4's built-in options also apply: automatic mesh LOD on import, `visibility_range` (HLOD-style) on MeshInstance3D, MultiMesh, and shadow distance limits.

**Waterways (river meshes)** - https://github.com/Arnklit/Waterways (MIT, Godot 3 original; a `godot4_0` branch exists) and Waterways .NET port https://github.com/Tshmofen/waterways-net (Godot 4, needs .NET 8/C#). The .NET port forces a C# build and has no stated mobile export story; README says "no additional licenses applied" but licence type was not confirmed. **SKIP for now** (C# requirement, mobile unknown). Use the CC0 water shader on a mesh instead.

**Global illumination on mobile.** Official docs (Introduction to Global Illumination): SDFGI and VoxelGI are "Not available" on Mobile and Compatibility renderers, and "For mobile games, LightmapGI and ReflectionProbes are the only supported options." Practical SDFGI alternatives for the storybook look:
1. Bake LightmapGI for static village geometry (needs RenderingDevice hardware to bake, i.e. do it on the desktop).
2. Strong warm sky/ambient + a second weak blue-tinted fill from a `DirectionalLight3D` opposite the sun with no shadows; painted-in AO in textures.
3. ReflectionProbes (cheaper in 4.6) for metals/water.
4. Fake bounce: vertex-colour or baked AO plus warm ground tint on ground-facing surfaces.
Keep SDFGI/SSIL for the desktop Forward+ profile only.

**Godot 4.6 mobile notes** (release coverage): glow is much faster on mobile and now blends in screen mode before tonemapping (revisit bloom strength when upgrading); reflection probes are lighter; SSR rewritten (Forward+ only); AgX tonemapper configurable; fixes for Mali/Adreno crashes. Source: https://godotengine.org/releases/4.6/.

**Wind/foliage system**: one global shader uniform for wind direction and time, shared by grass (Malido, CC0), leaves (Miu, CC0) and Quaternius trees via vertex-colour or height masks (Victor Karp's write-up https://victorkarp.com/godot-foliage-wind/ explains the vertex-colour mask method; it is a tutorial, licence of any code not stated). MultiMesh does no per-instance culling, so chunk it into grid cells (Terrain3D's instancer does this).

---

## SKIP list (licence doubts or practical blockers)

| Item | Reason |
|------|--------|
| GDQuest godot-4-VFX-assets textures/meshes | CC-BY-NC-SA 4.0 (NC + SA) |
| GDQuest godot-4-stylized-sky art assets | CC-BY-NC-SA 4.0 (code is MIT, but do not use their textures) |
| GDQuest godot-visual-effects | Licence file unreadable, 2D only |
| GDQuest/godot-shaders repo as a whole | Licence file not confirmed here (godotshaders.com pages say MIT); use the godotshaders.com page copies whose licence is shown |
| Sketchfab "Modular Stylized Village Pack" (vchiliaridis) | Paid, licence not stated |
| Godot Asset Store paid shaders (e.g. emace-art Stylized Water / Procedural Sky) | Paid, licence terms not reviewed |
| Cloud Shadows Analytically | MIT but needs engine pipeline changes |
| Waterways .NET | C# requirement, mobile unknown, licence type unconfirmed |
| TCA_Weather_System (as a dependency) | MIT but immature, unclear third-party parts |
| Unity CC0 flipbooks | Only "some" sequences CC0; realistic style |
| Any godotshaders.com shader whose page lacks a licence line | Treat as unclear |
| Any Sketchfab/Poly Pizza model not showing CC0 or CC-BY | Unclear |

---

## Suggested adoption order

1. Foliage: Quaternius Stylized Nature MegaKit + Miu fluffy leaf shader + Malido grass, scatter with ProtonScatter (or Terrain3D instancer).
2. Sky and light: axilirate sky, warm sun + blue ambient, SimplestGodRay3D at the gate.
3. VFX base: Kenney Particle Pack + RPicster textures, Flame FX free version for torches; borrow scene structure from GODOT-VFX-LIBRARY after checking its assets.
4. Buildings/props: Quaternius Medieval Village MegaKit (Standard) + Fantasy Props MegaKit, retint to the reference palette.
5. Water: Lesus CC0 water (or MinhCreatorVN MIT) with foam and depth, HIGH/MID only; flat animated colour plane on LOW.
6. Terrain3D spike on an Android device to decide go/no-go.
7. Keep every source in `docs/art/CREDITS.md` with URL, author, licence, date, and a copy of the licence page.
