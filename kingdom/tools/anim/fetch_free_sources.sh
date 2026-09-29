#!/usr/bin/env bash
# Download exactly the CMU BVH takes used by tools/anim/cfg_free_*.json into $ANIM_SRC/cmu-mocap/data
# (default ~/.cache/ashes_anim_src). Source: BVH conversion by B. Hahne (cgspeed), GitHub mirror
# https://github.com/una-dinosauria/cmu-mocap  (CMU terms: free for commercial use, see
# assets/incoming/animations_free/LICENSES.md). Raw files are not committed.
#
#   bash tools/anim/fetch_free_sources.sh
#   python tools/anim/make_free_cfgs.py            # writes cfg_free_*.json (needs Blender's python or bpy)
#   blender -b --python tools/anim/retarget_bvh.py -- tools/anim/cfg_free_kicks.json     (one per category)
#   python tools/anim/glb_reduce_anim.py assets/incoming/animations_free/kicks/UAL_Free_Kicks.glb
set -eu
ANIM_SRC="${ANIM_SRC:-$HOME/.cache/ashes_anim_src}"
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$ANIM_SRC/cmu-mocap/data"
mkdir -p "$D"
grep -ho '"file": "[0-9]*/[0-9_]*\.bvh"' "$HERE"/cfg_free_*.json | cut -d'"' -f4 | sort -u | while read -r f; do
  if [ ! -s "$D/$f" ]; then
    mkdir -p "$D/$(dirname "$f")"
    curl -sfL -o "$D/$f" "https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data/$f" || echo "FAILED $f"
  fi
done
echo "sources ready in $D"
