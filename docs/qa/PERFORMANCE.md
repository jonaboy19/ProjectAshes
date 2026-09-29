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

## Low-end budget pass (2026-09-27, later the same day)

Goal: LOW inside a Mali-G52 / Adreno 610 budget in the village: **<= 300k triangles, <= 250 draw
calls, <= 150 MB textures**. Same PC, Mobile renderer, 1280x720, bench.gd uncapped; other agents'
Godot/Blender jobs were running, so compare counts, not fps. Draw calls include the HUD (~55 in the
village; `--png` runs hide it).

| Scene, tier | Draws before -> after | Primitives before -> after | Texture VRAM on PC (`tex_mb`) | Phone export texture estimate |
|---|---|---|---|---|
| Village LOW | 336 -> **294** (3D only: **234**) | 0.83 M -> **0.29 M** | 948 -> 224 MB | **~121 MB** |
| Capital LOW | 237 -> 265 | 1.55 M -> **0.42 M** | 948 -> 225 MB | ~118 MB |
| Battle LOW | 229 -> **186** | 0.58 M -> **0.18 M** | 933 -> 220 MB | ~113 MB |
| Village HIGH | 680 -> **617** | 5.14 M -> **1.89 M** | -> 286 MB | ~133 MB |
| Capital HIGH | 565 -> 592 | 4.83 M -> **1.82 M** | -> 288 MB | ~136 MB |
| Battle HIGH | 539 -> **478** | 4.35 M -> **1.46 M** | -> 285 MB | ~130 MB |

Raw lines: `docs/qa/bench_results.jsonl`. "Phone export estimate" = textures in use after the mobile
export caps below, at 1 B/px ASTC/ETC2 incl. mips (`bench.gd --textures`).

Village LOW vs the budget: **triangles 0.29 M (in), draw calls 234 in 3D / 294 with the HUD, textures
~121 MB (in)**. The capital is still over on triangles (0.42 M) and at the limit on draws.

What changed (commits a9a49831, 9bb0a44e, 96880162 and the one with this doc):

1. **Meshy buildings: clean LOD chain.** `tools/meshy/bake_lod.py` (voxel shell + decimate + colour
   bake from LOD0, so nothing shreds) made LOD2 (hero 7k, houses 3.5-5.5k tris, 512 px) and LOD3
   (0.9-1.6k tris, 256 px) for all 9 Meshy buildings, and rebaked the **broken LOD1s** of the inn,
   healer, trader, family house and peasant_b (collapse decimation had shredded them into shiny,
   crumpled shells: the "crumpled distant houses" in the store shots). Meshy meshes no longer get
   `generate_lods()` on top of their own LOD files. Chain: LOD0 -> LOD1 at 45/70 m -> LOD2 at
   100/150 m -> LOD3 at 160/220 m (x0.55 on LOW). **LOW never loads LOD0**: LOD1 < 25 m, LOD2 < 55 m,
   LOD3 beyond. The 16 Blender village houses, barn and chapel got a baked 1.2k-tri LOD2 too.
   Previews: `docs/kingdom/blender_previews/lod2/*_lods.png` (LOD0/1/2 side by side); aerial
   before/after: `docs/qa/lod_aerial_before.png` / `lod_aerial_after.png`.
