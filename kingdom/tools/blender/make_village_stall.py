"""Village market stall: a trestle counter under a sagging striped cloth
awning with a scalloped valance, loaded with baskets of produce, with crates
and sacks underneath and behind, a string of onions and a small price slate.

Run: python3 make_village_stall.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Footprint <= 3.5 (X) x 2.5 (Y); awning peak ~2.6 m.
Origin at ground centre; the counter (customer side) faces Blender -Y
(Godot +Z).
Variant 1: red/cream awning, apples, pears, cabbages, carrots.
Variant 2: green/ochre awning, bread, onions, fish and plums.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON
from ra_kit import hexc, mix, vary

V = variant_arg()
k = VK("VillageStall" + ("" if V == 1 else f"_{V}"), seed=808 + V * 29, pal=palette())
W, CL, MT = k.M("Wood"), k.M("Cloth"), k.M("Metal")
STRIPES = {1: (hexc("9a3a2e"), hexc("dccfb4")), 2: (hexc("45694a"), hexc("cfae68")), 3: (hexc("3d5878"), hexc("d9cfb8"))}[V]
GOODS = {1: ["apple", "cabbage", "pear", "carrot"], 2: ["bread", "onion", "fish", "plum"],
         3: ["apple", "onion", "bread", "cabbage"]}[V]
WOODC = hexc("8a6a48") if V != 2 else hexc("6b4a2f")

HX = 1.55
FY, BY = -0.85, 0.85         # front / back post lines
FH, BH = 2.05, 2.5           # post heights

# ---------------------------------------------------------------- frame
for x in (-HX, HX):
    k.log((x, FY, 0), (x, FY, FH - 0.13), 0.055, W, WOODC, segs=6, noise_amt=0.008)
    k.log((x, BY, 0), (x, BY, BH - 0.13), 0.055, W, WOODC, segs=6, noise_amt=0.008)
    k.bar((x, FY, FH - 0.16), (x, BY, BH - 0.16), 0.07, 0.06, W, WOODC, up=(0, 0, 1))      # rafter
    k.bar((x, FY, 0.35), (x, BY, 0.35), 0.06, 0.05, W, WOODC, up=(0, 0, 1))
for (yy, hh) in ((FY, FH), (BY, BH)):
    k.bar((-HX - 0.1, yy, hh - 0.17), (HX + 0.1, yy, hh - 0.17), 0.07, 0.06, W, WOODC, up=(0, 0, 1))
# counter: plank top on trestles, front board
k.box((2 * HX + 0.2, 0.75, 0.06), (0, FY + 0.3, 0.86), W, vary(WOODC, 0.05), bevel=0.012)
k.box((2 * HX + 0.1, 0.03, 0.55), (0, FY - 0.05, 0.56), W, mix(WOODC, (0, 0, 0), 0.15))
for i in range(6):
    k.box((0.02, 0.035, 0.55), (-HX + 0.25 + i * (2 * HX - 0.5) / 5, FY - 0.07, 0.56), W, mix(WOODC, (0, 0, 0), 0.3), var=0)
for sx in (-1, 1):
    k.box((0.06, 0.6, 0.06), (sx * (HX - 0.3), FY + 0.3, 0.8), W, mix(WOODC, (0, 0, 0), 0.2))
k.stage("frame")

# ---------------------------------------------------------------- striped awning with scalloped valance
NS = 8
over = 0.25
p_back = (BY + 0.12, BH + 0.02)
p_front = (FY - over, FH - 0.12)
for i in range(NS):
    c = STRIPES[i % 2]
    x0 = -HX - 0.15 + i * (2 * HX + 0.3) / NS
    x1 = x0 + (2 * HX + 0.3) / NS

    def sag(u, v, i=i):
        gu = (i + u) / NS
        return (0, 0, -0.1 * math.sin(math.pi * gu) * math.sin(math.pi * v) - 0.04 * math.sin(math.pi * v))
    k.sheet(((x0, p_front[0], p_front[1]), (x1, p_front[0], p_front[1]),
             (x0, p_back[0], p_back[1]), (x1, p_back[0], p_back[1])), 1, 5, CL,
            lambda u, v, c=c: tuple(ch * (0.86 + 0.14 * v) for ch in c), sag_fn=sag, smooth=None)
    # valance tab hanging from the front edge
    w = x1 - x0
    pts = [(0, 0), (w, 0), (w, -0.2)]
    for j in range(1, 4):
        a = j / 4 * math.pi
        pts.append((w / 2 + math.cos(a) * w / 2, -0.2 - math.sin(a) * 0.1))
    pts.append((0, -0.2))
    k.prism(pts, 0.012, (x0, p_front[0], p_front[1] + 0.005), CL, c, var=0.02, grime=False)
k.bar((-HX - 0.15, p_front[0], p_front[1] + 0.01), (HX + 0.15, p_front[0], p_front[1] + 0.01), 0.04, 0.04, W, WOODC,
      up=(0, 0, 1), bevel=0)
k.stage("awning")

# ---------------------------------------------------------------- goods
GY = FY + 0.3
xs = [-1.15, -0.4, 0.4, 1.15]
for x, g in zip(xs, GOODS):
    if g in ("bread", "fish"):
        k.box((0.62, 0.45, 0.05), (x, GY, 0.915), W, hexc("b08a55"), bevel=0.01)       # flat tray
        k.produce(x, GY, 0.94, 0.24, g, n=7 if g == "bread" else 8)
    else:
        k.basket(x, GY + random.uniform(-0.05, 0.05), z=0.89, r=0.24, h=0.18, goods=g)
# crates and sacks beneath / behind
k.crate(-0.9, FY + 0.45, s=0.5, rz=0.05, c=vary(hexc("9a7a50"), 0.08))
k.produce(-0.9, FY + 0.45, 0.47, 0.2, GOODS[0], n=6)
k.crate(0.7, BY + 0.05, s=0.55, rz=-0.2)
k.crate(0.75, BY + 0.05, z=0.55, s=0.42, rz=0.15)
k.sack(-1.1, BY + 0.05, rz=0.3, c=hexc("b7a27c"))
k.sack(-0.6, BY + 0.15, s=0.85, rz=1.1, c=hexc("a8966e"))
# string of onions / garlic hanging from the front beam
for j in range(2):
    hx = -0.9 + j * 1.9
    k.box((0.01, 0.01, 0.55), (hx, FY, FH - 0.35), W, hexc("c9b78e"), var=0)
    for m in range(5):
        k.sphere(0.045, (hx + (m % 2 - 0.5) * 0.06, FY, FH - 0.2 - m * 0.1), k.M("Plant"),
                 vary(hexc("c28a5a") if j == 0 else hexc("e8dcc0"), 0.08), subdiv=1, grime=False)
# price slate on a stake
k.box((0.02, 0.02, 0.4), (HX - 0.15, FY - 0.08, 1.05), W, WOODC, var=0)
k.box((0.3, 0.025, 0.2), (HX - 0.15, FY - 0.1, 1.2), W, hexc("2c2c2e"), var=0)
k.box((0.34, 0.03, 0.24), (HX - 0.15, FY - 0.09, 1.2), W, WOODC, var=0)
for j in range(2):
    k.box((0.18 - j * 0.06, 0.005, 0.015), (HX - 0.18, FY - 0.115, 1.25 - j * 0.07), W, hexc("e8e4da"), var=0)
k.stage("goods")

k.finish_checked((3.5, 2.5), 3000, cam_dir=(0.9, -1.6, 0.8), fit=0.9)
