"""Region set 1: NATURE UPGRADE for the first 8 x 8 km region (Rising Ashes, Godot 4.6, mobile).

Painterly broadleaf trees (layered clumps of alpha-cut leaf-cluster cards with canopy normals),
spruces/pines, dead and dark-forest trees, bushes, grass and flower clumps, ferns, rocks,
mossy stumps and logs. Every asset shares 4 materials / 4 textures:
    RG_Foliage  foliage_atlas.png (1024, alpha scissor)     RG_Bark  bark_atlas.png (1024)
    RG_Rock     rock.png (512, tiled)                       RG_Moss  moss.png (512, tiled)
COLOR_0 = wind data: R sway weight, G phase, B baked AO (see region_kit.py and region/README.md).

Run headless (Blender 5.x) from the repo root:
    blender -b --factory-startup --python kingdom/tools/blender/make_region_nature.py -- \
        [names...] [--textures] [--no-thumbs] [--impostors] [--sheet] [--scene]

Outputs: kingdom/assets/generated/region/nature/<name>.glb, <name>_lod1.glb, trees also
<name>_lod2.glb (2 crossed impostor cards using textures/tree_impostors.png);
docs/kingdom/blender_previews/region_nature_sheet.png and region_forest_scene.png.
Budgets: trees LOD0 <= 3000 tris, LOD1 <= 800; grass <= 150 per clump.
"""
import os, sys, math, random, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, noise
import region_kit as K
from region_kit import RB

OUT = os.path.join(K.REGION, "nature")
REPORT = os.path.join(OUT, "_report.json")
UP = Vector((0, 0, 1))


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def sstep(a, b, x):
    t = clamp((x - a) / (b - a))
    return t * t * (3 - 2 * t)


def dir_from(az, el):
    return Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))


def rand_unit(rng, zmin=-1.0, zmax=1.0):
    z = rng.uniform(zmin, zmax)
    a = rng.uniform(0, math.tau)
    r = math.sqrt(max(0.0, 1 - z * z))
    return Vector((r * math.cos(a), r * math.sin(a), z))


def polyline(start, d, L, n, rng, wobble=0.15, trop=0.0, bend=None):
    pts = [Vector(start)]
    d = Vector(d).normalized()
    step = L / (n - 1)
    for i in range(1, n):
        d = (d + Vector((rng.gauss(0, wobble), rng.gauss(0, wobble), rng.gauss(0, wobble) + trop))).normalized()
        if bend is not None:
            d = (d + Vector(bend)).normalized()
        pts.append(pts[-1] + d * step)
    return pts


def perp_pair(n, rng):
    ref = rand_unit(rng)
    r = n.cross(ref)
    if r.length < 1e-4:
        r = n.cross(Vector((1, 0, 0)))
    r.normalize()
    u = r.cross(n).normalized()
    return r, u


# ============================================================================ colour (wind) fns
def bark_col(H, phase, ao_mul=1.0, flex=0.6):
    def f(p, n, t):
        sway = clamp((p.z - 0.25 * H) / (0.75 * H)) ** 1.5 * flex
        ao = (0.5 + 0.5 * sstep(-0.2, 1.4, p.z)) * ao_mul * (0.86 + 0.14 * max(0.0, n.z))
        return (sway, phase, clamp(ao), 1.0)
    return f


def leaf_col(cc, cr, H, phase, ao_lo=0.5, sway_base=0.35):
    def f(p, t):
        q = p - cc
        q = Vector((q.x / cr.x, q.y / cr.y, q.z / cr.z))
        outer = min(1.0, q.length)
        lit = clamp(0.55 * outer + 0.32 * (0.5 + 0.5 * clamp(q.z, -1, 1)) + 0.08)
        ao = ao_lo + (1 - ao_lo) * lit
        sway = clamp(sway_base + (1 - sway_base) * outer) * clamp(p.z / max(H, 0.1) + 0.25)
        return (sway, phase, ao, 1.0)
    return f


def canopy_nrm(clump_c, rc, cc, cr, up=0.22, w_clump=0.55):
    def f(p):
        a = (p - clump_c) / max(rc, 1e-3)
        q = p - cc
        b = Vector((q.x / cr.x, q.y / cr.y, q.z / cr.z))
        n = a * w_clump + b * (1 - w_clump) + UP * up
        return n.normalized() if n.length > 1e-6 else UP
    return f


