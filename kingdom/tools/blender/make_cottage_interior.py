"""Cottage interior: a humble village cottage room built as an open-fronted film
set for the player's birth cutscene. Three plaster-and-timber walls, a plank
floor, exposed ceiling joists and summer beams, a stone hearth with glowing
embers and flames, a rocking cradle with a swaddled baby, the mother's bed with
a patchwork quilt, a table with candles, a jug and bowls, wall shelves with
pots, dried herbs hanging from a beam, an oval rag rug, stools, a plank door
and a small moonlit window.

Run: python3 make_cottage_interior.py <out.glb> [preview.png]   (bpy, Blender 5.x)
The preview is a night-time render from the open side (warm hearth + candle
point lights, dim blue fill), not the kit's daylight preview. Detail shots:
RA_CAM="x,y,z" RA_TARGET="x,y,z" RA_SAMPLES=32 RA_EXPOSURE=0.0.
About 19.6k triangles. Emissive materials (Ember, Flame, FlameCore,
CandleFlame, and a faint blue Glass) glow with Godot's glow enabled; they
light nothing on their own, so add OmniLights at the positions below.

Scale/facing: metres. Room interior 6.0 m (X) x 5.0 m (Y) x 3.0 m (floor to
ceiling boards); inner wall faces at x = +-3.0 and y = +2.5, walls 0.22 m thick.
Origin at the floor centre of the room, floor surface z = 0.
The FRONT wall (Blender -Y = Godot +Z) is left OPEN: the room is filmed from
outside, looking toward Blender +Y (Godot -Z). Front corner posts at
x = +-3.1, y = -2.56 and a header beam at z 2.74-3.06 frame the opening.

Key positions (Blender x, y, z  ->  Godot x, y, z = x, z, -y):
- Cradle:       base centre (1.0, 1.2, 0)       -> Godot (1.0, 0, -1.2)
                0.86 x 0.5 m, long axis along X, headboard at +X, rim z ~0.41-0.57,
                mattress top z ~0.35.
  Baby:         face (1.19, 1.2, 0.40)          -> Godot (1.19, 0.40, -1.2)
                bundle centre (1.02, 1.2, 0.37)  -> Godot (1.02, 0.37, -1.2)
- Bed:          frame centre (-2.35, 1.33, 0), 1.2 x 2.15 m, head at +Y
                                                 -> Godot (-2.35, 0, -1.33)
  Mother rest:  quilt top centre (-2.35, 1.1, 0.62) -> Godot (-2.35, 0.62, -1.1)
  Pillow:       (-2.35, 2.1, 0.67)              -> Godot (-2.35, 0.67, -2.1)
- Hearth:       firebox centre (0, 2.2, 0.1) in a stone breast x in [-0.9, 0.9],
                front face y = 1.95; fire light at (0, 2.15, 0.4)
                                                 -> Godot (0, 0.4, -2.15)
                mantel top z 1.42; hearthstone y in [1.45, 1.95].
- Candles (flame centres, on the table):
      C1 (1.60, -0.60, 1.021) -> Godot (1.60, 1.021, 0.60)
      C2 (1.75, -0.79, 0.951) -> Godot (1.75, 0.951, 0.79)
      C3 (1.52, -0.85, 0.911) -> Godot (1.52, 0.911, 0.85)
- Table:        centre (1.9, -0.7), top z 0.76  -> Godot (1.9, 0.76, 0.7)
- Window:       left wall x = -3.0, y in [-1.35, -0.55], z in [1.05, 1.85]
                (emissive blue "moonlit" glass; a cool light at (-2.7, -0.95, 1.5)
                sells it).
- Door:         right wall x = +3.0, y in [-2.2, -1.3], closed.
- Stools:       (1.15, -1.1) at the table, (-0.95, 1.35) by the hearth.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, noise
from ra_kit import Kit, hexc, vary, mix, srgb

k = Kit("CottageInterior", seed=1207)
k.grime, k.grime_amt = 0.5, 0.12

MATTE = k.material("Matte", rough=0.93)                     # plaster, stone
WOOD = k.material("Wood", rough=0.72)
CLOTH = k.material("Cloth", rough=1.0, spec=0.15)
CERAMIC = k.material("Ceramic", rough=0.45, spec=0.5)
METAL = k.material("Metal", rough=0.45, metal=1.0)
WAX = k.material("Wax", rough=0.5, spec=0.4)
GLASS = k.material("Glass", rough=0.1, metal=0.2, emission=hexc("7f9fe0"), strength=0.5, spec=1.0)
EMBER = k.material("Ember", rough=0.9, emission=hexc("ff3c08"), strength=1.5)
FLAME = k.material("Flame", rough=1.0, emission=hexc("ff5a0e"), strength=1.7)
FLAMECORE = k.material("FlameCore", rough=1.0, emission=hexc("ff9a2a"), strength=2.6)
CANDLE = k.material("CandleFlame", rough=1.0, emission=hexc("ffa040"), strength=3.0)

TIMBER = hexc("5c3c25")
TIMBER_D = hexc("452b1b")
OAK = hexc("94653d")
HONEY = hexc("b27d47")
PL1, PL2 = hexc("f0e1c0"), hexc("e2cda3")
FLOORS = [hexc("8d5f3b"), hexc("7b5234"), hexc("9c6b44"), hexc("6f4b30"), hexc("a4754b"), hexc("86583a")]
STONES = [hexc("857a6a"), hexc("948672"), hexc("766c60"), hexc("9c8e78"), hexc("7f7264"), hexc("8c7c66")]
LINEN = hexc("ece2cc")
SWADDLE = hexc("f7ecd4")
IRON = hexc("2f2c2a")

HW, HD, H = 3.0, 2.5, 3.0          # half width, half depth, ceiling height
FRONT = -HD


_TRI = []
def _tri_mark(name):
    _TRI.append((name, k.tri_count()))


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def soot(p):
    """0..1 soot/smoke amount at world point p (hearth plume + ceiling smoke)."""
    s = 0.0
    dx = abs(p.x)
    if p.y > 1.2 and dx < 1.7:
        s = max(s, (1 - dx / 1.7) * clamp((p.z - 0.9) / 1.6) * 0.85)
    if p.z > 2.2:
        s = max(s, 0.35 * clamp((p.z - 2.2) / 0.8) * (0.6 + 0.4 * clamp((p.y + 1) / 3.5)))
    return s


def plaster_col(p):
    n = noise.noise(p * 0.9 + Vector((3.1, 7.7, 1.3)))
    c = mix(PL1, PL2, clamp(0.5 + 0.6 * n))
    kk = 1 + 0.05 * noise.noise(p * 3.7 + Vector((9, 2, 5)))
    c = tuple(x * kk for x in c)
    if noise.noise(p * 0.55 + Vector((1, 1, 20))) > 0.38:          # old damp stains
        c = mix(c, hexc("c9b186"), 0.25)
    if p.z < 0.7:
        c = mix(c, hexc("8a7458"), 0.4 * (1 - p.z / 0.7) ** 1.5)    # scuffed skirting zone
    return mix(c, hexc("3a2f27"), soot(p))


def wood_soot(f):
    return soot(f.calc_center_median())


def lathe(profile, loc, mat, color, segs=12, smooth=50, rot=(0, 0, 0), var=0.05, grime=False, noise_amt=0.0,
          noise_scale=6.0, bend=(0.0, 0.0)):
    """Revolve a (radius, z) profile around local Z (pots, bowls, candles, flames).
    noise_amt pushes verts radially by 3D noise; bend offsets XY by bend*(z/zmax)^2."""
    t = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-5:
            rings.append([t.verts.new((0, 0, z))])
        else:
            rings.append([t.verts.new((math.cos(a) * r, math.sin(a) * r, z))
                          for a in (j / segs * math.tau for j in range(segs))])
    for i in range(len(rings) - 1):
        A, B = rings[i], rings[i + 1]
        if len(A) == 1 and len(B) == 1:
            continue
        for j in range(segs):
            j2 = (j + 1) % segs
            if len(A) == 1:
                t.faces.new((A[0], B[j2], B[j]))
            elif len(B) == 1:
                t.faces.new((A[j], A[j2], B[0]))
            else:
                t.faces.new((A[j], A[j2], B[j2], B[j]))
    zmax = max(z for _, z in profile) or 1.0
    off = random.uniform(0, 100)
    for v in t.verts:
        f = v.co.z / zmax
        if noise_amt:
            d = Vector((v.co.x, v.co.y, 0))
            if d.length > 1e-6:
                v.co += d.normalized() * noise.noise(v.co * noise_scale + Vector((off, 0, 0))) * noise_amt
        v.co.x += bend[0] * f * f
        v.co.y += bend[1] * f * f
    k._merge(t, mat, vary(color, var) if var else color, k.xf(loc, rot), smooth, 0.02, None, grime)


def plaster(x0, x1, z0, z1, seed, step=0.4):
    """Softly undulating plaster sheet in the local XZ plane facing -Y."""
    nx = max(1, math.ceil((x1 - x0) / step))
    nz = max(1, math.ceil((z1 - z0) / step))
    t = bmesh.new()
    grid = []
    for j in range(nz + 1):
        z = z0 + (z1 - z0) * j / nz
        row = []
        for i in range(nx + 1):
            x = x0 + (x1 - x0) * i / nx
            n = noise.noise(Vector((x * 1.3, z * 1.3, seed)))
            n2 = noise.noise(Vector((x * 4.1, z * 4.1, seed + 5)))
            row.append(t.verts.new((x, -(0.006 + 0.009 * (n * 0.5 + 0.5) + 0.003 * n2), z)))
        grid.append(row)
    for j in range(nz):
        for i in range(nx):
            t.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
    k._merge(t, MATTE, (1, 1, 1), None, 80, 0.0, None, False, loop_fn=lambda l: plaster_col(l.vert.co))


def j(a=0.01):
    return random.uniform(-a, a)


def post(x, z0, z1, w=0.18, d=0.1):
    k.box((w, d, z1 - z0), (x + j(0.006), -d / 2 + 0.004, (z0 + z1) / 2), WOOD, vary(TIMBER, 0.1, 0.02),
          bevel=0.014, rot=(j(0.006), j(0.006), 0), color_fn=None)


def rail(x0, x1, z, h=0.14, d=0.1):
    k.box((x1 - x0, d, h), ((x0 + x1) / 2, -d / 2 + 0.002, z), WOOD, vary(TIMBER, 0.1, 0.02), bevel=0.014,
          rot=(0, j(0.004), 0))


def brace(a, b):
    k.beam((a[0], -0.045, a[1]), (b[0], -0.045, b[1]), 0.09, WOOD, TIMBER, bevel=0.012, width=0.14)


_tri_mark("floor")
# ======================================================================== floor
k.box((6.5, 5.4, 0.15), (0, 0.05, -0.1), WOOD, hexc("3a281b"), var=0)
x = -HW
while x < HW - 0.02:
    w = random.uniform(0.2, 0.3)
    if HW - (x + w) < 0.12:
        w = HW - x
    y = FRONT - 0.05
    cuts = sorted(random.uniform(FRONT + 0.8, HD - 0.8) for _ in range(random.choice((1, 1, 1, 2))))
    for yb in cuts + [HD]:
        L = yb - y
        c = vary(random.choice(FLOORS), 0.07, 0.03)
        cx, cy = x + w / 2, y + L / 2
        if abs(cx) < 1.3 and cy > 0.6:        # worn + darker by the hearth
            c = mix(c, hexc("4a3222"), 0.3)
        if abs(cx + 0.3) < 1.0 and abs(cy) < 1.0:   # footpath sheen
            c = mix(c, hexc("b58a5c"), 0.12)
        k.box((w - 0.008, L - 0.008, 0.04), (cx, cy, -0.02 + j(0.003)), WOOD, c, bevel=0.007, var=0,
              rot=(j(0.004), j(0.004), j(0.002)))
        y = yb
    x += w
k.box((6.5, 0.16, 0.12), (0, FRONT - 0.1, -0.05), WOOD, TIMBER_D, bevel=0.02)   # front sill beam

_tri_mark("walls")
# ======================================================================== walls
# shells (outer body of the walls, behind the plaster sheets)
k.box((6.5, 0.22, 3.0), (0, HD + 0.11, 1.5), MATTE, PL2, var=0)
k.box((0.22, 5.42, 3.0), (HW + 0.11, 0.04, 1.5), MATTE, PL2, var=0)
WY0, WY1, WZ0, WZ1 = -1.35, -0.55, 1.05, 1.85      # window hole in the left wall (world y / z)
for (ya, yb, za, zb) in ((-2.67, 2.75, 0, WZ0), (-2.67, 2.75, WZ1, 3.0), (-2.67, WY0, WZ0, WZ1),
                         (WY1, 2.75, WZ0, WZ1)):
    k.box((0.22, yb - ya, zb - za), (-HW - 0.11, (ya + yb) / 2, (za + zb) / 2), MATTE, PL2, var=0)

# back wall (+Y), local x = world x
k.push((0, HD, 0))
plaster(-HW, HW, 0, H, seed=1.0)
rail(-HW, HW, 0.08, h=0.16)                 # sole plate
rail(-HW, HW, 2.89, h=0.22)                 # top plate
for xp in (-1.95, -1.05, 1.05, 1.95):
    post(xp, 0.16, 2.78)
for sx in (-1, 1):
    rail(min(sx * 2.04, sx * 2.9), max(sx * 2.04, sx * 2.9), 1.08)
    rail(min(sx * 1.14, sx * 1.86), max(sx * 1.14, sx * 1.86), 1.08)
    brace((sx * 1.14, 1.16), (sx * 1.86, 2.76))
    brace((sx * 2.04, 2.76), (sx * 2.86, 1.16))
k.pop()

# left wall (-X), local x = world y
k.push((-HW, 0, 0), (0, 0, math.pi / 2))
plaster(-HD, WY0, 0, H, seed=2.0)
plaster(WY0, WY1, 0, WZ0, seed=2.0)
plaster(WY0, WY1, WZ1, H, seed=2.0)
plaster(WY1, HD, 0, H, seed=2.0)
rail(-HD, HD, 0.08, h=0.16)
rail(-HD, HD, 2.89, h=0.22)
for xp in (-1.47, -0.43, 0.95):
    post(xp, 0.16, 2.78)
rail(-HD + 0.1, -1.56, 1.08)
rail(-0.34, 0.86, 1.08)
rail(1.04, HD - 0.1, 1.08)
rail(-1.38, -0.52, WZ0 - 0.07, h=0.12)       # window sill rail
rail(-1.38, -0.52, WZ1 + 0.07, h=0.14)       # window head rail
brace((-0.34, 1.16), (0.86, 2.76))
brace((1.04, 2.76), (2.35, 1.16))
brace((-2.35, 1.16), (-1.56, 2.2))
k.pop()
# window reveal, frame, leaded glass
for (ya, yb, za, zb) in ((WY0 - 0.02, WY0 + 0.03, WZ0, WZ1), (WY1 - 0.03, WY1 + 0.02, WZ0, WZ1)):
    k.box((0.22, yb - ya, zb - za), (-HW - 0.11, (ya + yb) / 2, (za + zb) / 2), MATTE, hexc("dccaa2"), var=0.03)
k.box((0.28, 0.9, 0.06), (-HW - 0.1, (WY0 + WY1) / 2, WZ0 - 0.01), WOOD, OAK, bevel=0.012)      # deep sill
k.box((0.22, 0.86, 0.06), (-HW - 0.11, (WY0 + WY1) / 2, WZ1 + 0.02), WOOD, TIMBER_D, bevel=0.01)
GX = -HW - 0.16
k.quad(0.8, 0.8, (GX, (WY0 + WY1) / 2, (WZ0 + WZ1) / 2), GLASS, hexc("22314f"), rot=(0, 0, math.pi / 2),
       var=0, grime=False)
for yy in (WY0 + 0.02, WY1 - 0.02, (WY0 + WY1) / 2):
    k.box((0.05, 0.04, 0.8), (GX + 0.02, yy, (WZ0 + WZ1) / 2), WOOD, TIMBER_D, grime=False)
for zz in (WZ0 + 0.02, WZ1 - 0.02, (WZ0 + WZ1) / 2):
    k.box((0.05, 0.8, 0.04), (GX + 0.02, (WY0 + WY1) / 2, zz), WOOD, TIMBER_D, grime=False)
for s in (-1, 1):                      # diamond leading
    for off in (-0.2, 0.2):
        k.box((0.01, 0.012, 0.56), (GX + 0.01, (WY0 + WY1) / 2 + off, (WZ0 + WZ1) / 2), METAL, IRON,
              rot=(s * math.pi / 4, 0, 0), grime=False, var=0)
# a small clay cup and dried flowers on the sill
lathe([(0, 0), (0.035, 0), (0.042, 0.05), (0.036, 0.09), (0.03, 0.09), (0.032, 0.05), (0, 0.012)],
      (-2.92, -0.75, WZ0 + 0.02), CERAMIC, hexc("a65d3a"), segs=10)
for i in range(5):
    a = i / 5 * math.tau
    tip = Vector((-2.92 + math.cos(a) * 0.05, -0.75 + math.sin(a) * 0.05, WZ0 + 0.26 + j(0.03)))
    k.tube([(-2.92, -0.75, WZ0 + 0.08), tip], [0.005, 0.004], CLOTH, hexc("7d7a4a"), segs=4, point_end=False)
    k.sphere(0.018, tip, CLOTH, random.choice([hexc("c9b6e0"), hexc("e6d27a"), hexc("f0ece0")]), subdiv=1,
             grime=False)

# right wall (+X), local x = -world y
k.push((HW, 0, 0), (0, 0, -math.pi / 2))
plaster(-HD, HD, 0, H, seed=3.0)
rail(-HD, HD, 0.08, h=0.16)
rail(-HD, HD, 2.89, h=0.22)
for xp in (-0.15, 1.18, 2.32):
    post(xp, 0.16, 2.78)
rail(-HD + 0.1, -0.24, 0.95)
rail(-0.06, 1.09, 1.08)
brace((-0.06, 1.16), (1.09, 2.76))
brace((-2.3, 2.76), (-0.24, 1.9))
# plank door (room side: ledges and a Z brace), local x 1.3..2.2
DX0, DX1, DH = 1.3, 2.2, 1.95
rail(1.18, 2.32, DH + 0.08, h=0.16)
xx = DX0
for i in range(5):
    w = (DX1 - DX0) / 5
    k.box((w - 0.008, 0.045, DH - j(0.01)), (xx + w / 2, -0.03, DH / 2), WOOD, vary(hexc("7a5234"), 0.08, 0.02),
          bevel=0.006, var=0)
    xx += w
for zz in (0.35, 1.6):
    k.box((DX1 - DX0 - 0.08, 0.035, 0.13), ((DX0 + DX1) / 2, -0.07, zz), WOOD, hexc("6a452b"), bevel=0.01)
k.beam((DX0 + 0.1, -0.07, 0.42), (DX1 - 0.1, -0.07, 1.53), 0.035, WOOD, hexc("6a452b"), bevel=0.008, width=0.12)
for zz in (0.35, 1.6):                 # iron strap hinges
    k.box((0.42, 0.012, 0.045), (DX1 - 0.21, -0.094, zz), METAL, IRON, var=0)
k.ring(0.035, 0.05, 0.012, (DX0 + 0.12, -0.1, 1.0), METAL, IRON, segs=10)
k.box((0.14, 0.02, 0.025), (DX0 + 0.14, -0.1, 1.12), METAL, IRON, var=0)   # latch bar
k.pop()

# front corner posts + header (the proscenium of the set)
for sx in (-1, 1):
    k.box((0.26, 0.26, 3.06), (sx * 3.1, FRONT - 0.06, 1.53), WOOD, TIMBER_D, bevel=0.025, rot=(0, j(0.004), 0))
    k.box((0.36, 0.34, 0.14), (sx * 3.1, FRONT - 0.06, 0.07), MATTE, vary(STONES[0], 0.05), bevel=0.03)
k.box((6.56, 0.26, 0.32), (0, FRONT - 0.06, 2.9), WOOD, TIMBER_D, bevel=0.025)

_tri_mark("ceiling")
# ======================================================================== ceiling
k.push((0, 0, 0))
for (yy, ww) in ((-0.9, 0.26), (1.2, 0.26)):           # summer beams along X
    k.beam((-HW - 0.05, yy + j(0.02), 2.71 + j(0.01)), (HW + 0.05, yy + j(0.02), 2.71 + j(0.01)), 0.26, WOOD,
           TIMBER_D, bevel=0.022, width=ww)
for i in range(8):                                        # joists along Y
    xj = -2.63 + i * 0.75 + j(0.03)
    k.box((0.12, 5.2, 0.15), (xj, 0.05, 2.915), WOOD, TIMBER, bevel=0.012, rot=(j(0.003), 0, j(0.004)),
          color_fn=lambda f, base=vary(TIMBER, 0.1): mix(base, hexc("2a1c13"), wood_soot(f)))
yb = -2.66
while yb < 2.72:                                         # ceiling boards across the joists
    w = random.uniform(0.2, 0.28)
    xb = -3.2
    for xe in [random.uniform(-1.5, 1.5), 3.2]:
        base = vary(hexc("6d4a30"), 0.1, 0.03)
        k.box((xe - xb - 0.006, w - 0.008, 0.03), ((xb + xe) / 2, yb + w / 2, 3.005), WOOD, base, var=0,
              color_fn=lambda f, b=base: mix(b, hexc("2a1c13"), wood_soot(f)))
        xb = xe
    yb += w
k.pop()

_tri_mark("hearth")
# ======================================================================== hearth
BX, BY, BTOP = 0.9, 1.95, 1.25          # breast half width, front face, stone top
OX, OZ = 0.52, 0.92                     # firebox opening half width / top
def stone():
    c = random.choice(STONES)
    if random.random() < 0.1:
        c = mix(c, hexc("6d5a48"), 0.35)
    return vary(c, 0.08, 0.03)
MORTAR = hexc("3a332c")
for (xa, xb, za, zb) in ((-BX + 0.02, -OX, 0, BTOP), (OX, BX - 0.02, 0, BTOP), (-OX, OX, OZ, BTOP)):
    k.box((xb - xa, 0.5, zb - za), ((xa + xb) / 2, BY + 0.3, (za + zb) / 2), MATTE, MORTAR, var=0)
k.box((2 * OX, 0.1, OZ), (0, 2.48, OZ / 2), MATTE, hexc("1d1814"), var=0)
k.grid_wall(2 * OX, OZ - 0.1, (0, 2.43, 0.1), MATTE, lambda: vary(mix(random.choice(STONES), hexc("1a1511"), 0.75), 0.2),
            bw=0.3, bh=0.18, gap=0.02, push=0.02, grime=False)
for sx in (-1, 1):
    k.push((sx * OX, 2.2, 0.1), (0, 0, sx * math.pi / 2))
    k.grid_wall(0.5, OZ - 0.1, (0, 0, 0), MATTE, lambda: vary(mix(random.choice(STONES), hexc("1a1511"), 0.7), 0.2),
                bw=0.25, bh=0.18, gap=0.02, push=0.015, grime=False)
    k.pop()
k.box((2 * OX, 0.5, 0.03), (0, 2.2, OZ - 0.01), MATTE, hexc("15110e"), var=0)            # firebox roof
k.box((2 * OX + 0.02, 0.5, 0.1), (0, 2.2, 0.05), MATTE, hexc("4a443e"), var=0.05)        # firebox floor
rows = [0.0, 0.24, 0.47, 0.7, OZ, 1.1, BTOP]
for r in range(len(rows) - 1):
    za, zb = rows[r], rows[r + 1]
    if r == 4:
        spans = [(-BX, -0.62), (-0.62, 0.62), (0.62, BX)]
    elif zb <= OZ + 1e-6:
        spans = []
        for (a, b) in ((-BX, -OX), (OX, BX)):
            if r % 2 == 0:
                spans.append((a, b))
            else:
                m = (a + b) / 2 + j(0.05)
                spans += [(a, m), (m, b)]
    else:
        xs = [-BX]
        while xs[-1] < BX - 0.4:
            xs.append(xs[-1] + random.uniform(0.28, 0.45))
        xs.append(BX)
        spans = list(zip(xs[:-1], xs[1:]))
    for (a, b) in spans:
        outer = abs(a + BX) < 1e-6 or abs(b - BX) < 1e-6
        dep = 0.58 if outer else random.uniform(0.1, 0.14)
        cy = BY - 0.03 + dep / 2
        col = mix(stone(), hexc("2f2822"), 0.25) if r == 4 and a < 0 < b else stone()
        k.box((b - a - 0.025, dep, zb - za - 0.025), ((a + b) / 2, cy, (za + zb) / 2), MATTE, col,
              bevel=0.025, jitter=0.006, rot=(j(0.012), j(0.012), j(0.01)), var=0)
# hearthstone slabs in front of the fire
for i, (xa, xb) in enumerate(((-1.05, -0.3), (-0.3, 0.42), (0.42, 1.05))):
    k.box((xb - xa - 0.02, 0.5, 0.09), ((xa + xb) / 2, 1.7, 0.035), MATTE, vary(hexc("7a746b"), 0.08), bevel=0.02,
          jitter=0.004, rot=(j(0.006), j(0.006), j(0.01)))
# oak mantel beam + plastered smoke hood up to the ceiling
k.box((2.16, 0.36, 0.17), (0, BY + 0.14, BTOP + 0.085), WOOD, hexc("4d3120"), bevel=0.025, rot=(0, j(0.004), 0))
t = bmesh.new()
bmesh.ops.create_cube(t, size=1.0)
for v in t.verts:
    top = v.co.z > 0
    hw = 0.62 if top else 0.94
    y0 = 2.12 if top else 1.97
    v.co = Vector((math.copysign(hw, v.co.x), y0 if v.co.y < 0 else 2.5, 3.0 if top else BTOP + 0.17))
bmesh.ops.bevel(t, geom=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5], offset=0.05,
                segments=2, affect='EDGES')
bmesh.ops.subdivide_edges(t, edges=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5], cuts=4)
k._merge(t, MATTE, (1, 1, 1), None, 60, 0.0, None, False,
         loop_fn=lambda l: mix(plaster_col(l.vert.co), hexc("2c241e"),
                              0.15 + 0.3 * clamp((3.0 - l.vert.co.z) / 1.6)))
# mantel things: a pair of small crocks and an unlit candle stub
lathe([(0, 0), (0.05, 0), (0.06, 0.06), (0.045, 0.12), (0.04, 0.13), (0, 0.13)], (-0.6, 2.05, BTOP + 0.17),
      CERAMIC, hexc("9a8a74"), segs=10)
lathe([(0, 0), (0.04, 0), (0.05, 0.05), (0.035, 0.09), (0, 0.09)], (-0.42, 2.07, BTOP + 0.17), CERAMIC,
      hexc("7c5638"), segs=10)
lathe([(0, 0), (0.07, 0), (0.08, 0.02), (0, 0.02)], (0.55, 2.05, BTOP + 0.17), METAL, hexc("8c8780"), segs=10)
k.cyl(0.022, 0.07, (0.55, 2.05, BTOP + 0.19), WAX, hexc("efe4c8"), segs=8)

# --- fire: andirons, logs, ash, embers, flames
FX, FY, FZ = 0.0, 2.2, 0.1
for sx in (-1, 1):
    k.box((0.03, 0.4, 0.03), (sx * 0.2, FY, FZ + 0.06), METAL, IRON, var=0)
    k.box((0.03, 0.03, 0.2), (sx * 0.2, FY - 0.19, FZ + 0.1), METAL, IRON, var=0)
    k.sphere(0.03, (sx * 0.2, FY - 0.19, FZ + 0.21), METAL, IRON, subdiv=1)
k.sphere(0.36, (FX, FY + 0.02, FZ - 0.01), MATTE, hexc("58514b"), scale=(1.0, 0.55, 0.12), subdiv=1, noise_amt=0.02,
         grime=False)
CHAR = hexc("2b1d14")
k.log((-0.36, 2.1, 0.19), (0.34, 2.26, 0.2), 0.06, WOOD, hexc("4a3321"), segs=8, end_color=hexc("c46a2c"),
      grime=False, zfn=lambda c, z: mix(c, CHAR, 0.6))
k.log((-0.3, 2.3, 0.2), (0.36, 2.12, 0.19), 0.055, WOOD, hexc("553a25"), segs=8, end_color=hexc("d9782f"),
      grime=False, zfn=lambda c, z: mix(c, CHAR, 0.5))
k.log((-0.16, 2.14, 0.3), (0.2, 2.26, 0.26), 0.045, WOOD, hexc("5a3d26"), segs=7, end_color=hexc("e08a3a"),
      grime=False, zfn=lambda c, z: mix(c, CHAR, 0.7))
for i in range(18):
    a = random.uniform(0, math.tau)
    rr = random.uniform(0, 1) ** 0.6
    ex, ey = FX + math.cos(a) * rr * 0.34, FY + math.sin(a) * rr * 0.16
    s = random.uniform(0.022, 0.045)
    col = random.choice([hexc("c8380c"), hexc("d85010"), hexc("a02408"), hexc("e0681a"), hexc("7a1a06")])
    k.sphere(s, (ex, ey, FZ + 0.025 + (1 - rr) * 0.03), EMBER, col, scale=(1.2, 1.0, 0.6), subdiv=0,
             noise_amt=s * 0.3, rot=(0, 0, a), grime=False, smooth=None)
FLAME_PROF = [(0, 0), (0.55, 0.04), (0.9, 0.16), (1.0, 0.3), (0.78, 0.5), (0.45, 0.72), (0.18, 0.9), (0, 1.0)]
for i, (dx, dy, hh, rr) in enumerate(((0.0, 0.0, 0.44, 0.09), (-0.13, 0.03, 0.31, 0.075), (0.14, -0.02, 0.34, 0.075),
                                      (-0.24, 0.02, 0.2, 0.055), (0.25, 0.04, 0.21, 0.055), (0.06, 0.07, 0.27, 0.065))):
    bend = (j(0.06) - dx * 0.25, j(0.03))
    lathe([(r * rr, z * hh) for r, z in FLAME_PROF], (FX + dx, FY + dy, FZ + 0.1), FLAME, hexc("b8400c"),
          segs=7, smooth=85, noise_amt=0.2 * rr, noise_scale=9, bend=bend)
    lathe([(r * rr * 0.55, z * hh * 0.6) for r, z in FLAME_PROF], (FX + dx, FY + dy - 0.035, FZ + 0.1), FLAMECORE,
          hexc("e08a2a"), segs=5, smooth=85, noise_amt=0.1 * rr, noise_scale=9, bend=(bend[0] * 0.6, bend[1] * 0.6))
# iron pot on a trivet at the hearth's edge, a poker and a log basket
k.ring(0.1, 0.12, 0.015, (0.72, 1.72, 0.2), METAL, IRON, segs=10, rot=(math.pi / 2, 0, 0))
for a in range(3):
    ang = a / 3 * math.tau
    k.beam((0.72 + math.cos(ang) * 0.11, 1.72 + math.sin(ang) * 0.11, 0.08),
           (0.72 + math.cos(ang) * 0.11, 1.72 + math.sin(ang) * 0.11, 0.2), 0.014, METAL, IRON, bevel=0)
lathe([(0, 0), (0.09, 0.0), (0.13, 0.06), (0.135, 0.13), (0.115, 0.17), (0.125, 0.18), (0.11, 0.18),
       (0.105, 0.17), (0, 0.17)], (0.72, 1.72, 0.19), METAL, hexc("383430"), segs=12)
k.tube([(0.61, 1.72, 0.37), (0.72, 1.72, 0.45), (0.83, 1.72, 0.37)], [0.006, 0.006, 0.006], METAL, IRON, segs=4,
       point_end=False)
k.beam((-0.78, 1.93, 0.08), (-0.66, 1.97, 0.95), 0.018, METAL, IRON, bevel=0)
for i, (lx, lz) in enumerate(((-1.45, 0.06), (-1.3, 0.06), (-1.15, 0.06), (-1.375, 0.17), (-1.225, 0.17),
                              (-1.3, 0.28))):
    lx += j(0.01)
    k.log((lx, 2.0, lz + j(0.01)), (lx + j(0.02), 2.44, lz + j(0.01)), 0.065, WOOD,
          random.choice([hexc("6b4a30"), hexc("7a5638"), hexc("5e422c")]), segs=7, end_color=hexc("c9a070"),
          noise_amt=0.012)

_tri_mark("cradle  (1.0, 1.2, 0)")
# ======================================================================== cradle  (1.0, 1.2, 0)
CRX, CRY = 1.0, 1.2
k.push((CRX, CRY, 0))
arc = []
for i in range(9):
    a = -0.5 + i / 8
    arc.append((math.sin(a) * 0.7, 0.7 - math.cos(a) * 0.7 + 0.005))
for sx in (-1, 1):                      # rockers (curve in YZ)
    k.prism(arc + [(0.3, 0.19), (-0.3, 0.19)], 0.05, (sx * 0.34, 0, 0), WOOD, HONEY, rot=(0, 0, math.pi / 2),
            bevel=0.008)
k.box((0.86, 0.5, 0.03), (0, 0, 0.2), WOOD, HONEY, bevel=0.01)
side = [(-0.43, 0), (0.43, 0), (0.43, 0.36), (0.32, 0.29), (0.16, 0.2), (-0.16, 0.2), (-0.32, 0.28), (-0.43, 0.33)]
for sy in (-1, 1):
    k.prism(side, 0.024, (0, sy * 0.238, 0.21), WOOD, vary(HONEY, 0.05), bevel=0.008)
    k.box((0.24, 0.01, 0.06), (0, sy * 0.252, 0.3), WOOD, mix(HONEY, hexc("6b4526"), 0.35), var=0)   # carved band
head = [(-0.26, 0), (0.26, 0), (0.26, 0.4)] + [(math.cos(a) * 0.26, 0.4 + math.sin(a) * 0.12)
                                               for a in (i / 6 * math.pi for i in range(1, 6))] + [(-0.26, 0.4)]
k.prism(head, 0.03, (0.43, 0, 0.19), WOOD, HONEY, rot=(0, 0, math.pi / 2), bevel=0.01)
foot = [(-0.26, 0), (0.26, 0), (0.26, 0.32)] + [(math.cos(a) * 0.26, 0.32 + math.sin(a) * 0.06)
                                                for a in (i / 6 * math.pi for i in range(1, 6))] + [(-0.26, 0.32)]
k.prism(foot, 0.03, (-0.43, 0, 0.19), WOOD, HONEY, rot=(0, 0, math.pi / 2), bevel=0.01)
k.ring(0.05, 0.075, 0.034, (0.43, 0, 0.47), WOOD, mix(HONEY, hexc("6b4526"), 0.4), rot=(0, 0, math.pi / 2), segs=10)
for cx in (-0.43, 0.43):
    for cy in (-0.25, 0.25):
        k.sphere(0.028, (cx, cy, 0.56 if cx > 0 else 0.52), WOOD, HONEY, subdiv=1)
# soft mattress, sheet, baby bundle and blanket
k.sphere(1.0, (0, 0, 0.29), CLOTH, LINEN, scale=(0.41, 0.23, 0.06), subdiv=1, grime=False)
BX0, BZ0 = 0.02, 0.37
k.sphere(1.0, (BX0, 0, BZ0), CLOTH, SWADDLE, scale=(0.17, 0.085, 0.068), subdiv=2, noise_amt=0.05, grime=False)
k.sphere(1.0, (0.215, 0, 0.375), CLOTH, SWADDLE, scale=(0.075, 0.08, 0.065), subdiv=2, grime=False)  # hood
k.sphere(0.05, (0.19, -0.004, 0.40), CLOTH, hexc("e9b89a"), subdiv=2, grime=False)   # face
k.sphere(0.009, (0.215, -0.045, 0.41), CLOTH, hexc("f2c8aa"), subdiv=1, grime=False)  # tiny fist hint
BLANKET = hexc("cf8f80")
k.sphere(1.0, (-0.1, 0, 0.385), CLOTH, BLANKET, scale=(0.23, 0.2, 0.05), subdiv=2, noise_amt=0.1, grime=False)
k.sphere(1.0, (0.07, 0, 0.40), CLOTH, mix(BLANKET, (1, 1, 1), 0.35), scale=(0.035, 0.19, 0.035), subdiv=2,
         grime=False)                            # turned-down edge
k.sphere(1.0, (-0.12, -0.262, 0.36), CLOTH, BLANKET, scale=(0.15, 0.012, 0.07), subdiv=1, noise_amt=0.08,
         rot=(0.08, 0, 0.05), grime=False)
k.sphere(1.0, (-0.12, -0.245, 0.418), CLOTH, BLANKET, scale=(0.14, 0.025, 0.02), subdiv=1, grime=False)
k.pop()

_tri_mark("bed (left)")
# ======================================================================== bed (left)
BCX, BCY = -2.35, 1.325
BX0_, BX1_, BY0_, BY1_ = -2.95, -1.75, 0.25, 2.4
for (px, py, ph) in ((BX0_ + 0.05, BY1_ - 0.05, 1.15), (BX1_ - 0.05, BY1_ - 0.05, 1.15),
                     (BX0_ + 0.05, BY0_ + 0.05, 0.75), (BX1_ - 0.05, BY0_ + 0.05, 0.75)):
    k.box((0.09, 0.09, ph), (px, py, ph / 2), WOOD, OAK, bevel=0.015)
    k.sphere(0.055, (px, py, ph + 0.035), WOOD, OAK, subdiv=1, scale=(1, 1, 0.8))
for sx in (BX0_ + 0.05, BX1_ - 0.05):
    k.box((0.06, BY1_ - BY0_ - 0.1, 0.16), (sx, BCY, 0.32), WOOD, vary(OAK, 0.06), bevel=0.012)
k.box((1.12, 0.05, 0.5), (BCX, BY1_ - 0.05, 0.72), WOOD, vary(OAK, 0.06), bevel=0.012)
k.prism([(-0.56, 0), (0.56, 0)] + [(math.cos(a) * 0.56, 0.1 + math.sin(a) * 0.16)
                                   for a in (i / 8 * math.pi for i in range(1, 8))], 0.05, (BCX, BY1_ - 0.05, 0.96),
        WOOD, OAK, bevel=0.012)
k.box((1.12, 0.05, 0.26), (BCX, BY0_ + 0.05, 0.47), WOOD, vary(OAK, 0.06), bevel=0.012)
k.box((0.9, 0.012, 0.3), (BCX, BY1_ - 0.08, 0.72), WOOD, mix(OAK, hexc("4a2e1c"), 0.3), var=0.02)  # panel
k.box((1.12, 2.02, 0.22), (BCX, BCY + 0.02, 0.47), CLOTH, hexc("d9ccae"), bevel=0.06)      # straw tick
k.sphere(1.0, (BCX, 2.1, 0.64), CLOTH, LINEN, scale=(0.42, 0.19, 0.08), subdiv=2, noise_amt=0.06, grime=False)
k.sphere(1.0, (BCX + 0.1, 1.98, 0.65), CLOTH, mix(LINEN, hexc("d8c9a8"), 0.3), scale=(0.28, 0.14, 0.06), subdiv=2,
         noise_amt=0.06, grime=False, rot=(0, 0, 0.1))
# draped patchwork quilt
QX0, QX1, QY0, QY1, QZ = -2.9, -1.8, 0.3, 1.8, 0.585
OV, RR = 0.3, 0.06
PATCH = [hexc("a3453a"), hexc("c8963e"), hexc("3f5a86"), hexc("7d9460"), hexc("e6d8bb"), hexc("b0603a"),
         hexc("6b4a6e"), hexc("d7b06a")]
t = bmesh.new()
lay = t.faces.layers.int.new("cid")
keys = []
NU, NV = 16, 18
grid = []
for jv in range(NV + 1):
    v = (QY0 - OV) + (QY1 - QY0 + OV) * jv / NV
    row = []
    for iu in range(NU + 1):
        u = (QX0 - 0.08) + (QX1 - QX0 + 0.08 + OV) * iu / NU
        dx = max(0.0, u - QX1)
        dxl = max(0.0, QX0 - u)
        dy = max(0.0, QY0 - v)
        ox, oy = dx - dxl, -dy
        d = math.hypot(ox, oy)
        px, py, pz = min(max(u, QX0), QX1), min(max(v, QY0), QY1), QZ
        n = noise.noise(Vector((u * 5, v * 5, 3.3)))
        if d > 1e-6:
            nx_, ny_ = ox / d, oy / d
            arcL = RR * math.pi / 2
            if d < arcL:
                out, down = RR * math.sin(d / RR), RR * (1 - math.cos(d / RR))
            else:
                out, down = RR, RR + (d - arcL)
            fold = 0.018 * math.sin((u + v) * 22) * clamp((d - arcL) / 0.1)
            px += nx_ * (out + fold * 0.6)
            py += ny_ * (out + fold * 0.6)
            pz -= down
            px += -ny_ * fold * 0.3
            py += nx_ * fold * 0.3
        else:
            e = min(u - QX0, QX1 - u, v - QY0, QY1 - v)
            pz += 0.014 * n + 0.03 * clamp(e / 0.3) * (0.6 + 0.4 * noise.noise(Vector((u * 2, v * 2, 8.8))))
        row.append((t.verts.new((px, py, pz)), u, v, d))
    grid.append(row)
for jv in range(NV):
    for iu in range(NU):
        a, b, c2, d2 = grid[jv][iu], grid[jv][iu + 1], grid[jv + 1][iu + 1], grid[jv + 1][iu]
        f = t.faces.new((a[0], b[0], c2[0], d2[0]))
        uc, vc = (a[1] + c2[1]) / 2, (a[2] + c2[2]) / 2
        dd = (a[3] + b[3] + c2[3] + d2[3]) / 4
        if dd > 0.24:
            col = hexc("3a3f5c")                     # dark border band
        else:
            pi_, pj_ = math.floor((uc - QX0) / 0.275), math.floor((vc - QY0) / 0.3)
            col = PATCH[(pi_ * 3 + pj_ * 5 + (pi_ * pj_) % 3) % len(PATCH)]
        keys.append(vary(col, 0.03))
        f[lay] = len(keys) - 1
bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
k._merge(t, CLOTH, (1, 1, 1), None, 70, 0.0, lambda f: keys[f[lay]], False)
k.box((1.14, 0.14, 0.035), (BCX + 0.03, QY1 + 0.05, QZ + 0.03), CLOTH, LINEN, bevel=0.015, grime=False)
# a folded shawl at the foot and a chamber of rushes basket beside the bed
k.box((0.5, 0.3, 0.06), (BCX + 0.15, 0.55, QZ + 0.06), CLOTH, hexc("8e3b32"), bevel=0.025, rot=(0, 0, 0.15),
      grime=False)
k.cyl(0.17, 0.26, (-1.5, 0.3, 0.0), WOOD, hexc("b0915c"), segs=10, r2=0.2, noise_amt=0.01, noise_scale=12)
k.ring(0.19, 0.215, 0.04, (-1.5, 0.3, 0.26), WOOD, hexc("8a6f45"), segs=10, rot=(math.pi / 2, 0, 0))
k.sphere(1.0, (-1.5, 0.3, 0.25), CLOTH, hexc("ddd0b4"), scale=(0.17, 0.17, 0.06), subdiv=1, noise_amt=0.2)

_tri_mark("table, stools")
# ======================================================================== table, stools
TX, TY, TZ = 1.9, -0.7, 0.76
k.push((TX, TY, 0))
for i in range(3):
    k.box((1.14 + j(0.01), 0.232, 0.05), (j(0.008), -0.232 + i * 0.234, TZ - 0.025), WOOD, vary(OAK, 0.08, 0.03),
          bevel=0.01, var=0, rot=(j(0.004), j(0.004), 0))
for sx in (-1, 1):
    for sy in (-1, 1):
        k.beam((sx * 0.48, sy * 0.27, 0), (sx * 0.44, sy * 0.24, TZ - 0.05), 0.065, WOOD, TIMBER, bevel=0.012)
    k.box((0.05, 0.46, 0.06), (sx * 0.46, 0, 0.2), WOOD, TIMBER, bevel=0.01)
k.box((0.9, 0.05, 0.06), (0, 0, 0.2), WOOD, TIMBER, bevel=0.01)
k.box((1.0, 0.56, 0.08), (0, 0, TZ - 0.09), WOOD, TIMBER_D, var=0)       # apron
k.pop()
CANDLES = [(1.60, -0.60, 0.22), (1.75, -0.79, 0.15), (1.52, -0.85, 0.11)]
FLAME_POS = []
for (cx, cy, ch) in CANDLES:
    r = random.uniform(0.02, 0.026)
    lathe([(0, 0), (0.055, 0), (0.06, 0.01), (0.052, 0.014), (0, 0.014)], (cx, cy, TZ), METAL, hexc("8e8a84"),
          segs=12)
    z0 = TZ + 0.014
    k.cyl(r, ch, (cx, cy, z0), WAX, vary(hexc("efe3c2"), 0.03), segs=10, grime=False)
    for dz in (0.5,):
        a = random.uniform(0, math.tau)
        k.sphere(1.0, (cx + math.cos(a) * r, cy + math.sin(a) * r, z0 + ch * dz), WAX, hexc("f4e8cc"),
                 scale=(0.007, 0.007, 0.02), subdiv=1, grime=False)
    k.sphere(1.0, (cx, cy, z0 + 0.004), WAX, hexc("f2e6c8"), scale=(r * 1.5, r * 1.5, 0.006), subdiv=1, grime=False)
    k.box((0.003, 0.003, 0.014), (cx, cy, z0 + ch + 0.007), METAL, hexc("1a1512"), var=0, grime=False)
    fz = z0 + ch + 0.008
    lathe([(0, 0), (0.008, 0.005), (0.011, 0.015), (0.009, 0.028), (0.005, 0.04), (0, 0.052)], (cx, cy, fz),
          CANDLE, hexc("ffc060"), segs=8, smooth=80)
    FLAME_POS.append((cx, cy, round(fz + 0.019, 3)))
# jug with a handle, bowls, bread and a spoon
JX, JY = 2.18, -0.83
lathe([(0, 0), (0.07, 0), (0.09, 0.05), (0.095, 0.11), (0.075, 0.18), (0.055, 0.22), (0.06, 0.25), (0.052, 0.25),
       (0.047, 0.22), (0, 0.21)], (JX, JY, TZ), CERAMIC, hexc("b56a3e"), segs=10)
k.tube([(JX + 0.07, JY, TZ + 0.2), (JX + 0.14, JY, TZ + 0.19), (JX + 0.15, JY, TZ + 0.1), (JX + 0.085, JY, TZ + 0.06)],
       [0.013] * 4, CERAMIC, hexc("a8603a"), segs=6, point_end=False)
k.cyl(0.098, 0.03, (JX, JY, TZ + 0.1), CERAMIC, hexc("e8d2a4"), segs=10, caps=False, r2=0.096)   # glaze band
BOWL = [(0, 0), (0.035, 0), (0.07, 0.02), (0.085, 0.055), (0.078, 0.057), (0.062, 0.024), (0, 0.012)]
lathe(BOWL, (2.32, -0.55, TZ), WOOD, hexc("9c6b3f"), segs=10)
lathe([(r * 0.85, z * 0.85) for r, z in BOWL], (2.32, -0.55, TZ + 0.014), WOOD, hexc("b07b48"), segs=10)
lathe(BOWL, (1.95, -0.52, TZ), CERAMIC, hexc("d9c9a3"), segs=10)
k.sphere(1.0, (1.97, -0.52, TZ + 0.04), CLOTH, hexc("5b3c22"), scale=(0.05, 0.05, 0.022), subdiv=1, grime=False)  # stew
k.sphere(1.0, (2.05, -0.62, TZ + 0.045), CLOTH, hexc("b87a3c"), scale=(0.11, 0.075, 0.055), subdiv=1,
         noise_amt=0.05, grime=False, rot=(0, 0, 0.4))                                                  # bread
k.beam((1.85, -0.83, TZ + 0.008), (2.0, -0.9, TZ + 0.008), 0.008, WOOD, hexc("c49a64"), bevel=0, width=0.014)
k.sphere(1.0, (1.84, -0.826, TZ + 0.01), WOOD, hexc("c49a64"), scale=(0.02, 0.014, 0.006), subdiv=1)


def stool(x, y, h=0.44, r=0.17):
    for a in range(3):
        ang = a / 3 * math.tau + 0.3
        k.beam((x + math.cos(ang) * r * 1.1, y + math.sin(ang) * r * 1.1, 0),
               (x + math.cos(ang) * r * 0.55, y + math.sin(ang) * r * 0.55, h - 0.04), 0.04, WOOD, TIMBER, bevel=0.01)
    k.cyl(r, 0.05, (x, y, h - 0.05), WOOD, vary(OAK, 0.08), segs=10, smooth=40)
    k.cyl(r * 0.96, 0.012, (x, y, h - 0.004), WOOD, mix(OAK, hexc("c49a64"), 0.3), segs=10, caps=True, smooth=40)


stool(1.15, -1.1)
stool(-0.95, 1.35, h=0.38, r=0.15)

_tri_mark("shelves (right wall)")
# ======================================================================== shelves (right wall)
SY0, SY1 = 0.35, 1.95
for sz in (1.25, 1.72):
    k.box((0.28, SY1 - SY0, 0.035), (HW - 0.15, (SY0 + SY1) / 2, sz), WOOD, vary(OAK, 0.06), bevel=0.008)
    for yy in (SY0 + 0.15, SY1 - 0.15):
        k.prism([(0, 0), (0.22, 0), (0, -0.2)], 0.035, (HW - 0.23, yy, sz - 0.018), WOOD, TIMBER,
                rot=(0, 0, math.pi), bevel=0.006)
POTS = [hexc("a95f3a"), hexc("6f8a5a"), hexc("c89b55"), hexc("938b7c"), hexc("7d4b30"), hexc("5f7486")]
def pot(x, y, z, s, kind):
    c = random.choice(POTS)
    if kind == 0:     # round crock
        prof = [(0, 0), (0.6, 0), (0.95, 0.35), (1.0, 0.6), (0.7, 0.95), (0.72, 1.05), (0.62, 1.05), (0, 0.95)]
    elif kind == 1:   # tall jar
        prof = [(0, 0), (0.55, 0), (0.7, 0.3), (0.72, 1.1), (0.55, 1.4), (0.6, 1.5), (0, 1.5)]
    else:             # jug
        prof = [(0, 0), (0.6, 0), (0.85, 0.4), (0.7, 0.9), (0.4, 1.2), (0.45, 1.35), (0.35, 1.35), (0, 1.25)]
    lathe([(r * s, zz * s) for r, zz in prof], (x, y, z), CERAMIC, c, segs=10)
    if random.random() < 0.5:
        k.cyl(0.66 * s, 0.1 * s, (x, y, z + (1.05 if kind == 0 else 1.5 if kind == 1 else 1.35) * s), CLOTH,
              hexc("d8cba8"), segs=10, r2=0.5 * s)
sz = 1.25 + 0.018
for (yy, s, kd) in ((0.52, 0.1, 0), (0.78, 0.075, 1), (1.02, 0.09, 2), (1.3, 0.11, 0), (1.72, 0.07, 1)):
    pot(HW - 0.15, yy, sz, s, kd)
for i in range(3):                                   # stacked bowls
    lathe([(r * 1.1, z * 1.1) for r, z in BOWL], (HW - 0.15, 1.52, sz + i * 0.02), CERAMIC, hexc("d6c6a0"), segs=12)
sz = 1.72 + 0.018
for (yy, s, kd) in ((0.5, 0.08, 1), (0.7, 0.085, 0), (1.45, 0.07, 2), (1.62, 0.06, 1), (1.8, 0.075, 0)):
    pot(HW - 0.15, yy, sz, s, kd)
k.cyl(0.16, 0.14, (HW - 0.16, 1.07, sz), WOOD, hexc("b0915c"), segs=10, r2=0.18, noise_amt=0.01, noise_scale=12)
for i in range(3):
    k.sphere(0.05, (HW - 0.16 + j(0.06), 1.07 + j(0.08), sz + 0.15), CLOTH,
             random.choice([hexc("c23b2a"), hexc("d98a2b"), hexc("9aab4a")]), subdiv=0, grime=False)  # apples

_tri_mark("herbs from the front summer beam")
# ======================================================================== herbs from the front summer beam
HERBS = [hexc("6d7f45"), hexc("8a8a55"), hexc("9278a8"), hexc("5f7040"), hexc("a8904a"), hexc("7c8a5a"),
         hexc("8f6f45"), hexc("a6a070")]
HBZ = 2.58
for hx in [0.66, 0.95, 1.3, 1.62, 1.95, 2.3, -1.45, -1.1]:
    hy = -0.9 + j(0.04)
    L = random.uniform(0.05, 0.2)
    k.box((0.007, 0.007, L), (hx, hy, HBZ - L / 2), CLOTH, hexc("c9b78e"), var=0, grime=False)   # twine
    top = HBZ - L
    c = random.choice(HERBS)
    k.cyl(0.02, 0.04, (hx, hy, top - 0.04), CLOTH, hexc("8a6a40"), segs=6, grime=False)            # tie
    hl = random.uniform(0.24, 0.36)
    for s_ in range(3):                  # splayed sprigs, stems up, leafy heads down
        a_ = s_ / 3 * math.tau + random.uniform(0, 1)
        sp = random.uniform(0.03, 0.06)
        tip = Vector((hx + math.cos(a_) * sp, hy + math.sin(a_) * sp, top - 0.03 - hl * random.uniform(0.8, 1.05)))
        cc = vary(mix(c, random.choice(HERBS), 0.3), 0.1)
        k.tube([(hx, hy, top - 0.03), (hx + math.cos(a_) * sp * 0.5, hy + math.sin(a_) * sp * 0.5,
                top - 0.03 - hl * 0.5), tip], [0.006, 0.022, 0.028], CLOTH, cc, segs=5, point_end=False)
        k.sphere(0.03, tip, CLOTH, mix(cc, (0.12, 0.1, 0.05), 0.2), scale=(1, 1, 1.4), subdiv=0, noise_amt=0.012,
                 grime=False, rot=(0, 0, a_))
# a string of garlic/onions on the back-right post
for i in range(6):
    k.sphere(0.04, (2.6 + j(0.02), HD - 0.12, 2.1 - i * 0.075), CLOTH, random.choice([hexc("efe6d2"), hexc("c98d4e")]),
             scale=(1, 1, 0.85), subdiv=1, grime=False)
k.box((0.008, 0.008, 0.6), (2.6, HD - 0.12, 2.05), CLOTH, hexc("b8a47a"), var=0, grime=False)

_tri_mark("rug")
# ======================================================================== rug
RX, RY, RA, RB = -0.3, 0.1, 1.1, 0.7
RINGS = [hexc("a33f2c"), hexc("d4ac66"), hexc("3f506e"), hexc("c9b695"), hexc("a33f2c"), hexc("6c7a52"),
         hexc("d4ac66"), hexc("3a2c24")]
t = bmesh.new()
lay = t.faces.layers.int.new("cid")
keys = []
SEG, NR = 28, len(RINGS)
ctr = t.verts.new((RX, RY, 0.014))
prev = None
for ri in range(1, NR + 1):
    f = ri / NR
    ring = []
    for s in range(SEG):
        a = s / SEG * math.tau
        wob = 1 + 0.015 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, ri)))
        ring.append(t.verts.new((RX + math.cos(a) * RA * f * wob, RY + math.sin(a) * RB * f * wob,
                                 0.014 + 0.002 * noise.noise(Vector((a, ri, 1.0))))))
    for s in range(SEG):
        s2 = (s + 1) % SEG
        if prev is None:
            fc = t.faces.new((ctr, ring[s], ring[s2]))
        else:
            fc = t.faces.new((prev[s], ring[s], ring[s2], prev[s2]))
        keys.append(vary(RINGS[ri - 1], 0.05))
        fc[lay] = len(keys) - 1
    prev = ring
low = [t.verts.new((v.co.x, v.co.y, 0.001)) for v in prev]
for s in range(SEG):
    s2 = (s + 1) % SEG
    fc = t.faces.new((prev[s], low[s], low[s2], prev[s2]))
    keys.append(hexc("2e241e"))
    fc[lay] = len(keys) - 1
bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
k._merge(t, CLOTH, (1, 1, 1), None, None, 0.0, lambda f: keys[f[lay]], False)

_tri_mark("export + night preview")
# ======================================================================== export + night preview
for (n0, c0), (n1, c1) in zip(_TRI, _TRI[1:] + [("end", k.tri_count())]):
    print(f"  {c1 - c0:6d} tris  {n0}")
print("triangles:", k.tri_count())
print("cradle", (CRX, CRY, 0.0), "candle flames", FLAME_POS)
PNG = next((a for a in sys.argv[1:] if a.endswith(".png")), None)
sys.argv = [a for a in sys.argv if not a.endswith(".png")]
ob = k.finish()


def render_night(png):
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene

    def light(name, kind, loc, energy, color, size=0.1, rot=None, spot=None):
        ld = bpy.data.lights.new(name, kind)
        ld.energy = energy
        ld.color = color
        if kind == "AREA":
            ld.size = size
        else:
            ld.shadow_soft_size = size
        if spot:
            ld.spot_size = spot
            ld.spot_blend = 0.6
        o = bpy.data.objects.new(name, ld)
        o.location = loc
        if rot is not None:
            o.rotation_euler = rot
        sc.collection.objects.link(o)
        return o

    def aim(o, target):
        d = Vector(target) - o.location
        o.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()

    light("Hearth", "POINT", (0, 1.88, 0.62), 130, (1.0, 0.42, 0.13), 0.2)
    light("HearthGlow", "POINT", (0, 1.55, 0.45), 45, (1.0, 0.45, 0.16), 0.3)
    for i, p in enumerate(FLAME_POS):
        light(f"Candle{i}", "POINT", p, 6, (1.0, 0.62, 0.3), 0.02)
    f = light("BlueFill", "AREA", (-1.5, -7.0, 2.5), 45, (0.35, 0.5, 1.0), 4.0)
    aim(f, (0, 0.5, 1.0))
    m = light("Moon", "AREA", (-2.9, -0.95, 1.45), 14, (0.5, 0.65, 1.0), 0.6)
    aim(m, (-1.4, -0.4, 0.2))
    world = bpy.data.worlds.new("Night")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*srgb((0.05, 0.07, 0.13)), 1)
    bg.inputs["Strength"].default_value = 0.08
    sc.world = world

    cd = bpy.data.cameras.new("Cam")
    cd.lens = 28
    cam = bpy.data.objects.new("Cam", cd)
    sc.collection.objects.link(cam)
    cam.location = Vector(tuple(float(v) for v in os.environ.get("RA_CAM", "0.4,-7.6,1.85").split(",")))
    aim(cam, tuple(float(v) for v in os.environ.get("RA_TARGET", "0.2,0.8,1.05").split(",")))
    cd.clip_end = 100
    sc.camera = cam

    sc.render.engine = "CYCLES"
    sc.cycles.samples = int(os.environ.get("RA_SAMPLES", "96"))
    sc.cycles.use_denoising = True
    try:
        sc.cycles.denoiser = "OPENIMAGEDENOISE"
    except Exception:
        pass
    sc.cycles.max_bounces = 6
    sc.render.resolution_x = 1280
    sc.render.resolution_y = 720
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Punchy"
    except Exception:
        pass
    sc.view_settings.exposure = float(os.environ.get("RA_EXPOSURE", "0.0"))
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("preview", png)


if PNG:
    render_night(PNG)
