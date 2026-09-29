# motion_b: goblin / orc / troll motion pass

Blender 5.2 headless (`blender -b --python ...`, always wrapped in `timeout`). Nothing here touches the mesh.
The GLBs in `kingdom/assets/incoming/ai3d/meshy/creatures/` are imported, the edited clips are re-keyed as
plain FK keys (30 fps, frame 1 = t 0 like the original files) and exported again with all other clips untouched.

## Files
| File | Purpose |
|---|---|
| `authoring.py` | `Rig` (import/export, body frame, sampling) and the pose authoring layer: keys of hips / spine / head deltas, chest-relative hand targets and planted feet solved with an analytic 2-bone IK, baked to FK. Also `ground_lift_clip` (lift Hips just enough that no skinned vertex is below the floor) and `loop_close`. Hand targets can be floor-limited against the skinned fist vertices (`hand_ground`). |
| `specs_goblin.py`, `specs_orc.py`, `specs_troll.py` | The authored clips (key times, poses), `IMPACT` times, and which clips get ground / loop fixes. Edit these to change the motion. |
| `make_attacks.py` | `-- <creature> <in.glb> <out.glb> [--save baked.json \| --load baked.json]`. `--save` authors from the spec, `--load` re-applies the baked keys (LOD1 gets bit-identical clips). |
| `build_all.sh <creature>` | Rebuilds LOD0 + LOD1 from the ORIGINAL git HEAD files (`git show HEAD:...`) into the repo, saving `baked/<creature>.json`. |
| `iterate.sh <creature> <clip> [step]` | Author one clip to a temp GLB and write sheets to `docs/anim/creatures/<c>/wip/` (delete after use). |
| `render.py`, `render_lib.py`, `sheets.sh`, `render_all.sh` | Side + front render of every clip FROM THE GLB at 30 fps (step 1 up to 46 frames, else 2), hstacked and tiled with `tools/qa/video_to_sheets.sh`; PNGs are deleted after the jpg sheets are made. `render_all.sh <c> <glb> <before\|after>`. |
| `metrics.py`, `analyze.py`, `compare.py`, `loopcheck.py`, `hands.py` | World-space bone / mesh-min-z dump (`metrics.py`), foot-slip analysis (`analyze.py`, run with Blender's bundled `python.exe`, it has numpy), before/after and LOD0-vs-LOD1 comparison. |
| `inspect_glb.py`, `test_identity.py` | Debug helpers (bone list / clip ranges; identity round-trip test of the authoring layer). |
| `baked/*.json` | Baked FK keys of every edited clip (the LOD0 result). |
| `compare_attack.sh` | Before/after strip for one attack clip. |

## Conventions
* Time: frame f (Blender, starts at 1) = (f - 1) / 30 s. Clip duration = (frames - 1) / 30.
* Hand targets are `(forward, right, up)` in arm lengths from that shoulder; hips / feet are metres for a 1.1 m goblin and are multiplied by `K` (goblin 1, orc 1.8, troll 2.7).
* Pitch > 0 leans forward, yaw > 0 turns to the character's left, roll > 0 leans right.
* Ease names: `smooth`, `out` (decelerate), `in`, `snap` (slow start, very fast finish, used for the strike), `lin`.
* Tremble: 10 Hz (3-frame period) shake on hands and hips, in metres for the 1.1 m goblin, scaled by K.

## Reproduce
```
tools/creatures/motion_b/build_all.sh goblin      # also orc, troll
bash tools/creatures/motion_b/render_all.sh goblin "$PWD/kingdom/assets/incoming/ai3d/meshy/creatures/goblin.glb" after
"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python tools/creatures/motion_b/metrics.py -- <glb> <out.json>
"C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" tools/creatures/motion_b/analyze.py <out.json> <height_m> <walk> <run>
```
Paths inside the scripts are absolute for this worktree (`C:/Users/Jonna/Documents/PA_wt_creature`, temp in `%LOCALAPPDATA%/Temp/cm`).
