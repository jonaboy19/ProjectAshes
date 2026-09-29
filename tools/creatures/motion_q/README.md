# Group Q creature motion (boar, bear, spider, giant wasp)

Blender 5.2 headless (`"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python <script> -- <args>`), always wrapped in `timeout`.
Findings and numbers: `docs/anim/creatures/Q_REPORT.txt` and `docs/anim/creatures/<creature>/TABLE.txt`.

## Method
The clips are edited **in place on the shipped GLBs**. The Blender re-export is used only to produce animation data; `glbtools.graft()`
copies just the changed animations into the original GLB, so meshes, skins, textures and all unchanged clips stay byte for byte.
LOD0 and LOD1 get the same grafted clips (same skeleton).

## Files
| File | Purpose |
|---|---|
| `mq.py` | import a GLB at 30 fps, clip lookup, skinned vertex sampling |
| `qrig.py` | own forward kinematics in armature space (verified against Blender to 1e-6), world-axis rotations about bone heads, action writing |
| `qgait.py` | foot planting: skinned foot point + CCD IK; `lock_clip` plants stance feet for a ground speed `v` |
| `qpose.py` | keyframed authoring: `root.*`, `<Bone>.rx/ry/rz`, `foot.<F>.x/y/z` params with eases, IK feet |
| `author_boar.py`, `author_bear.py`, `author_spider.py`, `author_wasp.py` | the actual fixes; each writes `<out_dir>/<name>.glb` and `_lod1.glb` |
| `glbtools.py` | GLB read/write, animation graft, buffer repack |
| `analyze_feet.py` | foot slide metrics (v*, per-frame slip, per-stance excursion) |
| `analyze_attack.py` | attack timing / mass-shift metrics (wind-up, impact, hold, recovery) |
| `render_clip.py`, `review.sh`, `strip.sh`, `sheet.sh` | render frames FROM a GLB, tile to sheets (`tools/qa/video_to_sheets.sh`), delete frames |
| `measure_all.sh` | before/after foot metrics for all creatures |
| `dump_*.py`, `inspect_glb.py`, `glbinfo.py`, `roundtrip.py`, `feet_probe.py` | diagnostics |

## Reproduce
```bash
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
# 1. author into a scratch dir (reads the GLBs currently in the repo, so start from the ORIGINALS: git show HEAD~:path)
timeout 600 "$B" -b --python tools/creatures/motion_q/author_boar.py  -- /c/Users/Jonna/mqw/out
timeout 600 "$B" -b --python tools/creatures/motion_q/author_bear.py  -- /c/Users/Jonna/mqw/out
timeout 600 "$B" -b --python tools/creatures/motion_q/author_spider.py -- /c/Users/Jonna/mqw/out
timeout 600 "$B" -b --python tools/creatures/motion_q/author_wasp.py  -- /c/Users/Jonna/mqw/out
# 2. copy <out>/*.glb over the repo GLBs, then review from the GLB
WALKV=0.455 RUNV=1.95 bash tools/creatures/motion_q/review.sh boar kingdom/assets/incoming/ai3d/meshy/creatures/boar.glb docs/anim/creatures/boar
bash tools/creatures/motion_q/strip.sh boar <glb> out.jpg attack "0,4,8,12,16,20" "side front" 6   # quick iteration strip
```
`WALKV/RUNV` scroll the ground grid at that speed (treadmill) so planted feet must stay on their grid cell.
Axes in Blender: quadrupeds face -Y (+Z up, +X left); the wasp faces +X. `+rx` pitches a quadruped's nose down; for the wasp `+ry` does.

## Conventions
Attack impact = time of peak extremity speed (`analyze_attack.py`), the definition used by `creature_models.gd`.
The game plays the attack at `impact / windup` speed, so impacts were authored close to the species `windup`
(boar 0.55 s, bear 0.75 s) to keep the playback near 1.0.
