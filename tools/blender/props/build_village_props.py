"""Task B: procedural village props at exact real dimensions (Rising Ashes AAA prop pass, 2026-10-28).
These were rejected from Meshy (barrel rack, tavern sign, bench v1, trough v1) or don't exist as CC0.

  bench_hewn         1.80 x 0.32 x 0.45 m  split-log seat (flat top, bark underside), 4 splayed round legs through-wedged
  trough_granite     2.00 x 0.70 x 0.60 m  hewn granite: boolean basin, crisp 7 mm arrises, chipped edges, chisel tooling in the normal map, moss, water
  tavern_sign        1.05 m iron bracket   wall plate + square bar arm + scroll brace, 2 chains to the board top,
                                           0.75 x 0.50 board with a painted tankard emblem (both faces). Origin = wall mount.
  barrel_rack        1.95 x 0.80 x 0.87 m  3 oak barrels (18 staves, heads, 4 iron hoops each) on a hewn cradle rack
  fence_wattle       2.00 x 0.12 x 1.10 m  7 stakes + ~36 dense courses of thin irregular hazel rods (<= 5k tris)
  fence_post_rail    2.60 x 0.16 x 1.25 m  2 hewn posts, 2 split rails through mortises
  haystack           2.3 dia x 2.6 m       medieval rick around a centre pole (rectangular bales would be anachronistic)
  hay_bundle         0.85 x 0.42 x 0.40 m  a straw-bound truss of hay (the period "bale")
  firewood_stack     1.60 x 0.50 x 1.05 m  ~110 split billets (bark, split faces, ringed end grain) between end stakes on sleepers

Same pipeline as refine_meshy.py: CC0 materials per part -> smart-UV -> one baked 1K set -> GLB -> gate render.
Usage: tools/external/blender.sh tools/blender/props/build_village_props.py -- [names...] [--work DIR]
"""
import bpy, bmesh, sys, os, math, random, shutil
import numpy as np
from mathutils import Vector, Matrix, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refine_lib as RL

OUT = os.path.join(RL.ASSETS, "props_refined")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = argv[argv.index("--work") + 1] if "--work" in argv else r"C:\Users\Jonna\Tools\_scratch\refine"
NAMES = [a for a in argv if not a.startswith("--") and a != WORK]

RL.LIB["hazel"] = dict(kind="scan", tex="bark_brown_02", tile=0.25, sat=0.55, val=0.62, tint=(0.95, 0.88, 0.80), bump=0.35, rough=0.0,
                       edge=(0.55, 0.48, 0.40), wear=0.2, grime=0.4, mud=0.5)
RL.COLOR_DEBUG["hazel"] = (0.4, 0.3, 0.2)
MATS = {}
PAINT = None


def reset(seed):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    random.seed(seed)


def mat(cls):
    if cls not in MATS:
        MATS[cls] = RL.make_material(cls, paint_img=PAINT)
    return MATS[cls]


# ------------------------------------------------------------------ geometry helpers
class Part:
    """bmesh with per-face material classes and an 'aux' UV layer (end-grain rings / sign paint)."""
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.aux = self.bm.loops.layers.uv.new("aux")
        self.classes = []

    def ci(self, cls):
        if cls not in self.classes:
            self.classes.append(cls)
        return self.classes.index(cls)

    def face(self, verts, cls):
        f = self.bm.faces.new(verts)
        f.material_index = self.ci(cls)
        for l in f.loops:
            l[self.aux].uv = (5.0, 5.0)          # far outside the paint image / ring centre
        return f

    def set_aux(self, f, fn):
        for l in f.loops:
            l[self.aux].uv = fn(l.vert.co)

    def loft(self, rings, cls, closed=True, cap0=None, cap1=None):
        rows = [[self.bm.verts.new(p) for p in r] for r in rings]
        n = len(rings[0])
        side = []
        for i in range(len(rows) - 1):
            for j in range(n if closed else n - 1):
                c = cls(i, j) if callable(cls) else cls
                side.append(self.face((rows[i][j], rows[i][(j + 1) % n], rows[i + 1][(j + 1) % n], rows[i + 1][j]), c))
        caps = []
        if cap0:
            caps.append(self.face(list(reversed(rows[0])), cap0))
        if cap1:
            caps.append(self.face(rows[-1], cap1))
        return rows, side, caps

    def obj(self):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for c in self.classes:
            me.materials.append(mat(c))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        for p in me.polygons:
            p.use_smooth = True
        return ob


def frame(d):
    d = d.normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    s = d.cross(up).normalized()
    return s, s.cross(d).normalized()


