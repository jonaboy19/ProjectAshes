# Valencious terrain pipeline (W1-W5)

One page for whoever touches the world ground next: how the 12 288 m Valencious terrain is made, what reads what, which flags switch it on, and how to re-run
every step. Results and decisions per phase: `W1_W2_RESULTS.md`, `W3_RESULTS.md`, `W4_LANDMARKS.md`, `QA_W5.md` (verdict per capture + perf).

**Flags are still OFF by default** (the owner approves the flip): `--terrain_backend=legacy|terrain3d` (default legacy) and `--world_macro=noise|valencious`
(default noise). With both at their defaults every test and capture is byte-identical to before the world work. The look in the QA captures is
`--profile=pc --quality=high --terrain_backend=terrain3d --world_macro=valencious`.

## The chain

```
docs/world/valencious_places.json  ─┐   (bible: 343 places, rivers, lake; dumps of the live WorldGen)
data/world/valencious_regions.json ─┤   (12 sub-regions: lobes, height band, roughness, ridges, biome weights)
data/world/macro/raw_core.json     ─┘   (WorldGen noise around Ashford/Kingsreach, kept within +-8 m)
        │  tools/world/gen_valencious.py            (numpy/scipy/Pillow, seed 1066, deterministic, `--verify`)
        ▼
data/world/macro/height_16.png  biome_ids.png  splat_weights.png  preview.png  meta.json
        │  tools/world/make_biome_soft.py           (biome_ids -> two 256 px soft-weight PNGs: biome_soft_a/b.png)
        ▼
scripts/world/world_macro.gd   WorldMacro   ── loaded once in WorldGen.setup (0.33 s, 38.8 MB), sample(x,z) bilinear, thread-safe
        │  one hook in WorldGen._raw_height ("# Valencious macro hook"); settlements/camps/sites placed with the macro SUSPENDED,
        │  then WorldGen._rebase_to_macro re-seats base heights, lake, rivers, Westfen pools => no id/position ever moves
        ▼
WorldGen.height(x,z)   <- THE single height truth (navigation, building, founding, saves, collision, rivers, roads, stamps)
        │
        ├── scripts/world/terrain3d_bridge.gd  Terrain3DBridge   bakes WorldGen.height + colour weights + WorldBiomes soft field into Terrain3D
        │       regions (384 m = 256 px x 1.5 m, 32 x 32 locations = the whole world), 3x3 regions (MEDIUM-) or 5x5 (HIGH+) around the camera,
        │       on WorkerThreadPool, one region added per frame; Terrain3D collision is DISABLED (TerrainStreamer's trimesh stays the ground)
        ├── scripts/world/world_biomes.gd + shaders/terrain3d_ground.gdshader + terrain3d_look.gd   10+1 ground slots, soft biome mixes, lush grade,
        │       wetness / season / snow / Scar Tide from the legacy terrain shader (shader_override)
        ├── scripts/world/scatter_*.gd (ProtonScatter) + grass_field.gd   per-biome trees, undergrowth, rocks, grass
        ├── scripts/region1/region1_horizon.gd   far field outside the streamed ring: one 72 m-grid mesh of the whole world + canopy blobs
        └── data/region1/terrain_stamps.json  (+ terrain/*.res, tools_qa/region1/bake_stamps.gd)  W4 height deltas: Rift trench, Ashen Scar craters,
                mine benches, Grimfen cut; one variant per macro mode
```

## Flags and switches

| What | How | Notes |
|---|---|---|
| Ground renderer | `--terrain_backend=terrain3d`, env `ASHES_TERRAIN_BACKEND`, `user://settings.cfg [world] terrain_backend` | falls back to legacy when the Terrain3D GDExtension is not loaded |
| Macro terrain | `--world_macro=valencious`, env `ASHES_WORLD_MACRO`, `[world] macro` | `WorldMacro.override` in tests |
| Terrain3D shader override | `--t3d_look=off` drops it (plain Terrain3D shader) | `lush` grade is only on with the macro |
| Capture weather | look_capture pins `clear` (`--weather=auto` leaves the schedule) | the daily schedule can roll fog/rain into a capture |

## Re-running

