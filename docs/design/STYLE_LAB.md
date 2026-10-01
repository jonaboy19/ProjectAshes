# Style Lab: choose the look of Rising Ashes

**Why:** the owner wants the game to look "much nicer on phone", "really medieval", and dislikes the main character. Instead of guessing, `scenes/style_lab/style_lab.tscn` shows the SAME medieval street corner (timber-frame townhouse, stone wall, market stall with goods, cobbles -> mud -> grass, well, hand cart, lantern, tree, barrels and crates) in five styles, each with today's hero, an improved hero and a villager. Pick one, then apply it game-wide with the recipe at the bottom.

## Run it
| Where | How |
|---|---|
| Phone (debug export) | Main menu -> **Style Lab** (debug builds, or any build with an empty `user://style_lab.flag`). Grid of five tiles; tap one for full screen; drag = orbit; buttons: Prev / Next / Overview<->Close-up / Grid. Full screen shows live fps, draw calls and triangles. |
| PC / GPU | `godot --path kingdom -- --style_lab` (add `--box=C --cam=close` to open one box) |
| Renders | `godot --path kingdom --rendering-driver vulkan --quality=high -- --shot=style_lab --out=/tmp/claude-0/shots/style_lab [--box=A,B] [--w=2340 --h=1080]` writes `<out>_<A..E>_<over|close>.png` and `<out>_stats.json`. Sheet: `python3 kingdom/tools_qa/style_lab/make_sheet.py <out> <sheet.png>`. Under xvfb (llvmpipe) the numbers for draw calls and triangles are valid, fps/GPU time are not. |

Each box is its own `SubViewport` with its own `World3D`, `Environment` and sun, so a style is **self-contained** (`scripts/style_lab/lab_style.gd`: `env_for(id)`, `_sun(id)`, material factories).

## The boxes (seven, A to G)
Renders: `/tmp/claude-0/shots/style_lab_sheet.png` (rows A..G, overview + character close-up, references 00 and 03 on top) and `style_lab_G_vs_target.png`. Numbers below are from the xvfb/llvmpipe Forward+ renders at 2340x1080 (valid for draw calls and triangles; **not** fps or GPU ms: measure those on the phone with the Style Lab HUD).

| Box | What it is | Draws (overview / close-up) | Visible tris | Shadow-pass draws / tris |
|---|---|---|---|---|
| **A** Current look | Today's materials, HDRI sky, AgX + saturation 1.28, SSAO, today's hero + villager (copy of `main.gd _build_environment`, `terrain.gdshader`) | 36 / 34 | 68k / 63k | 36 / 68k |
| **B** Storybook painterly | `lab_toon` banded light with a lilac shadow ramp and pigment mottling, `lab_outline` inverted-hull ink line (constant screen width), painted cloud sky, warm colour-correction LUT, posterised ground | 64 / 60 (outline = 2nd pass) | 124k / 112k | 66 / 123k |
| **C** Grounded medieval | `lab_grounded`: Poly Haven CC0 plaster / timber / stone / mud / cobble (planar PBR, grime climbs from the ground, moss on top faces), SSAO (Forward+ only), contact-shadow blobs, mud + moss Decals, height fog, desaturated earthy palette, overcast sky | 51 / 48 (+15 blobs; 5 decals) | 69k / 63k | 36 / 69k |
| **D** Polished stylised | `lab_polished` (Lambert-wrap diffuse, hemispheric sky/honey bounce, baked-style height AO, rim, saturation), `lab_char` skin / cloth / hair / leather separation, bloom, saturated blue sky with cumulus, one lantern OmniLight | 36 / 34 | 69k / 63k | 36 / 69k |
| **E** Low-end safe (D lite) | `lab_polished_lite` (per-vertex lighting, no rim/bounce), no glow, no adjustment pass, 1 shadow split, 0.75 render scale, blob shadows | 51 / 48 (blobs could be one MultiMesh draw) | 69k / 63k | 37 / 69k |
| **F** Concept target | D's shaders pushed to golden hour (low orange sun, blue shadows, warm haze, strong soft bloom), far backdrop (meadow, mountains, castle, tree line), traveller-gear hero | 51 / 48 | 166k / 138k | 50 / 114k |
| **G** Target 03 recreation | The Kingsreach gate market of `docs/art/reference/03_TARGET_gate_market_detailed.webp`: 50 m street, 16 jettied townhouses (LOD0/1/2 by distance), 12 stalls with goods, banners, lamps, guards with spears, 9 townsfolk, hero from behind; **code-built gatehouse** (two round crenellated towers, arch, raised portcullis, red lion banners, flags) with Poly Haven `castle_wall_slates` | 143 / 112 | 334k / 244k | 534 / 1.14M (4 shadow splits over 110 m: drop to 2 splits / 60 m on phones) |

