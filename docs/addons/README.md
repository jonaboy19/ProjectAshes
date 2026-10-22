# Free addons and tools for "AAA feel" on mobile (session: local PC, 2026-09-29)

Scope: free, commercially usable (MIT) Godot 4.x addons that raise polish and are **not** already covered by our own code or by
the other sessions (menus/boot flow/Google Play Games, water shader, elemental VFX, animation/IK/mocap were left alone).
Every addon below was installed into `kingdom/addons/<name>/` with its licence file, run in Godot 4.6.3 (Mobile renderer, RTX 4070
Laptop) through a demo in `kingdom/tools_qa/addons_demo/`, measured, and screenshotted. Nothing is wired into gameplay code:
each row has an integration plan for whoever owns that system.

Run any demo: `Godot --path kingdom --rendering-method mobile res://tools_qa/addons_demo/addons_demo.tscn -- --demo=<pcam|debugmenu|footsteps|grass|shatter> [--capture=<dir>]`
(impostors: `res://tools_qa/addons_demo/impostor_forest.tscn`). Without `--capture` the demo stays open.

## Summary

| Addon | Licence | Version | Status | Perf (this PC, mobile renderer) | Owner session for integration |
|---|---|---|---|---|---|
| **Phantom Camera** (ramokz) | MIT | 0.11.0.3 | installed, **enabled** (autoload `PhantomCameraManager`, idle unless a PhantomCamera3D exists) | no measurable cost (3.4 vs 3.6 ms frame, noise); demo blends follow cam to cinematic cam and shakes | cloud (camera/cutscenes) |
| **Octahedral impostor baker + shader** (own code, technique credit below) | own / MIT reference | 1.0 | installed as `tools/impostors/` + `assets/generated/impostors/`, 6 impostors baked | see impostor section (numbers below) | local (perf), cloud (placement) |
| **Debug Menu** (Calinou) | MIT | 2025-11 (`master`) | installed, **not enabled** (instance `debug_menu.tscn` in debug builds only) | hidden = free; detailed = +78 draw calls of UI | local (QA), any |
| **Material Footsteps** (COOKIE-POLICE) | MIT | 1.0.0 | installed, not enabled (no autoload needed; `MaterialFootstepPlayer3D` class works at runtime) | 1 raycast per step, no measurable cost | audio/cloud |
| **SimpleGrassTextured** (IcterusGames) | MIT | 2.1.0 | installed, not enabled (needs `SimpleGrass` singleton + 10 global shader params, added at runtime by the demo) | 30k blades = 2.6 GPU ms with shadows, 1.2 ms without, 10k blades = 0.8 ms | cloud (world dressing) |
| **VoronoiShatter** (robertvaradan) | MIT | 0.3 | installed, not enabled (editor tool; also callable at runtime) | 22 samples: 0.9 s to fracture a box (do offline); 30 Jolt shards cost ~0 ms | cloud (`breakable.gd`) |
| **Sentry Godot SDK** (getsentry) | MIT | 2.2.0 | **not committed** (43 MB pruned); `tools/install_sentry.sh` installs it, boot-tested, no-op without a DSN | boots clean, no DSN = no-ops | local (release) |

(Full details, integration plans and rejected candidates below.)

## Screenshots (all read and verified)
| Demo | Files (in `docs/addons/`) |
|---|---|
| Phantom Camera: follow cam, mid blend, cinematic cam, shake | `pcam_1_follow.png`, `pcam_2_mid_blend.png`, `pcam_3_cinematic.png`, `pcam_4_shake.png`, `pcam_perf.txt` |
| Debug Menu (detailed) | `debugmenu_detailed.png`, `debugmenu_perf.txt` |
| Material Footsteps: grass > stone > wood detected | `footsteps_1..3.png`, `footsteps_perf.txt` |
| SimpleGrassTextured | `grass_1.png`, `grass_2_high.png`, `grass_perf.txt` |
| VoronoiShatter | `shatter_1_intact_pieces.png`, `shatter_2_exploding.png`, `shatter_3_settled.png`, `shatter_perf.txt` |
| Octahedral impostors | `impostors_forest_{mesh,impostor,hybrid}.png`, `crossfade_zoom_fade_vs_hard.png`, `crossfade_{fade,hard}/`, `impostors_forest_hybrid_lowcam.png`, `impostors_compare_row.png`, `impostors_perf.txt`; atlases in `kingdom/assets/generated/impostors/*_octa.png` |