```
# 1. macro maps (about 35 s). Then the soft biome field.
py -E -B kingdom/tools/world/gen_valencious.py            [--verify]      # byte-identical check
py -E -B kingdom/tools/world/make_biome_soft.py
# 2. W4 stamps (only when WorldGen/macro heights near a stamp change)
Godot --headless --path kingdom -s res://tools_qa/region1/bake_stamps.gd -- --mode=noise|valencious [--only=id]
py -I kingdom/tools/region1/merge_stamp_index.py <bake logs>
# 3. ground textures (only when a slot's source or grade changes) - new .import files must copy the legacy VRAM-compressed ones
Godot --headless --path kingdom -s res://tools_qa/terrain3d/pack_ground_textures.gd
# 4. captures (GPU, never --headless). Views are JSON; tools/world/gen_w5_views.py writes the W5 lists.
bash kingdom/tools_qa/world/run_w5_captures.sh tools_qa/world/w5_views_grid.json   <abs out dir> [batch]   # 36 aerials + reference spots + Rift orbit
bash kingdom/tools_qa/world/run_w5_captures.sh tools_qa/world/w5_views_regions.json <abs out dir> [batch]   # 12 sub-regions: ground dawn/noon/dusk + aerial 120/400 m
# one view by hand:
Godot --path kingdom --resolution 1920x1080 -s res://tools_qa/region1/look_capture.gd -- --adult --views=res://tools_qa/world/w5_views_regions.json \
      --out=<abs dir> --only=w06_rift_marches_ground_noon --profile=pc --quality=high --terrain_backend=terrain3d --world_macro=valencious
# 5. tests: gdUnit  test_world_macro, test_world_biomes, test_world_water_roads, test_terrain3d_bridge, test_region1_w4, test_world_12km, test_scripts_parse
```
After a `git merge` that adds scripts or textures run `Godot --headless --path kingdom --import` once (a stale `.godot` class cache makes `WorldBiomes` etc. "not declared", and
stale `.ctex` entries flood the log). The import rewrites `project.godot` (drops the renderer lines): `git checkout kingdom/project.godot` afterwards.

## View JSON keys (tools_qa/region1/look_capture.gd)
`name`, `at [x,z]`, `look [x,z]`, `up` (m above ground at `at`), `look_up`, `hour`, `fov`, `warm` (frames), plus W5 additions: `gate: <settlement index>` + `in` (m inside the first gate, looking out:
the owner's Kingsreach gate-market reference), `site: <r1id prefix>` + `site_at` / `site_look` (offsets from a Region 1 site), `env {Environment property: value}`, `t3d {Terrain3D property: value}`,
`mat {Terrain3DMaterial property: value}` (debug A/B toggles, restored before the next view), `probe [[dx,dz],..]` (prints WorldGen vs Terrain3D height + control word), `scan` (prints big flat
VisualInstance3Ds near the camera), `nohorizon`.

## Things that bit us (keep)
- **Terrain3D 1.0.2 must be told its camera.** Its `_grab_camera()` runs at `_ready`, finds no current camera inside the game's SubViewport ("Cannot find the active camera. Set it manually...") and
  **stops its `_physics_process`**: the clip-map (LOD0 rings, geomorph distance, tile layout) then never follows the real camera. Symptoms: ground that vanishes next to the camera away from the
  origin (Rift Marches "tilted plane over fog"), coarse flat far patches. `Terrain3DBridge._track_camera()` now sets the viewport's current camera every frame (cheap).
- Texture assets must be set two frames after the first region on a GPU (signal 11 otherwise); FSR2 + Terrain3D crashes on 4.6.3: the PC profile uses FSR1 + TAA with the backend on.
- Aerial fog: depth fog thins with camera height above ground (`Weather._alt_fog`: 1 at head height, 0.12 floor, half at ~80 m) and its colour is light blue-violet by day (`StyleG.DAY_KEYS`);
  a flat 0.0021 density with a beige colour turned every 400 m aerial into a dust-coloured wash.
- Region radius is per tier (`TerrainStreamer`: 1 on MEDIUM-, 2 on HIGH+). Beyond it the far horizon mesh draws (72 m grid, vertex colours): it cannot show features smaller than ~150 m.
- Terrain3D control words: base `<<27`, overlay `<<22`, blend `<<14`; the colour map is 8-bit, so tints can only darken (<= 1).
- `player.gd` and `hero_face_driver.gd` are CRLF; `world_gen.gd` settlement placement, `NAMES` and seed 1066 are frozen (saves and Discovery key on them).
