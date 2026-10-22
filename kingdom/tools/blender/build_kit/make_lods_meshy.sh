#!/bin/bash
# Makes meshy_<name>_lod1.glb from lod0 via gltfpack (-noq for Godot) and writes _meshy_manifest.json
# Run clean_meshy.py (Blender) first. Needs gltfpack + Blender (for tri readback of LOD1).
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$(cd "$(dirname "$0")/../../../assets/incoming/build_kit" && pwd)"
GP="/c/Users/Jonna/Tools/gltfpack/gltfpack.exe"
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd "$D"
for f in meshy_*_lod0.glb; do
  b="${f%_lod0.glb}"
  tris=$(grep -o "\"$b\": {[^}]*\"tris_lod0\": [0-9]*" _meshy_manifest_lod0.json | grep -o '[0-9]*$' || echo 9999)
  si=0.4; [ "${tris:-9999}" -lt 2000 ] && si=0.5
  "$GP" -i "$f" -o "${b}_lod1.glb" -noq -si $si -sa >/dev/null
done
timeout 900 "$BL" -b --factory-startup --python "$HERE/merge_manifest.py" -- "$D" >/dev/null
