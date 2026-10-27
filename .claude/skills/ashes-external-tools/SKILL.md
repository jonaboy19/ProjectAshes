---
name: ashes-external-tools
description: Approved external tools for Rising Ashes - animation (Rigify horse, Wiggle 2, Bone Dynamics, Expy Kit, RTMPose video mocap), world building (A.N.T.Landscape, erosion, Azgaar, Terrain3D), phone and GPU profiling (scrcpy, Perfetto, AGI, RenderDoc), meshes and textures (gltfpack LOD, Instant Meshes, Real-ESRGAN, Krita), NPC voices (Piper) and SFX (rFXGen, jsfxr) - with licence verdicts and headless commands. Also the agent MCP toolchain (DCC-MCP Godot and Blender, Serena, Context7, Debug Draw 3D): how to start and call them. Use before rigging, terrain, profiling the S22, simplifying or retopologising a GLB, upscaling a texture, generating voice lines or sound effects.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

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
| Terrain3D 1.0.2 + ProtonScatter 4.2.0 (in `kingdom/addons`) | runtime terrain and scatter behind `terrain_backend=terrain3d` (default `legacy`; bridge in `scripts/world/terrain3d_bridge.gd`, `scatter_chunk.gd`, `scatter_exclusion.gd`; handoff in docs/LOCAL_SESSION_HANDOFF.md), r16 import | MIT | `godot --headless ... -s tools/external/terrain3d_import_r16.gd -- ...`; tests `tests/test_terrain3d_bridge.gd` |

Rejected, do not reinstall: Gaea (non-commercial free tier), World Machine, Cascadeur Free (non-commercial, no FBX), Rokoko add-on (login libs), AnimAide (breaks on 5.2), Simplify Curves+ (breaks on 5.2; use `graph.decimate`), Wiggle 2 RTX Edition (unstable headless), Wonderdraft, Inkarnate, Watabou (no formal licence).

## Rules for agents
1. Run Blender through `tools/external/blender.sh` (sets the add-on paths). Never `taskkill` Blender globally; kill only your own PID.
2. Enable Rigify with `addon_utils.enable("rigify", default_set=True)`; other modules are `wiggle_2`, `bone_dynamics`, `expy_kit`, `bl_ext.user_default.antlandscape`. Helpers are in `tools/external/bl_common.py`.
3. Blender 5 actions are layered (layers, strips, channelbags, fcurves); `Action.fcurves` no longer exists.
4. Look at every proof render before reporting. Workbench does not draw armatures; `bl_common.bone_lines` draws bones as tubes.
5. In the game itself use Godot's built-in `SpringBoneSimulator3D` for spring bones; Wiggle 2 and Bone Dynamics are for baking motion into clips in Blender.
6. Heightmaps: erode with `erode_heightmap.py`, import to Terrain3D as r16 (0..1, scaled by max height). Azgaar rivers and cells GeoJSON can seed river splines and biome zones.

## Round 2 tools (2026-09-30) - full notes and proofs in `tools/README_EXTERNAL_TOOLS.md`
Local PC only (GPU or phone): scrcpy, Perfetto recording, AGI, RenderDoc, Real-ESRGAN, Krita, Instant Meshes. Portable CPU tools: gltfpack, rtmlib, Piper, rFXGen, jsfxr. No Ollama or local LLM (owner rule).

