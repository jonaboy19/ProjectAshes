#!/usr/bin/env bash
# usage: sheet.sh <frames_dir> <out_dir> <src_fps> [fps=12 cols=4 rows=3 w=400]
d=$1; o=$2; sf=$3
for f in "$d"/frame_*.png; do [ -e "$f" ] || continue; n=${f##*frame_}; n=${n%.png}; mv "$f" "$d/frame$(printf %08d $((10#$n))).png"; done
cd /c/Users/Jonna/Documents/PA_wt_r1stag
SRC_FPS=$sf bash tools/qa/video_to_sheets.sh "$d" "$o" ${4:-12} ${5:-4} ${6:-3} ${7:-400}
