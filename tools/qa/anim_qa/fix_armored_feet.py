# Asset fix found by the animation QA (tools/qa/anim_qa): the Meshy armored humanoids
# (kingdom/assets/incoming/ai3d/meshy/armored) have boot / sabaton vertices weighted to
# pelvis + thighs (the "skirt" clean-up in tools/meshy/armored_rig/armored_rig.py also
# catches wide boots near the floor). In game the feet then smear into paddles, sink up
# to 20-30 cm into the floor and slide. This re-binds the foot region to the foot / ball
# bones with a short blend into the existing weights above the ankle, and re-exports the
# GLB in place with the same exporter settings as armored_rig.py. Bones and rest poses
# are untouched (only vertex weights change).
#
# usage: blender -b --python fix_armored_feet.py -- <in.glb> [<out.glb>] [--report]
import bpy, sys, json
import numpy as np
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
REPORT = "--report" in argv
paths = [a for a in argv if not a.startswith("--")]
SRC = paths[0]
DST = paths[1] if len(paths) > 1 else SRC

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
mesh = next(o for o in bpy.context.scene.objects if o.type == "MESH")
bones = arm.data.bones
AW = arm.matrix_world


def head(name):
    return AW @ bones[name].head_local


def tail(name):
    return AW @ bones[name].tail_local


MW = mesh.matrix_world
V = np.array([(MW @ v.co)[:] for v in mesh.data.vertices])       # world, z up
names = [g.name for g in mesh.vertex_groups]
gi = {n: i for i, n in enumerate(names)}
W = np.zeros((len(V), len(names)))
for v in mesh.data.vertices:
    for g in v.groups:
        W[v.index, g.group] = g.weight
floor = V[:, 2].min()
stats = {"file": SRC.replace("\\", "/").split("/")[-1], "verts": len(V)}
changed = 0
for s in ("l", "r"):
    F = np.array(head("foot_" + s)[:])
    B = np.array(head("ball_" + s)[:])
    T = np.array(tail("ball_" + s)[:]) if "ball_leaf_" + s not in bones else np.array(head("ball_leaf_" + s)[:])
    C = np.array(head("calf_" + s)[:])
    ank = F[2] - floor                        # ankle height above the floor
    top = F[2] + 0.45 * ank                   # full foot weight below this
    blend_top = F[2] + 1.6 * ank              # blend back to the original weights by here
    # boot shaft: vertices around the knee -> ankle segment that are weighted to the
    # pelvis / thighs instead of the calf get calf weight (full at the ankle, fading out
    # towards the knee), so the shaft follows the shin instead of trailing behind.
    kz = C[2]
    seg = F - C
    ts = np.clip(((V - C) @ seg) / max(seg @ seg, 1e-9), 0, 1)
    ds = np.linalg.norm(V - (C + ts[:, None] * seg), axis=1)
    shin_r = 0.5 * ank + 0.07
    sideS = np.sign(V[:, 0]) == np.sign(F[0])
    legw = W[:, [gi[n] for n in ("calf_" + s, "foot_" + s, "ball_" + s) if n in gi]].sum(1)
    shaft = sideS & (ds < shin_r) & (V[:, 2] >= F[2] - 0.2 * ank) & (V[:, 2] < kz) & (legw < 0.8)
    ks = np.clip((kz - V[:, 2]) / max(kz - F[2], 1e-6), 0, 1) ** 0.5     # 1 at the ankle, 0 at the knee
    TS = np.zeros_like(W)
    TS[:, gi["calf_" + s]] = 1.0
    W[shaft] = W[shaft] * (1 - ks[shaft, None]) + TS[shaft] * ks[shaft, None]
    stats["shaft_%s" % s] = int(shaft.sum())
    changed += int(shaft.sum())
    # horizontal distance to the heel -> toe line of this foot
    fdir = (B - F)[:2] / max(np.linalg.norm((B - F)[:2]), 1e-9)
    heel2 = F[:2] - fdir * 0.6 * np.linalg.norm((B - F)[:2])
    a = heel2; b = T[:2]
    ab = b - a
    t = np.clip(((V[:, :2] - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    d = np.linalg.norm(V[:, :2] - (a + t[:, None] * ab), axis=1)
    foot_w = 0.55 * ank + 0.20                # sole half-width allowance (boot flares reach ~0.15 m out)
    side = np.sign(V[:, 0]) == np.sign(F[0])
    region = side & (d < foot_w) & (V[:, 2] < blend_top)
    fk = [gi[n] for n in ("foot_" + s, "ball_" + s, "calf_" + s) if n in gi]
    bad = region & (V[:, 2] < top) & (W[:, fk].sum(1) < 0.9)
    stats["foot_%s_region" % s] = int(region.sum())
    stats["foot_%s_badly_weighted" % s] = int(bad.sum())
    # target weights: foot, and ball for the part in front of the ball joint
    fwd = (V[:, :2] - B[:2]) @ ((B - F)[:2] / max(np.linalg.norm((B - F)[:2]), 1e-9))
    # armored boots are rigid: only the very tip follows the toe bone a little (the fitted
    # ball joint does not sit at the boot's flex line, so a full toe bend stretches the boot)
    wb = 0.25 * np.clip((fwd - 0.5 * np.linalg.norm((T - B)[:2])) / 0.03, 0, 1) if "ball_" + s in gi else np.zeros(len(V))
    Tgt = np.zeros_like(W)
    Tgt[:, gi["foot_" + s]] = 1 - wb
    if "ball_" + s in gi:
        Tgt[:, gi["ball_" + s]] = wb
    k = np.clip((blend_top - V[:, 2]) / max(blend_top - top, 1e-6), 0, 1)   # 1 at the sole, 0 at blend_top
    k = k * k * (3 - 2 * k)
    m = region
    W[m] = W[m] * (1 - k[m, None]) + Tgt[m] * k[m, None]
    changed += int((m & (k > 0.01)).sum())
# normalise, limit to 4 influences
W[W < 0.01] = 0
idx = np.argsort(-W, axis=1)[:, 4:]
np.put_along_axis(W, idx, 0, axis=1)
W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
stats["reweighted_verts"] = changed
print("FIXFEET", json.dumps(stats))
if REPORT:
    sys.exit(0)
for j, n in enumerate(names):
    g = mesh.vertex_groups[n]
    g.remove(list(range(len(V))))
    nz = np.nonzero(W[:, j])[0]
    for i in nz:
        g.add([int(i)], float(W[i, j]), "REPLACE")
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
mesh.select_set(True)
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", use_selection=True, export_animations=False,
                          export_draco_mesh_compression_enable=False, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)
print("WROTE", DST)
