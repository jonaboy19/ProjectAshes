"""Tuskridge Orc Chieftain Longhouse (Monster Stronghold Faction Interior)
Heavy timber and stone longhouse for the Tuskridge Orc Chieftain and war council.
Features:
- Massive central roaring hearth fire pit with stone rim and iron cauldron
- Chieftain's skull-draped throne and pelt rugs
- Heavy timber war table with bronze war axes, spiked shields and battle maps
- Grog barrels, iron meat hooks, and trophy weapon racks
- Smoldering embers, orange fire glow, and torchlight

Run:
    blender -b --python kingdom/tools/blender/make_interior_orc.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("orc", seed=6611, title="Tuskridge Chieftain Longhouse")
k = I.k
W, D, H = 9.5, 7.5, 3.8
hw, hd = W / 2, D / 2
DOOR_X = 0.0

def soot(p):
    # Heavy smoke and soot throughout the orc longhouse
    s = 0.35 * clamp(p.z / H)
    dx = abs(p.x)
    if abs(p.y) < 1.5 and dx < 1.8:
        s = max(s, 0.7 * clamp(p.z / 2.5))
    return s

I.soot = soot
I.env["ambient_energy"] = 0.85
I.env["exposure"] = 1.0

I.mark("shell")
I.room(W, D, H,
       doors={"front": [(DOOR_X, 1.6, 0, 2.6)]},
       windows={
           "left": [(0.0, 0.9, 1.4, 2.2)],
           "right": [(0.0, 0.9, 1.4, 2.2)]
       },
       posts=1.6, stone_base=0.6)

# Rough-hewn dark timber logs and flagstones
I.flagstones(-hw, hw, -hd, hd, size=0.8,
             dark=lambda x, y: 0.4 if (x*x + y*y < 3.0) else 0.1)

I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.4, 2.4), joist_step=0.9,
          board_c=hexc("3a2417"))

I.door("front", DOOR_X, 1.6, 2.6)
I.window("left", 0.0, 0.9, 1.4, 2.2, day=0.5)
I.window("right", 0.0, 0.9, 1.4, 2.2, day=0.5)

I.mark("central roaring fire pit")
# Central sunken stone firepit with cauldron
k.ring(1.1, 1.5, 0.25, (0.0, 0.0, 0.12), I.PL, STONES[0], segs=16)
k.cyl(1.1, 0.12, (0.0, 0.0, 0.06), I.GLOW, (1.0, 0.35, 0.08), segs=16)
# Central cauldron on iron tripod
I.mega("Cauldron", (0.0, 0.0, 0.2), s=1.1, collide=True)
FIRE_POS = (0.0, 0.0, 0.6)
I.light(FIRE_POS, colour=(1.0, 0.45, 0.15), energy=3.5, radius=9.0)

I.mark("chieftain throne & war dais")
# Back wall: Chieftain's raised seat with animal pelt rugs
I.mega("Chair_1", (0.0, hd - 0.75, 0), rz=math.pi, s=1.4, collide=True)
I.rug(0.0, hd - 1.2, 1.8, 1.2, [hexc("3a2215"), hexc("613f28"), hexc("21130b")], rect=True)

# Spiked shields and axes flanking throne
I.mega("Shield_Wooden", (-1.2, hd - 0.15, 1.6), rot=(0, 0, 0), s=1.3)
I.mega("Shield_Wooden", (1.2, hd - 0.15, 1.6), rot=(0, 0, 0), s=1.3)
I.mega("Axe_Bronze", (-0.6, hd - 0.15, 2.0), rot=(0, 0.4, 0), s=1.3)
I.mega("Axe_Bronze", (0.6, hd - 0.15, 2.0), rot=(0, -0.4, 0), s=1.3)

# War banners
I.banner("back", -2.8, 3.4, w=1.0, h=2.2, cloth=hexc("4a1210"), trim=hexc("8a5b28"), emblem="anvil")
I.banner("back", 2.8, 3.4, w=1.0, h=2.2, cloth=hexc("4a1210"), trim=hexc("8a5b28"), emblem="anvil")

I.mark("war table & benches")
# Long timber war planning table to the right
TX, TY = 2.4, -0.6
I.mega("Table_Large", (TX, TY, 0), rz=math.pi / 2, s=1.2, collide=True)
I.mega("Bench", (TX - 0.7, TY, 0), rz=math.pi / 2, s=1.2, collide=True)
I.mega("Bench", (TX + 0.7, TY, 0), rz=math.pi / 2, s=1.2, collide=True)
I.mega("Scroll_1", (TX, TY, 0.88), rz=0.4, s=1.2)
I.mega("Axe_Bronze", (TX - 0.2, TY + 0.6, 0.88), rz=-0.5, s=1.0)
I.mug(TX + 0.2, TY - 0.5, 0.88)
I.mug(TX - 0.2, TY - 0.7, 0.88)

I.mark("armory & grog barrels")
# Left armory wing: Weapon stands, grog barrels, crates
I.mega("WeaponStand", (-hw + 0.45, 1.2, 0), rz=math.pi / 2, s=1.2, collide=True)
I.mega("WeaponStand", (-hw + 0.45, -0.6, 0), rz=math.pi / 2, s=1.2, collide=True)
I.mega("Barrel", (-hw + 0.7, -2.0, 0), s=1.2, collide=True)
I.mega("Barrel", (-hw + 1.4, -2.1, 0), s=1.1, collide=True)
I.mega("Crate_Wooden", (-hw + 0.8, 2.4, 0), s=1.1, collide=True)
I.mega("Crate_Metal", (-hw + 0.8, 2.4, 0.45), s=1.0)

# Wall torches
I.mega("Torch_Metal", (-hw + 0.12, 0.0, 2.0), rz=math.pi / 2, s=1.1)
I.mega("Torch_Metal", (hw - 0.12, 0.0, 2.0), rz=-math.pi / 2, s=1.1)
I.light((-hw + 0.3, 0.0, 2.1), colour=(1.0, 0.5, 0.15), energy=1.4, radius=5.0)
I.light((hw - 0.3, 0.0, 2.1), colour=(1.0, 0.5, 0.15), energy=1.4, radius=5.0)

I.mark("lighting & godot setup")
I.rt_lights.append(("OrcRoaringFire", FIRE_POS, (1.0, 0.5, 0.15), 3.0, 9.0, True))
I.spawn = ((DOOR_X, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.8, 1.0, 2.6), 0.0)
I.npc("NPC_Chieftain_Gromkar", (0.0, hd - 1.2, 0), (0.0, -1.0), look="Orc_Warrior", anim="Idle", role="orc_chieftain")

I.cam("a", (0.0, -3.2, 1.8), (0.0, 1.2, 1.0), lens=20)
I.cam("b", (3.4, -2.4, 2.2), (-0.8, 0.8, 0.9), lens=20)
I.cam("c", (-3.4, 2.2, 2.2), (0.8, -0.6, 0.9), lens=20)

I.finish()
