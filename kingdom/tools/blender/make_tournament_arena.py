"""Tournament Arena / Colosseum (Valencious Regional Landmark)
A grand stone amphitheatre for martial tournaments, knightly duels, and combat trials.
Features:
- Sunken circular sandy combat ring (18m diameter) with heavy timber-and-iron safety barrier
- Concentric tiered stone spectator seating steps with carved timber benches
- Elevated Royal Patron Box with velvet canopy roof, golden thrones, and heraldic banners
- Dual gladiator/combatant arched entry gates with iron portcullises and torch sconces
- 4 perimeter watch turrets with crenellated battlements and tournament pennant poles
- Training dummies, weapon racks (practice swords, lances, shields), and water barrels

Run:
    blender -b --python kingdom/tools/blender/make_tournament_arena.py
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, WALLSTONE, LIMESTONE, DRESSED
from ra_kit import hexc, vary, mix

k = TK("ArenaColosseum", seed=8008, pal=palette(stone="grey", roof="slate_blue", accent="mustard"))
k.p["stone"] = WALLSTONE
MA, W, MT, CL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Cloth")
k.grime = 1.8
k.grime_amt = 0.25

CRIMSON = hexc("8b1e1e")
GOLD = hexc("d4af37")
NAVY = hexc("1e3d59")
SAND = hexc("c4aa7d")
TIMBER_DARK = hexc("4a2d18")

def banner(x, y, ztop, w=1.2, h=3.6, cloth=CRIMSON, trim=GOLD):
    """Hanging heraldic tournament banner."""
    k.cyl(0.04, w + 0.2, (x - (w + 0.2) / 2, y, ztop), MT, IRON, rot=(0, math.pi / 2, 0), segs=6)
    pts = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, -h), (0.0, -h + 0.6), (-w / 2, -h)]
    k.prism(pts, 0.03, (x, y - 0.02, ztop), CL, cloth, var=0.02)
    # Trim & emblem
    k.prism([(-w / 2 + 0.06, -0.1), (w / 2 - 0.06, -0.1), (w / 2 - 0.06, -0.2), (-w / 2 + 0.06, -0.2)], 0.02,
            (x, y - 0.04, ztop), CL, trim, var=0)

# ============================================================================ 1. Central Sand Combat Pit
k.stage("sand_pit")
R_PIT = 9.0
SEGS = 32
# Sand arena floor
k.cyl(R_PIT, 0.2, (0, 0, 0.1), MA, SAND, segs=SEGS)

# Inner timber-and-iron barrier fence (radius R_PIT, height 1.6m)
for i in range(SEGS):
    a0 = i / SEGS * math.tau
    a1 = (i + 1) / SEGS * math.tau
    # Skip entrances at East (a ~ 0) and West (a ~ pi)
    if abs(math.sin(a0)) < 0.18:
        continue
    x0, y0 = math.cos(a0) * R_PIT, math.sin(a0) * R_PIT
    x1, y1 = math.cos(a1) * R_PIT, math.sin(a1) * R_PIT
    # Heavy timber post
    k.box((0.2, 0.2, 1.8), (x0, y0, 0.9), W, TIMBER_DARK)
    # Horizontal wooden rails
    dx, dy = x1 - x0, y1 - y0
    dist = math.hypot(dx, dy)
    ang = math.atan2(dy, dx)
    for zh in (0.5, 1.0, 1.5):
        k.box((dist, 0.08, 0.12), ((x0 + x1) / 2, (y0 + y1) / 2, zh), W, vary(TIMBER_DARK, 0.05), rot=(0, 0, ang))
    # Vertical iron reinforcing bars
    for ib in (0.33, 0.66):
        k.cyl(0.02, 1.6, (x0 + dx * ib, y0 + dy * ib, 0.8), MT, IRON, segs=5)

# ============================================================================ 2. Spectator Amphitheatre Tiers
k.stage("tiers")
TIERS = 4
R_START = 9.5
TIER_RISE = 0.65
TIER_RUN = 1.35

for t in range(TIERS):
    r_inner = R_START + t * TIER_RUN
    r_outer = r_inner + TIER_RUN
    z_base = (t + 1) * TIER_RISE
    # Curved stone tier
    k.ring(r_inner, r_outer, TIER_RISE, (0, 0, z_base - TIER_RISE / 2), MA, vary(WALLSTONE[t % len(WALLSTONE)], 0.04), segs=SEGS)
    # Spectator wooden benches along tier
    for i in range(SEGS):
        a = (i + 0.5) / SEGS * math.tau
        # Avoid gate passages and Royal Box
        if abs(math.sin(a)) < 0.22 or (math.sin(a) > 0.7):
            continue
        rb = (r_inner + r_outer) / 2
        bx, by = math.cos(a) * rb, math.sin(a) * rb
        k.box((1.1, 0.35, 0.08), (bx, by, z_base + 0.35), W, vary(TIMBER_DARK, 0.08), rot=(0, 0, a + math.pi / 2))
        k.box((0.08, 0.3, 0.35), (bx - math.sin(a) * 0.45, by + math.cos(a) * 0.45, z_base + 0.17), MT, IRON)
        k.box((0.08, 0.3, 0.35), (bx + math.sin(a) * 0.45, by - math.cos(a) * 0.45, z_base + 0.17), MT, IRON)

# ============================================================================ 3. Outer Stone Perimeter Wall
k.stage("outer_wall")
R_OUTER = R_START + TIERS * TIER_RUN + 0.5   # ~15.5m
H_WALL = (TIERS + 1) * TIER_RISE + 1.4       # ~4.6m
k.ring(R_OUTER - 0.7, R_OUTER, H_WALL, (0, 0, H_WALL / 2), MA, k.stone(), segs=SEGS)

# Outer wall walkway & crenellations
k.ring(R_OUTER - 1.2, R_OUTER, 0.18, (0, 0, H_WALL + 0.09), MA, DRESSED, segs=SEGS)
for i in range(SEGS * 2):
    if i % 2 == 0:
        a = i / (SEGS * 2) * math.tau
        mx, my = math.cos(a) * (R_OUTER - 0.2), math.sin(a) * (R_OUTER - 0.2)
        k.box((0.7, 0.4, 0.75), (mx, my, H_WALL + 0.45), MA, k.stone(), rot=(0, 0, a + math.pi / 2))

# 4 Corner Turret Towers at quadrants
for i in range(4):
    ang = i * math.pi / 2 + math.pi / 4
    tx = math.cos(ang) * (R_OUTER + 0.3)
    ty = math.sin(ang) * (R_OUTER + 0.3)
    # Turret cylinder
    k.cyl(2.0, H_WALL + 2.5, (tx, ty, (H_WALL + 2.5) / 2), MA, k.stone(), segs=16)
    # Turret battlements
    k.ring(1.8, 2.3, 0.9, (tx, ty, H_WALL + 2.5 + 0.45), MA, DRESSED, segs=16)
    # Pennant pole
    k.cyl(0.04, 3.5, (tx, ty, H_WALL + 2.5 + 2.65), MT, IRON, segs=6)
    banner(tx, ty, H_WALL + 2.5 + 4.0, w=0.9, h=2.2, cloth=CRIMSON if i % 2 == 0 else NAVY, trim=GOLD)

# ============================================================================ 4. Royal / High Patron Box
k.stage("royal_box")
# Elevated north box overlooking combat ring
BOX_Y = 11.5
BOX_W = 6.0
BOX_D = 3.5
BOX_H = (TIERS + 1) * TIER_RISE + 0.4  # ~3.65m

# Supporting stone plinth
k.box((BOX_W, BOX_D, BOX_H), (0, BOX_Y, BOX_H / 2), MA, k.stone())
# Carved balustrade
k.box((BOX_W + 0.2, 0.25, 0.8), (0, BOX_Y - BOX_D / 2, BOX_H + 0.4), MA, DRESSED)
k.box((0.25, BOX_D, 0.8), (-BOX_W / 2, BOX_Y, BOX_H + 0.4), MA, DRESSED)
k.box((0.25, BOX_D, 0.8), (BOX_W / 2, BOX_Y, BOX_H + 0.4), MA, DRESSED)

# 4 Fluted pillars supporting the canopy
for px in (-BOX_W / 2 + 0.3, BOX_W / 2 - 0.3):
    for py in (BOX_Y - BOX_D / 2 + 0.3, BOX_Y + BOX_D / 2 - 0.3):
        k.cyl(0.18, 2.8, (px, py, BOX_H + 1.4), MA, DRESSED, segs=8)

# Canopy roof (pitched cloth with gold trim)
ROOF_Z = BOX_H + 2.8
k.box((BOX_W + 0.8, BOX_D + 0.6, 0.2), (0, BOX_Y, ROOF_Z), W, TIMBER_DARK)
# Cloth canopy overhang
pts_canopy = [
    (-(BOX_W + 0.8) / 2, -(BOX_D + 0.6) / 2), ((BOX_W + 0.8) / 2, -(BOX_D + 0.6) / 2),
    ((BOX_W + 0.8) / 2, (BOX_D + 0.6) / 2), (-(BOX_W + 0.8) / 2, (BOX_D + 0.6) / 2)
]
k.box((BOX_W + 0.6, BOX_D + 0.4, 0.4), (0, BOX_Y, ROOF_Z + 0.3), CL, CRIMSON)

# Royal Thrones (center of box)
for sx in (-0.7, 0.7):
    k.box((0.7, 0.6, 0.5), (sx, BOX_Y + 0.2, BOX_H + 0.25), W, TIMBER_DARK)
    k.box((0.7, 0.12, 0.9), (sx, BOX_Y + 0.5, BOX_H + 0.7), W, TIMBER_DARK)
    # Velvet seat cushion
    k.box((0.6, 0.5, 0.1), (sx, BOX_Y + 0.2, BOX_H + 0.55), CL, CRIMSON)

# Large royal heraldry banners flanking the Royal Box
banner(-BOX_W / 2 - 0.4, BOX_Y - BOX_D / 2, ROOF_Z + 0.2, w=1.4, h=4.2, cloth=CRIMSON, trim=GOLD)
banner(BOX_W / 2 + 0.4, BOX_Y - BOX_D / 2, ROOF_Z + 0.2, w=1.4, h=4.2, cloth=NAVY, trim=GOLD)

# ============================================================================ 5. Fighter Entry Gate Portals
k.stage("gates")
# East and West gladiator entry tunnels
for sx in (-1, 1):
    gx = sx * 12.0
    # Tunnel archway through the seating tiers
    k.box((4.0, 3.2, 3.0), (gx, 0, 1.5), MA, k.stone())
    # Arch opening
    k.box((2.4, 3.4, 2.4), (gx, 0, 1.2), MA, vary(hexc("1a1816"), 0.05))
    # Iron portcullis grate (raised)
    for px in (-0.8, -0.4, 0.0, 0.4, 0.8):
        k.cyl(0.03, 2.6, (gx + px, 0, 2.0), MT, IRON, segs=6)
    for pz in (1.2, 1.8, 2.4):
        k.box((2.0, 0.04, 0.06), (gx, 0, pz), MT, IRON)
    # Torches on gate pillars
    k.cyl(0.04, 0.6, (gx - 1.4, -1.7, 2.1), MT, IRON)
    k.cyl(0.04, 0.6, (gx + 1.4, -1.7, 2.1), MT, IRON)

# ============================================================================ 6. Arena Props & Stalls
k.stage("props")
# Weapon racks inside combat pit near gates
for sx in (-1, 1):
    wx = sx * 7.5
    # Weapon rack stand
    k.box((1.6, 0.4, 1.2), (wx, -2.5, 0.6), W, TIMBER_DARK)
    # Practice swords & spears
    k.cyl(0.03, 1.8, (wx - 0.4, -2.5, 0.9), MT, IRON, rot=(0.1, 0, 0), segs=5)
    k.cyl(0.03, 1.8, (wx, -2.5, 0.9), MT, IRON, rot=(-0.1, 0, 0), segs=5)
    k.cyl(0.03, 2.2, (wx + 0.4, -2.5, 1.1), W, TIMBER_DARK, rot=(0.1, 0, 0), segs=5)
    # Training wooden dummy
    k.cyl(0.12, 1.6, (wx, 2.5, 0.8), W, TIMBER_DARK, segs=8)
    k.box((0.8, 0.15, 0.15), (wx, 2.5, 1.2), W, TIMBER_DARK)
    # Water barrel
    k.cyl(0.4, 0.9, (wx + 0.8, 2.2, 0.45), W, vary(TIMBER_DARK, 0.08), segs=10)

# Output target
OUT_GLB = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "generated", "arena_colosseum.glb")
OUT_PREV = os.path.join(os.path.dirname(__file__), "..", "..", "..", "docs", "kingdom", "blender_previews", "arena_colosseum_a.png")

os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
os.makedirs(os.path.dirname(OUT_PREV), exist_ok=True)

# Build and export checked (36m footprint, 38k budget)
k.finish_checked((38.0, 38.0), 40000, cam_dir=(1.2, -1.4, 0.85), fit=0.92)
