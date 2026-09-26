"""Lamp post: a squared oak post with chamfered edges on a dressed stone
footing, a moulded cap, an iron bracket arm with a scroll brace and a
hanging iron lantern with emissive glass (material "Lamp", warm glow).

Run: python3 make_lamp_post.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Footing 0.55 m square; post top 2.95 m; the lantern
hangs 0.62 m out on the front (-Y, Godot +Z) with its glass centred at
~2.35 m. Origin at ground centre of the post. Add an OmniLight3D at
(0, 2.35, 0.62) in Godot (the lantern position) for real light.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("LampPost", seed=303, pal=palette(stone="grey", timber="dark"))
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 0.5
k.grime_amt = 0.18
tc = hexc("4a3a2e")

# stone footing (two courses) and a few cobbles
k.box((0.55, 0.55, 0.28), (0, 0, 0.14), MA, vary(hexc("8e887c"), 0.04), bevel=0.03, var=0)
k.box((0.42, 0.42, 0.14), (0, 0, 0.35), MA, vary(hexc("a39c8e"), 0.04), bevel=0.025, var=0)
for i in range(5):
    a = i * math.tau / 5 + random.uniform(-0.2, 0.2)
    k.sphere(0.07, (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.0), MA, vary(hexc("8a857c"), 0.1),
             scale=(1.2, 1.0, 0.5), subdiv=1, noise_amt=0.02)

# chamfered post (octagonal section), slight taper
k.cyl(0.1, 2.5, (0, 0, 0.4), W, tc, segs=8, r2=0.088, smooth=None, rot=(0, 0, math.pi / 8),
      color_fn=lambda f: vary(tc, 0.06, 0.02))
k.box((0.24, 0.24, 0.06), (0, 0, 2.93), W, mix(tc, (0, 0, 0), 0.1), bevel=0.012, var=0)
k.box((0.18, 0.18, 0.05), (0, 0, 2.98), W, tc, bevel=0.01, var=0)
k.cyl(0.07, 0.08, (0, 0, 3.0), MT, IRON, segs=8, r2=0.0)
for z in (0.62, 2.58):   # iron collars
    k.cyl(0.1, 0.05, (0, 0, z), MT, IRON, segs=8, caps=False, rot=(0, 0, math.pi / 8))

# bracket arm with scroll brace, out toward -Y
AZ = 2.72
k.box((0.05, 0.72, 0.05), (0, -0.4, AZ), MT, IRON, var=0)
k.box((0.14, 0.04, 0.3), (0, -0.09, AZ - 0.1), MT, IRON, var=0)
pts = []
for i in range(9):
    t = i / 8
    pts.append((0.0, -0.09 - 0.45 * t, AZ - 0.42 + 0.4 * math.sin(t * math.pi / 2)))
k.tube(pts, [0.016] * len(pts), MT, IRON, segs=5, point_end=False)
sc = [(0.0, -0.09 - 0.1 * math.cos(a) - 0.1, AZ - 0.2 + 0.08 * math.sin(a)) for a in
      [i / 8 * math.tau * 0.9 for i in range(9)]]
k.tube(sc, [0.012] * len(sc), MT, IRON, segs=4, point_end=False)
k.sphere(0.03, (0, -0.78, AZ), MT, IRON, subdiv=1)
k.lantern((0, -0.62, AZ - 0.02), s=1.35)

k.finish_checked((1.0, 1.4), 3000, cam_dir=(1.1, -1.5, 0.45), fit=1.1)
