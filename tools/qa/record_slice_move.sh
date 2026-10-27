#!/bin/bash
# Records the benchmark-slice player route (tools_qa/acceptance/slice_move.gd) with Movie Maker and makes the review set:
#   tools/qa/record_slice_move.sh <tag>   -> $OUT/<tag>.avi, <tag>.mp4, <tag>_sheet.jpg (1 frame / 1.5 s), <tag>_diff.txt (frame-diff spikes)
set -u
TAG="${1:-before}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
FF="${FFMPEG:-/c/Users/Jonna/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0-full_build/bin/ffmpeg.exe}"
OUT="${OUT:-/tmp/slice_move}"
mkdir -p "$OUT"
cd "$REPO/kingdom"
PLAYTEST_MOVIE=1 PLAYTEST_MOVIE_FPS=30 PLAYTEST_STAGES=slice_move PLAYTEST_OUT="$(cygpath -m "$OUT")" PLAYTEST_SHOTS="$(cygpath -m "$OUT")/shots" \
  timeout 1800 "$G" --path . scenes/main.tscn --resolution 1280x720 --fixed-fps 30 --write-movie "$(cygpath -m "$OUT/$TAG.avi")" \
  -- --quality=low --adult ${WORLD_ARGS---terrain_backend=terrain3d --world_macro=real} --qa=res://tools_qa/playtest_bot/playtest_bot.gd > "$OUT/$TAG.out.txt" 2>&1
cp "$OUT/run.log" "$OUT/$TAG.run.log"
# skip the loading screen: start at the movie frame the route logged (SLICEFRAME)
FR=$(grep -m1 SLICEFRAME "$OUT/run.log" | sed -E 's/.*SLICEFRAME ([0-9]+).*/\1/')
SS=$(python -c "print(${FR:-0}/30.0)")
"$FF" -y -v error -ss "${SS:-0}" -i "$(cygpath -w "$OUT/$TAG.avi")" -c:v libx264 -preset slow -b:v 3500k -pix_fmt yuv420p -movflags +faststart "$(cygpath -w "$OUT/$TAG.mp4")"
"$FF" -y -v error -i "$(cygpath -w "$OUT/$TAG.mp4")" -vf "fps=2/3,scale=480:-1,tile=6x5" -frames:v 1 "$(cygpath -w "$OUT/${TAG}_sheet.jpg")"
# frame-diff spikes (pops / snaps): mean abs luma difference between consecutive frames, report those > 3x the median
( cd "$OUT" && "$FF" -v error -i "$TAG.mp4" -vf "format=gray,tblend=all_mode=difference,signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=${TAG}_diff_raw.txt" -f null - )
python - "$(cygpath -w "$OUT/${TAG}_diff_raw.txt")" "$(cygpath -w "$OUT/${TAG}_diff.txt")" <<'PY'
import sys,re,statistics
v=[float(m) for m in re.findall(r'YAVG=([0-9.]+)',open(sys.argv[1]).read())]
med=statistics.median(v) if v else 0
sp=[(i,x) for i,x in enumerate(v) if med>0 and x>3*med and x>2.0]
open(sys.argv[2],'w').write("frames %d median %.2f spikes %d\n"%(len(v),med,len(sp))+"".join("frame %d t=%.2fs diff %.1f\n"%(i,i/30,x) for i,x in sp))
print(open(sys.argv[2]).read()[:800])
PY
echo "$OUT/$TAG.mp4"
