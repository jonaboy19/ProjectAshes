"""Highwatch Keep kit (Region 1, L2).
blender -b --python highwatch_kit.py -- <repo kingdom dir> <out_dir> [preview_dir]

Sources: CC0 Meshy community models (meshy_free). Each is scaled, decimated (LOD0/LOD1), colour-graded to one warm
palette and re-mapped into ONE shared 2048 atlas, together with Blender-built connectors (walls, banners, yard).
Outputs glb (no embedded textures: assign highwatch_kit.tres), atlas jpgs, site layout json, previews."""
import bpy, bmesh, math, os, sys, json, random
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(__file__))
import r1lib as L
import paint as P
import kitpaint as KP
import stonekit as SK
import stoneshapes as SH

KD, OUT = sys.argv[sys.argv.index("--") + 1], sys.argv[sys.argv.index("--") + 2]
PREV = sys.argv[sys.argv.index("--") + 3] if len(sys.argv) > sys.argv.index("--") + 3 else None
MF = os.path.join(KD, 'assets', 'incoming', 'meshy_free')
ATLAS = 2048
PPM_T = float(os.environ.get('KIT_PPM', '38'))
WALL_L = 14.6

SOURCES = {
    # id: (relpath, mode, value, (tris0, tris1), grade, ppm_target)
    'gate':        ('castle/gate_twin_towers_blue_lod0.glb', 'w', 14.0, (4800, 1600), 'stone_blue', 40),
    'tower_round': ('castle/tower_round_lod0.glb', 'h', 10.6, (3000, 900), 'stone', 40),
    'watchtower':  ('castle/watchtower_stone_small_lod0.glb', 'h', 8.6, (3200, 1000), 'stone', 40),
    'keep':        ('castle/keep_small_on_plinth_lod0.glb', 'w', 16.0, (7600, 2400), 'stone_flags', 36),
    'rack_swords': ('interior/weapon_rack_swords_lod0.glb', 'h', 1.9, (700, 260), 'wood', 90),
    'rack_spears': ('interior/weapon_racks_spears_lod0.glb', 'h', 2.4, (700, 260), 'wood', 90),
    'armour':      ('interior/armour_stand_knight_lod0.glb', 'h', 2.1, (1000, 320), 'keep', 90),
    'shield':      ('props/shield_dragon_heraldic_lod0.glb', 'w', 1.0, (450, 160), 'keep', 90),
    'torch':       ('lighting/torch_stake_lod0.glb', 'h', 1.7, (220, 100), 'wood', 90),
    'well':        ('props/well_stone_roofed_lod0.glb', 'h', 3.0, (1200, 420), 'stone', 70),
    'barrels':     ('props/barrels_crates_stack_lod0.glb', 'w', 2.4, (700, 260), 'wood', 90),
    'hay':         ('farm/hay_bale_lowpoly_lod0.glb', 'w', 1.3, (260, 100), 'keep', 70),
}

if os.environ.get('KIT_ONLY'):
    SOURCES = {k: v for k, v in SOURCES.items() if k in os.environ['KIT_ONLY'].split(',')}
TILE_PX_UNUSED = {'gate': 960, 'tower_round': 576, 'watchtower': 512, 'keep': 896, 'rack_swords': 224, 'rack_spears': 256, 'armour': 256, 'shield': 128, 'torch': 96, 'well': 256, 'barrels': 256, 'hay': 160}
sc = L.reset()
L.engine(sc)


# ------------------------------------------------------------------------------------------ sources
def import_piece(path, mode, val, ref_xf=None):
    """import one glb as a single grounded mesh, scaled to `val`; returns (mesh, image pixels, xf) where xf reproduces the transform."""
    imgs_before = set(bpy.data.images)
    objs = L.import_glb(path)
    ms = L.meshes(objs)
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn, mx = L.bbox([ob])
    if ref_xf is None:
        ref = (mx.z - mn.z) if mode == 'h' else max(mx.x - mn.x, mx.y - mn.y)
        s_ = val / ref
        off = Vector((-(mn.x + mx.x) / 2 * s_, -(mn.y + mx.y) / 2 * s_, -mn.z * s_))
        xf = (s_, off)
    else:
        xf = ref_xf
    s_, off = xf
    ob.scale = (s_, s_, s_)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ob.location = off
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    for o in objs:
        if o is not ob and o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    img = [i for i in bpy.data.images if i not in imgs_before and i.size[0] > 4][0]
    me = ob.data.copy()
    me.materials.clear()
    me.uv_layers[0].name = 'UVMap'
    for pl in me.polygons:
        pl.use_smooth = True
    bpy.data.objects.remove(ob)
    img.colorspace_settings.name = 'Non-Color'
    w, h = img.size
    px = np.array(img.pixels[:], np.float32).reshape(h, w, 4)[..., :3][::-1].copy()
    return me, px, xf


def uv_density(me, px):
    me.calc_loop_triangles()
    uvl = me.uv_layers[0].data
    a3 = 0.0
    auv = 0.0
    for tri in me.loop_triangles:
        v = [me.vertices[i].co for i in tri.vertices]
        a3 += ((v[1] - v[0]).cross(v[2] - v[0])).length * 0.5
        u = [uvl[l].uv for l in tri.loops]
        auv += abs((u[1][0] - u[0][0]) * (u[2][1] - u[0][1]) - (u[2][0] - u[0][0]) * (u[1][1] - u[0][1])) * 0.5
    return math.sqrt(max(auv, 1e-6) * px.shape[0] * px.shape[1] / max(a3, 1e-6)), a3, len(me.loop_triangles)