| Tool | Licence | Use | Command |
|---|---|---|---|
| scrcpy 4.1 | Apache-2.0 | record/mirror S22 (`R5CT849XNVF`), no input | `tools/external/s22_capture.ps1 -Kind video -Seconds 10 -Out x.mp4` |
| Perfetto v58.2 | Apache-2.0 | S22 CPU/frame trace + SQL | `s22_capture.ps1 -Kind trace ...` then `trace_processor_shell.exe -q q.sql x.pftrace` |
| RenderDoc 1.46 | MIT | one-frame capture, draw calls (Godot on D3D12) | `tools/external/renderdoc_godot.ps1 -Project <dir> -Out <dir>` |
| AGI 3.3.3 | Apache-2.0 | phone GPU GUI; not device-tested, S22 is Exynos/Xclipse (doubtful); it installs an APK on the phone, never run it while another agent uses the phone | `Tools\agi\agi\agi.exe` |
| gltfpack 1.3 | MIT | GLB auto-LOD/simplify. For Godot always `-noq` (4.6.3 cannot import quantized or meshopt GLBs); use `-sa` on Meshy meshes | `gltfpack.exe -i in.glb -o out.glb -noq -si 0.4 -sa` |
| Instant Meshes | BSD-3 | quad retopo of single-shell organic meshes only (saddle, straps, buildings break); obj/ply in, drops UVs | `glb_to_obj.py` via blender.sh, then `"Instant Meshes.exe" in.obj -o out.obj -f 600 -d -b -c 30` |
| Real-ESRGAN ncnn | MIT code, BSD-3 weights | 2x/3x/4x texture upscale, `-g 2` = RTX 4070 | `realesrgan-ncnn-vulkan.exe -i a.png -o b.png -n realesrgan-x4plus -s 4 -g 2` |
| Krita 6.0.4 | GPL-3 | painting, headless convert | `krita.com in.png --export --export-filename out.kra` |
| rtmlib/RTMPose | Apache-2.0 | 2D keypoints; 0.06 vs MediaPipe 0.17 torso-length error on the synthetic clip, but 2D only | `Tools\rtmlib\venv\Scripts\python.exe kingdom/tools/anim/video_mocap/rtm_extract.py clip.mp4 out.npz` |
| Piper (MIT binary) | voices: only public-domain (norman, john, kristin, cori) and CC-BY libritts-high (credit needed); NC, SA and Lessac-derived voices rejected | NPC lines | `tools/external/piper_say.ps1 -Voice norman -Text "..." -Out x.wav` |
| rFXGen 5.0 | zlib | fixed presets (hit, coin, laser, explosion, powerup, jump, blip) | `rfxgen.exe -g hit -o x.wav` |
| jsfxr 1.4.1 | Unlicense | seeded SFX variations | `node tools/external/jsfxr_gen.js hitHurt 7 x.wav 3` |

Not installed: Upscayl (AGPL GUI, duplicate of Real-ESRGAN), FreeMoCap (AGPL, multi-camera), Piper 1.x GPL fork.
RenderDoc scripts run only inside `qrenderdoc.exe --python`. `bash` in PowerShell is WSL on this PC: run `blender.sh` via the Bash tool (Git Bash).

## Agent MCP toolchain (2026-10-01) - full notes in `tools/README_EXTERNAL_TOOLS.md`, plan in `docs/TOOLCHAIN_PLAN.md`
Three MCP servers are registered at project scope in `.mcp.json` (approve the trust prompt once). Exactly ONE Godot MCP exists (DCC-MCP Godot); do not add another.

| MCP | Use it for | Start |
|---|---|---|
| `dcc-mcp` (gateway `http://127.0.0.1:9765/mcp`, tools `search`, `describe`, `load_skill`, `call`) | Godot: inspect project, scene tree, open/play/stop scenes, editor errors and output, QA assertions, profiling. Blender 5.2 headless: primitives, mesh ops, UV, rig, materials, glTF export | `powershell -NoProfile -ExecutionPolicy Bypass -File tools/mcp/dcc_mcp_start.ps1 -Blender -Godot kingdom` (run it in the background; stop with `dcc_mcp_stop.ps1`) |
| `serena` | Symbol overview, find symbol, find references and symbol-level edits in GDScript, instead of reading big files. Always pass `relative_path` | needs the Godot editor LSP on port 6008, which the same start script provides |
| `context7` | Current docs for Godot 4.6 and addons (`resolve-library-id` then `query-docs`) | nothing, no key |

