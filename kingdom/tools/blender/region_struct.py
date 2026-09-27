"""Structure helpers + the generic set runner for the region structure sets (farm, mine, road, ruins).

All parts use the shared tint-convention materials of region_kit (COLOR_0 = albedo tint, painted
tileable textures in region/textures/), so Godot imports them with no overrides.
Conventions: metres, +Z up, origin at ground centre, front faces -Y (Godot +Z).
"""
import os, sys, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
import region_kit as K
from region_kit import RB, hexc, mix

UP = Vector((0, 0, 1))
# tints (multiply the painted textures)
WOOD = (1.0, 1.0, 1.0)
WOOD_DK = (0.62, 0.55, 0.5)
WOOD_GREY = (0.9, 0.9, 0.88)
TIMBER = (0.8, 0.74, 0.7)
IRON = (1.0, 1.0, 1.0)
STONE = (1.0, 1.0, 1.0)
HOLE = (0.12, 0.1, 0.09)
RED = hexc("b8453a")
CREAM = (1.0, 0.97, 0.92)
GREEN = hexc("7fa35a")


def jit(k, c, a=0.07):
    f = 1 + k.rng.uniform(-a, a)
    return tuple(min(1.0, x * f) for x in c)


# ============================================================================ building parts
def post(k, x, y, z0, z1, w=0.22, tint=TIMBER, mat="RG_Timber"):
    k.beam((x, y, z0), (x, y, z1), w, w, mat, jit(k, tint), up=(1, 0, 0))


def plank_wall(k, x0, x1, y, z0, z1, th=0.1, vertical=True, mat="RG_Planks", tint=WOOD, rot=0.0):
    """Wall box from x0..x1 (local frame), centred on y; vertical boards by default."""
    k.box((x1 - x0, th, z1 - z0), ((x0 + x1) / 2, y, (z0 + z1) / 2), mat, jit(k, tint), rot=(0, 0, rot),
          grain=2 if vertical else 0)


def roof_side(k, x0, x1, ye, ze, yr, zr, th, mat, tint=(1, 1, 1), under="RG_Planks", under_tint=WOOD_DK,
              ridge_over=0.0):
    """One roof plane from the eave line (ye, ze) up to the ridge line (yr, zr), x0..x1 along the ridge.
    Top UV: U along the ridge, V up the slope (shingle butts face downhill)."""
    s = K.MATS[mat].get("scale", 1.5)
    e = Vector((0, ye, ze))
    r = Vector((0, yr, zr))
    d = (r - e)
    L = d.length + ridge_over
    d.normalize()
    r = e + d * L
    n = Vector((0, -d.z, d.y)) if ye < yr else Vector((0, d.z, -d.y))
    if n.z < 0:
        n = -n
    off = -n * th
    ou = k.rng.uniform(0, 1)
    P = lambda x, p: Vector((x, p.y, p.z))
    top = [P(x0, e), P(x1, e), P(x1, r), P(x0, r)]
    uv = [(x0 / s + ou, 0), (x1 / s + ou, 0), (x1 / s + ou, L / s), (x0 / s + ou, L / s)]
    if K.newell(top).dot(n) < 0:
        top, uv = top[::-1], uv[::-1]
    k.add([top], mat, tint, uvs=[uv])
    c = sum(top, Vector()) / 4 + off * 0.5
    t0, t1, t2, t3 = top
    rest = [[p + off for p in top],
            [t0, t1, t1 + off, t0 + off], [t1, t2, t2 + off, t1 + off],
            [t2, t3, t3 + off, t2 + off], [t3, t0, t0 + off, t3 + off]]
    k.add(oriented(rest, c), under, under_tint)


def oriented(faces, c):
    """Flip faces so their normal points away from point c (closed convex parts)."""
    out = []
    for f in faces:
        f = [Vector(p) for p in f]
        fc = sum(f, Vector()) / len(f)
        out.append(f if K.newell(f).dot(fc - c) >= 0 else f[::-1])
    return out