# ============================================================================ broadleaf
def broadleaf(k, lod, P):
    """P: dict(seed, trunk_h, r0, limbs, limb_len, limb_el, sub, clump_r, cards, card, cells, lean,
    crown_squash, bark_col, extra_top)"""
    rng = random.Random(P["seed"])
    hs = P["trunk_h"]
    r0 = P["r0"]
    lean = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)).normalized() * P.get("lean", 0.08)
    # trunk: flare ring below ground, gentle S-curve
    tp, tr = [], []
    zs = [-0.25, 0.05, 0.35, hs * 0.35, hs * 0.65, hs]
    for i, z in enumerate(zs):
        off = lean * z + Vector((math.sin(z * 1.3 + P["seed"]) * 0.06, math.cos(z * 1.1) * 0.06, 0))
        tp.append(Vector((off.x, off.y, z)))
        tr.append(r0 * (1.75 if i == 0 else 1.3 if i == 1 else 1.08 if i == 2 else 1.0 - 0.22 * z / hs))
    top = tp[-1]
    H_est = hs + P["limb_len"] * 0.9 + P["clump_r"]
    phase0 = rng.random()
    bcol = P.get("bark_col", 0)
    segs_t = 8 if lod == 0 else 6
    k.tube(tp, tr, "RG_Bark", segs=segs_t, cap_start=False, cap_end=False, bark=bcol,
           col_fn=bark_col(H_est, phase0), noise_amt=0.12, vscale=2.5)
    # limbs
    clumps = []
    nl = P["limbs"]
    az0 = rng.uniform(0, math.tau)
    branch_list = []
    for i in range(nl):
        az = az0 + i / nl * math.tau + rng.uniform(-0.35, 0.35)
        el = math.radians(rng.uniform(*P["limb_el"]))
        L = P["limb_len"] * rng.uniform(0.8, 1.15)
        start = top - Vector((0, 0, rng.uniform(0, hs * 0.18)))
        pts = polyline(start, dir_from(az, el), L, 4, rng, wobble=0.12, trop=0.06)
        rl = tr[-1] * rng.uniform(0.62, 0.75)
        branch_list.append((pts, [rl, rl * 0.7, rl * 0.45, rl * 0.25], rng.random()))
        clumps.append((pts[-1] + dir_from(az, el) * P["clump_r"] * 0.3, P["clump_r"] * rng.uniform(0.95, 1.2)))
        for j in range(P["sub"]):
            t = rng.uniform(0.45, 0.85)
            idx = min(2, int(t * 3))
            sp = pts[idx].lerp(pts[idx + 1], t * 3 - idx)
            d = (pts[-1] - pts[0]).normalized()
            saz = math.atan2(d.y, d.x) + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0)
            sel = math.radians(rng.uniform(15, 55))
            sL = L * rng.uniform(0.45, 0.65)
            spts = polyline(sp, dir_from(saz, sel), sL, 3, rng, wobble=0.1, trop=0.08)
            rs = rl * 0.45
            branch_list.append((spts, [rs, rs * 0.6, rs * 0.3], rng.random()))
            clumps.append((spts[-1], P["clump_r"] * rng.uniform(0.75, 1.0)))
    # extra clumps filling the crown top/centre
    cc0 = sum((c for c, r in clumps), Vector()) / len(clumps)
    for i in range(P.get("extra_top", 2)):
        a = rng.uniform(0, math.tau)
        rr = P["clump_r"] * rng.uniform(0.0, 1.0)
        clumps.append((cc0 + Vector((math.cos(a) * rr, math.sin(a) * rr, P["clump_r"] * rng.uniform(0.4, 1.0))),
                       P["clump_r"] * 1.1))
    for i in range(P.get("extra_low", 0)):
        a = rng.uniform(0, math.tau)
        clumps.append((cc0 + Vector((math.cos(a) * P["clump_r"] * 1.1, math.sin(a) * P["clump_r"] * 1.1,
                                     -P["clump_r"] * 0.55)), P["clump_r"] * 0.85))
    for pts, rad, ph in branch_list:
        if lod == 1 and rad[0] < tr[-1] * 0.4:
            continue
        k.tube(pts, rad, "RG_Bark", segs=6 if lod == 0 else 4, cap_start=False, cap_end=False, bark=bcol,
               col_fn=bark_col(H_est, (phase0 + ph * 0.3) % 1, ao_mul=0.8), tip=True, vscale=2.5)
    # crown extents
    lo = Vector((min(c.x - r for c, r in clumps), min(c.y - r for c, r in clumps), min(c.z - r for c, r in clumps)))
    hi = Vector((max(c.x + r for c, r in clumps), max(c.y + r for c, r in clumps), max(c.z + r for c, r in clumps)))
    cc = (lo + hi) / 2
    cr = (hi - lo) / 2
    H = hi.z
    frng = random.Random(P["seed"] * 7 + 1)
    ncard = P["cards"] if lod == 0 else max(5, int(P["cards"] * P.get("lod1_frac", 0.3)))
    csize = P["card"] * (1.0 if lod == 0 else 1.45)
    for ci, (c, rc) in enumerate(clumps):
        ph = frng.random()
        colf = leaf_col(cc, cr, H, ph)
        nf = canopy_nrm(c, rc, cc, cr)
        for i in range(ncard):
            d = rand_unit(frng, -0.45, 1.0)
            p = c + Vector((d.x, d.y, d.z * P.get("crown_squash", 0.8))) * rc * frng.uniform(0.62, 1.0)
            n = (d + rand_unit(frng) * 0.45).normalized()
            r, u = perp_pair(n, frng)
            s = csize * frng.uniform(0.8, 1.2)
            cell = frng.choice(P["cells"])
            k.card(p, r, u, s, s, cell, cols=colf, nrms=nf)
    return H


TREES = {
    "oak_a": dict(seed=11, trunk_h=2.6, r0=0.34, limbs=5, limb_len=3.0, limb_el=(30, 55), sub=2, clump_r=1.6,
                  cards=26, card=1.75, cells=[(0, 0), (0, 0), (0, 1)], lean=0.05, extra_top=5, extra_low=3,
                  crown_squash=0.95),
    "oak_b": dict(seed=23, trunk_h=2.2, r0=0.28, limbs=4, limb_len=2.6, limb_el=(35, 60), sub=2, clump_r=1.45,
                  cards=26, card=1.6, cells=[(0, 1), (0, 0)], lean=0.12, extra_top=4, extra_low=2,
                  crown_squash=0.95),
    "beech_a": dict(seed=37, trunk_h=3.6, r0=0.3, limbs=4, limb_len=3.4, limb_el=(52, 72), sub=2, clump_r=1.45,
                    cards=26, card=1.65, cells=[(0, 2), (0, 2), (0, 1)], lean=0.04, extra_top=5, crown_squash=1.0, extra_low=2,
                    bark_col=0),
    "beech_b": dict(seed=41, trunk_h=2.8, r0=0.24, limbs=3, limb_len=2.6, limb_el=(45, 68), sub=2, clump_r=1.25,
                    cards=26, card=1.45, cells=[(0, 2), (0, 1)], lean=0.1, extra_top=4, extra_low=2, crown_squash=1.0),
    "young_oak": dict(seed=53, trunk_h=1.5, r0=0.12, limbs=3, limb_len=1.5, limb_el=(40, 65), sub=1, clump_r=0.9,
                      cards=24, card=1.05, cells=[(0, 1), (0, 2)], lean=0.1, extra_top=3, lod1_frac=0.33, crown_squash=1.0),
}


# ============================================================================ conifers
def spruce(k, lod, P):
    rng = random.Random(P["seed"])
    H = P["h"]
    r0 = P["r0"]
    base_r = P["spread"]
    z0 = P["crown_start"] * H
    tp = [Vector((0, 0, -0.25)), Vector((0, 0, 0.1))] + [Vector((rng.gauss(0, 0.03), rng.gauss(0, 0.03), H * t))
                                                        for t in (0.3, 0.6, 0.85, 1.0)]
    tr = [r0 * 1.5, r0 * 1.15, r0 * 0.8, r0 * 0.5, r0 * 0.25, 0.02]
    phase0 = rng.random()
    k.tube(tp, tr, "RG_Bark", segs=7 if lod == 0 else 5, cap_start=False, cap_end=False, bark=P.get("bark", 1),
           col_fn=bark_col(H, phase0, flex=0.35), tip=True, noise_amt=0.05)
    cc = Vector((0, 0, (z0 + H) / 2))
    cr = Vector((base_r, base_r, (H - z0) / 2))
    step = P["whorl"] * (1.0 if lod == 0 else 1.9)
    nb = P["per_whorl"] if lod == 0 else max(3, P["per_whorl"] - 2)
    z = z0
    frng = random.Random(P["seed"] + 5)
    az_off = 0.0
    while z < H - 0.35:
        t = (z - z0) / (H - z0)
        L = base_r * (1 - t) ** P.get("shape", 0.95) + 0.35
        az_off += 2.39996
        for i in range(nb):
            az = az_off + i / nb * math.tau + frng.uniform(-0.25, 0.25)
            el = math.radians(-P["droop"] * (1 - t) + frng.uniform(-6, 10))
            d = dir_from(az, el)
            start = Vector((0, 0, z))
            ph = frng.random()
            if lod == 0 and t < 0.75 and i % 2 == 0:
                k.tube([start, start + d * L * 0.9], [0.035 + 0.03 * (1 - t), 0.012], "RG_Bark", segs=3,
                       cap_start=False, cap_end=False, bark=P.get("bark", 1), col_fn=bark_col(H, ph, 0.7, 0.4))
            colf = leaf_col(cc, cr, H, ph, ao_lo=0.45)
            side = d.cross(UP).normalized()
            for roll in ((-0.6, 0.6) if lod == 0 else (0.0,)):
                # card plane contains the branch; tilt it around the branch axis
                r = (side * math.cos(roll) + UP * math.sin(roll)).normalized()
                u = d
                nrm = r.cross(u).normalized()
                w = L * P["card_w"] * (1.0 if lod == 0 else 1.25)
                h = L * 1.12
                nf = lambda p, s=start: (Vector((p.x, p.y, 0)).normalized() * 0.75 + UP * 0.45).normalized() \
                    if Vector((p.x, p.y, 0)).length > 1e-4 else UP
                k.card(start + d * 0.05 - UP * 0.05, r, u, w, h, frng.choice(P["cells"]), cols=colf, nrms=nf,
                       base=True, segs=2 if lod == 0 else 1, bend=-L * 0.12)
        z += step * frng.uniform(0.85, 1.15)
    # silhouette core: crossed vertical cards along the upper trunk + tip
    ncore = 3 if lod == 0 else 2
    for i in range(ncore):
        a = i / ncore * math.pi
        r = Vector((math.cos(a), math.sin(a), 0))
        ph = frng.random()
        colf = leaf_col(cc, cr, H, ph, ao_lo=0.45)
        nf = lambda p: (Vector((p.x, p.y, 0)).normalized() * 0.7 + UP * 0.5).normalized() \
            if Vector((p.x, p.y, 0)).length > 1e-4 else UP
        tip_h = min(H * 0.34, 3.6)
        k.card(Vector((0, 0, H - tip_h)), r, UP, tip_h * 0.62, tip_h + 0.25, P["cells"][0], cols=colf, nrms=nf,
               base=True)
    return H


