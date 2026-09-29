"""High-to-low PBR bake kit (bpy 5.x headless, Cycles CPU) for the Rising Ashes gate street.

Takes the LOW game mesh a generator (ra_kit.Kit.finish) produced -- flat cards for masonry blocks and
roof slates, bevelled boxes for timber, ... -- and

1. builds a HIGH-detail version procedurally (numpy + bmesh, no external assets):
   stone blocks become real chipped, bevelled, pillowed blocks; slates thick, tilted tiles with a broken
   lower edge and hairline cracks; timber is re-bevelled, densely subdivided, warped, cracked and knotted and
   gets wooden pegs; plaster is trowelled; cloth gets sine folds; iron gets nail heads;
2. unwraps the low mesh into ONE atlas: faces no camera can see share a dummy texel block, blocks and slates
   are INSTANCES of a few shared baked tiles (~1 cm/texel, colour carried by COLOR_0), everything else is
   isometrically unfolded into charts packed with visibility-weighted texel density (LOD1 uses planar
   patches instead, which survive decimated triangulation);
3. bakes tangent-space NORMAL, ambient occlusion, world position and vertex-colour base from high to low
   with Cycles, then paints ALBEDO in numpy (cavity, worn edges, granularity, wood strokes, plaster cracks,
   rust) and packs ORM (occlusion, roughness, metallic);
4. exports a glTF with ONE PBR material (baseColor x COLOR_0, normal, occlusion + metallicRoughness) next to
   the untouched emissive materials (lamps, heraldic decals) and shared leaded-glass window materials.

Entry point: `bake_asset(low_ob, name, ...)`, called from ra_kit.Kit.finish when the generator sets
`k.pbr = dict(size=1024, lod1_size=512, ...)` (RA_PBR=0 disables it). Textures go to
kingdom/assets/generated/pbr/<name>_{alb,nrm,orm}.png; write_pbr_godot.py writes the Godot import files.
Needs numpy + scipy + Pillow next to bpy. RA_PBR_CACHE=<dir> caches the four bake passes so paint-only
changes re-run in about a minute.
"""
import os, sys, math, json, struct, time, random
import numpy as np
import scipy.ndimage      # noqa: F401  (imported here so a missing dependency fails before the long bake)
from PIL import Image     # noqa: F401
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
PBR_DIR = os.path.join(ROOT, "kingdom", "assets", "generated", "pbr")

# ============================================================== material classes
EMISSIVE_KEYS = {"Glass", "WindowLit", "Lamp", "Coals", "Water", "Crystal", "Ember", "Flame", "FlameCore",
                 "CandleFlame", "Rune"}


def mat_key(name):
    k = name[3:] if name.startswith("RA_") else name
    if k.endswith("_hp"):
        k = k[:-3]
    return k


def cls_of(name):
    """material name -> bake class (None = keep the original material, not part of the atlas)."""
    k = mat_key(name)
    if k in EMISSIVE_KEYS:
        return None
    lk = k.lower()
    if lk in ("crown",) or lk.startswith("emblem"):     # image-textured heraldry decals keep their own material
        return None
    if lk.startswith("img_"):
        if "wood" in lk or "plank" in lk:
            return "wood"
        if "stone" in lk or "wall" in lk:
            return "stone"
        return "misc"
    if k in ("Wood", "Plank", "Board", "Deck", "Hull"):
        return "wood"
    if k in ("Matte", "Stone"):
        return "stone"
    if k == "Paving":
        return "paving"
    if k in ("Roof", "Shingle"):
        return "roof"
    if k == "Plaster":
        return "plaster"
    if k == "Metal":
        return "metal"
    if k in ("Cloth", "Rope", "Hide", "Canvas"):
        return "cloth"
    if k == "Thatch":
        return "thatch"
    if k == "Plant":
        return "plant"
    return "misc"


# base PBR constants per class: (roughness, metallic)
PBR_CONST = {"wood": (0.78, 0.0), "stone": (0.88, 0.0), "paving": (0.9, 0.0), "roof": (0.62, 0.0),
             "plaster": (0.93, 0.0), "metal": (0.5, 0.85), "cloth": (0.92, 0.0), "thatch": (0.98, 0.0),
             "plant": (0.85, 0.0), "misc": (0.8, 0.0)}


# ============================================================== numpy noise
def _hash(ix, iy, iz, seed):
    h = (ix.astype(np.int64) * 73856093) ^ (iy.astype(np.int64) * 19349663) ^ (iz.astype(np.int64) * 83492791) ^ int(seed * 2654435761 % (1 << 31))
    h = (h ^ (h >> 13)) * 1274126177
    h = (h ^ (h >> 16)) & 0xFFFFFF
    return h.astype(np.float64) / float(0xFFFFFF)


def vnoise(p, seed=0):
    """smooth value noise in [-1, 1] at points p (N,3)."""
    p = np.asarray(p, dtype=np.float64)
    i = np.floor(p)
    f = p - i
    u = f * f * f * (f * (f * 6 - 15) + 10)
    ix, iy, iz = i[:, 0], i[:, 1], i[:, 2]
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                out = out + w * _hash(ix + dx, iy + dy, iz + dz, seed)
    return out * 2.0 - 1.0


def fbm(p, freq, octaves=3, gain=0.5, seed=0):
    p = np.asarray(p, dtype=np.float64) * freq
    a, tot, out = 1.0, 0.0, 0.0
    for o in range(octaves):
        out = out + a * vnoise(p, seed + o * 17)
        tot += a
        a *= gain
        p = p * 2.03 + 11.7
    return out / tot


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a + 1e-12), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ============================================================== low-mesh analysis
class Chart:
    __slots__ = ("faces", "cls", "lvl", "vis", "L2", "uvw", "rect", "rot", "w", "h", "area")


def face_visibility(bm, bvh):
    """Per face: fraction of plausible camera directions (street level and aerial) that see it."""
    dirs = []
    for el in (-30, -12, 4, 18, 40, 65):
        for az in range(0, 360, 30):
            e, a = math.radians(el), math.radians(az)
            dirs.append(Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))))
    out = np.zeros(len(bm.faces))
    for f in bm.faces:
        c = f.calc_center_median()
        n = f.normal
        o = c + n * 0.015
        hit = 0
        for d in dirs:
            if n.dot(d) < 0.05:
                continue
            if o.z + 3.0 * d.z < 1.2:          # the camera would have to be below the ground
                continue
            _, _, idx, _ = bvh.ray_cast(o, d, 400.0)
            if idx is None:
                hit += 1
        out[f.index] = hit / len(dirs)
    return out


def _poly_overlap(a, b, eps=1e-4):
    """SAT overlap of two convex 2D polygons (lists of (x, y)); touching does not count."""
    for poly in (a, b):
        n = len(poly)
        for i in range(n):
            x0, y0 = poly[i]
            x1, y1 = poly[(i + 1) % n]
            ax, ay = y0 - y1, x1 - x0
            l = math.hypot(ax, ay)
            if l < 1e-12:
                continue
            ax /= l
            ay /= l
            pa = [ax * x + ay * y for x, y in a]
            pb = [ax * x + ay * y for x, y in b]
            if max(pa) <= min(pb) + eps or max(pb) <= min(pa) + eps:
                return False
    return True


def _shrink(poly, k=0.004):
    cx = sum(p[0] for p in poly) / len(poly)
    cy = sum(p[1] for p in poly) / len(poly)
    out = []
    for x, y in poly:
        dx, dy = x - cx, y - cy
        l = math.hypot(dx, dy)
        f = max(0.0, 1 - k / l) if l > 1e-9 else 1.0
        out.append((cx + dx * f, cy + dy * f))
    return out


def unfold_charts(bm, face_cls, face_lvl, max_dihedral=115.0, max_faces=400, fill_limit=2.2, max_len=5.5):
    """Isometric unfolding: grow charts across shared edges (same class + visibility level), laying each
    new face flat next to its neighbour; stop where it would overlap the chart or fold back too far."""
    mind = math.cos(math.radians(max_dihedral))
    done = set()
    charts = []
    for f0 in bm.faces:
        if f0.index in done or face_cls.get(f0.index) is None:
            continue
        c, lv = face_cls[f0.index], face_lvl[f0.index]
        ch = Chart()
        ch.cls, ch.lvl = c, lv
        # seed face laid out in its own plane
        n0 = f0.normal
        u0 = (f0.verts[1].co - f0.verts[0].co)
        u0 = (u0 - n0 * u0.dot(n0))
        if u0.length < 1e-9:
            u0 = Vector((1, 0, 0)) - n0 * n0.x
        u0.normalize()
        v0 = n0.cross(u0)
        o0 = f0.verts[0].co
        L2 = {f0.index: [((l.vert.co - o0).dot(u0), (l.vert.co - o0).dot(v0)) for l in f0.loops]}
        bx0 = min(p[0] for p in L2[f0.index])
        bx1 = max(p[0] for p in L2[f0.index])
        by0 = min(p[1] for p in L2[f0.index])
        by1 = max(p[1] for p in L2[f0.index])
        asum = f0.calc_area()
        seed_len = max(bx1 - bx0, by1 - by0)
        done.add(f0.index)
        queue = [f0]
        qi = 0
        while qi < len(queue) and len(L2) < max_faces:
            f = queue[qi]
            qi += 1
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in done or face_cls.get(g.index) != c or face_lvl[g.index] != lv:
                        continue
                    if g.normal.dot(f.normal) < mind:
                        continue
                    A, B = e.verts[0], e.verts[1]
                    fl = list(f.loops)
                    pa = pb = None
                    for i, l in enumerate(fl):
                        if l.vert == A:
                            pa = L2[f.index][i]
                        if l.vert == B:
                            pb = L2[f.index][i]
                    if pa is None or pb is None:
                        continue
                    e3 = (B.co - A.co)
                    el = e3.length
                    if el < 1e-9:
                        continue
                    e3 = e3 / el
                    a2, b2 = Vector(pa), Vector(pb)
                    e2 = (b2 - a2)
                    if e2.length < 1e-9:
                        continue
                    e2.normalize()
                    perp = Vector((-e2.y, e2.x))
                    cf = Vector(np.mean(L2[f.index], axis=0))
                    if perp.dot(cf - a2) > 0:
                        perp = -perp
                    poly = []
                    for l in g.loops:
                        w = l.vert.co - A.co
                        t = w.dot(e3)
                        s = (w - e3 * t).length
                        q = a2 + e2 * t + perp * s
                        poly.append((q.x, q.y))
                    # overlap check against the chart so far
                    sp = _shrink(poly)
                    bad = False
                    xs = [p[0] for p in sp]
                    ys = [p[1] for p in sp]
                    for fi, pl in L2.items():
                        if fi == f.index:
                            continue
                        px = [p[0] for p in pl]
                        py = [p[1] for p in pl]
                        if max(px) < min(xs) or min(px) > max(xs) or max(py) < min(ys) or min(py) > max(ys):
                            continue
                        if _poly_overlap(sp, _shrink(pl)):
                            bad = True
                            break
                    if bad:
                        continue
                    nx0, nx1 = min(bx0, min(xs)), max(bx1, max(xs))
                    ny0, ny1 = min(by0, min(ys)), max(by1, max(ys))
                    ag = g.calc_area()
                    if (nx1 - nx0) * (ny1 - ny0) > fill_limit * (asum + ag) and (asum + ag) > 0.04:
                        continue
                    if max(nx1 - nx0, ny1 - ny0) > max(max_len, seed_len):
                        continue
                    bx0, bx1, by0, by1, asum = nx0, nx1, ny0, ny1, asum + ag
                    L2[g.index] = poly
                    done.add(g.index)
                    queue.append(g)
        ch.faces = list(L2.keys())
        ch.L2 = L2
        ch.area = sum(bm.faces[i].calc_area() for i in ch.faces)
        charts.append(ch)
    return charts


def chart_basis(n):
    z = Vector((0, 0, 1))
    if abs(n.z) > 0.92:
        u = Vector((1, 0, 0))
    else:
        u = z.cross(n).normalized()
    v = n.cross(u).normalized()
    return u, v, n


def planar_charts(bm, face_cls, face_lvl, max_angle=24.0, cone=32.0):
    """Region-grow faces across shared edges into near-planar patches (normal cone) and project each patch
    orthographically. Robust for decimated / irregular triangulations (LOD1), where unfolding fragments."""
    cosa = math.cos(math.radians(max_angle))
    cosc = math.cos(math.radians(cone))
    done = set()
    charts = []
    for f0 in bm.faces:
        if f0.index in done or face_cls.get(f0.index) is None:
            continue
        c, lv = face_cls[f0.index], face_lvl[f0.index]
        ch = Chart()
        ch.cls, ch.lvl = c, lv
        seed_n = f0.normal.copy()
        fis = [f0]
        done.add(f0.index)
        acc = f0.normal * f0.calc_area()
        stack = [f0]
        while stack:
            f = stack.pop()
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in done or face_cls.get(g.index) != c or face_lvl[g.index] != lv:
                        continue
                    if g.normal.dot(f.normal) < cosa or g.normal.dot(seed_n) < cosc:
                        continue
                    done.add(g.index)
                    fis.append(g)
                    acc += g.normal * g.calc_area()
                    stack.append(g)
        n = acc.normalized() if acc.length > 1e-9 else seed_n
        u, v, _ = chart_basis(n)
        ch.faces = [f.index for f in fis]
        ch.L2 = {f.index: [(l.vert.co.dot(u), l.vert.co.dot(v)) for l in f.loops] for f in fis}
        ch.area = sum(f.calc_area() for f in fis)
        charts.append(ch)
    return charts


