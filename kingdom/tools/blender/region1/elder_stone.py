"""Hero Elder Stone (dais + monolith + 2 leaning shards + 6 ward menhirs + rubble).
blender -b --python elder_stone.py -- <out_dir>
Outputs glb LOD0/LOD1 (blue runes) + textures for blue and ancestor-gold variants."""
import bpy, math, os, sys, random
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(__file__))
import paint as P
import stonekit as SK
import stonepipe as SPI
import stoneshapes as SH

OUT = sys.argv[sys.argv.index("--") + 1]
H_MONO = 5.6
DAIS_TOP = 0.79
RKEYS = P.RUNE_KEYS


# ------------------------------------------------------------------ glyph layouts (part-local metres)
def mono_front(d, c):
    H = H_MONO
    rng = random.Random(4)
    d.line([(0, 0.32), (0, H - 1.75)], wm=0.11)
    for vz in (1.1, 2.15, 3.2):
        d.diamond(0, vz, 0.25, wm=0.07)
        d.line([(0.0, vz + 0.25), (0.22, vz + 0.5), (0.22, vz + 0.72)], wm=0.05, weight=0.9)
        d.line([(0.0, vz + 0.25), (-0.22, vz + 0.5), (-0.22, vz + 0.72)], wm=0.05, weight=0.9)
    keys = [RKEYS[i % len(RKEYS)] for i in range(3, 40)]
    rng.shuffle(keys)
    k = 0
    for i in range(7):
        vb = 0.55 + i * 0.47
        if any(abs(vb + 0.16 - vz) < 0.42 for vz in (1.1, 2.15, 3.2)):
            continue
        for sgn in (-1, 1):
            d.rune(keys[k % len(keys)], sgn * 0.36, vb, 0.30, wm=0.04, weight=0.95)
            k += 1
    ve = H - 1.25
    d.circle(0, ve, 0.33, 0.07)
    d.circle(0, ve, 0.13, 0.055)
    d.dot(0, ve, 0.11)
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        d.line([(0.42 * math.cos(a), ve + 0.42 * math.sin(a)), (0.56 * math.cos(a), ve + 0.56 * math.sin(a))], wm=0.045)
    for i in range(3):
        y0 = H - 0.5 + i * 0.0 - i * 0.16
        d.line([(-0.36 + i * 0.1, y0 + 0.2), (0, y0), (0.36 - i * 0.1, y0 + 0.2)], wm=0.045, weight=0.9)
    d.line([(-0.5, 0.3), (-0.5, H - 1.2)], wm=0.03, weight=0.4)
    d.line([(0.5, 0.3), (0.5, H - 1.2)], wm=0.03, weight=0.4)


def mono_back(d, c):
    rng = random.Random(9)
    for seg in ((0.4, 1.5), (1.9, 2.6), (3.0, 4.2)):
        d.line([(0, seg[0]), (0, seg[1])], wm=0.08, weight=0.35)
    for i in range(6):
        d.rune(RKEYS[(i * 3 + 1) % len(RKEYS)], rng.uniform(-0.3, 0.3), 0.7 + i * 0.75, 0.28, wm=0.04, weight=0.35)


def mono_side(d, c):
    d.line([(0, 0.4), (0, H_MONO - 1.5)], wm=0.07, weight=0.75)
    for i in range(8):
        sgn = -1 if i % 2 == 0 else 1
        d.rune(RKEYS[(i * 5 + 2) % len(RKEYS)], sgn * 0.2, 0.6 + i * 0.55, 0.26, wm=0.035, weight=0.75)


def mono_top(d, c):
    d.circle(0, 0, 0.18, 0.05)