PINES = {
    "spruce_a": dict(seed=61, h=13.0, r0=0.3, spread=2.9, crown_start=0.12, whorl=0.62, per_whorl=7, droop=24,
                     card_w=1.3, cells=[(1, 0), (1, 0), (1, 1)]),
    "spruce_b": dict(seed=67, h=8.5, r0=0.2, spread=2.1, crown_start=0.08, whorl=0.5, per_whorl=7, droop=20,
                     card_w=1.35, cells=[(1, 0), (1, 1)]),
}


def scots_pine(k, lod, P):
    """Tall bare trunk, crown only at the top: pine-spray clumps (broadleaf-style) with pine bark."""
    Q = dict(seed=P["seed"], trunk_h=P["trunk_h"], r0=P["r0"], limbs=5, limb_len=2.6, limb_el=(12, 38), sub=2,
             clump_r=1.3, cards=22, card=1.5, cells=[(1, 1), (1, 1), (1, 0)], lean=0.1, extra_top=3,
             crown_squash=0.6, bark_col=1)
    return broadleaf(k, lod, Q)


# ============================================================================ dead / dark trees
def dead_tree(k, lod, P):
    rng = random.Random(P["seed"])
    hs = P["trunk_h"]
    r0 = P["r0"]
    tp = [Vector((0, 0, -0.25)), Vector((0, 0, 0.1))]
    tr = [r0 * 1.8, r0 * 1.3]
    for i, t in enumerate((0.3, 0.55, 0.8, 1.0)):
        tp.append(Vector((math.sin(t * 4 + P["seed"]) * 0.35 * t, math.cos(t * 3) * 0.25 * t, hs * t)))
        tr.append(r0 * (1.0 - 0.45 * t))
    H = hs + P["limb_len"]
    phase0 = rng.random()
    bc = P.get("bark", 2)
    aom = P.get("ao", 1.0)
    k.tube(tp, tr, "RG_Bark", segs=8 if lod == 0 else 6, cap_start=False, cap_end=P.get("broken_top", False),
           bark=bc, col_fn=bark_col(H, phase0, aom, flex=0.2), noise_amt=0.18, tip=not P.get("broken_top", False))
    tips = []

    def grow(start, d, L, r, depth):
        pts = polyline(start, d, L, 4, rng, wobble=0.28, trop=P.get("trop", 0.02))
        tip = depth == 0 and rng.random() < 0.8
        if lod == 1 and depth < P["depth"] - 1:
            tips.append((pts[-1], (pts[-1] - pts[0]).normalized(), L))
            return
        k.tube(pts, [r, r * 0.7, r * 0.45, r * 0.2], "RG_Bark", segs=5 if (lod == 0 and r > 0.05) else 3,
               cap_start=False, cap_end=not tip, bark=bc, col_fn=bark_col(H, rng.random(), aom * 0.9, 0.5), tip=tip)
        tips.append((pts[-1], (pts[-1] - pts[0]).normalized(), L))
        if depth > 0:
            for j in range(rng.choice([1, 2, 2])):
                t = rng.uniform(0.5, 0.95)
                idx = min(2, int(t * 3))
                sp = pts[idx].lerp(pts[idx + 1], t * 3 - idx)
                dd = (d + rand_unit(rng) * 0.9).normalized()
                dd.z = abs(dd.z) * 0.8 + 0.1
                grow(sp, dd, L * rng.uniform(0.5, 0.7), r * 0.55, depth - 1)
    for i in range(P["limbs"]):
        az = i / P["limbs"] * math.tau + rng.uniform(-0.4, 0.4)
        t = rng.uniform(0.55, 1.0)
        idx = min(len(tp) - 2, 2 + int(t * 3))
        start = tp[idx].lerp(tp[idx + 1], 0.5)
        grow(start, dir_from(az, math.radians(rng.uniform(20, 55))), P["limb_len"] * rng.uniform(0.75, 1.1),
             r0 * 0.5, P["depth"])
    # twig cards (bare) at branch ends
    frng = random.Random(P["seed"] + 3)
    for p, d, L in tips:
        for j in range(P.get("twigs", 2) if lod == 0 else 1):
            n = (d.cross(UP) + rand_unit(frng) * 0.5).normalized()
            u = (d + UP * 0.3 + rand_unit(frng) * 0.3).normalized()
            r = u.cross(n).normalized()
            s = L * frng.uniform(0.7, 1.0) * P.get("twig_scale", 0.9)
            k.card(p - u * s * 0.15, r, u, s, s, (3, 1), base=True,
                   cols=lambda q, t: (clamp(0.4 + 0.6 * t), frng.random(), 0.75 + 0.25 * t, 1.0))
    return H, tips


