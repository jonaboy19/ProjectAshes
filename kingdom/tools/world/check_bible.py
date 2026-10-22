"""W0 acceptance check: every name in region1_parchment.json and docs/regions/WORLD_R1.md is in docs/world/valencious_places.json with coordinates,
and every live settlement/discovery place is there with its exact position.   py -E -B kingdom/tools/world/check_bible.py"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valencious_common as vc  # noqa: E402

places = vc.load_json(vc.PLACES_JSON)["places"]
names = {}
for p in places:
    assert isinstance(p["x"], (int, float)) and isinstance(p["z"], (int, float)), p
    for n in [p["name"], p.get("display_name", "")] + p.get("aliases", []):
        if n:
            names.setdefault(n, []).append(p)
parch = vc.load_json(os.path.join(vc.KINGDOM, "assets", "ui", "maps", "region1_parchment.json"))
need = set()
for f in parch["features"]:
    for n in (f["name"], f["id_name"]):
        if n:
            need.add(n)
for e in parch["elder_stones"]:
    need.add(e["name"])
for k, v in parch["aliases"].items():
    need.add(k)
    need.add(v)
md = open(os.path.join(vc.REPO, "docs", "regions", "WORLD_R1.md"), encoding="utf8").read()
for m in re.finditer(r"^\| `[a-z0-9_]+` \| ([^|]+?) \| [a-z_]+ \| \(-?\d+, -?\d+\) \|", md, re.M):
    need.add(m.group(1).strip())
# story place ids of quests/r1_registry.json that resolve by name (the others are first_region.json ids)
for n in ("Silverford", "Greenhollow", "Highwatch Keep", "Crownstead", "Elden Road", "Stagborn Glade", "Scar Watch", "Greyseam Mine"):
    need.add(n)
missing = sorted(n for n in need if n not in names)
print("names required:", len(need), "missing:", missing)
dump = vc.load_json(os.path.join(vc.REPO, "docs", "world", "dump_world_map.json"))
bad = []
for s in dump["settlements"]:
    hit = [p for p in places if p["category"] == "settlement" and p["name"] == s["name"]]
    if not hit or abs(hit[0]["x"] - s["pos"][0]) > 0.15 or abs(hit[0]["z"] - s["pos"][1]) > 0.15:
        bad.append(s["name"])
for pl in dump["places"]:
    if not any(abs(p["x"] - pl["pos"][0]) < 0.15 and abs(p["z"] - pl["pos"][1]) < 0.15 and pl["name"] in [p["name"], p.get("display_name")] + p.get("aliases", []) for p in places):
        bad.append(pl["name"])
print("live places missing or moved:", bad)
sub = {p["subregion"] for p in places}
print("sub-regions used:", len(sub), sorted(sub))
ok = not missing and not bad
print("RESULT", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
