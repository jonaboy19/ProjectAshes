"""Village props, round 3: barrels, crates, sacks, wagon, well, benches, lamp post,
notice board, weapon rack, anvil, fences, signpost, woodpile, market table, hay,
trough and planter, built for mobile (Rising Ashes, Godot 4.6).

Run headless (Blender 5.x):
    blender -b --python kingdom/tools/blender/make_village_props.py -- [names...] [--no-preview] [--atlas] [--sheet]

- names: any of PROPS below (default: all).
- --atlas: repaint the shared detail atlas first (props_atlas.png).
- --sheet: after building, compose docs/kingdom/blender_previews/_props_round3_sheet.png
  from the per-prop previews (only the sheet when no names are given with --sheet-only).

Outputs: kingdom/assets/generated/props/<name>.glb (+ shared props_atlas.png referenced by URI)
and docs/kingdom/blender_previews/prop_<name>.png. Every prop uses the one shared
"RA_Props" material (vertex colour x atlas); the lamp post adds "RA_PropsGlow".
Budgets: small props <= 1500 triangles, large <= 4000. Scale in metres, origin at
ground centre, front faces -Y (Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from prop_kit import (PK, make_atlas, ATLAS, OUT_DIR, PREV_DIR, OAK, OAK_DK, OAK_LT, PINE, BARK, ENDGRAIN,
                      IRON_C, IRON_LT, STONE_C, CANVAS, RED, ROPE, STRAW, SOIL, LEAF)
from ra_kit import hexc, vary, mix

SMALL, LARGE = 1500, 4000
tau = math.tau


# ====================================================================== shared bits
def barrel(k, x, y, z=0.0, h=0.9, r=0.34, rz=0.0, open_top=False, water=False, c=None, segs=12):
    """Coopered barrel: bulged lathe body with a recessed lid and chime, 4 iron hoops."""
    W, MT = k.M("Wood"), k.M("Metal")
    base = c or vary(OAK, 0.06)
    re = r * 0.84
    lid = h - 0.035
    prof = [(0, 0.03), (re - 0.03, 0.03), (re - 0.03, 0.0), (re, 0.0)]
    for i in range(1, 6):
        t = i / 6
        prof.append((re + (r - re) * math.sin(t * math.pi), h * t))
    prof += [(re, h), (re - 0.03, h), (re - 0.03, lid)]
    if water:
        prof += [(0, lid)]
    elif open_top:
        prof += [(re - 0.03, h * 0.3), (0, h * 0.3)]
    else:
        prof += [(0, lid)]
    stave = [vary(base, 0.12, 0.03) for _ in range(segs)]

    def cf(f):
        cc = f.calc_center_median()
        a = math.atan2(cc.y - y, cc.x - x) % tau
        return stave[int(a / tau * segs) % segs]
    k.lathe(prof, (x, y, z), W, base, segs=segs, smooth=40, rot=(0, 0, rz), color_fn=cf, grime=True, var=0)
    if water:
        k.cyl(re - 0.035, 0.01, (x, y, z + lid - 0.07), k.M("Water"), hexc("3f6f86"), segs=segs, var=0,
              grime=False)
    elif not open_top:
        # lid boards: two dark seams across the lid
        for dx in (-0.08, 0.08):
            k.box((0.012, 2 * (re - 0.05) * 0.95, 0.006), (x + dx, y, z + lid + 0.002), W, mix(base, (0, 0, 0), 0.45),
                  rot=(0, 0, rz), var=0, grime=False)
    for hz in (0.07, 0.3, 0.7, 0.93):
        rr = re + (r - re) * math.sin(hz * math.pi) + 0.008
        k.lathe([(rr - 0.004, -0.028), (rr + 0.006, -0.022), (rr + 0.006, 0.022), (rr - 0.004, 0.028)],
                (x, y, z + h * hz), MT, vary(IRON_C, 0.05), segs=segs, smooth=None, var=0, grime=True)


def crate(k, x, y, z=0.0, s=0.6, rz=0.0, c=None, open_top=False, lid=True, h=None):
    """Plank crate: dark core, 3 boards per side with gaps, bevelled corner battens,
    rim battens and a diagonal brace on front/back."""
    W = k.M("Wood")
    h = h or s
    c = c or vary(OAK_LT, 0.08)
    dk = mix(c, (0.08, 0.05, 0.03), 0.3)
    k.push((x, y, z), (0, 0, rz))
    k.box((s - 0.05, s - 0.05, h - 0.04), (0, 0, h / 2), W, mix(c, (0, 0, 0), 0.6), var=0)
    nb = 3
    bh = (h - 0.02) / nb
    for side in range(4):
        k.push((0, 0, 0), (0, 0, side * tau / 4))
        for i in range(nb):
            zc = 0.01 + bh * (i + 0.5)
            k.box((s - 0.06, 0.022, bh - 0.018), (0, -s / 2 + 0.011, zc), W, k.board_c(c, 0.1), var=0)
        if side % 2 == 0:   # diagonal brace
            k.bar((-s / 2 + 0.07, -s / 2 - 0.004, 0.08), (s / 2 - 0.07, -s / 2 - 0.004, h - 0.08), 0.07, 0.022, W,
                  vary(dk, 0.06), up=(-1, 0, 1), bevel=0.006, var=0)
        for zz in (0.035, h - 0.035):   # rim battens
            k.box((s - 0.1, 0.03, 0.07), (0, -s / 2 - 0.002, zz), W, vary(dk, 0.06), bevel=0.008, var=0)
        k.box((0.075, 0.075, h), (s / 2 - 0.03, -s / 2 + 0.03, h / 2), W, vary(dk, 0.05), bevel=0.012, var=0)
        k.pop()
    if lid and not open_top:
        for i in range(3):
            k.box((s - 0.02, (s - 0.04) / 3 - 0.012, 0.025), (0, -s / 2 + 0.02 + (i + 0.5) * (s - 0.04) / 3, h + 0.01),
                  W, k.board_c(c, 0.1), bevel=0.005, var=0)
    k.pop()


def rivet_row(k, pts, c=IRON_C, s=0.022):
    MT = k.M("Metal")
    for p in pts:
        k.box((s, s, s), p, MT, c, var=0.05, grime=False)


def spoked_wheel(k, x, y, z, r, rz=0.0, spokes=8, w=0.09, segs=14):
    """Wheel in the local XZ plane (axle along Y): felloe, iron tyre, hub, spokes."""
    W, MT = k.M("Wood"), k.M("Metal")
    k.push((x, y, z), (0, 0, rz))
    k.ring(r - 0.075, r - 0.012, w, (0, 0, 0), W, vary(OAK, 0.06), segs=segs)
    k.ring(r - 0.014, r, w + 0.012, (0, 0, 0), MT, IRON_C, segs=segs)
    k.cyl(0.085, w + 0.12, (0, (w + 0.12) / 2, 0), W, vary(OAK_DK, 0.05), rot=(math.pi / 2, 0, 0), segs=8)
    k.cyl(0.095, 0.03, (0, (w + 0.12) / 2 - 0.02, 0), MT, IRON_C, rot=(math.pi / 2, 0, 0), segs=8, caps=False)
    k.cyl(0.095, 0.03, (0, -(w + 0.12) / 2 + 0.05, 0), MT, IRON_C, rot=(math.pi / 2, 0, 0), segs=8, caps=False)
    for i in range(spokes):
        a = i / spokes * tau
        k.bar((math.cos(a) * 0.07, 0, math.sin(a) * 0.07), (math.cos(a) * (r - 0.06), 0, math.sin(a) * (r - 0.06)),
              0.045, 0.035, W, vary(OAK, 0.08), up=(0, 1, 0), bevel=0, var=0)
    k.pop()


def lantern(k, top, s=1.0):
    """Iron lantern hanging from `top`: ring, pyramid cap, 4 glowing panes with
    corner bars, base tray and drip finial. Glass uses the glow material."""
    MT, LP = k.M("Metal"), k.M("Lamp")
    x, y, z = top
    k.ring(0.018 * s, 0.03 * s, 0.012 * s, (x, y, z - 0.03 * s), MT, IRON_C, segs=6)
    zc = z - 0.06 * s
    k.cyl(0.03 * s, 0.05 * s, (x, y, zc - 0.05 * s), MT, IRON_C, segs=6, r2=0.02 * s)
    k.cyl(0.16 * s, 0.12 * s, (x, y, zc - 0.17 * s), MT, IRON_C, segs=4, r2=0.035 * s, rot=(0, 0, tau / 8),
          smooth=None)
    k.box((0.2 * s, 0.2 * s, 0.025 * s), (x, y, zc - 0.18 * s), MT, IRON_C, bevel=0.004 * s, var=0)
    k.box((0.15 * s, 0.15 * s, 0.24 * s), (x, y, zc - 0.31 * s), LP, hexc("ffd68e"), var=0, grime=False)
    for dx in (-1, 1):
        for dy in (-1, 1):
            k.box((0.022 * s, 0.022 * s, 0.27 * s), (x + dx * 0.078 * s, y + dy * 0.078 * s, zc - 0.31 * s), MT,
                  IRON_C, var=0)
    for (dx, dy) in ((0, -1), (0, 1), (-1, 0), (1, 0)):   # a vertical glazing bar on each pane
        k.box((0.012 * s if dy else 0.004 * s, 0.004 * s if dy else 0.012 * s, 0.24 * s),
              (x + dx * 0.077 * s, y + dy * 0.077 * s, zc - 0.31 * s), MT, IRON_C, var=0)
    k.box((0.19 * s, 0.19 * s, 0.03 * s), (x, y, zc - 0.445 * s), MT, IRON_C, bevel=0.004 * s, var=0)
    k.cyl(0.05 * s, 0.07 * s, (x, y, zc - 0.53 * s), MT, IRON_C, segs=6, r2=0.0, rot=(math.pi, 0, 0), base=False)


def stone_block(k, size, loc, rot=(0, 0, 0), c=None, bevel=0.035, jitter=0.012):
    k.box(size, loc, k.M("Matte"), c or vary(random.choice(STONE_C), 0.08, 0.02), rot=rot, bevel=bevel,
          jitter=jitter, var=0)


def grass_tufts(k, pts, h=0.18):
    PL = k.M("Plant")
    for (x, y) in pts:
        for i in range(3):
            a = random.uniform(0, tau)
            k.cyl(0.035, h * random.uniform(0.7, 1.2), (x + math.cos(a) * 0.04, y + math.sin(a) * 0.04, 0), PL,
                  vary(hexc("6d8f3c"), 0.12), segs=3, r2=0.0, rot=(random.uniform(-0.35, 0.35),
                                                                 random.uniform(-0.35, 0.35), a), grime=False)


# ====================================================================== props
def p_barrel():
    k = PK("barrel", seed=11)
    barrel(k, 0, 0, 0)
    return k.finish_prop("barrel", SMALL, fit=1.25)


def p_crate():
    k = PK("crate", seed=12)
    crate(k, 0, 0, 0, s=0.62)
    return k.finish_prop("crate", SMALL, fit=1.2)


def p_crate_stack():
    k = PK("crate_stack", seed=13)
    crate(k, -0.34, 0.06, 0, s=0.62, rz=0.04)
    crate(k, 0.36, 0.14, 0, s=0.62, rz=-0.1, c=vary(OAK, 0.06))
    crate(k, -0.3, 0.08, 0.645, s=0.54, rz=0.22, c=vary(OAK_LT, 0.1))
    # small open crate of apples in front
    crate(k, 0.5, -0.5, 0, s=0.42, rz=0.45, open_top=True, h=0.34)
    k.push((0.5, -0.5, 0), (0, 0, 0.45))
    k.box((0.36, 0.36, 0.02), (0, 0, 0.27), k.M("Plant"), hexc("7a2a22"), var=0)
    for i in range(9):
        k.fruit((random.uniform(-0.13, 0.13), random.uniform(-0.13, 0.13), 0.31 + random.uniform(0, 0.03)), 0.05,
                random.choice([hexc("b8322b"), hexc("c9452c"), hexc("9e2a24"), hexc("d08a38")]))
    k.pop()
    k.sack((-0.35, -0.55, 0), s=0.8, rot=(0.18, 0, 0.5))
    return k.finish_prop("crate_stack", LARGE, fit=1.1)


def p_sack_pile():
    k = PK("sack_pile", seed=14)
    W = k.M("Wood")
    # pallet: 3 runners + 5 top boards
    for y in (-0.36, 0.0, 0.36):
        k.box((1.15, 0.1, 0.08), (0, y, 0.04), W, k.board_c(OAK_DK), bevel=0.012, var=0)
    for i in range(5):
        x = -0.46 + i * 0.23
        k.box((0.19, 0.92, 0.035), (x, 0, 0.098), W, k.board_c(OAK_LT), bevel=0.008, var=0)
    top = 0.115
    k.sack((-0.3, 0.36, top + 0.24), s=0.95, rot=(math.pi / 2, 0, 0.08))
    k.sack((0.31, 0.36, top + 0.24), s=0.95, rot=(math.pi / 2, 0, -0.1), c=vary(hexc("a88c5e"), 0.05))
    k.sack((0.02, 0.3, top + 0.66), s=0.9, rot=(math.pi / 2 - 0.08, 0, 0.2), c=vary(hexc("c4a878"), 0.05))
    k.sack((0.85, 0.05, 0), s=1.0, rot=(0.06, -0.08, 0.6))
    k.sack((-0.82, 0.2, 0), s=0.85, rot=(-0.2, 0.1, 2.4), c=vary(hexc("a3875c"), 0.05))
    # spilled grain
    for i in range(7):
        a = random.uniform(-1.0, 0.4)
        k.sphere(0.035, (0.62 + math.cos(a) * random.uniform(0.1, 0.3), -0.4 + math.sin(a) * random.uniform(0.05, 0.2),
                         0.0), k.M("Thatch"), vary(hexc("d8bf7a"), 0.08), scale=(1.4, 1.0, 0.4), subdiv=1, grime=False)
    return k.finish_prop("sack_pile", SMALL, fit=1.1)


def p_basket_produce():
    k = PK("basket_produce", seed=15)
    TH = k.M("Thatch")
    wc = hexc("b58a52")
    prof = [(0, 0.0), (0.19, 0.0), (0.2, 0.02), (0.235, 0.12), (0.265, 0.22), (0.285, 0.3),
            (0.262, 0.3), (0.245, 0.22), (0.23, 0.2), (0, 0.2)]
    bands = [vary(wc, 0.08) for _ in range(12)]
    k.strip = "straw"
    k.lathe(prof, (0, 0, 0), TH, wc, segs=12, smooth=50, color_fn=lambda f: mix(
        bands[int(f.calc_center_median().z / 0.05) % 12], (0, 0, 0), 0.12 * ((int(f.calc_center_median().z / 0.05)) % 2)),
        grime=True, var=0)
    # rim roll
    k.lathe([(0.262, 0.29), (0.3, 0.292), (0.31, 0.315), (0.285, 0.335), (0.26, 0.318), (0.262, 0.29)],
            (0, 0, 0), TH, mix(wc, (0, 0, 0), 0.18), segs=12, smooth=60, var=0)
    # handle
    pts = [(-0.27 * math.cos(t * math.pi), 0.0, 0.31 + 0.3 * math.sin(t * math.pi)) for t in [i / 8 for i in range(9)]]
    k.tube(pts, [0.02] * 9, TH, mix(wc, (0, 0, 0), 0.15), segs=5, point_end=False)
    k.strip = None
    apples = [hexc("b8322b"), hexc("c9452c"), hexc("9e2a24"), hexc("d6a338"), hexc("c24a2a")]
    placed = []
    for ring, (rr, n, z) in enumerate(((0.19, 8, 0.25), (0.1, 5, 0.3), (0.0, 1, 0.35))):
        for i in range(n):
            a = i / n * tau + ring * 0.4
            p = (math.cos(a) * rr, math.sin(a) * rr, z)
            k.fruit(p, 0.052, random.choice(apples), rot=(random.uniform(-0.3, 0.3), random.uniform(-0.3, 0.3), 0))
            placed.append(p)
    for p in placed[-4:]:
        k.box((0.008, 0.008, 0.03), (p[0], p[1], p[2] + 0.055), k.M("Wood"), hexc("4a3020"), rot=(0.3, 0, 0), var=0)
    k.box((0.07, 0.035, 0.004), (placed[-1][0] + 0.03, placed[-1][1], placed[-1][2] + 0.05), k.M("Plant"), LEAF,
          rot=(0.2, 0.3, 0.5), var=0)
    # two fallen apples
    k.fruit((0.36, -0.2, 0.047), 0.05, apples[0])
    k.fruit((0.28, -0.33, 0.047), 0.05, apples[3], rot=(0.6, 0, 0))
    return k.finish_prop("basket_produce", SMALL, fit=1.25)


def p_covered_wagon():
    """Covered wagon, 3.9 m long along X (drawbar towards -X), 1.75 m wide, 2.3 m tall."""
    k = PK("covered_wagon", seed=16)
    W, MT, CL = k.M("Wood"), k.M("Metal"), k.M("Cloth")
    zb = 0.78          # bed floor top
    L, Wd = 2.4, 1.2
    # wheels
    for sx, r in ((0.72, 0.55), (-0.78, 0.45)):
        for sy in (-1, 1):
            spoked_wheel(k, sx, sy * 0.76, r, r, rz=0.0 if sy < 0 else math.pi, spokes=8, segs=12)
        k.box((0.12, 1.66, 0.1), (sx, 0, r), W, vary(OAK_DK, 0.05), bevel=0.015, var=0)             # axle
        k.box((0.16, 1.1, zb - 0.06 - r - 0.02), (sx, 0, (zb - 0.06 + r + 0.02) / 2 + 0.02), W, vary(OAK_DK, 0.05),
              bevel=0.012, var=0)                                                                    # bolster
    for sy in (-0.35, 0.35):                                                                        # chassis rails
        k.box((L - 0.1, 0.1, 0.1), (0, sy, zb - 0.1), W, vary(OAK_DK, 0.05), bevel=0.015, var=0)
    # bed floor + sides
    k.box((L, Wd, 0.06), (0, 0, zb - 0.03), W, vary(OAK, 0.05), bevel=0.01, var=0)
    for sy in (-1, 1):
        for i, zz in enumerate((zb + 0.1, zb + 0.28)):
            k.box((L - 0.04, 0.045, 0.17), (0, sy * (Wd / 2 - 0.02), zz), W, k.board_c(OAK), bevel=0.012, var=0)
        for x in (-1.15, -0.4, 0.4, 1.15):
            k.box((0.08, 0.07, 0.46), (x, sy * (Wd / 2 + 0.015), zb + 0.19), W, vary(OAK_DK, 0.05), bevel=0.015,
                  var=0)
        k.box((L + 0.06, 0.08, 0.06), (0, sy * (Wd / 2 - 0.01), zb + 0.41), W, vary(OAK_DK, 0.05), bevel=0.015,
              var=0)
        rivet_row(k, [(x, sy * (Wd / 2 + 0.055), zb + zz) for x in (-1.15, -0.4, 0.4, 1.15) for zz in (0.1, 0.3)])
    for sx in (-1, 1):
        for zz in (zb + 0.1, zb + 0.28):
            k.box((0.045, Wd - 0.06, 0.17), (sx * (L / 2 - 0.02), 0, zz), W, k.board_c(OAK), bevel=0.012, var=0)
    # drawbar / shafts
    k.bar((-0.78, 0, 0.45), (-2.05, 0, 0.3), 0.1, 0.08, W, vary(OAK_DK, 0.05), bevel=0.015, var=0)
    k.bar((-0.78, -0.35, 0.47), (-1.2, 0, 0.42), 0.07, 0.06, W, vary(OAK_DK, 0.05), bevel=0.01, var=0)
    k.bar((-0.78, 0.35, 0.47), (-1.2, 0, 0.42), 0.07, 0.06, W, vary(OAK_DK, 0.05), bevel=0.01, var=0)
    k.box((0.07, 0.8, 0.06), (-1.95, 0, 0.31), W, vary(OAK, 0.05), bevel=0.012, var=0)
    k.cyl(0.035, 0.1, (-2.08, 0, 0.3), MT, IRON_C, rot=(0, math.pi / 2, 0), segs=6, base=False)
    # canvas cover: striped, sagging between hoops, pinched at the ends
    x0, x1 = -1.12, 1.18
    zc = zb + 0.41
    ry, rz_ = Wd / 2 + 0.04, 0.95
    na, nl = 10, 8
    hoops = [0, 2, 4, 6, 8]
    verts = []
    for j in range(nl + 1):
        u = j / nl
        x = x0 + (x1 - x0) * u
        pinch = 1.0 - (0.12 if j in (0, nl) else 0.0)
        sag = 0.0 if j in hoops else 0.045
        row = []
        for i in range(na + 1):
            a = i / na * math.pi
            rr = pinch * (1 - sag / 0.6)
            row.append(Vector((x + (0.05 if j == 0 else -0.05 if j == nl else 0.0) * math.sin(a),
                               -math.cos(a) * ry * rr, zc + math.sin(a) * rz_ * rr)))
        verts.append(row)
    import bmesh
    t = bmesh.new()
    fl = t.faces.layers.int.new("stripe")
    cols = {}
    for side in (0, 1):
        vv = [[t.verts.new(p) for p in row] for row in verts]
        for j in range(nl):
            for i in range(na):
                c = vary(CANVAS if i % 2 == 0 else RED, 0.03)
                c = mix(c, hexc("8a7a5a"), 0.12 * (1 - math.sin(i / na * math.pi)))   # dirtier low down
                q = (vv[j][i], vv[j + 1][i], vv[j + 1][i + 1], vv[j][i + 1])
                if side == 1:   # side 0 winds outward (x-dir cross around-dir); side 1 is the lining
                    q = tuple(reversed(q))
                    c = mix(c, (0, 0, 0), 0.4)
                f = t.faces.new(q)
                f[fl] = len(cols)
                cols[len(cols)] = c
    t.normal_update()
    k.strip = "cloth"
    k._merge(t, CL, CANVAS, None, 60, 0.0, lambda f: cols[f[fl]], False)
    k.strip = None
    # hoops at the two ends (visible bows)
    for x in (x0 + 0.03, x1 - 0.03):
        pts = [(x, -math.cos(a) * ry * 0.9, zc + math.sin(a) * rz_ * 0.9) for a in [i / 8 * math.pi for i in range(9)]]
        k.tube(pts, [0.03] * 9, W, vary(OAK_DK, 0.05), segs=5, point_end=False, cap_start=False)
    # rope ties along the sides
    for x in (-0.75, 0.0, 0.75):
        for sy in (-1, 1):
            k.box((0.03, 0.02, 0.2), (x, sy * (Wd / 2 + 0.05), zb + 0.5), W, ROPE, var=0.05, grime=False)
    # a sack and a barrel peeking out at the back
    k.sack((0.85, 0.2, zb), s=0.8, rot=(0, 0, 0.4))
    return k.finish_prop("covered_wagon", LARGE, cam_dir=(0.9, -1.5, 0.55), fit=1.0)


def p_well():
    """Round fieldstone well with a slate roof, windlass, crank and bucket. 2.3 m tall."""
    k = PK("well", seed=17)
    W, MT, MA = k.M("Wood"), k.M("Metal"), k.M("Matte")
    R, depth = 0.78, 0.22
    k.grime = 0.6
    # dark shaft + water
    k.lathe([(R - depth + 0.02, 0.8), (R - depth + 0.02, 0.15), (0, 0.15)], (0, 0, 0), MA, hexc("2b2622"), segs=12,
            smooth=None, var=0, grime=False)
    k.cyl(R - depth + 0.02, 0.01, (0, 0, 0.32), k.M("Water"), hexc("2f5b6e"), segs=12, var=0, grime=False)
    n = 11
    hs = [0.26, 0.26, 0.24]
    z = 0.0
    for row, h in enumerate(hs):
        off = (row % 2) * 0.5
        for i in range(n):
            a = (i + off) / n * tau
            wlen = tau * (R - depth / 2) / n - 0.035
            stone_block(k, (wlen, depth, h - 0.03), (math.cos(a) * (R - depth / 2), math.sin(a) * (R - depth / 2),
                                                     z + h / 2), rot=(0, 0, a + math.pi / 2), bevel=0.04, jitter=0.012)
        z += h
    for i in range(n):   # cap stones, overhanging
        a = (i + 0.25) / n * tau
        wlen = tau * (R - 0.1) / n - 0.02
        stone_block(k, (wlen, depth + 0.12, 0.1), (math.cos(a) * (R - 0.1), math.sin(a) * (R - 0.1), z + 0.05),
                    rot=(0, 0, a + math.pi / 2), c=vary(hexc("aaa496"), 0.06), bevel=0.03, jitter=0.006)
    ztop = z + 0.1
    # posts, braces, ridge beam
    px = R + 0.1
    for sx in (-1, 1):
        k.box((0.16, 0.16, 2.18), (sx * px, 0, 1.09), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
        k.box((0.26, 0.3, 0.12), (sx * px, 0, 0.06), MA, vary(STONE_C[0], 0.05), bevel=0.03, var=0)
        for sy in (-1, 1):
            k.bar((sx * px, sy * 0.06, 1.75), (sx * px, sy * 0.45, 2.1), 0.09, 0.08, W, vary(OAK_DK, 0.05),
                  up=(0, -sy, 1), bevel=0.012, var=0)
    k.box((2 * px + 0.5, 0.14, 0.14), (0, 0, 2.2), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
    # roof: two slopes of slate shingles in 3 courses, barge boards
    run, rise = 0.95, 0.55
    ang = math.atan2(rise, run)
    Lr = 2 * px + 0.75
    slate = [hexc(h) for h in ("5a6a75", "4d5d68", "63737c", "56646b", "6a7780")]
    for sy in (-1, 1):
        for c in range(3):
            s0 = 0.08 + c * 0.34
            nsh = 6
            for i in range(nsh):
                wsh = Lr / nsh
                x = -Lr / 2 + (i + 0.5 + (0.5 if c % 2 else 0) * 0) * wsh + (c % 2) * wsh * 0.5 - (c % 2) * wsh * 0.25
                sl = 0.42
                d = run * (s0 + sl * 0.5) / 1.1
                yy = sy * d
                zz = 2.36 - rise * d / run + 0.035 + 0.018 * (2 - c)
                k.box((wsh - 0.025, sl, 0.04), (x, yy, zz), MA,
                      vary(random.choice(slate), 0.07), rot=(-sy * ang + random.uniform(-0.03, 0.03), 0,
                                                            random.uniform(-0.02, 0.02)), bevel=0.0, var=0)
        # barge boards
        for sx in (-1, 1):
            k.bar((sx * (Lr / 2 + 0.02), 0, 2.36), (sx * (Lr / 2 + 0.02), sy * 1.05, 2.36 - rise * 1.05 / run),
                  0.14, 0.05, W, vary(OAK_DK, 0.05), up=(0, sy * rise, run), bevel=0.012, var=0)
    k.box((Lr + 0.1, 0.12, 0.08), (0, 0, 2.38), W, vary(OAK_DK, 0.05), bevel=0.02, var=0)   # ridge cap
    # windlass
    zw = 1.3
    k.log((-px + 0.08, 0, zw), (px + 0.2, 0, zw), 0.075, W, vary(OAK, 0.05), segs=8, noise_amt=0.005, ring_step=3)
    k.strip = "straw"
    k.cyl(0.098, 0.5, (-0.25, 0, zw), W, ROPE, rot=(0, math.pi / 2, 0), segs=8)
    k.strip = None
    # crank on +X
    k.bar((px + 0.18, 0, zw), (px + 0.18, 0, zw - 0.32), 0.05, 0.04, MT, IRON_C, bevel=0.0, var=0)
    k.bar((px + 0.18, 0, zw - 0.32), (px + 0.36, 0, zw - 0.32), 0.035, 0.035, W, vary(OAK, 0.05), bevel=0.0, var=0)
    # rope + bucket
    k.strip = "straw"
    k.bar((-0.12, -0.0, zw - 0.09), (0.5, -0.36, ztop + 0.36), 0.022, 0.022, W, ROPE, bevel=0, var=0)
    k.strip = None
    bz = ztop
    k.lathe([(0, 0), (0.12, 0), (0.145, 0.23), (0.13, 0.23), (0.11, 0.05), (0, 0.05)], (0.5, -0.36, bz), W,
            vary(OAK_LT, 0.05), segs=10, smooth=50, var=0)
    for hz in (0.04, 0.19):
        k.cyl(0.125 + hz * 0.1 + 0.006, 0.025, (0.5, -0.36, bz + hz), MT, IRON_C, segs=10, caps=False)
    pts = [(0.5 - 0.14 * math.cos(t * math.pi), -0.36, bz + 0.23 + 0.12 * math.sin(t * math.pi)) for t in [i / 6 for i in range(7)]]
    k.tube(pts, [0.008] * 7, MT, IRON_C, segs=4, point_end=False)
    grass_tufts(k, [(0.9, -0.3), (-0.7, -0.55), (0.2, 0.85), (-0.95, 0.3)])
    return k.finish_prop("well", LARGE, fit=1.05)


def p_bench():
    k = PK("bench", seed=18)
    W = k.M("Wood")
    L = 1.6
    for sy in (-0.085, 0.085):
        k.box((L, 0.16, 0.065), (0, sy, 0.44), W, k.board_c(OAK), bevel=0.014, var=0)
    for sx in (-1, 1):
        k.box((0.11, 0.42, 0.07), (sx * 0.58, 0, 0.375), W, vary(OAK_DK, 0.05), bevel=0.014, var=0)
        for sy in (-1, 1):
            k.bar((sx * 0.6, sy * 0.13, 0.36), (sx * 0.68, sy * 0.2, 0.0), 0.08, 0.08, W, vary(OAK_DK, 0.05),
                  up=(0, 1, 0), bevel=0.014, var=0)
    k.box((1.25, 0.06, 0.06), (0, 0, 0.18), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    rivet_row(k, [(sx * 0.58 + dx, sy, 0.475) for sx in (-1, 1) for dx in (-0.03, 0.03) for sy in (-0.085, 0.085)],
              s=0.018)
    # tankard on the bench
    k.lathe([(0, 0), (0.055, 0), (0.05, 0.14), (0.045, 0.14), (0.042, 0.02), (0, 0.02)], (0.45, 0.03, 0.4725),
            W, vary(OAK_LT, 0.05), segs=8, smooth=50, var=0)
    k.cyl(0.058, 0.02, (0.45, 0.03, 0.5), k.M("Metal"), IRON_C, segs=8, caps=False)
    k.cyl(0.058, 0.02, (0.45, 0.03, 0.58), k.M("Metal"), IRON_C, segs=8, caps=False)
    k.box((0.02, 0.05, 0.09), (0.45, 0.03 + 0.075, 0.54), W, vary(OAK_LT, 0.05), var=0)
    return k.finish_prop("bench", SMALL, fit=1.2)


def p_lamp_post():
    """Wooden gallows lamp post: stone footing, oak post, arm with knee brace,
    iron straps, chain and a glowing iron lantern (glass centre ~2.2 m)."""
    k = PK("lamp_post", seed=19)
    W, MT = k.M("Wood"), k.M("Metal")
    stone_block(k, (0.5, 0.5, 0.24), (0, 0, 0.12), c=vary(STONE_C[0], 0.04), bevel=0.04, jitter=0.01)
    stone_block(k, (0.36, 0.36, 0.12), (0, 0, 0.3), c=vary(STONE_C[2], 0.04), bevel=0.03, jitter=0.006)
    for i in range(4):
        a = i * tau / 4 + 0.6
        stone_block(k, (0.16, 0.12, 0.08), (math.cos(a) * 0.36, math.sin(a) * 0.36, 0.02), rot=(0, 0, a),
                    bevel=0.025, jitter=0.01)
    H = 3.0
    k.box((0.17, 0.17, H - 0.34), (0, 0, 0.34 + (H - 0.34) / 2), W, vary(OAK_DK, 0.04), bevel=0.025, var=0)
    k.box((0.24, 0.24, 0.06), (0, 0, H + 0.03), W, vary(OAK_DK, 0.05), bevel=0.015, var=0)
    k.cyl(0.13, 0.12, (0, 0, H + 0.06), W, vary(OAK_DK, 0.05), segs=4, r2=0.0, rot=(0, 0, tau / 8), smooth=None)
    for z in (0.5, 1.9):
        k.box((0.19, 0.19, 0.05), (0, 0, z), MT, IRON_C, bevel=0.006, var=0)
    # arm to the front (-Y)
    za = 2.72
    k.box((0.13, 0.95, 0.14), (0, -0.4, za), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
    k.bar((0, -0.05, za - 0.55), (0, -0.52, za - 0.06), 0.1, 0.09, W, vary(OAK_DK, 0.05), up=(0, 1, 1), bevel=0.015,
          var=0)
    for y in (-0.06, -0.8):
        k.box((0.15, 0.04, 0.16), (0, y, za), MT, IRON_C, bevel=0.005, var=0)
    rivet_row(k, [(0.08, -0.4, za), (-0.08, -0.4, za)], s=0.025)
    # chain + lantern
    y = -0.76
    for i in range(3):
        k.ring(0.018, 0.03, 0.012, (0, y, za - 0.1 - i * 0.05), MT, IRON_C, rot=(0, 0, (i % 2) * math.pi / 2),
               segs=6)
    lantern(k, (0, y, za - 0.2), s=1.3)
    return k.finish_prop("lamp_post", SMALL, cam_dir=(1.2, -1.4, 0.4), fit=1.05)


def p_notice_board():
    k = PK("notice_board", seed=20)
    W, MT, MA = k.M("Wood"), k.M("Metal"), k.M("Matte")
    for sx in (-1, 1):
        stone_block(k, (0.28, 0.28, 0.14), (sx * 0.78, 0, 0.07))
        k.box((0.15, 0.15, 2.32), (sx * 0.78, 0, 1.16), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
    # plank board
    x0, x1, z0, z1 = -0.7, 0.7, 0.85, 1.8
    n = 7
    for i in range(n):
        x = x0 + (i + 0.5) * (x1 - x0) / n
        k.box(((x1 - x0) / n - 0.01, 0.05, z1 - z0), (x, 0.0, (z0 + z1) / 2), W, k.board_c(OAK), bevel=0.008, var=0)
    for z in (z0 - 0.02, z1 + 0.02):
        k.box((x1 - x0 + 0.14, 0.08, 0.08), (0, -0.01, z), W, vary(OAK_DK, 0.05), bevel=0.014, var=0)
    for x in (x0 - 0.03, x1 + 0.03):
        k.box((0.07, 0.07, z1 - z0), (x, -0.01, (z0 + z1) / 2), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    # shelf
    k.box((1.3, 0.16, 0.04), (0, -0.07, z0 - 0.1), W, vary(OAK, 0.05), bevel=0.01, var=0)
    # papers
    PAP = [hexc("efe3c2"), hexc("e6d6ae"), hexc("f3ead2"), hexc("dcc9a0")]
    notes = [(-0.45, 1.5, 0.3, 0.38, 0.05), (-0.08, 1.58, 0.26, 0.3, -0.08), (0.36, 1.46, 0.32, 0.42, 0.06),
             (-0.38, 1.08, 0.28, 0.26, -0.04), (0.02, 1.15, 0.22, 0.32, 0.1), (0.42, 1.05, 0.2, 0.2, -0.1)]
    for (x, z, w, h, r) in notes:
        c = random.choice(PAP)
        k.box((w, 0.006, h), (x, -0.03, z), k.M("Plaster"), c, rot=(0, r, 0), var=0.03, grime=False)
        for li in range(2):   # text lines
            lw = w * random.uniform(0.45, 0.75)
            k.box((lw, 0.004, 0.012), (x, -0.035, z + h * 0.25 - li * h * 0.18), k.M("Plaster"), hexc("5a4a3a"),
                  rot=(0, r, 0), var=0, grime=False)
        k.box((0.02, 0.01, 0.02), (x - math.sin(r) * h * 0.42, -0.036, z + math.cos(r) * h * 0.42), MT,
              hexc("8a2a22") if random.random() < 0.5 else IRON_C, var=0, grime=False)
    # little roof
    Lr = 1.95
    for sy in (-1, 1):
        k.box((Lr, 0.46, 0.05), (0, sy * 0.2, 2.26), W, vary(OAK_DK, 0.04), rot=(-sy * 0.52, 0, 0), bevel=0.012,
              var=0)
        for i in range(7):
            x = -Lr / 2 + (i + 0.5) * Lr / 7
            k.box((Lr / 7 - 0.02, 0.26, 0.035), (x, sy * 0.3, 2.37 - 0.573 * 0.3 + 0.035), MA,
                  vary(random.choice([hexc("5a6a75"), hexc("4d5d68"), hexc("63737c")]), 0.06),
                  rot=(-sy * 0.52 + random.uniform(-0.03, 0.03), 0, 0), bevel=0.0, var=0)
            k.box((Lr / 7 - 0.02, 0.24, 0.035), (x + 0.02, sy * 0.1, 2.37 - 0.573 * 0.1 + 0.035), MA,
                  vary(random.choice([hexc("5a6a75"), hexc("4d5d68"), hexc("63737c")]), 0.06),
                  rot=(-sy * 0.52 + random.uniform(-0.03, 0.03), 0, 0), bevel=0.0, var=0)
    k.box((Lr + 0.06, 0.1, 0.07), (0, 0, 2.43), W, vary(OAK_DK, 0.05), bevel=0.015, var=0)
    grass_tufts(k, [(0.95, -0.15), (-0.62, -0.2)])
    return k.finish_prop("notice_board", SMALL, fit=1.1)


def p_weapon_rack():
    k = PK("weapon_rack", seed=21)
    W, MT = k.M("Wood"), k.M("Metal")
    L = 1.7
    for sx in (-1, 1):
        k.box((0.14, 0.7, 0.12), (sx * L / 2, 0.05, 0.06), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)      # foot
        k.box((0.12, 0.12, 1.45), (sx * L / 2, 0.15, 0.12 + 0.72), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
        k.bar((sx * L / 2, -0.2, 0.1), (sx * L / 2, 0.1, 0.55), 0.07, 0.06, W, vary(OAK_DK, 0.05), up=(0, 1, 1),
              bevel=0.012, var=0)
        k.cyl(0.07, 0.1, (sx * L / 2, 0.15, 1.57), W, vary(OAK_DK, 0.05), segs=4, r2=0.0, rot=(0, 0, tau / 8),
              smooth=None)
    k.box((L + 0.12, 0.12, 0.1), (0, 0.1, 1.3), W, vary(OAK, 0.04), bevel=0.02, var=0)                 # top rail
    k.box((L - 0.1, 0.34, 0.06), (0, -0.02, 0.2), W, vary(OAK, 0.04), bevel=0.015, var=0)              # base shelf
    k.box((L - 0.1, 0.06, 0.1), (0, -0.17, 0.26), W, vary(OAK_DK, 0.04), bevel=0.012, var=0)           # front lip
    for x in [-0.6 + i * 0.24 for i in range(6)]:   # pegs on the top rail
        k.box((0.04, 0.12, 0.04), (x, 0.0, 1.33), W, vary(OAK_DK, 0.04), var=0)
    rivet_row(k, [(sx * (L / 2 - 0.02), 0.03, 1.3) for sx in (-1, 1)], s=0.03)
    steel, gold, grip = hexc("b8bec4"), hexc("b08a3a"), hexc("4a2c1a")
    lean = -0.2   # tops lean back onto the rail

    def spear(x, h=2.05):
        k.push((x, -0.08, 0.23), (lean, 0, 0))
        k.cyl(0.02, h - 0.3, (0, 0, 0), W, vary(OAK_LT, 0.05), segs=6)
        k.cyl(0.03, 0.12, (0, 0, h - 0.34), MT, IRON_C, segs=6, r2=0.02)
        k.prism([(0, h), (0.05, h - 0.2), (0.035, h - 0.26), (0, h - 0.24), (-0.035, h - 0.26), (-0.05, h - 0.2)],
                0.016, (0, 0, 0), MT, steel, var=0, grime=False)
        k.pop()

    def sword(x, length=1.05):
        k.push((x, -0.08, 0.23), (lean, 0, 0))
        k.sword((0, 0, length * 0.72), (0, 0, 0), MT, W, length=length, blade_c=steel, hilt_c=gold, grip_c=grip)
        k.pop()

    def axe(x):
        k.push((x, -0.08, 0.23), (lean, 0, 0))
        k.cyl(0.024, 1.1, (0, 0, 0), W, vary(OAK, 0.05), segs=6)
        k.prism([(0.02, 1.02), (0.2, 1.12), (0.22, 0.98), (0.2, 0.84), (0.02, 0.94)], 0.03, (0, 0, 0), MT, steel,
                bevel=0.004, var=0, grime=False)
        k.box((0.06, 0.05, 0.12), (0, 0, 0.98), MT, IRON_C, var=0)
        k.pop()

    spear(-0.62)
    sword(-0.36)
    axe(-0.12)
    sword(0.12, 0.95)
    spear(0.36, 1.95)
    spear(0.6, 2.1)
    # round shield leaning against the front, crate at the side
    k.push((-1.0, -0.4, 0.42), (1.32, 0, 0.35))
    # quartered painted face (red / cream), plain oak back
    q0 = k.frames[-1].inverted()

    def quarter(f):
        c = q0 @ f.calc_center_median()
        if c.z < 0.02:
            return vary(OAK, 0.05)
        qd = int(((math.atan2(c.y, c.x) + tau) % tau) / (tau / 4))
        return vary(hexc("9a2f24") if qd % 2 else hexc("dccaa0"), 0.04)
    k.lathe([(0, 0.0), (0.4, 0.0), (0.4, 0.035), (0.2, 0.04), (0, 0.042)], (0, 0, 0), W, OAK, segs=16,
            smooth=None, color_fn=quarter, var=0)
    k.lathe([(0.39, -0.005), (0.43, 0.0), (0.43, 0.045), (0.39, 0.05)], (0, 0, 0), MT, IRON_C, segs=16, smooth=40,
            var=0)
    k.lathe([(0.11, 0.03), (0.1, 0.07), (0.06, 0.11), (0, 0.12)], (0, 0, 0), MT, IRON_LT, segs=10, smooth=60,
            var=0)
    k.pop()
    return k.finish_prop("weapon_rack", LARGE, fit=1.05)


def p_anvil_stump():
    k = PK("anvil_stump", seed=22)
    W, MT = k.M("Wood"), k.M("Metal")
    # stump with root flare
    k.log((0, 0, 0), (0, 0, 0.55), 0.3, W, vary(BARK, 0.05), r_end=0.27, segs=10, noise_amt=0.02,
          end_color=vary(ENDGRAIN, 0.05), ring_step=0.3)
    for i in range(5):
        a = i / 5 * tau + 0.3
        k.bar((math.cos(a) * 0.2, math.sin(a) * 0.2, 0.2), (math.cos(a) * 0.42, math.sin(a) * 0.42, 0.0), 0.12, 0.1,
              W, vary(BARK, 0.08), up=(0, 0, 1), bevel=0.02, var=0)
    z = 0.55
    ir, top = hexc("3b3937"), hexc("8e8c88")
    k.box((0.36, 0.26, 0.07), (0, 0, z + 0.035), MT, ir, bevel=0.012, var=0)
    k.cyl(0.15, 0.14, (0, 0, z + 0.07), MT, ir, segs=4, r2=0.095, rot=(0, 0, tau / 8), smooth=None)
    k.box((0.5, 0.17, 0.11), (0.03, 0, z + 0.265), MT, ir, bevel=0.018, var=0)
    k.box((0.48, 0.15, 0.01), (0.03, 0, z + 0.32), MT, top, var=0, grime=False)          # polished face
    k.cyl(0.08, 0.3, (-0.22, 0, z + 0.27), MT, ir, rot=(0, -math.pi / 2 - 0.08, 0), segs=8, r2=0.008, smooth=45)
    k.box((0.1, 0.12, 0.07), (0.3, 0, z + 0.29), MT, ir, bevel=0.012, var=0)
    k.box((0.03, 0.03, 0.012), (0.2, 0, z + 0.326), MT, hexc("141312"), var=0, grime=False)   # hardy hole
    # hammer on the anvil
    k.bar((-0.02, 0.02, z + 0.345), (0.22, -0.26, z + 0.31), 0.035, 0.03, W, vary(OAK_LT, 0.05), bevel=0.006, var=0)
    k.box((0.13, 0.055, 0.055), (-0.03, 0.035, z + 0.35), MT, IRON_LT, rot=(0, 0, -0.85), bevel=0.008, var=0)
    # tongs leaning on the stump
    for s in (-1, 1):
        k.bar((0.28 + s * 0.02, -0.25, 0.0), (0.2 - s * 0.03, -0.18, 0.62), 0.022, 0.018, MT, IRON_C, bevel=0,
              var=0)
    # quench bucket with water
    bx, by = -0.55, -0.12
    k.lathe([(0, 0), (0.17, 0), (0.2, 0.36), (0.18, 0.36), (0.15, 0.04), (0, 0.04)], (bx, by, 0), W,
            vary(OAK_LT, 0.05), segs=10, smooth=50, var=0)
    k.cyl(0.19, 0.01, (bx, by, 0.3), k.M("Water"), hexc("2f5b6e"), segs=10, var=0, grime=False)
    for hz in (0.06, 0.3):
        k.cyl(0.17 + hz * 0.083 + 0.008, 0.03, (bx, by, hz), MT, IRON_C, segs=10, caps=False)
    # horseshoes on the ground
    for (hx, hy, hr) in ((0.3, 0.32, 0.4), (0.42, 0.18, 2.2)):
        pts = [(hx + 0.07 * math.cos(hr + a), hy + 0.07 * math.sin(hr + a), 0.012)
               for a in [math.radians(-130 + i * 260 / 7) for i in range(8)]]
        k.tube(pts, [0.014] * 8, MT, IRON_C, segs=4, point_end=False)
    return k.finish_prop("anvil_stump", SMALL, fit=1.3)


def fence_post(k, x, y, h=1.1, heavy=False):
    W = k.M("Wood")
    w = 0.18 if heavy else 0.15
    k.box((w, w, h), (x, y, h / 2), W, vary(OAK_DK, 0.05), bevel=0.02, var=0, jitter=0.006)
    k.cyl(w * 0.72, 0.09, (x, y, h), W, vary(OAK_DK, 0.05), segs=4, r2=0.0, rot=(0, 0, tau / 8), smooth=None)


def fence_rails(k, x0, x1, y, zs=(0.45, 0.85)):
    W = k.M("Wood")
    for z in zs:
        dz = random.uniform(-0.03, 0.03)
        k.bar((x0, y, z + dz), (x1, y, z - dz), 0.13, 0.065, W, k.board_c(OAK, 0.1), up=(0, 0, 1), bevel=0.012, var=0)


def p_fence_straight():
    """2 m section: post at x=-1, rails to x=+1 (tuck into the next section's post)."""
    k = PK("fence_straight", seed=23)
    fence_post(k, -1.0, 0)
    k.push((0, 0, 0))
    fence_rails(k, -1.0, 1.0, -0.108)
    k.pop()
    rivet_row(k, [(-1.0, -0.145, z) for z in (0.45, 0.85)], s=0.02)
    grass_tufts(k, [(-0.9, -0.15), (0.3, 0.1), (0.8, -0.12)])
    return k.finish_prop("fence_straight", SMALL, fit=1.2)


def p_fence_corner():
    """Corner post at the origin with 2 m of rails to +X and 2 m to +Y."""
    k = PK("fence_corner", seed=24)
    fence_post(k, 0, 0, heavy=True)
    fence_rails(k, 0.0, 2.0, -0.123)
    k.push((0, 0, 0), (0, 0, math.pi / 2))
    fence_rails(k, 0.0, 2.0, 0.123)
    k.pop()
    rivet_row(k, [(0.12, -0.16, z) for z in (0.45, 0.85)] + [(-0.16, 0.12, z) for z in (0.45, 0.85)], s=0.02)
    grass_tufts(k, [(0.15, -0.15), (1.2, -0.12), (-0.12, 1.3)])
    return k.finish_prop("fence_corner", SMALL, cam_dir=(1.2, -1.3, 0.7), fit=1.1)


def p_fence_gate():
    """2 m gate piece: heavy hinge post at x=-1, plank gate leaf closing on the next section's post at x=+1."""
    k = PK("fence_gate", seed=25)
    W, MT = k.M("Wood"), k.M("Metal")
    fence_post(k, -1.0, 0, h=1.3, heavy=True)
    gx0, gx1, z0, z1 = -0.9, 0.92, 0.12, 1.05
    n = 9
    for i in range(n):
        x = gx0 + (i + 0.5) * (gx1 - gx0) / n
        ht = z1 - z0 + 0.05 * math.sin(i / (n - 1) * math.pi)
        k.box(((gx1 - gx0) / n - 0.015, 0.035, ht), (x, -0.02, z0 + ht / 2), W, k.board_c(OAK), bevel=0.008, var=0)
        k.cyl(((gx1 - gx0) / n - 0.015) / 1.42, 0.05, (x, -0.02, z0 + ht), W, k.board_c(OAK), segs=4, r2=0.0,
              rot=(0, 0, tau / 8), smooth=None)
    for z in (z0 + 0.15, z1 - 0.15):
        k.box((gx1 - gx0, 0.045, 0.1), (0, -0.06, z), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    k.bar((gx0 + 0.08, -0.06, z0 + 0.2), (gx1 - 0.08, -0.06, z1 - 0.2), 0.09, 0.04, W, vary(OAK_DK, 0.05),
          up=(-1, 0, 1), bevel=0.01, var=0)
    for z in (z0 + 0.15, z1 - 0.15):   # strap hinges
        k.box((0.4, 0.012, 0.05), (gx0 + 0.12, -0.09, z), MT, IRON_C, var=0)
        k.cyl(0.025, 0.08, (-1.0 + 0.1, -0.06, z - 0.04), MT, IRON_C, segs=6)
    k.box((0.14, 0.015, 0.03), (gx1 - 0.05, -0.09, 0.75), MT, IRON_C, var=0)   # latch
    k.box((0.03, 0.02, 0.08), (gx1 - 0.14, -0.1, 0.75), MT, IRON_C, var=0)
    grass_tufts(k, [(-0.85, -0.2), (0.5, 0.15)])
    return k.finish_prop("fence_gate", SMALL, fit=1.2)


def p_signpost():
    k = PK("signpost", seed=26)
    W, MT = k.M("Wood"), k.M("Metal")
    stone_block(k, (0.42, 0.42, 0.18), (0, 0, 0.09))
    for i in range(3):
        a = i * tau / 3 + 0.5
        stone_block(k, (0.16, 0.13, 0.1), (math.cos(a) * 0.3, math.sin(a) * 0.3, 0.03), rot=(0, 0, a))
    k.box((0.15, 0.15, 2.5), (0, 0, 1.25), W, vary(OAK_DK, 0.04), bevel=0.02, var=0)
    k.box((0.22, 0.22, 0.05), (0, 0, 2.52), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    k.cyl(0.16, 0.14, (0, 0, 2.545), W, vary(OAK_DK, 0.05), segs=4, r2=0.0, rot=(0, 0, tau / 8), smooth=None)
    paint = [hexc("d9c9a0"), hexc("c9b58a"), hexc("e0d2ae")]
    for (z, rz, L, flip) in ((2.2, 0.12, 0.95, 1), (1.9, math.pi + 0.15, 0.85, -1), (1.6, 0.85, 0.8, 1)):
        k.push((0, 0, z), (0, 0, rz))
        pts = [(0.05, -0.1), (L - 0.14, -0.1), (L, 0.0), (L - 0.14, 0.1), (0.05, 0.1)]
        k.prism(pts, 0.04, (0, -0.1, 0), W, k.board_c(OAK), bevel=0.01, var=0)
        # painted lettering strokes on both faces
        for side in (-1, 1):
            for j in range(4):
                lx = 0.18 + j * (L - 0.4) / 4
                k.box(((L - 0.4) / 4 * 0.7, 0.004, 0.06), (lx + 0.05, -0.1 + side * 0.023, 0.0), k.M("Plaster"),
                      random.choice(paint), var=0, grime=False)
        k.box((0.03, 0.05, 0.03), (0.1, -0.1, 0.0), MT, IRON_C, var=0)
        k.pop()
    k.box((0.19, 0.19, 0.05), (0, 0, 1.4), MT, IRON_C, bevel=0.006, var=0)
    grass_tufts(k, [(0.3, -0.2), (-0.25, 0.3)])
    return k.finish_prop("signpost", SMALL, cam_dir=(1.2, -1.5, 0.5), fit=1.1)


def p_woodpile():
    k = PK("woodpile", seed=27)
    W = k.M("Wood")
    L, D, H = 1.6, 0.46, 0.95
    k.box((L - 0.12, D - 0.14, H - 0.12), (0, 0, H / 2), W, hexc("2e2118"), var=0, grime=False)   # dark core
    for sy in (-0.14, 0.14):
        k.box((L + 0.2, 0.1, 0.08), (0, sy, 0.04), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    r = 0.085
    rows = 6
    for j in range(rows):
        n = 9 if j % 2 == 0 else 8
        span = L - 0.12
        for i in range(n):
            x = -span / 2 + (i + 0.5 + (0.0 if j % 2 == 0 else 0.5)) * span / 9
            z = 0.08 + r * 0.9 + j * r * 1.72
            if j == rows - 1 and random.random() < 0.3:
                continue
            kind = random.choice(["quarter", "quarter", "half", "round"])
            yj = random.uniform(-0.03, 0.03)
            k.split_log((x, -D / 2 + yj, z), (x, D / 2 + yj, z), r * random.uniform(1.0, 1.25), kind=kind,
                        roll=random.uniform(0, tau))
    for sx in (-1, 1):
        k.log((sx * (L / 2 + 0.05), 0, 0), (sx * (L / 2 + 0.05), 0, H + 0.12), 0.05, W, vary(BARK, 0.05), segs=6,
              noise_amt=0.006, ring_step=3, point=0.06)
    # chopping block with axe + a few pieces on the ground
    cx, cy = 1.25, -0.35
    k.log((cx, cy, 0), (cx, cy, 0.42), 0.22, W, vary(BARK, 0.05), segs=9, noise_amt=0.015, end_color=ENDGRAIN,
          ring_step=1)
    k.bar((cx - 0.02, cy, 0.4), (cx + 0.3, cy - 0.32, 0.85), 0.04, 0.034, W, vary(OAK_LT, 0.05), bevel=0.006, var=0)
    k.box((0.17, 0.028, 0.13), (cx - 0.05, cy + 0.05, 0.44), k.M("Metal"), hexc("8a8e92"), rot=(0, 0.35, 0.8),
          bevel=0.006, var=0)
    for (x, y, a) in ((0.95, -0.55, 0.4), (1.5, -0.1, 1.9), (1.05, -0.75, 2.6)):
        k.split_log((x, y, 0.05), (x + math.cos(a) * 0.4, y + math.sin(a) * 0.4, 0.05), 0.08, kind="quarter",
                    roll=random.uniform(0, tau))
    return k.finish_prop("woodpile", SMALL, cam_dir=(0.9, -1.6, 0.6), fit=1.1)


def tray(k, x, y, z, w, d, h, tilt=0.0, c=None):
    """Open display tray (shallow crate) tilted towards the front (-Y); returns its frame (push'd)."""
    W = k.M("Wood")
    c = c or vary(OAK_LT, 0.08)
    k.push((x, y, z), (tilt, 0, 0))
    k.box((w, d, 0.025), (0, 0, 0.0125), W, k.board_c(c), var=0)
    for sy in (-1, 1):
        k.box((w, 0.025, h), (0, sy * (d / 2 - 0.0125), h / 2), W, k.board_c(c), bevel=0.006, var=0)
    for sx in (-1, 1):
        k.box((0.025, d - 0.05, h), (sx * (w / 2 - 0.0125), 0, h / 2), W, k.board_c(c), bevel=0.006, var=0)


def fill(k, w, d, z, goods, n):
    PL = k.M("Plant")
    cols = {"apple": [hexc("b8322b"), hexc("c9452c"), hexc("9e2a24"), hexc("d6a338")],
            "pear": [hexc("b5b84a"), hexc("a6a640"), hexc("c2b457")],
            "cabbage": [hexc("7da54c"), hexc("8fb45e"), hexc("6b9442")],
            "orange": [hexc("e0892c"), hexc("d87a24")], "bread": [hexc("b8834a"), hexc("c99459"), hexc("a8723e")],
            "carrot": [hexc("e07a2c"), hexc("d86c24")]}[goods]
    k.box((w - 0.06, d - 0.06, 0.02), (0, 0, z - 0.01), PL, mix(cols[0], (0, 0, 0), 0.45), var=0, grime=False)
    for i in range(n):
        px, py = random.uniform(-w / 2 + 0.07, w / 2 - 0.07), random.uniform(-d / 2 + 0.07, d / 2 - 0.07)
        c = random.choice(cols)
        if goods == "cabbage":
            k.fruit((px, py, z + 0.05), 0.075, c, squash=0.85, segs=7)
        elif goods == "bread":
            k.sphere(0.07, (px, py, z + 0.03), PL, vary(c, 0.06), scale=(1.4, 0.9, 0.6), subdiv=1, grime=False,
                     rot=(0, 0, random.uniform(0, 3)))
        elif goods == "carrot":
            a = random.uniform(-0.4, 0.4)
            k.cyl(0.022, 0.18, (px, py - 0.08, z + 0.02), PL, vary(c, 0.06), segs=5, r2=0.002,
                  rot=(-math.pi / 2 + 0.1, 0, a), smooth=50)
            k.cyl(0.02, 0.07, (px, py - 0.08, z + 0.02), PL, LEAF, segs=3, r2=0.0, rot=(math.pi / 2 - 0.3, 0, a),
                  grime=False)
        else:
            k.fruit((px, py, z + 0.045), 0.048, c, squash=1.1 if goods == "pear" else 0.9)


def p_produce_table():
    k = PK("produce_table", seed=28)
    W = k.M("Wood")
    L, D, zt = 1.8, 0.8, 0.78
    for i in range(4):
        k.box((L, D / 4 - 0.01, 0.05), (0, -D / 2 + (i + 0.5) * D / 4, zt - 0.025), W, k.board_c(OAK), bevel=0.01,
              var=0)
    for sx in (-1, 1):   # X trestles
        for sy in (-1, 1):
            k.bar((sx * 0.72, sy * 0.32, 0.0), (sx * 0.72, -sy * 0.3, zt - 0.08), 0.08, 0.07, W, vary(OAK_DK, 0.05),
                  up=(0, 1, 0), bevel=0.012, var=0)
        k.box((0.08, D - 0.1, 0.08), (sx * 0.72, 0, zt - 0.09), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    k.box((1.5, 0.07, 0.07), (0, 0, 0.36), W, vary(OAK_DK, 0.05), bevel=0.012, var=0)
    # display trays on the table, tilted to the front
    for (x, goods, n) in ((-0.58, "apple", 11), (0.0, "cabbage", 6), (0.58, "orange", 11)):
        tray(k, x, -0.02, zt + 0.075, 0.52, 0.55, 0.12, tilt=0.22)
        fill(k, 0.52, 0.55, 0.1, goods, n)
        k.pop()
    # riser at the back the trays rest on
    k.box((1.7, 0.2, 0.14), (0, 0.3, zt + 0.07), W, vary(OAK, 0.05), bevel=0.012, var=0)
    # ground: crate of cabbages and a basket of carrots in front
    crate(k, -0.55, -0.72, 0, s=0.44, rz=0.12, open_top=True, h=0.34)
    k.push((-0.55, -0.72, 0.0), (0, 0, 0.12))
    fill(k, 0.44, 0.44, 0.32, "cabbage", 5)
    k.pop()
    tray(k, 0.5, -0.7, 0.0, 0.46, 0.4, 0.16, tilt=0.0)
    fill(k, 0.46, 0.4, 0.14, "carrot", 9)
    k.pop()
    return k.finish_prop("produce_table", LARGE, fit=1.1)


def p_hay_bales():
    k = PK("hay_bales", seed=29)
    TH, W = k.M("Thatch"), k.M("Wood")

    def bale(x, y, z, rz, s=(0.95, 0.48, 0.42)):
        c = vary(STRAW, 0.06, 0.03)
        k.box(s, (x, y, z + s[2] / 2), TH, c, rot=(0, 0, rz), bevel=0.06, jitter=0.014, smooth=50,
              color_fn=lambda f: vary(c, 0.07), var=0)
        for dx in (-0.25, 0.25):
            ca, sa = math.cos(rz), math.sin(rz)
            k.box((0.022, s[1] + 0.014, s[2] + 0.014), (x + ca * dx * s[0], y + sa * dx * s[0], z + s[2] / 2),
                  TH, hexc("6e5234"), rot=(0, 0, rz), var=0)

    bale(-0.5, 0.0, 0.0, 0.05)
    bale(0.48, 0.05, 0.0, -0.06)
    bale(0.0, 0.05, 0.42, 0.12)
    bale(0.2, -0.75, 0.0, 1.4)
    # loose straw
    for i in range(14):
        a = random.uniform(0, tau)
        d = random.uniform(0.65, 1.0)
        k.cyl(0.015, random.uniform(0.15, 0.3), (math.cos(a) * d, math.sin(a) * d * 0.8, 0.01), TH,
              vary(STRAW, 0.1), segs=3, rot=(math.pi / 2, 0, random.uniform(0, tau)), grime=False)
    # pitchfork leaning on the stack
    k.push((1.2, -0.02, 0.0), (0, -0.5, 0.05))
    k.cyl(0.02, 1.35, (0, 0, 0), W, vary(OAK_LT, 0.05), segs=6)
    k.box((0.2, 0.025, 0.03), (0, 0, 1.36), k.M("Metal"), IRON_C, var=0)
    for dx in (-0.09, 0.0, 0.09):
        k.cyl(0.009, 0.24, (dx, 0, 1.36), k.M("Metal"), IRON_C, segs=4, r2=0.002)
    k.pop()
    return k.finish_prop("hay_bales", SMALL, fit=1.1)


def p_water_trough():
    k = PK("water_trough", seed=30)
    W, MT = k.M("Wood"), k.M("Metal")
    L, D, H = 1.7, 0.6, 0.5
    z0 = 0.12
    # log cradles
    for sx in (-1, 1):
        k.box((0.16, D + 0.26, 0.12), (sx * 0.55, 0, 0.06), W, vary(OAK_DK, 0.05), bevel=0.02, var=0)
    k.box((L - 0.1, D - 0.1, 0.05), (0, 0, z0 + 0.03), W, vary(OAK_DK, 0.05), var=0)
    for sy in (-1, 1):
        for i, zz in enumerate((z0 + 0.1, z0 + 0.29)):
            k.box((L, 0.06, 0.19), (0, sy * (D / 2 - 0.03), zz), W, k.board_c(OAK), rot=(-sy * 0.08, 0, 0),
                  bevel=0.012, var=0)
    for sx in (-1, 1):
        k.box((0.08, D + 0.04, H - 0.06), (sx * (L / 2 - 0.02), 0, z0 + (H - 0.06) / 2 - 0.0), W, vary(OAK_DK, 0.05),
              bevel=0.016, var=0)
    k.box((L - 0.14, D - 0.14, 0.01), (0, 0, z0 + 0.34), k.M("Water"), hexc("3c6e82"), var=0, grime=False)
    for x in (-0.45, 0.45):   # iron bands
        for sy in (-1, 1):
            k.box((0.06, 0.012, 0.4), (x, sy * (D / 2 + 0.005), z0 + 0.2), MT, IRON_C, rot=(-sy * 0.08, 0, 0), var=0)
        k.box((0.06, D + 0.04, 0.012), (x, 0, z0 + 0.0), MT, IRON_C, var=0)
    rivet_row(k, [(x, sy * (D / 2 + 0.02), z0 + zz) for x in (-0.45, 0.45) for sy in (-1, 1) for zz in (0.1, 0.3)],
              s=0.02)
    # bucket beside
    bx, by = 1.1, -0.3
    k.lathe([(0, 0), (0.13, 0), (0.155, 0.28), (0.14, 0.28), (0.115, 0.04), (0, 0.04)], (bx, by, 0), W,
            vary(OAK_LT, 0.05), segs=10, smooth=50, var=0)
    for hz in (0.05, 0.23):
        k.cyl(0.13 + hz * 0.09 + 0.008, 0.025, (bx, by, hz), MT, IRON_C, segs=10, caps=False)
    grass_tufts(k, [(-0.95, -0.35), (0.8, 0.35), (-0.3, -0.4)])
    return k.finish_prop("water_trough", SMALL, fit=1.15)


def p_flower_planter():
    k = PK("flower_planter", seed=31)
    W, PL = k.M("Wood"), k.M("Plant")
    L, D, H = 1.1, 0.4, 0.4
    for sy in (-1, 1):
        for zz in (0.1, 0.28):
            k.box((L - 0.1, 0.04, 0.17), (0, sy * (D / 2 - 0.02), zz), W, k.board_c(OAK), var=0)
    for sx in (-1, 1):
        for zz in (0.1, 0.28):
            k.box((0.04, D - 0.08, 0.17), (sx * (L / 2 - 0.07), 0, zz), W, k.board_c(OAK), var=0)
        for sy in (-1, 1):
            k.box((0.08, 0.08, H + 0.04), (sx * (L / 2 - 0.04), sy * (D / 2 - 0.02), (H + 0.04) / 2), W,
                  vary(OAK_DK, 0.05), bevel=0.014, var=0)
    k.box((L - 0.12, 0.05, 0.05), (0, -D / 2 - 0.005, H - 0.01), W, vary(OAK_DK, 0.05), bevel=0.01, var=0)
    k.box((L - 0.12, 0.05, 0.05), (0, D / 2 + 0.005, H - 0.01), W, vary(OAK_DK, 0.05), bevel=0.01, var=0)
    k.box((L - 0.14, D - 0.06, 0.02), (0, 0, H - 0.04), k.M("Matte"), SOIL, var=0, grime=False)
    greens = [hexc("4f7a34"), hexc("5f8c3c"), hexc("6f9a45"), hexc("426b2c")]

    def leaf(base, yaw, pitch, Ll, w):
        pts = [(0, 0), (0.35 * Ll, 0.5 * w), (0.8 * Ll, 0.28 * w), (Ll, 0), (0.8 * Ll, -0.28 * w), (0.35 * Ll, -0.5 * w)]
        k.push(base, (math.pi / 2, -pitch, yaw))
        k.prism(pts, 0.012, (0, 0, 0), PL, vary(random.choice(greens), 0.08), var=0, grime=False)
        k.pop()
    # leafy clumps
    for x in (-0.32, 0.0, 0.32):
        for i in range(7):
            yaw = i / 7 * tau + random.uniform(-0.3, 0.3)
            leaf((x + random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), H - 0.03), yaw,
                 random.uniform(0.05, 0.8), random.uniform(0.19, 0.26), 0.1)
    cols = [hexc("e04f5f"), hexc("f2c14e"), hexc("f5f0e6"), hexc("b05cc9"), hexc("e8833a")]
    for i in range(11):
        x = random.uniform(-0.45, 0.45)
        y = random.uniform(-0.14, 0.12)
        z = H + 0.12 + random.uniform(0, 0.1) - abs(y) * 0.3
        c = random.choice(cols)
        pts = []
        for j in range(10):
            a = j / 10 * tau + 0.3
            rr = 0.075 if j % 2 == 0 else 0.03
            pts.append((math.cos(a) * rr, math.sin(a) * rr))
        k.prism(pts, 0.014, (x, y, z), PL, vary(c, 0.06), rot=(math.pi / 2 + 0.4 + random.uniform(-0.25, 0.25),
                                                                random.uniform(-0.3, 0.3), 0), var=0, grime=False)
        if i % 2 == 0:
            k.box((0.025, 0.025, 0.02), (x, y - 0.01, z + 0.012), PL, hexc("f0c040"), var=0, grime=False)
    return k.finish_prop("flower_planter", SMALL, fit=1.2)


PROPS = {
    "barrel": p_barrel,
    "crate": p_crate,
    "crate_stack": p_crate_stack,
    "sack_pile": p_sack_pile,
    "basket_produce": p_basket_produce,
    "covered_wagon": p_covered_wagon,
    "well": p_well,
    "bench": p_bench,
    "lamp_post": p_lamp_post,
    "notice_board": p_notice_board,
    "weapon_rack": p_weapon_rack,
    "anvil_stump": p_anvil_stump,
    "fence_straight": p_fence_straight,
    "fence_corner": p_fence_corner,
    "fence_gate": p_fence_gate,
    "signpost": p_signpost,
    "woodpile": p_woodpile,
    "produce_table": p_produce_table,
    "hay_bales": p_hay_bales,
    "water_trough": p_water_trough,
    "flower_planter": p_flower_planter,
}


# ====================================================================== contact sheet
FONT = {  # 5x7 bitmap glyphs, rows top->bottom
    "A": "01110 10001 10001 11111 10001 10001 10001", "B": "11110 10001 10001 11110 10001 10001 11110",
    "C": "01111 10000 10000 10000 10000 10000 01111", "D": "11110 10001 10001 10001 10001 10001 11110",
    "E": "11111 10000 10000 11110 10000 10000 11111", "F": "11111 10000 10000 11110 10000 10000 10000",
    "G": "01111 10000 10000 10011 10001 10001 01111", "H": "10001 10001 10001 11111 10001 10001 10001",
    "I": "11111 00100 00100 00100 00100 00100 11111", "J": "00111 00010 00010 00010 00010 10010 01100",
    "K": "10001 10010 10100 11000 10100 10010 10001", "L": "10000 10000 10000 10000 10000 10000 11111",
    "M": "10001 11011 10101 10101 10001 10001 10001", "N": "10001 11001 10101 10011 10001 10001 10001",
    "O": "01110 10001 10001 10001 10001 10001 01110", "P": "11110 10001 10001 11110 10000 10000 10000",
    "Q": "01110 10001 10001 10001 10101 10010 01101", "R": "11110 10001 10001 11110 10100 10010 10001",
    "S": "01111 10000 10000 01110 00001 00001 11110", "T": "11111 00100 00100 00100 00100 00100 00100",
    "U": "10001 10001 10001 10001 10001 10001 01110", "V": "10001 10001 10001 10001 10001 01010 00100",
    "W": "10001 10001 10001 10101 10101 10101 01010", "X": "10001 10001 01010 00100 01010 10001 10001",
    "Y": "10001 10001 01010 00100 00100 00100 00100", "Z": "11111 00001 00010 00100 01000 10000 11111",
    "0": "01110 10001 10011 10101 11001 10001 01110", "1": "00100 01100 00100 00100 00100 00100 01110",
    "2": "01110 10001 00001 00010 00100 01000 11111", "3": "11110 00001 00001 01110 00001 00001 11110",
    "4": "00010 00110 01010 10010 11111 00010 00010", "5": "11111 10000 11110 00001 00001 10001 01110",
    "6": "00110 01000 10000 11110 10001 10001 01110", "7": "11111 00001 00010 00100 01000 01000 01000",
    "8": "01110 10001 10001 01110 10001 10001 01110", "9": "01110 10001 10001 01111 00001 00010 01100",
    "_": "00000 00000 00000 00000 00000 00000 11111", " ": "00000 00000 00000 00000 00000 00000 00000",
    "=": "00000 00000 11111 00000 11111 00000 00000", ".": "00000 00000 00000 00000 00000 01100 01100",
    "/": "00001 00010 00010 00100 01000 01000 10000", "(": "00010 00100 01000 01000 01000 00100 00010",
    ")": "01000 00100 00010 00010 00010 00100 01000", "-": "00000 00000 00000 11111 00000 00000 00000",
    "X2": "",
}


def draw_text(img, text, x, y, scale=3, color=(1, 1, 1)):
    """img: numpy HxWx4 with row 0 at the TOP."""
    cx = x
    for ch in text.upper():
        g = FONT.get(ch, FONT[" "])
        rows = g.split()
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit == "1":
                    y0, x0 = y + r * scale, cx + c * scale
                    img[y0:y0 + scale, x0:x0 + scale, :3] = color
        cx += 6 * scale


def make_sheet(names, lines):
    import numpy as np
    tw, th, lab = 400, 300, 34
    cols = 5
    rows = (len(names) + cols - 1) // cols
    head = 60
    W, H = cols * tw, head + rows * (th + lab)
    sheet = np.zeros((H, W, 4), dtype=np.float32)
    sheet[..., :3] = (0.13, 0.12, 0.11)
    sheet[..., 3] = 1
    draw_text(sheet, "RISING ASHES - VILLAGE PROPS ROUND 3", 16, 16, 4, (0.95, 0.85, 0.6))
    info = {l.split(":")[0].replace("PROP ", ""): l for l in lines}
    for i, n in enumerate(names):
        png = os.path.join(PREV_DIR, f"prop_{n}.png")
        if not os.path.exists(png):
            continue
        im = bpy.data.images.load(png)
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1]   # top row first
        bpy.data.images.remove(im)
        a = a[:h - h % 2, :w - w % 2].reshape(h // 2, 2, w // 2, 2, 4).mean(axis=(1, 3))
        r, c = divmod(i, cols)
        y0, x0 = head + r * (th + lab), c * tw
        sheet[y0 + lab:y0 + lab + th, x0:x0 + tw] = a[:th, :tw]
        tris = ""
        l = info.get(n, "")
        if "tris=" in l:
            tris = " " + l.split("tris=")[1].split()[0]
        draw_text(sheet, f"{n}{tris}", x0 + 8, y0 + 8, 3, (0.95, 0.95, 0.9))
    out = os.path.join(PREV_DIR, "_props_round3_sheet.png")
    im = bpy.data.images.new("sheet", W, H, alpha=False)
    im.pixels.foreach_set(sheet[::-1].ravel())
    im.filepath_raw = out
    im.file_format = "PNG"
    im.save()
    print("sheet", out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = [a for a in argv if not a.startswith("--")] or list(PROPS)
    if "--atlas" in argv or not os.path.exists(ATLAS):
        make_atlas()
    preview = "--no-preview" not in argv
    lines = []
    if "--sheet-only" not in argv:
        for n in names:
            random.seed(hash(n) & 0xffff)
            PK.preview = preview
            k_line = PROPS[n]()
            lines.append(k_line)
            print(k_line, flush=True)
    log = os.path.join(OUT_DIR, "_props_round3_report.txt")
    if lines:
        old = {}
        if os.path.exists(log):
            for l in open(log):
                if l.startswith("PROP "):
                    old[l.split(":")[0]] = l.rstrip("\n")
        for l in lines:
            old[l.split(":")[0]] = l
        with open(log, "w") as f:
            f.write("\n".join(old[k] for k in sorted(old)) + "\n")
    if "--sheet" in argv or "--sheet-only" in argv:
        all_lines = [l.rstrip("\n") for l in open(log)] if os.path.exists(log) else lines
        make_sheet(list(PROPS), all_lines)


main()
