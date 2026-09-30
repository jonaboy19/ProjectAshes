# Horse tack: procedural skinned tack pieces (saddle, bridle, reins, saddlebags, cart harness, barding) + market cart,
# all sharing ONE hand-painted 512 px atlas (horse_tack_atlas.png) and one material "horse_tack".
#   Blender 5.2 headless; driven by horse_export.py (build_all(arm, lod0)).
# Geometry hugs Horse_LOD0 (rest pose): strap vertices are snapped to the body surface (BVH, hair excluded) + offset.
import bpy, bmesh, os, sys, math
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hx_common as X
from hx_common import V

# ------------------------------------------------------------------ atlas layout (4 x 4 cells of 128 px, emblem = 2 x 2 cells)
KEYS = ["RED", "GOLD", "LEATHER", "DARK", "STEEL", "BRASS", "WOOD", "WOODD", "CREAM", "IRON", "EMBLEM", "PAINT", "STRAW"]
K = {n: i for i, n in enumerate(KEYS)}
from hx_atlas import CELL
_UNUSED = {
    "EMBLEM": (0, 2, 2, 2), "RED": (2, 3, 1, 1), "GOLD": (3, 3, 1, 1), "LEATHER": (2, 2, 1, 1), "DARK": (3, 2, 1, 1),
    "STEEL": (0, 1, 1, 1), "BRASS": (1, 1, 1, 1), "WOOD": (2, 1, 1, 1), "WOODD": (3, 1, 1, 1), "CREAM": (0, 0, 1, 1),
    "IRON": (1, 0, 1, 1), "PAINT": (2, 0, 1, 1), "STRAW": (3, 0, 1, 1)}

ARM = None
BODY = None
_BV = {}


# ------------------------------------------------------------------ body access
def setup(arm, lod0):
    """BVH of the body without hair faces (rest pose) + per-vertex weight cache."""
    global ARM, BODY
    ARM, BODY = arm, lod0
    me = lod0.data
    reg = me.attributes.get("region")
    verts = [v.co.copy() for v in me.vertices]
    polys, pmap = [], []
    for p in me.polygons:
        if reg is not None and reg.data[p.index].value == 7:
            continue
        polys.append(tuple(p.vertices))
        pmap.append(p.index)
    _BV["bvh"] = BVHTree.FromPolygons(verts, polys)
    _BV["pmap"] = pmap
    _BV["me"] = me
    _BV["gn"] = [g.name for g in lod0.vertex_groups]
    _BV["w"] = {}
    _BV["bones"] = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in arm.data.bones}
    X.log("tack body BVH", len(polys), "faces")


def bvh():
    return _BV["bvh"]


def near(p, maxd=0.08):
    """(location, normal, dist, poly index) on the body surface"""
    r = bvh().find_nearest(p, maxd)
    if r[0] is None:
        return None
    return r[0], r[1], r[3], _BV["pmap"][r[2]]


def snap(p, off, maxd=0.09):
    r = near(p, maxd)
    if r is None:
        return p.copy(), None
    loc, n, d, pi = r
    return loc + n * off, n


def ray(o, d):
    h = bvh().ray_cast(o, d)
    return h[0], h[1]


def env_x(y, z, side=1.0):
    """outermost body surface x at (y, z) seen from the side (+x side for side=1), None if empty"""
    h, n = ray(V(1.5 * side, y, z), V(-side, 0, 0))
    return None if h is None else h.x


def top_z(x, y):
    h, n = ray(V(x, y, 3.0), V(0, 0, -1))
    return None if h is None else h.z


def vweights(vi):
    if vi not in _BV["w"]:
        _BV["w"][vi] = {_BV["gn"][g.group]: g.weight for g in _BV["me"].vertices[vi].groups}
    return _BV["w"][vi]


def surface_weights(p, allowed=None):
    """body skin weights at the nearest surface point (inverse distance over the face corners)"""
    r = near(p, 0.5)
    if r is None:
        return {}
    loc, n, d, pi = r
    acc = {}
    tot = 0.0
    for vi in _BV["me"].polygons[pi].vertices:
        w_ = 1.0 / (1e-4 + (loc - _BV["me"].vertices[vi].co).length) ** 2
        tot += w_
        for b, w in vweights(vi).items():
            acc[b] = acc.get(b, 0.0) + w * w_
    acc = {b: w / tot for b, w in acc.items()}
    if allowed is not None:
        acc = {b: w for b, w in acc.items() if b in allowed}
    return acc


def bone_dist_weights(p, bones, top=3, power=2.0):
    ws = {}
    for b in bones:
        h, t = _BV["bones"][b]
        seg = t - h
        u = max(0.0, min(1.0, (p - h).dot(seg) / max(seg.length_squared, 1e-9)))
        d = (h + seg * u - p).length
        ws[b] = 1.0 / (d + 0.03) ** power
    keep = sorted(ws.items(), key=lambda kv: -kv[1])[:top]
    s = sum(w for _, w in keep)
    return {b: w / s for b, w in keep}


