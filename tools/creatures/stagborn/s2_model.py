"""Stage 2: variant geometry (Warden antlers/mane/bulk), vertex colours, UV unwrap, Cycles bake (albedo, AO, position, masks),
painted albedo + emissive rune texture (numpy), material. Saves char_<variant>.blend + textures.
blender -b --python s2_model.py -- <variant elk|warden> <base.blend> <out_dir>"""
import bpy, bmesh, sys, math, os, random
import numpy as np
from mathutils import Vector
variant, base, outdir = sys.argv[-3:]
outdir = os.path.abspath(outdir); os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=base)
D = bpy.data; sc = bpy.context.scene
mesh = D.objects["mesh"]; arm = D.objects["Armature"]; me = mesh.data
NB = int(mesh["n_body_polys"]); TEX = 1024
W = variant == "warden"
def s2l(c): return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)
def l2s(a): return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(np.clip(a, 1e-6, None), 1 / 2.4) - 0.055)

# ---------------------------------------------------------------- geometry
bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
if W:
    for f in [f for f in bm.faces if f.index >= NB]: bm.faces.remove(f)   # drop stock antlers, rebuilt below
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
bm.to_mesh(me); bm.free(); me.update()
print("welded verts", len(me.vertices))
if W:  # bulk: wider body, heavier neck and chest (weights drive the amount)
    gi = {g.name: g.index for g in mesh.vertex_groups}
    for v in me.vertices:
        w = {g.group: g.weight for g in v.groups}
        wn = sum(w.get(gi[n], 0) for n in ("Neck1", "Neck2", "Neck3")); wc = sum(w.get(gi[n], 0) for n in ("Torso2", "Torso3", "FrontShoulder.L", "FrontShoulder.R"))
        wh = w.get(gi["Head"], 0)
        v.co.x *= 1.10 + 0.25 * wn + 0.12 * wc + 0.10 * wh
        v.co.z += 0.06 * wc
        if wn > 0.3: v.co.y -= 0.03 * wn
nbv = len(me.vertices)

def add_group_obj(bm_, name, group_of):
    m = D.meshes.new(name); bm_.to_mesh(m); bm_.free()
    o = D.objects.new(name, m); sc.collection.objects.link(o)
    for gname in set(group_of):
        vg = o.vertex_groups.new(name=gname)
        vg.add([i for i, g in enumerate(group_of) if g == gname], 1.0, 'REPLACE')
    return o

def tube(bm_, pts, r0, r1, sides=6, seg=9, knot=0.0, taper=1.0):
    """Catmull-Rom sampled tube through pts (list of Vector), radius r0 -> r1."""
    P = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    samples = []
    for i in range(1, len(P) - 2):
        for k in range(seg):
            t = k / seg; a, b, c, d = P[i - 1], P[i], P[i + 1], P[i + 2]
            samples.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3))
    samples.append(pts[-1])
    rings = []; n = len(samples)
    for i, p in enumerate(samples):
        t = i / (n - 1)
        tan = (samples[min(i + 1, n - 1)] - samples[max(i - 1, 0)]).normalized()
        up = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
        s = tan.cross(up).normalized(); u = s.cross(tan).normalized()
        r = (r0 + (r1 - r0) * (t ** taper)) * (1 + knot * math.sin(t * 25))
        rings.append([bm_.verts.new(p + (s * math.cos(2 * math.pi * j / sides) + u * math.sin(2 * math.pi * j / sides)) * r) for j in range(sides)])
    for i in range(n - 1):
        for j in range(sides):
            bm_.faces.new((rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]))
    tip = bm_.verts.new(samples[-1] + (samples[-1] - samples[-2]).normalized() * r1 * 2.5)
    for j in range(sides): bm_.faces.new((rings[-1][j], rings[-1][(j + 1) % sides], tip))