def tube(P, pts, radius, segs, cls, cap=None, profile=None, twist=0.0, rough=0.0, seed=0):
    """Tube along a polyline; radius may be a function of t (0..1); profile(a) -> radial multiplier; caps get ring aux UV."""
    rings = []
    frames = []
    for i, p in enumerate(pts):
        t = i / (len(pts) - 1)
        d = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        s, u = frame(d)
        r = radius(t) if callable(radius) else radius
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs + twist
            m = profile(a) if profile else 1.0
            if rough:
                m *= 1.0 + rough * noise.noise(Vector((p.x * 7 + seed, p.y * 7 + k * 0.7, p.z * 7)))
            ring.append(p + (s * math.cos(a) + u * math.sin(a)) * r * m)
        rings.append(ring)
        frames.append((p, s, u))
    rows, side, caps = P.loft(rings, cls, True, cap, cap)
    if cap:
        for f, (p, s, u) in zip(caps, (frames[0], frames[-1])):
            P.set_aux(f, lambda co, p=p, s=s, u=u: ((co - p).dot(s), (co - p).dot(u)))
    return rows, side, caps


def box(P, c, size, cls, bevel=0.0, jitter=0.0, rot=None):
    """Axis box (with optional chamfer on the 4 long edges via an 8-gon section along X)."""
    sx, sy, sz = size[0] / 2, size[1] / 2, size[2] / 2
    b = min(bevel, sy * 0.8, sz * 0.8)
    sec = [(-sy + b, -sz), (sy - b, -sz), (sy, -sz + b), (sy, sz - b), (sy - b, sz), (-sy + b, sz), (-sy, sz - b), (-sy, -sz + b)] if b > 0 \
        else [(-sy, -sz), (sy, -sz), (sy, sz), (-sy, sz)]
    R = rot or Matrix.Identity(3)
    rings = []
    for x in (-sx, sx):
        rings.append([c + R @ Vector((x, y + random.uniform(-jitter, jitter), z + random.uniform(-jitter, jitter))) for y, z in sec])
    return P.loft(rings, cls, True, cls, cls)


# ------------------------------------------------------------------ assets
def bench_hewn():
    reset(11)
    P = Part("bench_hewn")
    L, W, T, H = 1.80, 0.32, 0.085, 0.45
    rings = []
    st = 28
    prof = 12
    for i in range(st + 1):
        x = -L / 2 + L * i / st
        w = W / 2 * (1 + 0.04 * noise.noise(Vector((x * 2.0, 0.3, 0.1))))
        ring = []
        # flat top (split face) from -w..w, rounded underside (half log, slightly flattened) with wane
        for k in range(prof):
            a = math.pi * k / (prof - 1)            # 0..pi under the seat
            y = math.cos(a) * w
            z = H - math.sin(a) * T * (1.0 + 0.08 * noise.noise(Vector((x * 4, a, 0.0))))
            ring.append(Vector((x, y, z)))
        rings.append(ring)
    # top face is the closing edge between the last and first profile points (flat): cls per strip
    rows, side, caps = P.loft(rings, lambda i, j: "wood_grey" if j == prof - 1 else ("bark" if 3 <= j <= prof - 5 else "wood_grey"),
                              True, "endgrain", "endgrain")
    for f in caps:
        cx = f.calc_center_median()
        P.set_aux(f, lambda co, cx=cx: (co.y * 0.9, co.z - H + T * 1.2))
    # legs: 4 round legs splayed 10 deg outward in X and 14 deg in Y, through-wedged (tops flush with the seat)
    for sx in (-1, 1):
        for sy in (-1, 1):
            top = Vector((sx * 0.66, sy * 0.075, H + 0.004))
            foot = top + Vector((sx * math.tan(math.radians(10)) * H, sy * math.tan(math.radians(14)) * H, -H - 0.004))
            pts = [top.lerp(foot, t) for t in np.linspace(0, 1, 6)]
            tube(P, pts, lambda t: 0.034 - 0.006 * t, 9, "wood_oak", cap="endgrain", rough=0.08, seed=sx * 3 + sy)
            # the wedge in the leg top (darker sliver across the end grain)
            wc = top + Vector((0, 0, 0.0005))
            box(P, wc, (0.06, 0.008, 0.002), "wood_dark")
    return [P.obj()], 1024


