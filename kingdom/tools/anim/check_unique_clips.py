"""Clip-name hygiene for the animation libraries (plain python 3, no Godot needed).
Fails on: duplicate names inside a GLB, names that collide after Godot's importer strips a -loop/_loop/-cycle/_cycle suffix
("Animation name X already exists in library"), names shared between libraries (merging libraries would clash), and .glb.import
files stuck at valid=false (a failed import that was committed; delete the .import and re-run --import, keep the old uid).
usage: python tools/anim/check_unique_clips.py [assets/incoming/animations_free assets/incoming/animations_free2 ...]"""
import glob, json, os, re, struct, sys, collections
roots = sys.argv[1:] or ["assets/incoming/animations_free", "assets/incoming/animations_free2"]
STRIP = re.compile(r"[-_](loop|cycle)$", re.I)
bad = 0; owner = collections.defaultdict(list)
for root in roots:
    for p in sorted(glob.glob(os.path.join(root, "**", "*.glb"), recursive=True)):
        d = open(p, "rb").read(); n = struct.unpack("<I", d[12:16])[0]
        names = [a.get("name", "") for a in json.loads(d[20:20 + n]).get("animations", [])]
        seen = collections.Counter(STRIP.sub("", x) for x in names)
        for k, v in seen.items():
            if v > 1:
                print("DUP inside", os.path.basename(p), k); bad += 1
        for x in set(names): owner[x].append(os.path.basename(p))
        imp = p + ".import"
        if os.path.exists(imp) and re.search(r"^valid=false", open(imp).read(), re.M):
            print("INVALID import", imp); bad += 1
for k, v in owner.items():
    if len(v) > 1: print("SHARED", k, v); bad += 1
print("clips", len(owner), "problems", bad)
sys.exit(1 if bad else 0)