def prep_source(key, spec):
    rel, mode, val, (t0, t1), grade, ppm_t = spec
    m0, px0, xf = import_piece(os.path.join(MF, rel), mode, val)
    ppm0, area, tris0 = uv_density(m0, px0)
    d = dict(key=key, m0=m0, px0=px0, ppm0=ppm0, grade=grade, ppm_t=ppm_t, area=area, tris0=tris0)
    p1 = os.path.join(MF, rel.replace('_lod0', '_lod1'))
    if os.path.exists(p1):
        m1, px1, _ = import_piece(p1, mode, val, xf)
        d['m1'], d['px1'] = m1, px1
        d['ppm1'] = uv_density(m1, px1)[0]
        d['lod1'] = 'shipped'
    else:
        d['m1'], d['px1'], d['ppm1'] = None, None, 0
        d['lod1'] = 'decimated'
    mn = Vector((min(v.co.x for v in m0.vertices), min(v.co.y for v in m0.vertices), min(v.co.z for v in m0.vertices)))
    mx = Vector((max(v.co.x for v in m0.vertices), max(v.co.y for v in m0.vertices), max(v.co.z for v in m0.vertices)))
    d['dims'] = tuple(mx - mn)
    print(f"[src {key}] {tris0} tris, native {ppm0:.1f} px/m, lod1 {d['lod1']}, dims {d['dims'][0]:.1f}x{d['dims'][1]:.1f}x{d['dims'][2]:.1f}")
    return d


src = {k: prep_source(k, v) for k, v in SOURCES.items()}


def make_lod1_decimated():
    for k, s_ in src.items():
        if s_['m1'] is not None:
            continue
        ob = bpy.data.objects.new('l1_' + k, s_['m0'].copy())
        bpy.context.scene.collection.objects.link(ob)
        m = ob.modifiers.new('d', 'DECIMATE')
        m.ratio = 0.3
        m.use_collapse_triangulate = True
        try:
            m.delimit = {'UV'}
        except Exception:
            pass
        ev = ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
        s_['m1'] = bpy.data.meshes.new_from_object(ev)
        s_['m1'].materials.clear()
        s_['ppm1'] = s_['ppm0']
        s_['px1'] = None      # shares the LOD0 tile
        bpy.data.objects.remove(ob)


make_lod1_decimated()

# ------------------------------------------------------------------------------------------ built geometry
B = {}    # piece name -> {'b': SK.Builder per lod}


def add_box(b, name, cx, cy, z0, sx, sy, sz, chart, meta=None, taper=1.0, yaw=0.0):
    """axis-aligned box (bottom at z0) with optional top taper (scales top ring around centre)."""
    hx, hy = sx / 2, sy / 2
    bot = [(-hx, -hy, 0), (hx, -hy, 0), (hx, hy, 0), (-hx, hy, 0)]
    top = [(-hx * taper, -hy * taper, sz), (hx * taper, -hy * taper, sz), (hx * taper, hy * taper, sz), (-hx * taper, hy * taper, sz)]
    fs, vs = b.ring_solid([bot, top], cap_top=True, cap_bottom=False)
    m = Matrix.Translation((cx, cy, z0)) @ Matrix.Rotation(yaw, 4, 'Z')
    b.finish_part(name, fs, chart, m, meta)


def gen_chart(prefix):
    def fn(f):
        key, co = SK.box_chart(f)
        return 'G', [(u * 0.9 % 1.0 if False else u, v) for (u, v) in co]
    return fn


def gen_tile(f):
    """generic tile chart: coords relative to the face centre placed in the middle of a 1x1 m tile (clamped)."""
    key, co = SK.box_chart(f)
    cu = sum(c[0] for c in co) / len(co)
    cv = sum(c[1] for c in co) / len(co)
    c0 = f.calc_center_median()
    j = ((int(abs(c0.x) * 977 + abs(c0.y) * 613 + abs(c0.z) * 331)) % 100) / 100.0
    return 'G', [(0.5 + 0.35 * (j - 0.5) + (u - cu), 0.5 + 0.35 * (1 - j - 0.5) + (v - cv)) for (u, v) in co]


def wall_piece(b, lod):
    hi = lod == 0
    Lm, T, Hh = WALL_L, 2.4, 6.4
    ch = SK.box_chart
    # body with batter
    fs, vs = b.ring_solid([[(-Lm / 2, -1.45, 0), (Lm / 2, -1.45, 0), (Lm / 2, 1.45, 0), (-Lm / 2, 1.45, 0)],
                           [(-Lm / 2, -1.30, 0.9), (Lm / 2, -1.30, 0.9), (Lm / 2, 1.30, 0.9), (-Lm / 2, 1.30, 0.9)],
                           [(-Lm / 2, -1.2, Hh), (Lm / 2, -1.2, Hh), (Lm / 2, 1.2, Hh), (-Lm / 2, 1.2, Hh)]], cap_top=True, cap_bottom=False)
    b.finish_part('wall', fs, ch, None)
    if hi:
        n = 7
        for i in range(n):
            x = -Lm / 2 + 0.9 + i * (Lm - 1.8) / (n - 1)
            add_box(b, 'wall', x, -0.85, Hh, 1.25, 0.65, 1.15, ch, taper=0.94)
        for x in (-4.4, 4.4):
            add_box(b, 'wall', x, -1.55, 0, 1.5, 0.75, Hh + 0.35, ch, taper=0.9)
    else:
        add_box(b, 'wall', 0, -0.85, Hh, Lm - 0.6, 0.65, 0.9, ch)


