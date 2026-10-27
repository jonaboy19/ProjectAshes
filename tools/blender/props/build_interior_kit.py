"""Interior kit for the scenario-A house and the inn (Rising Ashes, 2026-10-28): procedural Blender builds at real dimensions with
CC0 Poly Haven scans (rough_wood, old_planks_02, beam_wall_01, rough_linen, brown_leather, rusty_metal_02, thatch_roof_angled),
same pipeline as build_village_props.py (Part/tube/box helpers, one baked 1K set per asset, GLB, gate render) but gated in a
dim, warm "firelit" interior light (refs 09/20, KCD interiors).

  bed_rope            2.00 x 1.00 x 0.60  corner-post frame, rope lattice, straw mattress in undyed linen, bolster, rumpled wool blanket
  stool_three_leg     0.34 dia x 0.45     slab seat, 3 splayed legs
  chair_woven         0.45 x 0.45 x 0.92  post-and-rung chair, woven rush seat, 2 back slats
  shelf_pottery       1.20 x 0.26 x 0.30  plank shelf on 2 brackets with 5 jugs/pots (lathe-turned, terracotta + glaze)
  herbs_rack          0.90 x 0.10 x 0.55  hanging pole with 7 tied bundles of dried herbs on strings
  chest_iron          0.90 x 0.50 x 0.55  planked chest, iron bands, corner straps, hasp, side handles
  window_closed /     1.00 x 0.20 x 1.20  timber frame + mullion, diamond-leaded panes (glass = own alpha material),
  window_open                             two plank shutters with Z-braces and strap hinges (closed / swung open inward 100 deg)
  beam_2m/3m/4m       L x 0.20 x 0.24     adzed oak joists, origin at the start end, centre of the section
  post_2m/post_3m     0.22 x 0.22 x H     corner posts with chamfers, origin at the foot
  floor_rushes        1.6 x 1.2 patch     strewn rushes/straw: lumpy low mat + loose strands at the edge

Usage: tools/external/blender.sh tools/blender/props/build_interior_kit.py -- [names...]
"""
import bpy, bmesh, sys, os, math, random, shutil
import numpy as np
from mathutils import Vector, Matrix, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refine_lib as RL
import build_village_props as BV
from build_village_props import Part, tube, box, frame

OUT = os.path.join(RL.ASSETS, "props_refined", "interior")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = r"C:\Users\Jonna\Tools\_scratch\refine"
NAMES = [a for a in argv if not a.startswith("--")]

