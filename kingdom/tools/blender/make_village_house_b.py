"""Village house B: two-storey half-timbered town house with a jettied upper
floor (front and back), a wooden-shingle roof, a ridge chimney, an awning over
the door, shuttered windows with flower boxes, a hanging lantern, and barrels,
crates and a cart wheel by the walls.

Run: python3 make_village_house_b.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Ground-floor walls 6.8 m (X) x 5.0 m (Y); the upper
floor overhangs 0.4 m at the front and 0.3 m at the back. Overall footprint
incl. eaves, awning and clutter <= 8.0 x 7.0 m. Ridge ~8.5 m. Origin at ground
centre; front door faces Blender -Y (Godot +Z); floor level z=0.35.
Variant 2 is mirrored, rose limewash with black timbers, blue shutters and
silvered grey shingles.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg
from ra_kit import hexc

V = variant_arg()
PAL = {
    1: palette(plaster="cream", timber="dark", accent="green", roof="shingle_brown", stone="grey", box="natural"),
    2: palette(plaster="rose", timber="black", accent="blue", roof="shingle_grey", stone="cool", door="oxblood"),
    3: palette(plaster="sage", timber="oak", accent="mustard", roof="shingle_brown", stone="warm", door="teal"),
}[V]
k = VK("VillageHouseB" + ("" if V == 1 else f"_{V}"), seed=202 + V * 31, pal=PAL)

HX, HY = 3.4, 2.5
F0, SK = 0.35, 0.6
G1 = 3.0                 # ground storey top
BAND = 0.26
U0, U1 = G1 + BAND, 5.75
JF, JB = 0.4, 0.3
UY0, UY1 = -HY - JF, HY + JB
UHY, UCY = (UY1 - UY0) / 2, (UY0 + UY1) / 2
PITCH = 47
t = 0.18

# ---------------------------------------------------------------- ground floor
door_x = -0.275
k.stone_skirt(HX, HY, SK, opens_front=[{"x": door_x, "w": 1.05}], bw=0.55, bh=0.3)
with k.side("front", HX, HY):
    k.timber_wall(2 * HX, SK, G1, [-HX + 0.09, -2.0, -0.9, 0.35, 1.55, HX - 0.09],
                  [{"kind": "win", "z0": 1.25, "h": 1.2, "shutters": True}, "x",
                   {"kind": "door", "z0": F0, "h": 2.15, "lantern": 1},
                   {"kind": "win", "z0": 1.25, "h": 1.2},
                   {"kind": "win", "z0": 1.15, "h": 1.3, "w": 1.35, "panes": (3, 3), "shutters": True}], ext=0.11)
    k.stage("front")
with k.side("back", HX, HY):
    k.timber_wall(2 * HX, SK, G1, [-HX + 0.09, -1.2, 0.2, 1.6, HX - 0.09],
                  ["up", {"kind": "win", "z0": 1.3, "h": 1.1}, {"kind": "door", "z0": F0, "h": 2.05, "detail": 0},
                   "dn"], ext=0.11, detail=0)
for s in ("left", "right"):
    with k.side(s, HX, HY):
        k.timber_wall(2 * HY, SK, G1, [-HY + 0.09, -0.8, 0.8, HY - 0.09],
                      ["x", {"kind": "win", "z0": 1.3, "h": 1.1, "shutters": s == "right"}, "x"], detail=0)
k.stage("ground")

# ---------------------------------------------------------------- jetty + upper floor
k.jetty(-HX, HX, -HY, HY, G1, jf=JF, jb=JB, t=BAND)
up_posts = [-HX + 0.09 + i * (2 * HX - 0.18) / 5 for i in range(6)]
with k.side("front", HX, UHY, cy=UCY):
    k.timber_wall(2 * HX, U0, U1, up_posts,
                  ["up", {"kind": "win", "flowers": True, "shutters": True}, {"kind": "win", "flowers": True},
                   {"kind": "win", "flowers": True, "shutters": True}, "dn"], ext=0.11)
with k.side("back", HX, UHY, cy=UCY):
    k.timber_wall(2 * HX, U0, U1, up_posts, ["x", {"kind": "win", "panes": (1, 1)}, "studs", "chev", "x"], ext=0.11, detail=0)
for s in ("left", "right"):
    with k.side(s, HX, UHY, cy=UCY):
        k.timber_wall(2 * UHY, U0, U1, [-UHY + 0.09, -0.75, 0.75, UHY - 0.09],
                      ["chev", {"kind": "win", "shutters": True, "panes": (1, 2)}, "chev"], detail=0)
k.stage("upper")

# ---------------------------------------------------------------- roof
r = k.gable_roof("shingle", -HX, HX, UY0, UY1, U1, PITCH, over=0.4, verge=0.32, tile_w=(0.36, 0.6), course=0.42)
for s in ("left", "right"):
    with k.side(s, HX, UHY, cy=UCY):
        k.gable_wall(UHY, U1, lambda u: r["gable"](u), style="timber", window=True)
k.stage("roof")
k.chimney(1.9, UCY + 1.0, r["ridge"] - 1.0 * r["tan"] - 0.4, r["ridge"] + 0.9, sx=0.66, sy=0.66, pots=2)
k.stage("chimney")

# ---------------------------------------------------------------- lived-in details
k.barrel(HX + 0.26, -1.0, r=0.32)
k.barrel(HX + 0.24, -0.25, r=0.3, open_top=True)
k.crate(HX + 0.3, 0.6, s=0.6, rz=0.15)
k.sack(1.0, -HY - 0.45, rz=0.5)
k.sack(1.35, -HY - 0.35, s=0.8, rz=1.4)
k.plant_pot(door_x - 0.85, -HY - 0.3)
k.wheel(-HX - 0.12, -0.6, r=0.48, rz=math.pi / 2, lean=0.2)
k.stage("props")

if V == 2:
    k.mirror_x()
k.finish_checked((8.0, 7.0), 12000, cam_dir=(1.0, -1.5, 0.72), fit=0.95)
