#!/usr/bin/env bash
# usage: make_sheets.sh <render_dir> <sheet_root> [cols=3] [rows=4]
# For every <render_dir>/<clip>/_v (side s########.png + front f########.png) stack the two views, tile them into
# contact sheets with tools/qa/video_to_sheets.sh (width 480 per tile) into <sheet_root>/<clip>/, delete the raw frames.
# The sample fps is read from <render_dir>/metrics.json (sheet_fps) unless SHEET_FPS is set.
set -euo pipefail
R=${1:?render dir}; O=${2:?sheet root}; COLS=${3:-3}; ROWS=${4:-4}
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$HERE/../../../../tools/qa/video_to_sheets.sh"
for d in "$R"/*/; do
  c=$(basename "$d"); [ -d "$d/_v" ] || continue
  fps=$(grep -A40 "\"$c\"" "$R/metrics.json" | grep -m1 sheet_fps | tr -dc '0-9.')
  fps=${SHEET_FPS:-$fps}
  mkdir -p "$d/hs"
  ffmpeg -v error -y -framerate "$fps" -i "$d/_v/s%08d.png" -framerate "$fps" -i "$d/_v/f%08d.png" -filter_complex hstack "$d/hs/frame%08d.png"
  SRC_FPS=$fps bash "$Q" "$d/hs" "$O/$c" "$fps" "$COLS" "$ROWS" 480 >/dev/null
  rm -rf "$d/_v" "$d/hs"
  echo "sheets $c fps=$fps: $(ls "$O/$c"/sheet_*.png | wc -l)"
done
