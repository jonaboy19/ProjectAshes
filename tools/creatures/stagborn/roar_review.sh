#!/usr/bin/env bash
# Render the Warden roar (side + front 3/4) from a GLB and tile stop-motion sheets.
# usage: roar_review.sh <glb> <out_dir> [sample_step=2]
GLB=$1; OUT=$2; ST=${3:-2}
export PATH="$PATH:/c/Users/Jonna/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0-full_build/bin"
B="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"; HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$HERE/../../.." && pwd)
FR=$(mktemp -d); export RC_DIST=2.9
"$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR/side" 480 roar:side:$ST | grep FRAMES
"$B" -b --python "$HERE/render_clip.py" -- "$GLB" "$FR/front" 480 roar:front:$ST | grep FRAMES
cd "$ROOT"; mkdir -p "$OUT"
for v in side front; do SRC_FPS=$((30/ST)) bash tools/qa/video_to_sheets.sh "$FR/$v/roar" "$OUT/$v" $((30/ST)) 4 3 480 | tail -1; done
rm -rf "$FR"