if W:
    hb = arm.data.bones["Head"].head_local
    base_p = Vector((0.0, hb.y - 0.08, hb.z + 0.22))
    beam = [(0.00, 0.00, 0.00), (0.10, 0.16, 0.42), (0.34, 0.30, 0.90), (0.70, 0.28, 1.32), (1.08, 0.08, 1.56), (1.42, -0.30, 1.56), (1.66, -0.62, 1.44)]
    tines = [
        [(0.05, -0.12, 0.10), (0.16, -0.42, 0.34), (0.22, -0.78, 0.56), (0.24, -1.06, 0.52)],
        [(0.14, 0.05, 0.62), (0.34, -0.30, 0.94), (0.44, -0.66, 1.06), (0.46, -0.90, 1.02)],
        [(0.42, 0.24, 1.06), (0.66, -0.10, 1.46), (0.80, -0.44, 1.78), (0.82, -0.66, 1.86)],
        [(0.70, 0.28, 1.32), (0.78, 0.30, 1.78), (0.84, 0.22, 2.16), (0.86, 0.10, 2.46)],
        [(0.98, 0.14, 1.52), (1.10, 0.10, 1.90), (1.22, 0.00, 2.22), (1.30, -0.12, 2.42)],
        [(1.24, -0.05, 1.58), (1.50, -0.08, 1.86), (1.72, -0.20, 2.06), (1.86, -0.34, 2.14)],
        [(1.42, -0.30, 1.56), (1.64, -0.44, 1.30), (1.82, -0.66, 1.18)],
    ]
    bmA = bmesh.new(); grp = []
    for sgn in (1, -1):
        def V(p): return base_p + Vector((sgn * (p[0] + 0.14), p[1], p[2])) * 0.82
        n0 = len(bmA.verts)
        tube(bmA, [V(p) for p in beam], 0.145, 0.045, sides=7, seg=8, knot=0.06)
        for tl in tines:
            tube(bmA, [V(p) for p in tl], 0.078, 0.016, sides=5, seg=5, knot=0.05)
        grp += ["Head"] * (len(bmA.verts) - n0)
    antlers = add_group_obj(bmA, "antlers", grp)
    bmM = bmesh.new(); gm = []
    rng0 = random.Random(4)
    def cone(bm_, p, direction, length, rad):
        d = direction.normalized(); up = Vector((0, 0, 1)) if abs(d.z) < .9 else Vector((1, 0, 0))
        s = d.cross(up).normalized(); u = s.cross(d).normalized()
        ring = [bm_.verts.new(p + (s * math.cos(a) + u * math.sin(a)) * rad) for a in (0, 2.094, 4.189)]
        apex = bm_.verts.new(p + d * length)
        for j in range(3): bm_.faces.new((ring[j], ring[(j + 1) % 3], apex))
        bm_.faces.new(tuple(ring))
        return 4
    t0 = arm.data.bones["Neck1"].head_local; t1 = arm.data.bones["Head"].head_local
    for i in range(14):
        t = i / 13.0; c = t0.lerp(t1, t)
        g = "Neck1" if t < 0.34 else ("Neck2" if t < 0.68 else "Neck3")
        rad_back = 0.22 * (1 - 0.35 * t)
        for xo in ((-0.09, 0.0, 0.09) if i % 2 == 0 else (-0.045, 0.045)):
            cone(bmM, c + Vector((xo, rad_back, 0.06)), Vector((xo * 2.2, 0.75, -0.55)), rng0.uniform(0.30, 0.42), 0.075); gm += [g] * 4
        if i % 2 == 1:
            for xo in (-0.07, 0.0, 0.07):
                cone(bmM, c + Vector((xo, -0.21 * (1 - 0.3 * t), -0.05)), Vector((xo * 2, -0.35, -0.9)), rng0.uniform(0.22, 0.34), 0.065); gm += [g] * 4
    for sgn in (1, -1):
        for k in range(3):
            c = arm.data.bones["Torso3"].head_local + Vector((sgn * 0.16, 0.0 + 0.10 * k, 0.16))
            cone(bmM, c, Vector((sgn * 0.5, 0.6, -0.7)), 0.26, 0.07); gm += ["Torso3"] * 4
    mane = add_group_obj(bmM, "mane", gm)
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True); antlers.select_set(True); mane.select_set(True); bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.join()
    me = mesh.data
