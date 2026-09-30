"""The Wyrm's Ribs: landmark kit of giant bones (original procedural work).

Pieces: giant_rib_a, giant_rib_b, giant_spine_segment, giant_skull, giant_tusk
Each -> <name>_lod0.glb / <name>_lod1.glb, origin at ground contact, +Y up, metres.
Look: warm ivory bone painted in vertex colours (tan crevices, cream edge
highlights, moss, cracks, frost-tinted horn tips), simple grass/flowers at the base.

Run (Blender 5.x, headless):
  blender -b --factory-startup --python make_giant_bones.py -- build     # meshes + json
  blender -b --factory-startup --python make_giant_bones.py -- render    # sheet + ridge previews
Authoring is in Blender coords (Z up, snout/arch toward +X); the glTF exporter
converts to Y-up.
"""
import bpy, bmesh, sys, os, math, json, random
from mathutils import Vector, Matrix, noise

OUT = r"C:\Users\Jonna\Documents\PA_wt_look\kingdom\assets\incoming\region1\landmarks"
PREV = os.path.join(OUT, "_previews")
os.makedirs(PREV, exist_ok=True)

# ----------------------------------------------------------------- colours
def h(hexs):
    hexs = hexs.lstrip("#")
    return tuple(int(hexs[i:i + 2], 16) / 255.0 for i in (0, 2, 4))

IV = h("f3dcaa"); TAN = h("c48f55"); DEEP = h("8c5c34"); HI = h("fff3c9")
MOSS = h("5f9a2c"); MOSSL = h("9ec946"); DIRT = h("8a6a3e"); ICE = h("cfe6f2")
SOCK = h("3e2a1c"); MARROW = h("c9925a")
GREENS = [h("4c8a2a"), h("5ea030"), h("447a26")]
GREEN_TIP = [h("a5cf4a"), h("b9d955"), h("8fbf3d")]
FLOWERS = [h("fffbe8"), h("ffd23c"), h("f06a6a"), h("8f9bff"), h("fffbe8")]

def s2l(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))

def sstep(e0, e1, x):
    if e0 == e1:
        return 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)

# ----------------------------------------------------------------- mesh builder
class Mesh:
    def __init__(self):
        self.v = []      # Vector
        self.tag = []    # ('b', tipweight, darkweight) | ('f', rgb, None)
        self.f = []

    def add(self, verts, tags, faces):
        b = len(self.v)
        self.v += [Vector(x) for x in verts]
        self.tag += tags
        self.f += [tuple(i + b for i in f) for f in faces]
        return b

    def transform(self, mat, start=0, end=None):
        end = len(self.v) if end is None else end
        for i in range(start, end):
            self.v[i] = mat @ self.v[i]


def ico_data(sub):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    verts = [v.co.copy() for v in bm.verts]
    idx = {v: i for i, v in enumerate(bm.verts)}
    faces = [tuple(idx[v] for v in f.verts) for f in bm.faces]
    bm.free()
    return verts, faces

_ICO = {}
def blob(m, c, radii, tag, sub=1, rng=None, jit=0.0, rot_z=0.0):
    if sub not in _ICO:
        _ICO[sub] = ico_data(sub)
    vs, fs = _ICO[sub]
    out = []
    cz, sz = math.cos(rot_z), math.sin(rot_z)
    for v in vs:
        p = Vector((v.x * radii[0], v.y * radii[1], v.z * radii[2]))
        if rng and jit:
            p *= 1 + rng.uniform(-jit, jit)
        p = Vector((p.x * cz - p.y * sz, p.x * sz + p.y * cz, p.z))
        out.append(p + Vector(c))
    return m.add(out, [tag] * len(out), fs)


def cone(m, base, tip, r, n, tag_base, tag_tip, cap=False):
    base = Vector(base); tip = Vector(tip)
    ax = (tip - base).normalized()
    ref = Vector((0, 0, 1)) if abs(ax.z) < 0.9 else Vector((1, 0, 0))
    u = ax.cross(ref).normalized(); w = ax.cross(u)
    verts = [base + (u * math.cos(2 * math.pi * i / n) + w * math.sin(2 * math.pi * i / n)) * r for i in range(n)]
    verts.append(tip)
    tags = [tag_base] * n + [tag_tip]
    faces = [(i, (i + 1) % n, n) for i in range(n)]
    if cap:
        faces.append(tuple(reversed(range(n))))
    return m.add(verts, tags, faces)