def trough_granite():
    reset(12)
    L, W, H, wall, floor_t = 2.0, 0.7, 0.6, 0.12, 0.14
    bpy.ops.mesh.primitive_cube_add(size=1)
    ob = bpy.context.active_object
    ob.name = "trough_granite"
    ob.scale = (L, W, H)
    ob.location = (0, 0, H / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # the basin: boolean out a tapered block (wider at the top, as carved)
    bpy.ops.mesh.primitive_cube_add(size=1)
    cut = bpy.context.active_object
    cut.scale = (L - 2 * wall, W - 2 * wall, H)
    cut.location = (0, 0, floor_t + H / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for v in cut.data.vertices:
        if v.co.z < floor_t + 0.01:
            v.co.x *= 0.95
            v.co.y *= 0.85
    bo = ob.modifiers.new("cut", "BOOLEAN")
    bo.operation = "DIFFERENCE"
    bo.object = cut
    bo.solver = "EXACT"
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="cut")
    bpy.data.objects.remove(cut)
    # chipped arrises: knock a few irregular lumps off edges and corners (low-poly icospheres, exact boolean = crisp breaks)
    chips = [(0.99, 0.35, 0.60, 0.05), (-1.0, -0.35, 0.60, 0.04), (0.35, -0.35, 0.60, 0.03), (-0.62, 0.35, 0.60, 0.025),
             (-1.0, 0.35, 0.02, 0.05), (1.0, -0.35, 0.3, 0.03), (0.0, 0.23, 0.60, 0.022)]
    for k, (cx, cy, cz, rr) in enumerate(chips):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=rr, location=(cx, cy, cz))
        ch = bpy.context.active_object
        ch.scale = (random.uniform(0.8, 1.6), random.uniform(0.7, 1.3), random.uniform(0.5, 1.0))
        ch.rotation_euler = (random.uniform(0, 3), random.uniform(0, 3), random.uniform(0, 3))
        bo = ob.modifiers.new("chip%d" % k, "BOOLEAN")
        bo.operation = "DIFFERENCE"
        bo.object = ch
        bo.solver = "EXACT"
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=bo.name)
        bpy.data.objects.remove(ch)
    # crisp, small arris bevel (hewn granite: sharp but not CG-perfect)
    md = ob.modifiers.new("bev", "BEVEL")
    md.width = 0.007
    md.segments = 2
    md.limit_method = "ANGLE"
    md.angle_limit = math.radians(40)
    bpy.ops.object.modifier_apply(modifier="bev")
    # subdivide flat faces a little so AO/grime/moss have vertices to live on, then a 2 mm out-of-true wobble (hand dressing)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    long_e = [e for e in bm.edges if e.calc_length() > 0.12]
    bmesh.ops.subdivide_edges(bm, edges=long_e, cuts=3, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    for v in bm.verts:
        v.co += Vector((noise.noise(v.co * 2.5), noise.noise(v.co * 2.5 + Vector((5, 0, 0))), 0)) * 0.002
    bm.to_mesh(ob.data)
    bm.free()
    me = ob.data
    me.materials.clear()                   # the boolean leaves an empty slot behind
    me.materials.append(mat("granite"))
    for p in me.polygons:
        p.material_index = 0
    me.uv_layers.new(name="aux")
    for p in me.polygons:
        p.use_smooth = True
    # water plane (own material, not baked), 8 cm below the rim
    zw = H - 0.08
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, zw))
    wo = bpy.context.active_object
    wo.name = "water"
    # inner opening at that height (the basin walls taper): measure the cavity
    inner = [v.co for v in me.vertices if abs(v.co.z - zw) < 0.02 and abs(v.co.x) < L / 2 - wall * 0.5 and abs(v.co.y) < W / 2 - wall * 0.5]
    ix = max(abs(c.x) for c in inner) if inner else L / 2 - wall
    iy = max(abs(c.y) for c in inner) if inner else W / 2 - wall
    wo.scale = (ix * 2 + 0.01, iy * 2 + 0.01, 1)
    bpy.ops.object.transform_apply(scale=True)
    wo.data.materials.append(mat("water"))
    return [ob], 1024, wo


