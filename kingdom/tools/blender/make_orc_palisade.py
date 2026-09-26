"""Orc palisade: a 6 m straight, tileable section of sharpened log wall with
rope lashings, two back rails, raking back props, a few iron-banded logs,
war paint on the front and one skull trophy.

Run: python3 make_orc_palisade.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. 6.0 m long (X, from x=-3.0 to +3.0 so sections tile
end-to-end every 6 m), logs 3.0-3.7 m above ground, sunk 0.5 m below z=0 for
uneven terrain. ~0.4 m thick wall; back props reach 1.5 m behind (+Y).
Origin at ground centre of the wall line. The outer (enemy) face with paint
and the skull faces Blender -Y = Godot +Z; rails and props are on +Y.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("OrcPalisade", seed=31)
WOOD = k.material("Wood", rough=0.85)
ROPE = k.material("Rope", rough=1.0, spec=0.2)
PAINT = k.material("Paint", rough=0.7)
BONE = k.material("Bone", rough=0.6, spec=0.45)

LOGS = [hexc("6e5238"), hexc("5f4630"), hexc("7a5c3f"), hexc("67503a"), hexc("735538")]
RED = hexc("9e2b22")

x = -3.0
i = 0
tops = []
while x < 3.0 - 0.05:
    r = random.uniform(0.13, 0.17)
    if x + 2 * r > 3.0:
        r = (3.0 - x) / 2
    cx = x + r
    h = random.uniform(3.0, 3.7)
    lean = random.uniform(-0.03, 0.03)
    col = vary(random.choice(LOGS), 0.08)
    k.log((cx, random.uniform(-0.03, 0.03), -0.5), (cx + lean, random.uniform(-0.03, 0.03), h - 0.35), r, WOOD, col,
          segs=7, r_end=r * 0.92, noise_amt=0.02, point=0.4 + random.uniform(-0.05, 0.1),
          end_color=mix(col, hexc("c9a878"), 0.4), ring_step=1.0)
    tops.append((cx, h, r))
    x = cx + r + random.uniform(0.0, 0.015)
    i += 1

# rope lashings: a rope weaving across the log fronts at two heights, plus
# hidden straight runs at the back
for z in (1.0, 2.55):
    pts, rad = [], []
    for (cx, h, r) in tops:
        pts.append((cx - r * 0.95, -r * 0.35 - 0.03, z + random.uniform(-0.02, 0.02)))
        pts.append((cx, -r - 0.03, z - 0.015))
    pts.append((3.0, -0.08, z))
    k.tube(pts, [0.032] * len(pts), ROPE, hexc("a58a5c"), segs=4, cap_start=False, point_end=False, smooth=70)
    k.box((6.0, 0.05, 0.06), (0, 0.17, z), ROPE, hexc("8f774e"), var=0.04)

# back rails + raking props at each end and in the middle (props sit inside the
# section so neighbours do not collide)
for z in (0.9, 2.35):
    k.log((-3.0, 0.3, z), (3.0, 0.3, z), 0.1, WOOD, vary(hexc("5e4630"), 0.05), segs=7, noise_amt=0.015)
for px in (-2.4, 0.0, 2.4):
    k.log((px, 1.55, -0.2), (px, 0.35, 2.3), 0.09, WOOD, vary(hexc("5a432e"), 0.06), segs=6, noise_amt=0.015)
    k.log((px, 0.4, -0.2), (px, 0.4, 0.95), 0.08, WOOD, vary(hexc("5a432e"), 0.06), segs=6, noise_amt=0.01)

# war paint: each stroke is laid on every log it crosses as a curved strip
# hugging the log front (so it reads as paint, not floating planks)
import bmesh
def stroke(x0, z0, x1, z1, width, col):
    slope = (z1 - z0) / (x1 - x0)
    for (cx, h, r) in tops:
        if not (min(x0, x1) - r * 0.5 < cx < max(x0, x1) + r * 0.5):
            continue
        zc = z0 + slope * (cx - x0)
        t = bmesh.new()
        lo, hi = [], []
        rr = r + 0.012
        for th in (-70, -35, 0, 35, 70):
            a = math.radians(th)
            x = cx + rr * math.sin(a)
            y = -rr * math.cos(a)
            z = zc + slope * (x - cx)
            lo.append(t.verts.new((x, y, z - width / 2)))
            hi.append(t.verts.new((x, y, z + width / 2)))
        for i in range(len(lo) - 1):
            t.faces.new((lo[i], lo[i + 1], hi[i + 1], hi[i]))
        k._merge(t, PAINT, vary(col, 0.05), None, 80, 0.0, None, False)
stroke(-2.3, 1.2, -1.2, 2.1, 0.09, RED)
stroke(-2.1, 1.05, -1.0, 1.95, 0.09, RED)
stroke(-1.9, 0.9, -0.8, 1.8, 0.09, RED)
stroke(0.8, 2.2, 2.1, 1.5, 0.12, RED)
stroke(0.9, 1.3, 1.9, 1.3, 0.06, hexc("e6dcc8"))

# a skull trophy spiked on the tallest log near the centre
cx, h, r = max(tops[len(tops) // 3: 2 * len(tops) // 3], key=lambda t: t[1])
k.skull((cx, -0.22, h - 0.75), (0.1, 0, 0), 0.9, BONE, bone=hexc("e0d5bc"), dark=hexc("1e1712"),
        horn_c=hexc("4a3f33"), tusks=True)

print("triangles:", k.tri_count())
k.finish(cam_dir=(0.9, -1.8, 0.5), fit=0.95)
