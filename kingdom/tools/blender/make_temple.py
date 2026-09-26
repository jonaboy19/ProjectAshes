"""Town temple / church: a Gothic limestone church for towns and the capital.
West tower with buttresses, a great pointed door up three steps, a tall
west window, a rose window, louvred paired belfry lancets, a battlemented
parapet with corner pinnacles and a tall slate spire; a clerestoried nave
between lean-to aisles with buttresses and pointed windows; a lower chancel
with a big mullioned east window; stone-coped gables with crosses.

Run: python3 make_temple.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Aisles 14.0 m wide (X) and buttresses to 15.4 m, eaves
~15.8 m; nave 8.4 m wide; length from the tower steps to the chancel east
buttresses ~28 m (tower 6.4 x 6.4 m at the front). Aisle eaves ~5.2 m, nave
ridge ~16 m, tower parapet 19.9 m, spire apex ~28.6 m, cross ~29.6 m.
Origin at ground centre of the plan; the west door faces Blender -Y
(Godot +Z).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from town_kit import TK, palette, IRON, MORTAR, LIMESTONE, arch_hole, rect_hole, arch_top, DRESSED, GLASS_C
from ra_kit import hexc, vary, mix

k = TK("Temple", seed=4242, pal=palette(stone="warm", roof="slate_blue", timber="dark", door="natural"))
k.p["stone"] = LIMESTONE
MA, W, MT, PL = k.M("Matte"), k.M("Wood"), k.M("Metal"), k.M("Plant")
k.grime = 1.6
k.grime_amt = 0.24
BW, BH = 1.4, 0.62

TX, TY0, TY1, TZ = 3.2, -13.2, -6.8, 19.0          # tower
NX, NY0, NY1, NWT = 4.2, -6.8, 8.6, 11.0           # nave
AX, AWT = 7.0, 5.2                                  # aisles
CX, CY1, CWT = 3.6, 12.9, 9.0                       # chancel
PITCH = 50
TANP = math.tan(math.radians(PITCH))


def st():
    c = k.stone()
    if random.random() < 0.05:
        c = mix(c, hexc("7d7a5a"), 0.3)
    return c


def dressed():
    return mix(random.choice(LIMESTONE), DRESSED, 0.45)


def sface(L, h, **kw):
    kw.setdefault("bw", BW)
    kw.setdefault("bh", BH)
    kw.setdefault("color_fn", st)
    k.stone_face(L, h, **kw)


def coping(y, hd, apex, cross=False):
    base = apex - hd * TANP
    for sx in (-1, 1):
        k.bar((sx * (hd + 0.05), y, base + 0.12), (0.0, y, apex + 0.2), 0.4, 0.56, MA, dressed(),
              up=(-sx * math.sin(math.radians(PITCH)), 0, math.cos(math.radians(PITCH))), bevel=0.0)
        k.box((0.62, 0.6, 0.6), (sx * (hd - 0.1), y, base - 0.1), MA, dressed(), var=0)
    if cross:
        k.cross((0, y, apex + 0.3), h=1.3, mat=MA, color=dressed(), w=0.18)


# ---------------------------------------------------------------- plinth + cores
k.box((2 * AX + 0.3, NY1 - NY0 + 0.3, 0.35), (0, (NY0 + NY1) / 2, 0.175), MA, hexc("8a806e"), var=0)
k.box((2 * CX + 0.3, CY1 - NY1 + 0.15, 0.35), (0, (NY1 + CY1) / 2 + 0.07, 0.175), MA, hexc("8a806e"), var=0)
k.box((2 * TX + 0.3, TY1 - TY0 + 0.3, 0.35), (0, (TY0 + TY1) / 2, 0.175), MA, hexc("8a806e"), var=0)
k.core(-TX, TX, TY0, TY1, 0.0, TZ, inset=0.24)
k.core(-AX, AX, NY0, NY1, 0.0, AWT, inset=0.24)
k.core(-NX, NX, NY0, NY1, AWT - 0.5, NWT, inset=0.24)
k.core(-CX, CX, NY1 - 0.3, CY1, 0.0, CWT, inset=0.24)

k.stage("plinth")
# ---------------------------------------------------------------- roofs
rn = k.gable_roof("slate", -NX, NX, NY0, NY1, NWT, PITCH, over=0.45, verge=-0.02, along="y", barge=False,
                  tile_w=(1.0, 1.45), course=0.68)
rc = k.gable_roof("slate", -CX, CX, NY1 - 0.4, CY1, CWT, PITCH, over=0.4, verge=-0.02, along="y", barge=False,
                  tile_w=(0.85, 1.25), course=0.6)
A_RUN = AX - NX + 0.45
A_PITCH = math.radians(40)
A_EAVE = AWT + 0.08
A_RISE = A_RUN * math.tan(A_PITCH)
for sx in (-1, 1):
    y0, y1 = (NY0 - 0.05, NY1 + 0.05) if sx > 0 else (-NY1 - 0.05, -NY0 + 0.05)
    k.shingle_side(y0, y1, A_RUN, A_RISE, k.M("Roof"), k.tile, tile_w=(1.0, 1.45), course=0.68,
                   th=0.03, deck_mat=W, deck_color=k.timber(), rot=(0, 0, sx * math.pi / 2),
                   loc=(sx * NX, 0, A_EAVE), jag=0.04, droop=0.012)
    # flashing strip where the lean-to meets the clerestory wall
    k.box((0.25, NY1 - NY0 + 0.1, 0.12), (sx * (NX + 0.1), (NY0 + NY1) / 2, A_EAVE + A_RISE + 0.02), MA,
          dressed(), var=0)
A_TOP = A_EAVE + A_RISE

k.stage("roofs")
# ---------------------------------------------------------------- aisle + clerestory walls
BAYS = [NY0 + 1.93 + i * 3.85 for i in range(4)]
BUTT = [NY0 + 0.35] + [NY0 + 3.85 * i for i in (1, 2, 3)] + [NY1 - 0.35]
LEN_N = NY1 - NY0
yc_n = (NY0 + NY1) / 2
for s in ("left", "right"):
    sg = 1 if s == "right" else -1
    with k.side(s, AX, LEN_N / 2, cy=yc_n) as L:
        xs = [(y - yc_n) * sg for y in BAYS]
        holes = [k.lancet_hole(x, 1.5, 1.1, 2.9, pointed=0.7, ring=0.22) for x in xs]
        sface(L, AWT, holes=holes, rows=9)
        for x in xs:
            k.lancet(x, 1.5, 1.1, 2.9, pointed=0.7, ring=0.22, cheap=True, color_fn=dressed, sill=False)
        for y in BUTT:
            bx = (y - yc_n) * sg
            k.buttress(bx - 0.35, bx + 0.35, 0, [(AWT - 0.5, 0.7)], color_fn=st, bw=0.9, bh=0.7)
        k.box((L + 0.3, 0.3, 0.2), (0, 0.05, AWT - 0.1), MA, dressed(), var=0)
    with k.side(s, NX, LEN_N / 2, cy=yc_n) as L:
        z0 = A_TOP - 0.3
        holes = [k.lancet_hole(x, 8.9 - z0, 0.75, 1.6, pointed=0.6, ring=0.18) for x in xs]
        sface(L, NWT - z0, loc=(0, 0, z0), holes=holes, rows=5)
        for x in xs:
            k.lancet(x, 8.9, 0.75, 1.6, pointed=0.6, ring=0.18, cheap=True, bars=False, color_fn=dressed, sill=False)
        k.box((L + 0.3, 0.3, 0.2), (0, 0.05, NWT - 0.1), MA, dressed(), var=0)

k.stage("aislewalls")
# aisle west ends (either side of the tower) and east ends (either side of the chancel)
for sx in (-1, 1):
    for s, yy in (("front", NY0), ("back", NY1)):
        cx = sx * (NX + AX) / 2
        hl = (AX - NX) / 2
        with k.side(s, hl, 0.0, cx=cx, cy=yy) as L:
            # lean-to top: high at the nave side, low at the aisle wall
            def tf(x, s=s, sx=sx):
                xw = x * (1 if s == "front" else -1) * sx     # + toward the outer aisle wall
                return A_TOP + 0.1 - (xw + hl) / (2 * hl) * (A_TOP - AWT)
            sface(L, A_TOP + 0.1, top_fn=tf, holes=[k.lancet_hole(0, 1.6, 0.8, 2.4, pointed=0.7, ring=0.2)],
                  rows=int((A_TOP + 0.1) / BH + 0.5))
            k.lancet(0, 1.6, 0.8, 2.4, pointed=0.7, ring=0.2, cheap=True, color_fn=dressed, bars=False)

k.stage("aisleends")
# nave gables: west (above the aisles, beside/behind the tower) and east (above the chancel)
for s in ("front", "back"):
    with k.side(s, NX, LEN_N / 2, cy=yc_n) as L:
        gf = lambda x: rn["gable"](x) + 0.03
        z0 = 0.0 if s == "front" else A_TOP - 0.4
        hidden = [rect_hole(-TX + 0.25, -1.0, TX - 0.25, 30.0)] if s == "front" else []   # behind the tower
        sface(L, gf(0) - z0 + 0.05, loc=(0, 0, z0), top_fn=lambda x: gf(x) - z0, breaks=(0.0,), holes=hidden,
              rows=int((gf(0) - z0) / BH + 0.5))
        k.prism([(-NX + 0.1, 0.0), (NX - 0.1, 0.0), (0, gf(0) - NWT - 0.1)], 0.3, (0, 0.24, NWT), MA, MORTAR,
                var=0, grime=False)
        apex_n = gf(0)
coping(NY0 + 0.16, NX, apex_n)
coping(NY1 - 0.16, NX, apex_n, cross=True)

k.stage("gables")
# ---------------------------------------------------------------- chancel
LEN_C = CY1 - NY1
yc_c = (NY1 + CY1) / 2
for s in ("left", "right"):
    with k.side(s, CX, LEN_C / 2, cy=yc_c) as L:
        holes = [k.lancet_hole(0, 2.0, 1.1, 3.8, pointed=0.7, ring=0.22)]
        sface(L, CWT, holes=holes, rows=16)
        k.lancet(0, 2.0, 1.1, 3.8, pointed=0.7, ring=0.22, cheap=True, color_fn=dressed)
        k.box((L + 0.3, 0.3, 0.2), (0, 0.05, CWT - 0.1), MA, dressed(), var=0)
with k.side("back", CX, LEN_C / 2, cy=yc_c) as L:
    gf = lambda x: rc["gable"](x) + 0.03
    holes = [k.lancet_hole(0, 2.4, 2.3, 5.2, pointed=0.6, ring=0.26)]
    sface(L, gf(0) + 0.05, holes=holes, top_fn=gf, breaks=(0.0,), rows=int((gf(0) + 0.05) / BH + 0.5))
    k.prism([(-CX + 0.1, CWT - 0.2), (CX - 0.1, CWT - 0.2), (0, gf(0) - 0.1)], 0.3, (0, 0.24, 0), MA, MORTAR,
            var=0, grime=False)
    k.lancet(0, 2.4, 2.3, 5.2, pointed=0.6, ring=0.26, color_fn=dressed, cheap=True)
    for sx in (-1, 1):   # mullions + a little tracery quatrefoil
        k.box((0.1, 0.12, 3.9), (sx * 0.38, 0.12, 2.4 + 1.95), MA, dressed(), var=0)
    k.ring(0.22, 0.32, 0.12, (0, 0.12, 6.75), MA, dressed(), segs=10)
    for sx in (-1, 1):
        k.buttress(sx * (CX - 0.35) - 0.35, sx * (CX - 0.35) + 0.35, 0, [(3.0, 0.8), (CWT - 1.2, 0.55)],
                   color_fn=st, bw=0.9, bh=0.7)
    apex_c = gf(0)
coping(CY1 - 0.16, CX, apex_c, cross=True)

k.stage("chancel")
# ---------------------------------------------------------------- tower
DW, DH = 2.4, 4.6
DR, DRp, DRise = k.lancet_geom(DW, DH, 0.6)
D_SPRING = 0.35 + DH - DRise
WZ, WW, WH = 7.2, 1.5, 4.2
RZ = 13.0
BELL_Z = 15.0
towers_faces = {
    "front": [arch_hole(0, DW, 0.3, D_SPRING, ring=0.5, pointed=0.6), k.lancet_hole(0, WZ, WW, WH, 0.6, 0.24),
              k.rose_hole(0, RZ, 0.8)],
    "left": [k.lancet_hole(0, 7.6, 0.8, 2.6, 0.6, 0.2), k.lancet_hole(0, 11.6, 0.6, 1.8, 0.6, 0.18)],
    "right": [k.lancet_hole(0, 7.6, 0.8, 2.6, 0.6, 0.2), k.lancet_hole(0, 11.6, 0.6, 1.8, 0.6, 0.18)],
    "back": [],
}
for s, holes in towers_faces.items():
    BX = (-0.75, 0.75) if s != "back" else (0.0,)
    holes = holes + [k.lancet_hole(x, BELL_Z, 0.8, 2.9, 0.6, 0.2) for x in BX]
    with k.side(s, TX, (TY1 - TY0) / 2, cy=(TY0 + TY1) / 2) as L:
        if s == "back":      # below the nave ridge the back face is hidden by the nave
            holes = holes + [rect_hole(-TX - 0.1, -1.0, TX + 0.1, 12.8)]
        sface(L, TZ, holes=holes, rows=int(TZ / BH + 0.5))
        for x in BX:
            k.lancet(x, BELL_Z, 0.8, 2.9, 0.6, 0.2, cheap=True, fill="louvre", color_fn=dressed)
        if s in ("left", "right"):
            k.lancet(0, 7.6, 0.8, 2.6, 0.6, 0.2, cheap=True, color_fn=dressed)
            k.lancet(0, 11.6, 0.6, 1.8, 0.6, 0.18, cheap=True, bars=False, color_fn=dressed, sill=False)
        if s == "front":
            k.rose(0, RZ, 0.8, spokes=6, color=mix(LIMESTONE[0], DRESSED, 0.4))
        for zz in (6.3, 14.6):   # string courses
            k.box((L + 0.3, 0.32, 0.22), (0, 0.02, zz), MA, dressed(), var=0)
        if s == "front":
            k.lancet(0, WZ, WW, WH, 0.6, 0.24, color_fn=dressed)
            k.box((0.1, 0.12, 3.2), (0, 0.12, WZ + 1.6), MA, dressed(), var=0)
            # great door: voussoirs, jambs, planked leaves cut to the pointed arch, steps
            k.arch_ring(0, D_SPRING, DR, ring=0.3, depth=0.5, y=0.1, Rp=DRp, n=11, color_fn=dressed)
            k.arch_ring(0, D_SPRING, DR + 0.3, ring=0.2, depth=0.34, y=0.0, Rp=DRp + 0.3, n=9, color_fn=dressed)
            for sx in (-1, 1):
                for r in range(5):
                    wd = 0.55 if r % 2 == 0 else 0.42
                    hh = (D_SPRING - 0.35) / 5
                    k.box((wd, 0.5, hh - 0.03), (sx * (DR + wd / 2), 0.1, 0.35 + (r + 0.5) * hh), MA, dressed(),
                          var=0)
            dtop = arch_top(0, DR, D_SPRING, DRp)
            n = 8
            for i in range(n):
                x0 = -DR + i * DW / n
                x1 = x0 + DW / n
                pts = [(x0 + 0.006, 0.35), (x1 - 0.006, 0.35), (x1 - 0.006, dtop(x1) - 0.02),
                       (x0 + 0.006, dtop(x0) - 0.02)]
                if x0 < 0 < x1:
                    pts.insert(3, (0.0, dtop(0.0) - 0.02))
                k.prism(pts, 0.08, (0, 0.2, 0), W, vary(hexc("6e4126"), 0.1, 0.04), var=0)
            for zz in (1.0, 2.2, 3.4):
                k.box((DW - 0.3, 0.03, 0.1), (0, 0.155, zz), MT, IRON, var=0)
            for i in range(3):
                k.box((DW + 1.6 - i * 0.4, 0.3 * (3 - i), 0.12), (0, -0.15 - 0.15 * (3 - i), 0.06 + i * 0.1), MA,
                      vary(hexc("8d877c"), 0.05), var=0)
            for sx in (-1, 1):
                k.buttress(sx * (TX - 0.4) - 0.4, sx * (TX - 0.4) + 0.4, 0, [(6.2, 0.95), (13.0, 0.6)],
                           color_fn=st, bw=1.0, bh=0.75)
        elif s in ("left", "right"):
            bx = -(TX - 0.4) if s == "right" else (TX - 0.4)
            k.buttress(bx - 0.4, bx + 0.4, 0, [(6.2, 0.95), (13.0, 0.6)], color_fn=st, bw=1.0, bh=0.75)
k.stage("tower")
# tower top: parapet with merlons, corner pinnacles, spire
k.box((2 * TX + 0.4, TY1 - TY0 + 0.4, 0.24), (0, (TY0 + TY1) / 2, TZ + 0.02), MA, dressed(), var=0)
for s in ("front", "back", "left", "right"):
    with k.side(s, TX + 0.12, (TY1 - TY0) / 2 + 0.12, cy=(TY0 + TY1) / 2) as L:
        # plain parapet with a moulded coping between the pinnacles
        k.box((L - 1.3, 0.3, 0.8), (0, 0.2, TZ + 0.54), MA, MORTAR, var=0, grime=False)
        k.stone_face(L - 1.3, 0.8, loc=(0, 0, TZ + 0.14), bw=1.1, bh=0.4, rows=2, color_fn=st, grime=False)
        k.box((L - 1.3, 0.46, 0.14), (0, 0.18, TZ + 1.0), MA, dressed(), var=0, grime=False)
for sx in (-1, 1):
    for sy in (-1, 1):
        px, py = sx * (TX - 0.05), (TY0 + TY1) / 2 + sy * ((TY1 - TY0) / 2 - 0.05)
        k.box((0.7, 0.7, 1.2), (px, py, TZ + 0.74), MA, st(), var=0)
        k.cyl(0.52, 2.1, (px, py, TZ + 1.34), MA, dressed(), segs=4, r2=0.02, rot=(0, 0, math.pi / 4), smooth=None,
              var=0)
apex = k.pyramid_roof(0, (TY0 + TY1) / 2, 2.5, TZ + 0.3, 9.2, k.M("Roof"), k.tile, over=0.05,
                      tile_w=(0.7, 1.0), course=0.58, th=0.03)
k.sphere(0.2, (0, (TY0 + TY1) / 2, apex + 0.1), MT, hexc("b08a3a"), subdiv=1, grime=False)
k.cross((0, (TY0 + TY1) / 2, apex + 0.2), h=1.2, w=0.1, color=hexc("b08a3a"))

k.stage("towertop")
k.finish_checked((16.0, 28.5), 15000, cam_dir=(1.15, -1.25, 0.55), fit=0.9)
