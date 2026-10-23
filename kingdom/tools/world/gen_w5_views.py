"""W5 QA view lists for tools_qa/region1/look_capture.gd.  py -E -B kingdom/tools/world/gen_w5_views.py
Writes tools_qa/world/w5_views_grid.json (36 aerials every 2048 m at 600 m + the two reference spots) and
tools_qa/world/w5_views_regions.json (24 sub-region views x dawn/noon/dusk where cheap + 400 m aerials)."""
import json, os
root = os.path.join(os.path.dirname(__file__), "..", "..", "tools_qa", "world")
H = {"dawn": 6.8, "noon": 12.0, "dusk": 17.8}

grid = []
cs = [-5120, -3072, -1024, 1024, 3072, 5120]
for iz, cz in enumerate(cs):
    for ix, cx in enumerate(cs):
        # camera 900 m south of the cell centre, 600 m above the ground there, looking at the centre: covers the whole 2048 m cell
        grid.append({"name": "grid_%d%d_x%d_z%d" % (ix, iz, cx, cz), "at": [cx, min(cz + 900, 6100)], "look": [cx, cz],
                     "up": 600, "look_up": 0, "hour": 12.0, "fov": 60, "warm": 120})
refs = []
for tag, h in H.items():
    refs.append({"name": "ref_gate_market_" + tag, "gate": 1, "in": 42, "up": 1.7, "look_up": 4.0, "hour": h, "fov": 62, "warm": 220})
    refs.append({"name": "ref_tuskridge_hut_camp_" + tag, "at": [255, 975], "look": [300, 930], "up": 1.7, "look_up": 1.6, "hour": h, "fov": 62, "warm": 200})
refs.append({"name": "ref_tuskridge_aerial", "at": [300, 1010], "look": [300, 930], "up": 60, "look_up": 0, "hour": 12.0, "fov": 60, "warm": 150})
refs.append({"name": "ref_gate_aerial", "gate": 1, "in": 160, "up": 90, "look_up": 0, "hour": 12.0, "fov": 60, "warm": 220})
refs.append({"name": "sign_mistwood_heart_tree", "site": "w4_grove_mistwood", "up": 2.4, "look_up": 2.4, "hour": 14.0, "fov": 55, "warm": 150})
refs.append({"name": "sign_duskbriar_old_oak", "site": "w4_grove_duskbriar", "up": 2.4, "look_up": 2.4, "hour": 14.0, "fov": 55, "warm": 150})
refs.append({"name": "rift_orbit_a_south", "at": [1130, 1060], "look": [1130, 1004], "up": 6, "look_up": 2, "hour": 14.0, "fov": 60, "warm": 150})
refs.append({"name": "rift_orbit_b_east", "at": [1190, 1004], "look": [1130, 1004], "up": 6, "look_up": 2, "hour": 14.0, "fov": 60, "warm": 150})
refs.append({"name": "rift_orbit_c_north", "at": [1130, 950], "look": [1130, 1004], "up": 6, "look_up": 2, "hour": 14.0, "fov": 60, "warm": 150})
refs.append({"name": "rift_orbit_d_west", "at": [1070, 1004], "look": [1130, 1004], "up": 6, "look_up": 2, "hour": 14.0, "fov": 60, "warm": 150})
json.dump({"views": grid + refs}, open(os.path.join(root, "w5_views_grid.json"), "w"), indent=1)

w3 = json.load(open(os.path.join(root, "world_views_w3.json")))["views"]
w1 = {v["name"]: v for v in json.load(open(os.path.join(root, "world_views.json")))["views"]}
reg = []
for v in w3:
    if v["name"].endswith("_ground"):
        for tag, h in H.items():
            u = dict(v); u["name"] = v["name"] + "_" + tag; u["hour"] = h; reg.append(u)
    else:
        u = dict(v); u["name"] = v["name"] + "120_noon"; u["hour"] = 12.0; reg.append(u)
        a4 = dict(w1[v["name"]]); a4["name"] = v["name"] + "400_noon"; reg.append(a4)
json.dump({"views": reg}, open(os.path.join(root, "w5_views_regions.json"), "w"), indent=1)
print(len(grid), len(refs), len(reg))
