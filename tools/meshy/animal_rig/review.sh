#!/usr/bin/env bash
# review.sh <rigged.glb> <animal> <clip> <speed_mps> <view 3q|side|front> [step=2] [size=360]
# renders a clip and builds frame sheets in docs/art/meshy_free/rigged/<animal>_<clip>[_view]
set -e
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
R=$(cd "$(dirname "$0")/../../.." && pwd)
GLB=$1; A=$2; C=$3; SP=$4; V=$5; ST=${6:-2}; SZ=${7:-360}
TMP=${TMPDIR:-/c/tmp_pa}/fr/${A}_${C}_${V}
"$B" -b --python "$R/tools/meshy/animal_rig/render_clip.py" -- "$GLB" "$TMP" "$C" "$SP" "$V" "$SZ" "$ST" 2>&1 | grep -E "RENDERED|Error|Traceback"
OUT="$R/docs/art/meshy_free/rigged/${A}_${C}"
[ "$V" = "3q" ] || OUT="${OUT}_${V}"
SRC_FPS=$((30/ST)) bash "$R/tools/qa/video_to_sheets.sh" "$TMP" "$OUT" $((30/ST)) 4 3 $SZ | tail -2
rm -rf "$TMP"