# ------------------------------------------------------------------ mesh builder
class M:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.fk = self.bm.faces.layers.int.new("key")
        self.emb = None                      # function co -> (s, t) for EMBLEM faces
        self.tags = []                       # per-vertex tag (creation order), passed to the weight function
        self.tag = "body"
        self.wfun = None                     # (co, tag) -> {bone: w}, evaluated at finish

    def v(self, p):
        self.tags.append(self.tag)
        return self.bm.verts.new(p)

    def face(self, vs, key, expect=None):
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f[self.fk] = K[key] if isinstance(key, str) else key
        if expect is not None:
            f.normal_update()
            if f.normal.dot(expect) < 0:
                f.normal_flip()
        return f

    def loft(self, rings, key, closed=True, expect_out=None, keyf=None):
        """rings: list of lists of verts (same length); quads between consecutive rings"""
        n = len(rings[0])
        fs = []
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            for j in range(n if closed else n - 1):
                k = (j + 1) % n
                kk = keyf(i, j) if keyf else key
                fs.append(self.face((a[j], a[k], b[k], b[j]), kk))
        return fs

    def cap(self, ring, key, flip=False):
        vs = list(ring)[::-1] if flip else list(ring)
        return self.face(vs, key)

    def finish(self, ob_name, wfun=None):
        bm = self.bm
        self.wfun = wfun or self.wfun
        bm.verts.index_update()
        bm.normal_update()
        me = bpy.data.meshes.new(ob_name)
        uvl = bm.loops.layers.uv.new("UVMap")
        for f in bm.faces:
            key = KEYS[f[self.fk]]
            for l in f.loops:
                l[uvl].uv = atlas_uv(key, l.vert.co, l.vert.normal, self.emb)
        bm.to_mesh(me)
        # weights
        ob = bpy.data.objects.new(ob_name, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.parent = ARM
        ob.matrix_parent_inverse = Matrix.Identity(4)
        ob.matrix_world = Matrix.Identity(4)
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = ARM
        if self.wfun is not None:
            names = set()
            wl = []
            for v in me.vertices:
                d = self.wfun(v.co, self.tags[v.index])
                wl.append(d)
                names.update(d)
            for n in sorted(names):
                ob.vertex_groups.new(name=n)
            for v, d in zip(me.vertices, wl):
                tot = sum(d.values())
                for b, w in d.items():
                    if w > 1e-4:
                        ob.vertex_groups[b].add([v.index], w / tot, "REPLACE")
            X.limit_normalize(ob, 4)
        bm.free()
        for p in me.polygons:
            p.use_smooth = True
        return ob


def tri_wave(t):
    return abs(((t % 2.0) + 2.0) % 2.0 - 1.0) * 2 - 1


def atlas_uv(key, co, nrm, emb):
    cx, cy, cw, ch = CELL[key]
    u0, v0, w, h = cx * 0.25, cy * 0.25, cw * 0.25, ch * 0.25
    if key == "EMBLEM" and emb is not None:
        s, t = emb(co)
        s = min(0.96, max(0.04, s)); t = min(0.96, max(0.04, t))
        return (u0 + s * w, v0 + t * h)
    k = min(1.0, max(0.0, 0.5 + 0.5 * nrm.z))
    tw = tri_wave(co.x * 5.3 + co.y * 3.7 + co.z * 4.1)
    u = u0 + w * (0.5 + 0.16 * tw)
    v = v0 + h * (0.10 + 0.80 * k)
    if key == "EMBLEM":
        return (u0 + 0.5 * w, v0 + 0.5 * h)
    return (u, v)


# ------------------------------------------------------------------ strap / shapes
def tangents(pts, closed=False):
    n = len(pts)
    out = []
    for i in range(n):
        a = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        b = pts[(i + 1) % n] if closed else pts[min(i + 1, n - 1)]
        t = b - a
        out.append(t.normalized() if t.length > 1e-9 else V(0, 1, 0))
    return out


def strap(m, pts, width, thick, key, closed=False, off=0.007, up=None, solid=True, snapto=True, keyf=None, maxd=0.09):
    """A flat strap along pts. snapto: every cross-section vertex is projected onto the body and lifted by `off`
    (hugs the surface); otherwise `up` (Vector or fn(i, p)) gives the outward normal. Returns the list of rings."""
    T = tangents(pts, closed)
    rings = []
    for i, p in enumerate(pts):
        if snapto:
            c, n = snap(p, off, maxd)
            N = n if n is not None else (up(i, p) if callable(up) else (up or V(0, 0, 1)))
        else:
            N = up(i, p) if callable(up) else (up or V(0, 0, 1))
            N = N.normalized()
        B = T[i].cross(N)
        if B.length < 1e-6:
            B = T[i].orthogonal()
        B.normalize()
        N = B.cross(T[i]).normalized() if not snapto else N
        row = []
        for s in (-1, 1):
            q = p + B * (s * width * 0.5)
            if snapto:
                q, n2 = snap(q, off, maxd)
                Nq = n2 if n2 is not None else N
            else:
                Nq = N
            row.append((q, Nq))
        (q0, n0), (q1, n1) = row
        ring = [m.v(q1 + n1 * thick), m.v(q0 + n0 * thick), m.v(q0), m.v(q1)] if solid else \
               [m.v(q1 + n1 * thick), m.v(q0 + n0 * thick)]
        rings.append(ring)
    nseg = len(rings) if closed else len(rings) - 1
    for i in range(nseg):
        a, b = rings[i], rings[(i + 1) % len(rings)]
        kk = keyf(i) if keyf else key
        if solid:
            # outer, side (q0), inner, side (q1)
            m.face((a[0], b[0], b[1], a[1]), kk)
            m.face((a[1], b[1], b[2], a[2]), kk)
            m.face((a[2], b[2], b[3], a[3]), kk)
            m.face((a[3], b[3], b[0], a[0]), kk)
        else:
            m.face((a[0], b[0], b[1], a[1]), kk)
    return rings


def tube(m, pts, radius, key, sides=6, closed=False, up=None, cap=True, r_fn=None):
    T = tangents(pts, closed)
    rings = []
    for i, p in enumerate(pts):
        t = T[i]
        ref = up(i, p) if callable(up) else (up or V(0, 0, 1))
        b = t.cross(ref)
        if b.length < 1e-6:
            b = t.orthogonal()
        b.normalize()
        n = b.cross(t).normalized()
        r = r_fn(i) if r_fn else radius
        rings.append([m.v(p + (n * math.cos(2 * math.pi * k / sides) + b * math.sin(2 * math.pi * k / sides)) * r) for k in range(sides)])
    m.loft(rings, key, closed=True)
    if closed:
        m.loft([rings[-1], rings[0]], key, closed=True)
    elif cap:
        m.face(rings[0][::-1], key)
        m.face(rings[-1], key)
    return rings


def box(m, c, size, key, axes=None, keyf=None):
    """oriented box: axes = (ex, ey, ez) unit vectors (default world)"""
    ex, ey, ez = axes or (V(1, 0, 0), V(0, 1, 0), V(0, 0, 1))
    sx, sy, sz = size
    vs = {}
    for i in (-1, 1):
        for j in (-1, 1):
            for k in (-1, 1):
                vs[(i, j, k)] = m.v(c + ex * (i * sx / 2) + ey * (j * sy / 2) + ez * (k * sz / 2))
    q = lambda *ks: [vs[k] for k in ks]
    for face in ((q((1, -1, -1), (1, 1, -1), (1, 1, 1), (1, -1, 1))), (q((-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1))),
                 (q((-1, 1, -1), (-1, 1, 1), (1, 1, 1), (1, 1, -1))), (q((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1))),
                 (q((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))), (q((-1, -1, -1), (-1, 1, -1), (1, 1, -1), (1, -1, -1)))):
        m.face(face, keyf or key)


def torus(m, c, ax_u, ax_v, ax_n, R_u, R_v, r, key, seg=12, sides=5, phase=0.0):
    """oval ring in the (ax_u, ax_v) plane, radii R_u, R_v, tube radius r"""
    pts = [c + ax_u * (R_u * math.cos(2 * math.pi * i / seg + phase)) + ax_v * (R_v * math.sin(2 * math.pi * i / seg + phase)) for i in range(seg)]
    return tube(m, pts, r, key, sides=sides, closed=True, up=lambda i, p: ax_n)


def sphere(m, c, rx, ry, rz, key, nu=8, nv=5):
    rings = []
    top = m.v(c + V(0, 0, rz))
    bot = m.v(c + V(0, 0, -rz))
    for j in range(1, nv):
        th = math.pi * j / nv
        rings.append([m.v(c + V(rx * math.sin(th) * math.cos(2 * math.pi * i / nu), ry * math.sin(th) * math.sin(2 * math.pi * i / nu), rz * math.cos(th))) for i in range(nu)])
    for i in range(nu):
        m.face((top, rings[0][(i + 1) % nu], rings[0][i]), key)
        m.face((bot, rings[-1][i], rings[-1][(i + 1) % nu]), key)
    m.loft(rings, key, closed=True)
    return rings


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ skin helpers
def w_rigid(bone):
    return lambda co, tag: {bone: 1.0}


def w_surface(allowed, fallback=None):
    def f(co, tag):
        d = surface_weights(co, allowed)
        if not d:
            d = bone_dist_weights(co, fallback or list(allowed))
        return d
    return f


def w_bones(bones, top=3):
    return lambda co, tag: bone_dist_weights(co, bones, top)


# ------------------------------------------------------------------ SADDLE
def cross_section_rows(ys, zfun_hem, ncol, top_bias=2.0, off=0.012):
    """Cloth-like envelope surface over the barrel: for every y a polyline from the left hem over the back to the right
    hem (2*ncol+1 points), x = outermost body surface at that height + off. Returns rows of Vectors."""
    rows = []
    for y in ys:
        zt = top_z(0.0, y) or 1.45
        zh = zfun_hem(y, zt)
        pts = []
        # z levels clustered near the top, from hem up (left side +x) then down (right side -x)
        lv = [zt - (zt - zh) * ((1.0 - i / ncol) ** top_bias) for i in range(ncol + 1)]   # i=0 top ... ncol hem
        left = []
        for z in lv:                            # hem -> top (left side, +x)
            x = env_x(y, min(z, zt - 0.004), 1.0)
            left.append(V((x if x is not None else 0.0) + off, y, z))
        right = []
        for z in lv[::-1]:                      # top -> hem (right side, -x)
            x = env_x(y, min(z, zt - 0.004), -1.0)
            right.append(V((x if x is not None else 0.0) - off, y, z))
        # top point on the midline
        mid = V(0.0, y, zt + off)
        pts = left[:-1] + [mid] + right[1:]
        rows.append(pts)
    return rows


def build_saddle():
    m = M("horse_tack_saddle")
    # ---- cloth (saddle pad / shabraque): red, gold hem, heraldic patch on both flanks
    ys = [-0.62 + 0.80 * i / 9.0 for i in range(10)]                 # -0.62 .. 0.18
    yc, hy = -0.22, 0.40

    def hem(y, zt):
        t = (y - yc) / hy
        frac = smooth(0.62, 1.0, abs(t))
        return 1.03 + (zt - 1.03 - 0.03) * frac ** 1.5
    rows = cross_section_rows(ys, hem, 5, 1.6, 0.012)
    n = len(rows[0])
    vr = [[m.v(p) for p in r] for r in rows]
    em_y0, em_y1 = rows[6][0].y, rows[9][0].y
    em_z0, em_z1 = rows[6][0].z, rows[6][3].z

    def keyf_factory(i, j):
        if 6 <= i <= 8 and (j <= 2 or j >= n - 4):
            return "EMBLEM"
        return "RED"
    for i in range(len(rows) - 1):
        for j in range(n - 1):
            m.face((vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1]), keyf_factory(i, j), expect=None)

    # gold piping along the whole cloth border
    border = [rows[0][j] for j in range(n)] + [rows[i][n - 1] for i in range(1, len(rows))] +              [rows[len(rows) - 1][j] for j in range(n - 2, -1, -1)] + [rows[i][0] for i in range(len(rows) - 2, 0, -1)]
    strap(m, catmull(border, 2, closed=True), 0.020, 0.004, "GOLD", closed=True, off=0.016, solid=False, maxd=0.12)

    def emb(co):
        if co.x >= 0:
            return ((co.y - em_y0) / (em_y1 - em_y0), (co.z - em_z0) / (em_z1 - em_z0))
        return ((em_y1 - co.y) / (em_y1 - em_y0), (co.z - em_z0) / (em_z1 - em_z0))
    m.emb = emb
    # ---- leather skirts (flaps) under the rider's thighs
    m.tag = "body"
    ysf = [-0.47 + 0.36 * i / 5.0 for i in range(6)]
    for side in (1.0, -1.0):
        rowsf = []
        for y in ysf:
            zt = 1.44
            t = (y + 0.29) / 0.18
            zl = 1.19 + 0.05 * smooth(0.55, 1.0, abs(t))
            row = []
            for i in range(5):
                z = zl + (1.44 - zl) * i / 4.0
                x = env_x(y, z, side)
                row.append(V((x if x is not None else 0.2 * side) + side * 0.030, y, z))
            rowsf.append(row)
        vr = [[m.v(p) for p in r] for r in rowsf]
        for i in range(len(vr) - 1):
            for j in range(len(vr[0]) - 1):
                edge = (j == 0)
                fs = (vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1]) if side > 0 else (vr[i][j], vr[i][j + 1], vr[i + 1][j + 1], vr[i + 1][j])
                m.face(fs, "DARK" if edge else "LEATHER")
    # ---- girth: strap under the belly (from the flap bottoms round the barrel)
    gy = -0.17
    cz = 1.17
    pts = []
    for i in range(21):
        phi = math.radians(12 - 204 * i / 20.0)
        d = V(math.cos(phi), 0, math.sin(phi))
        h, nn = ray(V(0, gy, cz) + d * 1.2, -d)
        if h is not None:
            pts.append(h + d * 0.0)
    strap(m, pts, 0.075, 0.010, "LEATHER", off=0.028)
    # girth buckle plates (left side)
    bp, bn = snap(V(0.26, gy, 1.13), 0.045)
    box(m, bp, (0.012, 0.05, 0.05), "BRASS", axes=(bn, V(0, 1, 0), bn.cross(V(0, 1, 0)).normalized()))
    # ---- seat / tree: closed loft of top and bottom surfaces
    m.tag = "rigid"
    ny, nx = 13, 7
    y0, y1 = -0.53, -0.04
    seat_rows = []
    for i in range(ny):
        y = y0 + (y1 - y0) * i / (ny - 1)
        w = 0.095 + 0.085 * smooth(-0.53, -0.33, y)
        rowt, rowb = [], []
        for j in range(nx):
            xr = -1 + 2 * j / (nx - 1)
            x = xr * w
            zt = 1.561 + 0.035 * ((y + 0.24) / 0.2) ** 2 - 0.045 * abs(xr) ** 2.5
            cant = 0.115 * smooth(-0.14, -0.05, y) * (1.0 + 0.30 * abs(xr) ** 2)
            pom = 0.125 * smooth(-0.44, -0.51, y) * (1.0 - 0.45 * abs(xr) ** 2)
            zt += cant + pom
            zb_h = top_z(x, y)
            zb = (zb_h if zb_h is not None else 1.40) + 0.022
            zt = max(zt, zb + 0.032)
            rowt.append(V(x, y, zt))
            rowb.append(V(x, y, zb))
        seat_rows.append(rowt + rowb[::-1])
    vr = [[m.v(p) for p in r] for r in seat_rows]
    m.loft(vr, "LEATHER", closed=True, keyf=lambda i, j: "DARK" if (j >= nx - 1 and j <= nx) else ("LEATHER" if j < nx - 1 else "DARK"))
    m.cap(vr[0], "LEATHER", flip=True)
    m.cap(vr[-1], "LEATHER")
    # pommel knob + cantle piping
    sphere(m, V(0, -0.505, 1.561 + 0.125 + 0.028), 0.030, 0.030, 0.026, "BRASS", 8, 4)
    # ---- stirrup leathers + iron stirrups (rigid)
    m.tag = "rigid"
    for side in (1.0, -1.0):
        px = 0.31 * side
        zs = [1.47, 1.30, 1.16, 1.06]
        pts = []
        for z in zs:
            e = env_x(-0.30, z, side)
            xw = (e if e is not None else 0.2 * side)
            x = side * max(abs(xw) + 0.052, 0.0) if z > 1.09 else px
            pts.append(V(x, -0.30, z))
        strap(m, pts, 0.028, 0.008, "LEATHER", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0))
        # stirrup: oval iron ring in the x-z plane, tread on the bottom
        c = V(px, -0.30, 0.941 + 0.062)
        torus(m, c, V(1, 0, 0), V(0, 0, 1), V(0, 1, 0), 0.060, 0.070, 0.0085, "IRON", seg=10, sides=4)
        box(m, V(px, -0.30, 0.941 - 0.004), (0.118, 0.095, 0.010), "STEEL")
    allowed = {"spine_1", "spine_2", "spine_3", "chest", "belly"}
    body_w = w_surface(allowed, ["spine_2", "spine_3", "chest"])
    return m.finish("horse_tack_saddle", lambda co, tag: {"spine_3": 1.0} if tag == "rigid" else body_w(co, tag))


