#!/usr/bin/env bash
# Full rebuild of wolf.glb + wolf_lod1.glb from the original sources in src/.  usage: build_all.sh [work_dir=/tmp/wolfwork] [install=0|1]
# install=1 copies the GLBs and sidecar textures into kingdom/assets/incoming/ai3d/meshy/creatures/.
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"; cd "$(dirname "$0")"
W=${1:-/tmp/wolfwork}; INST=${2:-0}; DEST=../../../kingdom/assets/incoming/ai3d/meshy/creatures
mkdir -p "$W"
for L in 0 1; do
  src=src/wolf_orig.glb; name=wolf; [ $L = 1 ] && src=src/wolf_lod1_orig.glb && name=wolf_lod1
  timeout 600 "$B" -b --python build_base.py -- $src $W/base$L.blend $L 2>&1 | grep -E "BODY|TUFT|TEX|SAVED|Error|Traceback|line "
  timeout 900 "$B" -b --python author.py -- $W/base$L.blend $W/$name.glb 2>&1 | grep -E "^CLIP|LOOPCHK|Error|Traceback|line |EXPORTED"
  if [ $INST = 1 ]; then cp $W/$name.glb $DEST/$name.glb; cp $W/base${L}_tex.jpg $DEST/${name}_Image_0.jpg; fi
done
