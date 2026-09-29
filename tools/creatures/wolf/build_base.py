"""Stage 1: rebuild the wolf base (rest pose, proportions, ruff, tufts, albedo) from the ORIGINAL Meshy/Quaternius GLB.
blender -b --python build_base.py -- <src.glb> <out.blend> <lod 0|1> [scale=1.3]
- lowers the neck/head carriage by posing the neck bones and applying the pose as the new rest pose (mesh + bones stay consistent)
- scales the armature object (the file's scale carrier) by `scale` so Godot scale stays 1.0
- ruff: normal displacement weighted by neck/chest/shoulder skin weights + a few dozen mane tufts (weights/UV copied from the surface)
- albedo re-grade by position: charcoal saddle, silver-cream mane/underside, warm tan legs; face kept.
Keeps the bone names, the vertex groups and the original actions (fake-user) in the blend."""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
from wrig import *
import bmesh
from mathutils import kdtree

args = sys.argv[sys.argv.index('--') + 1:]
src, out, lod = args[0], os.path.abspath(args[1]), int(args[2])
SCALE = float(args[3]) if len(args) > 3 else 1.3
TARGET_TRIS = 15000 if lod == 0 else 5000
N_TUFTS = 90 if lod == 0 else 22
RUFF_THICK = 0.13
HEAD_SCALE = 1.12
PAW_SCALE = 1.14
arm, mesh = load_glb(src)
for a in bpy.data.actions: a.use_fake_user = True
if arm.animation_data: arm.animation_data.action = None
R = WRig(arm)
me = mesh.data
print("SRC verts", len(me.vertices), "tris", sum(len(p.vertices) - 2 for p in me.polygons))

# ---------------------------------------------------------------- 1. head carriage: pose then apply as rest
DEG = math.pi / 180
NECK_POSE = {"Torso3": 3.0, "Neck1": 7.0, "Neck2": 6.0, "Neck3": 5.0, "Head": -8.0}     # + = nose down
rots = {b: pitch(a * DEG) for b, a in NECK_POSE.items()}
A = R.fk(rots); bs = R.basis(A)
for n in R.names:
    pb = arm.pose.bones[n]; pb.rotation_mode = 'QUATERNION'; pb.location = bs[n][0]; pb.rotation_quaternion = bs[n][1]
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = mesh; mesh.select_set(True)
mod = [m for m in mesh.modifiers if m.type == 'ARMATURE'][0]
bpy.ops.object.modifier_apply(modifier=mod.name)
# new rest matrices
bpy.context.view_layer.objects.active = arm; arm.select_set(True); mesh.select_set(False)
new_rest = {n: (A[n] @ R.rest[n]) for n in R.names}
bpy.ops.object.mode_set(mode='EDIT')
for n in R.names:
    eb = arm.data.edit_bones[n]; eb.matrix = new_rest[n]
bpy.ops.object.mode_set(mode='OBJECT')
for n in R.names:
    pb = arm.pose.bones[n]; pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
mod = mesh.modifiers.new("Armature", 'ARMATURE'); mod.object = arm
arm.scale = arm.scale * SCALE
bpy.context.view_layer.update()
R = WRig(arm)                                            # refresh with the new rest and scale
print("SCALE", R.s, "head z rest (rig units)", R.head["Head"].z)

# ---------------------------------------------------------------- 2. ruff (normal displacement) on the rest mesh
me = mesh.data
me.calc_loop_triangles()
nv = len(me.vertices)
co = np.empty(nv * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(nv, 3)
nrm = np.empty(nv * 3, np.float32); me.vertices.foreach_get('normal', nrm); nrm = nrm.reshape(nv, 3)
gname = {g.index: g.name for g in mesh.vertex_groups}
W = {}
for v in me.vertices:
    for g in v.groups:
        W.setdefault(gname[g.group], np.zeros(nv, np.float32))[v.index] = g.weight
def wsum(*names):
    o = np.zeros(nv, np.float32)
    for nme in names:
        if nme in W: o += W[nme]
    return o
def sstep(a, b, x): t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
w_neck = wsum("Neck1", "Neck2", "Neck3"); w_head = wsum("Head", "Ear1.L", "Ear2.L", "Ear3.L", "Ear4.L", "Ear1.R", "Ear2.R", "Ear3.R", "Ear4.R")
w_t3 = wsum("Torso3"); w_t2 = wsum("Torso2"); w_bl = wsum("FrontShoulder.L", "FrontShoulder.R")
ruff = np.clip(w_neck + 0.9 * w_t3 + 0.45 * w_t2 - 1.2 * w_head, 0, 1)
ruff = sstep(0.05, 0.85, ruff)
# radial displacement from the neck/chest axis (the original vertex normals are too noisy to push along)
axis_names = ["Torso2", "Torso3", "Neck1", "Neck2", "Neck3"]
axis_pts = [R.head[n] for n in axis_names] + [R.head["Head"]]
def radial(p):
    best = None
    for a, b in zip(axis_pts[:-1], axis_pts[1:]):
        ab = b - a; t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared)); c = a + ab * t
        d = (p - c).length
        if best is None or d < best[0]: best = (d, c)
    return best[1]
