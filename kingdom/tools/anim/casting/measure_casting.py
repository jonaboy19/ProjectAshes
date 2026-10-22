"""Numbers for the casting clips, from the *.stats.json files written by render_preview.py (plain python 3).
   python measure_casting.py <preview_out_dir> <clips.json>
prints: loop gap (Charge), Charge->Release hand-over gap, lowest ball height, palm positions at the release frame, peak wrist speed
around the release (m/s) and the frames between the wind-up peak and the release (snap length)."""
import json, math, os, sys

d, cj = sys.argv[1], sys.argv[2]
clips = {c["name"]: c for c in json.load(open(cj))}
PTS = ("hand_l", "hand_r", "foot_l", "foot_r", "Head", "pelvis")

def load(n):
    return json.load(open(os.path.join(d, n + ".stats.json")))["frames"]

def gap(a, b):
    return max(math.dist(a[k], b[k]) for k in PTS)

print("| clip | frames | loop gap m | hand-over gap m | lowest ball m | release f | palm_l @release | palm_r @release | peak wrist speed m/s (frame) |")
print("|---|---:|---:|---:|---:|---:|---|---|---|")
for n, c in clips.items():
    fr = load(n)
    low = min(min(f["ball_l"][2], f["ball_r"][2]) for f in fr)
    loopgap = handgap = ""
    if c["loop"]:
        loopgap = "%.3f" % gap(fr[0], fr[-1])
    if n.endswith("_Release"):
        ch = load(n.replace("_Release", "_Charge"))
        handgap = "%.3f" % gap(ch[0], fr[0])
    rf = c.get("release_frame")
    pl = pr = sp = ""
    if rf is not None:
        pl = "(%.2f, %.2f, %.2f)" % tuple(fr[rf]["palm_l"])
        pr = "(%.2f, %.2f, %.2f)" % tuple(fr[rf]["palm_r"])
        best = (0.0, 0)
        for i in range(1, len(fr)):
            for k in ("hand_l", "hand_r"):
                v = math.dist(fr[i][k], fr[i - 1][k]) * 30.0
                if v > best[0]:
                    best = (v, i)
        sp = "%.1f (f%d)" % best
    print("| `%s` | %d | %s | %s | %.3f | %s | %s | %s | %s |" % (n, len(fr), loopgap, handgap, low, rf if rf is not None else "-", pl, pr, sp))