nv = len(me.vertices)
print("VERTS", nbv, nv)

# ---------------------------------------------------------------- classify verts: 0 body, 1 antler, 2 mane
kind = np.zeros(nv, dtype=np.int8)
if W:
    hg = mesh.vertex_groups["Head"].index
    hz = arm.data.bones["Head"].head_local.z
    for v in me.vertices:
        if v.index >= nbv:
            kind[v.index] = 1 if (len(v.groups) == 1 and v.groups[0].group == hg) else 2
else:
    for p in me.polygons:
        if p.index >= NB:
            for vi in p.vertices: kind[vi] = 1
zs = np.array([v.co.z for v in me.vertices]); ys = np.array([v.co.y for v in me.vertices]); xs = np.array([v.co.x for v in me.vertices])
ant = kind == 1
abase = np.array([0.0, ys[ant][zs[ant] < np.percentile(zs[ant], 6)].mean(), zs[ant].min()])
ah = zs[ant].max() - zs[ant].min()
print("antler base", abase, "height", ah)

# ---------------------------------------------------------------- vertex colours (display sRGB palette -> linear)
if W:
    pal = {0: (0.34, 0.17, 0.09), 1: (0.13, 0.09, 0.08), 2: (0.70, 0.76, 0.78), 3: (0.30, 0.17, 0.10), 4: (0.03, 0.03, 0.03)}
    a0, a1 = (0.20, 0.14, 0.11), (0.62, 0.56, 0.46); MANE = (0.72, 0.78, 0.80)
else:
    pal = {0: (0.66, 0.34, 0.15), 1: (0.16, 0.11, 0.09), 2: (0.94, 0.82, 0.60), 3: (0.36, 0.20, 0.10), 4: (0.04, 0.03, 0.03)}
    a0, a1 = (0.36, 0.26, 0.17), (0.90, 0.80, 0.60); MANE = (0.9, 0.9, 0.85)
acc = np.zeros((nv, 3)); cnt = np.zeros(nv)
for p in me.polygons:
    if kind[p.vertices[0]] == 0:
        c = np.array(pal.get(p.material_index, pal[0]))
        for vi in p.vertices: acc[vi] += c; cnt[vi] += 1
col = np.zeros((nv, 3))
zmin, zmax = zs[kind == 0].min(), zs[kind == 0].max()
for i in range(nv):
    if kind[i] == 1:
        t = np.clip((zs[i] - zs[ant].min()) / ah, 0, 1)
        col[i] = np.array(a0) * (1 - t) + np.array(a1) * t
    elif kind[i] == 2:
        col[i] = MANE
    else:
        col[i] = acc[i] / max(cnt[i], 1)
        col[i] *= 0.92 + 0.16 * np.clip((zs[i] - zmin) / (zmax - zmin), 0, 1) ** 0.6
col = np.array([s2l(c) for c in col])
ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
for i in range(nv): ca.data[i].color = (*col[i], 1)
ma = me.color_attributes.new("Msk", 'FLOAT_COLOR', 'POINT')
for i in range(nv): ma.data[i].color = (float(kind[i] == 1), float(kind[i] == 2), 0, 1)
for p in me.polygons: p.use_smooth = True

# ---------------------------------------------------------------- UV
bpy.ops.object.select_all(action='DESELECT'); mesh.select_set(True); bpy.context.view_layer.objects.active = mesh
while me.uv_layers: me.uv_layers.remove(me.uv_layers[0])
me.uv_layers.new(name="UVMap")
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(85), island_margin=0.006, area_weight=0.0)
bpy.ops.object.mode_set(mode='OBJECT')
me.materials.clear()
for a in list(D.materials): D.materials.remove(a)

