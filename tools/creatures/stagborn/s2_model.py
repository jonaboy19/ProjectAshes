"""Stage 2: variant geometry (Warden antlers/ivy/mane/bulk), vertex colours, UV unwrap, Cycles bake (albedo, AO, position, masks, channel map),
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
S = 0.576 if W else 0.48          # must match the s1 scale
AS = 0.8 if W else 1.0            # size of the procedural parts (antlers, ivy, mane)
def s2l(c): return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)
def l2s(a): return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(np.clip(a, 1e-6, None), 1 / 2.4) - 0.055)
def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

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
        v.co.x *= 1.14 + 0.28 * wn + 0.14 * wc + 0.10 * wh
        v.co.z += 0.06 * wc * (S / 0.72)
        if wn > 0.3: v.co.y -= 0.03 * wn * (S / 0.72)
nbv = len(me.vertices)

def add_obj(bm_, name, group_of, ch=None):
    m = D.meshes.new(name); bm_.to_mesh(m); bm_.free()
    o = D.objects.new(name, m); sc.collection.objects.link(o)
    for gname in set(group_of):
        vg = o.vertex_groups.new(name=gname)
        vg.add([i for i, g in enumerate(group_of) if g == gname], 1.0, 'REPLACE')
    if ch is not None:
        a = m.color_attributes.new("Ch", 'FLOAT_COLOR', 'POINT')
        for i, c in enumerate(ch): a.data[i].color = c
    return o

def tube(bm_, pts, r0, r1, sides, seg, knot, pref, tag, rec, tip_k=1.8):
    """Catmull-Rom tube with parallel-transport rings. rec gets (line, arclength, t, tag) per vertex; line=1 on ring index 0 (the rune channel)."""
    P = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    samples = []
    for i in range(1, len(P) - 2):
        for k in range(seg):
            t = k / seg; a, b, c, d = P[i - 1], P[i], P[i + 1], P[i + 2]
            samples.append(0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (-a + 3 * b - 3 * c + d) * t ** 3))
    samples.append(pts[-1])
    n = len(samples); rings = []; s_prev = None; arc = 0.0
    total = sum((samples[i + 1] - samples[i]).length for i in range(n - 1))
    for i, p in enumerate(samples):
        t = i / (n - 1)
        if i: arc += (p - samples[i - 1]).length
        tan = (samples[min(i + 1, n - 1)] - samples[max(i - 1, 0)]).normalized()
        ref = pref if s_prev is None else s_prev
        s = (ref - tan * ref.dot(tan))
        if s.length < 1e-4: s = tan.cross(Vector((0, 0, 1)))
        s = s.normalized(); u = tan.cross(s).normalized(); s_prev = s
        r = (r0 + (r1 - r0) * (t ** 0.8)) * (1 + knot * math.sin(t * 25))
        ring = []
        for j in range(sides):
            ring.append(bm_.verts.new(p + (s * math.cos(2 * math.pi * j / sides) + u * math.sin(2 * math.pi * j / sides)) * r))
            line = max(0.0, 1.0 - min(j, sides - j)); rec.append((line, arc, t, tag))
        rings.append(ring)
    for i in range(n - 1):
        for j in range(sides):
            bm_.faces.new((rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]))
    tip = bm_.verts.new(samples[-1] + (samples[-1] - samples[-2]).normalized() * r1 * tip_k); rec.append((0.0, arc, 1.0, tag))
    for j in range(sides): bm_.faces.new((rings[-1][j], rings[-1][(j + 1) % sides], tip))

if W:
    rng0 = random.Random(11)
    hb = arm.data.bones["Head"].head_local
    base_p = Vector((0.0, hb.y - 0.06 * AS, hb.z + 0.24 * AS))
    beam = [(0.00, 0.00, 0.00), (0.10, 0.16, 0.42), (0.34, 0.30, 0.90), (0.70, 0.28, 1.32), (1.08, 0.08, 1.56), (1.42, -0.30, 1.56), (1.66, -0.62, 1.44)]
    tines = [
        [(0.05, -0.12, 0.10), (0.16, -0.42, 0.34), (0.22, -0.78, 0.56), (0.24, -1.06, 0.52)],     # brow tine, points forward
        [(0.14, 0.05, 0.62), (0.34, -0.30, 0.94), (0.44, -0.66, 1.06), (0.46, -0.90, 1.02)],      # bez
        [(0.42, 0.24, 1.06), (0.66, -0.10, 1.46), (0.80, -0.44, 1.78), (0.82, -0.66, 1.86)],      # trez
        [(0.70, 0.28, 1.32), (0.78, 0.30, 1.78), (0.84, 0.22, 2.16), (0.86, 0.10, 2.46)],         # crown tines
        [(0.98, 0.14, 1.52), (1.10, 0.10, 1.90), (1.22, 0.00, 2.22), (1.30, -0.12, 2.42)],
        [(1.24, -0.05, 1.58), (1.50, -0.08, 1.86), (1.72, -0.20, 2.06), (1.86, -0.34, 2.14)],
        [(1.42, -0.30, 1.56), (1.64, -0.44, 1.30), (1.82, -0.66, 1.18)],                            # drop tine
        # back layer: shorter tines fanning rearward along the beam
        [(0.12, 0.18, 0.46), (0.16, 0.50, 0.62), (0.18, 0.80, 0.70)],
        [(0.36, 0.32, 0.92), (0.42, 0.66, 1.10), (0.44, 0.98, 1.16)],
        [(0.72, 0.30, 1.34), (0.80, 0.62, 1.60), (0.86, 0.90, 1.72)],
    ]
    bmA = bmesh.new(); grp = []; recA = []; bmI = bmesh.new(); grpI = []; recI = []
    for sgn in (1, -1):
        def V(p): return base_p + Vector((sgn * (p[0] + 0.14), p[1], p[2])) * AS
        pref = Vector((sgn, -0.5, 0.35))
        n0 = len(bmA.verts)
        tube(bmA, [V(p) for p in beam], 0.155 * AS, 0.058 * AS, 7, 8, 0.06, pref, 1, recA)
        for ti, tl in enumerate(tines):
            tube(bmA, [V(p) for p in tl], 0.088 * AS, 0.030 * AS, 5, 5, 0.05, pref, 1, recA)
            # layered spur off the middle of the longer tines
            if ti in (1, 2, 3, 4, 5):
                m = V(tl[1]); d = (V(tl[2]) - m).normalized(); out = Vector((sgn * 0.7, -0.25, 0.65))
                d2 = (d * 0.5 + out).normalized()
                tube(bmA, [m, m + d2 * 0.14 * AS + Vector((0, 0, 0.03)) * AS, m + d2 * 0.34 * AS + Vector((0, 0, 0.08)) * AS], 0.050 * AS, 0.022 * AS, 4, 4, 0.0, pref, 1, recA)
        grp += ["Head"] * (len(bmA.verts) - n0)
        # ivy strands hanging off the beam and the lower tines, with leaf quads
        anchors = [V(beam[2]), V(beam[3]), V(beam[4]), V(tines[0][2]), V(tines[1][2]), V(tines[2][1]), V(tines[6][1])]
        for a in anchors:
            n1 = len(bmI.verts)
            sway = Vector((sgn * rng0.uniform(-0.03, 0.05), rng0.uniform(-0.05, 0.05), 0)) * AS
            pts = [a + Vector((0, 0, -0.02)) * AS, a + Vector((0, 0.04, -0.22)) * AS + sway, a + Vector((sgn * 0.02, 0.02, -0.5)) * AS + sway * 1.6, a + Vector((sgn * 0.03, 0.05, -0.78 - rng0.uniform(0, 0.25))) * AS + sway * 2]
            tube(bmI, pts, 0.014 * AS, 0.008 * AS, 3, 4, 0.0, Vector((0, 1, 0)), 2, recI, tip_k=1.0)
            # leaves (2 tris each) along the strand: sample the control points
            for k, pt in enumerate(pts[1:]):
                for l in range(2):
                    c = pt + Vector((rng0.uniform(-0.05, 0.05), rng0.uniform(-0.05, 0.05), rng0.uniform(-0.08, 0.06))) * AS
                    ang = rng0.uniform(0, math.pi); sz = rng0.uniform(0.05, 0.075) * AS
                    e1 = Vector((math.cos(ang), math.sin(ang) * 0.6, 0.15)).normalized() * sz; e2 = Vector((-math.sin(ang) * 0.5, math.cos(ang) * 0.5, -1.0)).normalized() * sz * 1.2
                    vs = [bmI.verts.new(c - e1), bmI.verts.new(c + e2), bmI.verts.new(c + e1), bmI.verts.new(c - e2)]
                    bmI.faces.new(vs)
                    for _ in vs: recI.append((0.0, 1.0, 1.0, 2))
            grpI += ["Head"] * (len(bmI.verts) - n1)
    antlers = add_obj(bmA, "antlers", grp, recA)
    ivy = add_obj(bmI, "ivy", grpI, recI)
    # mane + throat ruff: tapered cones skinned to the neck
    bmM = bmesh.new(); gm = []
    def cone(bm_, p, direction, length, rad):
        d = direction.normalized(); up = Vector((0, 0, 1)) if abs(d.z) < .9 else Vector((1, 0, 0))
        s = d.cross(up).normalized(); u = s.cross(d).normalized()
        ring = [bm_.verts.new(p + (s * math.cos(a) + u * math.sin(a)) * rad) for a in (0, 2.094, 4.189)]
        apex = bm_.verts.new(p + d * length)
        for j in range(3): bm_.faces.new((ring[j], ring[(j + 1) % 3], apex))
        bm_.faces.new(tuple(ring))
    t0 = arm.data.bones["Neck1"].head_local; t1 = arm.data.bones["Head"].head_local
    for i in range(16):
        t = i / 15.0; c = t0.lerp(t1, t)
        g = "Neck1" if t < 0.34 else ("Neck2" if t < 0.68 else "Neck3")
        rad_back = 0.22 * AS * (1 - 0.35 * t) * 1.15
        for xo in ((-0.10, 0.0, 0.10) if i % 2 == 0 else (-0.05, 0.05)):
            cone(bmM, c + Vector((xo * AS, rad_back, 0.06 * AS)), Vector((xo * 2.2, 0.75, -0.55)), rng0.uniform(0.32, 0.46) * AS, 0.085 * AS); gm += [g] * 4
        if i % 2 == 1:
            for xo in (-0.09, 0.0, 0.09):
                cone(bmM, c + Vector((xo * AS, -0.21 * AS * (1 - 0.3 * t), -0.05 * AS)), Vector((xo * 2, -0.35, -0.9)), rng0.uniform(0.26, 0.38) * AS, 0.075 * AS); gm += [g] * 4
    for sgn in (1, -1):
        for k in range(3):
            c = arm.data.bones["Torso3"].head_local + Vector((sgn * 0.16 * AS, 0.10 * k * AS, 0.16 * AS))
            cone(bmM, c, Vector((sgn * 0.5, 0.6, -0.7)), 0.28 * AS, 0.08 * AS); gm += ["Torso3"] * 4
    mane = add_obj(bmM, "mane", gm, [(0.0, 0.0, 0.0, 0.0)] * len(bmM.verts))
    bpy.ops.object.select_all(action='DESELECT')
    mesh.select_set(True); antlers.select_set(True); ivy.select_set(True); mane.select_set(True); bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.join()
    me = mesh.data
nv = len(me.vertices)
print("VERTS", nbv, nv)

# ---------------------------------------------------------------- classify verts: 0 body, 1 antler, 2 mane, 3 ivy
kind = np.zeros(nv, dtype=np.int8); chan = np.zeros((nv, 4), dtype=np.float32)
if W:
    cha = me.color_attributes["Ch"]
    for i in range(nbv, nv):
        c = cha.data[i].color; chan[i] = c
        kind[i] = 1 if abs(c[3] - 1) < .01 else (3 if abs(c[3] - 2) < .01 else 2)
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
    pal = {0: (0.36, 0.18, 0.09), 1: (0.12, 0.08, 0.07), 2: (0.80, 0.80, 0.74), 3: (0.28, 0.15, 0.08), 4: (0.03, 0.03, 0.03)}
    a0, a1 = (0.17, 0.12, 0.09), (0.66, 0.60, 0.48); MANE = (0.80, 0.83, 0.82)
else:
    pal = {0: (0.66, 0.34, 0.15), 1: (0.16, 0.11, 0.09), 2: (0.94, 0.82, 0.60), 3: (0.36, 0.20, 0.10), 4: (0.04, 0.03, 0.03)}
    a0, a1 = (0.36, 0.26, 0.17), (0.90, 0.80, 0.60); MANE = (0.9, 0.9, 0.85)
IVY_S, IVY_L = (0.20, 0.30, 0.11), (0.36, 0.60, 0.20)
acc = np.zeros((nv, 3)); cnt = np.zeros(nv)
for p in me.polygons:
    if kind[p.vertices[0]] == 0:
        c = np.array(pal.get(p.material_index, pal[0]))
        for vi in p.vertices: acc[vi] += c; cnt[vi] += 1
col = np.zeros((nv, 3))
zmin, zmax = zs[kind == 0].min(), zs[kind == 0].max()
for i in range(nv):
    if kind[i] == 1:
        t = np.clip((zs[i] - zs[ant].min()) / ah, 0, 1) if not W else np.clip(chan[i][2] * 0.7 + (zs[i] - zs[ant].min()) / ah * 0.3, 0, 1)
        col[i] = np.array(a0) * (1 - t) + np.array(a1) * t
    elif kind[i] == 2:
        col[i] = MANE
    elif kind[i] == 3:
        col[i] = IVY_L if chan[i][1] > 0.5 else IVY_S
    else:
        col[i] = acc[i] / max(cnt[i], 1)
        col[i] *= 0.90 + 0.18 * np.clip((zs[i] - zmin) / (zmax - zmin), 0, 1) ** 0.6
col = np.array([s2l(c) for c in col])
ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
for i in range(nv): ca.data[i].color = (*col[i], 1)
ma = me.color_attributes.new("Msk", 'FLOAT_COLOR', 'POINT')
for i in range(nv): ma.data[i].color = (float(kind[i] == 1), float(kind[i] == 2), float(kind[i] == 3), 1)
cb = me.color_attributes.new("Chn", 'FLOAT_COLOR', 'POINT')
for i in range(nv): cb.data[i].color = (chan[i][0], chan[i][1] * 0.25, chan[i][2], 1)   # arclength scaled to stay in a friendly range
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
chn = bake("b_chn", 'EMIT', src_attr("Chn"))
mn = np.array([xs.min(), ys.min(), zs.min()]); mx = np.array([xs.max(), ys.max(), zs.max()]); rg = mx - mn
def src_pos():
    for l in list(em.inputs[0].links): nt.links.remove(l)
    g = nt.nodes.new("ShaderNodeNewGeometry"); s = nt.nodes.new("ShaderNodeVectorMath"); s.operation = 'SUBTRACT'
    m_ = nt.nodes.new("ShaderNodeVectorMath"); m_.operation = 'MULTIPLY'
    s.inputs[1].default_value = tuple(mn); m_.inputs[1].default_value = tuple(1 / rg)
    nt.links.new(g.outputs["Position"], s.inputs[0]); nt.links.new(s.outputs[0], m_.inputs[0]); nt.links.new(m_.outputs[0], em.inputs[0])
pos = bake("b_pos", 'EMIT', src_pos) * rg + mn
sc.world = D.worlds.new("w"); sc.world.use_nodes = True
sc.world.light_settings.distance = 0.5 * S / 0.44
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
def blur(a, r):
    k = 2 * r + 1
    for ax in (0, 1):
        c = np.cumsum(np.pad(a, [(r + 1, r) if i == ax else (0, 0) for i in range(a.ndim)], mode='edge'), axis=ax)
        a = (np.take(c, range(k, c.shape[ax]), axis=ax) - np.take(c, range(0, c.shape[ax] - k), axis=ax)) / k
    return a
isant = mask[..., 0] > 0.5; ismane = mask[..., 1] > 0.5; isivy = mask[..., 2] > 0.5
body_m = ~(isant | ismane | isivy)
L = lambda x: x[..., None]
mott = fbm(11, 5, 4); fine = fbm(23, 60, 2); stroke = vnoise(90, 14, 5); hair = vnoise(260, 40, 9)
Sq = S / 0.44
Q = pos / Sq
Y, Z, X = Q[..., 1], Q[..., 2], np.abs(Q[..., 0])
alb = albedo.copy()
alb *= L(0.86 + 0.28 * mott)
alb *= L(0.90 + 0.20 * stroke) * L(0.94 + 0.12 * hair) * L(0.96 + 0.08 * fine)
warm = np.array([1.05, 0.98, 0.88]); cool = np.array([0.90, 0.97, 1.08])
alb *= (L(mott) * warm + L(1 - mott) * cool) * 0.98
alb *= L(0.55 + 0.45 * ao)
ridge = np.clip((fbm(31, 30, 2) - 0.62) * 6, 0, 1)
bark = vnoise(500, 24, 17)
alb = np.where(L(isant), alb * L(0.78 + 0.44 * bark) + L(ridge) * 0.10, alb)
alb = np.where(L(isivy), alb * L(0.8 + 0.4 * fine), alb)
if W:
    # richer fur: darker saddle over the back, lighter belly, darker lower legs, pale fetlock tufts and dark hooves
    zr = np.clip((Z - 0.60) / 0.55, 0, 1)
    saddle = sstep(0.55, 0.9, zr) * sstep(-0.50, -0.25, Y) * (1 - sstep(0.55, 0.8, Y)) + 0.6 * sstep(0.85, 1.0, zr) * (1 - sstep(0.7, 1.0, Y))
    spine = (1 - sstep(0.0, 0.06, X)) * sstep(0.85, 0.98, zr)
    umber = np.array(s2l((0.20, 0.10, 0.06)))
    alb = np.where(L(body_m), alb * (1 - L(saddle) * 0.55) + L(saddle) * umber * L(0.9 + 0.3 * stroke) * 0.55, alb)
    alb = np.where(L(body_m), alb * (1 - L(spine) * 0.4) + L(spine) * np.array(s2l((0.10, 0.06, 0.04))) * 0.4, alb)
    belly = (1 - sstep(0.62, 0.86, Z)) * sstep(0.3, 0.5, Z) * (Y > -0.6)
    alb = np.where(L(body_m), alb * (1 - L(belly) * 0.45) + L(belly) * np.array(s2l((0.72, 0.56, 0.38))) * 0.45, alb)
    legs = (1 - sstep(0.34, 0.5, Z))
    alb = np.where(L(body_m), alb * (1 - L(legs) * 0.55) + L(legs) * np.array(s2l((0.16, 0.10, 0.07))) * 0.55, alb)
    tuft = np.exp(-((Z - 0.17) / 0.045) ** 2) * (Z < 0.3)
    alb = np.where(L(body_m), alb * (1 - L(tuft) * 0.65) + L(tuft) * np.array(s2l((0.78, 0.72, 0.58))) * L(0.85 + 0.3 * hair) * 0.65, alb)
    hoof = 1 - sstep(0.075, 0.105, Z)
    alb = np.where(L(body_m), alb * (1 - L(hoof)) + L(hoof) * np.array(s2l((0.075, 0.06, 0.055))) * L(0.8 + 0.6 * fine), alb)
    rim = np.exp(-((Z - 0.095) / 0.012) ** 2)
    alb = np.where(L(body_m), alb + L(rim) * 0.05, alb)
    # long-hair streaks on the silver mane
    alb = np.where(L(ismane), alb * L(0.85 + 0.30 * vnoise(300, 10, 21)), alb)
else:
    hoof = 1 - sstep(0.075, 0.105, Z)
    alb = np.where(L(body_m), alb * (1 - L(hoof) * 0.6) + L(hoof) * 0.6 * np.array(s2l((0.10, 0.08, 0.07))), alb)

# ---- rune emission
def seg_min_dist(py, pz, curves):
    """distance from texels (py,pz arrays) to a set of polylines [(N,2) arrays]"""
    d = np.full(py.shape, 9.0, dtype=np.float32)
    for cv in curves:
        a = cv[:-1]; b = cv[1:]
        for (ay, az), (by, bz) in zip(a, b):
            dy, dz = by - ay, bz - az; ll = dy * dy + dz * dz + 1e-12
            t = np.clip(((py - ay) * dy + (pz - az) * dz) / ll, 0, 1)
            d = np.minimum(d, np.hypot(py - (ay + t * dy), pz - (az + t * dz)))
    return d
rune = np.zeros(Y.shape, dtype=np.float32)
core_w = 0.0085
rr = np.hypot(Y - abase[1] / Sq, Z - abase[2] / Sq)
if W:
    curves = []
    th = np.linspace(0, 3.1 * math.pi, 120)
    r_ = 0.022 * np.exp(0.235 * th)
    sp = np.stack([-0.30 + r_ * np.cos(th), 0.92 + r_ * np.sin(th)], 1)            # shoulder spiral
    curves.append(sp)
    tail = np.linspace(0, 1, 60)                                                     # spiral outer end flows back along the flank in an S
    ys_ = sp[-1, 0] + tail * (0.62 - sp[-1, 0]) * 1.0
    zs_ = 0.98 + 0.05 * np.sin(tail * 2 * math.pi * 1.5 + 0.6) - 0.05 * tail
    curves.append(np.stack([ys_, zs_], 1))
    tt = np.linspace(0, 2 * math.pi, 140)                                            # haunch trefoil knot
    kx = (np.sin(tt) + 2 * np.sin(2 * tt)) / 3.0; kz = (np.cos(tt) - 2 * np.cos(2 * tt)) / 3.0
    curves.append(np.stack([0.50 + 0.15 * kx, 0.86 + 0.15 * kz], 1))
    tt2 = np.linspace(0, 1, 50)                                                      # parallel flow lines under the saddle
    curves.append(np.stack([-0.32 + tt2 * 0.98, 1.08 + 0.025 * np.sin(tt2 * 2 * math.pi * 2.2)], 1))
    curves.append(np.stack([-0.22 + tt2 * 0.85, 0.79 + 0.03 * np.sin(tt2 * 2 * math.pi * 1.6 + 1.2)], 1))
    ok = np.linspace(0, 1, 40)                                                       # shoulder-to-neck flow
    curves.append(np.stack([-0.50 - ok * 0.18 + 0.02 * np.sin(ok * 9), 1.0 + ok * 0.26], 1))
    flank_m = (X > 0.075) & (Y > -0.72) & (Y < 0.85) & (Z > 0.62) & (Z < 1.25) & body_m
    idx = np.nonzero(flank_m)
    dflank = seg_min_dist(Y[idx], Z[idx], curves)
    rune[idx] += np.exp(-(dflank / core_w) ** 2)
    # knots: small pearls where the lines cross
    for (py, pz) in [(-0.30, 0.92), (0.06, 0.985), (0.30, 1.0), (0.50, 0.86), (-0.55, 1.06)]:
        rune += np.exp(-(np.hypot(Y - py, Z - pz) / 0.014) ** 2) * flank_m * 0.9
    # neck braid: two interlaced strands along the neck axis
    nk = np.linspace(0.06, 0.88, 90)
    A0 = np.array([-0.66, 1.14]); A1 = np.array([-0.94, 1.66]); ax_ = (A1 - A0); nl = ax_ / np.linalg.norm(ax_); nn = np.array([nl[1] * -1, nl[0]])
    nk_curves = []
    for ph in (0, math.pi):
        pts_ = A0[None] + nk[:, None] * ax_[None] + (0.045 * np.sin(nk * 2 * math.pi * 2.6 + ph))[:, None] * nn[None]
        nk_curves.append(pts_)
    neck_m = (X > 0.045) & (Y > -1.0) & (Y < -0.55) & (Z > 1.08) & (Z < 1.72) & body_m
    idn = np.nonzero(neck_m)
    dn = seg_min_dist(Y[idn], Z[idn], nk_curves)
    rune[idn] += np.exp(-(dn / (core_w * 0.9)) ** 2)
    # legs: a thin double ring at the knee and a spiral wrap above the hoof
    leg_m = (Z < 0.62) & (X > 0.02) & body_m
    rune += (np.exp(-((Z - 0.43) / 0.007) ** 2) + 0.7 * np.exp(-((Z - 0.395) / 0.005) ** 2)) * leg_m * (0.6 + 0.4 * (fbm(51, 40, 1) > 0.4))
    # spine: thin continuous line with pulsing nodes
    spn = (X < 0.014) & (Z > 1.02) & (Y > -0.55) & (Y < 0.6) & body_m
    rune += spn * (0.5 + 0.5 * (np.sin(Y * 110) > 0.7))
    # brow: three fine arcs above the eye
    rune += (np.exp(-((np.hypot(Y + 0.98, Z - 1.63) - 0.07) / 0.005) ** 2) * (Z > 1.63) * (X < 0.12) + np.exp(-((np.hypot(Y + 0.98, Z - 1.63) - 0.10) / 0.004) ** 2) * (Z > 1.65) * (X < 0.12)) * body_m
    rune = np.clip(rune, 0, 1)
    # antler channels: one thin line up every beam and tine, dashed with pearls, brightening to the tips
    line = sstep(0.42, 0.9, chn[..., 0]); s_ = chn[..., 1] * 4.0; t_ = chn[..., 2]
    dash = 0.45 + 0.55 * (np.sin(s_ * 2 * math.pi / (0.16 * AS)) > -0.15)
    node = np.exp(-(((s_ / (0.32 * AS)) % 1.0 - 0.5) / 0.09) ** 2)
    ant_glow = line * np.clip(dash * (0.55 + 0.45 * t_) + 0.7 * node, 0, 1) + sstep(0.86, 0.98, t_) * isant * 0.8
    rune += (isant * np.clip(ant_glow, 0, 1)).astype(np.float32)
    strength = 1.0
else:
    bandsA = np.exp(-(((rr / 0.30) % 1.0 - 0.5) / 0.09) ** 2)
    rune += isant * bandsA * 0.9 * (rr > 0.2)
    rune += isant * np.clip((Z - (abase[2] / Sq + ah / Sq * 0.9)) * 12, 0, 1) * 0.6
    strength = 0.65
rune = np.clip(rune, 0, 1)
core = np.clip(rune, 0, 1)
halo = blur(core, 3) * 1.2 + blur(core, 8) * 0.9 if W else blur(core, 2)
glow = np.clip(core + 0.45 * halo, 0, 1.2)
glow_c = np.array([0.30, 0.86, 1.0])
emit = L(glow) * glow_c * strength + L(np.clip(core - 0.6, 0, 1) * 1.6) * np.array([0.55, 0.5, 0.3]) * strength
alb = alb * (1 - L(core) * 0.35) + L(core) * np.array([0.25, 0.6, 0.7]) * 0.35
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
for nm_ in ("Col", "Msk", "Chn", "Ch"):
    if nm_ in me.color_attributes: me.color_attributes.remove(me.color_attributes[nm_])
sc.render.engine = 'BLENDER_EEVEE'
print("TRIS", sum(len(p.vertices) - 2 for p in me.polygons))
bpy.ops.wm.save_as_mainfile(filepath=f"{outdir}/char_{variant}.blend")
