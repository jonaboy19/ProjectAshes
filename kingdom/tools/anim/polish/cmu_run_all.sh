#!/usr/bin/env bash
# Rebuild the fixed defense + reactions libraries from the pristine GLBs and render metrics / sheets.
#   bash cmu_run_all.sh <pristine_dir> <work_dir>      pristine_dir/{defense,reactions}/UAL_Free_*.glb(+.clips.json) = git HEAD~ copies
# Needs Blender 5.2 (mesh audit + render). Result GLBs are written in place under kingdom/assets/incoming/animations_free/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$HERE/../../../.."
ORIG=${1:?pristine dir}; W=${2:?work dir}
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; PY="C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
A="$ROOT/kingdom/assets/incoming/animations_free"; mkdir -p "$W"
for l in defense/UAL_Free_Defense reactions/UAL_Free_Reactions; do
  n=$(basename $l)
  cp "$ORIG/$l.glb" "$A/$l.glb"; cp "$ORIG/$l.glb.clips.json" "$A/$l.glb.clips.json"
  "$PY" "$HERE/cmu_fix.py" stage1 "$A/$l.glb"
  "$B" -b --python "$HERE/cmu_mesh_floor.py" -- "$A/$l.glb" "$W/$n.s1.json" | grep -E "Error|Traceback" || true
  "$PY" "$HERE/cmu_fix.py" floor "$A/$l.glb" "$W/$n.s1.json"
  "$B" -b --python "$HERE/cmu_mesh_floor.py" -- "$A/$l.glb" "$W/$n.final.json" | grep -E "MESH|Error|Traceback" || true
  "$B" -b --python "$HERE/render_clips.py" -- "$A/$l.glb" "$W/r_$n" --fps=${FPS:-12} | grep -E "DONE|Error|Traceback" || true
done
