"""Hand cart: a small two-wheeled barrow-cart with a plank box on an axle,
spoked iron-tyred wheels, two long handles resting on a leg stand, carrying
a couple of sacks, a bundle of firewood and a basket of turnips.

Run: python3 make_hand_cart.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Box 1.0 m (X) x 0.75 m (Y); wheels r=0.36 m at
x=+0.25; handles run out to x=-1.25. Overall ~1.8 m (X) x 1.0 m (Y) x
~0.95 m. Origin at ground centre under the box; seen broadside, its long side
faces Blender -Y (Godot +Z), handles toward -X.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("HandCart", seed=7171, pal=palette(timber="oak"))
W, MT, CL, MA = k.M("Wood"), k.M("Metal"), k.M("Cloth"), k.M("Matte")
k.grime = 0.35
k.grime_amt = 0.18
WOOD = hexc("8a6a48")
WR, AXX = 0.36, 0.25


def wheel(y, sgn):
    k.push((AXX, y, WR))
    k.ring(WR - 0.05, WR, 0.06, (0, 0, 0), W, vary(WOOD, 0.05), segs=14)
    k.ring(WR, WR + 0.012, 0.055, (0, 0, 0), MT, IRON, segs=14)
    k.cyl(0.07, 0.14, (0, -0.07, 0), W, mix(WOOD, (0, 0, 0), 0.2), rot=(-math.pi / 2, 0, 0), segs=8)
    for i in range(4):
        a = i * math.pi / 4 + 0.2
        k.box((2 * WR - 0.06, 0.03, 0.035), (0, 0, 0), W, vary(WOOD, 0.06), rot=(0, a, 0), var=0)
    k.pop()


wheel(-0.47, -1)
wheel(0.47, 1)
k.cyl(0.03, 0.98, (AXX, -0.49, WR), MT, IRON, rot=(-math.pi / 2, 0, 0), segs=6)
TILT = -math.atan2(WR + 0.06 - 0.45, 1.3)
k.push((AXX, 0, WR + 0.06), (0, TILT, 0))
X0, X1 = -0.8, 0.2
k.box((X1 - X0, 0.72, 0.04), ((X0 + X1) / 2, 0, 0.0), W, vary(WOOD, 0.05), var=0)
for sy in (-1, 1):
    for j in range(2):
        k.box((X1 - X0, 0.03, 0.13), ((X0 + X1) / 2, sy * 0.37, 0.08 + j * 0.15), W, vary(k.plank_c(WOOD), 0.05),
              var=0)
    # handles: long rails under the box running out to the back
    k.bar((X1 + 0.05, sy * 0.3, -0.05), (X0 - 0.5, sy * 0.28, -0.05), 0.055, 0.05, W, vary(WOOD, 0.04), up=(0, 0, 1),
          bevel=0.01)
    k.cyl(0.03, 0.14, (X0 - 0.51, sy * 0.28, -0.05), W, hexc("6b4a2f"), rot=(0, -math.pi / 2, 0), segs=6)
    k.bar((X0 + 0.05, sy * 0.3, -0.05), (X0 + 0.1, sy * 0.3, -0.62), 0.05, 0.05, W, vary(WOOD, 0.04), bevel=0)  # leg
for x in (X0 + 0.015, X1 - 0.015):
    k.box((0.03, 0.72, 0.28), (x, 0, 0.14), W, vary(k.plank_c(WOOD), 0.05), var=0)
for sy in (-1, 1):
    for x in (X0 + 0.02, X1 - 0.02):
        k.box((0.03, 0.03, 0.3), (x, sy * 0.385, 0.15), MT, IRON, var=0)
# load
k.sack(-0.55, -0.15, 0.04, s=0.72, rz=0.4)
k.sack(-0.5, 0.18, 0.04, s=0.68, rz=-0.3, c=hexc("a8936c"))
for i in range(6):   # firewood bundle lying across
    k.log((-0.18 + random.uniform(-0.02, 0.02), -0.3 + i * 0.03, 0.08 + (i % 2) * 0.07),
          (-0.18 + random.uniform(-0.02, 0.02), 0.32 + i * 0.01, 0.08 + (i % 2) * 0.07),
          0.045, W, vary(hexc("5a4330"), 0.12), segs=5, noise_amt=0.005, end_color=hexc("c79c68"), ring_step=3.0)
k.basket(0.02, 0.05, 0.03, r=0.15, h=0.14, goods="onion", n=6)
k.pop()

k.finish_checked((2.0, 1.2), 3000, cam_dir=(0.9, -1.6, 0.8), fit=1.0)