def orient_charts(charts, weights):
    """Rotate each chart to its min-area bounding box; store weighted (u, v) in metres."""
    for ch in charts:
        pts = np.array([p for fi in ch.faces for p in ch.L2[fi]])
        best = None
        for ang in np.arange(0, 90, 3.0):
            a = math.radians(ang)
            c, s = math.cos(a), math.sin(a)
            q = np.stack([pts[:, 0] * c + pts[:, 1] * s, -pts[:, 0] * s + pts[:, 1] * c], 1)
            mn, mx = q.min(0), q.max(0)
            ar = (mx[0] - mn[0]) * (mx[1] - mn[1])
            if best is None or ar < best[0] - 1e-9:
                best = (ar, a)
        a = best[1]
        c, s = math.cos(a), math.sin(a)
        w = weights(ch)
        q = np.stack([pts[:, 0] * c + pts[:, 1] * s, -pts[:, 0] * s + pts[:, 1] * c], 1)
        mn = q.min(0)
        mx = q.max(0)
        q = (q - mn) * w
        ch.w = float((mx[0] - mn[0]) * w)
        ch.h = float((mx[1] - mn[1]) * w)
        # back into per-face lists
        i = 0
        newL = {}
        for fi in ch.faces:
            n = len(ch.L2[fi])
            newL[fi] = [tuple(x) for x in q[i:i + n]]
            i += n
        ch.uvw = newL


class MaxRects:
    """MaxRects (best short side fit, 90 degree rotation) with numpy free-list bookkeeping."""

    def __init__(self, W, H):
        self.free = np.array([[0, 0, W, H]], dtype=np.int32)

    def place(self, w, h):
        F = self.free
        best = None
        for rot in (False, True):
            rw, rh = (h, w) if rot else (w, h)
            m = (F[:, 2] >= rw) & (F[:, 3] >= rh)
            if not m.any():
                continue
            idx = np.nonzero(m)[0]
            dw = F[idx, 2] - rw
            dh = F[idx, 3] - rh
            sc = np.minimum(dw, dh) * 4096 + np.maximum(dw, dh)
            j = int(np.argmin(sc))
            if best is None or sc[j] < best[0]:
                best = (sc[j], int(idx[j]), rw, rh, rot)
        if best is None:
            return None
        _, i, rw, rh, rot = best
        x, y = int(F[i, 0]), int(F[i, 1])
        fx, fy, fw, fh = F[:, 0], F[:, 1], F[:, 2], F[:, 3]
        hit = ~((x >= fx + fw) | (x + rw <= fx) | (y >= fy + fh) | (y + rh <= fy))
        keep = F[~hit]
        new = []
        for (ax, ay, aw, ah) in F[hit]:
            if x > ax:
                new.append((ax, ay, x - ax, ah))
            if x + rw < ax + aw:
                new.append((x + rw, ay, ax + aw - x - rw, ah))
            if y > ay:
                new.append((ax, ay, aw, y - ay))
            if y + rh < ay + ah:
                new.append((ax, y + rh, aw, ay + ah - y - rh))
        if new:
            F = np.concatenate([keep, np.array(new, dtype=np.int32)], 0)
        else:
            F = keep
        # prune rects contained in another
        if len(F) > 1:
            x0, y0, x1, y1 = F[:, 0], F[:, 1], F[:, 0] + F[:, 2], F[:, 1] + F[:, 3]
            cont = (x0[:, None] >= x0[None, :]) & (y0[:, None] >= y0[None, :]) & \
                   (x1[:, None] <= x1[None, :]) & (y1[:, None] <= y1[None, :])
            np.fill_diagonal(cont, False)
            # identical rects: keep the first
            same = cont & cont.T
            cont &= ~np.triu(same)
            F = F[~cont.any(1)]
        self.free = F
        return x, y, rw, rh, rot


def pack_charts(charts, size, margin=2, reserve=None):
    """Largest texel/metre k so all charts (padded by `margin` texels) fit; reserve = list of (w, h) px blocks
    placed first (dummy fill regions)."""
    order = sorted(range(len(charts)), key=lambda i: -max(charts[i].w, charts[i].h))
    lo, hi = 2.0, 800.0
    # area estimate narrows the search
    for kk in np.geomspace(2.0, 800.0, 80):
        A = sum((math.ceil(c.w * kk) + 2 * margin) * (math.ceil(c.h * kk) + 2 * margin) for c in charts)
        if A > 0.9 * size * size:
            hi = kk * 1.05
            lo = max(2.0, kk * 0.35)
            break
    best = None
    for _ in range(9):
        k = (lo * hi) ** 0.5
        mr = MaxRects(size, size)
        res = []
        ok = True
        for (w, h) in (reserve or []):
            r = mr.place(w, h)
            if r is None:
                ok = False
                break
            res.append(r)
        pos = {}
        if ok:
            for i in order:
                ch = charts[i]
                w = math.ceil(ch.w * k) + 2 * margin
                h = math.ceil(ch.h * k) + 2 * margin
                r = mr.place(w, h)
                if r is None:
                    ok = False
                    break
                pos[i] = r
        if ok:
            best = (k, pos, res)
            lo = k
        else:
            hi = k
    if best is None:
        raise RuntimeError("atlas packing failed")
    return best


def compute_levels(bm, thr=(0.008, 0.10)):
    """Per-face camera visibility (0..1) and its level: 0 hidden, 1 rarely seen, 2 normal."""
    bm.faces.index_update()
    bm.faces.ensure_lookup_table()
    bvh = BVHTree.FromBMesh(bm)
    vis = face_visibility(bm, bvh)
    lvl = {}
    for f in bm.faces:
        v = vis[f.index]
        lvl[f.index] = 0 if v < thr[0] else (1 if v < thr[1] else 2)
    return dict(bvh=bvh, vis=vis, lvl=lvl)


def plan_and_pack(bm, face_cls, size, lvl, inst, buckets, margin=2, level_weight=(0.0, 0.55, 1.0),
                  dummy_px=6, extra_weight=None, tile_dens=None, tile_budget=0.26, planar=False):
    uvl = bm.loops.layers.uv.get("Atlas") or bm.loops.layers.uv.new("Atlas")
    classes = sorted({c for c in face_cls.values() if c})
    vis_cls = {i: (c if (lvl[i] > 0 and i not in inst) else None) for i, c in face_cls.items()}
    charts = planar_charts(bm, vis_cls, lvl) if planar else unfold_charts(bm, vis_cls, lvl)
    orient_charts(charts, lambda ch: level_weight[ch.lvl] * (extra_weight(ch) if extra_weight else 1.0))
    tiles = make_tiles(buckets or {}, tile_dens or {"block": 100.0, "slate": 110.0}, tile_budget * size * size)
    reserve = [(dummy_px, dummy_px)] * (len(classes) + 1)
    reserve += [(t["wpx"] + 2 * TILE_MARGIN, t["hpx"] + 2 * TILE_MARGIN) for t in tiles]
    k, pos, res = pack_charts(charts, size, margin, reserve)
    for i, ch in enumerate(charts):
        x, y, rw, rh, rot = pos[i]
        wpx = math.ceil(ch.w * k)
        ch.rect = (x, y, rw, rh)
        ch.rot = rot
        for fi in ch.faces:
            f = bm.faces[fi]
            for li, (uu, vv) in enumerate(ch.uvw[fi]):
                px, py = uu * k, vv * k
                if rot:
                    px, py = py, wpx - px
                f.loops[li][uvl].uv = ((x + margin + px) / size, (y + margin + py) / size)
    dummies = {c: r for c, r in zip(classes, res[:len(classes)])}
    inst_dummy = res[len(classes)]
    for t, r in zip(tiles, res[len(classes) + 1:]):
        t["rect"] = r[:4]
        t["rot"] = r[4]
    tile_of = {(t["key"], t["variant"]): t for t in tiles}
    for f in bm.faces:
        c = face_cls.get(f.index)
        if c is None:
            continue
        info = inst.get(f.index)
        if info is not None and "key" in info and lvl[f.index] == 0:
            x, y, rw, rh, _ = inst_dummy               # hidden slate / block: neutral fill, colour from COLOR_0
            for l in f.loops:
                l[uvl].uv = ((x + rw / 2) / size, (y + rh / 2) / size)
            continue
        if info is not None and "key" in info and lvl[f.index] > 0:
            t = tile_of[(info["key"], info["variant"])]
            for li, l in enumerate(f.loops):
                j = (li - info["r"]) % 4
                cu, cv = TILE_CORNERS[(j + 2 * info["rot2"]) % 4]
                l[uvl].uv = tile_uv(t, cu, cv, size)
            continue
        if info is not None and "butt_of" in info:
            x, y, rw, rh, _ = inst_dummy
            for l in f.loops:
                l[uvl].uv = ((x + rw / 2) / size, (y + rh / 2) / size)
            continue
        if lvl[f.index] > 0:
            continue
        x, y, rw, rh, _ = dummies[c]
        for l in f.loops:
            l[uvl].uv = ((x + rw / 2) / size, (y + rh / 2) / size)
    return dict(charts=charts, k=k, dummies=dummies, inst_dummy=inst_dummy, tiles=tiles, lvl=lvl)


# ============================================================== HIGH geometry
def shell_ids(bm):
    seen = {}
    sid = 0
    for f in bm.faces:
        if f.index in seen:
            continue
        st = [f]
        seen[f.index] = sid
        while st:
            x = st.pop()
            for e in x.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen[g.index] = sid
                        st.append(g)
        sid += 1
    return seen, sid


class HighMesh:
    """Accumulates verts / polygons / corner colours in numpy chunks, then builds a bpy Mesh."""

    def __init__(self):
        self.V, self.F, self.C, self.nv = [], [], [], 0     # F chunks: (m, k) int arrays (all same k per chunk)

    def add(self, verts, faces, colors):
        """verts (n,3); faces (m,k) indices into verts (or a list of such arrays of different k);
        colors (m,k,4) per corner (matching list)."""
        verts = np.asarray(verts, dtype=np.float32)
        if not isinstance(faces, (list, tuple)):
            faces, colors = [faces], [colors]
        self.V.append(verts)
        for F, C in zip(faces, colors):
            self.F.append(np.asarray(F, dtype=np.int64) + self.nv)
            self.C.append(np.asarray(C, dtype=np.float32))
        self.nv += len(verts)

    def to_mesh(self, name):
        me = bpy.data.meshes.new(name)
        if not self.V:
            return me
        V = np.concatenate(self.V, 0)
        me.vertices.add(len(V))
        me.vertices.foreach_set("co", V.ravel())
        starts, totals, vidx, cols = [], [], [], []
        pos = 0
        for F, C in zip(self.F, self.C):
            m, k = F.shape
            starts.append(pos + np.arange(m) * k)
            totals.append(np.full(m, k))
            vidx.append(F.ravel())
            cols.append(C.reshape(-1, 4))
            pos += m * k
        starts = np.concatenate(starts)
        totals = np.concatenate(totals)
        vidx = np.concatenate(vidx)
        cols = np.concatenate(cols, 0)
        me.loops.add(len(vidx))
        me.polygons.add(len(starts))
        me.loops.foreach_set("vertex_index", vidx.astype(np.int32))
        me.polygons.foreach_set("loop_start", starts.astype(np.int32))
        me.polygons.foreach_set("loop_total", totals.astype(np.int32))
        me.update(calc_edges=True)
        ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
        ca.data.foreach_set("color", cols.ravel())
        me.polygons.foreach_set("use_smooth", np.ones(len(starts), dtype=bool))
        return me


def bilerp(c, a, b):
    """c: (4, k) corner values (p00, p10, p11, p01); a, b arrays -> (n, k)."""
    c = np.asarray(c, dtype=np.float64)
    a = a[:, None]
    b = b[:, None]
    return c[0] * (1 - a) * (1 - b) + c[1] * a * (1 - b) + c[2] * a * b + c[3] * (1 - a) * b


def grid_faces(nx, ny):
    ii, jj = np.meshgrid(np.arange(nx), np.arange(ny), indexing="ij")
    ii, jj = ii.ravel(), jj.ravel()
    s = ny + 1
    return np.stack([ii * s + jj, (ii + 1) * s + jj, (ii + 1) * s + jj + 1, ii * s + jj + 1], 1)


