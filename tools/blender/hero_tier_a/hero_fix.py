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
MAXSHIFT = float(next((x.split("=")[1] for x in a if x.startswith("--maxshift=")), "0.05"))
NARROW = float(next((x.split("=")[1] for x in a if x.startswith("--narrow=")), "0.0"))
SHELL = "--hood_shell" in a
SHOULDER = float(next((x.split("=")[1] for x in a if x.startswith("--shoulder=")), "0.18"))
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

# ---- feet: Meshy boots sit ~5 cm behind the UAL ankle (long heel lever = "ski" stretch). Slide the boot forward onto the
# bones (fading out up the shin), then: sole/heel rigid on foot, toe cap on ball, shin band blends calf -> foot.
nf = 0
for s in ("l", "r"):
    fh = B["foot_" + s][0]; bh = B["ball_" + s][0]
    heel = max(P[i].dot(-fwd) for i in range(len(P)) if P[i].z < 0.05 and abs(P[i].x - fh.x) < 0.08)
    shift = min(MAXSHIFT, max(0.0, heel - (fh.dot(-fwd) + 0.06)))   # heel should end ~6 cm behind the ankle (capped)
    ank = fh.z
    for i, p in enumerate(P):
        if p.z > ank + 0.16 or abs(p.x - fh.x) > 0.11:
            continue
        k = max(0.0, min(1.0, (ank + 0.16 - p.z) / 0.1))
        d = fwd * shift * k
        me.vertices[i].co += M.inverted().to_3x3() @ d
        P[i] = P[i] + d
        if p.z > ank + 0.1:
            continue
        up = max(0.0, min(1.0, (P[i].z - ank + 0.01) / 0.09))
        toe = max(0.0, min(1.0, ((P[i] - bh).dot(fwd) + 0.01) / 0.04))
        set_w(i, {"foot_" + s: (1 - toe) * (1 - up), "ball_" + s: toe * (1 - up), "calf_" + s: up})
        nf += 1
    print("FOOT", s, "shift", round(shift, 3))
print("FEET verts", nf)

# ---- fingers -----------------------------------------------------------------------------------------------------
def seg_d(p, a_, b_):
    ab = b_ - a_; t = max(0.0, min(1.0, (p - a_).dot(ab) / max(ab.length_squared, 1e-8)))
    return (p - (a_ + ab * t)).length, t
nfi = 0
FINGERS = "--fingers" in a     # off by default: Meshy hands are fused mitts, finger weights shred them in clips
for s in (("l", "r") if FINGERS else ()):
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

