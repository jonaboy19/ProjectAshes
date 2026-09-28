#!/usr/bin/env bash
# Rising Ashes frame-time benchmark matrix (real GPU window, ~90 s per run).
#   bash tools/qa/bench/run.sh                         # LOW+HIGH x Mobile+Compatibility x village/city/battle
#   TIERS="low medium high ultra" RENDERERS="forward_plus" SCENES=village bash tools/qa/bench/run.sh
# Results: one JSON line per run in docs/qa/bench_results.jsonl (appended); screenshots with SHOTS=1.
# Close other Godot instances first: they share the GPU and skew the numbers.
set -u
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
SCRIPT="$REPO/tools/qa/bench/bench.gd"
command -v cygpath >/dev/null 2>&1 && SCRIPT="$(cygpath -m "$SCRIPT")"
OUT="$REPO/docs/qa/bench_results.jsonl"
command -v cygpath >/dev/null 2>&1 && OUT="$(cygpath -m "$OUT")"
for r in ${RENDERERS:-mobile gl_compatibility}; do
  for s in ${SCENES:-village city battle}; do
    for q in ${TIERS:-low high}; do
      extra=()
      [ "${SHOTS:-0}" = 1 ] && extra+=("--png=$(dirname "$OUT")/bench_${s}_${q}_${r}.png")
      echo "== $r / $s / $q"
      timeout 600 "$GODOT" --path "$REPO/kingdom" --rendering-method "$r" -s "$SCRIPT" -- \
        --adult --skipintro --quality="$q" --scene="$s" --settle="${SETTLE:-12}" --seconds="${SECONDS_RUN:-10}" \
        --uncapped --csv="$OUT" "${extra[@]}" 2>&1 | grep -a "^BENCH\|SCRIPT ERROR\|Saved" || true
    done
  done
done