def sweep(m, pts, prof, nseg, cap0="fan", cap1="fan", ref=(0, 0, 1), tipfn=None,
          ext0=0.0, ext1=0.0, jag=None, darkfn=None):
    """Sweep an elliptical section along pts. prof(t,a,c)->(r_n, r_b). Returns ring vertex start."""
    pts = [Vector(p) for p in pts]
    n = len(pts)
    T = []
    for i in range(n):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, n - 1)]
        T.append((b - a).normalized())
    N = []
    prev = Vector(ref)
    for i in range(n):
        nn = prev - T[i] * prev.dot(T[i])
        if nn.length < 1e-4:
            nn = Vector((1, 0, 0)) - T[i] * T[i].x
        nn.normalize(); N.append(nn); prev = nn
    verts, tags = [], []
    for i in range(n):
        t = i / (n - 1)
        B = T[i].cross(N[i])
        for j in range(nseg):
            a = 2 * math.pi * j / nseg
            rn, rb = prof(t, a, pts[i])
            p = pts[i] + N[i] * math.cos(a) * rn + B * math.sin(a) * rb
            if jag and i == n - 1:
                p = p + T[i] * jag[j]
            verts.append(p)
            tw = tipfn(t) if tipfn else 0.0
            dw = darkfn(p) if darkfn else 0.0
            tags.append(('b', tw, dw))
    faces = []
    for i in range(n - 1):
        for j in range(nseg):
            j2 = (j + 1) % nseg
            faces.append((i * nseg + j, i * nseg + j2, (i + 1) * nseg + j2, (i + 1) * nseg + j))
    base = m.add(verts, tags, faces)
    # caps
    def cap(mode, ring_i, direction, ext):
        c = pts[ring_i]
        if mode is None:
            return
        cen = c + direction * (ext if mode in ("point", "dome") else (-0.25 if mode == "jag" else 0.0))
        tg = ('f', MARROW, None) if mode == "jag" else ('b', tipfn(1.0 if ring_i else 0.0) if tipfn else 0.0, 0.0)
        ci = m.add([cen], [tg], [])
        for j in range(nseg):
            j2 = (j + 1) % nseg
            a0 = base + ring_i * nseg + j; a1 = base + ring_i * nseg + j2
            m.f.append((ci, a1, a0) if ring_i == 0 else (ci, a0, a1))
    cap(cap0, 0, -T[0], ext0)
    cap(cap1, n - 1, T[-1], ext1)
    return base


# ----------------------------------------------------------------- painting + finalize
def paint_and_build(m, name, seed=1, mosscap=2.0, paint=True):
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in m.v]
    for f in m.f:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass
    bm.verts.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.normal_update()
    n = len(bm.verts)
    curv = [0.0] * n
    for v in bm.verts:
        s = 0.0; k = 0
        for e in v.link_edges:
            u = e.other_vert(v); d = u.co - v.co
            L = d.length
            if L > 1e-6:
                s += d.dot(v.normal) / L; k += 1
        curv[v.index] = -s / k if k else 0.0
    for _ in range(2):
        nc = curv[:]
        for v in bm.verts:
            k = [curv[e.other_vert(v).index] for e in v.link_edges]
            if k:
                nc[v.index] = 0.5 * curv[v.index] + 0.5 * sum(k) / len(k)
        curv = nc
    sv = Vector((seed * 7.13, seed * 3.71, seed * 1.37))
    cols = []
    for i, v in enumerate(bm.verts):
        tg = m.tag[i]
        if tg[0] == 'f':
            cols.append(tg[1]); continue
        p = v.co; nr = v.normal
        n1 = noise.noise(p * 0.3 + sv)
        col = mix(IV, TAN, 0.12 + 0.18 * (n1 * 0.5 + 0.5))
        col = mix(col, TAN, (1 - nr.z) * 0.14)
        cv = max(-1.0, min(1.0, curv[i] * 2.2))
        if cv > 0:
            col = mix(col, HI, cv * 0.75)
        else:
            col = mix(col, DEEP, -cv * 0.85)
        # cracks: thin contours of two noise fields
        for sc, off in ((0.55, 11.0), (1.3, 27.0)):
            q = noise.noise(Vector((p.x * sc * 0.5, p.y * sc * 0.5, p.z * sc)) + sv * 0.3 + Vector((off, 0, 0)))
            cr = 1 - sstep(0.0, 0.035, abs(q))
            col = mix(col, mix(DEEP, SOCK, 0.4), cr * 0.5)
        # moss
        mh = mosscap + 1.4 * noise.noise(p * 0.4 + sv * 2)
        mm = sstep(mh, mh - 1.2, p.z) * sstep(-0.35, 0.35, nr.z)
        mm *= sstep(-0.45, 0.2, noise.noise(p * 0.85 + sv * 3) + 0.25)
        col = mix(col, mix(MOSS, MOSSL, cv * 0.8 + 0.25 + 0.25 * noise.noise(p * 2.0)), mm * 0.95)
        # ground dirt
        col = mix(col, DIRT, sstep(0.5, -0.5, p.z) * 0.75)
        if tg[1] > 0:
            col = mix(col, ICE, tg[1])
        if tg[2] > 0:
            col = mix(col, SOCK, tg[2])
        cols.append(col)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    for i, c in enumerate(cols):
        ca.data[i].color = (s2l(c[0]), s2l(c[1]), s2l(c[2]), 1.0)
    me.materials.append(bone_material())
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


_MAT = None
def bone_material():
    global _MAT
    if _MAT:
        return _MAT
    mat = bpy.data.materials.new("WyrmBone")
    mat.use_nodes = True
    nt = mat.node_tree
    for nd in list(nt.nodes):
        nt.nodes.remove(nd)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bs = nt.nodes.new("ShaderNodeBsdfPrincipled")
    vc = nt.nodes.new("ShaderNodeVertexColor"); vc.layer_name = "Col"
    bs.inputs["Roughness"].default_value = 0.9
    bs.inputs["Metallic"].default_value = 0.0
    for k in ("Specular IOR Level", "Specular"):
        if k in bs.inputs:
            bs.inputs[k].default_value = 0.15
    nt.links.new(vc.outputs["Color"], bs.inputs["Base Color"])
    nt.links.new(bs.outputs["BSDF"], out.inputs["Surface"])
    _MAT = mat
    return mat


# ----------------------------------------------------------------- decoration
def fbm_r(p, seed):
    return noise.noise(p + Vector((seed, seed * 2.3, 0)))

