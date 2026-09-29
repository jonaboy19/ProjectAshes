"""Inn interior: the ground-floor tavern hall (bar counter with kegs and a back bar of
bottles, big stone fireplace, long tables with benches, red-and-gold banners,
wagon-wheel chandeliers, barrels and sacks) and a staircase up through the
ceiling to one guest bedroom (curtained window, carved double bed with a red
quilt, nightstand, chest, wardrobe shelves, wash stand, rug).

    blender -b --python make_interior_inn.py -- [--no-preview]

-> kingdom/assets/generated/interiors/interior_inn.glb
   kingdom/scenes/interiors/inn_interior.tscn
   docs/kingdom/blender_previews/interior_inn_a.png / _b.png (hall) / _c.png (bedroom)
Hall 12 x 10 m, ceiling 3.6 m; entrance door in the front wall (Godot +Z) at x = -1.2.
Stairs along the back wall from x = 0.6 (floor) up to x = 5.4 (bedroom floor, z = 3.68).
Bedroom above the hall's right half: x in [-1, 6], y in [0, 5] (Godot z in [-5, 0]).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("inn", seed=8505, title="Inn")
k = I.k
W, D, H = 12.0, 10.0, 3.6
hw, hd = W / 2, D / 2
DOOR_X = -1.2
FX = -2.8                          # fireplace centre on the back wall
UP = H + 0.08                      # bedroom floor level
SX0, SX1, SY0, SY1 = 0.6, 5.4, 3.78, 4.95     # stairs: foot x, top x, y span
HOLE = (2.7, SX1, SY0, 5.0)        # stairwell opening (x0, x1, y0, y1)
BX0, BX1, BY0, BY1 = -1.0, 6.0, 0.0, 5.0      # bedroom footprint
RED = hexc("9a2a22")
GOLD = hexc("d9aa45")


def soot(p):
    dx = abs(p.x - FX)
    if p.y > 3.3 and dx < 2.0 and p.z < H + 0.05:
        return (1 - dx / 2.0) * clamp((p.z - 1.0) / 1.8) * 0.8
    if H - 0.6 < p.z < H + 0.05:
        return 0.28 * clamp((p.z - (H - 0.6)) / 0.6)
    return 0.0


I.soot = soot
I.env["ambient_energy"] = 0.95

# ============================================================================ hall
I.mark("hall shell")
I.room(W, D, H, doors={"front": [(DOOR_X, 1.4, 0, 2.4)]},
       windows={"front": [(-4.2, 1.2, 1.1, 2.2), (2.2, 1.2, 1.1, 2.2)], "left": [(-2.2, 1.1, 1.1, 2.2), (1.4, 1.1, 1.1, 2.2)]},
       posts=1.4)
I.planks(-hw, hw, -hd, hd, along="y",
         dark=lambda x, y: 0.3 if (abs(x - FX) < 1.4 and y > 3.6) else (0.15 if x > 3.3 else 0.0))
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.4, 0.8), joist_step=0.85, holes=[HOLE], collide=False)
I.collide((-3.5, 0, H + 0.25), (5.0, D, 0.4))                     # hall ceiling outside the bedroom
I.collide((2.5, -2.5, H + 0.25), (7.0, 5.0, 0.4))
I.door("front", DOOR_X, 1.4, 2.4)
I.window("front", -4.2, 1.2, 1.1, 2.2, day=0.7)
I.window("front", 2.2, 1.2, 1.1, 2.2, day=0.7)
I.window("left", -2.2, 1.1, 1.1, 2.2, day=0.7)
I.window("left", 1.4, 1.1, 1.1, 2.2, day=0.7)

I.mark("fireplace")
FIRE = I.fireplace("back", FX, width=2.4, energy=2.6, radius=8.0)
I.rug(FX, 2.9, 1.2, 0.75, [hexc("8a2a22"), GOLD, hexc("5a2a22"), hexc("c9b695"), hexc("8a2a22"), hexc("3a2c24")])
I.mega("Chair_1", (FX - 1.1, 2.6, 0), rz=-2.5)
I.mega("Chair_1", (FX + 1.2, 2.5, 0), rz=2.4)
I.mug(FX - 0.8, 4.2, 1.42)
I.mug(FX - 0.6, 4.25, 1.42)
I.candle(FX + 0.8, 4.2, 1.42, h=0.14, energy=0.0)
I.mega("Shield_Wooden", (FX, hd - 0.1, 2.05), rot=(0, 0, 0), s=1.0)

I.mark("stairs")
N = 18
rise = UP / N
run = (SX1 - SX0) / N
for i in range(N):
    x = SX0 + i * run
    z = (i + 1) * rise
    k.box((run + 0.03, SY1 - SY0, 0.05), (x + run / 2, (SY0 + SY1) / 2, z - 0.025), I.WOOD, vary(OAK, 0.08), bevel=0.008)
    k.box((0.03, SY1 - SY0 - 0.04, rise), (x + 0.015, (SY0 + SY1) / 2, z - rise / 2), I.WOOD, vary(OAK_D, 0.06), var=0)
# closed side under the stairs (hall side), with a stringer and posts
t = bmesh.new()
vs = [t.verts.new(v) for v in ((SX0, SY0, 0), (SX1, SY0, 0), (SX1, SY0, UP - 0.05), (SX0 + run, SY0, rise - 0.05))]
t.faces.new(vs)
bmesh.ops.subdivide_edges(t, edges=t.edges[:], cuts=4, use_grid_fill=True)
bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
for f in t.faces:
    if f.normal.y > 0:
        f.normal_flip()
k._merge(t, I.WOOD, hexc("6a452b"), None, None, 0.03, None, True)
k.beam((SX0, SY0 - 0.04, 0.1), (SX1, SY0 - 0.04, UP + 0.02), 0.08, I.WOOD, TIMBER_D, bevel=0.012, width=0.26)
for i in range(1, 6):
    x = SX0 + (SX1 - SX0) * i / 6
    zt = (x - SX0) / (SX1 - SX0) * UP
    k.box((0.1, 0.08, zt), (x, SY0 - 0.06, zt / 2), I.WOOD, TIMBER, bevel=0.01)
# handrail with balusters
for i in range(0, 13):
    x = SX0 + 0.1 + (SX1 - SX0 - 0.2) * i / 12
    zt = (x - SX0) / (SX1 - SX0) * UP
    k.box((0.04, 0.04, 0.9), (x, SY0 + 0.05, zt + 0.45), I.WOOD, OAK_D, var=0.04)
k.beam((SX0 + 0.05, SY0 + 0.05, 0.95), (SX1, SY0 + 0.05, UP + 0.92), 0.07, I.WOOD, OAK_D, bevel=0.012)
k.box((0.12, 0.12, 1.1), (SX0 + 0.05, SY0 + 0.05, 0.55), I.WOOD, TIMBER_D, bevel=0.015)
k.sphere(0.07, (SX0 + 0.05, SY0 + 0.05, 1.14), I.WOOD, TIMBER_D, subdiv=1)
ang = math.atan2(UP, SX1 - SX0)
L = math.hypot(UP, SX1 - SX0)
I.collide(((SX0 + SX1) / 2 + 0.1 * math.sin(ang), (SY0 + SY1) / 2, UP / 2 - 0.1 * math.cos(ang)), (L + 0.2, SY1 - SY0, 0.2),
          ry=-ang)
for i in range(6):                  # solid below the ramp
    xa = SX0 + (SX1 - SX0) * i / 6
    xb = SX0 + (SX1 - SX0) * (i + 1) / 6
    zt = (xa - SX0) / (SX1 - SX0) * UP - 0.12
    if zt > 0.1:
        I.collide(((xa + xb) / 2, (SY0 + SY1) / 2, zt / 2), (xb - xa, SY1 - SY0, zt))
I.collide((SX0 + 1.2, SY0 - 0.05, 0.6), (0.1, 0.1, 1.2))
I.prop("barrel", (5.7, 3.25, 0), rz=0.4, s=0.9, collide=True)

I.mark("bar")
BXC = 3.3                          # bar front line (x); counter from y -2.4 to 1.8
BA, BB = -2.4, 1.8
k.box((0.7, BB - BA, 1.0), (BXC + 0.35, (BA + BB) / 2, 0.5), I.WOOD, hexc("5a3a24"), var=0)
n = 7
for i in range(n):
    y = BA + (i + 0.5) * (BB - BA) / n
    k.box((0.03, (BB - BA) / n - 0.1, 0.66), (BXC - 0.01, y, 0.5), I.WOOD, hexc("7a5234"), bevel=0.01)
    k.box((0.05, 0.07, 1.0), (BXC - 0.02, y - (BB - BA) / (2 * n), 0.5), I.WOOD, hexc("4a2e1c"), var=0.03)
k.box((0.95, BB - BA + 0.25, 0.07), (BXC + 0.33, (BA + BB) / 2, 1.035), I.WOOD, hexc("8a5a34"), bevel=0.02)
k.box((0.07, BB - BA, 0.07), (BXC - 0.1, (BA + BB) / 2, 0.18), I.PL, hexc("8a7a5a"), var=0)     # foot rail
I.collide((BXC + 0.35, (BA + BB) / 2, 0.55), (0.9, BB - BA, 1.1))
# a return to the wall at the front end
k.box((6.0 - BXC, 0.7, 1.0), ((BXC + 6.0) / 2, BA - 0.35, 0.5), I.WOOD, hexc("5a3a24"), var=0)
k.box((6.0 - BXC + 0.1, 0.95, 0.07), ((BXC + 6.0) / 2, BA - 0.33, 1.035), I.WOOD, hexc("8a5a34"), bevel=0.02)
for i in range(3):
    x = BXC + (i + 0.5) * (6.0 - BXC) / 3
    k.box(((6.0 - BXC) / 3 - 0.1, 0.03, 0.66), (x, BA - 0.71, 0.5), I.WOOD, hexc("7a5234"), bevel=0.01)
I.collide(((BXC + 6.0) / 2, BA - 0.35, 0.55), (6.0 - BXC, 0.75, 1.1))
TZ = 1.07
for (y, s_) in ((-1.9, 1.0), (-1.2, 1.0), (0.4, 1.0), (1.3, 1.0)):
    I.mug(BXC + 0.25 + j(0.05), y + j(0.1), TZ, s=1.1)
I.plate(BXC + 0.35, -0.3, TZ)
I.candle(BXC + 0.3, 0.9, TZ, h=0.14, energy=0.45)
I.candle(BXC + 0.25, -2.1, TZ, h=0.1, energy=0.35)
# kegs on a rack on the counter end
for kx in (4.75, 5.45):
    I.prop("barrel", (kx, BA - 0.1, TZ + 0.24), rot=(math.pi / 2, 0, 0), s=0.55)
    k.cyl(0.02, 0.1, (kx, BA - 0.6, TZ + 0.2), I.WOOD, OAK_D, rot=(math.pi / 2, 0, 0), segs=6)
    for sx_ in (-0.15, 0.15):
        k.box((0.05, 0.4, 0.1), (kx + sx_, BA - 0.35, TZ + 0.05), I.WOOD, TIMBER_D, bevel=0.008)
I.mega("Mug", (4.5, BA - 0.2, TZ), rz=0.3, s=1.1)
# back bar: shelves of bottles on the right wall, barrels on their sides below
I.shelf_unit("right", -0.6, w=1.8, h=2.4, depth=0.34, levels=(0.35, 1.2, 1.65, 2.1),
             items=[None, "bottles", "bottles", "pots"])
I.shelf_unit("right", 1.3, w=1.6, h=2.4, depth=0.34, levels=(0.35, 1.2, 1.65, 2.1), items=[None, "mixed", "bottles", "mixed"])
for y in (-1.15, -0.1, 1.0, 1.75):
    I.prop("barrel", (hw - 0.45, y, 0.36), rot=(math.pi / 2, 0, 0), s=0.72)
I.banner("right", -1.6, 3.1, w=0.7, h=1.2, cloth=RED, trim=GOLD, emblem="cross")

I.mark("tables")
for (tx, ty) in ((-3.3, -1.4), (0.2, -1.2), (-3.3, 1.4)):
    I.mega("Table_Large", (tx, ty, 0), rz=0.0, s=0.8, collide=True)
    I.mega("Bench", (tx, ty - 0.75, 0), rz=0.0, s=0.75)
    I.mega("Bench", (tx, ty + 0.75, 0), rz=0.0, s=0.75)
    for i in range(random.randint(2, 4)):
        I.mug(tx + random.uniform(-0.9, 0.9), ty + j(0.25), 0.65)
    I.plate(tx + random.uniform(-0.6, 0.6), ty + j(0.15), 0.65)
    I.candle(tx + j(0.3), ty, 0.65, h=0.14, energy=0.45)
I.table(0.4, 1.6, L=1.1, W=1.0)
for (sx_, sy_) in ((-0.75, 0.0), (0.75, 0.0), (0.0, 0.8), (0.0, -0.8)):
    I.stool(0.4 + sx_, 1.6 + sy_)
I.mug(0.3, 1.5, 0.76)
I.candle(0.55, 1.75, 0.76, h=0.12, energy=0.35)

I.mark("walls deco")
I.banner("left", -0.4, 3.1, w=0.7, h=1.25, cloth=RED, trim=GOLD, emblem="cross")
I.banner("front", -2.7, 3.1, w=0.7, h=1.25, cloth=RED, trim=GOLD, emblem="cross")
I.lantern("left", 3.4, z=1.9, energy=0.6)
I.lantern("left", -4.0, z=1.9, energy=0.6)
I.lantern("front", 0.6, z=1.9, energy=0.5)
I.lantern("back", -0.3, z=1.9, energy=0.5)
I.shelf("left", -3.9, 2.35, L=1.2, items="pots")
I.prop("sack_pile", (-hw + 1.2, -hd + 0.6, 0), rz=0.0, s=0.7, collide=True)
I.prop("barrel", (-hw + 0.45, -hd + 1.6, 0), rz=0.9, collide=True)
I.prop("crate", (-hw + 0.45, -hd + 2.3, 0), rz=0.2, s=0.85, collide=True)
I.prop("barrel", (0.6 + 0.9, -hd + 0.45, 0), rz=0.2, s=0.95, collide=True)
I.chandelier(-3.3, 0.0, H, r=0.55, n=6, drop=1.0)
I.chandelier(0.3, -0.4, H, r=0.55, n=6, drop=1.0)

# ============================================================================ bedroom
I.mark("bedroom shell")
BH = 2.7
I.room(BX1 - BX0, BY1 - BY0, BH, windows={"right": [(2.3, 1.0, 0.9, 2.0)], "front": [(1.0, 0.9, 0.9, 1.9)]},
       z0=UP, cx=(BX0 + BX1) / 2, cy=(BY0 + BY1) / 2, posts=1.3)
for (x0, x1, y0, y1) in ((BX0, BX1, BY0, HOLE[2]), (BX0, HOLE[0], HOLE[2], BY1), (HOLE[1], BX1, HOLE[2], BY1)):
    I.planks(x0, x1, y0, y1, z=UP, along="x")
I.ceiling(BX0, BX1, BY0, BY1, UP + BH, beams_x=(2.5,), joist_step=0.8)
I.window("right", 2.3, 1.0, 0.9, 2.0, day=0.9)
I.window("front", 1.0, 0.9, 0.9, 1.9, day=0.6)
# stairwell railing
for i in range(10):
    x = HOLE[0] + 0.05 + (HOLE[1] - HOLE[0] - 0.1) * i / 9
    k.box((0.04, 0.04, 0.85), (x, HOLE[2] - 0.03, UP + 0.43), I.WOOD, OAK_D, var=0.04)
k.box((HOLE[1] - HOLE[0], 0.08, 0.07), ((HOLE[0] + HOLE[1]) / 2, HOLE[2] - 0.03, UP + 0.88), I.WOOD, OAK_D, bevel=0.01)
for i in range(4):
    y = HOLE[2] + 0.1 + (HOLE[3] - HOLE[2] - 0.2) * i / 3
    k.box((0.04, 0.04, 0.85), (HOLE[0] - 0.03, y, UP + 0.43), I.WOOD, OAK_D, var=0.04)
k.box((0.08, HOLE[3] - HOLE[2], 0.07), (HOLE[0] - 0.03, (HOLE[2] + HOLE[3]) / 2, UP + 0.88), I.WOOD, OAK_D, bevel=0.01)
k.box((0.1, 0.1, 0.95), (HOLE[0] - 0.03, HOLE[2] - 0.03, UP + 0.48), I.WOOD, TIMBER_D, bevel=0.012)
k.box((HOLE[1] - HOLE[0], 0.14, 0.1), ((HOLE[0] + HOLE[1]) / 2, HOLE[2] - 0.03, UP - 0.02), I.WOOD, TIMBER_D, var=0)
I.collide(((HOLE[0] + HOLE[1]) / 2 - 0.2, HOLE[2] - 0.03, UP + 0.5), (HOLE[1] - HOLE[0] - 0.4, 0.1, 1.0))
I.collide((HOLE[0] - 0.03, (HOLE[2] + HOLE[3]) / 2, UP + 0.5), (0.1, HOLE[3] - HOLE[2], 1.0))

I.mark("bedroom furniture")
# curtains either side of the right window
for s_ in (-1, 1):
    m = I.wall_frame("right")
    x = m(2.3) + s_ * 0.72
    I.cloth_sheet(x, -0.12, 2.25, 0.42, 1.7, 0.0, hexc("a8302a"), nx=3)
    k.pop()
m = I.wall_frame("right")
k.beam((m(2.3) - 1.0, -0.14, 2.3), (m(2.3) + 1.0, -0.14, 2.3), 0.03, I.PL, IRON, bevel=0)
k.pop()
k.push((0, 0, UP))                 # free-standing bedroom furniture sits on the upper floor
I.bed(0.9, 3.85, 0.0, w=1.6, l=2.1, pillows=2, frame=hexc("7a4a2a"),
      patches=[hexc("a8302a"), hexc("8a2622"), hexc("b8453a"), hexc("d9b06a")], border=hexc("5a1a16"))
I.table(-0.4, 4.55, L=0.45, W=0.4, h=0.6)
I.candle(-0.4, 4.5, 0.6, h=0.14, energy=0.8)
I.chest(0.9, 2.45, 0.0, w=1.1, d=0.5, h=0.5, c=hexc("6a4428"))
I.table(4.3, 0.55, L=0.9, W=0.55, h=0.78)
I.lathe([(0, 0), (0.12, 0), (0.2, 0.06), (0.22, 0.1), (0.2, 0.105), (0.1, 0.04), (0, 0.03)], (4.15, 0.55, 0.78),
        I.PL, hexc("d9c9a3"), segs=12)                                   # wash basin
I.lathe([(0, 0), (0.06, 0), (0.08, 0.05), (0.08, 0.12), (0.05, 0.2), (0.055, 0.24), (0, 0.24)], (4.6, 0.6, 0.78),
        I.PL, hexc("b56a3e"), segs=10)                                   # jug
I.chair(3.4, 0.9, -math.pi / 2)
I.rug(2.3, 2.0, 1.1, 0.7, [hexc("7a2a22"), GOLD, hexc("3f506e"), hexc("c9b695"), hexc("7a2a22")], rect=True)
I.prop("crate", (-0.55, 0.45, 0), rz=0.3, s=0.7)
k.pop()
I.shelf_unit("left", 1.2, w=1.1, h=2.0, depth=0.45, levels=(0.4, 1.0, 1.55), items=["books", None, "pots"],
             c_wood=hexc("5a3a24"))
I.lantern("left", 3.4, z=1.65, energy=0.7)
# restore the hall as the active room for anything placed after this
I.W, I.D, I.H, I.cx, I.cy, I.z0 = W, D, H, 0.0, 0.0, 0.0

I.mark("end")
I.rt_lights.append(("FireLight", tuple(FIRE), (1.0, 0.58, 0.3), 1.8, 8.0, True))
I.rt_lights.append(("BedroomLight", (-0.35, 4.3, UP + 1.0), (1.0, 0.72, 0.42), 0.9, 4.5, True))
I.spawn = ((DOOR_X, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.9, 1.0, 2.4), 0.0)
I.npc("NPC_Innkeeper", (4.55, -0.3, 0), (-1, 0), look="Barbarian", height=1.78, anim="Idle", role="innkeeper")
I.npc("NPC_Patron", (FX + 1.5, 2.2, 0), (-0.8, 0.6), look="Rogue_Hooded", height=1.75, anim="Idle", role="patron")
I.markers.append(("BedSpawn", (2.0, 2.6, UP + 0.05), yaw_toward(0, 1), dict(role="rest_point")))
I.cam("a", (-5.3, -4.3, 2.4), (2.6, 2.4, 1.0), lens=17)
I.cam("b", (4.9, -4.2, 2.5), (-3.2, 3.2, 1.0), lens=17)
I.cam("c", (-0.6, 0.5, UP + 1.95), (5.0, 2.8, UP + 0.9), lens=17)
I.finish()
