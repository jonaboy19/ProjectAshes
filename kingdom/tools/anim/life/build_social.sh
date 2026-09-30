#!/usr/bin/env bash
# Build UAL_Life_Social.glb (talk pairs, reactions, hug / handshake, mourning, kids, ambient fidgets, rain layer, cane walk)
# and its sidecars (.clips.json, .life.json). Run from anywhere; needs Blender 5.2 and python (numpy) on PATH as `py`.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KING="$(cd "$HERE/../../.." && pwd)"
OUT="$KING/assets/incoming/animations/life/UAL_Life_Social.glb"
BLENDER="${BLENDER:-C:/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
cd "$HERE"
timeout 900 "$BLENDER" -b -P author_life.py -- "$OUT" life_clips_social,life_clips_kids,life_clips_ambient | grep -E "REACHWARN|EXPORTED|LIFE_SIDECAR|Error|Traceback" || true
py ../glb_reduce_anim.py "$OUT" --rot-deg 0.25 --pos-m 0.001
(cd "$KING" && py tools/anim/check_unique_clips.py assets/incoming/animations/life)
