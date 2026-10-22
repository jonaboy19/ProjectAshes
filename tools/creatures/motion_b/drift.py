import json, numpy as np
T = "C:/Users/Jonna/AppData/Local/Temp/cm/"
for c in ("goblin", "orc", "troll"):
    d = json.load(open(T + f"{c}_after.json"))
    for n, cl in sorted(d.items()):
        h = np.array(cl["pos"]["Hips"]); xy = h[:, :2] - h[0, :2]
        print(f"{c:7s} {n:15s} hips horizontal drift: max {np.linalg.norm(xy, axis=1).max():.2f} m, end {np.linalg.norm(xy[-1]):.2f} m; hips z {h[:,2].min():.2f}..{h[:,2].max():.2f}")
