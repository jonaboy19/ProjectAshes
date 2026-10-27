#!/bin/bash
# Benchmark slice recording (video QA lane): the same route after every push.
#   tools/qa/video/record_slice.sh [label] [--quality=low|high]
# -> C:/Users/Jonna/Documents/PA_plans/videos/slice_<date>_<sha>[_label].mp4 + .txt (config dump: SLICECFG lines, segments)
#    docs/qa/video/slice/<sha>[_label]/sheet_*.jpg + spikes.tsv
set -u
R=/c/Users/Jonna/Documents/PA_wt_w3; cd $R/kingdom
G=${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64.exe}
LABEL=${1:-}; Q=${2:---quality=low}
SHA=$(git -C $R rev-parse --short HEAD); D=$(date +%Y-%m-%d_%H%M)
NAME="slice_${D}_${SHA}${LABEL:+_$LABEL}"
TMP="$TEMP/slice_rec/$NAME"; mkdir -p "$TMP"
OUTV=/c/Users/Jonna/Documents/PA_plans/videos; mkdir -p "$OUTV"
git -C $R status --porcelain | sort > "$TMP/s1.txt"
PLAYTEST_MOVIE=1 PLAYTEST_MOVIE_FPS=30 PLAYTEST_STAGES=boot,slice_route PLAYTEST_OUT="$(cygpath -m "$TMP/bot")" \
  timeout 2400 "$G" --path . scenes/main.tscn --resolution 1280x720 --fixed-fps 30 --write-movie "$(cygpath -m "$TMP/slice.avi")" \
  -- $Q --adult --qa=res://tools_qa/playtest_bot/playtest_bot.gd > "$TMP/log.txt" 2>&1
git -C $R status --porcelain | sort > "$TMP/s2.txt"; comm -13 "$TMP/s1.txt" "$TMP/s2.txt" | grep '^ M .*\.import$' | cut -c4- | xargs -r -d '\n' git -C $R checkout --
{ echo "commit $SHA ($(git -C $R log -1 --format=%s | cut -c1-90))"; echo "args: $Q --adult (PLAYTEST_STAGES=boot,slice_route)"; grep -hoE "SLICECFG .*|SLICESEG .*" "$TMP/log.txt" "$TMP"/bot/*.log 2>/dev/null | sort -u; } > "$OUTV/$NAME.txt"
bash $R/tools/qa/video/analyse_tour.sh "$TMP/slice.avi" "$TMP/an" 0.12 > /dev/null 2>&1
cp "$TMP/an/tour.mp4" "$OUTV/$NAME.mp4" 2>/dev/null
mkdir -p "$R/docs/qa/video/slice/$NAME"; cp "$TMP"/an/sheet_*.jpg "$TMP/an/spikes.tsv" "$R/docs/qa/video/slice/$NAME/" 2>/dev/null
# disk is tight: keep only the MP4, the sheets and the sidecar
[ -s "$OUTV/$NAME.mp4" ] && rm -f "$TMP/slice.avi" "$TMP/an/tour.mp4"
echo "RECORDED $OUTV/$NAME.mp4 $(ls -la "$OUTV/$NAME.mp4" 2>/dev/null | awk '{print $5}') sheets=$(ls "$R/docs/qa/video/slice/$NAME" | wc -l) crash=$(grep -c CrashHandler "$TMP/log.txt")"
