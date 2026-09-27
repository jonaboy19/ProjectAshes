# Rig an unrigged Meshy T/A-pose humanoid (single textured mesh) onto the exact
# Quaternius UAL skeleton (same rest orientations as the MakeHuman / G6 / CDmir
# characters), so every UAL-library clip plays on it through Assets._ual_for().
#
# usage: blender -b --python armored_rig.py -- <config.json> [--debug]
#
# Steps
#  1. import the (Meshy-remeshed) GLB, join, weld UV-seam duplicates
#  2. find landmarks: hand tips, arm line (tracked from the tip inward), torso width,
#     shoulder, feet; place every UAL joint (UAL proportions scaled by the shoulder
#     height; arm joints on the fitted arm line). Config "overrides" can pin values.
#  3. bone-heat weights on the fitted rig (deform bones only; fingers -> hand)
#  4. rigid-armor clean-up: helmet -> Head, pauldrons -> upperarm/clavicle, arm/leg
#     bleed removed, skirts/coats/capes below the pelvis -> pelvis + thighs with a
#     smooth falloff, optional rigid boxes (bow -> spine_03 ...), smooth, 4 influences
#  5. pose into the UAL T-pose, bake, scale to the UAL pelvis height, fit the final
#     UAL armature by translation only (rest rotations stay bit-identical to UAL)
#  6. LOD0 (<= tris budget, 1024 px) and LOD1 (decimated, 512 px), same skeleton,
#     no Draco. Writes <name>.glb, <name>_lod1.glb and <name>_report.json.
import bpy, bmesh, sys, os, json, math, re
import numpy as np
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
cfg = json.load(open(argv[0], encoding="utf-8"))
DEBUG = "--debug" in argv
ov = cfg.get("overrides", {})
NAME = cfg["name"]
OUT = cfg["out_dir"]
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=cfg["source"])
meshes = [o for o in sc.objects if o.type == "MESH"]
for o in meshes:
    mw = o.matrix_world.copy(); o.parent = None; o.data.transform(mw); o.matrix_world = Matrix()
for o in [o for o in sc.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o, do_unlink=True)
if len(meshes) > 1:
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
M = bpy.context.view_layer.objects.active if len(meshes) > 1 else meshes[0]
M.name = NAME + "_body"; M.data.name = NAME + "_body"
bm = bmesh.new(); bm.from_mesh(M.data)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
bm.to_mesh(M.data); bm.free()
# feet on the floor, centred in x/y on the feet
V = np.array([v.co[:] for v in M.data.vertices])
V[:, 2] -= V[:, 2].min()
H = float(V[:, 2].max())

# ---- UAL reference (and its mannequin for calibration) -----------------------
def import_ual(name, keep_mesh=False):
    before = set(bpy.data.objects); ba = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=cfg["ual"])
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == "ARMATURE"][0]
    mesh = None
    for o in new:
        if o is arm:
            continue
        if keep_mesh and o.name.startswith("Mannequin"):
            mesh = o; continue
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in ba:
            bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()
    arm.name = name
    return arm, mesh

FINAL, MANN = import_ual("UAL_Final", keep_mesh=True)
TMP, _ = import_ual("UAL_Tmp")
U = {b.name: (FINAL.matrix_world @ b.head_local, FINAL.matrix_world @ b.tail_local) for b in FINAL.data.bones}
par = {b.name: (b.parent.name if b.parent else None) for b in FINAL.data.bones}
kids = {b.name: [c.name for c in b.children] for b in FINAL.data.bones}
order = []
def walk(n):
    order.append(n)
    for c in kids[n]:
        walk(c)
for n, p in par.items():
    if p is None:
        walk(n)
dg = bpy.context.evaluated_depsgraph_get()
me_eval = MANN.evaluated_get(dg).to_mesh()
VU = np.array([(MANN.matrix_world @ v.co)[:] for v in me_eval.vertices])
MANN.evaluated_get(dg).to_mesh_clear()
bpy.data.objects.remove(MANN, do_unlink=True)

