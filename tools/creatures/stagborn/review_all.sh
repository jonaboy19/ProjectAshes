#!/usr/bin/env bash
# Re-render EVERY clip of a Stagborn GLB and tile stop-motion sheets (read them!).
# usage: review_all.sh <elk|warden> <glb> <out_root> [walk_mps run_mps charge_mps]
# Ground grid scrolls at the gait speed (treadmill) so a planted hoof stays on its grid cell.
V=$1; GLB=$2; OUT=$3; WM=${4:-1.22}; RM=${5:-5.2}; CM=${6:-5.0}
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../../.." && pwd)
FR=$OUT/_frames; rm -rf "$FR"; mkdir -p "$FR"
STATIC="idle:side:3 idle_alt:side:3 graze:side:10 attack:three:1 attack_butt:side:1 hit:three:1 death:three:1"
[ "$V" = warden ] && STATIC="$STATIC kick:side:1 roar:side:1"
export RC_DIST=2.5
RC_TREADMILL=0 "$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR" 480 $STATIC | grep FRAMES
RC_TREADMILL=$WM "$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR" 480 walk:side:1 | grep FRAMES
RC_TREADMILL=$RM "$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR" 480 run:side:1 | grep FRAMES
RC_TREADMILL=$CM "$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR" 480 run_charge:three:1 | grep FRAMES
cd "$ROOT"
for d in "$FR"/*/; do
  c=$(basename "$d"); case $c in idle|idle_alt) src=10; f=10;; graze) src=3; f=3;; *) src=30; f=15;; esac
  SRC_FPS=$src bash tools/qa/video_to_sheets.sh "$d" "$OUT/stagborn_${V}_$c" $f 4 3 480 | tail -1
done
rm -rf "$FR"