# ---------------------------------------------------------------- bake
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'
sc.render.bake.margin = 12; sc.render.bake.margin_type = 'EXTEND'
mat = D.materials.new("bake"); mat.use_nodes = True; nt = mat.node_tree; nt.nodes.clear()
me.materials.append(mat)
out = nt.nodes.new("ShaderNodeOutputMaterial"); em = nt.nodes.new("ShaderNodeEmission")
nt.links.new(em.outputs[0], out.inputs[0])
tex = nt.nodes.new("ShaderNodeTexImage")
def bake(name, kind_, src_setup, samples=1):
    img = D.images.new(name, TEX, TEX, float_buffer=True, alpha=False); img.colorspace_settings.name = 'Non-Color'
    tex.image = img; nt.nodes.active = tex; src_setup()
    sc.cycles.samples = samples
    bpy.ops.object.bake(type=kind_)
    return np.array(img.pixels[:], dtype=np.float32).reshape(TEX, TEX, 4)[..., :3].copy()
def src_attr(nm):
    def f():
        for l in list(em.inputs[0].links): nt.links.remove(l)
        a = nt.nodes.new("ShaderNodeAttribute"); a.attribute_name = nm; a.attribute_type = 'GEOMETRY'
        nt.links.new(a.outputs["Color"], em.inputs[0])
    return f
albedo = bake("b_col", 'EMIT', src_attr("Col"))
mask = bake("b_msk", 'EMIT', src_attr("Msk"))
mn = np.array([xs.min(), ys.min(), zs.min()]); mx = np.array([xs.max(), ys.max(), zs.max()]); rg = mx - mn
def src_pos():
    for l in list(em.inputs[0].links): nt.links.remove(l)
    g = nt.nodes.new("ShaderNodeNewGeometry"); s = nt.nodes.new("ShaderNodeVectorMath"); s.operation = 'SUBTRACT'
    m_ = nt.nodes.new("ShaderNodeVectorMath"); m_.operation = 'MULTIPLY'
    s.inputs[1].default_value = tuple(mn); m_.inputs[1].default_value = tuple(1 / rg)
    nt.links.new(g.outputs["Position"], s.inputs[0]); nt.links.new(s.outputs[0], m_.inputs[0]); nt.links.new(m_.outputs[0], em.inputs[0])
pos = bake("b_pos", 'EMIT', src_pos) * rg + mn
sc.world = D.worlds.new("w"); sc.world.use_nodes = True
sc.world.light_settings.distance = 0.5 * (0.72 if W else 0.48) / 0.44
ao = bake("b_ao", 'AO', lambda: None, samples=64)[..., 0]
print("baked")

# ---------------------------------------------------------------- paint
def vnoise(cx, cy, seed):
    r = np.random.RandomState(seed); g = r.rand(cy + 2, cx + 2)
    xi = np.linspace(0, cx, TEX, endpoint=False); yi = np.linspace(0, cy, TEX, endpoint=False)
    x0 = xi.astype(int); y0 = yi.astype(int); fx = xi - x0; fy = yi - y0
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy)
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy[:, None]) + (c * (1 - fx) + d * fx) * fy[:, None]
def fbm(seed, base_=6, oct_=4):
    t = 0; amp = 1; tot = 0
    for o in range(oct_):
        t = t + vnoise(base_ * 2 ** o, base_ * 2 ** o, seed + o) * amp; tot += amp; amp *= .5
    return t / tot
