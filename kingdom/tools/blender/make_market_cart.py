"""Market cart: a two-wheeled wooden farm cart parked with its shafts resting
on the ground, plank bed with staked side boards, iron-tyred spoked wheels,
loaded with crates of produce, grain sacks, a small barrel and a basket, a
canvas half folded over the back.

Run: python3 make_market_cart.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Bed 1.9 m (X) x 1.25 m (Y); wheels r=0.62 m on the
axle at x=+0.15; shafts run out to x=-1.95 where they rest on the ground.
Overall ~3.1 m (X) x 1.6 m (Y) x ~1.55 m. Origin at ground centre under the
bed. The cart is seen broadside: its long side faces Blender -Y (Godot +Z),
shafts toward -X.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("MarketCart", seed=6161, pal=palette(timber="oak"))
W, MT, CL, PL, MA = k.M("Wood"), k.M("Metal"), k.M("Cloth"), k.M("Plant"), k.M("Matte")
k.grime = 0.45
k.grime_amt = 0.2
WOOD = hexc("7a5c3e")
WR = 0.62
AX = 0.15
TILT = -math.atan2(0.66, 2.15)       # bed tips forward so the shafts reach the ground


def wheel(y, sgn):
    k.push((AX, y, WR), (0, 0, 0))
    k.ring(WR - 0.08, WR, 0.09, (0, 0, 0), W, vary(WOOD, 0.05), segs=16)
    k.ring(WR, WR + 0.018, 0.08, (0, 0, 0), MT, IRON, segs=16)
    k.cyl(0.11, 0.24, (0, -0.12, 0), W, mix(WOOD, (0, 0, 0), 0.15), rot=(-math.pi / 2, 0, 0), segs=10)
    k.cyl(0.115, 0.04, (0, sgn * 0.08, 0), MT, IRON, rot=(-math.pi / 2, 0, 0), segs=10, caps=False, base=False)
    for i in range(6):
        a = i * math.pi / 6 + 0.1
        k.bar((math.cos(a) * 0.1, 0, math.sin(a) * 0.1), (math.cos(a) * (WR - 0.06), 0, math.sin(a) * (WR - 0.06)),
              0.045, 0.035, W, vary(WOOD, 0.06), up=(0, 1, 0), bevel=0)
        a += math.pi
        k.bar((math.cos(a) * 0.1, 0, math.sin(a) * 0.1), (math.cos(a) * (WR - 0.06), 0, math.sin(a) * (WR - 0.06)),
              0.045, 0.035, W, vary(WOOD, 0.06), up=(0, 1, 0), bevel=0)
    k.pop()


wheel(-0.74, -1)
wheel(0.74, 1)
k.cyl(0.05, 1.62, (AX, -0.81, WR), MT, IRON, rot=(-math.pi / 2, 0, 0), segs=6)          # axle

# bed frame, tilted about the axle
k.push((AX, 0, WR + 0.12), (0, TILT, 0))
BX0, BX1 = -1.1, 0.8
k.box((BX1 - BX0, 1.25, 0.05), ((BX0 + BX1) / 2, 0, 0.0), W, vary(WOOD, 0.05), var=0)
for i in range(7):   # floor boards (seen at the back edge)
    k.box((BX1 - BX0, 0.17, 0.02), ((BX0 + BX1) / 2, -0.53 + i * 0.177, 0.035), W, vary(WOOD, 0.1), var=0)
for sy in (-1, 1):
    k.box((BX1 - BX0 + 0.1, 0.1, 0.1), ((BX0 + BX1) / 2, sy * 0.58, -0.07), W, mix(WOOD, (0, 0, 0), 0.15), var=0)
    # stakes and side boards
    for x in (BX0 + 0.05, (BX0 + BX1) / 2, BX1 - 0.05):
        k.box((0.06, 0.06, 0.52), (x, sy * 0.65, 0.2), W, mix(WOOD, (0, 0, 0), 0.1), var=0)
    for j in range(3):
        k.box((BX1 - BX0, 0.03, 0.12), ((BX0 + BX1) / 2, sy * 0.62, 0.1 + j * 0.14), W,
              vary(k.plank_c(WOOD), 0.06), var=0)
    k.box((0.03, 0.03, 0.4), (BX0 + 0.5, sy * 0.605, 0.25), MT, IRON, var=0)
# end boards
k.box((0.03, 1.2, 0.3), (BX0 + 0.01, 0, 0.16), W, vary(WOOD, 0.06), var=0)
# shafts
for sy in (-1, 1):
    k.bar((BX1 - 0.1, sy * 0.52, -0.05), (BX0 - 1.05, sy * 0.4, -0.08), 0.07, 0.06, W, vary(WOOD, 0.05),
          up=(0, 0, 1), bevel=0.01)
k.box((0.07, 0.85, 0.06), (BX0 - 0.35, 0, -0.05), W, WOOD, var=0)

# cargo (in the tilted bed frame)
k.crate(-0.65, -0.28, 0.05, s=0.5, rz=0.08)
k.produce(-0.65, -0.28, 0.51, 0.2, "apple", n=10)
k.crate(-0.65, 0.3, 0.05, s=0.48, rz=-0.1)
k.produce(-0.65, 0.3, 0.5, 0.2, "cabbage", n=5)
k.crate(-0.62, 0.0, 0.55, s=0.42, rz=0.25)
k.sack(0.05, -0.3, 0.05, s=0.85, rz=0.3)
k.sack(0.1, 0.25, 0.05, s=0.8, rz=-0.5)
k.sack(0.0, -0.02, 0.38, s=0.7, rz=0.1, c=hexc("a8936c"))
k.barrel(0.55, 0.3, 0.05, r=0.2, h=0.5, segs=8)
k.basket(0.55, -0.3, 0.05, r=0.18, h=0.16, goods="carrot", n=6)
# folded canvas over the back corner
# canvas thrown over the back corner, hanging down over the side board
k.sheet(((0.35, -0.8, 0.02), (0.82, -0.8, 0.05), (0.35, 0.05, 0.62), (0.82, 0.05, 0.6)), 4, 5, CL,
        lambda u, v: vary(mix(hexc("b9a882"), hexc("8f8466"), 0.3 * (1 - v)), 0.02),
        sag_fn=lambda u, v: (0.03 * math.sin(v * 7 + u * 2), -0.12 * math.sin(math.pi * v) * (1 - v),
                             0.3 * math.sin(math.pi * v * 0.9) + 0.04 * math.sin(u * 9 + v * 4)), both=True)
k.pop()

# a prop stone under the shaft ends and a few grass tufts
k.sphere(0.12, (-1.95, -0.4, 0.0), MA, vary(hexc("8a857c"), 0.08), scale=(1.2, 1.0, 0.6), subdiv=1, noise_amt=0.02)
k.sphere(0.12, (-1.95, 0.4, 0.0), MA, vary(hexc("8a857c"), 0.08), scale=(1.2, 1.0, 0.6), subdiv=1, noise_amt=0.02)

k.pbr = dict(size=512, seed=23, ao_dist=0.35, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((3.3, 1.8), 3000, cam_dir=(0.8, -1.6, 0.7), fit=0.95)
