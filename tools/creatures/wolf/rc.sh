#!/usr/bin/env bash
# usage: rc.sh <glb> <clip> <view side|front|three|back> <step> [treadmill m/s] [out_root=/tmp/wolfwork/fr] [res=640]
# renders frames of one clip from the GLB, tiles contact sheets into <out_root>/<clip>_<view>/ (sheet_001.png ...)
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"; cd "$(dirname "$0")"
glb=$1; clip=$2; view=$3; step=$4; tm=${5:-0}; root=${6:-/tmp/wolfwork/fr}; res=${7:-640}
rm -rf "$root/${clip}_${view}" "$root/${clip}"; mkdir -p "$root"
RC_ROOT=${RC_ROOT:-} RC_TREADMILL=$tm timeout 600 "$B" -b --python render_clip.py -- "$glb" "$root" $res "$clip:$view:$step" 2>&1 | grep -E "FRAMES|Error|Traceback|line "
mv "$root/$clip" "$root/${clip}_${view}"
fps=$((30 / step))
bash sheet.sh "$root/${clip}_${view}" "$root/${clip}_${view}_sheets" $fps $fps ${8:-4} ${9:-3} 400 | tail -3
