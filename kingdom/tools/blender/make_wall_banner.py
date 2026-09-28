"""Wall banner: a flat red cloth banner with gold trim and the gold crown/gate
emblem (tower_crown.png decal), hanging from a short iron rod for mounting
on walls, gatehouses and towers. A cheap, mostly-flat prop (no LOD needed).

Run: python3 make_wall_banner.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. 0.8 m wide x 2.0 m long. Origin/pivot at the top centre
of the mounting rod (z=0): the rod sits right at the origin and the cloth
hangs straight down from there to z=-2.0, offset a hair into Blender -Y
(Godot +Z) from the rod so it clears whatever it is mounted flush against.
To hang it elsewhere, just rotate the node's Y axis; the emblem always faces
the -Y (Godot +Z) side. Budget: <= 400 triangles.
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette
from ra_kit import hexc

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CROWN = os.path.join(ROOT, "kingdom", "assets", "art", "emblems", "tower_crown.png")

k = VK("WallBanner", seed=515, pal=palette())
CRIMSON, GOLD = hexc("9b1d24"), hexc("d4a63a")
k.grime = 0.0
# the pivot sits at the TOP of this asset (the mounting rod) and the cloth
# hangs down into -Z, so ra_polish's ground-plane passes (which assume z=0 is
# the floor) would wrongly treat the whole banner as "below ground" and
# delete it; this small flat prop doesn't need the weathering bake anyway.
k.polish = False

k.banner(0, 0.0, w=0.8, h=2.0, color=CRIMSON, trim=GOLD, emblem=None, y=-0.09, rod=True, tail="point")
k.image_quad(CROWN, 0.42, 0.42, (0, -0.09 - 0.024, -0.85), key="Crown", double_sided=True)

k.finish_checked((1.2, 0.3), 400, cam_dir=(0.4, -1.6, 0.15), fit=1.0)