def tuft(m, rng, c, scale=1.0, blades=5):
    for _ in range(blades):
        a = rng.uniform(0, 6.283)
        d = rng.uniform(0.05, 0.22) * scale
        base = Vector((c[0] + math.cos(a) * d, c[1] + math.sin(a) * d, c[2] - 0.03))
        hgt = rng.uniform(0.45, 0.95) * scale
        lean = rng.uniform(0.1, 0.35) * scale
        tip = base + Vector((math.cos(a) * lean, math.sin(a) * lean, hgt))
        k = rng.randrange(3)
        cone(m, base, tip, 0.06 * scale, 3, ('f', GREENS[k], None), ('f', GREEN_TIP[k], None))

def flower(m, rng, c, scale=1.0, sub=0):
    hgt = rng.uniform(0.3, 0.55) * scale
    top = Vector((c[0], c[1], c[2] + hgt))
    cone(m, (c[0], c[1], c[2] - 0.03), top, 0.03 * scale, 3, ('f', GREENS[0], None), ('f', GREENS[1], None))
    col = FLOWERS[rng.randrange(len(FLOWERS))]
    r = rng.uniform(0.13, 0.2) * scale
    blob(m, top, (r, r, r * 0.6), ('f', col, None), sub=sub)
    blob(m, top + Vector((0, 0, r * 0.35)), (r * 0.4, r * 0.4, r * 0.3), ('f', h("ffb400"), None), sub=0)

def decorate(m, rng, lod, n_moss=5, n_tuft=7, n_flower=5, zmax=0.55, spacing=1.8):
    """Moss blobs, grass tufts and flowers where the bone meets the ground."""
    cand = [i for i, v in enumerate(m.v) if m.tag[i][0] == 'b' and -0.7 < v.z < zmax]
    if not cand:
        return
    cx = sum(m.v[i].x for i in cand) / len(cand); cy = sum(m.v[i].y for i in cand) / len(cand)
    rng.shuffle(cand)
    chosen = []
    for i in cand:
        p = m.v[i]
        if all((p - q).xy.length > spacing for q in chosen):
            chosen.append(p)
    chosen = chosen[:max(n_moss, n_tuft)]
    sub = 1 if lod == 0 else 0
    for k, p in enumerate(chosen):
        d = Vector((p.x - cx, p.y - cy, 0))
        d = d.normalized() if d.length > 1e-3 else Vector((1, 0, 0))
        if k < n_moss:
            r = rng.uniform(0.7, 1.25)
            blob(m, (p.x + d.x * 0.5, p.y + d.y * 0.5, 0.05), (r, r * rng.uniform(0.8, 1.2), rng.uniform(0.32, 0.5)),
                 ('f', mix(MOSS, MOSSL, rng.uniform(0.0, 0.7)), None), sub=sub, rng=rng, jit=0.12, rot_z=rng.uniform(0, 3))
        if lod == 0:
            side = Vector((-d.y, d.x, 0))
            if k < n_tuft:
                q = p + d * rng.uniform(0.9, 1.8) + side * rng.uniform(-0.8, 0.8)
                tuft(m, rng, (q.x, q.y, 0.0), rng.uniform(0.9, 1.4))
            if k < n_flower:
                for _ in range(2 if k % 2 == 0 else 1):
                    q = p + d * rng.uniform(0.6, 1.6) + side * rng.uniform(-1.0, 1.0)
                    flower(m, rng, (q.x, q.y, 0.0), rng.uniform(0.9, 1.5))


# ----------------------------------------------------------------- pieces
def Q(lod, hi, lo):
    return hi if lod == 0 else lo