def add_card(hm, P, cc, rng, prm, skirt, kind, origin_n=None):
    """Turn a quad P (4 x 3, ccw seen from outside) into a solid-looking card: dense grid with a
    displacement height field, skirt of depth `skirt` on all four sides."""
    P = np.asarray(P, dtype=np.float64)
    e0 = P[1] - P[0]
    e1 = P[3] - P[0]
    W = 0.5 * (np.linalg.norm(e0) + np.linalg.norm(P[2] - P[3]))
    H = 0.5 * (np.linalg.norm(e1) + np.linalg.norm(P[2] - P[1]))
    if W < 0.02 or H < 0.02:
        return
    nrm = np.cross(P[1] - P[0], P[2] - P[0]) + np.cross(P[2] - P[0], P[3] - P[0])
    ln = np.linalg.norm(nrm)
    if ln < 1e-12:
        return
    nrm /= ln
    cell = prm["cell"]
    nx = int(np.clip(math.ceil(W / cell), 2, 64))
    ny = int(np.clip(math.ceil(H / cell), 2, 64))
    a = np.repeat(np.linspace(0, 1, nx + 1), ny + 1)
    b = np.tile(np.linspace(0, 1, ny + 1), nx + 1)
    pos = bilerp(P, a, b)
    x = a * W
    y = b * H
    dE = np.minimum(np.minimum(x, W - x), np.minimum(y, H - y))       # distance to the nearest edge
    h = card_height(x, y, W, H, dE, rng, prm, kind)
    pos = pos + nrm[None, :] * h[:, None]
    # skirt: boundary vertices dropped by `skirt` along -normal
    idx = np.arange((nx + 1) * (ny + 1)).reshape(nx + 1, ny + 1)
    ring = np.concatenate([idx[:, 0], idx[nx, 1:], idx[nx - 1::-1, ny], idx[0, ny - 1:0:-1]])
    sk = pos[ring] - nrm[None, :] * skirt
    nring = len(ring)
    verts = np.concatenate([pos, sk], 0)
    base = len(pos)
    F = grid_faces(nx, ny)
    sF = np.stack([ring, np.roll(ring, -1), base + np.roll(np.arange(nring), -1), base + np.arange(nring)], 1)
    # ring runs counter-clockwise seen from the front => skirt quads face outwards with this order
    vcol = bilerp(np.array(cc)[:, :4], a, b)
    dark = np.array([0.55, 0.55, 0.55, 1.0])
    ccol = vcol[F]
    scol = np.concatenate([vcol[ring][:, None, :], vcol[np.roll(ring, -1)][:, None, :],
                           (vcol[np.roll(ring, -1)] * dark)[:, None, :], (vcol[ring] * dark)[:, None, :]], 1)
    hm.add(verts, [F, sF], [ccol, scol])


def _chips(x, y, W, H, rng, n_corner_p, rmin, rmax, dmin, dmax, edge_p):
    """height (negative) from random corner / edge chips."""
    h = np.zeros_like(x)
    for cx, cy in ((0, 0), (W, 0), (W, H), (0, H)):
        if rng.random() < n_corner_p:
            r = rng.uniform(rmin, rmax)
            d = rng.uniform(dmin, dmax)
            dist = np.hypot(x - cx, y - cy) / r
            # ragged: modulate radius with angle-dependent wobble
            ang = np.arctan2(y - cy, x - cx)
            dist = dist * (1.0 + 0.35 * np.sin(ang * 5 + rng.uniform(0, 6)) * np.sin(ang * 3 + rng.uniform(0, 6)))
            h -= d * smoothstep(1.0, 0.25, dist)
    for _ in range(2):
        if rng.random() < edge_p:
            side = rng.integers(0, 4)
            r = rng.uniform(rmin * 0.7, rmax * 0.8)
            d = rng.uniform(dmin * 0.7, dmax * 0.8)
            t = rng.random()
            if side == 0:
                cx, cy = t * W, 0.0
            elif side == 1:
                cx, cy = W, t * H
            elif side == 2:
                cx, cy = t * W, H
            else:
                cx, cy = 0.0, t * H
            dist = np.hypot((x - cx) * 0.75, (y - cy)) / r if side in (0, 2) else np.hypot((x - cx), (y - cy) * 0.75) / r
            h -= d * smoothstep(1.0, 0.2, dist)
    return h


def card_height(x, y, W, H, dE, rng, prm, kind):
    n = len(x)
    seed = int(rng.integers(0, 1 << 20))
    pts = np.stack([x, y, np.full(n, float(seed % 97))], 1)
    h = np.zeros(n)
    if kind == "stone":
        bw = prm["bevel_w"] * rng.uniform(0.8, 1.35)
        bd = prm["bevel_d"] * rng.uniform(0.7, 1.4)
        h -= bd * (1 - smoothstep(0.0, bw, dE)) ** 1.6
        # pillowed, hand-dressed face
        pil = prm["pillow"] * rng.uniform(0.4, 1.3)
        h += pil * np.sqrt(np.clip(np.sin(math.pi * np.clip(x / W, 0, 1)) * np.sin(math.pi * np.clip(y / H, 0, 1)), 0, 1))
        # random tilt of the whole block
        tx, ty = math.tan(math.radians(rng.normal(0, prm["tilt"]))), math.tan(math.radians(rng.normal(0, prm["tilt"])))
        h += (x - W / 2) * tx + (y - H / 2) * ty
        h += prm["noise"] * fbm(pts, 1 / 0.11, 3, 0.55, seed)
        h += prm["noise"] * 0.55 * fbm(pts * 3.1, 1 / 0.11, 2, 0.5, seed + 5)
        if prm.get("fine"):
            h += prm["fine"] * fbm(pts * 1.0, 1 / 0.028, 2, 0.5, seed + 11)
        h += _chips(x, y, W, H, rng, prm["chip_p"], 0.035, 0.12, 0.010, 0.034, 0.7)
        # pitting: a few small dents
        for _ in range(rng.integers(0, 4)):
            cx, cy, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0.012, 0.03)
            h -= rng.uniform(0.002, 0.006) * smoothstep(1.0, 0.0, np.hypot(x - cx, y - cy) / r)
    elif kind == "slate":
        bw = prm["bevel_w"] * rng.uniform(0.8, 1.3)
        h -= prm["bevel_d"] * (1 - smoothstep(0.0, bw, dE)) ** 2.3
        # bottom (butt) edge: y == 0 : thick rounded lip with a ragged, hand-split outline
        lip = 1 - smoothstep(0.0, 0.03, y)
        h -= 0.006 * lip * (0.5 + 0.5 * vnoise(np.stack([x * 30, np.zeros(n), np.full(n, float(seed % 31))], 1), seed))
        # slight curl: bottom edge lifts
        h += prm["curl"] * rng.uniform(0, 1) * (1 - np.clip(y / max(H * 0.6, 1e-3), 0, 1)) ** 2
        tx, ty = math.tan(math.radians(rng.normal(0, prm["tilt"]))), math.tan(math.radians(rng.normal(0, prm["tilt"])))
        h += (x - W / 2) * tx + (y - H / 2) * ty
        # cleavage layers / streaks across the slope
        h += prm["noise"] * fbm(np.stack([x * 1.0, y * 2.6, np.full(n, float(seed % 53))], 1), 1 / 0.06, 3, 0.5, seed)
        if prm.get("fine"):
            h += prm["fine"] * fbm(np.stack([x, y * 1.8, np.full(n, float(seed % 41))], 1), 1 / 0.024, 2, 0.5, seed + 13)
        h += _chips(x, y, W, H, rng, prm["chip_p"], 0.02, 0.06, 0.004, 0.014, 0.15)
        # occasional crack: a thin groove from the lower edge
        if rng.random() < prm.get("crack_p", 0.12):
            cxk = rng.uniform(0.2, 0.8) * W
            ang = rng.uniform(-0.25, 0.25)
            dxk = (x - cxk) - ang * y
            h -= 0.005 * smoothstep(0.006, 0.0, np.abs(dxk + 0.004 * np.sin(y * 40))) * smoothstep(rng.uniform(0.5, 1.0) * H, 0.0, y)
    else:
        h += 0.002 * fbm(pts, 1 / 0.1, 2, 0.5, seed)
    return h


# ---------------------------------------------------------------- generic (bmesh) solids
CLOTH_AMP = 0.02
STONE_CARD = dict(cell=0.032, bevel_w=0.026, bevel_d=0.013, pillow=0.010, tilt=1.5, noise=0.0042, chip_p=0.78)
SLATE_CARD = dict(cell=0.026, bevel_w=0.013, bevel_d=0.0055, curl=0.006, tilt=1.8, noise=0.0020, chip_p=0.30,
                  crack_p=0.14)
SOLID = {   # class -> (bevel width, bevel segments, subdiv target edge)
    "wood": (0.007, 2, 0.045), "stone": (0.012, 2, 0.05), "paving": (0.012, 2, 0.05),
    "roof": (0.006, 1, 0.05), "plaster": (0.0, 0, 0.075), "metal": (0.003, 1, 0.04),
    "cloth": (0.0, 0, 0.04), "thatch": (0.0, 0, 0.06), "plant": (0.0, 0, 0.0), "misc": (0.0, 0, 0.0),
}


def _copy_faces(bm, fis, col_lay_src, dst, col_lay_dst, shell_lay, shell_of):
    vmap = {}
    for fi in fis:
        f = bm.faces[fi]
        vs = []
        for v in f.verts:
            nv = vmap.get(v.index)
            if nv is None:
                nv = dst.verts.new(v.co)
                vmap[v.index] = nv
            vs.append(nv)
        try:
            nf = dst.faces.new(vs)
        except ValueError:
            # a double-sided sheet: the back face has the same vertices; give it its own copies so it survives
            vs = [dst.verts.new(v.co) for v in f.verts]
            try:
                nf = dst.faces.new(vs)
            except ValueError:
                continue
        nf[shell_lay] = shell_of[fi]
        for l_src, l_dst in zip(f.loops, nf.loops):
            l_dst[col_lay_dst] = l_src[col_lay_src]
    return vmap


def _shell_frames(bm, shell_faces):
    """per shell: centre, principal axis (unit), the two cross axes, extents along (axis, p1, p2)."""
    out = {}
    for sid, fis in shell_faces.items():
        pts = np.array([v.co[:] for fi in fis for v in bm.faces[fi].verts])
        c = pts.mean(0)
        q = pts - c
        if len(q) < 3:
            continue
        w, vec = np.linalg.eigh(q.T @ q)
        ax = vec[:, 2]
        p1 = vec[:, 1]
        p2 = vec[:, 0]
        ext = [float(np.ptp(q @ a)) for a in (ax, p1, p2)]
        out[sid] = (c, ax, p1, p2, ext)
    return out


def _vert_normals(me):
    n = len(me.vertices)
    a = np.zeros(n * 3, dtype=np.float32)
    me.vertex_normals.foreach_get("vector", a)
    return a.reshape(n, 3).astype(np.float64)


