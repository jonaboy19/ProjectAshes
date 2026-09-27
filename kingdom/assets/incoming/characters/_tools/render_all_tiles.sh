#!/bin/bash
# Renders every tiles/*.json with render_tile.py; results appended to tiles/results.jsonl
cd "$(dirname "$0")/tiles"
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
: > results.jsonl
for j in [0-9]*.json; do
  "$B" -b --python ../render_tile.py -- "$j" "$(cygpath -m "$PWD")/${j%.json}.png" 2>&1 | grep -E "^TILE" | sed 's/^TILE //' >> results.jsonl || echo "FAIL $j"
done
