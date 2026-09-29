#!/usr/bin/env bash
# usage: build_all.sh <goblin|orc|troll>
# Rebuilds <creature>.glb (authored on LOD0) and <creature>_lod1.glb (same baked keys re-applied) from the ORIGINAL git HEAD files.
C=$1; REPO=/c/Users/Jonna/Documents/PA_wt_creature; HERE=$REPO/tools/creatures/motion_b
D=kingdom/assets/incoming/ai3d/meshy/creatures; T=/c/Users/Jonna/AppData/Local/Temp/cm; mkdir -p $T/orig $T/out
BL="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
cd $REPO
[ -f $T/orig/$C.glb ] || git show HEAD:$D/$C.glb > $T/orig/$C.glb
[ -f $T/orig/${C}_lod1.glb ] || git show HEAD:$D/${C}_lod1.glb > $T/orig/${C}_lod1.glb
timeout 590 "$BL" -b --python $HERE/make_attacks.py -- $C $T/orig/$C.glb $T/out/$C.glb --save $HERE/baked/$C.json 2>&1 | grep -E "AUTHORED|GROUNDLIFT|SAVED|EXPORTED|Error|Trace|line "
timeout 590 "$BL" -b --python $HERE/make_attacks.py -- $C $T/orig/${C}_lod1.glb $T/out/${C}_lod1.glb --load $HERE/baked/$C.json 2>&1 | grep -E "LOADED|EXPORTED|Error|Trace|line "
cp $T/out/$C.glb $D/$C.glb; cp $T/out/${C}_lod1.glb $D/${C}_lod1.glb; ls -la $D/$C.glb $D/${C}_lod1.glb
