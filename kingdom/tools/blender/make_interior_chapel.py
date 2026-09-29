"""Chapel of the Dawn Throne interior (Region 1, L3): a bright nave of warm white ashlar and gold.

    blender -b --python make_interior_chapel.py -- [--no-preview]

Church palette (poster 02, Aurelis): warm white stone, gold trim and beams, deep-red runner,
the Dawn Throne sun emblem (twelve rays, a glowing core) above a stepped dais and altar,
white-and-gold sun banners, pews, a sun mosaic in the floor, two saint statues, candelabra.
-> kingdom/assets/generated/interiors/interior_chapel.glb
   kingdom/scenes/interiors/chapel_interior.tscn
   docs/kingdom/blender_previews/interior_chapel_a.png / _b.png
Nave 9 x 14 m, ceiling 7 m; double door in the front wall (Godot +Z) at x = 0. Altar dais at the back.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import interior_kit as IK
from interior_kit import *

# ---- Church palette: repaint the shared stone / flag lists in place (wall() and flagstones() read them)
WHITES = [hexc("efe6d2"), hexc("f4ecda"), hexc("e6dcc4"), hexc("f1e7cf"), hexc("eadfc6"), hexc("f6eedc")]
IK.FLAGS[:] = [hexc("ece2cb"), hexc("e3d8bd"), hexc("f1e8d3"), hexc("d9cdb2"), hexc("e8dcc2"), hexc("f0e6cf")]
GOLD = hexc("e0a93c")
GOLD_D = hexc("b98428")
GOLD_L = hexc("f3cf6c")
CRIMSON = hexc("a3322a")
CREAM = hexc("f2e8d0")

I = Interior("chapel", seed=9102, title="Chapel of the Dawn Throne")
k = I.k
I.SUN = k.material("Sun", rough=0.6, emission=hexc("ffc850"), strength=1.5)      # the Dawn Throne sun core
W, D, H = 9.0, 14.0, 7.0
hw, hd = W / 2, D / 2
I.env["ambient"] = (1.0, 0.95, 0.85)
I.env["ambient_energy"] = 1.25
I.env["exposure"] = 1.15
I.preview_ambient = 0.75


def marble(p):
    n = noise.noise(p * 0.8 + Vector((4.1, 2.2, 7.3)))
    c = mix(hexc("f2e9d6"), hexc("e4d8bd"), clamp(0.5 + 0.6 * n))
    zl = p.z - I.floor_z(p)
    return c


I.plaster_col = marble          # bright plaster everywhere (ceiling band, sills)


def stone_wall(wname, holes, seed=1.0):
    """White ashlar wall, full height, with windows/door holes. holes: (x0, x1, z0, z1) along the wall."""
    spec = {"back": ((-hw, hd), (hw, hd)), "right": ((hw, hd), (hw, -hd)), "front": ((hw, -hd), (-hw, -hd)),
            "left": ((-hw, -hd), (-hw, hd))}[wname]
    p0, p1 = Vector((*spec[0], 0)), Vector((*spec[1], 0))
    d = p1 - p0
    L = d.length
    ang = math.atan2(d.y, d.x)
    k.push((p0.x, p0.y, 0.0), (0, 0, ang))
    # mortar core in pieces around the openings (so windows and the door are real holes)
    xs = sorted({0.0, L} | {v for (a, b, z0, z1) in holes for v in (a, b)})
    for xa, xb in zip(xs, xs[1:]):
        mid = (xa + xb) / 2
        hs = [h for h in holes if h[0] <= mid <= h[1]]
        spans = [(0.0, H)] if not hs else [(0.0, min(h[2] for h in hs)), (max(h[3] for h in hs), H)]
        for (za, zb) in spans:
            if zb - za > 0.02:
                k.box((xb - xa, 0.1, zb - za), (mid, 0.06, (za + zb) / 2), I.PL, hexc("cfc5ad"), var=0)
    k.grid_wall(L, H, (L / 2, -0.005, 0), I.PL, lambda: vary(random.choice(WHITES), 0.05, 0.02),
                bw=0.95, bh=0.5, gap=0.035, push=0.035, holes=[(a - L / 2, z0, b - L / 2, z1) for (a, b, z0, z1) in holes])
    # gold string course + cornice
    k.box((L, 0.16, 0.16), (L / 2, -0.06, 1.05), I.PL, GOLD_D, bevel=0.02, var=0.02)
    k.box((L, 0.24, 0.3), (L / 2, -0.1, H - 0.15), I.PL, GOLD, bevel=0.03, var=0.02)
    k.box((L, 0.34, 0.1), (L / 2, -0.14, H - 0.35), I.PL, hexc("f4ebd6"), bevel=0.02, var=0.02)
    k.pop()
    return L


# --------------------------------------------------------------- shell
I.mark("shell")
I.W, I.D, I.H, I.cx, I.cy, I.z0 = W, D, H, 0.0, 0.0, 0.0
WIN = [(-4.9, 1.2, 2.3, 5.6), (-1.6, 1.2, 2.3, 5.6), (1.7, 1.2, 2.3, 5.6), (4.8, 1.2, 2.3, 5.6)]   # centre y, w, z0, z1
side_holes_l = [((y + hd) - w / 2, (y + hd) + w / 2, z0, z1) for (y, w, z0, z1) in WIN]
side_holes_r = [((hd - y) - w / 2, (hd - y) + w / 2, z0, z1) for (y, w, z0, z1) in WIN]
front_holes = [((hw - 0) - 1.05, (hw - 0) + 1.05, 0.0, 3.4)]      # door: x measured from the front wall start (x = +hw)
back_holes = [(hw - 0.9, hw + 0.9, 3.4, 5.9)]                     # (unused, sun emblem sits on solid stone)
stone_wall("left", side_holes_l, 1.0)
stone_wall("right", side_holes_r, 2.0)
stone_wall("front", front_holes, 3.0)
stone_wall("back", [], 4.0)
for (wn, sz, c) in (("left", (0.3, D + 0.3, H), (-hw + 0.13, 0, H / 2)), ("right", (0.3, D + 0.3, H), (hw - 0.13, 0, H / 2)),
                    ("front", (W + 0.3, 0.3, H), (0, -hd + 0.13, H / 2)), ("back", (W + 0.3, 0.3, H), (0, hd - 0.13, H / 2))):
    I.collide(c, sz)

# windows: wall_frame based helper places glass + gold sill; tall arched-look with gold mullions
for (y, w, z0, z1) in WIN:
    for wn in ("left", "right"):
        I.window(wn, y, w, z0, z1, day=0.9, sill_deco=False)

# floor: cream flagstones + carved aisle + sun mosaic
I.flagstones(-hw, hw, -hd, hd, size=0.85)
# runner: crimson carpet with gold borders and a row of gold diamonds (plain boxes: z-fight free)
RY0, RY1 = -hd + 1.7, 1.1
k.box((1.8, RY1 - RY0, 0.02), (0, (RY0 + RY1) / 2, 0.022), I.PL, CRIMSON, var=0.03, grime=False)
for sx in (-1, 1):
    k.box((0.1, RY1 - RY0, 0.024), (sx * 0.8, (RY0 + RY1) / 2, 0.024), I.PL, GOLD, var=0.02, grime=False)
    k.box((0.04, RY1 - RY0, 0.026), (sx * 0.66, (RY0 + RY1) / 2, 0.025), I.PL, GOLD_L, var=0.02, grime=False)
yy = RY0 + 0.7
while yy < RY1 - 0.4:
    k.box((0.5, 0.5, 0.026), (0, yy, 0.026), I.PL, GOLD, rot=(0, 0, math.pi / 4), var=0.02, grime=False)
    k.box((0.22, 0.22, 0.028), (0, yy, 0.027), I.PL, hexc("c14a36"), rot=(0, 0, math.pi / 4), var=0.02, grime=False)
    yy += 1.25
# sun mosaic in front of the dais
I.rug(0, 2.6, 1.25, 1.25, [GOLD_D, CREAM, GOLD, CREAM, GOLD_L, GOLD])

# entrance double doors (front wall)
I.door("front", -0.5, 1.0, 3.3)
I.door("front", 0.5, 1.0, 3.3)
# gold arch over the door inside
m = I.wall_frame("front")
xc = m(0.0)
for sx in (-1, 1):
    k.box((0.3, 0.3, 3.6), (xc + sx * 1.22, -0.1, 1.8), I.PL, GOLD_D, bevel=0.02, var=0.02)
k.box((2.9, 0.3, 0.32), (xc, -0.1, 3.7), I.PL, GOLD, bevel=0.03, var=0.02)
k.pop()

# ceiling: cream coffers between gold beams
I.mark("ceiling")
k.box((W, D, 0.3), (0, 0, H + 0.15), I.PL, hexc("f0e6cf"), var=0.02)
for yy in (-5.6, -2.8, 0.0, 2.8, 5.6):
    k.box((W, 0.4, 0.32), (0, yy, H - 0.16), I.PL, GOLD_D, bevel=0.03, var=0.02)
    k.box((W, 0.2, 0.08), (0, yy, H - 0.34), I.PL, GOLD, bevel=0.01, var=0.02)
for xx in (-3.0, 0.0, 3.0):
    k.box((0.34, D, 0.26), (xx, 0, H - 0.13), I.PL, GOLD_D, bevel=0.03, var=0.02)
I.collide((0, 0, H + 0.25), (W, D, 0.4))
I.collide((0, 0, -0.25), (W, D, 0.5))

# pilasters between windows with gold capitals and bases
I.mark("pilasters")
for wn, sgn in (("left", -1), ("right", 1)):
    for y in (-7.0 + 0.5, -3.25, 0.05, 3.25, 6.5):
        x = sgn * (hw - 0.22)
        k.box((0.36, 0.5, H - 0.4), (x, y, (H - 0.4) / 2), I.PL, hexc("f3ebd8"), bevel=0.03, var=0.02)
        k.box((0.46, 0.62, 0.3), (x, y, 0.15), I.PL, GOLD_D, bevel=0.03, var=0.02)
        k.box((0.46, 0.62, 0.3), (x, y, H - 0.55), I.PL, GOLD, bevel=0.03, var=0.02)
        I.collide((x, y, 1.0), (0.4, 0.55, 2.0))

# --------------------------------------------------------------- altar dais
I.mark("altar")
DY0 = 4.1                      # dais front edge
k.box((6.6, 0.9, 0.12), (0, DY0 + 0.45, 0.06), I.PL, hexc("e9decb"), bevel=0.02, var=0.02)       # step 1
k.box((6.0, 0.9, 0.24), (0, DY0 + 1.35, 0.12), I.PL, hexc("efe5d0"), bevel=0.02, var=0.02)      # step 2
k.box((5.4, 1.65, 0.36), (0, hd - 0.98, 0.18), I.PL, hexc("f3ebd7"), bevel=0.02, var=0.02)      # platform (to wall)
k.box((6.7, 0.06, 0.05), (0, DY0 + 0.02, 0.13), I.PL, GOLD, var=0.02)
I.collide((0, DY0 + 1.7, 0.1), (6.6, 3.4, 0.2))
I.collide((0, DY0 + 0.45, 0.06), (6.6, 0.9, 0.12))
# ramp collider up the steps (so the player can walk onto the dais)
I.collide((0, DY0 + 1.35, 0.18), (6.0, 1.3, 0.1), rx=math.radians(12))
I.collide((0, hd - 0.98, 0.18), (5.4, 1.65, 0.36))
AZ = 0.36
# altar block with white-and-gold cloth
ay = hd - 2.3
k.box((2.6, 1.0, 0.98), (0, ay, AZ + 0.49), I.PL, hexc("f1e8d3"), bevel=0.03, var=0.02)
k.box((2.9, 1.2, 0.09), (0, ay, AZ + 1.02), I.PL, hexc("f6eedc"), bevel=0.02, var=0.01)
k.box((2.95, 1.25, 0.05), (0, ay, AZ + 0.95), I.PL, GOLD, bevel=0.01, var=0.01)
k.box((1.4, 0.04, 0.6), (0, ay - 0.54, AZ + 0.55), I.PL, GOLD, var=0.02)            # frontal panel with sun disc
k.cyl(0.22, 0.04, (0, ay - 0.57, AZ + 0.55), I.SUN, hexc("ffd27a"), rot=(math.pi / 2, 0, 0), segs=16, grime=False)
I.collide((0, ay, AZ + 0.5), (2.9, 1.25, 1.0))
I.mega("Chalice", (0.0, ay, AZ + 1.07), s=1.4, wood=False)
I.mega("CandleStick_Triple", (-0.95, ay + 0.05, AZ + 1.07), s=1.5, wood=False)
I.mega("CandleStick_Triple", (0.95, ay + 0.05, AZ + 1.07), s=1.5, wood=False)
I.mega("Book_7", (0.55, ay - 0.12, AZ + 1.07), rz=0.2, s=1.3)
I.light((-0.95, ay, AZ + 1.6), CANDLE, 0.7, 4.0)
I.light((0.95, ay, AZ + 1.6), CANDLE, 0.7, 4.0)

# the Dawn Throne sun (back wall): glowing core, gold halo ring, twelve rays
mb = I.wall_frame("back")
xs = mb(0.0)
SZ = 4.6
R_out, R_in = 1.75, 1.12
pts = []
for i in range(24):
    an = i / 24 * math.tau + math.pi / 2
    rr = R_out if i % 2 == 0 else R_in
    pts.append((math.cos(an) * rr, math.sin(an) * rr))
k.prism(pts, 0.07, (xs, -0.1, SZ), I.PL, GOLD, var=0.02)
k.ring(1.0, 1.16, 0.06, (xs, -0.13, SZ), I.PL, GOLD_L, segs=32)
k.cyl(0.95, 0.06, (xs, -0.14, SZ), I.SUN, hexc("ffe9a0"), rot=(math.pi / 2, 0, 0), segs=28, grime=False)
k.pop()
I.light((0, hd - 0.8, SZ), (1.0, 0.82, 0.45), 1.6, 7.0)
# tall banners flanking the sun
I.banner("back", -3.2, 5.7, w=1.0, h=3.3, cloth=hexc("f4ecd8"), trim=GOLD, emblem="star", emblem_c=GOLD)
I.banner("back", 3.2, 5.7, w=1.0, h=3.3, cloth=hexc("f4ecd8"), trim=GOLD, emblem="star", emblem_c=GOLD)
# side-wall banners between pilasters
for wn in ("left", "right"):
    for yy in (-5.1, -1.6, 1.6, 5.0):
        pass

# saint statues on plinths either side of the altar
def statue(x, y, rot):
    k.box((0.7, 0.7, 0.55), (x, y, AZ + 0.275), I.PL, hexc("e8ddc6"), bevel=0.03, var=0.02)
    I.lathe([(0, 0), (0.30, 0), (0.30, 0.1), (0.25, 0.5), (0.2, 1.0), (0.17, 1.35), (0.13, 1.5), (0.12, 1.55), (0, 1.56)],
            (x, y, AZ + 0.55), I.PL, hexc("f6efdd"), segs=14)                     # robe
    k.sphere(0.13, (x, y, AZ + 0.55 + 1.74), I.PL, hexc("f3e6cc"), subdiv=2, grime=False)
    k.ring(0.16, 0.2, 0.03, (x, y, AZ + 0.55 + 1.98), I.PL, GOLD, rot=(math.pi / 2 * 0.0, 0, 0), segs=14)   # gold halo
    k.beam((x - 0.2, y - 0.12, AZ + 0.55 + 1.2), (x + 0.1, y - 0.3, AZ + 0.55 + 1.35), 0.05, I.PL, hexc("f0e5cf"), bevel=0)
    I.collide((x, y, AZ + 1.0), (0.7, 0.7, 2.0))
statue(-2.35, hd - 0.9, 0)
statue(2.35, hd - 0.9, 0)

# candelabra stands flanking the dais steps
for (x, y) in ((-2.6, DY0 + 0.3), (2.6, DY0 + 0.3)):
    I.lathe([(0, 0), (0.16, 0), (0.17, 0.05), (0.06, 0.15), (0.04, 1.3), (0.09, 1.38), (0.0, 1.4)], (x, y, 0.12), I.PL, GOLD, segs=10)
    for i in range(5):
        an = i / 5 * math.tau
        I.candle(x + math.cos(an) * 0.13, y + math.sin(an) * 0.13, 1.5 + (0.05 if i % 2 else 0.0), h=0.12, holder=False,
                 energy=0)
    I.light((x, y, 1.75), CANDLE, 0.6, 3.6)
    I.collide((x, y, 0.8), (0.4, 0.4, 1.6))

# --------------------------------------------------------------- pews
I.mark("pews")
def pew(cx, cy, L=2.9):
    wood = hexc("c48f52")
    k.box((L, 0.46, 0.07), (cx, cy, 0.46), I.WOOD, vary(wood, 0.05), bevel=0.012)
    k.box((L, 0.06, 0.52), (cx, cy + 0.24, 0.8), I.WOOD, vary(hexc("b98149"), 0.05), bevel=0.012)
    k.box((L, 0.05, 0.08), (cx, cy + 0.24, 1.09), I.WOOD, hexc("d4a75c"), bevel=0.012)
    for sx in (-1, 1):
        k.box((0.08, 0.56, 1.1), (cx + sx * (L / 2 - 0.04), cy + 0.03, 0.55), I.WOOD, vary(hexc("a8733d"), 0.05), bevel=0.012)
        k.sphere(0.05, (cx + sx * (L / 2 - 0.04), cy + 0.03, 1.13), I.PL, GOLD, subdiv=1, grime=False)
    k.box((L - 0.1, 0.24, 0.03), (cx, cy - 0.32, 0.16), I.WOOD, hexc("8a5d33"), bevel=0.006)   # kneeler
    I.collide((cx, cy, 0.5), (L, 0.6, 1.0))
for row in range(6):
    y = -4.9 + row * 1.25
    pew(-2.45, y)
    pew(2.45, y)

# font (holy-water basin) by the door and a lectern
I.lathe([(0, 0), (0.28, 0), (0.3, 0.06), (0.14, 0.15), (0.12, 0.85), (0.26, 0.95), (0.42, 1.08), (0.36, 1.12), (0, 1.1)],
        (-3.2, -hd + 1.0, 0), I.PL, hexc("efe5d0"), segs=16)
I.collide((-3.2, -hd + 1.0, 0.55), (0.9, 0.9, 1.1))
I.mega("BookStand", (2.2, DY0 + 0.15, 0.12), rz=math.pi, s=1.3)
I.chest(3.5, -hd + 0.6, 0.0, w=1.0, d=0.5, c=hexc("c9982f"))

# --------------------------------------------------------------- lighting
I.mark("lights")
for y in (-3.6, 0.2):
    I.chandelier(0.0, y, H, r=0.75, n=8, drop=1.7, energy=1.4, radius=8.0)
for (wn, c) in (("left", -6.4), ("right", -6.4), ("left", 6.5), ("right", 6.5)):
    I.lantern(wn, c, z=2.4, energy=0.6)

I.mark("end")
I.rt_lights.append(("AltarLight", (0.0, hd - 1.6, 3.2), (1.0, 0.8, 0.45), 1.7, 8.0, True))
I.rt_lights.append(("NaveLight", (0.0, -2.2, 3.4), (1.0, 0.9, 0.72), 0.9, 9.0, False))
I.spawn = ((0.0, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((0.0, -hd + 0.45, 0.0), (2.4, 1.0, 3.3), 0.0)
I.npc("NPC_Priest", (0.0, hd - 3.6, AZ), (0, -1), look="Monk", height=1.75, anim="Idle", role="priest")
I.npc("NPC_Pilgrim", (-2.45, -1.2 + 0.0, 0.0), (0, 1), look="Elder_Woman", height=1.6, anim="Idle", role="pilgrim")
I.cam("a", (0.0, -hd + 0.8, 2.3), (0.0, 4.5, 2.4), lens=16)
I.cam("b", (3.6, -1.5, 3.4), (-1.5, 4.6, 1.6), lens=18)
I.finish()
