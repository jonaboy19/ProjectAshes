#!/bin/bash
# Analyse a Movie Maker QA recording: MP4 for the owner (H.264, < 30 MB), contact sheets (1 frame / 0.5 s, 6x5 = 15 s
# per sheet, timestamp burnt in) and scene-difference spikes (pops, LOD swaps, flicker, teleports).
#   tools/qa/video/analyse_tour.sh <movie.avi> <out_dir> [scene_threshold=0.12]
set -e
IN=$1; OUT=$2; TH=${3:-0.12}
mkdir -p "$OUT"
ffmpeg -loglevel error -y -i "$IN" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an "$OUT/tour.mp4"
ffmpeg -loglevel error -y -i "$IN" -vf "fps=2,scale=320:-1,drawtext=text='%{pts\:hms}':x=4:y=4:fontsize=14:fontcolor=yellow:box=1:boxcolor=black@0.6,tile=6x5" "$OUT/sheet_%03d.jpg"
ffmpeg -hide_banner -i "$IN" -vf "select='gt(scene,$TH)',metadata=print:file=$OUT/scene.txt" -an -f null - 2>/dev/null || true
grep -oE "pts_time:[0-9.]+|scene_score=[0-9.]+" "$OUT/scene.txt" | paste - - | sed 's/pts_time://;s/lavfi.scene_score=//;s/scene_score=//' > "$OUT/spikes.tsv" || true
ls -la "$OUT" | head; echo "spikes: $(wc -l < "$OUT/spikes.tsv")"