# ---- landmark detection (same code on the mannequin -> calibration ratios) ----
def landmarks(V, o=None):
    o = o or {}
    L = {}
    H = V[:, 2].max()
    for s, side in ((1, "l"), (-1, "r")):
        sx = s * V[:, 0]
        tip = V[np.argmax(sx)]
        L["tip_" + side] = tip
        tx = s * tip[0]
        # track the arm from the tip inward in 2.5 cm x-slabs
        pts = []; zp = tip[2]; yp = tip[1]; slope = 0.0
        x = tx - 0.03
        while x > tx * 0.40:
            m = (sx > x - 0.0125) & (sx <= x + 0.0125) & (np.abs(V[:, 2] - (zp - slope * 0.025)) < 0.12 * H / 1.8)
            if m.sum() < 3:
                x -= 0.025; continue
            z = 0.5 * (V[m, 2].max() + V[m, 2].min()); y = 0.5 * (V[m, 1].max() + V[m, 1].min())
            if pts:
                slope = 0.7 * slope + 0.3 * ((z - pts[-1][2]) / -0.025) if len(pts) > 2 else (z - pts[-1][2]) / -0.025
            pts.append((x, y, z)); zp = z; yp = y
            x -= 0.025
        P = np.array(pts)
        lo_, hi_ = o.get("arm_fit_range", (0.45, 0.75))
        sel = (P[:, 0] > tx * lo_) & (P[:, 0] < tx * hi_)
        A = P[sel]
        cz = np.polyfit(A[:, 0], A[:, 2], 1); cy = np.polyfit(A[:, 0], A[:, 1], 1)
        L["arm_" + side] = (cz, cy, tx)
        L["track_" + side] = P
    return L

def torso_halfwidth(V, z, H):
    # half width of the torso: from x=0 outward until a gap of >= 3 cm (arm / torso gap)
    m = np.abs(V[:, 2] - z) < 0.03 * H / 1.8
    xs = np.abs(V[m, 0])
    bins = np.zeros(200, bool)
    bins[np.clip((xs / 0.01).astype(int), 0, 199)] = True
    i = int(np.argmax(bins))
    while i < 197 and (bins[i] or bins[i + 1] or bins[i + 2]):
        i += 1
    return i * 0.01

def fit(V, o, calib=None):
    """joint positions dict for mesh V (T/A pose)."""
    H = V[:, 2].max()
    L = landmarks(V, o)
    J = {}
    # shoulder: iterate x_sh <-> z_sh
    res = {}
    for side, s in (("l", 1), ("r", -1)):
        cz, cy, tx = L["arm_" + side]
        x_sh = 0.2 * tx
        for _ in range(3):
            z_sh = np.polyval(cz, x_sh)
            thw = torso_halfwidth(V, z_sh - 0.20 * z_sh / 1.441, H)
            if calib:
                x_sh = min(thw * calib["sh_ratio"], 0.205 * z_sh / 1.441)
            else:
                x_sh = 0.192
        x_sh = o.get("shoulder_x", x_sh)
        z_sh = float(np.polyval(cz, x_sh)) + o.get("shoulder_dz", 0.0)
        res[side] = dict(x_sh=x_sh, z_sh=z_sh, thw=thw, tx=tx, cz=cz, cy=cy)
    return L, res

# calibration on the UAL mannequin
LU, RU = fit(VU, {}, None)
thw_u = 0.5 * (RU["l"]["thw"] + RU["r"]["thw"])
calib = {"sh_ratio": 0.192 / max(thw_u, 1e-3)}
# arm fraction along shoulder->tip for elbow/wrist in UAL
tip_u = 0.5 * (LU["tip_l"][0] - LU["tip_r"][0])
f_elb = (U["lowerarm_l"][0].x - 0.192) / (tip_u - 0.192)
f_wri = (U["hand_l"][0].x - 0.192) / (tip_u - 0.192)
def ankle_stats(V, H):
    m = (V[:, 2] > 0.03 * H) & (V[:, 2] < 0.075 * H) & (np.abs(V[:, 0]) < 0.25 * H)
    A = V[m]
    out = {}
    for s, side in ((1, "l"), (-1, "r")):
        B = A[s * A[:, 0] > 0.02]
        out[side] = (float(np.median(B[:, 0])), float(np.median(B[:, 1])))
    return out
AU = ankle_stats(VU, VU[:, 2].max())
def head_y(V, z0, z1):
    m = (V[:, 2] > z0) & (V[:, 2] < z1) & (np.abs(V[:, 0]) < 0.08)
    return float(np.median(V[m, 1]))
L, R = fit(V, ov, calib)
print("CALIB", calib, "f_elb", f_elb, "f_wri", f_wri, "tip_u", tip_u)
print("SHOULDERS", {k: (round(v["x_sh"], 3), round(v["z_sh"], 3), round(v["thw"], 3)) for k, v in R.items()})

