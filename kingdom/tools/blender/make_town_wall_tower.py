"""Town wall tower: a round, slightly battered rubble tower with a chamfered
plinth, arrow slits on three levels, an arched ground-floor door on the town
side, arched wall-walk doors on both flanks (where the curtain walls meet it),
a corbelled, overhanging top storey with small windows and a conical slate
roof with an iron finial and pennant.

Run: python3 make_town_wall_tower.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Tower radius 3.05 m at the ground (6.1 m diameter,
plinth 6.4 m), 2.9 m at the corbels; upper storey radius 3.15 m; roof eave
radius 3.55 m; roof apex 11.9 m, finial tip ~12.9 m. Origin at ground centre.
The field side (-Y, Godot +Z) is the front; the ground door faces +Y (town).
Wall-walk doors sit on +X and -X at z=5.2, matching town_wall.glb's walk:
end a town_wall run 2.6 m from the tower centre (the wall's 2.4 m body then
tucks into the drum).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, WALLSTONE, arch_hole, rect_hole
from ra_kit import hexc, vary, mix

k = TK("TownWallTower", seed=311, pal=palette(stone="grey", roof="slate_blue", accent="oxblood", door="natural"))
k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=3, ao_dist=0.9,
         tint_override={"paving": (0.70, 0.60, 0.47), "stone": (0.70, 0.60, 0.47)})   # high-to-low PBR bake (pbr_kit.py)
k.weather_ao = 0.34
k.p["stone"] = WALLSTONE
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 1.4
k.grime_amt = 0.28
R0, R1 = 3.05, 2.9          # drum radius at ground / at the corbels
Z_PL, Z_TOP = 0.7, 7.5
RU, ZU0, ZU1 = 3.15, 7.55, 8.75
START = math.radians(60)    # masonry seam direction (hidden between features)


def rad(z):
    return R0 + (R1 - R0) * (z / Z_TOP)


def st():
    c = k.stone()
    if random.random() < 0.05:
        c = mix(c, hexc("5d6b3e"), 0.35)
    return c


def U(ang, r):
    return k.ang_u(r, ang, START)


# ---------------------------------------------------------------- plinth + drum
k.cyl(R0 + 0.1, Z_PL, (0, 0, 0), MA, MORTAR, segs=20, var=0, smooth=None, grime=False)
k.stone_ring(0, 0, R0 + 0.22, 0.0, Z_PL, r_top=R0 + 0.12, bw=0.9, bh=0.35, rows=2, start=START,
             color_fn=lambda: mix(st(), MORTAR, 0.12))
k.cyl(R0 - 0.4, Z_TOP, (0, 0, 0), MA, MORTAR, segs=20, var=0, smooth=None, grime=False, r2=R1 - 0.4)
rr_c = rad(Z_PL)
ring_polys = []
for i in range(26):   # chamfered weathering course on the plinth
    a0, a1 = i * math.tau / 26 + 0.004, (i + 1) * math.tau / 26 - 0.004
    ro, ri = R0 + 0.24, rr_c - 0.02
    zb, zt = Z_PL - 0.02, Z_PL + 0.16
    P = lambda a, r, z: (math.cos(a) * r, math.sin(a) * r, z)
    ring_polys.append(((P(a0, ro, zb), P(a1, ro, zb), P(a1, ri, zt), P(a0, ri, zt)), vary(k.dressed(0.28), 0.05)))
k.quads([p for p, c in ring_polys], [c for p, c in ring_polys], MA)

DOOR_W, DOOR_H = 1.3, 2.6
WDOOR_W, WDOOR_H = 1.05, 2.15
WALK = 5.2
holes = [arch_hole(U(math.pi / 2, R0), DOOR_W, -1.0, DOOR_H - DOOR_W / 2 - Z_PL, ring=0.3)]
for ang in (0.0, math.pi):
    holes.append(arch_hole(U(ang, R0), WDOOR_W, WALK - Z_PL, WALK + WDOOR_H - WDOOR_W / 2 - Z_PL, ring=0.3))
SLITS = [(-math.pi / 2, 1.6), (-math.pi / 2 - 0.9, 3.4), (-math.pi / 2 + 0.9, 3.4), (-math.pi / 2, 5.3),
         (math.radians(130), 2.2), (math.radians(40), 2.2), (-math.pi / 2 - 1.7, 5.6), (-math.pi / 2 + 1.7, 5.6)]
for ang, z in SLITS:
    u = U(ang, R0)
    holes.append(rect_hole(u - 0.35, z - 0.2 - Z_PL, u + 0.35, z + 1.2 - Z_PL))
k.stone_ring(0, 0, rad(Z_PL), Z_PL, Z_TOP, r_top=R1, holes=holes, bw=0.78, bh=0.42, rows=16, start=START,
             color_fn=st)
for ang, z in SLITS:
    k.push((math.cos(ang) * (rad(z) - 0.02), math.sin(ang) * (rad(z) - 0.02), 0), (0, 0, ang + math.pi / 2))
    k.slit(0, z, h=1.0)
    k.pop()

# ---------------------------------------------------------------- doors
k.push((0, R0 - 0.03, 0), (0, 0, math.pi))
k.door(0, w=DOOR_W, h=DOOR_H, z0=0.0, depth=0.3, arch=True, stone=True, step=True, color=hexc("6e4126"))
k.pop()
for ang in (0.0, math.pi):
    r = rad(WALK) - 0.03
    k.push((math.cos(ang) * r, math.sin(ang) * r, 0), (0, 0, ang + math.pi / 2))
    k.door(0, w=WDOOR_W, h=WDOOR_H, z0=WALK, depth=0.3, arch=True, stone=True, step=False, color=hexc("5e3a22"),
           detail=0)
    k.pop()

# ---------------------------------------------------------------- corbels + top storey
k.corbels(0, 0, R1 - 0.05, Z_TOP + 0.02, 22, drop=0.7, out=0.42, w=0.34)
k.cyl(RU - 0.18, ZU1 - Z_TOP + 0.1, (0, 0, Z_TOP - 0.05), MA, MORTAR, segs=20, var=0, smooth=None, grime=False)
# underside of the overhang
k.cyl(RU + 0.02, 0.1, (0, 0, ZU0 - 0.1), MA, mix(WALLSTONE[0], MORTAR, 0.4), segs=22, var=0, smooth=None,
      grime=False)
WIN = [(-math.pi / 2, 0.55), (-math.pi / 2 - 1.2, 0.55), (-math.pi / 2 + 1.2, 0.55), (math.pi / 2 + 0.6, 0.55),
       (math.pi / 2 - 0.6, 0.55)]
uholes = []
for ang, w in WIN:
    u = U(ang, RU)
    uholes.append(rect_hole(u - w / 2, 0.25, u + w / 2, 0.95))
k.stone_ring(0, 0, RU, ZU0, ZU1, holes=uholes, bw=0.7, bh=0.4, rows=3, start=START, color_fn=st, grime=False)
for ang, w in WIN:
    k.push((math.cos(ang) * RU, math.sin(ang) * RU, 0), (0, 0, ang + math.pi / 2))
    k.quad(w, 0.7, (0, 0.14, ZU0 + 0.6), MA, hexc("1f1c1a"), var=0, grime=False)
    k.box((w + 0.28, 0.16, 0.1), (0, -0.04, ZU0 + 0.2), MA, k.dressed(0.3), var=0, grime=False)
    k.box((w + 0.28, 0.14, 0.14), (0, -0.03, ZU0 + 1.02), MA, k.dressed(0.3), var=0, grime=False)
    for sx in (-1, 1):
        k.box((0.12, 0.13, 0.72), (sx * (w / 2 + 0.06), -0.03, ZU0 + 0.6), MA, k.dressed(0.3), var=0, grime=False)
    k.pop()
# wall plate under the roof
k.cyl(RU + 0.05, 0.16, (0, 0, ZU1 - 0.02), W, k.timber(), segs=22, var=0, smooth=None, grime=False)

# ---------------------------------------------------------------- roof
RE, ZE, RH = 3.6, ZU1 + 0.05, 3.15
apex = k.cone_roof(0, 0, RE, ZE, RH, k.M("Roof"), k.tile, tile_w=0.46, course=0.34, th=0.03)
k.cyl(0.16, 0.35, (0, 0, apex - 0.35), MT, IRON, segs=8, r2=0.06)
k.cyl(0.035, 1.0, (0, 0, apex - 0.1), MT, IRON, segs=6)
k.sphere(0.08, (0, 0, apex + 0.3), MT, hexc("b08a3a"), subdiv=1, grime=False)
k.banner_pole(0, 0, apex + 0.25, h=0.8, color=hexc("7a2e26"), trim=hexc("c9a24a"), rz=-0.4, flag_len=0.9,
              flag_h=0.45, wave=0.08)

# ---------------------------------------------------------------- grass at the foot
GR = [hexc("5f8a3e"), hexc("6f9448"), hexc("7f9a50"), hexc("4f7a34")]
for i in range(14):
    a = random.uniform(0, math.tau)
    for j in range(4):
        b = a + random.uniform(-0.05, 0.05)
        rr = R0 + 0.3 + random.uniform(0, 0.15)
        k.cyl(random.uniform(0.014, 0.024), random.uniform(0.15, 0.4), (math.cos(b) * rr, math.sin(b) * rr, 0.0), PL,
              vary(random.choice(GR), 0.1), segs=3, r2=0.0,
              rot=(random.uniform(-0.4, 0.4), random.uniform(-0.4, 0.4), b), grime=False, smooth=None, caps=False)

k.finish_checked((7.6, 7.6), 15000, cam_dir=(1.0, -1.5, 0.55), fit=0.95)