rad = np.zeros_like(co)
for i in np.where(ruff > 0.02)[0]:
    p = Vector(co[i]); v = p - radial(p)
    v = v.normalized() if v.length > 1e-6 else Vector((0, 0, 1))
    rad[i] = v
up = np.clip(rad[:, 2] * 0.5 + 0.5, 0, 1)
disp = ruff * (RUFF_THICK * (0.7 + 0.3 * up))
new_co = co + rad * disp[:, None]
new_co[:, 2] += ruff * 0.05 * sstep(0.1, 0.8, rad[:, 2])                        # raise the hackles
# bigger head (wolves carry a heavy head) and bigger paws
hp = R.head["Head"]
hw = np.clip(w_head * 1.1, 0, 1)
new_co = hp[:] if False else new_co
for i in np.where(hw > 0.01)[0]:
    new_co[i] = np.array(hp) + (new_co[i] - np.array(hp)) * (1 + (HEAD_SCALE - 1) * hw[i])
paw_c = [R.head[b] for b in ("IKFrontLeg.L", "IKFrontLeg.R", "IKBackLeg.L", "IKBackLeg.R")]
for i in np.where(co[:, 2] < 0.36)[0]:
    c = min(paw_c, key=lambda q: (q.x - co[i][0]) ** 2 + (q.y - co[i][1]) ** 2)
    if (c.x - co[i][0]) ** 2 + (c.y - co[i][1]) ** 2 > 0.3 ** 2: continue
    f = 1 + (PAW_SCALE - 1) * float(sstep(0.36, 0.12, co[i][2]))
    new_co[i][0] = c.x + (new_co[i][0] - c.x) * f; new_co[i][1] = c.y + (new_co[i][1] - c.y) * f
me.vertices.foreach_set('co', new_co.ravel()); me.update()
print("ruff verts", int((ruff > 0.3).sum()))

