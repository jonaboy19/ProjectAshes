"""Clinker-built wooden rowboat: lofted double-skin hull with stepped lapstrake
planks, a painted sheer strake, keel, stem post, transom, ribs, three thwarts,
oarlocks, two oars resting inside and a coiled painter rope.

Run: python3 make_rowboat.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. 4.0 m long (Y), 1.45 m beam (X), ~0.85 m high at the
bow. Origin at the bottom of the keel, midships (z=0 is the lowest point);
design waterline is z=+0.25, so to float it place the origin 0.25 m below the
water surface. Bow points Blender -Y = Godot +Z; transom stern at +Y.
"""
import os, sys, math, random
import bpy, bmesh
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("Rowboat", seed=19)
k.grime_amt = 0.0
HULL = k.material("Hull", rough=0.6, spec=0.5)
WOOD = k.material("Wood", rough=0.78)
ROPE = k.material("Rope", rough=1.0, spec=0.2)
METAL = k.material("Metal", rough=0.4, metal=1.0)

L, BEAM = 4.0, 1.45
STRAKES = 6            # planks per side
NS = 18                # stations along the length
OUTER = [hexc("8a5a34"), hexc("7d5230"), hexc("93633a"), hexc("80552f"), hexc("8c5d36")]
SHEER = hexc("2f6f78")         # painted top strake (teal)
BOTTOM = hexc("3c2f25")        # tarred bottom
INNER = hexc("b08a5e")

def half_width(t):
    """t in [-1 (bow), 1 (stern)] -> half beam."""
    if t < 0:
        return BEAM / 2 * (1 - abs(t) ** 2.1) ** 0.75
    return BEAM / 2 * (1 - 0.52 * t ** 2.4)

def keel_z(t):
    return 0.06 + 0.28 * max(0.0, -t) ** 3 + 0.08 * max(0.0, t) ** 3

def sheer_z(t):
    return 0.62 + 0.2 * max(0.0, -t) ** 2 + 0.07 * max(0.0, t) ** 2

def section(t, j, side, inset=0.0):
    """Point j (0 keel .. STRAKES top) on a station; lapstrake step outward."""
    u = j / STRAKES
    w = half_width(t)
    kz, sz = keel_z(t), sheer_z(t)
    a = u * math.pi / 2
    x = w * math.sin(a) ** 0.85
    z = kz + (sz - kz) * (1 - math.cos(a)) ** 0.9
    x = max(0.0, x - inset)
    z = z + inset * 0.6 * (1 - u)
    return Vector((side * x, t * L / 2, z))

t_vals = [-1 + 2 * i / (NS - 1) for i in range(NS)]
t_vals[0] = -0.995
bm = bmesh.new()
lay = bm.faces.layers.int.new("cid")
keys = []
def face(vs, col):
    f = bm.faces.new(vs)
    keys.append(col)
    f[lay] = len(keys) - 1
    return f
TH = 0.035
for side in (-1, 1):
    # each strake is its own band of quads, lower edge pushed out -> clinker step
    for j in range(STRAKES):
        col_outer = BOTTOM if j < 2 else (SHEER if j == STRAKES - 1 else vary(OUTER[j % len(OUTER)], 0.04))
        lo_o, hi_o, lo_i, hi_i = [], [], [], []
        for t in t_vals:
            p0 = section(t, j, side)
            p1 = section(t, j + 1, side)
            out = Vector((side * 0.018, 0, -0.006)) * min(1.0, half_width(t) / 0.2)
            lo_o.append(bm.verts.new(p0 + out))
            hi_o.append(bm.verts.new(p1))
            lo_i.append(bm.verts.new(section(t, j, side, TH)))
            hi_i.append(bm.verts.new(section(t, j + 1, side, TH)))
        for i in range(NS - 1):
            a, b = (i, i + 1) if side > 0 else (i + 1, i)
            face((lo_o[a], lo_o[b], hi_o[b], hi_o[a]), vary(col_outer, 0.03))
            face((hi_i[a], hi_i[b], lo_i[b], lo_i[a]), vary(INNER if j > 0 else mix(INNER, (0.3, 0.25, 0.2), 0.4), 0.04))
            # plank lower edge (the visible clinker lip)
            face((lo_i[a], lo_i[b], lo_o[b], lo_o[a]), mix(col_outer, (0, 0, 0), 0.35))
        if j == STRAKES - 1:   # gunwale top
            for i in range(NS - 1):
                a, b = (i, i + 1) if side > 0 else (i + 1, i)
                face((hi_o[a], hi_o[b], hi_i[b], hi_i[a]), hexc("6b4a2c"))
        # transom end cap for this strake
        a = NS - 1
        vs = (lo_o[a], hi_o[a], hi_i[a], lo_i[a]) if side > 0 else (lo_i[a], hi_i[a], hi_o[a], lo_o[a])
        face(vs, hexc("7a5230"))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
