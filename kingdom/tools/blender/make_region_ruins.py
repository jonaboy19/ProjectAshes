"""Region set 5: RUINS AND HIDDEN PLACES (collapsed tower, overgrown shrine, bandit camp pieces,
goblin totems).

Run headless (Blender 5.x) from the repo root:
    blender -b --factory-startup --python kingdom/tools/blender/make_region_ruins.py -- [names...|all] [--sheet]

Outputs kingdom/assets/generated/region/ruins/<name>.glb + _lod1.glb and
docs/kingdom/blender_previews/region_ruins_sheet.png. Ivy and weeds are alpha cards on RG_Crop
(foliage_atlas.png, COLOR_0 = tint), so they import with Godot's defaults.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import region_kit as K
from region_struct import *   # noqa: F401,F403
import region_struct as S

MOSS = (0.6, 0.72, 0.45)
BONE = hexc("e3d6b8")
EMBER = (1.0, 0.45, 0.12)
UPV = Vector((0, 0, 1))


def ivy(k, base, normal, w, h, n=3, cell=(0, 1)):
    """Leaf cards hugging a surface: base point on the wall, outward normal."""
    nrm = Vector(normal).normalized()
    side = nrm.cross(UPV)
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side.normalize()
    for i in range(n):
        p = Vector(base) + side * k.rng.uniform(-w / 2, w / 2) + UPV * k.rng.uniform(0, h) + nrm * 0.06
        s = k.rng.uniform(0.6, 1.0)
        u = (UPV * math.cos(k.rng.uniform(-0.8, 0.8)) + side * k.rng.uniform(-0.5, 0.5)).normalized()
        r = u.cross(nrm).normalized()
        k.card(p, r, u, s, s, cell, mat="RG_Crop", cols=(*K.lin((0.9, 1.0, 0.85)), 1.0),
               nrms=lambda q, nn=nrm: (nn + UPV * 0.3).normalized())


def weeds(k, pts, cells=((2, 0), (2, 2)), h=0.55):
    for p in pts:
        a = k.rng.uniform(0, math.pi)
        for b in (0.0, math.pi / 2):
            r = Vector((math.cos(a + b), math.sin(a + b), 0))
            k.card(Vector(p), r, UPV, h * 1.1, h, cells[k.rng.randrange(len(cells))], mat="RG_Crop",
                   cols=(*K.lin((1, 1, 1)), 1.0), base=True)


# ============================================================================ collapsed tower
def collapsed_tower(k, lod):
    R, t = 3.2, 0.9
    segs = 20 if lod == 0 else 12
    rng = random.Random(5)
    hs = []
    for i in range(segs):
        a = i / segs
        # tall on the back, broken down to the ground on the east
        h = 4.0 + 5.5 * (0.5 + 0.5 * math.cos((a - 0.45) * math.tau)) + rng.uniform(-0.8, 0.8)
        if 0.72 < a < 0.9:
            h = rng.uniform(0.6, 1.6)
        hs.append(max(0.5, h))
    stone = (0.98, 0.98, 0.99)         # cool grey: the texture (RG_Ruin) carries the weathering
    for i in range(segs):
        a0 = (i / segs - 0.25) * math.tau
        a1 = ((i + 1) / segs - 0.25) * math.tau
        z0 = 2.4 if i == 0 else 0.0            # doorway gap at the front (-Y)
        z1 = hs[i]
        z1b = hs[(i + 1) % segs] if lod == 0 else z1
        top = [z1, z1b]
        P = lambda a, r, z: Vector((math.cos(a) * r, math.sin(a) * r, z))
        o0, o1, i0, i1 = P(a0, R, 0), P(a1, R, 0), P(a0, R - t, 0), P(a1, R - t, 0)
        faces = [[P(a0, R, z0), P(a1, R, z0), P(a1, R, top[1]), P(a0, R, top[0])],
                 [P(a1, R - t, z0), P(a0, R - t, z0), P(a0, R - t, top[0]), P(a1, R - t, top[1])],
                 [P(a0, R - t, top[0]), P(a0, R, top[0]), P(a1, R, top[1]), P(a1, R - t, top[1])]]
        if abs(hs[i] - hs[i - 1]) > 0.05 or i == 0:
            faces.append([P(a0, R - t, z0), P(a0, R, z0), P(a0, R, top[0]), P(a0, R - t, top[0])][::-1])
        if abs(hs[(i + 1) % segs] - hs[i]) > 0.05 or i == segs - 1:
            faces.append([P(a1, R - t, z0), P(a1, R, z0), P(a1, R, top[1]), P(a1, R - t, top[1])])
        if z0 > 0:
            faces.append([P(a0, R - t, z0), P(a1, R - t, z0), P(a1, R, z0), P(a0, R, z0)])
        c = P((a0 + a1) / 2, R - t / 2, (z0 + z1) / 2)
        k.add(S.oriented(faces, c), "RG_Ruin", jit(k, stone, 0.05), scale=3.4,
              uvs=[[(math.atan2(p.y, p.x) * R / 3.4, p.z / 3.4) for p in f] for f in S.oriented(faces, c)])
        # arrow slits
        if lod == 0 and i % 5 == 2 and z1 > 5:
            am = (a0 + a1) / 2
            k.box((0.18, 0.1, 1.0), tuple(P(am, R + 0.02, 4.2)), "RG_Timber", HOLE, rot=(0, 0, am + math.pi / 2))
    # door lintel stone
    a0 = (-0.25) * math.tau
    k.beam(tuple(Vector((math.cos(a0), math.sin(a0), 0)) * (R + 0.05) + Vector((0, 0, 2.45))),
           tuple(Vector((math.cos(a0 + math.tau / segs), math.sin(a0 + math.tau / segs), 0)) * (R + 0.05) + Vector((0, 0, 2.45))),
           0.35, 0.3, "RG_Ruin", (0.86, 0.86, 0.88))
    # rubble + fallen blocks where the wall collapsed
    for i in range(14 if lod == 0 else 5):
        a = k.rng.uniform(0.7, 0.95) * math.tau - 0.25 * math.tau
        d = k.rng.uniform(R - 0.5, R + 3.0)
        s = k.rng.uniform(0.35, 0.8)
        S.crag(k, (math.cos(a) * d, math.sin(a) * d, 0), (s, s * 0.8, s * 0.6), 100 + i, mat="RG_Ruin",
               tint=jit(k, stone, 0.08), lod=1, cuts=6, rot=a, subdiv=2, top_tint=MOSS)
    if lod == 0:
        for i in range(6):
            a = k.rng.uniform(0, math.tau)
            ivy(k, (math.cos(a) * (R + 0.02), math.sin(a) * (R + 0.02), 0.1), (math.cos(a), math.sin(a), 0), 1.2,
                min(4.0, hs[int((a / math.tau + 0.25) % 1 * segs)] - 1.0), n=5)
        weeds(k, [(k.rng.uniform(-R - 2, R + 2), k.rng.uniform(-R - 2, R + 2), 0) for _ in range(8)])
        k.markers = [("interior", Vector((0, 0, 0)))]


# ============================================================================ overgrown shrine
def overgrown_shrine(k, lod):
    stone = (0.9, 0.9, 0.86)
    k.box((6.0, 6.0, 0.5), (0, 0, 0.25), "RG_Stone", stone)
    k.box((5.0, 5.0, 0.35), (0, 0.3, 0.67), "RG_Stone", jit(k, stone))
    for i in range(3):   # steps
        k.box((2.4, 0.4, 0.17 * (i + 1)), (0, -3.2 + i * 0.0 - 0.4 * (2 - i), 0.085 * (i + 1)), "RG_Stone", jit(k, stone))
    segs = 10 if lod == 0 else 6
    cols = [(-1.8, -1.5, 3.4), (1.8, -1.5, 1.4), (-1.8, 2.1, 2.2), (1.8, 2.1, 3.4)]
    for x, y, h in cols:
        k.cyl(0.4, 0.3, (x, y, 0.85), "RG_Stone", (0.82, 0.8, 0.76), segs=segs)
        k.cyl(0.3, h, (x, y, 1.15), "RG_Plaster", (0.82, 0.8, 0.74), segs=segs, r2=0.27)
        if h > 3:
            k.box((0.8, 0.8, 0.25), (x, y, 1.15 + h + 0.12), "RG_Stone", (0.85, 0.83, 0.78))
    # lintel remaining across the back pair, fallen drum pieces in front
    k.beam((-2.2, 2.1, 4.9), (2.2, 2.1, 4.75), 0.55, 0.6, "RG_Stone", (0.85, 0.83, 0.78))
    k.cyl(0.29, 1.1, (2.6, -2.3, 0.3), "RG_Plaster", (0.8, 0.78, 0.72), rot=(0, math.pi / 2, 0.5), segs=segs)
    k.cyl(0.29, 0.8, (3.4, -0.9, 0.3), "RG_Plaster", (0.8, 0.78, 0.72), rot=(0, math.pi / 2, 1.4), segs=segs)
    # altar with a carved rune (faintly glowing)
    k.box((1.6, 0.9, 1.0), (0, 1.0, 1.35), "RG_Stone", (0.8, 0.78, 0.74))
    k.box((1.8, 1.1, 0.15), (0, 1.0, 1.9), "RG_Stone", (0.75, 0.73, 0.7))
    k.box((0.5, 0.02, 0.5), (0, 0.54, 1.35), "RG_Glow", (0.35, 0.7, 0.8))
    k.markers = [("altar", Vector((0, 0.3, 1.0)))]
    if lod == 0:
        for x, y, h in cols:
            ivy(k, (x, y - 0.32, 1.15), (0, -1, 0), 0.4, h * 0.7, n=3)
        for x in (-2.9, 2.9):
            ivy(k, (x, 0, 0.1), (1 if x > 0 else -1, 0, 0), 5.0, 0.3, n=4)
        weeds(k, [(k.rng.uniform(-2.3, 2.3), k.rng.uniform(-2.0, 2.6), 0.85) for _ in range(10)] +
              [(k.rng.uniform(-3.2, 3.2), -3.4 + k.rng.uniform(-0.5, 0.2), 0) for _ in range(6)])
        for i in range(4):
            S.crag(k, (k.rng.uniform(-3, 3), k.rng.uniform(-3.8, -3.0) if i % 2 else k.rng.uniform(3.1, 3.6), 0),
                   (0.4, 0.35, 0.3), 200 + i, mat="RG_Stone", tint=stone, lod=1, cuts=6, subdiv=2, top_tint=MOSS)


# ============================================================================ bandit camp
DIRTY = (0.72, 0.64, 0.52)


def bandit_tent(k, lod):
    """A-frame tent (2.4 x 3.2 m, 2.1 m ridge), patched dirty canvas on a ridge pole."""
    L, W, H = 3.2, 2.6, 2.1
    for y in (-L / 2, L / 2):
        log_post(k, 0, y, H + 0.25, 0.05, lod)
    log_beam(k, (0, -L / 2 - 0.3, H), (0, L / 2 + 0.3, H), 0.05, lod)
    nv = 4 if lod == 0 else 1
    for sx in (-1, 1):
        k.sheet(((0, -L / 2, H), (0, L / 2, H), (sx * W / 2, -L / 2, 0.02), (sx * W / 2, L / 2, 0.02)), 3, nv,
                "RG_Canvas", tint=DIRTY, sag_fn=lambda u, v: (0, 0, -0.12 * math.sin(math.pi * v) * (0.6 + 0.4 * math.sin(math.pi * u))))
    # back wall triangle + door flaps at the front
    k.poly([(-W / 2, L / 2, 0.02), (0, L / 2, H), (W / 2, L / 2, 0.02)][::-1], "RG_Canvas", DIRTY, both=True)
    k.poly([(-W / 2, -L / 2, 0.02), (-0.15, -L / 2 - 0.2, 0.02), (0, -L / 2, H)], "RG_Canvas", jit(k, DIRTY), both=True)
    k.poly([(0.35, -L / 2 - 0.3, 0.02), (W / 2, -L / 2, 0.02), (0, -L / 2, H)], "RG_Canvas", jit(k, DIRTY), both=True)
    k.box((1.0, 0.02, 1.2), (0, -L / 2 + 0.3, 0.6), "RG_Timber", HOLE)
    if lod == 0:
        for p in ((-0.4, 0.3), (0.5, -0.4)):
            k.box((0.5, 0.35, 0.02), (p[0], L / 2 + 0.0, 0.9 + p[1]), "RG_Canvas", (0.55, 0.45, 0.35),
                  rot=(0, 0.6 if p[0] < 0 else -0.6, 0))   # patches
        for sx in (-1, 1):   # guy ropes + pegs
            for y in (-L / 2, L / 2):
                k.beam((0, y, H), (sx * (W / 2 + 0.9), y + (0.4 if y > 0 else -0.4), 0.0), 0.02, 0.02, "RG_Hay",
                       (0.8, 0.7, 0.55))
        sack(k, 1.6, 0.8, 0, 0.9)


def bandit_lean_to(k, lod):
    for x in (-1.5, 1.5):
        log_post(k, x, 0.0, 1.9, 0.07, lod)
    log_beam(k, (-1.8, 0, 1.85), (1.8, 0, 1.85), 0.06, lod)
    k.sheet(((-1.7, 0, 1.85), (1.7, 0, 1.85), (-1.7, 1.9, 0.1), (1.7, 1.9, 0.1)), 3, 2, "RG_Canvas",
            tint=hexc("7a5a40"), sag_fn=lambda u, v: (0, 0, -0.1 * math.sin(math.pi * v)))
    # bedroll + firewood
    k.cyl(0.18, 1.5, (-0.8, 1.0, 0.18), "RG_Canvas", hexc("5e6f5a"), rot=(0, math.pi / 2, 0.1), segs=8 if lod == 0 else 5)
    if lod == 0:
        for i in range(5):
            k.tube([(0.6 + i * 0.12, 1.2, 0.1 + (i % 2) * 0.1), (0.6 + i * 0.12, 0.4, 0.1 + (i % 2) * 0.1)], [0.07, 0.07],
                   "RG_Log", WOOD, segs=5, bark=0)
        crate(k, 1.2, -0.6, 0, 0.55, 0.4)


def campfire(k, lod):
    n = 9 if lod == 0 else 6
    for i in range(n):
        a = i / n * math.tau
        S.crag(k, (math.cos(a) * 0.75, math.sin(a) * 0.75, 0), (0.22, 0.18, 0.18), 300 + i, mat="RG_Cliff",
               tint=(0.7, 0.68, 0.64), lod=1, cuts=5, rot=a, subdiv=1)
    k.box((1.0, 1.0, 0.04), (0, 0, 0.0), "RG_Soil", (0.3, 0.27, 0.25))
    for i in range(5 if lod == 0 else 3):
        a = i / 5 * math.tau
        d = Vector((math.cos(a), math.sin(a), 0))
        k.tube([tuple(d * 0.6 + Vector((0, 0, 0.08))), tuple(d * 0.05 + Vector((0, 0, 0.45)))], [0.07, 0.05], "RG_Log",
               (0.5, 0.42, 0.36), segs=5 if lod == 0 else 4, bark=0)
    S.lumpy(k, (0, 0, 0.0), (0.35, 0.35, 0.15), "RG_Glow", EMBER, seed=3, subdiv=1 if lod == 0 else 0, sink=0.3)
    # embers glow; the flames themselves are a game VFX at the "fire" marker
    k.markers = [("fire", Vector((0, 0, 0.4)))]
    if lod == 0:
        for x in (-0.9, 0.9):
            k.beam((x, 0, 0), (x * 0.95, 0, 1.0), 0.05, 0.05, "RG_Timber", jit(k, WOOD_DK), up=(1, 0, 0))
            k.beam((x * 0.95, 0, 1.0), (x * 0.95 + 0.1 * (1 if x > 0 else -1), 0, 1.15), 0.05, 0.05, "RG_Timber",
                   jit(k, WOOD_DK))
        k.beam((-1.0, 0, 0.98), (1.0, 0, 0.98), 0.03, 0.03, "RG_Iron", IRON)
        k.lathe([(0.0, 0), (0.2, 0.02), (0.24, 0.2), (0.22, 0.3)], (0, 0, 0.6), "RG_Iron", (0.6, 0.6, 0.6), segs=8,
                caps=(False, False))   # hanging pot
        for x in (-1.6, 1.5):   # log seats
            k.tube([(x, -0.8, 0.22), (x + 0.1, 0.8, 0.22)], [0.22, 0.2], "RG_Log", WOOD, segs=7, bark=0)


def bandit_stash(k, lod):
    crate(k, -0.8, 0, 0, 0.75, 0.2, lod=lod)
    crate(k, -0.75, 0.05, 0.75, 0.6, -0.2, lod=lod)
    crate(k, 0.1, 0.5, 0, 0.6, 0.6, lod=lod)
    barrel(k, 0.7, -0.3, 0, lod=lod)
    sack(k, -0.1, -0.6, 0, 1.0, 0.4, lod=lod)
    sack(k, 0.35, -0.85, 0, 0.9, -0.3, lod=lod)
    # weapon rack with spears + a stolen chest
    for x in (1.4, 2.4):
        k.beam((x, 0.6, 0), (x, 0.6, 1.2), 0.08, 0.08, "RG_Timber", jit(k, WOOD_DK), up=(1, 0, 0))
    k.beam((1.3, 0.6, 1.1), (2.5, 0.6, 1.1), 0.07, 0.07, "RG_Timber", jit(k, WOOD_DK))
    for i in range(3 if lod == 0 else 1):
        x = 1.6 + i * 0.3
        k.beam((x, 0.5, 0.0), (x + 0.05, 0.62, 1.9), 0.04, 0.04, "RG_Timber", jit(k, WOOD))
        k.prism([(-0.05, 0), (0.05, 0), (0, 0.25)], 0.02, (x + 0.05, 0.62, 1.9), "RG_Iron", IRON)
    k.box((0.8, 0.5, 0.45), (0.9, 1.4, 0.23), "RG_Planks", (0.7, 0.45, 0.35), grain=0)
    k.box((0.84, 0.54, 0.06), (0.9, 1.4, 0.47), "RG_Iron", (0.9, 0.8, 0.5))


def bandit_palisade(k, lod):
    """4 m sharpened-log palisade section (x = -2..2), with a cross rail behind."""
    n = 13 if lod == 0 else 7
    for i in range(n):
        x = -2 + 4 * (i + 0.5) / n
        h = 2.6 + k.rng.uniform(-0.25, 0.25)
        r = 4 / n / 2 * 0.95
        k.tube([(x, 0, -0.2), (x, 0, h), (x, 0, h + 0.35)], [r, r, 0.02], "RG_Log", jit(k, WOOD, 0.1),
               segs=6 if lod == 0 else 4, bark=0, tip=True, cap_start=False)
    for z in (0.7, 1.9):
        log_beam(k, (-2.05, 0.2, z), (2.05, 0.2, z), 0.07, lod)


# ============================================================================ goblin totems
def skull(k, c, s=1.0, lod=0, horns=True):
    c = Vector(c)
    k.lathe([(0.0, -0.12 * s), (0.14 * s, -0.1 * s), (0.17 * s, 0.03 * s), (0.13 * s, 0.14 * s), (0.0, 0.18 * s)],
            tuple(c), "RG_Plaster", BONE, segs=8 if lod == 0 else 5)
    k.box((0.2 * s, 0.14 * s, 0.1 * s), tuple(c + Vector((0, -0.12 * s, -0.12 * s))), "RG_Plaster", BONE)
    for sx in (-1, 1):
        k.box((0.06 * s, 0.03 * s, 0.06 * s), tuple(c + Vector((sx * 0.06 * s, -0.16 * s, 0.02 * s))), "RG_Timber", HOLE)
        if horns and lod == 0:
            pts = [c + Vector((sx * (0.12 + 0.12 * t) * s, 0.02 * s, (0.08 + 0.25 * t - 0.12 * t * t) * s))
                   for t in (0, 0.4, 0.8, 1.2)]
            k.tube(pts, [0.04 * s, 0.03 * s, 0.018 * s, 0.005], "RG_Plaster", (0.55, 0.47, 0.38), segs=5, tip=True,
                   cap_start=False)


def goblin_totem_a(k, lod):
    """3.4 m carved pole: painted face bands, rag streamers, horned skull on top."""
    H = 3.2
    k.tube([(0, 0, -0.3), (0.03, 0, H * 0.5), (-0.02, 0, H)], [0.2, 0.18, 0.15], "RG_Log", jit(k, WOOD), segs=8 if lod == 0 else 5,
           bark=0)
    for z, c in ((1.0, hexc("9e2f25")), (1.9, hexc("d6a13a")), (2.6, hexc("9e2f25"))):
        k.cyl(0.215, 0.18, (0, 0, z), "RG_Canvas", c, segs=8 if lod == 0 else 5, caps=(False, False))
    # carved face: brow, eyes, teeth
    k.box((0.32, 0.08, 0.08), (0, -0.19, 1.55), "RG_Timber", WOOD_DK)
    for sx in (-1, 1):
        k.box((0.08, 0.04, 0.08), (sx * 0.08, -0.2, 1.45), "RG_Glow", (0.5, 0.9, 0.3))
    k.box((0.24, 0.04, 0.12), (0, -0.2, 1.25), "RG_Timber", HOLE)
    if lod == 0:
        for sx in (-0.07, 0.0, 0.07):
            k.prism([(-0.025, 0), (0.025, 0), (0, -0.06)], 0.03, (sx, -0.22, 1.3), "RG_Plaster", BONE)
    skull(k, (0, -0.02, H + 0.15), 1.2, lod)
    # crossbar with hanging rags and bones
    k.beam((-0.7, 0, 2.3), (0.7, 0, 2.35), 0.08, 0.08, "RG_Timber", jit(k, WOOD_DK))
    for x, c in ((-0.6, hexc("7a3a2a")), (0.55, hexc("4d5a3a"))):
        k.sheet(((x - 0.12, -0.02, 2.3), (x + 0.12, -0.02, 2.3), (x - 0.1, -0.08, 1.5), (x + 0.14, -0.05, 1.45)), 1,
                2 if lod == 0 else 1, "RG_Canvas", tint=c, sag_fn=lambda u, v: (0.05 * math.sin(v * 3), 0, 0))
    if lod == 0:
        for x in (-0.3, 0.3):
            k.beam((x, 0, 2.3), (x, 0, 1.9), 0.01, 0.01, "RG_Hay", (0.7, 0.6, 0.45), up=(1, 0, 0))
            k.beam((x - 0.08, 0, 1.88), (x + 0.08, 0, 1.84), 0.04, 0.04, "RG_Plaster", BONE)
        for i in range(4):   # rock cairn at the foot
            a = i / 4 * math.tau
            S.crag(k, (math.cos(a) * 0.35, math.sin(a) * 0.35, 0), (0.22, 0.2, 0.18), 400 + i, mat="RG_Cliff",
                   tint=(0.75, 0.72, 0.68), lod=1, cuts=5, subdiv=1)


def goblin_totem_b(k, lod):
    """Bone gate marker: two crooked poles with a skull-hung lintel (2.8 m)."""
    for x in (-1.0, 1.0):
        k.tube([(x, 0, -0.3), (x + 0.1 * x, 0, 1.4), (x - 0.05, 0, 2.6)], [0.13, 0.11, 0.08], "RG_Log", jit(k, WOOD, 0.1),
               segs=6 if lod == 0 else 4, bark=0)
        skull(k, (x - 0.05, -0.02, 2.75), 0.9, lod, horns=True)
    k.tube([(-1.3, 0, 2.35), (0, 0, 2.2), (1.3, 0, 2.4)], [0.08, 0.08, 0.08], "RG_Log", jit(k, WOOD_DK),
           segs=5 if lod == 0 else 4, bark=0)
    for i, x in enumerate((-0.5, 0.0, 0.5) if lod == 0 else (0.0,)):
        k.beam((x, 0, 2.25), (x, 0, 1.75 - 0.15 * (i % 2)), 0.01, 0.01, "RG_Hay", (0.7, 0.6, 0.45), up=(1, 0, 0))
        skull(k, (x, 0, 1.6 - 0.15 * (i % 2)), 0.6, lod, horns=False)
    for x in (-0.75, 0.75):
        k.sheet(((x - 0.1, -0.05, 2.3), (x + 0.1, -0.05, 2.3), (x - 0.12, -0.08, 1.7), (x + 0.12, -0.08, 1.65)), 1, 1,
                "RG_Canvas", tint=hexc("8a3326"))
    k.markers = [("warning", Vector((0, 0, 0)))]


ASSETS = {
    "collapsed_tower": (collapsed_tower, 8000, 2400, dict(cam=(1.0, -1.5, 0.6))),
    "overgrown_shrine": (overgrown_shrine, 5000, 1500, {}),
    "bandit_tent": (bandit_tent, 1500, 500, {}),
    "bandit_lean_to": (bandit_lean_to, 1500, 500, {}),
    "campfire": (campfire, 2000, 600, {}),
    "bandit_stash": (bandit_stash, 3000, 1000, {}),
    "bandit_palisade": (bandit_palisade, 1500, 500, {}),
    "goblin_totem_a": (goblin_totem_a, 2000, 600, {}),
    "goblin_totem_b": (goblin_totem_b, 2000, 600, {}),
}

run_set("ruins", ASSETS, "RISING ASHES - REGION 1 RUINS + HIDDEN PLACES  (TRIS LOD0 / LOD1)")
