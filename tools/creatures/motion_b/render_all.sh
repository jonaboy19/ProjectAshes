#!/usr/bin/env bash
# usage: render_all.sh <creature> <glb> <tag> <docs_subdir_suffix> [clip ...]
# renders side+front at 30 fps (step 1 for <=46 frames else 2) FROM THE GLB, tiles, writes jpg sheets, deletes PNGs.
C=$1; GLB=$2; TAG=$3; shift 3
REPO=/c/Users/Jonna/Documents/PA_wt_creature; HERE=$REPO/tools/creatures/motion_b
TMP=/c/Users/Jonna/AppData/Local/Temp/cm/fr/${C}_$TAG; rm -rf $TMP; mkdir -p $TMP
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
OUTD=$REPO/docs/anim/creatures/$C/$TAG; mkdir -p $OUTD
CLIPS=${@:-idle walk run attack attack_charged slam hit death}
SP=(); for k in $CLIPS; do SP+=("$k:auto${TM_ARGS[$k]}"); done
timeout 580 "$BL" -b --python $HERE/render.py -- $GLB $TMP ${RW:-420} "${SP[@]}" 2>&1 | grep -E "FRAMES|Error|Traceback"
for k in $CLIPS; do [ -d $TMP/$k ] || continue; st=$(cat $TMP/$k/step.txt); sf=$((30/st))
  bash $HERE/sheets.sh $TMP $k $sf $OUTD/$k ${sf} ${COLS:-3} ${ROWS:-3} ${TW:-340} >/dev/null; done
ls $OUTD | head -80; rm -rf $TMP
