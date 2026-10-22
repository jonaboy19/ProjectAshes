#!/usr/bin/env bash
# Fetch the raw CMU BVH takes used by cfg_life_cmu.json into $ANIM_SRC/cmu-mocap/data (default ~/.cache/ashes_anim_src).
# (curl of single raw files; no git needed)
# Source: github.com/una-dinosauria/cmu-mocap (cgspeed BVH conversion of the CMU Graphics Lab mocap DB; free for commercial use).
# Raw takes are NOT committed.   usage: bash fetch_life_cmu.sh [extra takes like 79_01 ...]
set -eu
SRC="${ANIM_SRC:-$HOME/.cache/ashes_anim_src}"
REPO="$SRC/cmu-mocap"
base=https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data
TAKES="14_31 70_05 79_70 14_24 56_06 91_09 137_16 91_16 77_19 137_33 91_13 104_11 91_21 91_22 91_18 138_01 91_33 79_01 79_04 79_87 79_26 79_55 62_03 62_07 79_13 79_09 70_03 79_25 69_70 80_06 79_16 79_12 79_42 79_33 79_38 79_17 79_34 141_17 13_01 18_01 19_01 18_08 19_08 18_10 19_10 22_03 23_03 13_14 13_27 139_25 79_72 79_71 79_69 80_14 141_16 79_68 141_13 139_01 139_02 75_13 20_13 56_03 $*"
for t in $TAKES; do
  s=${t%_*}; n=${t#*_}; d=$(printf %03d $((10#$s))); f=$(printf "%02d_%02d.bvh" $((10#$s)) $((10#$n)))
  mkdir -p "$SRC/cmu-mocap/data/$d"
  [ -s "$SRC/cmu-mocap/data/$d/$f" ] || curl -sfL -o "$SRC/cmu-mocap/data/$d/$f" "$base/$d/$f" || { rm -f "$SRC/cmu-mocap/data/$d/$f"; echo "FAIL $f"; }
done
echo done