# ------------------------------------------------------------------ BRIDLE + REINS
HEAD_C0 = V(0, -1.20, 1.76)
HEAD_C1 = V(0, -1.42, 1.52)
HEAD_A = (HEAD_C1 - HEAD_C0).normalized()
HEAD_F = (V(0, 0, 1) - HEAD_A * HEAD_A.z).normalized()        # up-forward, perpendicular to the head axis


def head_c(t):
    return HEAD_C0.lerp(HEAD_C1, t)


def head_ring(t, thetas, reach=0.45):
    """surface points around the head at axis station t (theta 0 = front of the face, +90 = left side)"""
    c = head_c(t)
    out = []
    for th in thetas:
        d = HEAD_F * math.cos(math.radians(th)) + V(1, 0, 0) * math.sin(math.radians(th))
        h, n = ray(c + d * reach, -d)
        if h is not None:
            out.append(h)
    return out


def catmull(pts, n_per=2, closed=False):
    P = list(pts)
    out = []
    cnt = len(P)
    for i in range(cnt if closed else cnt - 1):
        p0 = P[(i - 1) % cnt] if closed else P[max(i - 1, 0)]
        p1 = P[i]
        p2 = P[(i + 1) % cnt]
        p3 = P[(i + 2) % cnt] if closed else P[min(i + 2, cnt - 1)]
        for k in range(n_per):
            u = k / n_per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    if not closed:
        out.append(P[-1])
    return out


