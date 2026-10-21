# VFX tooling for Rising Ashes

Everything here is free and allowed for commercial use. Tools are installed OUTSIDE the repo in `C:\Users\Jonna\Tools\<tool>` (no accounts, official GitHub releases only). Results and upgrade suggestions: `docs/art/vfx_tools/README.md`.

## Installed (2026-09-29)

| Tool | Version | Licence | Where | Verdict |
|---|---|---|---|---|
| Material Maker | 1.7 (Godot 4.7 build) | MIT | `C:\Users\Jonna\Tools\material-maker\material_maker_1_7_windows\material_maker.exe` (from https://github.com/RodZill4/material-maker/releases/tag/1.7) | GUI works. Headless `--export-material` runs but wrote nothing in 1.7 (`user://export_targets` is not created on first run), so it is a hand-authoring tool, not a batch baker. Use it for hand-tuned tiling noise, masks and gradients; not part of the scripted pipeline. |
| Effekseer editor | 1.80.7 | MIT (+ bundled third-party notices in `LICENSE_TOOL`) | `C:\Users\Jonna\Tools\effekseer\editor\Effekseer1.80.7Win\Effekseer.exe` (https://github.com/effekseer/Effekseer/releases/tag/1807) | Authoring GUI for `.efkefc` effects. Samples inside are CC0. |
| Effekseer for Godot 4 | 1.80.5.1 | MIT | `C:\Users\Jonna\Tools\effekseer\godot-plugin\` (full zip contents), trimmed copy in `kingdom/addons/effekseer/` (https://github.com/effekseer/EffekseerForGodot4/releases/tag/1.80.5.1) | Works on Godot 4.6.3 desktop (tested, Mobile renderer). See the verdict in `docs/art/vfx_tools/README.md`. |
| Blender | 5.2 (already installed) | GPL (renders are not encumbered) | `C:\Program Files\Blender Foundation\Blender 5.2` | Mantaflow smoke/fire/liquid + Cycles. Bundled numpy is our only Python (no system Python on this PC). |

Not installed, evaluated only (see docs): Laigter (GPL-3, external tool, normal maps for sprites, no need for it now), TextureLab (GPL-3, Electron, no animation export, stalled), Godot VFX Library (haowg, MIT repo, provenance of assets unclear), Kenney Particle Pack (already in `kingdom/assets/incoming/vfx_free/`, CC0), ambientCG / Poly Haven (CC0, PBR surface scans: not useful for VFX sprites), ShaderToy (default licence CC BY-NC-SA: **do not copy code**, only learn techniques).

Reinstall from scratch: download the three zips from the URLs above, unzip into the folders shown, and copy `addons/effekseer/` (minus `bin/ios`, `bin/macos`, `bin/web`, `bin/linux`, x86 binaries) into `kingdom/addons/`. The iOS static libs (124 MB) must be copied back in only when building the iOS export.

## The flipbook pipeline (scripts in this folder)

Run everything with Blender's bundled Python (no GUI):

```
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$B" -b --python tools/vfx/bake_procedural.py -- lightning_sheet <out_dir>       # numpy, ~40 s
"$B" -b --python tools/vfx/bake_procedural.py -- magic_swirl <out_dir>           # numpy, ~40 s
"$B" -b --python tools/vfx/bake_puffs.py      -- smoke_puff <out_dir>            # numpy, cel-shaded lumps
"$B" -b --python tools/vfx/bake_puffs.py      -- dust_burst <out_dir>            # numpy, dust ring + rocks
"$B" -b --python tools/vfx/bake_gas_sims.py   -- fire_burst <out_dir> <cache_dir>   # Mantaflow + Cycles, first run ~10 min
"$B" -b --python tools/vfx/bake_water_splash.py -- <out_dir> <cache_dir>           # Mantaflow FLIP + Cycles
```

| File | What |
|---|---|
| `flipbook_common.py` | premultiplied float frames -> straight-alpha sRGB, fringe-free colour, optional soft cel banding, PNG writer, atlas tiler (row-major, top-left first) |
| `bake_gas_sims.py` | Mantaflow gas domain + emitter, Cycles volume render with warm sun / cool blue-violet fill, gradient-map for fire. Saves `sim.blend` next to the cache: a baked cache is only read when that .blend is reopened. |
| `bake_water_splash.py` | Mantaflow FLIP liquid: falling blob into a pool, toon water shader with pool surface masked out |
| `bake_procedural.py` | lightning strike (16 frames) and looping vortex (16 frames) in numpy |
| `bake_puffs.py` | cel-shaded smoke and dust (64 frames each) in numpy |

Findings that cost time (so nobody repeats them):
- Blender 5.2 headless: **Cycles renders nothing when the gas domain has `use_noise` on** (the noise cache is not read). Bake without noise and use a higher base resolution.
- `bpy.ops.fluid.bake_data` only sees the domain if it is the *active* object; and a baked cache is only picked up in a new session by opening the saved `.blend`, not by rebuilding the domain.
- `Render Result` pixels are empty in background mode: write EXR with `write_still=True` and load that.
- Volume renders are grainy at 128 px and photoreal; for smoke and dust the painted, depth-sorted sphere-lump look (bake_puffs.py) matches the art style better and bakes in seconds, so the volume route is kept for fire and liquid only.
- Bake times (RTX 4070 laptop, other jobs running): gas sim res 128 x 48 frames about 8 min plus about 5 min render; FLIP splash bake about 20 min, render 2 min.

## In-game use

`kingdom/scripts/vfx/flipbook_fx.gd` (`FlipbookFX.play(&"fire_burst", pos)`), shader `kingdom/shaders/vfx_flipbook/flipbook.gdshader`, sheets in `kingdom/assets/vfx/flipbooks/` (licences in its `LICENSE.md`). Gallery: `kingdom/tools_qa/vfx_flipbooks/flipbook_gallery.tscn`.
