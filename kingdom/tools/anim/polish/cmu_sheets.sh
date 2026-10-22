#!/usr/bin/env bash
# usage: cmu_sheets.sh <render_dir> <out_root> <k> <cols> <rows> [clip ...]
# Like make_sheets.sh but keeps every k-th rendered frame (render at 12 fps, k=2 -> 6 fps contact sheets for the long get-ups), keeps the raw
# frames (writes a subsampled copy in <render_dir>/../_sub), and quantises the tiled sheets to 32 colours (PNG, ~3x smaller, still readable).
set -euo pipefail
R=${1:?render dir}; O=${2:?out root}; K=${3:?k}; COLS=${4:?cols}; ROWS=${5:?rows}; shift 5
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$HERE/../../../../tools/qa/video_to_sheets.sh"
BASEFPS=$(grep -m1 sheet_fps "$R/metrics.json" | tr -dc '0-9.' ); BASEFPS=${BASEFPS%.}
FPS=$(awk -v a="${BASEFPS}" -v k="$K" 'BEGIN{printf "%g", a/k}')
CLIPS=("$@"); [ ${#CLIPS[@]} -eq 0 ] && CLIPS=($(ls -d "$R"/*/ | xargs -n1 basename))
for c in "${CLIPS[@]}"; do
  d="$R/$c/_v"; [ -d "$d" ] || { echo "no frames $c"; continue; }
  T=$(mktemp -d); mkdir -p "$T/s" "$T/f" "$T/hs"
  i=0; for f in $(ls "$d"/s*.png | awk -v k="$K" 'NR%k==1||k==1'); do n=$(printf "%08d" $i); cp "$f" "$T/s/s$n.png"; cp "$d/f${f##*/s}" "$T/f/f$n.png"; i=$((i+1)); done
  ffmpeg -v error -y -framerate "$FPS" -i "$T/s/s%08d.png" -framerate "$FPS" -i "$T/f/f%08d.png" -filter_complex hstack "$T/hs/frame%08d.png"
  SRC_FPS=$FPS bash "$Q" "$T/hs" "$O/$c" "$FPS" "$COLS" "$ROWS" 480 >/dev/null
  rm -f "$O/$c/motion.png" "$O/$c/info.txt"
  for s in "$O/$c"/sheet_*.png; do
    ffmpeg -v error -y -i "$s" -vf "split[a][b];[a]palettegen=max_colors=32:stats_mode=full[p];[b][p]paletteuse=dither=none" "$s.q.png" && mv "$s.q.png" "$s"
  done
  rm -rf "$T"
  echo "sheets $c fps=$FPS: $(ls "$O/$c"/sheet_*.png | wc -l)"
done
