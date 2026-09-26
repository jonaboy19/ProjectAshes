"""Haystack: a traditional round rick of hay built around a pole, settled and
leaning slightly, with straw streaks running down its flanks, a weathered
grey-brown cap, a greener, trampled skirt, loose wisps at the foot, a hay
rope with stone weights over the top and a pitchfork left leaning on it.

Run: python3 make_haystack.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. ~2.9 m across at the widest, ~3.2 m to the top of the
stack, pole tip ~3.7 m. Leans ~5 degrees toward +X. Origin at ground centre.
The pitchfork leans on the front (-Y, Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON
from ra_kit import hexc, vary, mix
from mathutils import Vector, noise

k = TK("Haystack", seed=88, pal=palette())
TH, W, MT, PL, MA = k.M("Thatch"), k.M("Wood"), k.M("Metal"), k.M("Plant"), k.M("Matte")
k.grime = 0.6
k.grime_amt = 0.15
HAY = [hexc("a88b4c"), hexc("c2a35c"), hexc("94783f"), hexc("d0b46c"), hexc("86703f"), hexc("b89a57"), hexc("9f8a55")]
CAP = hexc("7d725e")
SKIRT = hexc("8b8a4a")
LEAN = 0.09
off = random.uniform(0, 50)

BASE = [(1.28, -0.05), (1.4, 0.25), (1.45, 0.65), (1.42, 1.1), (1.34, 1.5), (1.18, 1.9)]
# thatched cap: overlapping layers, each a small overhanging ledge
CAPL = []
for i in range(6):
    z = 1.9 + i * 0.21
    f = (z - 1.9) / 1.32
    r = 1.18 * math.sqrt(max(0.0, 1 - f * f)) * (1 - 0.1 * f)
    f2 = (z + 0.19 - 1.9) / 1.32
    r2 = 1.18 * math.sqrt(max(0.0, 1 - f2 * f2)) * (1 - 0.1 * f2)
    CAPL += [(r + 0.035, z + 0.02), (r2 + 0.005, z + 0.2)]
CAPL += [(0.1, 3.15), (0.0, 3.2)]
prof = BASE + CAPL


def rad_at(zq):
    for (r0, z0), (r1, z1) in zip(prof[:-1], prof[1:]):
        if z0 <= zq <= z1 and z1 > z0:
            return r0 + (r1 - r0) * (zq - z0) / (z1 - z0)
    return 0.0


def vfn(co):
    z = co.z
    r = math.hypot(co.x, co.y)
    if r > 1e-4:
        n = noise.noise(Vector((co.x * 0.9, co.y * 0.9, z * 0.7 + off))) * 0.09
        n += noise.noise(Vector((co.x * 4.0, co.y * 4.0, z * 3.0 + off))) * 0.03
        n += noise.noise(Vector((co.x * 9.0, co.y * 9.0, z * 1.0 + off))) * 0.012
        sag = 0.05 * math.sin(math.atan2(co.y, co.x) * 3 + off)          # uneven settling
        f = (r + n + sag * min(1.0, z / 1.2)) / r
        co.x *= f
        co.y *= f
    co.x += LEAN * z
    return co


def surf(a, zq, out=0.0):
    """Point on the (deformed) stack surface at angle a and height zq, pushed out."""
    r = rad_at(zq)
    p = vfn(Vector((math.cos(a) * r, math.sin(a) * r, zq)))
    return Vector((p.x + math.cos(a) * out, p.y + math.sin(a) * out, p.z))


def vcol(co):
    z = co.z
    a = math.atan2(co.y, co.x - LEAN * z)
    st = noise.noise(Vector((a * 9.0, z * 0.4, off))) * 0.5 + 0.5
    st2 = noise.noise(Vector((a * 25.0, z * 1.5, off + 3))) * 0.35
    c = HAY[int(min(0.999, max(0.0, st + st2)) * len(HAY))]
    k2 = 0.85 + 0.25 * noise.noise(Vector((co.x * 1.5, co.y * 1.5, z * 1.5 + off + 5)))
    c = tuple(x * k2 for x in c)
    if z > 1.9:
        c = mix(c, CAP, min(0.7, (z - 1.9) / 1.2 * 0.7))
    if z < 0.5:
        c = mix(c, SKIRT, (0.5 - z) / 0.5 * 0.45)
    return c


fine = []
for i in range(len(prof) - 1):
    (r0, z0), (r1, z1) = prof[i], prof[i + 1]
    steps = 2 if (i < len(BASE) - 1) else 1
    for s_ in range(steps):
        t = s_ / steps
        fine.append((r0 + (r1 - r0) * t, z0 + (z1 - z0) * t))
fine.append(prof[-1])
k.lathe(fine, (0, 0, 0), TH, HAY[0], segs=30, smooth=70, vfn=vfn, vcol=vcol)
# straw litter around the foot (irregular flat patch)
k.lathe([(0.0, 0.012), (1.3, 0.012), (1.75, 0.004)], (0, 0, 0), TH, hexc("a89452"), segs=20, smooth=None,
        vfn=lambda co: Vector((co.x * (1 + 0.25 * noise.noise(co * 1.3 + Vector((off, 0, 0)))) + LEAN * 0.0,
                               co.y * (1 + 0.25 * noise.noise(co * 1.3 + Vector((off, 0, 0)))), co.z)),
        vcol=lambda co: mix(hexc("a38f55"), hexc("6f8a40"), min(1.0, max(0.0, math.hypot(co.x, co.y) - 1.25) * 2.0)))
# wisps sticking out of the flanks
for i in range(40):
    a = random.uniform(0, math.tau)
    zq = random.uniform(0.3, 2.6)
    p = surf(a, zq, -0.02)
    k.cyl(random.uniform(0.01, 0.018), random.uniform(0.15, 0.32), tuple(p), TH, vary(random.choice(HAY), 0.08),
          segs=3, r2=0.0, rot=(0, random.uniform(1.9, 2.5), a), grime=False, smooth=None, caps=False)

# pole
k.log((0.28, 0.0, 2.6), (0.34, 0.02, 3.75), 0.05, W, hexc("5a4330"), segs=6, noise_amt=0.01, ring_step=2.0,
      point=0.06)

# hay rope over the top with stone weights hanging on both sides
for ang in (0.35, 0.35 + math.pi / 2):
    pts = []
    for zq in (1.35, 1.7, 2.05, 2.35, 2.6, 2.85, 3.05):
        pts.append(tuple(surf(ang, zq, 0.05)))
    top = surf(0, 3.2, 0.0)
    pts.append((top.x, top.y, top.z + 0.03))
    for zq in (3.05, 2.85, 2.6, 2.35, 2.05, 1.7, 1.35):
        pts.append(tuple(surf(ang + math.pi, zq, 0.05)))
    k.tube(pts, [0.03] * len(pts), k.M("Cloth"), hexc("8f7a4a"), segs=5, point_end=False)
    for e, a2 in ((pts[0], ang), (pts[-1], ang + math.pi)):
        k.tube([e, (e[0] + math.cos(a2) * 0.08, e[1] + math.sin(a2) * 0.08, e[2] - 0.3)], [0.025, 0.025],
               k.M("Cloth"), hexc("8f7a4a"), segs=4, point_end=False)
        k.sphere(0.14, (e[0] + math.cos(a2) * 0.12, e[1] + math.sin(a2) * 0.12, e[2] - 0.42), MA,
                 vary(hexc("8a857c"), 0.1), scale=(1.1, 1.0, 0.85), subdiv=1, noise_amt=0.03)

# loose straw at the foot
for i in range(26):
    a = random.uniform(0, math.tau)
    r = random.uniform(1.35, 1.75)
    k.cyl(random.uniform(0.012, 0.02), random.uniform(0.25, 0.5), (math.cos(a) * r, math.sin(a) * r, 0.0), TH,
          vary(random.choice(HAY), 0.08), segs=3, r2=0.0,
          rot=(random.uniform(0.6, 1.3) * random.choice((-1, 1)), random.uniform(-0.5, 0.5), a), grime=False,
          smooth=None, caps=False)
# pitchfork leaning on the front
fp = surf(-math.pi / 2 - 0.25, 1.8, 0.03)
fb = (fp.x - 0.25, fp.y - 0.75, 0.0)
k.log(fb, (fp.x, fp.y, fp.z), 0.028, W, hexc("8a6a48"), segs=6, noise_amt=0.0, ring_step=3.0)
d = (Vector((fp.x, fp.y, fp.z)) - Vector(fb)).normalized()
head = Vector((fp.x, fp.y, fp.z)) + d * 0.05
side = d.cross(Vector((0, 0, 1))).normalized()
k.bar(tuple(head - side * 0.11), tuple(head + side * 0.11), 0.035, 0.03, MT, IRON, bevel=0)
for dx in (-0.1, 0.0, 0.1):
    b0 = head + side * dx
    k.tube([tuple(b0), tuple(b0 + d * 0.2 + Vector((0, 0.02, 0))), tuple(b0 + d * 0.38 + Vector((0, 0.06, 0)))],
           [0.013, 0.011, 0.004], MT, IRON, segs=4)

k.finish_checked((4.2, 4.2), 3000, cam_dir=(1.0, -1.6, 0.55), fit=0.9)
