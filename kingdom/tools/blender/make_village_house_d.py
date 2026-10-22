"""Village house D: narrow three-storey town house, gable end to the street.
Stone ground floor with a wide shop window and a door under a shingled
awning, two jettied half-timbered storeys above, a steep roof, a hoist beam
with a pulley in the front gable, a side chimney, flower boxes, a lantern and
barrels / crates by the door.

Run: python3 make_village_house_d.py <out.glb> [preview.png] [--variant=N]

Scale/facing: metres. Ground-floor walls 5.0 m (X) x 6.3 m (Y, y in
[-2.85, 3.45]); each upper storey jetties 0.3 m further toward the street.
Overall footprint incl. eaves, awning and clutter <= 6.0 x 8.0 m. Ridge
~12.6 m. Origin at ground centre; the street gable and front door face
Blender -Y (Godot +Z); floor level z=0.25.
Variant 2 is mirrored with a clay-tile roof, ochre limewash, oak frame and
mustard shutters.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg
from ra_kit import hexc

V = variant_arg()
PAL = {
    1: palette(plaster="straw", timber="dark", accent="blue", roof="slate_blue", stone="grey", door="oxblood",
               box="natural"),
    2: palette(plaster="blue", timber="oak", accent="mustard", roof="clay", stone="warm", door="green"),
    3: palette(plaster="white", timber="red", accent="green", roof="shingle_grey", stone="field", door="natural"),
    4: palette(plaster="cream", timber="dark", accent="blue", roof="slate_teal", stone="grey", door="oxblood",
               box="natural"),
}[V]
k = VK("VillageHouseD" + ("" if V == 1 else f"_{V}"), seed=404 + V * 7, pal=PAL)
k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=V * 11 + 3, ao_dist=0.7)   # high-to-low PBR bake (pbr_kit.py)

HX = 2.5
Y0, Y1 = -2.7, 3.3
F0 = 0.25
G1 = 3.2
BAND = 0.24
J = 0.3
S2 = (G1 + BAND, 5.85)
S3 = (S2[1] + BAND, 8.3)
PITCH = 58
ROOF_KIND = "shingle" if PAL["roof_kind"].startswith(("shingle", "clay")) else "slate"


def box_side(s, y0, y1):
    return k.side(s, HX, (y1 - y0) / 2, cy=(y0 + y1) / 2)


# ---------------------------------------------------------------- stone ground floor
k.core(-HX, HX, Y0, Y1, 0.0, G1, inset=0.22)
with box_side("front", Y0, Y1) as L:
    k.stone_wall(L, 0.0, G1, [
        {"kind": "win", "x": -1.05, "z0": 0.9, "h": 1.45, "w": 1.9, "panes": (4, 2), "flowers": True},
        {"kind": "door", "x": 1.35, "z0": F0, "h": 2.1, "w": 1.0, "awning": 0.5, "lantern": None}])
    k.wall_lantern(0.45, 2.3)
with box_side("back", Y0, Y1) as L:
    k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": 0.0, "z0": 1.1, "h": 1.0, "w": 0.8}])
for s in ("left", "right"):
    with box_side(s, Y0, Y1) as L:
        k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": -1.0, "z0": 1.2, "h": 1.0, "w": 0.75}] if s == "right" else [],
                     bw=0.75, bh=0.36)
k.quoins(-HX, HX, Y0, Y1, 0.0, G1, n=8)
k.stage("ground")

# ---------------------------------------------------------------- jettied upper storeys
posts2 = [-HX + 0.09, -1.3, 0.0, 1.3, HX - 0.09]
posts3 = [-HX + 0.09, -0.7, 0.7, HX - 0.09]
for lvl, (z0, z1), jy, bays, posts in (
        (2, S2, Y0 - J, ["up", {"kind": "win", "w": 0.85, "flowers": True, "shutters": True},
                         {"kind": "win", "w": 0.85, "flowers": True, "shutters": True}, "dn"], posts2),
        (3, S3, Y0 - 2 * J, ["x", {"kind": "win", "w": 1.0, "shutters": True}, "x"], posts3)):
    k.jetty(-HX, HX, jy + J, Y1, z0 - BAND, jf=J, jb=0.0, t=BAND)
    with box_side("front", jy, Y1) as L:
        k.timber_wall(L, z0, z1, posts, bays, ext=0.11)
    with box_side("back", jy, Y1) as L:
        k.timber_wall(L, z0, z1, posts3, ["dn", {"kind": "win", "w": 0.8, "panes": (1, 2)}, "up"], ext=0.11,
                      detail=0)
    for s in ("left", "right"):
        with box_side(s, jy, Y1) as L:
            n = 4
            pp = [-L / 2 + 0.09 + i * (L - 0.18) / n for i in range(n + 1)]
            bb = ["x", "rail", "rail", "x"]
            if s == "right":
                bb[1] = {"kind": "win", "w": 0.75, "panes": (1, 2)}
            k.timber_wall(L, z0, z1, pp, bb, detail=0)
    k.stage(f"storey{lvl}")

# ---------------------------------------------------------------- roof (gable to the street)
RY0 = Y0 - 2 * J
r = k.gable_roof(ROOF_KIND, -HX, HX, RY0, Y1, S3[1], PITCH, over=0.32, verge=0.3, along="y",
                 tile_w=(0.36, 0.6), course=0.4)
for s in ("front", "back"):
    with box_side(s, RY0, Y1):
        k.gable_wall(HX, S3[1], r["gable"], style="timber", window=(s == "front"))
k.stage("roof")
# hoist beam and pulley under the front apex
apex = r["ridge"]
W = k.M("Wood")
k.box((0.2, 0.8, 0.2), (0, RY0 - 0.25, apex - 0.75), W, k.timber(), bevel=0.02)
k.bar((0, RY0 - 0.02, apex - 1.4), (0, RY0 - 0.45, apex - 0.85), 0.14, 0.14, W, k.timber(), up=(0, 1, 1))
k.cyl(0.12, 0.06, (-0.03, RY0 - 0.52, apex - 0.95), W, hexc("5a3e26"), rot=(0, math.pi / 2, 0), segs=10, base=False)
k.box((0.02, 0.02, 1.9), (0, RY0 - 0.64, apex - 1.95), W, hexc("c9b78e"), var=0)
k.box((0.02, 0.02, 2.4), (0, RY0 - 0.4, apex - 2.2), W, hexc("c9b78e"), var=0)
# chimney through the right slope
cz = r["ridge"] - 1.05 * r["tan"]
k.chimney(1.05, 1.9, cz - 0.4, r["ridge"] + 0.35, sx=0.65, sy=0.8, pots=1)
k.stage("chimney")

# ---------------------------------------------------------------- street clutter
k.barrel(HX - 0.3, Y0 - 0.42, r=0.3)
k.crate(-HX + 0.4, Y0 - 0.45, s=0.55, rz=0.1)
k.basket(-1.35, Y0 - 0.38, goods="apple")
k.basket(-0.8, Y0 - 0.4, r=0.2, goods="cabbage", n=5)
k.stage("props")
# ---------------------------------------------------------------- variant dressing (procedural kit extras)
if V == 3:
    k.dormer(1.0, r["eave"], r["run"], r["rise"], cy=0.0, side=1, along="y", w=1.1, wall_h=0.95, inset=0.8)
    with k.side("front", HX, (Y1 - Y0) / 2, cy=(Y0 + Y1) / 2):
        k.hanging_sign(-HX + 0.3, 2.7, emblem="leaf", board_c=hexc("5a3a24"), emb_c=hexc("9ad07a"), arm=0.9,
                       size=0.6, shape="square", lantern=False)
elif V == 4:
    k.dormer(0.6, r["eave"], r["run"], r["rise"], cy=0.0, side=1, along="y", w=1.1, wall_h=0.95, inset=0.8)
    with k.side("front", HX, (Y1 - Y0) / 2, cy=(Y0 + Y1) / 2):
        k.ivy([(-HX + 0.2, 0.4), (-HX + 0.35, 1.5), (-HX + 0.2, 2.6)], width=0.4)
k.stage("variant")

if V in (2, 4):
    k.mirror_x()
k.finish_checked((6.0, 8.0), 12000, cam_dir=(1.0, -1.6, 0.62), fit=0.95)
