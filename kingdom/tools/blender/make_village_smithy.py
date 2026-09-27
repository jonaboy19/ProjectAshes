"""Village smithy (hero building, concept_blacksmith.png): a stone-and-timber
smith's house with its gable to the street joined to an open forge wing.

- House (left): coursed-stone ground floor with a plank door under a slate
  awning, a shuttered window and a glowing lantern; jettied half-timbered upper
  storey and a steep dark-slate gable roof with a dormer; a big anvil sign
  hangs from an iron bracket.
- Forge wing (right): heavy braced posts under a slate roof, open to the
  street; an arched stone hearth glowing at the back ("Coals" emissive), a big
  stone chimney rising between the two roofs, bellows, anvil on a stump,
  quench barrel, workbench and tool wall.
- Yard: grindstone, weapon rack with swords and spears, crates, a short
  post-and-rail fence, a coal heap and bar stock.

Run: python3 make_village_smithy.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Overall 8.6 m (X) x 6.0 m (Y) of building; footprint
incl. eaves, sign and yard clutter <= 10.0 x 8.0 m. House ridge ~9.0 m,
forge ridge ~5.4 m, chimney ~10 m. Origin at ground centre; the open forge
front and the house door face Blender -Y (Godot +Z). The chimney top carries
an empty named chimney_top.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON, MORTAR
from ra_kit import hexc, mix, vary

V = variant_arg()
PAL = {
    1: palette(plaster="cream", timber="oak", accent="natural", roof="slate_grey", stone="grey", door="natural"),
    2: palette(plaster="cream", timber="dark", accent="oxblood", roof="slate_purple", stone="warm", door="oxblood"),
}[V]
k = VK("VillageSmithy" + ("" if V == 1 else f"_{V}"), seed=606 + V * 5, pal=PAL)
k.lit_ratio = 0.7
W, MT, MA = k.M("Wood"), k.M("Metal"), k.M("Matte")
STEEL = hexc("4a4c50")

HX, HY = 4.3, 3.0
XS = -0.3                 # house x in [-HX, XS]; forge wing x in [XS, HX]
HW = XS + HX              # house width 4.0
HCX = (-HX + XS) / 2
HH = HW / 2
G1 = 3.0                  # stone ground floor top (house)
U0, U1 = G1 + 0.24, 5.3   # upper storey
WT = 3.4                  # forge wing wall/eave top
F0 = 0.2

# ================================================================ house block
k.core(-HX, XS, -HY, HY, 0.0, G1, inset=0.22)
with k.side("front", HH, HY, cx=HCX) as L:
    k.stone_wall(L, 0.0, G1, [
        {"kind": "door", "x": 0.75, "z0": F0, "h": 2.1, "w": 1.05, "awning": 0.45, "lantern": None},
        {"kind": "win", "x": -0.95, "z0": 1.05, "h": 1.05, "w": 0.95, "panes": (2, 2), "shutters": True,
         "flowers": True}])
    k.wall_lantern(-0.1, 2.35)
with k.side("back", HH, HY, cx=HCX) as L:
    k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": 0.0, "z0": 1.2, "h": 1.0, "w": 0.8, "panes": (2, 2)}],
                 bw=0.75, bh=0.36)
with k.side("left", HH, HY, cx=HCX) as L:
    k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": 0.6, "z0": 1.2, "h": 1.0, "w": 0.85, "panes": (2, 2),
                               "shutters": True}], bw=0.75, bh=0.36)
k.quoins(-HX, XS, -HY, HY, 0.0, G1, n=6)
k.stage("house_ground")
# jettied upper storey
J = 0.25
k.jetty(-HX, XS, -HY, HY, G1, jf=J, jb=0.0, t=0.24)
posts_f = [-HH + 0.09, -0.6, 0.6, HH - 0.09]
with k.side("front", HH, HY + J / 2, cx=HCX, cy=-J / 2) as L:
    k.timber_wall(L, U0, U1, posts_f, ["x", {"kind": "win", "w": 0.85, "shutters": True, "flowers": True}, "x"],
                  ext=0.11)
with k.side("back", HH, HY + J / 2, cx=HCX, cy=-J / 2) as L:
    k.timber_wall(L, U0, U1, posts_f, ["dn", {"kind": "win", "w": 0.8}, "up"], ext=0.11, detail=0)
with k.side("left", HH, HY + J / 2, cx=HCX, cy=-J / 2) as L:
    pp = [-L / 2 + 0.09 + i * (L - 0.18) / 4 for i in range(5)]
    k.timber_wall(L, U0, U1, pp, ["up", {"kind": "win", "w": 0.8, "panes": (1, 2)}, "rail", "dn"], detail=0)
with k.side("right", HH, HY + J / 2, cx=HCX, cy=-J / 2) as L:
    pp = [-L / 2 + 0.09 + i * (L - 0.18) / 4 for i in range(5)]
    k.timber_wall(L, U0, U1, pp, ["x", "rail", {"kind": "win", "w": 0.75, "panes": (1, 2)}, "x"], detail=0)
k.stage("house_upper")
# steep gable roof, gable to the street
r = k.gable_roof("slate", -HX, XS, -HY - J, HY, U1, 54, over=0.3, verge=0.32, along="y", tile_w=(0.34, 0.56),
                 course=0.36)
for s in ("front", "back"):
    with k.side(s, HH, HY + J / 2, cx=HCX, cy=-J / 2):
        k.gable_wall(HH, U1, r["gable"], style="timber", window=(s == "front"))
k.finial(HCX, -HY - J - 0.3, r["ridge"] + 0.05)
k.finial(HCX, HY + 0.3, r["ridge"] + 0.05)
k.dormer(0.2, r["eave"], r["run"], r["rise"], cy=HCX, side=-1, along="y", w=1.2, wall_h=1.0, inset=0.9)
k.stage("house_roof")
# anvil sign on an iron bracket off the front corner
with k.side("front", HH, HY, cx=HCX):
    k.hanging_sign(-HH + 0.35, 3.55, emblem="anvil", board_c=hexc("3b2a1e"), emb_c=hexc("e3b04a"), arm=1.3,
                   size=0.95, shape="square")
k.stage("sign")

# ================================================================ forge wing
FXW = HX - XS             # wing width 4.6
FCX = (XS + HX) / 2
k.box((FXW - 0.1, 2 * HY - 0.1, 0.08), (FCX, 0, 0.04), MA, hexc("4a4038"), var=0.03)
k.core(XS, HX, HY - 0.5, HY, 0.0, WT, inset=0.05)                 # back wall core
with k.side("back", FXW / 2, HY, cx=FCX) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "win", "x": -1.4, "z0": 1.4, "h": 0.8, "w": 0.7, "panes": (2, 2)}])
k.push((FCX, HY - 0.5, 0), (0, 0, math.pi))                        # inner face of the back wall
k.stone_wall(FXW - 0.2, 0.0, WT, [{"kind": "hole", "x": 1.4, "z0": 1.4, "h": 0.8, "w": 0.7}], place=False)
k.pop()
# right side: boarded frame (tool wall inside)
k.box((0.06, 2 * HY - 0.2, WT - 0.2), (HX - 0.1, 0, WT / 2), MA, hexc("2a221c"), var=0)
with k.side("right", HX, HY) as L:
    k.plank_wall(L - 0.2, WT - 0.15, (0, 0, 0.12), W, lambda: k.plank_c(hexc("7e6248")), plank=(0.2, 0.3))
    for x in (-HY + 0.1, 0.0, HY - 0.1):
        k.box((0.2, 0.18, WT), (x, -0.08, WT / 2), W, k.timber(), bevel=0.02)
    k.box((L + 0.1, 0.18, 0.2), (0, -0.08, WT - 0.1), W, k.timber(), bevel=0.02)
    k.box((L + 0.1, 0.18, 0.18), (0, -0.08, 0.09), W, k.timber(), bevel=0.02)
posts = [XS + 0.25, FCX, HX - 0.1]
for x in posts:
    k.box((0.34, 0.34, 0.25), (x, -HY + 0.15, 0.125), MA, vary(hexc("8a847a"), 0.06), bevel=0.03)
    k.box((0.24, 0.24, WT - 0.25), (x, -HY + 0.15, 0.25 + (WT - 0.25) / 2), W, k.timber(), bevel=0.025)
    for sx in (-1, 1):
        if (x == posts[0] and sx < 0) or (x == posts[-1] and sx > 0):
            continue
        k.bar((x, -HY + 0.15, WT - 1.0), (x + sx * 0.8, -HY + 0.15, WT - 0.2), 0.16, 0.14, W, k.timber(),
              up=(-sx, 0, 1))
k.box((FXW + 0.2, 0.26, 0.3), (FCX, -HY + 0.15, WT - 0.15), W, k.timber(), bevel=0.025)
k.box((0.2, 2 * HY, 0.22), (FCX, 0, WT - 0.11), W, k.timber(), bevel=0.02)
k.push((FCX, -HY - 0.03, WT - 0.55))                              # horseshoe for luck
k.ring(0.07, 0.1, 0.025, (0, 0, 0), MT, STEEL, segs=8)
k.pop()
rf = k.gable_roof("slate", XS - 0.2, HX, -HY, HY, WT, 32, over=0.45, verge=0.32, tile_w=(0.4, 0.66), course=0.44)
with k.side("right", HX, HY):
    k.gable_wall(HY, WT, rf["gable"], style="boards", window=False, vent=True)
# canvas awning off the wing's right gable end over the timber stack
with k.side("right", HX, HY):
    k.striped_awning(-1.4, 1.2, 2.7, 0.9, 0.45, [hexc("e2d2ae")], posts=False, scallop=False, sag=0.06)
k.stage("wing")

# ---------------------------------------------------------------- arched hearth + chimney
FX, FY = FCX - 0.2, HY - 0.95
FW, FD, FH = 2.0, 1.2, 0.8
k.box((FW, FD, 2.3), (FX, FY + 0.05, 1.15), MA, MORTAR, var=0)
with k.side("front", FW / 2, FD / 2, cx=FX, cy=FY) as L:
    AW, SPR = 1.1, 1.35
    k.grid_wall(L, 2.3, (0, 0, 0), MA, lambda: mix(k.stone(), hexc("8a5a44"), 0.2), bw=0.42, bh=0.25, gap=0.025,
                holes=[(-AW / 2, FH, AW / 2, SPR + AW / 2)])
    nv = 7
    for i in range(nv):     # voussoirs round the fire mouth
        a0, a1 = math.pi * i / nv, math.pi * (i + 1) / nv
        R0, R1 = AW / 2, AW / 2 + 0.24
        pts = [(math.cos(a0) * R0, SPR + math.sin(a0) * R0), (math.cos(a0) * R1, SPR + math.sin(a0) * R1),
               (math.cos(a1) * R1, SPR + math.sin(a1) * R1), (math.cos(a1) * R0, SPR + math.sin(a1) * R0)]
        k.prism(pts, 0.28, (0, 0.06, 0), MA, mix(k.stone(), hexc("c8bfae"), 0.3), var=0)
    k.box((AW + 0.5, 0.36, 0.14), (0, 0.0, FH - 0.07), MA, hexc("6e675c"), bevel=0.02)
    # glowing fire bed and back, embers
    k.box((AW - 0.1, 0.5, 0.1), (0, 0.35, FH + 0.05), k.M("Coals"), hexc("ff7a2a"), var=0.05, grime=False)
    k.quad(AW - 0.05, SPR - FH + AW / 2 - 0.1, (0, 0.62, (FH + SPR + AW / 2) / 2), k.M("Coals"),
           hexc("c8401a"), var=0, grime=False)
    for i in range(10):
        a = random.uniform(-0.45, 0.45)
        k.box((0.09, 0.08, 0.07), (a, 0.3 + random.uniform(-0.1, 0.1), FH + 0.13), k.M("Coals"),
              hexc("ffb040") if i % 2 else hexc("ff6a1a"), rot=(random.uniform(0, 1), random.uniform(0, 1), a), var=0,
              grime=False)
k.box((FW + 0.2, FD + 0.2, 0.14), (FX, FY + 0.05, 2.35), MA, hexc("6e675c"), bevel=0.02)
k.chimney(XS + 0.1, HY - 0.75, 2.4, r["ridge"] + 1.0, sx=1.0, sy=1.0, pots=2, shoulder=(4.0, 1.25, 1.25))
k.stage("forge")

# bellows beside the hearth
BX, BY = FX + FW / 2 + 0.5, FY + 0.1
k.push((BX, BY, 0.95), (0, 0, math.pi / 2))
leaf = [(-0.5, -0.28), (0.3, -0.12), (0.45, 0.0), (0.3, 0.12), (-0.5, 0.28)]
k.prism([(x, z) for x, z in leaf], 0.05, (0, 0, 0.0), W, hexc("6b4a2f"), rot=(math.pi / 2, 0, 0))
k.prism([(x * 0.98, z * 0.9) for x, z in leaf], 0.2, (0, 0, 0.14), k.M("Cloth"), hexc("5a3a24"),
        rot=(math.pi / 2, 0, 0))
k.prism([(x, z) for x, z in leaf], 0.05, (0, 0, 0.28), W, hexc("6b4a2f"), rot=(math.pi / 2, 0, 0))
k.pop()
for sx in (-1, 1):
    k.box((0.08, 0.08, 0.95), (BX + sx * 0.2, BY - 0.35, 0.475), W, k.timber())

# ---------------------------------------------------------------- anvil, quench barrel, tools
AX, AY = FCX - 0.3, -0.9
k.log((AX, AY, 0.0), (AX, AY, 0.55), 0.3, W, hexc("5a4330"), segs=8, noise_amt=0.02, end_color=hexc("9c7a55"))
k.push((AX, AY, 0.55), (0, 0, 0.25))
k.box((0.42, 0.32, 0.1), (0, 0, 0.05), MT, STEEL, bevel=0.015)
k.box((0.24, 0.18, 0.18), (0, 0, 0.19), MT, STEEL, bevel=0.01)
k.box((0.62, 0.22, 0.14), (-0.04, 0, 0.35), MT, STEEL, bevel=0.012)
k.cyl(0.11, 0.34, (0.26, 0, 0.35), MT, STEEL, rot=(0, math.pi / 2, 0), segs=8, r2=0.0, base=True)
k.box((0.6, 0.2, 0.012), (-0.04, 0, 0.425), MT, hexc("8d9096"), var=0)   # polished face
k.pop()
k.bar((AX - 0.15, AY + 0.05, 1.0), (AX + 0.1, AY + 0.15, 0.99), 0.035, 0.035, W, hexc("8a6a48"), up=(0, 0, 1))
k.box((0.07, 0.14, 0.07), (AX - 0.17, AY + 0.04, 1.0), MT, STEEL, var=0)
k.barrel(AX + 1.0, AY + 0.3, r=0.32, h=0.78, water=True)
k.bar((AX + 0.95, AY + 0.2, 0.76), (AX + 1.25, AY - 0.15, 1.03), 0.03, 0.03, MT, STEEL, bevel=0)
# workbench + tool wall on the right side
BXW = HX - 0.55
k.box((0.8, 2.0, 0.08), (BXW, 0.6, 0.88), W, hexc("7a5638"), bevel=0.012)
for dy in (-0.5, 1.5):
    for dx in (-0.3, 0.3):
        k.box((0.08, 0.08, 0.86), (BXW + dx, 0.6 + dy, 0.43), W, hexc("5c4028"))
k.box((0.18, 0.14, 0.2), (BXW - 0.3, -0.2, 1.02), MT, STEEL, bevel=0.01)
with k.detail():
    for i, (tz, tl) in enumerate(((1.95, 0.5), (1.9, 0.6), (1.95, 0.45), (1.85, 0.7), (1.95, 0.5))):
        ty = -0.2 + i * 0.4
        k.box((0.03, 0.03, tl), (HX - 0.18, ty, tz - tl / 2), W, hexc("8a6a48"), var=0.1)
        k.box((0.06, 0.14 if i % 2 == 0 else 0.05, 0.08), (HX - 0.18, ty, tz - 0.02), MT, STEEL, var=0)
k.stage("tools")

# ---------------------------------------------------------------- yard: grindstone, weapon rack, fence, stock
GX, GY = XS - 0.6, -HY - 0.75
k.push((GX, GY, 0.0), (0, 0, 0.3))
for sy in (-1, 1):
    k.box((0.7, 0.06, 0.08), (0, sy * 0.18, 0.55), W, hexc("6b4a2f"))
    for sx in (-1, 1):
        k.box((0.06, 0.06, 0.6), (sx * 0.3, sy * 0.18, 0.3), W, hexc("5c4028"))
k.cyl(0.42, 0.12, (0, -0.06, 0.66), MA, hexc("b3ac9c"), rot=(math.pi / 2, 0, 0), segs=12, base=False, smooth=None)
k.box((0.03, 0.44, 0.03), (0, 0, 0.66), MT, STEEL, var=0)
k.bar((0.0, 0.26, 0.66), (0.0, 0.34, 0.9), 0.03, 0.03, MT, STEEL, bevel=0)
k.pop()
# weapon rack against the forge's front-right post: two rails, blades and spears leaning in
RX, RY = HX - 0.9, -HY - 0.45
k.push((RX, RY, 0))
for sx in (-1, 1):
    k.box((0.07, 0.07, 1.3), (sx * 0.6, 0, 0.65), W, hexc("6b4a2f"))
k.box((1.3, 0.08, 0.07), (0, 0.0, 1.2), W, hexc("6b4a2f"))
k.box((1.3, 0.2, 0.06), (0, 0.06, 0.22), W, hexc("5c4028"))
with k.detail():
    for i in range(4):
        x = -0.45 + i * 0.3
        if i % 2 == 0:
            k.sword((x, 0.06, 0.28), (-0.12, 0, 0), MT, MT, length=1.05, blade_c=hexc("b9bec6"),
                    hilt_c=hexc("8a6a3a"), grip_c=hexc("3a2214"))
        else:
            k.bar((x, 0.08, 0.2), (x, -0.02, 1.8), 0.035, 0.035, W, hexc("8a6a48"), bevel=0)
            k.cyl(0.05, 0.25, (x, -0.025, 1.78), MT, hexc("aab0b8"), segs=4, r2=0.0, rot=(0.06, 0, 0))
k.pop()
# post-and-rail fence closing the yard to the left of the house door and to the right
for (x0, x1, yy) in ((-HX - 0.1, -HX + 1.9, -HY - 1.3), (HX - 2.0, HX + 0.3, -HY - 1.1)):
    n = max(2, round((x1 - x0) / 1.0))
    for i in range(n + 1):
        x = x0 + i * (x1 - x0) / n
        k.bar((x, yy, 0.0), (x, yy, 1.0), 0.09, 0.09, W, vary(hexc("6e5238"), 0.06), bevel=0.01)
    for z in (0.45, 0.85):
        k.bar((x0 - 0.05, yy, z), (x1 + 0.05, yy, z + 0.02), 0.07, 0.05, W, hexc("7a5a3e"), up=(0, 0, 1), bevel=0)
# crates, a coal heap and bar stock
k.crate(-HX + 0.4, -HY - 0.65, s=0.55, rz=0.15)
k.crate(-HX + 0.45, -HY - 0.65, z=0.55, s=0.45, rz=-0.1)
for i in range(3):
    k.sphere(0.42 - i * 0.08, (HX - 0.6 + i * 0.2, HY - 0.9 - i * 0.2, 0.05), MA, vary(hexc("1f1d1c"), 0.1),
             scale=(1.2, 1.0, 0.55), subdiv=1, noise_amt=0.05)
with k.detail():
    for i in range(5):
        k.bar((XS + 0.5 + i * 0.05, -0.6 + i * 0.07, 0.05), (XS + 0.4 + i * 0.05, -0.75 + i * 0.07, 1.8), 0.03, 0.03,
              MT, vary(hexc("5a5048"), 0.1), bevel=0)
k.bucket(1.3, 1.8)
k.planter(-2.9, -HY - 0.45, L=0.8, D=0.36, H=0.36)
k.stage("yard")

k.finish_checked((10.0, 8.0), 12000, cam_dir=(0.75, -1.5, 0.45), fit=0.9)
