"""Heavenly Mist Sect Meditation Chamber (Wuxia / Cultivation Faction Interior)
Taoist cultivation hall for the Mount Taiyun Heavenly Mist Sect.
Features:
- Raised central meditation dais with woven rush matting and spirit incense burner
- Wall calligraphy scrolls and cultivation scripture banners
- Martial dao & jian sword rack stands and training dummies
- Low cedar tea ceremony table with porcelain tea bowls and steaming teapot
- Ethereal jade-mist lantern illumination and meditation cushions

Run:
    blender -b --python kingdom/tools/blender/make_interior_sect.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("sect", seed=9903, title="Heavenly Mist Cultivation Hall")
k = I.k
W, D, H = 8.5, 8.5, 3.6
hw, hd = W / 2, D / 2
DOOR_X = 0.0

def soot(p):
    # Pure meditation hall, minimal hearth smoke, faint incense residue high up
    if p.z > 3.2:
        return 0.1 * clamp((p.z - 3.2) / 0.4)
    return 0.0

I.soot = soot
I.env["ambient_energy"] = 1.15
I.env["exposure"] = 1.1

I.mark("shell")
I.room(W, D, H,
       doors={"front": [(DOOR_X, 1.4, 0, 2.4)]},
       windows={
           "front": [(-2.6, 1.2, 1.1, 2.3), (2.6, 1.2, 1.1, 2.3)],
           "left": [(-1.8, 1.2, 1.1, 2.3), (1.8, 1.2, 1.1, 2.3)],
           "right": [(-1.8, 1.2, 1.1, 2.3), (1.8, 1.2, 1.1, 2.3)]
       },
       posts=1.4)

# Light cedar / bamboo style planks
I.planks(-hw, hw, -hd, hd, along="x",
         palette=[hexc("c4a275"), hexc("b8966b"), hexc("d2b285"), hexc("ae8c61")])

I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-2.0, 2.0), joist_step=0.8,
          board_c=hexc("96724a"))

I.door("front", DOOR_X, 1.4, 2.4)
I.window("front", -2.6, 1.2, 1.1, 2.3, day=0.85)
I.window("front", 2.6, 1.2, 1.1, 2.3, day=0.85)
I.window("left", -1.8, 1.2, 1.1, 2.3, day=0.8)
I.window("left", 1.8, 1.2, 1.1, 2.3, day=0.8)
I.window("right", -1.8, 1.2, 1.1, 2.3, day=0.8)
I.window("right", 1.8, 1.2, 1.1, 2.3, day=0.8)

I.mark("central meditation dais")
# Woven rush meditation dais (concentric green/gold woven mats)
I.rug(0.0, 0.4, 1.6, 1.6, [hexc("526d4e"), hexc("a89c67"), hexc("3f543c"), hexc("c4b882")], rect=True)
I.rug(0.0, 0.4, 0.9, 0.9, [hexc("2e402c"), hexc("e6db9a")], rect=False)

# Bronze incense censer at center-front of dais
I.mega("Cauldron", (0.0, -0.7, 0), s=0.45, collide=True)
I.light((0.0, -0.7, 0.35), colour=(0.6, 0.9, 1.0), energy=0.8, radius=3.5)

I.mark("cultivation scrolls & banners")
# Calligraphy banners on back wall
I.banner("back", -2.2, 3.3, w=0.8, h=2.0, cloth=hexc("1e3d59"), trim=hexc("e8d082"), emblem="star")
I.banner("back", 0.0, 3.4, w=1.0, h=2.2, cloth=hexc("2b4b45"), trim=hexc("f2d679"), emblem="leaf")
I.banner("back", 2.2, 3.3, w=0.8, h=2.0, cloth=hexc("1e3d59"), trim=hexc("e8d082"), emblem="star")

# Altar table below central banner
I.mega("Workbench", (0.0, hd - 0.5, 0), rz=0.0, s=1.1, collide=True)
I.mega("Scroll_1", (-0.6, hd - 0.5, 0.88), rz=0.1, s=1.0)
I.mega("Scroll_2", (0.6, hd - 0.5, 0.88), rz=-0.2, s=1.0)
I.mega("CandleStick_Stand", (-1.2, hd - 0.5, 0.88), s=0.9)
I.mega("CandleStick_Stand", (1.2, hd - 0.5, 0.88), s=0.9)
I.candle(-1.2, hd - 0.5, 1.45, h=0.12, holder=False, energy=0.45)
I.candle(1.2, hd - 0.5, 1.45, h=0.12, holder=False, energy=0.45)

I.mark("martial weapon displays")
# Left training wing: Dao & Jian sword stands and training dummy
I.mega("WeaponStand", (-hw + 0.45, 0.5, 0), rz=math.pi / 2, s=1.1, collide=True)
I.mega("WeaponStand", (-hw + 0.45, -1.2, 0), rz=math.pi / 2, s=1.1, collide=True)
I.mega("Dummy", (-hw + 0.9, 2.0, 0), rz=math.pi / 3, s=1.0, collide=True)

I.mark("tea ceremony wing")
# Right wing: low tea table with porcelain cups and bench
TX, TY = 2.4, -0.5
I.mega("Table_Large", (TX, TY, -0.2), rz=0.0, s=0.85, collide=True)
I.rug(TX, TY, 1.4, 1.0, [hexc("3e5c46"), hexc("c4b276"), hexc("2b4031")], rect=True)
I.mega("Chalice", (TX - 0.35, TY, 0.55), s=0.7)
I.mega("Chalice", (TX + 0.35, TY, 0.55), s=0.7)
# Ceramic tea pot
I.lathe([(0, 0), (0.08, 0), (0.11, 0.06), (0.1, 0.12), (0.06, 0.16), (0.03, 0.18), (0, 0.18)],
        (TX, TY, 0.55), I.PL, hexc("2d4a3e"), segs=10)

I.mark("ancient scriptures")
I.mega("Bookcase_2", (hw - 0.4, 1.8, 0), rz=-math.pi / 2, s=1.0, collide=True)
I.mega("BookStand", (hw - 1.0, 1.8, 0), rz=-math.pi / 2, s=0.95, collide=True)

I.mark("lighting & mist")
# Ethereal lanterns
I.lantern("left", -0.5, z=2.1, energy=0.6)
I.lantern("right", 0.5, z=2.1, energy=0.6)
I.lantern("left", 1.8, z=2.1, energy=0.6)
I.lantern("right", -1.8, z=2.1, energy=0.6)

# Realtime qi glow
I.rt_lights.append(("QiMistGlow", (0.0, 0.0, 0.4), (0.7, 0.85, 1.0), 1.2, 5.5, False))

I.mark("exit & markers")
I.spawn = ((DOOR_X, -hd + 1.4, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.6, 1.0, 2.4), 0.0)
I.npc("NPC_Elder_Taiyun", (0.0, 0.5, 0.02), (0.0, -1.0), look="Mage_Male", anim="Idle", role="sect_elder")

I.cam("a", (0.0, -3.4, 1.9), (0.0, 0.8, 1.0), lens=20)
I.cam("b", (3.2, -2.6, 2.2), (-1.0, 0.8, 1.0), lens=20)
I.cam("c", (-3.2, 2.4, 2.2), (1.0, -0.6, 1.0), lens=20)

I.finish()
