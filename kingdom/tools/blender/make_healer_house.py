"""Healer's house: a whitewashed half-timber cottage-clinic with a thick thatch
roof, a porch with drying herb bundles, a round green-cross-and-leaf sign, a
glowing healing-crystal lamp, and a fenced herb garden with raised beds.

Run: python3 make_healer_house.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Ground footprint 8.0 m (X) x 7.2 m (Y) from the garden
fence (y=-3.5) to the back wall (y=+3.7); the back roof eave overhangs to
y=+4.35. The cottage body is 6.4 x 4.0 m at y in [-0.3, 3.7], thatch ridge
~6.9 m, chimney top ~7.1 m. Origin at ground centre of that footprint, floor
level z=0.3.
Front (door, sign, garden gate) faces Blender -Y = Godot +Z. The gate opening
is x in [-0.6, 0.6] at y=-3.5; the door is at x=0 on the wall y=-0.3.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("HealerHouse", seed=77)
MATTE = k.material("Matte", rough=0.93)
WOOD = k.material("Wood", rough=0.75)
THATCH = k.material("Thatch", rough=1.0, spec=0.2)
PLANT = k.material("Plant", rough=0.8, spec=0.3)
METAL = k.material("Metal", rough=0.4, metal=1.0)
GLASS = k.material("Glass", rough=0.06, metal=0.35, emission=hexc("ffb060"), strength=0.12, spec=1.0)
CRYSTAL = k.material("Crystal", rough=0.2, emission=hexc("63ffb0"), strength=3.0)

PLASTER = hexc("f1e9d6")
TIMBER = hexc("6b4a2f")
TIMBER_D = hexc("4f3522")
SAGE = hexc("6f9a6a")
DOORG = hexc("3f6e46")
GLASS_C = hexc("58768e")
STRAWS = [hexc("8f7445"), hexc("a3824c"), hexc("b8934f"), hexc("c9a55e"), hexc("b08d52"), hexc("9c8156"), hexc("7e6a48")]
STONES = [hexc("938d80"), hexc("a39b8b"), hexc("857f76"), hexc("aaa18f")]
def straw(t):
    c = random.choice(STRAWS)
    c = mix(c, hexc("8a7a4a"), 0.25 * (1 - t))   # weathered, darker toward the eave
    if random.random() < 0.05:
        c = mix(c, hexc("6f7d45"), 0.35)          # moss patch
    return vary(c, 0.07, 0.02)
def stone():
    return vary(random.choice(STONES), 0.1, 0.03)

X0, X1, Y0, Y1 = -3.2, 3.2, -0.3, 3.7
HW, HD = (X1 - X0) / 2, (Y1 - Y0) / 2
CY = (Y0 + Y1) / 2
F0, WT = 0.3, 3.0                 # floor, wall top
PITCH = math.radians(52)
OVER = 0.55
RISE = HD * math.tan(PITCH)
RIDGE = WT + RISE
EAVE = WT - OVER * math.tan(PITCH)

# ------------------------------------------------------------------ body
k.box((X1 - X0 + 0.3, Y1 - Y0 + 0.3, F0), (0, CY, F0 / 2), MATTE, hexc("7e786e"), bevel=0.04)
k.box((X1 - X0 - 0.3, Y1 - Y0 - 0.3, 0.75), (0, CY, F0 + 0.375), MATTE, hexc("3d3935"), var=0)   # mortar core
k.box((X1 - X0 - 0.04, Y1 - Y0 - 0.04, WT - F0 - 0.7), (0, CY, F0 + 0.7 + (WT - F0 - 0.7) / 2), MATTE, PLASTER, var=0.02)
door_hole = [(-0.6, 0, 0.6, 1.0)]
for loc, rz, L, holes in (((0, Y0, F0), 0.0, X1 - X0, door_hole), ((0, Y1, F0), math.pi, X1 - X0, []),
                          ((X1, CY, F0), math.pi / 2, Y1 - Y0, []), ((X0, CY, F0), -math.pi / 2, Y1 - Y0, [])):
    k.grid_wall(L, 0.75, loc, MATTE, stone, rot=(0, 0, rz), bw=0.55, bh=0.25, holes=holes, gap=0.03, push=0.03)
    k.push(loc, (0, 0, rz))
    k.box((L + 0.04, 0.12, 0.1), (0, -0.02, 0.78), WOOD, TIMBER_D)          # sole plate on the stone skirt
    k.box((L + 0.04, 0.12, 0.14), (0, -0.02, WT - F0 - 0.07), WOOD, TIMBER_D)  # top plate
    k.pop()

def frame_wall(L, posts, braces):
    y = -0.04
    z0, z1 = F0 + 0.83, WT - 0.14          # between sole plate and top plate
    for x in posts:
        k.box((0.16, 0.1, z1 - z0), (x, y, (z0 + z1) / 2), WOOD, vary(TIMBER, 0.08))
    for a, b, up in braces:
        k.beam((a, y, z0 if up else z1), (b, y, z1 if up else z0), 0.1, WOOD, TIMBER, bevel=0, width=0.12)

def window(x, z0, w, h, shutters=True, box=True):
    zc = z0 + h / 2
    k.quad(w, h, (x, -0.02, zc), GLASS, GLASS_C, var=0.05, grime=False)
    for sx in (-1, 1):
        k.box((0.08, 0.1, h + 0.08), (x + sx * (w / 2 + 0.03), -0.05, zc), WOOD, TIMBER_D)
    k.box((w + 0.14, 0.1, 0.08), (x, -0.05, z0 + h + 0.03), WOOD, TIMBER_D)
    k.box((0.04, 0.04, h), (x, -0.04, zc), WOOD, TIMBER)
    k.box((w, 0.04, 0.04), (x, -0.04, zc + h * 0.1), WOOD, TIMBER)
    k.box((w + 0.3, 0.16, 0.06), (x, -0.09, z0 - 0.03), WOOD, TIMBER)
    if shutters:
        for sx in (-1, 1):
            cx = x + sx * (w / 2 + 0.07 + w * 0.27)
            sc = vary(SAGE, 0.06)
            k.box((w * 0.52, 0.04, h + 0.04), (cx, -0.05, zc), WOOD, sc)
            k.box((w * 0.52, 0.02, 0.06), (cx, -0.08, zc + h * 0.3), WOOD, mix(sc, (0, 0, 0), 0.3))
            k.box((w * 0.52, 0.02, 0.06), (cx, -0.08, zc - h * 0.3), WOOD, mix(sc, (0, 0, 0), 0.3))
    if box:
        k.box((w + 0.15, 0.22, 0.18), (x, -0.18, z0 - 0.15), WOOD, TIMBER_D)
        for i in range(3):
            fx = x - w / 2 + (i + 0.5) * w / 3
            k.sphere(0.17, (fx, -0.18, z0 - 0.02), PLANT, vary(hexc("5b8a3a"), 0.15), scale=(1.0, 0.75, 0.65),
                     subdiv=0, noise_amt=0.04, rot=(0, 0, random.uniform(0, 3)))
            k.box((0.07, 0.07, 0.07), (fx + random.uniform(-0.06, 0.06), -0.28, z0 + 0.07), PLANT,
                  random.choice([hexc("f0f0ff"), hexc("b58ae0"), hexc("f5c542")]), rot=(0.6, 0.4, 0.3))

# Front wall: door in the middle, a window each side
k.push((0, Y0, 0))
frame_wall(X1 - X0, [X0 + 0.08, -0.75, 0.75, X1 - 0.08], [(X0 + 0.2, -2.3, True), (X1 - 0.2, 2.3, True)])
for x in (-1.75, 1.75):
    window(x, 1.3, 0.8, 1.0)
# Round-top door
DW, DS = 1.0, 1.8
pts = [(-DW / 2, 0), (DW / 2, 0)]
for i in range(9):
    a = i / 8 * math.pi
    pts.append((math.cos(a) * DW / 2, DS + math.sin(a) * DW / 2))
pts = pts[:2] + pts[2:]
k.prism(pts, 0.08, (0, 0.01, F0), WOOD, DOORG, bevel=0.01)
for i in range(4):
    k.box((0.02, 0.02, DS + 0.3), (-0.375 + i * 0.25, -0.035, F0 + (DS + 0.3) / 2), WOOD, mix(DOORG, (0, 0, 0), 0.3))
k.cyl(0.13, 0.03, (0, -0.03, F0 + DS + 0.08), GLASS, GLASS_C, rot=(math.pi / 2, 0, 0), segs=10)
k.ring(0.13, 0.19, 0.06, (0, -0.04, F0 + DS + 0.08), METAL, hexc("b08a3a"), segs=10)
k.sphere(0.05, (0.35, -0.07, F0 + 1.0), METAL, hexc("b08a3a"), subdiv=0)
k.ring(DW / 2, DW / 2 + 0.12, 0.14, (0, -0.02, F0 + DS), WOOD, TIMBER_D, segs=16, rot=(0, 0, 0))
for sx in (-1, 1):
    k.box((0.12, 0.14, DS), (sx * (DW / 2 + 0.06), -0.02, F0 + DS / 2), WOOD, TIMBER_D)
k.box((1.3, 0.5, 0.15), (0, -0.25, 0.1), MATTE, hexc("8d877c"), bevel=0.03)   # door step
k.pop()

# Back and sides
k.push((0, Y1, 0), (0, 0, math.pi))
frame_wall(X1 - X0, [X0 + 0.08, -1.0, 1.0, X1 - 0.08], [(-1.0, -2.8, False), (1.0, 2.8, False)])
window(0, 1.3, 0.9, 1.0, shutters=True, box=False)
k.pop()
for sx in (-1, 1):
    k.push((sx * X1, CY, 0), (0, 0, sx * math.pi / 2))
    frame_wall(Y1 - Y0, [-HD + 0.08, HD - 0.08], [(-HD + 0.2, -0.5, True), (HD - 0.2, 0.5, True)])
    window(0, 1.3, 0.75, 1.0, box=(sx < 0))
    # gable: plaster triangle + attic window
    k.prism([(-HD - 0.02, 0), (HD + 0.02, 0), (0, RISE)], 0.2, (0, 0.08, WT), MATTE, PLASTER, var=0.02)
    k.beam((0, -0.04, WT), (0, -0.04, RIDGE - 0.15), 0.14, WOOD, TIMBER_D, bevel=0)
    k.box((HD * 1.2, 0.1, 0.14), (0, -0.04, WT + RISE * 0.3), WOOD, TIMBER_D)
    window(0, WT + RISE * 0.3 + 0.2, 0.5, 0.6, shutters=False, box=False)
    k.pop()

# ------------------------------------------------------------------ thatch roof
k.push((0, CY, EAVE))
for rz in (0.0, math.pi):
    k.thatch_side(X0 - 0.45, X1 + 0.45, HD + OVER, RIDGE - EAVE, THATCH, STRAWS, th=0.34,
                  deck_mat=THATCH, deck_color=hexc("5e4628"), rot=(0, 0, rz), ridge_color=hexc("6f5733"))
k.pop()
# ridge roll with bound scallops
k.log((X0 - 0.5, CY, RIDGE + 0.2), (X1 + 0.5, CY, RIDGE + 0.2), 0.3, THATCH, hexc("6f5733"), segs=10, noise_amt=0.04)
for i in range(11):   # hazel binding rods over the ridge roll
    x = X0 - 0.3 + i * (X1 - X0 + 0.6) / 10
    k.cyl(0.315, 0.05, (x, CY, RIDGE + 0.2), WOOD, hexc("5a4128"), rot=(0, math.pi / 2, 0), segs=10, base=False,
          caps=False)

# Chimney on the back-left
cx, cy = -1.9, Y1 - 0.9
z = RIDGE - 1.4
while z < RIDGE + 1.2:
    h = random.uniform(0.28, 0.36)
    k.box((0.7 + random.uniform(-0.02, 0.02), 0.7, h - 0.02), (cx, cy, z + h / 2), MATTE, stone())
    z += h
k.box((0.85, 0.85, 0.1), (cx, cy, z + 0.05), MATTE, hexc("7d776d"), bevel=0.02)

# ------------------------------------------------------------------ porch + drying herbs
PZ = 2.55
k.push((0, Y0, 0))
for sx in (-1, 1):
    k.log((sx * 1.05, -1.25, 0.02), (sx * 1.05, -1.25, PZ), 0.08, WOOD, TIMBER, segs=8, noise_amt=0.01)
    k.beam((sx * 1.05, -1.25, PZ - 0.5), (sx * 1.05, -0.9, PZ - 0.08), 0.08, WOOD, TIMBER_D, bevel=0)
k.box((2.4, 0.12, 0.14), (0, -1.25, PZ), WOOD, TIMBER_D)
porch_run, porch_rise = 1.55, 0.55
k.push((0, 0.05, PZ - 0.1))
k.thatch_side(-1.35, 1.35, porch_run, porch_rise, THATCH, STRAWS, th=0.2, du=0.22, band=0.42, step=0.05,
              deck_mat=THATCH, deck_color=hexc("5e4628"))
k.pop()
# herb bundles hanging from the porch beam
HERBS = [hexc("6d8f4e"), hexc("8a9a5b"), hexc("a07cc0"), hexc("5f7f45"), hexc("b8a04a"), hexc("7c9b6a")]
for i in range(9):
    hx = -0.92 + i * 0.23
    L = random.uniform(0.15, 0.3)
    k.box((0.01, 0.01, L), (hx, -1.25, PZ - 0.07 - L / 2), WOOD, hexc("c9b78e"))
    top = PZ - 0.07 - L
    c = random.choice(HERBS)
    k.cyl(0.03, 0.06, (hx, -1.25, top - 0.06), WOOD, hexc("8a6a40"), segs=6)
    k.cyl(0.075, 0.36, (hx, -1.25, top - 0.42), PLANT, c, segs=7, r2=0.02, noise_amt=0.03, noise_scale=9,
          rot=(0, 0, random.uniform(0, 1)))
    k.sphere(0.075, (hx, -1.25, top - 0.42), PLANT, mix(c, (0.1, 0.1, 0.05), 0.25), scale=(1, 1, 0.5), subdiv=1,
             noise_amt=0.02)
# bench under the window
k.box((1.2, 0.4, 0.06), (-1.75, -0.3, 0.48), WOOD, hexc("8a6238"), bevel=0.01)
for sx in (-1, 1):
    k.box((0.08, 0.36, 0.45), (-1.75 + sx * 0.5, -0.3, 0.225), WOOD, TIMBER)
# glowing healing crystal lamp on a post by the door
k.log((0.9, -0.55, 0.0), (0.9, -0.55, 1.5), 0.05, WOOD, TIMBER_D, segs=6, noise_amt=0.0)
k.cyl(0.1, 0.06, (0.9, -0.55, 1.5), METAL, hexc("b08a3a"), segs=8, r2=0.14)
k.cyl(0.07, 0.34, (0.9, -0.55, 1.56), CRYSTAL, hexc("7dffc0"), segs=6, r2=0.0, smooth=None)
k.cyl(0.07, 0.1, (0.9, -0.55, 1.56), CRYSTAL, hexc("7dffc0"), segs=6, r2=0.07, smooth=None, rot=(math.pi, 0, 0))
for a in range(3):
    ang = a / 3 * math.tau
    k.beam((0.9 + math.cos(ang) * 0.12, -0.55 + math.sin(ang) * 0.12, 1.54),
           (0.9 + math.cos(ang) * 0.05, -0.55 + math.sin(ang) * 0.05, 1.82), 0.02, METAL, hexc("b08a3a"), bevel=0)
k.pop()

# ------------------------------------------------------------------ hanging sign: green cross + leaf
k.box((0.75, 0.06, 0.06), (-1.42, Y0 - 1.25, 2.25), METAL, hexc("333333"))          # arm off the porch post
k.beam((-1.05, Y0 - 1.25, 1.95), (-1.5, Y0 - 1.25, 2.23), 0.035, METAL, hexc("333333"), bevel=0)
for dx in (-0.2, 0.2):
    k.box((0.015, 0.015, 0.14), (-1.6 + dx, Y0 - 1.25, 2.16), METAL, hexc("333333"))
k.push((-1.6, Y0 - 1.25, 1.7))
k.cyl(0.4, 0.07, (0, 0, 0), WOOD, hexc("efe6cf"), rot=(math.pi / 2, 0, 0), segs=18, base=False, smooth=None)
k.ring(0.4, 0.47, 0.1, (0, 0, 0), WOOD, TIMBER_D, segs=18)
for side in (-1, 1):
    y = side * 0.05
    k.box((0.46, 0.03, 0.15), (0, y, 0.05), MATTE, hexc("249a52"), var=0)
    k.box((0.15, 0.03, 0.46), (0, y * 1.1, 0.05), MATTE, hexc("249a52"), var=0)
    leaf = [(0, 0), (0.07, 0.04), (0.11, 0.12), (0.08, 0.2), (0.0, 0.25), (-0.04, 0.12)]
    k.prism(leaf, 0.02, (0.03, y, -0.33), MATTE, hexc("6cbf45"), rot=(0, 1.0, 0))
    k.prism(leaf, 0.02, (-0.03, y, -0.33), MATTE, hexc("58a838"), rot=(0, -1.0 + math.pi, 0))
k.pop()

# ------------------------------------------------------------------ herb garden + fence
GY0, GY1 = -3.5, Y0 - 0.05
for sx in (-1, 1):   # raised beds either side of the path
    bx = sx * 2.2
    bw, bd = 2.6, 2.1
    by = (GY0 + GY1) / 2 - 0.1
    for (dx, dy, lx, ly) in ((0, -bd / 2, bw, 0.1), (0, bd / 2, bw, 0.1), (-bw / 2, 0, 0.1, bd), (bw / 2, 0, 0.1, bd)):
        k.box((lx, ly, 0.3), (bx + dx, by + dy, 0.15), WOOD, vary(hexc("7a5638"), 0.1), bevel=0.01)
    k.box((bw - 0.1, bd - 0.1, 0.24), (bx, by, 0.12), MATTE, hexc("4a3526"), var=0.05)   # soil
    plants = [hexc("9b7fd0"), hexc("7fa35c"), hexc("5f8f4a"), hexc("e39b3a"), hexc("a8c46a"), hexc("6e9a8a")]
    for r in range(3):
        for c in range(3):
            px = bx - bw / 2 + 0.45 + c * (bw - 0.9) / 2 + random.uniform(-0.06, 0.06)
            py = by - bd / 2 + 0.42 + r * (bd - 0.84) / 2 + random.uniform(-0.06, 0.06)
            col = plants[(r * 2 + c + (sx > 0)) % len(plants)]
            green = vary(mix(col, hexc("4f7f34"), 0.55), 0.1)
            hgt = random.uniform(0.28, 0.42)
            for b2 in range(2):
                ox, oy = random.uniform(-0.12, 0.12), random.uniform(-0.12, 0.12)
                k.sphere(random.uniform(0.15, 0.2), (px + ox, py + oy, 0.24 + hgt * 0.35), PLANT,
                         vary(green, 0.08), scale=(1.0, 1.0, hgt / 0.28), subdiv=1, noise_amt=0.05,
                         rot=(0, 0, random.uniform(0, 3)))
            if col in (plants[0], plants[3], plants[5]):   # lavender / calendula / borage flowers
                for f in range(6):
                    a2 = random.uniform(0, math.tau)
                    rr = random.uniform(0.05, 0.2)
                    k.box((0.05, 0.05, 0.05), (px + math.cos(a2) * rr, py + math.sin(a2) * rr,
                          0.24 + hgt * (0.8 - rr)), PLANT, vary(col, 0.1), rot=(0.6, 0.5, a2))
# stepping-stone path
for i in range(5):
    k.cyl(random.uniform(0.26, 0.32), 0.06, (random.uniform(-0.08, 0.08), -3.2 + i * 0.62, 0.0), MATTE,
          vary(hexc("9a948a"), 0.08), segs=7, smooth=None, rot=(0, 0, random.uniform(0, 1)))
# picket fence around the garden (gate gap at the front centre)
def picket_run(a, b, gate=None):
    a, b = (a[0], a[1]), (b[0], b[1])
    L = math.dist(a, b)
    n = int(L / 0.2)
    dx, dy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
    ang = math.atan2(dy, dx)
    for i in range(n + 1):
        t = i * L / n
        px, py = a[0] + dx * t, a[1] + dy * t
        if gate and gate[0] < px < gate[1] and abs(dy) < 1e-6:
            continue
        h = 0.85 + random.uniform(-0.04, 0.03)
        post = (i % 8 == 0) or i == n
        if post:
            k.box((0.1, 0.1, 1.0), (px, py, 0.5), WOOD, vary(hexc("8a6a48"), 0.06))
            k.cyl(0.07, 0.1, (px, py, 1.0), WOOD, hexc("8a6a48"), segs=4, r2=0.0, rot=(0, 0, math.pi / 4), smooth=None)
        else:
            k.prism([(-0.04, 0), (0.04, 0), (0.04, h - 0.07), (0, h), (-0.04, h - 0.07)], 0.025, (px, py, 0.0),
                    WOOD, vary(hexc("e6dcc6"), 0.05), rot=(0, 0, ang))
    for z in (0.3, 0.68):   # rails
        segs = [(0, L)]
        if gate and abs(dy) < 1e-6:
            segs = [(0, gate[0] - a[0]), (gate[1] - a[0], L)]
        for s0, s1 in segs:
            mx = a[0] + dx * (s0 + s1) / 2
            my = a[1] + dy * (s0 + s1) / 2
            k.box((s1 - s0, 0.04, 0.06), (mx, my + 0.03 * (1 if dy == 0 else 0), z), WOOD, hexc("b8a888"),
                  rot=(0, 0, ang))
FX = 3.95
picket_run((-FX, GY0), (FX, GY0), gate=(-0.6, 0.6))
picket_run((-FX, GY0), (-FX, Y0 + 0.2))
picket_run((FX, GY0), (FX, Y0 + 0.2))
# gate (slightly open)
k.push((0.6, GY0, 0), (0, 0, -0.5))
for i in range(5):
    k.prism([(-0.04, 0), (0.04, 0), (0.04, 0.8), (0, 0.87), (-0.04, 0.8)], 0.025, (-0.1 - i * 0.22, 0, 0.05),
            WOOD, vary(hexc("e6dcc6"), 0.05))
for z in (0.3, 0.65):
    k.box((1.05, 0.04, 0.07), (-0.55, 0.03, z), WOOD, hexc("b8a888"))
k.beam((-0.08, 0.035, 0.3), (-1.0, 0.035, 0.65), 0.05, WOOD, hexc("b8a888"), bevel=0)
k.pop()
# water barrel and a basket of herbs by the house
k.cyl(0.33, 0.85, (3.55, 0.2, 0.0), WOOD, hexc("7a5230"), segs=10, r2=0.31)
k.cyl(0.3, 0.02, (3.55, 0.2, 0.8), GLASS, hexc("35607a"), segs=10)
for hz in (0.15, 0.7):
    k.cyl(0.34, 0.05, (3.55, 0.2, hz), METAL, hexc("3a3836"), segs=10, caps=False)
k.cyl(0.25, 0.22, (-0.9, -1.05, 0.0), WOOD, hexc("b89a64"), segs=8, r2=0.3, caps=True)
k.sphere(0.24, (-0.9, -1.05, 0.25), PLANT, hexc("6f9a4e"), scale=(1, 1, 0.4), subdiv=0, noise_amt=0.03)

print("triangles:", k.tri_count())
k.finish(cam_dir=(1.0, -1.5, 0.75), fit=0.9)
