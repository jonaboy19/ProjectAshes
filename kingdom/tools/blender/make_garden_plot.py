"""Garden plot: a 4 x 3 m cottage vegetable bed. Dark tilled soil raised in
ridged rows, two rows of cabbages, two of leeks, a row of young lettuces and
a row of carrot tops, inside a low woven wattle edge (hazel stakes with
withies weaving in and out), with a trodden path gap at the front and a hand
fork left in the soil.

Run: python3 make_garden_plot.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Wattle edge encloses x in [-2, 2], y in [-1.5, 1.5]
(4.0 x 3.0 m), 0.35 m high; rows run along X. Origin at ground centre; the
gap in the edge is on the front (-Y, Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix
from mathutils import Vector, noise

k = TK("GardenPlot", seed=8181, pal=palette())
W, MT, PL, MA = k.M("Wood"), k.M("Metal"), k.M("Plant"), k.M("Matte")
k.grime = 0.3
k.grime_amt = 0.0
HX, HY = 2.0, 1.5
SOIL = [hexc("4a3727"), hexc("3f2f22"), hexc("54402c"), hexc("463425")]

# soil: ridged rows along X as one height-field (ridges at the row lines)
ROWS = [-1.05, -0.62, -0.2, 0.22, 0.64, 1.06]
nx, ny = 6, 18
polys, cols = [], []


def hz(x, y):
    d = min(abs(y - r) for r in ROWS)
    ridge = 0.06 * max(0.0, 1 - d / 0.2) ** 1.5
    edge = min(1.0, (HX - abs(x)) / 0.15, (HY - abs(y)) / 0.15)
    return 0.05 + ridge * max(0.0, edge) + noise.noise(Vector((x * 3, y * 3, 1.7))) * 0.012


for j in range(ny):
    for i in range(nx):
        x0, x1 = -HX + 0.04 + (2 * HX - 0.08) * i / nx, -HX + 0.04 + (2 * HX - 0.08) * (i + 1) / nx
        y0, y1 = -HY + 0.04 + (2 * HY - 0.08) * j / ny, -HY + 0.04 + (2 * HY - 0.08) * (j + 1) / ny
        polys.append(((x0, y0, hz(x0, y0)), (x1, y0, hz(x1, y0)), (x1, y1, hz(x1, y1)), (x0, y1, hz(x0, y1))))
        cols.append(vary(random.choice(SOIL), 0.06))
k.quads(polys, cols, MA, grime=False)
k.box((2 * HX - 0.02, 2 * HY - 0.02, 0.05), (0, 0, 0.02), MA, SOIL[1], var=0, grime=False)

# crops
LEAF = [hexc("6f9a4a"), hexc("7fa857"), hexc("5d8a3d"), hexc("8db462")]
for y in (ROWS[0], ROWS[1]):          # cabbages
    x = -HX + 0.3
    while x < HX - 0.25:
        c = vary(random.choice([hexc("7da54c"), hexc("8fb45e"), hexc("6b9442")]), 0.06)
        k.sphere(0.13, (x, y, hz(x, y) + 0.1), PL, mix(c, hexc("c8d890"), 0.25), scale=(1, 1, 0.85), subdiv=0,
                 grime=False, noise_amt=0.01)
        k.sphere(0.2, (x, y, hz(x, y) + 0.05), PL, vary(c, 0.08), scale=(1.15, 1.0, 0.22),
                 rot=(random.uniform(-0.15, 0.15), random.uniform(-0.15, 0.15), random.uniform(0, 3)), subdiv=0,
                 grime=False, smooth=40, noise_amt=0.02)   # outer leaves
        x += random.uniform(0.48, 0.56)
for y in (ROWS[2], ROWS[3]):          # leeks
    x = -HX + 0.2
    while x < HX - 0.15:
        z0 = hz(x, y)
        k.cyl(0.022, 0.2, (x, y, z0 - 0.02), PL, hexc("e0e2c8"), segs=5, grime=False, caps=False)
        for b in range(2):
            ang = random.uniform(0, math.tau)
            lean = random.uniform(0.25, 0.55)
            k.cyl(0.02, random.uniform(0.3, 0.42), (x, y, z0 + 0.15), PL, vary(hexc("4f7a4a"), 0.08), segs=3, r2=0.004,
                  rot=(lean, 0, ang), grime=False, smooth=None, caps=False)
        x += random.uniform(0.34, 0.4)
y = ROWS[4]                           # lettuces
x = -HX + 0.3
while x < HX - 0.25:
    c = vary(random.choice([hexc("9cc26a"), hexc("8db85e"), hexc("a8c877")]), 0.06)
    for a in range(2):
        ang = a * math.pi + random.uniform(0, 1)
        k.sphere(0.09, (x + math.cos(ang) * 0.04, y + math.sin(ang) * 0.04, hz(x, y) + 0.05), PL, vary(c, 0.06),
                 scale=(1.2, 0.8, 0.6), rot=(0, -0.6, ang), subdiv=0, grime=False, smooth=40)
    x += random.uniform(0.42, 0.48)
y = ROWS[5]                           # carrot tops: feathery tufts
x = -HX + 0.2
while x < HX - 0.15:
    for b in range(1):
        k.cyl(0.035, random.uniform(0.14, 0.22), (x + random.uniform(-0.02, 0.02), y, hz(x, y)), PL,
              vary(hexc("5f9a3a"), 0.08), segs=3, r2=0.0, rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4),
                                                                 random.uniform(0, 3)), grime=False, smooth=None,
              caps=False)
    x += random.uniform(0.16, 0.2)

# wattle edge: stakes + three withies weaving in and out
STAKE = hexc("6b5a45")
WITHY = [hexc("7d6448"), hexc("8a704f"), hexc("6f5840")]
GAP = (-0.35, 0.35)       # path gap in the front edge


def run(p0, p1, gap=None):
    p0, p1 = (p0[0], p0[1], 0.0), (p1[0], p1[1], 0.0)
    L = (Vector(p1) - Vector(p0)).length
    n = max(2, round(L / 0.38))
    d = (Vector(p1) - Vector(p0)) / n
    nrm = Vector((-d.y, d.x, 0)).normalized()
    segs = [(0, n)]
    if gap:
        # split around the gap (x range) on the front run
        ia = int((gap[0] - p0[0]) / d.x)
        ib = int(math.ceil((gap[1] - p0[0]) / d.x))
        segs = [(0, ia), (ib, n)]
    for a, b in segs:
        for i in range(a, b + 1):
            p = Vector(p0) + d * i
            k.cyl(0.024, 0.4 + random.uniform(-0.03, 0.03), (p.x, p.y, -0.02), W, vary(STAKE, 0.08), segs=3,
                  r2=0.018, caps=False, smooth=None)
        for w, z in enumerate((0.1, 0.16, 0.22, 0.28)):
            pts = []
            for i in range(a, b + 1):
                p = Vector(p0) + d * i
                side = 0.03 * (1 if (i + w) % 2 else -1)
                q = p + nrm * side
                pts.append((q.x, q.y, z + random.uniform(-0.01, 0.01)))
            k.tube(pts, [0.03] * len(pts), W, vary(random.choice(WITHY), 0.06), segs=3, point_end=False,
                   smooth=70, cap_start=False)


run((-HX, -HY), (HX, -HY), gap=GAP)
run((HX, -HY), (HX, HY))
run((HX, HY), (-HX, HY))
run((-HX, HY), (-HX, -HY))

# hand fork left in the soil and a stepping board in the gap
k.log((1.35, -0.4, 0.02), (1.45, -0.32, 0.55), 0.016, W, hexc("8a6a48"), segs=5, noise_amt=0.0, ring_step=3.0)
for dx in (-0.035, 0.0, 0.035):
    k.box((0.008, 0.008, 0.14), (1.345 + dx, -0.405, 0.0), MT, IRON, var=0)
k.box((0.6, 0.3, 0.03), (0, -HY + 0.2, 0.08), W, vary(hexc("7d6a52"), 0.05), var=0)

k.finish_checked((4.2, 3.2), 3000, cam_dir=(0.8, -1.4, 1.0), fit=0.85)