def banner_piece(b, lod):
    hi = lod == 0
    # pole
    N = 8 if hi else 6
    rings = [[(0.06 * math.cos(2 * math.pi * i / N), 0.06 * math.sin(2 * math.pi * i / N), z) for i in range(N)] for z in (0, 3.9)]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=False)
    b.finish_part('gen_wood', fs, gen_tile, None)
    add_box(b, 'gen_wood', 0, 0, 3.55, 1.05, 0.06, 0.07, gen_tile)
    add_box(b, 'gen_wood', 0, 0, 0, 0.5, 0.5, 0.12, gen_tile, taper=0.8)
    # spear finial
    rings = [[(0.05 * math.cos(2 * math.pi * i / N), 0.05 * math.sin(2 * math.pi * i / N), z) for i in range(N)] for z in (3.9, 4.05)] + \
            [[(0.0 + 0.001 * math.cos(2 * math.pi * i / N), 0.001 * math.sin(2 * math.pi * i / N), 4.3) for i in range(N)]]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=False)
    b.finish_part('gen_gold', fs, gen_tile, None)
    # cloth: swallow-tail banner, waved, double sided thin slab
    bm = b.bm
    rows = 6 if hi else 2
    W, Hc, y0 = 0.95, 2.1, 3.5
    xs = [-W / 2, 0, W / 2]
    cols = []
    for r in range(rows + 1):
        t = r / rows
        z = y0 - Hc * t
        wave = 0.05 * math.sin(t * 5.0 + 0.6) * (0.3 + t)
        cols.append([(x, wave + (0.012 if False else 0), z) for x in (-W / 2, -W / 4, 0, W / 4, W / 2)])
    # swallow-tail: pull the middle of last row up
    cols[-1][2] = (0, cols[-1][2][1], cols[-1][2][2] + 0.28)
    def cloth_face(front):
        vv = [[bm.verts.new((x, y + (-0.02 if front else 0.02), z)) for (x, y, z) in row] for row in cols]
        fl = []
        for r in range(rows):
            for c in range(4):
                a, bq, cq, d = vv[r][c], vv[r][c + 1], vv[r + 1][c + 1], vv[r + 1][c]
                fl.append(bm.faces.new((a, d, cq, bq) if front else (a, bq, cq, d)))
        return fl
    fs = cloth_face(True) + cloth_face(False)
    b.finish_part('banner_cloth', fs, SK.box_chart, None)


def dummy_piece(b, lod, prefix='dm'):
    ch = gen_tile
    add_box(b, 'gen_wood', 0, 0, 0, 0.9, 0.12, 0.10, ch)
    add_box(b, 'gen_wood', 0, 0, 0, 0.12, 0.9, 0.10, ch)
    add_box(b, 'gen_wood', 0, 0, 0.1, 0.14, 0.14, 1.75, ch)
    add_box(b, 'gen_wood', 0, 0, 1.25, 1.15, 0.10, 0.10, ch)
    N = 8
    rings = [[(0.27 * math.cos(2 * math.pi * i / N), 0.22 * math.sin(2 * math.pi * i / N), z) for i in range(N)] for z in (0.75, 0.95, 1.4, 1.55)]
    rings[1] = [(x * 1.08, y * 1.08, z) for (x, y, z) in rings[1]]
    rings[2] = [(x * 1.08, y * 1.08, z) for (x, y, z) in rings[2]]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=True)
    b.finish_part('gen_straw', fs, gen_tile, None)
    rings = [[(0.14 * math.cos(2 * math.pi * i / N) * s, 0.14 * math.sin(2 * math.pi * i / N) * s, 1.62 + zz) for i in range(N)] for (zz, s) in ((0, 0.6), (0.1, 1.0), (0.24, 0.9), (0.32, 0.4))]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=True)
    b.finish_part('gen_straw', fs, gen_tile, None)


def target_piece(b, lod):
    N = 16
    R = 0.55
    zc = 1.05
    rings = [[(R * math.cos(2 * math.pi * i / N), -0.08 + (0 if k == 0 else 0.16), zc + R * math.sin(2 * math.pi * i / N)) for i in range(N)] for k in (0, 1)]
    # disc built in XZ plane facing -Y: use ring_solid rings along y is awkward; build faces manually
    bm = b.bm
    f_ring = [bm.verts.new((R * math.cos(2 * math.pi * i / N), -0.06, zc + R * math.sin(2 * math.pi * i / N))) for i in range(N)]
    b_ring = [bm.verts.new((R * math.cos(2 * math.pi * i / N), 0.08, zc + R * math.sin(2 * math.pi * i / N))) for i in range(N)]
    fs = [bm.faces.new(f_ring[::-1] if False else f_ring)]
    fs[0].normal_update()
    if fs[0].normal.y > 0:
        fs[0].normal_flip()
    fs.append(bm.faces.new(b_ring))
    fs[1].normal_update()
    if fs[1].normal.y < 0:
        fs[1].normal_flip()
    for i in range(N):
        q = bm.faces.new((f_ring[i], f_ring[(i + 1) % N], b_ring[(i + 1) % N], b_ring[i]))
        fs.append(q)
    b.finish_part('target_disc', fs, SK.box_chart, None)
    for (lx, ang) in ((-0.55, 0.28), (0.55, -0.28), (0.0, 0.0)):
        pass
    add_box(b, 'gen_wood', -0.5, 0.35, 0, 0.09, 0.09, 1.1, gen_tile, taper=0.8, yaw=0.3)
    add_box(b, 'gen_wood', 0.5, 0.35, 0, 0.09, 0.09, 1.1, gen_tile, taper=0.8, yaw=-0.3)
    add_box(b, 'gen_wood', 0, 0.5, 0, 0.09, 0.09, 1.2, gen_tile, taper=0.8)


def yard_ground(b, lod, w=11.0, d=15.0):
    Z = 0.14
    rings = [[(-w / 2, -d / 2, 0), (w / 2, -d / 2, 0), (w / 2, d / 2, 0), (-w / 2, d / 2, 0)],
             [(-w / 2 + 0.05, -d / 2 + 0.05, 0.10), (w / 2 - 0.05, -d / 2 + 0.05, 0.10), (w / 2 - 0.05, d / 2 - 0.05, 0.10), (-w / 2 + 0.05, d / 2 - 0.05, 0.10)],
             [(-w / 2 + 0.25, -d / 2 + 0.25, Z), (w / 2 - 0.25, -d / 2 + 0.25, Z), (w / 2 - 0.25, d / 2 - 0.25, Z), (-w / 2 + 0.25, d / 2 - 0.25, Z)]]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=False)
    b.finish_part('yard_ground', fs, SK.box_chart, None)


