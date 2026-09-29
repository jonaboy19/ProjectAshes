#!/usr/bin/env bash
# Water QA shots: bash tools/qa/water_shots/run.sh <outdir> [quality=ultra] [shots=lake,river,pier] [W=1600] [H=900] [extra --k=v ...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
OUT="$1"; Q="${2:-ultra}"; SHOTS="${3:-lake,river,pier}"; W="${4:-1600}"; H="${5:-900}"; shift 5 2>/dev/null || shift $#
SCENE="$(cygpath -m "$HERE/water_shots.tscn")"
OUTW="$(cygpath -m "$OUT")"
mkdir -p "$OUT"
"$GODOT" --path "$REPO/kingdom" --rendering-driver vulkan --windowed --resolution "${W}x${H}" "$SCENE" -- \
	--quality="$Q" --adult --skipintro --outdir="$OUTW" --w="$W" --h="$H" --ss=1 --shots="$SHOTS" "$@" 2>&1 | grep -aE "STORE|SCRIPT ERROR|Parse Error|Invalid" | uniq -c | head -80
