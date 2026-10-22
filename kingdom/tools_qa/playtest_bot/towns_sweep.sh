#!/bin/bash
# Visual-bug sweep of the kit towns: one arrival view + one street view per town through the real main scene (xvfb, LOW tier).
#   tools_qa/playtest_bot/towns_sweep.sh <out-dir> [town,town,...|all] [batch=2]   (a second run fills the towns a first run lost)
# A main-scene run grows about 2.5 GB per town visited (RSS 14 GB after four), so the towns go through in batches of `batch` (2; 1 for the biggest: highcliff, kingsreach, ironmarch, longmeadow), one Godot
# process each (run_playtest.sh gates every start on free memory). Result: <out-dir>/<town>_arrive.png, <town>_street.png and
# <out-dir>/sweep.json (people / stacked / in_wall / plates / draws per view). Delete the pngs you do not keep: disk is tight.
OUT="${1:?out dir}"
WHICH="${2:-all}"
BATCH="${3:-2}"
KINGDOM="$(cd "$(dirname "$0")/../.." && pwd)"
mkdir -p "$OUT"
if [ "$WHICH" = "all" ]; then
  TOWNS=$(ls "$KINGDOM"/data/region1/towns/*.json | xargs -n1 basename | sed 's/\.json$//' | tr '\n' ' ')
else
  TOWNS=$(echo "$WHICH" | tr ',' ' ')
fi
# towns that already have both views in <out-dir> are skipped, so a second run only fills the gaps (a heavy town can be OOM-killed in a batch)
TODO=""
for t in $TOWNS; do
  if [ ! -f "$OUT/${t}_arrive.png" ] || [ ! -f "$OUT/${t}_street.png" ]; then TODO="$TODO $t"; fi
done
set -- $TODO
while [ $# -gt 0 ]; do
  B=""; n=0
  while [ $n -lt "$BATCH" ] && [ $# -gt 0 ]; do B="$B,$1"; shift; n=$((n+1)); done
  B="${B#,}"
  T="$OUT/.batch"; rm -rf "$T"; mkdir -p "$T/shots" "$T/out"
  echo "== batch $B"
  PLAYTEST_TOWNS="$B" PLAYTEST_OUT="$T/out" PLAYTEST_SHOTS="$T/shots" PLAYTEST_SHEET="$T/sheet.png" PLAYTEST_ARGS="--adult" PLAYTEST_TIMEOUT=1500 \
    "$KINGDOM/tools_qa/playtest_bot/run_playtest.sh" boot,townsweep > "$T/run.out" 2>&1
  for f in "$T"/shots/*_townsweep_*.png; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .png); mv "$f" "$OUT/$(echo "$b" | sed 's/^[0-9]*_townsweep_//').png"
  done
  cp "$T"/out/townsweep_*.json "$OUT/" 2>/dev/null
  cp "$T/out/run.log" "$OUT/run_$(echo "$B" | cut -d, -f1).log" 2>/dev/null
  grep -c "godot exit 137" "$T/run.out" | sed 's/^/oom retries: /'
done
rm -rf "$OUT/.batch"
python3 - "$OUT" <<'PY'
import json, glob, sys
out = {}
for f in sorted(glob.glob(sys.argv[1] + "/townsweep_*.json")):
    out.update(json.load(open(f)))
json.dump(out, open(sys.argv[1] + "/sweep.json", "w"), indent=1)
print("sweep.json:", len(out), "towns")
PY
