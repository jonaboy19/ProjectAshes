#!/usr/bin/env bash
# Water perf ablation: bash tools/qa/water_shots/prof.sh <out.jsonl> [views=lake,river,pier] [W=1600] [H=900] [extra --k=v ...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
OUT="$(cygpath -m "$1")"; VIEWS="${2:-lake,river,pier}"; W="${3:-1600}"; H="${4:-900}"; shift 4 2>/dev/null || shift $#
# The scene lives next to the script; write it with this checkout's absolute path.
SC="${TMPDIR:-/tmp}/water_prof_$$.tscn"
printf '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="%s" id="1"]\n\n[node name="WaterProf" type="Node"]\nscript = ExtResource("1")\n' "$(cygpath -m "$HERE/water_prof.gd")" > "$SC"
"$GODOT" --path "${PROJECT:-$REPO/kingdom}" --rendering-driver vulkan --rendering-method "${RENDERER:-forward_plus}" --windowed --resolution "${W}x${H}" "$(cygpath -m "$SC")" -- \
	--quality=ultra --adult --skipintro --skip-intro --outdir="$(dirname "$OUT")/prof_shots" --w="$W" --h="$H" --ss=1 --shots=prof --jsonl="$OUT" --views="$VIEWS" "$@" 2>&1 | grep -aE "PROF|CENSUS|SCRIPT ERROR|Parse Error|Invalid|STORE" | grep -av "previously freed" | head -1000
rm -f "$SC"
