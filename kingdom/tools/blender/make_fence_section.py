"""Rustic post-and-rail fence section (3.0 m) that tiles end to end.

Weathered round post at the -X end (plus a lighter mid post), two slightly sagging rails running
the full 3 m (their +X ends tuck into the next section's post), iron nails /
lashing at the posts, and grass tufts along the foot.

Run: python3 make_fence_section.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Section spans x in [-1.5, +1.5]; the post is centred
on x = -1.5, so sections placed every 3.0 m along X form a continuous fence
(add one extra section, or any post, to close the +X end of a run). Height
~1.15 m, depth ~0.2 m. Origin at ground level, centre of the section; the
"front" (-Y, Godot +Z) is the side the rails are nailed to.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON
from ra_kit import hexc, mix, vary

V = variant_arg()
k = VK("FenceSection" + ("" if V == 1 else f"_{V}"), seed=909 + V, pal=palette())
k.deform_amp = k.deform_sag = 0      # tiles end to end: no bow / sag (seams must match)
W, MT, PL = k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 0.35
WOOD = hexc("7f6a54") if V == 1 else hexc("6b5540")

def post(x, r, h):
    lean = random.uniform(-0.03, 0.03)
    k.log((x, 0.02, -0.05), (x + lean, 0.02 + random.uniform(-0.02, 0.02), h), r, W, vary(WOOD, 0.08), segs=8,
          noise_amt=0.014, point=0.05, end_color=hexc("a38c6c"), ring_step=0.3,
          zfn=lambda c, z: mix(c, hexc("4f5a3a"), 0.35) if z < 0.12 else c)


post(-1.5, 0.085, 1.12)
post(0.0, 0.065, 1.02)
# two split rails, each a gently sagging, knotty tube nailed to the front of the posts
for z, rr in ((0.45, 0.055), (0.9, 0.05)):
    z0 = z + random.uniform(-0.03, 0.03)
    z1 = z + random.uniform(-0.03, 0.03)
    sag = random.uniform(0.02, 0.04)
    pts = []
    n = 9
    for i in range(n + 1):
        t = i / n
        x = -1.62 + t * 3.16
        zz = z0 + (z1 - z0) * t - sag * math.sin(math.pi * t)
        pts.append((x, -0.085 + random.uniform(-0.012, 0.012), zz + random.uniform(-0.008, 0.008)))
    c = vary(WOOD, 0.06)
    k.tube(pts, [rr * random.uniform(0.82, 1.15) for _ in pts], W, c, segs=6, cap_start=True, point_end=False,
           color_fn=lambda f, c=c: vary(mix(c, hexc("5a4a3a"), random.random() * 0.4), 0.08), grime=True, smooth=35)
    for px in (-1.5, 0.0):
        k.box((0.03, 0.02, 0.03), (px, -0.145, z0 + (z1 - z0) * (px + 1.62) / 3.16), MT, IRON, var=0)
        k.cyl(0.095 if px < -1 else 0.075, 0.05, (px, 0.0, z0 + (z1 - z0) * (px + 1.62) / 3.16 - 0.08), W,
              hexc("b8a47c"), segs=8, caps=False, grime=False)
# grass blades and a weed or two along the foot of the fence


def tuft(cx, cy, n, hmax):
    for i in range(n):
        a = random.uniform(0, math.tau)
        rr = random.uniform(0.0, 0.1)
        k.cyl(random.uniform(0.012, 0.022), random.uniform(0.4, 1.0) * hmax,
              (cx + math.cos(a) * rr, cy + math.sin(a) * rr, 0.0), PL,
              vary(random.choice([hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("8f9a5a")]), 0.1),
              segs=3, r2=0.0, rot=(random.uniform(-0.45, 0.45), random.uniform(-0.45, 0.45), a), grime=False, smooth=None,
              caps=False)


tuft(-1.5, 0.02, 14, 0.4)
tuft(0.0, 0.02, 10, 0.32)
for x in (-0.8, 0.7, 1.2):
    tuft(x + random.uniform(-0.1, 0.1), random.uniform(-0.05, 0.1), 6, 0.25)

k.finish_checked((3.3, 0.5), 3000, cam_dir=(0.7, -1.6, 0.55), fit=0.85)
