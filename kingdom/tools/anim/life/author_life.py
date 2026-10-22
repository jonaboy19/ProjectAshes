# Build a LIFE clip library (villager work / social / ambient clips) on the Quaternius UAL skeleton.
# Runs the combat key-pose framework (../combat/author_combat.py: IK key poses -> baked FK quaternions -> GLB with one
# NLA track per clip, "_Loop" suffix for loops) with the life clip modules from this folder, then writes the
# living-world sidecar <out>.life.json (life_common.LIFE + frames/seconds from <out>.clips.json).
#
#   blender -b -P author_life.py -- <out.glb> <module[,module]> [clip,clip,...]
#   python ../glb_reduce_anim.py <out.glb> --rot-deg 0.25 --pos-m 0.001
#   python ../check_unique_clips.py assets/incoming/animations/life
import sys, os, runpy, json
HERE = os.path.dirname(os.path.abspath(__file__))
COMBAT = os.path.normpath(os.path.join(HERE, "..", "combat"))
sys.path.insert(0, COMBAT)
sys.path.insert(0, HERE)
runpy.run_path(os.path.join(COMBAT, "author_combat.py"), run_name="__main__")

import life_common as LC
argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
report = {c["name"]: c for c in json.load(open(OUT + ".clips.json"))}
lib = "res://" + os.path.relpath(OUT, os.path.normpath(os.path.join(HERE, "..", "..", ".."))).replace("\\", "/")
clips = {}
for name, e in LC.LIFE.items():
    if name not in report:
        continue
    d = dict(e)
    d["frames"] = report[name]["frames"]
    d["seconds"] = report[name]["seconds"]
    clips[name] = d
json.dump({"library": lib, "fps": 30, "clips": clips}, open(OUT + ".life.json", "w"), indent=1)
print("LIFE_SIDECAR", OUT + ".life.json", len(clips))
