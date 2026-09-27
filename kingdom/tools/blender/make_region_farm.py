"""Region set 2: FARM (barn, granary, windmill + separate sails, chicken coop, pig sty, crop rows,
fences, scarecrow, hay wagon) for the first region of Rising Ashes (Godot 4.6, mobile).

Run headless (Blender 5.x) from the repo root:
    blender -b --factory-startup --python kingdom/tools/blender/make_region_farm.py -- [names...|all] [--sheet]

Outputs kingdom/assets/generated/region/farm/<name>.glb + <name>_lod1.glb and
docs/kingdom/blender_previews/region_farm_sheet.png. Shared painted textures in region/textures/
(COLOR_0 = albedo tint, default Godot import). Metres, origin at ground centre, front = Godot +Z.
windmill.glb carries an empty "sail_hub"; windmill_sails.glb has its origin on the hub and turns
around its local Z axis in Godot (Blender -Y).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import region_kit as K
from region_struct import *   # noqa: F401,F403
import region_struct as S


# ============================================================================ barn
def barn(k, lod):
    L, W, eave, plinth = 11.0, 7.0, 4.3, 0.6
    hx, hy = L / 2, W / 2
    stone_plinth(k, -hx - 0.1, hx + 0.1, -hy - 0.1, hy + 0.1, plinth)
    dw, dh = 3.2, 3.4
    # front wall (-Y) with the big double door
    plank_wall(k, -hx, -dw / 2 - 0.2, -hy, plinth, eave)
    plank_wall(k, dw / 2 + 0.2, hx, -hy, plinth, eave)
    plank_wall(k, -dw / 2 - 0.2, dw / 2 + 0.2, -hy, plinth + dh + 0.15, eave)
    plank_wall(k, -hx, hx, hy, plinth, eave)
    for x in (-hx, hx):
        k.box((0.1, W, eave - plinth), (x, 0, (plinth + eave) / 2), "RG_Planks", jit(k, WOOD), grain=2)
    door(k, 0, -hy - 0.02, dw, dh, z0=plinth - 0.35, double=True, tint=(0.78, 0.58, 0.48))
    k.box((dw + 0.4, 1.2, 0.35), (0, -hy - 0.55, plinth - 0.35 / 2 - 0.05), "RG_Stone", (0.95, 0.95, 0.95))  # ramp
    # frame: corner + bay posts, wall plates, braces
    for x in (-hx, -hx / 2 - 0.3, -dw / 2 - 0.3, dw / 2 + 0.3, hx / 2 + 0.3, hx):
        for y in (-hy, hy):
            post(k, x, y + (-0.06 if y < 0 else 0.06), plinth, eave, 0.24)
    for y in (-hy - 0.06, hy + 0.06):
        k.beam((-hx - 0.2, y, eave - 0.1), (hx + 0.2, y, eave - 0.1), 0.26, 0.26, "RG_Timber", jit(k, TIMBER))
        k.beam((-hx - 0.1, y, plinth + 0.08), (hx + 0.1, y, plinth + 0.08), 0.16, 0.2, "RG_Timber", jit(k, TIMBER))
    if lod == 0:
        for x0, x1 in ((-hx, -hx / 2 - 0.3), (hx / 2 + 0.3, hx)):
            for y in (-hy - 0.09, hy + 0.09):
                k.beam((x0, y, plinth + 0.2), (x1, y, eave - 0.3), 0.14, 0.08, "RG_Timber", jit(k, TIMBER), up=(0, -1, 0))
        window(k, -hx / 2 - 1.6, -hy - 0.07, plinth + 1.6, 0.7, 0.7, shutters=True, lod=lod)
        window(k, hx / 2 + 1.6, -hy - 0.07, plinth + 1.6, 0.7, 0.7, shutters=True, lod=lod)
    rz = gable_roof(k, 0, 0, L, W, eave, pitch=44, over_x=0.5, over_y=0.6, th=0.16, mat="RG_Shingle")
    for x in (-hx, hx):
        gable_end(k, 0, x, 0, W, eave - 0.05, rz - 0.1)
    # hay loft door on the west gable
    k.push((-hx - 0.08, 0, 0), (0, 0, -math.pi / 2))
    k.box((1.3, 0.08, 1.3), (0, 0, eave + 0.8), "RG_Planks", (0.78, 0.58, 0.48), grain=2)
    k.beam((-0.8, -0.05, eave + 1.5), (0.8, -0.05, eave + 1.5), 0.16, 0.16, "RG_Timber", jit(k, TIMBER))
    k.beam((0, -0.05, eave + 1.5), (0, -1.1, eave + 1.9), 0.15, 0.15, "RG_Timber", jit(k, TIMBER))   # hoist beam
    k.pop()
    if lod == 0:
        for i, (x, y) in enumerate(((hx - 1.2, -hy - 1.0), (hx - 2.2, -hy - 0.9))):
            k.box((1.0, 0.5, 0.45), (x, y, 0.225 + (0.45 if i == 2 else 0)), "RG_Hay", jit(k, (1, 0.95, 0.85)),
                  rot=(0, 0, k.rng.uniform(-0.3, 0.3)), grain=0)
        k.box((1.0, 0.5, 0.45), (hx - 1.7, -hy - 0.95, 0.675), "RG_Hay", jit(k, (1, 0.95, 0.85)), rot=(0, 0, 0.2), grain=0)
        barrel(k, -hx + 1.0, -hy - 0.7, 0, lod=lod)
        wheel(k, (-hx + 2.1, -hy - 0.25, 0.55), 0.55, lod=lod, axis="y")


# ============================================================================ granary
def staddle(k, x, y, h=0.75, lod=0):
    k.cyl(0.16, h - 0.08, (x, y, 0), "RG_Stone", jit(k, STONE), segs=8 if lod == 0 else 5, r2=0.1)
    k.cyl(0.36, 0.1, (x, y, h - 0.1), "RG_Stone", jit(k, STONE), segs=10 if lod == 0 else 6)


def granary(k, lod):
    L, W, fz, eave = 4.2, 3.2, 0.85, 3.0
    hx, hy = L / 2, W / 2
    for x in (-hx + 0.2, 0, hx - 0.2):
        for y in (-hy + 0.2, hy - 0.2):
            staddle(k, x, y, fz - 0.1, lod)
    k.box((L + 0.2, W + 0.2, 0.18), (0, 0, fz), "RG_Timber", jit(k, TIMBER), grain=0)
    for y in (-hy, hy):
        plank_wall(k, -hx, hx, y, fz + 0.09, eave, vertical=False)
    for x in (-hx, hx):
        k.box((0.1, W, eave - fz), (x, 0, (fz + eave) / 2), "RG_Planks", jit(k, WOOD), grain=1)
    for x in (-hx, hx):
        for y in (-hy, hy):
            post(k, x + (0.05 if x > 0 else -0.05), y + (0.05 if y > 0 else -0.05), fz, eave, 0.2)
    for y in (-hy - 0.05, hy + 0.05):
        k.beam((-hx - 0.15, y, eave - 0.08), (hx + 0.15, y, eave - 0.08), 0.2, 0.2, "RG_Timber", jit(k, TIMBER))
    door(k, 0.4, -hy - 0.03, 0.9, 1.7, z0=fz + 0.09, tint=(0.8, 0.62, 0.5))
    rz = gable_roof(k, 0, 0, L, W, eave, pitch=50, over_x=0.4, over_y=0.55, th=0.32, mat="RG_Thatch")
    for x in (-hx, hx):
        gable_end(k, 0, x, 0, W, eave - 0.05, rz - 0.3, vertical=True)
    # steps up to the door
    for i in range(3):
        z = fz - (i + 1) * 0.25
        k.box((1.0, 0.35, 0.08), (0.4, -hy - 0.35 - i * 0.3, z + 0.12), "RG_Planks", jit(k, WOOD_DK), grain=0)
    for sx in (-1, 1):
        k.beam((0.4 + sx * 0.5, -hy - 0.15, fz), (0.4 + sx * 0.5, -hy - 1.15, 0.0), 0.1, 0.12, "RG_Timber",
               jit(k, TIMBER))
    if lod == 0:
        sack(k, -1.1, -hy - 0.6, 0, 1.0, 0.3)
        sack(k, -1.55, -hy - 0.5, 0, 0.9, -0.4)
        sack(k, -1.3, -hy - 0.95, 0, 0.95, 1.0)


# ============================================================================ windmill
TOWER_H = 9.2
HUB = Vector((0, -2.95, 10.1))


def windmill(k, lod):
    segs = 16 if lod == 0 else 10
    prof = [(3.1, -0.1), (3.05, 0.6), (2.75, 3.0), (2.45, 6.0), (2.2, TOWER_H)]
    k.lathe(prof, (0, 0, 0), "RG_Stone", (0.97, 0.95, 0.92), segs=segs, caps=(False, True), uscale=2.0)
    k.cyl(3.3, 0.5, (0, 0, -0.1), "RG_Stone", (0.85, 0.83, 0.8), segs=segs)
    # timber band + gallery beam at the cap base
    k.cyl(2.35, 0.3, (0, 0, TOWER_H - 0.05), "RG_Timber", jit(k, TIMBER), segs=segs)
    # cap: boat-ish cone of shingles
    cap = [(2.6, 0), (2.45, 0.6), (1.9, 1.6), (1.0, 2.4), (0.2, 2.8), (0.0, 2.85)]
    k.lathe(cap, (0, 0.25, TOWER_H + 0.25), "RG_Shingle", (0.95, 0.9, 0.9), segs=segs, caps=(True, False),
            uscale=1.2)
    k.cyl(0.12, 0.6, (0, 0.25, TOWER_H + 3.0), "RG_Timber", jit(k, TIMBER), segs=6)   # finial
    # windshaft + hub block
    k.cyl(0.32, 1.4, (0, -1.6, HUB.z), "RG_Timber", jit(k, WOOD_DK), rot=(math.pi / 2, 0, 0), segs=8)
    k.box((0.7, 0.4, 0.7), (0, HUB.y + 0.35, HUB.z), "RG_Timber", jit(k, WOOD_DK))
    # door + windows (front -Y), cut in as dark insets with frames
    door(k, 0, -3.05, 1.1, 2.0, z0=0.4, tint=(0.75, 0.5, 0.4))
    k.box((1.6, 0.9, 0.4), (0, -3.25, 0.2), "RG_Stone", (0.9, 0.9, 0.9))   # step
    window(k, 0, -2.6, 4.2, 0.6, 0.8, shutters=False, lod=lod)
    k.push((0, 0, 0), (0, 0, math.pi * 0.6))
    window(k, 0, -2.4, 6.4, 0.55, 0.75, shutters=False, lod=lod)
    k.pop()
    k.push((0, 0, 0), (0, 0, -math.pi * 0.55))
    window(k, 0, -2.85, 2.4, 0.6, 0.8, shutters=True, lod=lod)
    k.pop()
    if lod == 0:
        sack(k, 1.4, -3.2, 0, 1.0, 0.2)
        sack(k, 1.9, -3.0, 0, 0.9, -0.5)
        barrel(k, -1.6, -3.1, 0, lod=lod)
    k.markers = [("sail_hub", HUB)]


def windmill_sails(k, lod):
    """4 sail arms in the XZ plane around the origin (the hub). Rotate around Blender -Y / Godot +Z."""
    k.cyl(0.35, 0.5, (0, 0.05, 0), "RG_Timber", jit(k, WOOD_DK), rot=(math.pi / 2, 0, 0), segs=8)
    for i in range(4):
        a = i / 4 * math.tau + 0.3
        d = Vector((math.cos(a), 0, math.sin(a)))
        side = Vector((-math.sin(a), 0, math.cos(a)))
        k.beam(tuple(d * 0.2), tuple(d * 7.6), 0.2, 0.18, "RG_Timber", jit(k, TIMBER), up=(0, 1, 0))
        # lattice frame on the trailing side
        r0, r1, w = 1.4, 7.4, 1.35
        for s in (0.02, 1.0):
            k.beam(tuple(d * r0 + side * w * s - Vector((0, 0.05, 0))), tuple(d * r1 + side * w * s - Vector((0, 0.05, 0))),
                   0.07, 0.07, "RG_Timber", jit(k, TIMBER), up=(0, 1, 0))
        nbar = 9 if lod == 0 else 3
        for j in range(nbar):
            t = r0 + (r1 - r0) * j / (nbar - 1)
            k.beam(tuple(d * t - Vector((0, 0.05, 0))), tuple(d * t + side * w - Vector((0, 0.05, 0))), 0.05, 0.05,
                   "RG_Timber", jit(k, TIMBER), up=(0, 1, 0))
        # canvas sail, slightly billowed
        p00 = d * (r0 + 0.1) + side * 0.08 - Vector((0, 0.1, 0))
        p10 = d * (r1 - 0.1) + side * 0.08 - Vector((0, 0.1, 0))
        p01 = d * (r0 + 0.1) + side * (w - 0.08) - Vector((0, 0.1, 0))
        p11 = d * (r1 - 0.1) + side * (w - 0.08) - Vector((0, 0.1, 0))
        k.sheet((p00, p10, p01, p11), 4 if lod == 0 else 1, 1, "RG_Canvas", tint=(1, 0.97, 0.9),
                sag_fn=lambda u, v: (0, 0.12 * math.sin(math.pi * v) * (0.6 + 0.4 * u), 0))


# ============================================================================ chicken coop
def chicken_coop(k, lod):
    L, W, fz, eave = 1.8, 1.3, 0.6, 1.65
    hx, hy = L / 2, W / 2
    for x in (-hx + 0.08, hx - 0.08):
        for y in (-hy + 0.08, hy - 0.08):
            post(k, x, y, 0, eave, 0.12)
    k.box((L, W, 0.08), (0, 0, fz), "RG_Planks", jit(k, WOOD), grain=0)
    for y in (-hy, hy):
        plank_wall(k, -hx, hx, y, fz, eave, th=0.06, vertical=False)
    for x in (-hx, hx):
        k.box((0.06, W, eave - fz), (x, 0, (fz + eave) / 2), "RG_Planks", jit(k, WOOD), grain=1)
    rz = gable_roof(k, 0, 0, L, W, eave, pitch=35, over_x=0.2, over_y=0.25, th=0.08, mat="RG_Shingle")
    for x in (-hx, hx):
        gable_end(k, 0, x, 0, W, eave - 0.03, rz - 0.06, th=0.06)
    k.box((0.34, 0.05, 0.4), (0.35, -hy - 0.03, fz + 0.26), "RG_Timber", HOLE)   # pop hole
    # ramp with cleats
    k.beam((0.35, -hy - 0.05, fz), (0.35, -hy - 1.2, 0.02), 0.36, 0.04, "RG_Planks", jit(k, WOOD_DK),
           up=(1, 0, 0))
    if lod == 0:
        for i in range(4):
            t = (i + 0.5) / 4
            k.box((0.34, 0.04, 0.03), (0.35, -hy - 0.05 - 1.15 * t, fz * (1 - t) + 0.05), "RG_Timber", jit(k, WOOD_DK))
        # nest box on the side
        k.box((0.45, 0.8, 0.45), (hx + 0.24, 0, fz + 0.3), "RG_Planks", jit(k, WOOD), grain=1)
        k.box((0.6, 0.95, 0.06), (hx + 0.28, 0, fz + 0.56), "RG_Shingle", (0.95, 0.9, 0.9), rot=(0, 0.35, 0))
        # small run fence
        fence_run(k, -1.6, 1.6, -2.6, h=0.8, posts=4, rails=(0.25, 0.6), lod=lod)
        k.push((0, 0, 0), (0, 0, math.pi / 2))
        fence_run(k, -2.6, -0.7, 1.6, h=0.8, posts=2, rails=(0.25, 0.6), lod=lod)
        fence_run(k, -2.6, -0.7, -1.6, h=0.8, posts=2, rails=(0.25, 0.6), lod=lod)
        k.pop()
        hay_pile(k, (-0.5, -1.3, 0), 0.35, 0.15, seed=3, lod=lod)


# ============================================================================ pig sty
def pig_sty(k, lod):
    L, W, h, t = 4.4, 3.6, 0.9, 0.36
    hx, hy = L / 2, W / 2
    ts = (0.97, 0.95, 0.9)
    k.box((L, t, h), (0, hy - t / 2, h / 2), "RG_Stone", jit(k, ts, 0.04))
    k.box((t, W - 2 * t, h), (-hx + t / 2, 0, h / 2), "RG_Stone", jit(k, ts, 0.04))
    k.box((t, W - 2 * t, h), (hx - t / 2, 0, h / 2), "RG_Stone", jit(k, ts, 0.04))
    k.box((1.3, t, h), (-hx + 0.65, -hy + t / 2, h / 2), "RG_Stone", jit(k, ts, 0.04))
    k.box((1.3, t, h), (hx - 0.65, -hy + t / 2, h / 2), "RG_Stone", jit(k, ts, 0.04))
    # coping
    for (sx, sy, cx, cy) in ((L + 0.1, t + 0.1, 0, hy - t / 2), (t + 0.1, W - t, -hx + t / 2, -t / 2),
                             (t + 0.1, W - t, hx - t / 2, -t / 2)):
        k.box((sx, sy, 0.1), (cx, cy, h + 0.05), "RG_Stone", (0.82, 0.8, 0.78))
    # plank gate in the front gap
    k.box((L - 2.66, 0.06, 0.85), (0, -hy + 0.1, 0.5), "RG_Planks", jit(k, (0.85, 0.75, 0.65)), grain=0)
    for x in (-(L - 2.6) / 2 + 0.1, (L - 2.6) / 2 - 0.1):
        k.beam((x, -hy + 0.04, 0.1), (x, -hy + 0.04, 0.95), 0.1, 0.05, "RG_Timber", jit(k, WOOD_DK), up=(1, 0, 0))
    k.box((L - 2 * t, W - 2 * t, 0.06), (0, 0, 0.03), "RG_Soil", (0.8, 0.72, 0.62))
    # lean-to shelter over the back half
    for x in (-hx + t / 2, hx - t / 2):
        post(k, x, -0.1, h, 1.82, 0.16)
    k.push((0, 0, 0))
    roof_side(k, -hx - 0.3, hx + 0.3, -0.5, 1.85, hy + 0.35, 2.5, 0.28, "RG_Thatch")
    k.pop()
    k.beam((-hx - 0.2, -0.1, 1.76), (hx + 0.2, -0.1, 1.76), 0.18, 0.18, "RG_Timber", jit(k, TIMBER))
    # trough
    k.push((0.6, -0.9, 0))
    k.box((1.3, 0.45, 0.3), (0, 0, 0.21), "RG_Planks", jit(k, WOOD_DK), grain=0)
    k.box((1.2, 0.35, 0.02), (0, 0, 0.33), "RG_Soil", (0.6, 0.55, 0.45))
    k.pop()
    if lod == 0:
        hay_pile(k, (-1.2, 0.8, 0.06), 0.6, 0.35, seed=5, lod=lod)
        k.box((0.5, 0.5, 0.3), (1.5, 1.0, 0.2), "RG_Planks", jit(k, WOOD), grain=0)


# ============================================================================ crops
def soil_rows(k, L, W, n, lod):
    k.box((L, W, 0.06), (0, 0, 0.0), "RG_Soil", (0.85, 0.8, 0.72), skip=("-z",))
    rows = []
    for i in range(n):
        y = -W / 2 + W * (i + 0.5) / n
        rows.append(y)
        k.prism([(-0.28, 0.03), (0.28, 0.03), (0.12, 0.2), (-0.12, 0.2)], L - 0.2, (0, y, 0), "RG_Soil",
                (0.95, 0.9, 0.82), rot=(0, 0, math.pi / 2))
    return rows


def crop_wheat(k, lod):
    L, W = 4.0, 4.0
    rows = soil_rows(k, L, W, 5, lod)
    per = 7
    for y in rows:
        for i in range(per):
            x = -L / 2 + 0.3 + (L - 0.6) * (i + k.rng.uniform(0.3, 0.7)) / per
            h = k.rng.uniform(0.85, 1.05)
            for j, a in enumerate((0.0, math.pi / 2) if lod == 0 else (k.rng.uniform(0, 1),)):
                a += k.rng.uniform(-0.3, 0.3) + (0.8 if lod else 0)
                r = Vector((math.cos(a), math.sin(a), 0))
                k.card(Vector((x, y, 0.12)), r, Vector((0, 0, 1)), 0.85, h, (3, 3), mat="RG_Crop",
                       cols=(*K.lin((1, 1, 1)), 1.0), base=True)
    k.markers = []


def crop_cabbage(k, lod):
    L, W = 4.0, 3.6
    rows = soil_rows(k, L, W, 4, lod)
    per = 6
    for y in rows:
        for i in range(per):
            x = -L / 2 + 0.35 + (L - 0.7) * (i + 0.5) / per + k.rng.uniform(-0.08, 0.08)
            s = k.rng.uniform(0.85, 1.1)
            S.lumpy(k, (x, y, 0.14), (0.2 * s, 0.2 * s, 0.17 * s), "RG_Plaster", jit(k, (0.62, 0.8, 0.45), 0.08),
                    seed=int(x * 10 + y * 7), subdiv=1 if lod == 0 else 0, sink=0.3)
            if lod == 0:
                for j in range(3):
                    a = j / 3 * math.tau + k.rng.uniform(0, 1)
                    r = Vector((math.cos(a), math.sin(a), 0))
                    k.card(Vector((x, y, 0.1)) + Vector((-r.y, r.x, 0)) * 0.12, r,
                           Vector((-r.y * 0.9, r.x * 0.9, 0.45)).normalized(), 0.42, 0.34, (1, 2), mat="RG_Crop",
                           cols=(*K.lin((0.85, 1.0, 0.8)), 1.0), base=True)


# ============================================================================ fences
def fence_rail(k, lod):
    """3 m split-rail section: posts at x = -1.5 and +1.5 (tile along X)."""
    for x in (-1.5, 1.5):
        log_post(k, x, 0, 1.15, 0.085, lod)
    for z in (0.45, 0.9):
        log_beam(k, (-1.62, -0.09, z + k.rng.uniform(-0.03, 0.03)), (1.62, -0.09, z + k.rng.uniform(-0.03, 0.03)),
                 0.055, lod)


def fence_picket(k, lod):
    """2 m plank fence section (x = -1..1)."""
    for x in (-1.0, 1.0):
        post(k, x, 0, -0.1, 1.15, 0.12, jit(k, WOOD_GREY))
    for z in (0.3, 0.85):
        k.beam((-1.05, 0.07, z), (1.05, 0.07, z), 0.09, 0.05, "RG_Timber", jit(k, WOOD_GREY))
    n = 9 if lod == 0 else 5
    if lod == 0:
        for i in range(n):
            x = -0.95 + 1.9 * (i + 0.5) / n
            h = 1.0 + k.rng.uniform(-0.05, 0.05)
            k.prism([(-0.08, 0.05), (0.08, 0.05), (0.08, h), (0, h + 0.1), (-0.08, h)], 0.03, (x, 0.0, 0),
                    "RG_Planks", jit(k, WOOD_GREY, 0.1), grain=2)
    else:
        k.box((1.9, 0.03, 1.0), (0, 0, 0.55), "RG_Planks", jit(k, WOOD_GREY), grain=2)


def fence_gate(k, lod):
    for x in (-0.8, 0.8):
        log_post(k, x, 0, 1.4, 0.1, lod)
    k.push((-0.72, -0.05, 0.12), (0, 0, -0.35))
    for z in (0.15, 0.55, 0.95):
        k.beam((0, 0, z), (1.4, 0, z), 0.1, 0.05, "RG_Timber", jit(k, WOOD_GREY))
    for x in (0.05, 1.35):
        k.beam((x, 0.02, 0.05), (x, 0.02, 1.05), 0.1, 0.05, "RG_Timber", jit(k, WOOD_GREY), up=(1, 0, 0))
    k.beam((0.05, 0.03, 0.15), (1.35, 0.03, 0.95), 0.1, 0.05, "RG_Timber", jit(k, WOOD_GREY), up=(0, -1, 0))
    k.box((0.12, 0.04, 0.06), (0.05, -0.02, 0.25), "RG_Iron", IRON)
    k.box((0.12, 0.04, 0.06), (0.05, -0.02, 0.85), "RG_Iron", IRON)
    k.pop()


# ============================================================================ scarecrow
def scarecrow(k, lod):
    log_post(k, 0, 0, 2.2, 0.06, lod)
    log_beam(k, (-0.85, 0, 1.55), (0.85, 0, 1.55), 0.045, lod)
    # shirt
    k.box((0.6, 0.32, 0.7), (0, 0, 1.3), "RG_Canvas", hexc("a5553f"), grain=2)
    k.beam((-0.3, 0, 1.55), (-0.75, 0, 1.52), 0.2, 0.2, "RG_Canvas", hexc("9c4f3b"))
    k.beam((0.3, 0, 1.55), (0.75, 0, 1.52), 0.2, 0.2, "RG_Canvas", hexc("9c4f3b"))
    k.box((0.64, 0.34, 0.08), (0, 0, 1.0), "RG_Canvas", hexc("6d5843"))      # belt of rope
    # trousers
    for sx in (-1, 1):
        k.beam((sx * 0.13, 0, 0.98), (sx * 0.17, 0, 0.55), 0.22, 0.22, "RG_Canvas", hexc("5e6f84"))
    # sack head + hat
    S.sack(k, 0, 0, 1.64, 0.62, 0.0, tint=(0.95, 0.86, 0.68), lod=lod)
    k.cyl(0.38, 0.05, (0, 0, 1.98), "RG_Hay", (1, 0.95, 0.8), segs=10 if lod == 0 else 6)
    k.cyl(0.2, 0.3, (0, 0, 2.02), "RG_Hay", (1, 0.95, 0.8), r2=0.08, segs=8 if lod == 0 else 5)
    if lod == 0:
        for sx in (-1, 1):
            S.lumpy(k, (sx * 0.85, 0, 1.46), (0.1, 0.1, 0.12), "RG_Hay", (1, 0.95, 0.8), seed=sx + 3, subdiv=1)
            S.lumpy(k, (sx * 0.17, 0, 0.45), (0.1, 0.1, 0.1), "RG_Hay", (1, 0.95, 0.8), seed=sx + 7, subdiv=1)
        # painted face: dark eyes + mouth
        for sx in (-1, 1):
            k.box((0.06, 0.02, 0.05), (sx * 0.08, -0.17, 1.88), "RG_Timber", HOLE)
        k.box((0.14, 0.02, 0.03), (0, -0.17, 1.78), "RG_Timber", HOLE)


# ============================================================================ hay wagon
def hay_wagon(k, lod):
    L, W, bz = 3.2, 1.6, 0.85
    k.box((L, W, 0.1), (0, 0, bz), "RG_Planks", jit(k, WOOD), grain=0)
    for y in (-W / 2 + 0.1, W / 2 - 0.1):
        k.beam((-L / 2, y, bz - 0.1), (L / 2, y, bz - 0.1), 0.14, 0.12, "RG_Timber", jit(k, WOOD_DK))
    # ladder sides
    for y in (-W / 2, W / 2):
        k.beam((-L / 2, y, bz + 0.75), (L / 2, y, bz + 0.75), 0.08, 0.08, "RG_Timber", jit(k, WOOD_DK))
        n = 7 if lod == 0 else 3
        for i in range(n):
            x = -L / 2 + 0.05 + (L - 0.1) * i / (n - 1)
            k.beam((x, y, bz), (x, y, bz + 0.78), 0.06, 0.06, "RG_Timber", jit(k, WOOD_DK), up=(1, 0, 0))
    for x in (-L / 2 + 0.55, L / 2 - 0.55):
        k.beam((x, -W / 2 - 0.15, 0.55), (x, W / 2 + 0.15, 0.55), 0.12, 0.12, "RG_Timber", jit(k, WOOD_DK))
        for y in (-W / 2 - 0.12, W / 2 + 0.12):
            wheel(k, (x, y, 0.55), 0.55, lod=lod, axis="y")
    # shafts
    for y in (-0.45, 0.45):
        k.beam((L / 2 - 0.2, y, bz - 0.1), (L / 2 + 1.9, y * 0.8, 0.55), 0.08, 0.08, "RG_Timber", jit(k, WOOD_DK))
    # hay load
    S.lumpy(k, (0, 0, bz + 0.05), (L * 0.52, W * 0.55, 0.75), "RG_Hay", (1, 0.95, 0.85), seed=11,
            subdiv=2 if lod == 0 else 1, sink=0.05)
    if lod == 0:
        k.beam((-L / 2 - 0.2, 0.3, bz + 1.2), (0.4, 0.5, bz + 1.4), 0.04, 0.04, "RG_Timber", jit(k, WOOD))  # pitchfork
        k.beam((-L / 2 - 0.2, 0.3, bz + 1.2), (-L / 2 - 0.45, 0.25, bz + 1.05), 0.12, 0.02, "RG_Iron", IRON)


ASSETS = {
    "barn": (barn, 8000, 2400, dict(cam=(1.0, -1.35, 0.55))),
    "granary": (granary, 4000, 1200, {}),
    "windmill": (windmill, 6000, 1800, dict(cam=(0.9, -1.5, 0.35))),
    "windmill_sails": (windmill_sails, 3000, 800, dict(cam=(0.4, -1.6, 0.2), lift=8.0)),
    "chicken_coop": (chicken_coop, 3000, 900, {}),
    "pig_sty": (pig_sty, 3000, 900, {}),
    "crop_wheat": (crop_wheat, 1500, 500, dict(cam=(1.0, -1.6, 0.9))),
    "crop_cabbage": (crop_cabbage, 2500, 800, dict(cam=(1.0, -1.6, 0.9))),
    "fence_rail": (fence_rail, 600, 200, {}),
    "fence_picket": (fence_picket, 600, 200, {}),
    "fence_gate": (fence_gate, 600, 250, {}),
    "scarecrow": (scarecrow, 1500, 500, {}),
    "hay_wagon": (hay_wagon, 4000, 1200, {}),
}

if __name__ == "__main__" or True:
    run_set("farm", ASSETS, "RISING ASHES - REGION 1 FARM SET  (TRIS LOD0 / LOD1)")