def gable_roof(k, cx, cy, L, W, z_eave, pitch=40, over_x=0.4, over_y=0.45, th=0.14, mat="RG_Shingle", tint=(1, 1, 1),
               ridge=True, ridge_tint=TIMBER):
    """Ridge along X. Returns ridge height."""
    t = math.tan(math.radians(pitch))
    z_eave = z_eave + th / math.cos(math.radians(pitch)) + 0.03   # underside sits on the wall plate
    rz = z_eave + W / 2 * t
    k.push((cx, cy, 0))
    x0, x1 = -L / 2 - over_x, L / 2 + over_x
    for s in (-1, 1):
        ye = s * (W / 2 + over_y)
        ze = z_eave - over_y * t
        roof_side(k, x0, x1, ye, ze, 0.0, rz, th, mat, tint, ridge_over=th * 0.6)
    if ridge:
        if mat == "RG_Thatch":
            k.beam((x0, 0, rz - 0.05), (x1, 0, rz - 0.05), 0.42, 0.3, "RG_Thatch", (0.85, 0.8, 0.72), up=(0, 0, 1))
        else:
            k.beam((x0 - 0.05, 0, rz + 0.02), (x1 + 0.05, 0, rz + 0.02), 0.2, 0.16, "RG_Timber", ridge_tint,
                   up=(0, 0, 1))
    k.pop()
    return rz


def gable_end(k, cx, x, cy, W, z0, rz, th=0.12, mat="RG_Planks", tint=WOOD, vertical=True):
    """Triangular gable wall at x (plane YZ) from z0 up to the ridge rz, width W (along y)."""
    pts = [(-W / 2, z0), (W / 2, z0), (0, rz)]
    k.prism(pts, th, (x, cy, 0), mat, jit(k, tint), rot=(0, 0, math.pi / 2), grain=2 if vertical else None)


