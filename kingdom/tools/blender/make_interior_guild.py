"""Adventurers' Guild hall interior: a tall stone-and-timber hall with the guild's
blue-and-gold banners, a panelled reception desk (ledgers, quill, bell, coins)
in front of bookcases, a big quest board crowded with notices, tables and
benches for adventurers, a hearth with a weapon stand, wagon-wheel chandeliers
and a blue runner from the door to the desk.

    blender -b --python make_interior_guild.py -- [--no-preview]

-> kingdom/assets/generated/interiors/interior_guild.glb
   kingdom/scenes/interiors/guild_interior.tscn
   docs/kingdom/blender_previews/interior_guild_a.png / _b.png
Hall 12 x 10 m, ceiling 4.4 m; double door in the front wall (Godot +Z) at x = 0.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("guild", seed=7404, title="Adventurers' Guild")
k = I.k
W, D, H = 12.0, 10.0, 4.4
hw, hd = W / 2, D / 2
BLUE = hexc("2f4a86")
GOLD = hexc("d9aa45")
PARCH = [hexc("efe2bf"), hexc("e6d3a6"), hexc("f3e9cc"), hexc("dcc493"), hexc("e9dab4")]


def soot(p):
    dy = abs(p.y + 1.0)
    if p.x > 4.8 and dy < 1.4:
        return (1 - dy / 1.4) * clamp((p.z - 0.9) / 1.8) * 0.7
    return 0.25 * clamp((p.z - 3.6) / 0.8) if p.z > 3.6 else 0.0


I.soot = soot
I.env["ambient_energy"] = 0.8

I.mark("shell")
I.room(W, D, H, doors={"front": [(0.0, 1.9, 0, 2.8)]},
       windows={"front": [(-3.8, 1.2, 1.5, 2.9), (3.8, 1.2, 1.5, 2.9)], "left": [(1.6, 1.1, 1.5, 2.8), (-3.2, 1.1, 1.5, 2.8)],
                "right": [(2.4, 1.1, 1.5, 2.8)]},
       stone_base=1.1, posts=1.5)
I.planks(-hw, hw, -hd, hd, along="x", palette=[hexc("6f4b30"), hexc("7b5234"), hexc("86583a"), hexc("5f4029")])
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.6, 0.4, 3.2), joist_step=0.9, board_c=hexc("5e3f29"))
I.door("front", -0.475, 0.95, 2.8)
I.door("front", 0.475, 0.95, 2.8)
for (w_, c_) in (("front", -3.8), ("front", 3.8)):
    I.window(w_, c_, 1.2, 1.5, 2.9, day=0.8)
I.window("left", 1.6, 1.1, 1.5, 2.8, day=0.7)
I.window("left", -3.2, 1.1, 1.5, 2.8, day=0.7)
I.window("right", 2.4, 1.1, 1.5, 2.8, day=0.7)
I.rug(0, -1.1, 0.75, 3.6, [hexc("2f4a86"), GOLD, hexc("2f4a86"), hexc("3a5a9a")], rect=True)

I.mark("reception desk")
DY = 2.3                      # desk front line (y)
DL = 3.8
k.box((DL, 0.75, 0.95), (0, DY + 0.38, 0.475), I.WOOD, hexc("5a3a24"), var=0)
for i in range(6):            # panelled front
    x = -DL / 2 + (i + 0.5) * DL / 6
    k.box((DL / 6 - 0.12, 0.03, 0.62), (x, DY - 0.01, 0.5), I.WOOD, hexc("7a5234"), bevel=0.01)
    k.box((DL / 6 - 0.22, 0.02, 0.42), (x, DY - 0.03, 0.5), I.WOOD, hexc("8a6040"), bevel=0.006)
    k.box((0.07, 0.05, 0.95), (x - DL / 12, DY - 0.02, 0.475), I.WOOD, hexc("4a2e1c"), var=0.03)
k.box((DL + 0.2, 0.95, 0.07), (0, DY + 0.38, 0.985), I.WOOD, hexc("8a5a34"), bevel=0.02)
k.box((DL + 0.1, 0.06, 0.12), (0, DY - 0.03, 0.06), I.WOOD, hexc("3d2819"), bevel=0.01)
for sx in (-1, 1):            # carved end posts with gold caps
    k.box((0.14, 0.14, 1.12), (sx * (DL / 2 + 0.05), DY - 0.02, 0.56), I.WOOD, hexc("4a2e1c"), bevel=0.02)
    k.sphere(0.08, (sx * (DL / 2 + 0.05), DY - 0.02, 1.18), I.PL, GOLD, subdiv=1, grime=False)
I.collide((0, DY + 0.38, 0.55), (DL + 0.3, 0.95, 1.1))
TZ = 1.02
I.mega("Book_Stack_2", (-1.4, DY + 0.45, TZ), rz=0.3)
I.mega("Book_7", (-0.5, DY + 0.35, TZ), rz=-0.15, s=1.4)        # open ledger
I.mega("Coin_Pile_2", (0.9, DY + 0.3, TZ), rz=0.5, s=1.2)
I.mega("Scroll_1", (0.35, DY + 0.55, TZ + 0.03), rz=1.2)
I.lathe([(0, 0), (0.035, 0), (0.04, 0.03), (0.02, 0.05), (0, 0.05)], (-0.1, DY + 0.5, TZ), I.PL, hexc("2a2622"),
        segs=8)                                                     # inkwell
k.tube([(-0.1, DY + 0.5, TZ + 0.04), (-0.05, DY + 0.55, TZ + 0.2), (0.0, DY + 0.58, TZ + 0.32)], [0.004, 0.02, 0.004],
       I.PL, hexc("efe6d6"), segs=4, point_end=True)                # quill
I.lathe([(0, 0), (0.06, 0), (0.065, 0.015), (0.045, 0.06), (0.012, 0.08), (0.02, 0.1), (0, 0.1)], (1.45, DY + 0.35, TZ),
        I.PL, GOLD, segs=10)                                         # desk bell
I.candle(-1.75, DY + 0.35, TZ, h=0.16, energy=0.5)
I.candle(1.7, DY + 0.55, TZ, h=0.12, energy=0.4)

I.mark("back wall")
I.banner("back", 0.0, 3.9, w=1.3, h=2.2, cloth=BLUE, trim=GOLD, emblem="star")
I.banner("back", -2.1, 3.7, w=0.7, h=1.4, cloth=BLUE, trim=GOLD, emblem="star")
I.banner("back", 2.1, 3.7, w=0.7, h=1.4, cloth=BLUE, trim=GOLD, emblem="star")
I.shelf_unit("back", -4.1, w=1.6, h=2.5, levels=(0.4, 0.95, 1.5, 2.05), items=["books", "books", "mixed", "books"])
I.shelf_unit("back", 4.1, w=1.6, h=2.5, levels=(0.4, 0.95, 1.5, 2.05), items=["mixed", "books", "books", "pots"])
I.chest(-2.5, hd - 0.4, 0.0, w=1.0, d=0.5)
I.prop("crate_stack", (2.9, hd - 0.75, 0), rz=0.0, s=0.75, collide=True)

I.mark("quest board")
m = I.wall_frame("left")
QB = m(-0.8)
QW, QZ0, QZ1 = 2.8, 0.95, 2.55
k.box((QW, 0.05, QZ1 - QZ0), (QB, -0.04, (QZ0 + QZ1) / 2), I.PL, hexc("9a7650"), var=0)   # cork / board
for (x0, z0, x1, z1) in ((-QW / 2 - 0.08, QZ0 - 0.08, QW / 2 + 0.08, QZ0), (-QW / 2 - 0.08, QZ1, QW / 2 + 0.08, QZ1 + 0.1),
                         (-QW / 2 - 0.08, QZ0, -QW / 2, QZ1), (QW / 2, QZ0, QW / 2 + 0.08, QZ1)):
    k.box((x1 - x0, 0.09, z1 - z0), (QB + (x0 + x1) / 2, -0.06, (z0 + z1) / 2), I.WOOD, hexc("4a2e1c"), bevel=0.012)
k.prism([(-QW / 2 - 0.25, 0), (QW / 2 + 0.25, 0), (QW / 2 + 0.1, 0.18), (-QW / 2 - 0.1, 0.18)], 0.12,
        (QB, -0.08, QZ1 + 0.1), I.WOOD, hexc("5a3a24"), bevel=0.01)                            # little roof ledge
k.prism([(-0.55, 0), (0.55, 0), (0.5, 0.26), (-0.5, 0.26)], 0.03, (QB, -0.14, QZ1 + 0.3), I.WOOD, hexc("6a452b"),
        bevel=0.008)                                                                            # sign board
k.box((0.8, 0.01, 0.06), (QB, -0.16, QZ1 + 0.43), I.PL, GOLD, var=0)
notes = 0
for row in range(3):
    xx = QB - QW / 2 + 0.12
    while xx < QB + QW / 2 - 0.3:
        nw = random.uniform(0.22, 0.36)
        nh = random.uniform(0.28, 0.42)
        zc = QZ0 + 0.3 + row * 0.5 + j(0.06)
        rot = j(0.12)
        c = random.choice(PARCH)
        k.box((nw, 0.006, nh), (xx + nw / 2, -0.07 - 0.002 * notes % 3, zc), I.PL, c, rot=(0, rot, 0), var=0.03,
              grime=False)
        for li in range(random.randint(2, 5)):           # scribbled lines
            k.box((nw * random.uniform(0.4, 0.8), 0.004, 0.012),
                  (xx + nw / 2 + j(0.02), -0.077 - 0.002 * notes % 3, zc + nh / 2 - 0.07 - li * 0.05), I.PL,
                  hexc("5a4a3a"), rot=(0, rot, 0), var=0, grime=False)
        if random.random() < 0.35:
            k.sphere(0.022, (xx + nw / 2, -0.085, zc + nh / 2 - 0.03), I.PL, hexc("a8241c"), subdiv=1, grime=False)
        else:
            k.box((0.02, 0.02, 0.02), (xx + nw / 2, -0.08, zc + nh / 2 - 0.03), I.PL, IRON, var=0, grime=False)
        if random.random() < 0.2:                          # a "wanted" sketch
            k.box((nw * 0.55, 0.004, nh * 0.35), (xx + nw / 2, -0.078, zc + 0.02), I.PL, hexc("6a5a48"),
                  rot=(0, rot, 0), var=0, grime=False)
        xx += nw + random.uniform(0.04, 0.12)
        notes += 1
k.pop()
I.lantern("left", -2.6, z=2.3, energy=0.7)

I.mark("hearth + weapons")
FIRE = I.fireplace("right", -1.0, width=2.0, energy=2.0, radius=7.0)
I.mega("WeaponStand", (hw - 0.8, -3.6, 0), rz=math.pi / 2, collide=True)
I.mega("Shield_Wooden", (hw - 0.1, 1.2, 2.0), rot=(0, 0, -math.pi / 2), s=1.1)
I.banner("right", 4.0, 3.9, w=0.75, h=1.5, cloth=BLUE, trim=GOLD, emblem="star")
I.banner("left", 3.8, 3.9, w=0.75, h=1.5, cloth=BLUE, trim=GOLD, emblem="star")
I.banner("left", -4.6, 3.9, w=0.75, h=1.5, cloth=BLUE, trim=GOLD, emblem="star")

I.mark("seating")
for (tx, ty) in ((3.2, -1.2), (-3.4, -3.3)):
    I.mega("Table_Large", (tx, ty, 0), rz=math.pi / 2, s=0.8, collide=True)
    I.mega("Bench", (tx - 0.75, ty, 0), rz=math.pi / 2, s=0.8)
    I.mega("Bench", (tx + 0.75, ty, 0), rz=math.pi / 2, s=0.8)
    for i in range(3):
        I.mug(tx + j(0.25), ty + j(0.8), 0.65)
    I.plate(tx + 0.15, ty - 0.4, 0.65)
    I.candle(tx - 0.1, ty + 0.3, 0.65, h=0.14, energy=0.35)
I.table(3.4, -3.6, L=1.3, W=0.8, rot=0.0)
I.chair(3.4, -3.0, math.pi)
I.chair(3.4, -4.2, 0.0)
I.chair(2.4, -3.6, math.pi / 2)
I.mega("Chair_1", (hw - 1.3, 0.8, 0), rz=-2.2)                 # fireside chairs
I.mega("Chair_1", (hw - 1.4, -2.8, 0), rz=-0.9)
I.prop("barrel", (-hw + 0.5, -hd + 0.5, 0), rz=0.3, collide=True)
I.prop("barrel", (-hw + 1.2, -hd + 0.45, 0), rz=1.0, s=0.95, collide=True)
I.prop("crate", (-hw + 0.5, -hd + 1.2, 0), rz=0.2, s=0.85, collide=True)

I.mark("chandeliers")
I.chandelier(-2.2, -0.8, H, r=0.6, n=6, drop=1.3)
I.chandelier(2.2, 0.6, H, r=0.6, n=6, drop=1.3)

I.mark("end")
I.rt_lights.append(("FireLight", tuple(FIRE), (1.0, 0.58, 0.3), 1.8, 7.0, True))
I.rt_lights.append(("DeskCandles", (0.0, DY + 0.1, 1.9), (1.0, 0.75, 0.45), 0.7, 4.5, True))
I.spawn = ((0.0, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((0.0, -hd + 0.45, 0.0), (2.3, 1.0, 2.8), 0.0)
I.npc("NPC_Receptionist", (0.0, DY + 1.1, 0), (0, -1), look="Mage", height=1.7, anim="Idle", role="receptionist")
I.npc("NPC_Adventurer", (-hw + 1.4, -0.6, 0), (-1, 0.1), look="Rogue", height=1.8, anim="Idle", role="adventurer")
I.cam("a", (-0.2, -hd + 0.9, 2.6), (0.0, 3.0, 1.4), lens=16)
I.cam("b", (4.9, 3.9, 3.0), (-3.5, -1.6, 1.0), lens=18)
I.finish()
