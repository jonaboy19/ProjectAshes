"""Woodpile: split logs stacked between round posts under a small lean-to
shingle roof on four posts, a chopping block with an axe stuck in it, a few
split pieces and chips on the ground.

Run: python3 make_woodpile.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Stack 2.2 m (X) x 0.6 m deep x 1.3 m high; roof
2.5 x 1.25 m, high side 2.05 m at the back, low side 1.75 m at the front.
Footprint ~2.6 x 1.9 m incl. the chopping block. Origin at ground centre of
the stack; the log ends face Blender -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix

k = TK("Woodpile", seed=4040, pal=palette(roof="shingle_grey", timber="grey"))
W, MT, PL, MA = k.M("Wood"), k.M("Metal"), k.M("Plant"), k.M("Matte")
k.grime = 0.5
k.grime_amt = 0.2

# ground board / sleepers under the stack
for y in (-0.2, 0.2):
    k.box((2.3, 0.12, 0.08), (0, y, 0.04), W, vary(hexc("5a4a3a"), 0.05), var=0)
k.push((0, 0, 0.08))
L, H, D = 2.2, 1.22, 0.6
k.box((L - 0.1, D - 0.12, H - 0.1), (0, 0, H / 2), W, hexc("3b2a1c"), var=0)
r = 0.095
rows = int(H / (r * 1.72))
for j in range(rows):
    n = max(2, int(L / (r * 2.05)))
    offx = (r if j % 2 else 0.0)
    for i in range(n):
        lx = -L / 2 + r + offx + i * (L - 2 * r - offx) / max(1, n - 1)
        lz = r + j * r * 1.72
        rr = r * random.uniform(0.8, 1.12)
        yj = random.uniform(-0.05, 0.05)
        bark = vary(hexc("5a4330"), 0.15, 0.04)
        split = random.random() < 0.55       # split logs: half-round with pale faces
        k.log((lx, -D / 2 + yj, lz), (lx, D / 2 + yj, lz), rr, W, bark, segs=5 if split else 6, noise_amt=0.012,
              end_color=vary(hexc("c79c68") if not split else hexc("d2a978"), 0.12, 0.04), ring_step=2.0)
k.pop()
# stakes at the ends
for sx in (-1, 1):
    for sy in (-1, 1):
        k.log((sx * (L / 2 + 0.07), sy * 0.2, 0.0), (sx * (L / 2 + 0.07) + random.uniform(-0.02, 0.02), sy * 0.2, 1.35),
              0.045, W, hexc("5a4330"), segs=6, noise_amt=0.008, ring_step=2.0)

# lean-to roof on four posts
tc = k.timber()
PX, PY = 1.15, 0.5
for sx in (-1, 1):
    k.bar((sx * PX, -PY, 0.0), (sx * PX, -PY, 1.7), 0.1, 0.1, W, tc, bevel=0.01)
    k.bar((sx * PX, PY, 0.0), (sx * PX, PY, 2.0), 0.1, 0.1, W, tc, bevel=0.01)
    k.bar((sx * PX, -PY - 0.3, 1.66), (sx * PX, PY + 0.2, 2.02), 0.1, 0.08, W, tc, up=(0, 0, 1), bevel=0)   # rafter
    k.bar((sx * PX, PY, 1.55), (sx * PX, PY - 0.35, 1.97), 0.07, 0.06, W, tc, up=(0, 0, 1), bevel=0)      # brace
for y, z in ((-PY, 1.68), (PY, 1.98)):
    k.box((2 * PX + 0.2, 0.09, 0.09), (0, y, z), W, tc, var=0)
run, rise = 1.25, 0.43
k.shingle_side(-1.28, 1.28, run, rise, k.M("Roof"), k.tile, tile_w=(0.14, 0.24), course=0.18, th=0.02,
               deck_mat=W, deck_color=tc, loc=(0, PY + 0.28, 1.63), jag=0.03, droop=0.012)

# chopping block with axe, split pieces and chips
cx, cy = 0.75, -1.05
k.log((cx, cy, 0), (cx, cy, 0.48), 0.24, W, hexc("5a4330"), segs=9, noise_amt=0.02, end_color=hexc("b89068"),
      ring_step=2.0)
k.bar((cx + 0.02, cy, 0.44), (cx - 0.3, cy - 0.35, 0.95), 0.04, 0.035, W, hexc("8a6a48"), up=(0, 0, 1), bevel=0)
k.box((0.03, 0.16, 0.12), (cx + 0.01, cy + 0.02, 0.47), MT, hexc("6a6c70"), rot=(0.25, 0, 0.7), var=0)
for i in range(4):
    a = random.uniform(0, math.tau)
    k.box((0.34, 0.08, 0.07), (cx + math.cos(a) * 0.45, cy + math.sin(a) * 0.4, 0.035), W, vary(hexc("c79c68"), 0.1),
          rot=(0, 0, a + 1.3))
for i in range(14):
    a = random.uniform(0, math.tau)
    rr = random.uniform(0.25, 0.6)
    k.box((0.06, 0.03, 0.01), (cx + math.cos(a) * rr, cy + math.sin(a) * rr, 0.005), W,
          vary(hexc("d8b27e"), 0.12), rot=(0, 0, random.uniform(0, 3)), grime=False)
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(8):
    x = random.choice((-1, 1)) * random.uniform(1.15, 1.35)
    y = random.uniform(-0.5, 0.6)
    for j in range(4):
        k.cyl(random.uniform(0.012, 0.02), random.uniform(0.15, 0.3), (x + random.uniform(-0.06, 0.06),
                                                                        y + random.uniform(-0.06, 0.06), 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
              smooth=None, caps=False)

k.finish_checked((3.0, 2.5), 3000, cam_dir=(1.0, -1.6, 0.6), fit=1.0)
