"""Village bell tower: a square fieldstone tower with limestone quoins and
stepped corner buttresses, an arched oak door up three steps, a lancet window
and a round window, a string course, then an oak-framed belfry (boarded lower
half, open arched bays) with a bronze bell hanging from its headstock in a
timber bell frame, under a steep pyramid spire of silvered wooden shingles
with an iron cross.

Run: python3 make_bell_tower.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Tower body 5.2 x 5.2 m, corner buttresses to 6.9 x
6.9 m, steps 1.1 m out front (overall <= 7 x 7.4 m). Stone to 10.5 m,
belfry 10.5-13.3 m, spire apex ~16.9 m, cross tip ~17.9 m. Origin at ground
centre; the door faces Blender -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, LIMESTONE, arch_hole, rect_hole, GLASS_C, arch_top
from ra_kit import hexc, vary, mix

k = TK("BellTower", seed=1717, pal=palette(stone="field", roof="shingle_grey", timber="oak", door="natural"))
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 1.2
k.grime_amt = 0.26
HX = 2.6
ZS = 10.5          # top of the stone
ZB = 13.3          # top of the belfry frame
BRONZE = hexc("a47c44")


def st():
    c = k.stone()
    if random.random() < 0.06:
        c = mix(c, hexc("5d6b3e"), 0.3)
    return c


def lime():
    return vary(random.choice(LIMESTONE), 0.06, 0.02)


# ---------------------------------------------------------------- body
k.core(-HX, HX, -HX, HX, 0.0, ZS, inset=0.25)
DOOR_W, DOOR_H = 1.4, 2.9
F0 = 0.5
openings = {
    "front": [arch_hole(0, DOOR_W, F0 - 0.05, F0 + DOOR_H - DOOR_W / 2, ring=0.3),
              arch_hole(0, 0.55, 4.6, 5.9, ring=0.2, pointed=0.6), rect_hole(-0.48, 7.52, 0.48, 8.48)],
    "back": [arch_hole(0, 0.55, 4.6, 5.9, ring=0.2, pointed=0.6)],
    "left": [rect_hole(-0.35, 2.4, 0.35, 3.8), rect_hole(-0.35, 7.0, 0.35, 8.4)],
    "right": [rect_hole(-0.35, 2.4, 0.35, 3.8), rect_hole(-0.35, 7.0, 0.35, 8.4)],
}
for s, holes in openings.items():
    with k.side(s, HX, HX) as L:
        k.stone_face(L, ZS, holes=holes, bw=0.8, bh=0.42, rows=25, color_fn=st)
        if s in ("left", "right"):
            k.slit(0, 2.6, h=1.0)
            k.slit(0, 7.2, h=1.0)
        else:
            k.arch_ring(0, 5.9, 0.275, ring=0.22, depth=0.3, y=0.04, n=7, Rp=0.275 * 1.6, color_fn=lime)
            k.push((0, 0.12, 0))
            ft = arch_top(0, 0.275, 5.9, 0.44)
            f = [(-0.275, 4.6), (0.275, 4.6)] + [(0.275 - 0.55 * i / 10, ft(0.275 - 0.55 * i / 10)) for i in range(11)]
            k.prism(f, 0.03, (0, 0, 0), k.M("Glass"), vary(GLASS_C, 0.05), var=0, grime=False)
            k.pop()
            k.box((0.8, 0.3, 0.12), (0, -0.05, 4.54), MA, lime(), var=0)
            for sx in (-1, 1):
                for r in range(3):
                    k.box((0.26, 0.28, 0.42), (sx * 0.4, 0.02, 4.6 + 0.21 + r * 0.43), MA, lime(), var=0)
# quoins above the buttresses
k.quoins(-HX - 0.04, HX + 0.04, -HX - 0.04, HX + 0.04, 7.6, ZS, c=hexc("c2b8a2"))

# round window, front
with k.side("front", HX, HX):
    RZ = 8.0
    k.cyl(0.52, 0.03, (0, 0.14, RZ), k.M("Glass"), GLASS_C, rot=(math.pi / 2, 0, 0), segs=16, smooth=None)
    k.ring(0.5, 0.72, 0.3, (0, 0.02, RZ), MA, hexc("c2b8a2"), segs=16)
    for i in range(3):
        k.box((1.0, 0.05, 0.05), (0, 0.1, RZ), MT, IRON, rot=(0, i * math.pi / 3, 0), var=0)
    # door with steps
    k.door(0, w=DOOR_W, h=DOOR_H, z0=F0, depth=0.3, arch=True, stone=True, step=True, color=hexc("6e4126"),
           lantern=1)
    k.box((DOOR_W + 1.6, 0.9, F0), (0, -0.2, F0 / 2), MA, vary(hexc("8d877c"), 0.05), bevel=0.03, var=0)

# ---------------------------------------------------------------- corner buttresses
BW_, BZ1, BZ2 = 0.95, 4.2, 7.4
for cx in (-1, 1):
    for cy in (-1, 1):
        for (z0, z1, w) in ((0.0, BZ1, BW_), (BZ1 + 0.35, BZ2, BW_ - 0.25)):
            x0 = cx * (HX - 0.3)
            px, py = cx * (HX + w / 2 - 0.35), cy * (HX + w / 2 - 0.35)
            k.box((w - 0.1, w - 0.1, z1 - z0), (px, py, (z0 + z1) / 2), MA, MORTAR, var=0, grime=False)
            # two exposed faces
            for face, sgn in (("x", 1), ("x", -1), ("y", 1), ("y", -1)):
                if face == "x":
                    loc = (px + sgn * w / 2, py, z0)
                    rot = (0, 0, sgn * math.pi / 2)
                else:
                    loc = (px, py + sgn * w / 2, z0)
                    rot = (0, 0, 0 if sgn < 0 else math.pi)
                k.stone_face(w, z1 - z0, loc=loc, rot=rot, bw=0.5, bh=0.42, color_fn=st)   # inner sides show too
            # sloped set-off (weathering) on top
            k.push((px, py, z1), (0, 0, math.atan2(cy, cx) - math.pi / 4 + math.pi / 2 * 0))
            k.box((w + 0.04, w + 0.04, 0.12), (0, 0, 0.06), MA, lime(), var=0)
            k.pop()
            k.cyl(w * 0.72, 0.3, (px, py, z1 + 0.12), MA, lime(), segs=4, r2=0.12, rot=(0, 0, math.pi / 4),
                  smooth=None, var=0)

# string course and belfry floor
k.box((2 * HX + 0.3, 2 * HX + 0.3, 0.22), (0, 0, ZS + 0.05), MA, hexc("b8ae98"), bevel=0.04, var=0)

# ---------------------------------------------------------------- belfry (timber)
BH = 2.3
tc = k.timber()
Z0 = ZS + 0.16
posts = [-BH, -0.75, 0.75, BH]
k.box((2 * BH - 0.3, 2 * BH - 0.3, 0.05), (0, 0, Z0 + 0.02), W, mix(tc, (0, 0, 0), 0.25), var=0)
for s in ("front", "back", "left", "right"):
    with k.side(s, BH, BH) as L:
        k.box((L + 0.2, 0.24, 0.24), (0, 0.1, Z0 + 0.12), W, tc, bevel=0.02, var=0)          # sill
        k.box((L + 0.2, 0.24, 0.24), (0, 0.1, ZB - 0.12), W, tc, bevel=0.02, var=0)          # plate
        for x in posts:
            k.box((0.24, 0.22, ZB - Z0 - 0.4), (x, 0.1, (Z0 + ZB) / 2), W, k.timber(), var=0)
        # boarded lower half and rail
        k.plank_wall(L - 0.2, 0.9, (0, 0.12, Z0 + 0.22), W, lambda: k.plank_c(hexc("6f5a45")), plank=(0.18, 0.26),
                     holes=[], grime=False)
        k.box((L, 0.2, 0.14), (0, 0.08, Z0 + 1.18), W, tc, bevel=0.015, var=0)
        # arched braces in each open bay (segmented)
        for i in range(3):
            a, b = posts[i] + 0.12, posts[i + 1] - 0.12
            cx_, half = (a + b) / 2, (b - a) / 2
            zt = ZB - 0.24
            zs = zt - 0.75
            pts = [(cx_ - half + 2 * half * j / 6,
                    zs + 0.75 * math.sin(math.pi * j / 6) ** 0.6) for j in range(7)]
            for p, q in zip(pts[:-1], pts[1:]):
                k.bar((p[0], 0.1, p[1]), (q[0], 0.1, q[1]), 0.14, 0.12, W, tc, up=(0, 1, 0), bevel=0)
            # spandrel boards above the arch
            k.box((b - a, 0.05, 0.28), (cx_, 0.16, zt - 0.14), W, mix(tc, (0, 0, 0), 0.15), var=0)
        # louvre boards behind the side bays only (the middle bay stays open to show the bell)
        for i in (0, 2):
            a, b = posts[i] + 0.12, posts[i + 1] - 0.12
            for j in range(5):
                z = Z0 + 1.45 + j * 0.24
                k.box((b - a, 0.22, 0.04), ((a + b) / 2, 0.22, z), W, vary(hexc("5e4a38"), 0.06), rot=(0.6, 0, 0),
                      var=0)

# bell frame and bell
BZ = Z0 + 2.25          # headstock axis height
for sx in (-1, 1):
    for sy in (-1, 1):
        k.bar((sx * 0.95, sy * 0.55, Z0 + 0.05), (sx * 0.95, sy * 0.06, BZ - 0.1), 0.14, 0.14, W, tc, up=(0, 0, 1),
              bevel=0)
    k.box((0.2, 1.4, 0.16), (sx * 0.95, 0, Z0 + 0.12), W, tc, var=0)
    k.box((0.22, 0.24, 0.12), (sx * 0.95, 0, BZ - 0.12), MT, IRON, var=0)
k.box((2.1, 0.24, 0.26), (0, 0, BZ), W, mix(tc, (0, 0, 0), 0.15), bevel=0.02, var=0)        # headstock
for sx in (-1, 1):
    k.box((0.06, 0.26, 0.5), (sx * 0.16, 0, BZ - 0.25), MT, IRON, var=0)
bell = [(0.62, 0.0), (0.64, 0.05), (0.58, 0.12), (0.46, 0.35), (0.4, 0.62), (0.38, 0.85), (0.33, 1.0),
        (0.2, 1.06), (0.0, 1.08)]
k.lathe(bell, (0, 0, BZ - 1.5), MT, BRONZE, segs=16, smooth=50)
k.cyl(0.58, 0.02, (0, 0, BZ - 1.48), MT, hexc("2e2418"), segs=16, var=0, grime=False)   # dark mouth
k.cyl(0.07, 0.35, (0, 0, BZ - 1.72), MT, hexc("5a4630"), segs=8, r2=0.05)                # clapper
k.sphere(0.1, (0, 0, BZ - 1.75), MT, hexc("5a4630"), subdiv=1)
k.tube([(0.9, 0.12, BZ + 0.05), (0.9, 0.12, Z0 + 0.1)], [0.022, 0.022], k.M("Cloth"), hexc("c9a66b"), segs=5,
       point_end=False)

# ---------------------------------------------------------------- spire
apex = k.pyramid_roof(0, 0, BH + 0.1, ZB - 0.02, 3.6, k.M("Roof"), k.tile, over=0.45, tile_w=(0.22, 0.36),
                      course=0.26, th=0.022, droop=0.01)
k.cyl(0.14, 0.3, (0, 0, apex - 0.2), MT, IRON, segs=8, r2=0.06)
k.sphere(0.12, (0, 0, apex + 0.15), MT, hexc("b08a3a"), subdiv=1, grime=False)
k.cross((0, 0, apex + 0.2), h=0.85, w=0.06, color=hexc("3a3836"))

# ---------------------------------------------------------------- grass
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(16):
    s = random.choice((-1, 1))
    along = random.uniform(-3.3, 3.3)
    x, y = (along, s * 3.5) if random.random() < 0.5 else (s * 3.5, along)
    if y < -3 and abs(x) < 1.8:
        continue
    for j in range(4):
        k.cyl(random.uniform(0.014, 0.024), random.uniform(0.15, 0.4),
              (x + random.uniform(-0.15, 0.15), y + random.uniform(-0.1, 0.1), 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), random.uniform(0, 3)), grime=False,
              smooth=None, caps=False)

k.finish_checked((7.4, 7.6), 15000, cam_dir=(1.0, -1.5, 0.45), fit=0.95)
