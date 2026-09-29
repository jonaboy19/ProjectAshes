#!/usr/bin/env bash
# Copy contact sheets into docs/anim/free_library/frames/polish/acrobatics/<clip>/ as small palette PNGs (32 colours, no dither, ~0.3 MB each).
# usage: cmu_acro_sheets.sh <src_sheet.png> <dst.png>
set -euo pipefail
S=${1:?src}; D=${2:?dst}
mkdir -p "$(dirname "$D")"
P="$(mktemp -u).png"
ffmpeg -v error -y -i "$S" -vf "palettegen=max_colors=32:stats_mode=full" "$P"
ffmpeg -v error -y -i "$S" -i "$P" -lavfi "paletteuse=dither=none" "$D"
rm -f "$P"
