"""Kingsreach market stall (green/white awning): a trestle counter under a
striped canvas awning with a scalloped front valance, packed with fruit
crates (red/orange/yellow apples), bread loaves and pottery jugs, a hanging
lantern, a barrel and grain sacks beside the counter.

Run: python3 make_market_stall_green.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Footprint <= 3.5 (X) x 2.5 (Y); awning peak ~2.6 m.
Origin at ground centre; the counter (customer side) faces Blender -Y
(Godot +Z). Budget: <= 4000 triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, IRON
from ra_kit import hexc, mix, vary

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "kingdom", "assets", "art", "textures")

k = VK("MarketStallGreen", seed=9032, pal=palette())
k.pbr = dict(size=512, seed=9, ao_dist=0.35, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.weather_ao = 0.34
W, CL, MT = k.M("Wood"), k.M("Cloth"), k.M("Metal")
STRIPES = (hexc("2f6b3a"), hexc("f1e9d8"))
WOODC = hexc("8a6a48")
ROPE = hexc("c9b48a")

HX = 1.6
FY, BY = -0.85, 0.85
FH, BH = 2.05, 2.5
k.grime, k.grime_amt = 0.45, 0.2

# ---------------------------------------------------------------- frame (chunky posts, braced)
for x in (-HX, HX):
    k.bar((x, FY, 0), (x, FY, FH - 0.1), 0.11, 0.11, W, WOODC, bevel=0.016)
    k.bar((x, BY, 0), (x, BY, BH - 0.1), 0.11, 0.11, W, WOODC, bevel=0.016)
    k.bar((x, FY - 0.02, FH - 0.16), (x, BY + 0.02, BH - 0.16), 0.08, 0.07, W, WOODC, up=(0, 0, 1), bevel=0.01)
    k.bar((x, FY, 0.35), (x, BY, 0.35), 0.07, 0.06, W, mix(WOODC, (0, 0, 0), 0.1), up=(0, 0, 1), bevel=0)
    for (yy, hh, sg) in ((FY, FH, 1), (BY, BH, -1)):
        k.bar((x, yy, hh - 0.62), (x, yy + sg * 0.42, hh - 0.2), 0.06, 0.05, W, WOODC, up=(0, -sg, 1), bevel=0)
    for (yy, hh) in ((FY, FH), (BY, BH)):
        k.box((0.2, 0.2, 0.08), (x, yy, 0.04), k.M("Matte"), vary(hexc("9a948a"), 0.05), var=0)
for (yy, hh) in ((FY, FH), (BY, BH)):
    k.bar((-HX - 0.1, yy, hh - 0.17), (HX + 0.1, yy, hh - 0.17), 0.08, 0.07, W, WOODC, up=(0, 0, 1), bevel=0.01)

# counter: plank top on trestles (hand-painted wood_planks.png decal on top), boarded front, shelf under
k.box((2 * HX + 0.2, 0.75, 0.06), (0, FY + 0.3, 0.86), W, vary(WOODC, 0.05), bevel=0.012)
k.image_quad(os.path.join(TEX, "wood_planks.png"), 2 * HX + 0.18, 0.73, (0, FY + 0.3, 0.892), rot=(-math.pi / 2, 0, 0),
             repeat=(4.4, 1.6), double_sided=False)
with k.grain_axis("z"):
    k.box((2 * HX + 0.1, 0.03, 0.55), (0, FY - 0.05, 0.56), W, mix(WOODC, (0, 0, 0), 0.12))
for i in range(6):
    k.box((0.03, 0.035, 0.55), (-HX + 0.25 + i * (2 * HX - 0.5) / 5, FY - 0.07, 0.56), W,
          mix(WOODC, (0, 0, 0), 0.3), var=0)
k.box((2 * HX - 0.1, 0.55, 0.04), (0, FY + 0.32, 0.36), W, mix(WOODC, (0, 0, 0), 0.08), var=0)
for sx in (-1, 1):
    k.box((0.06, 0.6, 0.06), (sx * (HX - 0.3), FY + 0.3, 0.8), W, mix(WOODC, (0, 0, 0), 0.2))
k.stage("frame")

# ---------------------------------------------------------------- awning: green/white striped canvas, scalloped
NS = 8
over = 0.28
X0, X1 = -HX - 0.15, HX + 0.15
yb, zb = BY + 0.14, BH + 0.03
yf, zf = FY - over, FH - 0.1
fold = 0.24


def drape(gx, v):
    between = 0.09 * math.sin(math.pi * v) ** 1.2
    front = 0.07 * (1 - v) ** 3 * math.sin(math.pi * gx)
    ripple = 0.018 * math.sin(gx * math.pi * 6.0) * math.sin(math.pi * v)
    dz = -(between * (0.55 + 0.45 * math.sin(math.pi * gx)) + front + ripple)
    e = min(gx, 1 - gx)
    if e < 0.07:
        dz -= fold * (1 - e / 0.07) ** 1.6
    return dz


for i in range(NS):
    c = STRIPES[i % 2]
    x0 = X0 + i * (X1 - X0) / NS
    x1 = x0 + (X1 - X0) / NS

    def sag(u, v, i=i):
        gx = (i + u) / NS
        return (0, 0, drape(gx, 1 - v))
    k.sheet(((x0, yf, zf), (x1, yf, zf), (x0, yb, zb), (x1, yb, zb)), 1, 4, CL,
            lambda u, v, c=c: tuple(ch * (0.84 + 0.16 * v) for ch in c), sag_fn=sag, smooth=None)
    w = x1 - x0
    gx = (i + 0.5) / NS
    zv = zf + drape(gx, 0.0)
    pts = [(0, 0), (w, 0), (w, -0.19)]
    for j in range(1, 4):
        a = j / 4 * math.pi
        pts.append((w / 2 + math.cos(a) * w / 2, -0.19 - math.sin(a) * 0.1))
    pts.append((0, -0.19))
    k.prism(pts, 0.012, (x0, yf - 0.004, zv + 0.004), CL, c, var=0.02, grime=False)
k.bar((X0 + 0.1, yf + 0.03, zf - 0.03), (X1 - 0.1, yf + 0.03, zf - 0.03), 0.035, 0.035, W, WOODC, up=(0, 0, 1),
      bevel=0)
for sx in (-1, 1):
    k.tube([(sx * (HX + 0.13), yf + 0.02, zf - fold + 0.02), (sx * (HX + 0.12), FY - 0.1, FH - 0.55),
            (sx * HX, FY - 0.05, FH - 0.9)], [0.012, 0.012, 0.012], CL, ROPE, segs=4, point_end=False,
           cap_start=False)
    k.tube([(sx * (HX + 0.13), yb - 0.02, zb - fold + 0.02), (sx * HX, BY + 0.05, BH - 1.0)], [0.012, 0.012], CL,
           ROPE, segs=4, point_end=False, cap_start=False)
    for (yy, hh) in ((FY, FH - 0.2), (BY, BH - 0.2)):
        k.ring(0.055, 0.075, 0.12, (sx * HX, yy, hh - 0.04), CL, ROPE, rot=(math.pi / 2, 0, 0), segs=6)
k.stage("awning")

# ---------------------------------------------------------------- lantern
k.box((0.03, 0.03, 0.18), (HX - 0.55, FY, FH - 0.28), MT, IRON, var=0)
k.lantern((HX - 0.55, FY, FH - 0.36), s=0.75)
k.stage("lantern")

# ---------------------------------------------------------------- goods: fruit crates, bread, pottery jugs
GY = FY + 0.32
# two tilted crates of red/orange/yellow apples front-and-centre
for x, rz in ((-0.85, -0.3), (0.15, 0.28)):
    k.push((x, GY + 0.02, 0.89), (-0.32, 0, rz))
    k.box((0.52, 0.4, 0.05), (0, 0, 0.025), W, vary(hexc("9a7a50"), 0.05), var=0)
    for sx in (-1, 1):
        k.box((0.04, 0.4, 0.16), (sx * 0.24, 0, 0.1), W, vary(hexc("8e6a42"), 0.05), var=0)
    for sy in (-1, 1):
        k.box((0.52, 0.04, 0.16 if sy > 0 else 0.1), (0, sy * 0.18, 0.08), W, vary(hexc("8e6a42"), 0.05), var=0)
    k.produce(0, 0, 0.06, 0.2, "apple", n=10)
    k.pop()
# bread loaves on a board
k.box((0.6, 0.42, 0.05), (1.05, GY, 0.915), W, hexc("b08a55"), bevel=0.01)
k.produce(1.05, GY, 0.94, 0.22, "bread", n=7)
# pottery jugs, a small huddle
for jx, jy, jr in ((-1.28, GY + 0.04, 0.1), (-1.28, GY - 0.22, 0.085), (-1.05, GY - 0.05, 0.09)):
    k.jug(jx, jy, 0.89, r=jr, h=0.16 + jr, c=vary(hexc("a8744a") if jr > 0.09 else hexc("946842"), 0.06))
# crates and jugs stacked behind
k.crate(0.75, BY + 0.02, s=0.55, rz=-0.12)
k.crate(0.78, BY + 0.02, z=0.55, s=0.4, rz=0.1)
k.produce(0.78, BY + 0.02, 0.93, 0.16, "apple", n=6)
k.jug(-0.7, BY - 0.05, 0.0, r=0.13, h=0.3)

# barrel and sacks beside the counter (tucked against the front-left post, inside the awning footprint)
k.barrel(-HX + 0.2, FY - 0.15, r=0.24, h=0.64)
k.sack(-HX + 0.47, FY - 0.22, rz=0.3, c=hexc("c2ad84"))
k.sack(-HX + 0.16, FY - 0.32, s=0.8, rz=1.1, c=hexc("b09d74"))
k.sack(-HX + 0.5, FY - 0.35, z=0.0, s=0.62, rz=2.0, c=hexc("a8966e"))
k.stage("goods")

k.finish_checked((3.5, 2.5), 4000, cam_dir=(0.9, -1.6, 0.8), fit=0.9)
