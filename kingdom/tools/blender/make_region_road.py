"""Region set 4: ROAD AND TRAVEL (roadside inn, wayshrine, milestone, stone and wooden bridges,
checkpoint barrier + separate boom, toll booth, covered caravan wagon).

Run headless (Blender 5.x) from the repo root:
    blender -b --factory-startup --python kingdom/tools/blender/make_region_road.py -- [names...|all] [--sheet]

Outputs kingdom/assets/generated/region/road/<name>.glb + _lod1.glb and
docs/kingdom/blender_previews/region_road_sheet.png. Same painted texture set and conventions as
the farm set (region_struct.py). Bridges span along Blender Y (Godot -Z): road runs along the bridge.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import region_kit as K
from region_struct import *   # noqa: F401,F403
import region_struct as S

LAMP = (1.0, 0.72, 0.35)
LIT = (0.95, 0.62, 0.3)


def lantern(k, x, y, z):
    k.box((0.18, 0.18, 0.26), (x, y, z), "RG_Glow", LAMP)
    k.box((0.24, 0.24, 0.04), (x, y, z + 0.15), "RG_Iron", IRON)
    k.box((0.22, 0.22, 0.03), (x, y, z - 0.14), "RG_Iron", IRON)


def lit_window(k, x, y, z0, w, h, face=-1, lod=0, shutters=False):
    window(k, x, y, z0, w, h, face=face, shutters=shutters, lod=lod)
    k.push((x, y, z0), (0, 0, 0 if face < 0 else math.pi))
    k.box((w - 0.04, 0.02, h - 0.04), (0, -0.065, h / 2), "RG_Glow", tuple(c * 0.55 for c in LIT))
    k.pop()


def half_timber(k, x0, x1, y, z0, z1, lod, face=-1, braces=True):
    """Timber framing on a plaster face (wall plane y, outward = face)."""
    off = face * 0.07
    n = max(2, int((x1 - x0) / 1.4) + 1)
    xs = [x0 + (x1 - x0) * i / (n - 1) for i in range(n)]
    for x in xs:
        k.beam((x, y + off, z0), (x, y + off, z1), 0.18, 0.1, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    for z in (z0 + 0.08, z1 - 0.08):
        k.beam((x0 - 0.1, y + off, z), (x1 + 0.1, y + off, z), 0.18, 0.1, "RG_Timber", jit(k, TIMBER))
    if lod == 0 and braces:
        for i in range(n - 1):
            if i % 2 == 0:
                k.beam((xs[i], y + off * 1.1, z0 + 0.1), (xs[i + 1], y + off * 1.1, z1 - 0.1), 0.15, 0.08, "RG_Timber",
                       jit(k, TIMBER), up=(0, face, 0))


# ============================================================================ inn
def roadside_inn(k, lod):
    L, W, g, e = 9.0, 6.0, 2.9, 5.4          # ground floor stone to g, jettied upper to eave e
    hx, hy = L / 2, W / 2
    j = 0.3                                    # jetty
    stone_t = (0.95, 0.93, 0.9)
    k.box((L, W, g), (0, 0, g / 2), "RG_Stone", stone_t)
    k.box((L + 2 * j, W + 2 * j, e - g), (0, 0, g + (e - g) / 2), "RG_Plaster", (1.0, 0.97, 0.9))
    k.beam((-hx - j - 0.1, -hy - j - 0.05, g + 0.05), (hx + j + 0.1, -hy - j - 0.05, g + 0.05), 0.22, 0.2, "RG_Timber",
           jit(k, TIMBER))
    for y, f in ((-hy - j, -1), (hy + j, 1)):
        half_timber(k, -hx - j + 0.1, hx + j - 0.1, y, g, e, lod, face=f)
    k.push((0, 0, 0), (0, 0, math.pi / 2))
    for y, f in ((-hx - j, -1), (hx + j, 1)):
        half_timber(k, -hy - j + 0.1, hy + j - 0.1, y, g, e, lod, face=f, braces=False)
    k.pop()
    # openings: front door with lantern + windows below, lit windows above
    door(k, -1.0, -hy - 0.02, 1.3, 2.2, tint=(0.65, 0.4, 0.3))
    lit_window(k, -3.2, -hy - 0.04, 0.9, 0.9, 1.1, lod=lod, shutters=True)
    lit_window(k, 1.2, -hy - 0.04, 0.9, 0.9, 1.1, lod=lod, shutters=True)
    lit_window(k, 3.2, -hy - 0.04, 0.9, 0.9, 1.1, lod=lod, shutters=True)
    for x in (-3.0, -0.6, 1.8, 3.6):
        lit_window(k, x, -hy - j - 0.02, g + 0.8, 0.75, 1.0, lod=lod)
    lit_window(k, 0, hy + j + 0.02, g + 0.8, 0.75, 1.0, face=1, lod=lod)
    lit_window(k, 2.0, hy + 0.02, 0.9, 0.8, 1.0, face=1, lod=lod)
    rz = gable_roof(k, 0, 0, L + 2 * j, W + 2 * j, e, pitch=47, over_x=0.45, over_y=0.5, th=0.16, mat="RG_Slate")
    for x in (-hx - j, hx + j):
        gable_end(k, 0, x, 0, W + 2 * j, e - 0.05, rz - 0.12, mat="RG_Plaster", tint=(1.0, 0.97, 0.9))
    # chimney on the west gable
    k.box((1.0, 1.1, rz + 1.0), (-hx - j - 0.3, 0.8, (rz + 1.0) / 2), "RG_Stone", (0.85, 0.83, 0.8))
    k.box((1.15, 1.25, 0.15), (-hx - j - 0.3, 0.8, rz + 1.0), "RG_Stone", (0.7, 0.68, 0.66))
    k.markers = [("chimney_top", Vector((-hx - j - 0.3, 0.8, rz + 1.1))), ("door", Vector((-1.0, -hy - 0.3, 0)))]
    # porch roof over the door
    for x in (-2.1, 0.1):
        k.beam((x, -hy - 1.4, 0), (x, -hy - 1.4, 2.6), 0.16, 0.16, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    k.push((-1.0, 0, 0))
    roof_side(k, -1.5, 1.5, -hy - 1.7, 2.55, -hy - 0.05, 3.1, 0.1, "RG_Shingle")
    k.pop()
    # hanging sign
    k.beam((2.4, -hy - j - 0.05, g + 0.3), (2.4, -hy - j - 1.2, g + 0.3), 0.1, 0.1, "RG_Iron", IRON)
    k.box((0.9, 0.06, 0.65), (2.4, -hy - j - 0.85, g - 0.25), "RG_Planks", (0.8, 0.6, 0.45), grain=0)
    k.box((0.3, 0.08, 0.35), (2.4, -hy - j - 0.85, g - 0.25), "RG_Canvas", hexc("d9a93a"))
    lantern(k, 0.35, -hy - 0.25, 2.3)
    lantern(k, -2.1, -hy - 1.4, 2.35)
    # stable lean-to on the east side
    for y in (-2.2, 2.2):
        post(k, hx + 2.4, y, 0, 2.2, 0.18)
    k.push((0, 0, 0), (0, 0, math.pi / 2))
    roof_side(k, -2.6, 2.6, -hx - 2.7, 2.2, -hx - 0.02, 3.1, 0.2, "RG_Thatch")
    k.pop()
    if lod == 0:
        k.box((1.0, 3.8, 0.9), (hx + 2.4, 0, 0.45), "RG_Planks", jit(k, WOOD_DK), grain=0)   # stall rail wall
        hay_pile(k, (hx + 1.3, 1.0, 0), 0.7, 0.5, seed=2)
        barrel(k, 3.9, -hy - 0.6, 0)
        barrel(k, 4.4, -hy - 0.9, 0)
        # bench
        k.box((1.6, 0.35, 0.07), (1.8, -hy - 0.5, 0.45), "RG_Planks", jit(k, WOOD), grain=0)
        for x in (1.2, 2.4):
            k.box((0.08, 0.3, 0.45), (x, -hy - 0.5, 0.22), "RG_Timber", jit(k, WOOD_DK))


# ============================================================================ wayshrine / milestone
def wayshrine(k, lod):
    k.box((1.5, 1.2, 0.3), (0, 0, 0.15), "RG_Stone", (0.9, 0.9, 0.88))
    k.box((1.1, 0.8, 1.2), (0, 0.05, 0.9), "RG_Stone", (0.95, 0.93, 0.9))
    k.box((0.7, 0.3, 0.8), (0, -0.25, 1.05), "RG_Timber", (0.18, 0.16, 0.15))       # niche
    # little carved figure: stacked lathe
    k.lathe([(0.12, 0), (0.14, 0.3), (0.09, 0.45), (0.1, 0.55), (0.0, 0.62)], (0, -0.2, 0.68), "RG_Plaster",
            (0.85, 0.82, 0.75), segs=8 if lod == 0 else 5)
    for x in (-0.6, 0.6):
        k.beam((x, 0.05, 1.5), (x, 0.05, 2.1), 0.14, 0.14, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    k.box((1.3, 0.9, 0.1), (0, 0.05, 1.5), "RG_Stone", (0.85, 0.83, 0.8))
    rz = gable_roof(k, 0, 0.05, 1.2, 0.9, 2.05, pitch=40, over_x=0.15, over_y=0.25, th=0.08, mat="RG_Shingle")
    # candles + offering
    for x in (-0.2, 0.2):
        k.cyl(0.03, 0.12, (x, -0.3, 0.68), "RG_Plaster", (1, 0.97, 0.9), segs=6)
        k.box((0.025, 0.025, 0.05), (x, -0.3, 0.83), "RG_Glow", LAMP)
    if lod == 0:
        S.lumpy(k, (0.45, -0.75, 0), (0.25, 0.2, 0.2), "RG_Crop", (1, 1, 1), subdiv=1) if False else None
        for i, (x, y) in enumerate(((-0.55, -0.75), (0.5, -0.7), (0.0, -0.85))):
            a = k.rng.uniform(0, math.pi)
            for b in (0, math.pi / 2):
                r = Vector((math.cos(a + b), math.sin(a + b), 0))
                k.card(Vector((x, y, 0.0)), r, Vector((0, 0, 1)), 0.5, 0.45, (2, 2 + i % 2), mat="RG_Crop",
                       cols=(1, 1, 1, 1), base=True)
        k.markers = [("interact", Vector((0, -1.0, 0)))]


def milestone(k, lod):
    segs = 10 if lod == 0 else 6
    k.box((0.7, 0.5, 0.15), (0, 0, 0.05), "RG_Stone", (0.85, 0.83, 0.8))
    k.box((0.5, 0.32, 0.95), (0, 0, 0.6), "RG_Cliff", (0.95, 0.94, 0.9))
    k.cyl(0.25, 0.3, (0, 0.15, 1.07), "RG_Cliff", (0.95, 0.94, 0.9), rot=(math.pi / 2, 0, 0), segs=segs)
    k.box((0.36, 0.02, 0.05), (0, -0.17, 0.95), "RG_Timber", HOLE)
    k.box((0.26, 0.02, 0.05), (0, -0.17, 0.82), "RG_Timber", HOLE)
    k.box((0.3, 0.02, 0.05), (0, -0.17, 0.69), "RG_Timber", HOLE)
    if lod == 0:
        k.box((0.52, 0.34, 0.12), (0, 0, 0.18), "RG_Stone", (0.55, 0.7, 0.4))   # moss band at the foot


# ============================================================================ bridges
def bridge_stone(k, lod):
    """Single-arch stone bridge, 12 m long (Y), 3.6 m wide, deck at 2.6 m, 6 m span."""
    Lb, Wb, H, span, spring = 12.0, 3.6, 2.6, 6.0, 0.8
    n = 10 if lod == 0 else 5
    R = span / 2
    pts = [(-Lb / 2, -0.8), (-R, -0.8), (-R, spring)]
    for i in range(1, n):
        a = math.pi - math.pi * i / n
        pts.append((math.cos(a) * R, spring + math.sin(a) * R * 0.62))
    pts += [(R, spring), (R, -0.8), (Lb / 2, -0.8), (Lb / 2, H - 0.9), (Lb * 0.25, H), (-Lb * 0.25, H),
            (-Lb / 2, H - 0.9)]
    k.prism(pts, Wb, (0, 0, 0), "RG_Stone", (0.95, 0.93, 0.9), rot=(0, 0, math.pi / 2))
    # voussoir ring (darker dressed stones) on both faces
    for sx in (-1, 1):
        for i in range(n):
            a0 = math.pi - math.pi * i / n
            a1 = math.pi - math.pi * (i + 1) / n
            p0 = Vector((sx * (Wb / 2 + 0.02), math.cos(a0) * R, spring + math.sin(a0) * R * 0.62))
            p1 = Vector((sx * (Wb / 2 + 0.02), math.cos(a1) * R, spring + math.sin(a1) * R * 0.62))
            q0 = Vector((sx * (Wb / 2 + 0.02), math.cos(a0) * (R + 0.5), spring + math.sin(a0) * (R * 0.62 + 0.5)))
            q1 = Vector((sx * (Wb / 2 + 0.02), math.cos(a1) * (R + 0.5), spring + math.sin(a1) * (R * 0.62 + 0.5)))
            f = [p0, p1, q1, q0] if sx > 0 else [p1, p0, q0, q1]
            if K.newell(f).x * sx < 0:
                f = f[::-1]
            k.add([f], "RG_Stone", jit(k, (0.8, 0.78, 0.75), 0.06))
    # parapets following the deck
    prof = [(-Lb / 2, H - 0.9), (-Lb * 0.25, H), (Lb * 0.25, H), (Lb / 2, H - 0.9)]
    for sx in (-1, 1):
        for (y0, z0), (y1, z1) in zip(prof[:-1], prof[1:]):
            k.beam((sx * (Wb / 2 - 0.2), y0, z0), (sx * (Wb / 2 - 0.2), y1, z1), 0.4, 0.75, "RG_Stone",
                   (0.92, 0.9, 0.86), up=(1, 0, 0), ext=0.18)
            k.beam((sx * (Wb / 2 - 0.2), y0, z0 + 0.4), (sx * (Wb / 2 - 0.2), y1, z1 + 0.4), 0.5, 0.12, "RG_Stone",
                   (0.78, 0.76, 0.72), up=(1, 0, 0), ext=0.2)
    # cobbled deck strip
    for (y0, z0), (y1, z1) in zip(prof[:-1], prof[1:]):
        k.poly([(-Wb / 2 + 0.4, y0, z0 + 0.03), (Wb / 2 - 0.4, y0, z0 + 0.03), (Wb / 2 - 0.4, y1, z1 + 0.03),
                (-Wb / 2 + 0.4, y1, z1 + 0.03)], "RG_Soil", (0.95, 0.9, 0.82))
    if lod == 0:
        for sy in (-1, 1):
            k.box((0.5, 0.5, 1.4), (-(Wb / 2 - 0.2), sy * (Lb / 2 - 0.2), H - 0.5), "RG_Stone", (0.85, 0.83, 0.8))
            k.box((0.5, 0.5, 1.4), ((Wb / 2 - 0.2), sy * (Lb / 2 - 0.2), H - 0.5), "RG_Stone", (0.85, 0.83, 0.8))


def bridge_wood(k, lod):
    """10 m plank bridge on log trestles (Y), 3 m wide, deck at 1.6 m."""
    Lb, Wb, H = 10.0, 3.0, 1.6
    # deck planks across the span
    n = 24 if lod == 0 else 6
    for i in range(n):
        y = -Lb / 2 + Lb * (i + 0.5) / n
        k.box((Wb, Lb / n - (0.03 if lod == 0 else 0), 0.08), (k.rng.uniform(-0.05, 0.05), y, H), "RG_Planks",
              jit(k, WOOD_GREY, 0.12), grain=0)
    for sx in (-1, 1):
        k.beam((sx * (Wb / 2 - 0.2), -Lb / 2, H - 0.14), (sx * (Wb / 2 - 0.2), Lb / 2, H - 0.14), 0.22, 0.22, "RG_Timber",
               jit(k, TIMBER))
    for y in (-Lb / 2 + 0.3, -1.7, 1.7, Lb / 2 - 0.3):
        for sx in (-1, 1):
            log_post(k, sx * (Wb / 2 - 0.2), y, H - 0.1, 0.14, lod, z0=-1.2)
        log_beam(k, (-Wb / 2 - 0.1, y, H - 0.3), (Wb / 2 + 0.1, y, H - 0.3), 0.1, lod)
        if lod == 0 and abs(y) < 2:
            log_beam(k, (-Wb / 2 + 0.2, y, -0.8), (Wb / 2 - 0.2, y, H - 0.4), 0.07, lod)
    # railings
    for sx in (-1, 1):
        for y in [(-Lb / 2 + Lb * i / 5) for i in range(6)] if lod == 0 else (-Lb / 2, 0, Lb / 2):
            log_post(k, sx * (Wb / 2 - 0.05), y, H + 1.0, 0.06, lod, z0=H)
        log_beam(k, (sx * (Wb / 2 - 0.05), -Lb / 2, H + 0.95), (sx * (Wb / 2 - 0.05), Lb / 2, H + 0.95), 0.05, lod)
        if lod == 0:
            log_beam(k, (sx * (Wb / 2 - 0.05), -Lb / 2, H + 0.5), (sx * (Wb / 2 - 0.05), Lb / 2, H + 0.5), 0.04, lod)
    # ramps
    for sy in (-1, 1):
        k.push((0, sy * (Lb / 2), 0))
        k.beam((0, 0, H - 0.05), (0, sy * 2.0, 0.0), Wb, 0.1, "RG_Planks", jit(k, WOOD_GREY), up=(1, 0, 0))
        k.pop()


# ============================================================================ checkpoint
BOOM_PIVOT = Vector((-2.2, 0, 1.05))


def checkpoint_barrier(k, lod):
    """Posts, counterweight post and a boom; the boom is ALSO exported alone as checkpoint_boom
    (pivot at the empty 'boom_pivot') so the game can raise it."""
    log_post(k, -2.2, 0, 1.2, 0.14, lod)
    log_post(k, 2.3, 0, 1.0, 0.11, lod)
    k.box((0.3, 0.3, 0.12), (2.3, 0, 0.95), "RG_Timber", jit(k, WOOD_DK))   # boom rest fork
    checkpoint_boom(k, lod, BOOM_PIVOT)
    k.markers = [("boom_pivot", BOOM_PIVOT)]
    if lod == 0:
        k.box((0.5, 0.08, 0.35), (-2.2, -0.16, 0.7), "RG_Planks", (0.9, 0.8, 0.65), grain=0)   # notice board
        k.box((0.35, 0.02, 0.22), (-2.2, -0.21, 0.7), "RG_Canvas", (1, 0.96, 0.85))


def checkpoint_boom(k, lod, origin=Vector((0, 0, 0))):
    o = Vector(origin)
    n = 8 if lod == 0 else 4
    L = 4.6
    for i in range(n):
        a = o + Vector((0.1 + (L - 0.1) * i / n, 0, 0))
        b = o + Vector((0.1 + (L - 0.1) * (i + 1) / n, 0, 0))
        c = hexc("b8392e") if i % 2 == 0 else (0.95, 0.92, 0.85)
        k.beam(tuple(a), tuple(b), 0.13, 0.13, "RG_Planks", c)
    k.box((0.45, 0.35, 0.4), tuple(o + Vector((-0.35, 0, 0))), "RG_Stone", (0.8, 0.78, 0.75))   # counterweight
    k.cyl(0.06, 0.4, tuple(o + Vector((0, 0.2, 0))), "RG_Iron", IRON, rot=(math.pi / 2, 0, 0), segs=6)


def toll_booth(k, lod):
    L, W, e = 2.2, 2.0, 2.4
    k.box((L + 0.2, W + 0.2, 0.2), (0, 0, 0.1), "RG_Stone", (0.9, 0.9, 0.88))
    for y in (-W / 2, W / 2):
        if y < 0:
            plank_wall(k, -L / 2, L / 2, y, 0.2, 1.0, vertical=False)
            plank_wall(k, -L / 2, L / 2, y, 2.0, e, vertical=False)
            k.box((L + 0.1, 0.45, 0.07), (0, y - 0.15, 1.02), "RG_Planks", jit(k, WOOD_DK), grain=0)  # counter
            for x in (-L / 2, 0, L / 2):
                post(k, x, y, 1.0, 2.0, 0.12)
            k.box((L - 0.2, 0.05, 0.95), (0, y + 0.5, 1.5), "RG_Timber", (0.2, 0.18, 0.16))   # dark interior
        else:
            plank_wall(k, -L / 2, L / 2, y, 0.2, e, vertical=False)
    for x in (-L / 2, L / 2):
        k.box((0.1, W, e - 0.2), (x, 0, 0.2 + (e - 0.2) / 2), "RG_Planks", jit(k, WOOD), grain=1)
    for x in (-L / 2, L / 2):
        for y in (-W / 2, W / 2):
            post(k, x, y, 0.2, e, 0.16)
    rz = gable_roof(k, 0, 0, L, W, e, pitch=38, over_x=0.3, over_y=0.6, th=0.1, mat="RG_Shingle")
    for x in (-L / 2, L / 2):
        gable_end(k, 0, x, 0, W, e - 0.03, rz - 0.08)
    door(k, 0, W / 2 + 0.02, 0.9, 1.9, z0=0.2, face=1)
    lantern(k, L / 2 + 0.25, -W / 2 - 0.2, 2.1)
    k.beam((L / 2 + 0.05, -W / 2 - 0.2, 2.35), (L / 2 + 0.3, -W / 2 - 0.2, 2.35), 0.05, 0.05, "RG_Iron", IRON)
    if lod == 0:
        # banner pole with the realm colours
        log_post(k, -L / 2 - 0.5, -W / 2 - 0.3, 3.6, 0.05, lod)
        k.sheet(((-L / 2 - 0.47, -W / 2 - 0.3, 3.5), (-L / 2 + 0.6, -W / 2 - 0.3, 3.45),
                 (-L / 2 - 0.47, -W / 2 - 0.3, 2.3), (-L / 2 + 0.6, -W / 2 - 0.3, 2.2)), 3, 3, "RG_Canvas",
                tint=hexc("3d5878"), sag_fn=lambda u, v: (0, 0.08 * math.sin(u * 3.0), 0))
        crate(k, L / 2 + 0.5, 0.3, 0, 0.6, 0.3)
        barrel(k, L / 2 + 0.55, -0.5, 0)


# ============================================================================ caravan
def caravan_wagon(k, lod):
    L, W, bz = 3.6, 1.7, 0.95
    k.box((L, W, 0.12), (0, 0, bz), "RG_Planks", jit(k, WOOD), grain=0)
    for y in (-W / 2, W / 2):
        k.box((L, 0.08, 0.5), (0, y, bz + 0.3), "RG_Planks", jit(k, WOOD), grain=0)
    k.box((0.08, W, 0.5), (-L / 2, 0, bz + 0.3), "RG_Planks", jit(k, WOOD), grain=1)
    for x in (-L / 2 + 0.6, L / 2 - 0.6):
        k.beam((x, -W / 2 - 0.15, 0.6), (x, W / 2 + 0.15, 0.6), 0.12, 0.12, "RG_Timber", jit(k, WOOD_DK))
        for y in (-W / 2 - 0.13, W / 2 + 0.13):
            wheel(k, (x, y, 0.6), 0.6 if x < 0 else 0.52, lod=lod, axis="y")
    # striped canvas cover on hoops: one sheet per stripe (crisp colour bands)
    R = W / 2 + 0.05
    z0 = bz + 0.55
    ns = 7 if lod == 0 else 3
    x0, x1 = -L / 2 + 0.05, L / 2 - 0.35
    nv = 7 if lod == 0 else 4
    for i in range(ns):
        a, b = x0 + (x1 - x0) * i / ns, x0 + (x1 - x0) * (i + 1) / ns
        c = hexc("b8453a") if i % 2 == 0 else (0.96, 0.92, 0.84)
        if lod:
            c = (0.95, 0.8, 0.72)
        k.sheet(((a, -R, z0), (b, -R, z0), (a, R, z0), (b, R, z0)), 1, nv, "RG_Canvas", tint=c,
                sag_fn=lambda u, v: (0, -math.cos(math.pi * v) * R - (-R + 2 * R * v), math.sin(math.pi * v) * R * 1.15))
    for x in (x0, (x0 + x1) / 2, x1) if lod == 0 else ():
        pts = [(x, -math.cos(math.pi * t) * (R + 0.02), z0 + math.sin(math.pi * t) * (R * 1.15 + 0.02)) for t in
               [i / 8 for i in range(9)]]
        for p, q in zip(pts[:-1], pts[1:]):
            k.beam(p, q, 0.05, 0.05, "RG_Timber", jit(k, WOOD_DK))
    # shafts + driver bench
    for y in (-0.5, 0.5):
        k.beam((L / 2 - 0.3, y, bz - 0.1), (L / 2 + 2.2, y * 0.8, 0.6), 0.09, 0.09, "RG_Timber", jit(k, WOOD_DK))
    k.box((0.4, W - 0.1, 0.1), (L / 2 - 0.25, 0, bz + 0.55), "RG_Planks", jit(k, WOOD_DK), grain=1)
    if lod == 0:
        crate(k, -L / 2 - 0.1, -0.4, bz - 0.35, 0.45, 0.1)
        barrel(k, -L / 2 - 0.15, 0.35, bz - 0.35, h=0.6, r=0.22)
        lantern(k, L / 2 - 0.3, W / 2 - 0.1, z0 + 0.8)


ASSETS = {
    "roadside_inn": (roadside_inn, 12000, 3600, dict(cam=(1.0, -1.4, 0.55))),
    "wayshrine": (wayshrine, 1500, 500, {}),
    "milestone": (milestone, 400, 150, {}),
    "bridge_stone": (bridge_stone, 3000, 1000, dict(cam=(1.5, -0.9, 0.45))),
    "bridge_wood": (bridge_wood, 3000, 1000, dict(cam=(1.5, -0.9, 0.5))),
    "checkpoint_barrier": (checkpoint_barrier, 1200, 400, {}),
    "checkpoint_boom": (lambda k, lod: checkpoint_boom(k, lod), 600, 200, dict(lift=1.0)),
    "toll_booth": (toll_booth, 3000, 1000, {}),
    "caravan_wagon": (caravan_wagon, 4000, 1200, {}),
}

run_set("road", ASSETS, "RISING ASHES - REGION 1 ROAD AND TRAVEL SET  (TRIS LOD0 / LOD1)")
