"""Region set 3: MINE (entrance in a rock face with timber supports, rail cart + track pieces, ore
piles, head-frame winch over a shaft, miner's hut, tunnel support frame, mining props).

Run headless (Blender 5.x) from the repo root:
    blender -b --factory-startup --python kingdom/tools/blender/make_region_mine.py -- [names...|all] [--sheet]

Outputs kingdom/assets/generated/region/mine/<name>.glb + _lod1.glb and
docs/kingdom/blender_previews/region_mine_sheet.png. Rails: gauge 0.9 m, track pieces run along +Y
(Blender) from y=0 to y=4 (straight) so they chain end to end; rail_curve turns 45 deg left on a 6 m
radius and has an empty "track_end" at its exit.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import region_kit as K
from region_struct import *   # noqa: F401,F403
import region_struct as S

GAUGE = 0.9
ROCK = (0.8, 0.77, 0.72)
LAMP = (1.0, 0.72, 0.35)


def cliff_lump(k, c, size, seed, lod, tint=ROCK):
    S.lumpy(k, c, size, "RG_Cliff", jit(k, tint, 0.05), seed=seed, subdiv=2 if lod == 0 else 1, sink=0.15)


def lantern(k, x, y, z, lod=0):
    k.box((0.18, 0.18, 0.26), (x, y, z), "RG_Glow", LAMP)
    k.box((0.24, 0.24, 0.04), (x, y, z + 0.15), "RG_Iron", IRON)
    k.box((0.22, 0.22, 0.03), (x, y, z - 0.14), "RG_Iron", IRON)


def track(k, pts, lod, sleeper_step=0.6):
    """Rails + sleepers along a polyline of centre points (Vector, z=0)."""
    n = len(pts)
    L = 0.0
    segs = []
    for i in range(n - 1):
        segs.append((pts[i], pts[i + 1]))
    for side in (-1, 1):
        rp = []
        for i in range(n):
            d = (pts[min(n - 1, i + 1)] - pts[max(0, i - 1)]).normalized()
            s = Vector((d.y, -d.x, 0))
            rp.append(pts[i] + s * side * GAUGE / 2 + Vector((0, 0, 0.14)))
        for i in range(n - 1):
            k.beam(tuple(rp[i]), tuple(rp[i + 1]), 0.06, 0.09, "RG_Iron", (0.95, 0.9, 0.85), up=(0, 0, 1))
    # sleepers
    acc = sleeper_step / 2
    step = sleeper_step if lod == 0 else sleeper_step * 2
    total = sum((b - a).length for a, b in segs)
    t = step / 2
    while t < total:
        rem = t
        for a, b in segs:
            l = (b - a).length
            if rem <= l:
                p = a + (b - a) * (rem / l)
                d = (b - a).normalized()
                s = Vector((d.y, -d.x, 0))
                k.beam(tuple(p - s * 0.7 + Vector((0, 0, 0.05))), tuple(p + s * 0.7 + Vector((0, 0, 0.05))), 0.2, 0.12,
                       "RG_Timber", jit(k, WOOD_DK, 0.1), up=(0, 0, 1))
                break
            rem -= l
        t += step


def mine_entrance(k, lod):
    ow, oh = 2.6, 2.9
    # rock face around the portal
    moss = (0.62, 0.72, 0.45)
    S.crag(k, (-3.9, 1.3, 0), (2.5, 2.2, 3.6), 1, tint=ROCK, lod=lod, top_tint=moss, cuts=15, rot=0.2)
    S.crag(k, (4.0, 1.4, 0), (2.6, 2.3, 3.3), 2, tint=ROCK, lod=lod, top_tint=moss, cuts=15, rot=-0.3)
    S.crag(k, (0.0, 2.6, 3.2), (3.4, 2.4, 2.2), 3, tint=ROCK, lod=lod, top_tint=moss, cuts=15, sink=0.0)
    S.crag(k, (-2.6, 4.2, 0), (4.4, 2.8, 5.6), 4, tint=(0.86, 0.84, 0.82), lod=lod, top_tint=moss, cuts=15, rot=0.4)
    S.crag(k, (2.8, 4.4, 0), (4.0, 2.8, 5.0), 5, tint=(0.86, 0.84, 0.82), lod=lod, top_tint=moss, cuts=15, rot=-0.2)
    S.crag(k, (0.3, 5.2, 2.5), (3.6, 2.6, 3.4), 8, tint=(0.82, 0.8, 0.78), lod=lod, top_tint=moss, cuts=15)
    if lod == 0:
        S.crag(k, (-6.2, 0.0, 0), (1.2, 1.0, 0.9), 6, tint=ROCK, lod=lod, top_tint=moss, cuts=15)
        S.crag(k, (6.4, 0.2, 0), (1.0, 0.9, 0.8), 7, tint=ROCK, lod=lod, top_tint=moss, cuts=15)
    # tunnel interior (inward-facing dark walls), 5 m deep
    D = 5.0
    dark = (0.22, 0.2, 0.19)
    k.box((0.3, D, oh + 0.3), (-ow / 2 - 0.15, 0.2 + D / 2, (oh + 0.3) / 2), "RG_Cliff", dark)
    k.box((0.3, D, oh + 0.3), (ow / 2 + 0.15, 0.2 + D / 2, (oh + 0.3) / 2), "RG_Cliff", dark)
    k.box((ow + 0.6, D, 0.3), (0, 0.2 + D / 2, oh + 0.15), "RG_Cliff", dark)
    k.box((ow + 0.6, 0.3, oh + 0.3), (0, 0.2 + D, (oh + 0.3) / 2), "RG_Cliff", (0.05, 0.05, 0.05))
    k.box((ow, D, 0.04), (0, 0.2 + D / 2, 0.0), "RG_Soil", (0.5, 0.45, 0.4))
    # timber portal: posts, lintel, knee braces, a second set inside
    for yy, dk in ((-0.2, 1.0), (1.6, 0.7), (3.4, 0.45)):
        if lod == 1 and yy > 2:
            continue
        for sx in (-1, 1):
            k.beam((sx * ow / 2, yy, -0.1), (sx * (ow / 2 - 0.08), yy, oh), 0.26, 0.26, "RG_Timber",
                   jit(k, tuple(c * dk for c in TIMBER)), up=(1, 0, 0))
        k.beam((-ow / 2 - 0.35, yy, oh + 0.12), (ow / 2 + 0.35, yy, oh + 0.12), 0.3, 0.3, "RG_Timber",
               jit(k, tuple(c * dk for c in TIMBER)))
        if lod == 0 and yy < 0:
            for sx in (-1, 1):
                k.beam((sx * (ow / 2 - 0.05), yy - 0.02, oh - 0.7), (sx * (ow / 2 - 0.75), yy - 0.02, oh + 0.02), 0.16,
                       0.14, "RG_Timber", jit(k, TIMBER), up=(0, -1, 0))
    # plank lagging over the lintel + a sign board
    k.box((ow + 0.9, 0.1, 0.6), (0, -0.25, oh + 0.57), "RG_Planks", jit(k, WOOD_DK), grain=0)
    if lod == 0:
        k.box((1.2, 0.06, 0.4), (0, -0.33, oh + 0.62), "RG_Planks", (0.95, 0.85, 0.7), grain=0)
        k.box((0.8, 0.02, 0.06), (0, -0.37, oh + 0.64), "RG_Timber", HOLE)
        lantern(k, ow / 2 + 0.3, -0.35, 2.3, lod)
        k.beam((ow / 2 + 0.05, -0.3, 2.55), (ow / 2 + 0.35, -0.3, 2.55), 0.05, 0.05, "RG_Iron", IRON)
        barrel(k, -ow / 2 - 0.8, -0.8, 0, lod=lod)
        crate(k, -ow / 2 - 1.3, -1.6, 0, 0.6, 0.3, lod=lod)
    track(k, [Vector((0, y, 0)) for y in (4.8, 2.0, -0.5, -3.0)], lod)


def rail_straight(k, lod):
    track(k, [Vector((0, 0, 0)), Vector((0, 4.0, 0))], lod)


def rail_curve(k, lod):
    R, ang = 6.0, math.radians(45)
    n = 6 if lod == 0 else 3
    pts = [Vector((-R + R * math.cos(a), R * math.sin(a), 0)) for a in [ang * i / n for i in range(n + 1)]]
    track(k, pts, lod)
    k.markers = [("track_end", pts[-1])]


def rail_end(k, lod):
    track(k, [Vector((0, 0, 0)), Vector((0, 2.0, 0))], lod)
    # buffer stop: timber frame + earth mound
    for sx in (-1, 1):
        k.beam((sx * GAUGE / 2, 1.9, 0), (sx * GAUGE / 2, 1.9, 0.9), 0.2, 0.2, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
        k.beam((sx * GAUGE / 2, 2.8, 0), (sx * GAUGE / 2, 1.95, 0.85), 0.16, 0.16, "RG_Timber", jit(k, TIMBER))
    k.box((1.6, 0.25, 0.4), (0, 1.8, 0.65), "RG_Timber", jit(k, WOOD_DK))
    S.lumpy(k, (0, 2.9, 0), (1.3, 0.9, 0.6), "RG_Soil", (0.9, 0.85, 0.78), seed=4, subdiv=2 if lod == 0 else 1)


def mine_cart(k, lod):
    L, W, H, z0 = 1.3, 0.95, 0.6, 0.3
    # tapered body: wider at the top
    pts = [(-W / 2 + 0.08, 0), (W / 2 - 0.08, 0), (W / 2, H), (-W / 2, H)]
    k.prism(pts, L, (0, 0, z0), "RG_Planks", jit(k, WOOD_DK), grain=0)
    for t in (0.15, 0.85):
        k.prism([(-W / 2 + 0.08 - 0.02, 0), (W / 2 - 0.08 + 0.02, 0), (W / 2 + 0.02, H), (-W / 2 - 0.02, H)], 0.06,
                (0, -L / 2 + L * t, z0), "RG_Iron", IRON)
    k.box((W * 0.95, L * 0.95, 0.04), (0, 0, z0 + H - 0.05), "RG_Cliff", (0.45, 0.35, 0.3))   # ore load top
    for i in range(9 if lod == 0 else 3):
        S.crag(k, (k.rng.uniform(-0.3, 0.3), k.rng.uniform(-0.45, 0.45), z0 + H - 0.08), (0.13, 0.12, 0.1), 60 + i,
               tint=(0.85, 0.6, 0.45), lod=1, cuts=6, sink=0.0, subdiv=2)
    k.box((W - 0.2, L + 0.1, 0.12), (0, 0, z0 - 0.05), "RG_Timber", jit(k, WOOD_DK))
    for y in (-L / 2 + 0.25, L / 2 - 0.25):
        for sx in (-1, 1):
            c = (sx * GAUGE / 2, y, 0.2)
            k.cyl(0.2, 0.08, (c[0] - sx * 0.04, c[1], c[2]), "RG_Iron", (0.8, 0.78, 0.75), rot=(0, sx * math.pi / 2, 0),
                  segs=12 if lod == 0 else 7)
        k.beam((-GAUGE / 2, y, 0.2), (GAUGE / 2, y, 0.2), 0.06, 0.06, "RG_Iron", IRON)
    if lod == 0:
        k.beam((0, -L / 2 - 0.02, z0 + 0.25), (0, -L / 2 - 0.25, z0 + 0.1), 0.06, 0.06, "RG_Iron", IRON)  # coupling


def ore_pile(kind):
    tint = {"iron": (0.85, 0.62, 0.5), "coal": (0.3, 0.29, 0.29), "copper": (0.7, 0.72, 0.64)}[kind]
    chunk = {"iron": hexc("b0582c"), "coal": hexc("202022"), "copper": hexc("3f9a86")}[kind]

    def f(k, lod):
        S.lumpy(k, (0, 0, 0), (1.25, 1.05, 0.62), "RG_Soil", tint, seed=sum(map(ord, kind)) % 50,
                subdiv=2 if lod == 0 else 1, sink=0.05)
        n = 22 if lod == 0 else 7
        for i in range(n):
            a = k.rng.uniform(0, math.tau)
            r = k.rng.uniform(0.0, 1.25) if lod == 0 else k.rng.uniform(0.0, 0.9)
            s = k.rng.uniform(0.2, 0.4) * (1.3 if lod else 1.0)
            z = max(0.0, 0.62 * (1 - (r / 1.35) ** 2) - s * 0.5)
            S.crag(k, (math.cos(a) * r, math.sin(a) * r * 0.85, z), (s, s * 0.85, s * 0.75), 40 + i,
                   tint=jit(k, chunk if k.rng.random() < 0.55 else tint, 0.1), lod=1, cuts=6, rot=a, sink=0.0,
                   subdiv=2)
        if lod == 0:
            k.beam((0.9, -0.3, 0.0), (1.35, -0.1, 1.1), 0.04, 0.04, "RG_Timber", jit(k, WOOD))     # shovel handle
            k.box((0.22, 0.03, 0.28), (0.86, -0.32, 0.05), "RG_Iron", IRON, rot=(0.2, 0, 0.4))
    return f


def mine_winch(k, lod):
    """Head frame over a timber-collared shaft: two A-frames, sheave wheel, winch drum + crank, bucket."""
    s = 1.2   # shaft half size
    k.box((2 * s + 0.1, 2 * s + 0.1, 0.05), (0, 0, 0.02), "RG_Timber", (0.03, 0.03, 0.03))   # shaft void
    for sy in (-1, 1):
        k.beam((-s - 0.3, sy * s, 0.12), (s + 0.3, sy * s, 0.12), 0.3, 0.3, "RG_Timber", jit(k, TIMBER))
        k.beam((sy * s, -s - 0.3, 0.12), (sy * s, s + 0.3, 0.12), 0.3, 0.3, "RG_Timber", jit(k, TIMBER))
    H = 5.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            k.beam((sx * (s + 0.2), sy * (s + 0.9), 0), (sx * (s + 0.05), sy * 0.25, H), 0.22, 0.22, "RG_Timber",
                   jit(k, TIMBER))
        k.beam((sx * (s + 0.12), -s - 0.4, 2.2), (sx * (s + 0.12), s + 0.4, 2.2), 0.16, 0.16, "RG_Timber", jit(k, TIMBER))
    k.beam((-s - 0.4, 0, H), (s + 0.4, 0, H), 0.28, 0.28, "RG_Timber", jit(k, TIMBER))
    # sheave wheel
    wheel(k, (0, 0, H + 0.55), 0.6, w=0.12, spokes=6, lod=lod, axis="x")
    # rope down the shaft + bucket
    k.beam((0, -0.6, H + 0.55), (0, -0.6, 1.2), 0.035, 0.035, "RG_Hay", (0.8, 0.7, 0.55), up=(1, 0, 0))
    k.beam((0, 0.6, H + 0.55), (0, 3.6, 1.0), 0.035, 0.035, "RG_Hay", (0.8, 0.7, 0.55))
    k.lathe([(0.28, 0), (0.34, 0.55)], (0, -0.6, 0.65), "RG_Planks", jit(k, WOOD_DK), segs=10 if lod == 0 else 6,
            caps=(True, False), uscale=0.8)
    k.cyl(0.35, 0.04, (0, -0.6, 1.1), "RG_Iron", IRON, segs=10 if lod == 0 else 6, caps=(False, False))
    # winch drum with crank on a trestle
    for sx in (-1, 1):
        k.beam((sx * 0.9, 3.6, 0), (sx * 0.9, 3.6, 1.1), 0.18, 0.18, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
        k.beam((sx * 0.9, 3.2, 0), (sx * 0.9, 4.0, 0), 0.16, 0.16, "RG_Timber", jit(k, TIMBER))
    k.cyl(0.3, 1.6, (-0.8, 3.6, 1.0), "RG_Log", jit(k, WOOD), rot=(0, math.pi / 2, 0), segs=10 if lod == 0 else 6,
          bark=0)
    k.beam((0.95, 3.6, 1.0), (1.2, 3.6, 1.0), 0.06, 0.06, "RG_Iron", IRON)
    k.beam((1.2, 3.6, 1.0), (1.2, 3.6, 0.6), 0.06, 0.06, "RG_Iron", IRON, up=(1, 0, 0))
    k.beam((1.2, 3.6, 0.6), (1.5, 3.6, 0.6), 0.05, 0.05, "RG_Timber", jit(k, WOOD))
    if lod == 0:
        crate(k, -2.2, 2.4, 0, 0.65, 0.4, lod=lod)
        barrel(k, -2.4, 3.3, 0, lod=lod)


def miners_hut(k, lod):
    """Small log cabin: stacked round logs with crossed corners, shingle roof, stone chimney."""
    L, W, eave, r = 4.4, 3.6, 2.4, 0.15
    hx, hy = L / 2, W / 2
    k.box((L + 0.3, W + 0.3, 0.3), (0, 0, 0.1), "RG_Stone", (0.9, 0.9, 0.88))
    n = int((eave - 0.3) / (2 * r * 0.92))
    dw, dh, dx = 1.0, 1.9, -0.6
    wx0, wx1, wz0, wz1 = 0.8, 1.6, 1.0, 1.7
    segs = 6 if lod == 0 else 4
    for i in range(n):
        z = 0.3 + r + i * 2 * r * 0.92
        for y in (-hy, hy):
            if y < 0 and z < dh + 0.25:
                parts = [(-hx - 0.3, dx - dw / 2), (dx + dw / 2, hx + 0.3)]
                if wz0 < z < wz1:
                    parts = [(-hx - 0.3, dx - dw / 2), (dx + dw / 2, wx0), (wx1, hx + 0.3)]
            else:
                parts = [(-hx - 0.3, hx + 0.3)]
            for a, b in parts:
                k.tube([(a, y, z), (b, y, z)], [r, r * 0.95], "RG_Log", jit(k, WOOD, 0.1), segs=segs, bark=0)
        for x in (-hx, hx):
            k.tube([(x, -hy - 0.3, z + r * 0.92), (x, hy + 0.3, z + r * 0.92)], [r, r * 0.95], "RG_Log",
                   jit(k, WOOD, 0.1), segs=segs, bark=0)
    # fill behind the logs (so gaps read as chinking, not holes)
    k.box((L - 0.1, W - 0.1, eave - 0.3), (0, 0, 0.3 + (eave - 0.3) / 2), "RG_Plaster", (0.55, 0.5, 0.45),
          skip=("+z", "-z"))
    door(k, dx, -hy - 0.1, dw, dh, z0=0.3, tint=(0.75, 0.55, 0.45))
    window(k, (wx0 + wx1) / 2, -hy - 0.12, wz0, wx1 - wx0, wz1 - wz0, shutters=True, sh_tint=(0.7, 0.5, 0.4), lod=lod)
    rz = gable_roof(k, 0, 0, L, W, eave + 0.2, pitch=38, over_x=0.5, over_y=0.5, th=0.12, mat="RG_Shingle")
    for x in (-hx, hx):
        gable_end(k, 0, x, 0, W, eave + 0.2, rz - 0.1, th=0.14)
    # stone chimney on the east gable
    k.box((0.8, 0.9, rz + 0.6), (hx + 0.45, 0.4, (rz + 0.6) / 2), "RG_Stone", (0.9, 0.88, 0.85))
    k.box((0.9, 1.0, 0.12), (hx + 0.45, 0.4, rz + 0.6), "RG_Stone", (0.75, 0.73, 0.7))
    k.markers = [("chimney_top", Vector((hx + 0.45, 0.4, rz + 0.7)))]
    if lod == 0:
        lantern(k, dx + 0.8, -hy - 0.35, 2.0, lod)
        # pick and shovel leaning by the door
        k.beam((dx - 0.9, -hy - 0.3, 0.0), (dx - 0.8, -hy - 0.2, 1.2), 0.05, 0.05, "RG_Timber", jit(k, WOOD))
        k.beam((dx - 1.05, -hy - 0.25, 1.2), (dx - 0.55, -hy - 0.15, 1.15), 0.06, 0.05, "RG_Iron", IRON)
        barrel(k, hx - 0.3, -hy - 0.6, 0, lod=lod)
        # woodpile under the eave on the west side
        for i in range(3):
            for j in range(4 - i):
                k.tube([(-hx - 0.55, -1.0 + j * 0.24 + i * 0.12, 0.12 + i * 0.2),
                        (-hx - 0.55 + 0.02, -1.0 + j * 0.24 + i * 0.12, 0.12 + i * 0.2)], [0.1, 0.1], "RG_Log",
                       WOOD, segs=5, bark=0)


def tunnel_support(k, lod):
    """Free-standing timber set (posts, cap, lagging planks) to line tunnels or ruined shafts."""
    ow, oh = 2.6, 2.9
    for sx in (-1, 1):
        k.beam((sx * ow / 2, 0, 0), (sx * (ow / 2 - 0.1), 0, oh), 0.26, 0.26, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    k.beam((-ow / 2 - 0.3, 0, oh + 0.12), (ow / 2 + 0.3, 0, oh + 0.12), 0.3, 0.3, "RG_Timber", jit(k, TIMBER))
    n = 6 if lod == 0 else 2
    for i in range(n):
        x = -ow / 2 + ow * (i + 0.5) / n
        k.box((ow / n - 0.03, 1.6, 0.06), (x, 0.8, oh + 0.3), "RG_Planks", jit(k, WOOD_DK), grain=1)
    for sx in (-1, 1):
        k.beam((sx * (ow / 2 - 0.05), 0, oh - 0.6), (sx * (ow / 2 - 0.6), 0, oh), 0.14, 0.14, "RG_Timber", jit(k, TIMBER),
               up=(0, -1, 0))


def mine_props(k, lod):
    """Crates, barrels, a wheelbarrow with ore and a tool rack: dressing for the mine yard."""
    crate(k, -1.2, 0.3, 0, 0.7, 0.2, lod=lod)
    crate(k, -1.15, 0.35, 0.7, 0.55, -0.3, lod=lod)
    barrel(k, -0.2, 0.6, 0, lod=lod)
    # wheelbarrow
    k.push((1.0, -0.2, 0), (0, 0, 0.4))
    k.prism([(-0.35, 0.3), (0.35, 0.3), (0.45, 0.65), (-0.45, 0.65)], 0.9, (0, 0, 0), "RG_Planks", jit(k, WOOD_DK),
            rot=(0, 0, math.pi / 2), grain=0)
    S.lumpy(k, (0, 0, 0.55), (0.3, 0.38, 0.14), "RG_Cliff", (0.75, 0.55, 0.45), seed=2, subdiv=1 if lod == 0 else 0,
            sink=0.1)
    wheel(k, (0, -0.65, 0.25), 0.25, w=0.07, spokes=6, lod=lod, axis="x")
    for sx in (-1, 1):
        k.beam((sx * 0.25, -0.6, 0.3), (sx * 0.3, 0.95, 0.55), 0.06, 0.06, "RG_Timber", jit(k, WOOD_DK))
        k.beam((sx * 0.25, 0.35, 0.3), (sx * 0.25, 0.45, 0.0), 0.05, 0.05, "RG_Timber", jit(k, WOOD_DK))
    k.pop()
    # tool rack with picks
    for x in (-0.5, 0.5):
        k.beam((x, 1.5, 0), (x, 1.5, 1.3), 0.1, 0.1, "RG_Timber", jit(k, TIMBER), up=(1, 0, 0))
    k.beam((-0.6, 1.45, 1.2), (0.6, 1.45, 1.2), 0.08, 0.08, "RG_Timber", jit(k, TIMBER))
    for i, x in enumerate((-0.3, 0.0, 0.3)):
        k.beam((x, 1.4, 0.05), (x, 1.4, 1.15), 0.045, 0.045, "RG_Timber", jit(k, WOOD))
        k.beam((x - 0.25, 1.38, 1.1), (x + 0.25, 1.38, 1.18), 0.05, 0.04, "RG_Iron", IRON)


ASSETS = {
    "mine_entrance": (mine_entrance, 8000, 2400, dict(cam=(0.9, -1.6, 0.5))),
    "rail_straight": (rail_straight, 600, 200, dict(cam=(1.2, -1.2, 0.8))),
    "rail_curve": (rail_curve, 1000, 300, dict(cam=(0.6, -1.4, 1.0))),
    "rail_end": (rail_end, 800, 300, {}),
    "mine_cart": (mine_cart, 1500, 500, {}),
    "ore_pile_iron": (ore_pile("iron"), 3000, 800, {}),
    "ore_pile_coal": (ore_pile("coal"), 3000, 800, {}),
    "ore_pile_copper": (ore_pile("copper"), 3000, 800, {}),
    "mine_winch": (mine_winch, 4000, 1200, dict(cam=(1.0, -1.4, 0.55))),
    "miners_hut": (miners_hut, 5000, 1500, {}),
    "tunnel_support": (tunnel_support, 800, 250, {}),
    "mine_props": (mine_props, 3000, 1000, {}),
}

run_set("mine", ASSETS, "RISING ASHES - REGION 1 MINE SET  (TRIS LOD0 / LOD1)")
