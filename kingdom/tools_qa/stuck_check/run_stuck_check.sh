#!/usr/bin/env bash
# Village stuck-check: walks street lanes and door paths of every settlement (or --towns=Ashford,Kingsreach)
# with real player input and logs every place the player stops progressing.
# Headless is fine (pure simulation). Output: docs/qa/stuck_check/<out>/ (log.txt, stuck.json)
# Usage: kingdom/tools_qa/stuck_check/run_stuck_check.sh [--out=name] [--towns=Ashford,Kingsreach] [--scale=3]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
KINGDOM="$(cd "$HERE/../.." && pwd)"
GODOT="${GODOT:-/tmp/claude-0/godot/Godot_v4.6.2-stable_linux.x86_64}"
"$GODOT" --headless --path "$KINGDOM" res://tools_qa/stuck_check/stuck_check.tscn -- "$@" 2>&1 | grep -E "STUCKQA|SCRIPT ERROR|Parse Error"