def dais_top(d, c):
    d.circle(0, 0, 1.05, 0.05, weight=0.85)
    d.circle(0, 0, 1.75, 0.10)
    for k in range(8):
        a0 = math.radians(k * 135)
        a1 = math.radians((k + 1) * 135)
        d.line([(1.7 * math.cos(a0), 1.7 * math.sin(a0)), (1.7 * math.cos(a1), 1.7 * math.sin(a1))], wm=0.05, weight=0.9)
    for k in range(4):
        a = math.radians(k * 90 + 45)
        d.line([(0.9 * math.cos(a), 0.9 * math.sin(a)), (2.12 * math.cos(a), 2.12 * math.sin(a))], wm=0.11)
    d.circle(0, 0, 2.05, 0.05, weight=0.9)
    for k in range(20):
        a = 2 * math.pi * k / 20
        r = 2.55
        x, y = r * math.cos(a), r * math.sin(a)
        d.rune(RKEYS[k % len(RKEYS)], x, y - 0.13, 0.26, wm=0.04, weight=0.9, rot=a - math.pi / 2)
    d.circle(0, 0, 2.93, 0.06)
    d.circle(0, 0, 3.17, 0.14)
    for k in range(48):
        a = 2 * math.pi * (k + 0.5) / 48
        d.line([(3.32 * math.cos(a), 3.32 * math.sin(a)), (3.46 * math.cos(a), 3.46 * math.sin(a))], wm=0.045, weight=0.7)


def dais_side(d, c):
    umax = c.umin + c.w / c.ppm
    for band, vb in ((0, 0.055), (1, 0.325), (2, 0.585)):
        n = int((umax - c.umin) / 0.62)
        for i in range(n):
            u = c.umin + 0.15 + i * 0.62
            d.rune(RKEYS[(i + band * 5) % len(RKEYS)], u, vb, 0.15, wm=0.022, weight=0.6)


def shard_front(d, c):
    hh = c.vmax
    d.line([(0, 0.25), (0, hh - 0.6)], wm=0.08)
    for i in range(5):
        d.rune(RKEYS[(i * 4 + 5) % len(RKEYS)], (-1) ** i * 0.19, 0.5 + i * 0.42, 0.24, wm=0.035, weight=0.9)
    d.circle(0, hh - 0.45, 0.14, 0.05)


def shard_side(d, c):
    d.line([(0, 0.25), (0, c.vmax - 0.8)], wm=0.06, weight=0.7)


def menhir_front(d, c):
    hh = c.vmax
    d.circle(0, hh - 0.42, 0.13, 0.055)
    d.line([(0, 0.2), (0, hh - 0.62)], wm=0.06)
    d.rune('ansuz', -0.03, hh - 1.0, 0.3, wm=0.04)


# ------------------------------------------------------------------ vertex colour (sweep, glyph flag, ao proxy)
def vc_mono(co):
    return (0.30 + 0.70 * min(1.0, max(0.0, (co.z - DAIS_TOP) / H_MONO)), 1.0, 0.55 + 0.45 * min(1.0, (co.z - DAIS_TOP) / 1.5))


def vc_dais(co):
    r = math.hypot(co.x, co.y)
    return (0.10 + 0.20 * (1 - min(1.0, r / 3.6)), 1.0, 0.85)


def vc_shard(co):
    return (0.50 + 0.5 * min(1.0, max(0.0, (co.z - DAIS_TOP) / 3.2)), 1.0, 0.6 + 0.4 * min(1.0, (co.z - DAIS_TOP) / 1.2))


def vc_menhir(co):
    return (max(0.0, min(0.2, co.z / 8.0)), 1.0, 0.6 + 0.4 * min(1.0, co.z / 0.8))


def vc_rock(co):
    return (0.0, 0.0, 0.7)


