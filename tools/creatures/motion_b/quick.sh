#!/usr/bin/env bash
# usage: quick.sh <creature> <clip> -> author to temp GLB + print hand/hips heights every 3rd frame
C=$1; K=$2; REPO=/c/Users/Jonna/Documents/PA_wt_creature; HERE=$REPO/tools/creatures/motion_b; T=/c/Users/Jonna/AppData/Local/Temp/cm
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"; PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
"$BL" -b --python $HERE/make_attacks.py -- $C $REPO/kingdom/assets/incoming/ai3d/meshy/creatures/${C}_lod1.glb $T/t/${C}_lod1.glb $K 2>&1 | grep -E "AUTHORED|Error|Trace|line "
"$BL" -b --python $HERE/metrics.py -- $T/t/${C}_lod1.glb $T/${C}_wip.json 2>&1 | grep -E "^CLIP $K "
"$PY" $HERE/hands.py $T/${C}_wip.json $K ${3:-1} ${4:-0} ${5:-0}