Flow for dcc-mcp: `search` with `kind=skill` and `dcc_type`, `load_skill`, then `call` with `tool_slug` `<dcc>.<instance8>.<tool>`. If no tools answer, the back ends are not running: start them first. `tools/mcp/mcp_call.sh` makes the same calls from any shell (Codex fallback).
Rules:
- One Godot editor at a time for the MCP. Never kill Godot or Blender globally; the stop script kills only its own PIDs.
- **Never commit the DCC-MCP Godot plugin lines in `kingdom/project.godot`** (plugin and `DccMcpRuntimePeer` autoload). The plugin is enabled per checkout by the start script and excluded in `.git/info/exclude`. `git diff kingdom/project.godot` before every commit; the `[debug_draw_3d]` section is the only addition to keep.
- The Godot editor run touches `.import`, `.uid` and `godot_gas` files: commit only your own paths.
- Debug Draw 3D (`kingdom/addons/debug_draw_3d`, committed) is a GDExtension: `DebugDraw3D.draw_*` / `DebugDraw2D`. Release templates make it a no-op; gate game calls with `OS.is_debug_build()` and a debug flag so nothing draws unless debugging.
- Android Performance Analyzer is not installed (562 MB, Android SDK licence the owner must accept); use Perfetto + `s22_capture.ps1` as before.
- No Godot LSP means Serena symbol tools fail; start the editor (headless is fine) before using them.

## Blender 5.2 extensions (installed 2026-10-28, official extensions.blender.org, all GPL; outputs free for commercial use)
Installed in `%APPDATA%\Blender Foundation\Blender\5.2\extensions\user_default\` and enabled. Use them before writing custom Blender code.
| Need | Extension |
|---|---|
| Realistic trees (oak/ash/beech), leaves | `sapling_tree_gen`, `modular_tree`, `space_colonization_tree_generator`, `leaf_gen` (+ Poly Haven bark; bake impostors/LODs) |
| Ivy on walls (ref 20), scatter, random arrays, simple architecture | `ivygen`, `Bagapie`, `scatter_objects`, `PlaceHelper` |
| Terrain noise and displacement | `antlandscape` |
| Modelling helpers | `looptools`, `bool_tool`, `extra_mesh_objects`, `archimesh`, `copy_attributes_menu`, `animall` |
| PBR baking (re-material Meshy props, edge wear, atlases) | `thebetterbaker`, `paws_bakery`, `bake_to_single_material` |
| LODs, decimation, texel density | `lod_gen`, `lodify_optimizer`, `texel_density_checker` |
| Animation retarget and root motion | `retarget`, `root_maker` (also Expy Kit, Rigify, Wiggle 2) |
| Realistic humans (CC0 output) | `mpfb` (MakeHuman) — candidate for the hero and NPC body base |
Built in, no add-on needed: Geometry Nodes (fences, walls, cobbles, scatter), Cloth sim (canopies, laundry, banners, capes → bake), QuadriFlow remesh, Decimate, Cycles bake. Blender's online repo sync is off here: install new extensions with `blender -b --command extension install-file -r user_default -e <zip>` (zip URLs from `https://extensions.blender.org/api/v1/extensions/`).

## AI tools (local, RTX 4070 8 GB)
- Real-ESRGAN (texture upscale), RTMPose (2D video mocap), Instant Meshes, Piper — see above.
- DeepBump (GPL-3, `C:\Users\Jonna\Tools\deepbump`): photo/albedo → normal and height maps (ONNX, CPU OK, ~1 min per 2K map; tested 2026-10-28). Set `PYTHONIOENCODING=utf-8` first. `C:\Users\Jonna\Tools\deepbump\venv\Scripts\python.exe C:\Users\Jonna\Tools\deepbump\DeepBump-8\cli.py in.png out_normal.png color_to_normals`.
- Rejected: TRELLIS image→3D (needs ~16 GB VRAM), Hunyuan3D (licence), SMPL-based video mocap (non-commercial body model), local LLMs (owner rule), AudioCraft/XTTS (non-commercial weights).