_I = dict(rough=0.0, wear=0.3, grime=0.6, mud=0.15, mud_h=0.12)
RL.LIB.update({
    "oak_old":    dict(kind="scan", tex="rough_wood", tile=0.9, sat=0.9, val=0.52, tint=(0.92, 0.74, 0.54), bump=0.6,
                       edge=(0.62, 0.50, 0.38), edge_dist=0.006, **_I),
    "planks_old": dict(kind="scan", tex="old_planks_02", tile=1.0, sat=0.85, val=0.55, tint=(0.92, 0.76, 0.58), bump=0.7,
                       edge=(0.6, 0.5, 0.4), edge_dist=0.006, **_I),
    "beam_dark":  dict(kind="scan", tex="beam_wall_01", tile=2.5, sat=0.4, val=0.28, tint=(0.85, 0.72, 0.6), bump=0.8,
                       edge=(0.36, 0.30, 0.25), **_I),
    "linen_raw":  dict(kind="scan", tex="rough_linen", tile=0.35, sat=0.0, val=0.82, tint=(0.80, 0.72, 0.58), bump=0.6,
                       edge=(0.8, 0.74, 0.62), rough=0.0, wear=0.05, grime=0.5, mud=0.0),
    "wool":       dict(kind="scan", tex="rough_linen", tile=0.18, sat=0.0, val=0.7, tint=(0.60, 0.50, 0.40), bump=1.0,
                       edge=(0.5, 0.42, 0.34), rough=0.05, wear=0.05, grime=0.4, mud=0.0),
    "clay":       dict(kind="proc", color=(0.36, 0.17, 0.09), metal=0.0, rough0=0.75, bumpscale=120.0, bump=0.2,
                       edge=(0.5, 0.3, 0.2), wear=0.4, grime=0.5, mud=0.0, edge_dist=0.004),
    "glaze":      dict(kind="proc", color=(0.16, 0.12, 0.06), metal=0.0, rough0=0.3, bumpscale=60.0, bump=0.1,
                       edge=(0.35, 0.22, 0.12), wear=0.3, grime=0.3, mud=0.0, edge_dist=0.004),
    "herb_brown": dict(kind="proc", color=(0.20, 0.15, 0.07), metal=0.0, rough0=0.9, bumpscale=300.0, bump=0.6,
                       edge=(0.32, 0.26, 0.14), wear=0.3, grime=0.3, mud=0.0, edge_dist=0.004),
    "herb_lav":   dict(kind="proc", color=(0.16, 0.13, 0.17), metal=0.0, rough0=0.9, bumpscale=300.0, bump=0.6,
                       edge=(0.30, 0.26, 0.30), wear=0.3, grime=0.3, mud=0.0, edge_dist=0.004),
    "herb":       dict(kind="proc", color=(0.15, 0.17, 0.07), metal=0.0, rough0=0.9, bumpscale=300.0, bump=0.6,
                       edge=(0.30, 0.28, 0.14), wear=0.3, grime=0.3, mud=0.0, edge_dist=0.004),
    "rush":       dict(kind="proc", color=(0.42, 0.34, 0.18), metal=0.0, rough0=0.9, weave=900.0, bump=0.6,
                       edge=(0.55, 0.45, 0.28), wear=0.1, grime=0.5, mud=0.0, edge_dist=0.004),
    "glass":      dict(kind="glass"),
})
for k in ("oak_old", "planks_old", "beam_dark", "linen_raw", "wool", "clay", "glaze", "herb", "rush", "herb_brown", "herb_lav"):
    RL.COLOR_DEBUG[k] = (0.5, 0.5, 0.5)


def reset(seed):
    BV.reset(seed)


def lathe(P, c, prof, segs, cls_fn):
    """Surface of revolution around Z at c; prof = [(r, z)...] bottom->top; cls_fn(i) -> class of ring band i."""
    rings = [[c + Vector((math.cos(2 * math.pi * k / segs) * r, math.sin(2 * math.pi * k / segs) * r, z)) for k in range(segs)]
             for r, z in prof]
    return P.loft(rings, lambda i, j: cls_fn(i), True, cls_fn(0), None)


