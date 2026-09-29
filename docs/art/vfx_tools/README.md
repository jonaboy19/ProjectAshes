# VFX tools: findings, proof, and upgrade plan (2026-09-29)

Goal: premium VFX for the Godot 4.6.3 mobile RPG, in the sunny storybook style, with free tools that are allowed in a commercial game. Install notes and scripts: `tools/vfx/README.md`. Earlier shader/texture research (not repeated here): `docs/art/free_vfx_shader_research.md`.

Pictures in this folder: `flipbook_atlases_overview.png` (the six new sheets), `gallery_new_sheet_001.png` and `_002.png` (in Godot, stop-motion, 10 fps), `gallery_old_sheet_001.png` (the closest existing elemental effects, same stage and camera), `effekseer_demo.png`.

## 1. Tool verdicts

| Tool | Licence | Windows | Godot 4.6 | Mobile cost | Value | Verdict |
|---|---|---|---|---|---|---|
| **Blender 5.2** Mantaflow + Cycles (flipbook baking) | GPL tool, renders are ours | installed | output is plain PNG | 1 quad, about 0.05 ms CPU | high | **Use.** Fire and liquid sims work. Volume smoke looked photoreal and grainy, so smoke and dust use our cel-shaded lump baker instead. Bakes take minutes (gotchas in `tools/vfx/README.md`). |
| **numpy procedural bakers** (`tools/vfx/bake_*.py`, run in Blender's Python) | own code | yes | PNG | same | high | **Use.** Fastest route to the storybook look (cel bands, cool violet shadow, warm rim). Lightning, swirl, smoke and dust were made this way, each in about a minute. |
| **Material Maker 1.7** | MIT | GUI runs (Godot 4.7 build) | exports PNG / Godot materials | none (offline) | medium | **Keep for hand-authored tiling noise, gradients and masks.** Headless `--export-material` ran but wrote no files (1.7 expects `user://export_targets`, which a fresh install does not create), so it cannot be a scripted step. The shipped sheets do not use Material Maker output. |
| **Effekseer editor 1.80.7 + EffekseerForGodot4 1.80.5.1** | MIT (samples CC0) | yes | **works** (section 2) | high (section 2) | medium-low for us | **Vendored, not enabled, not wired.** Only for hero effects we cannot bake. |
| **TextureLab** | GPL-3, Electron | yes | PNG | none | low | Skip. No animation export; the repo says it is being rewritten. |
| **Laigter** | GPL-3 (tool only, output is free) | yes | PNG | none | low | Skip for now. Only useful for lit 2D sprites (normal maps); our VFX are unlit. |
| **Kenney Particle Pack** | CC0 | in repo | PNG | very low | done | Already used by ElementFX. Static masks only, which is why the current effects look flat. |
| **GODOT-VFX-LIBRARY (haowg)** and similar Godot VFX repos | MIT repo, asset provenance unclear | | | | low | Skip unless one scene is worth restyling. We cannot ship art whose source is unknown. |
| **Unity Labs Paris flipbooks** (CC0 smoke, fire, explosion sequences) | CC0 | download only | PNG | low | low | Realistic, wrong style. Fallback if a baked sim is needed in a hurry. |
| **ambientCG / Poly Haven** | CC0 | web | PNG | | low for VFX | Surface scans and HDRIs. Nothing VFX-shaped (no fire, smoke or water sprites). |
| **ShaderToy** | per shader, default CC BY-NC-SA | web | GLSL | | technique only | **Do not copy code** (non-commercial). Learn the techniques and write our own. |
| Gabriel Aguiar tutorials | tutorial content, assets mostly paid | | | | | Watch for techniques, do not import assets. |

## 2. Effekseer verdict

Tested with the CC0 "Aura01" sample from the editor, first in a scratch project and then inside `kingdom/`:
- **Godot 4.6.3 desktop, Mobile (Vulkan) renderer: works.** Aura and light samples render; 6 aura instances run at 84 fps.
- **Compatibility (OpenGL) renderer: the extension loads and does not crash, but draws nothing** (it renders through RenderingDevice). The game's LOW tier falls back to `gl_compatibility` on some phones, so every Effekseer effect needs a flipbook or particle fallback there.
- **Android:** the release ships `libeffekseer.arm64.so`, `arm32`, `x86_64`, `x86_32` (10 MB). iOS ships static xcframeworks (124 MB, left out of the repo; copy them back when building for iOS). Web wasm exists. I could not run on a phone from this PC, so mobile is "plausible, unmeasured".
- Boot is not affected: the game boots headless with the extension present (`--quit-after 240 -- --skip-intro`). The editor plugin is **not** enabled in `project.godot`. The extension loads by itself from `addons/effekseer/effekseer.gdextension`; the plugin is only needed to import `.efkefc` files.
- Import pitfall: with an existing `.godot` cache, `godot --import` does not register the plugin's importer in time, so `.efkefc` files never import. `tools/vfx/efk_import.gd` converts them to `.res` with the extension's own `EffekseerEffect.import()` (used for `assets/vfx/effekseer/00_Version16/aura01.res`).
- Style: the samples are neon/anime. A warm storybook look means authoring in the Effekseer editor with our own textures.

Cost (RTX 4070 laptop, Mobile renderer, 1280x720, average of 180 frames; `effekseer_demo.tscn --perf`, `flipbook_gallery.tscn --perf`):

| Scene | CPU render ms | GPU ms | draw calls |
|---|---|---|---|
| 1 Effekseer Aura01 | 0.67 | 0.18 | 8 |
| 6 Effekseer Aura01 | 2.05 | 0.89 | 48 |
| 12 Effekseer Aura01 | 2.87 | 1.04 | varies |
| 6 new flipbooks playing at once (whole stage) | 0.79 | 0.36 | 17 |
| 6 existing ElementFX effects playing at once (whole stage) | 1.20 | 0.48 | 37 |

A phone CPU is 4-6x slower, so one Effekseer aura costs roughly 3-4 ms of CPU on a phone, while a baked flipbook quad is about a tenth of that. Recommendation: do not use Effekseer for routine combat effects. Consider it later for one or two boss or ultimate effects on the HIGH tier, behind a renderer check.

## 3. What was proven: six new flipbooks

All in `kingdom/assets/vfx/flipbooks/` (licences: `LICENSE.md`, project-owned, no third-party content). Atlases are at most 1024 px, VRAM-compressed on import, alpha-blended (no additive wash-out in daylight). Player: `FlipbookFX.play(&"fire_burst", pos)` (`kingdom/scripts/vfx/flipbook_fx.gd`), shader `kingdom/shaders/vfx_flipbook/flipbook.gdshader` (frame blending, tint, energy, per-instance progress, pooled quads). Gallery: `kingdom/tools_qa/vfx_flipbooks/flipbook_gallery.tscn` (`--mode=new|old|grid`, `--perf`).

| Sheet | Method | Grid | Frames | Play time |
|---|---|---|---|---|
| fire_burst | Blender Mantaflow fire, Cycles volume, gradient map to a warm cel ramp | 4x4 @ 256 | 16 | 0.85 s |
| smoke_puff | numpy cel-shaded lumps, warm light and violet shadow, noise dissolve | 8x8 @ 128 | 64 | 2.2 s |
| dust_burst | numpy: ground ring of lumps and thrown rocks | 8x8 @ 128 | 64 | 1.7 s |
| water_splash | Blender Mantaflow FLIP liquid, toon emission ramp, pool surface masked out | 4x4 @ 256 | 16 | 0.9 s |
| lightning_sheet | numpy: midpoint-displaced bolt, branches, ground flash, gold/violet glow | 4x4 @ 256 | 16 | 0.8 s |
| magic_swirl | numpy: 3-arm log spiral, warped noise, sparkles (loops seamlessly) | 4x4 @ 256 | 16 | 1.2 s loop |

Review (frame sheets read in order: `gallery_new_sheet_001.png`, `_002.png`):
- Smoke, dust, swirl and lightning read clearly at phone size, match the painted cumulus style, and fade cleanly or loop.
- The water splash has a crown, a central jet and a collapse. The crown is very wide, and around frame 5 the sheet is almost empty for one frame (real physics; retime if it flickers in use).
- Fire is the weakest: the sim starts as a flat disc for 3-4 frames and rises as a mushroom. The colour ramp is right (cream core, orange, red, dark soot) but the shape is not yet a storybook fireball. Treat it as v1.
- Known limits: the shader is a camera-facing billboard (no ground-plane mode yet, so the swirl cannot lie flat as a sigil). Each sheet has one colour set; the `tint` argument recolours it per element.

## 4. Comparison with the current elemental effects

`gallery_old_sheet_001.png` versus `gallery_new_sheet_001.png` (same stage and camera, 10 fps):
- Current fire impact is a cel-banded orange dome with red and green blotches: readable as fire but flat, no billowing, no soot. The new fire burst has volume, a hot core and a smoke tail.
- Current dark and earth impacts are low-contrast grey and brown puffs. The new smoke and dust have clear lit and shadow lumps and thrown rocks, and dissolve at the end.
- Current water impact is a faceted crystal bowl. The new splash has a real crown, jet and droplets.
- Current lightning AOE is a hard white zig-zag with a huge ground disc that spills over the neighbouring slots at 3 m radius. The new lightning has branches, a ground flash and a soft gold/violet glow in a fraction of the screen area.
- Cost is equal or lower: 6 flipbooks 0.79 ms CPU and 17 draw calls versus 6 ElementFX 1.20 ms and 37 draw calls (desktop GPU).

## 5. Upgrade suggestions per element

General rule: keep the existing `ElementFX` scenes for charge, aura, projectile, beam and status loops (particles suit those), and use flipbooks for the moments that carry the read: impact bursts, ground bursts, big AOE centres. Recolour a sheet per element with the `tint` argument instead of baking eight versions; bake a new sheet only when the silhouette differs.

| Element | Now | Upgrade |
|---|---|---|
| fire | impact is an orange dome; aoe is a ring and a wall | `fire_burst` at the impact point (scale 0.6-1.2), keep the existing nova ring under it. Re-bake v2: start the sim at frame 8 so the disc phase is gone, larger emitter with a noise-displaced surface, lower `burning_rate`. Add `smoke_puff` tinted charcoal (0.35, 0.3, 0.3) 0.3 s after the flame peak. |
| water | impact is a crystal bowl; geyser and wave ring | `water_splash` for impact and for the geyser base; drop the crystal bowl. Keep the wave ring at ground level. Bake a vertical water column sheet later. |
| earth | impact is grey rocks; spikes erupt | `dust_burst` at each spike eruption and on impact (scale 0.7-1.4), tint (0.85, 0.7, 0.5). The rocks inside the sheet replace the separate rock-chunk particles on LOW. |
| wind | tornado and leaves | `smoke_puff` tinted white-green at low alpha as gust punctuation. Bake a wind variant of `magic_swirl` (fewer sparkles, 6 pale arcs) for the tornado base. |
| lightning | sky strike and ring; jagged beam | `lightning_sheet` for the strike (size 4 m; keep the 0.28 s telegraph ring). Chain arcs can reuse the sheet rotated. |
| ice | frost nova and spikes | `smoke_puff` tinted pale cyan (0.7, 0.9, 1.0) at 0.5 alpha as frost mist on the nova. Bake a frost burst (numpy: crystal shards fanning out) as the seventh sheet. |
| light | pillar and sigil | `magic_swirl` (gold, energy 1.6) as the halo above heals. Needs a ground-plane mode in the shader for a flat sigil (`billboard = false`). |
| dark | void disc and tendrils | `smoke_puff` tinted deep violet (0.35, 0.2, 0.55) with `energy` below 1; `magic_swirl` tinted violet for the void vortex. |
| generic hit, level-up | sparks, ribbons | Small `dust_burst` or `smoke_puff` at scale 0.3 on hit; `magic_swirl` tinted per element on level-up. |

Next steps in value order: (1) ground-plane mode in `flipbook.gdshader`; (2) fire v2 and a frost burst sheet; (3) wire `FlipbookFX` into `ElementFX` impact and aoe with a `Quality` tier switch (LOW: 16-frame sheets only, no frame blending); (4) measure on a real phone (Adreno 610 / Mali-G52). Each 1024 px atlas is about 1 MB of VRAM compressed (4 MB if left lossless), so the six sheets are about 6 MB.
