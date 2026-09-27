"""Procedural 8-leg rig + IK-baked idle/walk/attack/hit/death for the Meshy giant spider.
args: mesh.glb outdir"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from proc_common import *
from groundfix import fix_ground
import numpy as np

a = sys.argv[sys.argv.index('--') + 1:]
src, outdir = a[0], a[1]
reset(30)
mesh = load_normalised(src, 'width', 1.5)
mesh.name = "spider"
P = np.array([v.co[:] for v in mesh.data.vertices])
H = P[:, 2].max()
print("SPIDER bbox", P.min(axis=0).round(3), P.max(axis=0).round(3))

C = np.array([0.0, -0.22, 0.30])          # cephalothorax centre (from ortho views)
ABD = ((0, 0.41, 0.35), (0.30, 0.44, 0.30))
CEPH = ((0, -0.24, 0.30), (0.17, 0.24, 0.16))
est = {1: (0.52, -0.82), 2: (0.74, -0.37), 3: (0.68, 0.09), 4: (0.51, 0.48)}
low = P[P[:, 2] < 0.05]
def in_body(Q):
    r = np.zeros(len(Q), bool)
    for c, rr in (ABD, CEPH):
        r |= (((Q - np.array(c)) / np.array(rr)) ** 2).sum(axis=1) <= 1.0
    return r
bones = [dict(name="root", head=(0, 0, 0), tail=(0, 0.25, 0), deform=False),
         dict(name="body", head=(0, -0.22, 0.30), tail=(0, 0.0, 0.30), parent="root"),
         dict(name="ceph", head=(0, -0.10, 0.31), tail=(0, -0.48, 0.28), parent="body"),
         dict(name="abdomen", head=(0, 0.0, 0.33), tail=(0, 0.82, 0.36), parent="body")]
legs = []
for side, sx in (("L", 1), ("R", -1)):
    for n, (ex, ey) in est.items():
        e = np.array([sx * ex, ey])
        near = low[np.linalg.norm(low[:, :2] - e, axis=1) < 0.12]
        if len(near) == 0:
            near = low[np.argsort(np.linalg.norm(low[:, :2] - e, axis=1))[:10]]
        tipv = near[np.argmin(near[:, 2])]
        tip = np.array([near[:, 0].mean(), near[:, 1].mean(), max(0.005, tipv[2])])
        d = tip[:2] - C[:2]; L = np.linalg.norm(d); u = d / L
        root = np.array([C[0] + 0.10 * u[0], C[1] + 0.10 * u[1], C[2]])
        ln = tip[:2] - root[:2]; LL = np.linalg.norm(ln); un = ln / LL
        rel = P[:, :2] - root[:2]
        along = rel @ un; perp = np.abs(rel[:, 0] * un[1] - rel[:, 1] * un[0])
        corr = (perp < 0.04) & ~in_body(P)
        def zc(t):
            s = P[corr & (np.abs(along - t * LL) < 0.03)]
            return None if len(s) < 3 else 0.5 * (s[:, 2].min() + s[:, 2].max())
        ts = [t for t in np.linspace(0.2, 0.65, 10) if zc(t) is not None]
        tk = max(ts, key=zc) if ts else 0.4
        knee_z = zc(tk) if ts else 0.45
        za = zc(0.82) or 0.5 * knee_z
        knee = np.array([*(root[:2] + un * tk * LL), knee_z])
        ank = np.array([*(root[:2] + un * 0.82 * LL), za])
        nm = f"{side}{n}"
        legs.append(nm)
        bones += [dict(name=f"femur_{nm}", head=tuple(root), tail=tuple(knee), parent="ceph"),
                  dict(name=f"tibia_{nm}", head=tuple(knee), tail=tuple(ank), parent=f"femur_{nm}"),
                  dict(name=f"tarsus_{nm}", head=tuple(ank), tail=tuple(tip), parent=f"tibia_{nm}"),
                  dict(name=f"ik_{nm}", head=tuple(tip), tail=tuple(tip + np.array([0, 0.08, 0])), parent="root", deform=False)]
        print("LEG", nm, "root", root.round(2), "knee", knee.round(2), "ankle", ank.round(2), "tip", tip.round(2))
arm = build_armature("spider", bones)
skin_nearest(mesh, arm, zones=[(ABD[0], ABD[1], ["abdomen"]), (CEPH[0], CEPH[1], ["ceph", "body"])])
print("UNWEIGHTED", sum(1 for v in mesh.data.vertices if not v.groups))
for nm in legs:
    add_ik(arm, f"tarsus_{nm}", f"ik_{nm}", 3)

X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
groupA = {"L1", "R2", "L3", "R4"}
out = {}

# walk: tetrapod gait, 24-frame loop, feet slide back in stance, lift in swing
an = Anim(arm, "walk"); T = 24; stride = 0.20; duty = 0.6
for f in range(T + 1):
    for nm in legs:
        u = (f / T + (0 if nm in groupA else 0.5)) % 1.0
        if u < duty:
            y = -stride / 2 + stride * (u / duty); z = 0
        else:
            t = (u - duty) / (1 - duty); y = stride / 2 - stride * t; z = 0.09 * math.sin(math.pi * t)
        an.loc(f, f"ik_{nm}", (0, y, z))
    an.loc(f, "body", (0, 0, 0.012 * math.sin(4 * math.pi * f / T)))
    an.rot(f, "body", Z, 2.0 * math.sin(2 * math.pi * f / T))
    an.rot(f, "abdomen", X, 3.0 * math.sin(2 * math.pi * f / T + 1))
out["walk"] = an

an = Anim(arm, "idle"); T = 60
for f in range(0, T + 1, 2):
    s = math.sin(2 * math.pi * f / T)
    an.loc(f, "body", (0, 0, 0.012 * s))
    an.rot(f, "abdomen", X, 2.5 * math.sin(2 * math.pi * f / T + 0.8))
    for nm in legs:
        an.loc(f, f"ik_{nm}", (0, 0, 0))
    tw = max(0.0, math.sin(4 * math.pi * f / T)) ** 3
    an.loc(f, "ik_L1", (0, -0.02 * tw, 0.05 * tw))
    an.loc(f, "ik_R1", (0, -0.02 * tw, 0.05 * tw))
out["idle"] = an

def pose_keys(an, f, body_z=0.0, pitch=0.0, front=(0, 0, 0), back_y=0.0, abd=0.0, curl=0.0, body_y=0.0, roll=0.0):
    an.loc(f, "body", (0, body_y, body_z))
    an.rot(f, "body", X, pitch)   # negative pitch = front up
    if roll: an.rot(f, "body", Y, roll)
    an.rot(f, "abdomen", X, abd)
    for nm in legs:
        if nm[1] == "1":
            v = front
        else:
            v = (0, back_y, 0)
        if curl:
            b = arm.data.bones[f"ik_{nm}"].head_local
            v = (v[0] - b.x * 0.55 * curl, v[1] - (b.y + 0.2) * 0.55 * curl, v[2] + 0.12 * curl)
        an.loc(f, f"ik_{nm}", v)

# attack: rear up with the front legs raised, then stab down
an = Anim(arm, "attack")
pose_keys(an, 0)
pose_keys(an, 8, body_z=0.06, pitch=-22, front=(0, -0.05, 0.42), back_y=0.03, abd=8)
pose_keys(an, 12, body_z=0.07, pitch=-26, front=(0, -0.02, 0.48), back_y=0.03, abd=10)
pose_keys(an, 17, body_z=-0.03, pitch=10, front=(0, -0.22, 0.0), back_y=-0.02, abd=-6)
pose_keys(an, 22, body_z=-0.02, pitch=6, front=(0, -0.20, 0.0), abd=-3)
pose_keys(an, 32)
out["attack"] = an

an = Anim(arm, "hit")
pose_keys(an, 0)
pose_keys(an, 3, body_z=0.02, pitch=-9, body_y=0.06, abd=6)
pose_keys(an, 8, body_z=-0.01, pitch=3, body_y=0.02, abd=-2)
pose_keys(an, 14)
out["hit"] = an

an = Anim(arm, "death")
pose_keys(an, 0)
pose_keys(an, 6, body_z=0.04, pitch=-12, front=(0, 0, 0.2), abd=6)
pose_keys(an, 16, body_z=-0.18, pitch=4, roll=8, curl=0.4, abd=-4)
pose_keys(an, 30, body_z=-0.22, pitch=2, roll=10, curl=0.75, abd=-6)
pose_keys(an, 45, body_z=-0.22, pitch=2, roll=10, curl=0.75, abd=-6)
out["death"] = an

for nm, an in out.items():
    ctl, f0, f1 = an.write()
    bake(arm, ctl, f0, f1, nm)
clear_constraints(arm)
fix_ground(arm, mesh, "root", skip=("death", "attack"), tol=0.01)
for tag, t, px in (("", 15000, 1024), ("_lod1", 5000, 512)):
    n = decimate_to(mesh, t); cap_images(px)
    print("TIER spider", tag or "lod0", n, px, "bones", len(arm.data.bones))
    export(os.path.join(outdir, f"spider{tag}.glb"), [arm, mesh])
