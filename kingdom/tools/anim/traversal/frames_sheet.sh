#!/usr/bin/env bash
# usage: frames_sheet.sh <clip/_v dir> <out.jpg> <cols> <f1,f2,...> [tile_width=480] [label]
# Stacks side (s) + front (f) view of each listed source frame, labels it "#frame", tiles the frames (row-major) into one jpg.
set -euo pipefail
D=${1:?dir}; OUT=${2:?out}; COLS=${3:?cols}; LIST=${4:?frames}; W=${5:-480}; LAB=${6:-}
FONT="C\:/Windows/Fonts/arial.ttf"
T=$(mktemp -d); IFS=',' read -ra FR <<< "$LIST"; n=0
for f in "${FR[@]}"; do
  p=$(printf "%08d" "$f")
  ffmpeg -v error -y -i "$D/s$p.png" -i "$D/f$p.png" -filter_complex "hstack,scale=$W:-2,drawtext=text='$LAB #$f  t=$(awk "BEGIN{printf \"%.2f\",$f/30}")s':x=6:y=6:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=4:fontfile='$FONT'" "$T/$(printf %04d $n).png"
  n=$((n+1))
done
rows=$(( (n + COLS - 1) / COLS ))
ffmpeg -v error -y -framerate 1 -i "$T/%04d.png" -vf "tile=${COLS}x${rows}:padding=4:margin=4:color=0x202020" -frames:v 1 -q:v 4 "$OUT"
rm -rf "$T"; ls -la "$OUT" | awk '{print $5, $9}'