# ------------------------------------------------------------------ 1 bed
def bed_rope():
    reset(31)
    P = Part("bed_rope")
    L, W, H = 2.0, 1.0, 0.6
    post = 0.085
    rail_z = 0.30
    for sx in (-1, 1):
        for sy in (-1, 1):
            h = H if sx < 0 else 0.48                                  # taller posts at the head
            box(P, Vector((sx * (L / 2 - post / 2), sy * (W / 2 - post / 2), h / 2)), (h, post, post), "oak_old", bevel=0.012,
                jitter=0.003, rot=Matrix.Rotation(math.pi / 2, 3, "Y"))
    for sy in (-1, 1):   # side rails
        box(P, Vector((0, sy * (W / 2 - post / 2), rail_z)), (L - 2 * post, 0.06, 0.11), "oak_old", bevel=0.01, jitter=0.003)
    for sx in (-1, 1):   # end rails + headboard plank
        box(P, Vector((sx * (L / 2 - post / 2), 0, rail_z)), (W - 2 * post, 0.06, 0.11), "oak_old", bevel=0.01, jitter=0.003,
            rot=Matrix.Rotation(math.pi / 2, 3, "Z"))
    box(P, Vector((-(L / 2 - post / 2), 0, 0.50)), (W - 2 * post, 0.04, 0.16), "oak_old", bevel=0.008, jitter=0.003,
        rot=Matrix.Rotation(math.pi / 2, 3, "Z"))
    # rope lattice (seen between the rails under the mattress edge)
    for k in range(6):
        y = -W / 2 + post + (W - 2 * post) * (k + 0.5) / 6
        tube(P, [Vector((-L / 2 + post, y, rail_z + 0.02)), Vector((0, y, rail_z - 0.01)), Vector((L / 2 - post, y, rail_z + 0.02))],
             0.007, 4, "rope")
    for k in range(11):
        x = -L / 2 + post + (L - 2 * post) * (k + 0.5) / 11
        tube(P, [Vector((x, -W / 2 + post, rail_z + 0.025)), Vector((x, 0, rail_z - 0.005)), Vector((x, W / 2 - post, rail_z + 0.025))],
             0.007, 4, "rope")
    # straw mattress: lumpy pillow-box, tied tufts
    mx, my, mz0, mt = L - 2 * post - 0.03, W - 2 * post - 0.02, rail_z + 0.04, 0.15
    rings = []
    st, sg = 22, 24
    for i in range(st + 1):
        x = -mx / 2 + mx * i / st
        ring = []
        for k in range(sg):
            a = 2 * math.pi * k / sg
            ca, sa = math.cos(a), math.sin(a)
            # superellipse section: flat top/bottom, rounded sides
            yy = math.copysign(abs(ca) ** 0.35, ca) * my / 2
            zz = math.copysign(abs(sa) ** 0.6, sa) * mt / 2
            ends = 1 - 0.5 * max(0, (abs(x) - (mx / 2 - 0.06)) / 0.06) ** 2
            lump = 1 + 0.06 * noise.noise(Vector((x * 3, yy * 3, zz * 6)))
            ring.append(Vector((x, yy * ends, mz0 + mt / 2 + zz * lump * ends + 0.012 * noise.noise(Vector((x * 5, yy * 5, 1))))))
        rings.append(ring)
    P.loft(rings, "linen_raw", True, "linen_raw", "linen_raw")
    # bolster at the head
    tube(P, [Vector((-mx / 2 + 0.14, -my / 2 + 0.06, mz0 + mt + 0.05)), Vector((-mx / 2 + 0.14, my / 2 - 0.06, mz0 + mt + 0.05))],
         lambda t: 0.075 * (1 - 0.3 * (2 * t - 1) ** 4), 12, "linen_raw", cap="linen_raw", rough=0.08)
    # rumpled wool blanket: a grid draped over the foot 2/3, hanging over the sides, with folds
    gx, gy = 26, 18
    bx0, bx1 = -mx / 2 + 0.45, mx / 2 + 0.06
    by = my / 2 + 0.16
    top = mz0 + mt + 0.012
    verts = []
    for i in range(gx + 1):
        row = []
        for j in range(gy + 1):
            x = bx0 + (bx1 - bx0) * i / gx
            y = -by + 2 * by * j / gy
            z = top + 0.06 * max(0, math.sin(x * 6.0 + 1.2 * math.sin(y * 3.5))) ** 1.5 + 0.03 * noise.noise(Vector((x * 4, y * 4, 0))) ** 2 + 0.02 * noise.noise(Vector((x * 9, y * 9, 2)))
            over = abs(y) - my / 2
            if over > 0:                                     # hangs down the sides
                y = math.copysign(my / 2 + 0.02 + over * 0.15, y)
                z = top - over * 1.05
            if x > mx / 2:                                   # and over the foot
                z -= (x - mx / 2) * 1.6
                x = mx / 2 + 0.02 + (x - mx / 2) * 0.15
            if i == 0:                                       # turned-back edge, thicker roll
                z += 0.03
            row.append(P.bm.verts.new((x, y, z)))
        verts.append(row)
    for i in range(gx):
        for j in range(gy):
            P.face((verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]), "wool")
    # give the blanket thickness: solidify-like second skin underneath
    for i in range(gx):
        for j in range(gy):
            pass
    return [P.obj()], 1024


# ------------------------------------------------------------------ 2 seats
def stool_three_leg():
    reset(32)
    P = Part("stool_three_leg")
    r, t, h = 0.17, 0.045, 0.45
    prof = [(r * 0.97, h - t), (r, h - t + 0.008), (r, h - 0.008), (r * 0.97, h)]
    rows, side, caps = lathe(P, Vector((0, 0, 0)), prof, 20, lambda i: "oak_old")
    top_cap = P.face(list(rows[-1]), "endgrain")
    P.set_aux(top_cap, lambda co: (co.x * 0.6 + 0.05, co.y * 0.6))
    for k in range(3):
        a = 2 * math.pi * k / 3 + 0.3
        top = Vector((math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, h - 0.005))
        foot = Vector((math.cos(a) * (r * 0.55 + 0.11), math.sin(a) * (r * 0.55 + 0.11), 0))
        tube(P, [top.lerp(foot, t) for t in (0, 0.5, 1)], lambda t: 0.022 - 0.004 * t, 8, "oak_old", cap="endgrain", rough=0.06, seed=k)
    return [P.obj()], 1024