def door(k, x, y, w=1.1, h=2.0, z0=0.0, face=-1, double=False, tint=(0.82, 0.72, 0.64), frame=True, open_=0.0):
    """Plank door in the wall plane y (face=-1: faces -Y). Hinged straps, frame."""
    k.push((x, y, z0), (0, 0, 0 if face < 0 else math.pi))
    k.box((w + 0.04, 0.1, h + 0.02), (0, 0.02, h / 2), "RG_Timber", HOLE)
    leaves = [(-w / 2, w / 2)] if not double else [(-w / 2, 0), (0, w / 2)]
    for a, b in leaves:
        k.box((b - a - 0.02, 0.06, h - 0.02), ((a + b) / 2, -0.05, h / 2), "RG_Planks", jit(k, tint), grain=2)
        for zz in (0.3, h - 0.35):
            k.box((b - a - 0.08, 0.02, 0.07), ((a + b) / 2, -0.09, zz), "RG_Iron", (0.8, 0.8, 0.8))
        if double:
            k.beam(((a + 0.08), -0.085, 0.35), ((b - 0.08), -0.085, h - 0.4), 0.12, 0.04, "RG_Timber",
                   jit(k, WOOD_DK), up=(0, -1, 0))
    if frame:
        for xx in (-w / 2 - 0.08, w / 2 + 0.08):
            k.beam((xx, -0.04, 0), (xx, -0.04, h + 0.1), 0.16, 0.16, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
        k.beam((-w / 2 - 0.2, -0.04, h + 0.12), (w / 2 + 0.2, -0.04, h + 0.12), 0.18, 0.18, "RG_Timber",
               jit(k, TIMBER))
    k.pop()


def window(k, x, y, z0, w=0.7, h=0.8, face=-1, shutters=True, sh_tint=(0.55, 0.7, 0.62), lod=0):
    k.push((x, y, z0), (0, 0, 0 if face < 0 else math.pi))
    k.box((w, 0.12, h), (0, 0.0, h / 2), "RG_Timber", (0.16, 0.14, 0.13))
    for xx in (-w / 2 - 0.05, w / 2 + 0.05):
        k.beam((xx, -0.05, -0.05), (xx, -0.05, h + 0.05), 0.1, 0.1, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    k.beam((-w / 2 - 0.12, -0.08, -0.05), (w / 2 + 0.12, -0.08, -0.05), 0.12, 0.14, "RG_Timber", jit(k, TIMBER))
    k.beam((-w / 2 - 0.1, -0.05, h + 0.05), (w / 2 + 0.1, -0.05, h + 0.05), 0.1, 0.1, "RG_Timber", jit(k, TIMBER))
    if lod == 0:
        k.beam((0, -0.07, 0), (0, -0.07, h), 0.05, 0.04, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
        k.beam((-w / 2, -0.07, h / 2), (w / 2, -0.07, h / 2), 0.05, 0.04, "RG_Timber", jit(k, TIMBER))
    if shutters:
        for sx in (-1, 1):
            k.box((w / 2, 0.04, h), (sx * (w * 0.75 + 0.1), -0.09, h / 2), "RG_Planks", jit(k, sh_tint), grain=2)
    k.pop()


def stone_plinth(k, x0, x1, y0, y1, h, tint=STONE):
    k.box((x1 - x0, y1 - y0, h), ((x0 + x1) / 2, (y0 + y1) / 2, h / 2), "RG_Stone", jit(k, tint, 0.04))


def ring_lathe(k, center, r_in, r_out, w, axis_rot, mat, tint, segs=16):
    """Flat ring (wheel rim, hoop) with its axis along local Z rotated by axis_rot."""
    prof = [(r_in, -w / 2), (r_out, -w / 2), (r_out, w / 2), (r_in, w / 2), (r_in, -w / 2)]
    k.lathe(prof, center, mat, tint, rot=axis_rot, segs=segs, caps=(False, False), smooth=False)


def wheel(k, c, r=0.5, w=0.09, spokes=8, lod=0, axis="x", tint=WOOD_DK):
    rot = (0, math.pi / 2, 0) if axis == "x" else (math.pi / 2, 0, 0)
    segs = 14 if lod == 0 else 8
    ring_lathe(k, c, r * 0.84, r, w, rot, "RG_Timber", jit(k, tint), segs)
    ring_lathe(k, c, r, r + 0.02, w * 1.05, rot, "RG_Iron", (0.9, 0.9, 0.9), segs)
    c = Vector(c)
    ax = Vector((1, 0, 0)) if axis == "x" else Vector((0, 1, 0))
    k.cyl(r * 0.16, w * 2.2, tuple(c - ax * w * 1.1), "RG_Timber", jit(k, tint), rot=(0, math.pi / 2, 0) if axis == "x"
          else (-math.pi / 2, 0, 0), segs=8 if lod == 0 else 6)
    ns = spokes if lod == 0 else spokes // 2
    for i in range(ns):
        a = i / ns * math.tau
        if axis == "x":
            d = Vector((0, math.cos(a), math.sin(a)))
        else:
            d = Vector((math.cos(a), 0, math.sin(a)))
        k.beam(tuple(c + d * r * 0.14), tuple(c + d * r * 0.86), 0.05, 0.04, "RG_Timber", jit(k, tint), up=tuple(ax))


def barrel(k, x, y, z=0.0, h=0.9, r=0.33, lod=0, tint=WOOD):
    segs = 12 if lod == 0 else 8
    prof = [(r * 0.84, 0)] + [(r * (0.84 + 0.16 * math.sin(t * math.pi)), h * t) for t in (0.25, 0.5, 0.75)] + \
           [(r * 0.84, h)]
    k.lathe(prof, (x, y, z), "RG_Planks", jit(k, tint), segs=segs, uscale=0.9)
    for t in (0.12, 0.88) if lod else (0.1, 0.35, 0.65, 0.9):
        rr = r * (0.84 + 0.16 * math.sin(t * math.pi)) + 0.012
        k.cyl(rr, 0.05, (x, y, z + h * t - 0.025), "RG_Iron", (0.85, 0.85, 0.85), segs=segs, caps=(False, False))


def crate(k, x, y, z=0.0, s=0.7, rz=0.0, lod=0, tint=WOOD):
    k.push((x, y, z), (0, 0, rz))
    k.box((s, s, s), (0, 0, s / 2), "RG_Planks", jit(k, tint), grain=0)
    if lod == 0:
        e = 0.07
        for sx in (-1, 1):
            for sy in (-1, 1):
                k.beam((sx * (s / 2 - e / 2 + 0.01), sy * (s / 2 - e / 2 + 0.01), 0),
                       (sx * (s / 2 - e / 2 + 0.01), sy * (s / 2 - e / 2 + 0.01), s), e, e, "RG_Timber",
                       jit(k, WOOD_DK))
        k.beam((-s / 2 + 0.05, -s / 2 - 0.01, 0.06), (s / 2 - 0.05, -s / 2 - 0.01, s - 0.06), 0.07, 0.03,
               "RG_Timber", jit(k, WOOD_DK), up=(0, -1, 0))
    k.pop()


def sack(k, x, y, z=0.0, s=1.0, rz=0.0, tint=(0.78, 0.66, 0.5), lod=0):
    prof = [(0.0, 0.0), (0.24 * s, 0.02 * s), (0.28 * s, 0.2 * s), (0.25 * s, 0.42 * s), (0.12 * s, 0.56 * s),
            (0.05 * s, 0.62 * s), (0.0, 0.64 * s)]
    k.lathe(prof, (x, y, z), "RG_Canvas", jit(k, tint), rot=(0.1, 0, rz), segs=8 if lod == 0 else 6,
            caps=(False, False))


def lumpy(k, c, size, mat, tint, seed=0, subdiv=2, sink=0.25, flat_bottom=True):
    """Organic lump (hay pile, ore heap, dirt mound, cabbage)."""
    import bmesh
    from mathutils import noise
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    off = seed * 13.1
    for v in bm.verts:
        p = v.co.copy()
        p += p * noise.noise(p * 1.6 + Vector((off, 0, 0))) * 0.18
        v.co = Vector((p.x * size[0], p.y * size[1], p.z * size[2]))
        if flat_bottom:
            v.co.z = max(v.co.z, -size[2] * sink)
        v.co.z += size[2] * sink
        v.co += Vector(c)
    faces = [[v.co.copy() for v in f.verts] for f in bm.faces]
    bm.normal_update()
    nrm = {}
    ctr = Vector(c) + Vector((0, 0, size[2] * sink))
    def nf(p):
        d = Vector(p) - ctr
        return Vector((d.x / size[0], d.y / size[1], d.z / size[2] + 0.3))
    k.add(faces, mat, tint, nrm_fn=nf)
    bm.free()


def hay_pile(k, c, r, h, seed=0, lod=0):
    lumpy(k, c, (r, r * 0.9, h), "RG_Hay", jit(k, (1.0, 0.95, 0.85)), seed, subdiv=2 if lod == 0 else 1, sink=0.2)


def fence_run(k, x0, x1, y, h=1.1, posts=None, rails=(0.45, 0.85), lod=0, tint=WOOD_GREY):
    n = posts or max(2, int(abs(x1 - x0) / 2.2) + 1)
    for i in range(n):
        x = x0 + (x1 - x0) * i / (n - 1)
        log_post(k, x, y, h + k.rng.uniform(-0.05, 0.05), 0.075, lod, tint)
    for z in rails:
        k.beam((x0 - 0.1, y - 0.07, z + k.rng.uniform(-0.04, 0.04)), (x1 + 0.1, y - 0.07, z + k.rng.uniform(-0.04, 0.04)),
               0.1, 0.07, "RG_Timber", jit(k, tint))


def log_post(k, x, y, h, r=0.08, lod=0, tint=WOOD, z0=-0.1, tip=True):
    """Round barked post (RG_Log = bark atlas, oak column), pointed/capped top."""
    k.tube([(x, y, z0), (x + k.rng.uniform(-0.02, 0.02), y + k.rng.uniform(-0.02, 0.02), h)], [r, r * 0.9], "RG_Log",
           jit(k, tint), segs=6 if lod == 0 else 4, cap_start=False, cap_end=True, bark=0)


def log_beam(k, a, b, r=0.08, lod=0, tint=WOOD, caps=True):
    k.tube([a, b], [r, r * 0.92], "RG_Log", jit(k, tint), segs=6 if lod == 0 else 4, cap_start=caps, cap_end=caps,
           bark=0)


def ladder(k, a, b, w=0.45, rungs=6, tint=WOOD_DK):
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 1, 0)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side = Vector((1, 0, 0))
    for s in (-1, 1):
        k.beam(tuple(a + side * s * w / 2), tuple(b + side * s * w / 2), 0.07, 0.06, "RG_Timber", jit(k, tint))
    for i in range(1, rungs + 1):
        p = a + (b - a) * (i / (rungs + 1))
        k.beam(tuple(p - side * w / 2), tuple(p + side * w / 2), 0.045, 0.045, "RG_Timber", jit(k, tint))


# ============================================================================ runner
def _markers(k):
    out = []
    for name, p in getattr(k, "markers", []):
        e = bpy.data.objects.new(name, None)
        e.location = p
        e.empty_display_size = 0.3
        bpy.context.scene.collection.objects.link(e)
        out.append(e)
    return out


def _decimate(ob, target):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris <= target:
        return tris
    m = ob.modifiers.new("dec", "DECIMATE")
    m.ratio = max(0.05, target / tris * 0.97)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    t = sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
    return t


def run_set(setname, assets, title, cols=5):
    """assets: {name: (fn(k, lod), budget0, budget1, opts)}; opts: cam, fit, seed."""
    args = K.argv()
    out = os.path.join(K.REGION, setname)
    rep_path = os.path.join(out, "_report.json")
    rep = json.load(open(rep_path)) if os.path.exists(rep_path) else {}
    names = [a for a in args if not a.startswith("--")]
    if not names and "--sheet" not in args:
        names = list(assets)
    if names == ["all"]:
        names = list(assets)
    for n in names:
        fn, b0, b1, opt = assets[n]
        K.reset()
        seed = opt.get("seed", sum(map(ord, n)))
        k1 = RB(n + "_lod1", seed)
        fn(k1, 1)
        k0 = RB(n, seed)
        fn(k0, 0)
        t0 = k0.tris()
        (x0, y0, z0), (x1, y1, z1) = k0.bounds()
        ob1 = k1.build()
        t1 = _decimate(ob1, b1)
        ex = _markers(k1)
        K.export_glb(ob1, os.path.join(out, n + "_lod1.glb"), extra=ex)
        for e in ex:
            bpy.data.objects.remove(e, do_unlink=True)
        ob1.hide_render = True
        ob0 = k0.build()
        ex = _markers(k0)
        K.export_glb(ob0, os.path.join(out, n + ".glb"), extra=ex)
        info = dict(tris0=t0, tris1=t1, size=[round(x1 - x0, 2), round(y1 - y0, 2), round(z1, 2)],
                    mats=list(k0.mnames), ok=t0 <= b0 and t1 <= b1, b0=b0, b1=b1,
                    markers=[(m, [round(v, 3) for v in p]) for m, p in getattr(k0, "markers", [])])
        rep[n] = info
        os.makedirs(out, exist_ok=True)
        json.dump(rep, open(rep_path, "w"), indent=1, sort_keys=True)
        print(f"ASSET {n}: LOD0 {t0} (<= {b0})  LOD1 {t1} (<= {b1})  size {info['size']}  mats {len(k0.mnames)}",
              flush=True)
        if "--no-thumbs" not in args:
            ob0.location.z += opt.get("lift", 0.0)
            K.render_thumb([ob0], os.path.join(K.THUMBS, f"{setname}_{n}.png"), cam_dir=opt.get("cam", (1.0, -1.45, 0.62)),
                           fit=opt.get("fit", 1.0))
    if "--sheet" in args:
        entries = []
        for n in assets:
            if n not in rep:
                continue
            i = rep[n]
            s = i["size"]
            entries.append((os.path.join(K.THUMBS, f"{setname}_{n}.png"), n,
                            f"LOD0 {i['tris0']}  LOD1 {i['tris1']}  {s[0]:.1f}X{s[1]:.1f}X{s[2]:.1f}M  {len(i['mats'])} MAT"))
        K.sheet(entries, os.path.join(K.PREV, f"region_{setname}_sheet.png"), title, cols=cols)


def crag(k, c, size, seed, mat="RG_Cliff", tint=(1, 1, 1), lod=0, cuts=10, rot=0.0, sink=0.15, subdiv=None,
         top_tint=None):
    """Faceted boulder / cliff chunk: icosphere clipped by random planes (chiselled painterly facets)."""
    import bmesh
    from mathutils import noise
    rng = random.Random(seed)
    bm = bmesh.new()
    sd = subdiv if subdiv is not None else (3 if max(size) > 1.5 else 2)
    bmesh.ops.create_icosphere(bm, subdivisions=max(1, sd - lod), radius=1.0)
    planes = []
    for i in range(cuts):
        z = rng.uniform(-0.3, 0.9)
        a = rng.uniform(0, math.tau)
        rr = math.sqrt(max(0.0, 1 - z * z))
        planes.append((Vector((rr * math.cos(a), rr * math.sin(a), z)), rng.uniform(0.55, 0.85)))
    ca, sa = math.cos(rot), math.sin(rot)
    for v in bm.verts:
        p = v.co.copy()
        for n, d in planes:
            e = p.dot(n) - d
            if e > 0:
                p -= n * e
        p += p.normalized() * noise.noise(p * 1.7 + Vector((seed * 3.1, 0, 0))) * 0.05
        p = Vector((p.x * size[0], p.y * size[1], p.z * size[2]))
        v.co = Vector((p.x * ca - p.y * sa, p.x * sa + p.y * ca, p.z))
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= zmin + size[2] * sink
        v.co += Vector(c)
    bm.normal_update()
    vn = {v: v.normal.copy() for v in bm.verts}
    faces, nrms = [], []
    for f in bm.faces:
        faces.append([l.vert.co.copy() for l in f.loops])
        nrms.append([(vn[l.vert] * 0.5 + f.normal * 0.5).normalized() for l in f.loops])
    bm.free()
    M = k.M()
    R = M.to_3x3().inverted().transposed()
    s = K.MATS[mat].get("scale", 2.0)
    for f, nr in zip(faces, nrms):
        n = K.newell(f)
        ax = max(range(3), key=lambda i: abs(n[i]))
        U, V = [(1, 2), (0, 2), (0, 1)][ax]
        uv = [(p[U] / s + seed * 0.37, p[V] / s + seed * 0.11) for p in f]
        wp = [M @ p for p in f]
        t = top_tint if (top_tint and n.normalized().z > 0.7) else tint
        k.face(wp, uv, [k.tint_col(t, p) for p in wp], [(R @ v).normalized() for v in nr], mat)
