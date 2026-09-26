"""Adventurer Guild quest board: framed plank board on two footed posts, carved
crest header, rank tabs (S A B C D E F) and pinned, rank-coloured commission
papers. Works standing on a porch or pushed against an interior wall.

Run: python3 make_guild_board.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres; 2.5 m wide, ~2.45 m tall, 0.6 m deep (feet). Origin at
ground centre. The papered face points Blender -Y (= Godot +Z). The back of the
board sits at y=+0.06, so it can be placed ~0.1 m from a wall.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("GuildBoard", seed=23)
WOOD = k.material("Wood", rough=0.8)
BOARD = k.material("Board", rough=0.9)
PAPER = k.material("Paper", rough=0.95, spec=0.2)
METAL = k.material("Metal", rough=0.35, metal=1.0)

dark = hexc("5a3a22")
mid = hexc("8a5f3a")
board_c = hexc("a0764a")
brass = hexc("c9a24a")
parch = hexc("efe3c4")

# Rank colours (tint + ribbon)
RANKS = [("S", hexc("e8b923")), ("A", hexc("c8372d")), ("B", hexc("8e4ec6")),
         ("C", hexc("2f7fd0")), ("D", hexc("3a9d4f")), ("E", hexc("b8743a")),
         ("F", hexc("9aa0a6"))]

W, H0, H1 = 2.3, 0.75, 2.05       # board width, bottom, top
BY = 0.02                          # board centre depth

# Posts with feet and caps
for x in (-1.22, 1.22):
    k.box((0.14, 0.14, 2.3), (x, BY, 1.15), WOOD, dark, bevel=0.02)
    k.box((0.16, 0.62, 0.12), (x, BY, 0.06), WOOD, dark, bevel=0.025)
    k.box((0.2, 0.2, 0.06), (x, BY, 2.33), WOOD, mid, bevel=0.015)
    k.sphere(0.07, (x, BY, 2.41), WOOD, mid, scale=(1, 1, 0.8), subdiv=1)
    for s in (-1, 1):  # small diagonal braces on the feet
        k.beam((x, BY + s * 0.28, 0.1), (x, BY + s * 0.04, 0.42), 0.06, WOOD, dark, bevel=0.01)

# Plank board (vertical planks, slightly uneven) + frame
n = 9
for i in range(n):
    x = -W / 2 + (i + 0.5) * W / n
    k.box((W / n - 0.008, 0.045, H1 - H0), (x, BY, (H0 + H1) / 2), BOARD,
          vary(board_c, 0.18, 0.08), bevel=0.006, jitter=0.003)
fr = 0.09
k.box((W + 0.22, 0.09, fr), (0, BY - 0.02, H1 + fr / 2), WOOD, dark, bevel=0.015)
k.box((W + 0.22, 0.09, fr), (0, BY - 0.02, H0 - fr / 2), WOOD, dark, bevel=0.015)
k.box((W + 0.3, 0.16, 0.05), (0, BY - 0.04, H0 - fr - 0.02), WOOD, mid, bevel=0.012)  # ledge
for x in (-W / 2 - 0.02, W / 2 + 0.02):
    k.box((fr, 0.09, H1 - H0), (x, BY - 0.02, (H0 + H1) / 2), WOOD, dark, bevel=0.015)

# Header: arched crest plate with shield + crossed swords
arch = [(-1.0, 0.0), (1.0, 0.0), (1.0, 0.16)]
for i in range(1, 12):
    a = i / 12 * math.pi
    arch.append((math.cos(a) * 1.0, 0.16 + math.sin(a) * 0.2))
arch.append((-1.0, 0.16))
k.prism(arch, 0.07, (0, BY - 0.01, H1 + fr), WOOD, mid, bevel=0.012)
shield = [(0, -0.2), (0.12, -0.12), (0.17, 0.02), (0.17, 0.14), (0, 0.18), (-0.17, 0.14),
          (-0.17, 0.02), (-0.12, -0.12)]
sz = H1 + fr + 0.2
k.prism([(x * 1.1, z * 1.1) for x, z in shield], 0.03, (0, BY - 0.06, sz), METAL, brass, bevel=0.008)
k.prism(shield, 0.03, (0, BY - 0.08, sz), WOOD, hexc("7a1f1a"), bevel=0.006)
for s in (-1, 1):  # crossed swords behind the shield, hilts up
    k.sword((s * 0.24, BY - 0.05, sz + 0.2), (0, s * 0.75, 0), METAL, METAL, length=0.9,
            hilt_c=brass, grip_c=hexc("3b2415"))

# Rank tabs along the top and pinned papers in 7 columns
cols = len(RANKS)
cw = W / cols
for ci, (rank, rc) in enumerate(RANKS):
    cx = -W / 2 + (ci + 0.5) * cw
    k.box((cw * 0.7, 0.02, 0.1), (cx, BY - 0.04, H1 - 0.08), WOOD, rc, bevel=0.008, var=0.02)
    k.box((0.02, 0.022, 0.05), (cx, BY - 0.052, H1 - 0.08), PAPER, (0.97, 0.94, 0.85), var=0)
    z = H1 - 0.25
    count = random.randint(2, 4) if rank not in ("S",) else 1
    for p in range(count):
        pw, ph = random.uniform(0.2, 0.26), random.uniform(0.24, 0.32)
        if z - ph < H0 + 0.05:
            break
        px = cx + random.uniform(-0.04, 0.04)
        pz = z - ph / 2
        rot = (0, random.uniform(-0.12, 0.12), 0)
        paper_c = mix(vary(parch, 0.05), rc, 0.18)
        k.box((pw, 0.006, ph), (px, BY - 0.028 - p * 0.001, pz), PAPER, paper_c, rot=rot, var=0.02)
        # rank ribbon band across the top of each paper + faint text lines
        k.quad(pw * 0.96, 0.035, (px, BY - 0.0318 - p * 0.001, pz + ph / 2 - 0.035), PAPER, rc,
               rot=rot, var=0.03)
        for li in range(3):
            lw = pw * random.uniform(0.45, 0.75)
            k.quad(lw, 0.012, (px - (pw - lw) * 0.35, BY - 0.0325 - p * 0.001, pz + ph * 0.18 - li * 0.055),
                   PAPER, hexc("6b5b48"), rot=rot, var=0.05)
        k.sphere(0.014, (px, BY - 0.04, pz + ph / 2 - 0.015), METAL, brass, subdiv=1)
        z -= ph + random.uniform(0.03, 0.06)

# A few loose tacked notes on the frame and a wax-sealed notice
k.box((0.18, 0.006, 0.12), (1.05, BY - 0.07, H0 - 0.02), PAPER, parch, rot=(0, 0.3, 0))

k.finish(cam_dir=(0.9, -1.8, 0.55), fit=0.95)
