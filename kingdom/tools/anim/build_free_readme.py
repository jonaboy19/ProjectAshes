# Generates the clip tables of docs/anim/free_library/README.md from make_free_cfgs.py + the
# *.clips.json written by retarget_bvh.py. Run with Blender's python (or any python 3):
#   blender -b --python tools/anim/build_free_readme.py
import json, os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_free_cfgs as M

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "incoming", "animations_free"))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "docs", "anim", "free_library", "clip_tables.md"))
ELEM = {"Kick": "fire / physical", "Punch": "physical", "Combo": "physical", "Cast_Slam": "earth", "Cast_Push": "wind",
        "Cast_Throw": "fire", "Cast_Aura": "buff / light", "Cast_Summon": "earth", "Cast_Raise": "lightning / channel",
        "Cast_Shoot": "any projectile", "Cast_Spell": "any", "Weapon": "physical"}

def info(cat_dir, glb):
    j = json.load(open(os.path.join(ROOT, cat_dir, glb + ".clips.json")))
    return {c["name"] + ("_Loop" if c["loop"] else ""): c for c in j}

lines = []
total = 0
def table(title, folder, glb, rows, kk=False):
    global total
    d = info(folder, glb)
    lines.append("### %s  (`animations_free/%s/%s`)\n" % (title, folder, glb))
    lines.append("| clip | s | loop | root travel | source | use |\n|---|---:|---|---:|---|---|")
    for r in rows:
        name = r[0]; loop = (r[3] if kk else r[4]).get("loop", False)
        key = name + ("_Loop" if loop else "")
        c = d[key]
        src = ("KayKit %s / %s (CC0)" % (r[1], r[2])) if kk else ("CMU %s, %.1f-%.1f s%s (CMU terms)" % (r[1], r[2], r[3], ", mirrored" if r[4].get("mirror") else ""))
        use = r[4] if kk is False and False else (r[5] if not kk else r[4])
        lines.append("| `%s` | %.2f | %s | %s | %s | %s |" % (key, c["seconds"], "loop" if loop else "", ("%.2f m" % c["travel_m"]) if c["travel_m"] > 0.05 else "-", src, r[5] if not kk else r[4] if isinstance(r[4], str) else r[5]))
        total += 1
    lines.append("")

for cat, rows in M.TABLE.items():
    table(cat, cat, "UAL_Free_%s.glb" % cat.title().replace("_", ""), rows)
for cat, rows in M.KK_TABLE.items():
    folder = "casting" if cat.startswith("casting") else cat
    d = info(folder, "UAL_Free_%s.glb" % cat.title().replace("_", ""))
    lines.append("### %s  (`animations_free/%s/UAL_Free_%s.glb`)\n" % (cat, folder, cat.title().replace("_", "")))
    lines.append("| clip | s | loop | root travel | source | use |\n|---|---:|---|---:|---|---|")
    for name, f, action, o, use in rows:
        loop = o.get("loop", False); key = name + ("_Loop" if loop else "")
        c = d[key]
        lines.append("| `%s` | %.2f | %s | %s | KayKit %s / %s (CC0) | %s |" % (key, c["seconds"], "loop" if loop else "", ("%.2f m" % c["travel_m"]) if c["travel_m"] > 0.05 else "-", f, action, use))
        total += 1
    lines.append("")
lines.append("Total: %d clips.\n" % total)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write("\n".join(lines))
print("wrote", OUT, total, "clips")
