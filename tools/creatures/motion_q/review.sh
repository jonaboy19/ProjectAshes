#!/usr/bin/env bash
# Render + tile review sheets for one creature straight from its exported GLB, then delete the frames.
# usage: review.sh <creature> <glb> <out_dir> [clips="idle walk run attack hit death"] [views="side front"]
# env: WALKV / RUNV = ground speed (m/s) for the treadmill (grid scrolls so planted feet stay on their cell)
#      WORK = scratch dir (default /c/Users/Jonna/mqw) ; W = tile width (default 320) ; COLS ROWS ; DIST
set -euo pipefail
cr=$1; glb=$2; out=$3; clips=${4:-"idle walk run attack hit death"}; views=${5:-"side front"}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
WORK=${WORK:-/c/Users/Jonna/mqw}; W=${W:-320}; COLS=${COLS:-5}; ROWS=${ROWS:-4}
case "$glb" in /*|[A-Za-z]:*) GLBABS="$glb";; *) GLBABS="$ROOT/$glb";; esac
mkdir -p "$out" "$WORK/fr_$cr" "$WORK/sh_$cr"
export RC_DIST=${DIST:-1.7}
step_for() { # clip view -> step
  case "$1" in idle) [ "$2" = side ] && echo 2 || echo 3;; *) echo 1;; esac; }
render() { # treadmill specs...
  local tm=$1; shift
  RC_TREADMILL=$tm timeout 590 "$B" -b --python "$ROOT/tools/creatures/motion_q/render_clip.py" -- "$GLBABS" "$WORK/fr_$cr" 480 "$@" 2>&1 | grep "FRAMES\|Error" || true
}
stat=(); loco=()
for c in $clips; do for v in $views; do
  s=$(step_for $c $v)
  case $c in walk) loco+=("$c:$v:$s");; run) loco+=("run:$v:$s");; *) stat+=("$c:$v:$s");; esac
done; done
[ ${#stat[@]} -gt 0 ] && render 0 "${stat[@]}"
for spec in "${loco[@]:-}"; do
  [ -z "$spec" ] && continue
  c=${spec%%:*}; tm=${WALKV:-0}; [ "$c" = run ] && tm=${RUNV:-0}
  render $tm "$spec"
done
for d in "$WORK/fr_$cr"/*/; do
  n=$(basename "$d"); clip=${n%_*}; view=${n##*_}
  s=$(step_for $clip $view); fps=$((30 / s))
  ww=$W; cc=$COLS; rr=$ROWS
  [ "$clip" = attack ] && { ww=${WA:-400}; cc=4; rr=3; }
  for f in "$d"frame*.png; do :; done
  rm -rf "$WORK/sh_$cr/$n"
  SRC_FPS=$fps bash "$ROOT/tools/qa/video_to_sheets.sh" "$d" "$WORK/sh_$cr/$n" $fps $cc $rr $ww > /dev/null
  i=0
  for p in "$WORK/sh_$cr/$n"/sheet_*.png; do i=$((i+1)); ffmpeg -v error -y -i "$p" -q:v 4 "$out/${n}_sheet_$i.jpg"; done
  echo "SHEETS $n step=$s -> $i sheets"
  rm -rf "$d" "$WORK/sh_$cr/$n"
done