# ---- shoulder/collar sculpt: the Meshy shirt balloons around the neck. Slim the depth, narrow a little and slope the
# shoulders down, fading out toward the arms (T-pose arms start at |x| ~0.2) and leaving the head alone.
def ss(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
chest = B["spine_03"][0].z; neck = B["neck_01"][0]
ncol = 0
for i, p in enumerate(P):
    if p.z < chest - 0.05 or p.z > neck.z + 0.07 or weights(i).get("Head", 0.0) > 0.4:
        continue
    hx = abs(p.x - neck.x)
    f = (1.0 - ss(0.16, 0.24, hx)) * ss(chest - 0.05, chest + 0.03, p.z)
    if f <= 0:
        continue
    q = Vector((neck.x + (p.x - neck.x) * (1 - 0.06 * f), neck.y + (p.y - neck.y) * (1 - SHOULDER * f), p.z - 0.02 * f * ss(0.05, 0.15, hx)))
    me.vertices[i].co = M.inverted() @ q
    P[i] = q
    ncol += 1
print("SHOULDER verts", ncol)

# ---- hands: the Meshy hands are fused mitts. Cut them at the wrist; HeroTierA attaches the G6 hands (real finger bones).
hand_cut = []
for s_ in ("l", "r"):
    hh = B["hand_" + s_][0]
    out = (B["hand_" + s_][1] - hh).normalized()
    for i, p in enumerate(P):
        if weights(i).get("hand_" + s_, 0.0) > 0.4 and (p - hh).dot(out) > 0.015:
            hand_cut.append(i)
if "--keep_hands" not in a:
    bmh = bmesh.new(); bmh.from_mesh(me); bmh.verts.ensure_lookup_table()
    bmesh.ops.delete(bmh, geom=[bmh.verts[i] for i in hand_cut], context="VERTS")
    bmh.to_mesh(me); bmh.free()
    uvl = me.uv_layers.active.data
    P = [M @ v.co for v in me.vertices]
    N = [(M.to_3x3() @ v.normal).normalized() for v in me.vertices]
    vuv = {}
    for l in me.loops:
        vuv.setdefault(l.vertex_index, uvl[l.index].uv.copy())
print("HAND verts cut", len(hand_cut))

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

# ---- mouth smear: paint over dark slashes / red smears around the mouth with the local skin median (lip line kept) ---
mouth = nose - fwd * 0.012 + Vector((0, 0, -0.03))
fixed = 0
for dz in np.linspace(-0.03, 0.01, 21):
    for dx in np.linspace(-0.032, 0.032, 25):
        s_ = sample(mouth + Vector((dx, 0, dz)) + fwd * 0.1, -fwd)
        if s_ is None:
            continue
        uv = s_[2]
        cx, cy = int(uv.x * (W - 1)), int(uv.y * (H - 1))
        r = 4
        y0, y1, x0, x1 = max(0, cy - r), min(H, cy + r + 1), max(0, cx - r), min(W, cx + r + 1)
        patch = px[y0:y1, x0:x1, :3]
        lum = patch.mean(axis=2)
        med = np.median(patch.reshape(-1, 3), axis=0)
        red = patch[..., 0] - 0.5 * (patch[..., 1] + patch[..., 2])
        lipline = abs(dz) < 0.0035 and abs(dx) < 0.02
        lips = abs(dz) < 0.008 and abs(dx) < 0.022
        bad = (lum < med.mean() * (0.45 if lipline else 0.62)) | ((red > 0.3) & ~np.bool_(lips))
        if bad.any():
            px[y0:y1, x0:x1, :3][bad] = med
            fixed += int(bad.sum())
print("MOUTH texels painted", fixed)

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
lv, lf, luv, lkey, lcol = [], [], [], [], []
# lids take ONE plain skin texel (upper cheek), shading comes from hero_lid: no brow/eye texels smeared onto the lid
_ch = sample(nose - fwd * 0.02 + Vector((0.035, 0, 0.012)) + fwd * 0.1, -fwd)
cheek_uv = _ch[2] if _ch else Vector((0.5, 0.5))
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
            s2 = sample(cen + Vector((u * EW * 0.8, 0, EH * 0.5)) + fwd * 0.1, -fwd)   # upper-lid skin band
            luv.append(cheek_uv)
            lv.append(pos)
            edge = min(1.0, (0.5 - abs(u)) / 0.18) * min(1.0, (v + 0.5) / 0.25 + 0.2)
            lcol.append((u + 0.5, v + 0.5))          # lid-local coords -> UV2 (soft border + lash line in hero_lid)
    for r_ in range(rows):
        for c_ in range(cols):
            lkey.append(lv[base + (rows - 1) * cols + c_] - fwd * 0.0004)     # Basis: every row folded onto the top row
    for r_ in range(rows - 1):
        for c_ in range(cols - 1):
            i0 = base + r_ * cols + c_
            lf.append((i0, i0 + 1, i0 + cols + 1, i0 + cols) if fwd.y < 0 else (i0, i0 + cols, i0 + cols + 1, i0 + 1))
lm = bpy.data.meshes.new("Lids")
lm.from_pydata([tuple(p) for p in lkey], [], lf)
ul = lm.uv_layers.new(name="UV")
for poly in lm.polygons:
    for li in poly.loop_indices:
        ul.data[li].uv = luv[lm.loops[li].vertex_index]
u2 = lm.uv_layers.new(name="Lid")
for poly in lm.polygons:
    for li in poly.loop_indices:
        u2.data[li].uv = lcol[lm.loops[li].vertex_index]
lm.uv_layers.active_index = 0
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

# ---- arms/shoulders: shrink the cross-section around each arm line (T-pose) by NARROW, fading in from the clavicle
if NARROW > 0:
    for s_ in ("l", "r"):
        a0 = B["clavicle_" + s_][0]; a1 = B["hand_" + s_][0]
        ax = (a1 - a0).normalized()
        for i, p in enumerate(P):
            if (p.x - neck.x) * (a1.x - neck.x) <= 0:
                continue
            t = (p - a0).dot(ax)
            if t < -0.02 or t > (a1 - a0).length + 0.02:
                continue
            foot = a0 + ax * t
            if (p - foot).length > 0.16 or p.z < chest - 0.12:      # arms + shoulders only (legs/torso untouched)
                continue
            k = NARROW * ss(-0.02, 0.08, t)
            q = foot + (p - foot) * (1 - k)
            q.x = neck.x + (q.x - neck.x) * (1 - 0.35 * k)      # pull the shoulder line in a little as well
            me.vertices[i].co = M.inverted() @ q
            P[i] = q
    print("ARMS narrowed", NARROW)

# ---- material mask in vertex colour R: 1 = hood/cowl wool (forced matte in hero_character, no colour heuristics)
head_ctr = B["Head"][0] + Vector((0, 0, 0.09))
mk = me.color_attributes.new("Mask", "BYTE_COLOR", "POINT")
nh = 0
for i, p in enumerate(P):
    w = weights(i)
    hood = p.z > neck.z - 0.08 and (p - head_ctr).length > 0.105 and abs(p.x - neck.x) < 0.24
    mk.data[i].color = (1.0 if hood else 0.0, 0.0, 0.0, 1.0)
    nh += hood
me.color_attributes.active_color = mk
print("HOOD mask verts", nh)

# ---- face paint: desaturate the red lips, soften the dark painted brows
for cen, nrm_, sx in eyes:
    for dz in np.linspace(0.006, 0.03, 9):
        for dx in np.linspace(-0.022, 0.022, 11):
            s_ = sample(cen + Vector((dx, 0, dz)) + fwd * 0.1, -fwd)
            if s_ is None:
                continue
            cx, cy = int(s_[2].x * (W - 1)), int(s_[2].y * (H - 1)); r = 5
            y0, y1, x0, x1 = max(0, cy - r), min(H, cy + r + 1), max(0, cx - r), min(W, cx + r + 1)
            patch = px[y0:y1, x0:x1, :3]
            med = np.median(patch.reshape(-1, 3), axis=0)
            px[y0:y1, x0:x1, :3] = patch * 0.55 + np.maximum(patch, med) * 0.45
for dz in np.linspace(-0.012, 0.006, 7):
    for dx in np.linspace(-0.025, 0.025, 11):
        s_ = sample(mouth + Vector((dx, 0, dz)) + fwd * 0.1, -fwd)
        if s_ is None:
            continue
        cx, cy = int(s_[2].x * (W - 1)), int(s_[2].y * (H - 1)); r = 5
        y0, y1, x0, x1 = max(0, cy - r), min(H, cy + r + 1), max(0, cx - r), min(W, cx + r + 1)
        patch = px[y0:y1, x0:x1, :3]
        lum = patch.mean(axis=2, keepdims=True)
        red = np.clip(patch[..., 0:1] - 0.5 * (patch[..., 1:2] + patch[..., 2:3]), 0, 1)
        k = np.clip(red * 3.0, 0, 0.6)
        px[y0:y1, x0:x1, :3] = patch * (1 - k) + (lum * np.array([1.08, 0.86, 0.78])) * k
print("FACE paint done")
bm.free()

# ---- hood: separate cloth shell grown from the body's collar/upper back (same weights -> deforms with the body, offset
# along the normals -> never clips), open V at the front, a folded hood bag bulging on the back. Material slot "Hood".
if SHELL:
    HOOD_OFF = 0.016
    bmc = bmesh.new(); bmc.from_mesh(me)
    dl = bmc.verts.layers.deform.active
    keep = set()
    for v in bmc.verts:
        p = M @ v.co
        hx = abs(p.x - neck.x)
        back = (p - neck).dot(-fwd) > -0.02
        if neck.z - 0.13 < p.z < neck.z + 0.035 and hx < 0.16 and (back or (hx > 0.1 and p.z > neck.z - 0.05)):   # front: only the shoulder tops
            keep.add(v.index)
    bmesh.ops.delete(bmc, geom=[f for f in bmc.faces if not any(x.index in keep for x in f.verts)], context="FACES")
    bmesh.ops.delete(bmc, geom=[v for v in bmc.verts if not v.link_faces], context="VERTS")
    bmesh.ops.subdivide_edges(bmc, edges=bmc.edges[:], cuts=2, use_grid_fill=True, smooth=0.6)   # sparse 4k body -> cloth density
    for _ in range(6):
        bmesh.ops.smooth_vert(bmc, verts=bmc.verts[:], factor=0.5, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    # rolled hem: pull boundary verts in toward the body so no edge stands off as a shard
    for _ in range(2):
        bnd = [v for v in bmc.verts if v.is_boundary]
        bmesh.ops.smooth_vert(bmc, verts=bnd, factor=0.8, use_axis_x=True, use_axis_y=True, use_axis_z=True)
    bmc.normal_update()
    bag_c = neck + fwd * -0.11 + Vector((0, 0, -0.08))
    for v in bmc.verts:
        p = M @ v.co
        bag = math.exp(-((p.x - neck.x) ** 2) / (2 * 0.06 ** 2)) * math.exp(-((p.z - bag_c.z) ** 2) / (2 * 0.045 ** 2)) * (1.0 if (p - neck).dot(-fwd) > 0 else 0.0)
        rim = ss(neck.z - 0.01, neck.z + 0.035, p.z)          # rolled edge at the neck stands up a little
        off = (HOOD_OFF + 0.035 * bag + 0.006 * rim) * (0.35 if v.is_boundary else 1.0)
        v.co += M.inverted().to_3x3() @ ((M.to_3x3() @ v.normal).normalized() * off)
    hood_me = bpy.data.meshes.new("Hood")
    bmc.to_mesh(hood_me); bmc.free()
    hood = bpy.data.objects.new("Hood", hood_me)
    bpy.context.scene.collection.objects.link(hood)
    hood.matrix_world = ob.matrix_world.copy()
    for g in ob.vertex_groups:
        hood.vertex_groups.new(name=g.name)
    hood.parent = arm
    hm = hood.modifiers.new("Armature", "ARMATURE"); hm.object = arm
    sol = hood.modifiers.new("Solid", "SOLIDIFY"); sol.thickness = 0.012; sol.offset = 1.0
    bpy.context.view_layer.objects.active = hood
    bpy.ops.object.modifier_move_to_index(modifier="Solid", index=0)
    bpy.ops.object.modifier_apply(modifier="Solid")
    mat = bpy.data.materials.new("Hood")
    hood_me.materials.clear(); hood_me.materials.append(mat)
    hc = hood_me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
    for i, v in enumerate(hood_me.vertices):
        t = ((M @ v.co).z - (neck.z - 0.13)) / 0.17
        c = (0.11 + 0.04 * t, 0.065 + 0.025 * t, 0.035 + 0.012 * t, 1.0)       # brown wool, lighter at the rolled edge
        hc.data[i].color = c
    hood_me.color_attributes.active_color = hc
    print("HOOD verts", len(hood_me.vertices))

# write the patched texture back
img.pixels[:] = px.ravel()
img.update()
img.file_format = "JPEG"
for o in bpy.data.objects:
    o.select_set(o.type in ("MESH", "ARMATURE"))
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animations=False, export_skins=True, export_morph=True, export_vertex_color="ACTIVE",
                          export_image_format="JPEG", export_jpeg_quality=92, use_selection=True)
print("DONE", OUT)
