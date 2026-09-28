#!/usr/bin/env bash
# Rising Ashes movement QA: boots the real game windowed on the GPU and drives the
# player through walk/run/stop/turn/backward/slope/dodge/dash with real key input.
# Output: docs/qa/movement/<scenario>/NN*.jpg, log.txt, godot_stdout.txt, errors.txt.
# Usage: kingdom/tools_qa/movement_qa/run_movement_qa.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KINGDOM="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$KINGDOM/.." && pwd)"
OUT="$REPO/docs/qa/movement"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe}"
mkdir -p "$OUT"
"$GODOT" --path "$KINGDOM" --rendering-driver vulkan --windowed --resolution 1280x720 \
	res://tools_qa/movement_qa/movement_qa.tscn -- --adult --skipintro --out="$OUT" "$@" \
	> "$OUT/godot_stdout.txt" 2>&1
code=$?
grep -E "SCRIPT ERROR|^ERROR|USER ERROR|Parse Error|^WARNING" "$OUT/godot_stdout.txt" | sort | uniq -c | sort -rn > "$OUT/errors.txt" || true
echo "exit $code; $(grep -c . "$OUT/errors.txt") error/warning lines -> $OUT/errors.txt"
grep -E "MOVEQA|scenario:|end speed|dodge\(|dash\(|DONE" "$OUT/log.txt" || tail -20 "$OUT/godot_stdout.txt"
exit $code
