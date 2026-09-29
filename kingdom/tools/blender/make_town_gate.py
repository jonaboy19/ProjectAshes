"""Town gate: a crenellated gatehouse with an 8 m round-arched cart passage
(barrel vault, dressed voussoirs and jambs), a half-raised oak-and-iron
portcullis, heavy gate leaves swung open against the passage walls, two round
flanking towers with corbelled top storeys and conical slate roofs, the town
arms and banners over the arch, wall-walk doors on both sides and a low hipped
roof behind the parapet.

Run: python3 make_town_gate.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Gatehouse block 9.8 m (X) x 6.0 m (Y); towers r=2.15 m
centred at x=+-5.85, y=-1.5 so the overall width is ~16.9 m and depth ~7 m.
Passage: 8.0 m wide (x in [-4, 4]), 7.2 m high at the crown, 6 m long, clear
headroom under the raised portcullis 4.1 m. Gatehouse walk at z=10, merlons
to 11.8 m, tower finials ~17.5 m. Origin at ground centre of the passage.
Front (field side, portcullis) faces Blender -Y (Godot +Z).
Joining the walls: town_wall.glb sections butt against the gatehouse sides at
x = +-4.9 (their y=0 on the gate's y=0); the wall-walk doors at z=5.2 match
the wall-walk. The flanking towers swallow the first ~3 m of each wall run.
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, arch_hole, rect_hole, arch_top
from ra_kit import hexc, vary, mix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
CROWN = os.path.join(ROOT, "kingdom", "assets", "art", "emblems", "tower_crown.png")

k = TK("TownGate", seed=515, pal=palette(stone="warm", roof="slate_blue", accent="oxblood"))
k.pbr = dict(size=1024, lod1_size=512, orm_div=2, seed=5, ao_dist=1.2,
         tint_override={"paving": (0.70, 0.60, 0.47), "stone": (0.70, 0.60, 0.47)})   # high-to-low PBR bake (pbr_kit.py)
k.weather_ao = 0.34
# warm beige/tan dressed stone (the reference's sunlit gatehouse), not the cool
# grey-green WALLSTONE the fortification kit uses by default
WARM_DRESSED = hexc("dcc79c")
k.dressed = lambda amt=0.35: mix(k.stone(), WARM_DRESSED, amt)
MA, W, MT, PL, CL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant"), k.M("Cloth")
k.grime = 1.5
k.grime_amt = 0.28
HX, HY = 4.9, 3.0
WALK, BREAST, TOP = 10.0, 10.9, 11.8
R, SPRING = 4.0, 3.2
RING = 0.42
CRIMSON, GOLD, NAVY = hexc("8e1f24"), hexc("c9a24a"), hexc("1f3b66")


def st():
    c = k.stone()
    if random.random() < 0.05:
        c = mix(c, hexc("5d6b3e"), 0.35)
    return c


# ---------------------------------------------------------------- core block (hollow over the passage)
for sx in (-1, 1):
    k.box((HX - R - 0.3, 2 * HY - 0.4, WALK), (sx * (R + 0.15 + (HX - R - 0.3) / 2), 0, WALK / 2), MA, MORTAR,
          var=0, grime=False)
k.box((2 * HX - 0.4, 2 * HY - 0.4, WALK - SPRING - R - 0.25), (0, 0, (WALK + SPRING + R + 0.25) / 2), MA, MORTAR,
      var=0, grime=False)
# plinth course
for s in ("front", "back"):
    with k.side(s, HX, HY):
        for sx in (-1, 1):
            k.box((HX - R - 0.2, 0.5, 0.5), (sx * (R + 0.1 + (HX - R - 0.2) / 2), 0.0, 0.25), MA,
                  mix(st(), MORTAR, 0.15), bevel=0.04, var=0)

# ---------------------------------------------------------------- faces
arch = [arch_hole(0, 2 * R, -1.0, SPRING, ring=RING)]
for s in ("front", "back"):
    with k.side(s, HX, HY) as L:
        k.stone_face(L, BREAST, holes=arch, bw=1.0, bh=0.5, rows=22, color_fn=st)
        k.arch_ring(0, SPRING, R, ring=RING + 0.06, depth=0.55, y=0.08, n=17)
        for sx in (-1, 1):       # dressed jambs
            for r in range(7):
                wd = 0.55 if r % 2 == 0 else 0.4
                k.box((wd, 0.5, SPRING / 7 - 0.03), (sx * (R + wd / 2 - 0.02), 0.1, (r + 0.5) * SPRING / 7), MA,
                      k.dressed(0.28), var=0)
        k.box((2 * R + 1.4, 0.2, 0.18), (0, -0.05, WALK - 0.35), MA, k.dressed(0.2), var=0)    # string course
for s in ("left", "right"):
    with k.side(s, HX, HY) as L:
        doors = [arch_hole(0, 1.1, 5.2, 5.2 + 2.15 - 0.55, ring=0.3)]
        k.stone_face(L, BREAST, holes=doors, bw=1.0, bh=0.5, rows=22, color_fn=st)
        k.door(0, w=1.1, h=2.15, z0=5.2, depth=0.3, arch=True, stone=True, step=False, color=hexc("5e3a22"),
               detail=0)

# ---------------------------------------------------------------- passage
for sx in (-1, 1):
    k.push((sx * R, 0, 0), (0, 0, -sx * math.pi / 2))
    k.stone_face(2 * HY - 0.3, SPRING, bw=0.8, bh=0.45, rows=7, color_fn=lambda: mix(st(), MORTAR, 0.1))
    k.pop()
k.vault(0, R, SPRING, -HY + 0.2, HY - 0.2, n=16, nd=6)
k.flagstones(-R, R, -HY - 0.6, HY + 0.6, 0.04, size=(1.1, 0.75),
             color_fn=lambda: vary(mix(random.choice(k.p["stone"]), hexc("6c6862"), 0.45), 0.06))
for sx in (-1, 1):      # cart ruts: darker worn strips
    k.box((0.35, 2 * HY + 1.1, 0.01), (sx * 0.8, 0, 0.055), MA, hexc("4f4a44"), var=0, grime=False)

# portcullis slot grooves + portcullis (raised, teeth at 4.1 m)
PY = -HY + 0.75
top = arch_top(0, R, SPRING)
PB = 4.1
PC = hexc("3a3029")
for sx in (-1, 1):
    k.box((0.12, 0.26, SPRING), (sx * (R - 0.04), PY, SPRING / 2), MA, hexc("1c1a18"), var=0, grime=False)
nv = 11
for i in range(nv):
    x = -R + 0.35 + i * (2 * R - 0.7) / (nv - 1)
    zt = top(x) - 0.03
    k.box((0.14, 0.14, zt - PB), (x, PY, (zt + PB) / 2), W, vary(PC, 0.06), var=0, grime=False)
    k.cyl(0.075, 0.28, (x, PY, PB - 0.26), MT, IRON, segs=4, r2=0.0, rot=(0, 0, math.pi / 4), smooth=None,
          grime=False)
for z in (PB + 0.35, PB + 1.0, PB + 1.65, PB + 2.3, PB + 2.9):
    if z > SPRING + R - 0.2:
        continue
    half = math.sqrt(max(0.0, R * R - (z - SPRING) ** 2)) - 0.06
    k.box((2 * half, 0.1, 0.14), (0, PY - 0.1, z), W, vary(PC, 0.05), var=0, grime=False)
    k.box((2 * half, 0.02, 0.05), (0, PY - 0.155, z), MT, IRON, var=0, grime=False)

# gate leaves, open against the passage walls behind the portcullis
for sx in (-1, 1):
    k.push((sx * (R - 0.14), 0.75, 0), (0, 0, -sx * math.pi / 2))
    LW, LH = 3.9, 3.35
    n = 10
    for i in range(n):
        x0 = -LW / 2 + i * LW / n
        k.box((LW / n - 0.02, 0.12, LH - random.uniform(0, 0.04)), (x0 + LW / n / 2, 0, LH / 2 + 0.06), W,
              vary(hexc("6b4a2f"), 0.1, 0.03), var=0)
    for zz in (0.5, 1.7, 2.9):
        k.box((LW - 0.2, 0.03, 0.14), (0, -0.075, zz), MT, IRON, var=0)
    k.bar((-LW / 2 + 0.2, -0.07, 0.6), (LW / 2 - 0.2, -0.07, 2.8), 0.16, 0.05, W, hexc("5a3e26"), up=(-1, 0, 1),
          bevel=0)
    k.pop()

# ---------------------------------------------------------------- parapet, walk and roof
k.flagstones(-HX + 0.55, HX - 0.55, -HY + 0.55, HY - 0.55, WALK, size=(1.2, 0.8))
for s in ("front", "back", "left", "right"):
    with k.side(s, HX, HY) as L:
        k.push((0, 0.55, 0), (0, 0, math.pi))
        k.stone_face(L - 1.1, BREAST - WALK, loc=(0, 0, WALK), bw=0.8, bh=0.3, rows=3, color_fn=st)
        k.pop()
        k.box((L, 0.62, 0.12), (0, 0.28, BREAST + 0.04), MA, k.dressed(0.25), var=0)
        k.merlons(-L / 2, L / 2, BREAST, h=TOP - BREAST, th=0.55, mw=1.0, cw=0.55, y=-0.03, slits=0.4,
                  start=-L / 2 + 0.5)
k.hip_roof(0, 0, HX - 0.9, HY - 0.9, WALK + 0.55, 2.3, k.M("Roof"), k.tile, over=0.2, tile_w=(0.5, 0.75),
           course=0.45, th=0.03)

# ---------------------------------------------------------------- flanking towers
TR0, TR1, TZ = 2.15, 2.02, 12.0
for sx in (-1, 1):
    cx, cy = sx * 5.85, -1.5
    start = math.atan2(1.5, -sx * 1.0)        # seam faces the gatehouse (hidden)
    k.cyl(TR0 - 0.3, TZ, (cx, cy, 0), MA, MORTAR, segs=16, var=0, smooth=None, grime=False, r2=TR1 - 0.3)
    k.stone_ring(cx, cy, TR0 + 0.14, 0.0, 0.6, r_top=TR0 + 0.08, bw=0.8, bh=0.3, rows=2, start=start,
                 color_fn=lambda: mix(st(), MORTAR, 0.12))
    slits = [(-math.pi / 2, 2.0), (-math.pi / 2 + sx * 0.9, 4.6), (-math.pi / 2, 7.2), (-math.pi / 2 + sx * 1.3, 9.4),
             (math.pi / 2 + sx * 1.0, 6.5)]
    holes = []
    for ang, z in slits:
        u = k.ang_u(TR0, ang, start)
        holes.append(rect_hole(u - 0.35, z - 0.2 - 0.6, u + 0.35, z + 1.2 - 0.6))
    k.stone_ring(cx, cy, TR0, 0.6, TZ, r_top=TR1, holes=holes, bw=0.9, bh=0.5, rows=23, start=start, color_fn=st)
    for ang, z in slits:
        rr = TR0 + (TR1 - TR0) * z / TZ - 0.02
        k.push((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, 0), (0, 0, ang + math.pi / 2))
        k.slit(0, z, h=1.0)
        k.pop()
    k.corbels(cx, cy, TR1 - 0.05, TZ + 0.02, 13, drop=0.6, out=0.36, w=0.34)
    RU = 2.22
    k.cyl(RU - 0.18, 1.2, (cx, cy, TZ - 0.05), MA, MORTAR, segs=16, var=0, smooth=None, grime=False)
    k.cyl(RU + 0.02, 0.1, (cx, cy, TZ - 0.04), MA, mix(k.p["stone"][0], MORTAR, 0.4), segs=18, var=0, smooth=None,
          grime=False)
    uh = []
    for ang in (-math.pi / 2, -math.pi / 2 + sx * 1.4, math.pi / 2 + sx * 0.3):
        u = k.ang_u(RU, ang, start)
        uh.append((ang, rect_hole(u - 0.25, 0.25, u + 0.25, 0.85)))
    k.stone_ring(cx, cy, RU, TZ + 0.05, TZ + 1.1, holes=[h for a, h in uh], bw=0.7, bh=0.35, rows=3, start=start,
                 color_fn=st, grime=False)
    for ang, h in uh:
        k.push((cx + math.cos(ang) * RU, cy + math.sin(ang) * RU, 0), (0, 0, ang + math.pi / 2))
        k.quad(0.5, 0.6, (0, 0.14, TZ + 0.6), MA, hexc("1f1c1a"), var=0, grime=False)
        k.box((0.72, 0.14, 0.1), (0, -0.03, TZ + 0.25), MA, k.dressed(0.25), var=0, grime=False)
        k.pop()
    k.cyl(RU + 0.05, 0.14, (cx, cy, TZ + 1.08), W, k.timber(), segs=18, var=0, smooth=None, grime=False)
    apex = k.cone_roof(cx, cy, 2.55, TZ + 1.18, 3.2, k.M("Roof"), k.tile, tile_w=0.52, course=0.38)
    k.cyl(0.13, 0.3, (cx, cy, apex - 0.3), MT, IRON, segs=8, r2=0.05)
    k.banner_pole(cx, cy, apex - 0.05, h=1.2, color=CRIMSON, trim=GOLD, rz=-0.5, flag_len=1.1, flag_h=0.5,
                  wave=0.1)

# ---------------------------------------------------------------- royal banners over the arch (gold crown on red)
with k.side("front", HX, HY):
    # a stone bracket holding a central red banner (replaces the old cross-and-shield motif)
    k.push((0, -0.1, 8.55))
    k.box((0.16, 0.14, 0.16), (0, 0.02, 0.62), MA, k.dressed(0.4), bevel=0.02, var=0)
    k.box((0.9, 0.045, 0.05), (0, 0.0, 0.62), MT, IRON, var=0)
    for sxx in (-1, 1):
        k.sphere(0.045, (sxx * 0.5, 0.0, 0.62), MT, GOLD, subdiv=0, grime=False)
    ban = [(-0.42, 0.62), (0.42, 0.62), (0.42, -0.55), (0.0, -0.85), (-0.42, -0.55)]
    k.prism(ban, 0.03, (0, -0.08, 0), CL, CRIMSON, var=0.02)
    k.prism([(-0.34, 0.52), (0.34, 0.52), (0.34, 0.44), (-0.34, 0.44)], 0.02, (0, -0.1, 0), CL, GOLD, var=0)
    k.image_quad(CROWN, 0.5, 0.5, (0, -0.11, 0.0), key="Crown", double_sided=True)
    k.pop()
    for bx in (-2.6, 2.6):
        k.cyl(0.04, 1.4, (bx - 0.7, -0.3, WALK - 0.75), MT, IRON, rot=(0, math.pi / 2, 0), segs=6)
        for s2 in (-1, 1):
            k.box((0.05, 0.3, 0.05), (bx + s2 * 0.6, -0.15, WALK - 0.75), MT, IRON, var=0)
        ban = [(-0.55, 0.0), (0.55, 0.0), (0.55, -2.6), (0.0, -2.2), (-0.55, -2.6)]
        k.prism(ban, 0.03, (bx, -0.27, WALK - 0.8), CL, CRIMSON, var=0.03)
        k.prism([(-0.47, -0.1), (0.47, -0.1), (0.47, -0.2), (-0.47, -0.2)], 0.02, (bx, -0.29, WALK - 0.8), CL, GOLD)
        k.image_quad(CROWN, 0.65, 0.65, (bx, -0.31, WALK - 1.55), key="Crown", double_sided=True)
# lanterns either side of the arch on the town side
with k.side("back", HX, HY):
    for sx in (-1, 1):
        k.wall_lantern(sx * (R + 0.9), 3.6)

k.finish_checked((17.0, 8.2), 15000, cam_dir=(0.75, -1.5, 0.5), fit=0.95)