def chair_woven():
    reset(33)
    P = Part("chair_woven")
    w, d, sh, bh = 0.44, 0.42, 0.45, 0.92
    for sx in (-1, 1):
        for sy in (-1, 1):
            top = bh if sy > 0 else sh + 0.03
            pts = [Vector((sx * w / 2, sy * d / 2, 0)), Vector((sx * w / 2, sy * d / 2 + (0.03 if sy > 0 else 0), top))]
            tube(P, pts, lambda t: 0.021 - 0.003 * t, 8, "oak_old", cap="endgrain", rough=0.05, seed=sx + 3 * sy)
    # seat rails (round rungs) + lower stretchers
    for z, rr in ((sh, 0.016), (0.16, 0.011)):
        tube(P, [Vector((-w / 2, -d / 2, z)), Vector((w / 2, -d / 2, z))], rr, 6, "oak_old")
        tube(P, [Vector((-w / 2, d / 2, z)), Vector((w / 2, d / 2, z))], rr, 6, "oak_old")
        tube(P, [Vector((-w / 2, -d / 2, z + 0.01)), Vector((-w / 2, d / 2, z + 0.01))], rr, 6, "oak_old")
        tube(P, [Vector((w / 2, -d / 2, z + 0.01)), Vector((w / 2, d / 2, z + 0.01))], rr, 6, "oak_old")
    # woven rush seat: a slightly dished cushion of rush, weave in the material
    rings = []
    for i in range(9):
        x = -w / 2 + w * i / 8
        ring = []
        for k in range(16):
            a = 2 * math.pi * k / 16
            yy = math.copysign(abs(math.cos(a)) ** 0.3, math.cos(a)) * d / 2
            zz = math.copysign(abs(math.sin(a)) ** 0.5, math.sin(a)) * 0.018
            dish = -0.012 * (1 - (2 * x / w) ** 2) * (1 - (2 * yy / d) ** 2) if zz > 0 else 0
            ring.append(Vector((x, yy, sh + 0.012 + zz + dish)))
        rings.append(ring)
    P.loft(rings, "rush", True, "rush", "rush")
    # back slats
    for z in (0.66, 0.82):
        box(P, Vector((0, d / 2 + 0.02, z)), (w - 0.03, 0.022, 0.07), "oak_old", bevel=0.006, jitter=0.002)
    return [P.obj()], 1024


# ------------------------------------------------------------------ 3 shelf + herbs
def pot(P, c, kind):
    if kind == "jug":
        prof = [(0.0, 0.0), (0.05, 0.0), (0.075, 0.05), (0.08, 0.11), (0.055, 0.19), (0.033, 0.24), (0.036, 0.27), (0.03, 0.27)]
    elif kind == "pot":
        prof = [(0.0, 0.0), (0.06, 0.0), (0.09, 0.05), (0.095, 0.10), (0.08, 0.15), (0.085, 0.165), (0.078, 0.165)]
    else:   # bowl / crock
        prof = [(0.0, 0.0), (0.045, 0.0), (0.07, 0.04), (0.075, 0.09), (0.072, 0.095)]
    top = prof[-1][1]
    glaze_from = int(len(prof) * 0.45)
    rows, side, caps = lathe(P, c, prof, 18, lambda i: "glaze" if i >= glaze_from else "clay")
    # dark interior cap (the mouth)
    P.face(list(rows[-1]), "glaze")
    if kind == "jug":   # handle
        tube(P, [c + Vector((0.055, 0, 0.22)), c + Vector((0.11, 0, 0.19)), c + Vector((0.105, 0, 0.11)), c + Vector((0.075, 0, 0.08))],
             0.011, 6, "clay")