# ------------------------------------------------------------------ build
def build(b, lod):
    hi = lod == 0
    # ---- dais
    prof = [(3.60, 0.0), (3.60, 0.20), (3.50, 0.27), (2.95, 0.27), (2.95, 0.46), (2.85, 0.53), (2.25, 0.53), (2.25, 0.72), (2.15, DAIS_TOP), (0.9, DAIS_TOP)]
    SH.lathe(b, 'dais', prof, N=32 if hi else 16, jit=0.018, seed=1.3, chart_fn=SK.cyl_chart_factory(3.0),
             meta=dict(ppm=85, seed=10, layouts={'T': dais_top, 'C': dais_side}, opts=dict(moss=0.9, moss_h=0.3, depth=0.02),
                       z0=0.0, smooth=False, vcol=vc_dais))
    # ---- monolith
    mprof = [(0, 1.10), (0.05, 1.14), (0.11, 1.02), (0.27, 0.97), (0.295, 1.09), (0.345, 1.09), (0.37, 0.95),
             (0.60, 0.86), (0.80, 0.78), (0.93, 0.72), (1.0, 0.66)]
    SH.monolith(b, 'mono', H_MONO, 0.85, 0.58, mprof, n=24 if hi else 12, extra=16 if hi else 0, p=4.0, lean=0.012,
                twist=0.06, cut=0.12, cut_phi=math.radians(200), jit=0.07, seed=2.0,
                transform=SH.xform((0, 0, DAIS_TOP)),
                meta=dict(ppm=150, seed=20, layouts={'F': mono_front, 'B': mono_back, 'L': mono_side, 'R': mono_side, 'T': mono_top},
                          opts=dict(moss=1.0, moss_h=1.3), z0=0.0, smooth=True, vcol=vc_mono, sharp_deg=62))
    # ---- shards (leaning in toward the monolith)
    shard_prof = [(0, 1.05), (0.1, 1.0), (0.5, 0.82), (0.85, 0.66), (1.0, 0.5)]
    for (ang, r, hh, seed) in ((150, 1.75, 3.3, 3.0), (20, 1.85, 2.3, 4.0)):
        a = math.radians(ang)
        pos = (r * math.cos(a), r * math.sin(a), DAIS_TOP)
        yaw = a + math.pi / 2                       # local -Y (front) -> outward
        SH.monolith(b, 'shard', hh, 0.42, 0.30, shard_prof, n=16 if hi else 10, extra=8 if hi else 0, p=3.5, lean=0.0, cut=0.20,
                    cut_phi=math.radians(90 + seed * 40), jit=0.06, seed=seed,
                    transform=SH.xform(pos, yaw=yaw, tilt_x=math.radians(-10)),
                    meta=dict(ppm=130, seed=30, layouts={'F': shard_front, 'L': shard_side, 'R': shard_side},
                              opts=dict(moss=1.0, moss_h=0.9), z0=0.0, smooth=True, vcol=vc_shard, sharp_deg=62))
    # ---- ward menhirs on the outer ring
    mp = [(0, 1.1), (0.15, 1.0), (0.7, 0.86), (1.0, 0.62)]
    for k in range(6):
        a = math.radians(30 + k * 60 + (8 if k % 2 else -6))
        r = 4.35 + (0.15 if k % 2 else 0)
        hh = 1.35 + 0.3 * math.sin(k * 2.1)
        SH.monolith(b, 'menhir', hh, 0.32, 0.22, mp, n=12 if hi else 8, extra=5 if hi else 0, p=3.0, lean=0.05 * (1 if k % 2 else -1),
                    cut=0.25, cut_phi=k * 1.1, jit=0.07, seed=5.0 + k,
                    transform=SH.xform((r * math.cos(a), r * math.sin(a), -0.06), yaw=a + math.pi / 2 + 0.15 * math.sin(k)),
                    meta=dict(ppm=110, seed=40, layouts={'F': menhir_front}, opts=dict(moss=1.1, moss_h=0.7),
                              z0=0.0, smooth=True, vcol=vc_menhir, sharp_deg=62))
    # ---- rubble
    rs = random.Random(11)
    for k in range(8 if hi else 5):
        a = rs.uniform(0, 2 * math.pi)
        r = rs.uniform(3.7, 5.2)
        s = rs.uniform(0.28, 0.6)
        SH.rock(b, 'rock', (s, s * rs.uniform(0.8, 1.2), s * 0.8), sub=2 if hi else 1, seed=k * 1.7,
                transform=SH.xform((r * math.cos(a), r * math.sin(a), s * 0.12), yaw=a),
                meta=dict(ppm=90, seed=50, layouts={}, opts=dict(moss=1.2, moss_h=0.3), smooth=True, vcol=vc_rock, sharp_deg=70))


sc = bpy.context.scene
bpy.ops.wm.read_factory_settings(use_empty=True)
os.makedirs(OUT, exist_ok=True)
objs, paths, npath, tex = SPI.run_set('elder_stone', build, OUT, atlas=(2048, 2048), lods=(0, 1), jpg_q=88)
for lod, (ob, mats) in objs.items():
    print("TRIS", lod, SK.tri_total(ob))
    SK.export_glb(ob, os.path.join(OUT, f'elder_stone_lod{lod}.glb'))
    ob.data.materials[0] = mats['gold']
    os.makedirs(os.path.join(OUT, '_work'), exist_ok=True)
    SK.export_glb(ob, os.path.join(OUT, '_work', f'elder_stone_gold_lod{lod}.glb'))