def solid_displace(cls, me, sh_of_vert, frames, rng, seed):
    n = len(me.vertices)
    P = np.zeros(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", P)
    P = P.reshape(n, 3).astype(np.float64)
    N = _vert_normals(me)
    d = np.zeros(n)
    if cls == "wood":
        d += 0.0032 * fbm(P, 1.3, 3, 0.55, seed)
        d += 0.0016 * fbm(P + 5.3, 11.0, 2, 0.5, seed + 3)
        sh = sh_of_vert
        for sid in np.unique(sh):
            fr = frames.get(int(sid))
            if fr is None:
                continue
            c, ax, p1, p2, ext = fr
            m = sh == sid
            if m.sum() < 8:
                continue
            q = P[m] - c
            t = q @ ax
            u = q @ p1
            v = q @ p2
            Nm = N[m]
            dd = np.zeros(m.sum())
            r = np.random.default_rng(int(sid) * 7919 + seed)
            if ext[1] > 0.3 and ext[2] < 0.14 and ext[2] < 0.5 * ext[1]:
                # a wide plate (counter top, crate side, floor board): cut plank seams along the long axis and
                # nudge every plank a millimetre or two so the seams read in the normal map
                spacing = r.uniform(0.11, 0.16)
                npl = max(2, int(round(ext[1] / spacing)))
                spacing = ext[1] / npl
                tt = (u - u.min()) / spacing
                idx = np.floor(np.clip(tt, 0, npl - 1e-6))
                frac = tt - idx
                dist = np.minimum(frac, 1 - frac) * spacing
                face = np.clip(np.abs(Nm @ p2), 0, 1) ** 3
                off = (np.array([r.random() for _ in range(npl + 1)])[idx.astype(int)] - 0.5) * 0.003
                dd += face * (-0.0035 * smoothstep(0.007, 0.0, dist) + off)
                if ext[0] > 0.9:      # butt joints across the long axis
                    ns = max(1, int(ext[0] / r.uniform(0.9, 1.6)))
                    tj = (t - t.min()) / (ext[0] / ns)
                    dj = np.minimum(tj % 1.0, 1 - tj % 1.0) * (ext[0] / ns)
                    dd += face * (-0.003 * smoothstep(0.006, 0.0, dj) * (dj < 0.02) * (tj > 0.05) * (tj < ns - 0.05))
            if ext[0] < 0.5:
                d[m] += dd
                continue
            # long checks (splits) on one of the four faces
            for _ in range(r.integers(0, 3)):
                face_dir = [p1, -p1, p2, -p2][r.integers(0, 4)]
                other_is_p2 = (abs(face_dir @ p1) > 0.5)
                across = (v if other_is_p2 else u)
                face_w = ext[2] if other_is_p2 else ext[1]
                cpos = r.uniform(-0.3, 0.3) * face_w
                t0 = r.uniform(-0.4, 0.2) * ext[0]
                L = r.uniform(0.25, 0.9) * ext[0] * 0.5 + 0.2
                mean = cpos + 0.006 * np.sin((t - t0) * 9 + r.uniform(0, 6))
                wid = r.uniform(0.005, 0.011)
                mask = np.clip(Nm @ face_dir, 0, 1) ** 3
                win = smoothstep(t0 - 0.03, t0 + 0.03, t) * smoothstep(t0 + L + 0.03, t0 + L - 0.03, t)
                taper = np.clip(1 - np.abs(t - (t0 + L * 0.4)) / (L * 0.8), 0.15, 1)
                dd -= 0.0065 * taper * smoothstep(wid, 0.0, np.abs(across - mean)) * win * mask
            # knots
            if ext[0] > 0.6 and r.random() < 0.7:
                face_dir = [p1, -p1, p2, -p2][r.integers(0, 4)]
                other_is_p2 = (abs(face_dir @ p1) > 0.5)
                across = (v if other_is_p2 else u)
                face_w = ext[2] if other_is_p2 else ext[1]
                kt = r.uniform(-0.35, 0.35) * ext[0]
                ka = r.uniform(-0.25, 0.25) * face_w
                kr = r.uniform(0.028, 0.05)
                dist = np.hypot(t - kt, across - ka)
                mask = np.clip(Nm @ face_dir, 0, 1) ** 2
                dd += mask * (0.0045 * np.exp(-((dist - kr) / (kr * 0.32)) ** 2) - 0.0035 * np.exp(-(dist / (kr * 0.55)) ** 2))
            d[m] += dd
    elif cls in ("stone", "paving"):
        d += 0.0065 * fbm(P, 1 / 0.16, 3, 0.55, seed)
        d += 0.0026 * fbm(P + 7.1, 1 / 0.05, 2, 0.5, seed + 9)
    elif cls == "plaster":
        d += 0.010 * fbm(P, 1 / 0.7, 3, 0.55, seed)
        d += 0.0035 * fbm(P + 3.7, 1 / 0.17, 2, 0.5, seed + 5)
        d += 0.0012 * fbm(P + 9.2, 1 / 0.05, 2, 0.5, seed + 7)
    elif cls == "metal":
        d += 0.0015 * fbm(P, 1 / 0.06, 2, 0.5, seed)
    elif cls == "roof":
        d += 0.0025 * fbm(P, 1 / 0.2, 2, 0.5, seed)
    elif cls == "thatch":
        d += 0.02 * fbm(P, 1 / 0.25, 3, 0.55, seed)
    elif cls == "cloth":
        # Folds as a pure function of position with a sign-normalised direction, so coincident front / back
        # layers of a double-sided cloth move together (otherwise they cross and the AO bake goes black).
        if os.environ.get("RA_PBR_NOFOLD"):
            return
        ref = np.array([0.0, 0.06, 1.0])
        Nf = N * np.sign(N @ ref + 1e-9)[:, None]
        zz = np.array([0.0, 0.0, 1.0])
        lat = np.cross(np.broadcast_to(zz, Nf.shape), Nf)
        ln = np.linalg.norm(lat, axis=1)
        alt = np.array([1.0, 0.0, 0.0])
        lat = np.where(ln[:, None] < 0.2, alt, lat / np.maximum(ln[:, None], 1e-6))
        down = np.cross(Nf, lat)
        l = np.einsum("ij,ij->i", P, lat)
        s_ = np.einsum("ij,ij->i", P, down)
        r = np.random.default_rng(seed + 977)
        lam = r.uniform(0.2, 0.28)
        ph = r.uniform(0, 6.28)
        wob = 0.14 * fbm(np.stack([s_ * 3.0, l * 0.5, np.zeros_like(s_)], 1), 1.0, 2, 0.5, seed + 5)
        fold = np.sin(2 * math.pi * (l / lam + wob) + ph)
        env_ = 0.6 + 0.4 * np.abs(np.sin(s_ * 2.3 + ph))
        dd = CLOTH_AMP * env_ * fold + 0.5 * CLOTH_AMP * fbm(P, 1 / 0.45, 2, 0.5, seed + 2)
        P += Nf * dd[:, None]
        me.vertices.foreach_set("co", P.astype(np.float32).ravel())
        me.update()
        return
    P += N * d[:, None]
    me.vertices.foreach_set("co", P.astype(np.float32).ravel())
    me.update()


def drop_coincident_backs(bm, fis):
    """Double-sided sheets are modelled as two coincident, opposite faces; in the HIGH keep only the one
    facing up / toward -Y (a coincident pair makes every bake ray tie between the two and AO goes black)."""
    ref = Vector((0.0, -0.06, 1.0))
    groups = {}
    for fi in fis:
        f = bm.faces[fi]
        c = f.calc_center_median()
        groups.setdefault((round(c.x, 2), round(c.y, 2), round(c.z, 2)), []).append(fi)
    keep = []
    for key, g in groups.items():
        if len(g) == 1:
            keep.append(g[0])
            continue
        best = max(g, key=lambda i: bm.faces[i].normal.dot(ref))
        opp = [i for i in g if i != best and bm.faces[i].normal.dot(bm.faces[best].normal) < -0.8]
        keep += [i for i in g if i not in opp]
    return keep


def build_solids(bm, fis_by_shell, cls, seed, coarse=False, ang=24.0):
    """Generic recipe for a set of shells of one class -> bpy Mesh."""
    col_src = bm.loops.layers.float_color.get("Col")
    dst = bmesh.new()
    col_dst = dst.loops.layers.float_color.new("Col")
    shl = dst.faces.layers.int.new("sh")
    shell_of = {}
    for sid, fis in fis_by_shell.items():
        for fi in fis:
            shell_of[fi] = sid
    allf = [fi for fis in fis_by_shell.values() for fi in fis]
    if cls in ("cloth", "plant", "misc"):
        allf = drop_coincident_backs(bm, allf)
    _copy_faces(bm, allf, col_src, dst, col_dst, shl, shell_of)
    frames = _shell_frames(bm, fis_by_shell)
    bw, seg, tgt = SOLID.get(cls, (0, 0, 0))
    if not coarse and bw > 0:
        dst.edges.ensure_lookup_table()
        ed = [e for e in dst.edges if len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(ang)]
        if ed:
            try:
                bmesh.ops.bevel(dst, geom=ed, offset=bw, offset_type="OFFSET", segments=seg, profile=0.5,
                                affect="EDGES", clamp_overlap=True)
            except Exception as ex:      # keep going without the extra bevel
                print("bevel failed", cls, ex)
    if not coarse and tgt > 0:
        for it in range(9):
            long_e = [e for e in dst.edges if e.calc_length() > tgt * 1.5]
            if not long_e:
                break
            bmesh.ops.subdivide_edges(dst, edges=long_e, cuts=1, use_grid_fill=True)
            if len(dst.verts) > 900000:
                break
    dst.normal_update()
    me = bpy.data.meshes.new("H_" + cls)
    # per-vertex shell id (all faces of a vertex share a shell)
    sh_of_v = np.zeros(len(dst.verts), dtype=np.int64)
    dst.verts.ensure_lookup_table()
    for v in dst.verts:
        if v.link_faces:
            sh_of_v[v.index] = v.link_faces[0][shl]
    dst.to_mesh(me)
    dst.free()
    for p in me.polygons:
        p.use_smooth = True
    if not coarse:
        solid_displace(cls, me, sh_of_v, frames, np.random.default_rng(seed), seed)
    return me


# ---------------------------------------------------------------- base colour tint (what the old textured material multiplied)
_TINT_CACHE = {}


def _srgb_to_lin_np(a):
    a = np.asarray(a, dtype=np.float64)
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def material_tint(mat):
    """Mean LINEAR colour of the base-colour texture the low material multiplies by its vertex colour
    ((1,1,1) for plain vertex-colour materials)."""
    if mat is None or not mat.use_nodes:
        return (1.0, 1.0, 1.0)
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            # only the base-colour one: skip non-colour maps (normal / metallicRoughness)
            if n.image.colorspace_settings.name == "Non-Color":
                continue
            path = bpy.path.abspath(n.image.filepath) if n.image.filepath else ""
            key = path or n.image.name
            if key in _TINT_CACHE:
                return _TINT_CACHE[key]
            try:
                if path and os.path.exists(path):
                    from PIL import Image
                    im = np.asarray(Image.open(path).convert("RGB").resize((128, 128)), dtype=np.float64) / 255.0
                else:
                    w, h = n.image.size
                    px = np.zeros(w * h * 4, dtype=np.float32)
                    n.image.pixels.foreach_get(px)
                    im = px.reshape(h, w, 4)[..., :3].astype(np.float64)
                    im = im[::max(1, h // 128), ::max(1, w // 128)]
                    im = im  # already linear-ish for generated images
                    _TINT_CACHE[key] = tuple(float(x) for x in im.reshape(-1, 3).mean(0))
                    return _TINT_CACHE[key]
                lin = _srgb_to_lin_np(im)
                t = tuple(float(x) for x in lin.reshape(-1, 3).mean(0))
            except Exception:
                t = (0.7, 0.7, 0.7)
            _TINT_CACHE[key] = t
            return t
    return (1.0, 1.0, 1.0)


def apply_tint(bm, me, override=None):
    """Multiply the Col layer by each face material's texture mean (in place on the private bm).
    override: {material name or class: (r, g, b)} replaces the texture mean."""
    col = bm.loops.layers.float_color.get("Col")
    tints = []
    for m in me.materials:
        t = material_tint(m)
        if override:
            t = override.get(m.name, override.get(cls_of(m.name), t))
        tints.append(t)
    for f in bm.faces:
        t = tints[f.material_index] if f.material_index < len(tints) else (1, 1, 1)
        for l in f.loops:
            c = l[col]
            l[col] = (min(1.0, c[0] * t[0]), min(1.0, c[1] * t[1]), min(1.0, c[2] * t[2]), 1.0)


# ---------------------------------------------------------------- instanced tiles (blocks, slates)
TILE_NEUTRAL = 0.72           # mean of the neutral tile albedo; COLOR_0 = face colour / TILE_NEUTRAL at runtime
TILE_KIND = {"stone": "block", "paving": "block", "roof": "slate"}
TILE_CORNERS = ((0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0))
TILE_MARGIN = 4


def orient_card(f, butt=None, roofy=False):
    """Rotation start r so [v[(r+j)%4]] has P0->P1 as the card's bottom edge (shared edge with the butt face,
    else the lowest edge for roofs, else 0)."""
    vl = list(f.verts)
    if butt is not None:
        shared = [v for v in vl if v in butt.verts]
        if len(shared) == 2:
            for i in range(4):
                if vl[i] in shared and vl[(i + 1) % 4] in shared:
                    return i
    if roofy:
        best, bi = None, 0
        for i in range(4):
            z = (vl[i].co.z + vl[(i + 1) % 4].co.z) / 2
            if best is None or z < best:
                best, bi = z, i
        return bi
    return 0


def card_dims(P):
    P = np.asarray(P, dtype=np.float64)
    W = 0.5 * (np.linalg.norm(P[1] - P[0]) + np.linalg.norm(P[2] - P[3]))
    H = 0.5 * (np.linalg.norm(P[3] - P[0]) + np.linalg.norm(P[2] - P[1]))
    return W, H


def plan_tiles(bm, face_cls, lvl, shells_of, max_buckets=22, ratio=1.22):
    """Which faces become instances of shared baked tiles. Returns (inst {face: info}, buckets {key: info})."""
    cand = []
    for (sid, cls), fis in shells_of.items():
        kind = TILE_KIND.get(cls)
        if kind is None or all(lvl[fi] == 0 for fi in fis):
            continue
        fs = [bm.faces[fi] for fi in fis]
        if not all(len(f.verts) == 4 for f in fs):
            continue
        if kind == "block" and len(fs) != 1:
            continue
        if kind == "slate" and len(fs) not in (1, 2):
            continue
        top = max(fs, key=lambda f: f.calc_area())
        butt = None
        if len(fs) == 2:
            butt = fs[0] if fs[1] is top else fs[1]
        r = orient_card(top, butt, roofy=(kind == "slate"))
        vl = list(top.verts)
        P = [vl[(r + j) % 4].co[:] for j in range(4)]
        W, H = card_dims(P)
        if W < 0.08 or H < 0.05 or W > 1.35 or H > 1.0 or top.calc_area() > 0.75:
            continue
        cand.append((top.index, butt.index if butt is not None else None, cls, kind, W, H, r))
    inst, buckets = {}, {}
    for kind in ("block", "slate"):
        cs = [c for c in cand if c[3] == kind]
        if not cs:
            continue
        rt = ratio
        while True:
            keys = {}
            for c in cs:
                iw = int(round(math.log(c[4] / 0.2) / math.log(rt)))
                ih = int(round(math.log(c[5] / 0.2) / math.log(rt)))
                keys.setdefault((kind, iw, ih), []).append(c)
            if len(keys) <= max_buckets or rt > 2.0:
                break
            rt *= 1.06
        for key, items in keys.items():
            _, iw, ih = key
            nv = 4 if len(items) >= 30 else (3 if len(items) >= 12 else (2 if len(items) >= 3 else 1))
            buckets[key] = dict(kind=kind, W=0.2 * rt ** iw, H=0.2 * rt ** ih, nv=nv, count=len(items))
            for (fi, bi, cls, kd, W, H, r) in items:
                h = (fi * 2654435761) & 0xFFFFFFFF
                inst[fi] = dict(key=key, variant=(h >> 8) % nv, rot2=(h >> 3) & 1, r=r, cls=cls, butt=bi)
                if bi is not None:
                    inst[bi] = dict(butt_of=fi, cls=cls)
    return inst, buckets


def make_tiles(buckets, dens, budget_px):
    """tile list (one per bucket variant) with pixel sizes; density scaled down to fit `budget_px` texels."""
    d = dict(dens)
    for _ in range(12):
        tiles = []
        tot = 0
        for key, b in sorted(buckets.items()):
            for v in range(b["nv"]):
                dk = d[b["kind"]]
                w = int(math.ceil(b["W"] * dk))
                h = int(math.ceil(b["H"] * dk))
                tiles.append(dict(key=key, variant=v, kind=b["kind"], W=b["W"], H=b["H"], wpx=w, hpx=h, dens=dk))
                tot += (w + 2 * TILE_MARGIN) * (h + 2 * TILE_MARGIN)
        if tot <= budget_px or not tiles:
            break
        d = {k: v * 0.9 for k, v in d.items()}
    return tiles


def tile_uv(tile, u, v, size):
    x, y, rw, rh = tile["rect"]
    px, py = u * tile["wpx"], v * tile["hpx"]
    if tile["rot"]:
        px, py = py, tile["wpx"] - px
    return ((x + TILE_MARGIN + px) / size, (y + TILE_MARGIN + py) / size)


TILE_STONE = dict(STONE_CARD, cell=0.010, noise=0.0030, fine=0.0011)
TILE_SLATE = dict(SLATE_CARD, cell=0.0095, noise=0.0016, fine=0.0007)


def tile_geometry(tiles, hm, seed):
    """Scratch scene for the tiles: the tile quad (baked low) plus the high card with neighbours around it.
    Returns list of (P(4x3), tile) for the low quads."""
    rng = np.random.default_rng(seed + 4242)
    lows = []
    ncol = np.array([TILE_NEUTRAL, TILE_NEUTRAL, TILE_NEUTRAL, 1.0])
    cc = [ncol] * 4
    for ti, t in enumerate(tiles):
        W, H = t["W"], t["H"]
        O = np.array([ti * 7.0, 0.0, -600.0])
        tb = rng.uniform(0.86, 1.06)
        ncol_t = np.array([TILE_NEUTRAL * tb, TILE_NEUTRAL * tb * rng.uniform(0.97, 1.03),
                           TILE_NEUTRAL * tb * rng.uniform(0.95, 1.04), 1.0])
        cc = [ncol_t] * 4
        P = [O + (0, 0, 0), O + (W, 0, 0), O + (W, H, 0), O + (0, H, 0)]
        lows.append((P, t))
        gap = 0.03 if t["kind"] == "block" else 0.012
        if t["kind"] == "block":
            add_card(hm, P, cc, rng, TILE_STONE, 0.09, "stone")
            nb = dict(TILE_STONE, cell=0.022)
            for dy in (0.0, H + gap, -(H + gap)):
                x = -rng.uniform(0.25, 0.7) * W - (0 if dy == 0 else 0.0)
                while x < 2.0 * W + 0.1:
                    wn = W * rng.uniform(0.7, 1.25)
                    if not (dy == 0.0 and x + wn > -gap * 0.5 and x < W + gap * 0.5):
                        Q = [O + (x + gap / 2, dy, 0), O + (x + wn - gap / 2, dy, 0), O + (x + wn - gap / 2, dy + H, 0),
                             O + (x + gap / 2, dy + H, 0)]
                        add_card(hm, Q, cc, rng, nb, 0.09, "stone")
                    x += wn
        else:
            add_card(hm, P, cc, rng, TILE_SLATE, min(0.04, 0.05), "slate")
            nb = dict(TILE_SLATE, cell=0.02)
            for dx in (-(W + gap), W + gap):
                wn = W * rng.uniform(0.85, 1.15)
                x0 = dx if dx < 0 else dx
                Q = [O + (x0, 0, 0), O + (x0 + W, 0, 0), O + (x0 + W, H, 0), O + (x0, H, 0)]
                add_card(hm, Q, cc, rng, nb, 0.04, "slate")
            # the next course lies over the upper part of this slate
            Q = [O + (-0.1 * W, H * 0.66, 0.03), O + (W * 0.9, H * 0.66, 0.03), O + (W * 0.9, H * 1.66, 0.008),
                 O + (-0.1 * W, H * 1.66, 0.008)]
            add_card(hm, Q, cc, rng, nb, 0.04, "slate")
    return lows


# ---------------------------------------------------------------- extras: wooden pegs, iron nails
def _cyl_dome(c, axis, r, length, seg=8, rings=2):
    """small domed cylinder (peg / nail head) standing on point c along unit axis."""
    a = np.array(axis, dtype=np.float64)
    a /= np.linalg.norm(a)
    t = np.cross(a, [0, 0, 1.0])
    if np.linalg.norm(t) < 0.2:
        t = np.cross(a, [1.0, 0, 0])
    t /= np.linalg.norm(t)
    b = np.cross(a, t)
    ang = np.linspace(0, 2 * math.pi, seg, endpoint=False)
    ring = lambda rr, h: np.array([c + a * h + rr * (math.cos(x) * t + math.sin(x) * b) for x in ang])
    verts = [ring(r, -length * 0.4), ring(r, length * 0.55), ring(r * 0.62, length * 0.9), np.array([c + a * length])]
    V = np.concatenate([v.reshape(-1, 3) for v in verts], 0)
    F = []
    for k in range(2):
        for i in range(seg):
            j = (i + 1) % seg
            F.append([k * seg + i, k * seg + j, (k + 1) * seg + j, (k + 1) * seg + i])
    quads = np.array(F)
    tri = np.array([[2 * seg + i, 2 * seg + (i + 1) % seg, 3 * seg] for i in range(seg)])
    return V, quads, tri


def add_pegs_nails(bm, face_cls, lvl, shells, frames, hm, seed):
    """pegs on long timbers, nails on iron straps -> HighMesh chunks"""
    rng = np.random.default_rng(seed + 99)
    col = bm.loops.layers.float_color.get("Col")
    npeg = nnail = 0
    for sid, fis in shells.items():
        cls = face_cls[fis[0]]
        if cls not in ("wood", "metal"):
            continue
        fr = frames.get(sid)
        if fr is None:
            continue
        c, ax, p1, p2, ext = fr
        if max(lvl[fi] for fi in fis) == 0:
            continue
        # the outward direction with the most visible area
        best, bd = 0.0, None
        for d in (p1, -p1, p2, -p2):
            s = sum(bm.faces[fi].calc_area() * max(0.0, np.dot(bm.faces[fi].normal[:], d)) ** 4 * (lvl[fi] >= 2)
                    for fi in fis)
            if s > best:
                best, bd = s, d
        if bd is None:
            continue
        other = p2 if abs(bd @ p1) > 0.5 else p1
        face_w = ext[2] if abs(bd @ p1) > 0.5 else ext[1]
        depth = ext[1] if abs(bd @ p1) > 0.5 else ext[2]
        # surface point along the axis: project vertices to find the face plane offset
        pts = np.array([v.co[:] for fi in fis for v in bm.faces[fi].verts])
        off = (pts - c) @ bd
        top = off.max()
        colr = np.mean([list(l[col])[:4] for fi in fis for l in bm.faces[fi].loops], axis=0)
        if cls == "wood" and ext[0] > 0.55 and face_w > 0.09:
            ts = [-ext[0] / 2 + 0.16, ext[0] / 2 - 0.16]
            if ext[0] > 2.4:
                ts.append(rng.uniform(-0.2, 0.2) * ext[0])
            for t in ts:
                jitter = rng.uniform(-0.15, 0.15) * face_w
                cc = c + ax * (t + rng.uniform(-0.03, 0.03)) + other * jitter + bd * top
                V, Q, T = _cyl_dome(cc, bd, 0.017 + rng.uniform(-0.003, 0.004), 0.016, 8)
                cl = np.array(colr) * np.array([0.72, 0.68, 0.62, 1.0])
                hm.add(V, [Q, T], [np.tile(cl, (len(Q), 4, 1)), np.tile(cl, (len(T), 3, 1))])
                npeg += 1
        elif cls == "metal" and ext[0] > 0.22 and ext[0] > 2.2 * face_w and face_w > 0.035:
            n = int(ext[0] / 0.13)
            for i in range(n + 1):
                t = -ext[0] / 2 + 0.05 + i * (ext[0] - 0.1) / max(1, n)
                cc = c + ax * t + bd * top
                V, Q, T = _cyl_dome(cc, bd, 0.0115, 0.009, 6)
                cl = np.array(colr) * np.array([1.15, 1.1, 1.05, 1.0])
                hm.add(V, [Q, T], [np.tile(cl, (len(Q), 4, 1)), np.tile(cl, (len(T), 3, 1))])
                nnail += 1
    return npeg, nnail


# ---------------------------------------------------------------- assemble the HIGH objects
def build_high(bm, face_cls, lvl, seed=1, extras=True, inst=None, tiles=None, log=print):
    inst = inst or {}
    seen, ns = shell_ids(bm)
    col = bm.loops.layers.float_color.get("Col")
    rng = np.random.default_rng(seed)
    shells = {}
    for f in bm.faces:
        shells.setdefault((seen[f.index], face_cls.get(f.index)), []).append(f.index)
    cards = HighMesh()
    flat = {}
    solids = {}
    nstone = nslate = ncoarse = 0
    for (sid, cls), fis in shells.items():
        hidden = all(lvl[fi] == 0 for fi in fis)
        if cls is None or hidden:
            for fi in fis:
                f = bm.faces[fi]
                k = len(f.verts)
                flat.setdefault(k, []).append(([v.co[:] for v in f.verts], [list(l[col])[:4] for l in f.loops]))
            continue
        fs = [bm.faces[fi] for fi in fis]
        quads = all(len(f.verts) == 4 for f in fs)
        is_inst = any(fi in inst and "key" in inst[fi] for fi in fis)
        if quads and cls in ("stone", "paving") and len(fs) == 1:
            f = fs[0]
            prm = dict(STONE_CARD, cell=0.085) if is_inst else STONE_CARD
            add_card(cards, [v.co[:] for v in f.verts], [list(l[col])[:4] for l in f.loops], rng, prm, 0.09, "stone")
            if is_inst:
                ncoarse += 1
            else:
                nstone += 1
            continue
        if quads and cls == "roof" and len(fs) in (1, 2):
            top = max(fs, key=lambda f: f.calc_area())
            butt = None
            if len(fs) == 2:
                butt = fs[0] if fs[1] is top else fs[1]
            r = orient_card(top, butt, roofy=True)
            vl = list(top.verts)
            cl = [list(l[col])[:4] for l in top.loops]
            P = [vl[(r + j) % 4].co[:] for j in range(4)]
            cols = [cl[(r + j) % 4] for j in range(4)]
            skirt = 0.03
            if butt is not None:
                shared = [v for v in top.verts if v in butt.verts]
                if len(shared) == 2:
                    other = [v for v in butt.verts if v not in shared]
                    skirt = max(0.02, (sum((v.co for v in other), Vector()) / 2 - sum((v.co for v in shared), Vector()) / 2).length)
            prm = dict(SLATE_CARD, cell=0.075) if is_inst else SLATE_CARD
            add_card(cards, P, cols, rng, prm, min(skirt, 0.07), "slate")
            if is_inst:
                ncoarse += 1
            else:
                nslate += 1
            continue
        solids.setdefault(cls, {})[sid] = fis
    log(f"  cards: {nstone} stone blocks, {nslate} slates, {ncoarse} instanced (coarse occluders)")
    tile_lows = []
    if tiles:
        tile_lows = tile_geometry(tiles, cards, seed)
        log(f"  tiles: {len(tiles)} baked from scratch patches")
    for k, items in flat.items():
        V = np.array([p for it in items for p in it[0]], dtype=np.float32)
        F = np.arange(len(V)).reshape(-1, k)
        C = np.array([it[1] for it in items], dtype=np.float32).reshape(-1, k, 4)
        cards.add(V, F, C)
    meshes = [("H_cards", cards.to_mesh("H_cards"))]
    frames_all = {}
    skip = set(filter(None, os.environ.get("RA_PBR_SKIP", "").split(",")))
    for cls, sd in solids.items():
        if cls in skip:
            continue
        coarse = cls in ("plant", "misc")
        me = build_solids(bm, sd, cls, seed + hash(cls) % 1000, coarse=coarse)
        meshes.append(("H_" + cls, me))
        log(f"  solids {cls}: {len(sd)} shells -> {len(me.polygons)} faces")
        frames_all.update(_shell_frames(bm, sd))
    if extras:
        ex = HighMesh()
        allsh = {}
        for cls, sd in solids.items():
            for sid, fis in sd.items():
                allsh[sid] = fis
        pn = add_pegs_nails(bm, face_cls, lvl, allsh, frames_all, ex, seed)
        log(f"  pegs {pn[0]}  nails {pn[1]}")
        meshes.append(("H_extras", ex.to_mesh("H_extras")))
    return meshes, tile_lows


# ============================================================== baking
def _new_float_image(name, size):
    if name in bpy.data.images:
        bpy.data.images.remove(bpy.data.images[name])
    img = bpy.data.images.new(name, size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    img.pixels.foreach_set(np.zeros(size * size * 4, dtype=np.float32))
    return img


def _read(img, size):
    a = np.zeros(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return a.reshape(size, size, 4)


def make_bake_material(name="HIGH_BAKE"):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return m


def set_pass(mat, kind, ao_dist=0.6):
    nt = mat.node_tree
    em = next(n for n in nt.nodes if n.type == "EMISSION")
    for l in list(nt.links):
        if l.to_node == em:
            nt.links.remove(l)
    for n in list(nt.nodes):
        if n.type not in ("EMISSION", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    if kind == "POS":
        g = nt.nodes.new("ShaderNodeNewGeometry")
        nt.links.new(g.outputs["Position"], em.inputs["Color"])
    elif kind == "COL":
        c = nt.nodes.new("ShaderNodeVertexColor")
        c.layer_name = "Col"
        nt.links.new(c.outputs["Color"], em.inputs["Color"])
    elif kind == "AO":
        outs = []
        for inside in (False, True):
            a = nt.nodes.new("ShaderNodeAmbientOcclusion")
            a.samples = 16
            a.inside = inside
            a.only_local = False
            a.inputs["Distance"].default_value = ao_dist
            outs.append(a.outputs["Color"])
        g = nt.nodes.new("ShaderNodeNewGeometry")
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        nt.links.new(g.outputs["Backfacing"], mx.inputs[0])
        nt.links.new(outs[0], next(x for x in mx.inputs if x.identifier == "A_Color"))
        nt.links.new(outs[1], next(x for x in mx.inputs if x.identifier == "B_Color"))
        nt.links.new(next(x for x in mx.outputs if x.identifier == "Result_Color"), em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0


def run_bake(low, highs, img, kind, mat, size, samples, cage=0.05, ray=0.12, ao_dist=0.6, log=print):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = cage
    sc.render.bake.max_ray_distance = ray
    sc.render.bake.margin = 0
    sc.render.bake.use_clear = False
    sc.render.bake.target = "IMAGE_TEXTURES"
    # target image node in the low material
    lm = low.data.materials[0]
    node = next(n for n in lm.node_tree.nodes if n.type == "TEX_IMAGE")
    node.image = img
    lm.node_tree.nodes.active = node
    low.data.uv_layers.active = low.data.uv_layers["Atlas"]
    low.data.uv_layers["Atlas"].active_render = True
    bpy.ops.object.select_all(action="DESELECT")
    for h in highs:
        h.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    t = time.time()
    if kind == "NORMAL":
        sc.render.bake.normal_space = "TANGENT"
        sc.render.bake.normal_r, sc.render.bake.normal_g, sc.render.bake.normal_b = "POS_X", "POS_Y", "POS_Z"
        bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, margin=0, use_clear=False)
    else:
        set_pass(mat, kind, ao_dist)
        bpy.ops.object.bake(type="EMIT", use_selected_to_active=True, margin=0, use_clear=False)
    log(f"  baked {kind} in {time.time() - t:.0f}s")
    return _read(img, size)


def bake_all(low, highs, size, cage=0.05, ray=0.12, ao_dist=0.6, ao_samples=48, log=print):
    """low = bake object (Atlas UVs + a material with an image node). Returns dict of float arrays."""
    mat = make_bake_material()
    for h in highs:
        h.data.materials.clear()
        h.data.materials.append(mat)
    # keep the low mesh out of the ray casts (visibility flags) so it does not shade / occlude
    for attr in ("visible_camera", "visible_diffuse", "visible_glossy", "visible_transmission",
                 "visible_volume_scatter", "visible_shadow"):
        try:
            setattr(low, attr, False)
        except Exception:
            pass
    # nothing but the high objects may occlude / shade during the bake
    hidden = []
    keep = set(o.name for o in highs) | {low.name}
    for o in bpy.context.scene.objects:
        if o.name not in keep and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    out = {}
    try:
        for kind, sm in (("NORMAL", 8), ("POS", 1), ("COL", 3), ("AO", ao_samples)):
            img = _new_float_image(f"bk_{kind}", size)
            out[kind] = run_bake(low, highs, img, kind, mat, size, sm, cage, ray, ao_dist, log)
    finally:
        for o in hidden:
            o.hide_render = False
    return out


# ============================================================== post: dilate, paint, pack
def rasterize_charts(bm, face_cls, lvl, charts, size):
    """(chart id + 1, class name list) rasters in Blender orientation (row 0 = v 0)."""
    from PIL import Image, ImageDraw
    uvl = bm.loops.layers.uv["Atlas"]
    ids = Image.new("I", (size, size), 0)
    d = ImageDraw.Draw(ids)
    fchart = {}
    for ci, ch in enumerate(charts):
        for fi in ch.faces:
            fchart[fi] = ci + 1
    for f in bm.faces:
        ci = fchart.get(f.index)
        if not ci:
            continue
        pts = [(l[uvl].uv.x * size, (1 - l[uvl].uv.y) * size) for l in f.loops]
        d.polygon(pts, fill=ci)
    return np.flipud(np.asarray(ids, dtype=np.int32)).copy()


def dilate(arrs, mask, reach=14):
    from scipy import ndimage
    dist, (iy, ix) = ndimage.distance_transform_edt(~mask, return_indices=True)
    fill = (~mask) & (dist <= reach)
    out = []
    for a in arrs:
        b = a.copy()
        b[fill] = a[iy[fill], ix[fill]]
        out.append(b)
    return out, mask | fill


def _blur(a, s):
    from scipy import ndimage
    return ndimage.gaussian_filter(a, s, mode="nearest")


def lin_to_srgb_np(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def paint_and_pack(passes, chart_map, charts, cls_of_chart, dummies, size, seed=1, cfg=None, log=print,
                   inst_dummy=None):
    cfg = cfg or {}
    rng = np.random.default_rng(seed)
    nrm = passes["NORMAL"]
    mask = nrm[..., 3] > 0.5
    log(f"  texel coverage {mask.mean() * 100:.1f}%")
    (nrm_d, pos_d, col_d, ao_d), full = dilate([nrm[..., :3], passes["POS"][..., :3], passes["COL"][..., :3],
                                                passes["AO"][..., :3]], mask)
    ao = ao_d[..., 0]
    # class index map (per texel) from the chart raster (dilated by nearest fill as well)
    cls_names = sorted(PBR_CONST.keys())
    cmap = np.zeros((size, size), dtype=np.int32)
    ch_cls = np.array([0] + [cls_names.index(c) + 1 for c in cls_of_chart], dtype=np.int32)
    cm = ch_cls[np.clip(chart_map, 0, len(ch_cls) - 1)]
    from scipy import ndimage
    dist, (iy, ix) = ndimage.distance_transform_edt(cm == 0, return_indices=True)
    cm_f = cm[iy, ix]
    cm_f[dist > 14] = 0
    isc = lambda name: (cm_f == cls_names.index(name) + 1)
    n = nrm_d * 2 - 1
    # curvature from the normal map (convex +, concave -)
    gx = np.gradient(_blur(n[..., 0], 0.7), axis=1)
    gy = np.gradient(_blur(n[..., 1], 0.7), axis=0)
    curv = gx + gy
    edge = np.clip(curv * 6.5, 0, 1)
    cav = np.clip(-curv * 6.5, 0, 1)
    slope = np.clip(np.hypot(n[..., 0], n[..., 1]) * 1.6, 0, 1)
    P = pos_d
    flatP = P.reshape(-1, 3)
    def fnoise(freq, octv=2, sd=0, off=0.0):
        return fbm(flatP + off, freq, octv, 0.5, sd).reshape(size, size)
    m_lo = fnoise(1 / 0.7, 3, seed)
    m_mid = fnoise(1 / 0.12, 2, seed + 3)
    hue = fnoise(1 / 1.3, 2, seed + 7)
    speck = rng.normal(0, 1, (size, size))
    speck = _blur(speck, 0.6) * 1.6
    c = col_d.copy()
    lum = (0.3 * c[..., 0] + 0.59 * c[..., 1] + 0.11 * c[..., 2])[..., None]
    var_amp = np.zeros((size, size))
    for name, amp in (("stone", 0.12), ("paving", 0.14), ("plaster", 0.07), ("wood", 0.10), ("roof", 0.07),
                      ("metal", 0.08), ("cloth", 0.05), ("plant", 0.05), ("thatch", 0.10)):
        var_amp[isc(name)] = amp
    c *= (1 + var_amp * (0.65 * m_lo + 0.55 * m_mid))[..., None]
    warm = np.array([1.05, 1.0, 0.92])
    cool = np.array([0.95, 1.0, 1.06])
    t = np.clip(hue * 0.5 + 0.5, 0, 1)[..., None]
    hue_k = np.zeros((size, size, 1))
    for name in ("stone", "paving", "plaster", "roof", "cloth"):
        hue_k[isc(name)] = 1.0
    c *= 1 + ((warm * t + cool * (1 - t)) ** 0.6 - 1) * hue_k
    grain_amp = np.zeros((size, size))
    for name, amp in (("stone", 0.05), ("paving", 0.05), ("plaster", 0.035), ("wood", 0.03), ("roof", 0.035),
                      ("cloth", 0.03)):
        grain_amp[isc(name)] = amp
    c *= (1 + grain_amp * speck)[..., None]
    # hand-painted stone granularity (dark / light flecks a texel or two wide)
    fleck = _blur(rng.normal(0, 1, (size, size)), 0.45) * 2.3
    stone_m = isc("stone") | isc("paving")
    c *= (1 + 0.075 * np.clip(fleck, -2.5, 2.5) * stone_m)[..., None]
    # plaster: hairline cracks and a few darker trowel patches
    plast = isc("plaster")
    if plast.any():
        rid = 1.0 - np.abs(fnoise(1 / 0.85, 3, seed + 31))
        crack = _blur(smoothstep(0.972, 0.995, rid) * plast, 0.7)
        c *= (1 - 0.30 * np.clip(crack * 1.6, 0, 1))[..., None]
        patch = fnoise(1 / 0.35, 2, seed + 41)
        c *= (1 + 0.05 * patch * plast)[..., None]
    # wood: painted grain streaks along each timber's long axis
    wood = isc("wood")
    if wood.any():
        yy, xx = np.mgrid[0:size, 0:size]
        streak = np.zeros((size, size))
        grain_lines = np.zeros((size, size))
        for ci, ch in enumerate(charts):
            if cls_of_chart[ci] != "wood":
                continue
            x0, y0, rw, rh = ch.rect
            if rw < 3 or rh < 3:
                continue
            sl = (slice(max(0, y0), min(size, y0 + rh)), slice(max(0, x0), min(size, x0 + rw)))
            sub = (chart_map[sl] == ci + 1)
            if not sub.any():
                continue
            r = np.random.default_rng(ci * 31 + seed)
            gh, gw = sub.shape
            if rw >= rh:      # grain runs along x
                prof = r.normal(0, 1, (gh, 1)) + 0.6 * _blur(r.normal(0, 1, (gh, 1)), 1.0)
                wob = _blur(r.normal(0, 1, (gh, gw)), (0.5, 6.0))
                st = prof + wob * 1.2
            else:
                prof = r.normal(0, 1, (1, gw)) + 0.6 * _blur(r.normal(0, 1, (1, gw)), 1.0)
                wob = _blur(r.normal(0, 1, (gh, gw)), (6.0, 0.5))
                st = prof + wob * 1.2
            streak[sl] = np.where(sub, st, streak[sl])
            # thin dark grain strokes along the timber (painted, a texel wide)
            if rw >= rh:
                ln = (r.random((gh, 1)) > 0.76).astype(np.float64)
                ln = _blur(np.broadcast_to(ln, (gh, gw)).copy() * r.uniform(0.5, 1.0, (gh, 1)), (0.35, 9.0))
            else:
                ln = (r.random((1, gw)) > 0.76).astype(np.float64)
                ln = _blur(np.broadcast_to(ln, (gh, gw)).copy() * r.uniform(0.5, 1.0, (1, gw)), (9.0, 0.35))
            grain_lines[sl] = np.where(sub, ln, grain_lines[sl])
        streak = np.where(wood, streak, 0.0)
        # spread the streaks into the dilated border
        s2 = _blur(streak, 0.5)
        c *= (1 + 0.14 * np.clip(s2, -2.2, 2.2) * wood)[..., None]
        gl = _blur(grain_lines, 0.4)
        c *= (1 - 0.32 * np.clip(gl * 2.6, 0, 1) * wood)[..., None]
    # cavities darken (warm, not black), worn convex edges catch light
    cav_col = np.array([0.30, 0.20, 0.13])
    k = (0.55 * cav * (cav_col[None, None, :].sum() > 0))[..., None]
    c = c * (1 - k) + (lum * cav_col * 1.6) * k
    edge_l = np.zeros((size, size, 3))
    edge_l[...] = (1.0, 1.0, 1.0)
    e = edge[..., None]
    light = np.ones_like(c)
    light[isc("stone")] = np.array([1.7, 1.6, 1.4])
    light[isc("paving")] = np.array([1.5, 1.42, 1.28])
    light[isc("plaster")] = np.array([1.25, 1.2, 1.12])
    light[isc("wood")] = np.array([1.5, 1.4, 1.25])
    light[isc("roof")] = np.array([1.55, 1.55, 1.7])
    light[isc("metal")] = np.array([2.6, 2.6, 2.6])
    light[isc("cloth")] = np.array([1.2, 1.2, 1.2])
    c = c * (1 + (light - 1) * e * 0.85)
    # slate / stone ledges: upward-tilted normals a little brighter, downward darker
    c *= (1 + 0.06 * (n[..., 1:2]))
    # ambient occlusion: a light touch (the ORM map carries the real one)
    c *= (0.86 + 0.14 * ao)[..., None]
    c = np.clip(c, 0.005, 1.0)
    # ---- ORM
    rough = np.full((size, size), 0.85)
    metal = np.zeros((size, size))
    for name, (r0, m0) in PBR_CONST.items():
        rough[isc(name)] = r0
        metal[isc(name)] = m0
    rough = rough + 0.09 * m_mid + 0.05 * speck * 0.5 + 0.10 * cav - 0.16 * edge
    # rusty iron: rough + dull
    ism = isc("metal")
    rust = smoothstep(0.35, 0.75, 0.5 + 0.9 * fnoise(1 / 0.05, 2, seed + 21)) * ism
    metal = metal * (1 - 0.85 * rust)
    rough = np.where(ism, rough + 0.32 * rust, rough)
    c[..., 0] = np.where(rust > 0, c[..., 0] * (1 + 0.5 * rust), c[..., 0])
    c[..., 2] = np.where(rust > 0, c[..., 2] * (1 - 0.35 * rust), c[..., 2])
    rough = np.clip(rough, 0.3, 1.0)
    aoo = np.clip(ao ** 1.15, 0, 1)
    orm = np.stack([aoo, rough, metal], -1)
    # ---- dummy fill blocks
    alb = c
    nrm_o = nrm_d.copy()
    tile_mask = np.zeros((size, size), dtype=bool)
    for ch in charts:
        if getattr(ch, "is_tile", False):
            x0_, y0_, rw_, rh_ = ch.rect
            tile_mask[y0_:y0_ + rh_, x0_:x0_ + rw_] = True
    for cname, (x, y, rw, rh, _) in dummies.items():
        sl = (slice(y, y + rh), slice(x, x + rw))
        m = np.array(PBR_CONST[cname])
        sel = (cm_f == cls_names.index(cname) + 1) & full & ~tile_mask
        if sel.any():
            mcol = alb[sel].mean(0)
        else:
            mcol = np.array([0.3, 0.25, 0.2])
        alb[sl] = mcol * 0.8
        nrm_o[sl] = (0.5, 0.5, 1.0)
        orm[sl] = (0.6, m[0], m[1])
    if inst_dummy is not None:
        x, y, rw, rh, _ = inst_dummy
        alb[y:y + rh, x:x + rw] = TILE_NEUTRAL
        nrm_o[y:y + rh, x:x + rw] = (0.5, 0.5, 1.0)
        orm[y:y + rh, x:x + rw] = (0.7, 0.75, 0.0)
    full2 = full.copy()
    if inst_dummy is not None:
        x, y, rw, rh, _ = inst_dummy
        full2[y:y + rh, x:x + rw] = True
    for cname, (x, y, rw, rh, _) in dummies.items():
        full2[y:y + rh, x:x + rw] = True
    # texels never baked or dilated: neutral defaults
    alb[~full2] = alb[full2].mean(0) if full2.any() else 0.3
    nrm_o[~full2] = (0.5, 0.5, 1.0)
    orm[~full2] = (0.7, 0.85, 0.0)
    # a touch more relief than the raw bake: stylised, and it survives the mip chain better
    nn = nrm_o * 2 - 1
    nn[..., :2] *= cfg.get("normal_gain", 1.5)
    nn[..., 2] = np.sqrt(np.clip(1 - nn[..., 0] ** 2 - nn[..., 1] ** 2, 0.02, 1))
    nrm_o = np.clip(nn * 0.5 + 0.5, 0, 1)
    return dict(alb=alb, nrm=nrm_o, orm=orm, edge=edge, cav=cav, mask=full2)


def save_png(path, arr, srgb=False):
    from PIL import Image
    a = np.flipud(np.clip(arr, 0, 1))
    if srgb:
        a = lin_to_srgb_np(a)
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGB").save(path, optimize=True)


# ============================================================== leaded window glass (shared tiny textures)
WIN_GRID = (6, 8)          # leaded quarries across x down (one window quad maps 0..1 x 0..1)
WIN_TEX = ("window_alb", "window_nrm", "window_emit")


def make_window_textures(out_dir=None, size=256, force=False):
    """Shared leaded-glass maps: albedo (glass tint x quarries, dark lead cames), tangent normal (raised
    cames, slightly domed quarries) and warm emission (lit windows). Returns the three paths."""
    out_dir = out_dir or PBR_DIR
    os.makedirs(out_dir, exist_ok=True)
    paths = [os.path.join(out_dir, n + ".png") for n in WIN_TEX]
    if all(os.path.exists(x) for x in paths) and not force:
        return paths
    rng = np.random.default_rng(11)
    nx, ny = WIN_GRID
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    u, v = xx / size, yy / size
    cx = (u * nx) % 1.0
    cy = (v * ny) % 1.0
    ix = np.floor(u * nx).astype(int)
    iy = np.floor(v * ny).astype(int)
    var = rng.uniform(-1, 1, (ny + 1, nx + 1))
    tint = var[np.clip(iy, 0, ny - 1), np.clip(ix, 0, nx - 1)]
    dx = np.minimum(cx, 1 - cx) * (size / nx)       # texel distance to the cell edge
    dy = np.minimum(cy, 1 - cy) * (size / ny)
    d = np.minimum(dx, dy)
    frame = np.minimum(np.minimum(u, 1 - u), np.minimum(v, 1 - v)) * size
    lead_w = 2.6
    lead = np.clip((lead_w - d) / 1.5, 0, 1)
    lead = np.maximum(lead, np.clip((lead_w * 1.3 - frame) / 1.5, 0, 1))
    dome = np.clip(d / (size / max(nx, ny) * 0.5), 0, 1)
    glass = np.stack([0.80 + 0.06 * tint, 0.88 + 0.05 * tint, 0.93 + 0.04 * tint], -1)
    glass *= (0.92 + 0.08 * dome)[..., None]
    glass *= (1 - 0.06 * (rng.random((size, size)) > 0.985))[..., None]        # a few bubbles
    leadc = np.array([0.16, 0.16, 0.18])
    alb = glass * (1 - lead[..., None]) + leadc * lead[..., None]
    # normal: gradient of a height field (cames stand proud, quarries bulge a little)
    h = 0.9 * lead + 0.25 * dome * (1 - lead) + 0.03 * tint
    gx = np.gradient(_blur(h, 0.7), axis=1) * 6.0
    gy = np.gradient(_blur(h, 0.7), axis=0) * 6.0
    n = np.stack([-gx, gy, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    nrm = n * 0.5 + 0.5
    warm = np.array([1.0, 0.70, 0.34])
    emit = warm[None, None, :] * (0.9 + 0.1 * tint)[..., None] * (1 - lead[..., None]) * (0.75 + 0.25 * dome)[..., None]
    save_png(paths[0], alb, srgb=True)
    save_png(paths[1], nrm)
    save_png(paths[2], emit, srgb=True)
    return paths


def make_window_material(kind, paths):
    """RA_PBR_glass (dark reflective glass) / RA_PBR_winlit (warm emissive), sharing the leaded maps."""
    name = "RA_PBR_glass" if kind == "glass" else "RA_PBR_winlit"
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]

    def img(path, nc):
        im = bpy.data.images.load(path, check_existing=True)
        im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        return n
    a = img(paths[0], False)
    mx = nt.nodes.new("ShaderNodeMix")
    mx.data_type = "RGBA"
    mx.blend_type = "MULTIPLY"
    mx.inputs[0].default_value = 1.0
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Col"
    nt.links.new(a.outputs["Color"], next(x for x in mx.inputs if x.identifier == "A_Color"))
    nt.links.new(vc.outputs["Color"], next(x for x in mx.inputs if x.identifier == "B_Color"))
    nt.links.new(next(x for x in mx.outputs if x.identifier == "Result_Color"), b.inputs["Base Color"])
    nm = img(paths[1], True)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.uv_map = "UVMap"
    nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.14 if kind == "glass" else 0.3
    b.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.8
    if kind == "winlit":
        e = img(paths[2], False)
        nt.links.new(e.outputs["Color"], b.inputs["Emission Color"])
        b.inputs["Emission Strength"].default_value = 1.6
    m.use_backface_culling = True
    return m


# ============================================================== final material + orchestration
def _gltf_occlusion_group():
    g = bpy.data.node_groups.get("glTF Material Output")
    if g is None:
        g = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
        g.interface.new_socket("Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return g


def make_pbr_material(name, alb_path, nrm_path, orm_path, use_col=True):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]

    def img(path, nc):
        im = bpy.data.images.load(path, check_existing=True)
        im.reload()
        im.colorspace_settings.name = "Non-Color" if nc else "sRGB"
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = im
        n.interpolation = "Linear"
        return n
    a = img(alb_path, False)
    if use_col:
        # albedo x COLOR_0 (instanced tiles carry their colour in the vertex colour; everything else is white)
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        mx.inputs[0].default_value = 1.0
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Col"
        nt.links.new(a.outputs["Color"], next(x for x in mx.inputs if x.identifier == "A_Color"))
        nt.links.new(vc.outputs["Color"], next(x for x in mx.inputs if x.identifier == "B_Color"))
        nt.links.new(next(x for x in mx.outputs if x.identifier == "Result_Color"), b.inputs["Base Color"])
    else:
        nt.links.new(a.outputs["Color"], b.inputs["Base Color"])
    o = img(orm_path, True)
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(o.outputs["Color"], sep.inputs["Color"])
    nt.links.new(sep.outputs["Green"], b.inputs["Roughness"])
    nt.links.new(sep.outputs["Blue"], b.inputs["Metallic"])
    nm = img(nrm_path, True)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.uv_map = "UVMap"
    nt.links.new(nm.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], b.inputs["Normal"])
    grp = nt.nodes.new("ShaderNodeGroup")
    grp.node_tree = _gltf_occlusion_group()
    nt.links.new(sep.outputs["Red"], grp.inputs["Occlusion"])
    if "Specular IOR Level" in b.inputs:
        b.inputs["Specular IOR Level"].default_value = 0.35
    m.use_backface_culling = True
    return m


CLASS_WEIGHT = {"plaster": 0.5, "roof": 0.75, "plant": 0.6, "paving": 0.8, "misc": 0.8, "metal": 1.1, "thatch": 0.7}


def default_weight(ch):
    w = CLASS_WEIGHT.get(ch.cls, 1.0)
    if ch.cls == "stone" and ch.area > 1.2:      # mortar core boxes: dark, flat
        w *= 0.55
    return w


def bake_asset(low_ob, name, size=1024, out_dir=None, seed=1, ao_dist=0.6, cage=0.05, ray=0.12, log=print,
               keep_high=False, level_weight=(0.0, 0.55, 1.0), ao_samples=48, weight_fn=None, tile_dens=None,
               tile_budget=0.26, tint_override=None, high_mesh=None, orm_div=1, planar=False):
    """Bake the PBR maps for the LOW mesh object `low_ob` (materials as the kit built them) and turn the object
    into the exportable PBR mesh: one atlas material for everything solid, the emissive materials untouched.
    high_mesh: a Mesh (same material names) to build the HIGH detail from instead of low_ob's own mesh (LOD1
    bakes the LOD0 detail onto its own coarser surface)."""
    global CLOTH_AMP
    out_dir = out_dir or PBR_DIR
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    me = low_ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    apply_tint(bm, me, tint_override)
    mats = list(me.materials)
    face_cls = {f.index: cls_of(mats[f.material_index].name) for f in bm.faces}
    L = compute_levels(bm)
    lvl = L["lvl"]
    seen, ns = shell_ids(bm)
    shells_of = {}
    for f in bm.faces:
        shells_of.setdefault((seen[f.index], face_cls.get(f.index)), []).append(f.index)
    inst, buckets = plan_tiles(bm, face_cls, lvl, shells_of)
    R = plan_and_pack(bm, face_cls, size, lvl, inst, buckets, level_weight=level_weight,
                      extra_weight=weight_fn or default_weight, tile_dens=tile_dens, tile_budget=tile_budget,
                      planar=planar)
    ninst = sum(1 for v in inst.values() if "key" in v)
    log(f"[{name}] atlas {size}: {len(R['charts'])} unique charts @ {R['k']:.1f} texel/m ({100 / R['k']:.1f} cm/texel), "
        f"{ninst} instanced faces -> {len(R['tiles'])} tiles  ({time.time() - t0:.0f}s)")
    cache = os.environ.get("RA_PBR_CACHE")
    cfile = os.path.join(cache, f"{name}_{size}.npz") if cache else None
    if cfile and os.path.exists(cfile):
        z = np.load(cfile)
        passes = {k: z[k] for k in z.files}
        log(f"  loaded cached bake passes {cfile}")
        return _finish_asset(low_ob, me, bm, mats, face_cls, lvl, inst, R, passes, name, size, out_dir, seed, log, t0,
                             [], [], None, None, orm_div=orm_div)
    # ---- HIGH
    if high_mesh is not None:
        bmh = bmesh.new()
        bmh.from_mesh(high_mesh)
        bmh.faces.ensure_lookup_table()
        apply_tint(bmh, high_mesh, tint_override)
        hmats = list(high_mesh.materials)
        fch = {f.index: cls_of(hmats[f.material_index].name) for f in bmh.faces}
        Lh = compute_levels(bmh)
        CLOTH_AMP = min(0.022, 0.55 * cage)
        metas, tile_lows = build_high(bmh, fch, Lh["lvl"], seed=seed, inst={}, tiles=R["tiles"], log=log)
        bmh.free()
    else:
        CLOTH_AMP = min(0.022, 0.55 * cage)
    metas, tile_lows = build_high(bm, face_cls, lvl, seed=seed, inst=inst, tiles=R["tiles"], log=log)
    highs = []
    for nm, m_ in metas:
        o = bpy.data.objects.new(nm, m_)
        bpy.context.scene.collection.objects.link(o)
        highs.append(o)
    log(f"  high built {time.time() - t0:.0f}s, {sum(len(m_.polygons) for _, m_ in metas)} polys")
    # ---- LOW bake object: unique faces + the tile quads
    bm.faces.index_update()
    kill_idx = [f.index for f in bm.faces if face_cls.get(f.index) is None or lvl[f.index] == 0
                or f.index in inst]
    bb = bm.copy()
    bb.faces.ensure_lookup_table()
    bmesh.ops.delete(bb, geom=[bb.faces[i] for i in kill_idx], context="FACES")
    uvb = bb.loops.layers.uv["Atlas"]
    for P, t in tile_lows:
        vs = [bb.verts.new(tuple(p)) for p in P]
        try:
            nf = bb.faces.new(vs)
        except ValueError:
            continue
        for li, l in enumerate(nf.loops):
            cu, cv = TILE_CORNERS[li]
            l[uvb].uv = tile_uv(t, cu, cv, size)
    lme = bpy.data.meshes.new(name + "_lowbake")
    bb.to_mesh(lme)
    bb.free()
    lme.materials.append(bpy.data.materials.new("LOWBAKE"))
    lm = lme.materials[0]
    lm.use_nodes = True
    lm.node_tree.nodes.new("ShaderNodeTexImage")
    lowb = bpy.data.objects.new(name + "_lowbake", lme)
    bpy.context.scene.collection.objects.link(lowb)
    lowb.matrix_world = low_ob.matrix_world
    passes = bake_all(lowb, highs, size, cage, ray, ao_dist, ao_samples, log)
    if cfile:
        os.makedirs(cache, exist_ok=True)
        np.savez_compressed(cfile, **passes)
    return _finish_asset(low_ob, me, bm, mats, face_cls, lvl, inst, R, passes, name, size, out_dir, seed, log, t0,
                         highs, metas, lowb, lme, keep_high, orm_div=orm_div)


def _finish_asset(low_ob, me, bm, mats, face_cls, lvl, inst, R, passes, name, size, out_dir, seed, log, t0,
                  highs, metas, lowb, lme, keep_high=False, orm_div=1):
    ninst = sum(1 for v in inst.values() if "key" in v)
    # ---- paint / pack
    chart_map = rasterize_charts(bm, {i: (c if (lvl[i] > 0 and i not in inst) else None) for i, c in face_cls.items()},
                                 lvl, R["charts"], size)
    class _T:
        pass
    all_charts = list(R["charts"])
    cls_of_chart = [ch.cls for ch in R["charts"]]
    for t in R["tiles"]:
        tc = _T()
        tc.is_tile = True
        tc.cls = "stone" if t["kind"] == "block" else "roof"
        x, y, rw, rh = t["rect"]
        tc.rect = (x, y, rw, rh)
        all_charts.append(tc)
        cls_of_chart.append(tc.cls)
        chart_map[y:y + rh, x:x + rw] = len(all_charts)
    maps = paint_and_pack(passes, chart_map, all_charts, cls_of_chart, R["dummies"], size, seed, log=log,
                          inst_dummy=R["inst_dummy"])
    p_alb = os.path.join(out_dir, f"{name}_alb.png")
    p_nrm = os.path.join(out_dir, f"{name}_nrm.png")
    p_orm = os.path.join(out_dir, f"{name}_orm.png")
    save_png(p_alb, maps["alb"], srgb=True)
    save_png(p_nrm, maps["nrm"])
    orm = maps["orm"]
    if orm_div > 1:      # AO / roughness are low frequency: half-size ORM saves texture memory
        n = size // orm_div
        orm = orm.reshape(n, orm_div, n, orm_div, 3).mean((1, 3))
    save_png(p_orm, orm)
    if os.environ.get("RA_PBR_DEBUG"):
        dbg = os.environ["RA_PBR_DEBUG"]
        os.makedirs(dbg, exist_ok=True)
        save_png(os.path.join(dbg, f"{name}_edge.png"), np.repeat(maps["edge"][..., None], 3, 2))
        save_png(os.path.join(dbg, f"{name}_ao.png"), np.repeat(passes["AO"][..., :1], 3, 2))
    if not keep_high and lowb is not None:
        for o in highs + [lowb]:
            bpy.data.objects.remove(o, do_unlink=True)
        for _, m_ in metas:
            bpy.data.meshes.remove(m_)
        bpy.data.meshes.remove(lme)
    # ---- final mesh: Atlas UV -> UVMap, one PBR material + the emissive ones
    pbr = make_pbr_material(f"RA_PBR_{name}", p_alb, p_nrm, p_orm)
    emissive = []
    fin = bm.copy()
    fin.faces.ensure_lookup_table()
    uvl_at = fin.loops.layers.uv["Atlas"]
    uv_old = fin.loops.layers.uv.get("UVMap")
    col = fin.loops.layers.float_color.get("Col")
    new_index = {}
    wpaths = None
    for f in fin.faces:
        c = face_cls.get(f.index)
        if c is None:
            mi = f.material_index
            if mi not in new_index:
                new_index[mi] = len(emissive) + 1
                mk_ = mat_key(mats[mi].name)
                if mk_ in ("Glass", "WindowLit"):
                    wpaths = wpaths or make_window_textures()
                    emissive.append(make_window_material("glass" if mk_ == "Glass" else "winlit", wpaths))
                else:
                    emissive.append(mats[mi])
            f.material_index = new_index[mi]
            if mat_key(mats[mi].name) in ("Glass", "WindowLit") and len(f.loops) == 4 and uv_old is not None:
                for li, l in enumerate(f.loops):
                    l[uv_old].uv = TILE_CORNERS[li]
            continue
        f.material_index = 0
        info = inst.get(f.index)
        for l in f.loops:
            if uv_old is not None:
                l[uv_old].uv = l[uvl_at].uv
            if info is not None:
                cc = l[col]
                l[col] = (min(1.0, cc[0] / TILE_NEUTRAL), min(1.0, cc[1] / TILE_NEUTRAL),
                          min(1.0, cc[2] / TILE_NEUTRAL), 1.0)
            else:
                l[col] = (1.0, 1.0, 1.0, 1.0)
    if uv_old is not None:
        fin.loops.layers.uv.remove(uvl_at)
    else:
        uvl_at.name = "UVMap"
    me.materials.clear()
    me.materials.append(pbr)
    for m_ in emissive:
        me.materials.append(m_)
    fin.to_mesh(me)
    fin.free()
    bm.free()
    for p_ in me.polygons:
        p_.use_smooth = p_.use_smooth
    log(f"[{name}] PBR bake done in {time.time() - t0:.0f}s  -> {os.path.relpath(p_alb, ROOT)}")
    return dict(paths=(p_alb, p_nrm, p_orm), charts=len(R["charts"]), k=R["k"], tiles=len(R["tiles"]),
                inst=ninst)


# ============================================================== close-up previews
def render_closeup(png, target, cam_dir, dist, lens=40, res=(960, 640), samples=64, ground_z=0.0, gsize=200.0,
                   sun=(57, 6, -38), hide=()):
    """Cycles render from `target` + cam_dir*dist with the game-like warm sun / sky (same as ra_kit previews)."""
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene
    for n in ("PreviewCam", "Sun", "PreviewGround"):
        for o in [o for o in bpy.data.objects if o.name.startswith(n)]:
            bpy.data.objects.remove(o, do_unlink=True)
    gm = bpy.data.materials.new("PreviewGround")
    gm.use_nodes = True
    b = gm.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*[c ** 2.2 for c in (0.40, 0.55, 0.24)], 1)
    b.inputs["Roughness"].default_value = 1.0
    bpy.ops.mesh.primitive_plane_add(size=gsize, location=(target[0], target[1], ground_z))
    g = bpy.context.active_object
    g.name = "PreviewGround"
    g.data.materials.append(gm)
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    d = Vector(cam_dir).normalized()
    tgt = Vector(target)
    cam.location = tgt + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    cam_data.clip_start = 0.05
    cam_data.clip_end = 2000
    sun_o = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun_o.data.energy = 4.0
    sun_o.data.color = (1.0, 0.87, 0.70)
    sun_o.data.angle = math.radians(2.0)
    sun_o.rotation_euler = tuple(math.radians(a) for a in sun)
    sc.collection.objects.link(sun_o)
    if sc.world is None or sc.world.name != "Sky":
        world = bpy.data.worlds.new("Sky")
        world.use_nodes = True
        nt = world.node_tree
        bg = nt.nodes["Background"]
        tc = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        nt.links.new(tc.outputs["Generated"], sep.inputs[0])
        nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
        ramp.color_ramp.elements[0].position = 0.5
        ramp.color_ramp.elements[0].color = (0.74, 0.76, 0.74, 1)
        ramp.color_ramp.elements[1].position = 0.53
        ramp.color_ramp.elements[1].color = (0.17, 0.39, 0.90, 1)
        nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
        bg.inputs["Strength"].default_value = 1.05
        sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = res
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)


# ============================================================== glTF export hook
import ra_polish as _RP
_orig_shared = _RP._is_shared_tex


def _shared_or_pbr(im):
    d = os.path.dirname(os.path.abspath(bpy.path.abspath(im.filepath)))
    return _orig_shared(im) or d == os.path.abspath(PBR_DIR)


_RP._is_shared_tex = _shared_or_pbr
