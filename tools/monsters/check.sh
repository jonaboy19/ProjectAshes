#!/usr/bin/env bash
# Harmonise one or more monsters and render a style/scale check next to the human, the Meshy goblin and the wolf.
#   bash tools/monsters/check.sh giant_rat [skeleton ...]   -> $TMPDIR/monsters_check_<name>.png
cd "$(dirname "$0")/../.."
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
P=$(pwd -W); T=$(cygpath -m "${MON_TMP:-${TMP:-/tmp}/ashes_monsters}"); mkdir -p "$T"
for n in "$@"; do [ -n "$ONLY_CLOSE" ] && break
  "$B" -b --python tools/monsters/harmonise.py -- tools/monsters/specs/$n.json > "$T/$n.log" 2>&1
  grep -E "PRUNED|SIZE|TRIS|STATS|Error|Traceback" "$T/$n.log" | cut -c1-400
  src=$(grep -o '"out_dir": *"[^"]*"' tools/monsters/specs/$n.json | sed 's/.*: *"//;s/"$//')
  cat > "$T/$n.json" <<J
{"out": "$T/check_$n.png", "res": [1600, 640], "show_h": true, "grid": true, "gap": 0.4, "yaw": -35,
 "items": [
 {"file": "$P/kingdom/assets/generated/characters/villager_man_a.glb", "label": "human 1.75 m"},
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/goblin.glb", "label": "goblin", "action": "idle"},
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/wolf.glb", "label": "wolf", "action": "idle"},
 {"file": "$P/$src/$n.glb", "label": "$n", "action": "idle"},
 {"file": "$P/$src/${n}_lod1.glb", "label": "$n LOD1", "action": "idle"}]}
J
  "$B" -b --python tools/monsters/render_lineup.py -- "$T/$n.json" 2>&1 | grep -E "ITEM|Error|Trace"
done
for n in "$@"; do
  src=$(grep -o '"out_dir": *"[^"]*"' tools/monsters/specs/$n.json | sed 's/.*: *"//;s/"$//')
  cat > "$T/c_$n.json" <<J
{"out": "$T/close_$n.png", "engine": "${ENGINE:-workbench}", "res": [1400, 700], "gap": 0.25, "yaw": -40, "elev": 12,
 "items": [
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/goblin.glb", "label": "goblin", "action": "idle"},
 {"file": "$P/$src/$n.glb", "label": "$n", "action": "${CLOSE_ACTION:-idle}", "frame": ${CLOSE_FRAME:-0}},
 {"file": "$P/kingdom/assets/incoming/ai3d/meshy/creatures/wolf.glb", "label": "wolf", "action": "idle"}]}
J
  "$B" -b --python tools/monsters/render_lineup.py -- "$T/c_$n.json" > /dev/null 2>&1
done
