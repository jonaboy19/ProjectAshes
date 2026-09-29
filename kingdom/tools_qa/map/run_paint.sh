#!/bin/bash
# usage: run_paint.sh <data_dir> [extra args]   (from the kingdom/ folder). Timeout-guarded, prints only the useful lines.
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
D="$1"; shift
timeout 300 "$G" --path . res://tools_qa/map/paint_parchment.tscn --resolution 1280x720 -- --data="$D" "$@" 2>&1 | grep -E "layout|save png|SCRIPT|Parse|ERROR: [^R]|rror" | grep -v "leaked\|still in use\|Pages in use" | head -30
