# External tools (installed outside the repo, 2026-09-30)

Everything lives in `C:\Users\Jonna\Tools\` (not in git). Small scripts that drive the tools live in `tools/external/`.
Proof images (each one was opened and checked): `C:\Users\Jonna\Tools\_proof\<tool>\`.
Every licence below was read at the source. What we ship are OUTPUTS (rigs, clips, heightmaps, maps); the kept tools are GPL/MIT applications whose output is not encumbered.
Already evaluated elsewhere, not repeated here: `docs/art/vfx_tools/README.md` (Material Maker, Effekseer, flipbooks) and `docs/anim/advanced/README.md` (KayKit, UAL, video mocap, rejected mocap sets).

## Kept and proven

| Tool | Version | Licence | For | Where |
|---|---|---|---|---|
| Blender Rigify + horse/wolf/cat/bird metarigs | built into Blender 5.2 (Rigify 0.6.10) | GPL-3 tool, output free | quadruped and horse rigging | Blender |
| Wiggle 2 (shteeve3d) | 2.2.3 plus a 1-line 5.2 patch | GPL-3.0 | spring bones / secondary motion, bake to keys | `Tools\blender-addons\addons\wiggle_2.py` |
| Bone Dynamics (Experience Elysian) | 1.3.0 | GPL-3.0-or-later | spring + wind + collision on bone chains, bake | `Tools\blender-addons\addons\bone_dynamics` |
| Expy Kit (pKrime) | 0.6.1 | GPL-3 (licence block in every source file; the repo has no LICENSE file) | "Rigify Game Friendly": one-root deform skeleton for export | `Tools\blender-addons\addons\expy_kit` |
| A.N.T.Landscape (extensions.blender.org) | 0.2.0 | GPL-2.0-or-later | mesh terrain from noise, includes an Eroder | `Tools\blender-extensions\user_default\antlandscape` |
| terrain-erosion-3-ways (dandrino) | master | MIT | hydraulic erosion plus river flow map on heightmaps | `Tools\terrain-erosion-3-ways` (with `venv`) |
| Azgaar Fantasy Map Generator | 1.153.1 | MIT; the author states maps, images and screenshots are free for any use including commercial | world and region maps, rivers and cells as GeoJSON | `Tools\azgaar` (built to `dist`) |
| Terrain3D (already in `kingdom/addons`) | repo copy | MIT | runtime terrain, imports r16 heightmaps | `kingdom/addons/terrain_3d` |

Proofs (all headless, reproducible with the commands below):
- **Rigify horse**: 70-bone horse metarig generates a 454-bone rig; rearing pose made by moving IK controls. `_proof\rigify\horse_both.png`.
- **Wiggle 2**: tail chain driven by a torso bounce; the tip moves 2.3 m away from the no-physics path; `wiggle.bake` writes 750 F-curves. `_proof\wiggle\sheet.png`.
- **Bone Dynamics**: same test with wind; tip moves 1.7 m; bake writes 20 tail F-curves. `_proof\bonedyn\sheet.png`.
- **Expy Kit**: Rigify human (706 bones) becomes a 162-bone single-root deform skeleton, exported to GLB and re-imported (root `DEF-spine`). `_proof\expykit\human_gamefriendly.png`. Game Friendly is human-only (needs `DEF-hand.L`); it fails on the horse rig.
- **A.N.T.Landscape + Eroder**: 129x129 valley; the eroder changes heights by up to 8.4 m; exports GLB and r16. `_proof\ant\ant_both.png`. The eroder leaves vertical streaks along the border; use a larger grid and crop, or use dandrino for heightmaps.
- **dandrino erosion**: 512x512 fBm becomes a branching valley with a river map (about 3 min on the laptop CPU). `_proof\erosion\valley_compare.png`.
- **Terrain3D**: the eroded r16 imported headlessly into 4 regions (height 0 to 73 m) and saved as `.res`. `_proof\terrain3d\`.
- **Azgaar**: seed `ashes1` gives 22 states and 1133 burgs; exported PNG, SVG, rivers and cells GeoJSON. `_proof\azgaar\map_ashes1.png`.

## Commands

Blender scripts run through the wrapper, which sets `BLENDER_USER_SCRIPTS` (legacy add-ons) and `BLENDER_USER_EXTENSIONS` (extensions) and uses `--factory-startup`:

```
tools/external/blender.sh tools/external/proof_rigify_horse.py -- <out_dir>
tools/external/blender.sh tools/external/proof_wiggle2.py      -- <out_dir>
tools/external/blender.sh tools/external/proof_bonedyn.py      -- <out_dir>
tools/external/blender.sh tools/external/proof_expykit.py      -- <out_dir>
tools/external/blender.sh tools/external/ant_terrain.py        -- <out_dir> [seed] [grid]
C:\Users\Jonna\Tools\terrain-erosion-3-ways\venv\Scripts\python.exe tools/external/erode_heightmap.py --generate 512 --seed 7 --out <dir>/valley
C:\Users\Jonna\Tools\terrain-erosion-3-ways\venv\Scripts\python.exe tools/external/erode_heightmap.py --in height.png --out <dir>/eroded
node tools/external/azgaar_export.mjs <seed> <out_dir> [width] [height]
Godot_v4.6.3-stable_win64_console.exe --headless --path <project with addons/terrain_3d> -s <abs path>/tools/external/terrain3d_import_r16.gd -- <r16 file> <size> <max_height_m> <out_dir>
```

Scripting hooks live in `tools/external/bl_common.py`: `enable("rigify","wiggle_2","bone_dynamics","expy_kit","bl_ext.user_default.antlandscape")`, `clear_scene()`, `setup_render()`, `camera()`, `bone_lines(obj, filter)` (draws bones as tubes, because Workbench does not render armatures), `render(path)`.

Gotchas found while proving:
- **Enable Rigify with `default_set=True`** (`addon_utils.enable("rigify", default_set=True)`). With `--addons rigify` or `default_set=False`, `register()` throws `KeyError: 'rigify'` and generation fails with `make_custom_pivot`.
- Horse: `bpy.ops.object.armature_horse_metarig_add()`, then `bpy.ops.pose.rigify_generate()` (the rig object is named `rig`). Other animals: `armature_wolf_metarig_add`, `armature_cat_metarig_add`, `armature_bird_metarig_add`, `armature_basic_quadruped_metarig_add`. Useful horse controls: `torso`, `hips`, `chest`, `neck`, `head`, `forefoot_ik.L/R`, `hind_foot_ik.L/R`, `upper_arm_ik.L/R`, `tail.001` to `tail.005`.
- **Wiggle 2 v2.2.3 needs a one-line patch on Blender 5.2** (`Bone.select` was removed): line 666 `b.bone.select = True` becomes `b.select = True`. Already applied in the installed copy (see `Tools\blender-addons\wiggle_2.LOCALPATCH.txt`). Properties: `scene.wiggle_enable`, `bone.wiggle_tail`, `wiggle_stiff`, `wiggle_damp`, `wiggle_mass`; operators `wiggle.reset`, `wiggle.bake`. Step frames with `scene.frame_set` so the handler simulates. Values that look right on the horse tail: stiff 400, damp 6.
- Blender 5 actions are layered, `action.fcurves` is gone: use `[fc for l in a.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]`.
- Bone Dynamics: `pb.bdyn.enabled/stiffness/damping/gravity/wind`, `scene.bdyn.wind_strength`, `bpy.ops.bdyn.bake()`. It loads as a legacy add-on (a warning about missing `bl_info` is harmless).
- A.N.T. `mesh.landscape_add` creates nothing headless unless `refresh=True`; `mesh_size_x/mesh_size_y` set the size in metres; `mesh.eroder(Iterations=2)` with default parameters is stable, while large Kr/Kv values blow the heights up.
- Azgaar's build is served under the base path `/Fantasy-Map-Generator/`. Exports are `window.Services.ExportMap.exportToPng()`, `exportToSvg()`, `saveGeoJsonRivers()`, `saveGeoJsonCells()`. Playwright drives Edge (`channel: "msedge"`), so no browser download is needed. Rebuild: `cd Tools\azgaar; npm ci --ignore-scripts; npm run build`.
- Terrain3D headless: write `res://.godot/extension_list.cfg` containing `res://addons/terrain_3d/terrain.gdextension` in a scratch project, add the node, then `await process_frame` twice before touching `terrain.data`.