def rib(lod, broken=False, seed=1):
    rng = random.Random(seed)
    m = Mesh()
    if not broken:
        Ry, Rx, th_end, lean, W0 = 16.6, 8.6, math.radians(100), 1.4, 0.74
    else:
        Ry, Rx, th_end, lean, W0 = 12.6, 7.0, 0.78, 0.9, 0.7
    n = Q(lod, 36, 13)
    pts = [Vector((0, 0, -1.4))]
    for i in range(n + 1):
        t = i / n
        th = th_end * t
        pts.append(Vector((Rx * (1 - math.cos(th)), lean * t * t, Ry * math.sin(th))))
    nseg = Q(lod, 14, 8)
    sd = seed

    def prof(t, a, c):
        # t is over the whole path incl. lead-in; remap so ground point is ~0
        tt = max(0.0, (t * (n + 1) - 1) / n)
        end = 0.34 if broken else 0.13
        W = W0 * (end + (1 - end) * (1 - tt) ** 1.05)
        flare = 1 + 0.5 * math.exp(-max(c.z, 0) / 1.4)
        lump = 1 + 0.07 * fbm_r(Vector((c.x * 0.5 + math.cos(a) * 0.9, c.y * 0.5 + math.sin(a) * 0.9, c.z * 0.5)), sd)
        lump *= 1 + 0.045 * math.sin(tt * 26 + a)
        w = W * flare * lump
        return w * 0.8, w * 1.05

    if not broken:
        sweep(m, pts, prof, nseg, "fan", "point", ref=(0, 1, 0), ext1=0.5)
    else:
        jag = [rng.uniform(0.0, 0.45) for _ in range(nseg)]
        jag[2] = 1.0; jag[nseg // 2 + 1] = 0.85
        sweep(m, pts, prof, nseg, "fan", "jag", ref=(0, 1, 0), jag=jag)
        # fallen tip fragment lying beside the base
        cp = [Vector((2.6 + 3.4 * i / 8, 3.4 + 0.7 * math.sin(i / 8 * 2.0), 0.42 + 0.06 * i / 8)) for i in range(9)]
        cp = cp if lod == 0 else cp[::2] + ([cp[-1]] if len(cp[::2]) * 2 - 1 < len(cp) else [])
        def prof2(t, a, c):
            w = 0.48 * (1.0 - 0.78 * t) * (1 + 0.05 * math.sin(a * 2 + t * 5))
            return w * 0.8, w
        jg = [rng.uniform(0.0, 0.3) for _ in range(nseg)]
        sweep(m, cp[::-1], prof2, nseg, "point", "jag", ref=(0, 0, 1), ext0=0.35, jag=jg)
    decorate(m, rng, lod, n_moss=Q(lod, 5, 3), n_tuft=Q(lod, 7, 0), n_flower=Q(lod, 5, 0))
    return m, 2.4 if not broken else 2.0, seed


def spine(lod, seed=5):
    rng = random.Random(seed)
    m = Mesh()
    nseg = Q(lod, 14, 8)
    # vertebral body (hourglass), axis along x
    nb = Q(lod, 11, 5)
    bp = [Vector((-1.35 + 2.7 * i / (nb - 1), 0, 0.15)) for i in range(nb)]
    def pb(t, a, c):
        e = abs(t - 0.5) * 2
        k = 0.78 + 0.22 * e * e + 0.05 * math.sin(t * 18 + a * 2)
        lump = 1 + 0.06 * fbm_r(c * 0.7 + Vector((math.cos(a), math.sin(a), 0)), seed)
        return 1.05 * k * lump, 1.5 * k * lump
    sweep(m, bp, pb, nseg, "dome", "dome", ref=(0, 0, 1), ext0=0.3, ext1=0.3)
    # neural arch shoulder
    blob(m, (0.0, 0.0, 1.05), (1.2, 0.85, 0.65), ('b', 0, 0), sub=Q(lod, 1, 0), rng=rng, jit=0.08)
    # dorsal spike, leaning back (-x)
    ns = Q(lod, 12, 5)
    sp = []
    for i in range(ns):
        t = i / (ns - 1)
        sp.append(Vector((-0.2 - 1.2 * t ** 1.6, 0, 1.0 + 4.0 * t)))
    def ps(t, a, c):
        w = (0.62 * (1 - t) ** 0.85 + 0.05) * (1 + 0.06 * math.sin(t * 20))
        return w * 1.25, w * 0.55
    sweep(m, sp, ps, Q(lod, 10, 6), "fan", "point", ref=(0, 1, 0), ext1=0.4)
    # transverse processes
    for side in (1, -1):
        npr = Q(lod, 8, 4)
        tp = [Vector((0.15 + 0.5 * (i / (npr - 1)) ** 2, side * (1.2 + 1.05 * i / (npr - 1)), 0.3 + 0.9 * (i / (npr - 1)) ** 1.5)) for i in range(npr)]
        def pt(t, a, c):
            w = 0.5 * (1 - t) ** 0.9 + 0.09
            return w * 0.7, w
        sweep(m, tp, pt, Q(lod, 8, 6), "fan", "point", ref=(0, 0, 1), ext1=0.3)
    # ribs stumps forward
    decorate(m, rng, lod, n_moss=Q(lod, 5, 3), n_tuft=Q(lod, 7, 0), n_flower=Q(lod, 5, 0), zmax=0.6)
    return m, 1.6, seed


def horn_path(base, side, L, beta_end, rise, n):
    pts = []; p = Vector(base); ds = L / n
    for i in range(n + 1):
        s = i / n
        pts.append(p.copy())
        beta = beta_end * s ** 1.1
        d = Vector((math.sin(beta), side * math.cos(beta), rise * (1 - 0.45 * s))).normalized()
        p = p + d * ds
    return pts


def skull(lod, seed=9):
    rng = random.Random(seed)
    m = Mesh()
    ra, rb, rc = 3.2, 2.3, 2.2
    nu = Q(lod, 30, 12); nv = Q(lod, 20, 8)
    sockets = [Vector((1.95, s * 1.85, 0.35)) for s in (1, -1)]
    verts, tags, faces = [], [], []
    for j in range(nv + 1):
        ph = math.pi * j / nv
        for i in range(nu if 0 < j < nv else 1):
            th = 2 * math.pi * i / nu
            p = Vector((ra * math.cos(ph), rb * math.sin(ph) * math.cos(th), rc * math.sin(ph) * math.sin(th)))
            # long axis is x (poles at +-x); crest along top
            nrm = Vector((p.x / ra ** 2, p.y / rb ** 2, p.z / rc ** 2)).normalized()
            crest = 0.42 * math.exp(-(p.y / 0.55) ** 2) * sstep(-3.2, 0.5, p.x) * (1 if p.z > 0 else 0)
            p += Vector((0, 0, crest))
            p += nrm * 0.07 * fbm_r(p * 0.8, seed)
            dark = 0.0
            for sk in sockets:
                d = (p - sk).length
                fall = 1 - sstep(0.25, 0.95, d)
                p -= nrm * 0.65 * fall
                dark = max(dark, sstep(0.12, 0.7, fall))
            verts.append(p); tags.append(('b', 0.0, dark))
    def vid(j, i):
        if j == 0: return 0
        if j == nv: return len(verts) - 1
        return 1 + (j - 1) * nu + (i % nu)
    for j in range(nv):
        for i in range(nu):
            a = vid(j, i); b = vid(j, i + 1); c = vid(j + 1, i + 1); d = vid(j + 1, i)
            if j == 0: faces.append((a, c, d))
            elif j == nv - 1: faces.append((a, b, d))
            else: faces.append((a, b, c, d))
    m.add(verts, tags, faces)
    # snout
    ns = Q(lod, 13, 6)
    sn = [Vector((1.8 + 4.9 * i / (ns - 1), 0, -0.15 - 0.7 * (i / (ns - 1)) ** 1.3)) for i in range(ns)]
    def psn(t, a, c):
        k = 1 - 0.5 * t ** 1.2
        lump = 1 + 0.05 * fbm_r(c * 0.8 + Vector((math.cos(a), math.sin(a), 0)), seed)
        return 1.35 * k * lump * (1 if math.sin(a) > -0.2 else 0.9), 1.55 * k * lump
    sweep(m, sn, psn, Q(lod, 14, 8), "fan", "dome", ref=(0, 0, 1), ext1=0.35)
    blob(m, (5.5, 0, 0.35), (1.15, 0.85, 0.5), ('b', 0, 0), sub=Q(lod, 1, 0), rng=rng, jit=0.08)
    if lod == 0:
        for s in (1, -1):
            blob(m, (6.6, s * 0.5, -0.45), (0.2, 0.2, 0.28), ('b', 0, 1.0), sub=0)
    # brow ridges
    for s in (1, -1):
        blob(m, (1.9, s * 1.65, 1.38), (1.15, 0.55, 0.42), ('b', 0, 0), sub=Q(lod, 1, 0), rng=rng, jit=0.06)
    # cheek arch
    ca = [Vector((1.0, s_ * 1.72, -0.55 - 0.9 * i / 6.0 * 1.0)) for s_ in (1,) for i in range(1)]
    for s in (1, -1):
        npz = Q(lod, 7, 4)
        z = [Vector((0.9 - 2.4 * i / (npz - 1), s * (1.75 + 0.15 * i / (npz - 1)), -0.7 - 0.8 * i / (npz - 1))) for i in range(npz)]
        def pz(t, a, c):
            w = 0.34 * (1 - 0.3 * t)
            return w, w * 0.8
        sweep(m, z, pz, Q(lod, 8, 5), "dome", "dome", ref=(0, 0, 1), ext0=0.1, ext1=0.1)
    # lower jaw, slightly open
    j0 = len(m.v)
    nj = Q(lod, 13, 6)
    jw = [Vector((-1.4 + 7.2 * i / (nj - 1), 0, -2.05 - 0.15 * math.sin(math.pi * i / (nj - 1)))) for i in range(nj)]
    def pj(t, a, c):
        k = 1 - 0.55 * t ** 1.3
        lump = 1 + 0.05 * fbm_r(c * 0.8 + Vector((math.cos(a), math.sin(a), 0)), seed + 3)
        return 0.62 * k * lump, 1.35 * k * lump
    sweep(m, jw, pj, Q(lod, 12, 8), "dome", "dome", ref=(0, 0, 1), ext0=0.25, ext1=0.3)
    if lod == 0:
        for xx in (2.6, 3.3, 4.0, 4.7, 5.4):
            for s in (1, -1):
                cone(m, (xx, s * 0.85 * (1 - 0.35 * (xx - 2.6) / 3), -1.5), (xx + 0.06, s * 0.85 * (1 - 0.35 * (xx - 2.6) / 3), -1.5 + 0.55), 0.17, 5, ('b', 0, 0), ('b', 0, 0))
    m.transform(Matrix.Rotation(math.radians(11), 4, 'Y') @ Matrix.Translation((0, 0, 0)), j0, len(m.v))
    if lod == 0:
        # upper teeth along the snout underside
        for xx in (3.4, 4.1, 4.8, 5.5):
            for s in (1, -1):
                zb = -0.15 - 0.7 * ((xx - 1.8) / 4.9) ** 1.3 - 0.9 * (1 - 0.5 * ((xx - 1.8) / 4.9) ** 1.2) * 0.95
                cone(m, (xx, s * 0.75, zb + 0.15), (xx + 0.05, s * 0.75, zb - 0.45), 0.17, 5, ('b', 0, 0), ('b', 0, 0))
    # horns
    h0 = len(m.v)
    for s in (1, -1):
        nh = Q(lod, 26, 10)
        hp = horn_path((-0.5, s * 1.55, 1.05), s, 10.0, 2.6, 0.9, nh - 1)
        def ph(t, a, c, s=s):
            w = 0.82 * (1 - t) ** 0.9 + 0.05
            w *= 1 + 0.42 * math.exp(-t * 9) + 0.06 * math.sin(t * 34)
            return w, w * 0.88
        sweep(m, hp, ph, Q(lod, 12, 7), "fan", "point", ref=(0, 0, 1), ext1=0.5, tipfn=lambda t: sstep(0.35, 1.0, t) * 0.85)
    # roll onto its side + bury the underside
    roll = math.radians(50)
    m.transform(Matrix.Rotation(roll, 4, 'X'))
    body_min = min(v.z for i, v in enumerate(m.v) if i < h0)
    m.transform(Matrix.Translation((0, 0, -body_min - 1.2)))
    m.transform(Matrix.Rotation(math.radians(-12), 4, 'Z'))
    decorate(m, rng, lod, n_moss=Q(lod, 8, 4), n_tuft=Q(lod, 9, 0), n_flower=Q(lod, 6, 0), zmax=0.5, spacing=2.4)
    return m, 2.4, seed


def tusk(lod, seed=13):
    rng = random.Random(seed)
    m = Mesh()
    n = Q(lod, 44, 15)
    R, phi = 10.0, 0.82
    pts = [Vector((R * math.sin(phi * i / (n - 1)) - 0.0, 0.5 * math.sin(math.pi * i / (n - 1)) * 0.6, 0.62 + R * (1 - math.cos(phi * i / (n - 1))))) for i in range(n)]
    def prof(t, a, c):
        w = 0.72 * (1 - t) ** 0.85 + 0.04
        w *= 1 + 0.05 * math.sin(t * 46) + 0.05 * math.cos(3 * a + t * 14)
        w *= 1 + 0.06 * fbm_r(c * 0.6 + Vector((math.cos(a), math.sin(a), 0)), seed)
        return w, w * 0.92
    sweep(m, pts, prof, Q(lod, 14, 8), "dome", "point", ref=(0, 1, 0), ext0=0.5, ext1=0.45,
          tipfn=lambda t: sstep(0.55, 1.0, t) * 0.8)
    decorate(m, rng, lod, n_moss=Q(lod, 5, 3), n_tuft=Q(lod, 6, 0), n_flower=Q(lod, 4, 0), zmax=0.5, spacing=2.5)
    return m, 1.0, seed


PIECES = {
    "giant_rib_a": (lambda lod: rib(lod, False, 1), 2.4),
    "giant_rib_b": (lambda lod: rib(lod, True, 2), 2.0),
    "giant_spine_segment": (lambda lod: spine(lod, 5), 1.0),
    "giant_skull": (lambda lod: skull(lod, 9), 2.2),
    "giant_tusk": (lambda lod: tusk(lod, 13), 1.0),
}
BUDGET = {"giant_skull": (6000, 1800)}


# ----------------------------------------------------------------- export
def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete()
    for c in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(c):
            c.remove(d)
    global _MAT
    _MAT = None


def export_obj(ob, path):
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_yup=True,
              export_apply=True, export_draco_mesh_compression_enable=False, export_materials='EXPORT')
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color='MATERIAL')
    except TypeError:
        bpy.ops.export_scene.gltf(**kw)