def shelf_pottery():
    reset(34)
    P = Part("shelf_pottery")
    L, D, T = 1.2, 0.26, 0.035
    zt = 0.30
    box(P, Vector((0, 0, zt - T / 2)), (L, D, T), "planks_old", bevel=0.006, jitter=0.002)
    for sx in (-1, 1):   # wall brackets (triangular knee)
        x = sx * (L / 2 - 0.15)
        box(P, Vector((x, D / 2 - 0.02, zt / 2)), (0.04, 0.04, zt - T), "oak_old", bevel=0.005,
            rot=Matrix.Rotation(math.pi / 2, 3, "Z") @ Matrix.Rotation(0, 3, "X"))
        tube(P, [Vector((x, D / 2 - 0.03, 0.04)), Vector((x, -D / 2 + 0.06, zt - T - 0.005))], 0.016, 4, "oak_old", cap="oak_old", twist=math.pi / 4)
    items = [("jug", -0.45), ("pot", -0.2), ("bowl", 0.02), ("jug", 0.22), ("pot", 0.45)]
    for kind, x in items:
        pot(P, Vector((x + random.uniform(-0.02, 0.02), random.uniform(-0.03, 0.02), zt)), kind)
    return [P.obj()], 1024


def herbs_rack():
    reset(35)
    P = Part("herbs_rack")
    zp = 0.55
    tube(P, [Vector((-0.45, 0, zp)), Vector((0.45, 0, zp + 0.005))], 0.02, 8, "oak_old", cap="endgrain", rough=0.05)
    for sx in (-1, 1):   # hanging cords to the ceiling hooks (short stubs; the rack hangs from a joist)
        tube(P, [Vector((sx * 0.4, 0, zp)), Vector((sx * 0.4, 0, zp + 0.2))], 0.004, 4, "rope")
    for k in range(7):
        x = -0.36 + 0.12 * k + random.uniform(-0.015, 0.015)
        ln = random.uniform(0.18, 0.3)
        tube(P, [Vector((x, 0, zp)), Vector((x, 0, zp - 0.06))], 0.003, 4, "rope")
        # bundle: 6-9 separate sprigs splayed from the tie, head-down, each a thin stem with a leafy, ragged tip
        top = zp - 0.06
        cls_b = random.choice(["herb", "herb", "herb_brown", "herb_lav"])
        for sp in range(random.randint(6, 9)):
            a = random.uniform(0, 2 * math.pi)
            spread = random.uniform(0.02, 0.06)
            l2 = ln * random.uniform(0.7, 1.05)
            end = Vector((x + math.cos(a) * spread, math.sin(a) * spread * 0.6, top - l2))
            mid = Vector((x + math.cos(a) * spread * 0.4, math.sin(a) * spread * 0.25, top - l2 * 0.45))
            tube(P, [Vector((x, 0, top)), mid], 0.0018, 3, "herb_brown")
            tube(P, [mid, mid.lerp(end, 0.5), end], lambda t: 0.004 + 0.013 * math.sin(math.pi * min(1, t * 1.2)) ** 0.7, 5, cls_b,
                 rough=0.45, seed=k * 10 + sp)
        tube(P, [Vector((x, 0, top - 0.01)) + Vector((math.cos(a) * 0.009, math.sin(a) * 0.009, 0)) for a in np.linspace(0, 2 * math.pi, 9)],
             0.003, 4, "rope")
    return [P.obj()], 1024


