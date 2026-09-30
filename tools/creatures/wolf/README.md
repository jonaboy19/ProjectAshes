# Wolf rebuild (scale, ruff, colour, turn / pack clips)

Reproducible Blender 5.2 pipeline (all runs `blender -b --python ... -- args`, wrap in `timeout`).

`src/wolf_orig.glb`, `src/wolf_lod1_orig.glb` are the original Meshy mesh + Quaternius rig GLBs (git history of
`kingdom/assets/incoming/ai3d/meshy/creatures/`). Everything is rebuilt from these.

| Script | What |
|---|---|
| `build_all.sh [work] [install]` | runs everything below for LOD0 and LOD1; `install=1` copies GLB + sidecar jpg into the game folder |
| `build_base.py` | stage 1: lowers the head carriage (neck bones posed, pose applied as the new rest pose so mesh and bones stay consistent), scales the armature object x1.3 (Godot scale stays 1.0), thickens the ruff (radial displacement from the neck axis), bigger head and paws, mane tufts (weights + UV copied from the surface), decimates to the tri budget (15k / 5k), re-grades the albedo by position (charcoal-blue saddle, silver-cream mane and underside, tan legs, face kept) and saves `<work>/baseN.blend` + `baseN_tex.jpg` |
| `author.py` | stage 2: builds the new clips on the base and exports the GLB (all old clips kept; `walk` / `run` are replaced by foot-locked versions, the originals stay as `walk_orig` / `run_orig`); writes `<name>_rootmotion.json` (per clip: root motion per frame `[forward m, left m, yaw rad]`, planted flags, events) |
| `wrig.py` / `gait.py` | analytic FK/IK rig model (world-axis rotations about pivots -> pose-bone basis; 2-link front leg, 3-link hind leg), planted-foot world model (`World`, `periodic_steps`, `foot_path`) |
| `clips_base.py`, `clips2.py`, `clips3.py`, `clips.py` | clip definitions: stalk, turn_l90/r90/l180/r180, circle_l/r, limp, flinch, howl, lunge (generated); walk, run, run_turn_l/r (source clip + foot lock, `lock.py`) |
| `measure.py` | slip measurement of any clip without root-motion table (used for the old clips) |
| `measure2.py` | world-space slip of the new clips using the root-motion table and planted flags (`MEASURE_OUT=file.json` to save) |
| `verify.py` | re-imports an exported GLB and prints clips, tris, images, bones, size |
| `render_still.py` | before/after stills over a green ground (side / three-quarter / front / 12 m phone-size) |
| `render_clip.py`, `rc.sh`, `review.sh`, `sheet.sh` | render a clip from the GLB (camera follows the root motion table so a fixed 1 m grid shows foot sliding) and tile numbered contact sheets with `tools/qa/video_to_sheets.sh` |

Typical loop: `./build_all.sh /tmp/wolfwork 0`, `./review.sh /tmp/wolfwork/wolf.glb /tmp/wolfwork/wolf_rootmotion.json /tmp/wolfwork/fr stalk:side:2`,
then `measure2.py`. Conventions: rig faces -Y in Blender (glTF +Z), +X = wolf left, yaw + = left turn, pitch + = nose down.
The rig has no toe or jaw bones, so paws are rigid with the lower leg (foot planting is solved on the paw vertex cloud) and the bite
is a head thrust plus snap, not an opening jaw.
