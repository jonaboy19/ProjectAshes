"""Noble Manor Interior (Rising Ashes / Valencious Region)
Grand stone-and-timber manor hall for regional lords and noble faction heads.
Features:
- Grand carved stone fireplace with heraldic shields and wall banners
- Long council / feast table with carved chairs, silverware and candles
- Master lord's quarters with velvet bed, ornate rugs, and nightstands
- Scholar alcove with double bookcases, bookstand, parchment and scrolls
- Vault corner with treasure chests, gold coins, and armored dummy display
- Wrought iron wagon-wheel chandelier with 8 flickering candles

Run:
    blender -b --python kingdom/tools/blender/make_interior_manor.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("manor", seed=7701, title="Noble Manor")
k = I.k
W, D, H = 9.0, 7.5, 3.5
hw, hd = W / 2, D / 2
DOOR_X = 0.0

def soot(p):
    s = 0.0
    dx = abs(p.x)
    if p.y > 2.2 and dx < 1.8:
        s = max(s, (1 - dx / 1.8) * clamp((p.z - 1.0) / 1.8) * 0.75)
    if p.z > 3.0:
        s = max(s, 0.25 * clamp((p.z - 3.0) / 0.5))
    return s

I.soot = soot
I.env["ambient_energy"] = 1.05

I.mark("shell")
I.room(W, D, H,
       doors={"front": [(DOOR_X, 1.4, 0, 2.4)]},
       windows={
           "front": [(-2.8, 1.1, 1.2, 2.3), (2.8, 1.1, 1.2, 2.3)],
           "left": [(-1.5, 1.2, 1.2, 2.4), (1.5, 1.2, 1.2, 2.4)],
           "right": [(-1.5, 1.2, 1.2, 2.4), (1.5, 1.2, 1.2, 2.4)]
       },
       posts=1.5, stone_base=0.45)

# Rich dark polished hardwood floors
I.planks(-hw, hw, -hd, hd, along="y",
         palette=[hexc("4a2f1b"), hexc("5c3a21"), hexc("3e2716"), hexc("52341e")],
         dark=lambda x, y: 0.25 if (abs(x) < 1.5 and y > 2.0) else 0.0)

I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.2, 2.2), joist_step=0.8)
I.door("front", DOOR_X, 1.4, 2.4)
I.window("front", -2.8, 1.1, 1.2, 2.3, day=0.8)
I.window("front", 2.8, 1.1, 1.2, 2.3, day=0.8)
I.window("left", -1.5, 1.2, 1.2, 2.4, day=0.75)
I.window("left", 1.5, 1.2, 1.2, 2.4, day=0.75)
I.window("right", -1.5, 1.2, 1.2, 2.4, day=0.75)
I.window("right", 1.5, 1.2, 1.2, 2.4, day=0.75)

I.mark("grand hearth")
FIRE = I.fireplace("back", 0.0, width=2.4, energy=3.0, radius=9.0)
I.banner("back", -2.0, 3.2, w=0.9, h=1.8, cloth=hexc("8b1e1e"), trim=hexc("d4af37"), emblem="cross")
I.banner("back", 2.0, 3.2, w=0.9, h=1.8, cloth=hexc("1e3d59"), trim=hexc("d4af37"), emblem="star")
I.mega("Shield_Wooden", (0.0, hd - 0.12, 2.5), rot=(0, 0, 0), s=1.2)
I.mega("Sword_Bronze", (-0.4, hd - 0.15, 2.5), rot=(0, 0.7, 0), s=1.1)
I.mega("Sword_Bronze", (0.4, hd - 0.15, 2.5), rot=(0, -0.7, 0), s=1.1)

I.mark("council table")
TX, TY = -2.2, -0.8
I.mega("Table_Large", (TX, TY, 0), rz=math.pi / 2, s=1.15, collide=True)
I.mega("Chair_1", (TX - 0.65, TY + 0.9, 0), rz=math.pi / 2, collide=True)
I.mega("Chair_1", (TX - 0.65, TY - 0.9, 0), rz=math.pi / 2, collide=True)
I.mega("Chair_1", (TX + 0.65, TY + 0.9, 0), rz=-math.pi / 2, collide=True)
I.mega("Chair_1", (TX + 0.65, TY - 0.9, 0), rz=-math.pi / 2, collide=True)
I.mega("Chair_1", (TX, TY - 1.6, 0), rz=0.0, collide=True)
I.rug(TX, TY, 1.8, 1.4, [hexc("7a1c1c"), hexc("c49a45"), hexc("2b2b2b"), hexc("947132")], rect=True)
I.mega("CandleStick_Triple", (TX, TY, 0.85), s=1.0)
I.candle(TX, TY, 1.05, h=0.15, holder=False, energy=0.7)
I.mega("Chalice", (TX - 0.25, TY + 0.8, 0.85), s=0.9)
I.mega("Chalice", (TX + 0.25, TY - 0.8, 0.85), s=0.9)
I.plate(TX - 0.2, TY + 0.5, 0.85, food=True)
I.plate(TX + 0.2, TY - 0.5, 0.85, food=True)

I.mark("scholar alcove")
BX, BY = -3.2, 2.2
I.mega("Bookcase_2", (BX, hd - 0.35, 0), rz=0.0, s=1.0, collide=True)
I.mega("Bookcase_2", (-hw + 0.35, 2.0, 0), rz=math.pi / 2, s=1.0, collide=True)
I.mega("Workbench", (-hw + 0.85, 0.8, 0), rz=math.pi / 2, s=1.0, collide=True)
I.mega("Chair_1", (-hw + 1.55, 0.8, 0), rz=-math.pi / 2, collide=True)
I.mega("BookStand", (-hw + 0.85, 0.8, 0.85), rz=math.pi / 2, s=0.9)
I.mega("BookGroup_Medium_1", (-hw + 0.85, 0.4, 0.85), rz=math.pi / 2, s=0.9)
I.mega("Scroll_1", (-hw + 0.85, 1.15, 0.85), rz=0.3, s=1.0)
I.candle(-hw + 0.7, 1.25, 0.85, h=0.14, energy=0.5)

I.mark("lord bed chamber")
LX, LY = 2.6, 1.8
I.bed(LX, LY, rot=-math.pi / 2, w=1.8, l=2.3, posts=True, frame=hexc("422617"),
      patches=[hexc("8b1e1e"), hexc("c49a45"), hexc("5c1414"), hexc("a8853b")],
      border=hexc("d4af37"), pillows=2)
I.rug(LX, LY - 1.4, 1.6, 1.1, [hexc("1e3d59"), hexc("d4af37"), hexc("17252a"), hexc("c49a45")], rect=True)
I.mega("Nightstand_Shelf", (LX - 1.25, LY + 0.8, 0), rz=0.0, s=0.95, collide=True)
I.mega("Nightstand_Shelf", (LX + 1.25, LY + 0.8, 0), rz=0.0, s=0.95, collide=True)
I.candle(LX - 1.25, LY + 0.8, 0.75, h=0.12, energy=0.35)
I.candle(LX + 1.25, LY + 0.8, 0.75, h=0.12, energy=0.35)

I.mark("armory & treasury")
AX, AY = 3.2, -1.8
I.mega("Chest_Wood", (AX, -hd + 0.55, 0), rz=math.pi, s=1.1, collide=True)
I.mega("Coin_Pile_2", (AX + 0.65, -hd + 0.45, 0), s=1.2)
I.mega("Coin_Pile", (AX - 0.55, -hd + 0.45, 0), s=1.0)
I.mega("Dummy", (hw - 0.8, -0.6, 0), rz=-math.pi / 3, s=1.05, collide=True)
I.mega("WeaponStand", (hw - 0.45, 0.8, 0), rz=-math.pi / 2, s=1.0, collide=True)
I.shelf("right", -1.8, 1.6, L=1.8, items="jars")

I.mark("chandelier & ambient")
I.chandelier(0.0, 0.4, H, r=0.75, n=8, drop=1.0, energy=2.0, radius=8.5)
I.lantern("left", -0.4, z=2.0, energy=0.6)
I.lantern("right", 0.4, z=2.0, energy=0.6)

I.mark("lighting & godot setup")
I.rt_lights.append(("GrandFireLight", tuple(FIRE), (1.0, 0.55, 0.25), 2.2, 7.5, True))
I.spawn = ((DOOR_X, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.6, 1.0, 2.4), 0.0)
I.npc("NPC_Lord_Aethelgard", (-1.2, 0.2, 0), (0.8, -0.4), look="Knight_Male", anim="Idle", role="manor_lord")

# High fidelity camera beauty angles
I.cam("a", (3.6, -2.8, 2.4), (-1.2, 1.2, 1.1), lens=20)
I.cam("b", (-3.5, 2.6, 2.4), (1.4, -0.8, 1.0), lens=20)
I.cam("c", (0.0, -3.2, 1.8), (0.0, 2.4, 1.5), lens=22)

I.finish()