def side_pts(side, ctrl):
    """points on the side of the head/neck (ray along -x), from (y, z) control points"""
    out = []
    for y, z in ctrl:
        x = env_x(y, z, side)
        out.append(V(x if x is not None else 0.1 * side, y, z))
    return out


def build_bridle():
    m = M("horse_tack_bridle")
    m.tag = "head"
    off = 0.008
    # noseband (full ring round the muzzle)
    ring = head_ring(0.78, range(0, 360, 30))
    strap(m, ring, 0.026, 0.005, "LEATHER", closed=True, off=off, solid=False)
    # browband: front arc under the ears
    arc = head_ring(0.10, range(-100, 101, 25))
    strap(m, arc, 0.022, 0.005, "RED", off=off, solid=False)
    # crown piece: over the poll behind the ears, plane y = -1.135
    cc = V(0, -1.135, 1.72)
    crown = []
    for phi in range(-100, 101, 25):
        d = V(math.sin(math.radians(phi)), 0, math.cos(math.radians(phi)))
        h, n = ray(cc + d * 0.5, -d)
        if h is not None:
            crown.append(h)
    strap(m, crown, 0.024, 0.005, "LEATHER", off=off, solid=False)
    # cheek pieces (crown side end -> bit ring) + rosettes
    for side in (1.0, -1.0):
        ctrl = [(-1.135, 1.66), (-1.19, 1.61), (-1.25, 1.555), (-1.31, 1.51), (-1.375, 1.495)]
        pts = catmull(side_pts(side, ctrl), 2)
        strap(m, pts, 0.020, 0.005, "LEATHER", off=off, solid=False)
        rp, rn = snap(V((env_x(-1.20, 1.66, side) or 0.12 * side), -1.20, 1.66), 0.012)
        sphere(m, rp, 0.011, 0.011, 0.011, "BRASS", 6, 3)
        # bit ring (in the y-z plane) at the mouth corner
        rc = V(0.088 * side, -1.385, 1.475)
        torus(m, rc, V(0, 1, 0), V(0, 0, 1), V(1, 0, 0), 0.026, 0.026, 0.0042, "STEEL", seg=10, sides=4)
    tube(m, [V(-0.09, -1.385, 1.475), V(0.09, -1.385, 1.475)], 0.0055, "STEEL", sides=4, up=V(0, 0, 1))
    return m.finish("horse_tack_bridle", w_surface({"head", "jaw"}, ["head"]))


