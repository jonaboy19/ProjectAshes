#!/usr/bin/env bash
# Build the TOWN-LIFE animation library (market / guard / shop / reading / prayer / tavern / music / rest / eating).
#   bash build_town.sh            -> assets/incoming/animations/life/UAL_Life_Town.glb (+ .clips.json, .life.json)
set -euo pipefail
cd "$(dirname "$0")"
OUT=../../../assets/incoming/animations/life/UAL_Life_Town.glb
BLENDER="${BLENDER:-C:/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
timeout 900 "$BLENDER" -b -P author_life.py -- "$OUT" life_clips_market,life_clips_tavern,life_clips_rest
py ../glb_reduce_anim.py "$OUT" --rot-deg 0.25 --pos-m 0.001
(cd ../../.. && py tools/anim/check_unique_clips.py assets/incoming/animations/life)
