"""Life-animation props for Rising Ashes villagers (Godot 4.6, mobile): 37 hand props
and 11 scene props, built with the shared prop kit (one "RA_Props" material = vertex
colour x the shared atlas kingdom/assets/generated/props/props_atlas.png).

Run headless (Blender 5.x), from the repo root:
    blender -b --python kingdom/tools/blender/make_life_props.py -- [names...] [--sheet] [--sheet-only]

- names: any of HAND / SCENE below (default: all).
- Outputs: kingdom/assets/generated/life_props/<name>.glb. The GLBs reference the atlas by the
  relative URI ../props/props_atlas.png (no per-folder copy, Godot shares one texture).
- --sheet / --sheet-only: render docs/anim/living_world/props_sheet.jpg (true-scale line-up with
  a 1.75 m human bar), props_grip.jpg (per-prop grip close-ups with an axis triad at the origin:
  X red, Y green, Z blue, yellow ball = grip_axis, cyan ball = front_axis from life_props.json)
  and props_scene.jpg.

GRIP CONTRACT (kingdom/data/living_world/life_props.json): every hand prop is modelled with the
point the fist closes around at the ORIGIN; grip_axis (thumb side, usually toward the working
end) and front_axis (along the knuckles) are native Blender axes (+Z up, front = -Y).
Scale: metres (adult villager 1.75 m). Hand props <= 350 tris, scene props <= 1500.
Scene props: origin at ground centre, front faces -Y.
"""
import os, sys, math, random, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
from mathutils import Vector, Matrix, Euler
import prop_kit
from prop_kit import (PK, ATLAS, fix_glb, OAK, OAK_DK, OAK_LT, PINE, BARK, ENDGRAIN, IRON_C, IRON_LT,
                      STONE_C, CANVAS, RED, ROPE, STRAW, SOIL, LEAF)
from ra_kit import hexc, vary, mix

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
LIFE_DIR = os.path.join(ROOT, "kingdom", "assets", "generated", "life_props")
DOC_DIR = os.path.join(ROOT, "docs", "anim", "living_world")
JSON_PATH = os.path.join(ROOT, "kingdom", "data", "living_world", "life_props.json")
SCRATCH = r"C:\Users\Jonna\AppData\Local\Temp\claude\life_props"
REPORT = os.path.join(SCRATCH, "_life_props_report.txt")
HAND_BUDGET, SCENE_BUDGET = 350, 1500
tau, pi = math.tau, math.pi

# ------------------------------------------------------------------ colours
STEEL = hexc("9aa2a8")
STEEL_DK = hexc("646b71")
GOLD = hexc("dcae3e")
HANDLE = hexc("bd925a")      # ash handles, warm and light so they read on grass
HANDLE_DK = hexc("8e6238")
LEATHER = hexc("8f5a30")
BREAD = hexc("d99b47")
WHEAT = hexc("e0b54f")
MILK = hexc("f6f0df")
WATER = hexc("68a8be")
SACK_C = hexc("c2a170")
BRASS = hexc("bb8f3c")


class LK(PK):
    """PK adapted to the current ra_kit (_merge grew a `subdiv` argument), no LOD split, no
    base grime (hand props are not ground-bound) and a single clean UV layer."""

    def __init__(self, name, seed=1, grime=0.0):
        super().__init__(name, seed)
        self.polish = False
        self.grime_amt = grime

    def _merge(self, *a, subdiv=False, **kw):
        return PK._merge(self, *a, **kw)

    def build_object(self):
        uvl = self.bm.loops.layers.uv
        if any(l.name == "UVMap" for l in uvl.values()) and len(uvl) > 1:
            uvl.remove(uvl["UVMap"])     # Kit's empty default layer; PK paints "UVMap.001"
        return PK.build_object(self)


