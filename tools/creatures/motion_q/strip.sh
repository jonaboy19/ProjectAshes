#!/usr/bin/env bash
# quick iteration strip: strip.sh <creature> <glb> <out.jpg> <clip> "<frames comma list>" [views="side front"] [cols=6]
# renders only the given clip frames from the GLB into one contact sheet (side row on top of front row)
set -euo pipefail
cr=$1; glb=$2; out=$3; clip=$4; frames=$5; views=${6:-"side front"}; cols=${7:-6}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
WORK=${WORK:-/c/Users/Jonna/mqw}; rm -rf "$WORK/st_$cr"; mkdir -p "$WORK/st_$cr"
export RC_DIST=${DIST:-1.7} RC_FRAMES=$frames
specs=(); for v in $views; do specs+=("$clip:$v:1"); done
timeout 590 "$B" -b --python "$ROOT/tools/creatures/motion_q/render_clip.py" -- "$glb" "$WORK/st_$cr" ${W:-360} "${specs[@]}" 2>&1 | grep "Error" || true
n=$(echo $frames | tr ',' '\n' | wc -l)
rows=(); for v in $views; do
  d="$WORK/st_$cr/${clip}_$v"; i=0
  for f in $(echo $frames | tr ',' ' '); do i=$((i+1)); ffmpeg -v error -y -i "$d/frame$(printf %08d $i).png" -vf "drawtext=text='$f':x=6:y=6:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=3:fontfile='C\:/Windows/Fonts/arial.ttf'" "$d/l$(printf %03d $i).png"; done
  ffmpeg -v error -y -framerate 1 -i "$d/l%03d.png" -vf "tile=${cols}x$(( (n + cols - 1) / cols )):padding=2:margin=2:color=0x202020" -frames:v 1 "$WORK/st_$cr/row_$v.png"
  rows+=("$WORK/st_$cr/row_$v.png")
done
if [ ${#rows[@]} -eq 1 ]; then ffmpeg -v error -y -i "${rows[0]}" -q:v 3 "$out"; else
  ffmpeg -v error -y $(for r in "${rows[@]}"; do echo -i $r; done) -filter_complex "vstack=inputs=${#rows[@]}" -q:v 3 "$out"; fi
rm -rf "$WORK/st_$cr"