# ------------------------------------------------------------------ 4 chest
def chest_iron():
    reset(36)
    P = Part("chest_iron")
    L, D, H = 0.90, 0.50, 0.52
    lid_t = 0.05
    # carcass + lid as planked boxes (board seams come from the old_planks scan)
    box(P, Vector((0, 0, (H - lid_t) / 2)), (L, D, H - lid_t), "planks_old", bevel=0.008, jitter=0.002)
    box(P, Vector((0, 0, H - lid_t / 2 + 0.003)), (L + 0.02, D + 0.02, lid_t), "planks_old", bevel=0.01, jitter=0.002)
    # feet / skids
    for sy in (-1, 1):
        box(P, Vector((0, sy * (D / 2 - 0.05), 0.015)), (L - 0.04, 0.07, 0.03), "oak_old", bevel=0.006)
    # iron bands: wrap over the lid and down the front/back at 3 positions, plus a horizontal band round the carcass
    for x in (-0.32, 0.0, 0.32):
        sec = [(-D / 2 - 0.016, 0.04), (-D / 2 - 0.016, H + 0.006), (D / 2 + 0.016, H + 0.006), (D / 2 + 0.016, 0.04)]
        for (y0, z0), (y1, z1) in zip(sec[:-1], sec[1:]):
            c = Vector((x, (y0 + y1) / 2, (z0 + z1) / 2))
            ln = math.hypot(y1 - y0, z1 - z0)
            if abs(z1 - z0) > 1e-6:
                box(P, c, (ln, 0.004, 0.045), "iron", rot=Matrix.Rotation(math.pi / 2, 3, "Y"))
            else:
                box(P, c, (0.045, ln, 0.004), "iron")
    for z in (0.12,):
        for sy in (-1, 1):
            box(P, Vector((0, sy * (D / 2 + 0.003), z)), (L - 0.02, 0.004, 0.04), "iron")
        for sx in (-1, 1):
            box(P, Vector((sx * (L / 2 + 0.003), 0, z)), (0.004, D - 0.02, 0.04), "iron")
    # corner straps (L-brackets) on the 4 vertical edges
    for sx in (-1, 1):
        for sy in (-1, 1):
            box(P, Vector((sx * (L / 2 + 0.002), sy * (D / 2 - 0.05), H * 0.45)), (0.004, 0.1, H * 0.8), "iron")
            box(P, Vector((sx * (L / 2 - 0.05), sy * (D / 2 + 0.002), H * 0.45)), (0.1, 0.004, H * 0.8), "iron")
    # hasp + lock plate on the front, ring handles on the ends
    box(P, Vector((0, -D / 2 - 0.022, H - 0.06)), (0.05, 0.006, 0.13), "iron", bevel=0.002)
    box(P, Vector((0, -D / 2 - 0.02, H - 0.15)), (0.12, 0.008, 0.1), "iron", bevel=0.003)
    for sx in (-1, 1):
        ring = [Vector((sx * (L / 2 + 0.03), 0.045 * math.cos(a), H * 0.62 + 0.045 * math.sin(a))) for a in np.linspace(math.pi, 2 * math.pi, 9)]
        tube(P, ring, 0.006, 5, "iron", cap="iron")
        box(P, Vector((sx * (L / 2 + 0.006), 0, H * 0.64)), (0.008, 0.11, 0.05), "iron")
    return [P.obj()], 1024


