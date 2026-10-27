"""W6 fly-over view list for tools_qa/region1/look_capture.gd: Ashford ground, every sub-region aerial, the snowy north, the border, the port.
Usage: py -E -B kingdom/tools/world/gen_w6_views.py"""
import json, os
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
a = json.load(open(os.path.join(ROOT, "data", "world", "real", "anchors.json")))
v = [{"name": "r00_ashford_ground", "at": [-70, -150], "look": [40, 60], "up": 3, "look_up": 0, "hour": 10.0, "fov": 65}]
for i, (n, (x, z)) in enumerate(a["region_labels"].items(), 1):
    k = n.lower().replace(" & ", "_").replace(" ", "_").replace("'", "")
    v.append({"name": "r%02d_%s_aerial" % (i, k), "at": [x, z + 1000], "look": [x, z], "up": 480, "look_up": 0, "hour": 11.0, "fov": 60})
v.append({"name": "r20_north_snow_aerial", "at": [600, -3200], "look": [600, -6800], "up": 400, "look_up": 0, "hour": 11.0, "fov": 60})
v.append({"name": "r21_border_north", "at": [-2000, -6600], "look": [-2000, -8000], "up": 30, "look_up": 0, "hour": 11.0, "fov": 60})
v.append({"name": "r22_coast_port", "at": [-8800, 7600], "look": [-10500, 8400], "up": 120, "look_up": 0, "hour": 17.5, "fov": 60})
places = json.load(open(os.path.join(ROOT, "data", "world", "real", "layout.json")))["places"]
mw = places["lore:mistwood"]; rf = places["site:The Rift:1130:1004"]
v.append({"name": "r30_mistwood_giants", "at": [mw["x"] - 900, mw["z"] + 900], "look": [mw["x"], mw["z"]], "up": 60, "look_up": 30, "hour": 15.0, "fov": 60})
v.append({"name": "r31_rift_close", "at": [rf["x"], rf["z"] + 450], "look": [rf["x"], rf["z"]], "up": 40, "look_up": 30, "hour": 19.0, "fov": 60})
json.dump({"views": v}, open(os.path.join(ROOT, "tools_qa", "world", "w6_views_real.json"), "w"), indent=1)
print(len(v))
