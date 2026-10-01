"""Foot-slide report from the demo's HOOF lines (horse_demo --hoofs=1): a hoof is planted while its toe is within
2 cm of the ground; the report gives, per leg, the number of plants and the worst horizontal drift of the toe inside
one plant (world space, metres), plus the planted-frame share (duty factor as seen in the engine).
usage: py -3 slide_report.py <godot log> [contact_height=0.02] [skip_frames=20]"""
import sys, re, collections, math
h = float(sys.argv[2]) if len(sys.argv) > 2 else 0.02
skip = int(sys.argv[3]) if len(sys.argv) > 3 else 20   # ignore the blend-in from Idle
rows = collections.defaultdict(list)
for line in open(sys.argv[1], errors="ignore"):
    if not line.startswith("HOOF f"):
        continue
    parts = line.split()
    f = int(parts[1][1:]); clip = parts[2]
    if f < skip:
        continue
    for m in re.finditer(r"(hoof_\w+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+)", line):
        rows[m.group(1)].append((f, clip, float(m.group(2)), float(m.group(3)), float(m.group(4))))
for leg, r in sorted(rows.items()):
    plants, cur, worst, down = [], [], 0.0, 0
    for f, clip, x, y, z in r:
        if y < h:
            cur.append((x, z)); down += 1
        elif cur:
            plants.append(cur); cur = []
    if cur:
        plants.append(cur)
    for p in plants:
        x0, z0 = p[0]
        worst = max([worst] + [math.hypot(x - x0, z - z0) for x, z in p])
    print("%-9s plants %3d  worst drift %.4f m  planted %.0f%% of %d frames" % (leg, len(plants), worst, 100.0 * down / max(len(r), 1), len(r)))
