"""Tier-A fixes on a UAL-rigged Meshy character (output of armored_rig.py), before smooth_lods.py. Skill ashes-hero-character.
  feet    : clean foot/ball weights below the ankle (no calf pull -> no stretched "ski" soles)
  fingers : hand texels past the palm re-weighted to the nearest UAL finger bones (so clip grips curl the fingers)
  collar  : pulls the oversized cream collar/shoulder shell in toward the body
  mouth   : blurs + de-reds the texture smear at the mouth corners
  lids    : adds 'Lids' (upper-lid patches sampled from the skin above each painted eye) with shape key Blink, skinned to Head
tools/external/blender.sh tools/blender/hero_tier_a/hero_fix.py -- <in.glb> <out.glb> [--collar=0.016]"""
import bpy, bmesh, sys, os, math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = a[0], a[1]
COLLAR = float(next((x.split("=")[1] for x in a if x.startswith("--collar=")), "0.035"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
ob = [o for o in bpy.data.objects if o.type == "MESH"][0]
me = ob.data
B = {b.name: (arm.matrix_world @ b.head_local, arm.matrix_world @ b.tail_local) for b in arm.data.bones}
gi = {g.name: g for g in ob.vertex_groups}
def grp(n):
    return gi[n] if n in gi else ob.vertex_groups.new(name=n)
M = ob.matrix_world
P = [M @ v.co for v in me.vertices]
N = [(M.to_3x3() @ v.normal).normalized() for v in me.vertices]
idx_of = {g.index: g.name for g in ob.vertex_groups}
def weights(v):
    return {idx_of[g.group]: g.weight for g in me.vertices[v].groups}
def set_w(v, d):
    for g in list(me.vertices[v].groups):
        ob.vertex_groups[g.group].remove([v])
    tot = sum(d.values()) or 1.0
    for n, w in d.items():
        if w > 1e-4:
            grp(n).add([v], w / tot, "REPLACE")

# texture as numpy (for colour classification + painting)
img = None
for n in me.materials[0].node_tree.nodes:
    if n.type == "TEX_IMAGE":
        img = n.image
W, H = img.size
px = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)
uvl = me.uv_layers.active.data
vuv = {}
for l in me.loops:
    vuv.setdefault(l.vertex_index, uvl[l.index].uv.copy())
def tex_at(uv):
    x = int((uv.x % 1.0) * (W - 1)); y = int((uv.y % 1.0) * (H - 1))
    return px[y, x, :3]

head_c = B["Head"][0]
# forward = where the toes point (the back of a Meshy head can stick out further than the nose)
toe = (B["ball_l"][0] + B["ball_r"][0]) - (B["foot_l"][0] + B["foot_r"][0])
fwd = Vector((0, 1 if toe.y > 0 else -1, 0))
hv = [i for i, p in enumerate(P) if abs(p.x) < 0.012 and head_c.z + 0.03 < p.z < head_c.z + 0.11]
nose = max((P[i] for i in hv), key=lambda p: p.dot(fwd))
print("FWD", fwd, "NOSE", nose)

# ---- feet --------------------------------------------------------------------------------------------------------
nf = 0
for s in ("l", "r"):
    fh, ft = B["foot_" + s]; bh = B["ball_" + s][0]
    ank = fh.z
    L = (bh - fh); L.z = 0
    for i, p in enumerate(P):
        if p.z > ank + 0.06 or (p.x > 0) != (fh.x > 0) or abs(p.x - fh.x) > 0.12:
            continue
        w = weights(i)
        if not any(k.endswith("_" + s) and k.split("_")[0] in ("foot", "ball", "calf") for k in w):
            continue
        q = p - fh; q.z = 0
        t = max(0.0, min(1.0, q.dot(L.normalized()) / max(L.length, 1e-4)))
        ball = max(0.0, min(1.0, (t - 0.55) / 0.4))
        up = max(0.0, min(1.0, (p.z - ank) / 0.06))           # above the ankle: blend into the calf
        d = {"foot_" + s: (1 - ball) * (1 - up), "ball_" + s: ball * (1 - up), "calf_" + s: up}
        set_w(i, d); nf += 1
print("FEET verts", nf)

# ---- fingers -----------------------------------------------------------------------------------------------------
def seg_d(p, a_, b_):
    ab = b_ - a_; t = max(0.0, min(1.0, (p - a_).dot(ab) / max(ab.length_squared, 1e-8)))
    return (p - (a_ + ab * t)).length, t
nfi = 0
for s in ("l", "r"):
    hh = B["hand_" + s][0]
    fingers = [n for n in B if n.endswith("_" + s) and n.split("_")[0] in ("index", "middle", "ring", "pinky", "thumb") and "leaf" not in n]
    knuck = sum((B["%s_01_%s" % (f, s)][0] for f in ("index", "middle", "ring", "pinky")), Vector()) / 4
    palm = (knuck - hh)
    for i, p in enumerate(P):
        if (p - hh).length > 0.25:
            continue
        w = weights(i)
        if w.get("hand_" + s, 0.0) < 0.5:
            continue
        along = (p - hh).dot(palm.normalized()) / palm.length
        ds = sorted((seg_d(p, *B[n])[0], n) for n in fingers)
        dthumb = min(d for d, n in ds if n.startswith("thumb"))
        if along < 0.85 and dthumb > 0.018:
            continue
        (d0, n0), (d1, n1) = ds[0], ds[1]
        w0 = 1.0 / (d0 + 0.002); w1 = 1.0 / (d1 + 0.002)
        k = max(0.0, min(1.0, (along - 0.85) / 0.25)) if not n0.startswith("thumb") else 1.0
        set_w(i, {n0: k * w0 / (w0 + w1), n1: k * w1 / (w0 + w1), "hand_" + s: 1 - k})
        nfi += 1
print("FINGER verts", nfi)

# ---- collar: cream shell above the chest pulled inward -----------------------------------------------------------
chest = B["spine_03"][0].z; neck = B["neck_01"][0]
ncol = 0
for i, p in enumerate(P):
    if not (chest - 0.02 < p.z < neck.z + 0.04):
        continue
    c = tex_at(vuv[i])
    mx, mn = max(c), min(c)
    if mx < 0.38 or (mx - mn) / max(mx, 1e-4) > 0.35:
        continue
    r = math.hypot(p.x - neck.x, (p.y - neck.y))
    f = max(0.0, min(1.0, (r - 0.06) / 0.05)) * max(0.0, min(1.0, (p.z - chest + 0.02) / 0.06))
    if f <= 0:
        continue
    d = -N[i] * COLLAR * f + Vector((0, 0, -0.006 * f))
    me.vertices[i].co += M.inverted().to_3x3() @ d
    ncol += 1
print("COLLAR verts", ncol)

# ---- triangulated BVH with UVs for surface sampling ----------------------------------------------------------------
bm = bmesh.new(); bm.from_mesh(me); bm.transform(M)
bmesh.ops.triangulate(bm, faces=bm.faces)
bm.faces.ensure_lookup_table()
uvlay = bm.loops.layers.uv.active
bvh = BVHTree.FromBMesh(bm)
def sample(o, d):
    hit, n, fi, _ = bvh.ray_cast(o, d, 0.3)
    if hit is None:
        return None
    f = bm.faces[fi]
    vs = [l.vert.co for l in f.loops]
    from mathutils.geometry import barycentric_transform
    uvs = [l[uvlay].uv.to_3d() for l in f.loops]
    uv = barycentric_transform(hit, *vs, *uvs)
    return hit, n, Vector((uv.x, uv.y))

# ---- mouth smear: blur + de-red around both mouth corners in texture space -------------------------------------------
side = Vector((1, 0, 0))
mouth = nose - fwd * 0.012 + Vector((0, 0, -0.034))
fixed = 0
for sx in (-1, 1):
    for dz in np.linspace(-0.018, 0.008, 9):
        for dx in np.linspace(0.008, 0.03, 9):
            o = mouth + side * sx * dx + Vector((0, 0, dz)) + fwd * 0.1
            s_ = sample(o, -fwd)
            if s_ is None:
                continue
            uv = s_[2]
            cx, cy = int(uv.x * (W - 1)), int(uv.y * (H - 1))
            r = 4
            y0, y1, x0, x1 = max(0, cy - r), min(H, cy + r + 1), max(0, cx - r), min(W, cx + r + 1)
            patch = px[y0:y1, x0:x1, :3]
            med = np.median(patch.reshape(-1, 3), axis=0)
            red = patch[..., 0] - 0.5 * (patch[..., 1] + patch[..., 2])
            lip = abs(dx) < 0.016 and abs(dz) < 0.004
            if not lip:
                px[y0:y1, x0:x1, :3] = patch * 0.4 + med * 0.6
                px[y0:y1, x0:x1, 0] -= np.clip(red - 0.12, 0, 1) * 0.5
                fixed += 1
print("MOUTH texels patched", fixed)

# ---- eyes: darkest painted cluster near the anthropometric guess ---------------------------------------------------
eyes = []
for sx in (-1, 1):
    guess = nose - fwd * 0.03 + Vector((sx * 0.032, 0, 0.037))
    best = []
    for dz in np.linspace(-0.012, 0.012, 13):
        for dx in np.linspace(-0.014, 0.014, 15):
            o = guess + Vector((dx, 0, dz)) + fwd * 0.1
            s_ = sample(o, -fwd)
            if s_ is None:
                continue
            c = tex_at(s_[2])
            best.append((float(sum(c)), s_[0], s_[1]))
    best.sort(key=lambda t: t[0])
    dark = best[:max(3, len(best) // 10)]
    cen = sum((b[1] for b in dark), Vector()) / len(dark)
    nrm = sum((b[2] for b in dark), Vector()).normalized()
    eyes.append((cen, nrm, sx))
print("EYES", [(tuple(round(v, 3) for v in e[0])) for e in eyes])

# ---- lids: 9x5 surface patch over each eye, UV from the skin 1.3 cm above (upper lid), Basis = rolled up, Blink = closed
lv, lf, luv, lkey = [], [], [], []
EW, EH = 0.032, 0.016
for cen, nrm, sx in eyes:
    base = len(lv)
    rows, cols = 5, 9
    top = []
    for r_ in range(rows):
        for c_ in range(cols):
            u = c_ / (cols - 1) - 0.5; v = r_ / (rows - 1) - 0.5        # v: -0.5 bottom .. 0.5 top
            arch = 0.25 * math.cos(u * math.pi) * EH
            o = cen + Vector((u * EW, 0, v * EH + arch * (0.5 - abs(v)))) + fwd * 0.1
            s_ = sample(o, -fwd)
            if s_ is None:
                hit, n_ = cen + Vector((u * EW, 0, v * EH)), nrm
            else:
                hit, n_ = s_[0], s_[1]
            pos = hit + n_ * (0.0012 + 0.0012 * math.cos(u * math.pi) * (0.5 - v))
            s2 = sample(hit + Vector((0, 0, 0.013)) + fwd * 0.1, -fwd)
            luv.append(s2[2] if s2 else Vector((0.5, 0.5)))
            lv.append(pos)
    for r_ in range(rows):
        for c_ in range(cols):
            lkey.append(lv[base + (rows - 1) * cols + c_] - fwd * 0.0004)     # Basis: every row folded onto the top row
    for r_ in range(rows - 1):
        for c_ in range(cols - 1):
            i0 = base + r_ * cols + c_
            lf.append((i0, i0 + 1, i0 + cols + 1, i0 + cols) if fwd.y < 0 else (i0, i0 + cols, i0 + cols + 1, i0 + 1))
bm.free()
lm = bpy.data.meshes.new("Lids")
lm.from_pydata([tuple(p) for p in lkey], [], lf)
ul = lm.uv_layers.new(name="UV")
for poly in lm.polygons:
    for li in poly.loop_indices:
        ul.data[li].uv = luv[lm.loops[li].vertex_index]
lo = bpy.data.objects.new("Lids", lm)
bpy.context.scene.collection.objects.link(lo)
lm.materials.append(me.materials[0])
lo.shape_key_add(name="Basis")
k = lo.shape_key_add(name="Blink", from_mix=False)
for i, p in enumerate(lv):
    k.data[i].co = p
g = lo.vertex_groups.new(name="Head"); g.add(list(range(len(lv))), 1.0, "REPLACE")
lo.parent = arm
mo = lo.modifiers.new("Armature", "ARMATURE"); mo.object = arm

# write the patched texture back
img.pixels[:] = px.ravel()
img.update()
img.file_format = "JPEG"
for o in bpy.data.objects:
    o.select_set(o.type in ("MESH", "ARMATURE"))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=False, export_skins=True, export_morph=True,
                          export_image_format="JPEG", export_jpeg_quality=92, use_selection=True)
print("DONE", OUT)