def do_build():
    info = {}
    for name, (fn, mosscap) in PIECES.items():
        info[name] = {"files": {}, "tris": {}}
        for lod in (0, 1):
            clear_scene()
            m, mc, seed = fn(lod)
            ob = paint_and_build(m, name + "_lod%d" % lod, seed=seed, mosscap=mosscap)
            me = ob.data
            me.calc_loop_triangles()
            tris = len(me.loop_triangles)
            b0, b1 = BUDGET.get(name, (4000, 1200))
            lim = b0 if lod == 0 else b1
            assert tris <= lim, "%s LOD%d has %d tris > %d" % (name, lod, tris, lim)
            fname = "%s_lod%d.glb" % (name, lod)
            export_obj(ob, os.path.join(OUT, fname))
            info[name]["files"]["lod%d" % lod] = fname
            info[name]["tris"]["lod%d" % lod] = tris
            if lod == 0:
                vs = [ob.matrix_world @ v.co for v in me.vertices]
                mn = [min(v[i] for v in vs) for i in range(3)]
                mx = [max(v[i] for v in vs) for i in range(3)]
                # Blender (x,y,z) -> Godot (x, z, -y)
                info[name]["size_m"] = [round(mx[0] - mn[0], 2), round(mx[2] - mn[2], 2), round(mx[1] - mn[1], 2)]
                info[name]["bbox_min_m"] = [round(mn[0], 2), round(mn[2], 2), round(-mx[1], 2)]
                info[name]["bbox_max_m"] = [round(mx[0], 2), round(mx[2], 2), round(-mn[1], 2)]
            print("BUILT", fname, tris)
    layout = make_layout()
    doc = {
        "landmark": "The Wyrm's Ribs",
        "note": "Original procedural work (make_giant_bones.py). Origin at ground contact, +Y up, metres. "
                "Vertex-colour painted, one material per piece. Layout = [piece, x, z, yaw_deg, scale], "
                "relative to landmark centre, +z south, skeleton ~60 m along x, skull at +x. "
                "Yaw is Godot rotation.y in degrees: ribs arch toward local +x, so yaw=90 arches toward -z (north), yaw=-90 toward +z.",
        "pieces": info,
        "layout": layout,
    }
    with open(os.path.join(OUT, "giant_bones.json"), "w") as f:
        json.dump(doc, f, indent=2)