## Rejected (and why)

| Tool | Verdict |
|---|---|
| Gaea (QuadSpinner) | The Community edition is non-commercial and capped at 1K export; commercial use needs a paid Indie/Pro licence. Rejected. |
| World Machine Basic | Free tier is non-commercial; not installed. |
| Cascadeur Free | Free plan is non-commercial and exports .casc only; FBX needs paid Indie. Rejected. |
| Rokoko Blender add-on (LGPL) | Ships a login manager and needs `boto3`/`lz4`, which are missing; retargeting is already covered by `kingdom/tools/anim/retarget_clips_to_ual.py`. Removed. |
| AnimAide (GPL headers) | Fails to register on Blender 5.2. Removed. |
| Simplify Curves+ 1.1.3 | Loads, but its operator poll crashes on 5.2 (`Action.fcurves` removed). Use Blender's own `graph.decimate` / `action.clean`. Removed. |
| Copy Attributes Menu, Retarget (KBS-DEV), Erosion terrain generator extension | GPL and installable, but GUI-only or a duplicate of a kept tool and not proven, so removed rather than kept unproven. |
| Wiggle 2 "RTX Edition" (extensions.blender.org) | Same API, but headless stepping exploded (tip 500 to 4000 m away at every setting tried). Upstream v2.2.3 is used instead. |
| BlendArMocap (GPL) | Needs mediapipe; an own phone-video mocap pipeline already exists (`docs/anim/advanced/video_mocap/README.md`). Not installed. |
| Godot jiggle plugins (GodotJiggleBone MIT, others) | Godot 4.6 has the built-in `SpringBoneSimulator3D`; these are older GDScript add-ons. Not needed. |
| Wonderdraft (paid), Inkarnate (account) | Rejected by rule. |
| Watabou generators | Only an informal "use as you like" note (resale of raw maps disliked), no formal licence. Rejected under the licence gate. |
| WFC add-ons for Godot | No need identified; `road-generator` and `proton_scatter` are already in `kingdom/addons`. |
| Quadruped or horse mocap datasets | No commercial-safe set found. Use the CC0 Quaternius animals in `incoming/animals/`, the Rigify horse for authoring, and the authored `Ride_*` clips. |
