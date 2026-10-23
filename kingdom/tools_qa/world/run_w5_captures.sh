#!/bin/bash
# W5 capture driver: runs tools_qa/region1/look_capture.gd over a views JSON in batches, restarting after a crash and skipping views that
# keep crashing. Resumes where it left off (a view is done when <out>/<name>.png exists).
#   bash kingdom/tools_qa/world/run_w5_captures.sh <views.json (res:// relative to kingdom)> <abs out dir> [batch=12]
export MSYS_NO_PATHCONV=1
G="${GODOT:-C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
VIEWS="$1"; OUT="$2"; BATCH="${3:-12}"
mkdir -p "$OUT"
cd "$(dirname "$0")/../.."          # kingdom/
fails=0
while true; do
  missing=$(py -E -B -c "
import json,os,sys
vs=[v['name'] for v in json.load(open('$VIEWS'.replace('res://','')))['views']]
skip=set(open('$OUT/skipped.txt').read().split()) if os.path.exists('$OUT/skipped.txt') else set()
print(','.join([n for n in vs if not os.path.exists('$OUT/'+n+'.png') and n not in skip][:$BATCH]))")
  [ -z "$missing" ] && break
  before=$(ls "$OUT"/*.png 2>/dev/null | wc -l)
  echo "[driver] batch: $missing"
  timeout 3000 "$G" --path . --resolution 1920x1080 -s res://tools_qa/region1/look_capture.gd -- --adult --views=res://$VIEWS --out="$OUT" --only="$missing" --budget=2900 --profile=pc --quality=high --terrain_backend=terrain3d --world_macro=valencious $EXTRA > "$OUT/run_$(date +%H%M%S).log" 2>&1
  after=$(ls "$OUT"/*.png 2>/dev/null | wc -l)
  if [ "$after" -le "$before" ]; then
    fails=$((fails+1))
    if [ $fails -ge 2 ]; then first=${missing%%,*}; echo "$first" >> "$OUT/skipped.txt"; echo "[driver] skipping $first"; fails=0; fi
  else fails=0; fi
done
echo "[driver] done"
