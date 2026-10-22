"""Village market stall: a trestle counter under a striped canvas awning that
really drapes (sags between the rafters, droops at the front, folds over the
side rails) with a scalloped valance, rope ties to the posts, a hanging lantern,
goods heaped in baskets and a tilted display crate, crates and sacks stacked
behind, strings of onions / herbs and a price slate.

Run: python3 make_village_stall.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Footprint <= 3.5 (X) x 2.5 (Y); awning peak ~2.6 m.
Origin at ground centre; the counter (customer side) faces Blender -Y
(Godot +Z).
Variant 1: red/cream awning, apples, pears, cabbages, carrots.
Variant 2: green/ochre awning, bread, onions, fish and plums.
Variant 3: blue/cream awning, apples, onions, bread, cabbages.
Variant 4: saffron/rust awning, pears, carrots, plums, onions.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON
from ra_kit import hexc, mix, vary

V = variant_arg()
k = VK("VillageStall" + ("" if V == 1 else f"_{V}"), seed=808 + V * 29, pal=palette())
W, CL, MT = k.M("Wood"), k.M("Cloth"), k.M("Metal")
STRIPES = {1: (hexc("b0372a"), hexc("ecdfc0")), 2: (hexc("3f7a4a"), hexc("e3c078")),
           3: (hexc("2f5d9a"), hexc("ebe2ca")), 4: (hexc("d99a2b"), hexc("9c4a2a"))}[V]
GOODS = {1: ["apple", "cabbage", "pear", "carrot"], 2: ["bread", "onion", "fish", "plum"],
         3: ["apple", "onion", "bread", "cabbage"], 4: ["pear", "carrot", "plum", "onion"]}[V]
WOODC = {1: hexc("8a6a48"), 2: hexc("6b4a2f"), 3: hexc("7d5e40"), 4: hexc("94704a")}[V]
ROPE = hexc("c9b48a")

HX = 1.55
FY, BY = -0.85, 0.85         # front / back post lines
FH, BH = 2.05, 2.5           # post heights
k.grime, k.grime_amt = 0.45, 0.2

# ---------------------------------------------------------------- frame (squared posts, braced)
for x in (-HX, HX):
    k.bar((x, FY, 0), (x, FY, FH - 0.1), 0.1, 0.1, W, WOODC, bevel=0.015)
    k.bar((x, BY, 0), (x, BY, BH - 0.1), 0.1, 0.1, W, WOODC, bevel=0.015)
    k.bar((x, FY - 0.02, FH - 0.16), (x, BY + 0.02, BH - 0.16), 0.08, 0.07, W, WOODC, up=(0, 0, 1), bevel=0.01)
    k.bar((x, FY, 0.35), (x, BY, 0.35), 0.07, 0.06, W, mix(WOODC, (0, 0, 0), 0.1), up=(0, 0, 1), bevel=0)
    for (yy, hh, sg) in ((FY, FH, 1), (BY, BH, -1)):   # knee braces
        k.bar((x - 0.02 * 0, yy, hh - 0.62), (x, yy + sg * 0.42, hh - 0.2), 0.06, 0.05, W, WOODC,
              up=(0, -sg, 1), bevel=0)
    for (yy, hh) in ((FY, FH), (BY, BH)):              # squat stone pads under the posts
        k.box((0.2, 0.2, 0.08), (x, yy, 0.04), k.M("Matte"), vary(hexc("9a948a"), 0.05), var=0)
for (yy, hh) in ((FY, FH), (BY, BH)):
    k.bar((-HX - 0.1, yy, hh - 0.17), (HX + 0.1, yy, hh - 0.17), 0.08, 0.07, W, WOODC, up=(0, 0, 1), bevel=0.01)
# counter: plank top on trestles, boarded front, shelf underneath
k.box((2 * HX + 0.2, 0.75, 0.06), (0, FY + 0.3, 0.86), W, vary(WOODC, 0.05), bevel=0.012)
with k.grain_axis("z"):
    k.box((2 * HX + 0.1, 0.03, 0.55), (0, FY - 0.05, 0.56), W, mix(WOODC, (0, 0, 0), 0.12))
for i in range(6):
    k.box((0.03, 0.035, 0.55), (-HX + 0.25 + i * (2 * HX - 0.5) / 5, FY - 0.07, 0.56), W,
          mix(WOODC, (0, 0, 0), 0.3), var=0)
k.box((2 * HX - 0.1, 0.55, 0.04), (0, FY + 0.32, 0.36), W, mix(WOODC, (0, 0, 0), 0.08), var=0)
for sx in (-1, 1):
    k.box((0.06, 0.6, 0.06), (sx * (HX - 0.3), FY + 0.3, 0.8), W, mix(WOODC, (0, 0, 0), 0.2))
k.stage("frame")

# ---------------------------------------------------------------- awning: draped striped canvas
NS = 8
over = 0.28
X0, X1 = -HX - 0.15, HX + 0.15
yb, zb = BY + 0.14, BH + 0.03          # back edge (tied over the back beam)
yf, zf = FY - over, FH - 0.1           # front edge (hangs past the front beam)
fold = 0.24                            # cloth folded down over the side rails


def drape(gx, v):
    """Offset of the canvas at global across-fraction gx (0..1), front->back v (0..1)."""
    between = 0.09 * math.sin(math.pi * v) ** 1.2          # belly between front and back beams
    front = 0.07 * (1 - v) ** 3 * math.sin(math.pi * gx)    # the free front edge droops mid-span
    ripple = 0.018 * math.sin(gx * math.pi * 6.0) * math.sin(math.pi * v)
    dz = -(between * (0.55 + 0.45 * math.sin(math.pi * gx)) + front + ripple)
    # fold over the side rails: the outer 7% of the width bends down
    e = min(gx, 1 - gx)
    if e < 0.07:
        dz -= fold * (1 - e / 0.07) ** 1.6
    return dz


for i in range(NS):
    c = STRIPES[i % 2]
    x0 = X0 + i * (X1 - X0) / NS
    x1 = x0 + (X1 - X0) / NS
    nu = 1

    def sag(u, v, i=i):
        gx = (i + u) / NS
        return (0, 0, drape(gx, 1 - v))
    k.sheet(((x0, yf, zf), (x1, yf, zf), (x0, yb, zb), (x1, yb, zb)), nu, 4, CL,
            lambda u, v, c=c: tuple(ch * (0.84 + 0.16 * v) for ch in c), sag_fn=sag, smooth=None)
    # scalloped valance tab hanging from the (drooping) front edge
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
# rope ties from the canvas corners down to the posts, and rope lashings at the joints
for sx in (-1, 1):
    k.tube([(sx * (HX + 0.13), yf + 0.02, zf - fold + 0.02), (sx * (HX + 0.12), FY - 0.1, FH - 0.55),
            (sx * HX, FY - 0.05, FH - 0.9)], [0.012, 0.012, 0.012], CL, ROPE, segs=4, point_end=False,
           cap_start=False)
    k.tube([(sx * (HX + 0.13), yb - 0.02, zb - fold + 0.02), (sx * HX, BY + 0.05, BH - 1.0)], [0.012, 0.012], CL,
           ROPE, segs=4, point_end=False, cap_start=False)
    for (yy, hh) in ((FY, FH - 0.2), (BY, BH - 0.2)):
        k.ring(0.055, 0.075, 0.12, (sx * HX, yy, hh - 0.04), CL, ROPE, rot=(math.pi / 2, 0, 0), segs=6)
k.stage("awning")

# ---------------------------------------------------------------- lantern + hanging strings
k.box((0.03, 0.03, 0.18), (HX - 0.55, FY, FH - 0.28), MT, IRON, var=0)
k.lantern((HX - 0.55, FY, FH - 0.36), s=0.75)
for j, hx in enumerate((-0.95, -0.35)):
    k.box((0.01, 0.01, 0.5), (hx, FY, FH - 0.43), W, ROPE, var=0)
    kind = GOODS[1] if GOODS[1] in ("onion",) else ("herb" if j else "onion")
    for m in range(4):
        if kind == "herb":
            k.cyl(0.05, 0.14, (hx, FY, FH - 0.3 - m * 0.11), k.M("Plant"),
                  vary(hexc("6f8f3a") if m % 2 else hexc("8a7a4a"), 0.08), segs=5, r2=0.015, rot=(math.pi, 0, 0),
                  grime=False)
        else:
            k.sphere(0.05, (hx + (m % 2 - 0.5) * 0.06, FY, FH - 0.25 - m * 0.1), k.M("Plant"),
                     vary(hexc("c28a5a") if j == 0 else hexc("e8dcc0"), 0.08), subdiv=0, grime=False, smooth=70)
k.stage("lantern")

# ---------------------------------------------------------------- goods, arranged with care
GY = FY + 0.32
xs = [-1.12, -0.38, 0.38, 1.12]
for idx, (x, g) in enumerate(zip(xs, GOODS)):
    if g in ("bread", "fish"):
        k.box((0.62, 0.45, 0.05), (x, GY, 0.915), W, hexc("b08a55"), bevel=0.01)       # flat tray / board
        k.produce(x, GY, 0.94, 0.24, g, n=8 if g == "bread" else 9)
    elif idx in (1, 2):
        # tilted display crate leaning toward the customer, heaped
        k.push((x, GY + 0.02, 0.89), (-0.32, 0, 0))
        k.box((0.52, 0.4, 0.05), (0, 0, 0.025), W, vary(hexc("9a7a50"), 0.05), var=0)
        for sx in (-1, 1):
            k.box((0.04, 0.4, 0.16), (sx * 0.24, 0, 0.1), W, vary(hexc("8e6a42"), 0.05), var=0)
        for sy in (-1, 1):
            k.box((0.52, 0.04, 0.16 if sy > 0 else 0.1), (0, sy * 0.18, 0.08), W, vary(hexc("8e6a42"), 0.05), var=0)
        k.produce(0, 0, 0.06, 0.2, g, n=10)
        k.pop()
    else:
        k.basket(x, GY + (-0.04 if idx % 2 else 0.04), z=0.89, r=0.24, h=0.18, goods=g)
# crates, a barrel and sacks beneath / behind
k.crate(-0.9, FY + 0.45, s=0.5, rz=0.05, c=vary(hexc("9a7a50"), 0.08))
k.produce(-0.9, FY + 0.45, 0.47, 0.2, GOODS[0], n=7)
k.crate(0.7, BY + 0.02, s=0.55, rz=-0.12)
k.crate(0.74, BY + 0.02, z=0.55, s=0.42, rz=0.1)
k.produce(0.74, BY + 0.02, 0.95, 0.17, GOODS[3], n=6)

k.sack(-1.1, BY + 0.05, rz=0.3, c=hexc("c2ad84"))
k.sack(-0.62, BY + 0.12, s=0.85, rz=1.1, c=hexc("b09d74"))
k.sack(-0.85, BY - 0.15, z=0.0, s=0.7, rz=2.0, c=hexc("a8966e"))
# price slate on a stake
k.box((0.02, 0.02, 0.4), (HX - 0.15, FY - 0.08, 1.05), W, WOODC, var=0)
k.box((0.3, 0.025, 0.2), (HX - 0.15, FY - 0.1, 1.2), W, hexc("2c2c2e"), var=0)
k.box((0.34, 0.03, 0.24), (HX - 0.15, FY - 0.09, 1.2), W, WOODC, var=0)
for j in range(2):
    k.box((0.18 - j * 0.06, 0.005, 0.015), (HX - 0.18, FY - 0.115, 1.25 - j * 0.07), W, hexc("e8e4da"), var=0)
k.stage("goods")

k.pbr = dict(size=512, seed=8 + V, ao_dist=0.35, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((3.5, 2.5), 2964, cam_dir=(0.9, -1.6, 0.8), fit=0.9)
