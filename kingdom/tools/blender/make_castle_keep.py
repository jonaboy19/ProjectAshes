"""Capital castle keep: a great square keep of grey rubble with a battered
plinth, round corner towers with corbelled top storeys and tall conical
slate roofs flying pennants, a crenellated parapet and wall-walk around a
hipped slate roof, a taller central donjon with its own battlements and the
royal standard, and a crenellated forebuilding with a great arched door up a
flight of steps. Arched upper windows, arrow slits, string courses, long
banners and the royal arms on the front.

Run: python3 make_castle_keep.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Keep 20 x 20 m; towers r=3.6 m centred on the keep
corners (overall ~28 x 28 m); forebuilding 8 x 3.2 m in front, steps to
y ~ -14.6 m. Keep walk 16 m, merlons 16.9 m; towers 20.2 m to the roof eaves,
cone apexes ~26.5 m; donjon battlements 25.4 m, standard pole top ~31 m.
Origin at ground centre of the keep. The great door faces Blender -Y
(Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, WALLSTONE, arch_hole, rect_hole, DRESSED
from ra_kit import hexc, vary, mix

k = TK("CastleKeep", seed=9001, pal=palette(stone="grey", roof="slate_blue", accent="oxblood"))
k.p["stone"] = WALLSTONE
MA, W, MT, CL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Cloth")
k.grime = 2.0
k.grime_amt = 0.28
HK = 10.0                   # keep half size
WALK, BREAST, TOP = 16.0, 16.9, 17.8
TR, TZ = 3.6, 19.0          # corner tower radius / top of drum
BW, BH = 1.25, 0.58
CRIMSON, GOLD, NAVY = hexc("8e1f24"), hexc("c9a24a"), hexc("1f3b66")


def st():
    c = k.stone()
    if random.random() < 0.05:
        c = mix(c, hexc("5d6b3e"), 0.35)
    return c


def dressed(a=0.28):
    return mix(k.stone(), DRESSED, a)


def banner(x, y, ztop, w=1.3, h=4.2, rz=0.0, emblem=True):
    """Long swallow-tailed banner on an iron rod, hanging flat on a wall (wall frame)."""
    k.cyl(0.05, w + 0.3, (x - (w + 0.3) / 2, y - 0.3, ztop), MT, IRON, rot=(0, math.pi / 2, 0), segs=6)
    for s2 in (-1, 1):
        k.box((0.06, 0.32, 0.06), (x + s2 * (w / 2 + 0.05), y - 0.15, ztop), MT, IRON, var=0)
    ban = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, -h), (0.0, -h + 0.5), (-w / 2, -h)]
    k.prism(ban, 0.04, (x, y - 0.27, ztop - 0.05), CL, CRIMSON, var=0.03)
    k.prism([(-w / 2 + 0.08, -0.12), (w / 2 - 0.08, -0.12), (w / 2 - 0.08, -0.24), (-w / 2 + 0.08, -0.24)], 0.02,
            (x, y - 0.3, ztop - 0.05), CL, GOLD)
    if emblem:
        e = w * 0.3
        k.prism([(0, -0.9), (e, -0.9 - e * 1.3), (0, -0.9 - e * 2.6), (-e, -0.9 - e * 1.3)], 0.02,
                (x, y - 0.3, ztop - 0.05), CL, GOLD)


# ---------------------------------------------------------------- keep core, plinth, faces
k.core(-HK, HK, -HK, HK, 0.0, WALK, inset=0.26)
FACE_W = 2 * (HK - TR + 0.45)
WINS = [-4.6, 0.0, 4.6]
faces = {}
for s in ("front", "back", "left", "right"):
    holes, slits = [], []
    for x in WINS:
        if s == "front" and x == 0.0:
            continue
        holes.append(k.lancet_hole(x, 10.6, 1.25, 2.9, pointed=0.0, ring=0.26))
    for x in (-3.0, 3.0):
        for z in (5.4,):
            if s == "front" and abs(x) < 4.4 and z < 11:
                continue
            slits.append((x, z))
            holes.append(rect_hole(x - 0.36, z - 0.2, x + 0.36, z + 1.2))
    faces[s] = (holes, slits)
for s, (holes, slits) in faces.items():
    with k.side(s, HK, HK) as L:
        # battered plinth
        ang = math.atan2(0.45, 1.8)
        k.stone_face(FACE_W, 1.8 / math.cos(ang), loc=(0, -0.45, 0), rot=(-ang, 0, 0), bw=1.3, bh=0.6, rows=3,
                     color_fn=lambda: mix(st(), MORTAR, 0.12))
        k.box((FACE_W, 0.3, 1.8), (0, 0.1, 0.9), MA, MORTAR, var=0, grime=False)
        k.stone_face(FACE_W, BREAST - 1.9, loc=(0, 0, 1.9), holes=[dict(h, z0=h["z0"] - 1.9, zmax=h["zmax"] - 1.9,
                                                                         top=(lambda x, f=h["top"]: f(x) - 1.9))
                                                                    for h in holes],
                     bw=BW, bh=BH, color_fn=st, rows=int((BREAST - 1.9) / BH + 0.5))
        for i in range(4):     # chamfered course on the batter
            k.push((-FACE_W / 2 + (i + 0.5) * FACE_W / 4, -0.02, 1.84), (0, 0, math.pi / 2))
            k.prism([(-0.2, 0.0), (0.12, 0.0), (0.12, 0.2), (-0.04, 0.2), (-0.2, 0.08)], FACE_W / 4 - 0.015,
                    (0, 0, 0), MA, dressed(0.2), var=0)
            k.pop()
        for x in WINS:
            if s == "front" and x == 0.0:
                continue
            k.lancet(x, 10.6, 1.25, 2.9, pointed=0.0, ring=0.26, cheap=True, color_fn=dressed, sill=True)
        for x, z in slits:
            k.slit(x, z, h=1.0)
        k.box((FACE_W, 0.34, 0.24), (0, 0.0, 9.8), MA, dressed(0.22), var=0)           # string course
        # parapet: walk side face, crenel copings, merlons
        k.push((0, 0.62, 0), (0, 0, math.pi))
        k.stone_face(FACE_W, BREAST - WALK, loc=(0, 0, WALK), bw=1.0, bh=0.3, rows=3, color_fn=st, grime=False)
        k.pop()
        k.box((FACE_W, 0.7, 0.14), (0, 0.3, BREAST + 0.03), MA, dressed(0.3), var=0, grime=False)
        k.merlons(-FACE_W / 2 + 0.3, FACE_W / 2 - 0.3, BREAST, h=TOP - BREAST, th=0.62, mw=1.15, cw=0.6, y=-0.03,
                  slits=0.3)
        if s != "front":
            for bx in (-2.3, 2.3):
                banner(bx, 0.0, 15.2, w=1.3, h=4.4)

k.stage("faces")
# ---------------------------------------------------------------- walk, hip roof, donjon
for sx in (-1, 1):
    k.flagstones(-HK + 0.6, HK - 0.6, sx * (HK - 0.62) - (1.35 if sx > 0 else 0), sx * (HK - 0.62) + (0 if sx > 0 else 1.35),
                 WALK, size=(1.7, 0.9), base=True)
    k.flagstones(sx * (HK - 0.62) - (1.35 if sx > 0 else 0), sx * (HK - 0.62) + (0 if sx > 0 else 1.35),
                 -HK + 2.0, HK - 2.0, WALK, size=(0.9, 1.7), base=True)
HR = HK - 2.0
k.hip_roof(0, 0, HR - 0.3, HR - 0.3, WALK + 0.1, 4.6, k.M("Roof"), k.tile, over=0.3, tile_w=(0.9, 1.3), course=0.62,
           th=0.03)
k.stage("walk+roof")
DJ, DZ0, DWALK = 3.9, WALK + 2.0, 24.4
k.core(-DJ, DJ, -DJ, DJ, DZ0, DWALK, inset=0.25)
for s in ("front", "back", "left", "right"):
    with k.side(s, DJ, DJ) as L:
        holes = [k.lancet_hole(0, 20.2 - DZ0, 1.1, 2.4, pointed=0.0, ring=0.24)]
        k.stone_face(L, DWALK + 0.9 - DZ0, loc=(0, 0, DZ0), holes=holes, bw=BW, bh=BH, color_fn=st,
                     rows=int((DWALK + 0.9 - DZ0) / BH + 0.5))
        k.lancet(0, 20.2, 1.1, 2.4, pointed=0.0, ring=0.24, cheap=True, color_fn=dressed)
        k.box((L + 0.3, 0.3, 0.22), (0, 0.0, DWALK - 0.4), MA, dressed(0.22), var=0)
        k.push((0, 0.55, 0), (0, 0, math.pi))
        k.stone_face(L - 1.1, 0.9, loc=(0, 0, DWALK), bw=1.0, bh=0.3, rows=3, color_fn=st, grime=False)
        k.pop()
        k.box((L, 0.62, 0.14), (0, 0.28, DWALK + 0.93), MA, dressed(0.3), var=0, grime=False)
        k.merlons(-L / 2, L / 2, DWALK + 0.9, h=0.95, th=0.55, mw=1.05, cw=0.6, y=-0.03, start=-L / 2 + 0.52)
k.flagstones(-DJ + 0.55, DJ - 0.55, -DJ + 0.55, DJ - 0.55, DWALK, size=(1.2, 0.9))
k.stage("donjon")
# royal standard
k.cyl(0.12, 0.5, (0, 0, DWALK), MA, dressed(), segs=8)
k.cyl(0.07, 6.2, (0, 0, DWALK + 0.4), W, hexc("4a3020"), segs=8)
k.sphere(0.16, (0, 0, DWALK + 6.7), MT, GOLD, subdiv=1, grime=False)
k.push((0, 0, DWALK + 6.45), (0, 0, -0.35))
k.sheet(((0.07, 0, -1.9), (3.6, 0, -1.75), (0.07, 0, 0), (3.6, 0, 0)), 10, 4, CL,
        lambda u, v: GOLD if (v < 0.1 or v > 0.9) else (NAVY if abs(v - 0.5) < 0.12 and 0.2 < u < 0.8 else CRIMSON),
        sag_fn=lambda u, v: (0, math.sin(u * 5.5 + v) * 0.3 * u, -0.25 * u * u))
k.pop()

k.stage("standard")
# ---------------------------------------------------------------- corner towers
for sx in (-1, 1):
    for sy in (-1, 1):
        cx, cy = sx * HK, sy * HK
        inward = math.atan2(-sy, -sx)
        start = inward - math.radians(42)
        hid = rect_hole(-0.1, -2.0, TR * math.radians(84), 40.0)       # quadrant inside the keep
        k.cyl(TR - 0.3, TZ, (cx, cy, 0), MA, MORTAR, segs=12, var=0, smooth=None, grime=False, r2=TR - 0.45)
        k.stone_ring(cx, cy, TR + 0.4, 0.0, 1.8, r_top=TR + 0.02, holes=[hid], bw=1.3, bh=0.6, rows=3, start=start,
                     seg_len=1.45,
                     color_fn=lambda: mix(st(), MORTAR, 0.12))
        slits = []
        for i, (da, z) in enumerate(((0.0, 5.0), (-0.75, 9.5), (0.75, 9.5), (0.0, 14.0))):
            slits.append((inward + math.pi + da, z))
        holes = [dict(hid, z0=-5.0)]
        for ang, z in slits:
            u = k.ang_u(TR, ang, start)
            holes.append(rect_hole(u - 0.36, z - 0.2 - 1.8, u + 0.36, z + 1.2 - 1.8))
        k.stone_ring(cx, cy, TR, 1.8, TZ, r_top=TR - 0.15, holes=holes, bw=1.5, bh=0.66, start=start, color_fn=st,
                     seg_len=1.45,
                     rows=int((TZ - 1.8) / 0.66 + 0.5))
        for ang, z in slits:
            rr = TR - 0.15 * (z - 1.8) / (TZ - 1.8) - 0.02
            k.push((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, 0), (0, 0, ang + math.pi / 2))
            k.slit(0, z, h=1.0)
            k.pop()
        k.corbels(cx, cy, TR - 0.2, TZ + 0.02, 14, drop=0.8, out=0.45, w=0.5, steps=1)
        RU = TR + 0.25
        k.cyl(RU - 0.2, 1.4, (cx, cy, TZ - 0.05), MA, MORTAR, segs=12, var=0, smooth=None, grime=False)
        k.cyl(RU + 0.02, 0.12, (cx, cy, TZ - 0.05), MA, mix(WALLSTONE[0], MORTAR, 0.4), segs=18, var=0, smooth=None,
              grime=False)
        uh = []
        for da in (-0.8, 0.0, 0.8):
            ang = inward + math.pi + da
            u = k.ang_u(RU, ang, start)
            uh.append((ang, rect_hole(u - 0.3, 0.3, u + 0.3, 1.0)))
        k.stone_ring(cx, cy, RU, TZ + 0.05, TZ + 1.25, holes=[h for a, h in uh], bw=1.0, bh=0.4, rows=3, start=start,
                     color_fn=st, grime=False)
        for ang, h in uh:
            k.push((cx + math.cos(ang) * RU, cy + math.sin(ang) * RU, 0), (0, 0, ang + math.pi / 2))
            k.quad(0.6, 0.7, (0, 0.14, TZ + 0.7), MA, hexc("1f1c1a"), var=0, grime=False)
            k.box((0.84, 0.14, 0.1), (0, -0.03, TZ + 0.3), MA, dressed(0.25), var=0, grime=False)
            k.pop()
        k.cyl(RU + 0.05, 0.16, (cx, cy, TZ + 1.22), W, k.timber(), segs=18, var=0, smooth=None, grime=False)
        apex = k.cone_roof(cx, cy, RU + 0.5, TZ + 1.34, 6.0, k.M("Roof"), k.tile, tile_w=0.95, course=0.62)
        k.cyl(0.16, 0.4, (cx, cy, apex - 0.4), MT, IRON, segs=8, r2=0.06)
        k.banner_pole(cx, cy, apex - 0.1, h=1.8, color=CRIMSON, trim=GOLD, rz=-0.35, flag_len=1.8, flag_h=0.8,
                      wave=0.14)

k.stage("towers")
# ---------------------------------------------------------------- forebuilding + great door
FX, FY0, FY1, FH = 4.0, -HK - 3.2, -HK + 0.2, 10.4
k.core(-FX, FX, FY0, FY1, 0.0, FH - 0.9, inset=0.25)
DW, DSP = 3.4, 3.4
fb_face = {"front": [arch_hole(0, DW, -1.0, DSP, ring=0.45)], "left": [], "right": []}
for s, holes in fb_face.items():
    with k.side(s, FX, (FY1 - FY0) / 2, cy=(FY0 + FY1) / 2) as L:
        k.stone_face(L, FH, holes=holes, bw=BW, bh=BH, color_fn=st, rows=int(FH / BH + 0.5))
        k.box((L + 0.3, 0.3, 0.2), (0, 0.0, FH - 1.3), MA, dressed(0.22), var=0)
        k.merlons(-L / 2, L / 2, FH - 0.95, h=0.95, th=0.55, mw=1.05, cw=0.6, y=-0.03, start=-L / 2 + 0.52)
        if s == "front":
            k.arch_ring(0, DSP, DW / 2, ring=0.5, depth=0.55, y=0.1, n=11, color_fn=lambda: dressed(0.35))
            for sx2 in (-1, 1):
                for r in range(6):
                    wd = 0.6 if r % 2 == 0 else 0.45
                    k.box((wd, 0.5, DSP / 6 - 0.03), (sx2 * (DW / 2 + wd / 2), 0.1, (r + 0.5) * DSP / 6), MA,
                          dressed(0.35), var=0)
            # recessed door leaves
            n = 10
            for i in range(n):
                x0 = -DW / 2 + i * DW / n
                x1 = x0 + DW / n
                t = lambda x: DSP + math.sqrt(max(0.0, (DW / 2) ** 2 - x * x)) - 0.02
                pts = [(x0 + 0.008, 0.0), (x1 - 0.008, 0.0), (x1 - 0.008, t(x1)), (x0 + 0.008, t(x0))]
                if x0 < 0 < x1:
                    pts.insert(3, (0.0, t(0.0)))
                k.prism(pts, 0.1, (0, 0.34, 0), W, vary(hexc("5e3a22"), 0.1, 0.04), var=0)
            for zz in (0.7, 2.0, 3.3):
                for sx2 in (-1, 1):
                    k.box((DW / 2 - 0.2, 0.03, 0.12), (sx2 * (DW / 4 + 0.03), 0.28, zz), MT, IRON, var=0)
            for sx2 in (-1, 1):
                k.ring(0.13, 0.17, 0.04, (sx2 * 0.45, 0.26, 1.6), MT, GOLD, segs=8)
            # royal arms above the door
            k.push((0, -0.08, 7.0))
            sh = [(0, -0.9), (0.5, -0.6), (0.72, -0.05), (0.74, 0.55), (0.0, 0.7), (-0.74, 0.55), (-0.72, -0.05),
                  (-0.5, -0.6)]
            k.prism([(x * 1.12, z * 1.12) for x, z in sh], 0.14, (0, 0.03, 0), MA, dressed(0.45), var=0)
            k.prism(sh, 0.1, (0, -0.06, 0), MA, NAVY, var=0)
            k.prism([(-0.08, -0.55), (0.08, -0.55), (0.08, 0.5), (-0.08, 0.5)], 0.04, (0, -0.12, 0), MA, GOLD, var=0)
            k.prism([(-0.55, 0.08), (0.55, 0.08), (0.55, 0.24), (-0.55, 0.24)], 0.04, (0, -0.12, 0), MA, GOLD, var=0)
            k.pop()
            for sx2 in (-1, 1):
                k.wall_lantern(sx2 * (DW / 2 + 1.1), 4.2)
k.flagstones(-FX + 0.55, FX - 0.55, FY0 + 0.55, FY1 - 0.1, FH - 0.95, size=(1.2, 0.8))
# steps
for i in range(4):
    k.box((DW + 3.0 - i * 0.5, 0.42 * (4 - i), 0.16), (0, FY0 - 0.21 * (4 - i), 0.08 + i * 0.16), MA,
          vary(hexc("8a857c"), 0.05), bevel=0.02, var=0)
# banners on the keep front either side of the forebuilding
with k.side("front", HK, HK):
    for bx in (-5.8, 5.8):
        banner(bx, 0.0, 15.2, w=1.5, h=5.0)

k.stage("fore")
k.finish_checked((30.0, 30.0), 25000, cam_dir=(1.0, -1.45, 0.62), fit=0.92)
