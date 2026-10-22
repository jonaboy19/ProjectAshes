# Numeric audit of the acrobatics clips (no Blender): floor clearance of soles / palms / head / torso, planted contact
# segments with slide, facing at start / end, travel direction.  usage: python cmu_acro_analyze.py [glb] [Clip,Clip] [--frames]
import sys
import numpy as np
from cmu_acro_lib import *   # noqa

args = [a for a in sys.argv[1:] if not a.startswith("--")]
glb = args[0] if args and args[0].endswith(".glb") else None
only = [a for a in args if not a.endswith(".glb")]
only = only[0].split(",") if only else None
g, rig, an = load(glb)
for name, ch in an.items():
    if only and name not in only and name.replace("MA_Acro_", "") not in only:
        continue
    c = Clip(rig, ch, name)
    cl = c.clearance()
    fa = c.facing(); pw = c.pelvis_world(); rw = c.root_world()
    tr = pw[-1] - pw[0]
    tdir = np.degrees(np.arctan2(tr[0], tr[2]))
    print("== %s  %d frames %.2fs  pelvis travel dx=%.2f dz=%.2f (dir %.0f deg)  root travel dx=%.2f dz=%.2f  facing %.0f -> %.0f  torso %.0f -> %.0f"
          % (name, c.nf + 1, c.nf / 30, tr[0], tr[2], tdir, rw[-1][0] - rw[0][0], rw[-1][2] - rw[0][2], fa[0], fa[-1], c.heading_torso()[0], c.heading_torso()[-1]))
    worst = sorted(((v.min(), k, int(v.argmin())) for k, v in cl.items()))[:6]
    print("   floor: " + "  ".join("%s %.3f@%d" % (k, m, f) for m, k, f in worst))
    for grp in ("toe", "palm", "head", "chest", "belly", "pelvis", "knee", "elbow"):
        bad = sum(int(np.sum(v < -0.02)) for k, v in cl.items() if k.startswith(grp))
        if bad:
            print("   below -2cm: %s frames*points=%d" % (grp, bad))
    cs = contact_segments(c)
    for eff, segs in cs.items():
        print("   %s: %s" % (eff, " ".join("[%d-%d h%.3f slide%.2f v%.1f]" % s for s in segs)))
    if "--frames" in sys.argv:
        for f in range(c.nf + 1):
            print("   f%3d pelvis y%.2f  facing %4.0f  lowest %s" % (f, pw[f, 1], fa[f], min(((v[f], k) for k, v in cl.items()))))
