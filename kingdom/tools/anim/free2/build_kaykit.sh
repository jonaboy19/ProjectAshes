#!/bin/bash
# Rebuild the KayKit (CC0) clip libraries retargeted to UAL. Needs Blender 5.2 + python (numpy).
# 1. python make_kaykit_cfgs.py ; 2. blender -b -P ../kaykit_make_blend.py -- <Rig_Medium dir> $ANIM_SRC2/kaykit_medium.blend $ANIM_SRC2/kaykit_medium_info.json
BL="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
PY="${PYTHON:-python}"
cd "$(dirname "$0")"
for c in life_sim combat_reactions movement_ext ranged undead; do
  "$BL" -b -P retarget_free2.py -- cfg_kk_$c.json | grep -E "EXPORTED|Traceback|Error"
  "$PY" ../glb_reduce_anim.py ../../../assets/incoming/animations_free2/kaykit_$c/UAL_Kay_$c.glb
done