z_sh = 0.5 * (R["l"]["z_sh"] + R["r"]["z_sh"])
if "arm_pts" in ov:
    z_sh = ov["arm_pts"]["sh"][1]
k = z_sh / U["upperarm_l"][0].z          # vertical scale vs UAL
kl = ov.get("leg_scale", 1.0) * k         # legs
AN = ankle_stats(V, H)
dy_head = head_y(V, z_sh + 0.05 * k, z_sh + 0.25 * k) - head_y(VU, U["upperarm_l"][0].z + 0.05, U["upperarm_l"][0].z + 0.25)
dy_foot = 0.5 * (AN["l"][1] + AN["r"][1]) - 0.5 * (AU["l"][1] + AU["r"][1])
dy_head += ov.get("dy_head", 0.0); dy_foot += ov.get("dy_foot", 0.0)
pelvis_z = ov.get("pelvis_z", U["pelvis"][0].z * kl)
thigh_z = pelvis_z + (U["thigh_l"][0].z - U["pelvis"][0].z) * kl
pos = {}
def lerp(a, b, t): return a + (b - a) * t
for n in order:
    u = U[n][0]
    if n == "root":
        pos[n] = Vector((0, 0, 0))
    elif n in ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"):
        if n == "pelvis":
            z = pelvis_z
        else:
            # distribute between pelvis and shoulder-referenced upper body
            z = pelvis_z + (u.z - U["pelvis"][0].z) / (U["upperarm_l"][0].z - U["pelvis"][0].z) * (z_sh - pelvis_z)
        t = min(1.0, max(0.0, (z - pelvis_z) / max(z_sh - pelvis_z, 1e-3)))
        pos[n] = Vector((0, u.y * k + lerp(dy_foot, dy_head, t), z))
    elif n.startswith("clavicle"):
        s = 1 if n.endswith("_l") else -1
        pos[n] = Vector((s * 0.019 * k, pos["spine_03"].y + (u.y - U["spine_03"][0].y) * k, z_sh + (u.z - U["upperarm_l"][0].z) * k))
    elif n.startswith(("thigh", "calf", "foot", "ball")):
        s = 1 if n.endswith("_l") else -1; side = "l" if s > 0 else "r"
        fx, fy = AN[side]
        fx = s * ov.get("foot_x", abs(fx))
        ux = abs(u.x) - abs(U["thigh_l"][0].x)
        if n.startswith("thigh"):
            pos[n] = Vector((fx * ov.get("hip_x_ratio", 1.0), (u.y - AU[side][1]) * kl + fy, thigh_z))
        else:
            z = u.z / U["calf_l"][0].z * (thigh_z * U["calf_l"][0].z / U["thigh_l"][0].z) if n.startswith("calf") else u.z * kl
            pos[n] = Vector((fx, (u.y - AU[side][1]) * kl + fy, z))
arm_desc = {}
for side in ("l", "r"):
    s = 1 if side == "l" else -1
    r = R[side]
    def armpt(x):
        return Vector((s * x, float(np.polyval(r["cy"], x)), float(np.polyval(r["cz"], x))))
    tx = r["tx"]; xs = r["x_sh"]
    sh = armpt(xs); sh.z += ov.get("shoulder_dz", 0.0)
    tip = Vector(L["tip_" + side].tolist())
    # polyline shoulder -> tracked arm centres -> tip; joints at UAL arc-length fractions
    P = L["track_" + side]
    poly = [sh] + [Vector((s * p[0], p[1], p[2])) for p in P[::-1] if p[0] > xs + 0.06 and p[0] < tx - 0.02] + [tip]
    cum = [0.0]
    for i in range(1, len(poly)):
        cum.append(cum[-1] + (poly[i] - poly[i - 1]).length)
    Lr = cum[-1]
    def at(f):
        t = f * Lr
        for i in range(1, len(poly)):
            if cum[i] >= t:
                u_ = (t - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-9)
                return poly[i - 1].lerp(poly[i], u_)
        return poly[-1].copy()
    pos["upperarm_" + side] = sh
    pos["lowerarm_" + side] = at(f_elb) + Vector(ov.get("elbow_off", (0, 0, 0)))
    pos["hand_" + side] = at(f_wri) + Vector(ov.get("wrist_off", (0, 0, 0)))
    if "arm_pts" in ov:
        # manual arm joints [x, z] (mirrored); depth = median y of the mesh around the point
        def local(xz):
            x_, z_ = s * xz[0], xz[1]
            mm = np.hypot(V[:, 0] - x_, V[:, 2] - z_) < 0.07
            return Vector((x_, float(np.median(V[mm, 1])) if mm.sum() else 0.0, z_))
        ap = ov["arm_pts"]
        sh = local(ap["sh"]); pos["upperarm_" + side] = sh
        pos["lowerarm_" + side] = local(ap["elb"]); pos["hand_" + side] = local(ap["wri"])
        tip = local(ap["tip"])
        L["tip_" + side] = np.array(tip[:])
        seg_ = [sh, pos["lowerarm_" + side], pos["hand_" + side], tip]
        Lr = sum((seg_[i + 1] - seg_[i]).length for i in range(3))
    d = (tip - pos["hand_" + side]).normalized()
    # fingers: UAL offsets from the hand, rotated from UAL arm dir to the fitted arm dir
    rot = Vector((s, 0, 0)).rotation_difference(d).to_matrix()
    ka = Lr / (tip_u - 0.192)
    stack = list(kids["hand_" + side])
    while stack:
        c = stack.pop()
        pos[c] = pos["hand_" + side] + rot @ ((U[c][0] - U["hand_" + side][0]) * ka)
        stack += kids[c]
    arm_desc[side] = d