# ------------------------------------------------------------------ 5 window kit
def window(open_):
    reset(37)
    P = Part("window_open" if open_ else "window_closed")
    W, H, fd, fw = 1.0, 1.2, 0.16, 0.08          # opening width/height, frame depth (wall), member width
    zs = 0.0                                      # origin = bottom centre of the frame (sill), wall face at y = 0
    rotz = Matrix.Rotation(math.pi / 2, 3, "Y")
    box(P, Vector((0, 0, zs + fw / 2)), (W + 2 * fw + 0.08, fd + 0.04, fw), "oak_old", bevel=0.008, jitter=0.002)   # sill
    box(P, Vector((0, 0, zs + H + fw * 1.5)), (W + 2 * fw, fd, fw), "oak_old", bevel=0.008, jitter=0.002)            # head
    for sx in (-1, 1):
        box(P, Vector((sx * (W / 2 + fw / 2), 0, zs + fw + H / 2 + fw / 2)), (H + fw, fd, fw), "oak_old", bevel=0.008, jitter=0.002, rot=rotz)
    box(P, Vector((0, 0, zs + fw + H / 2 + fw / 2)), (H + fw, fd * 0.8, fw * 0.7), "oak_old", bevel=0.006, jitter=0.002, rot=rotz)   # mullion
    # leaded panes: diamond lattice of lead cames in each light, glass sheet (own material, joined after the bake)
    leads = []
    for sx in (-1, 1):
        x0, x1 = (sx * fw * 0.35, sx * W / 2) if sx > 0 else (sx * W / 2, sx * fw * 0.35)
        z0, z1 = zs + fw, zs + fw + H
        step = 0.11
        for k in range(-12, 14):
            # lines x - z*0.6 = const and x + z*0.6 = const, clipped to the light
            for sgn in (1, -1):
                pts = []
                for t in np.linspace(0, 1, 18):
                    z = z0 + (z1 - z0) * t
                    x = k * step + sgn * (z - z0) * 0.6 + (x0 if sgn > 0 else x1) * 0
                    x = x + (x0 + x1) / 2 - 0.0
                    if x0 <= x <= x1:
                        pts.append(Vector((x, 0.0, z)))
                if len(pts) >= 2:
                    tube(P, [pts[0], pts[-1]], 0.0035, 3, "iron")
    # glass sheet
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, zs + fw + H / 2))
    glass = bpy.context.active_object
    glass.rotation_euler = (math.pi / 2, 0, 0)
    glass.scale = (W, H, 1)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    glass.data.materials.append(RL.make_material("glass"))
    # shutters: two leaves of vertical boards with a Z brace, iron strap hinges; inside the room (y < 0)
    for sx in (-1, 1):
        hinge = Vector((sx * (W / 2 + fw), -fd / 2 - 0.02, 0))
        ang = sx * math.radians(100) if open_ else 0.0
        R = Matrix.Rotation(ang, 3, "Z")
        lw = W / 2 + fw * 0.5
        def place(v, R=R, hinge=hinge):
            return hinge + R @ (v - hinge)
        nb = 4
        for b in range(nb):
            bx = hinge.x - sx * (lw * (b + 0.5) / nb)
            c = place(Vector((bx, hinge.y - 0.012, zs + fw + H / 2 + fw / 2)))
            box(P, c, (H + fw * 0.9, lw / nb - 0.004, 0.024), "planks_old", bevel=0.003, jitter=0.002,
                rot=R @ Matrix(((0, 1, 0), (0, 0, 1), (1, 0, 0))))        # local X -> up, Y -> board width (X), Z -> thickness (Y)
        for zz in (zs + fw + 0.12, zs + fw + H - 0.12):      # ledges
            c = place(Vector((hinge.x - sx * lw / 2, hinge.y - 0.036, zz)))
            box(P, c, (lw - 0.04, 0.022, 0.08), "oak_old", bevel=0.004, jitter=0.002, rot=R)
            hc = place(Vector((hinge.x - sx * lw * 0.3, hinge.y - 0.05, zz)))
            box(P, hc, (lw * 0.6, 0.005, 0.03), "iron", rot=R)                                         # strap hinge
        # Z brace
        a = place(Vector((hinge.x - sx * 0.06, hinge.y - 0.036, zs + fw + 0.16)))
        b_ = place(Vector((hinge.x - sx * (lw - 0.06), hinge.y - 0.036, zs + fw + H - 0.16)))
        d = b_ - a
        mid = (a + b_) / 2
        Rb = d.to_track_quat("X", "Z").to_matrix()
        box(P, mid, (d.length, 0.022, 0.07), "oak_old", bevel=0.004, rot=Rb)
    ob = P.obj()
    return [ob], 1024, glass


def window_closed():
    return window(False)


def window_open():
    return window(True)


# ------------------------------------------------------------------ 6 beams and posts
def beam(L):
    def f():
        reset(int(40 + L))
        P = Part("beam_%dm" % L)
        st = max(6, int(L * 5))
        rings = []
        for i in range(st + 1):
            x = L * i / st
            sag = -0.006 * math.sin(math.pi * i / st)
            w, h, ch = 0.10, 0.12, 0.022
            sec = [(-w + ch, -h), (w - ch, -h), (w, -h + ch), (w, h - ch), (w - ch, h), (-w + ch, h), (-w, h - ch), (-w, -h + ch)]
            ring = []
            for k, (y, z) in enumerate(sec):
                adze = 0.004 * noise.noise(Vector((x * 4, k * 1.7, 0))) + 0.006 * max(0, noise.noise(Vector((x * 1.3, k, 5))))
                ring.append(Vector((x, y * (1 + adze * 4), z + sag + adze * (1 if z > 0 else -1))))
            rings.append(ring)
        rows, side, caps = P.loft(rings, "beam_dark", True, "endgrain", "endgrain")
        for cf in caps:
            ccen = cf.calc_center_median()
            P.set_aux(cf, lambda co, ccen=ccen: (co.y + 0.02, co.z - 0.03))
        return [P.obj()], 1024
    return f


def post(H):
    def f():
        reset(int(50 + H))
        P = Part("post_%dm" % H)
        box(P, Vector((0, 0, H / 2)), (H, 0.22, 0.22), "beam_dark", bevel=0.025, jitter=0.004, rot=Matrix.Rotation(-math.pi / 2, 3, "Y"))
        return [P.obj()], 1024
    return f


