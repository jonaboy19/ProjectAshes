"""Adventurer Guild hall (hero building, concept_guild.png): two storeys, a
dressed-stone ground floor with an arched double door up steps from a raised
stone terrace (planters along its wall), a jettied half-timbered upper floor, a
blue slate roof with a front cross gable (round window), two dormers, finials
and two stone chimneys, blue guild banners with a gold compass star, lanterns,
a hanging banner sign on an iron bracket, a shield-and-swords sign and a quest
board on the terrace. Chimney tops carry empties chimney_top, chimney_top_2.

Run: python3 make_adventurer_guild.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Walls 14.0 m (X) x 10.0 m (Y) at ground level (upper
floor overhangs 0.35 m front/back, roof eaves ~0.6 m, terrace + steps 1.5 m
out front, chimney 0.9 m out on +X). Ridge ~11.5 m, chimney top ~12.6 m. Origin at ground
centre; floor level (door threshold) at z=0.5 on a stone plinth.
Front (main doors, sign) faces Blender -Y = Godot +Z. Door opening: x in
[-1.1, 1.1], front wall face at y=-5.0.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ra_kit import Kit, hexc, vary, mix
from village_kit import VK, palette

k = VK("AdventurerGuild", seed=41, pal=palette(plaster="cream", timber="oak", accent="blue", roof="slate_blue",
                                                  stone="warm", door="natural", box="natural"))
k.lit_ratio = 0.55
MATTE = k.material("Matte", rough=0.92)          # stone, plaster, cloth
WOOD = k.material("Wood", rough=0.72)
ROOF = k.material("Roof", rough=0.68, spec=0.5)
METAL = k.material("Metal", rough=0.38, metal=1.0)
GLASS = k.material("Glass", rough=0.12, metal=0.2, emission=hexc("ffb060"), strength=0.1, spec=0.8)
LIT = k.M("WindowLit")
ROYAL = hexc("2c4f96")

STONES = [hexc("c6b394"), hexc("b4a080"), hexc("d4c4a3"), hexc("a99776"), hexc("cab08a"), hexc("bba583")]
def stone():
    c = random.choice(STONES)
    if random.random() < 0.08:
        c = mix(c, hexc("6f7a5a"), 0.35)       # a mossy block
    return vary(c, 0.1, 0.03)
MORTAR = hexc("3f3b36")
PLASTER = hexc("eadfc6")
TIMBER = hexc("4e3220")
TIMBER2 = hexc("5c3b25")
DOOR = hexc("6e4126")
IRON = hexc("2e2d2c")
GOLD = hexc("d4a63a")
CRIMSON = hexc("9b1d24")
NAVY = hexc("1f3b66")
GLASS_C = hexc("58768e")
SLATES = [hexc("3e5f88"), hexc("4a6d96"), hexc("34547c"), hexc("5a7ca3"), hexc("436690"), hexc("5f84ae"),
          hexc("2f4b70")]
def slate(t):  # noqa: shingle colour, t = 0 at eave .. 1 at ridge
    c = random.choice(SLATES)
    r = random.random()
    if r < 0.06:
        c = mix(c, hexc("6d7f55"), 0.4)
    elif r < 0.14:
        c = mix(c, (0.95, 0.95, 0.95), 0.16)
    return vary(c, 0.12, 0.035)

W, D = 14.0, 10.0
HX, HY = W / 2, D / 2
F0 = 0.5            # floor / plinth top
G1 = 4.2            # top of the stone ground floor
U0, U1 = 4.5, 7.0   # upper floor wall (above the sill band)
J = 0.35            # jetty overhang front/back
PITCH = math.radians(40)
RUN = HY + J + 0.6
RISE = (HY + J) * math.tan(PITCH)
RIDGE = U1 + RISE
EAVE = U1 - 0.6 * math.tan(PITCH)

# ---------------------------------------------------------------- plinth
k.box((W + 0.5, D + 0.5, F0), (0, 0, F0 / 2), MATTE, hexc("7b776f"), bevel=0.06)
k.box((W + 0.62, D + 0.62, 0.12), (0, 0, 0.06), MATTE, hexc("6c6862"), bevel=0.03)
for i in range(3):   # front steps
    w = 3.8 + (2 - i) * 0.5
    k.box((w, 0.4 * (3 - i), 0.167), (0, -HY - 0.25 - 0.2 * (3 - i), 0.167 * (i + 0.5)), MATTE,
          vary(hexc("8b877e"), 0.06), bevel=0.03)

# ---------------------------------------------------------------- ground floor
# Dark core set 0.22 m behind the masonry face: shows as mortar joints and as
# the reveal inside window openings.
k.box((W - 0.44, D - 0.44, G1 - F0), (0, 0, (F0 + G1) / 2), MATTE, MORTAR, var=0)
gh = G1 - F0
DOOR_W, DOOR_SPRING = 2.2, 2.4      # opening width, straight-jamb height above floor
DOOR_R = DOOR_W / 2
gf_front = [-5.6, -3.5, 3.5, 5.6]
gf_side = [-2.8, 0.0, 2.8]
gf_right = [-2.8, -0.2]
gf_back = [-5.2, -1.8, 1.8]
WIN_W, WIN_Z0, WIN_Z1 = 1.1, 1.3, 3.2   # relative to floor F0
def holes_for(xs, extra=()):
    return [(x - WIN_W / 2 - 0.05, WIN_Z0 - 0.05, x + WIN_W / 2 + 0.05, WIN_Z1 + 0.05) for x in xs] + list(extra)
walls = [  # (loc, rotZ, length, window xs, extra holes)
    ((0, -HY, F0), 0.0, W, gf_front, [(-DOOR_R, 0, DOOR_R, DOOR_SPRING + DOOR_R)]),
    ((0, HY, F0), math.pi, W, gf_back, [(-4.3, 0, -3.1, 2.5)]),
    ((HX, 0, F0), math.pi / 2, D, gf_right, [(1.75, 0, 3.45, gh)]),
    ((-HX, 0, F0), -math.pi / 2, D, gf_side, []),
]
for loc, rz, L, xs, extra in walls:
    k.grid_wall(L - 0.1, gh, loc, MATTE, stone, rot=(0, 0, rz), bw=1.1, bh=0.46,
                holes=holes_for(xs, extra), gap=0.03, push=0.035)

# Corner quoins (alternating long/short dressed blocks)
for cx in (-1, 1):
    for cy in (-1, 1):
        for r in range(7):
            z = F0 + (r + 0.5) * gh / 7
            longx = (r % 2 == 0)
            sx, sy = (0.75, 0.42) if longx else (0.42, 0.75)
            k.box((sx, sy, gh / 7 - 0.03), (cx * (HX - sx / 2 + 0.06), cy * (HY - sy / 2 + 0.06), z), MATTE,
                  vary(hexc("b3ab9b"), 0.06), bevel=0.03)


def window(x, z0, w, h, recess, upper=False, shutter_c=None, flowers=False):
    """Window in the current wall frame (face at y=0, outward -Y)."""
    zc = z0 + h / 2
    if k.prng.random() < k.lit_ratio:
        k.quad(w, h, (x, recess - 0.005, zc), LIT, hexc("ffc27a"), var=0.05, grime=False)
    else:
        k.quad(w, h, (x, recess - 0.005, zc), GLASS, GLASS_C, var=0.05, grime=False)
    k.add_sill(x, z0 - 0.08, w + 0.2)
    fd = recess + 0.08   # frame depth
    yc = recess - fd / 2
    ft = 0.09
    for sx in (-1, 1):
        k.box((ft, fd, h + ft), (x + sx * (w / 2 + ft / 2 - 0.01), yc, zc), WOOD, TIMBER)
    k.box((w + ft * 2, fd, ft), (x, yc, z0 + h + ft / 2 - 0.01), WOOD, TIMBER)
    # mullion + transom (leaded panes feel)
    k.box((0.05, 0.05, h), (x, recess - 0.03, zc), WOOD, TIMBER2)
    k.box((w, 0.05, 0.05), (x, recess - 0.03, z0 + h * 0.64), WOOD, TIMBER2)
    if upper:
        k.box((w + 0.3, 0.2, 0.07), (x, -0.1, z0 - 0.03), WOOD, TIMBER2)
        if shutter_c:
            for sx in (-1, 1):
                sc = vary(shutter_c, 0.05)
                cx = x + sx * (w / 2 + ft + w * 0.26)
                k.box((w * 0.5, 0.05, h + 0.05), (cx, -0.06, zc), WOOD, sc)
                k.box((w * 0.5, 0.02, 0.07), (cx, -0.095, z0 + h - 0.2), WOOD, mix(sc, (0, 0, 0), 0.25))
        if not flowers:
            return
        # flower box
        k.box((w + 0.2, 0.26, 0.2), (x, -0.2, z0 - 0.17), WOOD, TIMBER2)
        for i in range(3):
            fx = x - w / 2 + (i + 0.5) * w / 3
            k.sphere(0.2, (fx, -0.2, z0 - 0.02), MATTE, vary(hexc("4f7a34"), 0.15), scale=(1.0, 0.7, 0.6),
                     subdiv=0, noise_amt=0.04, rot=(0, 0, random.uniform(0, 3)))
            bloom = random.choice([hexc("e04f5f"), hexc("f2c14e"), hexc("f5f0e6"), hexc("b05cc9")])
            for j in range(1):
                k.box((0.08, 0.08, 0.08), (fx + random.uniform(-0.08, 0.08), -0.31, z0 + 0.08), MATTE, bloom,
                      rot=(0.6, 0.4, random.uniform(0, 3)))
    else:
        k.box((w + 0.4, recess + 0.18, 0.12), (x, recess / 2 - 0.09, z0 - 0.06), MATTE, hexc("b6ae9e"), bevel=0.025)
        k.box((w + 0.5, 0.3, 0.3), (x, -0.02, z0 + h + 0.15), MATTE, hexc("aaa293"))


# Ground-floor windows
for loc, rz, L, xs, extra in walls:
    k.push(loc, (0, 0, rz))
    for x in xs:
        window(x, WIN_Z0, WIN_W, WIN_Z1 - WIN_Z0, 0.2)
    k.pop()

# ---------------------------------------------------------------- main door
k.push((0, -HY, F0))
R0, R1 = DOOR_R, DOOR_R + 0.5
n_v = 11
for i in range(n_v):   # voussoirs
    a0 = math.pi * i / n_v
    a1 = math.pi * (i + 1) / n_v
    pts = []
    for a in (a0, a1):
        pts.append((math.cos(a) * R0, DOOR_SPRING + math.sin(a) * R0))
    for a in (a1, a0):
        rr = R1 + (0.12 if i == n_v // 2 else 0.0)
        pts.append((math.cos(a) * rr, DOOR_SPRING + math.sin(a) * rr))
    pts = [pts[0], pts[3], pts[2], pts[1]]
    pts = pts[::-1] if False else pts
    k.prism([(p[0], p[1]) for p in (pts[0], pts[1], pts[2], pts[3])], 0.34, (0, 0.12, 0), MATTE,
            vary(hexc("b8b09f") if i != n_v // 2 else hexc("c9c0ab"), 0.05), bevel=0.02)
for sx in (-1, 1):     # jamb blocks
    for r in range(5):
        wid = 0.5 if r % 2 == 0 else 0.38
        k.box((wid, 0.36, DOOR_SPRING / 5 - 0.025), (sx * (R0 + wid / 2), 0.1, (r + 0.5) * DOOR_SPRING / 5), MATTE,
              vary(hexc("b3ab9b"), 0.06))
# Door leaves: vertical planks cut to the arch
n_p = 10
for i in range(n_p):
    x0 = -R0 + i * DOOR_W / n_p
    x1 = x0 + DOOR_W / n_p
    def top(x):
        return DOOR_SPRING + math.sqrt(max(0.0, R0 * R0 - x * x)) - 0.02
    pts = [(x0 + 0.006, 0.0), (x1 - 0.006, 0.0), (x1 - 0.006, top(x1)), (x0 + 0.006, top(x0))]
    if x0 < 0 < x1:
        pts.insert(3, (0.0, top(0.0)))
    k.prism(pts, 0.08, (0, 0.2, 0), WOOD, vary(DOOR, 0.1, 0.04))
k.box((0.05, 0.1, DOOR_SPRING + R0), (0, 0.14, (DOOR_SPRING + R0) / 2), WOOD, mix(DOOR, (0, 0, 0), 0.3))
for zz in (0.5, 1.4, 2.3):   # iron straps with studs
    for sx in (-1, 1):
        k.box((R0 - 0.12, 0.03, 0.09), (sx * (R0 / 2 + 0.02), 0.145, zz), METAL, IRON)
        for j in range(2):
            k.box((0.05, 0.03, 0.05), (sx * (0.3 + j * 0.45), 0.125, zz), METAL, IRON, rot=(0, 0.785, 0))
for sx in (-1, 1):   # ring pulls
    k.cyl(0.11, 0.025, (sx * 0.25, 0.12, 1.25), METAL, GOLD, rot=(math.pi / 2, 0, 0), segs=8, r2=0.11, caps=True)
    k.cyl(0.08, 0.03, (sx * 0.25, 0.11, 1.25), METAL, IRON, rot=(math.pi / 2, 0, 0), segs=8)
# Lanterns flanking the door
for sx in (-1, 1):
    lx = sx * 2.25
    k.box((0.06, 0.4, 0.06), (lx, -0.2, 3.0), METAL, IRON)
    k.box((0.3, 0.3, 0.06), (lx, -0.42, 2.72), METAL, IRON, bevel=0.01)
    k.box((0.22, 0.22, 0.36), (lx, -0.42, 2.5), GLASS, hexc("ffd08a"), var=0)
    k.cyl(0.2, 0.18, (lx, -0.42, 2.75), METAL, IRON, segs=4, r2=0.02, rot=(0, 0, math.pi / 4))
    k.box((0.26, 0.26, 0.05), (lx, -0.42, 2.3), METAL, IRON)
    for dx in (-1, 1):
        for dy in (-1, 1):
            k.box((0.025, 0.025, 0.4), (lx + dx * 0.115, -0.42 + dy * 0.115, 2.5), METAL, IRON)
k.pop()

# Back door
k.push((0, HY, F0), (0, 0, math.pi))
k.box((1.3, 0.08, 2.45), (3.7, 0.2, 1.22), WOOD, DOOR, bevel=0.015)
k.box((1.6, 0.34, 0.25), (3.7, 0.0, 2.6), WOOD, TIMBER, bevel=0.02)
for sx in (-1, 1):
    k.box((0.16, 0.34, 2.5), (3.7 + sx * 0.72, 0.0, 1.25), WOOD, TIMBER, bevel=0.02)
k.pop()

# ---------------------------------------------------------------- jetty + upper floor
k.box((W + 0.3, D + 2 * J + 0.2, 0.3), (0, 0, G1 + 0.15), WOOD, TIMBER, bevel=0.03)   # sill band
for sy in (-1, 1):   # joist ends + curved brackets under the jetty
    for i in range(18):
        x = -HX + 0.4 + i * (W - 0.8) / 17
        k.box((0.16, J + 0.2, 0.16), (x, sy * (HY + J / 2), G1 - 0.08), WOOD, TIMBER2)
    for x in (-5.25, -1.75, 1.75, 5.25):
        k.beam((x, sy * (HY - 0.02), G1 - 0.8), (x, sy * (HY + J - 0.05), G1 - 0.05), 0.16, WOOD, TIMBER, bevel=0)
k.box((W - 0.1, D + 2 * J - 0.1, U1 - U0 + 0.3), (0, 0, (U0 + U1) / 2 - 0.15), MATTE, PLASTER, var=0.02)

def timber_wall(L, posts, win_bays, brace_bays, banner_bays=(), shutter_c=None, flowers=False):
    """Half-timber framing on the current wall frame; wall spans x in [-L/2, L/2]."""
    t = 0.2
    y = -0.04
    k.box((L + 0.1, 0.16, t), (0, y, U0 + t / 2), WOOD, TIMBER, bevel=0.02)            # sole plate
    k.box((L + 0.1, 0.16, t), (0, y, U1 - t / 2 - 0.07), WOOD, TIMBER, bevel=0.02)     # top plate (under the roof deck)
    for x in posts:
        k.box((t, 0.14, U1 - U0 - 2 * t), (x, y, (U0 + U1) / 2), WOOD, vary(TIMBER, 0.1))
    mid = U0 + (U1 - U0) * 0.36
    for i in range(len(posts) - 1):
        a, b = posts[i], posts[i + 1]
        cx = (a + b) / 2
        if i in win_bays:
            window(cx, U0 + 0.7, min(1.0, (b - a) - 0.55), 1.3, -0.02, upper=True, shutter_c=shutter_c, flowers=flowers)
        elif i in brace_bays:
            k.beam((a + t / 2, y, U0 + t), (b - t / 2, y, U1 - t), 0.14, WOOD, TIMBER, bevel=0, width=0.14)
            k.beam((b - t / 2, y, U0 + t), (a + t / 2, y, U1 - t), 0.14, WOOD, TIMBER, bevel=0, width=0.14)
        elif i in banner_bays:
            pass
        else:
            k.box((b - a - t, 0.12, 0.14), (cx, y, mid), WOOD, TIMBER2)
            k.beam((a + t / 2, y, mid), (cx, y, U1 - t), 0.12, WOOD, TIMBER2, bevel=0, width=0.12)
            k.beam((b - t / 2, y, mid), (cx, y, U1 - t), 0.12, WOOD, TIMBER2, bevel=0, width=0.12)

posts_x = [-HX + i * W / 8 for i in range(9)]
posts_y = [-(HY + J) + i * (D + 2 * J) / 6 for i in range(7)]
SHUT = hexc("2f6b73")
k.push((0, -HY - J, 0))
timber_wall(W, posts_x, win_bays=(1, 3, 4, 6), brace_bays=(0, 7), banner_bays=(2, 5), shutter_c=SHUT, flowers=True)
# Banners hanging in bays 2 and 5: royal blue, gold trim, gold compass star
for bx in (posts_x[2] + W / 16, posts_x[5] + W / 16):
    k.banner(bx, U1 - 0.35, w=1.0, h=2.2, color=ROYAL, trim=GOLD, emblem="star", y=-0.22)
k.pop()
k.push((0, HY + J, 0), (0, 0, math.pi))
timber_wall(W, posts_x, win_bays=(1, 3, 4, 6), brace_bays=(0, 7), shutter_c=SHUT)
k.pop()
k.push((HX, 0, 0), (0, 0, math.pi / 2))
timber_wall(D + 2 * J, posts_y, win_bays=(1, 4), brace_bays=(0, 5), shutter_c=SHUT)
k.pop()
k.push((-HX, 0, 0), (0, 0, -math.pi / 2))
timber_wall(D + 2 * J, posts_y, win_bays=(1, 4), brace_bays=(0, 5), shutter_c=SHUT)
k.pop()

# ---------------------------------------------------------------- gables
def gable(half, base_z, rise, depth=0.2):
    """Plaster gable triangle in the current frame (face at y=0) with timbers."""
    k.prism([(-half, 0), (half, 0), (0, rise)], depth, (0, depth / 2 - 0.01, base_z), MATTE, PLASTER, var=0.02)
    y = -0.04
    k.beam((0, y, base_z), (0, y, base_z + rise - 0.1), 0.18, WOOD, TIMBER, bevel=0.015)          # king post
    zc = base_z + rise * 0.45
    hw = half * 0.55
    k.box((hw * 2, 0.14, 0.18), (0, y, zc), WOOD, TIMBER, bevel=0.015)                           # collar
    for sx in (-1, 1):
        k.beam((sx * half * 0.9, y, base_z + 0.1), (sx * hw * 0.6, y, zc), 0.14, WOOD, TIMBER2, bevel=0)
        k.beam((sx * hw * 0.55, y, zc), (sx * 0.12, y, base_z + rise * 0.8), 0.12, WOOD, TIMBER2, bevel=0)

GABLE_H = D / 2 + J
for sx in (-1, 1):
    k.push((sx * HX, 0, 0), (0, 0, sx * math.pi / 2))
    gable(GABLE_H, U1, RISE - 0.02)
    window(0, U1 + 0.5, 0.8, 1.0, -0.02, upper=False)
    k.pop()

# Front cross gable with a round window
CG = 3.0
CG_RISE = CG
k.push((0, -HY - J, 0))
k.prism([(-CG, 0), (CG, 0), (0, CG_RISE)], 0.2, (0, 0.09, U1), MATTE, PLASTER, var=0.02)
k.box((2 * CG + 0.1, 0.16, 0.2), (0, -0.04, U1 + 0.1), WOOD, TIMBER, bevel=0.02)
RW = 0.75
rz = U1 + 1.35
k.cyl(RW, 0.02, (0, 0.0, rz), GLASS, GLASS_C, rot=(math.pi / 2, 0, 0), segs=20, smooth=None)
k.ring(RW - 0.02, RW + 0.16, 0.16, (0, -0.04, rz), WOOD, TIMBER, segs=20)
k.ring(RW + 0.16, RW + 0.3, 0.1, (0, -0.02, rz), MATTE, hexc("b8b09f"), segs=20)
for i in range(4):
    a = i * math.pi / 4
    k.box((2 * RW, 0.05, 0.05), (0, -0.04, rz), WOOD, TIMBER2, rot=(0, a, 0))
k.cyl(0.16, 0.08, (0, -0.02, rz), METAL, GOLD, rot=(math.pi / 2, 0, 0), segs=12)
for sx in (-1, 1):
    k.beam((sx * (CG - 0.3), -0.04, U1 + 0.2), (sx * 1.0, -0.04, U1 + CG_RISE * 0.7), 0.14, WOOD, TIMBER, bevel=0.01)
k.pop()

# ---------------------------------------------------------------- roof
k.push((0, 0, EAVE))
roof_rise = RIDGE - EAVE
k.shingle_side(-HX - 0.7, HX + 0.7, RUN, roof_rise, ROOF, slate, tile_w=(0.7, 1.1), course=0.52, deck_mat=WOOD, deck_color=TIMBER)
k.shingle_side(-HX - 0.7, HX + 0.7, RUN, roof_rise, ROOF, slate, tile_w=(0.7, 1.1), course=0.52, deck_mat=WOOD, deck_color=TIMBER, rot=(0, 0, math.pi))
k.pop()
# cross gable roof (ridge along Y), from its front eave back into the main roof
CG_RUN = CG + 0.45
CG_EAVE = U1 - 0.45
k.push((0, 0, CG_EAVE))
y0, y1 = -HY - J - 0.55, -1.6
k.shingle_side(y0, y1, CG_RUN, U1 + CG_RISE - CG_EAVE, ROOF, slate, tile_w=(0.6, 1.0), course=0.46, deck_mat=WOOD, deck_color=TIMBER, rot=(0, 0, math.pi / 2))
k.shingle_side(-y1, -y0, CG_RUN, U1 + CG_RISE - CG_EAVE, ROOF, slate, tile_w=(0.6, 1.0), course=0.46, deck_mat=WOOD, deck_color=TIMBER, rot=(0, 0, -math.pi / 2))
k.pop()
# ridge caps and barge boards
k.cyl(0.16, W + 1.5, (-HX - 0.75, 0, RIDGE + 0.04), ROOF, hexc("2d3f4b"), rot=(0, math.pi / 2, 0), segs=8)
k.cyl(0.14, -y0 + y1 + 0.2, (0, y0 - 0.05, U1 + CG_RISE + 0.03), ROOF, hexc("2d3f4b"), rot=(-math.pi / 2, 0, 0), segs=8)
for sx in (-1, 1):
    for sy in (-1, 1):
        k.beam((sx * (HX + 0.72), sy * (RUN + 0.05), EAVE - 0.08), (sx * (HX + 0.72), 0, RIDGE + 0.02), 0.14,
               WOOD, TIMBER, bevel=0.02, width=0.3)
    k.beam((sx * (CG_RUN + 0.02), y0 - 0.03, CG_EAVE - 0.08), (0, y0 - 0.03, U1 + CG_RISE + 0.05), 0.14,
           WOOD, TIMBER, bevel=0.02, width=0.3)

# ---------------------------------------------------------------- chimney (on +X wall)
CX, CY = HX + 0.45, 2.6
z = 0.0
r = 0
while z < RIDGE + 1.2:
    h = random.uniform(0.34, 0.46)
    if z < U0:
        sx, sy = 0.95, 1.7
        cx = CX
    elif z < U0 + 1.0:
        f = (z - U0) / 1.0
        sx, sy = 0.95 - 0.1 * f, 1.7 - 0.6 * f
        cx = CX
    else:
        sx, sy = 0.85, 1.1
        cx = CX
    k.box((sx + random.uniform(-0.03, 0.03), sy + random.uniform(-0.03, 0.03), h - 0.02),
          (cx + random.uniform(-0.015, 0.015), CY, z + h / 2), MATTE, stone())
    z += h
    r += 1
k.box((1.05, 1.3, 0.14), (CX, CY, z + 0.07), MATTE, hexc("8f8a80"), bevel=0.03)
for dy in (-0.25, 0.25):
    k.cyl(0.14, 0.45, (CX, CY + dy, z + 0.14), MATTE, hexc("a4553a"), segs=10, r2=0.12)

# ---------------------------------------------------------------- hanging sign
k.push((-2.9, -HY, 0))
SZ = 3.95
k.box((0.3, 0.1, 0.5), (0, -0.05, SZ), METAL, IRON, bevel=0.01)          # wall plate
k.box((0.07, 1.45, 0.07), (0, -0.75, SZ), METAL, IRON)                   # arm
k.beam((0, -0.05, SZ - 0.45), (0, -0.9, SZ - 0.02), 0.05, METAL, IRON, bevel=0)  # strut
k.cyl(0.18, 0.04, (0, -1.1, SZ + 0.16), METAL, IRON, rot=(0, math.pi / 2, 0), segs=10, r2=0.18, caps=False)
k.sphere(0.06, (0, -1.5, SZ), METAL, GOLD, subdiv=0)
for dy in (-0.35, -1.15):
    k.box((0.02, 0.02, 0.32), (0, dy - 0.02, SZ - 0.18), METAL, IRON)
# Shield board in the YZ plane (readable from the street), with crossed swords
k.push((0, -0.77, SZ - 1.05), (0, 0, math.pi / 2))
sh = [(0, -0.58), (0.3, -0.36), (0.45, -0.02), (0.47, 0.34), (0.0, 0.44), (-0.47, 0.34), (-0.45, -0.02), (-0.3, -0.36)]
k.prism([(x * 1.08, z * 1.08 + 0.01) for x, z in sh], 0.08, (0, 0, 0), METAL, GOLD, bevel=0.015)
for side in (-1, 1):
    k.prism(sh, 0.06, (0, side * 0.025, 0), WOOD, NAVY, bevel=0.01)
    k.prism([(-0.36, 0.1), (0.36, 0.1), (0.36, 0.2), (-0.36, 0.2)], 0.02, (0, side * 0.06, 0), METAL, GOLD)
    for s2 in (-1, 1):
        k.sword((s2 * 0.2, side * 0.08, 0.28), (0, s2 * 0.72, 0), METAL, METAL, length=0.95,
                hilt_c=GOLD, grip_c=hexc("3a2214"))
k.pop()
k.pop()

# A couple of barrels and a crate by the door for life
for (bx, by, rr) in ((3.0, -HY - 0.75, 0.35), (3.65, -HY - 0.6, 0.32)):
    k.cyl(rr, 0.95, (bx, by, 0.0), WOOD, vary(hexc("7a5230"), 0.1), segs=10, r2=rr * 0.95)
    k.cyl(rr * 1.06, 0.25, (bx, by, 0.95), WOOD, vary(hexc("7a5230"), 0.1), segs=10, r2=rr * 0.9)
    for hz in (0.15, 0.8):
        k.cyl(rr * 1.03, 0.06, (bx, by, hz), METAL, IRON, segs=10, caps=False)
k.box((0.7, 0.7, 0.6), (-3.3, -HY - 0.7, 0.3), WOOD, hexc("8a6238"), bevel=0.03, rot=(0, 0, 0.2))

# ---------------------------------------------------------------- round-6 dressing
# raised stone terrace in front of the ground floor: low parapet wall with planters, steps up the middle
TY = -HY - 1.25
with k.side("front", HX, 0.0, cy=TY):
    for (x0, x1) in ((-HX + 0.2, -2.3), (2.3, HX - 0.2)):
        L = x1 - x0
        k.box((L - 0.1, 0.4, 0.6), ((x0 + x1) / 2, 0.22, 0.3), MATTE, MORTAR, var=0)
        k.grid_wall(L, 0.62, ((x0 + x1) / 2, 0, 0), MATTE, stone, bw=0.7, bh=0.31, gap=0.03, push=0.03)
        k.box((L + 0.08, 0.5, 0.1), ((x0 + x1) / 2, 0.2, 0.67), MATTE, vary(hexc("b3ab9b"), 0.04), bevel=0.02)
        n = max(1, round(L / 1.6))
        for i in range(n):
            fx = x0 + (i + 0.5) * L / n
            k.planter(fx, 0.22, L=min(1.2, L / n - 0.25), D=0.38, H=0.3, box_c=hexc("6e4b2e"))
    for sx in (-1, 1):   # banner poles on the terrace wall ends by the steps
        k.cyl(0.05, 2.9, (sx * 2.2, 0.2, 0.72), WOOD, TIMBER, segs=6)
        k.sphere(0.08, (sx * 2.2, 0.2, 3.66), METAL, GOLD, subdiv=0, grime=False)
        k.box((0.75, 0.05, 0.05), (sx * 2.2 - sx * 0.3, 0.2, 3.5), METAL, IRON, var=0)
        k.banner(sx * 2.2 - sx * 0.35, 3.45, w=0.55, h=1.35, color=ROYAL, trim=GOLD, emblem="star", y=0.2,
                 rod=False, tail="swallow")
k.box((W - 0.6, 1.3, 0.12), (0, -HY - 0.62, 0.06), k.M("Paving"), vary(hexc("8d877c"), 0.03), var=0)   # terrace paving
# big banners flanking the arched door
k.push((0, -HY, F0))
for sx in (-1, 1):
    for bx in (sx * 1.9, sx * 4.55):
        k.banner(bx, G1 - F0 - 0.25, w=0.85, h=2.0, color=ROYAL, trim=GOLD, emblem="star", y=-0.08)
k.pop()
# quest board on the terrace (left), weather-roofed
QX, QY = -HX + 1.6, -HY - 0.75
k.push((QX, QY, 0.0))
for sx in (-1, 1):
    k.box((0.14, 0.14, 2.2), (sx * 0.8, 0, 1.1), WOOD, TIMBER, bevel=0.015)
k.box((1.5, 0.08, 1.0), (0, 0, 1.45), WOOD, hexc("7a5a3a"), var=0)
with k.detail():
    for i, (px, pz, pw, ph) in enumerate(((-0.45, 1.6, 0.34, 0.42), (0.02, 1.62, 0.3, 0.36), (0.42, 1.52, 0.32, 0.44),
                                          (-0.2, 1.18, 0.3, 0.32), (0.3, 1.14, 0.28, 0.3))):
        k.box((pw, 0.01, ph), (px, -0.05, pz), MATTE, vary(hexc("e8dcb8"), 0.05), rot=(0, (i - 2) * 0.05, 0), var=0)
k.push((0, 0.1, 2.2))
k.shingle_side(-1.0, 1.0, 0.45, 0.2, ROOF, slate, tile_w=(0.25, 0.4), course=0.22, th=0.02, deck_mat=WOOD,
               deck_color=TIMBER)
k.shingle_side(-1.0, 1.0, 0.45, 0.2, ROOF, slate, tile_w=(0.25, 0.4), course=0.22, th=0.02, deck_mat=WOOD,
               deck_color=TIMBER, rot=(0, 0, math.pi))
k.pop()
k.pop()
# dormers either side of the cross gable, finials on the gables
for u in (-4.6, 4.6):
    k.dormer(u, EAVE, RUN, RIDGE - EAVE, cy=0.0, side=-1, w=1.4, wall_h=1.2, inset=1.4, flowers=True)
for sx in (-1, 1):
    k.finial(sx * (HX + 0.72), 0.0, RIDGE + 0.12, h=0.7, color=TIMBER)
k.finial(0.0, y0 - 0.05, U1 + CG_RISE + 0.12, h=0.7, color=TIMBER)
# second (smaller) chimney through the back slope on the -X side
k.chimney(-3.6, 2.4, RIDGE - 2.4 * math.tan(PITCH) - 0.4, RIDGE + 0.9, sx=0.85, sy=0.85, pots=2)
k.add_marker("chimney_top", (CX, CY, z + 0.6))
# lanterns at the terrace steps
for sx in (-1, 1):
    k.box((0.09, 0.09, 1.6), (sx * 2.2, TY + 0.2, 0.72 + 0.8), WOOD, TIMBER)
k.stage("dressing")
k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=21, ao_dist=0.9)   # high-to-low PBR bake (pbr_kit.py)
k.finish_checked((17.0, 14.5), 21800, cam_dir=(1.0, -1.45, 0.62), fit=0.95)
