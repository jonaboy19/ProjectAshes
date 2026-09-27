# Performance and quality tiers (2026-09-27, local PC)

Machine: laptop, **NVIDIA GeForce RTX 4070 Laptop GPU**, 16 threads, 16 GB RAM, Windows 11, Godot 4.6 stable.
Window 1280x720 (the game's base size; on phones the 3D view is the same logical size, see below).
Tool: `tools/qa/bench/bench.gd` (boots the real game, teleports, settles 12 s, measures 10 s uncapped,
vsync off) via `bash tools/qa/bench/run.sh`. Raw lines: `docs/qa/bench_results.jsonl`, `bench_final.jsonl`.

**Caveat:** two other local agents (animation QA, a playtest bot) were running Godot on the same GPU/CPU
for part of the session. The first matrix below ran while the machine was quiet; the per-tier run
afterwards had other Godot processes active, so its absolute fps are ~30 % low. Compare within a table.

## Quality tiers (`kingdom/scripts/core/quality.gd`)

| | LOW | MEDIUM | HIGH | ULTRA |
|---|---|---|---|---|
| Meant for | Mali-G52/G57, Adreno 5xx-620, PowerVR, <=3 GB, Compatibility renderer | Adreno 640-650/7xx-low, Mali-G68..G78, Apple A11-A12 | Adreno 730+, Mali-G710+, Apple A13+, integrated PC GPUs | desktop discrete GPUs |
| 3D height cap (upscaled) | 540 px, bilinear | 720 px, FSR1 | 900 px, FSR1 | native |
| Max fps | 30 | 60 | 60 | uncapped (60 on phones) |
| Sun shadows | off | 1 split, 55 m, 2048 atlas | 2 splits, 100 m, 4096 | 4 splits, 140 m, 4096 |
| Soft-shadow filter | hard | low | medium | high |
| Omni/spot light shadows | off | off | on | on |
| SSAO / SSIL / SDFGI / vol. fog / SSR | off | off | SSAO only (Forward+) | all but SSR (Forward+) |
| Glow | off | off | on | on |
| Mesh LOD threshold (px) | 8 | 2 | 1 | 1 |
| Visibility ranges (props, trees, grass fade, building LOD swap) | x0.55 | x0.75 | x1 | x1 |
| Towns (buildings with no range) drawn to | 420 m | 600 m | camera far | camera far |
| Grass + undergrowth kept | 30 % | 60 % | 100 % | 100 % |
| Particles (amount ratio) | 35 % | 60 % | 100 % | 100 % |
| Light distance fade | 35 m | 50 m | 80 m | off |
| Props < 1 m cast shadows | no | no | no | yes |
| Anisotropic filtering | off | 2x | 4x | 8x |
| AA | none | none | FXAA | MSAA 2x + FXAA |
| People: full 3D / sprites per look | 6 / 40 | 12 / 120 | 24 / 300 | 24 / 300 |
| Terrain view radius (64 m chunks) | 2 | 3 | 4 | 5 |
| Physics ticks | 60 (unchanged: player/army use `_physics_process` + `move_and_slide`, 30 Hz without physics interpolation judders) | | | |

AUTO: first launch picks from GPU name/vendor/type, renderer, RAM, cores (e.g. RTX 4070 -> ULTRA,
Compatibility renderer on a phone -> LOW, Mali-G52 -> LOW, <3.2 GB RAM -> LOW, <5 GB -> max MEDIUM).
Then, after loading, it measures 16 s of frames (after a 4 s warm-up) and steps down one tier at a
time while the average is below 85 % of the target (30/60). A desktop discrete GPU is never stepped
below HIGH (it is CPU-bound, see below). Players can override in Pack -> Settings & Credits, plus a
30 fps battery saver; saved in `user://settings.cfg`. `--quality=low|medium|high|ultra` forces a tier.

Renderer: Forward+ on desktop, **Mobile on Android/iOS** (`rendering_method.mobile`), and
**Compatibility (GLES3)** fallback when Vulkan is missing (`rendering_device/fallback_to_opengl3`).
Compatibility check (`--rendering-method gl_compatibility`): the game, water (screen/depth texture),
terrain, grass, impostor and sky shaders all run; no shader errors. The only messages are Godot's
"only available in Forward+" warnings for effects main.gd enables before Quality turns them off.

## Results: quiet machine (LOW vs HIGH, Mobile and Compatibility renderer)

| Renderer | Scene | Tier | fps (uncapped) | frame ms avg / p95 | GPU ms | draw calls | primitives | people full/sprites |
|---|---|---|---|---|---|---|---|---|
| Mobile | village | LOW | 95.8 | 10.4 / 13.0 | 3.4 | 346 | 0.90 M | 6 / 117 |
| Mobile | village | HIGH | 54.4 | 18.4 / 25.0 | 8.0 | 799 | 5.14 M | 24 / 281 |
| Mobile | capital street | LOW | 65.2 | 15.3 / 25.0 | 3.6 | 227 | 1.55 M | 6 / 160 |
| Mobile | capital street | HIGH | 39.9 | 25.1 / 42.4 | 9.7 | 565 | 4.83 M | 24 / 1200 |
| Mobile | battle (24 soldiers charge) | LOW | 114.6 | 8.7 / 11.1 | 4.4 | 258 | 1.67 M | - / 103 |
| Mobile | battle | HIGH | 56.7 | 17.7 / 18.1 | 16.6 | 539 | 4.35 M | - / 179 |
| Compatibility | village | LOW | 71.2 | 14.0 / 20.8 | 4.2 | 522 | 0.89 M | 6 / 117 |
| Compatibility | village | HIGH | 40.3 | 24.8 / 36.5 | 8.0 | 1410 | 5.08 M | 24 / 288 |
| Compatibility | capital street | LOW | 43.3 | 23.1 / 35.1 | 6.5 | 430 | 1.55 M | 6 / 160 |
| Compatibility | capital street | HIGH | 23.9 | 41.9 / 100 | 10.3 | 1243 | 4.82 M | 24 / 1200 |
| Compatibility | battle | LOW | 108.2 | 9.2 / 11.9 | 3.6 | 491 | 1.67 M | - / 103 |
| Compatibility | battle | HIGH | 77.6 | 12.9 / 15.8 | 10.8 | 973 | 4.31 M | - / 180 |

All four tiers, village (other Godot processes active, so fps ~30 % low):

| Renderer | Tier | fps | frame ms / p95 | GPU ms | draws | primitives |
|---|---|---|---|---|---|---|
| Mobile | LOW | 66.5 | 15.0 / 17.4 | 4.1 | 352 | 0.83 M |
| Mobile | MEDIUM | 42.0 | 23.7 / 31.1 | 5.8 | 605 | 2.30 M |
| Mobile | HIGH | 33.7 | 29.6 / 42.1 | 8.3 | 777 | 5.13 M |
| Mobile | ULTRA | 32.0 | 31.2 / 44.8 | 9.0 | 843 | 7.33 M |
| Forward+ | ULTRA | 28.5 | 35.0 / 63.1 | 14.2 | 2186 | 7.18 M |
| Compatibility | LOW | 27.5 | 36.3 / 44.3 | 4.2 | 506 | 0.83 M |

After the last fix (small props stop casting shadows) the Mobile village is **282 draw calls at LOW**
(was 352) and 680 at HIGH (was 777).

Screenshots of the same view: `docs/qa/quality_low.png` (LOW) and `docs/qa/quality_high.png` (HIGH),
Mobile renderer. LOW has no sun shadows and a softer 540p image but reads well: same colours, materials
and layout, people and stalls intact. UI: `docs/qa/ui_settings.png`, `docs/qa/ui_credits.png`.

## What LOW means for an old phone

Typical budgets for 30 fps on a Mali-G52 (e.g. Galaxy A21s/A32) or Adreno 610 (Galaxy A11/A12,
Redmi 9 class): **~150-300 draw calls** and **~150-300k triangles per frame**, and ~300-500 MB of
texture memory before the OS starts killing the app on a 3 GB device. The GPU here is ~15-25x faster.

| Village, LOW (Mobile) | Measured | Old-phone budget | Verdict |
|---|---|---|---|
| Draw calls | 282 | 150-300 | at the limit |
| Primitives | ~0.82 M | 150-300 k | **~3x over** |
| GPU time here | 2.4-4 ms | x15-25 on Mali-G52 -> 35-100 ms | 30 fps likely only in light scenes |
| Textures in use | ~354 MB at 1 B/px (ASTC/ETC2), 204 textures, most 2048 px | 300-500 MB | tight |
| Main thread | 9-15 ms here | x3-4 on a Cortex-A55 phone | **the biggest risk** |

So: LOW is playable on mid-range phones today; on the oldest phones it needs the geometry and
CPU items below. A real-device run is still required (see docs/RELEASE.md).

## Top 5 remaining costs

1. **Main-thread CPU (biggest).** The PC is CPU-bound in every scene: frame 10-35 ms while the GPU
   needs 3-14 ms. Toggling systems off one at a time (`bench.gd --profile`) showed no single script
   dominating (noise from the other agents' Godot runs); the cost is spread over draw submission
   (up to 2186 draw calls on Forward+ ULTRA), WorldSim (5,000 people), streaming and 24 animated
   villagers. Next: profile on a device with the Godot profiler; lower `WorldSim` slice size and
   `PopulationLOD.refresh()` rate on LOW.
2. **Triangles in town (LOW 0.8 M).** Settlements are ~600k of it (`bench.gd --gpuprof`): Meshy
   hero buildings are 20-40k tris each at LOD0 and in-town trees 5-6k. Fixed cheaply: merged meshes
   had lost their LODs (13 M -> 5 M primitives at HIGH, see commit 77a1c958), LOW uses a
   stronger LOD threshold. Remaining fix (asset side): real `_lod1` trees (~800 tris) or tree impostors,
   and Meshy LOD1 at a shorter distance on LOW.
3. **Texture memory.** ~354 MB in view on LOW, most textures 2048 px (Poly Haven terrain x15,
   nature megakit bark/leaves, Meshy buildings, props trim sheets). Fix: 1024 px mobile variants
   (import `process/size_limit=1024` per asset, or gltf-transform resize) for everything but the
   terrain's near layers. The 4K HDR sky (64 MB half-float) is now imported at 2048 (fixed).
4. **Draw calls.** 282 (Mobile LOW) / 506 (Compatibility LOW) / 680-2186 (HIGH/ULTRA): one
   MultiMesh per plant kind per 64 m chunk, per-building near/far pairs, contact-shadow quads.
   Fix: fewer scatter kinds per chunk on LOW, merge chunk scatter into one MultiMesh per kind per
   2x2 chunks.
5. **Shadows at HIGH/ULTRA.** Forest trees cast into 2-4 cascades; the battle scene's GPU time is
   mostly shadows (16.6 ms at HIGH). Fixed cheaply: small props (<1 m) no longer cast below ULTRA
   (-100 draw calls in the village), local lights fade out by distance (street lamps, camp fires),
   no omni shadows below HIGH.

Also fixed: the impostor-bake SubViewport rendered every frame for the whole game
(`UPDATE_ALWAYS`); it now idles between bakes. The root viewport no longer runs FXAA/MSAA over the
UI (the world renders in its own SubViewport).

## How to reproduce

```bash
bash tools/qa/bench/run.sh                                   # LOW+HIGH x Mobile+Compat x 3 scenes
TIERS="low medium high ultra" RENDERERS=mobile SCENES=village bash tools/qa/bench/run.sh
# one run with a per-layer GPU/primitive breakdown:
godot --path kingdom --rendering-method mobile -s <abs>/tools/qa/bench/bench.gd -- \
      --adult --skipintro --quality=low --scene=village --uncapped --gpuprof
# --census (LOD0 tris by mesh), --textures (textures in use), --png=<file> (screenshot, HUD hidden)
godot --headless --path kingdom -s <abs>/tools/qa/bench/check_clips.gd   # clip library check
```