def make_layout():
    L = []
    # skull at +x end, snout pointing +x
    L.append(["giant_skull", 25.0, 0.0, 0, 1.0])
    # tusks in front of / beside the skull
    L.append(["giant_tusk", 22.0, 9.5, -25, 1.0])
    L.append(["giant_tusk", 29.0, -10.5, 170, 0.9])
    # rib cage: 4 pairs, arching over the spine from both sides
    rows = [
        (-6.0, 0.95, "giant_rib_a", "giant_rib_a"),
        (-1.0, 1.1, "giant_rib_a", "giant_rib_a"),
        (4.5, 1.05, "giant_rib_a", "giant_rib_a"),
        (10.0, 0.9, "giant_rib_b", "giant_rib_a"),
    ]
    for x, s, ps, pn in rows:
        L.append([ps, x, 9.0 * s, 90, s])
        L.append([pn, x + 1.4, -9.0 * s, -90, s * 0.97])
    # spine: vertebrae from the tail (small) toward the skull
    xs = [-27, -23.5, -20, -16.5, -13, -9.5, -6, -2.5, 1, 4.5, 8, 11.5, 15, 18.5]
    for i, x in enumerate(xs):
        s = 0.55 + 0.6 * i / (len(xs) - 1)
        L.append(["giant_spine_segment", x, round(0.35 * math.sin(i * 1.7), 2), round(4 * math.sin(i * 2.3), 1), round(s, 2)])
    return [[p, round(x, 2), round(z, 2), yaw, round(s, 2)] for p, x, z, yaw, s in L]


