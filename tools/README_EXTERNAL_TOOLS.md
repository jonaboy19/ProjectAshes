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


# Round 2 (2026-09-30): phone, GPU, mesh, texture, mocap, voice and SFX tools

Installed in `C:\Users\Jonna\Tools\<tool>` (not in git). Proofs, each opened and read: `C:\Users\Jonna\Tools\_proof2\<tool>\`. Wrappers in `tools/external/`.
**Only on the local PC (needs the GPU, the phone or the Windows tool):** scrcpy, Perfetto recording, AGI, RenderDoc, Real-ESRGAN (Vulkan GPU), Krita, Instant Meshes (Windows exe). CPU-only and portable to any box with the same binaries: gltfpack, rtmlib, Piper, rFXGen, jsfxr.
No Ollama or local LLM was installed (owner rule).

| Tool | Version | Licence (verified at source) | For | Where |
|---|---|---|---|---|
| scrcpy | 4.1 (SHA256 checked against the release) | Apache-2.0 | mirror, record, control the S22 | `Tools\scrcpy\scrcpy-win64-v4.1` |
| RenderDoc | 1.46 portable zip from renderdoc.org | MIT | one-frame GPU capture, draw-call counts on the PC | `Tools\renderdoc\RenderDoc_1.46_64` |
| Android GPU Inspector (AGI) | 3.3.3 | Apache-2.0 | phone GPU profiling GUI | `Tools\agi\agi` |
| Perfetto | v58.2 (`trace_processor_shell`, `perfetto`, `traceconv`, `record_android_trace.py`) | Apache-2.0 | phone CPU/frequency/frame traces and SQL over them | `Tools\perfetto` |
| gltfpack (meshoptimizer) | 1.3 | MIT | GLB simplify / auto LOD / compress | `Tools\gltfpack\gltfpack.exe` |
| Real-ESRGAN ncnn Vulkan | binary from Real-ESRGAN release v0.2.5.0 (20220424) incl. models | code MIT (ncnn repo) and BSD-3 (Real-ESRGAN repo); no non-commercial clause on the weights (realesrgan-x4plus, x4plus-anime, animevideov3) | 2x/3x/4x texture upscale | `Tools\realesrgan` |
| Krita | 6.0.4 portable zip from download.kde.org | GPL-3 tool, your art is yours | texture painting, headless conversion | `Tools\krita\krita-x64-6.0.4\bin\krita.com` |
| Instant Meshes | master Windows build (wjakob) | BSD-3-Clause | quad retopology of organic meshes | `Tools\instantmeshes` |
| rtmlib (RTMPose) | 0.0.16, onnxruntime 1.30 CPU, model rtmpose-m body7 | rtmlib Apache-2.0, mmpose/RTMPose Apache-2.0 | 2D body keypoints from video, better than MediaPipe on limbs | `Tools\rtmlib\venv` (models cached in `~\.cache\rtmlib`) |
| Piper TTS | binary 2023.11.14-2 (rhasspy/piper) | MIT (binary bundles espeak-ng, GPL-3: only the tool, not the audio) | NPC voice lines | `Tools\piper` |
| rFXGen | 5.0 | zlib | retro SFX from presets | `Tools\rfxgen\rfxgen_v5.0_win_x64\rfxgen.exe` |
| jsfxr (npm) | 1.4.1 | Unlicense (public domain) | seeded SFX variations (hit, coin, jump ...) | `Tools\jsfxr` |

## Proofs (real project data)
- **scrcpy**: 10 s record of the S22 (SM-S901B, Android 16) with `--no-control --no-window`: H.264 1080x2340 plus Opus audio, 9.4 s (home screen was static, so only 33 video frames); the frame shows the launcher. `_proof2\scrcpy\s22_10s.mp4`. No input was sent.
- **Perfetto**: 5 s trace of the S22 (sched, freq, idle, gfx, view; 1.9 MB). `trace_processor_shell` read it: 26 385 sched slices, 8 CPUs, 633 threads, 28 215 counter samples. `_proof2\perfetto\`.
- **RenderDoc**: Godot 4.6.3 (mobile renderer, D3D12) rendering 3 castle LODs from `meshy_free`: one captured frame, 25.9 MB `.rdc`, replayed through the Python API: **17 draw calls** (16 indexed), 2 render passes, 4 clears, about 109 k triangles including the shadow pass. `_proof2\renderdoc\drawcalls.json`.
- **gltfpack**: `meshy_free/castle/castle_sandstone_b_lod0.glb` 1 799 864 B and 14 997 tris -> `-si 0.4 -sa -noq` 363 240 B and 5 826 tris -> `-si 0.1 -sa -noq` 285 116 B and 1 057 tris. Loaded back in Godot 4.6.3 and triangle counts read from the meshes (14 997 / 5 826 / 1 057). `_proof2\gltfpack\`.
- **Real-ESRGAN**: `region/textures/planks.png` (downscaled to 256) -> 1024x1024 with `realesrgan-x4plus`; side by side with a nearest-neighbour upscale the grain and the plank seams are crisp instead of mushy. 59 s on the RTX 4070 (`-g 2`), 115 s on the CPU fallback. `_proof2\upscale\compare_small.png`.
- **Krita**: headless `krita.com in.png --export --export-filename out.kra` converted the upscaled texture (4.4 MB .kra). `_proof2\krita\`.
- **Instant Meshes**: `meshy_free/creatures/horse_saddled_lod0.glb` (7 962 tris, messy, multi-shell saddle and straps) -> `-f 600` gives 2 179 clean quads on the body (3.9 k tris after triangulation). The body flows well, but saddle, straps and tail fall apart into fragments. Verdict: use it only on single-shell organic bodies, then re-bake textures (it drops UVs). A house (`blacksmith_lod0`) came out broken. `_proof2\instantmeshes\horse_compare_f600.png`.
- **RTMPose vs MediaPipe** on the synthetic sword clip (`kingdom/tools/anim/video_mocap/out/sword_char`, 35 frames, ground truth known), 2D error as a fraction of torso length over 12 joints: MediaPipe heavy mean 0.167 (wrists 0.41 to 0.45, elbows 0.23 to 0.26), RTMPose-m mean **0.060** (wrists 0.04, elbows 0.03 to 0.06); PCK@0.1 0.72 vs **0.81**. Hips are equal or slightly worse for RTMPose (0.08). In the overlay the MediaPipe wrists and arm points drift off the body in the crouch frame, RTMPose stays on the joints. `_proof2\rtmpose\overlay.png`, `compare_2d.json`. RTMPose-m is 2D only: `mocap_to_bvh.py` needs MediaPipe's 3D world landmarks, so `rtm_extract.py` is a cross-check and a 2D upgrade today, not yet a drop-in (next step: fuse RTM 2D with MediaPipe depth, or rtmlib `Wholebody3d`). CPU speed: 35 frames in about 45 s including the one-off 48 MB model download.
- **Piper**: Wren's line from `docs/regions/STORY_R1.md` ("You glow now. Insufferable. I'm coming on every road.") with the `young` voice: 4.3 s wav, pitch about 225 Hz; Bram's ledger line with `norman`: 7.4 s, about 120 Hz. `_proof2\piper\`. Not auditioned by ear: check by listening.
- **rFXGen**: `-g hit` gives a 0.14 s 44.1 kHz 16-bit mono wav, peak -8 dB. The CLI presets are fixed (same file every run); for variations use jsfxr. `_proof2\rfxgen\hit.wav`.
- **jsfxr**: `hitHurt` seeds 7, 8, 9 give three different 8-bit 44.1 kHz hits of 0.08 to 0.14 s. `_proof2\jsfxr\`.

## Piper voices: licence verdicts (read from each MODEL_CARD)
Kept (nothing derived from a restricted dataset):
- `en_US-norman-medium` male, public domain (LibriVox), trained from scratch. `en_US-john-medium` male, public domain, fine-tuned from Kristin. `en_US-kristin-medium` female, public domain, from scratch. `en_GB-cori-high` UK female, public domain, from scratch.
- `en_US-libritts-high` (904 speakers), CC BY 4.0, trained from scratch: credit "LibriTTS (Zen et al.)" in the game credits. Speaker 250 = higher voice (`young`), speaker 400 = low voice (`deep`). Pitch only; no speaker ages are documented.
Rejected: `hfc_female/male`, `l2arctic`, `semaine`, `ryan` (CC BY-NC(-SA), non-commercial); `northern_english_male` and `southern_english_female` (CC BY-SA share-alike); **every voice fine-tuned from `lessac`** (joe, mike, kusal, sam, arctic, alba, aru, vctk, jenny, libritts_r, reza_ibrahim ...) because the Lessac Blizzard 2013 data is under a research-only licence, so commercial status of derived weights is unclear; `amy`, `danny`, `kathleen`, `alan`, `bryce` (fine-tuned from Ryan which is NC, or from an unreleased base).
The Piper voices live in `Tools\piper\voices` together with their MODEL_CARDs. The 1.x Piper fork (OHF-Voice/piper1-gpl) is GPL-3 and was not used; the binary used is the MIT 2023 release.

## Commands for agents
```
# phone (local PC only). The wrapper forces the platform-tools adb so the shared adb server is not restarted.
powershell -File tools/external/s22_capture.ps1 -Kind video -Seconds 10 -Out C:\out\s22.mp4
powershell -File tools/external/s22_capture.ps1 -Kind trace -Seconds 10 -Out C:\out\s22.pftrace
C:\Users\Jonna\Tools\perfetto\windows-amd64\trace_processor_shell.exe -q q.sql C:\out\s22.pftrace
scrcpy live mirror: $env:ADB='C:\Users\Jonna\platform-tools\adb.exe'; scrcpy.exe -s R5CT849XNVF --no-control   (leave off input)