# ---------------------------------------------------------------- 3. decimate the body to leave room for tufts
def tris_of(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
body_target = TARGET_TRIS - N_TUFTS * 3 - 60
if tris_of(mesh) > body_target:
    bpy.context.view_layer.objects.active = mesh
    for o in bpy.data.objects: o.select_set(o == mesh)
    m = mesh.modifiers.new("dec", 'DECIMATE'); m.ratio = body_target / tris_of(mesh); m.use_collapse_triangulate = True
    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
    bpy.ops.object.modifier_apply(modifier="dec")
print("BODY tris", tris_of(mesh))

# ---------------------------------------------------------------- 4. mane tufts (weights + UV copied from the surface)
me = mesh.data
nv = len(me.vertices)
co = np.empty(nv * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(nv, 3)
nrm = np.empty(nv * 3, np.float32); me.vertices.foreach_get('normal', nrm); nrm = nrm.reshape(nv, 3)
gname = {g.index: g.name for g in mesh.vertex_groups}
W = {}
for v in me.vertices:
    for g in v.groups: W.setdefault(gname[g.group], np.zeros(nv, np.float32))[v.index] = g.weight
w_neck = wsum("Neck1", "Neck2", "Neck3"); w_head = wsum("Head", "Ear1.L", "Ear2.L", "Ear3.L", "Ear4.L", "Ear1.R", "Ear2.R", "Ear3.R", "Ear4.R")
w_t3 = wsum("Torso3"); w_t2 = wsum("Torso2")
ruff_v = sstep(0.05, 0.85, np.clip(w_neck + 0.9 * w_t3 + 0.45 * w_t2 - 1.2 * w_head, 0, 1))
cand = np.where((ruff_v > 0.45) & (co[:, 2] > 1.25))[0]
rng = random.Random(11)
picks = rng.sample(list(cand), min(N_TUFTS, len(cand)))
kd = kdtree.KDTree(nv)
for i in range(nv): kd.insert(Vector(co[i]), i)
kd.balance()
bm = bmesh.new(); bm.from_mesh(me)
bm.verts.ensure_lookup_table()
uvl = bm.loops.layers.uv.active
dl = bm.verts.layers.deform.verify()
vuv = {}
for f in bm.faces:
    for l in f.loops: vuv.setdefault(l.vert.index, l[uvl].uv.copy())
n0 = len(bm.faces)
for i in picks:
    p = Vector(co[i]); n = Vector(nrm[i])
    d = (n * 0.22 + Vector((0, 0.9, -0.38))).normalized()
    ln = rng.uniform(0.12, 0.22) * (1.0 if lod == 0 else 1.3)
    side = d.cross(Vector((1, 0, 0)));
    if side.length < 1e-3: side = d.cross(Vector((0, 0, 1)))
    side.normalize(); up_ = d.cross(side).normalized()
    wdt = 0.05 * (1.0 if lod == 0 else 1.3)
    b0 = p - n * 0.02 + side * wdt; b1 = p - n * 0.02 - side * wdt * 0.5 + up_ * wdt * 0.87; b2 = p - n * 0.02 - side * wdt * 0.5 - up_ * wdt * 0.87
    tip = p + d * ln
    vs = [bm.verts.new(x) for x in (b0, b1, b2, tip)]
    bm.verts.ensure_lookup_table()
    for v in vs:
        for gi, gv in ((g.group, g.weight) for g in me.vertices[i].groups): v[dl][gi] = gv
    faces = []
    for a, b in ((0, 1), (1, 2), (2, 0)):
        try:
            f = bm.faces.new((vs[a], vs[b], vs[3]))
        except ValueError:
            continue
        faces.append(f)
    # make sure the normals point away from the tuft axis
    for f in faces:
        c = f.calc_center_median()
        if (c - (p + d * ln * 0.3)).dot(f.normal) < 0: f.normal_flip()
        for l in f.loops: l[uvl].uv = vuv.get(i, Vector((0.5, 0.5)))
bm.to_mesh(me); bm.free()
print("TUFT tris", len(me.polygons) - n0, "TOTAL tris", tris_of(mesh))

# ---------------------------------------------------------------- 5. albedo re-grade
me = mesh.data
img = None
for m in mesh.data.materials:
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image: img = n.image
w_, h_ = img.size
px = np.empty(w_ * h_ * 4, np.float32); img.pixels.foreach_get(px); px = px.reshape(h_, w_, 4)
nv = len(me.vertices)
co = np.empty(nv * 3, np.float32); me.vertices.foreach_get('co', co); co = co.reshape(nv, 3)
nrm = np.empty(nv * 3, np.float32); me.vertices.foreach_get('normal', nrm); nrm = nrm.reshape(nv, 3)
gname = {g.index: g.name for g in mesh.vertex_groups}
W = {}
for v in me.vertices:
    for g in v.groups: W.setdefault(gname[g.group], np.zeros(nv, np.float32))[v.index] = g.weight
w_neck = wsum("Neck1", "Neck2", "Neck3"); w_head = wsum("Head", "Ear1.L", "Ear2.L", "Ear3.L", "Ear4.L", "Ear1.R", "Ear2.R", "Ear3.R", "Ear4.R")
w_t3 = wsum("Torso3"); w_t2 = wsum("Torso2")
w_tail = wsum(*[f"Tail{i}" for i in range(1, 9)])
w_legs = wsum(*[f"{p}{q}.{s}" for p in ("FrontUpperLeg", "FrontLowerLeg", "BackUpperLeg", "BackLowerLeg", "BackLeg") for q in ("",) for s in "LR"])
ruff_v = sstep(0.05, 0.85, np.clip(w_neck + 0.9 * w_t3 + 0.45 * w_t2 - 1.2 * w_head, 0, 1))
nz = nrm[:, 2]; z = co[:, 2]; y = co[:, 1]
dorsal = sstep(0.0, 0.5, nz * 0.45 + (z - 1.5) * 1.3)
saddle = dorsal * sstep(-0.85, -0.35, y) * (1 - sstep(1.15, 1.5, y)) * (1 - ruff_v) * (1 - np.clip(w_head * 2, 0, 1)) * (1 - np.clip(w_legs * 1.5, 0, 1))
silver = np.clip(ruff_v * 1.15 + sstep(-0.05, -0.55, nz) * 0.85 * (1 - np.clip(w_head * 2, 0, 1)), 0, 1)     # mane + belly/underside
legs = np.clip(w_legs * 1.4, 0, 1) * sstep(1.25, 0.85, z) * (1 - saddle)
tail = np.clip(w_tail * 1.5, 0, 1)
head = np.clip(w_head * 1.6, 0, 1) * (1 - ruff_v)
chan = np.stack([saddle, silver, legs, tail, head, np.clip(z / 2.3, 0, 1)], 1).astype(np.float32)   # (nv, C)

# rasterise vertex channels into UV space
uvd = me.uv_layers.active.data
me.calc_loop_triangles()
C = chan.shape[1]
maps = np.zeros((h_, w_, C), np.float32); cov = np.zeros((h_, w_), bool)
for tri in me.loop_triangles:
    vi = tri.vertices; uv = np.array([uvd[l].uv[:] for l in tri.loops]); pxy = uv * np.array([w_, h_]) - 0.5
    x0, y0 = np.floor(pxy.min(0)).astype(int) - 1; x1, y1 = np.ceil(pxy.max(0)).astype(int) + 1
    x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, w_ - 1); y1 = min(y1, h_ - 1)
    if x1 < x0 or y1 < y0: continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    P = np.stack([gx, gy], -1).astype(np.float32)
    a, b, c = pxy
    den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(den) < 1e-9: continue
    l1 = ((b[1] - c[1]) * (P[..., 0] - c[0]) + (c[0] - b[0]) * (P[..., 1] - c[1])) / den
    l2 = ((c[1] - a[1]) * (P[..., 0] - c[0]) + (a[0] - c[0]) * (P[..., 1] - c[1])) / den
    l3 = 1 - l1 - l2
    inside = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
    if not inside.any(): continue
    val = l1[..., None] * chan[vi[0]] + l2[..., None] * chan[vi[1]] + l3[..., None] * chan[vi[2]]
    sel = inside
    maps[gy[sel], gx[sel]] = val[sel]; cov[gy[sel], gx[sel]] = True
# dilate into uncovered texels
for _ in range(6):
    if cov.all(): break
    acc = np.zeros_like(maps); cnt = np.zeros((h_, w_), np.float32)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            sh = np.roll(np.roll(maps * cov[..., None], dy, 0), dx, 1); sc_ = np.roll(np.roll(cov.astype(np.float32), dy, 0), dx, 1)
            acc += sh; cnt += sc_
    fill = (~cov) & (cnt > 0)
    maps[fill] = acc[fill] / cnt[fill][:, None]; cov |= fill
print("UV coverage", float(cov.mean()))
m_sad, m_sil, m_leg, m_tail, m_head, m_h = [maps[..., i] for i in range(C)]
rgb = px[..., :3]
lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
lo, hi = np.percentile(lum, 4), np.percentile(lum, 97)
d = np.clip((lum - lo) / (hi - lo + 1e-6), 0, 1)
d_dark = d ** 1.6; d_lite = d ** 0.7
def tone(dark, light, dd=None):
    dd = d if dd is None else dd
    return np.array(dark, np.float32) * (1 - dd[..., None]) + np.array(light, np.float32) * dd[..., None]
flank = tone((0.20, 0.20, 0.22), (0.70, 0.66, 0.58))
sad_c = tone((0.05, 0.06, 0.09), (0.26, 0.28, 0.34), d_dark)
sil_c = tone((0.82, 0.74, 0.60), (1.0, 0.97, 0.87), d_lite)
leg_c = tone((0.45, 0.32, 0.20), (0.88, 0.72, 0.50))
tail_c = tone((0.10, 0.10, 0.11), (0.36, 0.34, 0.32))
wS, wI, wL = m_sad[..., None], m_sil[..., None], m_leg[..., None]
tot = wS + wI + wL
col = flank * np.clip(1 - tot, 0, 1) + (sad_c * wS + sil_c * wI + leg_c * wL)
col = np.where(tot > 1, col / np.maximum(tot, 1), col)
col = col * (1 - m_tail[..., None]) + tail_c * m_tail[..., None] * 0.9 + col * m_tail[..., None] * 0.1
# keep the face texels (eyes, nose): mostly original, slightly lifted for readability
face = np.clip(m_head * 1.2, 0, 1)[..., None]
col = col * (1 - face) + np.clip(rgb * 1.08 + 0.02, 0, 1) * face
px2 = px.copy(); px2[..., :3] = np.clip(col, 0, 1)
img.pixels.foreach_set(px2.ravel()); img.update()
tag = "lod1" if lod else "lod0"
prev = os.environ.get("TEX_PREVIEW")
if prev:
    img2 = bpy.data.images.new("prev", w_, h_); img2.pixels.foreach_set(px2.ravel()); img2.filepath_raw = prev; img2.file_format = 'PNG'; img2.save()
jpg = out.replace('.blend', '_tex.jpg')
img.filepath_raw = jpg; img.file_format = 'JPEG'; img.save()
new = bpy.data.images.load(jpg); new.name = 'Image_0_new'; new.pack()
for m in mesh.data.materials:
    for n in m.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image == img: n.image = new
bpy.data.images.remove(img); new.name = 'Image_0'
print('TEX', w_, h_, 'reloaded mean', float(np.array(new.pixels[:]).reshape(-1, 4)[:, :3].mean()))
bpy.ops.wm.save_as_mainfile(filepath=out)
print("SAVED", out, "tris", tris_of(mesh))