def dark_tree(k, lod, P):
    H, tips = dead_tree(k, lod, dict(seed=P["seed"], trunk_h=P["trunk_h"], r0=P["r0"], limbs=P["limbs"],
                                     limb_len=P["limb_len"], depth=1, bark=0, ao=0.62, twigs=1, trop=0.05,
                                     twig_scale=0.7))
    frng = random.Random(P["seed"] + 9)
    pts = [p for p, d, L in tips]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))) - Vector((1, 1, 1))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))) + Vector((1, 1, 1))
    cc, cr = (lo + hi) / 2, (hi - lo) / 2
    for p, d, L in tips:
        if frng.random() < 0.3:
            continue
        rc = 0.95 * frng.uniform(0.8, 1.15)
        c = p + UP * 0.2
        ph = frng.random()
        colf = leaf_col(cc, cr, hi.z, ph, ao_lo=0.3)
        nf = canopy_nrm(c, rc, cc, cr)
        for i in range(P["cards"] if lod == 0 else 3):
            dd = rand_unit(frng, -0.3, 1.0)
            q = c + dd * rc * frng.uniform(0.3, 0.9)
            n = (dd + rand_unit(frng) * 0.5).normalized()
            r, u = perp_pair(n, frng)
            s = 1.35 * frng.uniform(0.8, 1.2) * (1 if lod == 0 else 1.4)
            k.card(q, r, u, s, s, (0, 3), cols=colf, nrms=nf)
        # hanging moss strands under the clump
        for i in range(2 if lod == 0 else 1):
            a = frng.uniform(0, math.pi)
            r = Vector((math.cos(a), math.sin(a), 0))
            s = frng.uniform(1.0, 1.6)
            k.card(c + Vector((frng.uniform(-0.4, 0.4), frng.uniform(-0.4, 0.4), -0.25)), r, -UP, s * 0.45, s * 0.8,
                   (3, 2), base=True, cols=lambda q_, t: (clamp(0.5 + 0.5 * t), ph, 0.7, 1.0),
                   nrms=lambda q_: UP)
    return H


# ============================================================================ bushes
def bush(k, lod, P):
    rng = random.Random(P["seed"])
    R = P["r"]
    H = P["h"]
    phase0 = rng.random()
    clumps = []
    for i in range(P["n"]):
        a = i / P["n"] * math.tau + rng.uniform(-0.4, 0.4)
        rr = R * rng.uniform(0.25, 0.6)
        c = Vector((math.cos(a) * rr, math.sin(a) * rr, H * rng.uniform(0.35, 0.6)))
        clumps.append((c, R * rng.uniform(0.45, 0.6)))
    clumps.append((Vector((0, 0, H * 0.65)), R * 0.55))
    if lod == 0:
        for c, rc in clumps[:4]:
            k.tube([Vector((0, 0, -0.05)), c * 0.5, c], [0.04, 0.03, 0.012], "RG_Bark", segs=3, cap_start=False,
                   cap_end=False, bark=0, col_fn=bark_col(H, phase0, 0.6, 0.3), tip=True)
    cc = Vector((0, 0, H * 0.5))
    cr = Vector((R, R, H * 0.55))
    frng = random.Random(P["seed"] + 1)
    for c, rc in clumps:
        ph = frng.random()
        colf = leaf_col(cc, cr, H, ph, ao_lo=0.48, sway_base=0.5)
        nf = canopy_nrm(c, rc, cc, cr, up=0.3)
        for i in range(P["cards"] if lod == 0 else max(3, P["cards"] // 3)):
            d = rand_unit(frng, -0.2, 1.0)
            p = c + Vector((d.x, d.y, d.z * 0.8)) * rc * frng.uniform(0.55, 1.0)
            p.z = max(p.z, P["card"] * 0.35)
            n = (d + rand_unit(frng) * 0.45).normalized()
            r, u = perp_pair(n, frng)
            s = P["card"] * frng.uniform(0.8, 1.2) * (1 if lod == 0 else 1.35)
            k.card(p, r, u, s, s, frng.choice(P["cells"]), cols=colf, nrms=nf)
    return H


BUSHES = {
    "bush_round": dict(seed=71, r=0.85, h=1.25, n=6, cards=20, card=0.85, cells=[(1, 2), (1, 2), (0, 1)]),
    "bush_hazel": dict(seed=73, r=1.2, h=1.9, n=7, cards=20, card=1.05, cells=[(0, 1), (0, 2)]),
    "bush_berry": dict(seed=79, r=0.75, h=1.0, n=6, cards=20, card=0.8, cells=[(1, 3), (1, 3), (1, 2)]),
    "bush_dark": dict(seed=83, r=0.9, h=1.2, n=6, cards=20, card=0.9, cells=[(0, 3)]),
}


# ============================================================================ ground plants
def ground_clump(k, lod, P):
    """Radial bent cards from the ground. COLOR_0.R = 0 at the ground -> 1 at the tip."""
    rng = random.Random(P["seed"])
    n = P["n"] if lod == 0 else max(2, P["n"] // 3)
    segs = P.get("segs", 2) if lod == 0 else 1
    for i in range(n):
        a = i / n * math.pi * (2 if P.get("radial") else 1) + rng.uniform(-0.3, 0.3)
        ph = rng.random()
        h = P["h"] * rng.uniform(0.75, 1.15)
        w = P["w"] * rng.uniform(0.85, 1.15)
        cell = rng.choice(P["cells"])
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * P.get("spread", 0.08)
        if P.get("radial"):   # fronds: arch out from the centre
            out = Vector((math.cos(a), math.sin(a), 0))
            u = (out * P.get("out", 0.55) + UP).normalized()
            r = Vector((-out.y, out.x, 0))
            bend = h * P.get("arch", 0.35)
            fwd = r.cross(u)
            sgn = 1 if fwd.dot(out) > 0 else -1
            k.card(off, r, u, w, h, cell, base=True, segs=segs + (1 if lod == 0 else 0), bend=bend * sgn,
                   cols=lambda p, t, ph=ph: (t, ph, 0.5 + 0.5 * t, 1.0),
                   nrms=lambda p: (Vector((p.x, p.y, 0)) * 0.6 + UP).normalized())
        else:
            r = Vector((math.cos(a), math.sin(a), 0))
            u = (UP + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * 0.15).normalized()
            k.card(off, r, u, w, h, cell, base=True, segs=segs, bend=rng.uniform(-0.12, 0.12) * h,
                   cols=lambda p, t, ph=ph: (t, ph, 0.5 + 0.5 * t, 1.0),
                   nrms=lambda p: (Vector((p.x, p.y, 0)) * 0.35 + UP).normalized())
    return P["h"]


GROUND = {
    "grass_a": dict(seed=91, n=10, h=0.55, w=0.7, cells=[(2, 0)], spread=0.12),
    "grass_tall": dict(seed=93, n=10, h=0.95, w=0.85, cells=[(2, 1), (2, 0)], spread=0.15),
    "flowers_warm": dict(seed=95, n=9, h=0.55, w=0.65, cells=[(2, 2), (2, 2), (2, 0)], spread=0.15),
    "flowers_cool": dict(seed=97, n=9, h=0.55, w=0.65, cells=[(2, 3), (2, 3), (2, 0)], spread=0.15),
    "fern_a": dict(seed=101, n=9, h=0.95, w=0.5, cells=[(3, 0)], radial=True, out=0.9, arch=0.3, segs=2,
                   spread=0.03),
    "fern_b": dict(seed=103, n=7, h=0.65, w=0.42, cells=[(3, 0)], radial=True, out=0.6, arch=0.25, segs=2,
                   spread=0.03),
}


# ============================================================================ rocks, stumps, logs
def rock(k, lod, center, size, seed, cuts=9, moss=0.55, rot=0.0):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=(4 if max(size) > 1.1 else 3) if lod == 0 else 2, radius=1.0)
    planes = []
    for i in range(cuts):
        n = rand_unit(rng, -0.35, 0.95)
        planes.append((n, rng.uniform(0.55, 0.85)))
    off = rng.uniform(0, 50)
    sx, sy, sz = size
    for v in bm.verts:
        p = v.co.copy()
        for n, d in planes:
            e = p.dot(n) - d
            if e > 0:
                p -= n * e
        p += p.normalized() * noise.noise(p * 1.8 + Vector((off, 0, 0))) * 0.06
        p = Vector((p.x * sx, p.y * sy, p.z * sz))
        c, s_ = math.cos(rot), math.sin(rot)
        v.co = Vector((p.x * c - p.y * s_, p.x * s_ + p.y * c, p.z))
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= zmin + sz * 0.18
        v.co += Vector(center)
    bm.normal_update()
    vn = {v: v.normal.copy() for v in bm.verts}
    ph = rng.random()
    top = max(v.co.z for v in bm.verts)
    for f in bm.faces:
        fn = f.normal
        pts = [l.vert.co.copy() for l in f.loops]
        nr = [(vn[l.vert] * 0.55 + fn * 0.45).normalized() for l in f.loops]
        mz = sum(p.z for p in pts) / len(pts)
        mossy = moss and fn.z > moss + noise.noise(f.calc_center_median() * 1.5) * 0.25 and mz > 0.1
        mat = "RG_Moss" if mossy else "RG_Rock"
        s = K.MATS[mat]["scale"]
        ax = max(range(3), key=lambda i: abs(fn[i]))
        U, V = [(1, 2), (0, 2), (0, 1)][ax]
        uv = [(p[U] / s + seed * 0.37, p[V] / s + seed * 0.11) for p in pts]
        cols = [(0.0, ph, clamp(0.5 + 0.5 * sstep(-0.05, max(0.3, top * 0.6), p.z)) * (0.9 + 0.1 * n.z), 1.0)
                for p, n in zip(pts, nr)]
        k.face(pts, uv, cols, nr, mat)
    bm.free()


def rock_asset(specs):
    def f(k, lod, P=None):
        for c, s, seed, kw in specs:
            rock(k, lod, c, s, seed, **kw)
        return max(c[2] + s[2] for c, s, _, _ in specs)
    return f


def moss_blob(k, lod, c, r, sq=0.45, seed=0):
    rng = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r, v.co.y * r, max(v.co.z, -0.2) * r * sq)) + Vector(c)
    bm.normal_update()
    ph = rng.random()
    for f in bm.faces:
        pts = [l.vert.co.copy() for l in f.loops]
        nr = [(l.vert.normal * 0.6 + UP * 0.4).normalized() for l in f.loops]
        uv = [(p.x / 1.4, p.y / 1.4) for p in pts]
        k.face(pts, uv, [(0.0, ph, 0.9, 1.0)] * len(pts), nr, "RG_Moss")
    bm.free()


