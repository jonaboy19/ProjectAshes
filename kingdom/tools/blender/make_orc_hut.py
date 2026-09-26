"""Orc round hut: a ring wall of upright logs on an earth berm, a conical roof
of patchwork hides and furs sagging between crossed rafter poles (tipi-style
smoke-hole crown), a rope binding, a painted zigzag band, a tusk-arched
doorway with a horned skull and hide door flap, plus a hide drying frame,
a chopping stump with an axe and a firewood pile.

Run: python3 make_orc_hut.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Wall ring 5.6 m diameter, roof eaves ~7.2 m diameter,
pole tips ~5.9 m high. Overall footprint about 8 x 8 m with the props.
Origin at ground centre of the hut. The doorway faces Blender -Y = Godot +Z
(opening ~1.3 m wide, 1.9 m tall).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector
from ra_kit import Kit, hexc, vary, mix

k = Kit("OrcHut", seed=61)
WOOD = k.material("Wood", rough=0.85)
HIDE = k.material("Hide", rough=0.9, spec=0.3)
EARTH = k.material("Earth", rough=1.0, spec=0.2)
BONE = k.material("Bone", rough=0.6, spec=0.45)
ROPE = k.material("Rope", rough=1.0, spec=0.2)
METAL = k.material("Metal", rough=0.45, metal=1.0)

LOGS = [hexc("6e5238"), hexc("5f4630"), hexc("7a5c3f"), hexc("67503a")]
HIDES = [hexc("9a7148"), hexc("87603c"), hexc("b08658"), hexc("7a5434"), hexc("a57a4f"), hexc("6f6a60"),
         hexc("8c6a4a")]
RED = hexc("9e2b22")
BLACK = hexc("2a221c")
BONE_C = hexc("e0d5bc")

RW = 2.8            # wall radius
WH = 2.0            # wall height
ER, EZ = 3.5, 2.45  # eave radius / height
AZ = 5.6            # roof apex height
DOOR_HALF = math.radians(14)

# ------------------------------------------------------------------ berm + wall
k.cyl(RW + 0.45, 0.35, (0, 0, -0.05), EARTH, hexc("5a4632"), segs=24, r2=RW + 0.05, smooth=None)
k.cyl(RW - 0.1, 2.98, (0, 0, 0), EARTH, hexc("2b2119"), segs=20, caps=False, smooth=None, var=0)     # dark mud core
n_logs = int(2 * math.pi * RW / 0.31)
for i in range(n_logs):
    a = i / n_logs * math.tau
    rel = (a - 1.5 * math.pi + math.pi) % math.tau - math.pi   # angle from the front (-Y)
    if abs(rel) < DOOR_HALF:
        continue
    r = random.uniform(0.13, 0.17)
    h = WH + random.uniform(-0.1, 0.15)
    x, y = math.cos(a) * RW, math.sin(a) * RW
    k.log((x, y, -0.3), (x, y, h), r, WOOD, vary(random.choice(LOGS), 0.08), segs=7, noise_amt=0.02,
          ring_step=1.2, end_color=hexc("a88a62"))
# wall-top ring beam (bent log) the rafters sit on
pts = [(math.cos(i / 24 * math.tau) * RW, math.sin(i / 24 * math.tau) * RW, WH + 0.1) for i in range(25)]
k.tube(pts, [0.12] * 25, WOOD, hexc("5a432e"), segs=6, cap_start=False, point_end=False, smooth=70)
# short posts from the ring beam up to the rafters (the gap is closed by the dark core)
for i in range(14):
    a = (i + 0.5) / 14 * math.tau + 0.11
    k.log((math.cos(a) * RW, math.sin(a) * RW, WH + 0.1), (math.cos(a) * RW, math.sin(a) * RW, 2.85), 0.08, WOOD,
          hexc("5a432e"), segs=5, ring_step=2.0)

# ------------------------------------------------------------------ hide roof
NB = 16             # rafter bays
SUB = 2             # vertices per bay (rafter + sag)
RINGS = 8
t = bmesh.new()
lay = t.faces.layers.int.new("cid")
keys = []
rows = []
for j in range(RINGS + 1):
    f = j / RINGS
    row = []
    for i in range(NB * SUB):
        a = i / (NB * SUB) * math.tau + 0.11
        on_rafter = (i % SUB == 0)
        rr = ER + (0.18 - ER) * f
        z = EZ + (AZ - 0.25 - EZ) * f
        if not on_rafter and 0 < j < RINGS:
            sag = 0.1 * math.sin(f * math.pi) + 0.03
            rr -= sag * 0.6
            z -= sag
        rr += random.uniform(-0.03, 0.03)
        z += random.uniform(-0.03, 0.03)
        row.append(t.verts.new((math.cos(a) * rr, math.sin(a) * rr, z)))
    rows.append(row)
# ragged hanging fringe below the eave
fringe = []
for i in range(NB * SUB):
    a = i / (NB * SUB) * math.tau + 0.11
    drop = 0.28 if i % 2 else 0.12
    rr = ER + 0.05
    fringe.append(t.verts.new((math.cos(a) * rr, math.sin(a) * rr, EZ - drop - random.uniform(0, 0.08))))
patch = {}
N = NB * SUB
for j in range(RINGS):
    for i in range(N):
        i2 = (i + 1) % N
        bay = i // SUB
        band = j // 2 if (bay % 3) else (j + 1) // 3        # staggered patch seams
        if (bay, band) not in patch:
            patch[(bay, band)] = vary(random.choice(HIDES), 0.09, 0.04)
        c = patch[(bay, band)]
        if (j + 1) % 2 == 0 and bay % 3:                     # stitched seam darkening
            c = mix(c, BLACK, 0.06)
        a, b, cc, d = rows[j][i], rows[j][i2], rows[j + 1][i2], rows[j + 1][i]
        if j == 3:      # painted zigzag band: alternate triangle colours
            f1 = t.faces.new((a, b, cc)); keys.append(RED if i % 2 == 0 else hexc("dcc9a4")); f1[lay] = len(keys) - 1
            f2 = t.faces.new((a, cc, d)); keys.append(hexc("dcc9a4") if i % 2 == 0 else RED); f2[lay] = len(keys) - 1
        else:
            f = t.faces.new((a, b, cc, d)); keys.append(c); f[lay] = len(keys) - 1
for i in range(N):
    i2 = (i + 1) % N
    f = t.faces.new((fringe[i], fringe[i2], rows[0][i2], rows[0][i]))
    keys.append(mix(patch[(i // SUB, 0)], BLACK, 0.15)); f[lay] = len(keys) - 1
bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
for f in t.faces:   # make sure the roof faces outward/up
    c = f.calc_center_median()
    if f.normal.dot(Vector((c.x, c.y, 0.8))) < 0:
        f.normal_flip()
k._merge(t, HIDE, (1, 1, 1), None, 50, 0.0, lambda f: keys[f[lay]], False)
# rafter poles laid over the hides, crossing above the smoke hole
for i in range(NB):
    a = i / NB * math.tau + 0.11
    lo = Vector((math.cos(a) * (ER + 0.25), math.sin(a) * (ER + 0.25), EZ - 0.12))
    top = Vector((0, 0, AZ - 0.2))
    d = (top - lo).normalized()
    hi = top + d * random.uniform(0.7, 1.1) + Vector((random.uniform(-0.05, 0.05), random.uniform(-0.05, 0.05), 0))
    k.log(lo + Vector((0, 0, 0.06)), hi, 0.07, WOOD, vary(hexc("6a4f35"), 0.08), segs=5, r_end=0.05,
          noise_amt=0.01, ring_step=1.6)
# rope binding round the roof and round the pole crossing
for zf, extra in ((0.45, 0.04), (0.92, 0.07)):
    rr = ER + (0.18 - ER) * zf + extra
    z = EZ + (AZ - 0.25 - EZ) * zf + 0.05
    pts = [(math.cos(i / 28 * math.tau) * rr, math.sin(i / 28 * math.tau) * rr, z) for i in range(29)]
    k.tube(pts, [0.035] * 29, ROPE, hexc("a58a5c"), segs=4, cap_start=False, point_end=False, smooth=70)
k.cyl(0.25, 0.05, (0, 0, AZ - 0.2), EARTH, hexc("1c1612"), segs=10, var=0)   # smoke hole shadow

# ------------------------------------------------------------------ doorway
FY = -RW
for sx in (-1, 1):
    k.log((sx * 0.72, FY - 0.05, -0.3), (sx * 0.72, FY - 0.05, 2.3), 0.16, WOOD, hexc("4f3a28"), segs=7,
          noise_amt=0.02, ring_step=1.2)
    # great tusks arching over the door
    pts = [(sx * 1.05, FY - 0.3, -0.1), (sx * 1.12, FY - 0.5, 0.9), (sx * 0.98, FY - 0.52, 1.8),
           (sx * 0.62, FY - 0.42, 2.45), (sx * 0.22, FY - 0.25, 2.65)]
    k.tube(pts, [0.16, 0.14, 0.11, 0.07, 0.0], BONE, BONE_C, segs=8)
    k.cyl(0.19, 0.18, (sx * 1.05, FY - 0.35, -0.05), ROPE, hexc("7a5a3a"), segs=8)          # tusk socket binding
k.log((-1.0, FY - 0.08, 2.15), (1.0, FY - 0.08, 2.15), 0.14, WOOD, hexc("4f3a28"), segs=7, noise_amt=0.02)
k.skull((0, -3.25, 3.0), (-0.35, 0, 0), 1.7, BONE, bone=BONE_C, dark=hexc("1e1712"), horn_c=hexc("3f352b"),
        tusks=True)
# hide door flap, half rolled up
flap = bmesh.new()
cols = 6
rows_f = 4
vv = []
for j in range(rows_f + 1):
    row = []
    for i in range(cols + 1):
        x = -0.62 + 1.24 * i / cols
        z = 2.05 - 0.9 * j / rows_f
        y = FY + 0.02 - 0.04 * math.sin(i / cols * math.pi) - 0.03 * math.sin(j * 1.7 + i)
        row.append(flap.verts.new((x, y, z)))
    vv.append(row)
for j in range(rows_f):
    for i in range(cols):
        flap.faces.new((vv[j][i], vv[j][i + 1], vv[j + 1][i + 1], vv[j + 1][i]))
k._merge(flap, HIDE, hexc("8a6240"), None, 60, 0.06, None, False)
k.log((-0.66, FY - 0.04, 1.12), (0.66, FY - 0.04, 1.12), 0.11, HIDE, hexc("7a5434"), segs=8, noise_amt=0.02)
for sx in (-1, 1):   # painted claw glyph on the flap
    k.quad(0.07, 0.42, (sx * 0.16, FY - 0.03, 1.62), HIDE, RED, rot=(0, sx * 0.25, 0))
k.quad(0.07, 0.48, (0, FY - 0.035, 1.6), HIDE, RED)
k.box((1.5, 0.9, 0.12), (0, FY - 0.55, 0.02), EARTH, hexc("6b5a48"), bevel=0.04, rot=(0, 0, 0.03))  # threshold stone

# ------------------------------------------------------------------ props
# upright hide drying rack (front right)
k.push((2.9, -2.6, 0), (0, 0, math.radians(-35)))
for sx in (-1, 1):
    k.log((sx * 0.8, 0, -0.2), (sx * 0.8, 0, 2.0), 0.06, WOOD, hexc("6a4f35"), segs=6, noise_amt=0.01)
    k.log((sx * 0.8, 0, 1.2), (sx * 0.8, 0.7, -0.1), 0.045, WOOD, hexc("5a432e"), segs=5, noise_amt=0.01)  # prop
for z in (0.35, 1.85):
    k.log((-0.95, 0, z), (0.95, 0, z), 0.045, WOOD, hexc("6a4f35"), segs=5, noise_amt=0.01)
pelt = [(-0.5, 0.0), (-0.28, 0.08), (0.28, 0.08), (0.5, 0.0), (0.62, 0.3), (0.5, 0.65), (0.68, 1.05), (0.4, 1.3),
        (-0.4, 1.3), (-0.68, 1.05), (-0.5, 0.65), (-0.62, 0.3)]
k.prism(pelt, 0.02, (0, -0.03, 0.45), HIDE, hexc("a88058"))
k.prism([(-0.15, 0.3), (0.15, 0.3), (0.0, 0.95)], 0.01, (0, -0.045, 0.45), HIDE, RED)
for (x0, z0, x1, z1) in ((-0.62, 0.8, -0.95, 1.1), (0.62, 0.8, 0.95, 1.1), (-0.5, 0.45, -0.8, 0.35), (0.5, 0.45, 0.8, 0.35),
                         (-0.4, 1.75, -0.4, 1.85), (0.4, 1.75, 0.4, 1.85)):
    k.beam((x0, -0.02, z0), (x1, -0.02, z1), 0.015, ROPE, hexc("b89c6a"), bevel=0)   # lacing
k.pop()
# chopping stump with an axe and a firewood pile (left side)
k.cyl(0.35, 0.55, (-2.6, -2.7, 0), WOOD, hexc("6e5238"), segs=10, r2=0.32, noise_amt=0.02)
k.cyl(0.32, 0.01, (-2.6, -2.7, 0.55), WOOD, hexc("b89a6c"), segs=10)
k.log((-2.55, -2.62, 0.6), (-2.3, -2.95, 1.25), 0.03, WOOD, hexc("4a3526"), segs=5)
k.prism([(0, 0), (0.24, -0.05), (0.26, 0.2), (0.0, 0.12)], 0.03, (-2.62, -2.57, 0.52), METAL, hexc("6a6660"),
        rot=(0, 0, math.radians(-50)))
for i in range(9):
    row = i // 4
    k.log((-3.6, -1.1 + (i % 4) * 0.2 + row * 0.1, 0.1 + row * 0.18), (-3.0, -1.1 + (i % 4) * 0.2 + row * 0.1,
          0.1 + row * 0.18), 0.09, WOOD, vary(hexc("7a5c3f"), 0.1), segs=6, end_color=hexc("c29a68"))

print("triangles:", k.tri_count())
k.finish(cam_dir=(1.0, -1.7, 0.6), fit=0.85)
