#!/usr/bin/env bash
# Rising Ashes autoplay playtest: boots the real game windowed on the GPU and plays
# the scripted scenario. Output: docs/qa/playtest/ (NN_*.jpg, log.txt, summary.json,
# godot_stdout.txt, errors.txt).
# Usage: kingdom/tools_qa/autoplay/run_autoplay.sh [--uncapped]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KINGDOM="$(cd "$HERE/../.." && pwd)"
REPO="$(cd "$KINGDOM/.." && pwd)"
OUT="$REPO/docs/qa/playtest"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
mkdir -p "$OUT"
"$GODOT" --path "$KINGDOM" --rendering-driver vulkan --windowed --resolution 1280x720 \
	res://tools_qa/autoplay/autoplay.tscn -- --outdir="$OUT" "$@" > "$OUT/godot_stdout.txt" 2>&1
code=$?
grep -E "SCRIPT ERROR|^ERROR|USER ERROR|Parse Error|^WARNING" "$OUT/godot_stdout.txt" | sort | uniq -c | sort -rn > "$OUT/errors.txt" || true
echo "exit $code; $(grep -c . "$OUT/errors.txt") error/warning lines -> $OUT/errors.txt"
grep -E "FIRST PLAYABLE|SUMMARY|FINDING|FIGHT|done in" "$OUT/log.txt" || tail -20 "$OUT/godot_stdout.txt"
exit $code