2. **Per-cell batches.** A MultiMesh switches LOD and visibility as a whole (by its bounds' centre),
   so one town-wide batch drew every house at the near LOD. Meshy buildings and village greenery are
   batched per 40 m cell, yard clutter per 80 m cell (120 m range), town walls per 150 m. The Blender
   houses stay one batch per town (4-6 materials each: cells cost more draws than they save).
3. **Trees.** The painterly region trees (0.7-1.6k tris, `generated/region/nature`) replace the
   5-6k Blender trees and the megakit far stand-ins wherever trees are placed (forest chunks,
   village greenery): LOD0 < 40 m, LOD1 < 120 m, 4-tri impostor beyond (x0.55 on LOW). A chunk's far
   impostors are merged into one mesh (one draw per distant chunk) and get a horizontal crown card
   so they don't read as an "X" from the zoomed-out camera. Their wind ShaderMaterials are applied
   in `Assets` (the `.glb.import` swap the region README describes was missing, so COLOR_0 wind data
   tinted trunks black and leaves red). Bushes -> region bushes (316 vs 1489 tris), field fence ->
   region rail fence (72 vs 594 tris, x120 in a village).
4. **Textures.** 410 shipped 3D textures were still imported **Lossless** (the editor never flagged
   them as 3D because the world is built from scripts): 4 B/px uncompressed on a phone.
   `tools/qa/texture_vram.py` sets VRAM compression + mipmaps (normal maps flagged) on every texture
   the Android export ships: PC texture memory 948 -> 224 MB. **Mobile-only size caps:**
   `addons/mobile_texture_limit` (EditorExportPlugin, enabled in project.godot) downsizes
   `res://assets` textures to 1024 px (512 for photo-scanned clutter and animals) as ETC2 (Android) /
   ASTC (iOS) at export time; the editor and desktop keep 2048, so HIGH/ULTRA on PC stay sharp.
   Verified with `--export-pack Android`: e.g. `inn_lod0_Image_0.jpg` loads from the pck as a
   1024x1024 PortableCompressedTexture2D and decodes correctly. Run
   `py tools/qa/texture_vram.py --write` after adding textures (new glTF images import Lossless).
5. **Draw calls.** Contact-shadow quads batched per settlement (28 -> 12 in Ashford), haystacks one
   MultiMesh per town instead of a node each (5 surfaces per stack), 7 tree kinds per chunk.

Screenshots (Mobile renderer): `docs/qa/quality_low.png`, `docs/qa/quality_high.png` (street, same
view as before) and `quality_low_aerial.png` / `quality_high_aerial.png`. LOW still reads well at
street level. Playtest bot (`--steps=boot,village`): runs through, no new errors, 1 known finding
(no blacksmith lot).

## What LOW means for an old phone

Typical budgets for 30 fps on a Mali-G52 (e.g. Galaxy A21s/A32) or Adreno 610 (Galaxy A11/A12,
Redmi 9 class): **~150-300 draw calls** and **~150-300k triangles per frame**, and ~150-300 MB of
texture memory before the OS starts killing the app on a 3 GB device. The GPU here is ~15-25x faster.

| Village, LOW (Mobile) | Before this pass | Now | Budget | Verdict |
|---|---|---|---|---|
| Draw calls | 336 (HUD incl.) | 294 (234 without HUD) | <= 250 | 3D in; the HUD's ~55 push it over |
| Primitives | ~0.83 M | **~0.29 M** | <= 300 k | in |
| Textures | "354 MB at 1 B/px", but most were Lossless (4 B/px) | ~121 MB in the phone export | <= 150 MB | in |
| GPU time here | 2.4-4 ms | ~0.8 ms | x15-25 on Mali-G52 -> ~12-20 ms | fits 30 fps |
| Main thread | 9-15 ms | 7-9 ms (noisy) | x3-4 on a Cortex-A55 | **still the biggest risk** |

A real-device run is still required (see docs/RELEASE.md).

## Top remaining costs (after the budget pass)

1. **Main-thread CPU.** Unchanged in kind: WorldSim, population LOD, streaming, draw submission.
   Next: device profile; lower `WorldSim` slice size and `PopulationLOD.refresh()` rate on LOW.
2. **Capital at LOW: 0.42 M primitives, 265 draws.** The Blender houses (house_1..16) are 16 kinds x
   4-6 materials in town-wide batches: their LOD1 (2-3.6k tris) draws everywhere and each kind costs
   ~5 draws. Next: atlas them to one material so they can be cell-batched cheaply (then their baked
   LOD2 kicks in by distance); the town wall ring (~0.36 M LOD0 tris) needs a real low-poly LOD.
3. **HUD draw calls (~55 in the village).** Labels, panels, icons; batch/atlas the HUD or drop the
   debug fps line in release builds. 16-30 chickens/critters are individual MeshInstances
   (animation-owned code, left alone).
4. **Door/street clutter** (photo-scanned crates, baskets, buckets: 730-850 tris each, town-wide
   batches): swap to the props-atlas props for one shared material and fewer triangles.
5. **LOD1 trees from a steep camera** read as crossed cards (region LOD1 is a few large cards); a
   horizontal crown card in the region generator's LOD1 would fix it.

Also fixed earlier: the impostor-bake SubViewport idles between bakes; the root viewport no longer
runs FXAA/MSAA over the UI.

## How to reproduce

```bash
bash tools/qa/bench/run.sh                                   # LOW+HIGH x Mobile+Compat x 3 scenes
TIERS="low medium high ultra" RENDERERS=mobile SCENES=village bash tools/qa/bench/run.sh
# one run with a per-layer GPU/primitive breakdown:
godot --path kingdom --rendering-method mobile -s <abs>/tools/qa/bench/bench.gd -- \
      --adult --skipintro --quality=low --scene=village --uncapped --gpuprof
# --census (LOD0 tris by mesh), --textures (textures in use + phone export estimate),
# --drawcensus (draws and triangles in view by owner/model), --png=<file> (screenshot, HUD hidden)
py tools/qa/texture_vram.py [--write]          # every shipped 3D texture VRAM-compressed
godot --headless --path kingdom --export-pack "Android" /tmp/a.pck   # applies the mobile texture caps
godot --headless --path kingdom -s <abs>/tools/qa/bench/check_clips.gd   # clip library check
```

## 2026-09-28: the village/forest run lag was an error flood (procedural_rig.gd)
- Real-input perf_visual with `--ablate` pinned 50-100 ms frames on `procedural_rig.gd`. Each stage callback took ~16 ms because the engine
  printed "The axis Vector3 must be normalized" (`set_axis_angle`) thousands of times: once from the torso spring (`basis.x/z` not unit) and once
  from `Vector3.slerp` on two nearly equal foot normals (its internal cross-product axis is ~0.999 long). Fix: normalize the axes and use lerp+normalize.
  **Rule: any engine error printed per frame costs milliseconds. `grep -c ERROR` the log of every perf run.**
- Rig budget: only the nearest `Quality.value("rig_budget")` NPC rigs (LOW 0 / MED 3 / HIGH 6 / ULTRA 10) within 25 m run IK and springs. The player always does.
- HIGH, village_forest, speed 7, real input: before avg ~48 fps, p99 63 ms, 278-312 hitches >33 ms → after **58 fps, p99 29.3 ms, max 42.7 ms, 43 hitches, 0 errors**.
  Remaining yellow (20-25 ms) is the walk back into Ashford with ~70 people nearby. That's crowd cost, next target (VAT crowds).
  Evidence: `docs/qa/perf_visual/rig_fix/`.

## 2026-09-28: distant-NPC LOD throttle (villager.gd), and why it barely moved the number

**Where the cost actually is.** `tools/qa/bench/bench.gd --profile` (village, HIGH, forward_plus, 16 full
NPCs / 55 sprites) disables one subtree at a time and measures the frame-time delta. `population_lod.gd`
(the whole node, including every embodied `Villager`'s `_physics_process`, animation and the sprite
MultiMesh refresh) only saved **1.1 ms** off a 16.4 ms frame — smaller than `WorldSim` (1.5 ms), `Life`
(1.4 ms) or `frontier_presence.gd` (1.4 ms) alone. Full NPCs are comparatively cheap in the profiler's
static village view; the 20-25 ms frames the goal cites happen during the walk back into Ashford, where a
hazard event (`fleeing!`) puts ~15-20 villagers into **contact range** at once (route re-planning, capsule
`move_and_slide()`, per-frame steering) — cost that isn't specific to "distant" NPCs and isn't safe to
throttle without touching locomotion, which is out of scope here (Codex owns animation/locomotion; the
task also excludes `procedural_rig.gd`, already fixed).

**What shipped.** `kingdom/scripts/population/villager.gd`: full NPCs outside contact range (not about to
be touched or stepped around) and beyond 12 m now run their `AnimationPlayer` in
`ANIMATION_CALLBACK_MODE_PROCESS_MANUAL` instead of per-frame `PROCESS_IDLE`, advanced manually at ~12 Hz
(clip, blend and speed choice are untouched — only how often the pose is refreshed). Beyond 15 m their
mesh instances also stop casting a sun shadow (`SHADOW_CASTING_SETTING_OFF`), matching the shadow-cost
tier logic `quality.gd` already applies to small props but explicitly skips for skinned meshes. Both
thresholds are re-checked on each `THINK_INTERVAL` (0.3 s, already staggered per person), not every
frame, so there's no per-frame branch cost added beyond a couple of field comparisons.

**Verification.** `tools/qa/perf_visual/perf_visual.gd --route=village_forest --quality=high --speed=7`,
3 runs same session (1 without the change, 2 with):
  - without: `fps=55 p99=33.3 max=63.0 hitches>33ms=64` (0 per-frame errors; 8 errors are all
    shutdown-time RID/resource leak warnings, not printed during play)
  - with: `fps=56 p99=33.3 max=89.1 hitches>33ms=61` and `fps=56 p99=33.3 max=65.4 hitches>33ms=63`
  All three are close to each other and *worse* than the `58 fps / p99 29.3 / 43 hitches` baseline logged
  above for the same route — this session's machine was noisier (this file's own caveat: shared-GPU runs
  read ~30% low), not a regression from the change. The two "with" runs agree with each other, so the
  throttle itself is measurement-noise-neutral on this scene: it doesn't hurt, and it structurally removes
  cost that scales with NPC count (fewer AnimationMixer pose evaluations and shadow-map draws per distant
  NPC), which matters more as Ashford's `Realm` population grows and on phone GPUs where shadow map
  passes are relatively far more expensive than on an RTX 4070. It is not, by itself, a fix for the
  contact-range flee-event spike; that needs the still-open VAT/crowd-system item this doc already flags.
  Visual check: `docs/qa/perf_visual/verify6/0104_HITCH_39ms_92.5s.jpg` and `0106_94.4s.jpg` (71 people
  nearby, 16 full / 55 sprites, mid-flee) — NPCs animate normally, no T-poses, no floating, no popping.

