"""Generic village house interior, reused by all five house types (peasant a/b,
family, trader, manor): one timber-framed room with a stone hearth, a table
with stools and a bench, a double bed and a child's bed, a chest, shelves of
crocks, barrels and sacks, dried herbs from the beams and a rag rug.

    blender -b --python make_interior_house.py -- [--no-preview]

-> kingdom/assets/generated/interiors/interior_house.glb
   kingdom/scenes/interiors/house_interior.tscn
   docs/kingdom/blender_previews/interior_house_a.png / _b.png
Room 7 x 6 m, ceiling 3.0 m; entrance door in the front wall (Godot +Z) at x = 1.8.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("house", seed=4101, title="House")
k = I.k
W, D, H = 7.0, 6.0, 3.0
hw, hd = W / 2, D / 2
DOOR_X = 1.8


def soot(p):
    s = 0.0
    dx = abs(p.x + 1.2)
    if p.y > 1.8 and dx < 1.6:
        s = max(s, (1 - dx / 1.6) * clamp((p.z - 0.9) / 1.6) * 0.8)
    if p.z > 2.3:
        s = max(s, 0.3 * clamp((p.z - 2.3) / 0.7))
    return s


I.soot = soot

I.mark("shell")
I.room(W, D, H, doors={"front": [(DOOR_X, 1.1, 0, 2.1)]},
       windows={"front": [(-1.4, 0.9, 1.1, 1.9)], "left": [(1.2, 0.8, 1.1, 1.9)], "right": [(-0.9, 0.8, 1.1, 1.9)]})
I.planks(-hw, hw, -hd, hd, along="y",
         dark=lambda x, y: 0.3 if (abs(x + 1.2) < 1.2 and y > 1.6) else 0.0)
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-1.0, 1.3))
I.door("front", DOOR_X, 1.1, 2.1)
I.window("front", -1.4, 0.9, 1.1, 1.9)
I.window("left", 1.2, 0.8, 1.1, 1.9)
I.window("right", -0.9, 0.8, 1.1, 1.9)

I.mark("hearth")
FIRE = I.fireplace("back", -1.2, width=1.8)

I.mark("beds")
I.bed(2.35, 1.85, 0.0, w=1.4, l=2.1, pillows=2)
I.chest(2.35, 0.45, 0.0, w=1.0)
I.bed(-2.85, -1.2, math.pi / 2, w=0.95, l=1.75, frame=HONEY, posts=False,
      patches=[hexc("7d9460"), hexc("e6d8bb"), hexc("c8963e"), hexc("8e5a3a")], border=hexc("5a6a3a"))
I.rug(0.9, 1.35, 0.55, 0.4, [hexc("a33f2c"), hexc("d4ac66"), hexc("3f506e"), hexc("c9b695")])

I.mark("table")
TX, TY = 0.9, -0.85
I.table(TX, TY, L=1.6, W=0.8, rot=0.0)
I.bench(TX, TY + 0.68, L=1.4)
I.stool(TX - 0.45, TY - 0.7)
I.stool(TX + 0.5, TY - 0.72)
I.candle(TX - 0.3, TY + 0.1, 0.76, h=0.16, energy=0.45)
I.candle(TX - 0.15, TY - 0.05, 0.76, h=0.1, energy=0.0)
I.plate(TX + 0.3, TY + 0.15, 0.76)
I.plate(TX - 0.5, TY - 0.2, 0.76, food=False)
I.mug(TX + 0.55, TY - 0.2, 0.76)
I.mug(TX + 0.05, TY + 0.25, 0.76)
I.lathe([(0, 0), (0.07, 0), (0.09, 0.05), (0.095, 0.11), (0.075, 0.18), (0.055, 0.22), (0.06, 0.25), (0, 0.25)],
        (TX + 0.15, TY - 0.2, 0.76), I.PL, hexc("b56a3e"), segs=10)          # jug
I.rug(0.9, -0.85, 1.35, 0.95, [hexc("6c7a52"), hexc("c9b695"), hexc("a33f2c"), hexc("d4ac66"), hexc("3a2c24")],
      rect=True)

I.mark("storage")
I.prop("barrel", (-2.95, -2.45, 0), rz=0.3, collide=True)
I.prop("barrel", (-2.25, -2.55, 0), rz=1.2, collide=True)
I.prop("sack_pile", (-2.3, 2.45, 0), rz=math.pi, s=0.7, collide=True)
I.prop("crate", (-3.0, -1.85 + 0.0, 0), rz=0.15, s=0.8)
I.mega("Bucket_Wooden_1", (-0.1, 1.55, 0), rz=0.4)
I.shelf("right", 1.1, 1.55, L=1.5, items="pots")
I.shelf("right", 1.1, 1.95, L=1.5, items="jars")
I.shelf("back", 1.0, 1.7, L=1.0, items="mixed")
I.mega("Peg_Rack", (hw - 0.06, -2.1, 1.55), rz=math.pi / 2)
I.lantern("left", -1.2, z=1.85, energy=0.45)

I.mark("herbs")
for hx in [-0.2, 0.2, 0.55, 0.9, 1.25, 1.6, -2.3, -2.0]:
    I.herbs(hx, -1.0 + j(0.04), H - 0.42)

I.mark("end")
I.rt_lights.append(("FireLight", tuple(FIRE), (1.0, 0.58, 0.3), 1.6, 6.0, True))
I.spawn = ((DOOR_X, -hd + 1.4, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.6, 1.0, 2.2), 0.0)
I.npc("NPC_Resident", (0.35, 1.0, 0), (-0.4, -1.0), look="Rogue_Hooded", anim="Idle", role="resident")
I.cam("a", (2.9, -2.6, 2.1), (-0.9, 1.6, 0.8), lens=18)
I.cam("b", (-2.9, 2.5, 2.2), (1.8, -1.6, 0.7), lens=18)
I.finish()