def build_reins():
    m = M("horse_tack_reins")
    N = 12
    for side, sname in ((1.0, "L"), (-1.0, "R")):
        p0 = V(0.088 * side, -1.385, 1.502)         # top of the bit ring
        p1 = V(0.09 * side, -0.60, 1.721)           # rein_grip
        pts = []
        for i in range(N + 1):
            t = i / N
            p = p0.lerp(p1, t)
            p.z += -0.105 * math.sin(math.pi * t)                # slight sag
            tz = top_z(0.0, p.y)
            e = env_x(p.y, min(p.z, (tz - 0.01) if tz else p.z), side)
            need = (abs(e) + 0.035) if e is not None else 0.0
            if 0.05 < t < 0.97 and abs(p.x) < need:
                p.x = need * side
            pts.append(p)
        for _ in range(3):                                         # smooth the outward push
            pts = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) * 0.25 for i in range(1, N)] + [pts[-1]]
        i0 = len(m.tags)
        tube(m, pts, 0.0065, "DARK", sides=4, up=V(0, 0, 1))
        for j in range(i0, len(m.tags)):
            k = j - i0
            ring = min(k // 4, N)
            m.tags[j] = (sname, ring / N)

    def wf(co, tag):
        sname, t = tag
        s = smooth(0.0, 1.0, t)
        if s <= 0.0:
            return {"head": 1.0}
        if s >= 1.0:
            return {"rein_grip_" + sname: 1.0}
        return {"head": 1.0 - s, "rein_grip_" + sname: s}
    return m.finish("horse_tack_reins", wf)


# ------------------------------------------------------------------ helpers for the body-wrapping pieces
def env_up(y, z, side, tries=14):
    """env_x, but if nothing is hit (below the belly) look upward until the body is found"""
    for k in range(tries):
        x = env_x(y, z + 0.02 * k, side)
        if x is not None:
            return x
    return 0.0


def wrap_rows(ys, hem_fn, ncol, bias=1.6, off=0.012, zcap=0.004):
    """rows of (2*ncol+1) points from the left hem over the back to the right hem, outermost body surface + off"""
    rows = []
    for y in ys:
        zt = top_z(0.0, y) or 1.45
        zh = hem_fn(y, zt)
        lv = [zt - (zt - zh) * ((1.0 - i / ncol) ** bias) for i in range(ncol + 1)]      # hem -> top
        left = [V(env_up(y, min(z, zt - zcap), 1.0) + off, y, z) for z in lv]
        right = [V(-env_up(y, min(z, zt - zcap), -1.0) - off, y, z) for z in lv[::-1]]
        rows.append(left[:-1] + [V(0.0, y, zt + off)] + right[1:])
    return rows


def grid_faces(m, rows, keyfn, flip=False):
    vr = [[m.v(p) for p in r] for r in rows]
    for i in range(len(vr) - 1):
        for j in range(len(vr[0]) - 1):
            q = (vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1])
            m.face(q[::-1] if flip else q, keyfn(i, j, rows))
    return vr


