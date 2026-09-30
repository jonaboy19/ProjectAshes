---
name: ashes-external-tools
description: Approved external tools for Rising Ashes animation (Rigify horse, Wiggle 2, Bone Dynamics, Expy Kit) and world building (A.N.T.Landscape, dandrino erosion, Azgaar maps, Terrain3D import), with licence verdicts and headless commands. Use before rigging animals or horses, adding spring bones or hair/tail/cloth motion, or generating terrain, rivers or maps.
---

# External tools for Rising Ashes

Installed in `C:\Users\Jonna\Tools\` (never in the repo). Full notes, gotchas and the rejected list: `tools/README_EXTERNAL_TOOLS.md`. Scripts: `tools/external/`. Proof images: `C:\Users\Jonna\Tools\_proof\`.
Licence rule: the tool's licence must allow commercial use of its OUTPUT; no accounts or logins; official downloads only. Kept tools are GPL/MIT applications, their outputs (rigs, clips, heightmaps, maps) are ours.

| Tool | Use it for | Verdict | Headless call |
|---|---|---|---|
| Rigify horse/wolf/cat/bird metarig (Blender 5.2) | quadruped rigs, rearing and gallop authoring | GPL tool, output free | `tools/external/blender.sh tools/external/proof_rigify_horse.py -- out` |
| Wiggle 2 v2.2.3 (patched for 5.2) | tail, mane, hair, cloak springs; bake to keys | GPL-3 | `proof_wiggle2.py`: set `bone.wiggle_tail/stiff/damp`, step `frame_set`, `bpy.ops.wiggle.bake()` |
| Bone Dynamics 1.3.0 | springs with wind and collision, bake | GPL-3+ | `proof_bonedyn.py`: `pb.bdyn.enabled`, `bpy.ops.bdyn.bake()` |
| Expy Kit 0.6.1 | Rigify human to single-root game skeleton, GLB export | GPL-3 (file headers) | `proof_expykit.py`: `bpy.ops.armature.expykit_convert_gamefriendly(keep_backup=False)` (human only) |
| A.N.T.Landscape 0.2.0 | mesh terrain from noise, GLB/r16 export | GPL-2+ | `ant_terrain.py -- out seed grid`: `mesh.landscape_add(refresh=True)` |
| dandrino terrain-erosion-3-ways | erosion and river flow map on heightmaps | MIT | tool venv python + `tools/external/erode_heightmap.py` |
| Azgaar Fantasy Map Generator 1.153.1 | world and region maps, rivers, GeoJSON | MIT, maps free for commercial use | `node tools/external/azgaar_export.mjs <seed> <out>` |
| Terrain3D (in `kingdom/addons`) | runtime terrain, r16 import | MIT | `godot --headless ... -s tools/external/terrain3d_import_r16.gd -- ...` |

Rejected, do not reinstall: Gaea (non-commercial free tier), World Machine, Cascadeur Free (non-commercial, no FBX), Rokoko add-on (login libs), AnimAide (breaks on 5.2), Simplify Curves+ (breaks on 5.2; use `graph.decimate`), Wiggle 2 RTX Edition (unstable headless), Wonderdraft, Inkarnate, Watabou (no formal licence).

## Rules for agents
1. Run Blender through `tools/external/blender.sh` (sets the add-on paths). Never `taskkill` Blender globally; kill only your own PID.
2. Enable Rigify with `addon_utils.enable("rigify", default_set=True)`; other modules are `wiggle_2`, `bone_dynamics`, `expy_kit`, `bl_ext.user_default.antlandscape`. Helpers are in `tools/external/bl_common.py`.
3. Blender 5 actions are layered (layers, strips, channelbags, fcurves); `Action.fcurves` no longer exists.
4. Look at every proof render before reporting. Workbench does not draw armatures; `bl_common.bone_lines` draws bones as tubes.
5. In the game itself use Godot's built-in `SpringBoneSimulator3D` for spring bones; Wiggle 2 and Bone Dynamics are for baking motion into clips in Blender.
6. Heightmaps: erode with `erode_heightmap.py`, import to Terrain3D as r16 (0..1, scaled by max height). Azgaar rivers and cells GeoJSON can seed river splines and biome zones.