def make_paint(w_m, h_m, res=1024):
    """Sign paint: burgundy field, ochre border, a foaming tankard (cream/ochre with dark outline). RGBA, alpha = paint."""
    hpx = int(res * h_m / w_m)
    xs = (np.arange(res) + 0.5) / res * w_m
    zs = (np.arange(hpx) + 0.5) / hpx * h_m
    X, Z = np.meshgrid(xs, zs)
    img = np.zeros((hpx, res, 4), dtype=np.float32)

    def put(mask, col):
        img[mask, :3] = col
        img[mask, 3] = 1.0
    def rrect(m, r):
        dx = np.maximum(np.abs(X - w_m / 2) - (w_m / 2 - m - r), 0)
        dz = np.maximum(np.abs(Z - h_m / 2) - (h_m / 2 - m - r), 0)
        return np.hypot(dx, dz) < r
    put(rrect(0.022, 0.03), (0.62, 0.45, 0.16))          # ochre border
    put(rrect(0.040, 0.02), (0.27, 0.055, 0.045))        # burgundy field
    put(rrect(0.048, 0.015) & ~rrect(0.052, 0.012), (0.55, 0.40, 0.15))   # thin inner gold line
    cx, z0, z1 = w_m * 0.46, h_m * 0.17, h_m * 0.66
    t = np.clip((Z - z0) / (z1 - z0), 0, 1)
    half = 0.085 - 0.012 * t
    body = (np.abs(X - cx) < half) & (Z > z0) & (Z < z1)
    # handle: a ring to the right of the body
    hc = (cx + 0.085, (z0 + z1) / 2 + 0.01)
    dd = np.hypot((X - hc[0]) * 1.0, (Z - hc[1]) * 0.8)
    handle = (dd > 0.045) & (dd < 0.075) & (X > cx + 0.06)
    foam = np.zeros_like(body)
    for fx, fz, fr in ((-0.06, 0.012, 0.034), (-0.02, 0.025, 0.04), (0.03, 0.02, 0.037), (0.07, 0.008, 0.028), (0.0, 0.0, 0.03)):
        foam |= np.hypot(X - (cx + fx), Z - (z1 + fz)) < fr
    drip = (np.abs(X - (cx + 0.05)) < 0.012) & (Z > z1 - 0.07) & (Z < z1)
    shape = body | handle | foam | drip
    # dark outline = dilate the shape by ~6 mm
    out = np.zeros_like(shape)
    k = max(2, int(0.006 / w_m * res))
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            if dx * dx + dy * dy <= k * k:
                out |= np.roll(np.roll(shape, dy, 0), dx, 1)
    put(out, (0.06, 0.035, 0.025))
    put(body | handle, (0.74, 0.52, 0.22))
    # body shading: darker toward the edges (painted volume), staves and two dark hoops
    sh = np.clip(1.0 - (np.abs(X - cx) / 0.09) ** 2 * 0.45, 0.5, 1.0)
    img[body, :3] *= sh[body, None]
    stave = body & (np.abs(((X - cx) / 0.028) % 1.0 - 0.5) < 0.06)
    put(stave, (0.48, 0.32, 0.13))
    for hz in (z0 + 0.06, z1 - 0.07):
        put(body & (np.abs(Z - hz) < 0.012), (0.18, 0.12, 0.08))
    put(foam | drip, (0.86, 0.82, 0.70))
    img[foam, :3] *= np.clip(0.8 + (Z[foam] - z1) * 4.0, 0.75, 1.0)[:, None]
    im = bpy.data.images.new("sign_paint", res, hpx, alpha=True)
    im.pixels.foreach_set(img.ravel())
    im.pack()
    return im


def tavern_sign():
    global PAINT
    reset(13)
    BW, BH, BT = 0.75, 0.50, 0.04
    PAINT = make_paint(BW, BH)
    P = Part("tavern_sign")
    iron = "iron"
    # wall plate (vertical flat bar) at x = 0..0.012, from z = -0.42 .. 0.06, two nail heads
    box(P, Vector((0.006, 0, -0.18)), (0.48, 0.06, 0.012), iron, bevel=0.003, rot=Matrix.Rotation(math.pi / 2, 3, "Y"))
    for zn in (0.02, -0.38):
        tube(P, [Vector((0.012, 0, zn)), Vector((0.022, 0, zn))], 0.009, 6, iron, cap=iron)
    # arm: square bar 2.2 cm from the plate to x = 1.05, ending in a small curl
    arm = [Vector((0.01 + 1.04 * t, 0, 0.0)) for t in np.linspace(0, 1, 12)]
    curl = [Vector((1.05 + 0.04 * math.sin(a), 0, 0.04 - 0.04 * math.cos(a) * 1.0 - 0.0)) for a in np.linspace(0, 1.6 * math.pi, 14)]
    curl = [Vector((1.05 + 0.035 * math.sin(a), 0, 0.035 - 0.035 * math.cos(a))) for a in np.linspace(0.2, 1.75 * math.pi, 14)]
    tube(P, arm + curl[1:], lambda t: 0.011 * (1 - 0.35 * max(0, t - 0.7) / 0.3), 4, iron, cap=iron, twist=math.pi / 4)
    # brace: from the plate bottom sweeping up to the arm at x = 0.62 (a quarter-ellipse), then a scroll inside the corner
    br = [Vector((0.012 + 0.6 * (1 - math.cos(a)), 0, -0.40 + 0.40 * math.sin(a))) for a in np.linspace(0, math.pi / 2, 16)]
    tube(P, br, 0.008, 4, iron, cap=iron, twist=math.pi / 4)
    sc = []
    for a in np.linspace(0, 3.3 * math.pi, 40):
        r = 0.012 + 0.0095 * a
        sc.append(Vector((0.21 + r * math.cos(a + math.pi), 0, -0.13 + r * math.sin(a + math.pi))))
    tube(P, sc[::-1], 0.0055, 4, iron, cap=iron, twist=math.pi / 4)
    # second small scroll near the arm tip
    sc2 = [Vector((0.80 + (0.008 + 0.006 * a) * math.cos(-a), 0, -0.045 + (0.008 + 0.006 * a) * math.sin(-a))) for a in np.linspace(0, 2.6 * math.pi, 26)]
    tube(P, sc2[::-1] + [Vector((0.80, 0, -0.011))], 0.0045, 4, iron, cap=iron)
    # hooks on the arm and eyes on the board, chains between
    cx0 = 0.62
    bx0, bz1 = cx0 - BW / 2, -0.33           # board left edge, board top
    for hx in (cx0 - BW / 2 + 0.08, cx0 + BW / 2 - 0.08):
        # hook ring around the arm
        ring = [Vector((hx, 0.017 * math.cos(a), -0.002 + 0.017 * math.sin(a))) for a in np.linspace(0, 2 * math.pi, 9)]
        tube(P, ring, 0.0035, 5, iron)
        # chain: oval links alternating 90 deg, from z = -0.02 down to the eye at the board top
        z = -0.022
        k = 0
        while z > bz1 + 0.03:
            Ln, Wd = 0.042, 0.022
            rot = (k % 2) * math.pi / 2
            pts = []
            for a in np.linspace(0, 2 * math.pi, 11):
                lx = math.cos(a) * Wd / 2
                lz = math.sin(a) * Ln / 2
                pts.append(Vector((hx + lx * math.cos(rot), lx * math.sin(rot), z - Ln / 2 + 0.004 + lz)))
            tube(P, pts, 0.0035, 5, iron)
            z -= Ln - 0.011
            k += 1
        # eye bolt in the board top
        eye = [Vector((hx, 0.0145 * math.cos(a), bz1 + 0.018 + 0.0145 * math.sin(a))) for a in np.linspace(0, 2 * math.pi, 9)]
        tube(P, eye, 0.0035, 5, iron)
        tube(P, [Vector((hx, 0, bz1 + 0.006)), Vector((hx, 0, bz1 - 0.03))], 0.005, 6, iron, cap=iron)
    # board: chamfered outline with a slightly shaped (ogee-ish) top edge, two planks with a faint seam
    outline = []
    for t in np.linspace(0, 1, 9):          # top edge, gentle arch
        outline.append((bx0 + 0.03 + (BW - 0.06) * t, bz1 + 0.012 * math.sin(math.pi * t)))
    outline = [(bx0, bz1 - 0.03)] + outline + [(bx0 + BW, bz1 - 0.03), (bx0 + BW, bz1 - BH + 0.03), (bx0 + BW - 0.03, bz1 - BH),
                                                (bx0 + 0.03, bz1 - BH), (bx0, bz1 - BH + 0.03)]
    outline = outline[::-1]
    front = [Vector((x, -BT / 2, z)) for x, z in outline]
    back = [Vector((x, BT / 2, z)) for x, z in outline]
    rows, side, caps = P.loft([front, back], "sign_board", True, "sign_board", "sign_board")
    zb = bz1 - BH
    for f in caps:
        is_front = f.calc_center_median().y < 0
        P.set_aux(f, lambda co, fr=is_front: (((co.x - bx0) / BW) if fr else (1 - (co.x - bx0) / BW), (co.z - zb) / BH))
    obs = [P.obj()]
    return obs, 1024


