#!/usr/bin/env bash
# usage: compare_attack.sh <creature> <clip> [step=3] [cols=8]
# Side-view strips of the ORIGINAL (git HEAD) and the NEW clip, stacked: docs/anim/creatures/<c>/compare_<clip>.jpg
C=$1; K=$2; ST=${3:-3}; COLS=${4:-8}
REPO=/c/Users/Jonna/Documents/PA_wt_creature; HERE=$REPO/tools/creatures/motion_b; T=/c/Users/Jonna/AppData/Local/Temp/cm
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"; D=$REPO/kingdom/assets/incoming/ai3d/meshy/creatures
W=/c/Users/Jonna/AppData/Local/Temp/cm/cmp_${C}_$K; rm -rf $W; mkdir -p $W
FONT="fontfile='C\:/Windows/Fonts/arial.ttf'"
for tag in before after; do
  G=$T/orig/$C.glb; [ $tag = after ] && G=$D/$C.glb
  RC_STEP=$ST timeout 500 "$BL" -b --python $HERE/render.py -- $G $W/$tag 300 $K:$ST 2>&1 | grep -E "Error|Trace"
  NF=$(ls $W/$tag/$K/side/frame*.png | wc -l); ROWS=$(( (NF + COLS - 1) / COLS ))
  ffmpeg -v error -y -framerate 30 -i $W/$tag/$K/side/frame%08d.png -vf "scale=300:-2,drawtext=text='${tag} %{eif\:(n*$ST/30*1000)\:d}ms':x=4:y=4:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6:$FONT,tile=${COLS}x${ROWS}:padding=2:color=0x202020" -frames:v 1 $W/$tag.png
done
ffmpeg -v error -y -i $W/before.png -i $W/after.png -filter_complex "[0][1]vstack=inputs=2" -q:v 4 $REPO/docs/anim/creatures/$C/compare_$K.jpg
rm -rf $W; ls -la $REPO/docs/anim/creatures/$C/compare_$K.jpg