# ---- build the Tmp rig on the fitted joints ----------------------------------
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = TMP; TMP.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
inv = TMP.matrix_world.inverted()
CHILD = {"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01", "neck_01": "Head",
         "clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
         "clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
         "thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l", "ball_l": "ball_leaf_l",
         "thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r", "ball_r": "ball_leaf_r"}
for n in order:
    eb = TMP.data.edit_bones[n]
    ln = max((U[n][1] - U[n][0]).length * k, 0.005)
    if n in CHILD:
        dvec = pos[CHILD[n]] - pos[n]
        dvec = dvec.normalized() if dvec.length > 1e-5 else (U[n][1] - U[n][0]).normalized()
    elif n.startswith(tuple(f + "_0" for f in ("index", "middle", "ring", "pinky", "thumb"))):
        side = n[-1]
        dvec = Vector((1 if side == "l" else -1, 0, 0)).rotation_difference(arm_desc[side]).to_matrix() @ (U[n][1] - U[n][0]).normalized()
    else:
        dvec = (U[n][1] - U[n][0]).normalized()
    eb.head = inv @ pos[n]
    eb.tail = inv @ (pos[n] + dvec * ln)
bpy.ops.object.mode_set(mode="OBJECT")

# ---- debug render of the fitted joints ----------------------------------------
if DEBUG:
    for n in order:
        if "leaf" in n or n.startswith(("index", "middle", "ring", "pinky", "thumb")):
            continue
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.018, location=pos[n], segments=8, ring_count=6)
        sp = bpy.context.active_object; sp.name = "J_" + n
        mat = bpy.data.materials.get("jm") or bpy.data.materials.new("jm")
        mat.use_nodes = True
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1, 0.05, 0.05, 1)
        mat.node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value = (1, 0, 0, 1)
        mat.node_tree.nodes["Principled BSDF"].inputs["Emission Strength"].default_value = 2.0
        sp.data.materials.append(mat); sp.show_in_front = True

# ---- weights -----------------------------------------------------------------
DEFORM = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"] + \
    [b + "_" + s for s in ("l", "r") for b in ("clavicle", "upperarm", "lowerarm", "hand", "thigh", "calf", "foot", "ball")]
for b in TMP.data.bones:
    b.use_deform = b.name in DEFORM
M.data.transform(Matrix.Translation((0, 0, -min(v.co.z for v in M.data.vertices))))
for mdf in list(M.modifiers):
    M.modifiers.remove(mdf)
M.vertex_groups.clear()
bpy.ops.object.select_all(action="DESELECT")
M.select_set(True); TMP.select_set(True)
bpy.context.view_layer.objects.active = TMP
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
V = np.array([v.co[:] for v in M.data.vertices])
nv = len(V)
gi = {g.name: g.index for g in M.vertex_groups}
for b in DEFORM:
    if b not in gi:
        g = M.vertex_groups.new(name=b); gi[b] = g.index
BI = {b: i for i, b in enumerate(DEFORM)}
W = np.zeros((nv, len(DEFORM)))
inv_gi = {v: k_ for k_, v in gi.items()}
for v in M.data.vertices:
    for g in v.groups:
        nme = inv_gi.get(g.group)
        if nme in BI:
            W[v.index, BI[nme]] = g.weight

