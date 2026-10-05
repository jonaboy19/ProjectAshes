#!/usr/bin/env bash
# Runs the whole gdUnit4 suite in batches, one Godot process per batch.
# One process for all ~150 suites piles up orphans and crashes the engine (signal 11) near the end,
# and a few suites depend on state earlier suites leave behind; small batches avoid both.
#   GODOT=/path/to/godot tools/qa/run_tests.sh [batch_size]
# Exit 0 when every batch ends 0 or 101 (101 = orphan warnings only) with no failures.
set -u
GODOT="${GODOT:-godot}"
BATCH="${1:-20}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT/kingdom" || exit 2
LOGDIR="${LOGDIR:-$ROOT/kingdom/reports/batches}"
mkdir -p "$LOGDIR"
mapfile -t SUITES < <(ls tests/test_*.gd | sort)
total=0; failed=0; bad_batches=()
for ((i = 0; i < ${#SUITES[@]}; i += BATCH)); do
	n=$((i / BATCH + 1))
	args=()
	for s in "${SUITES[@]:i:BATCH}"; do args+=(--add "res://$s"); done
	log="$LOGDIR/batch_$n.log"
	timeout 1800 "$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd "${args[@]}" \
		--ignoreHeadlessMode -c > "$log" 2>&1
	code=$?
	summary=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E "Overall Summary" | tail -1)
	cases=$(echo "$summary" | grep -oE "[0-9]+ test cases" | grep -oE "^[0-9]+")
	fails=$(echo "$summary" | grep -oE "[0-9]+ failures" | grep -oE "^[0-9]+")
	total=$((total + ${cases:-0})); failed=$((failed + ${fails:-0}))
	echo "batch $n (exit $code): ${summary:-no summary}"
	if { [ "$code" != "0" ] && [ "$code" != "101" ]; } || [ "${fails:-1}" != "0" ]; then
		bad_batches+=("$n")
		sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E "FAILED|Parse Error|SCRIPT ERROR|signal 11" | sort -u | head -20
	fi
done
echo "TOTAL: $total test cases, $failed failures, bad batches: ${bad_batches[*]:-none}"
[ ${#bad_batches[@]} -eq 0 ]
