#!/usr/bin/env bash
# Perf round 3: draw calls (world viewport) for the heavy Region 1 views, LOW (and optionally HIGH) tier, Mobile renderer.
#   TAG=before TIERS="low" bash tools/qa/bench/perf_round3.sh
# Appends one JSON line per view to docs/qa/qa3/perf/round3_<TAG>.jsonl. Check the machine load first (other Godot runs skew ms, not draws).
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
SCRIPT="$(cygpath -m "$REPO/tools/qa/bench/bench.gd")"
OUT="$(cygpath -m "$REPO/docs/qa/qa3/perf/round3_${TAG:-run}.jsonl")"
mkdir -p "$(dirname "$OUT")"
# label|scene|extra args
VIEWS=(
 "city_gate|city|"
 "village_plaza|village|"
 "thornfield_landmark|pos|--at=1336,-197 --look=1306,-211"
 "kingsreach_landmark|pos|--at=358.2,-320 --look=323.5,-322"
 "redwater_landmark|pos|--at=847.9,-1211.8 --look=838,-1181.8"
 "vale_stone_gap|pos|--at=-118,-668 --look=-205,-860 --pitch=0.15"
 "vale_mouth_up|pos|--at=-306,-300 --look=-205,-700 --pitch=0.05"
 "vale_ruins|pos|--at=-205,-470 --look=-120,-480 --pitch=0.0"
)
for t in ${TIERS:-low}; do
  for v in "${VIEWS[@]}"; do
    IFS='|' read -r label scene extra <<< "$v"
    [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $label "* ]] && continue
    echo "== $t / $label"
    timeout 420 "$GODOT" --path "$REPO/kingdom" --rendering-method mobile -s "$SCRIPT" -- --adult --skipintro --quality="$t" --scene="$scene" $extra \
      --label="$label" --settle="${SETTLE:-15}" --seconds="${SECONDS_RUN:-6}" --uncapped --csv="$OUT" ${CENSUS:+--drawcensus --census_n=60} 2>&1 | grep -a "^BENCH\|^DRAWS" | sed -E 's/(BENCH .*"world_draws":[0-9.]+).*/\1/' | cut -c1-200
  done
done
