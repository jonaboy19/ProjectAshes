#!/usr/bin/env bash
# Split a feel_capture Movie Maker recording into one contact-sheet set per scenario.
#
# Usage: tools/qa/feel_sheets.sh <capture_dir> <out_dir> [fps=15] [cols=5] [rows=4] [width=384]
#   <capture_dir> holds feel.avi (Movie Maker, --fixed-fps 30) and scenarios.txt
#   ("<scenario> <first_frame> <last_frame>" per line, written by tools_qa/feel_capture).
# Per scenario: <out_dir>/<scenario>/sheet_NNN.png + motion.png + info.txt, plus
# <out_dir>/<scenario>/clip.mp4 (the scenario cut, for sending to the owner).
# CROP=w:h:x:y crops before tiling (e.g. 480:420:400:220 frames the third-person body).
# FRAME_OFFSET (default 0) shifts every range if the overlay frame and the movie frame disagree.
set -euo pipefail
CAP=${1:?capture dir}; OUT=${2:?out dir}
FPS=${3:-15}; COLS=${4:-5}; ROWS=${5:-4}; W=${6:-384}
HERE="$(cd "$(dirname "$0")" && pwd)"
OFF=${FRAME_OFFSET:-0}
VID="$CAP/feel.avi"
[ -f "$VID" ] || { echo "no $VID"; exit 1; }
mkdir -p "$OUT"
while read -r name a b; do
  [ -z "${name:-}" ] && continue
  if [ -n "${ONLY:-}" ] && [[ "$name" != ${ONLY}* ]]; then continue; fi
  s=$(awk "BEGIN{printf \"%.4f\", ($a+$OFF)/30}")
  d=$(awk "BEGIN{printf \"%.4f\", ($b-$a)/30}")
  mkdir -p "$OUT/$name"
  VF=${CROP:+-vf crop=$CROP}
  ffmpeg -v error -y -ss "$s" -i "$VID" -t "$d" $VF -c:v libx264 -crf 20 -pix_fmt yuv420p -an "$OUT/$name/clip.mp4"
  bash "$HERE/video_to_sheets.sh" "$OUT/$name/clip.mp4" "$OUT/$name" "$FPS" "$COLS" "$ROWS" "$W" > /dev/null
  echo "$name: frames $a-$b ($d s) -> $(ls "$OUT/$name"/sheet_*.png | wc -l) sheets"
done < "$CAP/scenarios.txt"
