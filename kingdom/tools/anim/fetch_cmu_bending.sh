#!/usr/bin/env bash
# Re-fetch the 39 CMU BVH trials used by tools/anim/cfg_cmu_bending.json into
# kingdom/assets/incoming/mocap/cmu/_raw/<subject3>/<trial>.bvh (about 63 MB; local only, *.bvh is git-ignored there).
# Source: GitHub mirror of the cgspeed BVH conversion (CMU terms: free for commercial use, see the pack LICENSE).
#   bash tools/anim/fetch_cmu_bending.sh
# Then: python tools/anim/retarget_clips_to_ual.py tools/anim/cfg_cmu_bending.json   (bpy 5.0.1 wheel, python 3.11)
#       python tools/anim/glb_reduce_anim.py assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
RAW="$HERE/../../assets/incoming/mocap/cmu/_raw"
TMP="${TMPDIR:-/tmp}/cmu_bending_fetch"
rm -rf "$TMP"; mkdir -p "$TMP" "$RAW"
git clone --depth 1 --filter=blob:none --no-checkout https://github.com/una-dinosauria/cmu-mocap "$TMP"
TRIALS="05_03 05_04 13_17 13_26 14_02 17_10 49_09 49_12 49_18 49_21 55_01 75_08 76_01 76_02 76_04 78_13 78_18 78_19 81_05 81_07 82_06 86_01 86_06 88_04 88_06 90_07 141_06 141_14 143_23 144_03 144_11 144_13 144_15 144_17 144_20 144_22 144_24 144_28 144_31"
FILES=""
for t in $TRIALS; do s="${t%%_*}"; FILES="$FILES data/$(printf '%03d' $((10#$s)))/$t.bvh"; done
(cd "$TMP" && git checkout HEAD -- READMEFIRST.txt $FILES)
for t in $TRIALS; do s="${t%%_*}"; d="$(printf '%03d' $((10#$s)))"; mkdir -p "$RAW/$d"; cp "$TMP/data/$d/$t.bvh" "$RAW/$d/"; done
cp "$TMP/READMEFIRST.txt" "$RAW/"
rm -rf "$TMP"
echo "fetched into $RAW"
