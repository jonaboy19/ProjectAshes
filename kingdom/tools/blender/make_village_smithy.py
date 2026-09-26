"""Village smithy: an open-fronted forge shed. Stone back and side wall, a
board-clad side with the tool wall, heavy braced posts carrying a shingle roof,
a stone hearth with a glowing coal bed (emissive "Coals" material) under a
hood and chimney, bellows, an anvil on a stump, a quench barrel, a workbench
with a vise, tongs and hammers on the wall, a coal heap, iron bar stock and a
grindstone.

Run: python3 make_village_smithy.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Shed 8.6 m (X) x 6.0 m (Y); overall footprint incl.
eaves and clutter <= 10.0 x 8.0 m. Ridge ~5.4 m, chimney ~6.6 m. Origin at
ground centre; the open front faces Blender -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON, MORTAR
from ra_kit import hexc, mix, vary

V = variant_arg()
PAL = {
    1: palette(plaster="grey", timber="grey", accent="natural", roof="shingle_grey", stone="field"),
    2: palette(plaster="cream", timber="dark", accent="natural", roof="slate_grey", stone="warm"),
}[V]
k = VK("VillageSmithy" + ("" if V == 1 else f"_{V}"), seed=606 + V * 5, pal=PAL)
ROOF_KIND = "slate" if PAL["roof_kind"].startswith("slate") else "shingle"
W, MT, MA = k.M("Wood"), k.M("Metal"), k.M("Matte")
STEEL = hexc("4a4c50")

HX, HY = 4.3, 3.0
WT = 3.5
PITCH = 32

# ---------------------------------------------------------------- floor + walls
k.box((2 * HX - 0.1, 2 * HY - 0.1, 0.08), (0, 0, 0.04), MA, hexc("4a4038"), var=0.03)
for i in range(9):   # a few flagstones by the forge
    k.box((random.uniform(0.5, 0.8), random.uniform(0.4, 0.6), 0.04),
          (-1.6 + (i % 3 - 1) * 0.75 + random.uniform(-0.05, 0.05), 1.0 - (i // 3) * 0.6, 0.09), MA,
          vary(hexc("6e675c"), 0.1), rot=(0, 0, random.uniform(-0.1, 0.1)))
k.core(-HX, HX, HY - 0.5, HY, 0.0, WT, inset=0.05)                 # back wall core
k.core(-HX, -HX + 0.5, -HY, HY, 0.0, WT, inset=0.05)               # left wall core
with k.side("back", HX, HY) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "win", "x": -2.0, "z0": 1.4, "h": 0.9, "w": 0.8, "panes": (2, 2)}])
with k.side("left", HX, HY) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "win", "x": 0.2, "z0": 1.4, "h": 0.9, "w": 0.8, "panes": (2, 2)}])

with k.side("front", 0.25, HY, cx=-HX + 0.25) as L:        # end face of the side wall
    k.stone_wall(L, 0.0, WT, [])
# inner faces (seen through the open front)
k.push((0, HY - 0.5, 0), (0, 0, math.pi))
k.stone_wall(2 * HX - 1.0, 0.0, WT, [{"kind": "hole", "x": 2.0, "z0": 1.4, "h": 0.9, "w": 0.8}], place=False)
k.pop()
k.push((-HX + 0.5, -0.25, 0), (0, 0, math.pi / 2))
k.stone_wall(2 * HY - 0.5, 0.0, WT, [{"kind": "hole", "x": 0.45, "z0": 1.4, "h": 0.9, "w": 0.8}], place=False)
k.pop()
# right side: timber frame with vertical boards (tool wall inside)
k.box((0.06, 2 * HY - 0.2, WT - 0.2), (HX - 0.1, 0, WT / 2), MA, hexc("2a221c"), var=0)
with k.side("right", HX, HY) as L:
    k.plank_wall(L - 0.2, WT - 0.15, (0, 0, 0.12), W, lambda: k.plank_c(hexc("7e6248")), plank=(0.2, 0.3))
    for x in (-HY + 0.1, 0.0, HY - 0.1):
        k.box((0.2, 0.18, WT), (x, -0.08, WT / 2), W, k.timber(), bevel=0.02)
    k.box((L + 0.1, 0.18, 0.2), (0, -0.08, WT - 0.1), W, k.timber(), bevel=0.02)
    k.box((L + 0.1, 0.18, 0.18), (0, -0.08, 0.09), W, k.timber(), bevel=0.02)
    k.box((L, 0.14, 0.14), (0, -0.07, 1.45), W, k.timber())
k.stage("walls")

# ---------------------------------------------------------------- open front: posts, braces, tie beam
posts = [-HX + 0.15, -1.45, 1.45, HX - 0.1]
for x in posts:
    k.box((0.34, 0.34, 0.25), (x, -HY + 0.15, 0.125), MA, vary(hexc("8a847a"), 0.06), bevel=0.03)
    k.box((0.24, 0.24, WT - 0.25), (x, -HY + 0.15, 0.25 + (WT - 0.25) / 2), W, k.timber(), bevel=0.025)
    for sx in (-1, 1):
        if (x == posts[0] and sx < 0) or (x == posts[-1] and sx > 0):
            continue
        k.bar((x, -HY + 0.15, WT - 1.0), (x + sx * 0.8, -HY + 0.15, WT - 0.2), 0.16, 0.14, W, k.timber(),
              up=(-sx, 0, 1))
k.box((2 * HX + 0.2, 0.26, 0.3), (0, -HY + 0.15, WT - 0.15), W, k.timber(), bevel=0.025)
for x in (-1.45, 1.45):   # tie beams front to back
    k.box((0.2, 2 * HY, 0.22), (x, 0, WT - 0.11), W, k.timber(), bevel=0.02)
# horseshoes nailed over the middle posts for luck
for x in (-1.45, 1.45):
    k.push((x, -HY - 0.03, WT - 0.55))
    k.ring(0.07, 0.1, 0.025, (0, 0, 0), MT, STEEL, segs=8)
    k.pop()
k.stage("front")

# ---------------------------------------------------------------- roof
r = k.gable_roof(ROOF_KIND, -HX, HX, -HY, HY, WT, PITCH, over=0.45, verge=0.32,
                 tile_w=(0.3, 0.5) if ROOF_KIND == "shingle" else (0.4, 0.66), course=0.36 if ROOF_KIND == "shingle" else 0.44)
with k.side("left", HX, HY):
    k.gable_wall(HY, WT, r["gable"], style="stone", window=False)
with k.side("right", HX, HY):
    k.gable_wall(HY, WT, r["gable"], style="boards", window=False, vent=True)
k.stage("roof")

# ---------------------------------------------------------------- forge hearth + hood + chimney
FX, FY = -1.6, HY - 0.95
FW, FD, FH = 1.9, 1.3, 0.85
k.box((FW - 0.2, FD - 0.2, FH), (FX, FY, FH / 2), MA, MORTAR, var=0)
with k.side("front", FW / 2, FD / 2, cx=FX, cy=FY) as L:
    k.grid_wall(L, FH, (0, 0, 0), MA, lambda: mix(k.stone(), hexc("7a4a36"), 0.25), bw=0.36, bh=0.21, gap=0.025)
for s in ("left", "right"):
    with k.side(s, FW / 2, FD / 2, cx=FX, cy=FY) as L:
        k.grid_wall(L, FH, (0, 0, 0), MA, lambda: mix(k.stone(), hexc("7a4a36"), 0.25), bw=0.36, bh=0.21, gap=0.025)
k.box((FW + 0.1, FD + 0.1, 0.12), (FX, FY, FH + 0.06), MA, hexc("6e675c"), bevel=0.02)
# coal bed: glowing core, cooler rim, a few embers
k.box((FW - 0.5, FD - 0.5, 0.08), (FX, FY, FH + 0.13), k.M("Coals"), hexc("ff7a2a"), var=0.05, grime=False)
for i in range(26):
    a = random.uniform(0, math.tau)
    rr = random.uniform(0.25, 0.62)
    px, py = FX + math.cos(a) * rr * 1.3, FY + math.sin(a) * rr * 0.75
    hot = rr < 0.4 and random.random() < 0.6
    k.box((0.09, 0.08, 0.06), (px, py, FH + 0.17 + random.uniform(0, 0.03)), k.M("Coals") if hot else MA,
          hexc("ff9a3a") if hot else vary(hexc("1c1a19"), 0.2), rot=(random.uniform(0, 1), random.uniform(0, 1), a),
          grime=False, var=0)
# iron tuyere pipe and a piece of stock in the fire
k.bar((FX + FW / 2 + 0.3, FY, FH + 0.25), (FX + 0.3, FY, FH + 0.18), 0.07, 0.07, MT, STEEL, bevel=0)
k.bar((FX - 0.1, FY - 0.2, FH + 0.21), (FX - 0.2, FY - 1.0, FH + 0.35), 0.035, 0.035, MT, hexc("c24a1a"), bevel=0)
# hood (square pyramid) and stone chimney through the roof
k.cyl(1.05, 0.9, (FX, FY + 0.1, 2.05), MA, mix(k.stone(), MORTAR, 0.35), segs=4, r2=0.45, rot=(0, 0, math.pi / 4),
      smooth=None)
k.box((1.5, 1.5, 0.14), (FX, FY + 0.1, 2.0), MA, hexc("6e675c"), bevel=0.02)
for sx in (-1, 1):
    k.box((0.14, 0.14, 1.2), (FX + sx * 0.68, FY - 0.55, 1.4), MA, vary(hexc("6e675c"), 0.06))
top = k.chimney(FX, FY + 0.15, 2.9, r["ridge"] + 1.1, sx=0.7, sy=0.7, pots=0)
k.stage("forge")

# bellows beside the hearth
BX, BY = FX + FW / 2 + 0.55, FY + 0.1
k.push((BX, BY, 0.95), (0, 0, math.pi / 2))
leaf = [(-0.5, -0.28), (0.3, -0.12), (0.45, 0.0), (0.3, 0.12), (-0.5, 0.28)]
k.prism([(x, z) for x, z in leaf], 0.05, (0, 0, 0.0), W, hexc("6b4a2f"), rot=(math.pi / 2, 0, 0))
k.prism([(x * 0.98, z * 0.9) for x, z in leaf], 0.2, (0, 0, 0.14), k.M("Cloth"), hexc("5a3a24"), rot=(math.pi / 2, 0, 0))
k.prism([(x, z) for x, z in leaf], 0.05, (0, 0, 0.28), W, hexc("6b4a2f"), rot=(math.pi / 2, 0, 0))
k.pop()
for sx in (-1, 1):
    k.box((0.08, 0.08, 0.95), (BX + sx * 0.2, BY - 0.35, 0.475), W, k.timber())
    k.box((0.08, 0.08, 0.95), (BX + sx * 0.2, BY + 0.35, 0.475), W, k.timber())
k.bar((BX, BY + 0.5, 1.6), (BX, BY - 0.9, 1.35), 0.06, 0.06, W, hexc("8a6a48"), up=(0, 0, 1))
k.box((0.02, 0.02, 0.5), (BX, BY - 0.85, 1.1), W, hexc("c9b78e"), var=0)

# ---------------------------------------------------------------- anvil, quench barrel, tools
AX, AY = 0.4, -0.5
k.log((AX, AY, 0.0), (AX, AY, 0.55), 0.3, W, hexc("5a4330"), segs=9, noise_amt=0.02, end_color=hexc("9c7a55"))
k.push((AX, AY, 0.55), (0, 0, 0.25))
k.box((0.42, 0.32, 0.1), (0, 0, 0.05), MT, STEEL, bevel=0.015)
k.box((0.24, 0.18, 0.18), (0, 0, 0.19), MT, STEEL, bevel=0.01)
k.box((0.62, 0.22, 0.14), (-0.04, 0, 0.35), MT, STEEL, bevel=0.012)
k.cyl(0.11, 0.34, (0.26, 0, 0.35), MT, STEEL, rot=(0, math.pi / 2, 0), segs=8, r2=0.0, base=True)
k.box((0.12, 0.2, 0.08), (-0.38, 0, 0.38), MT, STEEL, bevel=0.01)
k.box((0.6, 0.2, 0.012), (-0.04, 0, 0.425), MT, hexc("8d9096"), var=0)   # polished face
k.pop()
k.bar((AX - 0.15, AY + 0.05, 1.0), (AX + 0.1, AY + 0.15, 0.99), 0.035, 0.035, W, hexc("8a6a48"), up=(0, 0, 1))   # hammer
k.box((0.07, 0.14, 0.07), (AX - 0.17, AY + 0.04, 1.0), MT, STEEL, var=0)
k.barrel(AX + 1.05, AY + 0.1, r=0.34, h=0.8, water=True)
k.bar((AX + 1.0, AY + 0.0, 0.78), (AX + 1.3, AY - 0.35, 1.05), 0.03, 0.03, MT, STEEL, bevel=0)   # tongs in the barrel
k.bar((AX + 1.05, AY + 0.05, 0.78), (AX + 1.36, AY - 0.3, 1.08), 0.03, 0.03, MT, STEEL, bevel=0)
# workbench + vise + tool wall on the right side
BXW = HX - 0.55
k.box((0.8, 2.4, 0.08), (BXW, 0.4, 0.88), W, hexc("7a5638"), bevel=0.012)
for dy in (-0.7, 1.5):
    for dx in (-0.3, 0.3):
        k.box((0.08, 0.08, 0.86), (BXW + dx, 0.4 + dy, 0.43), W, hexc("5c4028"))
k.box((0.18, 0.14, 0.2), (BXW - 0.3, -0.4, 1.02), MT, STEEL, bevel=0.01)
k.box((0.03, 0.3, 0.03), (BXW - 0.4, -0.4, 1.02), MT, STEEL, var=0)
for i, (tz, tl) in enumerate(((1.95, 0.5), (1.9, 0.6), (1.95, 0.45), (1.85, 0.7), (1.95, 0.5))):
    ty = -0.4 + i * 0.42
    k.box((0.03, 0.03, tl), (HX - 0.18, ty, tz - tl / 2), W, hexc("8a6a48"), var=0.1)
    k.box((0.06, 0.14 if i % 2 == 0 else 0.05, 0.08), (HX - 0.18, ty, tz - 0.02), MT, STEEL, var=0)
k.box((0.04, 2.2, 0.06), (HX - 0.15, 0.45, 2.02), W, hexc("5c4028"))
# coal heap, bar stock, grindstone
for i in range(3):
    k.sphere(0.45 - i * 0.08, (-HX + 0.9 + i * 0.25, HY - 0.8 - i * 0.2, 0.05), MA, vary(hexc("1f1d1c"), 0.1),
             scale=(1.2, 1.0, 0.55), subdiv=2, noise_amt=0.06)
for i in range(6):
    k.bar((-HX + 0.4 + i * 0.05, -1.2 + i * 0.08, 0.05), (-HX + 0.3 + i * 0.05, -1.35 + i * 0.08, 1.9), 0.03, 0.03, MT,
          vary(hexc("5a5048"), 0.1), bevel=0)
GX, GY = -HX + 1.2, -HY + 0.6
k.push((GX, GY, 0.0))
for sy in (-1, 1):
    k.box((0.7, 0.06, 0.08), (0, sy * 0.18, 0.55), W, hexc("6b4a2f"))
    for sx in (-1, 1):
        k.box((0.06, 0.06, 0.6), (sx * 0.3, sy * 0.18, 0.3), W, hexc("5c4028"))
k.cyl(0.36, 0.1, (0, -0.05, 0.62), MA, hexc("a39c8c"), rot=(math.pi / 2, 0, 0), segs=14, base=False, smooth=None)
k.box((0.03, 0.44, 0.03), (0, 0, 0.62), MT, STEEL, var=0)
k.pop()
k.bucket(1.9, 1.8)
k.sack(2.4, HY - 0.5, s=0.9, c=hexc("5a5048"))
k.stage("props")

k.finish_checked((10.0, 8.0), 12000, cam_dir=(0.55, -1.5, 0.32), fit=0.9, focus_z=2.2)