def barrel(P, c, L=0.86, R0=0.235, R1=0.29, staves=18):
    def rad(u):        # u in -1..1 along the barrel
        return R0 + (R1 - R0) * (1 - u * u)
    st = 10
    for s in range(staves):
        a0 = 2 * math.pi * s / staves + 0.004
        a1 = 2 * math.pi * (s + 1) / staves - 0.004
        dr = random.uniform(-0.002, 0.002)
        rings = []
        for i in range(st + 1):
            u = -1 + 2 * i / st
            y = u * L / 2
            r = rad(u) + dr
            th = 0.022
            ring = []
            for a, rr in ((a0, r), ((a0 + a1) / 2, r + 0.001), (a1, r), (a1, r - th), (a0, r - th)):
                ring.append(c + Vector((math.cos(a) * rr, y, math.sin(a) * rr)))
            rings.append(ring)
        P.loft(rings, "wood_oak", True, "endgrain", "endgrain")
    # heads (recessed 3.5 cm, the croze), made of 2 discs (inner faces never seen)
    for sgn in (-1, 1):
        y = sgn * (L / 2 - 0.035)
        r = R0 - 0.018
        ring = [c + Vector((math.cos(a) * r, y, math.sin(a) * r)) for a in np.linspace(0, 2 * math.pi, 20, endpoint=False)]
        ring2 = [p + Vector((0, -sgn * 0.02, 0)) for p in ring]
        rows, side, caps = P.loft([ring2, ring] if sgn > 0 else [ring, ring2], "wood_oak", True, "wood_dark", "wood_dark")
    # hoops: flat iron bands
    for u in (-0.86, -0.55, 0.55, 0.86):
        y = u * L / 2
        r = rad(u) + 0.0035
        w = 0.034 if abs(u) > 0.7 else 0.03
        segs = 36
        rings = []
        for k, (dy, dr) in enumerate(((-w / 2, 0), (w / 2, 0), (w / 2, 0.004), (-w / 2, 0.004))):
            pass
        sec = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, 0.0045), (-w / 2, 0.0045)]
        rings = [[c + Vector((math.cos(a) * (r + dr), y + dy, math.sin(a) * (r + dr))) for dy, dr in sec]
                 for a in np.linspace(0, 2 * math.pi, segs, endpoint=False)]
        n = len(rings)
        rows = [[P.bm.verts.new(p) for p in rg] for rg in rings]
        for i in range(n):
            for j in range(4):
                P.face((rows[i][j], rows[i][(j + 1) % 4], rows[(i + 1) % n][(j + 1) % 4], rows[(i + 1) % n][j]), "iron")