def yard_fence(b, lod, w=11.0, d=15.0):
    ch = gen_tile
    sides = [((-w / 2 + 0.3, -d / 2 + 0.3), (-w / 2 + 0.3, d / 2 - 0.3)),        # west
             ((-w / 2 + 0.3, d / 2 - 0.3), (w / 2 - 0.3, d / 2 - 0.3)),          # north
             ((-w / 2 + 0.3, -d / 2 + 0.3), (w / 2 - 0.3, -d / 2 + 0.3))]        # south
    for (p0, p1) in sides:
        ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        n = max(2, int(ln / 2.4))
        yaw = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
        for i in range(n + 1):
            t = i / n
            add_box(b, 'gen_wood', p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t, 0.1, 0.16, 0.16, 1.25, ch, taper=0.85)
        for zc in (0.55, 0.95):
            add_box(b, 'gen_wood', (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, zc, ln, 0.07, 0.11, ch, yaw=0.0 if False else 0.0) if False else None
            # rails as rotated boxes
            add_box_rot(b, 'gen_wood', (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, zc, ln, 0.07, 0.11, ch, yaw)


def add_box_rot(b, name, cx, cy, z0, sx, sy, sz, chart, yaw):
    add_box(b, name, cx, cy, z0, sx, sy, sz, chart, yaw=yaw)


def plinth_piece(b, lod, w=2.4, d=2.4):
    add_box(b, 'post_base', 0, 0, 0, w, d, 0.16, SK.box_chart, taper=0.96)


def roof_piece(b, lod):
    N = 14 if lod == 0 else 8
    prof = [(3.75, 0.0), (3.35, 0.32), (2.75, 1.25), (1.7, 2.9), (0.75, 4.2), (0.10, 5.0)]
    rings = []
    for (r, z) in prof:
        rings.append([(r * math.cos(2 * math.pi * i / N), r * math.sin(2 * math.pi * i / N), z) for i in range(N)])
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=False)
    b.finish_part('roof', fs, SK.cyl_chart_factory(3.0), None)
    M = 6 if lod == 0 else 4
    rings = [[(0.07 * math.cos(2 * math.pi * i / M) * sc_, 0.07 * math.sin(2 * math.pi * i / M) * sc_, 5.0 + z) for i in range(M)] for (z, sc_) in ((0, 1.0), (0.5, 0.8), (0.95, 0.0001))]
    fs, vs = b.ring_solid(rings, cap_top=True, cap_bottom=False)
    b.finish_part('gen_gold', fs, gen_tile, None)


BUILT_CHARTS_PPM = {'roof': 34, 'wall': 40, 'yard_ground': 28, 'banner_cloth': 120, 'target_disc': 110, 'post_base': 40}


# ------------------------------------------------------------------------------------------ atlas planning
def collect_requests(builders):
    """chart requests: sources (square tiles incl. padding) + built charts (incl. padding)"""
    req = {}
    bounds = {}
    for b in builders:
        for (nm, key), bd in SPI_bounds(b.parts).items():
            cur = bounds.setdefault((nm, key), list(bd))
            cur[0] = min(cur[0], bd[0]); cur[1] = max(cur[1], bd[1]); cur[2] = min(cur[2], bd[2]); cur[3] = max(cur[3], bd[3])
    for (nm, key), bd in bounds.items():
        wm, hm = bd[1] - bd[0], bd[3] - bd[2]
        if nm.startswith('gen_'):
            wm, hm = 1.0, 1.0
            bd[0], bd[1], bd[2], bd[3] = 0.0, 1.0, 0.0, 1.0
        req[('built', nm, key)] = (max(wm, 0.35), max(hm, 0.35), BUILT_CHARTS_PPM.get(nm, 90 if nm.startswith('gen_') else 40))
    return req, bounds


def SPI_bounds(parts):
    out = {}
    for p in parts:
        for (f, key, co) in p['faces']:
            b = out.setdefault((p['name'], key), [1e9, -1e9, 1e9, -1e9])
            for (u, v) in co:
                b[0] = min(b[0], u); b[1] = max(b[1], u); b[2] = min(b[2], v); b[3] = max(b[3], v)
    return out


# build every LOD of every built piece
built = {}
for name, fn in (('wall', wall_piece), ('banner', banner_piece)):
    built[name] = {}
    for lod in (0, 1):
        bb = SK.Builder(); fn(bb, lod); built[name][lod] = bb


def dummy_target_builder(fn):
    bb = SK.Builder(); fn(bb, 0); return bb


built['dummy'] = {0: dummy_target_builder(dummy_piece), 1: dummy_target_builder(dummy_piece)}
built['target'] = {0: dummy_target_builder(target_piece), 1: dummy_target_builder(target_piece)}
built['yard_ground'] = {0: dummy_target_builder(yard_ground), 1: dummy_target_builder(yard_ground)}
built['yard_fence'] = {0: dummy_target_builder(yard_fence), 1: dummy_target_builder(yard_fence)}
built['roof'] = {0: dummy_target_builder(roof_piece), 1: dummy_target_builder(lambda bb, lod: roof_piece(bb, 1))}
built['plinth'] = {0: dummy_target_builder(plinth_piece), 1: dummy_target_builder(plinth_piece)}

allb = [bb for d in built.values() for bb in d.values()]
req0, bounds = collect_requests(allb)
BASE_PPM = 36.0
# requests in metres so one uniform scale search keeps every chart at the same relative density
REL = {}
for k, v in req0.items():
    REL[k] = (v[0], v[1], v[2] / BASE_PPM)
for k, s_ in src.items():
    for lod in (0, 1):
        if lod == 1 and s_['px1'] is None:
            continue
        px = s_['px0'] if lod == 0 else s_['px1']
        ppm_native = s_['ppm0'] if lod == 0 else s_['ppm1']
        size_m = max(px.shape[:2]) / ppm_native
        want = 1.0 if s_['ppm_t'] <= 40 else (2.2 if s_['ppm_t'] >= 90 else 1.7)
        if lod == 1:
            want *= 0.5
        cap = ppm_native / BASE_PPM            # never above the source's own density
        REL[('src', k, lod)] = (size_m + 8 / 20.0, size_m + 8 / 20.0, min(want, cap))
sc_ = 1.0
while True:
    req = {k: (max(10, int(v[0] * v[2] * BASE_PPM * sc_) + 6), max(10, int(v[1] * v[2] * BASE_PPM * sc_) + 6), 1.0) for k, v in REL.items()}
    try:
        rects, ps = SK.pack(req, ATLAS, ATLAS, gap=2)
    except RuntimeError:
        sc_ *= 0.94
        continue
    if ps < 0.999:
        sc_ *= 0.94
        continue
    break
ppm_abs = {k: v[2] * BASE_PPM * sc_ for k, v in REL.items()}
print(f"[atlas] {len(rects)} rects, architecture density {BASE_PPM * sc_:.1f} px/m (fill {sum(w * h for (x, y, w, h) in rects.values()) / ATLAS ** 2:.2f})")
for k in list(req0):
    req0[k] = (req0[k][0], req0[k][1], ppm_abs[k])

# ------------------------------------------------------------------------------------------ paint atlas
atlas = np.zeros((ATLAS, ATLAS, 3), np.float32)
atlas[:] = P.rgb(0.62, 0.56, 0.48)


def resize(px, S):
    h, w = px.shape[:2]
    ys = (np.arange(S) + 0.5) * h / S - 0.5
    xs = (np.arange(S) + 0.5) * w / S - 0.5
    if S >= w:
        y0 = np.clip(np.floor(ys).astype(int), 0, h - 1); x0 = np.clip(np.floor(xs).astype(int), 0, w - 1)
        y1 = np.clip(y0 + 1, 0, h - 1); x1 = np.clip(x0 + 1, 0, w - 1)
        fy = (ys - y0)[:, None, None]; fx = (xs - x0)[None, :, None]
        return (px[y0][:, x0] * (1 - fx) + px[y0][:, x1] * fx) * (1 - fy) + (px[y1][:, x0] * (1 - fx) + px[y1][:, x1] * fx) * fy
    # box filter for downscale
    f = w / S
    k = int(math.ceil(f))
    out = np.zeros((S, S, 3), np.float32)
    ys_i = (np.arange(S) * h / S).astype(int); xs_i = (np.arange(S) * w / S).astype(int)
    acc = np.zeros((S, S, 3), np.float32)
    n = 0
    for dy in range(k):
        for dx in range(k):
            acc += px[np.clip(ys_i + dy, 0, h - 1)][:, np.clip(xs_i + dx, 0, w - 1)]
            n += 1
    return acc / n


src_tile = {}
for k, s_ in src.items():
    for lod in (0, 1):
        if lod == 1 and s_['px1'] is None:
            continue
        px = s_['px0'] if lod == 0 else s_['px1']
        rx, ry, rw, rh = rects[('src', k, lod)]
        S = min(rw, rh) - 8
        t = KP.grade(resize(px, S), s_['grade'])
        pad = np.pad(t, ((4, 4), (4, 4), (0, 0)), mode='edge')
        atlas[ry:ry + S + 8, rx:rx + S + 8] = pad
        src_tile[(k, lod)] = (rx + 4, ry + 4, S)
        native = (s_['ppm0'] if lod == 0 else s_['ppm1'])
        print(f"[tile {k} lod{lod}] {S}px = {S / (max(px.shape[:2]) / native):.1f} px/m")

built_rect = {}
for k, (rx, ry, rw, rh) in rects.items():
    if k[0] != 'built':
        continue
    nm, key = k[1], k[2]
    bd = bounds[(nm, key)]
    ppm = req0[k][2]
    px_w, px_h = rw - 6, rh - 6
    seed = sum(map(ord, nm + key)) * 7
    if nm == 'wall':
        if key == 'F' or key == 'B':
            img = KP.bricks(px_h, px_w, ppm, seed, slits=[(3.0, 2.6, 0.16, 1.0), (7.3, 2.6, 0.16, 1.0), (11.6, 2.6, 0.16, 1.0)], moss=0.8)
        elif key == 'T':
            img = KP.flagstone(px_h, px_w, ppm, seed, moss=0.05)
        else:
            img = KP.bricks(px_h, px_w, ppm, seed, moss=0.5)
    elif nm == 'roof':
        img = KP.roof_tiles(px_h, px_w, ppm, seed)
    elif nm == 'banner_cloth':
        img = KP.banner_cloth(px_h, px_w, ppm, seed)
    elif nm == 'target_disc':
        img = KP.target_rings(px_h, px_w, ppm, seed) if key == 'F' else KP.straw(px_h, px_w, ppm, seed)
    elif nm == 'yard_ground':
        img = KP.dirt(px_h, px_w, ppm, seed, ring=(px_w * 0.5, px_h * 0.5, min(px_w, px_h) * 0.30) if key == 'T' else None)
    elif nm == 'post_base':
        img = KP.flagstone(px_h, px_w, ppm, seed)
    elif nm == 'gen_wood':
        img = KP.wood(px_h, px_w, ppm, seed)
    elif nm == 'gen_straw':
        img = KP.straw(px_h, px_w, ppm, seed)
    elif nm == 'gen_gold':
        img = np.zeros((px_h, px_w, 3), np.float32); img[:] = KP.GOLD
    else:
        img = np.zeros((px_h, px_w, 3), np.float32); img[:] = P.rgb(0.6, 0.5, 0.4)
    pad = np.pad(img, ((3, 3), (3, 3), (0, 0)), mode='edge')
    atlas[ry:ry + rh, rx:rx + rw] = pad[:rh, :rw]
    built_rect[k] = (rx + 3, ry + 3, px_w, px_h, ppm, bd)

# ------------------------------------------------------------------------------------------ UV assign
def source_mesh(me, key, lod=0):
    tk = (key, lod) if (key, lod) in src_tile else (key, 0)
    rx, ry, S = src_tile[tk]
    me = me.copy()
    uv = me.uv_layers['UVMap'].data
    for l in uv:
        u, v = l.uv
        l.uv = ((rx + min(max(u, 0.0), 1.0) * S) / ATLAS, 1.0 - (ry + (1.0 - min(max(v, 0.0), 1.0)) * S) / ATLAS)
    return me


def builder_mesh(bb, name):
    bm = bb.bm
    uvl = bm.loops.layers.uv.new('UVMap')
    for p in bb.parts:
        for (f, key, co) in p['faces']:
            r = built_rect.get(('built', p['name'], key))
            for l, (u, v) in zip(f.loops, co):
                if r is None:
                    l[uvl].uv = (0.5, 0.5)
                    continue
                rx, ry, rw, rh, ppm, bd = r
                uu = min(max(u, bd[0]), bd[1]); vv = min(max(v, bd[2]), bd[3])
                if p['name'].startswith('gen_'):
                    l[uvl].uv = ((rx + uu * rw) / ATLAS, 1.0 - (ry + (1 - vv) * rh) / ATLAS)
                else:
                    l[uvl].uv = ((rx + (uu - bd[0]) * ppm) / ATLAS, 1.0 - (ry + (bd[3] - vv) * ppm) / ATLAS)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


kit_mesh = {}    # (piece, lod) -> mesh datablock


def merge(name, comps):
    """comps: list of (mesh, Matrix). returns a joined mesh datablock"""
    bm = bmesh.new()
    for me, M in comps:
        n0 = len(bm.verts)
        bm.from_mesh(me)
        bm.verts.ensure_lookup_table()
        bmesh.ops.transform(bm, matrix=M, verts=[bm.verts[i] for i in range(n0, len(bm.verts))])
    out = bpy.data.meshes.new(name)
    bm.to_mesh(out)
    bm.free()
    return out


IDENT = Matrix.Identity(4)
bmesh_cache = {}
for lod in (0, 1):
    for k in src:
        kit_mesh[(k, lod)] = source_mesh(src[k]['m0'] if lod == 0 else src[k]['m1'], k, lod)
    for nm in built:
        # each built builder consumed once (bm freed): make meshes now
        pass
built_me = {}
for nm, d in built.items():
    for lod, bb in d.items():
        built_me[(nm, lod)] = builder_mesh(bb, f'{nm}_{lod}')
        kit_mesh[(nm, lod)] = built_me[(nm, lod)]


def T(x=0, y=0, z=0, yaw=0.0, s=1.0, tilt=0.0):
    m = Matrix.Translation((x, y, z)) @ Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Rotation(math.radians(tilt), 4, 'X')
    return m @ Matrix.Scale(s, 4) if s != 1.0 else m


# clusters (merged into one mesh = one draw call)
def yard(lod):
    comps = [(kit_mesh[('yard_ground', lod)], IDENT), (kit_mesh[('yard_fence', lod)], IDENT)]
    for (x, y, yaw) in ((-2.5, 3.5, 20), (0.5, 5.0, -15), (3.0, 3.0, 200)):
        comps.append((kit_mesh[('dummy', lod)], T(x, y, 0.14, yaw)))
    for (x, y, yaw) in ((-3.5, -4.5, 0), (0.5, -5.0, 8)):
        comps.append((kit_mesh[('target', lod)], T(x, y, 0.14, yaw)))
    comps.append((kit_mesh[('rack_swords', lod)], T(-4.3, 6.4, 0.14, 0)))
    comps.append((kit_mesh[('rack_spears', lod)], T(-1.8, 6.6, 0.14, 0)))
    for (x, y, yaw) in ((4.2, -2.0, 30), (4.4, -3.6, -10), (4.0, 0.5, 80)):
        comps.append((kit_mesh[('hay', lod)], T(x, y, 0.14, yaw)))
    return merge('training_yard', comps)


def guard_post(lod):
    comps = [(kit_mesh[('plinth', lod)], IDENT), (kit_mesh[('armour', lod)], T(0, 0, 0.16, 0)),
             (kit_mesh[('torch', lod)], T(0.95, -0.8, 0.16, 0)), (kit_mesh[('torch', lod)], T(-0.95, -0.8, 0.16, 0)),
             (kit_mesh[('shield', lod)], T(0.75, 0.35, 0.16, 0, tilt=0))]
    return merge('guard_post', comps)


def supplies(lod):
    comps = [(kit_mesh[('barrels', lod)], IDENT), (kit_mesh[('hay', lod)], T(1.9, 0.6, 0, 20)), (kit_mesh[('torch', lod)], T(-1.5, 0.9, 0, 0))]
    return merge('supplies', comps)


PIECES = {}     # name -> {lod: mesh}
for lod in (0, 1):
    for nm in ('gate', 'tower_round', 'watchtower', 'keep', 'well'):
        PIECES.setdefault(nm, {})[lod] = kit_mesh[(nm, lod)]
    PIECES.setdefault('wall_14', {})[lod] = kit_mesh[('wall', lod)]
    PIECES.setdefault('banner_pole', {})[lod] = kit_mesh[('banner', lod)]
    PIECES.setdefault('tower_roof', {})[lod] = kit_mesh[('roof', lod)]
    PIECES.setdefault('training_yard', {})[lod] = yard(lod)
    PIECES.setdefault('guard_post', {})[lod] = guard_post(lod)
    PIECES.setdefault('supplies', {})[lod] = supplies(lod)


def tri_of(me):
    me.calc_loop_triangles()
    return len(me.loop_triangles)


# ------------------------------------------------------------------------------------------ material + atlas files
os.makedirs(OUT, exist_ok=True)
tex_dir = os.path.join(OUT, 'textures')
os.makedirs(tex_dir, exist_ok=True)
tmp = os.path.join(tex_dir, '_tmp.png')
SK.write_png(tmp, SK.to8(atlas))
SK.save_jpg(tmp, os.path.join(tex_dir, 'highwatch_atlas.jpg'), 90)
SK.write_png(tmp, SK.to8(SK.down2(atlas)))
SK.save_jpg(tmp, os.path.join(tex_dir, 'highwatch_atlas_1024.jpg'), 90)
os.remove(tmp)
SK.write_png(os.path.join(OUT, 'textures', '_atlas_preview.png'), SK.to8(SK.down2(atlas)))

atlas_mat = SK.make_material('highwatch_atlas', os.path.join(tex_dir, 'highwatch_atlas.jpg'), None, None, rough=0.9)
plain_mat = bpy.data.materials.new('highwatch_atlas_plain')      # exported (no texture); Godot side assigns highwatch_kit.tres
plain_mat.use_nodes = True
plain_mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9

stats = {}
for nm, d in PIECES.items():
    for lod, me in d.items():
        me.materials.clear()
        me.materials.append(plain_mat)
        ob = bpy.data.objects.new(f'{nm}_lod{lod}', me)
        bpy.context.scene.collection.objects.link(ob)
        stats[(nm, lod)] = tri_of(me)
        kw = dict(filepath=os.path.join(OUT, f'{nm}_lod{lod}.glb'), export_format='GLB', use_selection=True, export_apply=True,
                  export_yup=True, export_image_format='NONE', export_materials='EXPORT', export_cameras=False, export_lights=False)
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.export_scene.gltf(**kw)
        bpy.data.objects.remove(ob)
        me.materials.clear()
        me.materials.append(atlas_mat)

for (nm, lod), t in sorted(stats.items()):
    print("TRIS", nm, lod, t)

# ------------------------------------------------------------------------------------------ layout
def dims_of(me):
    xs = [v.co for v in me.vertices]
    mn = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    mx = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return mn, mx


TX, TY = 24.3, 34.6
LAYOUT = []


def place(piece, x, y, yaw=0.0, z=0.0, note=''):
    LAYOUT.append(dict(piece=piece, x=x, y=y, z=z, yaw=yaw, note=note))


place('gate', 0, 0, 0, note='exterior faces -Y (south / Godot +Z)')
for sx in (-1, 1):
    place('wall_14', sx * 14.0, 0, 0, note='south wing')
for x in (-WALL_L, 0, WALL_L):
    place('wall_14', x, TY, 180, note='north run')
for y in (TY * 0.25, TY * 0.75):
    place('wall_14', TX, y, 90, note='east run')
    place('wall_14', -TX, y, -90, note='west run')
for sx in (-1, 1):
    for y in (0, TY):
        place('tower_round', sx * TX, y, 0, note='corner tower')
        place('tower_roof', sx * TX, y, 0, z=8.75, note='conical blue roof on the corner tower')
    place('watchtower', sx * TX, TY / 2, -90 if sx > 0 else 90, note='mid-wall watchtower, door faces the yard')
place('keep', 0, 23.4, 0, note='keep built into the north wall, faces the gate')
place('training_yard', -16.0, 13.0, 0, note='west yard 11 x 15 m')
place('guard_post', -9.6, 4.2, 15, note='inner gate guard')
place('guard_post', 9.6, 4.2, -15, note='inner gate guard')
place('well', 15.5, 10.0, 0)
place('supplies', 16.5, 20.0, 160)
for (x, y) in ((-8.6, -4.2), (8.6, -4.2), (-3.6, 6.5), (3.6, 6.5), (-5.2, 13.2), (5.2, 13.2)):
    place('banner_pole', x, y, 0)

print("INSTANCES", len(LAYOUT))
# ------------------------------------------------------------------------------------------ preview scene
def preview(path, mode, lod=0):
    bpy.ops.wm.read_factory_settings(use_empty=True) if False else None
    sc2 = bpy.context.scene
    for o in list(sc2.collection.objects):
        bpy.data.objects.remove(o)
    L.engine(sc2)
    sc2.view_settings.view_transform = 'Standard'
    sc2.view_settings.exposure = -0.35
    L.storybook_world(sc2, sky_top=(0.18, 0.42, 0.9), sky_hor=(0.75, 0.88, 1.0), strength=1.0)
    L.sun(sc2, 4.8, (50, 0, 40))
    g = L.ground(sc2, 400, color=(0.40, 0.56, 0.20))
    g.name = 'ground'
    # dirt road from the gate
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -14, 0.02))
    rd = bpy.context.active_object
    rd.scale = (6.0, 60.0, 1)
    m = bpy.data.materials.new('road'); m.use_nodes = True
    m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.66, 0.55, 0.38, 1)
    m.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 1
    rd.data.materials.append(m)
    for it in LAYOUT:
        me = PIECES[it['piece']][lod]
        ob = bpy.data.objects.new(it['piece'], me)
        me.materials.clear(); me.materials.append(atlas_mat)
        ob.location = (it['x'], it['y'], it['z'])
        ob.rotation_euler = (0, 0, math.radians(it['yaw']))
        sc2.collection.objects.link(ob)
    if mode == 'iso':
        L.camera(sc2, (40, -62, 40), (0, 15, 2), lens=36)
    elif mode == 'yard':
        L.camera(sc2, (-6, -4, 14), (-16, 13, 1.2), lens=30)
    elif mode == 'gate':
        L.camera(sc2, (14, -26, 5), (0, 2, 4.5), lens=34)
    elif mode == 'front':
        L.camera(sc2, (-6, -60, 9), (0, 14, 6), lens=32)
    else:
        L.camera(sc2, (0, 17, 150), (0, 17, 0), ortho=78)
        sc2.camera.rotation_euler = (0, 0, 0)
    L.render(sc2, path, 1800 if mode != 'top' else 1400, 1000 if mode != 'top' else 1400, samples=32)