k._merge(bm, HULL, (1, 1, 1), None, 35, 0.0, lambda f: keys[f[lay]], False)

# Transom board (flat stern panel)
tS = t_vals[-1]
pts = [(section(tS, j, 1).x + 0.02, section(tS, j, 1).z) for j in range(STRAKES + 1)]
poly = [(-x, z) for x, z in reversed(pts)] + pts[1:]
k.prism(poly, 0.05, (0, L / 2 * tS + 0.02, 0), WOOD, hexc("6e4a2c"), rot=(0, 0, 0))
k.prism([(-0.18, 0.35), (0.18, 0.35), (0.18, 0.47), (-0.18, 0.47)], 0.02, (0, L / 2 * tS + 0.05, 0), WOOD, SHEER)

# Keel + stem post
k.beam((0, -L / 2 * 0.6, 0.0), (0, L / 2 * 0.97, 0.0), 0.08, WOOD, hexc("4a3526"), bevel=0.01, width=0.07)
stem = []
for i in range(7):
    t = -0.6 - 0.4 * i / 6
    stem.append(Vector((0, t * L / 2 - 0.02, keel_z(t) - 0.06 * (1 - i / 6))))
stem.append(Vector((0, -L / 2 - 0.03, sheer_z(-1.0) + 0.02)))
for a, b in zip(stem[:-1], stem[1:]):
    k.beam(a, b, 0.06, WOOD, hexc("4a3526"), bevel=0.0, width=0.06)

# Ribs (inside frames), thwarts, oarlocks
for t in (-0.55, -0.3, -0.05, 0.2, 0.45, 0.7):
    for side in (-1, 1):
        prev = None
        for j in range(0, STRAKES + 1, 2):
            p = section(t, j, side, TH + 0.02)
            if prev is not None:
                k.beam(prev, p, 0.035, WOOD, hexc("8f6a42"), bevel=0, width=0.05)
            prev = p
for t, wdt in ((-0.45, 0.24), (0.05, 0.28), (0.62, 0.3)):
    zz = sheer_z(t) - 0.16
    w = half_width(t) * 2 - 0.12
    k.box((w, wdt, 0.04), (0, t * L / 2, zz), WOOD, vary(hexc("a57d52"), 0.06), bevel=0.01)
    for side in (-1, 1):
        k.box((0.1, wdt, 0.1), (side * (w / 2 - 0.05), t * L / 2, zz - 0.06), WOOD, hexc("7a5230"))
for side in (-1, 1):
    tt = 0.2
    p = section(tt, STRAKES, side)
    k.box((0.05, 0.05, 0.12), (p.x, p.y, p.z + 0.06), METAL, hexc("5d5a55"))
    k.box((0.05, 0.14, 0.03), (p.x, p.y, p.z + 0.12), METAL, hexc("5d5a55"))
# Floorboards
for i in range(5):
    x = -0.34 + i * 0.17
    k.box((0.14, 2.3, 0.025), (x, 0.25, 0.14 + abs(x) * 0.35), WOOD, vary(hexc("9a7650"), 0.08))

# Oars resting along the thwarts
for side in (-1, 1):
    a = Vector((side * 0.42, -1.25, 0.5))
    b = Vector((side * 0.3, 1.55, 0.62))
    k.log(a, b, 0.028, WOOD, hexc("c8a878"), segs=6, noise_amt=0.0)
    d = (b - a).normalized()
    bc = b + d * 0.35
    k.box((0.14, 0.6, 0.018), ((b.x + bc.x) / 2, (b.y + bc.y) / 2 + 0.05, (b.z + bc.z) / 2 + 0.02), WOOD,
          hexc("c8a878"), rot=(math.atan2(d.z, d.y) * 0.5, 0, 0), bevel=0.005)
    k.box((0.145, 0.15, 0.02), ((b.x + bc.x) / 2, bc.y + 0.12, bc.z + 0.03), WOOD, SHEER)

# Painter rope coil in the bow
for j in range(3):
    k.ring(0.13 - j * 0.015, 0.16 - j * 0.015, 0.03, (0, -1.35, 0.3 + j * 0.028), ROPE, vary(hexc("b89c6a"), 0.05),
           rot=(math.pi / 2, 0, 0), segs=12)
k.cyl(0.02, 0.04, (0, -L / 2 - 0.02, sheer_z(-1.0) - 0.05), METAL, hexc("5d5a55"), rot=(math.pi / 2, 0, 0), segs=6)

print("triangles:", k.tri_count())
k.finish(cam_dir=(1.2, -1.3, 0.8), fit=0.85)
