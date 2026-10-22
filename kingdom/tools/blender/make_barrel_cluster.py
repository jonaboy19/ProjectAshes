"""Barrel cluster: three market barrels, two crates and a grouped sack pile,
huddled together as loose street clutter (against a wall, beside a stall, in
a gate passage corner).

Run: python3 make_barrel_cluster.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Footprint roughly 1.3 x 1.1 m, tallest barrel ~0.9 m.
Origin at ground centre; not strongly directional (reads fine from any side),
but the crates and sacks face slightly toward Blender -Y (Godot +Z) for the
best "front" view. Budget: <= 2000 triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette
from ra_kit import hexc, vary, mix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "kingdom", "assets", "art", "textures")

k = VK("BarrelCluster", seed=3131, pal=palette())
W, MA = k.M("Wood"), k.M("Matte")
k.grime, k.grime_amt = 0.4, 0.2

# a few loose wood planks (a broken pallet) under the cluster, hand-painted texture
k.image_quad(os.path.join(TEX, "wood_planks.png"), 1.6, 1.55, (0.0, -0.1, 0.012), rot=(-math.pi / 2, 0, 0),
             repeat=(3.1, 3.0), double_sided=False)
k.box((1.55, 1.5, 0.02), (0, -0.1, 0.0), MA, vary(hexc("6a5236"), 0.06), var=0, grime=False)

# three barrels: two standing apart, one fallen on its side in front
k.barrel(-0.55, 0.42, r=0.26, h=0.7)
k.barrel(0.1, 0.55, r=0.24, h=0.64)
k.push((0.45, 0.05, 0.23), (math.pi / 2, 0, -0.35))
k.barrel(0, 0, r=0.23, h=0.58)
k.pop()

# two crates side by side toward the front, one with a smaller crate on top
k.crate(-0.15, -0.5, s=0.48, rz=-0.15)
k.crate(0.38, -0.48, s=0.4, rz=0.2)
k.crate(-0.12, -0.52, z=0.46, s=0.3, rz=0.5)

# a grouped sack pile, three distinct sacks leaning together
k.sack(-0.68, -0.15, rz=0.4, c=hexc("c2ad84"))
k.sack(-0.9, 0.12, s=0.82, rz=1.2, c=hexc("b09d74"))
k.sack(-0.62, 0.22, z=0.0, s=0.62, rz=2.0, c=hexc("a8966e"))

k.pbr = dict(size=512, seed=27, ao_dist=0.3, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((1.9, 1.75), 2000, cam_dir=(1.0, -1.5, 0.7), fit=1.05)