# ------------------------------------------------------------------ helpers
def seg(k, a, b, r, mat, color, r2=None, segs=6, caps=True, var=0.04, smooth=None):
    """Round bar / cone from a to b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    rot = d.to_track_quat('Z', 'Y').to_euler()
    k.cyl(r, d.length, tuple(a), k.M(mat), color, rot=tuple(rot), segs=segs, r2=r2, caps=caps, var=var,
          smooth=smooth, grime=False)


def bx(k, size, loc, color, mat="Wood", rot=(0, 0, 0), bevel=0.0, var=0.04):
    k.box(size, loc, k.M(mat), color, rot=rot, bevel=bevel, var=var, grime=False)


def bar(k, a, b, w, d, color, mat="Wood", up=(1, 0, 0), bevel=0.0, var=0.04):
    k.bar(a, b, w, d, k.M(mat), color, up=up, bevel=bevel, var=var, grime=False)


def pr(k, pts, depth, loc, color, mat="Metal", rot=(0, 0, 0), bevel=0.0):
    """Flat prism: polygon (x, z) extruded along Y (thickness `depth`)."""
    k.prism(pts, depth, loc, k.M(mat), color, rot=rot, bevel=bevel, grime=False)


def side(k, pts, depth, loc, color, mat="Metal", rot=(0, 0, 0)):
    """Side-profile prism: polygon (fwd, up) with fwd = -Y (toward the front); thickness along X."""
    k.push(loc, rot)
    k.prism(pts, depth, (0, 0, 0), k.M(mat), color, rot=(0, 0, -pi / 2), grime=False)
    k.pop()


def blob(k, r, loc, color, mat="Cloth", scale=(1, 1, 1), subdiv=2, rot=(0, 0, 0), noise=0.0, var=0.05):
    k.sphere(r, loc, k.M(mat), color, scale=scale, subdiv=subdiv, var=var, rot=rot, noise_amt=noise, grime=False)


def lathe(k, prof, loc, color, mat="Wood", segs=10, smooth=45, rot=(0, 0, 0), color_fn=None, vfn=None, var=0.03):
    k.lathe(prof, loc, k.M(mat), color, segs=segs, smooth=smooth, rot=rot, color_fn=color_fn, vfn=vfn,
            grime=False, var=var)


def stave_fn(n, base, cx=0.0, cy=0.0):
    st = [vary(base, 0.1, 0.03) for _ in range(n)]

    def cf(f):
        c = f.calc_center_median()
        a = math.atan2(c.y - cy, c.x - cx) % tau
        return st[int(a / tau * n) % n]
    return cf


def handle(k, z0, z1, r=0.024, c=None, x=0.0, y=0.0, r2=None):
    seg(k, (x, y, z0), (x, y, z1), r, "Wood", c or HANDLE, r2=r2, segs=6)


def flat(k, x0, y0, x1, y1, z, color, mat="Matte"):
    """Up-facing quad on the ground plane (chalk, decals)."""
    t = bmesh.new()
    vs = [t.verts.new(p) for p in ((x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z))]
    t.faces.new(vs)
    bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
    for f in t.faces:
        if f.normal.z < 0:
            f.normal_flip()
    k._merge(t, k.M(mat), color, None, None, 0.0, None, False)


HAND, SCENE = {}, {}


def hand(fn):
    HAND[fn.__name__[2:]] = fn
    return fn


def scene(fn):
    SCENE[fn.__name__[2:]] = fn
    return fn


def fin(k, name, budget):
    prop_kit.OUT_DIR = LIFE_DIR
    os.makedirs(LIFE_DIR, exist_ok=True)
    line = k.finish_prop(name, budget, preview=False)
    path = os.path.join(LIFE_DIR, f"{name}.glb")
    retarget_uri(path)
    stray = os.path.join(LIFE_DIR, "props_atlas.png")
    if os.path.exists(stray):
        os.remove(stray)
    return line


def retarget_uri(path):
    """Point the atlas URI at the shared copy in ../props/ (one texture for every prop)."""
    import struct
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, total = struct.unpack_from("<III", data, 0)
    jlen, jtype = struct.unpack_from("<II", data, 12)
    js = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    for im in js.get("images", []):
        if im.get("uri") == "props_atlas.png":
            im["uri"] = "../props/props_atlas.png"
    jb = json.dumps(js, separators=(",", ":")).encode("utf-8")
    jb += b" " * ((4 - len(jb) % 4) % 4)
    out = struct.pack("<III", magic, ver, 12 + 8 + len(jb) + len(rest)) + struct.pack("<II", len(jb), jtype) + jb + rest
    with open(path, "wb") as f:
        f.write(out)


# ====================================================================== HAND PROPS
@hand
def p_hoe():
    k = LK("hoe", 101)
    # grip origin = the LOWER (right) hand, 0.5 m up from the butt, so the other hand can hold the butt end
    # 0.35-0.45 m behind it (a real hoeing grip); blade 0.85 m beyond the grip.
    handle(k, -0.50, 0.97, 0.025)
    seg(k, (0, 0, 0.85), (0, 0, 1.01), 0.036, "Metal", IRON_LT, r2=0.028)          # socket
    bar(k, (0, 0, 0.95), (0, -0.13, 0.91), 0.05, 0.035, IRON_LT, "Metal", up=(1, 0, 0))    # neck
    bx(k, (0.22, 0.17, 0.02), (0, -0.21, 0.885), STEEL, "Metal", rot=(0.28, 0, 0), bevel=0.004)  # blade
    bx(k, (0.22, 0.02, 0.03), (0, -0.125, 0.905), STEEL_DK, "Metal", rot=(0.28, 0, 0))     # blade rib
    return fin(k, "hoe", HAND_BUDGET)


@hand
def p_shovel():
    k = LK("shovel", 102)
    handle(k, -0.15, 0.9, 0.025)
    bx(k, (0.1, 0.04, 0.035), (0, 0, -0.15), HANDLE_DK)                             # butt knob
    seg(k, (0, 0, 0.82), (0, 0, 1.0), 0.038, "Metal", IRON_LT, r2=0.03)
    pts = [(-0.06, 0.95), (0.06, 0.95), (0.12, 1.06), (0.125, 1.18), (0.07, 1.31), (0, 1.35), (-0.07, 1.31),
           (-0.125, 1.18), (-0.12, 1.06)]
    pr(k, pts, 0.02, (0, 0, 0), STEEL)
    bx(k, (0.05, 0.03, 0.34), (0, -0.012, 1.14), STEEL_DK, "Metal")                   # centre rib
    bx(k, (0.1, 0.03, 0.03), (0, -0.012, 0.99), STEEL_DK, "Metal")
    return fin(k, "shovel", HAND_BUDGET)


@hand
def p_rake():
    k = LK("rake", 103)
    handle(k, -0.15, 1.34, 0.025)
    bx(k, (0.56, 0.04, 0.05), (0, 0, 1.36), HANDLE_DK, bevel=0.005)
    for sx in (-1, 1):
        seg(k, (0, 0, 1.08), (sx * 0.15, 0, 1.33), 0.014, "Wood", HANDLE_DK, segs=4)
    for i in range(7):
        x = -0.24 + i * 0.08
        seg(k, (x, -0.03, 1.365), (x, -0.23, 1.30), 0.016, "Metal", STEEL_DK, r2=0.006, segs=4, caps=False)
    return fin(k, "rake", HAND_BUDGET)


@hand
def p_pitchfork():
    k = LK("pitchfork", 104)
    handle(k, -0.15, 1.2, 0.025)
    seg(k, (0, 0, 1.1), (0, 0, 1.3), 0.036, "Metal", IRON_LT, r2=0.03)
    bx(k, (0.3, 0.035, 0.04), (0, 0, 1.33), IRON_LT, "Metal")
    for sx in (-1, 1):
        seg(k, (sx * 0.135, 0, 1.33), (sx * 0.14, 0, 1.5), 0.02, "Metal", STEEL, r2=0.018, segs=4, caps=False)
        seg(k, (sx * 0.14, 0, 1.5), (sx * 0.125, 0, 1.68), 0.018, "Metal", STEEL, r2=0.004, segs=4, caps=False)
    seg(k, (0, 0, 1.33), (0, 0, 1.72), 0.021, "Metal", STEEL, r2=0.004, segs=4, caps=False)
    return fin(k, "pitchfork", HAND_BUDGET)


@hand
def p_sickle():
    k = LK("sickle", 105)
    handle(k, -0.13, 0.15, 0.028, r2=0.024)
    seg(k, (0, 0, 0.11), (0, 0, 0.2), 0.03, "Metal", IRON_LT, r2=0.022)
    bx(k, (0.06, 0.06, 0.03), (0, 0, -0.13), HANDLE_DK)
    cx, cz, R = 0.165, 0.2, 0.17
    n = 9
    outer, inner = [], []
    for i in range(n):
        t = i / (n - 1)
        th = math.radians(195 - 232 * t)
        w = 0.06 * (1 - t) + 0.005
        outer.append((cx + R * math.cos(th), cz + R * math.sin(th)))
        inner.append((cx + (R - w) * math.cos(th), cz + (R - w) * math.sin(th)))
    side(k, outer + inner[::-1][1:], 0.016, (0, 0, 0), STEEL)
    return fin(k, "sickle", HAND_BUDGET)


@hand
def p_seed_bag():
    k = LK("seed_bag", 106)
    prof = [(0, -0.31), (0.08, -0.3), (0.14, -0.235), (0.16, -0.15), (0.125, -0.08), (0.06, -0.035), (0.04, -0.015)]
    off = random.uniform(0, 50)

    def vfn(v):
        v.x *= 1.05
        v.y *= 0.95
        return v
    lathe(k, prof, (0, 0, 0), SACK_C, "Cloth", segs=9, smooth=80, vfn=vfn)
    seg(k, (0, 0, -0.012), (0, 0, 0.075), 0.045, "Cloth", mix(SACK_C, (0.3, 0.2, 0.1), 0.1), r2=0.085, segs=7)
    seg(k, (0, 0, -0.05), (0, 0, -0.012), 0.062, "Cloth", ROPE, segs=7, caps=False)
    bx(k, (0.1, 0.012, 0.1), (0, -0.155, -0.17), RED, "Cloth", rot=(0.12, 0, 0.15))        # patch
    for i in range(5):                                                                        # seeds in the mouth
        blob(k, 0.016, (random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), 0.075), WHEAT, "Plant", subdiv=1)
    return fin(k, "seed_bag", HAND_BUDGET)


@hand
def p_sheaf():
    k = LK("sheaf", 107)
    rng = random.Random(7)
    n = 10
    for i in range(n):
        a = i * 2.39996
        rr = 0.6 + 0.4 * ((i * 0.618) % 1.0)
        d = Vector((math.cos(a), math.sin(a), 0))
        b0 = d * 0.085 * rr
        mid = d * 0.035 * rr
        top = d * (0.12 * rr)
        c = vary(WHEAT, 0.1, 0.03)
        seg(k, (b0.x, b0.y, -0.32), (mid.x, mid.y, 0.0), 0.015, "Thatch", c, r2=0.012, segs=3, caps=False)
        seg(k, (mid.x, mid.y, 0.0), (top.x, top.y, 0.28 + 0.03 * rr), 0.012, "Thatch", c, r2=0.010, segs=3, caps=False)
        e0 = Vector((top.x, top.y, 0.28 + 0.03 * rr))
        seg(k, tuple(e0), (top.x * 1.08, top.y * 1.08, e0.z + 0.11), 0.026, "Thatch", vary(hexc("e8c55e"), 0.08),
            r2=0.004, segs=4, caps=False)
    seg(k, (0, 0, -0.045), (0, 0, 0.045), 0.062, "Cloth", ROPE, segs=8, caps=False)
    return fin(k, "sheaf", HAND_BUDGET)


def pail(k, name, h, rt, rb, rimz, fillc, wood, hoop_n, rope_bail):
    z0 = rimz - h
    fz = rimz - 0.05

    def rad(z):
        return rb + (rt - rb) * (z - z0) / h
    prof = [(0, z0), (rb, z0), (rt, rimz), (rt - 0.014, rimz), (rt - 0.016, fz)]
    n = 8
    lathe(k, prof, (0, 0, 0), wood, "Wood", segs=n, smooth=40, color_fn=stave_fn(n, wood))
    seg(k, (0, 0, fz - 0.002), (0, 0, fz + 0.006), rt - 0.016, "Water", fillc, segs=n, var=0.02)
    for i in range(hoop_n):
        z = z0 + h * (0.14 + 0.62 * i / max(1, hoop_n - 1)) if hoop_n > 1 else z0 + h * 0.3
        r = rad(z) + 0.006
        lathe(k, [(r - 0.004, z - 0.02), (r + 0.006, z - 0.014), (r + 0.006, z + 0.014), (r - 0.004, z + 0.02)],
              (0, 0, 0), IRON_LT, "Metal", segs=n, smooth=None)
    # ears + bail
    for sx in (-1, 1):
        bx(k, (0.03, 0.04, 0.05), (sx * (rt + 0.006), 0, rimz - 0.05), IRON_LT, "Metal")
    pts = [(-rt - 0.01, 0, rimz - 0.05), (-rt * 0.85, 0, rimz + 0.05), (-rt * 0.5, 0, rimz + 0.12),
           (0, 0, 0.0), (rt * 0.5, 0, rimz + 0.12), (rt * 0.85, 0, rimz + 0.05), (rt + 0.01, 0, rimz - 0.05)]
    pts[3] = (0, 0, rimz + 0.15)
    top = rimz + 0.15
    # shift everything so the bail apex is the origin: done by caller through rimz choice
    k.tube(pts, [0.011] * 7, k.M("Metal") if not rope_bail else k.M("Cloth"), IRON_LT if not rope_bail else ROPE,
           segs=4, cap_start=True, point_end=False, smooth=None, var=0.02)


@hand
def p_milk_pail():
    k = LK("milk_pail", 108)
    pail(k, "milk", 0.27, 0.125, 0.10, -0.15, MILK, hexc("c9a06a"), 2, False)
    return fin(k, "milk_pail", HAND_BUDGET)


@hand
def p_bucket():
    k = LK("bucket", 109)
    pail(k, "bucket", 0.34, 0.15, 0.115, -0.15, WATER, hexc("9a6a3e"), 3, True)
    return fin(k, "bucket", HAND_BUDGET)


def bowl(k, fillc, fill_kind, wood):
    # bowl centre 0.13 m behind the grip (+Y); rim at z=+0.05
    R = 0.135
    prof = [(0, -0.065), (0.06, -0.065), (0.1, -0.035), (R, 0.05), (R - 0.016, 0.05), (R - 0.03, 0.012),
            (0.06, -0.03), (0, -0.03)]
    lathe(k, prof, (0, 0.13, 0), wood, "Wood", segs=10, smooth=45)
    lathe(k, [(R - 0.006, 0.048), (R + 0.004, 0.052), (R + 0.004, 0.046)], (0, 0.13, 0), hexc("6b4426"), "Wood",
          segs=10, smooth=None)
    if fill_kind == "grain":
        blob(k, 0.12, (0, 0.13, 0.02), fillc, "Thatch", scale=(1, 1, 0.42), subdiv=2, noise=0.01)
    else:
        seg(k, (0, 0.13, 0.026), (0, 0.13, 0.036), R - 0.03, "Water", fillc, segs=10)


@hand
def p_grain_bowl():
    k = LK("grain_bowl", 110)
    bowl(k, WHEAT, "grain", hexc("b98a52"))
    return fin(k, "grain_bowl", HAND_BUDGET)


@hand
def p_bowl():
    k = LK("bowl", 111)
    bowl(k, hexc("c4762c"), "soup", hexc("8f6238"))
    for i in range(4):
        blob(k, 0.015, (random.uniform(-0.05, 0.05), 0.13 + random.uniform(-0.05, 0.05), 0.04), hexc("6f9a3a"),
             "Plant", subdiv=1)
    return fin(k, "bowl", HAND_BUDGET)


@hand
def p_smith_hammer():
    k = LK("smith_hammer", 112)
    handle(k, -0.16, 0.36, 0.028, c=hexc("a9784a"), r2=0.024)
    bx(k, (0.1, 0.2, 0.1), (0, -0.005, 0.42), STEEL_DK, "Metal", bevel=0.012)            # head block
    bx(k, (0.11, 0.028, 0.11), (0, -0.115, 0.42), STEEL, "Metal", bevel=0.006)          # striking face
    seg(k, (0, 0.09, 0.42), (0, 0.19, 0.42), 0.045, "Metal", STEEL_DK, r2=0.012, segs=4, rot=None) if False else None
    side(k, [(-0.09, 0.375), (-0.09, 0.465), (-0.19, 0.44), (-0.19, 0.4)], 0.07, (0, 0, 0), STEEL_DK)   # peen
    return fin(k, "smith_hammer", HAND_BUDGET)


@hand
def p_tongs():
    k = LK("tongs", 113)
    for s in (-1, 1):
        bar(k, (s * 0.07, 0, -0.27), (0, 0, 0.06), 0.032, 0.026, IRON_LT, "Metal")
        bar(k, (0, 0, 0.06), (-s * 0.03, 0, 0.2), 0.036, 0.026, IRON_LT, "Metal")
        bar(k, (-s * 0.03, 0, 0.2), (-s * 0.008, 0, 0.42), 0.036, 0.03, STEEL_DK, "Metal")
        seg(k, (s * 0.07, 0, -0.27), (s * 0.075, 0, -0.29), 0.022, "Metal", IRON_LT, segs=5)
    seg(k, (0, -0.02, 0.06), (0, 0.02, 0.06), 0.028, "Metal", STEEL, segs=6, rot=None) if False else None
    bx(k, (0.04, 0.05, 0.04), (0, 0, 0.06), STEEL, "Metal")
    return fin(k, "tongs", HAND_BUDGET)


@hand
def p_hammer():
    k = LK("hammer", 114)
    handle(k, -0.13, 0.27, 0.023, r2=0.02)
    side(k, [(0.065, 0.245), (0.065, 0.335), (0.02, 0.34), (-0.05, 0.335), (-0.13, 0.30), (-0.16, 0.255),
             (-0.13, 0.26), (-0.06, 0.29), (-0.02, 0.28), (-0.02, 0.245)], 0.045, (0, 0, 0), STEEL)
    bx(k, (0.05, 0.05, 0.14), (0, 0, 0.29), STEEL_DK, "Metal")
    bx(k, (0.048, 0.02, 0.11), (0, -0.07, 0.29), STEEL_DK, "Metal")                        # face ring
    return fin(k, "hammer", HAND_BUDGET)


@hand
def p_saw():
    k = LK("saw", 115)
    # pistol grip (side profile, fwd = -Y)
    side(k, [(-0.06, -0.14), (-0.06, 0.07), (0.075, 0.07), (0.075, -0.01), (0.045, -0.01), (0.045, -0.14)],
         0.034, (0, 0, 0), hexc("a7703f"), "Wood")
    n = 7
    pts = [(-0.05, 0.075), (-0.05, 0.6)]
    front = [(0.075, 0.075)]
    for i in range(n):
        z = 0.075 + (0.60 - 0.075) * i / n
        zn = 0.075 + (0.60 - 0.075) * (i + 1) / n
        w0 = 0.075 - 0.05 * (z - 0.075) / 0.525
        w1 = 0.075 - 0.05 * (zn - 0.075) / 0.525
        front += [(w0 + 0.022, z + 0.005), (w1, zn)]
    front.append((0.02, 0.6))
    poly = [(-0.05, 0.075)] + [(-0.03, 0.6)] + front[::-1][:0] + list(reversed(front))
    poly = [(-0.05, 0.075), (-0.03, 0.6)] + list(reversed(front))
    side(k, poly, 0.008, (0, 0, 0), STEEL)
    bx(k, (0.012, 0.05, 0.035), (0, 0.0, 0.085), STEEL_DK, "Metal")
    return fin(k, "saw", HAND_BUDGET)


@hand
def p_plank():
    k = LK("plank", 116)
    bx(k, (0.2, 0.03, 2.4), (0, 0, 0), hexc("c69a5f"), "Wood", bevel=0.004, var=0.02)
    for z, x in ((0.55, -0.04), (-0.7, 0.05), (0.98, 0.03)):
        seg(k, (x, -0.0155, z), (x, -0.0175, z), 0.026, "Wood", hexc("7a5230"), segs=6, rot=None) if False else None
        bx(k, (0.05, 0.004, 0.07), (x, -0.017, z), hexc("7b5332"), "Wood", var=0.02)
    return fin(k, "plank", HAND_BUDGET)


@hand
def p_axe():
    k = LK("axe", 117)
    handle(k, -0.5, 0.44, 0.026, c=hexc("b98e58"), r2=0.022)
    side(k, [(-0.05, 0.27), (-0.05, 0.43), (0.03, 0.44), (0.1, 0.5), (0.175, 0.53), (0.175, 0.17), (0.1, 0.22),
             (0.03, 0.26)], 0.035, (0, 0, 0), STEEL)
    bx(k, (0.055, 0.1, 0.14), (0, 0, 0.35), STEEL_DK, "Metal", bevel=0.005)                # eye block
    side(k, [(0.15, 0.53), (0.175, 0.53), (0.175, 0.17), (0.15, 0.19)], 0.012, (0, 0, 0), hexc("c9d0d4"))   # bright edge
    return fin(k, "axe", HAND_BUDGET)


@hand
def p_fishing_rod():
    k = LK("fishing_rod", 118)
    seg(k, (0, 0, -0.42), (0, 0, 0.16), 0.03, "Wood", hexc("d2ae74"), segs=6)           # cork grip
    pts = [(0, 0, 0.16), (0, -0.01, 0.7), (0, -0.05, 1.2), (0, -0.14, 1.7), (0, -0.28, 2.1)]
    k.tube(pts, [0.017, 0.013, 0.009, 0.006, 0.004], k.M("Wood"), hexc("8a5a30"), segs=5, cap_start=True,
           point_end=True, smooth=None, var=0.02)
    seg(k, (-0.045, 0.045, 0.12), (0.045, 0.045, 0.12), 0.05, "Metal", IRON_LT, segs=8)      # reel
    seg(k, (0, 0.02, 0.12), (0, 0.06, 0.12), 0.02, "Metal", STEEL, segs=5, rot=None) if False else None
    tip = (0, -0.28, 2.1)
    seg(k, tip, (0, -0.28, 1.6), 0.0045, "Cloth", hexc("ece6d2"), segs=3, caps=False, var=0.0)   # line
    lathe(k, [(0, 1.535), (0.032, 1.56), (0.04, 1.6), (0.03, 1.64), (0, 1.69)], (0, -0.28, 0), RED, "Plant",
          segs=7, smooth=60)
    seg(k, (0, -0.28, 1.535), (0, -0.28, 1.5), 0.007, "Metal", STEEL, segs=3)
    return fin(k, "fishing_rod", HAND_BUDGET)


@hand
def p_ladle():
    k = LK("ladle", 119)
    seg(k, (0, 0, -0.22), (0, 0, 0.3), 0.02, "Wood", HANDLE_DK, r2=0.016, segs=5)
    bx(k, (0.03, 0.03, 0.04), (0, 0, -0.22), HANDLE_DK)
    prof = [(0, -0.062), (0.035, -0.055), (0.062, -0.02), (0.07, 0.03), (0.058, 0.03), (0.05, 0.0), (0.03, -0.035),
            (0, -0.04)]
    lathe(k, prof, (0, -0.035, 0.37), hexc("7d7f83"), "Metal", segs=8, smooth=50, rot=(pi / 2, 0, 0))
    seg(k, (0, 0, 0.28), (0, -0.01, 0.34), 0.017, "Metal", STEEL_DK, segs=5)
    return fin(k, "ladle", HAND_BUDGET)


@hand
def p_knife():
    k = LK("knife", 120)
    bx(k, (0.03, 0.042, 0.125), (0, 0, -0.065), hexc("a5723f"), "Wood", bevel=0.005)
    bx(k, (0.036, 0.048, 0.02), (0, 0, 0.005), STEEL_DK, "Metal")
    for z in (-0.03, -0.1):
        seg(k, (-0.017, 0, z), (0.017, 0, z), 0.007, "Metal", BRASS, segs=4, rot=None) if False else None
    side(k, [(-0.022, 0.015), (-0.022, 0.2), (-0.004, 0.245), (0.03, 0.22), (0.038, 0.1), (0.034, 0.015)], 0.014,
         (0, 0, 0), STEEL)
    return fin(k, "knife", HAND_BUDGET)


@hand
def p_broom():
    k = LK("broom", 121)
    handle(k, -0.62, 0.55, 0.023, c=hexc("a9784a"))
    n = 8
    cf = lambda f: vary(STRAW, 0.14, 0.03)
    seg(k, (0, 0, -0.98), (0, 0, -0.52), 0.15, "Thatch", STRAW, r2=0.055, segs=n, smooth=None, var=0.02)
    for i in range(n):
        a = i / n * tau + 0.2
        seg(k, (math.cos(a) * 0.115, math.sin(a) * 0.115, -0.82), (math.cos(a) * 0.185, math.sin(a) * 0.185, -1.02),
            0.038, "Thatch", vary(STRAW, 0.14), r2=0.008, segs=3, caps=False)
    seg(k, (0, 0, -0.62), (0, 0, -0.575), 0.085, "Cloth", ROPE, segs=8, caps=False)
    seg(k, (0, 0, -0.76), (0, 0, -0.715), 0.113, "Cloth", ROPE, segs=8, caps=False)
    return fin(k, "broom", HAND_BUDGET)


@hand
def p_sack():
    k = LK("sack", 122)
    k.sack((0, 0, -0.56), s=0.88, rot=(0, 0, 0))
    return fin(k, "sack", HAND_BUDGET)


@hand
def p_crate_small():
    k = LK("crate_small", 123)
    c = hexc("b98b52")
    dk = hexc("7e5433")
    L, D, H = 0.45, 0.32, 0.26
    for x in (-1, 1):
        for y in (-1, 1):
            bx(k, (0.05, 0.05, H), (x * (L / 2 - 0.025), y * (D / 2 - 0.025), H / 2), dk, "Wood")
    bx(k, (L - 0.04, D - 0.04, 0.03), (0, 0, 0.015), dk, "Wood")
    for zi in range(3):
        z = 0.05 + zi * 0.085
        for y in (-1, 1):
            bx(k, (L - 0.09, 0.022, 0.07), (0, y * (D / 2 - 0.011), z + 0.03), k.board_c(c), "Wood")
        for x in (-1, 1):
            bx(k, (0.022, D - 0.09, 0.07), (x * (L / 2 - 0.011), 0, z + 0.03), k.board_c(c), "Wood")
    for i in range(5):
        col = random.choice([hexc("c2392b"), hexc("d08a2e"), hexc("a3372b"), hexc("7aa03c")])
        blob(k, 0.052, (-0.16 + (i % 3) * 0.16 + random.uniform(-0.02, 0.02), -0.06 + (i // 3) * 0.13, H - 0.03), col,
             "Plant", subdiv=1)
    return fin(k, "crate_small", HAND_BUDGET)


@hand
def p_basket():
    k = LK("basket", 124)
    wick = hexc("cfa565")
    prof = [(0, -0.38), (0.11, -0.375), (0.16, -0.3), (0.185, -0.22), (0.2, -0.16), (0.195, -0.155),
            (0.18, -0.16), (0.17, -0.19)]
    n = 10

    def cf(f):
        c = f.calc_center_median()
        band = int((c.z + 0.4) / 0.045)
        return vary(wick, 0.1, 0.03) if band % 2 == 0 else mix(vary(wick, 0.08), hexc("8e6636"), 0.35)
    lathe(k, prof, (0, 0, 0), wick, "Thatch", segs=n, smooth=None, color_fn=cf)
    # rim + goods
    lathe(k, [(0.176, -0.17), (0.2, -0.165), (0.2, -0.15), (0.176, -0.155)], (0, 0, 0), hexc("a9793e"), "Thatch",
          segs=n, smooth=None)
    blob(k, 0.17, (0, 0, -0.19), hexc("efe6cb"), "Cloth", scale=(1, 1, 0.5), subdiv=1)
    for i, (x, y, col) in enumerate(((-0.06, -0.04, hexc("c2392b")), (0.07, 0.03, hexc("d9a13b")),
                                     (0.0, 0.08, hexc("a3372b")), (-0.05, 0.07, hexc("7aa03c")))):
        blob(k, 0.055, (x, y, -0.13), col, "Plant", subdiv=1)
    pts = [(-0.2, 0, -0.16), (-0.19, 0, -0.06), (-0.12, 0, 0.0), (0, 0, 0.03), (0.12, 0, 0.0), (0.19, 0, -0.06),
           (0.2, 0, -0.16)]
    k.tube(pts, [0.017] * 7, k.M("Thatch"), hexc("a9793e"), segs=4, cap_start=True, point_end=False, smooth=None)
    return fin(k, "basket", HAND_BUDGET)


@hand
def p_spear():
    k = LK("spear", 125)
    handle(k, -0.75, 1.32, 0.022, c=hexc("a9784a"), r2=0.019)
    seg(k, (0, 0, -0.75), (0, 0, -0.71), 0.028, "Metal", IRON_LT, segs=6)
    seg(k, (0, 0, 1.22), (0, 0, 1.36), 0.036, "Metal", IRON_LT, r2=0.026)
    pts = [(0, 1.34), (0.05, 1.4), (0.062, 1.5), (0.045, 1.6), (0, 1.72), (-0.045, 1.6), (-0.062, 1.5), (-0.05, 1.4)]
    pr(k, pts, 0.018, (0, 0, 0), STEEL)
    bx(k, (0.02, 0.026, 0.3), (0, 0, 1.52), STEEL_DK, "Metal")
    pr(k, [(0, 1.18), (0.075, 1.09), (0.05, 0.98), (0, 0.9), (-0.05, 0.98), (-0.075, 1.09)], 0.008, (0.0, 0.03, 0),
       RED, "Cloth")                                                                       # pennon
    return fin(k, "spear", HAND_BUDGET)


@hand
def p_book():
    k = LK("book", 126)
    red = hexc("8d2f27")
    L, H, T = 0.2, 0.28, 0.05
    bx(k, (L, T, H), (L / 2 + 0.02, 0, 0), red, "Cloth", bevel=0.006)
    bx(k, (L - 0.03, T - 0.014, H - 0.03), (L / 2 + 0.032, 0, 0), hexc("efe3c4"), "Cloth", var=0.02)
    bx(k, (0.045, T + 0.008, H + 0.008), (0.0, 0, 0), hexc("6f231d"), "Cloth", bevel=0.008)     # spine
    bx(k, (0.06, 0.008, 0.06), (L / 2 + 0.05, -T / 2 - 0.003, 0.0), GOLD, "Metal", rot=(0, pi / 4, 0))
    for z in (H / 2 - 0.0, -H / 2 + 0.0):
        bx(k, (0.05, T + 0.012, 0.03), (L + 0.02 - 0.025, 0, z), GOLD, "Metal", var=0.02)
    bx(k, (0.014, 0.006, 0.09), (L / 2 + 0.05, 0.0, -H / 2 - 0.04), RED, "Cloth")            # ribbon
    return fin(k, "book", HAND_BUDGET)


@hand
def p_quill():
    k = LK("quill", 127)
    seg(k, (0, 0, -0.14), (0, 0, 0.25), 0.009, "Cloth", hexc("efe6cf"), segs=4, r2=0.007)
    seg(k, (0, 0, -0.15), (0, 0, -0.1), 0.007, "Metal", hexc("2a2622"), segs=4, r2=0.001, rot=None) if False else None
    seg(k, (0, 0, -0.10), (0, 0, -0.16), 0.008, "Metal", hexc("2a2622"), r2=0.0015, segs=4, caps=False)
    vane = [(0.0, 0.02), (0.035, 0.07), (0.05, 0.16), (0.038, 0.26), (0.0, 0.34), (-0.025, 0.26), (-0.036, 0.16),
            (-0.028, 0.07)]
    pr(k, vane, 0.008, (0.0, 0.006, 0.0), hexc("f4eee0"), "Cloth")
    pr(k, [(0.0, 0.16), (0.05, 0.16), (0.038, 0.26), (0.0, 0.34)], 0.006, (0.0, -0.004, 0.0), hexc("d9603a"), "Cloth")
    return fin(k, "quill", HAND_BUDGET)


@hand
def p_mug():
    k = LK("mug", 128)
    cy = -0.09
    prof = [(0, -0.08), (0.072, -0.08), (0.066, 0.0), (0.062, 0.08), (0.054, 0.08), (0.05, 0.05)]
    n = 10
    lathe(k, prof, (0, cy, 0), hexc("a4703c"), "Wood", segs=n, smooth=40, color_fn=stave_fn(n, hexc("a4703c"), 0, cy))
    for z in (-0.05, 0.05):
        r = 0.069 - (0.0 if z < 0 else 0.007)
        lathe(k, [(r, z - 0.014), (r + 0.007, z - 0.01), (r + 0.007, z + 0.01), (r, z + 0.014)], (0, cy, 0), IRON_LT,
              "Metal", segs=n, smooth=None)
    seg(k, (0, cy, 0.05), (0, cy, 0.062), 0.05, "Water", hexc("d59a2e"), segs=n)               # beer
    blob(k, 0.055, (0, cy, 0.07), MILK, "Cloth", scale=(1, 1, 0.55), subdiv=1)                  # foam
    pts = [(0, cy + 0.06, 0.06), (0, 0.03, 0.055), (0, 0.048, 0.0), (0, 0.03, -0.055), (0, cy + 0.065, -0.06)]
    k.tube(pts, [0.014] * 5, k.M("Wood"), hexc("8a5a30"), segs=4, cap_start=True, point_end=False, smooth=None)
    return fin(k, "mug", HAND_BUDGET)


@hand
def p_lute():
    k = LK("lute", 129)
    body = hexc("b47a3e")
    prof = [(0, -0.56), (0.09, -0.545), (0.16, -0.48), (0.2, -0.38), (0.2, -0.28), (0.165, -0.19), (0.1, -0.12),
            (0.05, -0.08), (0.04, -0.05)]

    def vfn(v):
        return Vector((v.x, v.y * 0.62 + 0.0, v.z))
    lathe(k, prof, (0, 0.06, 0), body, "Wood", segs=8, smooth=60, vfn=vfn, color_fn=stave_fn(8, body, 0, 0.06))
    board = [(0.0, -0.56), (0.075, -0.545), (0.135, -0.49), (0.17, -0.4), (0.17, -0.3), (0.14, -0.2), (0.08, -0.13),
             (0.04, -0.1), (-0.04, -0.1), (-0.08, -0.13), (-0.14, -0.2), (-0.17, -0.3), (-0.17, -0.4), (-0.135, -0.49),
             (-0.075, -0.545)]
    pr(k, board, 0.012, (0, -0.06, 0), hexc("dcb373"), "Wood")
    seg(k, (0, -0.064, -0.33), (0, -0.075, -0.33), 0.045, "Metal", hexc("3b2a1d"), segs=8)   # sound hole
    bx(k, (0.11, 0.02, 0.022), (0, -0.075, -0.5), hexc("4a3020"), "Wood")                       # bridge
    bx(k, (0.05, 0.035, 0.45), (0, -0.005, 0.11), hexc("5a3a22"), "Wood")                       # neck
    bx(k, (0.036, 0.008, 0.42), (0, -0.026, 0.12), hexc("2f2018"), "Wood")                      # fingerboard
    k.push((0, -0.005, 0.34), (-0.5, 0, 0))
    bx(k, (0.07, 0.035, 0.15), (0, 0, 0.07), hexc("4a3020"), "Wood")               # pegbox
    for sx in (-1, 1):
        for zz in (0.04, 0.11):
            bx(k, (0.035, 0.014, 0.016), (sx * 0.05, 0, zz), hexc("2a1c12"), "Wood")
    k.pop()
    for sx in (-0.008, 0.008):
        bx(k, (0.005, 0.005, 0.62), (sx, -0.078, -0.18), hexc("f0e6c8"), "Cloth", var=0.0)
    return fin(k, "lute", HAND_BUDGET)


@hand
def p_flute():
    k = LK("flute", 130)
    seg(k, (0, 0, -0.2), (0, 0, 0.24), 0.018, "Wood", hexc("b47a3a"), segs=6)
    for i in range(6):
        z = -0.08 + i * 0.045 + (0.02 if i > 2 else 0)
        seg(k, (0, -0.015, z), (0, -0.022, z), 0.0095, "Wood", hexc("3a2416"), segs=5, var=0.0)
    seg(k, (0, 0, -0.205), (0, 0, -0.17), 0.02, "Metal", BRASS, segs=6, caps=False)
    seg(k, (0, 0, 0.2), (0, 0, 0.24), 0.02, "Metal", BRASS, segs=6, caps=False)
    seg(k, (0, -0.012, 0.13), (0, -0.02, 0.13), 0.011, "Wood", hexc("3a2416"), segs=5, var=0.0)
    return fin(k, "flute", HAND_BUDGET)


@hand
def p_cane():
    k = LK("cane", 131)
    seg(k, (0, 0, -0.9), (0, 0, 0.0), 0.02, "Wood", hexc("9a6a3a"), r2=0.024, segs=6)
    seg(k, (0, 0, -0.9), (0, 0, -0.85), 0.022, "Metal", IRON_LT, r2=0.026, segs=6, caps=False)
    pts = [(0, 0, -0.02), (0, 0, 0.07), (0, -0.03, 0.13), (0, -0.09, 0.15), (0, -0.15, 0.11), (0, -0.17, 0.05)]
    k.tube(pts, [0.026, 0.028, 0.028, 0.028, 0.026, 0.022], k.M("Wood"), hexc("9a6a3a"), segs=6, cap_start=False,
           point_end=False, smooth=None)
    seg(k, (0, -0.17, 0.05), (0, -0.17, 0.02), 0.03, "Metal", BRASS, segs=6, rot=None) if False else None
    blob(k, 0.03, (0, -0.17, 0.045), hexc("d6b060"), "Wood", subdiv=1)
    return fin(k, "cane", HAND_BUDGET)


@hand
def p_bread():
    k = LK("bread", 132)
    blob(k, 1.0, (0, 0, 0), BREAD, "Cloth", scale=(0.135, 0.075, 0.062), subdiv=2, noise=0.0)
    for i in range(3):
        bx(k, (0.055, 0.012, 0.012), (-0.06 + i * 0.06, -0.005, 0.056), hexc("f0d49a"), "Cloth", rot=(0, 0, 0.55),
           var=0.02)
    blob(k, 1.0, (0, 0.005, -0.03), hexc("b9782d"), "Cloth", scale=(0.13, 0.072, 0.03), subdiv=1)
    return fin(k, "bread", HAND_BUDGET)


@hand
def p_spoon():
    k = LK("spoon", 133)
    seg(k, (0, 0, -0.14), (0, 0, 0.14), 0.014, "Wood", hexc("c9985c"), r2=0.009, segs=5)
    blob(k, 1.0, (0, 0, 0.2), hexc("c9985c"), "Wood", scale=(0.046, 0.024, 0.062), subdiv=2)
    blob(k, 1.0, (0, -0.016, 0.2), hexc("6e4726"), "Wood", scale=(0.033, 0.01, 0.048), subdiv=1)
    return fin(k, "spoon", HAND_BUDGET)


@hand
def p_laundry():
    k = LK("laundry", 134)
    blob(k, 1.0, (0, 0, 0), hexc("f1ead6"), "Cloth", scale=(0.18, 0.1, 0.085), subdiv=2, noise=0.012)
    blob(k, 1.0, (0.03, -0.045, -0.01), hexc("5f83b0"), "Cloth", scale=(0.12, 0.07, 0.07), subdiv=1, rot=(0, 0, 0.3))
    blob(k, 1.0, (-0.1, 0.03, 0.02), hexc("c35a45"), "Cloth", scale=(0.085, 0.06, 0.055), subdiv=1, rot=(0.2, 0, -0.4))
    blob(k, 1.0, (0.16, 0.0, 0.0), hexc("f1ead6"), "Cloth", scale=(0.06, 0.05, 0.05), subdiv=1)
    for x in (-0.03, 0.09):                                                               # wet drips
        blob(k, 0.014, (x, -0.02, -0.11), hexc("a9d2e0"), "Water", scale=(0.7, 0.7, 1.4), subdiv=1)
    return fin(k, "laundry", HAND_BUDGET)


@hand
def p_coin():
    k = LK("coin", 135)
    prof = [(0, -0.062), (0.04, -0.057), (0.066, -0.02), (0.06, 0.02), (0.032, 0.05), (0.02, 0.062)]
    lathe(k, prof, (0, 0, 0), LEATHER, "Cloth", segs=8, smooth=80)
    seg(k, (0, 0, 0.055), (0, 0, 0.1), 0.03, "Cloth", LEATHER, r2=0.05, segs=7)
    seg(k, (0, 0, 0.045), (0, 0, 0.065), 0.036, "Cloth", ROPE, segs=7, caps=False)
    seg(k, (0.02, -0.012, 0.09), (0.02, 0.008, 0.125), 0.027, "Metal", GOLD, segs=8, rot=None) if False else None
    for i, (x, z, r) in enumerate(((0.012, 0.1, 0.35), (-0.03, 0.11, -0.4))):
        k.push((x, 0, z), (r, 0, 0.2))
        seg(k, (0, -0.005, 0), (0, 0.005, 0), 0.03, "Metal", GOLD, segs=8, rot=None) if False else None
        k.cyl(0.03, 0.008, (0, 0, 0), k.M("Metal"), GOLD, rot=(pi / 2, 0, 0), segs=8, grime=False, smooth=None)
        k.pop()
    return fin(k, "coin", HAND_BUDGET)


@hand
def p_bellows_handle():
    k = LK("bellows_handle", 136)
    seg(k, (0, 0, -0.22), (0, 0, 0.36), 0.026, "Wood", hexc("a9784a"), r2=0.022, segs=6)
    blob(k, 0.042, (0, 0, 0.4), hexc("8e6238"), "Wood", scale=(1, 1, 1.15), subdiv=1)
    seg(k, (0, 0, -0.27), (0, 0, -0.2), 0.034, "Metal", IRON_LT, segs=6, caps=False)
    bx(k, (0.07, 0.03, 0.05), (0, 0, -0.29), IRON_LT, "Metal")
    seg(k, (0, 0, 0.3), (0, 0, 0.32), 0.032, "Cloth", LEATHER, segs=6, caps=False)
    return fin(k, "bellows_handle", HAND_BUDGET)


# ====================================================================== SCENE PROPS
@scene
def p_sawhorse():
    k = LK("sawhorse", 201, grime=0.1)
    bx(k, (1.05, 0.13, 0.1), (0, 0, 0.55), hexc("b98b52"), bevel=0.006)
    for x, ty in ((-0.4, 1), (0.4, 1)):
        for sy in (-1, 1):
            bar(k, (x, sy * 0.05, 0.53), (x * 1.13, sy * 0.3, 0.0), 0.075, 0.055, hexc("8e6238"), up=(1, 0, 0))
        bx(k, (0.05, 0.43, 0.05), (x * 1.075, 0, 0.22), hexc("7e5433"))
    bx(k, (0.86, 0.045, 0.05), (0, 0, 0.36), hexc("7e5433"))
    for x in (-0.5, 0.5):
        bx(k, (0.05, 0.135, 0.005), (x, 0, 0.603), hexc("6a4529"), var=0.02)
    return fin(k, "sawhorse", SCENE_BUDGET)


@scene
def p_wash_tub():
    k = LK("wash_tub", 202, grime=0.1)
    n = 12
    wood = hexc("b48350")
    prof = [(0, 0.0), (0.285, 0.0), (0.34, 0.45), (0.318, 0.45), (0.31, 0.385)]
    lathe(k, prof, (0, 0, 0), wood, "Wood", segs=n, smooth=40, color_fn=stave_fn(n, wood))
    seg(k, (0, 0, 0.383), (0, 0, 0.392), 0.312, "Water", hexc("a8cdd6"), segs=n, var=0.02)
    for z in (0.09, 0.24, 0.39):
        r = 0.285 + 0.055 * z / 0.45 + 0.006
        lathe(k, [(r - 0.004, z - 0.022), (r + 0.007, z - 0.016), (r + 0.007, z + 0.016), (r - 0.004, z + 0.022)],
              (0, 0, 0), IRON_LT, "Metal", segs=n, smooth=None)
    for sx in (-1, 1):
        bx(k, (0.05, 0.11, 0.035), (sx * 0.365, 0, 0.36), hexc("8e6238"), bevel=0.005)
    # washboard leaning on the back rim
    k.push((0, 0.155, 0.36), (-pi / 4, 0, 0))
    for sx in (-1, 1):
        bx(k, (0.04, 0.035, 0.5), (sx * 0.15, 0, 0), hexc("8e6238"))
    bx(k, (0.34, 0.035, 0.045), (0, 0, 0.245), hexc("8e6238"))
    bx(k, (0.28, 0.02, 0.4), (0, -0.005, -0.01), hexc("c3b48a"), var=0.02)
    for i in range(6):
        bx(k, (0.28, 0.018, 0.022), (0, -0.02, -0.15 + i * 0.065), STEEL_DK, "Metal", var=0.02)
    k.pop()
    for (x, y, r) in ((-0.1, -0.12, 0.05), (0.08, -0.1, 0.04), (-0.02, 0.0, 0.045), (0.14, 0.02, 0.035), (-0.17, 0.04, 0.03)):
        blob(k, r, (x, y, 0.39), hexc("f7fbfb"), "Cloth", scale=(1, 1, 0.75), subdiv=1)
    blob(k, 1.0, (0.12, -0.2, 0.395), hexc("e9d9a8"), "Cloth", scale=(0.05, 0.03, 0.02), subdiv=1)
    return fin(k, "wash_tub", SCENE_BUDGET)


@scene
def p_cook_pot():
    k = LK("cook_pot", 203, grime=0.1)
    rng = random.Random(3)
    ns = 10
    for i in range(ns):
        a = i / ns * tau
        r = 0.44
        blob(k, 1.0, (math.cos(a) * r, math.sin(a) * r, 0.06), vary(random.choice(STONE_C), 0.08), "Matte",
             scale=(0.15, 0.115, 0.085), subdiv=1, rot=(0, 0, a + pi / 2), var=0.0)
    seg(k, (0, 0, 0.0), (0, 0, 0.03), 0.4, "Matte", hexc("4a3f37"), segs=12, var=0.02)
    for i in range(3):
        a = i / 3 * pi + 0.4
        seg(k, (-math.cos(a) * 0.3, -math.sin(a) * 0.3, 0.075), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.075), 0.04,
            "Wood", hexc("5b4130"), segs=5)
        seg(k, (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.075), (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.075), 0.04,
            "Coals", hexc("e6501a"), segs=5, caps=True) if False else None
    for (x, y, h, c) in ((0, 0, 0.3, "ff9a2a"), (0.1, 0.05, 0.22, "ffc93a"), (-0.09, 0.08, 0.2, "ff8a26"),
                         (0.02, -0.11, 0.24, "ffb02f"), (-0.1, -0.06, 0.17, "ffd24a")):
        seg(k, (x, y, 0.08), (x * 0.6, y * 0.6, 0.08 + h), 0.055, "Plant", hexc(c), r2=0.004, segs=4, caps=False, var=0.02)
    for i in range(3):                                                                    # tripod
        a = pi / 2 + i * tau / 3
        seg(k, (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.0), (0, 0, 1.42), 0.032, "Wood", hexc("7e5433"), r2=0.024,
            segs=5)
    seg(k, (0, 0, 1.33), (0, 0, 1.4), 0.075, "Cloth", ROPE, segs=6, caps=False)
    seg(k, (0, 0, 1.36), (0, 0, 0.8), 0.011, "Metal", IRON_LT, segs=4, var=0.02)
    # pot: rim at 0.6 m
    prof = [(0, 0.24), (0.15, 0.24), (0.24, 0.31), (0.295, 0.42), (0.29, 0.53), (0.31, 0.6), (0.275, 0.6),
            (0.27, 0.55)]
    lathe(k, prof, (0, 0, 0), hexc("3c3835"), "Metal", segs=12, smooth=55)
    seg(k, (0, 0, 0.545), (0, 0, 0.555), 0.272, "Water", hexc("b9702c"), segs=12)
    for (x, y) in ((0.09, 0.05), (-0.1, -0.03), (0.0, -0.14), (-0.08, 0.13)):
        blob(k, 0.035, (x, y, 0.56), hexc("6f9a3a"), "Plant", subdiv=1, scale=(1, 1, 0.6))
    pts = [(-0.31, 0, 0.58), (-0.26, 0, 0.72), (-0.13, 0, 0.8), (0, 0, 0.83), (0.13, 0, 0.8), (0.26, 0, 0.72),
           (0.31, 0, 0.58)]
    k.tube(pts, [0.011] * 7, k.M("Metal"), IRON_LT, segs=4, cap_start=True, point_end=False, smooth=None)
    for sx in (-1, 1):
        bx(k, (0.04, 0.05, 0.05), (sx * 0.3, 0, 0.58), IRON_LT, "Metal")
    return fin(k, "cook_pot", SCENE_BUDGET)


@scene
def p_milking_stool():
    k = LK("milking_stool", 204, grime=0.1)
    seat = hexc("c0925a")
    seg(k, (0, 0, 0.255), (0, 0, 0.3), 0.175, "Wood", seat, segs=12, var=0.02)
    for i in range(3):
        a = -pi / 2 + i * tau / 3
        seg(k, (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.27), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.0), 0.028,
            "Wood", hexc("8e6238"), r2=0.024, segs=6)
        seg(k, (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.298), (math.cos(a) * 0.09, math.sin(a) * 0.09, 0.303), 0.022,
            "Wood", hexc("6a4529"), segs=5)
    return fin(k, "milking_stool", SCENE_BUDGET)


@scene
def p_chopping_block():
    k = LK("chopping_block", 205, grime=0.15)
    n = 18
    az_notch = math.radians(-50)
    rings = [0.0, 0.07, 0.14, 0.21, 0.27]
    top = 0.45
    prof = [(0, top)]
    prof = [(0.0, 0.0)] if False else [(0.0, 0.0), (0.36, 0.0), (0.33, 0.07), (0.29, 0.2), (0.28, 0.35), (0.285, top - 0.001)]
    prof += [(0.27, top)] + [(r, top) for r in (0.21, 0.14, 0.07)] + [(0.0, top)]

    def vfn(v):
        a = math.atan2(v.y, v.x)
        r = math.hypot(v.x, v.y)
        if v.z < top - 0.05:
            f = 1 + 0.035 * math.sin(a * 5 + 1.0) + 0.02 * math.sin(a * 9)
            v.x *= f
            v.y *= f
        elif v.z >= top - 0.002 and r > 0.01:
            d = abs((a - az_notch + pi) % tau - pi)
            if d < 0.42:
                v.z -= 0.075 * (1 - d / 0.42) * min(1.0, r / 0.27)
        return v

    def vcol(v):
        r = math.hypot(v.x, v.y)
        if v.z > top - 0.09 and r < 0.275:
            base = hexc("d4a76a")
            if v.z < top - 0.003:
                return hexc("5a3a22")
            i = min(4, int(r / 0.07 + 0.25))
            return mix(base, hexc("a8763f"), 0.5 if i % 2 else 0.05)
        return mix(BARK, hexc("8b6544"), 0.25 * (0.5 + 0.5 * math.sin(math.atan2(v.y, v.x) * 7)))
    k.lathe(prof, (0, 0, 0), k.M("Wood"), BARK, segs=n, smooth=None, vcol=vcol, vfn=vfn, grime=False, var=0.0)
    k.split_log((0.5, -0.2, 0.0), (0.5, -0.2, 0.34), 0.1, kind="quarter", roll=0.7)
    for (x, y, rz) in ((0.32, -0.46, 0.5), (-0.4, -0.35, 1.2), (-0.3, 0.42, 0.2)):
        bx(k, (0.1, 0.045, 0.02), (x, y, 0.012), hexc("d0a468"), rot=(0, 0.1, rz), var=0.05)
    return fin(k, "chopping_block", SCENE_BUDGET)


@scene
def p_bar_counter():
    k = LK("bar_counter", 206, grime=0.12)
    dk = hexc("5d3d25")
    bx(k, (1.96, 0.5, 0.95), (0, 0.04, 0.475), dk)
    for i in range(10):
        bx(k, (0.19, 0.03, 0.83), (-0.9 + i * 0.2, -0.235, 0.12 + 0.415), k.board_c(hexc("94663a"), 0.1))
    for x in (-0.98, 0.0, 0.98):
        bx(k, (0.1, 0.05, 0.9), (x, -0.25, 0.45), hexc("6b4527"), bevel=0.006)
    bx(k, (2.0, 0.055, 0.075), (0, -0.25, 0.9), hexc("6b4527"))
    bx(k, (2.0, 0.055, 0.09), (0, -0.25, 0.045), hexc("6b4527"))
    bx(k, (2.1, 0.66, 0.06), (0, 0, 1.02), hexc("bd8b4e"), bevel=0.008, var=0.02)
    bx(k, (2.1, 0.04, 0.03), (0, -0.31, 0.985), hexc("6b4527"))
    seg(k, (-0.9, -0.44, 0.2), (0.9, -0.44, 0.2), 0.026, "Metal", BRASS, segs=6)
    for x in (-0.88, 0.0, 0.88):
        seg(k, (x, -0.28, 0.26), (x, -0.44, 0.2), 0.016, "Metal", BRASS, segs=4)
    for x in (-0.6, 0.55):                                                               # rings of wet cups
        seg(k, (x, -0.1, 1.05), (x, -0.1, 1.053), 0.07, "Wood", hexc("9a6c3c"), segs=8, rot=None) if False else None
    return fin(k, "bar_counter", SCENE_BUDGET)


@scene
def p_bellows():
    k = LK("bellows", 207, grime=0.1)
    frame = hexc("7e5433")
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(k, (0.07, 0.07, 0.5), (sx * 0.24, sy * 0.4, 0.25), frame, bevel=0.005)
        bx(k, (0.05, 0.86, 0.06), (sx * 0.24, 0, 0.46), frame)
    for sy in (-1, 1):
        bx(k, (0.5, 0.05, 0.06), (0, sy * 0.4, 0.46), frame)
    bx(k, (0.05, 0.86, 0.05), (0, 0, 0.18), frame)
    bx(k, (0.36, 0.95, 0.04), (0, 0, 0.51), hexc("a97a45"), bevel=0.004)                       # lower board
    hy = 0.42                                                                                 # hinge at the nozzle end
    ang = 0.32
    k.push((0, hy, 0.53), (ang, 0, 0))
    bx(k, (0.36, 0.95, 0.04), (0, -0.475, 0.02), hexc("b98b52"), bevel=0.004)                  # upper board (opens at -Y)
    bx(k, (0.4, 0.05, 0.06), (0, -0.95, 0.02), hexc("6b4527"))
    k.pop()
    leather = hexc("7a4a2a")
    gap = 0.95 * math.sin(ang)
    for sx in (-1, 1):
        side_pts = [(-hy, 0.55), (0.53, 0.55), (0.53, 0.55 + gap * 0.98), (0.2, 0.55 + gap * 0.5)]
        k.push((sx * 0.17, 0, 0.0), (0, 0, 0))
        k.prism([(y, z) for y, z in [(0.42, 0.55), (-0.53, 0.55), (-0.53, 0.55 + gap * 0.96)]], 0.02,
                (0, 0, 0), k.M("Cloth"), leather, rot=(0, 0, 0), grime=False) if False else None
        k.pop()
    # leather gussets (side profile: y along the board length, z height)
    for sx in (-1, 1):
        k.push((sx * 0.17, 0, 0.0))
        k.prism([(0.0, 0.0)] * 0 or [(-0.0, 0.0), (0.0, 0.0), (0.0, 0.0)], 0.001, (0, 0, 0), k.M("Cloth"), leather) if False else None
        k.pop()
    def gus(sx):
        t = bmesh.new()
        A = (sx * 0.175, hy, 0.55)
        B = (sx * 0.175, -0.53, 0.55)
        C = (sx * 0.175, -0.53, 0.55 + 0.95 * math.sin(ang) + 0.02)
        vs = [t.verts.new(p) for p in (A, B, C)]
        t.faces.new(vs if sx > 0 else vs[::-1])
        bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
        # outward normal check
        for f in t.faces:
            if f.normal.x * sx < 0:
                f.normal_flip()
        k._merge(t, k.M("Cloth"), leather, None, None, 0.03, None, False)
    for sx in (1, -1):
        gus(sx)
        gus(sx * 1.0) if False else None
    k.box((0.02, 0.02, 0.02), (0, 0, -5), k.M("Cloth"), leather, grime=False) if False else None
    # rear closing flap (leather) and ribs
    k.push((0, -0.53, 0.55))
    bx(k, (0.34, 0.03, 0.3 * 0 + 0.95 * math.sin(ang) + 0.02), (0, 0, (0.95 * math.sin(ang) + 0.02) / 2), leather, "Cloth")
    k.pop()
    for i, t_ in enumerate((0.3, 0.55, 0.8)):
        y = hy - t_ * 0.95
        zc = 0.55 + 0.95 * math.sin(ang) * t_ / 2
        bx(k, (0.4, 0.028, 0.95 * math.sin(ang) * t_ + 0.008), (0, y, zc), hexc("6b4527"), "Wood") if False else None
    for sx in (-1, 1):
        for i, t_ in enumerate((0.25, 0.5, 0.75)):
            y = hy - t_ * 0.95
            zc = 0.55 + 0.95 * math.sin(ang) * t_ * 0.5
            bx(k, (0.04, 0.03, 0.95 * math.sin(ang) * t_ + 0.01), (sx * 0.19, y, zc), hexc("5d3d25"), "Wood")
    # nozzle
    seg(k, (0, hy - 0.05, 0.56), (0, hy + 0.42, 0.56), 0.06, "Metal", IRON_LT, r2=0.028, segs=8)
    seg(k, (0, hy + 0.36, 0.56), (0, hy + 0.44, 0.56), 0.036, "Metal", STEEL_DK, segs=8, caps=False)
    # long lever (handle ~1.0 m) from the upper board's rear
    a = (0, -0.5, 0.75)
    b = (0, -1.2, 1.35)
    seg(k, a, b, 0.032, "Wood", hexc("a9784a"), r2=0.026, segs=6)
    blob(k, 0.05, b, hexc("8e6238"), "Wood", subdiv=1)
    seg(k, (0, -0.5, 0.62), (0, -0.5, 0.78), 0.028, "Metal", IRON_LT, segs=5)
    return fin(k, "bellows", SCENE_BUDGET)


@scene
def p_stool():
    k = LK("stool", 208, grime=0.1)
    seg(k, (0, 0, 0.57), (0, 0, 0.62), 0.2, "Wood", hexc("c0925a"), segs=12, var=0.02)
    seg(k, (0, 0, 0.545), (0, 0, 0.575), 0.185, "Wood", hexc("7e5433"), segs=12, var=0.02)
    for sx in (-1, 1):
        for sy in (-1, 1):
            seg(k, (sx * 0.11, sy * 0.11, 0.56), (sx * 0.19, sy * 0.19, 0.0), 0.03, "Wood", hexc("8e6238"), r2=0.026,
                segs=6)
    z = 0.24
    p = 0.11 + 0.08 * (0.56 - z) / 0.56
    for sx, sy, tx, ty in ((-1, -1, 1, -1), (1, -1, 1, 1), (1, 1, -1, 1), (-1, 1, -1, -1)):
        seg(k, (sx * p, sy * p, z), (tx * p, ty * p, z), 0.016, "Wood", hexc("7e5433"), segs=4)
    return fin(k, "stool", SCENE_BUDGET)


@scene
def p_hopscotch():
    k = LK("hopscotch", 209, grime=0.0)
    flat(k, -1.6, -0.45, 1.6, 0.45, 0.003, hexc("bfa172"), "Matte")
    ch = hexc("f3efe3")
    w = 0.03
    cell = 0.4
    # cells: (x0, x1, y0, y1)
    cells = []
    xs = -1.45
    layout = [("1",), ("2",), ("3", "4"), ("5",), ("6", "7"), ("8",)]
    for grp in layout:
        if len(grp) == 1:
            cells.append((grp[0], xs, xs + cell, -0.2, 0.2))
        else:
            cells.append((grp[0], xs, xs + cell, -0.4, 0.0))
            cells.append((grp[1], xs, xs + cell, 0.0, 0.4))
        xs += cell
    cells.append(("9", xs, xs + 0.52, -0.4, 0.4))
    z = 0.007
    for (nm, x0, x1, y0, y1) in cells:
        flat(k, x0 - w / 2, y0 - w / 2, x1 + w / 2, y0 + w / 2, z, ch)
        flat(k, x0 - w / 2, y1 - w / 2, x1 + w / 2, y1 + w / 2, z, ch)
        flat(k, x0 - w / 2, y0 - w / 2, x0 + w / 2, y1 + w / 2, z, ch)
        flat(k, x1 - w / 2, y0 - w / 2, x1 + w / 2, y1 + w / 2, z, ch)
    # chalk numbers (7-segment style, bold), read from the -Y side (screen-up = +Y)
    SEG = {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg", "7": "abc",
           "8": "abcdefg", "9": "abcdfg"}
    for (nm, x0, x1, y0, y1) in cells:
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        hw, hh, t = 0.05, 0.075, 0.022
        # digits are drawn lying on the ground, upright when seen from -Y (bottom = -Y)
        segs_ = {"a": (cx - hw, cy + hh - t / 2, cx + hw, cy + hh + t / 2), "d": (cx - hw, cy - hh - t / 2, cx + hw, cy - hh + t / 2),
                 "g": (cx - hw, cy - t / 2, cx + hw, cy + t / 2),
                 "f": (cx - hw - t / 2, cy, cx - hw + t / 2, cy + hh + t / 2),
                 "b": (cx + hw - t / 2, cy, cx + hw + t / 2, cy + hh + t / 2),
                 "e": (cx - hw - t / 2, cy - hh - t / 2, cx - hw + t / 2, cy),
                 "c": (cx + hw - t / 2, cy - hh - t / 2, cx + hw + t / 2, cy)}
        for s_ in SEG[nm]:
            x0_, y0_, x1_, y1_ = segs_[s_]
            flat(k, x0_, y0_, x1_, y1_, z, ch)
    # a few pebbles at the start line
    for (x, y) in ((-1.55, 0.3), (-1.52, -0.32)):
        blob(k, 0.035, (x, y, 0.02), hexc("8f8a7e"), "Matte", scale=(1, 0.8, 0.6), subdiv=1)
    return fin(k, "hopscotch", SCENE_BUDGET)


@scene
def p_lectern():
    k = LK("lectern", 210, grime=0.1)
    dk = hexc("6b4527")
    bx(k, (0.5, 0.42, 0.08), (0, 0, 0.04), dk, bevel=0.01)
    bx(k, (0.22, 0.18, 0.7), (0, 0, 0.42), hexc("94663a"), bevel=0.012)
    bx(k, (0.34, 0.27, 0.07), (0, 0, 0.79), dk, bevel=0.01)
    bx(k, (0.03, 0.008, 0.2), (0, -0.094, 0.45), GOLD, "Metal")
    bx(k, (0.11, 0.008, 0.03), (0, -0.094, 0.5), GOLD, "Metal")
    k.push((0, 0, 0.86), (0.42, 0, 0))
    bx(k, (0.62, 0.44, 0.045), (0, 0, 0), hexc("b98b52"), bevel=0.006)
    bx(k, (0.62, 0.04, 0.06), (0, -0.21, 0.04), dk)
    bx(k, (0.62, 0.025, 0.04), (0, 0.2, 0.035), dk)
    bx(k, (0.25, 0.32, 0.018), (-0.125, 0, 0.032), hexc("f0e5c6"), "Cloth", rot=(0, -0.05, 0))
    bx(k, (0.25, 0.32, 0.018), (0.125, 0, 0.032), hexc("f0e5c6"), "Cloth", rot=(0, 0.05, 0))
    bx(k, (0.52, 0.34, 0.014), (0, 0, 0.018), hexc("8d2f27"), "Cloth")
    bx(k, (0.012, 0.005, 0.12), (0.0, -0.005, 0.043), RED, "Cloth")
    k.pop()
    return fin(k, "lectern", SCENE_BUDGET)


@scene
def p_table():
    k = LK("table", 211, grime=0.1)
    for i in range(4):
        bx(k, (1.4, 0.195, 0.045), (0, -0.3 + i * 0.2, 0.7275), k.board_c(hexc("b98b52"), 0.08))
    for x in (-0.5, 0.5):
        bx(k, (0.06, 0.66, 0.04), (x, 0, 0.685), hexc("7e5433"))
    for sx in (-1, 1):
        for sy in (-1, 1):
            bx(k, (0.085, 0.085, 0.68), (sx * 0.6, sy * 0.3, 0.34), hexc("8e6238"), bevel=0.006)
    for sy in (-1, 1):
        bx(k, (1.15, 0.03, 0.09), (0, sy * 0.3, 0.6), hexc("7e5433"))
    for sx in (-1, 1):
        bx(k, (0.03, 0.55, 0.09), (sx * 0.6, 0, 0.6), hexc("7e5433"))
    bx(k, (1.15, 0.05, 0.05), (0, 0, 0.2), hexc("7e5433"))
    return fin(k, "table", SCENE_BUDGET)


# ====================================================================== build
def main_build(names):
    lines = []
    allp = {**HAND, **SCENE}
    for n in names:
        random.seed(hash(n) & 0xffff)
        try:
            ln = allp[n]()
        except Exception:
            import traceback
            traceback.print_exc()
            ln = f"PROP {n}: FAILED"
        lines.append(ln)
        print(ln, flush=True)
    os.makedirs(SCRATCH, exist_ok=True)
    old = {}
    if os.path.exists(REPORT):
        for l in open(REPORT):
            if l.startswith("PROP "):
                old[l.split(":")[0]] = l.rstrip("\n")
    for l in lines:
        old[l.split(":")[0]] = l
    with open(REPORT, "w") as f:
        f.write("\n".join(old[k_] for k_ in sorted(old)) + "\n")


# ====================================================================== sheets
def _report_tris():
    d = {}
    if os.path.exists(REPORT):
        for l in open(REPORT):
            if l.startswith("PROP ") and "tris=" in l:
                d[l.split(":")[0][5:]] = int(l.split("tris=")[1].split()[0])
    return d


def _emit(name, col, strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*col, 1)
    em.inputs["Strength"].default_value = strength
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def _flatmat(name, col, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    return m


def _new_scene(bg=(0.80, 0.86, 0.93)):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = "BLENDER_EEVEE"
    except TypeError:
        sc.render.engine = "BLENDER_EEVEE_NEXT"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bgn = world.node_tree.nodes["Background"]
    bgn.inputs["Color"].default_value = (*bg, 1)
    bgn.inputs["Strength"].default_value = 1.0
    sc.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.data.color = (1.0, 0.88, 0.72)
    sun.data.angle = math.radians(3)
    sun.rotation_euler = (math.radians(55), math.radians(8), math.radians(-35))
    sc.collection.objects.link(sun)
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    return sc


def _camera(sc, target, width_m, res, az_deg=22, el_deg=14):
    cd = bpy.data.cameras.new("Cam")
    cd.type = "ORTHO"
    cd.ortho_scale = width_m
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    az, el = math.radians(az_deg), math.radians(el_deg)
    d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
    cam.location = Vector(target) + d * 40
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    cd.clip_end = 200
    sc.camera = cam
    sc.render.resolution_x, sc.render.resolution_y = res
    return cam


def _text(sc, body, loc, cam, size=0.09, col=(0.12, 0.09, 0.06), align="CENTER"):
    cu = bpy.data.curves.new("t", "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    ob = bpy.data.objects.new("t", cu)
    ob.location = loc
    ob.rotation_euler = cam.rotation_euler
    ob.data.materials.append(_emit("txt", col))
    sc.collection.objects.link(ob)
    return ob


def _box(sc, size, loc, col):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.scale = size
    o.data.materials.append(_emit("b", col))
    return o


def _cyl_between(a, b, r, col):
    a, b = Vector(a), Vector(b)
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, vertices=8, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    o.data.materials.append(_emit("c", col))
    return o


def _triad(origin, L=0.12, r=0.007, grip=None, front=None):
    o = Vector(origin)
    for axis, col in (((1, 0, 0), (1.0, 0.1, 0.1)), ((0, 1, 0), (0.1, 0.85, 0.1)), ((0, 0, 1), (0.15, 0.3, 1.0))):
        _cyl_between(o - Vector(axis) * 0.02, o + Vector(axis) * L, r, col)
    for ax, col in ((grip, (1.0, 0.9, 0.0)), (front, (0.0, 0.9, 0.95))):
        if ax is None:
            continue
        bpy.ops.mesh.primitive_uv_sphere_add(radius=r * 2.4, location=o + Vector(ax) * (L + 0.035), segments=12, ring_count=8)
        s = bpy.context.active_object
        s.data.materials.append(_emit("dot", col))


def _import(path, off=(0, 0, 0)):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in new if o.parent is None]
    for o in roots:
        o.location = Vector(o.location) + Vector(off)
    bpy.context.view_layer.update()
    return new, roots


def _bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
    return lo, hi


def _shift(roots, d):
    for o in roots:
        o.location = Vector(o.location) + Vector(d)
    bpy.context.view_layer.update()


def _human_bar(sc, cam, x, z0, label="1.75 m"):
    n = 7
    for i in range(n):
        _box(sc, (0.07, 0.07, 0.25), (x, 0, z0 + 0.125 + i * 0.25),
             (0.85, 0.75, 0.55) if i % 2 == 0 else (0.35, 0.25, 0.15))
    _text(sc, label, (x + 0.25, -0.1, z0 - 0.14), cam, 0.09)


def _load_contract():
    return json.load(open(JSON_PATH))


def _render(sc, path, quality=80):
    sc.render.image_settings.file_format = "JPEG"
    sc.render.image_settings.quality = quality
    sc.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("sheet", path, os.path.getsize(path) // 1024, "KB", flush=True)


def sheet_lineup():
    """True-scale hand-prop line-up (tall tools in a row, small props in a grid) + 1.75 m bar."""
    contract = _load_contract()["hand"]
    tris = _report_tris()
    sc = _new_scene()
    items = {}
    for n in HAND:
        p = os.path.join(LIFE_DIR, n + ".glb")
        if not os.path.exists(p):
            continue
        objs, roots = _import(p)
        lo, hi = _bounds(objs)
        items[n] = (objs, roots, lo, hi)
    tall = [n for n, (o, r, lo, hi) in items.items() if (hi - lo).z > 0.85 or (hi - lo).x > 0.85]
    small = [n for n in items if n not in tall]
    # tall row: baseline z=0
    x = 0.0
    placed = []
    for n in tall:
        objs, roots, lo, hi = items[n]
        w = max(hi.x - lo.x, 0.3)
        cx = x + w / 2 + 0.05
        _shift(roots, (cx - (lo.x + hi.x) / 2, 0, -lo.z))
        o = Vector(roots[0].location)
        placed.append((n, cx, Vector((cx - (lo.x + hi.x) / 2, 0, -lo.z))))
        x = cx + w / 2 + 0.28
    row_w = x
    cols = 7
    pitch_x, pitch_z = 0.95, 0.85
    z_top = -0.55
    cam_tmp = None
    small_pos = []
    for i, n in enumerate(small):
        objs, roots, lo, hi = items[n]
        r_, c_ = divmod(i, cols)
        cx = 0.5 + c_ * pitch_x
        cz = z_top - 0.5 - r_ * pitch_z
        d = Vector((cx - (lo.x + hi.x) / 2, 0, cz - (lo.z + hi.z) / 2))
        _shift(roots, d)
        small_pos.append((n, cx, cz, d))
    width = max(row_w, 0.5 + cols * pitch_x)
    nrows = math.ceil(len(small) / cols)
    z_bot = z_top - 0.5 - nrows * pitch_z
    z_hi = 2.55
    height = z_hi - z_bot + 0.2
    W = 3000
    H = int(W * height / (width + 0.3))
    cam = _camera(sc, ((width) / 2 - 0.1, 0, (z_hi + z_bot) / 2), width + 0.3, (W, H), az_deg=18, el_deg=10)
    # floor strip under tall row
    _box(sc, (row_w + 0.1, 1.6, 0.03), (row_w / 2 - 0.05, 0, -0.016), (0.42, 0.56, 0.27))
    _human_bar(sc, cam, -0.25, 0.0)
    for (n, cx, d) in placed:
        contr = contract[n]
        _triad(Vector(d), 0.13, 0.008, contr["grip_axis"], contr["front_axis"])
        _text(sc, f"{n} {tris.get(n, '')}", (cx, -0.95, -0.14), cam, 0.085)
    for (n, cx, cz, d) in small_pos:
        contr = contract[n]
        _triad(Vector(d), 0.1, 0.006, contr["grip_axis"], contr["front_axis"])
        _text(sc, f"{n} {tris.get(n, '')}", (cx, -0.3, cz - 0.4), cam, 0.075)
    _text(sc, "TRUE SCALE  |  bar = 1.75 m villager  |  triad at grip origin: X red, Y green, Z blue; "
              "yellow = grip axis, cyan = front axis; label = tris", (0.0, -0.2, 2.42), cam, 0.09, align="LEFT")
    sc.render.resolution_percentage = 100
    _render(sc, os.path.join(DOC_DIR, "props_sheet.jpg"), 78)


def sheet_grip():
    """Per-prop close-up tiles centred on the origin, composited into one sheet."""
    import numpy as np
    contract = _load_contract()["hand"]
    tris = _report_tris()
    names = [n for n in HAND if os.path.exists(os.path.join(LIFE_DIR, n + ".glb"))]
    T = 300
    cols = 8
    rows = math.ceil(len(names) / cols)
    sheet = np.ones((rows * T, cols * T, 4), dtype=np.float32)
    tmp = os.path.join(SCRATCH, "tile.png")
    for i, n in enumerate(names):
        sc = _new_scene()
        objs, roots = _import(os.path.join(LIFE_DIR, n + ".glb"))
        contr = contract[n]
        cam = _camera(sc, (0, 0, 0), 0.9, (T, T), az_deg=30, el_deg=20)
        _triad((0, 0, 0), 0.14, 0.009, contr["grip_axis"], contr["front_axis"])
        _text(sc, f"{n}", (0, -0.3, -0.29), cam, 0.06)
        sc.render.image_settings.file_format = "PNG"
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        im = bpy.data.images.load(tmp)
        a = np.array(im.pixels[:], dtype=np.float32).reshape(T, T, 4)
        bpy.data.images.remove(im)
        r, c = divmod(i, cols)
        y0 = (rows - 1 - r) * T
        sheet[y0:y0 + T, c * T:(c + 1) * T] = a
        print("tile", n, flush=True)
    sc = bpy.context.scene
    out = os.path.join(DOC_DIR, "props_grip.jpg")
    im = bpy.data.images.new("gsheet", cols * T, rows * T, alpha=False)
    im.pixels.foreach_set(sheet.ravel())
    im.filepath_raw = out
    im.file_format = "JPEG"
    sc.render.image_settings.quality = 80
    im.save()
    print("sheet", out, os.path.getsize(out) // 1024, "KB")


def sheet_scene():
    tris = _report_tris()
    sc = _new_scene()
    names = [n for n in SCENE if os.path.exists(os.path.join(LIFE_DIR, n + ".glb"))]
    items = {}
    for n in names:
        objs, roots = _import(os.path.join(LIFE_DIR, n + ".glb"))
        lo, hi = _bounds(objs)
        items[n] = (objs, roots, lo, hi)
    rowlim = 9.0
    rows = [[]]
    wsum = 0.0
    for n in names:
        w = max(items[n][3].x - items[n][2].x, 0.5) + 0.5
        if wsum + w > rowlim and rows[-1]:
            rows.append([])
            wsum = 0.0
        rows[-1].append(n)
        wsum += w
    pos = []
    z0s = []
    rowz = 0.0
    maxw = 0.0
    for r, row in enumerate(rows):
        x = 0.0
        rh = max((items[n][3].z - items[n][2].z) for n in row)
        rz = -r * 2.7
        z0s.append(rz)
        for n in row:
            objs, roots, lo, hi = items[n]
            w = max(hi.x - lo.x, 0.5)
            cx = x + w / 2 + 0.2
            d = Vector((cx - (lo.x + hi.x) / 2, 0.0 - (lo.y + hi.y) / 2, rz))
            _shift(roots, d)
            pos.append((n, cx, rz))
            x = cx + w / 2 + 0.3
        maxw = max(maxw, x)
    nrow = len(rows)
    height = nrow * 2.7 + 0.3
    W = 3000
    Wm = maxw + 0.9
    H = int(W * height / Wm)
    cam = _camera(sc, (Wm / 2 - 0.7, 0, -(nrow - 1) * 2.7 / 2 + 0.8), Wm, (W, H), az_deg=18, el_deg=16)
    for r, rz in enumerate(z0s):
        _box(sc, (maxw + 0.3, 3.0, 0.03), (maxw / 2 - 0.1, 0, rz - 0.016), (0.42, 0.56, 0.27))
        _human_bar(sc, cam, -0.5, rz)
    for (n, cx, rz) in pos:
        _text(sc, f"{n} {tris.get(n, '')}", (cx, -1.15, rz - 0.12), cam, 0.11)
    sc.render.resolution_percentage = 100
    _render(sc, os.path.join(DOC_DIR, "props_scene.jpg"), 78)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")]
    allp = list(HAND) + list(SCENE)
    if "--sheet-only" not in argv:
        main_build(names or allp)
    if "--sheet" in argv or "--sheet-only" in argv:
        os.makedirs(DOC_DIR, exist_ok=True)
        sheet_lineup()
        sheet_grip()
        sheet_scene()


main()
