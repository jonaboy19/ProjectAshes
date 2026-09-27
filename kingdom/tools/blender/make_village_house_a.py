"""Village house A: small one-storey cottage. Fieldstone skirt, half-timbered
limewashed walls, a thick thatch roof with a bound ridge roll, an external
stone chimney on one gable, shuttered windows with flower boxes, a lantern by
the door, a bench, firewood stack, water butt and chopping block.

Run: python3 make_village_house_a.py <out.glb> [preview.png] [--variant=N]
     (variant is also read from an output name ending in _N.glb)

Scale/facing: metres. Walls 5.4 m (X) x 4.2 m (Y); overall footprint incl.
thatch eaves, chimney and yard clutter <= 7.0 x 6.0 m. Origin at ground centre.
Front door faces Blender -Y (Godot +Z); floor level z=0.25.
Variant 2 is a mirrored layout (door / chimney swap sides) with an ochre
limewash, oak frame, oxblood shutters, warm stone and aged thatch.
Variant 3: rose limewash, black frame, herbalist's leaf sign, ivy and planters.
Variant 4 (mirrored): cream + oak under a blue slate roof with a dormer, porch pots.
The chimney top carries an empty named chimney_top.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg
from ra_kit import hexc

V = variant_arg()
PAL = {
    1: palette(plaster="white", timber="dark", accent="teal", stone="grey", thatch="golden", box="natural"),
    2: palette(plaster="ochre", timber="oak", accent="oxblood", stone="warm", thatch="aged", door="green"),
    3: palette(plaster="rose", timber="black", accent="sage", stone="field", thatch="golden", door="blue"),
    4: palette(plaster="cream", timber="oak", accent="blue", stone="grey", roof="slate_blue", door="natural",
               box="natural"),
}[V]
k = VK("VillageHouseA" + ("" if V == 1 else f"_{V}"), seed=101 + V * 17, pal=PAL)

HX, HY = 2.7, 2.1
F0, SK, WT = 0.25, 0.75, 3.3          # floor, top of stone skirt, wall top
PITCH = 50

# ---------------------------------------------------------------- walls
posts_f = [-HX + 0.09, -1.0, 0.0, 1.3, HX - 0.09]
front_bays = [{"kind": "win", "shutters": True, "flowers": True, "z0": 1.3, "h": 1.1}, "x",
              {"kind": "door", "z0": F0, "h": 2.1, "lantern": -1},
              {"kind": "win", "shutters": True, "flowers": True, "z0": 1.3, "h": 1.1}]
door_x = 0.65
k.stone_skirt(HX, HY, SK, opens_front=[{"x": door_x, "w": 1.0}])
k.stage("skirt")
with k.side("front", HX, HY):
    k.timber_wall(2 * HX, SK, WT, posts_f, front_bays, ext=0.11)
with k.side("back", HX, HY):
    k.timber_wall(2 * HX, SK, WT, [-HX + 0.09, -0.6, 0.6, HX - 0.09],
                  ["up", {"kind": "win", "w": 0.7, "h": 0.8, "z0": 1.45}, "dn"], ext=0.11)
with k.side("right", HX, HY):
    k.timber_wall(2 * HY, SK, WT, [-HY + 0.09, -0.6, 0.6, HY - 0.09],
                  ["chev", {"kind": "win", "w": 0.75, "shutters": True}, "chev"])
with k.side("left", HX, HY):
    k.timber_wall(2 * HY, SK, WT, [-HY + 0.09, HY - 0.09], ["x"])

k.stage("walls")
# ---------------------------------------------------------------- roof + gables
r = k.gable_roof("thatch" if V != 4 else "slate", -HX, HX, -HY, HY, WT, PITCH, over=0.42, verge=0.4)
for s in ("left", "right"):
    with k.side(s, HX, HY):
        k.gable_wall(HY, WT, r["gable"], style="timber", window=(s == "right"))

k.stage("roof")
# external chimney on the left gable
k.chimney(-HX - 0.3, 0.55, 0.0, r["ridge"] + 0.75, sx=0.62, sy=0.7, pots=1, shoulder=(WT - 0.4, 0.62, 1.15))

k.stage("chimney")
# ---------------------------------------------------------------- lived-in details
k.bench(-1.8, -HY - 0.38, L=1.3)
k.plant_pot(0.0, -HY - 0.35)
k.sack(-0.5, -HY - 0.4, s=0.8, rz=0.4)
k.barrel(HX + 0.3, -1.3, r=0.3, h=0.85, water=True)
k.bucket(HX - 0.3, -HY - 0.35)
k.firewood(HX + 0.32, 0.4, L=2.2, H=1.15, D=0.42, rz=math.pi / 2)
k.chopping_block(HX - 0.8, HY + 0.4)
k.bush(-HX - 0.1, -HY - 0.3, r=0.38, c=hexc("4c7534"))
k.crate(-HX + 0.2, HY + 0.45, s=0.55, rz=0.2)

k.stage("props")
# ---------------------------------------------------------------- variant dressing (procedural kit extras)
if V == 3:
    with k.side("front", HX, HY):
        k.hanging_sign(-HX + 0.3, 2.75, emblem="leaf", board_c=hexc("6a4a2c"), emb_c=hexc("8fd07a"), arm=1.0,
                       size=0.6, shape="square", lantern=False)
        k.ivy([(HX - 0.2, 0.9), (HX - 0.35, 1.9), (HX - 0.2, 2.9)], width=0.4)
    k.planter(-1.1, -HY - 0.38, L=0.8, D=0.34, H=0.32)
elif V == 4:
    k.dormer(-1.2, r["eave"], r["run"], r["rise"], side=-1, w=1.1, wall_h=0.95, inset=0.95)
    k.planter(0.45, -HY - 0.62, L=0.42, H=0.38, kind="pot")
    k.planter(1.3, -HY - 0.35, L=0.8, D=0.34, H=0.32)
k.stage("variant")
if V in (2, 4):
    k.mirror_x()
print("triangles:", k.tri_count())
k.finish_checked((7.0, 6.0), 12000, cam_dir=(1.0, -1.5, 0.7), fit=0.95)
