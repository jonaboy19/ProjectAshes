"""Kingsreach gate-street townhouses (hero row houses, docs/art/reference/
00_MAIN_kingsreach_gate_market.webp): tall 3-storey half-timbered townhouses
with a stone shopfront ground floor and two jettied timber-framed storeys
above, to line the capital's gate street.

- Ground floor: coursed warm-beige stone with a wide arched shopfront doorway
  and a shuttered shop window (a lantern by the door).
- Floor 1 and floor 2: half-timbered (cream/white plaster, dark oak beams,
  diagonal braces), each jettied ~0.4 m out over the storey below on visible
  joists, with shuttered windows and red/yellow flower boxes.
- Steep gable roof (ridge along the width, gable ends on the narrow sides),
  a chimney, and a little heraldic/shopfront dressing that varies per variant:
    a: royal-blue slate roof, a hanging shield sign, a small red/gold banner.
    b: terracotta tile roof, a red/cream striped awning over the door.
    c: royal-blue slate roof, a hanging sign over the shop window, ivy.
    d: royal-blue slate roof with a front gable dormer, a door lantern.

Run: python3 make_townhouses.py <out.glb> [preview.png] --variant=N   (N=1..4)
     or one of the make_townhouse_<a|b|c|d>.py wrappers (bpy, Blender 5.x).

Scale/facing: metres. Ground footprint 7.0 m (X) x 8.0 m (Y); floor 1 and
floor 2 each jetty 0.4 m out at the front and back (depth grows to 8.8 m then
9.6 m). Ridge ~13.0 m. Origin at ground centre; front (door, shopfront) faces
Blender -Y (Godot +Z). Door threshold at x=DOOR_X (per variant), z=0.0.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg
from ra_kit import hexc, mix, vary

FLOWERS = [hexc("e0394a"), hexc("f7c843"), hexc("f0932a")]     # red / yellow / orange only

PAL = {
    1: palette(plaster="cream", timber="dark", accent="oxblood", roof="slate_blue", stone="warm",
               door="oxblood", box="natural", flowers=FLOWERS),
    2: palette(plaster="white", timber="oak", accent="green", roof="clay", stone="warm",
               door="green", box="natural", flowers=FLOWERS),
    3: palette(plaster="straw", timber="black", accent="blue", roof="slate_blue", stone="warm",
               door="teal", box="natural", flowers=FLOWERS),
    4: palette(plaster="cream", timber="oak", accent="blue", roof="slate_blue", stone="warm",
               door="natural", box="natural", flowers=FLOWERS),
}

CRIMSON = hexc("9b1d24")
GOLD = hexc("d4a63a")
CREAM = hexc("ece2c8")


def build(variant):
    V = variant
    pal = PAL[V]
    k = VK("Townhouse" + "abcd"[V - 1].upper(), seed=730 + V * 19, pal=pal)
    k.lit_ratio = 0.5
    # high-to-low PBR bake (pbr_kit.py): unique 1024 atlas (albedo / normal / ORM) + instanced block and slate
    # tiles; LOD1 gets its own 512 atlas
    k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=V * 11 + 3, ao_dist=0.7)
    k.weather_ao = 0.34

    HX, HY = 3.5, 4.0                 # ground footprint 7.0 x 8.0
    G1 = 2.8                          # top of the stone ground floor
    BAND = 0.24                       # jetty floor-band thickness
    JF = JB = 0.4                     # jetty overhang, front and back, each floor
    U0 = G1 + BAND
    U1 = U0 + 2.2                     # top of floor 1 (jettied)
    U0b = U1 + BAND
    U1b = U0b + 2.2                   # top of floor 2 (jettied) = wall_top for the roof
    HY1 = HY + JF
    HY2 = HY1 + JF
    PITCH = 46
    ROOFK = "slate" if pal["roof_kind"].startswith("slate") else "tile"
    tile_w = (0.34, 0.56) if ROOFK == "slate" else (0.32, 0.5)
    course = 0.4 if ROOFK == "slate" else 0.36

    door_x = -0.7
    win_x = 1.75

    # ---------------------------------------------------------------- ground floor (stone shopfront)
    k.core(-HX, HX, -HY, HY, 0.0, G1, inset=0.22)
    with k.side("front", HX, HY) as L:
        k.stone_wall(L, 0.0, G1, [
            {"kind": "door", "x": door_x, "w": 2.0, "h": 2.6, "z0": 0.0, "arch": True, "lantern": 1},
            {"kind": "win", "x": win_x, "w": 1.3, "h": 1.4, "z0": 0.75, "shutters": True, "panes": (2, 2)},
        ], bw=0.65, bh=0.32)
        if V == 1:
            k.hanging_sign(HX - 0.35, 2.55, emblem="shield", board_c=hexc("4a2c1a"), emb_c=CRIMSON,
                           arm=1.0, size=0.62, shape="shield")
        elif V == 2:
            k.striped_awning(door_x - 1.15, door_x + 1.15, 2.72, run=0.85, drop=0.55,
                             colors=[hexc("9b1d24"), hexc("ece2c8")])
        elif V == 3:
            k.hanging_sign(win_x + 0.15, 2.5, emblem="leaf", board_c=hexc("3a4a2c"), emb_c=hexc("8fd07a"),
                           arm=0.95, size=0.58, shape="square", lantern=False)
            k.ivy([(-HX + 0.18, 0.6), (-HX + 0.3, 1.6), (-HX + 0.18, 2.5)], width=0.36)
    k.stage("ground")
    with k.side("back", HX, HY) as L:
        k.stone_wall(L, 0.0, G1, [
            {"kind": "door", "x": 0.0, "w": 1.0, "h": 2.05, "z0": 0.0},
            {"kind": "win", "x": 1.5, "w": 0.9, "h": 1.05, "z0": 1.15, "panes": (2, 2)},
        ], bw=0.7, bh=0.34)
    for s in ("left", "right"):
        with k.side(s, HX, HY) as L:
            k.stone_wall(L, 0.0, G1, [{"kind": "win", "x": 0.0, "w": 0.9, "h": 1.05, "z0": 1.15,
                                       "shutters": s == "right", "panes": (2, 2)}], bw=0.7, bh=0.34)
    k.stage("shopfront")

    # ---------------------------------------------------------------- floor 1 (jettied)
    k.jetty(-HX, HX, -HY, HY, G1, jf=JF, jb=JB, t=BAND)
    posts_f = [-HX + 0.09, -2.0, -0.65, 0.65, 2.0, HX - 0.09]
    win1 = {"kind": "win", "shutters": True, "flowers": True, "z0": 0.55, "h": 1.15}
    with k.side("front", HX, HY1, cy=0.0) as L:
        k.timber_wall(L, U0, U1, posts_f, ["up", win1, dict(win1), dict(win1), "dn"], ext=0.11)
    with k.side("back", HX, HY1, cy=0.0) as L:
        k.timber_wall(L, U0, U1, [-HX + 0.09, -0.7, 0.7, HX - 0.09],
                      ["x", {"kind": "win", "z0": 0.6, "h": 1.0}, "x"], ext=0.11, detail=0)
    for s in ("left", "right"):
        with k.side(s, HX, HY1, cy=0.0) as L:
            k.timber_wall(L, U0, U1, [-HY1 + 0.09, -0.75, 0.75, HY1 - 0.09],
                          ["chev", {"kind": "win", "shutters": (s == "right"), "z0": 0.55, "h": 1.0}, "chev"],
                          detail=0)
    k.stage("floor1")

    # ---------------------------------------------------------------- floor 2 (jettied again)
    k.jetty(-HX, HX, -HY1, HY1, U1, jf=JF, jb=JB, t=BAND)
    win2 = {"kind": "win", "shutters": True, "flowers": True, "z0": 0.5, "h": 1.1}
    with k.side("front", HX, HY2, cy=0.0) as L:
        k.timber_wall(L, U0b, U1b, posts_f, ["up", dict(win2), dict(win2), dict(win2), "dn"], ext=0.11)
        if V == 1:
            k.banner(-2.35, U1b - 0.25, w=0.55, h=1.35, color=CRIMSON, trim=GOLD, emblem="star", y=-0.14)
    with k.side("back", HX, HY2, cy=0.0) as L:
        k.timber_wall(L, U0b, U1b, [-HX + 0.09, -0.7, 0.7, HX - 0.09],
                      ["dn", {"kind": "win", "z0": 0.55, "h": 1.0}, "up"], ext=0.11, detail=0)
    for s in ("left", "right"):
        with k.side(s, HX, HY2, cy=0.0) as L:
            k.timber_wall(L, U0b, U1b, [-HY2 + 0.09, -0.75, 0.75, HY2 - 0.09],
                          ["x", {"kind": "win", "z0": 0.5, "h": 1.0, "panes": (1, 2)}, "x"], detail=0)
    k.stage("floor2")

    # ---------------------------------------------------------------- roof
    r = k.gable_roof(ROOFK, -HX, HX, -HY2, HY2, U1b, PITCH, over=0.35, verge=0.3,
                     tile_w=tile_w, course=course)
    for s in ("left", "right"):
        with k.side(s, HX, HY2, cy=0.0):
            k.gable_wall(HY2, U1b, r["gable"], style="timber", window=(s == "right"))
    for sx in (-1, 1):
        k.finial(sx * HX, 0.0, r["ridge"] + 0.05, h=0.5)
    if V == 4:
        k.dormer(0.0, r["eave"], r["run"], r["rise"], cy=0.0, side=-1, w=1.35, wall_h=1.1, inset=1.0,
                flowers=True)
    k.stage("roof")

    # ---------------------------------------------------------------- chimney
    k.chimney(HX - 0.55, 1.6, r["ridge"] - 1.6 * r["tan"] - 0.35, r["ridge"] + 0.9, sx=0.62, sy=0.66, pots=2)
    k.stage("chimney")

    if V in (2, 4):
        k.mirror_x()
    print("triangles:", k.tri_count())
    k.finish_checked((8.6, 11.2), 20000, cam_dir=(1.0, -1.55, 0.62), fit=0.95)


if __name__ == "__main__":
    build(variant_arg())
