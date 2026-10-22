#!/usr/bin/env bash
# Feel capture under Godot Movie Maker (deterministic 30 fps). See feel_capture.gd.
# Usage: kingdom/tools_qa/feel_capture/run_feel_capture.sh <out_dir> [quality=high] [--only=01,02]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KINGDOM="$(cd "$HERE/../.." && pwd)"
OUT=${1:?out dir}; Q=${2:-high}; shift 2 || shift $#
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
mkdir -p "$OUT"
rm -f "$OUT/feel.avi"
"$GODOT" --path "$KINGDOM" --rendering-method mobile --windowed --resolution 1280x720 \
	--write-movie "$OUT/feel.avi" --fixed-fps 30 \
	res://tools_qa/feel_capture/feel_capture.tscn -- --adult --skipintro --quality="$Q" --out="$OUT" "$@" \
	> "$OUT/stdout.txt" 2>&1
echo "exit $?"
grep -E "FEELCAP|SCRIPT ERROR|Parse Error" "$OUT/stdout.txt" | head -80
