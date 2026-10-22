"""Village chapel: a small Romanesque stone chapel. Coursed warm limestone on
a plinth, stepped buttresses, round-headed windows with leaded glass, an
arched west door up a step under a rose window, stone-coped gables with a
bell-cote (and its bell) on the west apex and a cross on the east gable, a
steep slate nave roof and a lower, narrower chancel.

Run: python3 make_chapel.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Nave walls 6.8 m (X) x 9.5 m (Y), chancel 4.8 x 3.1 m;
with buttresses, eaves and the west step the footprint is ~8.9 x 13.9 m.
Nave eaves ~5.2 m, ridge ~9.6 m, bell-cote top ~12 m. Origin at ground centre
of the whole plan. The west door faces Blender -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, LIMESTONE, arch_hole, rect_hole, DRESSED
from ra_kit import hexc, vary, mix

k = TK("Chapel", seed=1234, pal=palette(stone="warm", roof="slate_grey", timber="dark", door="natural"))
k.p["stone"] = LIMESTONE
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 1.1
k.grime_amt = 0.25
NX, N0, N1 = 3.4, -6.35, 3.15           # nave half width, west / east wall lines
CX, C1 = 2.4, 6.25                      # chancel half width, east wall
WT, CWT = 5.0, 4.2                      # wall tops
PITCH = 52
F0 = 0.3


def st():
    c = k.stone()
    if random.random() < 0.05:
        c = mix(c, hexc("7d7a5a"), 0.3)
    return c


def dressed():
    return mix(random.choice(LIMESTONE), DRESSED, 0.45)


# ---------------------------------------------------------------- plinth + cores
k.box((2 * NX + 0.3, N1 - N0 + 0.3, F0), (0, (N0 + N1) / 2, F0 / 2), MA, hexc("8a806e"), bevel=0.04, var=0)
k.box((2 * CX + 0.3, C1 - N1 + 0.15, F0), (0, (N1 + C1) / 2 + 0.07, F0 / 2), MA, hexc("8a806e"), bevel=0.04, var=0)
k.core(-NX, NX, N0, N1, 0.0, WT, inset=0.22)
k.core(-CX, CX, N1 - 0.3, C1, 0.0, CWT, inset=0.22)

# ---------------------------------------------------------------- roofs
rn = k.gable_roof("slate", -NX, NX, N0, N1, WT, PITCH, over=0.4, verge=-0.02, along="y", barge=False,
                  tile_w=(0.36, 0.56), course=0.34)
rc = k.gable_roof("slate", -CX, CX, N1 - 0.4, C1, CWT, PITCH, over=0.35, verge=-0.02, along="y", barge=False,
                  tile_w=(0.34, 0.52), course=0.32)
# the chancel roof's west verge tucks under the nave gable; nave's east gable stands above it

# ---------------------------------------------------------------- walls
WIN_W, WIN_H, WIN_Z = 0.7, 1.9, 2.2
nave_wins = [-4.0, -0.9, 2.0]
LEN_N = N1 - N0
yc_n = (N0 + N1) / 2
for s in ("left", "right"):
    with k.side(s, NX, LEN_N / 2, cy=yc_n) as L:
        # side frame x runs along world +y on the right, -y on the left
        xs = [(y - yc_n) * (1 if s == "right" else -1) for y in nave_wins]
        holes = [k.lancet_hole(x, WIN_Z, WIN_W, WIN_H, pointed=0.0, ring=0.2) for x in xs]
        k.stone_face(L, WT, holes=holes, bw=0.75, bh=0.38, rows=13, color_fn=st)
        for x in xs:
            k.lancet(x, WIN_Z, WIN_W, WIN_H, pointed=0.0, ring=0.2, color_fn=dressed)
        bys = [N0 + 0.3, -2.45, 0.55, N1 - 0.3]
        for y in bys:
            bx = (y - yc_n) * (1 if s == "right" else -1)
            k.buttress(bx - 0.3, bx + 0.3, 0, [(2.2, 0.75), (WT - 0.6, 0.5)], color_fn=st)
        k.box((L + 0.3, 0.3, 0.2), (0, 0.05, WT - 0.1), MA, dressed(), var=0)       # eaves course

LEN_C = C1 - N1
yc_c = (N1 + C1) / 2
for s in ("left", "right"):
    with k.side(s, CX, LEN_C / 2, cy=yc_c) as L:
        holes = [k.lancet_hole(0, 1.9, 0.6, 1.6, pointed=0.0, ring=0.18)]
        k.stone_face(L, CWT, holes=holes, bw=0.7, bh=0.38, rows=11, color_fn=st)
        k.lancet(0, 1.9, 0.6, 1.6, pointed=0.0, ring=0.18, color_fn=dressed)
        k.box((L + 0.3, 0.3, 0.2), (0, 0.05, CWT - 0.1), MA, dressed(), var=0)

# east (chancel) end: triple window, gable, cross
with k.side("back", CX, LEN_C / 2, cy=yc_c) as L:
    gf = lambda x: rc["gable"](x) + 0.03
    holes = [k.lancet_hole(x, z, 0.5, h, pointed=0.0, ring=0.16) for x, z, h in ((-0.85, 1.9, 1.5), (0, 1.9, 2.0),
                                                                              (0.85, 1.9, 1.5))]
    k.stone_face(L, gf(0) + 0.05, holes=holes, bw=0.7, bh=0.38, rows=int((gf(0) + 0.05) / 0.38 + 0.5),
                 top_fn=gf, breaks=(0.0,), color_fn=st)
    k.prism([(-CX + 0.1, CWT - 0.2), (CX - 0.1, CWT - 0.2), (0, gf(0) - 0.1)], 0.3, (0, 0.22, 0), MA, MORTAR,
            var=0, grime=False)
    for x, z, h in ((-0.85, 1.9, 1.5), (0, 1.9, 2.0), (0.85, 1.9, 1.5)):
        k.lancet(x, z, 0.5, h, pointed=0.0, ring=0.16, color_fn=dressed, sill=False)
    k.box((2.5, 0.42, 0.13), (0, -0.02, 1.84), MA, dressed(), var=0)
    apex_c = gf(0)

# west front: door, rose window, gable
with k.side("front", NX, LEN_N / 2, cy=yc_n) as L:
    gf = lambda x: rn["gable"](x) + 0.03
    DW, DH = 1.5, 3.0
    RZ, RR = 6.2, 0.75
    holes = [arch_hole(0, DW, F0 - 0.05, F0 + DH - DW / 2, ring=0.3), k.rose_hole(0, RZ, RR)]
    k.stone_face(L, gf(0) + 0.05, holes=holes, bw=0.75, bh=0.38, rows=int((gf(0) + 0.05) / 0.38 + 0.5),
                 top_fn=gf, breaks=(0.0,), color_fn=st)
    k.prism([(-NX + 0.1, WT - 0.2), (NX - 0.1, WT - 0.2), (0, gf(0) - 0.1)], 0.3, (0, 0.22, 0), MA, MORTAR, var=0,
            grime=False)
    k.door(0, w=DW, h=DH, z0=F0, depth=0.18, arch=True, stone=True, step=True, color=hexc("6e4126"))
    k.arch_ring(0, F0 + DH - DW / 2, DW / 2 + 0.3, ring=0.18, depth=0.2, y=-0.02, n=11, color_fn=dressed)  # hood
    k.rose(0, RZ, RR, spokes=8, color=mix(LIMESTONE[0], DRESSED, 0.4))
    for sx in (-1, 1):
        k.wall_lantern(sx * 1.45, 2.9)
        k.buttress(sx * (NX - 0.35) - 0.3, sx * (NX - 0.35) + 0.3, 0, [(2.2, 0.75), (WT - 0.6, 0.5)], color_fn=st)
    apex_n = gf(0)
# east gable of the nave (above the chancel roof)
with k.side("back", NX, LEN_N / 2, cy=yc_n) as L:
    gf = lambda x: rn["gable"](x) + 0.03
    k.stone_face(L, gf(0) + 0.05, bw=0.75, bh=0.38, rows=int((gf(0) + 0.05) / 0.38 + 0.5), top_fn=gf,
                 breaks=(0.0,), color_fn=st)
    k.prism([(-NX + 0.1, WT - 0.2), (NX - 0.1, WT - 0.2), (0, gf(0) - 0.1)], 0.3, (0, 0.22, 0), MA, MORTAR, var=0,
            grime=False)

# ---------------------------------------------------------------- gable copings (skews) and kneelers
def coping(y, hd, wall_top_lift, apex, sgn):
    tanp = math.tan(math.radians(PITCH))
    base = apex - hd * tanp
    for sx in (-1, 1):
        a = (sx * (hd + 0.05), y, base + 0.12)
        b = (0.0, y, apex + 0.2)
        k.bar(a, b, 0.4, 0.56, MA, dressed(), up=(-sx * math.sin(math.radians(PITCH)), 0,
                                                   math.cos(math.radians(PITCH))), bevel=0.02)
        k.box((0.6, 0.58, 0.6), (sx * (hd - 0.1), y, base - 0.1), MA, dressed(), bevel=0.02, var=0)


coping(N0 + 0.16, NX, 0, apex_n, -1)
coping(N1 - 0.16, NX, 0, apex_n, 1)
coping(C1 - 0.16, CX, 0, apex_c, 1)
k.cross((0, C1 - 0.16, apex_c + 0.35), h=1.0, mat=MA, color=dressed(), w=0.14)

# ---------------------------------------------------------------- bell-cote on the west apex
BY = N0 + 0.2
BZ0 = apex_n - 0.45
for sx in (-1, 1):
    k.box((0.36, 0.5, 1.45), (sx * 0.52, BY, BZ0 + 0.72), MA, st(), var=0)
    k.box((0.36, 0.5, 0.02), (sx * 0.52, BY, BZ0 + 0.72), MA, MORTAR, var=0)
k.box((1.44, 0.56, 0.2), (0, BY, BZ0 + 0.05), MA, dressed(), var=0)
k.arch_ring(0, BZ0 + 1.2, 0.34, ring=0.18, depth=0.5, y=BY, n=5, color_fn=dressed)
k.box((1.4, 0.5, 0.35), (0, BY, BZ0 + 1.62), MA, st(), var=0)
k.prism([(-0.78, 0), (0.78, 0), (0, 0.55)], 0.62, (0, BY, BZ0 + 1.8), MA, dressed(), var=0)
bell = [(0.26, 0.0), (0.27, 0.02), (0.2, 0.12), (0.16, 0.3), (0.14, 0.4), (0.08, 0.45), (0.0, 0.46)]
k.lathe(bell, (0, BY, BZ0 + 0.62), MT, hexc("a47c44"), segs=12)
k.cyl(0.24, 0.01, (0, BY, BZ0 + 0.63), MT, hexc("2e2418"), segs=12, var=0, grime=False)
k.box((0.8, 0.1, 0.1), (0, BY, BZ0 + 1.15), W, k.timber(), var=0)
k.cross((0, BY, BZ0 + 2.33), h=0.6, mat=MT, color=hexc("3a3836"), w=0.06)

# ---------------------------------------------------------------- grass + a few graves
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(20):
    x = random.choice((-1, 1)) * random.uniform(NX + 0.3, NX + 0.9)
    y = random.uniform(N0, C1)
    for j in range(4):
        k.cyl(random.uniform(0.014, 0.024), random.uniform(0.15, 0.4),
              (x + random.uniform(-0.15, 0.15), y + random.uniform(-0.15, 0.15), 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
              smooth=None, caps=False)

k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=18, ao_dist=1.0)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((9.0, 14.0), 15000, cam_dir=(1.1, -1.35, 0.6), fit=0.9)
