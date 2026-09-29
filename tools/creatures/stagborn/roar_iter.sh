#!/usr/bin/env bash
# dev loop: author roar from char blend, print antler clearance, export test GLB, render sheets. usage: roar_iter.sh <out_dir> [step]
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../../.." && pwd); cd "$ROOT"
GLB=${TMP:-/tmp}/rd.glb
RD_GLB=$(cygpath -m "$GLB") "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python tools/creatures/stagborn/roar_dev.py -- ${CHAR_BLEND:-C:/Users/Jonna/Documents/ProjectAshes_art_staging/stag/build3/char_warden.blend} 2>&1 | grep -E "^CLR roar|Error|Trace|line " | cut -c1-1200
bash tools/creatures/stagborn/roar_review.sh "$(cygpath -m "$GLB")" "$1" ${2:-3}