def moss_shell(k, pts, radii, arc=(-1.2, 1.2), prob=0.8, seed=0, lift=1.05, steps=5):
    """Moss draped over the top of a lying cylinder: per axis segment a patch of the surface
    between angles `arc` (0 = straight up) with ragged ends."""
    rng = random.Random(seed)
    ph = rng.random()
    n = len(pts)
    for i in range(n - 1):
        if rng.random() > prob:
            continue
        a0, a1 = arc[0] * rng.uniform(0.6, 1.0), arc[1] * rng.uniform(0.6, 1.0)
        t = (pts[i + 1] - pts[i]).normalized()
        side = t.cross(UP)
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        up2 = side.cross(t).normalized()
        if up2.z < 0:
            up2 = -up2
        s0, s1 = rng.uniform(0.0, 0.25), rng.uniform(0.75, 1.0)
        ring = []
        for q in (s0, s1):
            c = pts[i].lerp(pts[i + 1], q)
            r = (radii[i] + (radii[i + 1] - radii[i]) * q) * lift
            ring.append([(c + (side * math.sin(a) + up2 * math.cos(a)) * r,
                          (side * math.sin(a) + up2 * math.cos(a)))
                         for a in [a0 + (a1 - a0) * j / (steps - 1) for j in range(steps)]])
        for j in range(steps - 1):
            q = [ring[0][j][0], ring[0][j + 1][0], ring[1][j + 1][0], ring[1][j][0]]
            nr = [ring[0][j][1], ring[0][j + 1][1], ring[1][j + 1][1], ring[1][j][1]]
            uv = [(p.x / 1.4 + p.z / 1.4, p.y / 1.4) for p in q]
            if newell_dot(q, nr) < 0:
                q, nr, uv = q[::-1], nr[::-1], uv[::-1]
            k.face(q, uv, [(0.0, ph, 0.9, 1.0)] * 4, nr, "RG_Moss")


def newell_dot(q, nr):
    return K.newell(q).dot(sum(nr, Vector()))


