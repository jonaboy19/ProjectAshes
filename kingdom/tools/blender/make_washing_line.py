"""Washing line: two weathered T-posts 5 m apart with a sagging rope, a
forked prop pole holding the middle up, sheets, a shirt, a smock and small
cloths pegged on and stirring in the breeze, and a wicker basket of washing
on the grass.

Run: python3 make_washing_line.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Posts at x = -2.5 and +2.5 (5.0 m apart), 2.0 m tall
with 0.7 m cross arms; line at ~1.85 m sagging to ~1.65 m. Footprint
~5.3 x 1.4 m. Origin at ground centre between the posts; the basket side is
the front (-Y, Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("WashingLine", seed=5151, pal=palette())
W, CL, PL = k.M("Wood"), k.M("Cloth"), k.M("Plant")
k.grime = 0.4
k.grime_amt = 0.2
POST = hexc("6f6252")
ROPE = hexc("cdb892")
X0, X1, ZL = -2.5, 2.5, 1.86
SAG = 0.22

for x in (X0, X1):
    k.log((x, 0, -0.05), (x + random.uniform(-0.03, 0.03), 0.0, 2.02), 0.055, W, POST, segs=7, noise_amt=0.01,
          ring_step=0.5, end_color=hexc("9c8a6c"))
    k.bar((x, -0.35, 1.9), (x, 0.35, 1.9), 0.07, 0.06, W, vary(POST, 0.05), up=(0, 0, 1), bevel=0.008)
    for sy in (-1, 1):
        k.bar((x, 0.0, 1.62), (x, sy * 0.22, 1.87), 0.04, 0.04, W, POST, up=(0, 0, 1), bevel=0)


def line_z(x, sag=SAG):
    t = (x - X0) / (X1 - X0)
    return ZL - sag * 4 * t * (1 - t)


# two lines (front and back ends of the cross arms)
LINES = {-0.25: SAG, 0.25: SAG * 0.8}
for y, sag in LINES.items():
    pts = [(X0 + (X1 - X0) * i / 14, y, line_z(X0 + (X1 - X0) * i / 14, sag) + 0.03) for i in range(15)]
    k.tube(pts, [0.009] * len(pts), CL, ROPE, segs=4, point_end=False)
# prop pole with a fork in the middle of the front line
px = 0.35
k.log((px + 0.15, -0.55, 0.0), (px, -0.25, line_z(px) - 0.02), 0.03, W, hexc("7d6a52"), segs=5, noise_amt=0.005,
      ring_step=3.0)
for s in (-1, 1):
    k.bar((px, -0.25, line_z(px) - 0.03), (px + s * 0.07, -0.25, line_z(px) + 0.1), 0.025, 0.025, W, hexc("7d6a52"),
          bevel=0)


def hang(xa, xb, y, h, color_fn, sway=0.1, sag=SAG, nu=6, nv=4, notch=0.0):
    za, zb = line_z(xa, sag) + 0.02, line_z(xb, sag) + 0.02

    def sag_fn(u, v):
        wv = math.sin(u * 3.0 + v * 1.5) * sway * (1 - v)
        bulge = 0.05 * math.sin(math.pi * u) * (1 - v)
        return (0, wv + bulge, notch * math.sin(math.pi * u) * (1 - v) ** 2)
    corners = ((xa, y, za - h), (xb, y, zb - h), (xa, y, za), (xb, y, zb))
    k.sheet(corners, nu, nv, CL, color_fn, sag_fn=sag_fn, smooth=60)
    for x in (xa + 0.05, xb - 0.05):   # pegs
        z = line_z(x, sag) + 0.02
        k.box((0.02, 0.03, 0.09), (x, y, z - 0.02), W, hexc("b8a27c"), var=0, grime=False)


WHITE, CREAM, BLUE, OCHRE, RED = hexc("e8e2d4"), hexc("dcd0b4"), hexc("7a8fa8"), hexc("c49a52"), hexc("9a4a3a")
yF = -0.25
hang(-2.2, -1.1, yF, 1.05, lambda u, v: vary(WHITE, 0.02), sway=0.12, nu=7, nv=5)
hang(-0.95, -0.35, yF, 0.72, lambda u, v: BLUE if 0.35 < u < 0.65 or v > 0.2 else mix(BLUE, WHITE, 0.25), sway=0.08,
     nu=5, nv=4)
hang(0.55, 1.5, yF, 0.95, lambda u, v: CREAM if int(u * 6) % 2 == 0 else mix(CREAM, RED, 0.5), sway=0.1, nu=6,
     nv=4)
hang(1.65, 2.15, yF, 0.4, lambda u, v: vary(OCHRE, 0.03), sway=0.06, nu=3, nv=2)
yB = 0.25
hang(-1.9, -0.7, yB, 0.9, lambda u, v: vary(CREAM, 0.02), sway=0.1, sag=SAG * 0.8, nu=6, nv=4)
hang(0.2, 0.7, yB, 0.45, lambda u, v: vary(WHITE, 0.02), sway=0.06, sag=SAG * 0.8, nu=3, nv=2)
hang(1.0, 2.0, yB, 1.0, lambda u, v: vary(hexc("b7a88c"), 0.02), sway=0.1, sag=SAG * 0.8, nu=6, nv=4)

# wicker basket of folded washing
bx, by = -0.6, -0.8
k.cyl(0.26, 0.26, (bx, by, 0), W, hexc("b08a55"), segs=12, r2=0.32,
      color_fn=lambda f: vary(hexc("b08a55"), 0.1))
k.cyl(0.33, 0.04, (bx, by, 0.24), W, hexc("8d6c40"), segs=12, caps=False)
for i, c in enumerate((WHITE, BLUE, CREAM)):
    k.box((0.42 - i * 0.05, 0.3, 0.07), (bx + random.uniform(-0.03, 0.03), by, 0.22 + i * 0.065), CL, c, bevel=0.02,
          rot=(0, 0, random.uniform(-0.3, 0.3)))
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for x in (X0, X1):
    for j in range(8):
        k.cyl(random.uniform(0.012, 0.02), random.uniform(0.15, 0.3), (x + random.uniform(-0.15, 0.15),
                                                                        random.uniform(-0.15, 0.15), 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
              smooth=None, caps=False)

k.finish_checked((5.4, 1.6), 3000, cam_dir=(0.6, -1.6, 0.45), fit=0.85)