LOW-tier budget from `ashes-performance`: <= 150 draws in a town view, <= 300k triangles. A-F are far below it; **G is at the edge (143 draws, 334k tris)**: it needs the game's usual levers (distance culling, MultiMesh stalls/crates per street cell, 2 shadow splits) before it ships on LOW. Texture memory of the whole lab process was about 615 MB because Poly Haven textures are 2K; on phones use 1K (`tex_bias`) for C and G (about 4x less).

### Cheap vs expensive on phones
| Effect | Cost | Notes |
|---|---|---|
| Colour grade (tonemap, saturation, contrast, LUT) | cheap-moderate | One full-screen pass in Mobile/Forward+; the tonemap is free on Compatibility but **adjustments/LUT are a full-screen pass**: E drops them and bakes the grade into material saturation |
| Warm/cool light colours, ambient colour, sky gradient | free | Do this first on every tier |
| Toon ramp (`lab_toon`) | cheap | Custom `light()`, 1 texture; runs on Compatibility |
| Ink outline (`next_pass`) | **doubles draws + vertices** of outlined meshes (64 vs 36 draws), fragment cost tiny | Outline only characters + hero buildings on MEDIUM, nothing on LOW; or bake it into the textures |
| Lambert-wrap, rim, hemispheric bounce (`lab_polished`) | cheap | ~35 ALU, 1 tap; no extra passes |
| Per-vertex lighting (E) | cheapest | Slight Gouraud look on big triangles |
| Skin SSS | **not available** | The SSS pass is Forward+ only and blacked the characters out in the Lab: faked with warm emission |
| Bloom/glow | moderate (several blur passes) | MEDIUM+ only; skip on LOW (game already does) |
| SSAO | expensive, **Forward+ only** | Replace with baked height-AO ramp in the shader + contact-shadow blob quads (cheap, every renderer) |
| Height fog / depth fog | cheap | Per-pixel math, fine on every renderer |
| Volumetric fog, SSIL, SDFGI, SSR | very expensive, Forward+ only | Not used |
| Decals | moderate, Mobile + Forward+ only (not Compatibility) | Keep few; the game's LOW tier is Compatibility |
| Planar PBR with normal + ARM maps (`lab_grounded`, ground mode 1) | **7 texture taps**, ~60 ALU | HIGH tier only; LOW/MEDIUM: bake the same detail into the existing painted atlases or use albedo-only |
| Realtime omni light (lantern) | per-pixel cost on everything it touches | One only (C, D, F); the additive glow sprite is the cheap version and is in every box |
| Directional shadow splits | splits x scene geometry | G shows 534 shadow draws at 4 splits: 2 splits / 60 m / 2048 map on phones |
| Skinned characters | ~1.5k-3k tris each, 1 draw per surface | Unchanged by style |