if PREV:
    os.makedirs(PREV, exist_ok=True)
    for mode in ('iso', 'front', 'top', 'yard', 'gate'):
        preview(os.path.join(PREV, f'highwatch_{mode}.png'), mode)
    preview(os.path.join(PREV, 'highwatch_iso_lod1.png'), 'iso', 1)
    preview(os.path.join(PREV, 'highwatch_gate_lod1.png'), 'gate', 1)

# ------------------------------------------------------------------------------------------ site json
dims = {}
for nm, d in PIECES.items():
    mn, mx = dims_of(d[0])
    dims[nm] = dict(size=[round(mx.x - mn.x, 2), round(mx.z - mn.z, 2), round(mx.y - mn.y, 2)])
pieces = {}
for nm in PIECES:
    pieces[nm] = dict(lod0=f'{nm}_lod0.glb', lod1=f'{nm}_lod1.glb', tris_lod0=stats[(nm, 0)], tris_lod1=stats[(nm, 1)],
                      size_m_xyz=dims[nm]['size'])
inst = []
for it in LAYOUT:
    inst.append(dict(piece=it['piece'], pos=[round(it['x'], 3), round(it['z'], 3), round(-it['y'], 3)], yaw_deg=it['yaw'], note=it['note']))
tot0 = sum(stats[(i['piece'], 0)] for i in inst)
tot1 = sum(stats[(i['piece'], 1)] for i in inst)
site = dict(
    name='highwatch_keep', region='ashford_vale', faction='Order of the Highwatch (Valencious)',
    coordinate_space='Godot metres, site-local. Origin = centre of the gate threshold on the ground; the compound extends toward -Z (north). '
                     'Piece yaw is degrees about +Y (counter-clockwise seen from above); piece fronts face +Z at yaw 0.',
    footprint_m=dict(x=[-27.3, 27.3], z=[-37.6, 2.6]),
    material='highwatch_kit.tres (shared atlas textures/highwatch_atlas.jpg)',
    draw_calls=len(inst), instances=len(inst), tris_lod0=tot0, tris_lod1=tot1,
    lod_switch_m=[60.0, 160.0], far_lod='highwatch_site_far.glb',
    pieces=pieces, placements=inst,
    npc_markers=[
        dict(role='gate_guard', pos=[-6.0, 0, -0.5], yaw_deg=0, model='res://assets/incoming/ai3d/meshy/armored/guard.glb'),
        dict(role='gate_guard', pos=[6.0, 0, -0.5], yaw_deg=0, model='res://assets/incoming/ai3d/meshy/armored/guard.glb'),
        dict(role='knight_captain', pos=[0.0, 0, -13.0], yaw_deg=0, model='res://assets/incoming/ai3d/meshy/armored/knight.glb', note='Sir Rowan Ashby, in front of the keep'),
        dict(role='sparring_pair', pos=[-16.0, 0, -12.0], yaw_deg=90, model='res://assets/incoming/ai3d/meshy/armored/knight.glb'),
        dict(role='sparring_pair', pos=[-14.0, 0, -12.0], yaw_deg=-90, model='res://assets/incoming/ai3d/meshy/armored/mercenary.glb'),
        dict(role='wall_sentry', pos=[-24.3, 7.0, -8.6], yaw_deg=-90, model='res://assets/incoming/ai3d/meshy/armored/guard.glb', note='on the wall walk (z ~ 7.0 m)'),
    ],
    interactables=[dict(id='keep_door', pos=[0.0, 0, -14.8]), dict(id='yard_dummy', pos=[-18.5, 0, -16.5]),
                   dict(id='barracks_supplies', pos=[16.5, 0, -20.0]), dict(id='well', pos=[15.5, 0, -10.0])],
)
with open(os.path.join(OUT, 'highwatch_site.json'), 'w') as fh:
    json.dump(site, fh, indent=1)
