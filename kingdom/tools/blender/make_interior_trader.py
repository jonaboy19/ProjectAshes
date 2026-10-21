"""Merchant Trader Shop Interior (Rising Ashes / Valencious Region)
Enterable merchant shop and trading post for market towns and rural crossroads.
Features:
- L-shaped merchant sales counter with ledger, trade scales, gold coins and keys
- Back-wall apothecary and fine potion shelves (healing elixirs, crystal vials, urns)
- Trade goods stacks: produce crates, spice bags, apple barrels, metal lockboxes
- Display stalls, bolts of cloth, coiled climbing ropes, and merchant strongbox
- Warm lantern lighting and central chandelier

Run:
    blender -b --python kingdom/tools/blender/make_interior_trader.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("trader", seed=5522, title="Trader's Post")
k = I.k
W, D, H = 8.0, 6.5, 3.2
hw, hd = W / 2, D / 2
DOOR_X = 0.0

def soot(p):
    if p.z > 2.8:
        return 0.18 * clamp((p.z - 2.8) / 0.4)
    return 0.0

I.soot = soot
I.env["ambient_energy"] = 1.0

I.mark("shell")
I.room(W, D, H,
       doors={"front": [(DOOR_X, 1.2, 0, 2.2)]},
       windows={
           "front": [(-2.2, 1.1, 1.1, 2.1), (2.2, 1.1, 1.1, 2.1)],
           "left": [(0.0, 1.1, 1.1, 2.1)],
           "right": [(0.0, 1.1, 1.1, 2.1)]
       },
       posts=1.3)

I.planks(-hw, hw, -hd, hd, along="y",
         palette=[hexc("704d2e"), hexc("613f24"), hexc("825b36"), hexc("56371f")],
         dark=lambda x, y: 0.15 if (abs(x) < 1.0 and y < -1.5) else 0.0)

I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-1.6, 1.6), joist_step=0.75)
I.door("front", DOOR_X, 1.2, 2.2)
I.window("front", -2.2, 1.1, 1.1, 2.1, day=0.8)
I.window("front", 2.2, 1.1, 1.1, 2.1, day=0.8)
I.window("left", 0.0, 1.1, 1.1, 2.1, day=0.7)
I.window("right", 0.0, 1.1, 1.1, 2.1, day=0.7)

I.mark("merchant sales counter")
# Front L-shaped service counter
I.mega("Workbench_Drawers", (-0.8, -0.4, 0), rz=0.0, s=1.1, collide=True)
I.mega("Workbench", (0.8, -0.4, 0), rz=0.0, s=1.1, collide=True)
I.mega("Workbench", (1.75, 0.45, 0), rz=math.pi / 2, s=1.1, collide=True)

# Items on counter: ledger, coins, keys, scales
I.mega("Scroll_2", (-0.6, -0.4, 0.88), rz=0.2, s=0.9)
I.mega("Coin_Pile", (-0.2, -0.4, 0.88), s=1.1)
I.mega("Coin_Pile_2", (0.2, -0.4, 0.88), s=0.9)
I.mega("Key_Gold", (0.5, -0.4, 0.88), rz=0.5, s=1.2)
I.mega("Pouch_Large", (-1.2, -0.4, 0.88), rz=0.3, s=1.0)
I.candle(1.1, -0.4, 0.88, h=0.15, energy=0.5)

I.mark("back apothecary & goods shelves")
# Large shelves on back wall
I.mega("Bookcase_2", (-2.6, hd - 0.35, 0), rz=0.0, s=1.0, collide=True)
I.mega("Bookcase_2", (2.6, hd - 0.35, 0), rz=0.0, s=1.0, collide=True)
I.mega("Shelf_Small_Bottles", (-0.8, hd - 0.25, 1.4), rz=0.0, s=1.1)
I.mega("Shelf_Small_Bottles", (0.8, hd - 0.25, 1.4), rz=0.0, s=1.1)
I.shelf("back", 0.0, 2.1, L=2.2, items="jars")

# Potions and display bottles
I.mega("Potion_1", (-2.4, hd - 0.35, 0.9), s=1.0)
I.mega("Potion_2", (-2.2, hd - 0.35, 0.9), s=1.0)
I.mega("Potion_4", (-2.8, hd - 0.35, 0.9), s=1.0)
I.mega("Vase_2", (2.4, hd - 0.35, 0.9), s=1.0)
I.mega("Vase_4", (2.8, hd - 0.35, 0.9), s=1.0)

I.mark("produce & storage stacks")
I.mega("FarmCrate_Apple", (-hw + 0.8, -1.8, 0), rz=0.1, s=1.0, collide=True)
I.mega("FarmCrate_Carrot", (-hw + 0.8, -1.0, 0), rz=-0.15, s=1.0, collide=True)
I.mega("FarmCrate_Empty", (-hw + 0.8, -1.0, 0.38), rz=0.2, s=1.0)
I.mega("Barrel_Apples", (-hw + 0.7, 0.2, 0), s=1.0, collide=True)
I.mega("Bag", (-hw + 0.6, 1.1, 0), rz=0.4, s=1.1, collide=True)
I.mega("Bag", (-hw + 0.7, 1.6, 0), rz=-0.3, s=1.0, collide=True)
I.mega("Rope_1", (-hw + 0.6, 2.2, 0), s=1.1)

# Merchant treasury / vault corner
I.mega("Chest_Wood", (hw - 0.7, 2.2, 0), rz=math.pi / 4, s=1.05, collide=True)
I.mega("Crate_Metal", (hw - 0.8, 1.4, 0), rz=0.1, s=1.0, collide=True)
I.mega("Crate_Wooden", (hw - 0.8, 0.7, 0), rz=-0.2, s=1.0, collide=True)

# Customer seating & rug
I.rug(0.0, -1.5, 1.4, 1.0, [hexc("2e4a3e"), hexc("c4a052"), hexc("783424"), hexc("41544a")], rect=True)
I.mega("Bench", (-1.8, -hd + 0.65, 0), rz=0.0, s=1.0, collide=True)

I.mark("lighting & decoration")
I.chandelier(0.0, 0.2, H, r=0.65, n=6, drop=0.8, energy=1.8, radius=7.5)
I.lantern("left", 0.0, z=1.9, energy=0.6)
I.lantern("right", 0.0, z=1.9, energy=0.6)

# Dried herbs hanging from trade beams
for hx in [-1.5, -0.6, 0.6, 1.5]:
    I.herbs(hx, 0.2 + j(0.05), H - 0.4)

I.mark("exit & markers")
I.spawn = ((DOOR_X, -hd + 1.2, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.5, 1.0, 2.2), 0.0)
I.npc("NPC_Shopkeeper", (0.0, 0.5, 0), (0.0, -1.0), look="Merchant_Male", anim="Idle", role="shopkeeper")

I.cam("a", (2.8, -2.4, 2.0), (-0.8, 0.8, 0.9), lens=20)
I.cam("b", (-2.7, -2.3, 2.0), (0.8, 0.8, 0.9), lens=20)
I.cam("c", (0.0, 2.6, 2.1), (0.0, -1.2, 0.8), lens=22)

I.finish()
