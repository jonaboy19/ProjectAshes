"""Blacksmith's forge interior: a stone-floored workshop with a brick forge full of
glowing coals under a sooty hood, leather bellows, the anvil on its stump, a
quench trough, weapon racks and a wall of hung tools, a workbench, a grinding
wheel, coal, ingots, barrels and crates.

    blender -b --python make_interior_blacksmith.py -- [--no-preview]

-> kingdom/assets/generated/interiors/interior_blacksmith.glb
   kingdom/scenes/interiors/blacksmith_interior.tscn
   docs/kingdom/blender_previews/interior_blacksmith_a.png / _b.png
Room 10 x 8 m, ceiling 4.0 m; entrance door in the front wall (Godot +Z) at x = -2.5.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from interior_kit import *

I = Interior("blacksmith", seed=5202, title="Blacksmith")
k = I.k
W, D, H = 10.0, 8.0, 4.0
hw, hd = W / 2, D / 2
DOOR_X = -2.5
FX = 1.2                      # forge centre (x), against the back wall
BRICK = [hexc("8a4a32"), hexc("9a5a3a"), hexc("7a4230"), hexc("a0643f"), hexc("834a36")]


def soot(p):
    s = 0.0
    dx = abs(p.x - FX)
    if p.y > 1.5 and dx < 2.4:
        s = max(s, (1 - dx / 2.4) * clamp((p.z - 0.8) / 2.0) * 0.9)
    if p.z > 2.8:
        s = max(s, 0.45 * clamp((p.z - 2.8) / 1.2))
    return s


I.soot = soot
I.env["ambient_energy"] = 0.9

I.mark("shell")
I.room(W, D, H, doors={"front": [(DOOR_X, 1.4, 0, 2.4)]},
       windows={"front": [(2.2, 1.2, 1.4, 2.4)], "left": [(0.8, 1.0, 1.4, 2.3)], "right": [(1.8, 1.0, 1.4, 2.3)]},
       stone_base=1.0, posts=1.5)
I.flagstones(-hw, hw, -hd, hd, dark=lambda x, y: 0.35 * clamp(1 - math.hypot(x - FX, y - 2.6) / 3.0))
I.ceiling(-hw, hw, -hd, hd, H, beams_x=(-1.6, 1.4), joist_step=0.9, board_c=hexc("5e3f29"))
I.door("front", DOOR_X, 1.4, 2.4)
I.window("front", 2.2, 1.2, 1.4, 2.4, day=0.7)
I.window("left", 0.8, 1.0, 1.4, 2.3, day=0.6)
I.window("right", 1.8, 1.0, 1.4, 2.3, day=0.6)

I.mark("forge")
# --- the forge: brick block with a coal bed, back wall, hood and chimney
FY0, FY1, FZ = hd - 1.5, hd, 0.85            # block depth from the wall, bed height
FW = 2.5


def brick():
    return vary(random.choice(BRICK), 0.08, 0.03)


k.box((FW, FY1 - FY0, FZ), (FX, (FY0 + FY1) / 2, FZ / 2), I.PL, hexc("3a2a22"), var=0)
k.push((FX, FY0, 0))
k.grid_wall(FW, FZ, (0, -0.005, 0), I.PL, brick, bw=0.34, bh=0.14, gap=0.018, push=0.012)
k.pop()
for sx in (-1, 1):
    k.push((FX + sx * FW / 2, (FY0 + FY1) / 2, 0), (0, 0, -sx * math.pi / 2))
    k.grid_wall(FY1 - FY0, FZ, (0, -0.005, 0), I.PL, brick, bw=0.34, bh=0.14, gap=0.018, push=0.012)
    k.pop()
k.box((FW + 0.12, FY1 - FY0 + 0.06, 0.1), (FX, (FY0 + FY1) / 2 - 0.03, FZ + 0.03), I.PL, hexc("6f685e"), bevel=0.02)
# coal bed: a ring of stone edging, dark cinders, glowing coals
k.box((1.3, 0.9, 0.06), (FX, FY0 + 0.65, FZ + 0.1), I.PL, hexc("1e1814"), var=0)
for i in range(70):
    a = random.uniform(0, math.tau)
    rr = random.uniform(0, 1) ** 0.7
    x = FX + math.cos(a) * rr * 0.62
    y = FY0 + 0.65 + math.sin(a) * rr * 0.4
    s = random.uniform(0.035, 0.07)
    hot = rr < 0.75 and random.random() < 0.8
    col = random.choice([hexc("ff5a10"), hexc("ff7a1a"), hexc("e8400c"), hexc("ffa030")]) if hot else \
        random.choice([hexc("2a2220"), hexc("1d1715"), hexc("3a2e28")])
    k.sphere(s, (x, y, FZ + 0.13 + (1 - rr) * 0.05), I.GLOW if hot else I.PL, col, scale=(1.2, 1.0, 0.7), subdiv=0,
             noise_amt=s * 0.3, rot=(0, 0, a), grime=False, smooth=None)
# small flames licking up from the coals
FLAME = [(0, 0), (0.55, 0.04), (0.9, 0.16), (1.0, 0.3), (0.78, 0.5), (0.45, 0.72), (0.18, 0.9), (0, 1.0)]
for (dx, dy, hh, rr) in ((0.0, 0.0, 0.3, 0.08), (-0.2, 0.08, 0.2, 0.06), (0.22, -0.05, 0.22, 0.06), (0.05, 0.15, 0.16, 0.05)):
    I.lathe([(r * rr, z * hh) for r, z in FLAME], (FX + dx, FY0 + 0.65 + dy, FZ + 0.15), I.GLOW, hexc("ff8a2a"),
            segs=6, smooth=85, noise_amt=0.2 * rr, noise_scale=9, bend=(j(0.05), j(0.03)))
# brick back wall behind the bed, up to the hood
k.push((FX, FY1 - 0.02, 0), (0, 0, math.pi))
k.box((FW, 0.25, 1.1), (0, -0.1, FZ + 0.55), I.PL, hexc("2a201a"), var=0)
k.pop()
k.push((FX, FY1 - 0.26, FZ + 0.08))
k.grid_wall(FW - 0.2, 1.05, (0, 0, 0), I.PL, lambda: mix(brick(), hexc("201814"), 0.35), bw=0.34, bh=0.14, gap=0.018,
            push=0.01)
k.pop()
# hood: tapered sooty plaster funnel from 2.1 m up into the ceiling, with an oak lintel
HZ = 2.1
t = bmesh.new()
bmesh.ops.create_cube(t, size=1.0)
for v in t.verts:
    top = v.co.z > 0
    hw_ = 0.55 if top else FW / 2 + 0.15
    y0 = FY1 - 0.9 if top else FY0 - 0.15
    v.co = Vector((FX + math.copysign(hw_, v.co.x), y0 if v.co.y < 0 else FY1, H if top else HZ))
bmesh.ops.subdivide_edges(t, edges=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) > 0.5], cuts=5)
bmesh.ops.subdivide_edges(t, edges=[e for e in t.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 0.01
                                    and (e.verts[0].co - e.verts[1].co).length > 1.0], cuts=4)
k._merge(t, I.PL, (1, 1, 1), None, 50, 0.0, None, False,
         loop_fn=lambda l: mix(I.plaster_col(l.vert.co), hexc("231c17"), 0.35 + 0.35 * clamp((l.vert.co.z - HZ) / 1.5)))
k.box((FW + 0.4, 0.26, 0.24), (FX, FY0 - 0.1, HZ - 0.05), I.WOOD, hexc("3d2819"), bevel=0.02)
for sx in (-1, 1):
    k.box((0.24, 0.24, HZ - FZ - 0.05), (FX + sx * (FW / 2 + 0.05), FY0 - 0.1, (HZ + FZ) / 2 - 0.05), I.WOOD,
          hexc("3d2819"), bevel=0.02)
# tools on the forge rim: tongs, poker, a glowing bar in the coals
for (a, b, c) in (((FX + 0.9, FY0 + 0.1, FZ + 0.09), (FX + 0.35, FY0 + 0.6, FZ + 0.16), IRON),
                  ((FX - 0.95, FY0 + 0.15, FZ + 0.09), (FX - 0.3, FY0 + 0.75, FZ + 0.18), IRON)):
    k.beam(a, b, 0.022, I.PL, c, bevel=0)
k.beam((FX + 0.05, FY0 + 0.25, FZ + 0.2), (FX + 0.3, FY0 + 0.7, FZ + 0.18), 0.03, I.GLOW, hexc("ffb040"), bevel=0)
I.collide((FX, (FY0 + FY1) / 2, FZ / 2 + 0.2), (FW + 0.2, FY1 - FY0 + 0.1, FZ + 0.4))

I.mark("bellows")
# leather bellows on a frame to the left of the forge, nozzle into the coals
BX, BY = FX - FW / 2 - 0.75, FY0 + 0.7
k.push((BX, BY, 0.75), (0, 0, 0.0))
for sy in (-1, 1):
    k.box((0.07, 0.07, 0.75), (-0.35, sy * 0.3, -0.375), I.WOOD, TIMBER, bevel=0.01)
    k.box((0.07, 0.07, 0.75), (0.35, sy * 0.3, -0.375), I.WOOD, TIMBER, bevel=0.01)
k.box((0.8, 0.07, 0.07), (0, -0.3, -0.5), I.WOOD, TIMBER, bevel=0.01)
k.box((0.8, 0.07, 0.07), (0, 0.3, -0.5), I.WOOD, TIMBER, bevel=0.01)
k.prism([(-0.5, -0.32), (0.4, -0.18), (0.4, 0.18), (-0.5, 0.32)], 0.04, (0, 0, 0.02), I.WOOD, OAK,
        rot=(math.pi / 2, 0, 0), bevel=0.008)
k.prism([(-0.5, -0.32), (0.4, -0.18), (0.4, 0.18), (-0.5, 0.32)], 0.04, (0, 0, 0.32), I.WOOD, OAK,
        rot=(math.pi / 2 - 0.12, 0, 0), bevel=0.008)
t = bmesh.new()
bot = [(-0.48, -0.3, 0.05), (0.38, -0.16, 0.05), (0.38, 0.16, 0.05), (-0.48, 0.3, 0.05)]
top = [(-0.48, -0.3, 0.3), (0.38, -0.16, 0.26), (0.38, 0.16, 0.26), (-0.48, 0.3, 0.3)]
rings = []
for i in range(5):
    f = i / 4
    bulge = 1.0 + 0.12 * math.sin(f * math.pi)
    rings.append([t.verts.new((p[0], p[1] * bulge, p[2] + (q[2] - p[2]) * f)) for p, q in zip(bot, top)])
for i in range(4):
    for s in range(4):
        s2 = (s + 1) % 4
        t.faces.new((rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s]))
bmesh.ops.recalc_face_normals(t, faces=t.faces[:])
k._merge(t, I.PL, hexc("5a3a26"), None, 30, 0.04, None, True)
k.pop()
k.cyl(0.05, 0.8, (BX + 0.4, BY, 0.9), I.PL, IRON, rot=(0, math.pi / 2 + 0.25, 0), segs=8, r2=0.035)
k.beam((BX - 0.45, BY, 1.1), (BX - 0.1, BY, 2.0), 0.05, I.WOOD, TIMBER, bevel=0.008)   # lever
k.beam((BX - 0.1, BY, 2.0), (BX + 0.5, BY - 0.2, 1.95), 0.05, I.WOOD, TIMBER, bevel=0.008)
k.tube([(BX - 0.4, BY, 1.1), (BX - 0.42, BY, 1.4), (BX - 0.3, BY, 1.9)], [0.01] * 3, I.PL, hexc("8a6a40"), segs=4,
       point_end=False)
I.collide((BX, BY, 0.6), (0.9, 0.8, 1.2))

I.mark("anvil, trough")
AX, AY = 1.0, 1.2
I.prop("anvil_stump", (AX, AY, 0), rz=math.pi + 0.15, collide=True)
I.prop("water_trough", (FX + FW / 2 + 0.95, 1.9, 0), rz=math.pi / 2, s=0.85, collide=True)
# coal heap and a scuttle
for i in range(40):
    a = random.uniform(0, math.tau)
    rr = random.uniform(0, 1) ** 0.6
    s = random.uniform(0.05, 0.1)
    k.sphere(s, (-2.2 + math.cos(a) * rr * 0.6, hd - 0.55 + math.sin(a) * rr * 0.4, (1 - rr) * 0.3 + 0.02), I.PL,
             random.choice([hexc("2a2422"), hexc("1f1b19"), hexc("35302c")]), subdiv=0, noise_amt=s * 0.3, grime=False,
             smooth=None, rot=(0, 0, a))
I.mega("Bucket_Metal", (-1.4, hd - 0.5, 0), rz=0.6)
I.collide((-2.2, hd - 0.55, 0.2), (1.2, 0.8, 0.4))

I.mark("tool wall")
# hung tools on a board on the back wall (left of the forge): hammers, tongs, files
m = I.wall_frame("back")
bx = m(-3.4)
k.box((2.2, 0.05, 1.1), (bx, -0.03, 1.95), I.WOOD, OAK_D, bevel=0.01)
for i in range(9):
    x = bx - 0.95 + i * 0.24
    k.box((0.03, 0.08, 0.03), (x, -0.08, 2.35), I.WOOD, TIMBER, var=0)
    kind = i % 3
    if kind == 0:      # hammer
        k.box((0.03, 0.03, 0.45), (x, -0.1, 2.1), I.WOOD, HONEY, var=0.05)
        k.box((0.14, 0.05, 0.06), (x, -0.1, 1.88), I.PL, IRON, var=0.05)
    elif kind == 1:    # tongs
        k.beam((x - 0.03, -0.1, 2.32), (x - 0.01, -0.1, 1.75), 0.018, I.PL, IRON, bevel=0)
        k.beam((x + 0.03, -0.1, 2.32), (x + 0.01, -0.1, 1.75), 0.018, I.PL, IRON, bevel=0)
    else:              # file / chisel
        k.box((0.025, 0.02, 0.35), (x, -0.1, 2.12), I.PL, hexc("4a4642"), var=0.05)
        k.box((0.04, 0.035, 0.12), (x, -0.1, 2.33), I.WOOD, HONEY, var=0.05)
k.pop()
I.shelf("back", -3.4, 2.75, L=2.0, items="pots")

I.mark("weapons")
I.prop("weapon_rack", (-hw + 0.6, 1.2, 0), rz=-math.pi / 2, s=0.9, collide=True)
I.mega("WeaponStand", (-hw + 0.75, -1.4, 0), rz=-math.pi / 2, collide=True)
for (y, z, kind) in ((-0.2, 2.5, "shield"), (-1.0, 2.4, "sword"), (-1.6, 2.4, "sword"), (-2.4, 2.5, "shield")):
    if kind == "shield":
        I.mega("Shield_Wooden", (-hw + 0.12, y, z - 0.3), rot=(0, 0, math.pi / 2))
    else:
        I.mega("Sword_Bronze", (-hw + 0.08, y, z - 0.55), rot=(0, 0, math.pi / 2), s=0.95)

# a barrel of blades by the door and a crate
I.prop("barrel", (-hw + 0.55, -hd + 0.6, 0), rz=0.3, collide=True)
for (dx, dy, rz) in ((0.02, 0.12, 2.4), (-0.1, -0.1, 0.9)):
    k.sword((-hw + 0.55 + dx, -hd + 0.6 + dy, 1.35), (j(0.12), j(0.12), rz), I.PL, I.WOOD, length=0.95,
            blade_c=hexc("a8a49c"), hilt_c=hexc("8a6a3a"), grip_c=hexc("4a2e1c"))
for i, (dx, dy, rz) in enumerate(((-0.08, 0.05, 0.2), (0.1, -0.06, 1.3))):
    I.mega("Sword_Bronze", (-hw + 0.55 + dx, -hd + 0.6 + dy, 0.62), rot=(j(0.15), j(0.15), rz), s=0.85)
I.prop("crate", (-hw + 0.5, -hd + 1.35, 0), rz=0.25, s=0.85, collide=True)
# finished work laid out on a table under the front window
I.table(2.2, -hd + 0.55, L=1.3, W=0.55, h=0.8)
I.mega("Sword_Bronze", (1.9, -hd + 0.5, 0.82), rot=(0, math.pi / 2, 0.1), s=0.9)
I.mega("Sword_Bronze", (2.3, -hd + 0.6, 0.82), rot=(0, math.pi / 2, -0.15), s=0.9)
I.mega("Axe_Bronze", (2.65, -hd + 0.5, 0.82), rot=(0, math.pi / 2, 0.4), s=0.8)
I.mega("Shield_Wooden", (1.35, -hd + 0.4, 0.0), rot=(0.2, 0, math.pi), s=0.9)
# horseshoes and a hook on the hood lintel, a chain from the beam
for i in range(5):
    k.ring(0.045, 0.06, 0.015, (FX - 0.8 + i * 0.4, FY0 - 0.26, HZ - 0.3), I.PL, IRON, segs=8)
    k.box((0.012, 0.012, 0.12), (FX - 0.8 + i * 0.4, FY0 - 0.25, HZ - 0.2), I.PL, IRON, var=0)

I.mark("workbench")
I.mega("Workbench", (hw - 0.6, -1.5, 0), rz=math.pi / 2, collide=True)
I.mega("Pickaxe_Bronze", (hw - 0.55, -1.0, 0.89), rot=(0, math.pi / 2, 0.3), s=0.8)
I.mega("Axe_Bronze", (hw - 0.6, -2.0, 0.93), rot=(0, math.pi / 2, math.pi / 2), s=0.9)
for i in range(6):                      # iron ingots
    k.box((0.24, 0.09, 0.05), (hw - 0.62 + (i % 3) * 0.0, -1.55 + (i % 3) * 0.1, 0.915 + (i // 3) * 0.052), I.PL,
          vary(hexc("4c4844"), 0.08), bevel=0.012, rot=(0, 0, (i // 3) * math.pi / 2))
I.mega("Whetstone", (-1.9, -2.6, 0), rz=0.4, collide=True)
I.prop("barrel", (hw - 0.55, -hd + 0.55, 0), rz=0.4, collide=True)
I.prop("barrel", (hw - 1.25, -hd + 0.5, 0), rz=1.4, collide=True)
I.prop("crate_stack", (hw - 0.8, 0.2, 0), rz=math.pi / 2, s=0.8, collide=True)
I.prop("woodpile", (-hw + 1.4, hd - 0.5, 0), rz=math.pi, s=0.8, collide=True)
I.lantern("front", 0.2, z=2.2, energy=0.8)
I.lantern("right", -2.6, z=2.3, energy=0.6)

I.mark("end")
FIRE = (FX, FY0 + 0.4, FZ + 0.5)
I.bake.append((Vector(FIRE), (1.0, 0.5, 0.18), 3.2, 8.5))
I.bake.append((Vector((FX, FY0 + 0.65, FZ + 0.35)), (1.0, 0.4, 0.12), 1.6, 3.5))
I.rt_lights.append(("ForgeLight", (FX, FY0 - 0.2, FZ + 0.7), (1.0, 0.5, 0.2), 2.2, 7.5, True))
I.spawn = ((DOOR_X, -hd + 1.5, 0.05), 0.0)
I.exit_door = ((DOOR_X, -hd + 0.45, 0.0), (1.9, 1.0, 2.4), 0.0)
I.npc("NPC_Blacksmith", (AX + 0.05, AY - 0.75, 0), (0, 1), look="Barbarian", height=1.85, anim="Idle",
      role="blacksmith")
I.cam("a", (-3.6, -3.2, 2.5), (1.2, 2.8, 0.9), lens=18)
I.cam("b", (4.4, -3.5, 2.6), (-1.6, 2.4, 0.9), lens=18)
I.finish()