## Impostors (biggest win for mobile fps)
The two GitHub baker addons (wojtekpil, MIT, Godot 3 era; belzecue's "initial porting attempt" for 4.0) still contain Godot 3 code
(`idle_frame`, `Texture.flags`, `.completed`) and don't run on 4.6, so I wrote our own baker (`kingdom/tools/impostors/impostor_baker.gd`)
and shader (`kingdom/assets/generated/impostors/impostor_octa.gdshader`): hemi-octahedral views into one albedo + alpha atlas, 4-frame
bilinear blend, lit at runtime with an up-biased normal so sun colour and day/night still apply. It works per instance, so MultiMesh is fine.
Baked 6 assets, each down to 2 tris: `oak1` (6265 tris), `oak4` (4066), `twisted` (9564), `village_house` (8684), `chapel` (11371), `bell_tower` (10459).

### Edge quality pass (2026-09-29)
Before: 8x8 views of 128 px (1024 px atlas, hard 1-bit alpha, blocky when magnified, stored uncompressed, 4 MB each).
After:
- **Texel density**: trees 7x7 views of 176 px (1232 px atlas), buildings 6x6 views of 208 px (1248 px atlas). Imported as VRAM-compressed with mipmaps: **2.03 MB per tree species and 2.08 MB per building species in ETC2** (measured `.etc2.ctex` sizes, mips included; ASTC 4x4 has the same 8 bpp, ASTC 8x8 would be 4x smaller). Tile 176-208 px is about 1:1 with the on-screen size of a tree impostor at 45 m on a 1080p screen (about 190 px), the old 128 px tile was magnified 1.5x.
- **Anti-aliased alpha**: each view is rendered at 3x and resolved on the GPU (`tools/impostors/impostor_resolve.gdshader`) with a coverage-weighted box filter.
- **Dilated colour**: transparent texels take the colour of the nearest opaque texel of the same tile (12 px ring search, never crosses a tile border), so bilinear, mip and ETC2 blocks never bleed dark fringes.
- **Edge in the shader**: `alpha_to_coverage_and_one` (uses the project's 4x MSAA; without MSAA it degrades to a hard cut at 0.5), alpha contrast that grows with the mip level (thin trunks and canopy gaps lose alpha in mips otherwise), texture LOD bias -1, optional dithered cut-off (`edge_dither`, interleaved gradient noise) for renderers without MSAA.
- Before/after: `docs/addons/impostors_compare_row.png` (new bake, read it: silhouettes are smooth, trunks solid); the old image is in git history (`git show 9d2c8770:docs/addons/impostors_compare_row.png`).

### Crossfade mesh <-> impostor (about 5 m, dithered)
- `impostor_octa.gdshader`: `fade_in_end` / `fade_in_len` (per instance, camera distance to the bounding-sphere centre, interleaved-gradient-noise dither).
- `tools_qa/addons_demo/mesh_fade.gdshader`: the full-mesh side, complementary noise (mesh keeps a pixel while noise < keep, the impostor keeps the rest), so no hole and no double draw. Demo: `impostor_forest.gd --fly=fade|hard` (camera flies through the 45 m switch, crossfade centred on 45 m, 42.5 to 47.5 m). `hard` is the old hard switch for comparison.
- **Godot's own `visibility_range` fade (FADE_SELF) did not fade MultiMesh cells in the Mobile renderer**: even with a 20 m margin the switch was instant (verified frame by frame), so the game must use this shader pair (or per-object visibility ranges on single MeshInstances). Any GLB material has to be wrapped into `mesh_fade.gdshader` (albedo texture, colour, vertex colour, roughness) for the fade to apply; other material features (normal maps, emission) are not carried.
- Frame evidence: `docs/addons/crossfade_zoom_fade_vs_hard.png` (top row fade, bottom row hard, consecutive frames of one tree: the hard switch jumps from light impostor to dark mesh in one frame, the fade gets there gradually), `docs/addons/crossfade_{fade,hard}/sheet_*.png` (30 fps window around the switch). The generic `motion.png` difference strip is not sensitive enough for a small far object, so it is not used as proof. The wrapped mesh renders lighter than the game's lit mesh (no shadow terms in the wrapper), so the fade row looks pop-free partly because of that; wrap the real material in the game.

### Numbers
Dense scene: 3000 trees + 80 houses (3071 instances in 32 m cell MultiMeshes so cells are frustum-culled), mobile renderer, 1280x720, RTX 4070 Laptop, measured 2026-09-29 with the machine otherwise idle (`impostors_perf.txt`):

| Mode | Frame | FPS | GPU ms | Render-CPU ms | Draw calls | Triangles |
|---|---:|---:|---:|---:|---:|---:|
| all full meshes | 8.58 ms | 117 | 7.33 | 1.99 | 441 | 2,006,738 |
| all impostors | 4.26 ms | 235 | 0.64 | 1.15 | 242 | 5,538 |
| hybrid (full < 45 m, impostor beyond) | 4.74 ms | 211 | 1.90 | 1.44 | 280 | 423,688 |

Hybrid gives 1.8x the fps of full meshes and 3.9x less GPU time; triangles fall from 2.0M to 0.42M (mobile budget: 1.5M). The earlier table (75 / 214 / 142 fps) was taken while other sessions loaded the GPU; the new impostor GPU cost (0.64 ms, was 0.47 ms) includes alpha-to-coverage and the alpha sharpening. Frame time also contains the game's autoloads (about 3.5 ms CPU), so the GPU column is the honest comparison. Limits: the bake is unlit albedo (no baked AO, emissive windows are baked as colour), impostors don't cast shadows, frame blending "swims" slightly up close and blends the thin trunk of `twisted` into a faint ghost at some angles, so keep the switch distance at 40 m or more for trees and 60 m or more for buildings; near-top-down frames use a fallback up vector. Not tested on a phone: alpha-to-coverage needs MSAA (LOW tier without MSAA gets the hard 0.5 cut, still supersampled).
Re-bake: `Godot --path kingdom --rendering-method mobile res://tools/impostors/impostor_baker.tscn -- --jobs=oak1:res://.../CommonTree_1.gltf,chapel:res://assets/generated/chapel.glb@6@208` (needs a GPU, not `--headless`; then run `--import`).
Integration plan: (1) tree/building scatter keeps the LOD0 GLB within about 45 m and the `*_octa.tscn` quad beyond, with the crossfade shader pair; (2) use the same 32 m cell MultiMesh scheme, with hard `visibility_range` values only for culling (mesh end = 45 + 2.5 + 24 m, impostor begin = 45 - 2.5 - 24 m from the cell centre); (3) compare against the existing 4-tri `_lod2` cross cards of generated trees and use whichever looks better; (4) bake more kinds with the baker; (5) a `Quality` tier switch distance (LOW: 30 m).

## Integration plans and notes per addon
- **Phantom Camera**: `PhantomCameraHost` as child of the game's `Camera3D`, one `PhantomCamera3D` (THIRD_PERSON or SIMPLE follow) for the
  player, and extra pcams (higher priority) for shop/dialogue/cutscene framing with `PhantomCameraTween` blends; replaces manual lerps in
  `cutscene_player.gd` / `birth_cutscene.gd`. Shake: `PhantomCameraNoiseEmitter3D.emit()` can replace `camera_shake.gd` (keep the old one
  until the chase camera moves over). Set inactive pcams' `inactive_update_mode` to NEVER on mobile. The only enabled piece is the idle
  `PhantomCameraManager` autoload. Needs the camera owner (cloud session); don't swap the camera in one step.
- **Debug Menu**: instance `res://addons/debug_menu/debug_menu.tscn` under `OS.is_debug_build()`; F3 cycles hidden / compact / detailed
  (hidden costs nothing). Not enabled as a plugin, so it never adds an autoload or ships in release. FPS/CPU/GPU rows work; its graph
  panels stayed grey in my run; detailed mode adds 78 UI draw calls.
- **Material Footsteps**: add `MaterialFootstepPlayer3D` (a RayCast3D) under the player `CharacterBody3D`, a sound map of `MaterialFootstep`
  resources per surface, and put meta `surface_type` on collision bodies (or use its Terrain3D detector: Terrain3D is installed). Feed the
  existing `audio_director.gd` clips through the map or call `play_footstep()`. The demo proved grass > stone > wood switching.
- **SimpleGrassTextured**: add the `SimpleGrass` singleton scene under /root only on levels with grass (its 6 SubViewports render only when
  `interactive` is on) and register the 10 `sgt_*` global shader params (see `_demo_grass`), or enable the plugin once in the editor.
  Runtime nodes need `_update_multimesh()` called after `add_grass_batch` (its `_process` is off outside the editor). Cost: 30k blades =
  360k tris, 2.6 GPU ms (1.2 ms with shadows off), 10k blades = 0.84 ms, so near-field only (<= 25 m), shadows off, about 8k blades, lower-poly
  blade mesh. Default albedo is neon lime: tint to the storybook palette. Don't ship its bundled `grassbushcc008.png` (unknown source).
  The game already has `shaders/grass.gdshader`; adopt this only for its paint-in-editor workflow and interactive bending.
- **VoronoiShatter**: pre-fracture hero props (barrels, crates, statues) in the editor (20-30 samples) and save the pieces as scenes; swap in
  at break time (30 Jolt shards: no measurable frame cost). Generation takes about 0.9 s per box, so never at runtime. `breakable.gd`
  slices at runtime today; this gives cleaner fractures. Needs manifold meshes.
- **Sentry**: run `tools/install_sentry.sh` (43 MB, git-ignored), set the DSN via a release-only `override.cfg`. Verified on 4.6.3: the full
  autoplay boot and 10 minutes of play ran with no new errors; without a DSN it prints "Automatic initialization is disabled". Caveats: it
  forces `debug/settings/gdscript/always_track_call_stacks=true` and writes a `[sentry]` section into `project.godot` when the editor
  opens (measure the CPU cost, consider beta builds only), and crash reporting needs a privacy line in the store listing.
- **Jolt**: already `3d/physics_engine="Jolt Physics"`; nothing to add (the standalone godot-jolt addon is obsolete on 4.4+).
- **Occlusion culling**: not tested here. Enable `rendering/occlusion_culling/use_occlusion_culling`, add a few `OccluderInstance3D` boxes
  in big buildings and castle walls, and measure in the `city` bench scene.

## Rejected or skipped
| Candidate | Reason |
|---|---|
| Resonate (hugemenace) | Duplicates `audio_director.gd`, `adaptive_music.gd`, `music_bank.gd` (about 1,900 lines with mood-driven music); its autoloads would clash with `Audio`. |
| Waterways | Another session owns water; revisit for rivers after their shader lands. |
| Spatial Gardener / foliage painters | ProtonScatter and Terrain3D's instancer are installed already. |
| godot-statecharts, Beehave | LimboAI covers behaviour trees and HSM. |
| Dialogic 2 | `dialogue_manager` is installed and lighter. |
| Scene/transition managers | Boot flow and menus belong to another session. |
| wojtekpil / belzecue octahedral addons | Godot 3 code, don't run on 4.6; replaced by our own baker. |
| Mobile ads, analytics SDKs | Skipped by request. |
| Volumetric fog | Not supported by the Mobile renderer; use height fog / SimplestGodRay3D from the VFX session. |
| godot-jolt addon | Jolt is built in and already selected. |
