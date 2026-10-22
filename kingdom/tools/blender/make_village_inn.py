"""Village inn (hero building, concept_inn.png): a big two-storey coaching inn.
Stone ground floor with dressed quoins and an arched double door, half-timbered
upper floor full of warm glowing windows, a red tile roof with a front cross
gable, two dormers and three chimneys, a timber balcony with flower boxes on
posts across most of the front, a striped canvas awning over the outdoor table
on the right, benches and barrels on the plank deck, ivy on a corner and a
hanging tankard sign with a lantern on an iron bracket.

Run: python3 make_village_inn.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Walls 11.2 m (X) x 7.0 m (Y, y in [-2.9, 4.1]); the
porch runs the full front, 1.7 m deep. Overall footprint incl. eaves, porch,
sign and clutter <= 13.0 x 10.0 m. Ridge ~10.3 m. Origin at ground centre;
front door and porch face Blender -Y (Godot +Z). Floor level z=0.35.
Variant 2 swaps to warm sandstone, ochre limewash and a shingle roof.
Chimney tops carry empties named chimney_top, chimney_top_2, chimney_top_3.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON
from ra_kit import hexc, mix, vary

V = variant_arg()
PAL = {
    1: palette(plaster="cream", timber="oak", accent="green", roof="clay", stone="warm", door="natural",
               box="natural"),
    2: palette(plaster="ochre", timber="black", accent="green", roof="shingle_brown", stone="warm", door="oxblood"),
}[V]
k = VK("VillageInn" + ("" if V == 1 else f"_{V}"), seed=505 + V * 11, pal=PAL)
k.lit_ratio = 0.85        # an inn glows
ROOF_KIND = "slate" if PAL["roof_kind"].startswith("slate") else "shingle"

HX = 5.6
Y0, Y1 = -2.9, 4.1
HY, CY = (Y1 - Y0) / 2, (Y0 + Y1) / 2
F0 = 0.35
G1 = 3.7                 # top of the stone ground floor
U0, U1 = G1 + 0.26, 6.5
PITCH = 44
PY = Y0 - 1.7            # porch front line
W, MT = k.M("Wood"), k.M("Metal")


def side(s):
    return k.side(s, HX, HY, cy=CY)


# ---------------------------------------------------------------- stone ground floor
k.core(-HX, HX, Y0, Y1, 0.0, G1, inset=0.22)
front = [{"kind": "door", "x": 0.0, "z0": F0, "h": 2.5, "w": 1.6, "arch": True, "step": False}]
for x in (-4.3, -2.2, 2.2, 4.3):
    front.append({"kind": "win", "x": x, "z0": 1.15, "h": 1.45, "w": 1.1, "panes": (2, 2)})
with side("front") as L:
    k.stone_wall(L, 0.0, G1, front)
with side("back") as L:
    k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": x, "z0": 1.2, "h": 1.2, "w": 0.9, "panes": (1, 2)}
                              for x in (-3.8, 0.0)] +
                 [{"kind": "door", "x": 3.2, "z0": F0, "h": 2.1, "w": 1.1, "detail": 0}], bw=0.8, bh=0.4)
for s in ("left", "right"):
    with side(s) as L:
        k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": x, "z0": 1.2, "h": 1.3, "w": 0.95, "panes": (1, 2)}
                                  for x in (-1.6, 1.6)], bw=0.8, bh=0.4)
k.quoins(-HX, HX, Y0, Y1, 0.0, G1, n=7)
k.stage("ground")

# ---------------------------------------------------------------- upper floor
k.jetty(-HX, HX, Y0, Y1, G1, jf=0.0, jb=0.0, t=0.26, joists=False)
k.box((2 * HX + 0.4, 0.3, 0.12), (0, Y0 - 0.1, G1 - 0.03), k.M("Matte"), mix(k.p["stone"][2], hexc("c8bfae"), 0.3),
      bevel=0.02)   # string course
posts_f = [-HX + 0.09 + i * (2 * HX - 0.18) / 9 for i in range(10)]
with side("front") as L:
    k.timber_wall(L, U0, U1, posts_f,
                  ["up", {"kind": "win", "flowers": True, "shutters": True}, "x", {"kind": "win"},
                   {"kind": "win", "flowers": True, "shutters": True}, {"kind": "win"}, "x",
                   {"kind": "win", "flowers": True, "shutters": True}, "dn"], ext=0.11)
with side("back") as L:
    pb = [-HX + 0.09 + i * (2 * HX - 0.18) / 6 for i in range(7)]
    k.timber_wall(L, U0, U1, pb, ["x", {"kind": "win"}, "chev", "chev", {"kind": "win"}, "x"], ext=0.11, detail=0)
for s in ("left", "right"):
    with side(s) as L:
        ps = [-HY + 0.09 + i * (2 * HY - 0.18) / 5 for i in range(6)]
        k.timber_wall(L, U0, U1, ps, ["up", {"kind": "win", "panes": (1, 2)}, "rail",
                                      {"kind": "win", "panes": (1, 2)}, "dn"], detail=0)
k.stage("upper")

# ---------------------------------------------------------------- roofs
tw = (0.46, 0.76) if ROOF_KIND == "slate" else (0.4, 0.64)
co = 0.5 if ROOF_KIND == "slate" else 0.44
r = k.gable_roof(ROOF_KIND, -HX, HX, Y0, Y1, U1, PITCH, over=0.42, verge=0.32, tile_w=tw, course=co)
for s in ("left", "right"):
    with side(s):
        k.gable_wall(HY, U1, r["gable"], style="timber", window=True)
# front cross gable over the door
CG = 2.1
cr = k.gable_roof(ROOF_KIND, -CG, CG, Y0, CY - 0.6, U1, 50, over=0.36, verge=0.3, along="y", tile_w=tw,
                  course=co, barge=True)
with k.side("front", CG, (CY - 0.6 - Y0) / 2, cy=(Y0 + CY - 0.6) / 2):
    k.gable_wall(CG, U1, cr["gable"], style="timber", window=True)
k.stage("roofs")
for cx in (-HX + 0.9, HX - 0.9):
    k.chimney(cx, CY + 0.9, r["ridge"] - 0.9 * r["tan"] - 0.4, r["ridge"] + 0.8, sx=0.8, sy=0.8,
              pots=1)
k.chimney(0.6, CY + 1.4, r["ridge"] - 1.4 * r["tan"] - 0.4, r["ridge"] + 1.0, sx=0.9, sy=0.8, pots=2)
k.stage("chimneys")
for u in (-3.7, 3.7):
    k.dormer(u, r["eave"], r["run"], r["rise"], cy=CY, side=-1, w=1.25, wall_h=1.05, inset=1.05, flowers=True)
k.stage("dormers")

# ---------------------------------------------------------------- porch
P_TOP, P_LOW = 3.45, 2.75
k.box((2 * HX + 0.1, Y0 - PY + 0.1, 0.3), (0, (Y0 + PY) / 2, 0.15), W, hexc("6f5238"), var=0)   # deck frame
k.push((0, PY, 0.3))
k.plank_wall(2 * HX + 0.1, Y0 - PY + 0.05, (0, 0, 0), W, lambda: k.plank_c(hexc("8a6a48")), rot=(-math.pi / 2, 0, 0),
             plank=(0.22, 0.3), ragged=0.0, grime=False)   # deck boards (a plank "wall" laid flat)
k.pop()
for i in range(2):       # steps up to the door
    k.box((2.2 + 0.3 * (1 - i), 0.35, 0.15), (0, PY - 0.17 - 0.35 * (1 - i) * 0.5, 0.075 + 0.15 * i - 0.075 * i),
          k.M("Matte"), vary(hexc("8d877c"), 0.06), bevel=0.02)
BX1 = 1.55                   # balcony spans x in [-HX, BX1]; striped awning beyond
with side("front"):
    k.balcony(-HX - 0.05, BX1, U0 - 0.02, Y0 - PY + 0.05, rail_h=0.95, posts_to_ground=True, flowers=True)
    k.striped_awning(BX1 + 0.25, HX + 0.1, 3.2, Y0 - PY - 0.05, 0.75,
                     [hexc("b3342a"), hexc("efe3c6")] if V == 1 else [hexc("3f6b44"), hexc("e8d7a8")],
                     posts=True, sag=0.07)
    k.ivy([(-HX + 0.25, 0.3), (-HX + 0.35, 1.6), (-HX + 0.2, 2.9), (-HX + 0.45, 3.9), (-HX + 0.3, 5.2)],
          width=0.45, y=-0.05)
# lanterns hanging from the porch beam
for x in (-3.4, -0.6):
    k.lantern((x, PY + 0.08, U0 - 0.4), s=0.9)
# benches, a trestle table with tankards, barrels
for x in (-4.3, -2.2):
    k.bench(x, Y0 - 0.35, L=1.6)
k.push((3.6, PY + 0.95, 0.3))
k.box((1.6, 0.75, 0.06), (0, 0, 0.74), W, hexc("8a6238"), bevel=0.012)
for sx in (-1, 1):
    k.bar((sx * 0.6, -0.3, 0.0), (sx * 0.6, 0.0, 0.72), 0.06, 0.08, W, hexc("6b4a2f"), up=(1, 0, 0), bevel=0)
    k.bar((sx * 0.6, 0.3, 0.0), (sx * 0.6, 0.0, 0.72), 0.06, 0.08, W, hexc("6b4a2f"), up=(1, 0, 0), bevel=0)
    k.box((1.5, 0.28, 0.05), (0, sx * 0.62, 0.44), W, hexc("7a5638"), bevel=0.01)
    for sy in (-1, 1):
        k.box((0.06, 0.06, 0.44), (sx * 0.62, sy * 0.62, 0.22), W, hexc("5c4028"))
for (tx, ty) in ((-0.4, -0.12), (0.15, 0.1), (0.5, -0.15)):
    k.cyl(0.055, 0.14, (tx, ty, 0.77), W, hexc("8a6a48"), segs=8)
    k.cyl(0.05, 0.02, (tx, ty, 0.91), k.M("Cloth"), hexc("f3ecd8"), segs=8)
k.pop()
k.barrel(-HX + 1.0, PY + 0.6, z=0.3, r=0.34)
k.barrel(-HX + 1.6, PY + 0.5, z=0.3, r=0.32)
k.planter(-1.6, PY + 0.3, L=0.9, D=0.4, H=0.38)
k.planter(1.2, PY + 0.3, L=0.5, H=0.42, kind="pot")
k.barrel(-HX + 0.45, PY + 0.55, z=0.3, r=0.33, water=True)
k.plant_pot(-1.35, PY + 0.35)
k.stage("porch")

# ---------------------------------------------------------------- tankard sign on an iron bracket
SX, SZ = 2.35, 5.75
k.push((SX, Y0, 0))
k.box((0.3, 0.1, 0.5), (0, -0.05, SZ), MT, IRON, bevel=0.01)
k.box((0.07, 1.55, 0.07), (0, -0.8, SZ), MT, IRON)
k.bar((0, -0.05, SZ - 0.5), (0, -1.0, SZ - 0.03), 0.05, 0.05, MT, IRON, bevel=0)
k.cyl(0.16, 0.04, (0, -1.15, SZ + 0.14), MT, IRON, rot=(0, math.pi / 2, 0), segs=10, caps=False)
k.sphere(0.06, (0, -1.6, SZ), MT, hexc("b08a3a"), subdiv=1)
for dy in (-0.42, -1.3):
    k.box((0.02, 0.02, 0.3), (0, dy, SZ - 0.17), MT, IRON)
# board in the YZ plane, readable from the street
k.push((0, -0.86, SZ - 0.95), (0, 0, math.pi / 2))
board = [(-0.6, -0.55), (0.6, -0.55), (0.6, 0.45), (0.45, 0.62), (-0.45, 0.62), (-0.6, 0.45)]
k.prism([(x * 1.06, z * 1.06) for x, z in board], 0.06, (0, 0, 0), W, hexc("3a2616"), bevel=0.012)
for sd in (-1, 1):
    k.prism(board, 0.05, (0, sd * 0.02, 0), W, hexc("2d4a3a") if V == 1 else hexc("5a2a22"), bevel=0.01)
    y = sd * 0.055
    # tankard: body, lid rim, foam and handle
    k.box((0.42, 0.03, 0.56), (-0.05, y, -0.05), W, hexc("c9a063"), var=0)
    for zz in (-0.25, 0.15):
        k.box((0.46, 0.035, 0.05), (-0.05, y * 1.1, zz), MT, hexc("4a4a4a"), var=0)
    k.box((0.5, 0.035, 0.12), (-0.05, y * 1.1, 0.26), k.M("Cloth"), hexc("f3ecd8"), var=0)
    for (fx, fz) in ((-0.2, 0.33), (0.0, 0.36), (0.16, 0.32)):
        k.cyl(0.09, 0.035, (fx - 0.05, y * 1.1, fz), k.M("Cloth"), hexc("f7f1e1"), rot=(math.pi / 2, 0, 0), segs=8,
              base=False)
    k.ring(0.1, 0.16, 0.035, (0.26, y, -0.03), W, hexc("b08850"), segs=10)
    k.box((0.9, 0.03, 0.06), (0, y * 1.1, 0.5), W, hexc("c9a063"), var=0)
    k.box((0.9, 0.03, 0.06), (0, y * 1.1, -0.45), W, hexc("c9a063"), var=0)
k.pop()
k.pop()
k.stage("sign")

k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=V * 11 + 5, ao_dist=0.8)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((13.0, 10.0), 23000, cam_dir=(1.0, -1.45, 0.62), fit=0.95)
