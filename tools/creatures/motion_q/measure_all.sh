#!/usr/bin/env bash
# before/after numeric measurement. usage: measure_all.sh <orig_dir> <out_dir>   (orig_dir holds the pre-fix GLBs)
ROOT=$(cd "$(dirname "$0")/../../.." && pwd); B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
O=$1; M=$2; mkdir -p "$M"; PY="$ROOT/tools/creatures/motion_q"
cur() { case $1 in boar) echo "0.45,2.7";; bear) echo "1.35,4.0";; spider) echo "0.26";; esac; }
fix() { case $1 in boar) echo "0.455,1.95";; bear) echo "1.4,4.05";; spider) echo "0.40";; esac; }
for c in boar bear spider; do
  clips="idle walk run"; [ $c = spider ] && clips="idle walk"
  MQ_SPEEDS=$(cur $c) timeout 500 "$B" -b --python $PY/analyze_feet.py -- $c $O/$c.glb $M/feet_${c}_before.json $clips 2>&1 | grep "CLIP\|slip@" > $M/feet_${c}_before.txt
  MQ_SPEEDS=$(fix $c) timeout 500 "$B" -b --python $PY/analyze_feet.py -- $c - $M/feet_${c}_after.json $clips 2>&1 | grep "CLIP\|slip@" > $M/feet_${c}_after.txt
done