print("SITE tris lod0", tot0, "lod1", tot1, "draw calls", len(inst))

# far LOD: whole site merged into one mesh (1 draw call), decimated
comps = []
for it in LAYOUT:
    M = Matrix.Translation((it['x'], it['y'], it['z'])) @ Matrix.Rotation(math.radians(it['yaw']), 4, 'Z')
    comps.append((PIECES[it['piece']][1], M))
far = merge('site_far', comps)
obf = bpy.data.objects.new('highwatch_site_far', far)
bpy.context.scene.collection.objects.link(obf)
n_far = tri_of(far)
mod = obf.modifiers.new('d', 'DECIMATE'); mod.ratio = min(1.0, 9000.0 / n_far); mod.use_collapse_triangulate = True
dg = bpy.context.evaluated_depsgraph_get()
far2 = bpy.data.meshes.new_from_object(obf.evaluated_get(dg))
obf.modifiers.remove(mod)
obf.data = far2
far2.materials.clear(); far2.materials.append(plain_mat)
bpy.ops.object.select_all(action='DESELECT'); obf.select_set(True); bpy.context.view_layer.objects.active = obf
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'highwatch_site_far.glb'), export_format='GLB', use_selection=True, export_apply=True,
                          export_yup=True, export_image_format='NONE', export_materials='EXPORT')
print("FAR tris", tri_of(far2), "from", n_far)
