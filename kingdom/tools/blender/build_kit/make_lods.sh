#!/usr/bin/env bash
# gltfpack LOD1 for every Blender-built build_kit piece (meshy_* are handled by make_lods_meshy.sh unless ALL=1)
D="${1:-$(dirname "$0")/../../../assets/incoming/build_kit}"
GP="/c/Users/Jonna/Tools/gltfpack/gltfpack.exe"
for f in "$D"/*_lod0.glb; do
  b=$(basename "$f" _lod0.glb)
  case "$b" in meshy_*) [ -z "$ALL" ] && continue;; esac
  r=0.4
  sz=$(stat -c %s "$f")
  [ "$sz" -lt 9000 ] && r=0.5
  "$GP" -i "$f" -o "$D/${b}_lod1.glb" -noq -si $r -sa >/dev/null 2>&1 || echo "FAILED $b"
done
echo done
