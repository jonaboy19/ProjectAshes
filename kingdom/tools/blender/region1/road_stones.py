"""4 road-stone variants. blender -b --python road_stones.py -- <out_dir>"""
import bpy, math, os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
import paint as P
import stonekit as SK
import stonepipe as SPI
import stoneshapes as SH

OUT = sys.argv[sys.argv.index("--") + 1]
RK = P.RUNE_KEYS


def lay_slab(d, c):
    H = c.vmax
    d.line([(0, 0.25), (0, H - 0.55)], wm=0.07)
    for i in range(3):
        d.rune(RK[(i * 4 + 2) % len(RK)], (-1) ** i * 0.17, 0.4 + i * 0.32, 0.22, wm=0.035)
    d.circle(0, H - 0.4, 0.13, 0.05)


def lay_point(d, c):
    H = c.vmax
    for k, r in enumerate((0.09, 0.17, 0.25)):
        d.circle(0, 0.75, r, 0.05, a0=0.5 * k, a1=0.5 * k + 5.2)
    d.line([(0, 0.25), (0, 0.5)], wm=0.06)
    for i in range(3):
        d.line([(-0.2, 1.15 + i * 0.22 + 0.12), (0, 1.15 + i * 0.22), (0.2, 1.15 + i * 0.22 + 0.12)], wm=0.05)


def lay_squat(d, c):
    d.line([(-0.5, 0.42), (0.5, 0.42)], wm=0.05, weight=0.9)
    for i in range(6):
        d.rune(RK[(i * 3 + 1) % len(RK)], -0.45 + i * 0.18, 0.5, 0.2, wm=0.03)
    d.diamond(0, 0.26, 0.11, wm=0.045)
    d.line([(-0.5, 0.15), (0.5, 0.15)], wm=0.04, weight=0.6)


def lay_pillar(d, c):
    H = c.vmax
    d.circle(0, H - 0.5, 0.15, 0.05)
    d.dot(0, H - 0.5, 0.08)
    d.line([(0, 0.3), (0, H - 0.75)], wm=0.06)
    d.diamond(0, 0.65, 0.15, wm=0.04)
    d.rune('othala', -0.12, 0.85, 0.3, wm=0.035)


def lay_ring(d, c):
    d.circle(0, 0, 0.62, 0.05)
    for k in range(10):
        a = 2 * math.pi * k / 10
        d.rune(RK[k % len(RK)], 0.8 * math.cos(a), 0.8 * math.sin(a) - 0.05, 0.1, wm=0.02, weight=0.7, rot=a - math.pi / 2)


def vc_body(H):
    return lambda co: (0.2 + 0.8 * min(1.0, max(0.0, co.z / H)), 1.0, 0.6 + 0.4 * min(1.0, co.z / 0.7))


def vc_base(co):
    return (0.1, 1.0, 0.85)


def vc_rock(co):
    return (0.0, 0.0, 0.7)


def make(spec):
    name, H, a, bd, p, prof, lay, kw, seed = spec

    def build(b, lod):
        hi = lod == 0
        SH.lathe(b, 'base', [(0.95, 0.0), (0.95, 0.09), (0.86, 0.13), (0.45, 0.13)], N=16 if hi else 10, jit=0.03, seed=seed,
                 meta=dict(ppm=150, seed=seed, layouts={'T': lay_ring}, opts=dict(moss=1.0, moss_h=0.1, depth=0.012),
                           smooth=False, vcol=vc_base), chart_fn=SK.cyl_chart_factory(0.9))
        SH.monolith(b, 'body', H, a, bd, prof, n=16 if hi else 10, extra=8 if hi else 0, p=p, jit=0.06, seed=seed,
                    transform=SH.xform((0, 0, 0.12)),
                    meta=dict(ppm=300, seed=seed + 5, layouts={'F': lay, 'L': lambda d, c: d.line([(0, 0.3), (0, c.vmax - 0.5)], wm=0.05, weight=0.7),
                                                          'R': lambda d, c: d.line([(0, 0.3), (0, c.vmax - 0.5)], wm=0.05, weight=0.7)},
                              opts=dict(moss=1.0, moss_h=0.5, depth=0.014), smooth=True, vcol=vc_body(H), sharp_deg=62), **kw)
        rs = random.Random(seed)
        for k in range(3 if hi else 2):
            ang = rs.uniform(0, 6.28)
            s = rs.uniform(0.12, 0.22)
            SH.rock(b, 'rock', (s, s, s * 0.8), sub=1, seed=k * 1.3 + seed,
                    transform=SH.xform((1.05 * math.cos(ang), 1.05 * math.sin(ang), s * 0.1), yaw=ang),
                    meta=dict(ppm=120, seed=seed + 9, layouts={}, opts=dict(moss=1.2, moss_h=0.2), smooth=True, vcol=vc_rock, sharp_deg=70))
    return build


SPECS = [
    # name, H, a, bd, p, profile, layout, monolith kwargs, seed
    ('road_stone_a_slab', 1.55, 0.45, 0.17, 5.0, [(0, 1.05), (0.1, 1.0), (0.8, 0.94), (1.0, 0.8)], lay_slab, dict(cut=0.10, cut_phi=1.0, lean=0.03), 1.0),
    ('road_stone_b_menhir', 2.0, 0.34, 0.27, 3.0, [(0, 1.1), (0.15, 1.0), (0.6, 0.78), (0.9, 0.5), (1.0, 0.22)], lay_point, dict(cut=0.05, lean=-0.03, twist=0.15), 2.0),
    ('road_stone_c_squat', 1.0, 0.62, 0.42, 3.2, [(0, 1.08), (0.2, 1.0), (0.6, 0.95), (0.85, 0.85), (1.0, 0.7)], lay_squat, dict(cut=0.18, cut_phi=2.4), 3.0),
    ('road_stone_d_pillar', 1.7, 0.28, 0.26, 2.4, [(0, 1.1), (0.1, 1.0), (0.42, 0.96), (0.46, 1.16), (0.54, 1.16), (0.58, 0.94), (0.9, 0.88), (1.0, 0.8)], lay_pillar, dict(cut=0.14, cut_phi=4.0, twist=0.08), 4.0),
]

bpy.ops.wm.read_factory_settings(use_empty=True)
for spec in SPECS:
    name = spec[0]
    objs, paths, npath, tex = SPI.run_set(name, make(spec), OUT, atlas=(512, 512), lods=(0, 1), jpg_q=88, normal_down=False, emis_down=False)
    for lod, (ob, mats) in objs.items():
        print("TRIS", name, lod, SK.tri_total(ob))
        SK.export_glb(ob, os.path.join(OUT, f'{name}_lod{lod}.glb'))
        if lod == 0:
            ob.data.materials[0] = mats['gold']
            os.makedirs(os.path.join(OUT, '_work'), exist_ok=True)
            SK.export_glb(ob, os.path.join(OUT, '_work', f'{name}_gold_lod0.glb'))
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