# ----------------------------------------------------------------- rendering
def setup_render(w, h_, samples=48):
    sc = bpy.context.scene
    for eng in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT', 'CYCLES'):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    print("ENGINE", sc.render.engine)
    sc.render.resolution_x = w; sc.render.resolution_y = h_
    sc.render.resolution_percentage = 100
    if sc.render.engine == 'CYCLES':
        sc.cycles.samples = 24; sc.cycles.device = 'CPU'
        try: sc.cycles.use_denoising = True
        except Exception: pass
    else:
        try: sc.eevee.taa_render_samples = samples
        except Exception: pass
        for a, v in (("use_gtao", True), ("use_raytracing", True), ("use_shadows", True)):
            try: setattr(sc.eevee, a, v)
            except Exception: pass
    for vt in ('Khronos PBR Neutral', 'Standard'):
        try:
            sc.view_settings.view_transform = vt
            break
        except TypeError:
            continue
    sc.view_settings.look = 'None'
    sc.render.image_settings.file_format = 'PNG'


def setup_world():
    w = bpy.data.worlds.new("Sky"); bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    for n_ in list(nt.nodes): nt.nodes.remove(n_)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[0].color = (0.75, 0.88, 1.0, 1)
    ramp.color_ramp.elements[1].position = 0.85; ramp.color_ramp.elements[1].color = (0.28, 0.55, 0.95, 1)
    nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    pass
    bg.inputs["Strength"].default_value = 1.15
    bg.inputs["Color"].default_value = (0.42, 0.68, 1.0, 1)
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def add_sun(direction=(0.55, -0.45, 0.8), strength=4.2):
    ld = bpy.data.lights.new("Sun", 'SUN')
    ld.energy = strength; ld.color = (1.0, 0.86, 0.66); ld.angle = math.radians(4)
    ob = bpy.data.objects.new("Sun", ld)
    bpy.context.scene.collection.objects.link(ob)
    d = Vector(direction).normalized()
    ob.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    return ob


def make_ground_mat(color):
    mat = bpy.data.materials.new("Ground")
    mat.use_nodes = True
    bs = mat.node_tree.nodes["Principled BSDF"]
    bs.inputs["Base Color"].default_value = (s2l(color[0]), s2l(color[1]), s2l(color[2]), 1)
    bs.inputs["Roughness"].default_value = 1.0
    return mat


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def world_bbox(objs):
    pts = []
    for o in objs:
        if o.type == 'MESH':
            pts += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx


def place_camera(center, radius, dirv, lens=45):
    cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = lens
    cam = bpy.data.objects.new("Cam", cam_d)
    bpy.context.scene.collection.objects.link(cam)
    fov = 2 * math.atan(18.0 / lens)
    dist = radius / math.tan(fov / 2) * 1.05
    cam.location = center + Vector(dirv).normalized() * dist
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    bpy.context.scene.camera = cam
    cam_d.clip_end = 5000
    return cam


def new_scene_clean():
    global _MAT
    _MAT = None
    bpy.ops.wm.read_factory_settings(use_empty=True)


def do_render():
    import numpy as np
    tile = 560
    views = [(1.0, -1.15, 0.5), (-0.95, -0.9, 0.45)]
    names = list(PIECES.keys())
    tiles = {}
    for vi, dv in enumerate(views):
        for name in names:
            new_scene_clean()
            setup_render(tile, tile, 32); setup_world(); add_sun()
            objs = import_glb(os.path.join(OUT, name + "_lod0.glb"))
            mn, mx = world_bbox(objs)
            c = (mn + mx) / 2; c.z = max(c.z, (mn.z + mx.z) / 2)
            rad = (mx - mn).length / 2
            gr = max(mx.x - mn.x, mx.y - mn.y) * 0.9
            bpy.ops.mesh.primitive_circle_add(vertices=64, radius=gr, fill_type='NGON', location=(c.x, c.y, 0))
            g = bpy.context.active_object; g.data.materials.append(make_ground_mat(h("7a9c44")))
            place_camera(c, rad * 0.98, dv)
            p = os.path.join(PREV, "_tmp_%s_%d.png" % (name, vi))
            bpy.context.scene.render.filepath = p
            bpy.ops.render.render(write_still=True)
            tiles[(name, vi)] = p
    # stitch
    def load(p):
        im = bpy.data.images.load(p); w, h_ = im.size
        a = np.empty(w * h_ * 4, dtype=np.float32); im.pixels.foreach_get(a)
        return a.reshape(h_, w, 4)
    rows = []
    for vi in range(len(views)):
        rows.append(np.concatenate([load(tiles[(n, vi)]) for n in names], axis=1))
    sheet = np.concatenate(rows[::-1], axis=0)  # image rows bottom-up: last view first
    H, W = sheet.shape[:2]
    im = bpy.data.images.new("sheet", W, H, alpha=False)
    im.pixels.foreach_set(sheet.ravel()); im.filepath_raw = os.path.join(PREV, "giant_bones_sheet.png")
    im.file_format = 'PNG'; im.save()
    for p in tiles.values():
        try: os.remove(p)
        except OSError: pass
    render_ridge()


