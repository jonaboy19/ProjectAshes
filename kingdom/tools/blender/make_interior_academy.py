"""Kingdom Magic & Alchemy Academy (School & Faction Laboratory Interior)
Prestigious academy laboratory for magical and alchemical research in Valencious.
Features:
- Master alchemical distillation bench with bubbling potions, alembics and specimens
- Student lecture benches and desks with parchment, ink, and open textbooks
- High arcana library stacks with ancient grimoires, scroll codices and bookstands
- Astrological and magical artifacts (enchanted cauldrons, runic pedestals)
- Arcane glow illumination (cerulean, violet and warm candlelight)

Run:
    blender -b --python kingdom/tools/blender/make_interior_academy.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("academy", seed=8834, title="Valencious Royal Academy Laboratory")
k = I.k
W, D, H = 9.0, 7.5, 3.6
hw, hd = W / 2, D / 2
DOOR_X = 0.0

def soot(p):
    # Magical residue, clean laboratory
    if p.z > 3.1:
        return 0.12 * clamp((p.z - 3.1) / 0.5)
    return 0.0

I.soot = soot
I.env["ambient_energy"] = 1.1
I.env["exposure"] = 1.05

I.mark("shell")
I.room(W, D, H,
       doors={"front": [(DOOR_X, 1.4, 0, 2.4)]},
       windows={
           "front": [(-2.8, 1.2, 1.2, 2.4), (2.8, 1.2, 1.2, 2.4)],
           "left": [(-1.5, 1.2, 1.2, 2.4), (1.5, 1.2, 1.2, 2.4)],
           "right": [(-1.5, 1.2, 1.2, 2.4), (1.5, 1.2, 1.2, 2.4)]
       },
       posts=1.4, stone_base=0.5)

# Smooth polished flagstones
I.flagstones(-hw, hw, -hd, hd, size=0.65)

I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.2, 2.2), joist_step=0.8,
          board_c=hexc("4a3c30"))

I.door("front", DOOR_X, 1.4, 2.4)
I.window("front", -2.8, 1.2, 1.2, 2.4, day=0.85)
I.window("front", 2.8, 1.2, 1.2, 2.4, day=0.85)
I.window("left", -1.5, 1.2, 1.2, 2.4, day=0.8)
I.window("left", 1.5, 1.2, 1.2, 2.4, day=0.8)
I.window("right", -1.5, 1.2, 1.2, 2.4, day=0.8)
I.window("right", 1.5, 1.2, 1.2, 2.4, day=0.8)

I.mark("master alchemical workbench")
# Front-center master alchemist demonstration platform
I.mega("Workbench_Drawers", (-0.8, 1.5, 0), rz=0.0, s=1.15, collide=True)
I.mega("Workbench", (0.8, 1.5, 0), rz=0.0, s=1.15, collide=True)

# Alchemical apparatus on bench
I.mega("Cauldron", (0.0, 1.5, 0.9), s=0.55)
I.light((0.0, 1.5, 1.15), colour=(0.3, 0.8, 1.0), energy=1.2, radius=4.0)

I.mega("Potion_1", (-0.7, 1.5, 0.9), s=1.0)
I.mega("Potion_2", (-0.5, 1.5, 0.9), s=1.0)
I.mega("Potion_4", (0.5, 1.5, 0.9), s=1.0)
I.mega("SmallBottles_1", (0.8, 1.5, 0.9), s=1.1)
I.mega("BookStand", (-1.2, 1.5, 0.9), rz=0.3, s=0.95)
I.mega("CandleStick_Stand", (1.2, 1.5, 0.9), s=0.9)
I.candle(1.2, 1.5, 1.48, h=0.14, holder=False, energy=0.5)

I.mark("student lecture seating")
# Lecture rows facing the master workbench
for row_y in [-0.2, -1.4]:
    I.mega("Table_Large", (-1.6, row_y, 0), rz=0.0, s=1.0, collide=True)
    I.mega("Table_Large", (1.6, row_y, 0), rz=0.0, s=1.0, collide=True)
    I.mega("Bench", (-1.6, row_y - 0.65, 0), rz=0.0, s=1.0, collide=True)
    I.mega("Bench", (1.6, row_y - 0.65, 0), rz=0.0, s=1.0, collide=True)
    # Books and parchment on student desks
    I.mega("BookGroup_Small_1", (-1.6, row_y, 0.8), s=0.9)
    I.mega("Scroll_1", (1.6, row_y, 0.8), rz=0.2, s=0.9)
    I.candle(-1.1, row_y, 0.8, h=0.1, energy=0.3)
    I.candle(2.1, row_y, 0.8, h=0.1, energy=0.3)

I.mark("arcana library walls")
# Massive bookcases along the back and side walls
I.mega("Bookcase_2", (-2.8, hd - 0.35, 0), rz=0.0, s=1.1, collide=True)
I.mega("Bookcase_2", (0.0, hd - 0.35, 0), rz=0.0, s=1.1, collide=True)
I.mega("Bookcase_2", (2.8, hd - 0.35, 0), rz=0.0, s=1.1, collide=True)
I.mega("Bookcase_2", (-hw + 0.35, 1.2, 0), rz=math.pi / 2, s=1.1, collide=True)
I.mega("Bookcase_2", (hw - 0.35, 1.2, 0), rz=-math.pi / 2, s=1.1, collide=True)

# Extra book stacks & specimens
I.mega("Book_Stack_1", (-2.2, hd - 0.35, 0.95), s=1.0)
I.mega("Book_Stack_2", (2.2, hd - 0.35, 0.95), s=1.0)
I.mega("Shelf_Small_Bottles", (-hw + 0.3, 0.0, 1.6), rz=math.pi / 2, s=1.1)
I.mega("Shelf_Small_Bottles", (hw - 0.3, 0.0, 1.6), rz=-math.pi / 2, s=1.1)

# Wall banners of the Royal Academy
I.banner("back", -1.4, 3.3, w=0.8, h=2.0, cloth=hexc("2c1f4a"), trim=hexc("8fa4d4"), emblem="star")
I.banner("back", 1.4, 3.3, w=0.8, h=2.0, cloth=hexc("2c1f4a"), trim=hexc("8fa4d4"), emblem="star")

I.mark("chandelier & lanterns")
I.chandelier(0.0, 0.0, H, r=0.75, n=8, drop=1.0, energy=2.0, radius=8.0)
I.lantern("left", 0.0, z=2.0, energy=0.6)
I.lantern("right", 0.0, z=2.0, energy=0.6)

I.mark("lighting & godot setup")
I.rt_lights.append(("AlchemyBrewGlow", (0.0, 1.5, 1.15), (0.35, 0.85, 1.0), 1.5, 5.0, True))
I.spawn = ((DOOR_X, -hd + 1.4, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.6, 1.0, 2.4), 0.0)
I.npc("NPC_Archmage_Vaelin", (0.0, 2.2, 0), (0.0, -1.0), look="Mage_Male", anim="Idle", role="academy_dean")

I.cam("a", (0.0, -3.2, 2.0), (0.0, 1.4, 1.0), lens=20)
I.cam("b", (3.2, -2.4, 2.2), (-0.8, 1.2, 1.0), lens=20)
I.cam("c", (-3.2, 2.0, 2.2), (0.8, -0.6, 1.0), lens=20)

I.finish()
