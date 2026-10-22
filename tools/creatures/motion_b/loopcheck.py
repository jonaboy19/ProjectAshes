import json, sys, numpy as np
for c in ("goblin","orc","troll"):
    d = json.load(open(f"C:/Users/Jonna/AppData/Local/Temp/cm/{c}_before.json"))
    for name, cl in d.items():
        p = cl["pos"]; pd = max(np.linalg.norm(np.array(p[b][0]) - np.array(p[b][-1])) for b in p)
        # max per-frame jump (m) of any tracked bone: pop detector
        jump = max(np.linalg.norm(np.diff(np.array(p[b]), axis=0), axis=1).max() for b in p)
        print(c, name, "first-last %.3f m" % pd, "max frame jump %.3f m" % jump, "minz %.3f" % min(cl["minz"]))
