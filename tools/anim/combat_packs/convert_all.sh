#!/usr/bin/env bash
# Retarget the owner's Mixamo combat packs onto UAL, one Blender at a time (RAM).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PACKS=${PACKS_DIR:-/c/Users/Jonna/Documents/ProjectAshes_art_staging/downloads/mixamo/packs}
BL=${BLENDER:-"/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"}
OUT=$ROOT/kingdom/assets/incoming/animations/mixamo_combat
mkdir -p "$OUT"
for p in ${@:-pro_sword_and_shield great_sword pro_melee_axe pro_longbow male_injured}; do
  n=$(echo "$p" | sed 's/pro_//')
  "$BL" -b --python "$ROOT/tools/anim/mixamo_to_ual.py" -- --src "$PACKS/$p" --clips "$ROOT/tools/anim/combat_packs/$p.json" \
     --out "$OUT/UAL_Mx_${n}.glb" --root-motion keep > "$OUT/../../../../../tools/anim/combat_packs/log_$n.txt" 2>&1
  echo "DONE $p rc=$? $(ls -la "$OUT/UAL_Mx_${n}.glb" 2>/dev/null | awk '{print $5}')"
done
