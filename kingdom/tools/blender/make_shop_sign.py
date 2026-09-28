"""Shop sign: an iron wall bracket with a hanging shield-shaped board, red with
a gold crown emblem on both faces, and a small lantern. A cheap, mostly-solid
prop for shopfronts along the market street.

Run: python3 make_shop_sign.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. The wall plate sits at (0, 0, 2.2) (attach that point to
the wall); the bracket reaches 1.1 m out into Blender -Y (Godot +Z) and the
shield hangs square to the street, emblem facing +-Y. Origin at ground level
below the mount, matching the rest of the kit. Budget: <= 600 triangles.
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, IRON
from ra_kit import hexc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CROWN = os.path.join(ROOT, "kingdom", "assets", "art", "emblems", "tower_crown.png")

k = VK("ShopSign", seed=616, pal=palette())
CRIMSON, GOLD = hexc("9b1d24"), hexc("d4a63a")
k.grime = 0.3

Z = 2.2
ARM, SIZE = 1.1, 0.85
k.hanging_sign(0, Z, emblem=None, board_c=CRIMSON, arm=ARM, size=SIZE, lantern=False, shape="shield")
# gold crown decal on both faces of the board: same local frame hanging_sign uses
# internally for its own emblem() calls (pushed at the board centre, rotated 90
# degrees so the board's XZ plane faces the street).
bx = -ARM * 0.55
bz = Z - 0.1 - SIZE * 0.55
k.push((0, bx, bz), (0, 0, math.pi / 2))
s = SIZE * 0.5 * 0.95
for sd, rot in ((-1, (0, 0, 0)), (1, (0, math.pi, 0))):
    k.image_quad(CROWN, s, s, (0, sd * 0.06, 0.02), rot=rot, key="Crown", double_sided=False)
k.pop()

k.finish_checked((1.3, 1.3), 600, cam_dir=(1.1, -1.6, 0.35), fit=1.0)
