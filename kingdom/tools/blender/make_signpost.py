"""Crossroads signpost: a weathered round oak post with a little shingled cap,
three pointed arrow boards at different heights and bearings with carved
(dark) lettering on both faces, iron straps, a cairn of stones at the foot
and grass tufts.

Run: python3 make_signpost.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Post 2.7 m, cap to ~2.95 m; boards 1.0-1.15 m long,
0.24 m tall. Overall footprint ~2.2 x 1.9 m. Origin at ground centre of the
post. Boards point toward -X, +X (front, -Y side) and +Y-ish; rotate the node
to aim them.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("Signpost", seed=512, pal=palette(roof="shingle_grey"))
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 0.5
k.grime_amt = 0.2
POST = hexc("6f5a45")

k.log((0, 0, -0.05), (0.02, 0.01, 2.72), 0.075, W, POST, segs=8, noise_amt=0.012, ring_step=0.6,
      end_color=hexc("a38c6c"))
# cap: tiny pyramid of shingles on a block
k.box((0.2, 0.2, 0.08), (0.02, 0.01, 2.74), W, mix(POST, (0, 0, 0), 0.2), var=0)
k.cyl(0.19, 0.16, (0.02, 0.01, 2.78), W, mix(POST, hexc("7d7a70"), 0.3), segs=4, r2=0.02, rot=(0, 0, math.pi / 4),
      smooth=None, var=0)
k.sphere(0.03, (0.02, 0.01, 2.95), MT, IRON, subdiv=0)

BOARDS = [(2.3, math.radians(180), 1.1, hexc("8a6e50")), (1.95, math.radians(-15), 1.0, hexc("7c6147")),
          (1.62, math.radians(95), 1.05, hexc("927659"))]
INK = hexc("2a211a")
for z, ang, L, c in BOARDS:
    k.push((0.02, 0.01, z), (0, 0, ang))
    h = 0.24
    pts = [(0.06, -h / 2), (L - 0.22, -h / 2), (L, 0.0), (L - 0.22, h / 2), (0.06, h / 2)]
    k.prism(pts, 0.035, (0, -0.1, 0), W, vary(c, 0.06), bevel=0.008, var=0,
            color_fn=lambda f, c=c: vary(mix(c, hexc('8a877a'), random.uniform(0, 0.35)), 0.05))
    for side in (-1, 1):
        # carved lettering: a row of short dark strokes
        x = 0.22
        while x < L - 0.36:
            wl = random.randint(3, 6)                  # a word of wl letters
            for li in range(wl):
                if x > L - 0.36:
                    break
                wd = random.uniform(0.012, 0.03)
                hh = random.uniform(0.05, 0.075)
                k.quad(wd, hh, (x + wd / 2, -0.1 + side * 0.0185, random.uniform(-0.006, 0.006)), MA,
                       mix(INK, c, 0.25), rot=(0, 0, 0 if side < 0 else math.pi), var=0.05, grime=False)
                x += wd + 0.014
            x += 0.045
    k.box((0.06, 0.045, h + 0.02), (0.1, -0.1, 0), MT, IRON, var=0)
    k.box((0.04, 0.05, 0.04), (0.1, -0.1, 0), MT, IRON, var=0)
    k.pop()

# cairn of fieldstones + grass
for i in range(9):
    a = random.uniform(0, math.tau)
    r = random.uniform(0.12, 0.32)
    k.sphere(random.uniform(0.08, 0.14), (math.cos(a) * r, math.sin(a) * r, 0.02 + (0.06 if r < 0.2 else 0.0)), MA,
             vary(random.choice([hexc("8a857c"), hexc("9a9384"), hexc("7a766e")]), 0.1), scale=(1.2, 1.0, 0.7),
             subdiv=1, noise_amt=0.03, rot=(0, 0, a))
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(10):
    a = random.uniform(0, math.tau)
    r = random.uniform(0.3, 0.55)
    for j in range(4):
        k.cyl(random.uniform(0.012, 0.02), random.uniform(0.15, 0.35),
              (math.cos(a) * r + random.uniform(-0.08, 0.08), math.sin(a) * r + random.uniform(-0.08, 0.08), 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
              smooth=None, caps=False)

k.pbr = dict(size=512, seed=26, ao_dist=0.3, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((2.4, 2.4), 3000, cam_dir=(0.9, -1.6, 0.5), fit=1.05)
