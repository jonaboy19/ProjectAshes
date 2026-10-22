#!/usr/bin/env bash
# Downloads the raw CMU BVH takes used by cfg_loco.json into $LOCO_SRC/cmu (default ~/.cache/ashes_anim_src/loco).
# CMU Graphics Lab mocap (cgspeed BVH conversion, GitHub mirror una-dinosauria/cmu-mocap). Raw takes are NOT committed.
#   LOCO_SRC=... bash tools/anim/loco/fetch_loco_sources.sh
set -eu
LOCO_SRC="${LOCO_SRC:-$HOME/.cache/ashes_anim_src/loco}"
D="$LOCO_SRC/cmu"; mkdir -p "$D"; cd "$D"
base=https://raw.githubusercontent.com/una-dinosauria/cmu-mocap/master/data
get(){ f=$(printf "%02d_%02d.bvh" $((10#$1)) $((10#$2))); [ -f "$f" ] || curl -sfL -o "$f" "$base/$(printf %03d $((10#$1)))/$f" || echo "FAIL $f"; }
for n in 31 33 55; do get 16 $n; done; get 16 5; get 16 8; get 16 57
for n in 17 18 19 25 27; do get 127 $n; done
get 36 2; get 36 3; get 36 9; get 13 41; get 13 42; get 82 4
echo "done: $(ls | wc -l) files in $D"
