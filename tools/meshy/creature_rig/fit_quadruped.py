"""Fit a CC0 Quaternius quadruped armature (with its actions) to a Meshy mesh.
usage: blender -b --python fit_quadruped.py -- name mesh.glb donor.gltf shoulder_m outdir "out=Donor,..." [nodeform,prefixes]
"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *
from groundfix import fix_ground
from mathutils import Vector, Matrix
import numpy as np

a = sys.argv[sys.argv.index('--') + 1:]
name, meshfile, donorfile, shoulder, outdir = a[0], a[1], a[2], float(a[3]), a[4]
clipmap = dict(c.split('=') for c in a[5].split(','))
nodeform = [x for x in (a[6].split(',') if len(a) > 6 else []) if x]
reset(30)


def verts_np(o):
    mw = o.matrix_world
    return np.array([(mw @ v.co)[:] for v in o.data.vertices])


def landmarks(P):
    H = P[:, 2].max()
    low = P[P[:, 2] < 0.07 * H]
    ymid = 0.5 * (low[:, 1].min() + low[:, 1].max())
    feet = {}
    for k, cond in (("FL", (low[:, 1] < ymid) & (low[:, 0] > 0)), ("FR", (low[:, 1] < ymid) & (low[:, 0] <= 0)),
                    ("BL", (low[:, 1] >= ymid) & (low[:, 0] > 0)), ("BR", (low[:, 1] >= ymid) & (low[:, 0] <= 0))):
        feet[k] = low[cond].mean(axis=0)
    yF = 0.5 * (feet["FL"][1] + feet["FR"][1]); yB = 0.5 * (feet["BL"][1] + feet["BR"][1])
    L = P[:, 1].max() - P[:, 1].min()
    band = P[np.abs(P[:, 1] - (yF + 0.06 * (yB - yF))) < 0.03 * L]
    sh = band[:, 2].max()
    spread = 0.5 * ((feet["FL"][0] - feet["FR"][0]) + (feet["BL"][0] - feet["BR"][0]))
    return dict(H=H, yF=yF, yB=yB, ymin=P[:, 1].min(), ymax=P[:, 1].max(), sh=sh, spread=spread, feet=feet, P=P)


def centerline(lm, y, legtop):
    P = lm["P"]; L = lm["ymax"] - lm["ymin"]
    for w in (0.02, 0.04, 0.08):
        s = P[(np.abs(P[:, 1] - y) < w * L) & (P[:, 2] > legtop)]
        if len(s) > 10:
            return 0.5 * (s[:, 2].min() + s[:, 2].max()), max(1e-3, s[:, 2].max() - s[:, 2].min())
    return None, None


# ---- target mesh: ground it, centre it, scale to shoulder height
objs, _ = import_new(meshfile)
tgt = [o for o in objs if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = tgt
for o in bpy.data.objects: o.select_set(o == tgt)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
P = verts_np(tgt)
tgt.data.transform(Matrix.Translation(Vector((-(P[:, 0].max() + P[:, 0].min()) / 2,
                                               -(P[:, 1].max() + P[:, 1].min()) / 2, -P[:, 2].min()))))
T = landmarks(verts_np(tgt))
tgt.data.transform(Matrix.Scale(shoulder / T["sh"], 4)); tgt.data.update()
T = landmarks(verts_np(tgt))
print("TARGET", name, "H=%.3f shoulder=%.3f len=%.3f yF=%.3f yB=%.3f spread=%.3f" % (
    T["H"], T["sh"], T["ymax"] - T["ymin"], T["yF"], T["yB"], T["spread"]))

# ---- donor
dobjs, dacts = import_new(donorfile)
arm = [o for o in dobjs if o.type == 'ARMATURE'][0]
dmesh = [o for o in dobjs if o.type == 'MESH']
for o in dobjs:
    if o.animation_data: o.animation_data.action = None
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
D = landmarks(np.vstack([verts_np(m) for m in dmesh]))
s = T["sh"] / D["sh"]
print("DONOR H=%.3f shoulder=%.3f yF=%.3f yB=%.3f spread=%.3f scale=%.4f" % (D["H"], D["sh"], D["yF"], D["yB"], D["spread"], s))


def mapY(y):
    if y < D["yF"]:
        t = (y - D["yF"]) / (D["ymin"] - D["yF"]); return T["yF"] + t * (T["ymin"] - T["yF"])
    if y <= D["yB"]:
        t = (y - D["yF"]) / (D["yB"] - D["yF"]); return T["yF"] + t * (T["yB"] - T["yF"])
    t = (y - D["yB"]) / (D["ymax"] - D["yB"]); return T["yB"] + t * (T["ymax"] - T["yB"])


kx = T["spread"] / D["spread"]; kz = T["sh"] / D["sh"]
SPINE = ("Body", "Back", "Torso", "Neck", "Head", "Ear", "Tail")
legtopD = 0.45 * D["sh"]; legtopT = 0.45 * T["sh"]


def mapP(p, spine):
    y2 = mapY(p.y); x2 = p.x * kx
    if spine and p.z > legtopD:
        cD, tD = centerline(D, p.y, legtopD); cT, tT = centerline(T, y2, legtopT)
        if cD is not None and cT is not None:
            r = min(2.0, max(0.5, tT / tD))
            return Vector((x2, y2, cT + (p.z - cD) * r))
    return Vector((x2, y2, p.z * kz))


for m in dmesh: bpy.data.objects.remove(m)
bpy.context.view_layer.objects.active = arm
for o in bpy.data.objects: o.select_set(o == arm)
bpy.ops.object.mode_set(mode='EDIT')
eb = arm.data.edit_bones
new = {b.name: (mapP(b.head.copy(), b.name.startswith(SPINE)), mapP(b.tail.copy(), b.name.startswith(SPINE))) for b in eb}


def fit_tail():
    """Lay the donor tail chain along the target's own tail (which may hang down, unlike the donor's)."""
    Pt = T["P"]; L = T["ymax"] - T["ymin"]; sh = T["sh"]
    upper = Pt[Pt[:, 2] > 0.7 * sh]
    y_r = upper[:, 1].max()
    zt = upper[np.abs(upper[:, 1] - y_r) < 0.05 * L][:, 2]
    root = np.array([0.0, y_r - 0.04 * L, 0.5 * (zt.min() + zt.max()) if len(zt) else 0.8 * sh])
    tv = Pt[(Pt[:, 1] > y_r - 0.01 * L) & (Pt[:, 2] > 0.08 * sh) & (np.abs(Pt[:, 0]) < 0.2 * T["spread"])]
    if len(tv) < 20:
        return None
    d = np.linalg.norm(tv - root, axis=1)
    if d.max() < 0.12 * sh:
        return None
    edges = np.linspace(0, d.max(), 9)
    poly = [root]
    for i in range(8):
        sel = tv[(d >= edges[i]) & (d <= edges[i + 1])]
        if len(sel): poly.append(sel.mean(axis=0))
    poly = np.array(poly)
    seg = np.linalg.norm(np.diff(poly, axis=0), axis=1); cum = np.concatenate([[0], np.cumsum(seg)])
    def at(f):
        x = f * cum[-1]; i = min(len(seg) - 1, np.searchsorted(cum, x, side='right') - 1)
        t = (x - cum[i]) / max(1e-6, seg[i]); return Vector(poly[i] + t * (poly[i + 1] - poly[i]))
    chain = sorted([b.name for b in eb if b.name.startswith("Tail")], key=lambda n: int(n[4:]))
    lens = [eb[n].length for n in chain]; c = np.concatenate([[0], np.cumsum(lens)]) / sum(lens)
    print("TAIL fit length %.3f points %d" % (cum[-1], len(poly)))
    return {n: (at(c[i]), at(c[i + 1])) for i, n in enumerate(chain)}


tail = None if "Tail" in nodeform else fit_tail()
if tail:
    new.update(tail)
else:
    print("TAIL too small: tail bones collapsed onto the rump, non-deforming")
    nodeform.append("Tail")
    for n in [b.name for b in eb if b.name.startswith("Tail")]:
        h, _ = new["Tail1"]; new[n] = (h, h + Vector((0, 0.02, 0)))
for b in eb:
    h, t = new[b.name]
    b.head = h / s; b.tail = t / s
bpy.ops.object.mode_set(mode='OBJECT')
arm.scale = (s, s, s)
arm.data.pose_position = 'POSE'
bpy.context.view_layer.update()
for b in arm.data.bones:
    if b.name == "Body" or b.name.startswith(("IK", "Pole", "FF")) or any(b.name.startswith(x) for x in nodeform):
        b.use_deform = False
print("DEFORM", len([b for b in arm.data.bones if b.use_deform]), "of", len(arm.data.bones))

# ---- weights: bone heat on a watertight voxel proxy, transferred to the real mesh
arm.data.pose_position = 'REST'
for div in (110, 80, 140, 60, 170):
    proxy = tgt.copy(); proxy.data = tgt.data.copy(); bpy.context.scene.collection.objects.link(proxy)
    proxy.parent = None; proxy.modifiers.clear()
    for vg in list(proxy.vertex_groups): proxy.vertex_groups.remove(vg)
    vm = proxy.modifiers.new("vox", 'REMESH'); vm.mode = 'VOXEL'
    vm.voxel_size = max(T["H"], T["ymax"] - T["ymin"]) / div
    bpy.context.view_layer.objects.active = proxy
    for o in bpy.data.objects: o.select_set(o == proxy)
    bpy.ops.object.modifier_apply(modifier="vox")
    for o in bpy.data.objects: o.select_set(o in (proxy, arm))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    unw = sum(1 for v in proxy.data.vertices if not v.groups)
    print("PROXY div", div, "faces", len(proxy.data.polygons), "unweighted", unw, "of", len(proxy.data.vertices))
    if unw < 0.01 * len(proxy.data.vertices):
        break
    bpy.data.objects.remove(proxy)
else:
    raise SystemExit("bone heat failed for every proxy resolution")
for o in bpy.data.objects: o.select_set(o == tgt)
bpy.context.view_layer.objects.active = tgt
for vg in proxy.vertex_groups: tgt.vertex_groups.new(name=vg.name)
dt = tgt.modifiers.new("dt", 'DATA_TRANSFER'); dt.object = proxy
dt.use_vert_data = True; dt.data_types_verts = {'VGROUP_WEIGHTS'}; dt.vert_mapping = 'POLYINTERP_NEAREST'
dt.layers_vgroup_select_src = 'ALL'; dt.layers_vgroup_select_dst = 'NAME'
bpy.ops.object.modifier_apply(modifier="dt")
bpy.ops.object.vertex_group_clean(group_select_mode='ALL', limit=0.01)
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
bpy.data.objects.remove(proxy)
print("UNWEIGHTED target verts", sum(1 for v in tgt.data.vertices if not v.groups))
tgt.parent = arm; tgt.matrix_parent_inverse = arm.matrix_world.inverted()
am = tgt.modifiers.new("Armature", 'ARMATURE'); am.object = arm
arm.data.pose_position = 'POSE'

# ---- actions
arm.name = name + "_rig"; tgt.name = name
keep = {out: [x for x in dacts if x.name == src][0] for out, src in clipmap.items()}
for ac in list(bpy.data.actions):
    if ac not in keep.values(): bpy.data.actions.remove(ac)
for out, ac in keep.items():
    ac.name = out; ac.use_fake_user = True
    ac.slots[0].name_display = arm.name
arm.animation_data_create()
from mathutils import Quaternion
def damp(ac, prefix, f):
    """Scale rotations of bones starting with prefix towards rest (the target's tail rests in a different pose)."""
    for lay in ac.layers:
        for st in lay.strips:
            for cb in st.channelbags:
                groups = {}
                for fc in cb.fcurves:
                    if fc.data_path.endswith("rotation_quaternion") and fc.data_path.split('"')[1].startswith(prefix):
                        groups.setdefault(fc.data_path, [None] * 4)[fc.array_index] = fc
                for fcs in groups.values():
                    if None in fcs: continue
                    for i in range(len(fcs[0].keyframe_points)):
                        q = Quaternion([fc.keyframe_points[i].co[1] for fc in fcs])
                        q2 = Quaternion().slerp(q, f)
                        for j, fc in enumerate(fcs):
                            fc.keyframe_points[i].co[1] = q2[j]
                            fc.keyframe_points[i].handle_left[1] = q2[j]; fc.keyframe_points[i].handle_right[1] = q2[j]
                    for fc in fcs: fc.update()
TAILDAMP = float(os.environ.get("TAILDAMP", "0.35"))
for ac in keep.values():
    damp(ac, "Tail", TAILDAMP)
fix_ground(arm, tgt, "Body", tol=0.01 * T["sh"])
for tag, t, px in (("", 15000, 1024), ("_lod1", 5000, 512)):
    n = decimate_to(tgt, t); cap_images(px)
    print("TIER", name, tag or "lod0", n, px, "bones", len(arm.data.bones))
    export(os.path.join(outdir, f"{name}{tag}.glb"), [arm, tgt])