isant = mask[..., 0] > 0.5; ismane = mask[..., 1] > 0.5
L = lambda x: x[..., None]
mott = fbm(11, 5, 4); fine = fbm(23, 60, 2); stroke = vnoise(90, 14, 5)
alb = albedo.copy()
alb *= L(0.86 + 0.28 * mott)
alb *= L(0.93 + 0.14 * stroke) * L(0.96 + 0.08 * fine)
warm = np.array([1.05, 0.98, 0.88]); cool = np.array([0.90, 0.97, 1.08])
alb *= (L(mott) * warm + L(1 - mott) * cool) * 0.98
alb *= L(0.55 + 0.45 * ao)
ridge = np.clip((fbm(31, 30, 2) - 0.62) * 6, 0, 1)
alb = np.where(L(isant), alb + L(ridge) * 0.10, alb)
if W:
    P = pos; zr = (P[..., 2] - zmin) / (zmax - zmin)
    moss = np.clip((fbm(41, 9, 4) - 0.50) * 5, 0, 1) * np.clip((zr - 0.55) * 5, 0, 1) * (~isant) * (~ismane) * (P[..., 1] > -0.55 * (0.72 / 0.44))
    mossc = np.array(s2l((0.30, 0.46, 0.16)))
    alb = alb * (1 - L(moss) * 0.8) + L(moss) * mossc * L(0.8 + 0.4 * fine)
    mossA = np.clip((fbm(43, 12, 3) - 0.55) * 5, 0, 1) * isant * np.clip(1.2 - (P[..., 2] - zs[ant].min()) / max(ah, 1e-3) * 1.6, 0, 1)
    alb = alb * (1 - L(mossA) * 0.7) + L(mossA) * mossc * 0.9

# ---- rune emission (glyph strokes are evaluated per texel from the baked object-space position)
Sq = (0.72 if W else 0.48) / 0.44
Q = pos / Sq
Y, Z, X = Q[..., 1], Q[..., 2], np.abs(Q[..., 0])
def seg_d(px, py, a, b):
    ax, ay = a; bx, by = b; dx, dy = bx - ax, by - ay
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(px - (ax + t * dx), py - (ay + t * dy))
GL = [
    [((.3, 0), (.3, 1)), ((.3, 1), (.8, .75)), ((.3, .7), (.8, .45))],
    [((.5, 1), (.2, .7)), ((.2, .7), (.5, .4)), ((.5, .4), (.8, .7)), ((.8, .7), (.5, 1)), ((.5, .4), (.25, 0)), ((.5, .4), (.75, 0))],
    [((.5, 0), (.5, 1)), ((.5, .55), (.15, 1)), ((.5, .55), (.85, 1))],
    [((.2, .1), (.8, .1)), ((.5, .1), (.5, .9)), ((.2, .9), (.8, .9)), ((.2, .5), (.5, .9)), ((.8, .5), (.5, .9))],
]
def glyph_field(gl, cy, cz, size, w):
    d = np.full(Y.shape, 9.0)
    for a, b in gl:
        d = np.minimum(d, seg_d((Y - cy) / size, (Z - cz) / size, (a[0] - .5, a[1] - .5), (b[0] - .5, b[1] - .5)))
    return np.exp(-(d * size / w) ** 2)