## Honest assessment against the references
* **Closest to reference 00/03 today: G** (and, of the diorama boxes, **F** then **D**). G is a rebuilt scene, the others restyle a small corner, so G is the only one with the references' composition, depth and gatehouse.
* **G reaches about 55-60% of target 03** in my judgement (composition, street and gate silhouette, striped stalls, banners, guards and townsfolk placement, sun and sky, long cobbled perspective ~80%; material richness, density and the hero ~35-40%). What is missing:
  1. **Scan-like surface detail**: target walls/timber are weathered and photoreal-painterly; ours are the flat painted Meshy atlases (G's cobbles and gate stone are real PBR and are the best match).
  2. **Density and greenery**: ivy and hanging plants on facades, flower tubs, hanging pots, shelves of goods on the stalls, awnings with cloth drape, props everywhere. The stalls are the game's 3.5 m kit; needs 2-3x the dressing and an ivy/vine decal kit.
  3. **Hero**: target is a young man with shaggy hair, green tunic, hooded brown leather vest, satchel, bracers. G6 Hunter's Leathers + a green skirt + box satchel is a placeholder (the hood and shoulder cape are not modelled; hair is G6 hair_5). A bespoke (Meshy/Blender) hero and the villagers/guards at 2x screen size would close most of the gap.
  4. **Crowd**: target has ~25 people at all depths; G has 9 + 4 guards, some stand-ins use the idle clip.
  5. **Gate**: arch is round (target pointed with voussoir ring), tower tops lack machicolations and conical roofs on the small turrets, no ivy, portcullis is a plain grid.
  6. **Colour**: G is cooler and cleaner; target has stronger golden bounce light, richer shadows and local contrast (needs GI-like baked bounce).
* **Style picks:** if the owner wants "real medieval" grit: C's PBR approach on G's composition (C's own look is too grey and foggy as shown, re-tune). If "polished mobile RPG": D/G. B (storybook) is the most distinct but furthest from references 00 to 03.

## Characters
Every box shows **today's hero** (`player_young`, MakeHuman, `Assets.character("Player")`), the **improved hero** and one villager (`villager_woman_a`).
The improved hero is the CC0 System G6 modular human (`assets/incoming/characters/g6-ual/g6_m_modular_all.glb`, 65-bone UAL skeleton, so **all existing animation works unchanged**): villager tunic, brown leather boots, linen shirt, head 3, brown hair, built by `character_creation.gd build_model()` with `NEW_LOOK` in `scripts/style_lab/lab_chars.gd`. About 3k triangles. Other free candidates already in the repo (see `assets/incoming/characters/_previews/characters_sheet.png`): G6 apron/leather outfits, CDmir monk / old lady (CC0), Quaternius Ultimate Modular Men/Women (CC0, 5-7k tris, UAL compatible). No new third-party files were added, so `CREDITS.md` is unchanged.
Animation is untouched (Codex owns it): the lab only plays the existing `Idle` clip.

## Applying a style game-wide (recipe)
1. **Environment + sun:** copy `env_for(<id>)` and `_sun(<id>)` into `main.gd _build_environment()` (replace the `Environment` block; keep `_update_daylight()` driving `sun.light_energy/colour` and `env.ambient_light_energy` multiplicatively so day/night still works). Sky shader: `shaders/style_lab/lab_sky.gdshader` (gradient + clouds, one texture tap).
2. **Materials:** the shaders take an object's own albedo atlas, so no asset needs re-export. Put the material swap in ONE place: `Assets` (`building_mesh`, `merged_mesh`, `_transformed`) and `MarketGoods.material()`. Loop over the mesh surfaces once at cache time, build the `ShaderMaterial` with `lab_common.gd params()/apply_albedo()`, and set it as the surface material of the cached `ArrayMesh`. MultiMesh instances then share it automatically (draw calls unchanged). Terrain: add the style's splat shader in `terrain_streamer.gd` (`lab_ground*.gdshader` use the same vertex-colour splat encoding R = mud/path, B = cobble).
3. **Characters:** `Assets.mh_character()` / `humanoid()` end with the skeleton and its `MeshInstance3D`s; apply the character material factory (`lab_style.gd _polished`/`_toon`) per mesh there. The improved hero: set `MH_LOOKS["Player"]` to a G6 modular look (or call `character_creation.gd build_model` as `player.gd _build_body` already does for `Life.appearance`).
4. **Tiers:** keep the LOW/MEDIUM/HIGH split in `quality.gd`. Each style lists its cheap and expensive parts below; the "lite" variant (box E) is the LOW tier of any style.
5. Re-run `tools/qa/bench` (village, city) and the Style Lab sheet; record numbers in `docs/qa/PERFORMANCE.md`.

## Known issues in the Lab itself
* G6 modular meshes (`human_*`) have dark vertex colours on top of their texture: lab shaders ignore vertex colour for them (`lab_style.gd _polished`); MakeHuman meshes need it.
* The Quality autoload overrides environments, suns and viewports; `lab_style.finalize()` re-applies the style after it (and forces `--quality=high` in shots).
* Box E's contact-shadow blobs are 15 draws; batch them in one MultiMesh before judging its budget.
* Style F's backdrop (cones for mountains, 16 trees) is crude; a baked panorama sky-dome would be better and cheaper.
