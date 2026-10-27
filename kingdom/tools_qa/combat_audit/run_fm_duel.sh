#!/usr/bin/env bash
# Full-motion combat review movie (Movie Maker 1280x720 30 fps, HUD hidden) -> <out>/duel.avi + duel.mp4
# Usage: run_fm_duel.sh <out_dir> <only=fm01> [extra args: --classic-combat --style=greatsword]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; K="$(cd "$HERE/../.." && pwd)"
OUT=${1:?out}; ONLY=${2:-fm01}; shift 2
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
mkdir -p "$OUT"; rm -f "$OUT/duel.avi"
"$K/../tools/anim/combat_packs/wait_ram.sh" 1500
timeout 900 "$G" --path "$K" --rendering-method mobile --windowed --resolution 1280x720 --write-movie "$OUT/duel.avi" --fixed-fps 30 \
  res://tools_qa/combat_audit/combat_capture.tscn -- --adult --skipintro --nohud --out="$OUT" --only="$ONLY" "$@" > "$OUT/stdout.txt" 2>&1
echo "exit $?"
grep -E "COMBATCAP|SCRIPT ERROR|Parse Error" "$OUT/stdout.txt" | tail -8
ffmpeg -loglevel error -y -i "$OUT/duel.avi" -c:v libx264 -crf 24 -preset veryfast -pix_fmt yuv420p "$OUT/duel.mp4" && rm -f "$OUT/duel.avi"
ls -la "$OUT/duel.mp4"
