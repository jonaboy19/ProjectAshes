#!/usr/bin/env bash
# Render kingdom/assets/incoming/monsters/_previews: monsters_lineup.png (to scale with a 1.75 m human,
# the Meshy goblin and wolf), <name>_anim.png (idle, walk, attack, hit, death) and monsters_poses.png.
#   bash tools/monsters/previews.sh
cd "$(dirname "$0")/../.."
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
P=$(pwd -W); OUT=$P/kingdom/assets/incoming/monsters/_previews; M=$P/kingdom/assets/incoming/monsters/quaternius
T=$(cygpath -m "${MON_TMP:-${TMP:-/tmp}/ashes_monsters}"); mkdir -p "$T" "$OUT"
NAMES="giant_rat blight_rat bog_toad giant_wasp ghoul fungal_brute blackcap_brute rift_slime rift_wraith"
items=""
for n in $NAMES; do items="$items, {\"file\": \"$M/$n.glb\", \"label\": \"${n//_/ }\", \"action\": \"idle\"}"; done
cat > "$T/lineup.json" <<J
{"out": "$OUT/monsters_lineup.png", "engine": "eevee", "res": [2600, 900], "show_h": true, "grid": true, "gap": 0.35, "yaw": -35, "elev": 4,
 "items": [
 {"file": "$P/kingdom/assets/generated/characters/villager_man_a.glb", "label": "human 1.75 m"},
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/goblin.glb", "label": "goblin (Meshy)", "action": "idle"},
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/wolf.glb", "label": "wolf (Meshy)", "action": "idle"}$items]}
J
"$B" -b --python tools/monsters/render_lineup.py -- "$T/lineup.json" 2>&1 | grep -E "ITEM|Error|Trace"
for n in $NAMES; do
  it=""
  for pose in "idle 0.0" "walk 0.25" "walk 0.75" "attack 0.45" "hit 0.3" "death 1.0"; do
    set -- $pose
    lb=$1; [ "$1 $2" = "idle 0.0" ] && lb="${n//_/ }: idle"
    it="$it, {\"file\": \"$M/$n.glb\", \"label\": \"$lb\", \"action\": \"$1\", \"frame\": $2, \"frac\": true}"
  done
  cat > "$T/pose_$n.json" <<J
{"out": "$OUT/${n}_anim.png", "engine": "eevee", "res": [2000, 520], "gap": 0.3, "yaw": -50, "elev": 8, "items": [${it:2}]}
J
  "$B" -b --python tools/monsters/render_lineup.py -- "$T/pose_$n.json" > /dev/null 2>&1 || echo "pose render failed: $n"
done
# stack the rows into one pose sheet (labelled by the row file order)
"$B" -b --python tools/monsters/stack_rows.py -- "$OUT/monsters_poses.png" $(for n in $NAMES; do echo "$OUT/${n}_anim.png"; done) 2>&1 | grep -E "STACK|Error"
