#!/usr/bin/env bash
# Capture store screenshots from the real game (Ultra quality, real GPU).
# Usage: tools/store/make_screenshots.sh <outdir> <W> <H> <shots,...> [extra --key=value args]
# Example: tools/store/make_screenshots.sh /c/tmp/raw 1920 1080 plaza,guild,inn,goblins,night,runestone,knight,aerial
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6-stable_win64.exe/Godot_v4.6-stable_win64_console.exe}"
OUT="$1"; W="$2"; H="$3"; SHOTS="$4"; shift 4
SCENE="$(cygpath -m "$HERE/store_shots.tscn" 2>/dev/null || echo "$HERE/store_shots.tscn")"
OUTW="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"
mkdir -p "$OUT"
"$GODOT" --path "$REPO/kingdom" --rendering-driver vulkan --windowed --resolution "${W}x${H}" "$SCENE" -- \
	--quality=ultra --adult --skipintro --outdir="$OUTW" --w="$W" --h="$H" --shots="$SHOTS" "$@" 2>&1 | grep -E "STORE|SCRIPT ERROR|Parse Error|at: _shot|at: _run|Invalid" | head -60
