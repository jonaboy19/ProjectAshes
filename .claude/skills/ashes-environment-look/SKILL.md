---
name: ashes-environment-look
description: Recipe for Rising Ashes open-world surfaces in Style G - terrain ground, grass, paths/mud, rocks, cave rock - plus the fixed capture views and per-tier costs. Use when touching shaders/terrain.gdshader, shaders/grass.gdshader, GrassField, TerrainStreamer materials, dungeon shells, or judging "the ground doesn't look real".
---

# Environment look (ground, grass, rock)

Owner brief (2026-10-05): "grass/ground don't fit the world, not real enough. Style G, but GREAT." Target: docs/art/reference/03_TARGET.

## Views and capture (GPU only, never --headless)
`tools_qa/environment/env_views.json` (e01-e08 open world, p01-p06 Thornfield POIs at real world positions).
```
godot --path kingdom --resolution 960x540 -s res://tools_qa/region1/look_capture.gd -- --adult --quality=high \
  --views=res://tools_qa/environment/env_views.json --out=<abs dir> --tag=after [--only=a,b]
```
ALWAYS pass `--quality=high|low`: without it AUTO picks a tier and the look differs wildly. look_capture now hides HUD/caption
CanvasLayers (keeps the SubViewport layer). Rift interiors: `tools_qa/thornfield_wilds/wilds_standalone.gd -- --only=rift`
(its outdoor views use a stand-in heightfield with no terrain shader or grass: NOT the game look, do not judge ground from it).
Do not run captures while another agent exports an APK on the same PC (check Godot processes for `--export`).

## Terrain (shaders/terrain.gdshader)
- Tier switch: global `ashes_ground_detail` (Quality: LOW 0, MEDIUM 0.5, HIGH+ 1).
- Anti-tiling: second tap rotated per ~23 m cell (macro noise angle), weight 0.25-0.6; normal XY rotated back. LOW: 1 tap.
- Height blend (hb 0.75): layer height = AO x luminance (+bias: path .05, rock .1, cobble .15), keep within 0.08 of the max.
- Path shoulders: COLOR.r ramp 0.08-0.8 -> darker damp mud band, noise-broken; rougher.
- Under-grass shade: grass layer tinted toward `grass_root_col` (3a4d17) to 70 %, fades out by `grass_shade_end` (70 m = grass fade).
- Detail normal: grass normal at 4.3x, 6-28 m from camera, HIGH only.
- Far calm: 120-600 m drift 25 % toward a desaturated warm value.

## Grass (shaders/grass.gdshader + GrassField)
- Ground match: per clump (vertex), sample terrain grass albedo at mip 9 + same lush/parched macro + Region1 biome patchwork
  -> roots 75 %, tips 45 % toward the soil colour; 38-66 m melt fully into ground colour (no fade line).
  TerrainStreamer passes `macro_noise`/`ground_albedo`, Region1Look passes `region_biome` to GrassField's shared material.
- Existing: clumping, travelling gusts, SSS, trampling (8 interactors), near-camera sink.

## Cave rock (shaders/environment/cave_rock.gdshader)
Rock-theme dungeon shells (Rift): world triplanar, sharpened weights (pow 4), Poly Haven rocky_terrain_02 albedo+normal(whiteout)+ARM,
2.6 m tile + 37 m macro tint, vertex colour 70 %, dusty up-faces, damp low band. LOW: single dominant-axis tap, no normal.

## Squad banners
`squad.gd`: "☠ N · Line" standards show only in command view (player.view >= 2), for every squad incl. bandits/garrisons.

## Known open items (not this pass)
Oakvale aerial washout = fog/aerial perspective at altitude (Style G env owner); blurry/pixelated house atlases up close = asset
texture resolution/filtering (build-kit / Meshy agents).

## Pass 3 (2026-10-05) - shipped
- Rift: `thornfield_rift.json` organic=true (jittered two-row walls: real cave silhouettes instead of 3 m boxes) + cave_rock with
  Poly Haven rock_face 1k (tile 4 m, rock.png 7 m macro at 0.35, luminance-only contrast, no vertex-colour darkening).
  Lesson: the first version looked "flat" because the post chain crushed a low-contrast scan in a dark, foggy room; probe with
  ALBEDO = raw sample before tuning (no `return` in fragment()).
- look_capture pins WorldSim.time_of_day every frame (intro/sleep advance_hours() pushed shots to night).
- Terrain/grass edits stay on local-wip/env: neutral at best; the COLOR.r mud shoulder draws a hard dark rim on cobbles.
