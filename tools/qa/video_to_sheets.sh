#!/usr/bin/env bash
# Turn a video (or a PNG frame sequence) into "stop-motion" contact sheets that
# Claude can read as images: numbered frames with timestamps, in tiles, in order.
#
# Usage:
#   tools/qa/video_to_sheets.sh <video|frames_dir> <out_dir> [fps=6] [cols=4] [rows=3] [width=480]
# Examples:
#   tools/qa/video_to_sheets.sh intro.mp4 docs/qa/video/intro 8
#   tools/qa/video_to_sheets.sh /tmp/movie_frames docs/qa/video/combo 12 4 3 400
#
# Output:
#   <out_dir>/sheet_001.png ...   COLSxROWS frames each, labelled with frame# and time
#   <out_dir>/motion.png          a strip of frame differences (bright = movement; shows pops/jitter/frozen parts)
#   <out_dir>/info.txt            source, duration, fps used, frames per sheet, time covered per sheet
set -euo pipefail
SRC=${1:?video or frames dir}; OUT=${2:?out dir}
FPS=${3:-6}; COLS=${4:-4}; ROWS=${5:-3}; W=${6:-480}
mkdir -p "$OUT"; rm -f "$OUT"/sheet_*.png "$OUT"/motion.png

if [ -d "$SRC" ]; then
  # PNG sequence (e.g. Godot --write-movie out.png). Assume it was captured at 30 fps unless SRC_FPS is set.
  first=$(ls "$SRC"/*.png | head -1); base=${first%[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9].png}
  IN=(-framerate "${SRC_FPS:-30}" -i "${base}%08d.png")
else
  IN=(-i "$SRC")
fi

N=$((COLS*ROWS))
LABEL="drawtext=text='#%{n}  %{pts\:hms}':x=6:y=6:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=4"
# The font path is needed on Windows builds without fontconfig.
FONT="C\\:/Windows/Fonts/arial.ttf"
[ -f /c/Windows/Fonts/arial.ttf ] && LABEL="$LABEL:fontfile='$FONT'"

ffmpeg -v error -y "${IN[@]}" \
  -vf "fps=$FPS,scale=$W:-2,setpts=N/($FPS*TB),$LABEL,tile=${COLS}x${ROWS}:padding=4:margin=4:color=0x202020" \
  "$OUT/sheet_%03d.png"

# Motion strip: absolute difference between consecutive frames, one row.
ffmpeg -v error -y "${IN[@]}" \
  -vf "fps=$FPS,scale=240:-2,format=gray,tblend=all_mode=difference,eq=brightness=0.05:contrast=4,tile=${COLS}x${ROWS}:padding=2" \
  -frames:v 1 "$OUT/motion.png" || true

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${IN[@]: -1}" 2>/dev/null || echo "?")
{
  echo "source: $SRC"; echo "duration_s: $DUR"; echo "sample_fps: $FPS"
  echo "frames_per_sheet: $N  (= $(awk "BEGIN{print $N/$FPS}") s per sheet)"
  echo "sheets: $(ls "$OUT"/sheet_*.png | wc -l)"
} > "$OUT/info.txt"
cat "$OUT/info.txt"