# ------------------------------------------------------------------ 7 floor rushes
def floor_rushes():
    reset(60)
    P = Part("floor_rushes")
    # irregular low mat (1.6 x 1.2), thin at the edges
    segs, rings_n = 36, 7
    rings = []
    for r_i in range(rings_n + 1):
        t = r_i / rings_n
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            edge = 1 + 0.25 * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, 3.3)))
            rx, ry = 0.65 * edge * (1 - t), 0.48 * edge * (1 - t)
            z = 0.002 + 0.025 * (1 - (1 - t) ** 3) * (0.7 + 0.3 * noise.noise(Vector((math.cos(a) * 3, math.sin(a) * 3, t * 4))))
            ring.append(Vector((math.cos(a) * rx, math.sin(a) * ry, z)))
        rings.append(ring)
    rings[-1] = [Vector((0, 0, 0.028))] * segs
    P.loft(rings, "straw", True, None, None)
    bmesh.ops.remove_doubles(P.bm, verts=P.bm.verts, dist=1e-4)
    # loose strands around the edge (thin flat strips)
    for k in range(380):
        a = random.uniform(0, 2 * math.pi)
        rr = random.uniform(0.2, 1.25) ** 0.6
        c = Vector((math.cos(a) * 0.8 * rr, math.sin(a) * 0.6 * rr, 0.003 + (0.02 if rr < 0.8 else 0.0) * random.random()))
        d = Vector((math.cos(a + random.uniform(-1.2, 1.2)), math.sin(a + random.uniform(-1.2, 1.2)), 0)) * random.uniform(0.08, 0.22)
        tube(P, [c - d / 2, c + d / 2 + Vector((0, 0, 0.004))], 0.0025, 3, "straw")
    return [P.obj()], 1024


ASSETS = {"bed_rope": bed_rope, "stool_three_leg": stool_three_leg, "chair_woven": chair_woven, "shelf_pottery": shelf_pottery,
          "herbs_rack": herbs_rack, "chest_iron": chest_iron, "window_closed": window_closed, "window_open": window_open,
          "beam_2m": beam(2), "beam_3m": beam(3), "beam_4m": beam(4), "post_2m": post(2), "post_3m": post(3),
          "floor_rushes": floor_rushes}
ORIGIN_KEEP = {"window_closed", "window_open", "beam_2m", "beam_3m", "beam_4m"}


def build(name):
    res = ASSETS[name]()
    obs, tex = res[0], res[1]
    extra = res[2] if len(res) > 2 else None
    ob = RL.join(obs, name)
    if name not in ORIGIN_KEEP:
        RL.origin_to_feet(ob)
    RL.smart_uv(ob, angle=60.0, margin=0.003)
    tmp = os.path.join(WORK, "bake_" + name)
    fm = RL.bake_asset(ob, tex, tmp, name)
    RL.finalize_materials(ob, fm)
    if extra is not None:
        extra.data.uv_layers.new(name="bake_uv")
        ob = RL.join([ob, extra], name)
    folder = os.path.join(OUT, name)
    RL.export_glb(ob, os.path.join(folder, name + ".glb"))
    RL.write_license(folder, name, "Geometry: built procedurally in Blender by tools/blender/props/build_interior_kit.py (project-owned).")
    bpy.data.objects.remove(ob)
    for g in list(bpy.data.node_groups):
        bpy.data.node_groups.remove(g)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name + ".glb"))
    new = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    gate = os.path.join(WORK, "gate_i")
    os.makedirs(gate, exist_ok=True)
    RL.render_view(new, os.path.join(gate, f"{name}_B_refined.jpg"), interior=True)
    with open(os.path.join(WORK, "stats_i.txt"), "a") as f:
        mn, mx = RL.bbox_of(new)
        f.write(f"{name}\t{sum(RL.tri_count(o) for o in new)}\t{tex}\t{tuple(round(x, 2) for x in (mx - mn))}\n")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    for n in (NAMES or list(ASSETS)):
        try:
            build(n)
        except Exception as e:
            import traceback
            traceback.print_exc()
            print("FAILED", n, e, flush=True)
    print("DONE")
