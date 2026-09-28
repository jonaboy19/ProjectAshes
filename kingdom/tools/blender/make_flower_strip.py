"""Flower strip: a 3 m long low ribbon of grass tufts, white daisies and
yellow flowers, plus a cobblestone edge, to plant along building and wall
feet the way the reference lines its streets with flowers at every wall base.

Run: python3 make_flower_strip.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. 3.0 m long (X) x ~0.5 m deep (Y), flowers up to ~0.3 m
tall. Origin at ground centre. Not directional (scatter reads the same from
either long side); place it flush along a wall/building foot. Budget: <= 1200
triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette
from ra_kit import hexc, vary, mix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "kingdom", "assets", "art", "textures")

k = VK("FlowerStrip", seed=2626, pal=palette())
PL, MA = k.M("Plant"), k.M("Matte")
GREENS = [hexc("4f7a34"), hexc("5d8a3a"), hexc("3f6b2e"), hexc("6b8f3f")]
DAISY = hexc("f8f5ea")
DAISY_CTR = hexc("f2c94c")
YELLOW = hexc("f2c94c")
L = 3.0

# a thin hand-painted cobblestone edge the flowers spill out of
k.image_quad(os.path.join(TEX, "cobblestone.png"), L - 0.06, 0.26, (0, -0.15, 0.005), rot=(-math.pi / 2, 0, 0),
             repeat=(3.4, 0.3), double_sided=False)
k.box((L, 0.26, 0.01), (0, -0.15, -0.004), MA, vary(hexc("a89a80"), 0.05), var=0, grime=False)


def clump(x, y, bloom, daisy=False):
    r = random.uniform(0.1, 0.15)
    k.sphere(r, (x, y, r * 0.75), PL, vary(random.choice(GREENS), 0.12), scale=(1.1, 0.9, 0.8), subdiv=0,
             noise_amt=0.04, grime=False)
    n = random.randint(3, 4)
    for j in range(n):
        a = random.uniform(0, math.tau)
        px, py = x + math.cos(a) * r * 0.7, y + math.sin(a) * r * 0.65
        pz = r * 1.35 + random.uniform(0.0, 0.07)
        if daisy:
            k.box((0.08, 0.08, 0.012), (px, py, pz), PL, DAISY, rot=(random.uniform(-0.4, 0.4),
                  random.uniform(-0.4, 0.4), a), grime=False)
            k.sphere(0.018, (px, py, pz + 0.006), PL, DAISY_CTR, subdiv=0, grime=False)
        else:
            k.box((0.06, 0.06, 0.06), (px, py, pz), PL, vary(bloom, 0.08), rot=(0.6, 0.4, a), grime=False)


random.seed(2626)
N = 8
for i in range(N):
    x = -L / 2 + (i + 0.5) * L / N + random.uniform(-0.06, 0.06)
    y = random.uniform(0.0, 0.13)
    clump(x, y, YELLOW, daisy=(i % 2 == 0))
# a scatter of loose daisies/buttercups between the clumps, right at the cobble edge
for i in range(6):
    x = random.uniform(-L / 2 + 0.1, L / 2 - 0.1)
    y = random.uniform(-0.09, -0.01)
    if i % 2 == 0:
        k.box((0.07, 0.07, 0.01), (x, y, 0.1 + random.uniform(0, 0.04)), PL, DAISY,
              rot=(random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5), random.uniform(0, math.tau)), grime=False)
        k.sphere(0.016, (x, y, 0.11 + random.uniform(0, 0.04)), PL, DAISY_CTR, subdiv=0, grime=False)
    else:
        k.box((0.05, 0.05, 0.05), (x, y, 0.08 + random.uniform(0, 0.05)), PL, vary(YELLOW, 0.08),
              rot=(0.6, 0.4, random.uniform(0, math.tau)), grime=False)

k.finish_checked((3.1, 0.6), 1200, cam_dir=(0.55, -1.2, 0.7), fit=1.0)