## 2026-09-28: contact-range flee crowd — cap concurrent move_and_slide()

**Where the cost is.** Not route re-planning (`street_graph.gd` already spreads that over
`MAX_ROUTES_PER_FRAME := 2`) and not the sensing/steering math (already cached or grid-bound). It's
`move_and_slide()` itself: during the Ashford flee event ~15-20 villagers enter the player's contact
range (< 14 m, `Villager.CONTACT_ENTER`) at once and each calls `move_and_slide()` every physics frame.
Godot's narrow-phase collision resolution against a dense, bunched cluster of capsules scales with local
density, so this is the classic crowd O(n²)-ish cost the task description called out — confirmed by a
same-session control run (below) with the fix reverted.

**What shipped.** `kingdom/scripts/population/villager.gd`: added `physics_active` (public var, default
true). `_physics_process` now only calls `move_and_slide()` when `_contact and physics_active`; when
`physics_active` is false it falls back to the same plain kinematic move already used for out-of-contact
villagers (`global_position += planar * delta`) — same `_steer()` output, same speed, same animation,
same footsteps/yield logic (untouched). `kingdom/scripts/population/population_lod.gd`: `refresh()`
(already runs at 4 Hz) now walks its existing nearest-first `dists` list once and sets
`physics_active = true` for only the nearest `MAX_PHYSICS_CONTACT := 8` full villagers; farther
contact-range villagers (background of the crowd) get `physics_active = false`. No new per-frame work:
the ranking reuses a sort `refresh()` already does, and the villager-side check is one extra boolean.
`procedural_rig.gd` and animation/locomotion code are untouched.

