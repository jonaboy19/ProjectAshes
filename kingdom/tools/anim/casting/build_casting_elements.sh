#!/bin/bash
# Rebuild kingdom/assets/incoming/animations_free/casting/UAL_Free_CastingElements.glb (+ .clips.json) from the key poses in
# casting_clips.py, then shrink the keys.  Run from anywhere; needs Blender 5.2 (BLENDER env var overrides the path).
# Preview: ./run_preview.sh <glb> <out_dir>  (needs ffmpeg on PATH), then tools/qa/video_to_sheets.sh on <out_dir>/<clip>/frames.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
K="$(cd "$HERE/../../.." && pwd -W 2>/dev/null || cd "$HERE/../../.." && pwd)"
B="${BLENDER:-C:/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
PY="${BLENDER_PY:-C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe}"
OUT="$K/assets/incoming/animations_free/casting/UAL_Free_CastingElements.glb"
"$B" -b --python "$HERE/author_casting_elements.py" -- "$OUT"
"$PY" "$HERE/../glb_reduce_anim.py" "$OUT"
