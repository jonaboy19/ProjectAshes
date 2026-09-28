#!/usr/bin/env bash
# Visual performance run: records frames with a frame-time graph + every hitch frame.
#   bash tools/qa/perf_visual/run.sh [quality=high] [route=village_forest] [speed=7]
# Routes: village_forest (plaza -> road -> fields -> woods -> camp -> back), to_capital, village_loop.
# Speeds: 7 = running, 14 = riding/galloping. Output: docs/qa/perf_visual/<quality>_<route>/
#   timeline.png (whole run), NNNN_*.jpg frames (HITCH_* = frame-time spikes), log.txt,
#   anim_timing.txt (player speed vs. animation mismatches).
# By default the player is driven through the REAL input path (on-screen joystick
# touches + camera aim, same as tools_qa/autoplay), cycling idle/walk/run, so
# walking/running animations actually play and streaming reacts as in real play.
# Pass EXTRA="--teleport" for the old teleport-along-the-route mode (pure
# streaming/GPU benchmark, no real movement or animation).
# LOOK at timeline.png and every HITCH frame with Read - that's the point of this tool.
set -e
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
GODOT="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
Q="${1:-high}"; ROUTE="${2:-village_forest}"; SPEED="${3:-7}"
OUT="$REPO/docs/qa/perf_visual/${Q}_${ROUTE}"
rm -rf "$OUT"; mkdir -p "$OUT"
SCRIPT="$(cygpath -w "$REPO/tools/qa/perf_visual/perf_visual.gd" 2>/dev/null || echo "$REPO/tools/qa/perf_visual/perf_visual.gd")"
OUTW="$(cygpath -w "$OUT" 2>/dev/null || echo "$OUT")"
timeout 900 "$GODOT" --path "$REPO/kingdom" --resolution 1280x720 -s "$SCRIPT" -- \
  --adult --skipintro --quality="$Q" --route="$ROUTE" --speed="$SPEED" --out="$OUTW" ${EXTRA:-} 2>&1 \
  | grep -aE "^PERFVIS|SCRIPT ERROR|Parse Error" | sort | uniq -c || true
echo "frames: $(ls "$OUT"/*.jpg 2>/dev/null | wc -l)  hitch frames: $(ls "$OUT"/*HITCH* 2>/dev/null | wc -l)"
