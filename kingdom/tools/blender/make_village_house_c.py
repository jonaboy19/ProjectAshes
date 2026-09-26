"""Village house C: stone farmhouse. Coursed rubble walls with dressed quoins,
stone lintels and sills, a slate roof with a gable chimney, a shingled awning
over the door, and a timber lean-to shed on one gable sheltering a firewood
stack, a barrel and sacks. Hay bale, bench and flower box out front.

Run: python3 make_village_house_c.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. House walls 6.0 m (X, x in [-3.8, 2.2]) x 5.2 m (Y);
lean-to 2.0 m deep on +X (x in [2.2, 4.2]). Overall footprint incl. eaves,
awning and clutter <= 9.0 x 7.0 m. Ridge ~6.7 m, chimney ~7.8 m. Origin at
ground centre; front door faces Blender -Y (Godot +Z); floor level z=0.2.
Variant 2 is mirrored (shed on -X) in warm sandstone with a purple-grey slate
roof and teal paintwork.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg
from ra_kit import hexc, mix

V = variant_arg()
PAL = {
    1: palette(plaster="grey", timber="grey", accent="oxblood", roof="slate_grey", stone="field", door="natural",
               box="natural"),
    2: palette(plaster="cream", timber="oak", accent="teal", roof="slate_purple", stone="warm", door="teal"),
    3: palette(plaster="white", timber="dark", accent="green", roof="slate_blue", stone="cool", door="green"),
}[V]
k = VK("VillageHouseC" + ("" if V == 1 else f"_{V}"), seed=303 + V * 13, pal=PAL)

X0, X1 = -3.8, 2.2
HX, CX = (X1 - X0) / 2, (X0 + X1) / 2
HY = 2.6
WT = 4.0
F0 = 0.2
PITCH = 42
SX1 = 4.2                  # lean-to outer line

# ---------------------------------------------------------------- stone house
k.core(X0, X1, -HY, HY, 0.0, WT, inset=0.22)
front = [
    {"kind": "win", "x": -1.9, "z0": 1.0, "h": 1.2, "w": 0.9, "shutters": True, "flowers": True},
    {"kind": "door", "x": 0.35, "z0": F0, "h": 2.1, "w": 1.05, "awning": 0.55, "lantern": 1},
    {"kind": "win", "x": 2.05, "z0": 1.0, "h": 1.2, "w": 0.9, "shutters": True},
    {"kind": "win", "x": -1.9, "z0": 2.65, "h": 0.72, "w": 0.7, "panes": (2, 1)},
    {"kind": "win", "x": 2.05, "z0": 2.65, "h": 0.72, "w": 0.7, "panes": (2, 1)},
]
with k.side("front", HX, HY, cx=CX) as L:
    k.stone_wall(L, 0.0, WT, front)
with k.side("back", HX, HY, cx=CX) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "win", "x": -1.0, "z0": 1.1, "h": 1.0, "w": 0.8, "panes": (2, 2)},
                              {"kind": "door", "x": 1.6, "z0": F0, "h": 2.0, "w": 0.95, "detail": 0}])
with k.side("left", HX, HY, cx=CX) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "win", "x": 0.9, "z0": 1.1, "h": 1.1, "w": 0.8}])
with k.side("right", HX, HY, cx=CX) as L:
    k.stone_wall(L, 0.0, WT, [{"kind": "door", "x": -0.6, "z0": F0, "h": 2.0, "w": 0.95, "step": False,
                               "detail": 0}])
k.quoins(X0, X1, -HY, HY, 0.0, WT, n=10)
k.stage("walls")

# ---------------------------------------------------------------- roof + gables
r = k.gable_roof("slate", X0, X1, -HY, HY, WT, PITCH, over=0.42, verge=0.3)
for s in ("left", "right"):
    with k.side(s, HX, HY, cx=CX):
        k.gable_wall(HY, WT, r["gable"], style="stone", window=(s == "left"))
k.stage("roof")
# chimney rising out of the left gable
k.chimney(X0 + 0.45, 0.0, WT + 0.5, r["ridge"] + 1.05, sx=0.72, sy=1.0, pots=2)
k.stage("chimney")

# ---------------------------------------------------------------- lean-to shed
W = k.M("Wood")
SY0, SY1 = -HY + 0.25, HY - 0.1
S_TOP, S_LOW = 3.05, 2.2
run = SX1 - X1 + 0.3
k.push((X1, 0, S_LOW - 0.3 * (S_TOP - S_LOW) / (SX1 - X1)))
k.shingle_side(SY0 - 0.25, SY1 + 0.25, run, S_TOP - S_LOW + 0.3 * (S_TOP - S_LOW) / (SX1 - X1), k.M("Roof"), k.tile,
               tile_w=(0.3, 0.5), course=0.32, th=0.028, deck_mat=W, deck_color=k.timber(), rot=(0, 0, math.pi / 2))
k.pop()
k.box((0.16, SY1 - SY0 + 0.4, 0.2), (X1 + 0.05, (SY0 + SY1) / 2, S_TOP - 0.05), W, k.timber(), bevel=0.02)
k.box((0.18, SY1 - SY0 + 0.3, 0.2), (SX1 - 0.1, (SY0 + SY1) / 2, S_LOW - 0.12), W, k.timber(), bevel=0.02)
for yy in (SY0 + 0.1, 0.0, SY1 - 0.1):
    k.log((SX1 - 0.1, yy, 0.0), (SX1 - 0.1, yy, S_LOW - 0.2), 0.09, W, k.timber(), segs=7, noise_amt=0.012)
    k.bar((SX1 - 0.1, yy, S_LOW - 0.75), (SX1 - 0.65, yy, S_LOW - 0.15), 0.1, 0.09, W, k.timber(), up=(1, 0, 1))
# plank back wall on the shed (behind y = 0.6), open to the front
k.box((SX1 - X1 - 0.2, 0.06, S_LOW - 0.2), ((X1 + SX1) / 2, SY1 - 0.03, (S_LOW - 0.2) / 2), k.M("Matte"),
      hexc("2a221c"), var=0)
k.push(((X1 + SX1) / 2, SY1 - 0.08, 0), (0, 0, math.pi))
k.plank_wall(SX1 - X1 - 0.15, S_LOW - 0.15, (0, 0, 0), W, lambda: k.plank_c(), plank=(0.2, 0.3))
k.pop()
k.push((SX1 - 0.05, 1.3, 0), (0, 0, math.pi / 2))
k.box((2.4, 0.05, S_LOW - 0.2), (0, 0.05, (S_LOW - 0.2) / 2), k.M("Matte"), hexc("2a221c"), var=0)
k.plank_wall(2.4, S_LOW - 0.2, (0, 0, 0), W, lambda: k.plank_c(), plank=(0.2, 0.3))
k.pop()
k.firewood(X1 + 0.55, 1.0, L=2.4, H=1.4, D=0.5, rz=math.pi / 2, r=0.125)
k.barrel(X1 + 1.5, -1.5, r=0.32)
k.sack(X1 + 1.3, -0.6, rz=0.3)
k.sack(X1 + 1.65, -0.3, s=0.85, rz=1.2)
k.stage("shed")

# ---------------------------------------------------------------- yard
k.bench(-1.9, -HY - 0.38, L=1.4)
k.hay_bale(-3.3, -HY - 0.55, rz=0.25)
k.hay_bale(-3.35, -HY - 0.5, z=0.42, rz=0.05, s=(0.9, 0.48, 0.4))
k.plant_pot(1.15, -HY - 0.3)
k.bucket(-0.5, -HY - 0.3)
k.stage("props")

if V == 2:
    k.mirror_x()
k.finish_checked((9.0, 7.0), 12000, cam_dir=(1.0, -1.45, 0.7), fit=0.95)
