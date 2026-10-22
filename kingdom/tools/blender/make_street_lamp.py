"""Tall Kingsreach street lamp: a dark iron-banded oak post on a dressed stone
base, a curved iron bracket arm and a big hanging warm-glass lantern
(emissive glass, material "Lamp"). Taller and grander than the ordinary
lamp_post prop, for the main market street / gate approach.

Run: python3 make_street_lamp.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Stone base 0.66 m square; post to 3.75 m, finial ball to
3.95 m. The bracket arm reaches 0.78 m out on the front (-Y, Godot +Z) with
the lantern glass centred at ~3.45 m. Origin at ground centre of the post.
Add an OmniLight3D at (0, 3.45, 0.78) in Godot for real light. Budget: <= 1500
triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "kingdom", "assets", "art", "textures")

k = TK("StreetLamp", seed=707, pal=palette(stone="warm", timber="dark"))
k.pbr = dict(size=512, seed=1, ao_dist=0.3, cage=0.02, ray=0.06)   # high-to-low PBR bake (pbr_kit.py)
k.weather_ao = 0.34
MA, W, MT = k.M("Matte"), k.M("Wood"), k.M("Metal")
k.grime = 0.6
k.grime_amt = 0.18
tc = mix(hexc("352418"), hexc("15100c"), 0.35)   # dark iron-stained oak

# ---------------------------------------------------------------- stone base (two courses + apron)
k.box((0.66, 0.66, 0.16), (0, 0, 0.08), MA, vary(hexc("cab08a"), 0.05), bevel=0.03, var=0)
k.image_quad(os.path.join(TEX, "stone_wall_blocks.png"), 0.6, 0.13, (0, -0.332, 0.08), repeat=(1.8, 0.4),
             double_sided=False)
k.box((0.48, 0.48, 0.16), (0, 0, 0.24), MA, vary(hexc("bba583"), 0.05), bevel=0.025, var=0)
for i in range(6):
    a = i * math.tau / 6 + random.uniform(-0.2, 0.2)
    k.sphere(0.07, (math.cos(a) * 0.46, math.sin(a) * 0.46, 0.0), MA, vary(hexc("b7a488"), 0.1), scale=(1.2, 1.0, 0.5),
             subdiv=1, noise_amt=0.02)

# ---------------------------------------------------------------- chamfered post (octagonal), slight taper
POST_H = 3.15
k.cyl(0.1, POST_H, (0, 0, 0.32), W, tc, segs=8, r2=0.082, smooth=None, rot=(0, 0, math.pi / 8),
      color_fn=lambda f: vary(tc, 0.06, 0.02))
for z in (0.75, 1.9, 3.05):   # iron bands (dark, monumental post)
    k.cyl(0.105, 0.06, (0, 0, z), MT, IRON, segs=8, caps=False, rot=(0, 0, math.pi / 8))
k.box((0.26, 0.26, 0.07), (0, 0, POST_H + 0.36), W, mix(tc, (0, 0, 0), 0.1), bevel=0.012, var=0)
k.box((0.2, 0.2, 0.06), (0, 0, POST_H + 0.42), W, tc, bevel=0.01, var=0)
k.cyl(0.075, 0.09, (0, 0, POST_H + 0.47), MT, IRON, segs=8, r2=0.0)
k.sphere(0.06, (0, 0, POST_H + 0.55), MT, IRON, subdiv=1, grime=False)

# ---------------------------------------------------------------- bracket arm with scroll brace, toward -Y
AZ = POST_H + 0.17
k.box((0.06, 0.85, 0.06), (0, -0.46, AZ), MT, IRON, var=0)
k.box((0.15, 0.045, 0.34), (0, -0.1, AZ - 0.12), MT, IRON, var=0)
pts = []
for i in range(9):
    t = i / 8
    pts.append((0.0, -0.1 - 0.52 * t, AZ - 0.48 + 0.46 * math.sin(t * math.pi / 2)))
k.tube(pts, [0.018] * len(pts), MT, IRON, segs=5, point_end=False)
sc = [(0.0, -0.1 - 0.11 * math.cos(a) - 0.11, AZ - 0.22 + 0.09 * math.sin(a)) for a in
      [i / 8 * math.tau * 0.9 for i in range(9)]]
k.tube(sc, [0.013] * len(sc), MT, IRON, segs=4, point_end=False)
k.sphere(0.032, (0, -0.9, AZ), MT, IRON, subdiv=1)
k.lantern((0, -0.78, AZ - 0.02), s=1.6)

k.finish_checked((1.1, 1.6), 1500, cam_dir=(1.1, -1.5, 0.5), fit=1.05)