def mound_and_dressing():
    rng = random.Random(77)
    # mound
    nx, ny = 100, 44
    X0, X1, Y0, Y1 = -80, 80, -50, 50
    bm = bmesh.new()
    vg = []
    for j in range(ny + 1):
        for i in range(nx + 1):
            x = X0 + (X1 - X0) * i / nx; y = Y0 + (Y1 - Y0) * j / ny
            r = math.hypot(x / 52.0, y / 18.0)
            z = -4.5 * sstep(0.72, 1.35, r)
            z += 0.12 * noise.noise(Vector((x * 0.15, y * 0.15, 3))) * sstep(0.6, 1.0, r) + 0.25 * sstep(1.0, 1.5, r) * noise.noise(Vector((x * 0.08, y * 0.08, 9)))
            vg.append(bm.verts.new((x, y, z)))
    for j in range(ny):
        for i in range(nx):
            a = vg[j * (nx + 1) + i]; b = vg[j * (nx + 1) + i + 1]
            c = vg[(j + 1) * (nx + 1) + i + 1]; d = vg[(j + 1) * (nx + 1) + i]
            bm.faces.new((a, b, c, d))
    for f in bm.faces: f.smooth = True
    me = bpy.data.meshes.new("Mound"); bm.to_mesh(me); bm.free()
    ca = me.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    for i, v in enumerate(me.vertices):
        r = math.hypot(v.co.x / 52.0, v.co.y / 18.0)
        n1 = noise.noise(Vector((v.co.x * 0.2, v.co.y * 0.2, 0)))
        col = mix(h("74b83a"), h("5a9a2c"), 0.4 + 0.5 * n1)
        col = mix(col, h("a6cf48"), 0.35 * sstep(0.2, 0.7, noise.noise(Vector((v.co.x * 0.11, v.co.y * 0.11, 5)))))
        col = mix(col, h("4a8228"), sstep(0.8, 1.3, r) * 0.7)
        ca.data[i].color = (s2l(col[0]), s2l(col[1]), s2l(col[2]), 1)
    me.materials.append(bone_material())
    mo = bpy.data.objects.new("Mound", me); bpy.context.scene.collection.objects.link(mo)
    # far plane
    bpy.ops.mesh.primitive_plane_add(size=6000, location=(0, 0, -4.6))
    fp = bpy.context.active_object; fp.data.materials.append(make_ground_mat(h("6aa838")))
    # grass tufts + flowers across the plateau
    m = Mesh()
    for _ in range(420):
        x = rng.uniform(-44, 44); y = rng.uniform(-14.5, 14.5)
        if math.hypot(x / 52, y / 18) > 0.85: continue
        tuft(m, rng, (x, y, 0.0), rng.uniform(1.0, 2.0), blades=4)
    for _ in range(110):
        x = rng.uniform(-44, 44); y = rng.uniform(-14.5, 14.5)
        if math.hypot(x / 52, y / 18) > 0.85: continue
        flower(m, rng, (x, y, 0.0), rng.uniform(1.6, 2.6))
    bm = bmesh.new()
    vs = [bm.verts.new(p) for p in m.v]
    for f in m.f:
        try: bm.faces.new([vs[i] for i in f])
        except ValueError: pass
    me2 = bpy.data.meshes.new("Dressing"); bm.to_mesh(me2); bm.free()
    ca = me2.color_attributes.new("Col", 'FLOAT_COLOR', 'POINT')
    for i, t in enumerate(m.tag):
        c = t[1]; ca.data[i].color = (s2l(c[0]), s2l(c[1]), s2l(c[2]), 1)
    me2.materials.append(bone_material())
    do = bpy.data.objects.new("Dressing", me2); bpy.context.scene.collection.objects.link(do)


def render_ridge():
    new_scene_clean()
    setup_render(1920, 1080, 32); setup_world()
    add_sun((0.45, -0.55, 0.75), 4.4)
    mound_and_dressing()
    with open(os.path.join(OUT, "giant_bones.json")) as f:
        layout = json.load(f)["layout"]
    for k, (piece, x, z, yaw, s) in enumerate(layout):
        objs = import_glb(os.path.join(OUT, piece + "_lod0.glb"))
        em = bpy.data.objects.new("inst%d" % k, None)
        bpy.context.scene.collection.objects.link(em)
        em.location = (x, -z, 0); em.rotation_euler = (0, 0, math.radians(yaw)); em.scale = (s, s, s)
        for o in objs:
            if o.parent is None:
                o.parent = em
    center = Vector((3, 0, 6))
    def shot(path, loc, look, lens):
        cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = lens; cam_d.clip_end = 5000
        cam = bpy.data.objects.new("Cam", cam_d); bpy.context.scene.collection.objects.link(cam)
        cam.location = loc
        cam.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
        bpy.context.scene.camera = cam
        bpy.context.scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
    shot(os.path.join(PREV, "giant_bones_ridge.png"), (52, -62, 24), (2, 0, 7), 34)
    shot(os.path.join(PREV, "giant_bones_ridge_skull.png"), (60, -32, 9), (18, 0, 5.5), 30)


def main():
    argv = sys.argv
    mode = argv[argv.index("--") + 1] if "--" in argv else "build"
    if mode in ("build", "all"):
        do_build()
    if mode in ("render", "all"):
        do_render()


main()
