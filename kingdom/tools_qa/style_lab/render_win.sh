#!/usr/bin/env bash
# Style G lab render on the Windows PC (real GPU, Vulkan). Git Bash.
# usage: render_win.sh <out-prefix> [high|medium|low] [w] [h]
# Writes <prefix>_G_over|close|facade|gate|stall.png + <prefix>_stats.json. 15 min timeout, own PID only.
set -u
cd "$(dirname "$0")/../.."
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
OUT="$1"; TIER="${2:-high}"; W="${3:-1920}"; H="${4:-1080}"
REND="vulkan --rendering-method mobile"; Q=high   # the S22 runs the Mobile renderer on every tier
[ "$TIER" = low ] && { Q=low; }
timeout 900 "$G" --path . --rendering-driver $REND --quality=$Q -- --shot=style_lab --box=G --tier=$TIER --w=$W --h=$H --out="$OUT" > "$OUT.log" 2>&1
echo "EXIT $?" >> "$OUT.log"
grep -E "style_lab G|EXIT|SCRIPT ERROR" "$OUT.log" | head -20