def barrel_rack():
    reset(14)
    P = Part("barrel_rack")
    rail_top = 0.30
    xs = (-0.64, 0.0, 0.64)
    for x in xs:
        cz = rail_top + 0.267 - 0.004
        barrel(P, Vector((x, 0, cz)))
    # two hewn rails along X under the barrels at y = +-0.28, notched look via chamfer; 4 legs; 2 cross ties
    for y in (-0.28, 0.28):
        box(P, Vector((0, y, rail_top - 0.05)), (1.95, 0.10, 0.10), "wood_grey", bevel=0.012, jitter=0.004)
        for x in (-0.9, 0.9):
            box(P, Vector((x, y, (rail_top - 0.1) / 2)), (rail_top - 0.1, 0.10, 0.10), "wood_grey", bevel=0.01, jitter=0.004,
                rot=Matrix.Rotation(math.pi / 2, 3, "Y"))
        # chocks between barrels
        for x in (-0.32, 0.32, -0.96, 0.96):
            box(P, Vector((x, y, rail_top + 0.03)), (0.07, 0.09, 0.06), "wood_oak", bevel=0.01, jitter=0.003)
    for x in (-0.9, 0.9):
        box(P, Vector((x, 0, 0.09)), (0.66, 0.08, 0.08), "wood_grey", bevel=0.01, jitter=0.004, rot=Matrix.Rotation(math.pi / 2, 3, "Z"))
    return [P.obj()], 1024


def fence_wattle():
    """Dense hurdle: 7 stakes, ~36 courses of thin irregular hazel rods woven in and out, packed so nothing shows through at 3 m."""
    reset(15)
    P = Part("fence_wattle")
    n = 7
    xs = [-0.96 + 1.92 * i / (n - 1) + (random.uniform(-0.02, 0.02) if 0 < i < n - 1 else 0) for i in range(n)]
    sr = []
    for i, x in enumerate(xs):
        h = random.uniform(1.04, 1.12)
        r0 = random.uniform(0.024, 0.03)
        sr.append(r0)
        lean = Vector((random.uniform(-0.015, 0.015), random.uniform(-0.012, 0.012), 0))
        pts = [Vector((x, 0, -0.02)) + lean * t + Vector((0, 0, h * t)) for t in np.linspace(0, 1, 4)]
        rows, side, caps = tube(P, pts, lambda t, r0=r0: r0 - 0.004 * t, 6, "hazel", cap="endgrain", rough=0.06, seed=i)
        for v in rows[-1]:
            v.co.z += (v.co - pts[-1]).dot(Vector((1, 0.3, 0)).normalized()) * 0.6
    z = 0.05
    k = 0
    while z < 0.98:
        r = random.uniform(0.009, 0.015)
        z += r * 0.95                          # rods overlap their neighbours a little: no see-through gaps
        ph = 1 if k % 2 else -1
        x0 = -1.0 - random.uniform(0.0, 0.05)
        x1 = 1.0 + random.uniform(0.0, 0.06)
        steps = 13
        pts = []
        for sidx in range(steps + 1):
            t = sidx / steps
            x = x0 + (x1 - x0) * t
            # interpolate the stake index to get in-front / behind alternation
            u = (x - xs[0]) / (xs[-1] - xs[0]) * (n - 1)
            y = ph * math.cos(u * math.pi) * (0.026 + r) + random.uniform(-0.003, 0.003)
            pts.append(Vector((x, y, z + 0.008 * math.sin(x * 2.3 + k * 1.7) + random.uniform(-0.002, 0.002))))
        tube(P, pts, lambda t, r=r: r * (1.12 - 0.3 * t) if ph > 0 else r * (0.82 + 0.3 * t), 4, "hazel", cap="endgrain", seed=k,
             twist=random.uniform(0, 1.5))
        z += r * 0.95
        k += 1
    print("WATTLE courses", k, flush=True)
    return [P.obj()], 1024