# bone segments (for distance tests)
def seg_end(n):
    if n == "Head":
        return pos["Head"] + Vector((0, 0, 0.25 * k))
    if n.startswith("hand"):
        return Vector(L["tip_" + n[-1]].tolist())
    if n.startswith("ball"):
        return pos["ball_leaf_" + n[-1]]
    return pos[CHILD[n]]
SEG = {n: (np.array(pos[n][:]), np.array(seg_end(n)[:])) for n in DEFORM}
def seg_dist(P, n):
    a, b = SEG[n]; ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)
D = np.stack([seg_dist(V, n) for n in DEFORM], axis=1)

# 0) verts heat missed -> nearest segment
miss = W.sum(1) < 1e-4
W[miss, np.argmin(D[miss], axis=1)] = 1.0
print("heat-missed verts", int(miss.sum()), "of", nv)
# forearm radius (mid forearm cross-section) -> limb bleed limits
def limb_radius(side):
    a, b = SEG["lowerarm_" + side]
    c = (a + b) / 2; d = (b - a) / np.linalg.norm(b - a)
    m = (np.abs((V - c) @ d) < 0.02) & (np.linalg.norm(V - c, axis=1) < 0.2 * k)
    return float(np.percentile(seg_dist(V[m], "lowerarm_" + side), 90)) if m.sum() > 5 else 0.06
r_fa = max(0.045, 0.5 * (limb_radius("l") + limb_radius("r")))
print("forearm radius", r_fa)
LIM = {"upperarm": ov.get("upperarm_lim", 2.6 * r_fa), "lowerarm": 1.9 * r_fa, "hand": 2.2 * r_fa,
       "clavicle": ov.get("upperarm_lim", 2.6 * r_fa) + 0.03, "calf": ov.get("calf_lim", 0.11 * k), "foot": 0.14 * k, "ball": 0.12 * k}
# 1) remove limb bleed (cape/coat/torso verts that picked up arm or leg weights)
for n in DEFORM:
    base = n[:-2] if n[-2:] in ("_l", "_r") else n
    if base in LIM:
        far = D[:, BI[n]] > LIM[base]
        W[far, BI[n]] = 0.0
# 2) skirts / coats / capes below the pelvis: away from the leg cores -> pelvis + thighs
calf_z = pos["calf_l"].z
r_thigh = ov.get("thigh_r", 0.10 * k)
dl = seg_dist(V, "thigh_l"); dr = seg_dist(V, "thigh_r")
dcl = seg_dist(V, "calf_l"); dcr = seg_dist(V, "calf_r")
zt = pos["thigh_l"].z
below = V[:, 2] < zt + 0.02 * k
core = (np.minimum(dl, dr) < r_thigh * np.clip(1 - 0.35 * (zt - V[:, 2]) / (zt - calf_z), 0.6, 1)) | \
       (np.minimum(dcl, dcr) < ov.get("calf_r", 0.075 * k))
skirt = below & ~core & (V[:, 2] > ov.get("skirt_min_z", 0.0))
armd = np.min(D[:, [BI[b] for b in ("hand_l", "hand_r", "lowerarm_l", "lowerarm_r")]], axis=1)
skirt &= armd > 1.3 * r_fa     # hands hanging low (A-pose) are not skirt
xs = pos["thigh_l"].x
t = np.clip((zt - V[:, 2]) / max(zt - calf_z, 1e-3), 0, 1)
p_share = 1 - ov.get("skirt_thigh_share", 0.6) * t
a = np.clip(V[:, 0] / (1.6 * xs), -1, 1)
wl = 0.5 + 0.5 * np.sin(a * math.pi / 2)
S = np.zeros_like(W)
S[:, BI["pelvis"]] = p_share
S[:, BI["thigh_l"]] = (1 - p_share) * wl
S[:, BI["thigh_r"]] = (1 - p_share) * (1 - wl)
# blend in over the first few cm off the leg core so there is no seam
W[skirt] = S[skirt]
print("skirt verts", int(skirt.sum()))
# 3) pauldrons: the region around the shoulder joint above the arm line loses spine
# weight to clavicle/upperarm (so the plate rides the arm instead of stretching)
for side in ("l", "r"):
    sh = np.array(pos["upperarm_" + side][:])
    rp = ov.get("pauldron_r", 0.14 * k)
    m = (np.linalg.norm(V - sh, axis=1) < rp) & (np.abs(V[:, 0]) > abs(sh[0]) - ov.get("pauldron_in", 0.05 * k)) & (V[:, 2] > sh[2] - 0.04 * k)
    sp = W[m][:, [BI["spine_03"], BI["spine_02"], BI["neck_01"]]].sum(1)
    W[m, BI["spine_03"]] = 0; W[m, BI["spine_02"]] = 0; W[m, BI["neck_01"]] = 0
    # outer part -> upperarm, inner part -> clavicle
    f = np.clip((np.abs(V[m, 0]) - (abs(sh[0]) - 0.05 * k)) / (0.07 * k), 0, 1)
    W[m, BI["upperarm_" + side]] += sp * f
    W[m, BI["clavicle_" + side]] += sp * (1 - f)
    print("pauldron verts", side, int(m.sum()))