def ring_cast_h(center, dirs, reach=1.2):
    """horizontal (x-y plane) or any ring: rays from outside toward the centre, first surface hit for each dir"""
    out = []
    for d in dirs:
        h, n = ray(center + d * reach, -d)
        if h is not None:
            out.append(h)
    return out


# ------------------------------------------------------------------ SADDLEBAGS
def build_saddlebags():
    m = M("horse_tack_saddlebags")
    yc, zc, ay, az, depth = 0.235, 1.20, 0.17, 0.18, 0.115
    N = 8
    for side in (1.0, -1.0):
        rows = []
        for i in range(N + 1):
            u = -1 + 2 * i / N
            row = []
            for j in range(N + 1):
                v = -1 + 2 * j / N
                ru = u * (1 - 0.55 * (1 - math.sqrt(max(0.0, 1 - v * v / 2))))
                rv = v * (1 - 0.55 * (1 - math.sqrt(max(0.0, 1 - u * u / 2))))
                y, z = yc + ru * ay, zc + rv * az
                xi = env_up(y, z, side)
                sq = max(abs(u), abs(v))
                d = depth * math.sqrt(max(0.0, 1.0 - sq ** 4)) + 0.004
                row.append(V(xi + side * (0.014 + d), y, z))
            rows.append(row)
        vr = [[m.v(p) for p in r] for r in rows]
        for i in range(N):
            for j in range(N):
                v_mid = -1 + 2 * (j + 0.5) / N
                key = "DARK" if v_mid > 0.42 else "LEATHER"           # lid (top) darker
                q = (vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1])
                m.face(q if side > 0 else q[::-1], key)
        # buckle on the lid
        bp = V(rows[N // 2][N - 2].x + side * 0.012, yc, zc + az * 0.30)
        box(m, bp, (0.014, 0.05, 0.05), "BRASS")
        box(m, V(bp.x, yc, zc + az * 0.05), (0.010, 0.020, 0.10), "DARK")
    # strap over the back joining the two bags (with the girth-side buckle)
    cc = V(0, 0.235, 1.10)
    pts = []
    for phi in range(-80, 81, 10):
        d = V(math.sin(math.radians(phi)), 0, math.cos(math.radians(phi)))
        h, n = ray(cc + d * 0.9, -d)
        if h is not None:
            pts.append(h)
    strap(m, pts, 0.040, 0.008, "DARK", off=0.014, solid=True)

    def wf(co, tag):
        s = smooth(0.05, 0.42, co.y)
        return {"spine_2": 1.0 - s, "spine_1": s}
    return m.finish("horse_tack_saddlebags", wf)


# ------------------------------------------------------------------ CART HARNESS
def build_cart_harness():
    m = M("horse_tack_cart_harness")
    X_ = V(1, 0, 0)
    # ---- collar: tall padded oval round the neck base, in a plane leaning with the neck
    m.tag = "collar"
    cc = V(0, -0.80, 1.40)
    D = V(0, 0.55, 0.83).normalized()
    pts = []
    for k in range(20):
        ph = 2 * math.pi * k / 20
        d = D * math.cos(ph) + X_ * math.sin(ph)
        h, n = ray(cc + d * 1.3, -d)
        if h is None:
            continue
        pts.append((h, d, ph))
    ring = [h + d * 0.046 for h, d, ph in pts]
    tube(m, ring, 0.038, "LEATHER", sides=6, closed=True, up=lambda i, p: X_)
    # hames: metal bars on both sides of the collar, brass knobs on top, draught rings at mid height
    for side in (1.0, -1.0):
        sel = [(h, d) for h, d, ph in pts if d.x * side > 0.35]
        sel.sort(key=lambda hd: -hd[0].z)
        hp = [h + d * 0.084 for h, d in sel]
        if len(hp) >= 3:
            strap(m, hp, 0.022, 0.012, "BRASS", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
            sphere(m, hp[0] + V(0, 0, 0.02), 0.020, 0.020, 0.020, "BRASS", 6, 3)
            mid = hp[len(hp) // 2]
            torus(m, mid + V(side * 0.012, 0.015, -0.006), V(0, 1, 0), V(0, 0, 1), X_, 0.022, 0.022, 0.0055, "IRON", seg=8, sides=4)
    # ---- harness back pad with terret, belly band, tug loops
    m.tag = "pad"
    ys = [-0.16 + 0.32 * i / 3.0 for i in range(4)]
    rows = wrap_rows(ys, lambda y, zt: 1.30, 3, 1.4, 0.014)
    vr = grid_faces(m, rows, lambda i, j, r: "DARK")
    # pad borders (red piping)
    for i in (0, len(rows) - 1):
        strap(m, catmull(rows[i], 2), 0.016, 0.004, "RED", off=0.019, solid=False, maxd=0.12)
    tp, tn = snap(V(0, 0.0, 1.55), 0.02)
    torus(m, tp + V(0, 0, 0.03), V(1, 0, 0), V(0, 0, 1), V(0, 1, 0), 0.026, 0.030, 0.0065, "BRASS", seg=8, sides=4)
    box(m, tp + V(0, 0, 0.004), (0.03, 0.05, 0.016), "BRASS")
    gy = 0.03
    gp = []
    for i in range(19):
        phi = math.radians(14 - 208 * i / 18.0)
        d = V(math.cos(phi), 0, math.sin(phi))
        h, nn = ray(V(0, gy, 1.17) + d * 1.2, -d)
        if h is not None:
            gp.append(h)
    strap(m, gp, 0.060, 0.010, "DARK", off=0.016, solid=True)
    for side in (1.0, -1.0):
        tug = V(0.27 * side, 0.02, 1.10)
        torus(m, tug, X_, V(0, 0, 1), V(0, 1, 0), 0.034, 0.030, 0.0075, "IRON", seg=8, sides=4)
        # hanger strap pad edge -> tug loop
        top = V(env_up(0.02, 1.28, side) * 1.0, 0.02, 1.28)
        pts_ = []
        for k in range(5):
            z = 1.28 + (1.13 - 1.28) * k / 4
            x = max(abs(env_up(0.02, z, side)) + 0.022, 0.0)
            pts_.append(V(x * side, 0.02, z))
        strap(m, pts_, 0.030, 0.008, "DARK", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0))
    # ---- traces: collar draught ring -> tug loop along the barrel side
    m.tag = "trace"
    for side in (1.0, -1.0):
        ys_ = [-0.84 + 0.86 * k / 9.0 for k in range(10)]
        pts_ = []
        for k, y in enumerate(ys_):
            t = k / 9.0
            z = 1.34 + (1.10 - 1.34) * t
            x = abs(env_up(y, z, side)) + 0.026
            if k == 9:
                x = 0.27
            pts_.append(V(x * side, y, z))
        strap(m, pts_, 0.030, 0.009, "LEATHER", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
    # ---- breeching round the hindquarters, hip straps, crupper
    m.tag = "breech"
    c = V(0, 0.45, 1.13)
    dirs = [V(math.sin(math.radians(a)), math.cos(math.radians(a)), 0) for a in range(-100, 101, 12)]
    bp = ring_cast_h(c, dirs)
    strap(m, bp, 0.070, 0.011, "LEATHER", off=0.018, solid=True)
    for side in (1.0, -1.0):
        ang = 100 * side
        e = ring_cast_h(c, [V(math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0)])
        y_end = e[0].y if e else 0.45
        pts_ = []
        for k in range(8):
            y = y_end + (0.02 - y_end) * k / 7.0
            x = abs(env_up(y, 1.12, side)) + 0.024
            pts_.append(V(x * side, y, 1.13))
        strap(m, pts_, 0.040, 0.009, "LEATHER", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
        # hip strap: over the loin down the flank to the breeching
        hp = []
        for k in range(8):
            t = k / 7.0
            y = 0.30 + 0.22 * t
            zt = top_z(0.06 * side, y) or 1.45
            z = zt + (1.14 - zt) * (t ** 1.2)
            x = abs(env_up(y, min(z, zt - 0.02), side)) + 0.016 if t > 0.05 else 0.05
            hp.append(V(x * side, y, z))
        strap(m, hp, 0.028, 0.008, "LEATHER", off=0.016, solid=False, maxd=0.12)
    # crupper along the topline to the tail dock
    cp = []
    for k in range(9):
        y = 0.10 + 0.56 * k / 8.0
        cp.append(V(0, y, (top_z(0.0, y) or 1.45)))
    strap(m, cp, 0.030, 0.008, "LEATHER", off=0.014, solid=False)

    def wf(co, tag):
        if tag == "collar":
            return bone_dist_weights(co, ["neck_1", "withers", "chest", "neck_2"], 3)
        if tag == "trace":
            return bone_dist_weights(co, ["withers", "chest", "spine_3", "spine_2"], 3)
        if tag == "breech":
            d = surface_weights(co, {"hips", "thigh_L", "thigh_R", "spine_1", "spine_2", "tail_1"})
            return d or {"hips": 1.0}
        d = surface_weights(co, {"spine_1", "spine_2", "spine_3", "belly", "chest"})
        return d or bone_dist_weights(co, ["spine_2", "spine_3"], 2)
    return m.finish("horse_tack_cart_harness", wf)


# ------------------------------------------------------------------ BARDING (knight's warhorse)
def build_barding():
    m = M("horse_tack_barding")
    # ---- caparison: cloth over the body from the withers to the croup, hem near the knees / hocks
    ys = [-0.70 + 1.56 * i / 21.0 for i in range(22)]
    belly = {}
    for y in ys:
        b = None
        for k in range(60):
            zz = 0.45 + 0.015 * k
            if env_x(y, zz, 1.0) is not None and (zz > 0.55):
                b = zz
                break
        belly[y] = b if b is not None else 0.7

    def hem(y, zt):
        lowest = belly[y]
        return max(0.66, lowest + 0.10 if lowest > 0.78 else 0.66)
    rows = wrap_rows(ys, hem, 6, 1.7, 0.026)
    ny, nc = len(rows), len(rows[0])
    e_y0, e_y1 = -0.34, 0.10
    e_z0, e_z1 = 0.92, 1.34

    def keyfn(i, j, r):
        c = (r[i][j] + r[i + 1][j + 1]) * 0.5
        if abs(c.x) > 0.12 and e_y0 <= c.y <= e_y1 and e_z0 <= c.z <= e_z1:
            return "EMBLEM"
        return "RED"
    grid_faces(m, rows, keyfn)

    def emb(co):
        if co.x >= 0:
            return ((co.y - e_y0) / (e_y1 - e_y0), (co.z - e_z0) / (e_z1 - e_z0))
        return ((e_y1 - co.y) / (e_y1 - e_y0), (co.z - e_z0) / (e_z1 - e_z0))
    m.emb = emb
    border = [rows[0][j] for j in range(nc)] + [rows[i][nc - 1] for i in range(1, ny)] + \
             [rows[ny - 1][j] for j in range(nc - 2, -1, -1)] + [rows[i][0] for i in range(ny - 2, 0, -1)]
    strap(m, catmull(border, 1, closed=True), 0.022, 0.004, "GOLD", closed=True, off=0.030, solid=False, maxd=0.12)
    # gold stripe along the spine
    strap(m, [V(0, y, (top_z(0.0, y) or 1.4)) for y in ys[::2]], 0.026, 0.004, "GOLD", off=0.030, solid=False, maxd=0.12)
    n_cap = len(m.tags)
    m.tag = "head"
    # ---- chanfron: steel face plate hugging the front of the face
    X_ = V(1, 0, 0)
    prow = []
    NT, NS = 9, 6
    for a in range(NT + 1):
        t = 0.04 + 0.90 * a / NT
        w = 0.080 - 0.036 * smooth(0.1, 0.9, t)
        row = []
        for b in range(NS + 1):
            s = -w + 2 * w * b / NS
            o = head_c(t) + X_ * s + HEAD_F * 0.5
            h, n = ray(o, -HEAD_F)
            if h is None:
                h = head_c(t) + X_ * s
                n = HEAD_F
            _, nn = snap(h, 0.0)
            row.append(h + (nn if nn is not None else n) * 0.014)
        prow.append(row)
    grid_faces(m, prow, lambda i, j, r: "STEEL", flip=True)
    edge = prow[0] + [prow[i][NS] for i in range(1, NT + 1)] + prow[NT][::-1][1:] + [prow[i][0] for i in range(NT - 1, 0, -1)]
    strap(m, edge, 0.012, 0.004, "BRASS", closed=True, off=0.016, solid=False, maxd=0.12)
    # forehead spike
    sp0 = prow[2][NS // 2]
    _, spn = snap(sp0, 0.0)
    spn = spn or HEAD_F
    tube(m, [sp0, sp0 + spn * 0.03, sp0 + spn * 0.075], 0.011, "BRASS", sides=5, up=V(1, 0, 0), r_fn=lambda i: (0.016, 0.010, 0.002)[i])
    n_head = len(m.tags)
    m.tag = "crinet"
    # ---- crinet: overlapping steel plates along the crest of the neck
    for k in range(7):
        y = -1.12 + 0.065 * k * 1.0
        zt = top_z(0.0, y) or 1.7
        cc = V(0, y, zt - 0.20)
        rr = []
        for dy, lift in ((-0.04, 0.0), (0.045, 0.014)):
            r_ = []
            for ang in range(-70, 71, 20):
                d = V(math.sin(math.radians(ang)), 0, math.cos(math.radians(ang)))
                h, n = ray(cc + V(0, dy, 0) + d * 0.7, -d)
                if h is None:
                    continue
                r_.append(h + d * (0.020 + lift))
            rr.append(r_)
        if len(rr[0]) == len(rr[1]) and len(rr[0]) > 2:
            for j in range(len(rr[0]) - 1):
                m.face((rr[0][j], rr[1][j], rr[1][j + 1], rr[0][j + 1]), "STEEL")
    neck_bones = ["neck_1", "neck_2", "neck_3", "neck_4", "withers", "head"]
    skip = {"mane", "tail"}

    def wf(co, tag):
        if tag == "head":
            return {"head": 1.0}
        if tag == "crinet":
            return bone_dist_weights(co, neck_bones, 2, 3.0)
        d = surface_weights(co, None)
        d = {b: w for b, w in d.items() if not b.startswith("mane") and not b.startswith("tail_") and not b.startswith("ear")}
        if not d:
            d = {"spine_3": 1.0}
        return d
    return m.finish("horse_tack_barding", wf)