body_m = (~isant) & (~ismane)
rune = np.zeros(Y.shape)
glow_c = np.array([0.30, 0.86, 1.0])
rr = np.hypot(Y - abase[1] / Sq, Z - abase[2] / Sq)
if W:
    flank = (X > 0.075) & (Y > -0.42) & (Y < 0.52) & (Z > 0.64) & (Z < 1.16)
    for i, (cy, cz, sz) in enumerate([(-0.24, 0.98, 0.26), (0.02, 0.96, 0.28), (0.28, 0.93, 0.26)]):
        rune += glyph_field(GL[i], cy, cz, sz, 0.017) * flank
    hip = (X > 0.08) & (Y > 0.35) & (Y < 0.85) & (Z > 0.5) & (Z < 1.15)
    rune += glyph_field(GL[3], 0.62, 0.86, 0.22, 0.016) * hip
    rune += (np.exp(-((Z - 0.42) / 0.014) ** 2) + np.exp(-((Z - 0.24) / 0.010) ** 2)) * (Z < 0.6) * (np.abs(fbm(51, 40, 1) - .5) < 0.35)
    spine = (X < 0.022) & (Z > 1.0) & (Y > -0.5) & (Y < 0.55)
    rune += spine * ((0.55 + 0.45 * np.sin(Y * 90) ** 2) > 0.7)
    rune += (np.exp(-((Y + 0.72) / 0.012) ** 2) + np.exp(-((Y + 0.80) / 0.010) ** 2)) * (Z > 1.15) * (Z < 1.5) * (X < 0.16)
    rune += glyph_field(GL[1], -1.0, 1.66, 0.11, 0.008) * (Y < -0.9) * (Z > 1.5)
    rune *= body_m
    bandsA = np.exp(-(((rr / 0.34) % 1.0 - 0.5) / 0.06) ** 2) * (fbm(61, 14, 2) > 0.45)
    tipA = np.clip((Z - (abase[2] / Sq + ah / Sq * 0.80)) * 10, 0, 1)
    rune += isant * np.clip(bandsA + 0.8 * tipA, 0, 1)
    strength = 1.0
else:
    bandsA = np.exp(-(((rr / 0.30) % 1.0 - 0.5) / 0.09) ** 2)
    rune += isant * bandsA * 0.9 * (rr > 0.2)
    rune += isant * np.clip((Z - (abase[2] / Sq + ah / Sq * 0.9)) * 12, 0, 1) * 0.6
    strength = 0.65
rune = np.clip(rune, 0, 1)
emit = L(rune) * glow_c * strength + L(np.clip(rune - 0.7, 0, 1) * 2) * np.array([0.5, 0.5, 0.3])
alb = alb * (1 - L(rune) * 0.6) + L(rune) * np.array([0.25, 0.6, 0.7]) * 0.5
name = f"stagborn_{'warden' if W else 'elk'}"
def save_png(arr_lin, path):
    a = l2s(np.clip(arr_lin, 0, 1))
    img = D.images.new(os.path.basename(path), TEX, TEX, alpha=False); img.colorspace_settings.name = 'Non-Color'
    px = np.ones((TEX, TEX, 4), dtype=np.float32); px[..., :3] = a
    img.pixels.foreach_set(px.ravel()); img.filepath_raw = path; img.file_format = 'PNG'; img.save()
save_png(alb, f"{outdir}/{name}_albedo.png"); save_png(emit, f"{outdir}/{name}_emit.png")

# ---------------------------------------------------------------- final material
me.materials.clear()
m = D.materials.new(name); m.use_nodes = True; nt2 = m.node_tree
b = nt2.nodes["Principled BSDF"]
ta = nt2.nodes.new("ShaderNodeTexImage"); ta.image = D.images.load(f"{outdir}/{name}_albedo.png"); ta.image.colorspace_settings.name = 'sRGB'
te = nt2.nodes.new("ShaderNodeTexImage"); te.image = D.images.load(f"{outdir}/{name}_emit.png"); te.image.colorspace_settings.name = 'sRGB'
nt2.links.new(ta.outputs["Color"], b.inputs["Base Color"]); nt2.links.new(te.outputs["Color"], b.inputs["Emission Color"])
b.inputs["Emission Strength"].default_value = 1.0; b.inputs["Roughness"].default_value = 0.85
try: b.inputs["Specular IOR Level"].default_value = 0.1
except Exception: pass
me.materials.append(m)
me.color_attributes.remove(me.color_attributes["Col"]); me.color_attributes.remove(me.color_attributes["Msk"])
sc.render.engine = 'BLENDER_EEVEE'
print("TRIS", sum(len(p.vertices) - 2 for p in me.polygons))
bpy.ops.wm.save_as_mainfile(filepath=f"{outdir}/char_{variant}.blend")
