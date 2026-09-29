import json, sys, numpy as np
T = "C:/Users/Jonna/AppData/Local/Temp/cm/"
for c in ("goblin", "orc", "troll"):
    b = json.load(open(T + f"{c}_before.json")); a = json.load(open(T + f"{c}_after.json")); l = json.load(open(T + f"{c}_lod1_after.json"))
    print("==", c, "clips before", sorted(b), "after", sorted(a), "lod1", sorted(l))
    for name in sorted(a):
        pa = a[name]["pos"]; n = len(pa["Hips"])
        lod = max(np.linalg.norm(np.array(pa[k]) - np.array(l[name]["pos"][k]), axis=1).max() for k in pa) if name in l else -1
        if name in b:
            pb = b[name]["pos"]
            same = (len(pb["Hips"]) == n) and max(np.linalg.norm(np.array(pa[k]) - np.array(pb[k]), axis=1).max() for k in pa if k in pb) if len(pb["Hips"]) == n else None
            print(f"  {name:15s} frames {len(pb['Hips'])}->{n}  max bone delta vs before: {same if same is None else round(same*100,2)} cm ; LOD1 vs LOD0 delta {lod*100:.3f} cm; minz {min(a[name]['minz']):.3f}")
        else: print("  NEW", name)