def fence_post_rail():
    reset(16)
    P = Part("fence_post_rail")
    span = 2.4
    for x in (-span / 2, span / 2):
        # hewn post with a pyramid-cut top
        box(P, Vector((x, 0, 0.6)), (1.2, 0.12, 0.13), "wood_grey", bevel=0.018, jitter=0.005, rot=Matrix.Rotation(-math.pi / 2, 3, "Y"))
        apex = P.bm.verts.new(Vector((x + random.uniform(-0.01, 0.01), 0, 1.25)))
        top = [v for v in P.bm.verts if abs(v.co.z - 1.2) < 0.02 and abs(v.co.x - x) < 0.1]
        top.sort(key=lambda v: math.atan2(v.co.y, v.co.x - x))
        for f in [f for f in P.bm.faces if all(abs(v.co.z - 1.2) < 0.02 and abs(v.co.x - x) < 0.1 for v in f.verts)]:
            P.bm.faces.remove(f)
        for i in range(len(top)):
            P.face((top[i], top[(i + 1) % len(top)], apex), "wood_grey")
    # split rails (half-round, flat face down) passing through the posts with a slight sag
    for z in (0.45, 0.92):
        rings = []
        for i in range(17):
            t = i / 16
            x = -span / 2 - 0.2 + (span + 0.4) * t
            sag = -0.015 * math.sin(math.pi * t)
            ring = []
            for a in np.linspace(0, math.pi, 7):
                ring.append(Vector((x, math.cos(a) * 0.055, z + sag + math.sin(a) * 0.05 * (1 + 0.06 * noise.noise(Vector((x * 3, a, z)))))))
            rings.append(ring)
        P.loft(rings, lambda i, j: "wood_split" if j == 6 else "wood_grey", True, "endgrain", "endgrain")
    return [P.obj()], 1024


def haystack():
    reset(17)
    P = Part("haystack")
    R, Hc, Ht = 1.15, 0.95, 2.5

    def prof(z):
        if z < Hc:     # sides lean outward a little up to the eaves, small skirt at the foot
            return R * (0.86 + 0.14 * (z / Hc)) + 0.05 * max(0, 1 - z / 0.2)
        u = (z - Hc) / (Ht - Hc)
        return R * max(0.0, 1 - u ** 1.7) ** 0.62
    segs, st = 40, 24
    rings = []
    for i in range(st + 1):
        t = i / st
        z = Ht * t
        r = prof(z)
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            p = Vector((math.cos(a), math.sin(a), 0))
            lump = 1 + 0.06 * noise.noise(p * 2.2 + Vector((0, 0, z * 1.4))) + 0.025 * noise.noise(p * 7 + Vector((0, 0, z * 5)))
            ring.append(Vector((p.x * r * lump, p.y * r * lump, z)))
        rings.append(ring)
    rings[-1] = [Vector((0, 0, Ht))] * segs
    rows, side, caps = P.loft(rings, "straw", True, None, None)
    bmesh.ops.remove_doubles(P.bm, verts=P.bm.verts, dist=1e-4)
    # straw-rope weights over the top (follow the surface, 1.5 cm proud)
    for ang in (0.3, 0.3 + math.pi / 2):
        pts = []
        for z in list(np.linspace(Hc * 0.8, Ht, 14)) + list(np.linspace(Ht, Hc * 0.8, 14))[1:]:
            pass
        zs = list(np.linspace(Hc * 0.8, Ht - 0.02, 14))
        for sgn, seq in ((1, zs), (-1, zs[::-1])):
            for z in seq:
                rr = prof(z) * 1.02 + 0.01
                pts.append(Vector((math.cos(ang) * rr * sgn, math.sin(ang) * rr * sgn, z + (0.02 if z > Ht - 0.1 else 0))))
        pts = pts[:14] + pts[15:]
        # (left out: on the lumpy surface the ropes float in places; a bare rick reads better)
    # centre pole sticking out of the top
    tube(P, [Vector((0, 0, Ht - 0.3)), Vector((0.02, 0.01, Ht + 0.35))], lambda t: 0.04 - 0.012 * t, 7, "wood_grey", cap="endgrain", rough=0.08)
    return [P.obj()], 1024


def hay_bundle():
    reset(18)
    P = Part("hay_bundle")
    L, R = 0.85, 0.2
    rings = []
    st, segs = 16, 18
    for i in range(st + 1):
        u = -1 + 2 * i / st
        x = u * L / 2
        pinch = 1 - 0.18 * math.exp(-((abs(u) - 0.45) / 0.08) ** 2)       # where the bands tie it in
        flare = 1 + 0.12 * max(0, abs(u) - 0.8) / 0.2
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            m = (1 + 0.07 * noise.noise(Vector((x * 6, math.cos(a) * 2, math.sin(a) * 2)))) * pinch * flare
            ring.append(Vector((x, math.cos(a) * R * m, R * 0.92 + math.sin(a) * R * 0.92 * m)))
        rings.append(ring)
    P.loft(rings, "straw", True, "straw", "straw")
    for u in (-0.45, 0.45):
        x = u * L / 2
        pts = [Vector((x, math.cos(a) * R * 0.84, R * 0.92 + math.sin(a) * R * 0.78)) for a in np.linspace(0, 2 * math.pi, 21)]
        tube(P, pts, 0.012, 5, "rope")
    return [P.obj()], 1024


