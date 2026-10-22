#!/usr/bin/env bash
# Build the LIFE work clip library (farm, craft, chores) and reduce the keys.
#   bash build_work.sh [clip,clip,...]      (no arg = all clips)
set -e
cd "$(dirname "$0")"
OUT=../../../assets/incoming/animations/life/UAL_Life_Work.glb
MODS=life_clips_farm,life_clips_craft,life_clips_chores
ls life_clips_craft.py life_clips_chores.py >/dev/null 2>&1 || MODS=$(ls life_clips_*.py | grep -E 'farm|craft|chores' | sed 's/\.py//' | paste -sd,)
timeout 900 "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b -P author_life.py -- "$OUT" "$MODS" ${1:+"$1"}
py ../glb_reduce_anim.py "$OUT" --rot-deg 0.25 --pos-m 0.001
