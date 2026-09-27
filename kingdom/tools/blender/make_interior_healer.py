"""Healer's house interior: walls of shelves crowded with potions, jars and crocks,
bundles of drying herbs under the beams, a work table with mortar and pestle,
bottles, an open book and candles, two patient beds with a side table, a small
hearth with a cauldron, potted herbs and the healer's green banner.

    blender -b --python make_interior_healer.py -- [--no-preview]

-> kingdom/assets/generated/interiors/interior_healer.glb
   kingdom/scenes/interiors/healer_interior.tscn
   docs/kingdom/blender_previews/interior_healer_a.png / _b.png
Room 8 x 7 m, ceiling 3.4 m; entrance door in the front wall (Godot +Z) at x = -2.2.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("healer", seed=6303, title="Healer")
k = I.k
W, D, H = 8.0, 7.0, 3.4
hw, hd = W / 2, D / 2
DOOR_X = -2.2
GREEN = hexc("4f7a3a")
LINENS = [hexc("ece2cc"), hexc("dfe6d4"), hexc("e8dcc0"), hexc("cfdcc4"), hexc("f2ead8"), hexc("b9cfa8")]


def soot(p):
    dy = abs(p.y - 1.6)
    if p.x > 2.6 and dy < 1.3:
        return (1 - dy / 1.3) * clamp((p.z - 0.9) / 1.6) * 0.7
    return 0.25 * clamp((p.z - 2.8) / 0.6) if p.z > 2.8 else 0.0


I.soot = soot

I.mark("shell")
I.room(W, D, H, doors={"front": [(DOOR_X, 1.2, 0, 2.2)]},
       windows={"front": [(1.4, 1.1, 1.1, 2.1)], "left": [(-1.0, 0.9, 1.2, 2.1)], "right": [(-1.3, 0.9, 1.2, 2.1)]})
I.planks(-hw, hw, -hd, hd, along="x", palette=[hexc("9c6b44"), hexc("a4754b"), hexc("8d5f3b"), hexc("b08050")])
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-1.2, 1.1), joist_step=0.8)
I.door("front", DOOR_X, 1.2, 2.2)
I.window("front", 1.4, 1.1, 1.1, 2.1, day=0.7)
I.window("left", -1.0, 0.9, 1.2, 2.1, day=0.6)
I.window("right", -1.3, 0.9, 1.2, 2.1, day=0.6)

I.mark("hearth + cauldron")
FIRE = I.fireplace("right", 1.6, width=1.6, energy=1.8, radius=6.0, logs=False)
I.mega("Cauldron", (hw - 1.45, 0.5, 0), rz=0.3, s=0.75, collide=True)
k.cyl(0.33, 0.02, (hw - 1.45, 0.5, 0.52), I.PL, hexc("5f8a4a"), segs=12, caps=True)       # green brew
for i in range(4):
    k.sphere(0.03, (hw - 1.45 + j(0.18), 0.5 + j(0.18), 0.54), I.PL, hexc("8ab86a"), subdiv=1, grime=False)

I.mark("potion shelves")
# back wall: a cabinet under two shelf units of bottles, plus plain shelves of jars
I.mega("Cabinet", (-0.9, hd - 0.25, 0), rz=0.0, collide=True)
I.shelf("back", -0.9, 1.45, L=1.3, items="bottles")
I.shelf("back", -0.9, 1.95, L=1.3, items="jars")
I.shelf_unit("back", 0.65, w=1.2, h=2.3, levels=(0.4, 0.9, 1.4, 1.9), items=["jars", "bottles", "bottles", "pots"])
I.shelf_unit("back", 2.05, w=1.4, h=2.3, levels=(0.4, 0.9, 1.4, 1.9), items=["pots", "jars", "bottles", "mixed"])
I.shelf("left", 1.9, 1.5, L=1.6, items="bottles")
I.shelf("left", 1.9, 2.0, L=1.6, items="mixed")
I.banner("back", -2.6, 2.95, w=0.75, h=1.3, cloth=GREEN, trim=hexc("d9c38a"), emblem="leaf", emblem_c=hexc("f0e6c8"))

I.mark("work table")
TX, TY = 0.7, 1.25
I.table(TX, TY, L=2.0, W=0.9)
# mortar and pestle
I.lathe([(0, 0), (0.07, 0), (0.1, 0.03), (0.11, 0.09), (0.095, 0.1), (0.07, 0.035), (0, 0.03)], (TX - 0.5, TY - 0.1, 0.76),
        I.PL, hexc("9a948a"), segs=12)
k.cyl(0.02, 0.2, (TX - 0.48, TY - 0.1, 0.8), I.PL, hexc("b0a898"), rot=(0.4, 0.3, 0), segs=8, r2=0.028)
k.sphere(1.0, (TX - 0.5, TY - 0.1, 0.8), I.PL, hexc("6d8a45"), scale=(0.07, 0.07, 0.02), subdiv=1, grime=False)
# herbs laid out, bottles, a book, candles
for i in range(5):
    x = TX + 0.1 + i * 0.12
    k.tube([(x, TY + 0.25, 0.77), (x + 0.04, TY + 0.05, 0.775), (x + 0.02, TY - 0.15, 0.78)], [0.012, 0.03, 0.035], I.PL,
           random.choice(HERBS), segs=5, point_end=False)
for i in range(5):
    I.bottle(TX - 0.2 + j(0.25), TY + 0.28 + j(0.06), 0.76, s=random.uniform(0.7, 1.1))
I.mega("Book_7", (TX + 0.55, TY - 0.2, 0.765), rz=0.3, s=1.3)
I.candle(TX - 0.75, TY + 0.25, 0.76, h=0.18, energy=0.5)
I.candle(TX + 0.85, TY + 0.3, 0.76, h=0.12, energy=0.3)
I.stool(TX + 0.2, TY + 0.85, h=0.5)
I.prop("basket_produce", (TX + 1.4, TY + 0.4, 0), rz=0.5, s=0.8)

I.mark("beds")
PAT = LINENS
I.bed(-hw + 1.1, 1.9, math.pi / 2, w=1.0, l=2.0, patches=PAT, border=hexc("8aa878"), frame=HONEY, posts=False)
I.bed(-hw + 1.1, -0.1 - 0.9 + 0.2, math.pi / 2, w=1.0, l=2.0, patches=PAT, border=hexc("8aa878"), frame=HONEY,
      posts=False)
I.table(-hw + 0.5, 0.85, L=0.5, W=0.45, h=0.6, collide=True)
I.candle(-hw + 0.45, 0.8, 0.6, h=0.12, energy=0.35)
I.lathe([(0, 0), (0.05, 0), (0.09, 0.03), (0.1, 0.06), (0.09, 0.062), (0.07, 0.035), (0, 0.02)], (-hw + 0.55, 0.95, 0.6),
        I.PL, hexc("d9c9a3"), segs=10)
I.mega("Bucket_Wooden_1", (-hw + 2.1, 0.8, 0), rz=1.0)
# folded blankets on a chest at the foot of the beds
I.chest(-hw + 2.55, 1.9, math.pi / 2, w=0.8, d=0.45, h=0.45)
k.box((0.4, 0.55, 0.12), (-hw + 2.55, 1.9, 0.51), I.PL, hexc("b9cfa8"), bevel=0.03)
I.rug(-0.6, -0.4, 1.2, 0.8, [hexc("5f7a4a"), hexc("d4c496"), hexc("8a6a4a"), hexc("c9b695"), hexc("4f6a3a")])

I.mark("plants + corner")
I.prop("flower_planter", (1.4, -hd + 0.35, 0), rz=0.0, s=0.9, collide=True)
for (x, y) in ((hw - 0.35, -hd + 0.4), (hw - 0.8, -hd + 0.35), (-hw + 0.35, -hd + 1.5)):
    s = random.uniform(0.13, 0.17)
    I.lathe([(0, 0), (0.7 * s, 0), (1.0 * s, 1.1 * s), (1.05 * s, 1.2 * s), (0, 1.2 * s)], (x, y, 0), I.PL,
            hexc("a95f3a"), segs=10)
    for i in range(7):
        a = random.uniform(0, math.tau)
        k.sphere(s * random.uniform(0.5, 0.8), (x + math.cos(a) * s * 0.6, y + math.sin(a) * s * 0.6,
                                               1.2 * s + random.uniform(0.05, 0.3)), I.PL,
                 random.choice([hexc("4f7a34"), hexc("5f8a3a"), hexc("6d9a45")]), subdiv=1, noise_amt=0.02, grime=False)
I.prop("sack_pile", (hw - 1.4, -hd + 0.6, 0), rz=0.0, s=0.6, collide=True)
I.prop("barrel", (hw - 0.4, -1.6 + 0.3 - 1.0, 0), rz=0.7, s=0.9, collide=True)

I.mark("herbs")
for hx in [-1.2, -0.8, -0.4, 0.0, 0.4, 0.8, 1.2, 1.6, 2.0]:
    for hy in (1.1,):
        I.herbs(hx + j(0.05), hy + j(0.04), H - 0.44, colours=HERBS)
for hx in [-2.6, -2.2, -1.8, 2.4, 2.8]:
    I.herbs(hx, -1.2 + j(0.04), H - 0.44)
I.lantern("front", -0.3, z=1.9, energy=0.6)

I.mark("end")
I.rt_lights.append(("FireLight", tuple(FIRE), (1.0, 0.58, 0.3), 1.4, 5.5, True))
I.rt_lights.append(("TableCandle", (TX - 0.6, TY + 0.2, 1.1), (1.0, 0.72, 0.42), 0.6, 3.0, True))
I.spawn = ((DOOR_X, -hd + 1.4, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.7, 1.0, 2.2), 0.0)
I.npc("NPC_Healer", (TX, TY + 0.75, 0), (0, -1), look="Elder_Woman", height=1.65, anim="Idle", role="healer")
I.cam("a", (-3.2, -2.9, 2.2), (1.2, 2.2, 0.9), lens=18)
I.cam("b", (3.3, -2.9, 2.3), (-2.4, 1.6, 0.7), lens=18)
I.finish()
