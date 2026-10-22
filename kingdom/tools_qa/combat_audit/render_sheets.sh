#!/usr/bin/env bash
# Render combat clips in the combat studio and turn them into 30 fps contact sheets (every frame).
# usage: render_sheets.sh <sheet_out_dir> <clip[@rate],...> [studio args...]
#   e.g. render_sheets.sh docs/anim/combat/before "Sword_Regular_A@1.7" --layer=upper
# Output: <sheet_out_dir>/<clip>[_upper][_x<rate>]/sheet_###.jpg + metrics.json (frames deleted afterwards).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KINGDOM="$(cd "$HERE/../.." && pwd)"
ROOT="$(cd "$KINGDOM/.." && pwd)"
OUT=${1:?out}; CLIPS=${2:?clips}; shift 2
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
TMP="${TMPDIR:-/c/Users/Jonna/AppData/Local/Temp}/combat_frames_$$"
mkdir -p "$TMP" "$OUT"
timeout 900 "$GODOT" --path "$KINGDOM" --rendering-method mobile res://tools_qa/combat_audit/combat_studio.tscn -- \
	--out="$TMP" --render --clips="$CLIPS" "$@" > "$TMP/stdout.txt" 2>&1
grep -E "SCRIPT ERROR|Parse Error|missing" "$TMP/stdout.txt" | head
for d in "$TMP"/*/; do
	n=$(basename "$d")
	[ -f "$d/f_00000000.png" ] || continue
	mkdir -p "$OUT/$n"
	SRC_FPS=30 bash "$ROOT/tools/qa/video_to_sheets.sh" "$d" "$TMP/sh_$n" 30 4 4 540 > /dev/null 2>&1
	for s in "$TMP/sh_$n"/sheet_*.png; do
		ffmpeg -v error -y -i "$s" -q:v 4 "$OUT/$n/$(basename "${s%.png}").jpg"
	done
	echo "$OUT/$n: $(ls "$OUT/$n" | wc -l) sheets"
done
cp "$TMP/metrics.json" "$OUT/metrics_$(date +%s).json" 2>/dev/null
rm -rf "$TMP"