def stump(k, lod, P):
    rng = random.Random(P["seed"])
    r = P["r"]
    h = P["h"]
    segs = 10 if lod == 0 else 7
    col = lambda p, n, t: (0.0, 0.3, clamp(0.55 + 0.45 * sstep(-0.1, h, p.z)), 1.0)
    pts = [Vector((0, 0, -0.15)), Vector((0, 0, 0.08)), Vector((0, 0, h * 0.5)), Vector((0.02, 0, h))]
    rad = [r * 1.55, r * 1.2, r * 1.02, r]
    if P.get("jagged"):
        k.tube(pts, rad, "RG_Bark", segs=segs, cap_start=False, cap_end=False, bark=P.get("bark", 0),
               col_fn=col, noise_amt=0.1)
        # jagged broken top: ring of spikes, pale inner wood
        ring = []
        for i in range(segs):
            a = i / segs * math.tau
            ring.append(Vector((math.cos(a) * r * 0.97 + 0.02, math.sin(a) * r * 0.97,
                                h + (rng.uniform(0.25, 0.6) if i in (1, 2, 6) else rng.uniform(0.0, 0.12)))))
        c = Vector((0.02, 0, h + 0.05))
        for i in range(segs):
            j = (i + 1) % segs
            b0 = Vector((math.cos(i / segs * math.tau) * r + 0.02, math.sin(i / segs * math.tau) * r, h))
            b1 = Vector((math.cos(j / segs * math.tau) * r + 0.02, math.sin(j / segs * math.tau) * r, h))
            u0, u1 = i / segs * 0.25, (i + 1) / segs * 0.25
            k.face([b0, b1, ring[j], ring[i]], [(u0, 0.3), (u1, 0.3), (u1, 0.5), (u0, 0.5)],
                   [(0, 0.3, 0.9, 1)] * 4, None, "RG_Bark")
            k.face([ring[i], ring[j], c], [(0.875 + 0.1 * math.cos(i / segs * math.tau), 0.875 + 0.1 * math.sin(i / segs * math.tau)),
                                           (0.875 + 0.1 * math.cos(j / segs * math.tau), 0.875 + 0.1 * math.sin(j / segs * math.tau)),
                                           (0.875, 0.875)], [(0, 0.3, 0.8, 1)] * 3, None, "RG_Bark")
    else:
        k.tube(pts, rad, "RG_Bark", segs=segs, cap_start=False, cap_end=True, bark=P.get("bark", 0), col_fn=col,
               noise_amt=0.08)
    # roots
    for i in range(P.get("roots", 4)):
        a = i / P.get("roots", 4) * math.tau + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(a), math.sin(a), 0))
        rp = [d * r * 0.7 + UP * 0.25, d * r * 1.35 + UP * 0.05, d * r * 2.0 - UP * 0.08]
        k.tube(rp, [r * 0.32, r * 0.2, r * 0.08], "RG_Bark", segs=5 if lod == 0 else 4, cap_start=False,
               cap_end=False, bark=P.get("bark", 0), col_fn=col, tip=True)
    if P.get("moss", True):
        # moss skirt around the foot on one side
        segs_m = 7 if lod == 0 else 4
        a0 = rng.uniform(0, math.tau)
        ph = rng.random()
        tops = [h * rng.uniform(0.25, 0.6) for i in range(segs_m + 1)]
        for i in range(segs_m):
            aa = a0 + i / segs_m * 3.4
            ab = a0 + (i + 1) / segs_m * 3.4
            q = [Vector((math.cos(aa) * r * 1.3, math.sin(aa) * r * 1.3, -0.02)),
                 Vector((math.cos(ab) * r * 1.3, math.sin(ab) * r * 1.3, -0.02)),
                 Vector((math.cos(ab) * r * 1.07, math.sin(ab) * r * 1.07, tops[i + 1])),
                 Vector((math.cos(aa) * r * 1.07, math.sin(aa) * r * 1.07, tops[i]))]
            nr = [Vector((math.cos(a_), math.sin(a_), 0.5)).normalized() for a_ in (aa, ab, ab, aa)]
            uv = [(p.x / 1.4 + p.y / 1.4, p.z / 1.4) for p in q]
            if newell_dot(q, nr) < 0:
                q, nr, uv = q[::-1], nr[::-1], uv[::-1]
            k.face(q, uv, [(0.0, ph, 0.85, 1.0)] * 4, nr, "RG_Moss")
    return h


def log(k, lod, P):
    rng = random.Random(P["seed"])
    L, r = P["len"], P["r"]
    segs = 9 if lod == 0 else 6
    n = 6 if lod == 0 else 3
    pts = [Vector((-L / 2 + L * i / (n - 1), math.sin(i * 0.9) * 0.08, r * 0.82 + math.sin(i * 1.3) * 0.03)) for i in range(n)]
    rad = [r * (1.0 - 0.18 * i / (n - 1)) for i in range(n)]
    col = lambda p, n_, t: (0.0, 0.4, clamp(0.5 + 0.5 * sstep(0.0, r * 1.6, p.z)), 1.0)
    k.tube(pts, rad, "RG_Bark", segs=segs, bark=P.get("bark", 0), col_fn=col, noise_amt=0.08, vscale=2.2)
    # moss draped over the top
    moss_shell(k, pts, rad, arc=(-1.3, 1.1), prob=0.85 if lod == 0 else 1.0, seed=P["seed"], lift=1.1,
               steps=5 if lod == 0 else 3)
    for i in range(P.get("stubs", 0)):
        t = rng.uniform(0.25, 0.8)
        idx = int(t * (n - 1))
        base = pts[idx]
        d = Vector((rng.uniform(-0.3, 0.3), rng.choice([-1, 1]), rng.uniform(0.2, 0.9))).normalized()
        k.tube([base, base + d * (r + 0.35), base + d * (r + 0.7)], [r * 0.35, r * 0.25, r * 0.18], "RG_Bark",
               segs=5 if lod == 0 else 4, cap_start=False, cap_end=True, bark=P.get("bark", 0), col_fn=col)
    return r * 2


# ============================================================================ registry
def reg():
    A = {}
    for n, P in TREES.items():
        A[n] = ("tree", lambda k, lod, P=P: broadleaf(k, lod, P))
    for n, P in PINES.items():
        A[n] = ("tree", lambda k, lod, P=P: spruce(k, lod, P))
    A["pine_scots"] = ("tree", lambda k, lod: scots_pine(k, lod, dict(seed=131, trunk_h=7.5, r0=0.24)))
    A["dead_snag"] = ("tree", lambda k, lod: dead_tree(k, lod, dict(seed=141, trunk_h=5.0, r0=0.42, limbs=5,
                                                                   limb_len=2.8, depth=2, twigs=1, ao=0.8,
                                                                   twig_scale=0.75))[0])
    A["dark_oak"] = ("tree", lambda k, lod: dark_tree(k, lod, dict(seed=151, trunk_h=3.4, r0=0.36, limbs=5,
                                                                  limb_len=3.2, cards=14)))
    for n, P in BUSHES.items():
        A[n] = ("bush", lambda k, lod, P=P: bush(k, lod, P))
    for n, P in GROUND.items():
        A[n] = ("ground", lambda k, lod, P=P: ground_clump(k, lod, P))
    A["boulder_large"] = ("rock", rock_asset([((0, 0, 0), (1.3, 1.05, 1.0), 201, {})]))
    A["rock_medium"] = ("rock", rock_asset([((0, 0, 0), (0.7, 0.55, 0.5), 203, dict(cuts=8))]))
    A["rock_slab"] = ("rock", rock_asset([((0, 0, 0), (1.0, 0.8, 0.42), 207, dict(cuts=7, moss=0.82))]))
    A["rock_cluster"] = ("rock", rock_asset([((0, 0, 0), (0.9, 0.75, 0.75), 211, {}),
                                             ((0.95, 0.45, 0), (0.5, 0.45, 0.42), 213, {}),
                                             ((-0.6, 0.75, 0), (0.42, 0.36, 0.3), 217, dict(moss=0.4))]))
    A["stump_mossy"] = ("prop", lambda k, lod: stump(k, lod, dict(seed=221, r=0.36, h=0.55)))
    A["stump_broken"] = ("prop", lambda k, lod: stump(k, lod, dict(seed=223, r=0.3, h=0.9, jagged=True, bark=0,
                                                                  moss=True)))
    A["log_mossy"] = ("prop", lambda k, lod: log(k, lod, dict(seed=231, len=4.2, r=0.32)))
    A["log_branchy"] = ("prop", lambda k, lod: log(k, lod, dict(seed=233, len=3.2, r=0.26, stubs=2, bark=0)))
    return A


ASSETS = reg()
BUDGET = {"tree": (3000, 800), "bush": (1200, 400), "ground": (150, 40), "rock": (1500, 400), "prop": (1500, 500)}


def build(name, lod):
    kind, fn = ASSETS[name]
    k = RB(name + ("_lod1" if lod else ""), seed=sum(map(ord, name)))
    fn(k, lod)
    return k


def load_report():
    if os.path.exists(REPORT):
        with open(REPORT) as f:
            return json.load(f)
    return {}