def billet(P, c, axis_len, r, a0, span, rough_seed):
    """A split firewood billet lying along Y: wedge section (pith at c), bark on the outer arc, ringed end grain."""
    n_arc = 5 if span > 1.6 else 4
    sec = []
    if span < 2 * math.pi - 0.1:
        sec.append((0.0, 0.0))
    for k in range(n_arc + 1):
        a = a0 + span * k / n_arc
        rr = r * (1 + 0.05 * noise.noise(Vector((a * 2, rough_seed, 0))))
        sec.append((math.cos(a) * rr, math.sin(a) * rr))
    rings = []
    for y in (-axis_len / 2 + random.uniform(-0.01, 0.01), axis_len / 2 + random.uniform(-0.01, 0.01)):
        rings.append([c + Vector((sx, y, sz)) for sx, sz in sec])
    nsec = len(sec)
    def cls(i, j):
        if span < 2 * math.pi - 0.1 and (j == nsec - 1 or j == 0):
            return "wood_split"
        return "bark"
    rows, side, caps = P.loft(rings, cls, True, "endgrain", "endgrain")
    for f in caps:
        P.set_aux(f, lambda co, c=c: (co.x - c.x, co.z - c.z))


def firewood_stack():
    reset(19)
    P = Part("firewood_stack")
    W, H, D = 1.5, 1.0, 0.42
    # sleepers
    for y in (-0.12, 0.12):
        tube(P, [Vector((-W / 2 - 0.08, y, 0.045)), Vector((W / 2 + 0.08, y, 0.05))], 0.045, 8, "bark", cap="endgrain", rough=0.06)
    z = 0.09
    row = 0
    while z < H - 0.05:
        x = -W / 2 + 0.06
        rh = random.uniform(0.09, 0.11)
        while x < W / 2 - 0.05:
            r = random.uniform(0.06, 0.09)
            kind = random.random()
            span = math.pi / 2 if kind < 0.45 else (math.pi if kind < 0.85 else 2 * math.pi)
            a0 = random.uniform(0, 2 * math.pi)
            # place the pith so the piece's bounding circle centre sits in the cell
            cx = math.cos(a0 + span / 2) * r * (0.45 if span < 6 else 0.0)
            cz = math.sin(a0 + span / 2) * r * (0.45 if span < 6 else 0.0)
            c = Vector((x + rh / 2 - cx, random.uniform(-0.03, 0.03), z + rh / 2 - cz))
            billet(P, c, D + random.uniform(-0.03, 0.03), r * (0.85 if span < 6 else 0.7), a0, span, random.random() * 10)
            x += rh * random.uniform(0.95, 1.1)
        z += rh * 0.93
        row += 1
    # end stakes holding the stack
    for x in (-W / 2 - 0.02, W / 2 + 0.02):
        for y in (-0.16, 0.16):
            tube(P, [Vector((x, y, 0.0)), Vector((x + random.uniform(-0.02, 0.02), y, H + 0.05))], lambda t: 0.035 - 0.008 * t, 7, "bark", cap="endgrain")
    return [P.obj()], 1024


ASSETS = {"bench_hewn": bench_hewn, "trough_granite": trough_granite, "tavern_sign": tavern_sign, "barrel_rack": barrel_rack,
          "fence_wattle": fence_wattle, "fence_post_rail": fence_post_rail, "haystack": haystack, "hay_bundle": hay_bundle,
          "firewood_stack": firewood_stack}


def build(name):
    res = ASSETS[name]()
    obs, tex = res[0], res[1]
    extra = res[2] if len(res) > 2 else None
    ob = RL.join(obs, name)
    if name != "tavern_sign":
        RL.origin_to_feet(ob)
        if extra:
            pass
    RL.smart_uv(ob, angle=60.0, margin=0.003)
    tmp = os.path.join(WORK, "bake_" + name)
    fm = RL.bake_asset(ob, tex, tmp, name)
    RL.finalize_materials(ob, fm)
    if extra is not None:
        extra.data.uv_layers.new(name="bake_uv")
        ob = RL.join([ob, extra], name)
    folder = os.path.join(OUT, name)
    RL.export_glb(ob, os.path.join(folder, name + ".glb"))
    RL.write_license(folder, name, "Geometry: built procedurally in Blender by tools/blender/props/build_village_props.py (project-owned).")
    bpy.data.objects.remove(ob)
    for g in list(bpy.data.node_groups):
        bpy.data.node_groups.remove(g)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name + ".glb"))
    new = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    gate = os.path.join(WORK, "gate")
    os.makedirs(gate, exist_ok=True)
    RL.render_view(new, os.path.join(gate, f"{name}_B_refined.jpg"))
    with open(os.path.join(WORK, "stats.txt"), "a") as f:
        mn, mx = RL.bbox_of(new)
        f.write(f"{name}\t{sum(RL.tri_count(o) for o in new)}\t{tex}\t{tuple(round(x, 2) for x in (mx - mn))}\n")
    shutil.rmtree(tmp, ignore_errors=True)


for n in (NAMES or list(ASSETS)):
    build(n)
print("DONE")