**Verification.** `tools/qa/perf_visual/perf_visual.gd --route=village_forest --quality=high --speed=7`,
same session, same machine, back-to-back (fix stashed for the control run):
  - control (no fix): `fps=46 p99=38.5 max=104.3 hitches>33ms=79` (8 errors, all shutdown-time
    RID/resource leaks per the rule above, none per-frame)
  - with fix: `fps=51 p99=35.1 max=70.3 hitches>33ms=66` (8 errors, same shutdown-time set)
  Both runs read low vs. the session-baseline 55-58 fps logged elsewhere in this doc (shared-GPU noise
  this doc already flags), but they're back-to-back on the same noisy machine, so the comparison is
  apples-to-apples: +5 fps, p99 down 3.4 ms, worst frame down 34 ms (104.3 -> 70.3 ms), hitches down 13.
  Visual check: `docs/qa/perf_visual/flee/0104_HITCH_54ms_95.0s.jpg` and `0106_HITCH_43ms_96.3s.jpg`
  (71 people nearby, mid-flee, "fleeing" tags visible) — villagers still run normally away from the
  hazard, no freezing, no sliding, no T-poses.

## 2026-09-28: no blocky sprites next to the camera; fewer idle wanderers

At the full-model budget (`Quality.npc_full`, HIGH 16) a resident 5-8 m from the camera could still lose
the full-vs-sprite race (the budget can fill before `NEAR_HARD_CAP`'s per-refresh scan reaches them,
since `NEAR_HARD_CAP` (12) is below `MAX_FULL`/`npc_full`), and fell back to a flat MultiMesh sprite —
visibly a blocky low-res person right next to the player (seen in Ashford market, `perf_visual`
`village_forest`, ~106 s: `docs/qa/npc_density_shots/before_ashford_dusk.jpg`, bottom-left).