def save_report(rep):
    os.makedirs(OUT, exist_ok=True)
    with open(REPORT, "w") as f:
        json.dump(rep, f, indent=1, sort_keys=True)


def make_asset(name, thumbs=True):
    K.reset()
    k0 = build(name, 0)
    k1 = build(name, 1)
    t0, t1 = k0.tris(), k1.tris()
    (x0, y0, z0), (x1, y1, z1) = k0.bounds()
    ob1 = k1.build()
    K.export_glb(ob1, os.path.join(OUT, name + "_lod1.glb"))
    ob0 = k0.build()
    K.export_glb(ob0, os.path.join(OUT, name + ".glb"))
    kind = ASSETS[name][0]
    b0, b1 = BUDGET[kind]
    info = dict(kind=kind, tris0=t0, tris1=t1, size=[round(x1 - x0, 2), round(y1 - y0, 2), round(z1, 2)],
                mats=list(k0.mnames), ok=t0 <= b0 and t1 <= b1)
    print(f"ASSET {name}: LOD0 {t0} (<= {b0})  LOD1 {t1} (<= {b1})  size {info['size']}  mats {k0.mnames}",
          flush=True)
    if thumbs:
        ob1.hide_render = True
        cam = (1.0, -1.5, 0.35) if kind in ("tree",) else (1.0, -1.45, 0.75)
        K.render_thumb([ob0], os.path.join(K.THUMBS, f"nature_{name}.png"), cam_dir=cam,
                       fit=1.0 if kind != "ground" else 0.8)
    return info


# ============================================================================ impostors
TREE_NAMES = [n for n, (kind, _) in ASSETS.items() if kind == "tree"]


def make_impostors():
    import numpy as np
    cells = {}
    S = 256
    atlas = np.zeros((1024, 1024, 4), np.float32)
    tmp = os.path.join(K.THUMBS, "_imp")
    os.makedirs(tmp, exist_ok=True)
    for i, name in enumerate(TREE_NAMES):
        K.reset()
        k = build(name, 0)
        ob = k.build()
        (x0, y0, z0), (x1, y1, z1) = k.bounds()
        w = max(x1 - x0, y1 - y0, z1) * 1.04
        cx = (x0 + x1) / 2
        K.camera((cx, -60, w / 2), (cx, 0, w / 2), ortho=w)
        K.world_sky(strength=1.1, sun_rot=(40, 0, -25))
        K.preview_patch()
        png = os.path.join(tmp, name + ".png")
        K.render_setup(png, (S, S), 32, transparent=True)
        bpy.ops.render.render(write_still=True)
        a = K.load_png(png)
        r, c = divmod(i, 4)
        atlas[r * S:(r + 1) * S, c * S:(c + 1) * S] = a
        cells[name] = (r, c, w, cx)
    # un-premultiply-safe bleed of colour into transparent texels
    al = atlas[..., 3:4]
    mean = (atlas[..., :3] * al).sum(axis=(0, 1)) / max(1e-6, al.sum())
    atlas[..., :3] = np.where(al > 0.02, atlas[..., :3], mean[None, None, :])
    import region_paint as RP
    RP.save_rgba(os.path.join(K.TEX, "tree_impostors.png"), atlas[..., :3], atlas[..., 3])
    # lod2 meshes: two crossed cards
    for name, (r, c, w, cx) in cells.items():
        K.reset()
        k = RB(name + "_lod2")
        ins = 1 / 1024
        u0, u1 = c / 4 + ins, (c + 1) / 4 - ins
        v0, v1 = 1 - (r + 1) / 4 + ins, 1 - r / 4 - ins
        for a in (0.0, math.pi / 2):
            d = Vector((math.cos(a), math.sin(a), 0))
            p0 = d * (-w / 2 + (-cx if a == 0 else 0))
            p1 = d * (w / 2 + (-cx if a == 0 else 0))
            pts = [p0, p1, p1 + UP * w, p0 + UP * w]
            k.face(pts, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], [(1, 1, 1, 1)] * 4, [UP * 0.6 + d.cross(UP) * -0.8] * 4,
                   "RG_Impostor")
        ob = k.build()
        ob.data.color_attributes.remove(ob.data.color_attributes["Col"])
        K.export_glb(ob, os.path.join(OUT, name + "_lod2.glb"), vcol=False)
    print("impostors", cells)


# ============================================================================ sheet
ORDER = list(ASSETS)


def make_sheet():
    rep = load_report()
    entries = []
    for n in ORDER:
        if n not in rep:
            continue
        i = rep[n]
        s = i["size"]
        entries.append((os.path.join(K.THUMBS, f"nature_{n}.png"), n,
                        f"LOD0 {i['tris0']}  LOD1 {i['tris1']}  {s[0]:.1f}X{s[1]:.1f}X{s[2]:.1f}M"))
    K.sheet(entries, os.path.join(K.PREV, "region_nature_sheet.png"),
            "RISING ASHES - REGION 1 NATURE  (TRIS LOD0 / LOD1, 4 SHARED TEXTURES)", cols=6)


