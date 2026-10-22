"""Village barn: a big timber-framed barn with weathered vertical board siding
on a fieldstone plinth, a steep shingle roof, wide double doors standing open
(hay bales stacked inside, loose hay spilling out), a hay-loft door with a
hoist beam in one gable, and bales, a pitchfork, barrel and cart wheel out
front.

Run: python3 make_village_barn.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Walls 11.0 m (X) x 6.4 m (Y); overall footprint incl.
eaves, open door leaves and clutter <= 12.0 x 8.0 m. Ridge ~7.4 m. Origin at
ground centre; the double doors (opening x in [-1.6, 1.6], 3.3 m high) face
Blender -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON, MORTAR
from ra_kit import hexc, mix, vary

V = variant_arg()
PAL = {
    1: palette(plaster="grey", timber="grey", accent="natural", roof="shingle_brown", stone="field"),
    2: palette(plaster="grey", timber="dark", accent="oxblood", roof="shingle_grey", stone="grey"),
}[V]
k = VK("VillageBarn" + ("" if V == 1 else f"_{V}"), seed=707 + V * 3, pal=PAL)
W, MT, MA, TH = k.M("Wood"), k.M("Metal"), k.M("Matte"), k.M("Thatch")
BOARD = hexc("7d6450") if V == 1 else hexc("7a3b2c")      # weathered oak / barn red
HX, HY = 5.5, 3.2
PL = 0.5                 # plinth height
WT = 4.0
PITCH = 45
DW, DH = 3.2, 3.3        # door opening
BACK = hexc("2a221c")


def board():
    return k.plank_c(BOARD)


# ---------------------------------------------------------------- plinth + floor
for s in ("front", "back", "left", "right"):
    with k.side(s, HX, HY) as L:
        holes = [(-DW / 2, -0.1, DW / 2, PL + 0.1)] if s == "front" else []
        k.grid_wall(L, PL, (0, 0, 0), MA, lambda: mix(k.stone(), MORTAR, 0.12), bw=0.5, bh=0.25, gap=0.026,
                    holes=holes)
        k.box((L - 0.3, 0.3, PL), (0, 0.18, PL / 2), MA, MORTAR, var=0) if s != "front" else None
for sx in (-1, 1):
    k.box((HX - DW / 2 - 0.2, 0.3, PL), (sx * (DW / 2 + (HX - DW / 2) / 2), -HY + 0.18, PL / 2), MA, MORTAR, var=0)
k.box((2 * HX - 0.4, 2 * HY - 0.4, 0.06), (0, 0, 0.03), MA, hexc("5a4c3a"), var=0.03)       # earth floor
k.box((DW, 0.5, 0.12), (0, -HY + 0.1, 0.06), MA, vary(hexc("8d877c"), 0.05), bevel=0.02)      # threshold
k.stage("plinth")

# ---------------------------------------------------------------- board walls with exposed frame
H = WT - PL
for s in ("front", "back", "left", "right"):
    with k.side(s, HX, HY) as L:
        holes = [(-DW / 2, 0.0, DW / 2, DH - PL)] if s == "front" else []
        if s == "left":
            holes = [(-0.45, 1.3, 0.45, 2.1)]         # small window
        k.plank_wall(L, H, (0, 0, PL), W, board, holes=holes, plank=(0.22, 0.34))
        if s == "front":
            for sx in (-1, 1):
                seg = L / 2 - DW / 2
                k.box((seg - 0.1, 0.04, H), (sx * (DW / 2 + seg / 2), 0.07, PL + H / 2), MA, BACK, var=0)
            k.box((DW + 0.2, 0.04, WT - DH), (0, 0.07, DH + (WT - DH) / 2), MA, BACK, var=0)
        elif s == "left":
            k.box((L - 0.1, 0.04, H), (0, 0.07, PL + H / 2), MA, BACK, var=0)
        else:
            k.box((L - 0.1, 0.04, H), (0, 0.07, PL + H / 2), MA, BACK, var=0)
        # frame: sill, girt, top plate, posts and braces
        y = -0.07
        k.box((L + 0.2, 0.2, 0.22), (0, y, PL + 0.11), W, k.timber(), bevel=0.02) if s != "front" else None
        if s == "front":
            for sx in (-1, 1):
                seg = L / 2 - DW / 2
                k.box((seg + 0.1, 0.2, 0.22), (sx * (DW / 2 + seg / 2), y, PL + 0.11), W, k.timber(), bevel=0.02)
        k.box((L + 0.2, 0.2, 0.24), (0, y, WT - 0.12), W, k.timber(), bevel=0.02)
        n = 4 if s in ("front", "back") else 2
        xs = [-L / 2 + 0.1 + i * (L - 0.2) / n for i in range(n + 1)]
        if s == "front":
            xs = [-L / 2 + 0.1, -DW / 2 - 0.12, DW / 2 + 0.12, L / 2 - 0.1]
        for x in xs:
            k.box((0.22, 0.2, H), (x, y, PL + H / 2), W, k.timber(), bevel=0.02)
        gz = PL + H * 0.45
        for i in range(len(xs) - 1):
            a, b = xs[i] + 0.11, xs[i + 1] - 0.11
            if s == "front" and i == 1:
                k.box((b - a + 0.5, 0.22, 0.26), ((a + b) / 2, y - 0.01, DH + 0.13), W, k.timber(), bevel=0.02)
                continue
            k.box((b - a, 0.16, 0.16), ((a + b) / 2, y, gz), W, k.timber())
            k.strut(a, gz + 0.08, min(b, a + 1.6), WT - 0.24, w=0.15, y=y, d=0.15)
        if s == "left":
            k.window(0, PL + 1.3, 0.9, 0.8, depth=0.1, shutters=True, panes=(2, 1))
k.stage("walls")

# ---------------------------------------------------------------- open double doors
for sx in (-1, 1):
    ang = sx * (math.pi - 0.35)          # swung out, resting ~20 deg off the wall
    k.push((sx * DW / 2, -HY - 0.12, PL * 0.2), (0, 0, ang))
    lw = DW / 2 - 0.03
    d = -sx
    nb = 7
    for i in range(nb):
        cx = d * (lw * (i + 0.5) / nb)
        k.box((lw / nb - 0.012, 0.05, DH - 0.15), (cx, 0, (DH - 0.15) / 2), W, board(), var=0)
    for zz in (0.35, DH / 2, DH - 0.5):
        k.box((lw, 0.05, 0.16), (d * lw / 2, 0.05, zz), W, mix(BOARD, (0, 0, 0), 0.2), var=0.04)
    k.bar((d * 0.12, 0.05, 0.43), (d * (lw - 0.12), 0.05, DH / 2 - 0.08), 0.14, 0.05, W, mix(BOARD, (0, 0, 0), 0.2),
          up=(0, 1, 0), bevel=0)
    k.bar((d * 0.12, 0.05, DH / 2 + 0.08), (d * (lw - 0.12), 0.05, DH - 0.58), 0.14, 0.05, W, mix(BOARD, (0, 0, 0), 0.2),
          up=(0, 1, 0), bevel=0)
    for zz in (0.35, DH - 0.5):
        k.box((0.5, 0.02, 0.06), (d * 0.25, 0.085, zz), MT, IRON, var=0)
    k.pop()
k.stage("doors")

# ---------------------------------------------------------------- roof + gables with loft door
r = k.gable_roof("shingle", -HX, HX, -HY, HY, WT, PITCH, over=0.42, verge=0.34, tile_w=(0.36, 0.6), course=0.42)
for s in ("left", "right"):
    with k.side(s, HX, HY):
        k.gable_wall(HY, WT, r["gable"], style="boards", window=False, vent=(s == "left"))
        k.box((2 * HY, 0.2, 0.22), (0, -0.07, WT + 0.11), W, k.timber(), bevel=0.02)
with k.side("right", HX, HY):
    LZ = WT + 0.35
    k.box((1.2, 0.05, 1.3), (0, 0.04, LZ + 0.65), MA, hexc("1f1a16"), var=0)
    k.push((0.62, -0.08, LZ), (0, 0, 2.95))
    for i in range(5):
        k.box((0.22, 0.05, 1.25), (-0.12 - i * 0.24, 0, 0.64), W, board(), var=0)
    k.box((1.2, 0.05, 0.12), (-0.6, 0.05, 0.3), W, mix(BOARD, (0, 0, 0), 0.2))
    k.box((1.2, 0.05, 0.12), (-0.6, 0.05, 1.0), W, mix(BOARD, (0, 0, 0), 0.2))
    k.pop()
    for sx in (-1, 1):
        k.box((0.14, 0.14, 1.45), (sx * 0.68, -0.08, LZ + 0.65), W, k.timber())
    k.box((1.6, 0.16, 0.16), (0, -0.08, LZ - 0.06), W, k.timber())
    k.box((0.2, 0.6, 0.2), (0, -0.25, LZ + 1.7), W, k.timber(), bevel=0.02)       # hoist beam
    k.cyl(0.11, 0.06, (-0.03, -0.38, LZ + 1.52), W, hexc("5a3e26"), rot=(0, math.pi / 2, 0), segs=10, base=False)
    k.box((0.02, 0.02, 1.8), (0, -0.47, LZ + 0.6), W, hexc("c9b78e"), var=0)
k.stage("roof")

# ---------------------------------------------------------------- hay: stacked inside, spilling out, bales out front
for row in range(3):
    for col in range(4):
        if row == 2 and col in (0, 3):
            continue
        k.hay_bale(-4.6 + col * 1.05 + (0.5 if row % 2 else 0), HY - 0.9 - (col % 2) * 0.1, z=row * 0.43,
                   rz=random.uniform(-0.06, 0.06))
for row in range(2):
    for col in range(2):
        k.hay_bale(2.3 + col * 1.05, HY - 0.9, z=row * 0.43, rz=random.uniform(-0.06, 0.06))
for i in range(3):
    k.hay_bale(-1.6 + i * 0.1, 1.2 - i * 0.55, rz=1.57 + random.uniform(-0.1, 0.1))
for i in range(6):   # loose hay drifts
    a = random.uniform(-0.8, 0.8)
    k.sphere(random.uniform(0.35, 0.55), (a * 1.8, -HY + 0.9 - random.uniform(0, 1.4), 0.0), TH,
             vary(hexc("c2a45e"), 0.08), scale=(1.4, 1.0, 0.35), subdiv=2, noise_amt=0.08)
k.sphere(0.9, (0.5, 0.6, 0.0), TH, vary(hexc("c2a45e"), 0.06), scale=(1.4, 1.0, 0.6), subdiv=2, noise_amt=0.12)
# out front
k.hay_bale(-3.3, -HY - 0.5, rz=0.2)
k.hay_bale(-3.1, -HY - 0.52, z=0.42, rz=-0.15, s=(0.95, 0.48, 0.4))
k.hay_bale(-4.4, -HY - 0.45, rz=0.1)
k.bar((-2.55, -HY - 0.15, 0.0), (-2.4, -HY - 0.35, 1.7), 0.04, 0.04, W, hexc("8a6a48"), up=(0, 0, 1))   # pitchfork
for dx in (-0.06, 0.0, 0.06):
    k.bar((-2.4 + dx, -HY - 0.35, 1.7), (-2.4 + dx, -HY - 0.38, 1.95), 0.012, 0.012, MT, IRON, bevel=0)
k.box((0.18, 0.02, 0.02), (-2.4, -HY - 0.35, 1.7), MT, IRON, var=0)
k.barrel(3.4, -HY - 0.5, r=0.33, water=True)
k.bucket(2.85, -HY - 0.4)
k.wheel(4.4, -HY - 0.18, r=0.55, rz=0.0, lean=0.2)
k.sack(-1.95, 2.3, s=0.9)
k.stage("props")

k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=V * 11 + 7, ao_dist=0.8)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((12.0, 8.0), 12000, cam_dir=(0.9, -1.5, 0.55), fit=0.95)
