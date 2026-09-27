"""Flower bed to scatter at house fronts and along fences: an oval bed edged with
rounded stones, dark soil, leafy clumps, drifts of low flowers (five-petal
stars in white, yellow, pink and red), a few tall lavender / foxglove spikes and
a little mint-green ground cover. Low geometry only, no alpha cards.

Run: python3 make_flower_bed.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. ~1.9 m (X) x 1.0 m (Y), up to ~0.7 m tall. Origin at the
ground centre; the tall spikes stand toward +Y (the back), so face -Y (Godot +Z)
to the street. < 1500 triangles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, FLOWERS, STONE
from ra_kit import hexc, mix, vary
import bmesh
from mathutils import Vector

V = variant_arg()
k = VK("FlowerBed" + ("" if V == 1 else f"_{V}"), seed=919 + V * 7, pal=palette(stone="grey"))
PL, MA = k.M("Plant"), k.M("Matte")


def flower(pts, c):
    """Flat five-petal flower head (one polygon, 8 triangles) facing the frame's -Y."""
    t = bmesh.new()
    vs = [t.verts.new((x, 0.0, z)) for x, z in pts]
    t.faces.new(vs)
    bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
    if t.faces[0].normal.y > 0:
        t.faces[0].normal_flip()
    # back side (4 mm behind) so the head shows from every angle with back-face culling on
    t.faces.new([t.verts.new(v.co + Vector((0, 0.004, 0))) for v in reversed(list(t.faces[0].verts))])
    k._merge(t, PL, c, k.xf((0, 0, 0)), None, 0.0, None, False)

k.grime, k.grime_amt = 0.15, 0.1
RX, RY = 0.9, 0.46
FL = {1: [FLOWERS[2], FLOWERS[1], FLOWERS[5], FLOWERS[0]], 2: [FLOWERS[3], FLOWERS[2], FLOWERS[6], FLOWERS[4]],
      3: [FLOWERS[1], FLOWERS[4], FLOWERS[0], FLOWERS[2]]}[V]
SPIKE = {1: hexc("9b7fd0"), 2: hexc("e27aa8"), 3: hexc("9b7fd0")}[V]

# soil mound
k.sphere(1.0, (0, 0, -0.02), MA, hexc("4a3526"), scale=(RX, RY, 0.09), subdiv=1, face_var=0.03, grime=False)
# stone edging
n = 12
for i in range(n):
    a = i / n * math.tau
    x, y = math.cos(a) * (RX + 0.02), math.sin(a) * (RY + 0.02)
    k.sphere(random.uniform(0.07, 0.1), (x, y, 0.03), MA, k.stone(), scale=(1.3, 1.0, 0.7), subdiv=0,
             rot=(0, 0, a), noise_amt=0.02, smooth=60)


def inside(fx, fy):
    return (fx / (RX - 0.1)) ** 2 + (fy / (RY - 0.08)) ** 2 < 1.0


# leafy clumps, each crowned with a few flowers (so the bed reads as flowering plants)
greens = [hexc("4f8a34"), hexc("5f9a3a"), hexc("3f7a2e"), hexc("6fa044")]
pts = []
while len(pts) < 7:
    fx, fy = random.uniform(-RX, RX), random.uniform(-RY, RY)
    if inside(fx, fy) and all((fx - a) ** 2 + (fy - b) ** 2 > 0.09 for a, b in pts):
        pts.append((fx, fy))


def petals(r):
    return [(math.cos(j * math.pi / 5) * (r if j % 2 == 0 else r * 0.45),
             math.sin(j * math.pi / 5) * (r if j % 2 == 0 else r * 0.45)) for j in range(10)]


for ci, (fx, fy) in enumerate(pts):
    r = random.uniform(0.14, 0.19)
    h = r * 0.8
    zc = 0.04 + h * 0.45
    k.sphere(r, (fx, fy, zc), PL, random.choice(greens), scale=(1.15, 1.0, 0.8), subdiv=1,
             noise_amt=0.015, grime=False, face_var=0.0, smooth=180)
    c = FL[ci % len(FL)]
    for j in range(5):
        a = j * math.tau / 5 + random.uniform(-0.4, 0.4)
        rr = r * random.uniform(0.25, 0.75)
        up = 1.0 - (rr / r) ** 2
        k.push((fx + math.cos(a) * rr * 1.1, fy + math.sin(a) * rr, zc + h * (0.35 + 0.65 * up ** 0.5) + 0.01),
               (-math.pi / 2 + (rr / r) * 0.9, 0, a - math.pi / 2))
        flower(petals(random.uniform(0.05, 0.065)), vary(c, 0.06))
        k.pop()
# ground cover
for i in range(3):
    fx, fy = random.uniform(-RX * 0.8, RX * 0.8), random.uniform(-RY * 0.7, RY * 0.7)
    k.sphere(0.14, (fx, fy, 0.04), PL, hexc("7fb05a"), scale=(1.4, 1.0, 0.35), subdiv=0, grime=False, smooth=70)
# tall spikes at the back (lavender / foxglove) in two tufts: slim tapered cones on stems
for tuft in (-0.5, 0.45):
    for i in range(5):
        a = i * math.tau / 5 + random.uniform(-0.3, 0.3)
        fx = tuft * RX + math.cos(a) * 0.09
        fy = RY * 0.4 + math.sin(a) * 0.06
        h = random.uniform(0.42, 0.6)
        tilt = (math.sin(a) * 0.15, -math.cos(a) * 0.15, 0)
        k.cyl(0.01, h * 0.55, (fx, fy, 0.03), PL, hexc("4f7a34"), segs=3, grime=False, rot=tilt)
        k.cyl(0.03, h * 0.48, (fx + math.cos(a) * 0.08 * h, fy + math.sin(a) * 0.08 * h, 0.03 + h * 0.5), PL,
              vary(SPIKE, 0.08), segs=5, r2=0.006, grime=False, rot=tilt)
k.finish_checked((2.1, 1.2), 1500, cam_dir=(0.9, -1.6, 0.9), fit=0.9)
