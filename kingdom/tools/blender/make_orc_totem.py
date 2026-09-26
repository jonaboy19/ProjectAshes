"""Orc tribe totem: a carved, war-painted log with three stacked spirit faces
(orc chief with tusks, snarling wolf, spread-winged storm bird), crowned by a
horned beast skull with hanging feathers and bone charms, on a rock cairn.

Run: python3 make_orc_totem.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. ~4.6 m tall, wings span ~3.2 m, cairn ~1.6 m across.
Origin at ground centre. Carved faces look toward Blender -Y = Godot +Z.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix

k = Kit("OrcTotem", seed=13)
WOOD = k.material("Wood", rough=0.82)
PAINT = k.material("Paint", rough=0.7)
BONE = k.material("Bone", rough=0.6, spec=0.45)
STONE = k.material("Stone", rough=0.95)
CLOTH = k.material("Cloth", rough=0.95, spec=0.2)

LOG = hexc("7a5a3e")
RED = hexc("a8322a")
BLACK = hexc("25201c")
WHITE = hexc("e6dcc8")
OCHRE = hexc("c08a3a")
R = 0.42
FY = -R + 0.03          # front surface of the pole
LOG_L = mix(LOG, WHITE, 0.12)

# Rock cairn
for i in range(7):
    a = i / 7 * math.tau + random.uniform(-0.2, 0.2)
    rr = random.uniform(0.62, 0.85)
    k.sphere(random.uniform(0.22, 0.32), (math.cos(a) * rr, math.sin(a) * rr, 0.06), STONE,
             vary(random.choice([hexc("7c776d"), hexc("8e887c"), hexc("6b675f")]), 0.08),
             scale=(1.3, 1.0, 0.6), subdiv=1, noise_amt=0.08, rot=(0, 0, random.uniform(0, 3)))
for i in range(3):
    a = i / 3 * math.tau + 0.4
    k.sphere(0.28, (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.26), STONE, vary(hexc("858074"), 0.08),
             scale=(1.2, 1.0, 0.75), subdiv=1, noise_amt=0.06)

# Pole
k.log((0, 0, 0.0), (0, 0, 3.8), R, WOOD, LOG, segs=12, r_end=R * 0.88, noise_amt=0.02)
for z, c in ((0.6, BLACK), (1.72, RED), (2.84, BLACK)):   # carved, painted bands
    k.cyl(R + 0.06, 0.12, (0, 0, z - 0.06), PAINT, c, segs=14, caps=False, smooth=40)
    k.cyl(R + 0.045, 0.035, (0, 0, z + 0.07), PAINT, WHITE, segs=14, caps=False, smooth=40)

def mask(z0, w, h, outline, depth=0.2, color=LOG_L):
    pts = [(x * w / 2, z * h) for x, z in outline]
    k.prism(pts, depth, (0, FY - depth / 2 + 0.06, z0), WOOD, color, bevel=0.03)
    return FY - depth + 0.06          # front plane of the mask

# --- face 1: orc chief (z 0.72 - 1.66)
z0 = 0.72
fr = mask(z0, 0.86, 0.92, [(-0.8, 0.0), (0.8, 0.0), (1.0, 0.3), (0.95, 0.75), (0.7, 1.0), (-0.7, 1.0),
                           (-0.95, 0.75), (-1.0, 0.3)])
k.box((0.9, 0.2, 0.17), (0, fr + 0.02, z0 + 0.78), WOOD, mix(LOG, BLACK, 0.25), bevel=0.05, rot=(0.15, 0, 0))   # brow
for sx in (-1, 1):
    k.sphere(0.1, (sx * 0.19, fr + 0.01, z0 + 0.63), PAINT, BLACK, scale=(1.25, 0.5, 0.75), subdiv=1)       # sockets
    k.sphere(0.04, (sx * 0.19, fr - 0.035, z0 + 0.63), PAINT, hexc("f0c040"), subdiv=1)                   # eyes
    k.box((0.08, 0.02, 0.42), (sx * 0.3, fr - 0.005, z0 + 0.4), PAINT, RED, rot=(0, sx * 0.3, 0))          # paint
    k.box((0.06, 0.02, 0.3), (sx * 0.39, fr + 0.01, z0 + 0.36), PAINT, RED, rot=(0, sx * 0.3, 0))
    k.tube([(sx * 0.2, fr - 0.1, z0 + 0.14), (sx * 0.26, fr - 0.2, z0 + 0.3), (sx * 0.25, fr - 0.22, z0 + 0.5),
            (sx * 0.21, fr - 0.18, z0 + 0.6)], [0.065, 0.05, 0.03, 0.0], BONE, WHITE, segs=8)          # tusks
k.prism([(-0.13, 0), (0.13, 0), (0.07, 0.3), (-0.07, 0.3)], 0.17, (0, fr - 0.06, z0 + 0.33), WOOD,
        mix(LOG, BLACK, 0.1), bevel=0.0)                                                               # nose
k.box((0.56, 0.22, 0.18), (0, fr - 0.07, z0 + 0.13), WOOD, mix(LOG, BLACK, 0.35), bevel=0.04)          # jaw
k.box((0.44, 0.05, 0.07), (0, fr - 0.18, z0 + 0.2), BONE, WHITE, bevel=0.01)                          # teeth
for i in range(4):
    k.box((0.012, 0.055, 0.075), (-0.15 + i * 0.1, fr - 0.19, z0 + 0.2), PAINT, BLACK)

# --- face 2: snarling wolf (z 1.84 - 2.76)
z0 = 1.84
fr = mask(z0, 0.8, 0.86, [(-0.6, 0.0), (0.6, 0.0), (1.0, 0.45), (0.9, 0.85), (0.5, 1.0), (-0.5, 1.0),
                          (-0.9, 0.85), (-1.0, 0.45)])
k.prism([(-0.19, 0), (0.19, 0), (0.12, 0.22), (-0.12, 0.22)], 0.42, (0, fr - 0.2, z0 + 0.32), WOOD, LOG_L,
        rot=(math.pi / 2, 0, 0), bevel=0.03)                                                           # snout
k.box((0.34, 0.36, 0.09), (0, fr - 0.2, z0 + 0.24), PAINT, WHITE, bevel=0.03)                          # lower jaw
k.sphere(0.075, (0, fr - 0.41, z0 + 0.45), PAINT, BLACK, scale=(1.2, 1, 0.8), subdiv=1)               # nose
for i in range(5):
    k.cyl(0.022, 0.08, (-0.12 + i * 0.06, fr - 0.36, z0 + 0.33), BONE, WHITE, segs=4, r2=0.0, rot=(math.pi, 0, 0))
    k.cyl(0.02, 0.06, (-0.1 + i * 0.05, fr - 0.36, z0 + 0.28), BONE, WHITE, segs=4, r2=0.0)
for sx in (-1, 1):
    k.sphere(0.085, (sx * 0.18, fr + 0.0, z0 + 0.62), PAINT, WHITE, scale=(1.5, 0.5, 0.7), subdiv=1)
    k.sphere(0.045, (sx * 0.18, fr - 0.04, z0 + 0.62), PAINT, BLACK, subdiv=1)
    k.box((0.3, 0.06, 0.06), (sx * 0.17, fr - 0.02, z0 + 0.73), WOOD, mix(LOG, BLACK, 0.3), rot=(0, sx * 0.35, 0))
    k.prism([(-0.13, 0), (0.13, 0), (0.02, 0.4)], 0.1, (sx * 0.3, FY + 0.05, z0 + 0.8), WOOD, LOG_L,
            rot=(0, sx * 0.35, 0), bevel=0.0)                                                           # ears
    k.prism([(-0.07, 0), (0.07, 0), (0.01, 0.24)], 0.02, (sx * 0.3, FY - 0.01, z0 + 0.84), PAINT, RED,
            rot=(0, sx * 0.35, 0))
    k.box((0.2, 0.02, 0.05), (sx * 0.28, fr - 0.01, z0 + 0.35), PAINT, BLACK, rot=(0, -sx * 0.4, 0))  # whisker paint

# --- face 3: storm bird with spread wings (z 2.96 - 3.76)
z0 = 2.96
fr = mask(z0, 0.74, 0.78, [(-0.7, 0.0), (0.7, 0.0), (1.0, 0.5), (0.7, 1.0), (-0.7, 1.0), (-1.0, 0.5)])
k.tube([(0, fr + 0.02, z0 + 0.52), (0, fr - 0.2, z0 + 0.5), (0, fr - 0.33, z0 + 0.38), (0, fr - 0.3, z0 + 0.22)],
       [0.12, 0.09, 0.05, 0.0], PAINT, OCHRE, segs=8)                                                 # hooked beak
for sx in (-1, 1):
    k.sphere(0.09, (sx * 0.17, fr + 0.0, z0 + 0.58), PAINT, WHITE, scale=(1, 0.5, 1), subdiv=1)
    k.sphere(0.05, (sx * 0.17, fr - 0.04, z0 + 0.58), PAINT, BLACK, subdiv=1)
    k.prism([(-0.12, 0), (0.12, 0), (0.0, 0.12)], 0.03, (sx * 0.17, fr - 0.01, z0 + 0.68), PAINT, RED)
    for tier, (span, zoff, col) in enumerate(((1.3, 0.0, LOG_L), (1.05, -0.16, RED), (0.8, -0.3, BLACK))):
        pts = [(0.0, 0.2), (span * 0.3, 0.28), (span * 0.7, 0.32), (span, 0.45), (span * 0.96, 0.24)]
        n = 5
        for f in range(n, 0, -1):                                       # feather tips
            x = span * (0.35 + 0.6 * f / n)
            pts.append((x, 0.02 + 0.03 * f))
            pts.append((x - span * 0.08, 0.1))
        pts.append((0.0, 0.04))
        pts = [(x * sx, z) for x, z in pts]
        if sx < 0:
            pts = list(reversed(pts))
        k.prism(pts, 0.08 - tier * 0.015, (sx * 0.28, 0.06 - tier * 0.05, z0 + 0.25 + zoff), WOOD if tier == 0 else PAINT,
                col, bevel=0.0)

# --- crown: horned skull, feathers, bone charms
k.cyl(R * 0.92, 0.14, (0, 0, 3.78), WOOD, mix(LOG, BLACK, 0.3), segs=14, r2=R * 0.65)
k.skull((0, -0.05, 4.1), (0.15, 0, 0), 1.45, BONE, bone=hexc("e3d9c2"), dark=hexc("1e1712"),
        horn_c=hexc("4a3f33"), tusks=True)
FEATH = [hexc("f0ebe0"), hexc("2a2622"), hexc("a8322a"), hexc("f0ebe0")]
for i, sx in enumerate((-1, 1)):
    for j in range(2):
        x = sx * (0.3 + j * 0.12)
        top = 3.86 - j * 0.05
        k.box((0.008, 0.008, 0.28), (x, -0.36, top - 0.14), CLOTH, hexc("5a4632"))
        c = FEATH[(i * 2 + j) % 4]
        k.prism([(0, 0), (0.035, -0.12), (0.03, -0.34), (0, -0.4), (-0.03, -0.34), (-0.035, -0.12)], 0.012,
                (x, -0.36, top - 0.28), CLOTH, c, rot=(0, sx * 0.1, 0))
        k.box((0.012, 0.014, 0.1), (x, -0.367, top - 0.36), CLOTH, mix(c, BLACK, 0.5))
# offerings at the base
for i, (bx, by, ang) in enumerate(((0.55, -0.85, 0.4), (0.7, -0.75, -0.6))):   # offered bones
    k.tube([(bx - 0.18 * math.cos(ang), by - 0.18 * math.sin(ang), 0.05), (bx + 0.18 * math.cos(ang), by + 0.18 * math.sin(ang), 0.06)],
           [0.03, 0.03], BONE, hexc("d9cdb2"), segs=6, point_end=False)
    for e in (-1, 1):
        k.sphere(0.045, (bx + e * 0.19 * math.cos(ang), by + e * 0.19 * math.sin(ang), 0.06), BONE, hexc("d9cdb2"),
                 subdiv=0)
print("triangles:", k.tri_count())
k.finish(cam_dir=(0.8, -1.8, 0.4), fit=1.0, focus_z=2.3)
