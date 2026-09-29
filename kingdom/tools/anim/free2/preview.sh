#!/bin/bash
# usage: preview.sh <lib glb (abs)> <out dir (abs)> [frames=8] [rows=5]
G="${GODOT:-/c/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe}"
K="$(cd "$(dirname "$0")/../../.." && pwd)"
"$G" --path "$K" -s tools/anim/preview_free_library.gd -- --glb="$1" --out="$2" --frames=${3:-8} --rows=${4:-5} 2>&1 | grep -E "SHEET|rror"