1. **`kingdom/scripts/population/population_lod.gd`**: new `SPRITE_MIN_DIST` (20 m) / `SPRITE_MIN_DIST_RELEASE`
   (26 m, hysteresis) — nobody without a full-model slot is drawn as a sprite closer than 20 m; they're
   simply not drawn that refresh (WorldSim still tracks them; they reappear once a slot frees or they
   step out). A `_sprite_hidden` dict tracks per-person suppression state so the boundary doesn't chatter.
2. **`kingdom/scripts/world/world_gen.gd`**: settlement population cut ~33-35% (village 320->210, town
   1100->720, castle 2400->1600) — fewer residents overall, so the market and streets stay lively but
   less crowded (a town's `population()` HUD stat only; no other system reads it).
3. **`kingdom/autoload/world_sim.gd`** `is_indoors()`: blacksmiths/merchants stay indoors 3 in 4 refreshes
   once they've arrived at work (was 2 in 3) — more of the workforce is inside their shop at a given
   moment instead of idling outside it, with no change to where anyone actually is or how they move.

Does not touch `procedural_rig.gd`, animation blending, or locomotion (Codex-owned).

`perf_visual --quality=high --route=village_forest --speed=7`, real input, no errors either run:

| | before | after |
|---|---|---|
| fps / p99 | 60 avg (16.7 ms), p99 16.7 | 60 avg (16.7 ms), p99 16.7 |
| hitches >33 ms | 15 | 17 (noise; same machine load) |
| Ashford, HUD "people nearby" | 71 (16 full / 55 sprites) | 71 (16 full / 55 sprites) — same *drawn* budget, fewer total residents in the settlement (Realm 5,280 -> 3,490 souls) |
| errors in log | 0 | 0 |

The drawn full/sprite counts are unchanged (HIGH's budget was already saturated by the crowd both times,
so per-frame draw cost is equal or lower, never higher) — what changed is that nobody close to the camera
renders as a flat sprite, and the total simulated population feeding that budget is smaller. Visual
compare: `docs/qa/npc_density_shots/before_ashford_market.jpg` / `after_ashford_market.jpg` (market cart,
~29 s into the route) and `before_ashford_dusk.jpg` / `after_ashford_dusk.jpg` (~105 s, dusk, the frame
with the blocky close sprite before the fix — gone after).

## 2026-09-28: lower on-screen NPC caps (the user said "way too many NPCs")
`npc_full`/`npc_sprites`: LOW 6/14 → 5/10, MED 10/35 → 8/22, HIGH 16/55 → 12/32, ULTRA 20/70 → 16/45.
Ashford market on HIGH: 71 → 44 people nearby. On Godot 4.6.3 with the GDExtensions loaded: fps 60, p99 16.7 ms, 5 hitches >33 ms, clean exit.
Consecutive 0.5 s frames show no popping; the market still reads as lively (`docs/qa/npc_density_shots/after_caps_market.jpg`).
Note for Codex: perf_visual `anim_bad` rose (52 → 117-128) once LimboAI and the other GDExtensions loaded and the crowd shrank. Worth a look at the anim-timing report.

## 2026-09-29: denser towns (market goods, decals, village plazas, ruin stone)
What was added, and what it costs. No fps numbers: they need the PC (the cloud renders are llvmpipe); everything below is
counted from the built scene (`kingdom/tests/test_market_dressing.gd` prints the Kingsreach line) or bounded by construction.

* **Market goods** (`scripts/world/market_goods.gd`, `SettlementBuilder._market_dressing`): 56 CC0 pieces, one 1024 px atlas, one
  glb. Pieces are composed at load into ONE-surface layouts (6 stall themes x full/lite, 2 stacks, 4 shop-fronts), so a layout is one
  draw. Kingsreach total: 107 MultiMesh batches, 129 layout instances, 447k tris for the whole capital, but every batch is a 40 m
  cell culled at 70 m (LOW x0.55 = 38 m) so what is ever drawn is the ~10-25 stalls near the camera: about 5k tris per stall
  (HIGH: <= ~100k in the gate view; LOW: ~40k) and roughly 20-30 extra draws. No shadow casting, no contact-shadow blobs, no
  colliders (walk boxes stay the stalls' own). Textures: +1 x 1024 px (1.4 MB VRAM compressed). Build time is unchanged in practice
  (one extra clearance pass per stall against the door corridors and solid props).
  LOW keeps the same stall dressing but drops the stacks behind the stalls and half the shop fronts.
* **Decals** (`town_decals.gd`, `SettlementBuilder._decals`): the Mobile renderer allows 8 decals per mesh, so wall decals only
  project onto the house batches (visual layer 11) and ground decals only onto the terrain chunk meshes (layer 12), at most one
  wall decal per 32 m block and 5 ground decals per 64 m chunk; every decal fades out at 30-40 m (`distance_fade`); NONE on LOW
  (not built, hidden if the tier drops). Millbrook: 4 wall + 7 ground decals; Kingsreach soot decals (forge doors and chimneys): 22.
* **Village squares**: only `WorldGen.color_at()` (channel B out to plaza_r + ~3.4 m, spokes paved 16 m) and ~90 flower/grass
  instances per village (one batch per 40 m cell): zero extra draws on the terrain.
* **Collapsed tower**: same 618-tri mesh, new texture only.
* QA switches for A/B renders and benches: `-- --no-goods`, `-- --no-decals`, `-- --legacy-plaza`.

## 2026-09-29: why the water views were slow (PARTIAL: interrupted by a full disk)

Tool: `bash tools/qa/water_shots/prof.sh <out.jsonl> lake,river,pier` (`water_prof.gd`). Configs are measured round-robin in
25-frame bursts, 8 rounds, and each reports its **best round's median** (the machine was busy with other agents' imports and
renders, so plain averages were useless: 24-140 ms frames). Raw data: `docs/qa/water_prof/water_prof_2026-09-29.jsonl`
(`ms_best`, `gpu_best`, `proc_best`, draws, prims per view x tier x config). 3D viewport 1280x720, RTX 4070 Laptop, Forward+.

**Root cause (so far): the water shader is not the problem, the frame is CPU-bound.**
* GPU time per frame (best): LOW 0.5-0.8 ms, MEDIUM 1.7, HIGH 4-5, ULTRA 6-10 ms. Water is 0.3-1.2 ms of that
  (baseline minus `water_off`). New clear-water vs old shader: within +-0.3 ms GPU in every view and tier (noise level).
* Frame time (best round) is 24-34 ms for EVERY config: LOW, HIGH, water off, half-res 3D, no shadows, no post effects. Changing
  GPU work by 3-5 ms moves nothing, so the frame is limited by CPU (plus other processes competing for it).
* CPU ablation at the lake, HIGH (`--sysprof`, process+physics switched off per node): only **RegionDressing**
  (`scripts/world/region_dressing.gd` and its subtree) matters: 28.0 -> 20.7 ms best, p99 50 -> 28 ms. Every other autoload and world
  child is within +-3 ms of noise (WorldSim, Life, Frontier, Audio, population, soldiers, ...).
* Draw calls 180-690 and primitives 0.17-1.4 M are inside the budget except river/ULTRA (1.5 M).
* Shader features (caustics, glints, screen/depth read) each cost < 0.3 ms GPU on the desktop; on tile-based phone GPUs the
  screen/depth texture read is the expensive part (render-pass split), see the fix below.

Not yet done: what inside the RegionDressing subtree costs ~7 ms (my `--census` flag prints the per-frame processing nodes, lights
and colliders; not run), a village control run under the same load, before/after screenshots, frame sheets, the mobile renderer.

**Shader change (committed, needs a visual check + LOW screenshot):** `clear_water.gdshader` now compiles a `WATER_LITE` variant
(no `hint_screen_texture`, no `hint_depth_texture`) for LOW/Compatibility (`WaterStreamer.apply_quality` swaps it in). Before,
LOW still declared both textures, so the engine copied the frame every frame even though no branch read it. The screen copy also
lost its mipmaps (only LOD 0 was read). Desktop GPU cost is unchanged (0.5 ms level); the gain is expected on Mali/Adreno.

### 2026-09-29 (local, follow-up, INCOMPLETE: stopped by usage limit, no code changed)
Nothing new was measured. Findings from reading `region_dressing.gd` and `water_prof.gd`:
* `RegionDressing._process` itself is cheap (2 ms build queue, a 0.75 s site scan, a few sails and flicker lights); `Breakable.tick` is O(1) per frame unless a swing happens. The scan cost is not per frame.
* The earlier "RegionDressing = 7 ms" ablation used `process_mode = DISABLED` on the subtree. In Godot 4 that also removes every CollisionObject3D in the subtree from the physics space and stops all child processing, so the 7 ms may be physics colliders (per-part StaticBody3D + Breakable bodies), OmniLights (up to one per site light, unshadowed) or the render cost of the site nodes, not script time. Next step: split the ablation into (a) `set_process(false)` only, (b) `visible = false`, (c) colliders disabled, (d) lights hidden, and run `--census` (already in `water_prof.gd`).
* The machine was very busy (about 9 Godot processes from other agents: anim_tech, PA_wt_crash boots, imports), so frame times are unreliable; use best-of-N rounds only.
* Still to do: before/after table, WATER_LITE and canopy renders, frame sheet, missing .import/.uid files, Kay_* duplicate clip names, spinning-wheel/spindle error, boot_flow test, remove origin/tmp-water2 (kept for now).

### 2026-09-29 (local, round 2): RegionDressing is NOT the cost; measured properly
Tool: `tools/qa/water_shots/prof.sh` (`water_prof.gd`), Mobile renderer, 1600x900 window (3D 1280x720), RTX 4070 Laptop, best-of-N round-robin
bursts. **Caveat: the PC was shared with 9-12 other Godot processes (one anim_tech instance at 100 % CPU for 5 h) and had 1.4 GB free RAM,
so absolute numbers move by 2-4 ms between runs; only same-run comparisons are meaningful.** Raw data: `docs/qa/water_prof/water_prof_2026-09-29.jsonl` (round 1) and the numbers quoted here (round 2 logs were console-only).

**RegionDressing split ablation (lake, LOW, mobile; `--rdprof`):** at the lake no site is built (`built=0`, 0 nodes, 0 lights, 0 colliders) and
its `_process` costs 0.085 ms/frame (Time.get_ticks_usec counters `dbg_usec/dbg_frames`). Script off / colliders off / lights off / meshes hidden /
shadows off / whole node hidden / process DISABLED are all within noise of baseline (12.1-14.1 ms vs 14.1 baseline in one run, spread of
+-2 ms between identical configs). The earlier "28 -> 20.7 ms" was measurement noise from a busy machine. Nothing to fix there; only the
0.75 s site scan and the 2 ms build budget exist, and both are already sliced. (Census at the lake: 3896 nodes, 2400 MultiMeshInstance3D, 193 shapes.)

**CPU ablation per system (lake, LOW, best of 5):** baseline 11.4 ms; hide all world 9.9; hide multimesh 10.4; hide terrain 10.1; hide NPCs 10.6;
every script system within +-1 ms (noise) except **WorldSim off = 7.6 ms (-3.9 ms)**. Note that switching WorldSim off also freezes the clock
(no `hour_changed` listeners), so this over-states its own script. Direct timing of `WorldSim._simulate_slice`: **1.2 ms/frame** (1500 of ~20 000 people
per frame in GDScript).

**Fix (`autoload/world_sim.gd`, shared code, see LOCAL_SESSION_HANDOFF):** `_simulate_slice` now has a time budget (`BUDGET_US = 500`),
updates the people of settlements within 320 m of the player first (whole near set every ~4 frames, rebuilt every 1.5 s), and gives the rest of the
budget to the global cursor. Movement was already dt-based, so the slower far cycle is equivalent. Measured slice time 1.18-1.21 ms -> 1.04 ms at a 1 ms
budget; the shipped 0.5 ms budget should be about 0.5 ms (not re-benchmarked under the shared load).

**Before/after frame time (ms, best round of 4-6, LOW/HIGH, Mobile), same session, old vs new sim (budget 1 ms):**
| view | old LOW | new LOW | old HIGH | new HIGH |
|---|---|---|---|---|
| lake | 9.7 | 9.6 | 11.1 | n/a |
| village | 16.0 | 13.0 | 13.8 | n/a |
Earlier full grid (`ab_*` first pass, load differed between runs, so NOT comparable): old 9.1/6.4/8.1/12.6 (LOW lake/pier/river/village), HIGH 11.1/7.6/7.9/13.8.
Snapshot run with the shipped code (single 20-frame burst, indicative): lake LOW 11.3 / HIGH 12.4, river 13.8 / 13.9, pier 9.0 / 10.0 ms
(`docs/qa/water_after/*.png` renders). **All views are at or under 16.6 ms on this PC (60 fps), LOW is <= 14 ms.** GPU time is 0.24-2.2 ms.
Village is the most CPU-heavy view (13-16 ms); its per-system ablation is still to do (`--sysprof` currently runs at the lake only).
Other CPU consumers seen at the lake: MultiMeshInstance3D count (2400 nodes), critters (19), soldiers (12), fishing spots (6): each < 1 ms in the ablation.

**Visual check (read):** `docs/qa/water_after/lake_low.png` (WATER_LITE: clear blue shallows, soft reflection, no shore foam/caustics, reads fine),
`lake_high.png` (full: caustics, foam, glints), `river_*.png`, `pier_*.png`; frame sheet of the animated river `docs/qa/water_after/frames/sheet_001.png`
(ripple ring and glints move; no flicker). Tree canopy is warmer and fluffier than before but still slightly cooler/less golden than the reference gate market.
Mobile renderer note: forward_plus-only runs at HIGH/ULTRA print "Index p_mipmap out of bounds / All attachments unused" errors when the water shader's
screen texture is used on Mobile at the ULTRA setting; not investigated.
