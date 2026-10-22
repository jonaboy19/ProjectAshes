#!/usr/bin/env bash
# usage: iterate.sh <creature> <clip> [step=2] -- authors from the repo LOD1 GLB into a temp GLB and renders sheets to docs/anim/creatures/<c>/wip
C=$1; K=$2; ST=${3:-2}
REPO=/c/Users/Jonna/Documents/PA_wt_creature; HERE=$REPO/tools/creatures/motion_b; T=/c/Users/Jonna/AppData/Local/Temp/cm/t
rm -f $REPO/docs/anim/creatures/$C/wip/${K}_*
"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python $HERE/make_attacks.py -- $C $REPO/kingdom/assets/incoming/ai3d/meshy/creatures/${C}_lod1.glb $T/${C}_lod1.glb $K 2>&1 | grep -E "AUTHORED|Error|Trace|line "
cd $T && RC_STEP=$ST COLS=4 ROWS=3 TW=300 RW=380 bash $HERE/render_all.sh $C $T/${C}_lod1.glb wip $K 2>&1 | grep -E "Error|Trace"
ls $REPO/docs/anim/creatures/$C/wip | grep "^${K}_sheet"