# ============================================================================ forest scene
def make_scene(out=None, quick=False):
    import numpy as np
    K.reset()
    rng = random.Random(7)
    protos = {}
    for n in ASSETS:
        k = build(n, 0)
        ob = k.build(n + "_proto")
        ob.hide_render = True
        ob.location = (0, 0, -500)
        protos[n] = ob
    house_path = os.path.join(K.ROOT, "kingdom", "assets", "incoming", "ai3d", "meshy", "house_peasant_b_lod0.glb")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=house_path)
    house = [o for o in bpy.data.objects if o not in before]
    roots = [o for o in house if o.parent is None]
    for o in roots:
        o.location = (0.0, 2.0, 0.0)
        o.rotation_euler = (0, 0, math.radians(-18))
    bpy.context.view_layer.update()
    hb = []
    for o in house:
        if o.type == "MESH":
            hb += [o.matrix_world @ Vector(c) for c in o.bound_box]
    hz = max(p.z for p in hb) - min(p.z for p in hb)
    sc = 8.0 / hz      # the game scales house_peasant_b to 8.0 m (scripts/world/assets.gd)
    for o in roots:
        o.scale = tuple(v * sc for v in o.scale)
    bpy.context.view_layer.update()
    zmin = min((o.matrix_world @ Vector(c)).z for o in house if o.type == "MESH" for c in o.bound_box)
    for o in roots:
        o.location.z -= zmin
    print("house height", hz, "scaled x", sc)

    placed = []

    def put(n, x, y, rot=None, s=1.0):
        o = protos[n].copy()
        o.location = (x, y, 0)
        o.rotation_euler = (0, 0, rot if rot is not None else rng.uniform(0, math.tau))
        o.scale = (s, s, s)
        o.hide_render = False
        bpy.context.scene.collection.objects.link(o)
        placed.append((n, x, y))
        return o

    def free(x, y, r):
        if -5.5 < x < 5.5 and -2.8 < y < 7.0:     # house footprint + yard
            return False
        if abs(x - (y * 0.25 - 3.0)) < 1.2 and y < 0:   # path
            return False
        return all((x - px) ** 2 + (y - py) ** 2 > r * r for n, px, py in placed if n in ASSETS and ASSETS[n][0] == "tree")
    # background forest ring
    trees_bg = ["oak_a", "beech_a", "spruce_a", "oak_b", "beech_b", "spruce_b", "pine_scots", "oak_a", "beech_a"]
    for i in range(70):
        a = rng.uniform(math.radians(20), math.radians(200))
        d = rng.uniform(12, 34)
        x, y = math.cos(a) * d, math.sin(a) * d + 4
        if free(x, y, 4.2):
            put(rng.choice(trees_bg), x, y, s=rng.uniform(0.85, 1.15))
    # dark corner on the right: dead + dark oak
    put("dark_oak", 13, 9, s=1.0)
    put("dead_snag", 9.5, 15, s=1.0)
    put("dark_oak", 17, 17, s=1.1)
    # foreground feature trees
    put("oak_a", -10.5, 0.5, s=1.05)
    put("beech_b", 9.0, -1.5)
    put("young_oak", -6.5, -4.0)
    put("spruce_b", 11.5, 4.0)
    # bushes near the house and edges
    for n, x, y in [("bush_round", -6.3, 1.0), ("bush_hazel", 6.5, 5.5), ("bush_berry", -4.2, -3.0),
                    ("bush_round", 5.8, -1.8), ("bush_dark", 11.0, 10.5), ("bush_hazel", -9.0, 6.5),
                    ("bush_berry", 7.5, 0.8), ("bush_round", -12.5, -3.5)]:
        put(n, x, y)
    for n, x, y in [("boulder_large", -8.5, -6.0), ("rock_cluster", 7.8, -5.5), ("rock_medium", -3.0, -7.5),
                    ("rock_slab", 3.5, -8.0), ("stump_mossy", 4.5, -4.2), ("log_mossy", -7.0, -9.5),
                    ("stump_broken", 12.0, 6.5), ("log_branchy", 10.5, 12.5), ("rock_medium", 14.5, 11.0)]:
        put(n, x, y)
    for i in range(24):
        x, y = rng.uniform(-14, 16), rng.uniform(-10, 14)
        if free(x, y, 0):
            put(rng.choice(["fern_a", "fern_b"]), x, y)
    ng = 260 if quick else 900
    for i in range(ng):
        x, y = rng.uniform(-16, 18), rng.uniform(-13, 16)
        if not free(x, y, 0):
            continue
        r = rng.random()
        n = "grass_a" if r < 0.55 else "grass_tall" if r < 0.75 else "flowers_warm" if r < 0.88 else "flowers_cool"
        put(n, x, y, s=rng.uniform(0.8, 1.25))
    # ground + dirt path
    K.ground_plane(200, color=(0.38, 0.52, 0.22))
    path = RB("path")
    pts = []
    for i in range(12):
        y = -14 + i * 1.5
        x = y * 0.25 - 3.0 + math.sin(i * 0.7) * 0.4
        pts.append((x, y))
    for i in range(len(pts) - 1):
        (xa, ya), (xb, yb) = pts[i], pts[i + 1]
        wa, wb = 1.1, 1.1
        path.poly([(xa - wa, ya, 0.02), (xb - wb, yb, 0.02), (xb + wb, yb, 0.02), (xa + wa, ya, 0.02)], "RG_Soil",
                  tint=(0.95, 0.88, 0.78))
    pob = path.build()
    pob.data.materials[0] = K.ground_mat((0.74, 0.62, 0.44), scale=1.2)   # preview-only sandy track
    cam_loc = Vector((5.5, -24.0, 9.0))
    K.camera(cam_loc, (0.5, 3.0, 2.2), lens=30)
    K.world_sky(strength=1.0, sun_rot=(55, 0, -52), sun_energy=4.2)
    K.preview_patch()
    out = out or os.path.join(K.PREV, "region_forest_scene.png")
    K.render_setup(out, (1600, 900) if not quick else (800, 450), 96 if not quick else 24)
    bpy.ops.render.render(write_still=True)
    print("scene", out)


# ============================================================================ main
# ============================================================================ Godot import files
SCENE_PARAMS = """nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=false
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=false
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
"""
TEX_PARAMS = """compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""
RES = "res://assets/generated/region"


def write_godot_imports():
    """.glb.import files that swap the nature materials for the wind ShaderMaterials (Godot keeps
    these [params] and fills in uid/paths on first import), plus VRAM-compressed texture imports."""
    over = {"RG_Bark": "rg_bark", "RG_Rock": "rg_rock", "RG_Moss": "rg_moss"}
    for f in sorted(os.listdir(OUT)):
        if not f.endswith(".glb"):
            continue
        name = f[:-4].replace("_lod1", "").replace("_lod2", "")
        if f.endswith("_lod2.glb"):
            mats = {}
        else:
            ground = name in ASSETS and ASSETS[name][0] == "ground"
            mats = dict(over, RG_Foliage="rg_foliage_ground" if ground else "rg_foliage")
        sub = ",\n".join(f'"{m}": {{\n"use_external/enabled": true,\n"use_external/fallback_path": "{RES}/nature/{t}.tres",\n'
                         f'"use_external/path": "{RES}/nature/{t}.tres"\n}}' for m, t in mats.items())
        txt = (f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\n\n'
               f'source_file="{RES}/nature/{f}"\n\n[params]\n\n{SCENE_PARAMS}'
               f'_subresources={{\n"materials": {{\n{sub}\n}}\n}}\n' if mats else
               f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\n\n'
               f'source_file="{RES}/nature/{f}"\n\n[params]\n\n{SCENE_PARAMS}_subresources={{}}\n')
        txt += "gltf/naming_version=2\ngltf/embedded_image_handling=1\n"
        p = os.path.join(OUT, f + ".import")
        if not os.path.exists(p):          # never clobber a file Godot has already completed
            open(p, "w").write(txt)
    for f in sorted(os.listdir(K.TEX)):
        if f.endswith(".png") and not os.path.exists(os.path.join(K.TEX, f + ".import")):
            open(os.path.join(K.TEX, f + ".import"), "w").write(
                f'[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\n'
                f'source_file="{RES}/textures/{f}"\n\n[params]\n\n{TEX_PARAMS}')
    print("godot import files written")


def main():
    args = K.argv()
    if "--textures" in args:
        import region_paint as RP
        RP.make_all(force=True)
    names = [a for a in args if not a.startswith("--")]
    if not names and not any(a in args for a in ("--sheet", "--scene", "--impostors", "--textures", "--godot")):
        names = list(ASSETS)
    if names == ["all"]:
        names = list(ASSETS)
    rep = load_report()
    for n in names:
        rep[n] = make_asset(n, thumbs="--no-thumbs" not in args)
        save_report(rep)
    if "--impostors" in args:
        make_impostors()
    if "--sheet" in args:
        make_sheet()
    if "--scene" in args:
        make_scene(quick="--quick" in args)
    if "--godot" in args:
        write_godot_imports()


main()
