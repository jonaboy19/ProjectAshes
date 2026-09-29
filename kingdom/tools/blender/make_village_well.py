"""Village well: round fieldstone shaft with a dressed coping, two oak posts
carrying a small shingled gable roof, a windlass with rope coils and an iron
crank, a bucket hanging on the rope, a second pail on the coping and a paved
apron of radial slabs with grass creeping over its edge.

Run: python3 make_village_well.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Shaft outer radius 0.82 m, coping top 0.93 m, apron
radius 1.22 m, roof 1.9 m (X) x 1.9 m (Y), ridge ~2.75 m. Overall footprint
<= 2.5 x 2.5 m. Origin at ground centre of the shaft. The crank handle is on
+X; the front (-Y, Godot +Z) is the side the spare pail sits on.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR
from ra_kit import hexc, vary, mix

k = TK("VillageWell", seed=2024, pal=palette(stone="field", roof="shingle_brown", timber="oak"))
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 0.5
R_OUT, R_IN, TOP = 0.82, 0.56, 0.86

# ---------------------------------------------------------------- apron
polys, cols = [], []
n = 16
for ring, (r0, r1) in enumerate(((R_OUT - 0.02, 1.02), (1.02, 1.22))):
    ph = random.uniform(0, 1) + ring * 0.5
    m = n + ring * 4
    for i in range(m):
        a0 = (i + ph) * math.tau / m + 0.012
        a1 = (i + 1 + ph) * math.tau / m - 0.012
        rr1 = r1 - random.uniform(0.0, 0.06) * ring
        z = 0.05 - ring * 0.015 + random.uniform(-0.01, 0.01)
        pts = []
        for rr, a in ((r0 + 0.012, a0), (rr1 - 0.012, a0), (rr1 - 0.012, a1), (r0 + 0.012, a1)):
            pts.append((math.cos(a) * rr, math.sin(a) * rr, z))
        polys.append(tuple(pts))
        c = mix(k.stone(), hexc("6c6862"), 0.3)
        if random.random() < 0.2:
            c = mix(c, hexc("5d6b3e"), 0.3)
        cols.append(c)
k.quads(polys, cols, MA, grime=False)
k.cyl(1.2, 0.03, (0, 0, 0.0), MA, hexc("3b3732"), segs=20, var=0, grime=False, smooth=None)

# ---------------------------------------------------------------- shaft
k.cyl(R_OUT - 0.12, TOP - 0.02, (0, 0, 0), MA, MORTAR, segs=16, var=0, caps=False)
k.stone_ring(0, 0, R_OUT, 0.02, TOP, bw=0.4, bh=0.2, gap=0.028, push=0.03, seg_len=0.24,
             color_fn=lambda: mix(k.stone(), hexc("5d6b3e"), 0.25) if random.random() < 0.12 else k.stone())
k.stone_ring(0, 0, R_IN, 0.3, TOP, inward=True, bw=0.36, bh=0.19, gap=0.028, push=0.02, seg_len=0.22,
             color_fn=lambda: mix(k.stone(), MORTAR, 0.45), grime=False)
k.cyl(R_IN + 0.08, 0.02, (0, 0, 0.3), MA, hexc("1c1a18"), segs=16, var=0, grime=False)
k.cyl(R_IN, 0.01, (0, 0, 0.34), k.M("Water"), hexc("2c4a5a"), segs=16, var=0, grime=False)
# coping: wedge stones with a slightly rounded top
nc = 11
for i in range(nc):
    a0 = i * math.tau / nc + 0.015
    a1 = (i + 1) * math.tau / nc - 0.015
    am = (a0 + a1) / 2
    k.push((0, 0, TOP), (0, 0, am))
    ro, ri = R_OUT + 0.06, R_IN - 0.02
    half_o = math.tan((a1 - a0) / 2) * ro
    half_i = math.tan((a1 - a0) / 2) * ri
    pts = [(ri, -half_i), (ro, -half_o), (ro, half_o), (ri, half_i)]
    h = 0.08 + random.uniform(-0.01, 0.01)
    t_pts = [(x, y) for x, y in pts]
    k.push((0, 0, 0), (math.pi / 2, 0, 0))
    k.prism([(x, y) for x, y in t_pts], h, (0, h / 2, 0), MA, mix(k.stone(), hexc('a39c8c'), 0.3), var=0)
    k.pop()
    k.pop()

# ---------------------------------------------------------------- posts, roof frame
PX, PT = 0.74, 2.12
tc = k.timber()
for sx in (-1, 1):
    k.bar((sx * PX, 0, 0.05), (sx * PX, 0, PT), 0.15, 0.15, W, vary(tc, 0.05), bevel=0.02)
    for sy in (-1, 1):   # knee braces under the plate
        k.bar((sx * PX, sy * 0.04, PT - 0.5), (sx * PX, sy * 0.52, PT - 0.08), 0.08, 0.08, W, tc, up=(0, 0, 1),
              bevel=0)
k.box((0.14, 1.2, 0.12), (-PX, 0, PT - 0.03), W, tc, bevel=0.015)
k.box((0.14, 1.2, 0.12), (PX, 0, PT - 0.03), W, tc, bevel=0.015)
k.box((2 * PX + 0.3, 0.12, 0.12), (0, 0, PT + 0.08), W, tc, bevel=0.015)       # tie beam
k.box((0.1, 0.1, 0.55), (0, 0, PT + 0.38), W, tc)                  # king post
RUN, RISE = 0.95, 0.62
ZE = PT - 0.02
for s in (0, math.pi):
    k.shingle_side(-0.96, 0.96, RUN, RISE, k.M("Roof"), k.tile, tile_w=(0.16, 0.27), course=0.19, th=0.02,
                   deck_mat=W, deck_color=tc, rot=(0, 0, s), loc=(0, 0, ZE), jag=0.03, droop=0.01)
k.box((2.02, 0.12, 0.1), (0, 0, ZE + RISE + 0.06), W, mix(tc, (0, 0, 0), 0.2), bevel=0.02)   # ridge board
for sx in (-1, 1):
    for sy in (-1, 1):
        k.bar((sx * 0.98, sy * (RUN + 0.02), ZE - 0.06), (sx * 0.98, 0, ZE + RISE + 0.02), 0.14, 0.04, W, tc,
              up=(0, 0, 1), bevel=0)
    # small rafter feet under the eaves
    for sy in (-1, 1):
        k.bar((sx * 0.55, sy * 0.9, ZE - 0.02), (sx * 0.55, 0, ZE + RISE - 0.05), 0.07, 0.06, W, tc, up=(0, 0, 1),
              bevel=0.0)

# ---------------------------------------------------------------- windlass
AZ = 1.42
k.log((-PX - 0.1, 0, AZ), (PX + 0.16, 0, AZ), 0.055, W, hexc("6b5238"), segs=8, noise_amt=0.004,
      end_color=hexc("a88b64"), ring_step=2.0)
k.log((-0.34, 0, AZ), (0.34, 0, AZ), 0.1, W, hexc("5d4631"), segs=10, noise_amt=0.004, ring_step=2.0)
ROPE = hexc("c9a66b")
# rope coils: one lathe with a bumpy profile, alternating light/dark per coil
prof = []
for i in range(9):
    x = -0.3 + i * 0.075
    prof += [(0.108, x - 0.035), (0.128, x), (0.108, x + 0.035)]
k.lathe(prof, (0, 0, AZ), k.M("Cloth"), vary(ROPE, 0.04), segs=9, rot=(0, math.pi / 2, 0), smooth=80)
for sx in (-1, 1):   # iron bearings on the posts
    k.box((0.2, 0.18, 0.08), (sx * PX, 0, AZ - 0.085), MT, IRON, var=0)
# crank: iron arm and wooden handle on +X
cx = PX + 0.16
k.bar((cx, 0, AZ), (cx, 0.12, AZ - 0.36), 0.05, 0.035, MT, IRON, up=(1, 0, 0), bevel=0)
k.log((cx - 0.02, 0.12, AZ - 0.36), (cx + 0.2, 0.12, AZ - 0.36), 0.025, W, hexc("8a6a48"), segs=6,
      noise_amt=0.0, ring_step=2.0)
# rope down to the hanging bucket
k.tube([(0.2, -0.13, AZ - 0.02), (0.18, -0.13, AZ - 0.25), (0.12, -0.1, 1.2)], [0.017] * 3, k.M("Cloth"), ROPE,
       segs=5, point_end=False)
BZ = 0.9
k.push((0.12, -0.08, 0), (0, 0, 0.3))
k.bucket(0, 0, BZ, r=0.15)
k.tube([(-0.15, 0, BZ + 0.2)] + [(-0.15 * math.cos(a), 0, BZ + 0.2 + 0.12 * math.sin(a)) for a in
                                  (0.5, 1.0, 1.57, 2.1, 2.6)] + [(0.15, 0, BZ + 0.2)],
       [0.009] * 7, MT, IRON, segs=4, point_end=False)
k.pop()
# spare pail on the coping, front
k.bucket(-0.35, -0.62, TOP + 0.08, r=0.13)
k.tube([(-0.35 - 0.13 * math.cos(a), -0.62 - 0.05 * math.sin(a) * 0, TOP + 0.08 + 0.2 + 0.1 * math.sin(a))
        for a in (0.0, 0.8, 1.57, 2.34, 3.14)], [0.008] * 5, MT, IRON, segs=4, point_end=False)

# ---------------------------------------------------------------- grass and weeds around the apron
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(16):
    a = random.uniform(0, math.tau)
    rr = random.uniform(1.12, 1.22)
    for j in range(3):
        b = a + random.uniform(-0.05, 0.05)
        k.cyl(random.uniform(0.012, 0.02), random.uniform(0.12, 0.28),
              (math.cos(b) * rr, math.sin(b) * rr, 0.0), PL, vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), b), grime=False, smooth=None, caps=False)
for a in (0.7, 2.4, 4.1):   # weed tufts at the foot of the shaft
    k.bush(math.cos(a) * 0.9, math.sin(a) * 0.9, r=0.1, c=hexc("56803a"))

k.pbr = dict(size=512, seed=12, ao_dist=0.4, cage=0.03, ray=0.08)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((2.5, 2.5), 3000, cam_dir=(1.1, -1.5, 0.8), fit=0.98)
