#!/usr/bin/env bash
# Rebuild the farm animal GLBs in place (run from the repo root). Needs Blender 5.2. ~30 s per animal.
# usage: bash kingdom/tools/anim/farm/build_all.sh [outdir]   (default: kingdom/assets/incoming/meshy_free/farm/rigged)
set -e
B="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
F=kingdom/assets/incoming/meshy_free/farm
O=${1:-$F/rigged}
T=kingdom/tools/anim/farm
mkdir -p "$O"
"$B" -b --python $T/rig_cow.py -- $F/cow_spotted_lod0.glb "$O/cow_spotted_rigged.glb" | grep -E "GRAZE|RIGGED"
"$B" -b --python $T/rig_cow.py -- $F/cows_pair_lod0.glb "$O/cow_brown_a_rigged.glb" 0 | grep -E "GRAZE|RIGGED"
"$B" -b --python $T/rig_cow.py -- $F/cows_pair_lod0.glb "$O/cow_brown_b_rigged.glb" 1 | grep -E "GRAZE|RIGGED"
"$B" -b --python $T/rig_chicken.py -- $F/chicken_hen_lod0.glb "$O/chicken_hen_rigged.glb" | grep -E "RIGGED"
"$B" -b --python $T/rig_chicken.py -- $F/chicken_rooster_lod0.glb "$O/chicken_rooster_rigged.glb" | grep -E "RIGGED"