# ---- smoothing over the mesh graph (few iterations) ---------------------------
edges = np.array([e.vertices[:] for e in M.data.edges])
def smooth(W, it, mask=None):
    for _ in range(it):
        acc = np.zeros_like(W); cnt = np.zeros(len(W))
        np.add.at(acc, edges[:, 0], W[edges[:, 1]]); np.add.at(acc, edges[:, 1], W[edges[:, 0]])
        np.add.at(cnt, edges[:, 0], 1); np.add.at(cnt, edges[:, 1], 1)
        avg = acc / np.maximum(cnt, 1)[:, None]
        Wn = 0.5 * W + 0.5 * avg
        if mask is not None:
            W[mask] = Wn[mask]
        else:
            W = Wn
    return W
W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
W = smooth(W, ov.get("smooth_iters", 3))
# 4) hard rigid parts (after smoothing)
headz = pos["Head"].z + ov.get("head_rigid_dz", 0.0)
hm = (V[:, 2] > headz) & (np.abs(V[:, 0]) < ov.get("head_rigid_x", 0.22 * k))
W[hm] = 0; W[hm, BI["Head"]] = 1
print("helmet/head rigid verts", int(hm.sum()))
for ln_ in ov.get("rigid_lines", []):
    # verts near a line in the front (x/z) plane and behind y >= ymin (e.g. a bow slung on the back)
    a2 = np.array(ln_["a"]); b2 = np.array(ln_["b"]); ab2 = b2 - a2
    P2 = V[:, [0, 2]]
    t2 = np.clip(((P2 - a2) @ ab2) / (ab2 @ ab2), 0, 1)
    d2 = np.linalg.norm(P2 - (a2 + t2[:, None] * ab2), axis=1)
    m = (d2 < ln_.get("r", 0.05)) & (V[:, 1] >= ln_.get("ymin", -9)) & (V[:, 1] <= ln_.get("ymax", 9))
    W[m] = 0; W[m, BI[ln_["bone"]]] = 1
    print("rigid line", ln_["bone"], int(m.sum()))
for box in ov.get("rigid_boxes", []):
    lo = np.array(box["min"]); hi = np.array(box["max"])
    m = np.all((V >= lo) & (V <= hi), axis=1)
    wts = box.get("weights", {box.get("bone"): 1.0})
    W[m] = 0
    for bn, wv in wts.items():
        W[m, BI[bn]] = wv
    print("rigid box", wts, int(m.sum()))
# limit to 4 influences, drop tiny ones, normalise
W[W < 0.02] = 0
idx = np.argsort(-W, axis=1)[:, 4:]
np.put_along_axis(W, idx, 0, axis=1)
W = W / np.maximum(W.sum(1, keepdims=True), 1e-9)
for g in list(M.vertex_groups):
    M.vertex_groups.remove(g)
groups = {b: M.vertex_groups.new(name=b) for b in DEFORM}
for j, b in enumerate(DEFORM):
    nz = np.nonzero(W[:, j])[0]
    for i in nz:
        groups[b].add([int(i)], float(W[i, j]), "REPLACE")
M.modifiers.clear()
md = M.modifiers.new("UAL", "ARMATURE"); md.object = TMP
M.parent = None