# RenderDoc draw calls of a Godot run (GPU, local): prints drawcalls.json
powershell -File tools/external/renderdoc_godot.ps1 -Project <godot project dir> -Out C:\out\rd [-Script tools/external/godot_rd_scene.gd -ScriptArgs "a.glb b.glb"]

# meshes. gltfpack: for GODOT add -noq (no quantisation, no meshopt): Godot 4.6.3 cannot import KHR_mesh_quantization or EXT_meshopt_compression.
gltfpack.exe -i in.glb -o out_lod1.glb -noq -si 0.4 -sa      # -sa = aggressive, needed on Meshy meshes (plain -si 0.4 barely reduced them: UV seams lock edges)
gltfpack.exe -i in.glb -o web.glb -c -si 0.4 -sa              # compressed, only for viewers that support meshopt (not Godot)
tools/external/blender.sh tools/external/glb_to_obj.py -- in.glb out.obj                 # Instant Meshes only reads obj/ply
"C:\Users\Jonna\Tools\instantmeshes\Instant Meshes.exe" in.obj -o out.obj -f 600 -d -b -c 30   # -f = base face count, final quads are about 3.6x more; -d deterministic
tools/external/blender.sh tools/external/glb_to_obj.py -- --back out.obj out.glb
tools/external/blender.sh tools/external/retopo_compare_render.py -- in.obj out.obj compare.png

