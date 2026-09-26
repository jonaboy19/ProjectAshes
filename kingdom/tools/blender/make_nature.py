"""Builds the procedural temperate-forest nature set (semi-realistic, mobile budgets) as GLB.

Run from the repo root (needs the bpy module, Blender 5.x):
    python3 kingdom/tools/blender/make_nature_textures.py        # once: textures/
    python3 kingdom/tools/blender/make_nature.py [names...] [--no-preview]
Outputs kingdom/assets/generated/nature/<name>.glb and, unless --no-preview,
docs/kingdom/blender_previews/nature/<name>.png (Cycles CPU, 800x600, sky backdrop).

Assets (heights / budgets):   oak_a, oak_b (broadleaf 9-13 m), birch_a (10 m), pine_a (Scots pine
~16 m), pine_b (spruce-like conical conifer ~13 m), sapling (3 m), dead_tree, bush_a, bush_b
(1-1.5 m), grass_clump, grass_clump_tall, flowers_a.   Trees <= ~6k tris, bushes <= 1.5k, grass
60-150 (leaf cards are 2 tris each).

How a tree is made: recursive branching (trunk -> limbs -> branches -> twigs) with `ra_nature.grow`
(noise-bent, tapering, tropism/droop), child tips kept inside a crown envelope so the silhouette
reads as the species, root flare on the trunk, then alpha-cut sprig cards on the outer twigs.
Leaf count is whatever budget the bark leaves over. See ra_nature.py for normals / COLOR_0 rules.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
import ra_nature as rn
from ra_nature import (Vector, UP, GOLDEN, MeshBuilder, grow, child_dir, tube, Canopy, place_cards,
                       anchors_from, card, lerp, smoothstep)

TREE_BUDGET = 6000
BUSH_BUDGET = 1500


# ============================================================================ helpers
def start(seed):
    rn.noise.seed_set(seed)          # mathutils noise is randomly seeded per process otherwise
    return random.Random(seed), rn.standard_materials(), MeshBuilder()


def fit_len(p, d, L, center, radii, margin=1.0):
    """Shrink length L so p + d*L stays inside the ellipsoid (center, radii)."""
    for _ in range(12):
        q = p + d * L
        e = Vector(((q.x - center.x) / radii.x, (q.y - center.y) / radii.y, (q.z - center.z) / radii.z))
        if e.length <= margin or L < 0.2:
            return L
        L *= 0.85
    return L


def spawn(parent, rng, count, t_range, angle, length_fn, r_ratio, level, envelope=None, roll0=None,
          up_bias=0.0, out_bias=0.0, **grow_kw):
    """Spawn `count` children along parent (phyllotactic roll). angle: (min, max) radians from the
    parent tangent. length_fn(t) -> nominal length. Returns the new branches."""
    out = []
    roll = rng.random() * 6.283 if roll0 is None else roll0
    for i in range(count):
        t = lerp(t_range[0], t_range[1], (i + rng.uniform(0.15, 0.85)) / count)
        p, d, r = parent.at(t)
        roll += GOLDEN * 2 + rng.uniform(-0.4, 0.4)
        a = rng.uniform(*angle)
        dd = child_dir(d, a, roll, up_bias=up_bias, out=p, out_bias=out_bias)
        L = length_fn(t) * rng.uniform(0.8, 1.15)
        if envelope:
            L = fit_len(p, dd, L, *envelope)
        if L < 0.15:
            continue
        rc = max(0.008, min(r * r_ratio, r * 0.85))
        b = grow(p - dd * r * 0.3, dd, L + r * 0.3, rc, max(0.006, rc * 0.25), level, rng,
                 seed=rng.random() * 100, **grow_kw)
        parent.children.append(b)
        out.append(b)
    return out


def bark_color_fn(moss=(0.55, 0.62, 0.38), base_dark=0.72, moss_h=1.0):
    def f(p, t):
        k = smoothstep(moss_h, 0.0, p.z)            # 1 at ground
        return (lerp(1.0, moss[0] * base_dark, k), lerp(1.0, moss[1] * base_dark, k),
                lerp(1.0, moss[2] * base_dark, k))
    return f


def mesh_branches(mb, branches, mat, tint, rng, trunk_flare=None, col_fn=None, tile=(1.0, 1.3),
                  side_cap=None):
    for b in branches:
        fl = trunk_flare if b.level == 0 else None
        s = None
        if side_cap:
            s = min(rn.sides_for(b.radii[0]), side_cap(b))
        tube(mb, b, mat, tint(b) if callable(tint) else tint, rng, tile_u=tile[0], tile_v=tile[1],
             flare=fl, sides=s, col_fn=col_fn)


def finish(name, mb, mats, preview, wind=False, cam=(1.0, -1.7, 0.28), fit=1.0):
    ob = mb.build(name, mats)
    out = os.path.join(rn.NATURE, name + ".glb")
    rn.export_glb(ob, out, wind_vcol=wind)
    bb = [Vector(c) for c in ob.bound_box]
    h = max(v.z for v in bb)
    w = max(max(v.x for v in bb) - min(v.x for v in bb), max(v.y for v in bb) - min(v.y for v in bb))
    parts = ", ".join(f"{m}={mb.tris_of(m)}" for m in mb.mat_names)
    print(f"wrote {out}  triangles={mb.tris()} ({parts})  height={h:.2f}m  width={w:.2f}m")
    if preview:
        rn.render_asset(ob, os.path.join(rn.PREVIEWS, name + ".png"), cam_dir=cam, fit=fit)
    return ob


def leaf_budget(mb, budget, reserve=40):
    return max(0, (budget - mb.tris() - reserve) // 2)


# ============================================================================ broadleaf
def build_oak(name, seed, H, crown_w, preview, spread=1.0, crown_base=0.22):
    rng, mats, mb = start(seed)
    Rc = crown_w / 2
    zb, zt = H * crown_base, H * 0.98
    env = (Vector((0, 0, (zb + zt) / 2)), Vector((Rc, Rc, (zt - zb) / 2)))
    lean = Vector((rng.uniform(-0.07, 0.07), rng.uniform(-0.07, 0.07), 1))
    trunk = grow((0, 0, -0.25), lean, H * 0.64, 0.42 * H / 11, 0.1, 0, rng, seg_len=0.8, wobble=0.12,
                 freq=0.35, first=[0.12, 0.3, 0.55, 0.9], taper_pow=1.15, seed=seed)
    split_t = rng.uniform(0.3, 0.36)
    limbs = spawn(trunk, rng, rng.randint(5, 6), (split_t, 0.78), (0.6 * spread, 1.15 * spread),
                  lambda t: Rc * 1.25, 0.66, 1, envelope=env, seg_len=0.85, wobble=0.34, tropism=0.25,
                  freq=0.45, taper_pow=1.2)
    lvl2 = []
    for par in [trunk] + limbs:
        n = 4 if par is trunk else max(3, int(par.length / 0.75))
        t0 = 0.8 if par is trunk else 0.2
        lvl2 += spawn(par, rng, n, (t0, 0.97), (0.6, 1.3), lambda t: 4.0 * H / 11,
                      0.5, 2, envelope=env, seg_len=1.0, wobble=0.38, tropism=0.0, freq=0.8,
                      out_bias=0.55, gravity_end=0.2)
    # twigs are NOT meshed: they only spread the leaf cards around each branch (the sprig
    # texture carries the visible twig)
    twigs = []
    for par in lvl2:
        n = max(2, int(par.length / 0.45))
        twigs += spawn(par, rng, n, (0.3, 0.98), (0.7, 1.4), lambda t: 1.1, 0.6, 3,
                       envelope=(env[0], env[1] * 1.06), seg_len=1.2, wobble=0.4, out_bias=0.3)
    tint = lambda b: (0.78, 0.72, 0.62) if b.level < 2 else (0.70, 0.64, 0.56)
    mesh_branches(mb, [trunk] + limbs + lvl2, "Bark_Oak", tint, rng, trunk_flare=(0.55, 0.45, 5),
                  col_fn=bark_color_fn(), side_cap=lambda b: {1: 6, 2: 4}.get(b.level, 99))
    anchors = anchors_from(lvl2, t0=0.45, spacing=0.6) + anchors_from(twigs, t0=0.25, spacing=0.45)
    canopy = Canopy([p for p, d in anchors], up_blend=0.25, ao=(0.58, 1.0))
    n = leaf_budget(mb, TREE_BUDGET)
    place_cards(mb, "Leaves_Broadleaf", anchors, canopy, rng, n, (1.15 * H / 11, 1.65 * H / 11), [0, 1],
                (1.02, 1.02, 0.9), var=0.07)
    return finish(name, mb, mats, preview)


def build_birch(name, seed, H, preview):
    rng, mats, mb = start(seed)
    Rc = 2.8
    env = (Vector((0, 0, H * 0.6)), Vector((Rc, Rc, H * 0.42)))
    trunk = grow((0, 0, -0.2), Vector((rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1), 1)), H + 0.2,
                 0.19, 0.02, 0, rng, seg_len=0.8, wobble=0.07, freq=0.3, first=[0.12, 0.3, 0.6],
                 taper_pow=1.1, seed=seed)
    branches = [trunk]
    lvl1 = spawn(trunk, rng, 26, (0.25, 0.95), (0.6, 1.05), lambda t: lerp(3.4, 1.4, t), 0.5, 1,
                 envelope=env, seg_len=0.7, wobble=0.25, tropism=0.12, freq=0.7, gravity_end=0.3)
    branches += lvl1
    twigs = []
    for par in lvl1:
        n = max(1, int(par.length / 0.7))
        twigs += spawn(par, rng, n, (0.3, 0.95), (0.5, 1.0), lambda t: 1.2, 0.6, 2,
                       envelope=(env[0], env[1] * 1.1), seg_len=0.6, wobble=0.3, tropism=-0.2,
                       gravity_end=1.0)
    branches += twigs[::3]          # mesh a third of the weeping twigs, the rest only carry leaves

    def tint(b):
        return (1.0, 1.0, 1.0) if b.level == 0 else ((0.75, 0.72, 0.70) if b.level == 1 else (0.38, 0.32, 0.30))

    def col(p, t):     # black fissured base, clean white above
        k = smoothstep(1.3, 0.1, p.z)
        return (lerp(1.0, 0.22, k), lerp(1.0, 0.21, k), lerp(1.0, 0.2, k))
    mesh_branches(mb, branches, "Bark_Birch", tint, rng, trunk_flare=(0.35, 0.3, 4), col_fn=col,
                  tile=(1.0, 1.0), side_cap=lambda b: 3 if b.level == 2 else 99)
    anchors = anchors_from(lvl1, t0=0.5, spacing=0.6) + anchors_from(twigs, t0=0.2, spacing=0.3)
    canopy = Canopy([p for p, d in anchors], up_blend=0.2, ao=(0.6, 1.0))
    n = min(leaf_budget(mb, TREE_BUDGET), 2000)
    place_cards(mb, "Leaves_Broadleaf", anchors, canopy, rng, n, (0.8, 1.15), [2],
                (1.05, 1.05, 0.9), var=0.08, up_follow=0.85, out_push=0.1)
    return finish(name, mb, mats, preview)


def build_sapling(name, seed, preview):
    rng, mats, mb = start(seed)
    H = 3.0
    env = (Vector((0, 0, 1.85)), Vector((1.0, 1.0, 1.25)))
    trunk = grow((0, 0, -0.1), Vector((0.05, 0.02, 1)), H + 0.1, 0.045, 0.008, 0, rng, seg_len=0.45,
                 wobble=0.18, freq=0.8, seed=seed)
    lvl1 = spawn(trunk, rng, 12, (0.22, 0.95), (0.6, 1.1), lambda t: lerp(1.0, 0.45, t), 0.6, 1,
                 envelope=env, seg_len=0.35, wobble=0.3, tropism=0.2)
    twigs = []
    for par in lvl1:
        twigs += spawn(par, rng, 2, (0.4, 0.9), (0.5, 0.9), lambda t: 0.35, 0.6, 2, envelope=env,
                       seg_len=0.4, wobble=0.3)
    mesh_branches(mb, [trunk] + lvl1 + twigs, "Bark_Oak", (0.62, 0.55, 0.48), rng, tile=(0.6, 0.8),
                  side_cap=lambda b: 5 if b.level == 0 else 3)
    anchors = anchors_from(lvl1, t0=0.4, spacing=0.25) + anchors_from(twigs, t0=0.2, spacing=0.2) + \
        anchors_from([trunk], t0=0.45, spacing=0.2)
    canopy = Canopy([p for p, d in anchors], up_blend=0.25, ao=(0.55, 1.0))
    place_cards(mb, "Leaves_Broadleaf", anchors, canopy, rng, 190, (0.45, 0.65), [3, 1],
                (1.0, 1.02, 0.9), var=0.1)
    return finish(name, mb, mats, preview)


def build_dead(name, seed, preview):
    rng, mats, mb = start(seed)
    H = 9.0
    Rc = 3.8
    env = (Vector((0, 0, H * 0.55)), Vector((Rc, Rc, H * 0.47)))
    trunk = grow((0, 0, -0.25), Vector((0.12, 0.05, 1)), H * 0.62, 0.40, 0.09, 0, rng, seg_len=0.6,
                 wobble=0.14, freq=0.4, first=[0.12, 0.3, 0.55, 0.9], taper_pow=1.4, seed=seed, cap=True)
    limbs = spawn(trunk, rng, 5, (0.4, 0.85), (0.55, 1.1), lambda t: Rc * 1.1, 0.62, 1, envelope=env,
                  seg_len=0.55, wobble=0.4, tropism=0.3, freq=0.5)
    for b in limbs:
        if rng.random() < 0.4:            # snapped limb
            k = rng.uniform(0.35, 0.65)
            n = max(2, int(len(b.pts) * k))
            b.__init__(b.pts[:n], b.radii[:n], b.level, cap=True)
    lvl2 = []
    for par in limbs + [trunk]:
        n = max(2, int(par.length / 0.7))
        lvl2 += spawn(par, rng, n, (0.3, 0.95), (0.6, 1.2), lambda t: lerp(2.2, 1.0, t), 0.5, 2,
                      envelope=env, seg_len=0.5, wobble=0.45, tropism=0.15, freq=0.9, out_bias=0.3)
    for b in lvl2:
        if rng.random() < 0.35:
            n = max(2, int(len(b.pts) * rng.uniform(0.3, 0.7)))
            b.__init__(b.pts[:n], b.radii[:n], b.level, cap=True)
    twigs = []
    for par in lvl2:
        if par.cap:
            continue
        twigs += spawn(par, rng, 4, (0.3, 0.95), (0.5, 1.1), lambda t: 0.8, 0.6, 3, envelope=env,
                       seg_len=0.35, wobble=0.55, tropism=0.1)
    stubs = spawn(trunk, rng, 4, (0.1, 0.45), (1.1, 1.4), lambda t: 0.4, 0.3, 2, seg_len=0.3,
                  cap=True, wobble=0.1)
    tint = lambda b: (0.74, 0.68, 0.60) if b.level < 2 else (0.64, 0.58, 0.52)
    mesh_branches(mb, [trunk] + limbs + lvl2 + twigs + stubs, "Bark_Oak", tint, rng,
                  trunk_flare=(0.6, 0.4, 5), col_fn=bark_color_fn(moss=(0.62, 0.66, 0.46), moss_h=1.6))
    return finish(name, mb, mats, preview)


# ============================================================================ conifers
def build_scots_pine(name, seed, H, preview):
    rng, mats, mb = start(seed)
    trunk = grow((0, 0, -0.25), Vector((rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05), 1)), H + 0.25,
                 0.33 * H / 16, 0.035, 0, rng, seg_len=1.0, wobble=0.035, freq=0.25,
                 first=[0.12, 0.3, 0.6], taper_pow=1.25, seed=seed)
    crown0 = 0.6
    Rc = H * 0.27
    lvl1 = []
    z = crown0 * H
    while z < H - 0.6:
        hrel = (z / H - crown0) / (1 - crown0)
        k = rng.randint(2, 4)
        roll = rng.random() * 6.283
        for i in range(k):
            if rng.random() < 0.25:
                continue
            t = z / (H + 0.25) + 0.25 / (H + 0.25)
            p, d, r = trunk.at(t)
            ang = math.radians(lerp(95, 62, hrel) + rng.uniform(-10, 10))
            dd = child_dir(d, ang, roll + i * 6.283 / k + rng.uniform(-0.4, 0.4))
            L = Rc * (0.6 + 0.45 * math.sin(math.pi * min(1, 0.3 + hrel * 0.8))) * rng.uniform(0.6, 1.2)
            b = grow(p, dd, L, max(0.03, r * 0.42), 0.012, 1, rng, seg_len=0.9, wobble=0.28, tropism=0.12,
                     freq=0.6, seed=rng.random() * 100)
            lvl1.append(b)
        z += rng.uniform(0.55, 0.85)
    lvl2 = []
    for par in lvl1:
        n = max(1, int(par.length / 1.0))
        lvl2 += spawn(par, rng, n + 1, (0.35, 0.9), (0.5, 0.9), lambda t: rng.uniform(0.7, 1.3), 0.6, 2,
                      seg_len=0.6, wobble=0.3, tropism=0.25)
    stubs = spawn(trunk, rng, 7, (0.18, crown0 - 0.02), (1.3, 1.6), lambda t: rng.uniform(0.2, 0.55), 0.25, 2,
                  seg_len=0.3, cap=True, wobble=0.1)

    def col(p, t):   # grey-brown fissured lower trunk -> orange "fox" bark above
        k = smoothstep(H * 0.35, H * 0.6, p.z)
        base = smoothstep(0.8, 0.0, p.z)
        return (lerp(0.50, 1.15, k) * lerp(1, 0.7, base), lerp(0.45, 0.62, k) * lerp(1, 0.72, base),
                lerp(0.42, 0.38, k) * lerp(1, 0.6, base))
    tint = lambda b: (1.0, 1.0, 1.0) if b.level == 0 else (0.85, 0.6, 0.42)
    mesh_branches(mb, [trunk] + lvl1 + lvl2[::2] + stubs, "Bark_Pine", tint, rng, trunk_flare=(0.4, 0.35, 5),
                  col_fn=col, tile=(0.9, 1.1), side_cap=lambda b: 4 if b.level == 1 else (3 if b.level == 2 else 99))
    anchors = anchors_from(lvl2, t0=0.55, spacing=0.35) + anchors_from(lvl1, t0=0.6, spacing=0.4) + \
        anchors_from([trunk], t0=0.95, spacing=0.3)
    canopy = Canopy([p for p, d in anchors], up_blend=0.35, ao=(0.45, 1.0))
    n = leaf_budget(mb, TREE_BUDGET)
    place_cards(mb, "Needles_Conifer", anchors, canopy, rng, n, (0.9, 1.35), [0, 1], (1.08, 1.12, 1.0),
                var=0.08, facing_mode="out", up_follow=0.8, out_push=0.35)
    return finish(name, mb, mats, preview)


def build_spruce(name, seed, H, preview):
    rng, mats, mb = start(seed)
    trunk = grow((0, 0, -0.25), Vector((0, 0, 1)), H + 0.25, 0.28 * H / 13, 0.02, 0, rng, seg_len=1.0,
                 wobble=0.03, freq=0.2, first=[0.12, 0.3, 0.6], taper_pow=1.0, seed=seed)
    Rb = H * 0.21
    lvl1 = []
    z = 0.9
    while z < H - 0.35:
        hrel = z / H
        k = rng.randint(4, 5)
        roll = rng.random() * 6.283
        for i in range(k):
            t = (z + 0.25) / (H + 0.25)
            p, d, r = trunk.at(t)
            ang = math.radians(lerp(100, 62, hrel) + rng.uniform(-8, 8))
            dd = child_dir(d, ang, roll + i * 6.283 / k + rng.uniform(-0.3, 0.3))
            L = (Rb * (1 - hrel) ** 0.95 + 0.35) * rng.uniform(0.8, 1.15)
            b = grow(p, dd, L, max(0.02, r * 0.3), 0.01, 1, rng, seg_len=max(0.5, L / 2), wobble=0.12,
                     tropism=0.25, freq=0.5, gravity_end=0.25, seed=rng.random() * 100)
            lvl1.append(b)
        z += rng.uniform(0.42, 0.55)
    mesh_branches(mb, [trunk] + lvl1, "Bark_Pine", lambda b: (0.55, 0.45, 0.40) if b.level == 0 else (0.5, 0.4, 0.34),
                  rng, trunk_flare=(0.45, 0.35, 5), col_fn=bark_color_fn(moss=(0.6, 0.62, 0.45)),
                  tile=(0.9, 1.1), side_cap=lambda b: 3 if b.level == 1 else 8)
    anchors = anchors_from(lvl1, t0=0.15, spacing=0.3) + anchors_from([trunk], t0=0.9, spacing=0.25)
    canopy = Canopy([p for p, d in anchors], up_blend=0.2, axis_mode=True, ao=(0.4, 1.0))
    n = leaf_budget(mb, TREE_BUDGET)
    place_cards(mb, "Needles_Conifer", anchors, canopy, rng, n, (0.9, 1.3), [2, 3], (1.05, 1.12, 1.0),
                var=0.07, facing_mode="flat", up_follow=0.9, out_push=0.25)
    return finish(name, mb, mats, preview)


# ============================================================================ bushes
def build_bush(name, seed, H, W, cells, tint, preview, n_stems=7):
    rng, mats, mb = start(seed)
    env = (Vector((0, 0, H * 0.5)), Vector((W / 2, W / 2, H * 0.55)))
    stems = []
    for i in range(n_stems):
        a = i * GOLDEN * 2 + rng.uniform(-0.3, 0.3)
        tilt = rng.uniform(0.25, 0.7)
        d = Vector((math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt), math.cos(tilt)))
        p = Vector((math.cos(a) * 0.08, math.sin(a) * 0.08, -0.05))
        L = fit_len(p, d, H * rng.uniform(0.9, 1.25), *env)
        stems.append(grow(p, d, L, 0.022, 0.006, 1, rng, seg_len=0.35, wobble=0.3, tropism=-0.05,
                          gravity_end=0.3, seed=rng.random() * 100))
    twigs = []
    for par in stems:
        twigs += spawn(par, rng, 2, (0.35, 0.8), (0.5, 0.9), lambda t: 0.45, 0.6, 2, envelope=env,
                       seg_len=0.5, wobble=0.3)
    mesh_branches(mb, stems + twigs, "Bark_Oak", (0.55, 0.5, 0.45), rng, tile=(0.5, 0.7),
                  side_cap=lambda b: 4 if b.level == 1 else 3)
    anchors = anchors_from(stems, t0=0.3, spacing=0.12) + anchors_from(twigs, t0=0.2, spacing=0.12)
    canopy = Canopy([p for p, d in anchors], up_blend=0.3, ao=(0.45, 1.0))
    n = leaf_budget(mb, BUSH_BUDGET, reserve=10)
    place_cards(mb, "Leaves_Broadleaf", anchors, canopy, rng, n, (0.42, 0.6), cells, tint, var=0.1,
                out_push=0.45)
    return finish(name, mb, mats, preview, cam=(1.0, -1.7, 0.45))


# ============================================================================ grass & flowers
def wind_col(t, phase):
    return (t, phase, 0.5, 1.0)


def build_grass(name, seed, tall, preview):
    rng, mats, mb = start(seed)
    n = 20 if tall else 16
    segs = 3 if tall else 2
    cell = (0.5, 0.0) if tall else (0.0, 0.0)
    for i in range(n):
        yaw = i * math.pi / n * 2.3 + rng.uniform(-0.25, 0.25)
        h = rng.uniform(0.75, 1.05) if tall else rng.uniform(0.32, 0.5)
        w = h * rng.uniform(0.8, 1.0)
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * (0.1 if tall else 0.07)
        facing = Vector((math.cos(yaw), math.sin(yaw), 0))
        out = off.normalized() if off.length > 1e-3 else facing
        up = (UP + out * rng.uniform(0.1, 0.3)).normalized()
        phase = rng.random()
        nrm = lambda p, c=off: (UP * 0.8 + Vector((p.x - 0, p.y - 0, 0)).normalized() * 0.2).normalized() \
            if Vector((p.x, p.y, 0)).length > 1e-3 else UP
        card(mb, "Meadow", off, up, facing, w, h, cell, None, flip=rng.random() < 0.5, sink=0.02,
             segs=segs, bend=rng.uniform(0.05, 0.18), custom_nrm=nrm,
             vcol_fn=lambda p, t, ph=phase: wind_col(t, ph))
    return finish(name, mb, mats, preview, wind=True, cam=(1.0, -1.7, 0.55), fit=1.1)


def build_flowers(name, seed, preview):
    rng, mats, mb = start(seed)
    groups = [(0, Vector((0.12, 0.05, 0))), (1, Vector((-0.18, 0.12, 0))), (3, Vector((0.02, -0.2, 0))),
              (0, Vector((-0.12, -0.1, 0)))]
    nrm = lambda p: (UP * 0.8 + Vector((p.x, p.y, 0)).normalized() * 0.2).normalized() \
        if Vector((p.x, p.y, 0)).length > 1e-3 else UP
    for kind, c in groups:
        for j in range(4):
            yaw = j * math.pi / 4 + rng.uniform(-0.3, 0.3)
            h = rng.uniform(0.38, 0.55)
            off = c + Vector((rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), 0))
            facing = Vector((math.cos(yaw), math.sin(yaw), 0))
            up = (UP + Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))).normalized()
            ph = rng.random()
            card(mb, "Meadow", off, up, facing, h * 0.5, h, (kind * 0.25, 0.5), None,
                 flip=rng.random() < 0.5, sink=0.02, cell_size=(0.25, 0.5), segs=2, bend=0.05,
                 custom_nrm=nrm, vcol_fn=lambda p, t, ph=ph: wind_col(t, ph))
    for i in range(6):   # short grass skirt
        yaw = i * math.pi / 6 * 2.1
        h = rng.uniform(0.25, 0.35)
        off = Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
        ph = rng.random()
        card(mb, "Meadow", off, UP, Vector((math.cos(yaw), math.sin(yaw), 0)), h, h, (0.0, 0.0), None,
             flip=rng.random() < 0.5, sink=0.02, segs=2, bend=0.1, custom_nrm=nrm,
             vcol_fn=lambda p, t, ph=ph: wind_col(t, ph))
    return finish(name, mb, mats, preview, wind=True, cam=(1.0, -1.7, 0.6), fit=1.1)


# ============================================================================ main
ASSETS = {
    "oak_a": lambda pv: build_oak("oak_a", 11, 11.5, 10.0, pv),
    "oak_b": lambda pv: build_oak("oak_b", 27, 9.5, 9.5, pv, spread=1.1, crown_base=0.37),
    "birch_a": lambda pv: build_birch("birch_a", 5, 10.0, pv),
    "pine_a": lambda pv: build_scots_pine("pine_a", 8, 16.0, pv),
    "pine_b": lambda pv: build_spruce("pine_b", 3, 13.0, pv),
    "sapling": lambda pv: build_sapling("sapling", 4, pv),
    "dead_tree": lambda pv: build_dead("dead_tree", 9, pv),
    "bush_a": lambda pv: build_bush("bush_a", 12, 1.4, 1.8, [3], (1.0, 1.0, 0.9), pv),
    "bush_b": lambda pv: build_bush("bush_b", 21, 1.0, 1.7, [1, 3], (0.78, 0.86, 0.8), pv, n_stems=9),
    "grass_clump": lambda pv: build_grass("grass_clump", 1, False, pv),
    "grass_clump_tall": lambda pv: build_grass("grass_clump_tall", 2, True, pv),
    "flowers_a": lambda pv: build_flowers("flowers_a", 6, pv),
}


def main():
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or list(ASSETS)
    preview = "--no-preview" not in sys.argv
    os.makedirs(rn.NATURE, exist_ok=True)
    os.makedirs(rn.PREVIEWS, exist_ok=True)
    for n in names:
        rn.reset_scene()
        ASSETS[n](preview)


if __name__ == "__main__":
    main()
