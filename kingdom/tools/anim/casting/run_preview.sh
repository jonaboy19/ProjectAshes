#!/bin/bash
# usage: run_preview.sh <lib.glb> <out_dir> [clip,clip]   (renders side|front frames + stats for every clip, needs ffmpeg on PATH)
B="${BLENDER:-C:/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
"$B" -b --python "$(dirname "$0")/render_preview.py" -- "$1" "$2" "${3:-}" 2>&1 | grep -E "RENDERED|Traceback|Error|line "