# textures (local GPU; -g 2 is the RTX 4070, 0 and 1 are slow/AMD/CPU)
C:\Users\Jonna\Tools\realesrgan\realesrgan-ncnn-vulkan.exe -i in.png -o out.png -n realesrgan-x4plus -s 4 -g 2     # -n realesrgan-x4plus-anime for flat painted art
C:\Users\Jonna\Tools\krita\krita-x64-6.0.4\bin\krita.com in.png --export --export-filename out.kra

# video mocap: RTMPose 2D keypoints and the accuracy comparison
C:\Users\Jonna\Tools\rtmlib\venv\Scripts\python.exe kingdom/tools/anim/video_mocap/rtm_extract.py clip.mp4 out/clip_rtm.npz
python kingdom/tools/anim/video_mocap/compare_2d.py gt.json mp_pose.npz rtm.npz --json cmp.json

# voice and SFX
powershell -File tools/external/piper_say.ps1 -Voice kristin|norman|john|cori|young|deep -Text "..." -Out line.wav
C:\Users\Jonna\Tools\rfxgen\rfxgen_v5.0_win_x64\rfxgen.exe -g hit|coin|laser|explosion|powerup|jump|blip -o out.wav -f 44100,16,1
node tools/external/jsfxr_gen.js hitHurt <seed> out.wav [count]      # pickupCoin laserShoot explosion powerUp hitHurt jump blipSelect synth tone click random
```

Gotchas found while proving:
- **RenderDoc**: there is no standalone Python module in the portable zip; scripts run inside `qrenderdoc.exe --python script.py` (embedded Python 3.8) and must end with `os._exit`. The first start shows an analytics dialog: the config `%APPDATA%\qrenderdoc\UI.config` was set to `Analytics_TotalOptOut: true` and update checks off. The Vulkan layer is not registered (RenderDoc warns), so Godot is captured on D3D12; capturing Vulkan would need the layer registered in HKCU, which was deliberately not done. Launch the non-console Godot exe. `renderdoccmd` has no capture delay; the script triggers the capture through the target-control API.
- **AGI**: GUI tool (`Tools\agi\agi\agi.exe`). Running `gapit devices` made `gapis` start installing its APK on the phone, so it was killed and nothing was left installed. Do not run AGI against the phone while another agent is using it. The S22 here is SM-S901B (Exynos 2200, Xclipse GPU); AGI support for Xclipse is doubtful, so for that phone use Perfetto plus `adb shell dumpsys gfxinfo` and RenderDoc on the PC. AGI was not device-tested.
- **Real-ESRGAN**: the release v0.2.0 zip of the ncnn repo contains no models; use the 20220424 zip from the Real-ESRGAN repo (models included). The weights are trained on photo data; painted textures are sharpened and get extra noise, review before shipping and downscale to the game size.
- **scrcpy** records Opus audio; a static screen produces very few video frames.
- **Godot imports**: plain `-noq` output imports fine; LODs here are manual scene nodes or Godot's own automatic mesh LOD on import.
- **Git Bash vs WSL**: `bash` in PowerShell is WSL on this PC; run `blender.sh` through the Bash tool (Git Bash) or `"C:\Program Files\Git\bin\bash.exe"`.

## Round 2 rejected or not installed
| Tool | Verdict |
|---|---|
| Upscayl 2.15.0 | Not installed: AGPL-3.0 GUI, 249 MB, and it wraps the same Real-ESRGAN models; the ncnn CLI does the job headless. Reconsider only if a GUI is wanted. |
| FreeMoCap | Not installed: AGPL-3.0, multi-camera calibrated capture with a heavy dependency stack; we have single phone videos. RTMPose covers the single-camera case. |
| Piper 1.x (piper1-gpl) | GPL-3 fork; the MIT 2023 binary is enough. |
| Lessac-derived and NC Piper voices | See the voice table above. |
| Ollama and any local LLM | Forbidden by the owner. |