if DEBUG:
    # render the fitted joints over a see-through mesh (front + side) for a visual check
    keep_mats = list(M.data.materials)
    gm = bpy.data.materials.new("ghost"); gm.use_nodes = True
    b_ = gm.node_tree.nodes["Principled BSDF"]
    b_.inputs["Base Color"].default_value = (0.8, 0.8, 0.85, 1); b_.inputs["Alpha"].default_value = 0.25
    try:
        gm.surface_render_method = "BLENDED"
    except Exception:
        gm.blend_method = "BLEND"
    M.data.materials.clear(); M.data.materials.append(gm)
    M.modifiers["UAL"].show_render = False
    cam_d = bpy.data.cameras.new("DC"); cam_d.type = "ORTHO"; cam_d.ortho_scale = H * 1.15
    cam = bpy.data.objects.new("DC", cam_d); sc.collection.objects.link(cam); sc.camera = cam
    sun = bpy.data.lights.new("DS", "SUN"); sun.energy = 3; so = bpy.data.objects.new("DS", sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), 0, math.radians(20))
    w = bpy.data.worlds.new("DW"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.2, 0.2, 0.22, 1)
    sc.render.engine = "BLENDER_EEVEE"; sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = 700; sc.render.resolution_y = 700
    TMP.hide_render = True; FINAL.hide_render = True
    for tag, loc, rot in (("front", (0, -10, H / 2), (math.radians(90), 0, 0)), ("side", (10, 0, H / 2), (math.radians(90), 0, math.radians(90)))):
        cam.location = loc; cam.rotation_euler = rot
        sc.render.filepath = os.path.join(OUT, "_work", "dbg_" + NAME + "_" + tag + ".png")
        bpy.ops.render.render(write_still=True)
    # dominant-bone colours (weight check): front + back
    pal = {}
    rng = np.random.default_rng(3)
    for j, b in enumerate(DEFORM):
        pal[j] = rng.random(3) * 0.8 + 0.2
    ca = M.data.color_attributes.new("dbg", "FLOAT_COLOR", "POINT")
    dom = np.argmax(W, axis=1); mx = W.max(1)
    for i in range(nv):
        c = pal[dom[i]] * (0.35 + 0.65 * mx[i])
        ca.data[i].color = (c[0], c[1], c[2], 1)
    wm = bpy.data.materials.new("wdbg"); wm.use_nodes = True
    nt = wm.node_tree; ab = nt.nodes.new("ShaderNodeAttribute"); ab.attribute_name = "dbg"
    nt.links.new(ab.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    M.data.materials.clear(); M.data.materials.append(wm)
    for o_ in [o_ for o_ in sc.objects if o_.name.startswith("J_")]:
        o_.hide_render = True
    for tag, loc, rot in (("wfront", (0, -10, H / 2), (math.radians(90), 0, 0)), ("wback", (0, 10, H / 2), (math.radians(90), 0, math.radians(180)))):
        cam.location = loc; cam.rotation_euler = rot
        sc.render.filepath = os.path.join(OUT, "_work", "dbg_" + NAME + "_" + tag + ".png")
        bpy.ops.render.render(write_still=True)
    M.data.materials.clear()
    for m_ in keep_mats:
        M.data.materials.append(m_)
    M.modifiers["UAL"].show_render = True
    M.data.color_attributes.remove(M.data.color_attributes["dbg"])

# ---- pose Tmp into the UAL T-pose, bake ---------------------------------------
TMP.data.pose_position = "POSE"
for n in order:
    if "leaf" in n or par[n] is None or n == "pelvis":
        continue
    pb = TMP.pose.bones[n]
    bpy.context.view_layer.update()
    Mx = TMP.matrix_world @ pb.matrix
    cur = (Mx.to_3x3() @ Vector((0, 1, 0))).normalized()
    want = (U[n][1] - U[n][0]).normalized()
    q = cur.rotation_difference(want)
    h = Mx.to_translation()
    Mn = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ Mx
    pb.matrix = TMP.matrix_world.inverted() @ Mn
bpy.context.view_layer.update()
posed = {n: TMP.matrix_world @ TMP.pose.bones[n].head for n in order}
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = M; M.select_set(True)
bpy.ops.object.modifier_apply(modifier="UAL")
kk = U["pelvis"][0].z / posed["pelvis"].z
off = Vector((U["pelvis"][0].x - posed["pelvis"].x * kk, U["pelvis"][0].y - posed["pelvis"].y * kk, 0))
S_ = Matrix.Translation(off) @ Matrix.Scale(kk, 4)
M.data.transform(S_)
fitp = {n: S_ @ posed[n] for n in order}
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = FINAL; FINAL.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
finv = FINAL.matrix_world.inverted()
for n in order:
    if par[n] is None:
        continue
    eb = FINAL.data.edit_bones[n]
    v = eb.tail - eb.head
    h = finv @ fitp[n]
    eb.head = h; eb.tail = h + v      # translation only: rest orientation stays exactly UAL
bpy.ops.object.mode_set(mode="OBJECT")
M.parent = FINAL
M.matrix_parent_inverse = FINAL.matrix_world.inverted()
md = M.modifiers.new("Armature", "ARMATURE"); md.object = FINAL
bpy.data.objects.remove(TMP, do_unlink=True)
for o in [o for o in sc.objects if o.name.startswith("J_")]:
    bpy.data.objects.remove(o, do_unlink=True)
FINAL.name = "Armature"; FINAL.data.name = "Armature"

# ---- material: base colour only, <= 1024 px ------------------------------------
def rebuild_material(obj, size, tag):
    src_mat = obj.data.materials[0]
    img = None
    for nd in src_mat.node_tree.nodes:
        if nd.type == "BSDF_PRINCIPLED":
            lk = nd.inputs["Base Color"].links
            if lk and lk[0].from_node.type == "TEX_IMAGE":
                img = lk[0].from_node.image
    if img is None:
        cands = [nd.image for nd in src_mat.node_tree.nodes if nd.type == "TEX_IMAGE" and nd.image
                 and not re.search("normal|metal|rough", nd.image.name, re.I)]
        img = cands[0]
    im2 = img.copy(); im2.name = NAME + "_" + tag
    if max(im2.size) > size:
        im2.scale(size, size)
    im2.pack()
    mat = bpy.data.materials.new(NAME + "_" + tag); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = im2
    nt.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = ov.get("roughness", 0.75)
    obj.data.materials.clear(); obj.data.materials.append(mat)
rebuild_material(M, cfg.get("tex_lod0", 1024), "tex")

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    FINAL.select_set(True)
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_animations=False,
                              export_draco_mesh_compression_enable=False, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
budget0 = cfg.get("lod0_tris", 12000)
if tris(M) > budget0:
    dm = M.modifiers.new("Dec", "DECIMATE"); dm.ratio = budget0 / tris(M) * 0.98
    bpy.context.view_layer.objects.active = M
    bpy.ops.object.modifier_move_to_index(modifier="Dec", index=0)
    bpy.ops.object.modifier_apply(modifier="Dec")
report = {"name": NAME, "height_m": cfg["height"], "lod0_tris": tris(M)}
export([M], os.path.join(OUT, NAME + ".glb"))
# LOD1
L1 = M.copy(); L1.data = M.data.copy(); sc.collection.objects.link(L1)
L1.name = NAME + "_body_lod1"; L1.data.name = L1.name
for mdf in list(L1.modifiers):
    L1.modifiers.remove(mdf)
dm = L1.modifiers.new("Dec", "DECIMATE"); dm.ratio = cfg.get("lod1_tris", 4000) / tris(L1) * 0.97
bpy.context.view_layer.objects.active = L1
bpy.ops.object.modifier_apply(modifier="Dec")
L1.data.validate()
L1.parent = FINAL; L1.matrix_parent_inverse = FINAL.matrix_world.inverted()
am = L1.modifiers.new("Armature", "ARMATURE"); am.object = FINAL
rebuild_material(L1, cfg.get("tex_lod1", 512), "tex_lod1")
report["lod1_tris"] = tris(L1)
M.hide_set(True)
export([L1], os.path.join(OUT, NAME + "_lod1.glb"))
top_all = max(v.co.z for v in M.data.vertices)
# body height = top of the head/helmet column (|x| < 0.1), ignoring bows, horns tips, spikes
top = max(v.co.z for v in M.data.vertices if abs(v.co.x) < 0.1)
head_y = (FINAL.matrix_world @ FINAL.data.bones["Head"].head_local).z
report.update(model_units_top=round(top, 4), model_units_top_all=round(top_all, 4), head_bone_z=round(head_y, 4), pelvis_z=round(fitp["pelvis"].z, 4),
              # Assets.mh_character scales so head_z*1.1 == height; pass this to get top-of-mesh == height_m
              mh_character_height_param=round(cfg["height"] * head_y * 1.1 / top, 3),
              forearm_radius=round(r_fa, 3), skirt_verts=int(skirt.sum()), head_rigid_verts=int(hm.sum()),
              heat_missed=int(miss.sum()))
json.dump(report, open(os.path.join(OUT, "_work", NAME + "_report.json") if os.path.isdir(os.path.join(OUT, "_work")) else os.path.join(OUT, NAME + "_report.json"), "w"), indent=1)
print("REPORT", json.dumps(report))
