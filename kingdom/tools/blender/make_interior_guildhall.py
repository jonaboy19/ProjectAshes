"""Silverford Guild Hall interior (Region 1, L3): the Masons' and Runecarvers' Guild + Merchants' Hall.

    blender -b --python make_interior_guildhall.py -- [--no-preview]

A stone-and-timber hall in Silverford's blue and silver: a merchants' ledger counter with a
balance scale and shelves of contracts, a runecarver's corner with a standing runestone whose carved
runes glow soft cyan, a mason's bench and stacked blocks, a contract board, a long meeting table, a
hearth, a blue runner from the door and blue-and-silver banners.
-> kingdom/assets/generated/interiors/interior_guildhall.glb
   kingdom/scenes/interiors/guildhall_interior.tscn
   docs/kingdom/blender_previews/interior_guildhall_a.png / _b.png
Hall 13 x 10 m, ceiling 4.6 m; double door in the front wall (Godot +Z) at x = 0.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("guildhall", seed=6127, title="Silverford Guild Hall")
k = I.k
I.RUNE = k.material("Rune", rough=0.9, emission=hexc("6fe0ff"), strength=2.2)   # soft cyan runestone glow
W, D, H = 13.0, 10.0, 4.6
hw, hd = W / 2, D / 2
BLUE = hexc("2f5fae")
BLUE_D = hexc("24498a")
SILVER = hexc("dbe1ea")
GOLD = hexc("d9aa45")
PARCH = [hexc("efe2bf"), hexc("e6d3a6"), hexc("f3e9cc"), hexc("dcc493"), hexc("e9dab4")]
RUNE = hexc("b8f2ff")
I.env["ambient_energy"] = 1.1
I.env["exposure"] = 1.15
I.preview_ambient = 0.7


def soot(p):
    dy = abs(p.y - 1.0)
    if p.x > 5.0 and dy < 1.4:
        return (1 - dy / 1.4) * clamp((p.z - 0.9) / 1.8) * 0.6
    return 0.0


I.soot = soot

I.mark("shell")
I.room(W, D, H, doors={"front": [(0.0, 1.9, 0, 2.9)]},
       windows={"front": [(-4.2, 1.2, 1.4, 2.9), (4.2, 1.2, 1.4, 2.9)],
                "left": [(-2.6, 1.2, 1.4, 3.0), (2.4, 1.2, 1.4, 3.0)],
                "right": [(-3.0, 1.2, 1.4, 3.0)],
                "back": [(-4.6, 1.2, 1.5, 3.0), (4.6, 1.2, 1.5, 3.0)]},
       stone_base=1.25, posts=1.6)
I.planks(-hw, hw, -hd, hd, along="x", palette=[hexc("8a6a48"), hexc("977552"), hexc("a07d58"), hexc("7d5f41")])
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-3.0, 0.0, 3.0), joist_step=0.9, board_c=hexc("6b4c33"))
I.door("front", -0.475, 0.95, 2.9)
I.door("front", 0.475, 0.95, 2.9)
for (w_, c_) in (("front", -4.2), ("front", 4.2)):
    I.window(w_, c_, 1.2, 1.4, 2.9, day=0.9)
I.window("left", -2.6, 1.2, 1.4, 3.0, day=0.8)
I.window("left", 2.4, 1.2, 1.4, 3.0, day=0.8)
I.window("right", -3.0, 1.2, 1.4, 3.0, day=0.8)
I.window("back", -4.6, 1.2, 1.5, 3.0, day=0.8)
I.window("back", 4.6, 1.2, 1.5, 3.0, day=0.8)

# blue runner with silver borders (plain boxes: no z-fight)
RY0, RY1 = -hd + 1.6, 1.5
k.box((1.7, RY1 - RY0, 0.02), (0, (RY0 + RY1) / 2, 0.022), I.PL, BLUE, var=0.03, grime=False)
for sx in (-1, 1):
    k.box((0.09, RY1 - RY0, 0.024), (sx * 0.75, (RY0 + RY1) / 2, 0.024), I.PL, SILVER, var=0.02, grime=False)
yy = RY0 + 0.8
while yy < RY1 - 0.4:
    k.box((0.42, 0.42, 0.026), (0, yy, 0.026), I.PL, SILVER, rot=(0, 0, math.pi / 4), var=0.02, grime=False)
    k.box((0.2, 0.2, 0.028), (0, yy, 0.027), I.PL, BLUE_D, rot=(0, 0, math.pi / 4), var=0.02, grime=False)
    yy += 1.3

# ---------------------------------------------------------------- merchants' counter (back left)
I.mark("counter")
DY, DL, DX = 2.5, 4.4, -2.6                     # desk front line y, length, centre x
k.box((DL, 0.95, 0.78), (DX, DY + 0.475, 0.39), I.WOOD, hexc("5a3a24"), var=0)
for i in range(7):
    x = DX - DL / 2 + (i + 0.5) * DL / 7
    k.box((DL / 7 - 0.12, 0.03, 0.56), (x, DY - 0.01, 0.42), I.WOOD, hexc("7a5234"), bevel=0.01)
    k.box((DL / 7 - 0.24, 0.02, 0.36), (x, DY - 0.03, 0.42), I.PL, hexc("3f66ad"), bevel=0.006, grime=False)   # blue inset panels
k.box((DL + 0.2, 1.05, 0.07), (DX, DY + 0.475, 1.015), I.WOOD, hexc("8a5a34"), bevel=0.02)
k.box((DL + 0.1, 0.06, 0.12), (DX, DY - 0.03, 0.06), I.WOOD, hexc("3d2819"), bevel=0.01)
for sx in (-1, 1):
    k.box((0.14, 0.14, 1.12), (DX + sx * (DL / 2 + 0.05), DY - 0.02, 0.56), I.WOOD, hexc("4a2e1c"), bevel=0.02)
    k.sphere(0.08, (DX + sx * (DL / 2 + 0.05), DY - 0.02, 1.18), I.PL, SILVER, subdiv=1, grime=False)
I.collide((DX, DY + 0.475, 0.55), (DL + 0.3, 1.0, 1.1))
TZ = 1.05
I.mega("Book_7", (DX - 1.5, DY + 0.5, TZ), rz=0.2, s=1.4)
I.mega("Coin_Pile_2", (DX + 0.4, DY + 0.35, TZ), rz=0.5, s=1.2)
I.mega("Scroll_1", (DX - 0.5, DY + 0.6, TZ + 0.03), rz=1.2)
I.mega("Key_Gold", (DX + 1.55, DY + 0.35, TZ), rz=0.6, s=1.4)
# balance scale: pillar, beam, two pans on chains
sx0, sy0 = DX + 1.0, DY + 0.55
I.lathe([(0, 0), (0.09, 0), (0.08, 0.04), (0.03, 0.1), (0.02, 0.45), (0.05, 0.5), (0, 0.52)], (sx0, sy0, TZ), I.PL, hexc("b8892f"), segs=8)
k.box((0.7, 0.03, 0.03), (sx0, sy0, TZ + 0.5), I.PL, hexc("c99a3a"), var=0, grime=False)
for sx in (-1, 1):
    px = sx0 + sx * 0.33
    k.beam((px, sy0, TZ + 0.5), (px, sy0, TZ + 0.2), 0.006, I.PL, hexc("8e8a84"), bevel=0)
    I.lathe([(0, 0), (0.1, 0.02), (0.11, 0.04), (0, 0.02)], (px, sy0, TZ + 0.17), I.PL, hexc("c99a3a"), segs=12)
I.mug(DX + 2.0, DY + 0.5, TZ)
I.candle(DX - 2.0, DY + 0.35, TZ, h=0.16, energy=0.5)

# back wall: banner + scroll shelves
I.banner("back", -0.4, 4.15, w=1.5, h=2.4, cloth=BLUE, trim=SILVER, emblem="anvil", emblem_c=SILVER)
I.shelf_unit("back", -5.4, w=1.5, h=2.5, levels=(0.4, 0.95, 1.5, 2.05), items=["books", "books", "mixed", "books"])
I.shelf_unit("back", -3.5, w=1.6, h=2.5, levels=(0.4, 0.95, 1.5, 2.05), items=["mixed", "books", "books", "pots"])
I.chest(-1.4, hd - 0.4, 0.0, w=1.0, d=0.5, c=hexc("c9982f"))
I.prop("crate_stack", (0.9, hd - 0.75, 0), rz=0.0, s=0.75, collide=True)

# ---------------------------------------------------------------- runecarver's corner (back right)
I.mark("runecarver")
RX, RY = 4.3, 3.2
k.box((1.7, 1.5, 0.22), (RX, RY, 0.11), I.PL, hexc("bfb8a6"), bevel=0.03, var=0.03)           # plinth
k.box((1.5, 1.3, 0.1), (RX, RY, 0.27), I.PL, hexc("d1cab8"), bevel=0.02, var=0.03)
k.box((0.95, 0.4, 2.1), (RX, RY, 1.37), I.PL, hexc("aeb5be"), bevel=0.05, var=0.04)           # the stone
k.sphere(0.475, (RX, RY, 2.42), I.PL, hexc("aeb5be"), scale=(1, 0.42 / 0.475, 0.55), subdiv=2, var=0.04)
front = RY - 0.2 - 0.008
for (ax, az, bx_, bz, wd) in ((-0.22, 1.5, -0.22, 2.3, 0.05), (0.22, 1.5, 0.22, 2.3, 0.05), (-0.22, 1.9, 0.22, 1.9, 0.05),
                              (-0.22, 1.2, 0.0, 1.7, 0.04), (0.22, 1.2, 0.0, 1.7, 0.04), (0.0, 1.0, 0.0, 1.3, 0.05),
                              (-0.3, 2.45, 0.3, 2.45, 0.04)):
    k.beam((RX + ax, front, az), (RX + bx_, front, bz), wd / 2, I.RUNE, RUNE, bevel=0, width=0.03)
for (ox, oz) in ((0.0, 2.2),):
    k.cyl(0.07, 0.03, (RX + ox, front - 0.005, oz + 0.05), I.RUNE, RUNE, rot=(math.pi / 2, 0, 0), segs=10, grime=False)
I.light((RX, RY - 0.9, 1.8), (0.55, 0.85, 1.0), 1.2, 4.5)
I.collide((RX, RY, 1.2), (1.7, 1.5, 2.4))
# mason's bench, blocks and tools
I.mega("Workbench", (5.6, 0.2, 0.0), rz=-math.pi / 2, s=1.0, collide=True)
I.mega("Pickaxe_Bronze", (5.5, 0.6, 0.95), rot=(0, math.pi / 2, 0.3))
I.mega("Whetstone", (5.5, -0.2, 0.95), rz=0.4)
def block(x, y, z, sx, sy, sz, rz=0.0, c=None):
    k.box((sx, sy, sz), (x, y, z + sz / 2), I.PL, c or vary(random.choice(STONES), 0.07, 0.02), bevel=0.03, rot=(0, 0, rz), var=0.05)
block(4.2, -1.6, 0.0, 1.0, 0.7, 0.6, 0.2)
block(4.3, -1.5, 0.6, 0.8, 0.6, 0.5, -0.1, hexc("c8bfa8"))
block(5.3, -2.3, 0.0, 0.9, 0.6, 0.5, 0.5)
block(3.2, -2.9, 0.0, 1.1, 0.7, 0.45, 0.1, hexc("b7b0a0"))
I.collide((4.25, -1.55, 0.55), (1.2, 0.9, 1.1))
I.collide((5.3, -2.3, 0.25), (1.0, 0.8, 0.5))
I.collide((3.2, -2.9, 0.23), (1.2, 0.8, 0.46))
k.box((0.5, 0.5, 0.42), (4.5, 0.2, 0.21), I.PL, hexc("c9c0aa"), bevel=0.03, var=0.04)        # half-carved block on the floor
k.box((0.42, 0.04, 0.3), (4.5, -0.06, 0.24), I.RUNE, hexc("a4e8ff"), var=0, grime=False)
I.collide((4.5, 0.2, 0.22), (0.55, 0.55, 0.44))

# ---------------------------------------------------------------- contract board (left wall)
I.mark("board")
m = I.wall_frame("left")
QB = m(1.8 + 0.0)
QW, QZ0, QZ1 = 2.6, 0.95, 2.6
k.box((QW, 0.05, QZ1 - QZ0), (QB, -0.04, (QZ0 + QZ1) / 2), I.PL, hexc("9a7650"), var=0)
for (x0, z0, x1, z1) in ((-QW / 2 - 0.08, QZ0 - 0.08, QW / 2 + 0.08, QZ0), (-QW / 2 - 0.08, QZ1, QW / 2 + 0.08, QZ1 + 0.1),
                         (-QW / 2 - 0.08, QZ0, -QW / 2, QZ1), (QW / 2, QZ0, QW / 2 + 0.08, QZ1)):
    k.box((x1 - x0, 0.09, z1 - z0), (QB + (x0 + x1) / 2, -0.06, (z0 + z1) / 2), I.WOOD, hexc("4a2e1c"), bevel=0.012)
k.prism([(-0.6, 0), (0.6, 0), (0.55, 0.28), (-0.55, 0.28)], 0.03, (QB, -0.14, QZ1 + 0.28), I.WOOD, hexc("46689e"), bevel=0.008)
k.box((0.8, 0.01, 0.06), (QB, -0.16, QZ1 + 0.42), I.PL, SILVER, var=0)
for row in range(3):
    xx = QB - QW / 2 + 0.12
    while xx < QB + QW / 2 - 0.3:
        nw, nh = random.uniform(0.22, 0.36), random.uniform(0.28, 0.42)
        zc = QZ0 + 0.3 + row * 0.5 + j(0.06)
        rot = j(0.12)
        k.box((nw, 0.006, nh), (xx + nw / 2, -0.07, zc), I.PL, random.choice(PARCH), rot=(0, rot, 0), var=0.03, grime=False)
        for li in range(random.randint(2, 4)):
            k.box((nw * random.uniform(0.4, 0.8), 0.004, 0.012), (xx + nw / 2 + j(0.02), -0.077, zc + nh / 2 - 0.07 - li * 0.05),
                  I.PL, hexc("5a4a3a"), rot=(0, rot, 0), var=0, grime=False)
        if random.random() < 0.4:
            k.sphere(0.022, (xx + nw / 2, -0.085, zc + nh / 2 - 0.03), I.PL, hexc("2f5fae"), subdiv=1, grime=False)
        xx += nw + random.uniform(0.04, 0.12)
k.pop()
I.lantern("left", 0.0, z=2.3, energy=0.7)
I.banner("left", -4.2, 4.0, w=0.8, h=1.6, cloth=BLUE, trim=SILVER, emblem="star", emblem_c=SILVER)
I.banner("front", 0.0, 4.0, w=1.0, h=1.7, cloth=BLUE, trim=SILVER, emblem="anvil", emblem_c=SILVER)
I.banner("right", 4.2, 4.0, w=0.8, h=1.6, cloth=BLUE, trim=SILVER, emblem="star", emblem_c=SILVER)

# ---------------------------------------------------------------- hearth + meeting table
I.mark("hearth + table")
FIRE = I.fireplace("right", -1.6, width=2.0, energy=2.0, radius=7.0)
I.mega("Chair_1", (hw - 1.3, -0.4, 0), rz=-2.3)
I.mega("Chair_1", (hw - 1.4, -3.0, 0), rz=-0.8)
TXc, TYc = -2.6, -1.6
I.mega("Table_Large", (TXc, TYc, 0), rz=math.pi / 2, s=0.85, collide=True)
I.mega("Bench", (TXc - 0.8, TYc, 0), rz=math.pi / 2, s=0.85)
I.mega("Bench", (TXc + 0.8, TYc, 0), rz=math.pi / 2, s=0.85)
I.mega("Scroll_2", (TXc, TYc + 0.2, 0.66), rz=0.7)
for i in range(3):
    I.mug(TXc + j(0.25), TYc + j(0.9), 0.66)
I.plate(TXc + 0.15, TYc - 0.5, 0.66)
I.candle(TXc - 0.05, TYc + 0.6, 0.66, h=0.14, energy=0.35)
I.prop("barrel", (-hw + 0.5, -hd + 0.5, 0), rz=0.3, collide=True)
I.prop("barrel", (-hw + 1.2, -hd + 0.45, 0), rz=1.0, s=0.95, collide=True)
I.prop("crate", (-hw + 0.5, -hd + 1.2, 0), rz=0.2, s=0.85, collide=True)
I.prop("sack_pile", (hw - 1.3, -hd + 0.7, 0), rz=0.0, s=0.8, collide=True)
I.prop("weapon_rack", (-hw + 0.6, 3.2, 0), rz=-math.pi / 2, s=0.9, collide=True)

I.mark("chandeliers")
I.chandelier(-2.4, -1.2, H, r=0.6, n=6, drop=1.3)
I.chandelier(2.6, 0.2, H, r=0.6, n=6, drop=1.3)

I.mark("end")
I.rt_lights.append(("FireLight", tuple(FIRE), (1.0, 0.58, 0.3), 1.8, 7.0, True))
I.rt_lights.append(("RuneGlow", (RX, RY - 1.0, 1.7), (0.55, 0.85, 1.0), 0.9, 5.0, False))
I.spawn = ((0.0, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((0.0, -hd + 0.45, 0.0), (2.3, 1.0, 2.9), 0.0)
I.npc("NPC_Guildmaster", (DX, DY + 1.15, 0), (0, -1), look="Elder_Man", height=1.7, anim="Idle", role="guildmaster")
I.npc("NPC_Runecarver", (RX - 1.4, RY - 0.9, 0), (1, 0.5), look="Blacksmith", height=1.8, anim="Idle", role="runecarver")
I.npc("NPC_Clerk", (-hw + 1.6, 0.9, 0), (-1, 0.2), look="Trader", height=1.7, anim="Idle", role="clerk")
I.cam("a", (-0.2, -hd + 0.9, 2.6), (1.0, 3.0, 1.5), lens=16)
I.cam("b", (-5.0, -3.6, 3.2), (3.6, 2.4, 1.2), lens=18)
I.finish()
