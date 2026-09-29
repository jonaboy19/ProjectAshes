"""Realistic rigged medieval villagers from the MakeHuman base mesh (MPFB2, CC0).

    python3 make_humans.py [--only name,name] [--no-preview] [--closeups]

Pipeline (all headless, bpy + numpy):
1. MakeHuman body from macro parameters (gender, age, ethnic mix, weight,
   muscle, height, proportions) -- MPFB target stack applied to base.obj.
   Helper geometry (joint cubes, clothes helpers, teeth, tongue) is dropped:
   only the `body` face group is kept.
2. The body is posed from the MakeHuman A-pose into the Quaternius UAL T-pose
   (bone by bone, linear-blend skinned with MakeHuman's own game_engine rig
   weights, whose bone names already match UAL/UE), then scaled so hip height
   matches the UAL mannequin (so the pelvis position track keeps feet on the floor).
3. Clothes, hair and hood are generated from the posed body: offset shells of
   body regions (smoothed, pushed outside the skin, with turned-in hems) and
   lofted skirts/cloaks/belts. Body faces hidden under clothes are deleted.
4. Every part is decimated to a triangle budget, UV-mapped into one shared
   1024 px atlas (skin, fabrics, leather, hair, eyes) and coloured with
   vertex colours (palette, skin tone, dirt at hems) so all characters share
   one material and three textures.
5. A GLB is written directly (ual_rig.write_skinned_glb) with the exact UAL
   65-bone hierarchy and rest orientations, so Godot's UAL clips play on it.
   A 40 % LOD1 is written next to it.
"""
import sys, os, math, random, time
import numpy as np
import bpy, bmesh
from mathutils import Vector, bvhtree, kdtree, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mh_core as mh
import ual_rig

KINGDOM = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(KINGDOM, ".."))
OUT_DIR = os.path.join(KINGDOM, "assets", "generated", "characters")
TEX_DIR = os.path.join(OUT_DIR, "textures")
PREVIEW_DIR = os.path.join(REPO, "docs", "kingdom", "blender_previews")
AMBIENTCG = os.path.join(KINGDOM, "assets", "incoming", "ambientcg")

ATLAS = 1024
HEAD_TRIS = 1350
EYE_SCALE = 1.2
HAND_TRIS = 170
# Atlas regions (u0, v0, u1, v1), v up (Blender convention).
REG = {
    "skin": (0.0, 0.5, 0.5, 1.0),
    "wool": (0.0, 0.0, 0.5, 0.5),
    "linen": (0.5, 0.75, 0.75, 1.0),
    "coarse": (0.75, 0.75, 1.0, 1.0),
    "leather": (0.5, 0.5, 0.75, 0.6875),
    "strap": (0.5, 0.6875, 0.75, 0.75),
    "hair": (0.75, 0.5, 1.0, 0.75),
    "quilt": (0.5, 0.25, 0.75, 0.5),
    "eye": (0.75, 0.25, 0.875, 0.375),
    "eye_blue": (0.875, 0.25, 1.0, 0.375),
    "eye_green": (0.75, 0.375, 0.875, 0.5),
    "eye_grey": (0.875, 0.375, 1.0, 0.5),
    "bag": (0.5, 0.125, 0.625, 0.25),
    "metal": (0.625, 0.125, 0.75, 0.25),
    "felt": (0.75, 0.0, 1.0, 0.25),
    "sole": (0.5, 0.0, 0.75, 0.125),
}
ROUGH = {"skin": 0.52, "linen": 0.93, "wool": 0.96, "leather": 0.62, "hair": 0.5,
         "coarse": 0.97, "quilt": 0.95, "strap": 0.6, "bag": 0.6, "eye": 0.14, "eye_blue": 0.14,
         "eye_green": 0.14, "eye_grey": 0.14, "metal": 0.38, "felt": 0.98, "sole": 0.8}
METAL = {"metal": 0.85}

UAL = ual_rig.UALSkeleton()
BONES = UAL.joints                     # 65 names, glTF skin order
BI = {n: i for i, n in enumerate(BONES)}


def srgb2lin(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def smoothstep(e0, e1, x):
    t = np.clip((np.asarray(x, dtype=float) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ============================================================ image helpers

def load_img(path, size):
    im = bpy.data.images.load(path, check_existing=False)
    im.scale(size, size)
    a = np.array(im.pixels[:], dtype=np.float32).reshape(size, size, 4)
    bpy.data.images.remove(im)
    return a


def save_png(arr, path, noncolor=False):
    h, w = arr.shape[:2]
    if arr.shape[2] == 3:
        arr = np.concatenate([arr, np.ones((h, w, 1), np.float32)], axis=2)
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    if noncolor:
        im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(np.clip(arr, 0, 1).astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def value_noise(shape, scale, seed, octaves=3):
    """Tileable-ish fractal value noise in [0,1] (numpy, bilinear)."""
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        n = max(2, int(scale * 2 ** o))
        g = rng.random((n + 1, n + 1)).astype(np.float32)
        g[-1, :] = g[0, :]
        g[:, -1] = g[:, 0]
        ys = np.linspace(0, n, h, endpoint=False)
        xs = np.linspace(0, n, w, endpoint=False)
        y0 = ys.astype(int); x0 = xs.astype(int)
        fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
        out += amp * (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy)
        tot += amp
        amp *= 0.5
    return out / tot


def blur(img, r):
    """Separable box blur (wrap-around), r in pixels, applied twice (~gaussian)."""
    if r < 1:
        return img
    k = np.ones(2 * r + 1, np.float32) / (2 * r + 1)
    out = img.astype(np.float32)
    for _ in range(2):
        for ax in (0, 1):
            pad = [(0, 0)] * out.ndim
            pad[ax] = (r, r)
            o = np.pad(out, pad, mode="wrap")
            out = np.apply_along_axis(lambda m: np.convolve(m, k, "valid"), ax, o)
    return out


def height_to_normal(hgt, strength):
    gy, gx = np.gradient(hgt)
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(hgt)], axis=2)
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def raster_uv(tris_uv, tris_val, size):
    """Rasterise per-corner values (T,3,C) over triangles (T,3,2) in [0,1] UV
    into a (size,size,C) image; returns (img, coverage)."""
    C = tris_val.shape[2]
    img = np.zeros((size, size, C), np.float32)
    cov = np.zeros((size, size), bool)
    P = tris_uv * size - 0.5
    for t in range(len(P)):
        a, b, c = P[t]
        x0 = int(max(0, math.floor(min(a[0], b[0], c[0]))))
        x1 = int(min(size - 1, math.ceil(max(a[0], b[0], c[0]))))
        y0 = int(max(0, math.floor(min(a[1], b[1], c[1]))))
        y1 = int(min(size - 1, math.ceil(max(a[1], b[1], c[1]))))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / den
        l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / den
        l3 = 1 - l1 - l2
        m = (l1 >= -0.02) & (l2 >= -0.02) & (l3 >= -0.02)
        if not m.any():
            continue
        v = tris_val[t]
        val = l1[..., None] * v[0] + l2[..., None] * v[1] + l3[..., None] * v[2]
        img[ys[m], xs[m]] = val[m]
        cov[ys[m], xs[m]] = True
    return img, cov


def dilate(img, cov, it=6):
    """Grow covered pixels outward (avoids dark seams at UV island borders)."""
    img = img.copy(); cov = cov.copy()
    for _ in range(it):
        acc = np.zeros_like(img); cnt = np.zeros(cov.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sc = np.roll(cov, (dy, dx), (0, 1))
            si = np.roll(img, (dy, dx), (0, 1))
            acc += si * sc[..., None]
            cnt += sc
        new = (~cov) & (cnt > 0)
        img[new] = acc[new] / cnt[new][:, None]
        cov |= new
    return img


# ============================================================ atlas

def vnoise(shape, sy, sx, seed, octaves=2):
    """Periodic value noise with an independent grid size per axis (anisotropic strokes)."""
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape, np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        ny = max(2, int(sy * 2 ** o)); nx = max(2, int(sx * 2 ** o))
        g = rng.random((ny + 1, nx + 1)).astype(np.float32)
        g[-1, :] = g[0, :]; g[:, -1] = g[:, 0]
        ys = np.linspace(0, ny, h, endpoint=False); xs = np.linspace(0, nx, w, endpoint=False)
        y0 = ys.astype(int); x0 = xs.astype(int)
        fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
        fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
        a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
        out += amp * (a * (1 - fx) * (1 - fy) + b * fx * (1 - fy) + c * (1 - fx) * fy + d * fx * fy)
        tot += amp; amp *= 0.5
    return out / tot


def stitch_line(w, h, y, period=9, dash=5.5, width=0.0035, x_off=0.0):
    """(h,w) mask of a dashed stitch line at v=y."""
    xs = np.arange(w)[None, :]
    ys = np.linspace(0, 1, h)[:, None]
    d = (((xs + x_off) % period) < dash).astype(np.float32)
    line = np.exp(-((ys - y) / width) ** 2)
    return line * d


def build_atlas(base):
    """Writes character_albedo.png / _normal.png / _orm.png (1024, shared).
    Hand-painted look: fabrics with brush strokes, fold streaks, stitched hems;
    leather with pebble grain, scuffs and stitched straps; radial hair strands
    with a painted highlight band; painted eyes in four iris colours."""
    os.makedirs(TEX_DIR, exist_ok=True)
    A = np.ones((ATLAS, ATLAS, 3), np.float32) * 0.8
    N = np.zeros((ATLAS, ATLAS, 3), np.float32); N[...] = (0.5, 0.5, 1.0)
    O = np.zeros((ATLAS, ATLAS, 3), np.float32)
    O[..., 0] = 1.0
    O[..., 1] = 0.9

    def put(name, alb, nrm=None, rough=None, ao=None):
        u0, v0, u1, v1 = REG[name]
        x0, x1 = int(round(u0 * ATLAS)), int(round(u1 * ATLAS))
        y0, y1 = int(round(v0 * ATLAS)), int(round(v1 * ATLAS))
        A[y0:y1, x0:x1] = alb[..., :3]
        if nrm is not None:
            N[y0:y1, x0:x1] = nrm[..., :3]
        r = ROUGH[name] if rough is None else rough
        O[y0:y1, x0:x1, 1] = r
        O[y0:y1, x0:x1, 2] = METAL.get(name, 0.0)
        if ao is not None:
            O[y0:y1, x0:x1, 0] = ao

    def region_size(name):
        u0, v0, u1, v1 = REG[name]
        return int(round((u1 - u0) * ATLAS)), int(round((v1 - v0) * ATLAS))

    def cloth(name, src, seed, bright=0.92, weave=0.05, slub=0.0, folds=0.09, hem=0.034,
              mott=0.07, nstr=1.0, twill=0.0):
        w, hh = region_size(name)
        s = max(w, hh)
        rng = np.random.default_rng(seed)
        col = load_img(os.path.join(AMBIENTCG, src, f"{src}_2K-JPG_Color.jpg"), s)[:hh, :w, :3]
        wl = col.mean(axis=2)
        wl = blur(wl, 5)
        wl = (wl - wl.mean()) / max(wl.std(), 1e-3)
        xs = np.linspace(0, 1, w, endpoint=False)[None, :]
        ys = np.linspace(0, 1, hh, endpoint=False)[:, None]
        m1 = vnoise((hh, w), 4, 4, seed + 1, 4)
        brush = vnoise((hh, w), 5, max(20, w // 4), seed + 2, 2)
        brush2 = vnoise((hh, w), max(20, hh // 5), 6, seed + 3, 2)
        f = np.zeros((hh, w), np.float32)
        for k in range(4):
            fr = rng.uniform(2.5, 9.0); ph = rng.uniform(0, 1)
            f += rng.uniform(0.5, 1.0) * np.sin(2 * math.pi * (fr * xs + ph + 0.12 * np.sin(2 * math.pi * ys * 0.8 + k)))
        f /= 2.4
        dep = np.exp(-ys * 2.6)
        L = 1 + weave * wl + mott * (m1 - 0.5) * 2 + 0.06 * (brush - 0.5) * 2 + 0.03 * (brush2 - 0.5) * 2 + folds * f * dep
        L += 0.022 * np.sin(2 * math.pi * xs * (w / (6.0 if w > 300 else 4.0))) * np.sin(2 * math.pi * ys * (hh / (6.0 if w > 300 else 4.0)))
        if twill:
            L += twill * np.sin(2 * math.pi * (xs * w / 6.0 + ys * hh / 6.0))
        if slub:
            for _ in range(int(hh * 0.18)):
                yy = rng.integers(0, hh)
                L[yy, :] *= 1 + slub * rng.uniform(-1, 1) * (0.4 + vnoise((1, w), 1, 6, int(rng.integers(1e6)), 1)[0])
            for _ in range(int(w * 0.14)):
                xx = rng.integers(0, w)
                L[:, xx] *= 1 + slub * rng.uniform(-1, 1)
        alb = L * bright
        # turned hem at the bottom of the tile (v = 0 is always the garment hem)
        yh = hem
        band = ys < yh
        alb = np.where(band, alb * 0.93, alb)
        alb *= 1 - 0.22 * np.exp(-(ys / 0.006) ** 2)                           # hem edge shadow
        alb *= 1 - 0.28 * np.exp(-((ys - yh) / 0.0045) ** 2)                   # fold-over seam
        alb *= 1 - 0.30 * stitch_line(w, hh, yh * 0.5, period=max(6, w // 40), dash=max(4, w // 62), width=0.0028)
        alb = np.clip(alb, 0, 1)
        hgt = 0.35 * wl * 0.05 + 0.02 * f * dep + 0.03 * (brush - 0.5) - 0.05 * np.exp(-((ys - yh) / 0.006) ** 2) \
            - 0.04 * stitch_line(w, hh, yh * 0.5, period=max(6, w // 40), dash=max(4, w // 62), width=0.003)
        put(name, np.repeat(alb[..., None], 3, 2) * np.array([1.0, 0.995, 0.985], np.float32),
            height_to_normal(hgt, 14 * nstr))

    cloth("linen", "Fabric061", 11, bright=0.93, weave=0.025, slub=0.018, folds=0.08)
    cloth("wool", "Fabric066", 12, bright=0.9, weave=0.035, folds=0.1, mott=0.08, twill=0.012)
    cloth("coarse", "Fabric066", 13, bright=0.88, weave=0.06, folds=0.08, mott=0.1, slub=0.04)

    # Felt / cloak wool: soft fibres, stitched hem.
    w, h = region_size("felt")
    n1 = vnoise((h, w), 5, 5, 21, 5); n2 = vnoise((h, w), 60, 60, 22, 2)
    ys = np.linspace(0, 1, h, endpoint=False)[:, None]; xs = np.linspace(0, 1, w, endpoint=False)[None, :]
    rng = np.random.default_rng(23)
    f = sum(rng.uniform(0.5, 1) * np.sin(2 * math.pi * (rng.uniform(3, 8) * xs + rng.uniform(0, 1))) for _ in range(4)) / 2.4
    alb = 0.9 * (1 - 0.10 * (n1 - 0.5) * 2 - 0.05 * (n2 - 0.5) * 2 + 0.09 * f * np.exp(-ys * 2.6))
    alb *= 1 - 0.22 * np.exp(-(ys / 0.006) ** 2) * 1 - 0.0
    alb *= 1 - 0.28 * np.exp(-((ys - 0.04) / 0.0045) ** 2)
    alb *= 1 - 0.30 * stitch_line(w, h, 0.02, period=8, dash=5, width=0.003)
    put("felt", np.repeat(np.clip(alb, 0, 1)[..., None], 3, 2), height_to_normal(n2 * 0.4 + n1 * 0.6 + f * 0.05, 1.4))

    # Quilted gambeson: vertical puffed channels with stitch lines, stitched hem.
    w, h = region_size("quilt")
    xs = np.linspace(0, 1, w, endpoint=False)[None, :].repeat(h, 0)
    ys = np.linspace(0, 1, h, endpoint=False)[:, None].repeat(w, 1)
    ch = 12.0
    ph = (xs * ch) % 1.0
    puff = np.sin(ph * math.pi) ** 0.6
    stitch = np.exp(-((ph - 0.0) ** 2) / 0.0012) + np.exp(-((ph - 1.0) ** 2) / 0.0012)
    dash = (np.sin(ys * 120 * math.pi) > -0.3).astype(np.float32)
    n1 = vnoise((h, w), 5, 5, 31, 4)
    hgt = puff - 0.6 * stitch * dash
    alb = 0.92 * (0.74 + 0.26 * puff) * (1 - 0.4 * stitch * dash) * (1 - 0.1 * (n1 - 0.5))
    base_lin = load_img(os.path.join(AMBIENTCG, "Fabric061", "Fabric061_2K-JPG_Color.jpg"), w)[:h, :w, :3].mean(axis=2)
    alb = alb * (0.9 + 0.25 * (base_lin - base_lin.mean()))
    yh = 0.04
    alb *= 1 - 0.3 * np.exp(-((ys - yh) / 0.005) ** 2)
    alb *= 1 - 0.3 * stitch_line(w, h, yh * 0.5, 8, 5, 0.003)
    put("quilt", np.clip(np.repeat(alb[..., None], 3, 2), 0, 1), height_to_normal(hgt, 6))

    # Leather: pebbled grain, creases, scuffs (light) and dark patina.
    w, h = region_size("leather")
    g1 = vnoise((h, w), 70, 90, 41, 2)
    g2 = vnoise((h, w), 10, 12, 42, 3)
    peb = np.clip((vnoise((h, w), 70, 90, 44, 1) - 0.5) * 3 + 0.5, 0, 1)
    cre = (np.abs(vnoise((h, w), 4, 5, 43, 3) - 0.5) < 0.018).astype(np.float32)
    scuff = np.clip((vnoise((h, w), 16, 20, 45, 2) - 0.7) * 5, 0, 1) * 0.3
    alb = 0.80 * (1 - 0.12 * (g2 - 0.5) * 2) * (1 - 0.04 * (g1 - 0.5) * 2) * (1 - 0.025 * peb) * (1 - 0.12 * cre) * (1 + 0.28 * scuff)
    put("leather", np.repeat(np.clip(alb, 0, 1)[..., None], 3, 2), height_to_normal(peb * 0.06 + g1 * 0.05 + g2 * 0.08 - cre * 0.05, 3))
    u0, v0, u1, v1 = REG["leather"]
    O[int(v0 * ATLAS):int(v1 * ATLAS), int(u0 * ATLAS):int(u1 * ATLAS), 1] = 0.5 + 0.28 * g2 - 0.15 * scuff

    # Strap / belt strip (u along the strap, v across): edge paint, bevel, double stitching, holes.
    w, h = region_size("strap")
    ys = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    xs = np.arange(w)[None, :].repeat(h, 0).astype(np.float32)
    gn = vnoise((h, w), 6, 90, 46, 3)
    alb = 0.82 * (1 - 0.2 * (gn - 0.5) * 2)
    edge = np.minimum(ys, 1 - ys)
    alb *= 1 - 0.42 * np.exp(-(edge / 0.05) ** 2)                       # dark painted edge
    alb *= 1 + 0.16 * np.exp(-((edge - 0.115) / 0.03) ** 2)             # bevel highlight
    for yy in (0.24, 0.76):
        alb *= 1 - 0.55 * stitch_line(w, h, yy, period=11, dash=7, width=0.028)
    holes = np.zeros((h, w), np.float32)
    for k in range(5):
        cx = w - 14 - k * 16
        holes += np.exp(-(((xs - cx) / 3.2) ** 2 + ((ys - 0.5) * h / 3.2) ** 2))
    alb *= 1 - 0.7 * np.clip(holes, 0, 1)
    hg = -0.3 * np.exp(-(edge / 0.06) ** 2) - 0.25 * np.clip(holes, 0, 1)
    for yy in (0.24, 0.76):
        hg -= 0.2 * stitch_line(w, h, yy, 11, 7, 0.03)
    put("strap", np.repeat(np.clip(alb, 0, 1)[..., None], 3, 2), height_to_normal(hg + gn * 0.05, 8))

    # Bag panel (pouches / satchel): stitched border, flap line, brass stud.
    w, h = region_size("bag")
    ys = np.linspace(0, 1, h)[:, None].repeat(w, 1)
    xs = np.linspace(0, 1, w)[None, :].repeat(h, 0)
    gn = vnoise((h, w), 8, 8, 47, 4)
    alb = 0.82 * (1 - 0.2 * (gn - 0.5) * 2)
    bx = np.minimum(xs, 1 - xs); by = np.minimum(ys, 1 - ys); ed = np.minimum(bx, by)
    alb *= 1 - 0.4 * np.exp(-(ed / 0.03) ** 2)
    box = np.maximum(np.abs(xs - 0.5) / 0.4, np.abs(ys - 0.5) / 0.4)
    ring = np.exp(-((box - 1.0) / 0.03) ** 2)
    ang = np.arctan2(ys - 0.5, xs - 0.5)
    alb *= 1 - 0.5 * ring * (np.sin((xs + ys) * 90) > -0.2)
    flap = 0.42 + 0.06 * np.sin(xs * math.pi * 2) * 0 - 0.25 * (xs - 0.5) ** 2
    alb *= 1 - 0.45 * np.exp(-((ys - flap) / 0.018) ** 2)
    alb *= 1 + 0.15 * np.exp(-((ys - flap + 0.04) / 0.03) ** 2)
    stud = np.exp(-(((xs - 0.5) ** 2 + (ys - flap + 0.09) ** 2) / 0.0012))
    albc = np.repeat(np.clip(alb, 0, 1)[..., None], 3, 2)
    albc = albc * (1 - stud[..., None]) + stud[..., None] * np.array([0.95, 0.8, 0.45], np.float32)
    hg = -0.25 * ring - 0.3 * np.exp(-((ys - flap) / 0.02) ** 2) + 0.4 * stud
    put("bag", albc, height_to_normal(hg + gn * 0.04, 8))

    # Boot soles / dark leather.
    w, h = region_size("sole")
    n = vnoise((h, w), 20, 30, 51, 3)
    put("sole", np.repeat((0.55 + 0.12 * n)[..., None], 3, 2), height_to_normal(n, 3))

    # Hair strands: radial from the crown (u = azimuth, v = polar angle), clumps, sheen band.
    w, h = region_size("hair")
    rng = np.random.default_rng(61)
    xs = np.linspace(0, 1, w, endpoint=False)[None, :]
    ys = np.linspace(0, 1, h, endpoint=False)[:, None]
    line = np.zeros((h, w), np.float32)
    for _ in range(90):
        x0 = rng.random(); wd = rng.uniform(0.0012, 0.0035); dk = rng.uniform(0.25, 0.7)
        drift = rng.uniform(-0.03, 0.03); wob = rng.uniform(0, 6.28)
        xc = x0 + drift * ys + 0.004 * np.sin(ys * 9 + wob)
        d = np.abs((xs - xc + 0.5) % 1.0 - 0.5)
        line += dk * np.exp(-(d / wd) ** 2) * (0.5 + 0.5 * np.sin(ys * rng.uniform(1, 3) + rng.uniform(0, 6)) ** 2)
    line = np.clip(line, 0, 1)
    clump = vnoise((h, w), 3, 16, 62, 3)
    hi = np.zeros((h, w), np.float32)
    for _ in range(70):
        x0 = rng.random(); wd = rng.uniform(0.0015, 0.004)
        xc = x0 + 0.004 * np.sin(ys * 8 + rng.uniform(0, 6))
        d = np.abs((xs - xc + 0.5) % 1.0 - 0.5)
        hi += rng.uniform(0.3, 0.9) * np.exp(-(d / wd) ** 2)
    hi = np.clip(hi, 0, 1)
    sheen = np.exp(-((ys - 0.36) / 0.09) ** 2) * (0.55 + 0.45 * vnoise((h, w), 2, 9, 64, 2))
    alb = 0.58 * (0.80 + 0.20 * clump) * (1 - 0.50 * line) + 0.52 * hi * (0.45 + 0.75 * sheen) + 0.24 * sheen * (1 - line)
    alb *= 0.86 + 0.14 * smoothstep(0.0, 0.22, ys)                      # dark parting at the crown
    alb = np.clip(alb, 0, 1)
    put("hair", np.repeat(alb[..., None], 3, 2), height_to_normal(-line * 0.5 + hi * 0.3 + clump * 0.2, 3.5))

    # Metal: brushed, scratched iron/steel with soft bevel light.
    w, h = region_size("metal")
    br = vnoise((h, w), 40, 4, 71, 3); sc = vnoise((h, w), 3, 7, 72, 3)
    ys = np.linspace(0, 1, h)[:, None]
    alb = 0.72 * (1 + 0.16 * (br - 0.5) * 2) * (1 - 0.1 * (sc - 0.5) * 2) * (0.92 + 0.12 * ys)
    put("metal", np.repeat(np.clip(alb, 0, 1)[..., None], 3, 2), height_to_normal(br * 0.3, 2))

    # Eyes: painted iris (4 colours), limbal ring, pupil, catchlight, warm sclera with shaded rim.
    # Layout copied from the MakeHuman eye texture: two discs, iris r=.114, sclera r=.283 (of 1024).
    iris_cols = {"eye": (0.36, 0.20, 0.09), "eye_blue": (0.22, 0.42, 0.66),
                 "eye_green": (0.30, 0.50, 0.24), "eye_grey": (0.45, 0.50, 0.55)}
    ew, eh = region_size("eye")
    SS = 512
    yy, xx = np.mgrid[0:SS, 0:SS].astype(np.float32) / SS
    for nm, ic in iris_cols.items():
        img = np.ones((SS, SS, 3), np.float32) * np.array([0.9, 0.88, 0.84], np.float32)
        ic = np.array(ic, np.float32)
        for cx, cyi in ((0.705, 1 - 0.296), (0.288, 1 - 0.708)):        # centres (x, v up)
            dx = xx - cx; dy = yy - cyi
            r = np.sqrt(dx * dx + dy * dy)
            th = np.arctan2(dy, dx)
            rs = r / 0.283
            scl = np.array([0.95, 0.93, 0.89], np.float32) * (1 - 0.32 * smoothstep(0.55, 1.0, rs))[..., None]
            scl = scl * (1 - 0.12 * smoothstep(0.35, 0.5, rs) * (1 - smoothstep(0.5, 0.6, rs)))[..., None]
            ri = r / 0.114
            rad = 0.5 + 0.5 * np.sin(th * 34 + 3 * np.sin(th * 5)) * np.sin(th * 13 + 1.0)
            inner = np.clip(1.25 - ri, 0, 1)[..., None]
            iris = ic[None, None, :] * (0.55 + 0.5 * inner) * (0.85 + 0.3 * rad[..., None])
            iris += np.array([0.10, 0.08, 0.02], np.float32) * smoothstep(0.35, 0.7, ri)[..., None] * (1 - smoothstep(0.7, 0.85, ri))[..., None]
            limb = smoothstep(0.78, 1.0, ri)[..., None]
            iris = iris * (1 - 0.8 * limb)
            pup = smoothstep(0.36, 0.30, ri)[..., None]
            iris = iris * (1 - pup) + 0.02 * pup
            mix_i = smoothstep(1.02, 0.96, ri)[..., None]
            e = scl * (1 - mix_i) + iris * mix_i
            # catchlight up-left of the pupil (sphere up = +v)
            cl = np.exp(-(((xx - (cx - 0.045)) ** 2 + (yy - (cyi + 0.05)) ** 2) / 0.00028))
            cl2 = np.exp(-(((xx - (cx + 0.035)) ** 2 + (yy - (cyi - 0.04)) ** 2) / 0.00012)) * 0.5
            e = e * (1 - np.clip(cl + cl2, 0, 1)[..., None]) + np.clip(cl + cl2, 0, 1)[..., None]
            m = (r < 0.30)[..., None]
            img = np.where(m, e, img)
        tile = img.reshape(ew, SS // ew, ew, SS // ew, 3).mean(axis=(1, 3))
        put(nm, tile, None, rough=0.14)

    # ---------------- skin, painted in MakeHuman UV space
    skin_paint(base, put, O)

    paths = {k: os.path.join(TEX_DIR, f"character_{k}.png") for k in ("albedo", "normal", "orm")}
    save_png(A, paths["albedo"])
    save_png(N, paths["normal"], noncolor=True)
    save_png(O, paths["orm"], noncolor=True)
    print("atlas written", paths)
    return paths


def skin_paint(base, put, O):
    """Skin tile painted in MakeHuman UV space with analytic face features."""
    u0, v0, u1, v1 = REG["skin"]
    S = int(round((u1 - u0) * ATLAS))
    fidx = base.faces_of_group("body")
    vb = mh.to_blender(base.v)
    tri_uv, tri_pos = [], []
    for fi in fidx:
        vs, ts = base.faces[fi], base.fuv[fi]
        for k in range(1, len(vs) - 1):
            tri_uv.append([base.uv[ts[0]], base.uv[ts[k]], base.uv[ts[k + 1]]])
            tri_pos.append([vb[vs[0]], vb[vs[k]], vb[vs[k + 1]]])
    tri_uv = np.array(tri_uv); tri_pos = np.array(tri_pos, np.float32)
    posmap, cov = raster_uv(tri_uv, tri_pos, S)
    posmap = dilate(posmap, cov, 8)
    joints = mh.joint_positions(base, vb)

    def mask(name):
        return load_img(os.path.join(mh.MPFB, "textures", name), S)[..., 0]
    lips = mask("mpfb_lips.jpg")
    lids = mask("mpfb_eyelids.jpg")
    nails = mask("mpfb_fingernails.jpg") + mask("mpfb_toenails.jpg")
    ears = mask("mpfb_ears.jpg")
    px, py, pz = posmap[..., 0], posmap[..., 1], posmap[..., 2]
    b1 = vnoise((S, S), 5, 5, 81, 4)
    b2 = value_noise((S, S), 90, 82, 2)
    b3 = vnoise((S, S), 40, 40, 84, 3)
    skin = np.ones((S, S, 3), np.float32) * np.array([0.98, 0.93, 0.90], np.float32)
    skin *= (1 - 0.05 * (b1 - 0.5) * 2 - 0.015 * (b2 - 0.5) * 2)[..., None]
    le, re_ = joints["joint-l-eye"], joints["joint-r-eye"]
    mo = joints["joint-mouth"]
    eye_z = (le[2] + re_[2]) / 2
    eye_x = abs(le[0])
    front = (py < le[1] + 0.02) & (py < le[1] - 0.005 + 0.03)
    head = pz > eye_z - 0.16
    ax = np.abs(px)
    fh = front * head
    # warm/cool painterly zones: ruddy nose, cheeks and ears; cooler, slightly green temples/jaw
    cheek = np.exp(-(((ax - eye_x * 1.0) / 0.026) ** 2 + ((pz - (eye_z - 0.04)) / 0.022) ** 2)) * fh
    nose = np.exp(-((ax / 0.013) ** 2 + ((pz - (eye_z - 0.043)) / 0.016) ** 2)) * fh
    red = np.clip(cheek * 1.0 + nose * 0.7 + ears * 0.6, 0, 1)
    skin *= (1 - red[..., None] * np.array([0.0, 0.10, 0.10], np.float32))
    temple = np.exp(-(((ax - eye_x * 1.7) / 0.03) ** 2 + ((pz - (eye_z + 0.005)) / 0.03) ** 2)) * fh
    skin *= (1 - temple[..., None] * np.array([0.03, 0.0, 0.03], np.float32))
    # forehead highlight
    fore = np.exp(-((ax / 0.05) ** 2 + ((pz - (eye_z + 0.06)) / 0.03) ** 2)) * fh
    skin *= (1 + 0.03 * fore)[..., None]
    # eye sockets
    sock = np.exp(-(((ax - eye_x) / 0.024) ** 2 + ((pz - eye_z) / 0.016) ** 2)) * fh
    skin *= (1 - (sock * 0.13 + lids * 0.12)[..., None] * np.array([1.0, 1.05, 0.85], np.float32))
    # upper lash line (thick, winged) and soft lower lash
    ex = ax - eye_x
    ell = np.sqrt((ex / 0.0175) ** 2 + ((pz - (eye_z + 0.0015)) / 0.0105) ** 2)
    upper = np.exp(-((ell - 1.0) / 0.10) ** 2) * (pz > eye_z - 0.002) * (0.9 + 0.5 * np.clip(ex / 0.017, 0, 1))
    lower = np.exp(-((ell - 1.05) / 0.10) ** 2) * (pz <= eye_z - 0.002) * 0.22
    crease = np.exp(-(((np.sqrt((ex / 0.019) ** 2 + ((pz - (eye_z + 0.0075)) / 0.0115) ** 2)) - 1.0) / 0.2) ** 2) * (pz > eye_z + 0.004) * 0.28
    lash = np.clip(upper + lower, 0, 1) * fh
    skin *= (1 - lash[..., None] * 0.55)
    skin *= (1 - (crease * fh)[..., None] * np.array([0.35, 0.45, 0.5], np.float32))
    # eyebrows: bold tapered arcs
    s = (ax - (eye_x - 0.020)) / 0.052
    zc = eye_z + 0.0225 + 0.007 * np.sin(np.clip(s, 0, 1) * math.pi * 0.85) - 0.0045 * s
    half = 0.0030 * (1 - np.clip(s, 0, 1) ** 1.3) + 0.0011
    d = np.abs(pz - zc)
    brow = (1 - smoothstep(half * 0.55, half * 1.2, d)) * smoothstep(-0.08, 0.06, s) * (1 - smoothstep(0.85, 1.05, s))
    hairy = vnoise((S, S), 60, 180, 83, 2)
    brow *= (0.75 + 0.25 * hairy) * fh
    skin *= (1 - brow[..., None] * np.array([0.5, 0.56, 0.64], np.float32))
    # nostrils / nose wings shading
    nos = np.exp(-((((ax - 0.0085) / 0.005) ** 2) + ((pz - (eye_z - 0.0525)) / 0.0036) ** 2)) * fh
    skin *= (1 - 0.0 * nos[..., None])
    wing = np.exp(-((((ax - 0.0175) / 0.006) ** 2) + ((pz - (eye_z - 0.047)) / 0.008) ** 2)) * fh
    skin *= (1 - 0.08 * wing[..., None])
    # lips: rose colour, darker mouth line, brighter lower lip
    lipc = np.array([0.82, 0.52, 0.56], np.float32)
    skin = skin * (1 - lips[..., None]) + skin * lipc * lips[..., None]
    mline = np.exp(-(((pz - (mo[2] + 0.0035 * np.clip(ax / 0.02, 0, 1.3) ** 2)) / 0.0016) ** 2)) * (ax < 0.022) * fh * (1 - smoothstep(0.012, 0.02, ax) * 0.6)
    skin *= (1 - 0.34 * mline[..., None])
    lowlip = np.exp(-((ax / 0.012) ** 2 + ((pz - (mo[2] - 0.0075)) / 0.0035) ** 2)) * fh
    skin *= (1 + 0.06 * lowlip)[..., None]
    skin = skin * (1 - nails[..., None] * 0.5) + np.array([1.0, 0.93, 0.9], np.float32) * nails[..., None] * 0.5
    # knuckles / elbows / knees: slightly ruddy
    hgt = b2 * 0.4 + b1 * 0.2 + b3 * 0.15
    put("skin", np.clip(skin, 0, 1), height_to_normal(hgt, 1.0))
    O[int(v0 * ATLAS):int(v1 * ATLAS), int(u0 * ATLAS):int(u1 * ATLAS), 1] = \
        ROUGH["skin"] + 0.10 * (b2 - 0.5) - 0.12 * lips + 0.12 * brow - 0.05 * lowlip


# ============================================================ body

SEG_GROUPS = {
    "torso": {"pelvis", "spine_01", "spine_02", "spine_03", "clavicle_l", "clavicle_r"},
    "neck": {"neck_01"},
    "head": {"Head"},
    "uarm": {"upperarm_l", "upperarm_r"},
    "larm": {"lowerarm_l", "lowerarm_r"},
    "hand": {"hand_l", "hand_r"} | {f"{f}_{k:02d}_{sd}" for f in ("index", "middle", "ring", "pinky", "thumb")
                                    for k in (1, 2, 3) for sd in "lr"},
    "thigh": {"thigh_l", "thigh_r"},
    "calf": {"calf_l", "calf_r"},
    "foot": {"foot_l", "foot_r", "ball_l", "ball_r"},
}


_LIPS = {}


def lips_mask_sampler(base):
    if "img" not in _LIPS:
        im = bpy.data.images.load(os.path.join(mh.MPFB, "textures", "mpfb_lips.jpg"), check_existing=False)
        w, hh = im.size
        _LIPS["img"] = np.array(im.pixels[:], dtype=np.float32).reshape(hh, w, 4)[..., 0]
        bpy.data.images.remove(im)
    a = _LIPS["img"]
    hh, w = a.shape

    def f(uv):
        x = np.clip((uv[:, 0] * w).astype(int), 0, w - 1)
        y = np.clip((uv[:, 1] * hh).astype(int), 0, hh - 1)
        return a[y, x]
    return f


class Human:
    """Posed (UAL T-pose), normalised MakeHuman body at full resolution."""

    def __init__(self, base, r):
        self.base = base
        self.r = r
        stack = mh.macro_stack(r["gender"], r["age"], muscle=r.get("muscle", 0.5),
                               weight=r.get("weight", 0.5), height=r.get("height", 0.5),
                               proportions=r.get("proportions", 0.6), race=r["race"],
                               cupsize=r.get("cup", 0.5), firmness=r.get("firm", 0.5))
        extras = {"eyes/l-eye-scale-incr": 0.55, "eyes/r-eye-scale-incr": 0.55,
                  "eyes/l-eye-height2-incr": 0.25, "eyes/r-eye-height2-incr": 0.25,
                  "mouth/mouth-angles-up": 0.6,
                  "mouth/mouth-upperlip-volume-incr": 0.2, "mouth/mouth-lowerlip-volume-incr": 0.2}
        extras.update(r.get("extras", {}))
        v = mh.morph(base, stack, extras)
        vb = mh.to_blender(v)
        bones, joints = mh.mh_bones(base, vb)
        names = list(bones.keys())
        W, _ = mh.weight_matrix(len(vb), names)
        tdir = {n: UAL.axis_b(mh.ue_name(n)) for n in names}
        sec = {}
        for sd in "lr":
            sec["hand_" + sd] = (joints[f"joint-{sd}-finger-2-1"] - joints[f"joint-{sd}-finger-5-1"],
                                 UAL.pos_b("index_01_" + sd) - UAL.pos_b("pinky_01_" + sd))
            sec["foot_" + sd] = (np.array([1.0, 0, 0]), np.array([1.0, 0, 0]))
        vp, T = mh.pose_to_targets(vb, bones, W, names, tdir, sec)

        def tp(n, p):
            M = T[n]
            return M[:3, :3] @ p + M[:3, 3]
        J = {}
        for n in names:
            J[mh.ue_name(n)] = tp(n, bones[n][0])
        for sd in "lr":
            for f in ("index", "middle", "ring", "pinky", "thumb"):
                J[f"{f}_04_leaf_{sd}"] = tp(f"{f}_03_{sd}", bones[f"{f}_03_{sd}"][1])
            J[f"ball_leaf_{sd}"] = tp(f"ball_{sd}", bones[f"ball_{sd}"][1])
        # Normalise: hip joints at UAL height, pelvis offset like UAL.
        nb = 13380
        sole = vp[:nb, 2].min()
        thigh = (J["thigh_l"] + J["thigh_r"]) / 2
        ual_thigh = (UAL.pos_b("thigh_l") + UAL.pos_b("thigh_r")) / 2
        ual_pelvis = UAL.pos_b("pelvis")
        s = (ual_thigh[2] - 0.0) / (thigh[2] - sole)
        self.native_scale = 1.0 / s              # metres per model unit
        self.native_height = (vp[:nb, 2].max() - sole) / 1.0
        off = np.array([-thigh[0], 0.0, -sole])
        vp = (vp + off) * s
        for k in J:
            J[k] = (J[k] + off) * s
        thigh = (J["thigh_l"] + J["thigh_r"]) / 2
        J["pelvis"] = thigh + (ual_pelvis - ual_thigh)
        shift = np.array([0.0, ual_pelvis[1] - J["pelvis"][1], 0.0])
        vp += shift
        for k in J:
            J[k] = J[k] + shift
        J["root"] = np.zeros(3)
        self.J = J
        self.P = vp                      # all 19158 verts (helpers too)
        # UAL-indexed weights
        WU = np.zeros((len(vp), len(BONES)))
        for bi, n in enumerate(names):
            WU[:, BI[mh.ue_name(n)]] = W[:, bi]
        sw = WU.sum(axis=1, keepdims=True)
        self.W = np.where(sw > 0, WU / np.maximum(sw, 1e-9), 0)
        self.dom = np.array([BONES[i] for i in self.W.argmax(axis=1)])
        self._stylise(r.get("stylise", {"Head": 1.13, "hand": 1.2, "foot": 1.08}))
        # body topology
        self.fidx = base.faces_of_group("body")
        self.faces = [base.faces[i] for i in self.fidx]
        self.fuv = [base.fuv[i] for i in self.fidx]
        self.nb = nb
        self.N = vertex_normals(self.P[:nb], self.faces)
        self.bvh = bvhtree.BVHTree.FromPolygons([tuple(p) for p in self.P[:nb]], self.faces)
        seg = np.empty(nb, dtype=object)
        for k, g in SEG_GROUPS.items():
            m = np.isin(self.dom[:nb], list(g))
            seg[m] = k
        self.seg = seg
        # UV islands: ears and mouth interior (by MH UV position)
        vuv = np.zeros((nb, 2))
        for f, t in zip(self.faces, self.fuv):
            for a, b in zip(f, t):
                vuv[a] = base.uv[b]
        self.vuv = vuv
        self.ear = (vuv[:, 0] < 0.17) & (vuv[:, 1] > 0.42) & (vuv[:, 1] < 0.66)
        self.mouth_in = (vuv[:, 0] > 0.74) & (vuv[:, 1] < 0.14)
        jn = mh.joint_positions(base, vb)
        # landmark joints in posed/normalised space (head verts are skinned to Head only)
        self.eye_l = self.P[base.group_verts("helper-l-eye")].mean(axis=0)
        self.eye_r = self.P[base.group_verts("helper-r-eye")].mean(axis=0)
        lipm = lips_mask_sampler(base)
        lv = lipm(vuv[:nb]) > 0.5
        self.mouth = self.P[:nb][lv].mean(axis=0) if lv.sum() > 4 else self._head_pt(jn["joint-mouth"], vb, self.P)
        self.head_top = self.P[:nb][self.seg == "head"][:, 2].max()
        hv = self.P[:nb][self.seg == "head"]
        self.head_c = np.array([0.0, hv[:, 1].mean(), (hv[:, 2].max() + self.eye_l[2]) / 2 - 0.01])
        self.head_back = hv[:, 1].max()
        self.head_front = hv[:, 1].min()
        self.chin_z = hv[np.abs(hv[:, 0]) < 0.01][:, 2].min()

    def ear_near(self, P):
        e = self.P[:self.nb][self.ear]
        if len(e) == 0:
            return np.zeros(len(P), bool)
        kd = kdtree.KDTree(len(e))
        for i, p in enumerate(e):
            kd.insert(Vector(p), i)
        kd.balance()
        return np.array([kd.find(Vector(p))[2] < 0.02 for p in P])

    def _stylise(self, sc):
        """Slightly larger head, hands and feet (readable at distance): scale the
        vertices skinned to each chain about its root joint, children joints too."""
        chains = {"Head": ["Head"]}
        for sd in "lr":
            fingers = [f"{f}_{k:02d}_{sd}" for f in ("index", "middle", "ring", "pinky", "thumb") for k in (1, 2, 3)]
            fingers += [f"{f}_04_leaf_{sd}" for f in ("index", "middle", "ring", "pinky", "thumb")]
            chains["hand_" + sd] = ["hand_" + sd] + fingers
            chains["foot_" + sd] = ["foot_" + sd, "ball_" + sd, "ball_leaf_" + sd]
        P = self.P
        disp = np.zeros_like(P)
        for root, members in chains.items():
            key = root.split("_")[0]
            f = sc.get(key, 1.0)
            if f == 1.0:
                continue
            w = sum(self.W[:, BI[m]] for m in members if m in BI)
            c = self.J[root]
            disp += w[:, None] * (f - 1) * (P - c)
            for m in members[1:]:
                self.J[m] = c + (self.J[m] - c) * f
        self.P = P + disp

    def _head_pt(self, p_rest, vb, vp):
        """Map a rest-space point near the head into posed space via nearest vertex offset."""
        d = np.linalg.norm(vb[:self.nb] - p_rest, axis=1)
        i = d.argmin()
        return vp[i] + (p_rest - vb[i]) * (1.0 / self.native_scale) * 1.0 if False else vp[i] + (p_rest - vb[i]) / self.native_scale

    def mask(self, *segs):
        return np.isin(self.seg, list(segs))

    def z(self, bone):
        return self.J[bone][2]


def vertex_normals(P, faces):
    N = np.zeros_like(P)
    for f in faces:
        a = P[f[0]]
        for k in range(1, len(f) - 1):
            n = np.cross(P[f[k]] - a, P[f[k + 1]] - a)
            for i in (f[0], f[k], f[k + 1]):
                N[i] += n
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


# ============================================================ parts

class Part:
    """A mesh piece: verts (n,3), faces [tuple], per-corner uv (same shape as
    faces, in 0-1 of its atlas tile), weights (n,65), colour (n,3 linear)."""

    def __init__(self, name, verts, faces, uvs, weights, color, tile, budget=None):
        self.name = name
        self.v = np.asarray(verts, float)
        self.f = [tuple(int(i) for i in f) for f in faces]
        self.uv = uvs
        self.w = np.asarray(weights, float)
        self.c = np.asarray(color, float)
        self.tile = tile
        self.budget = budget


def edges_of(faces):
    e = set()
    for f in faces:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            e.add((min(a, b), max(a, b)))
    return np.array(sorted(e))


def laplacian(P, E, iters, lam=0.5, fixed=None, project=None):
    P = P.copy()
    for _ in range(iters):
        acc = np.zeros_like(P); cnt = np.zeros(len(P))
        np.add.at(acc, E[:, 0], P[E[:, 1]]); np.add.at(acc, E[:, 1], P[E[:, 0]])
        np.add.at(cnt, E[:, 0], 1); np.add.at(cnt, E[:, 1], 1)
        avg = acc / np.maximum(cnt, 1)[:, None]
        newP = P + lam * (avg - P)
        if fixed is not None:
            newP[fixed] = P[fixed]
        P = newP
        if project is not None:
            P = project(P)
    return P


def push_out(h, P, dmin):
    """Keep points at least dmin (per point) outside the body surface."""
    P = P.copy()
    dmin = np.broadcast_to(np.asarray(dmin, float), (len(P),))
    for i in range(len(P)):
        loc, nrm, idx, dist = h.bvh.find_nearest(Vector(P[i]))
        if loc is None:
            continue
        loc = np.array(loc); nrm = np.array(nrm)
        s = np.dot(P[i] - loc, nrm)
        if s < dmin[i]:
            P[i] = P[i] + nrm * (dmin[i] - s)
    return P


def boundary_loops(faces):
    """Directed boundary edges (a->b as they appear in their face)."""
    cnt = {}
    for f in faces:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            key = (min(a, b), max(a, b))
            cnt[key] = cnt.get(key, 0) + 1
    out = []
    for f in faces:
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            if cnt[(min(a, b), max(a, b))] == 1:
                out.append((a, b))
    return out


def shell(h, mask, d, smooth=6, dmin=None, extra=None, rim=True, rim_depth=None, noise_amp=0.0, seed=0, taubin=0, push_final=True):
    """Offset shell from body faces whose verts are all in `mask`.
    d: offset (scalar or per-body-vertex array). Returns dict with verts,
    faces (local), src (body vertex id per local vertex), rim flags."""
    nb = h.nb
    dd = np.broadcast_to(np.asarray(d, float), (nb,)) if np.ndim(d) == 0 else np.asarray(d, float)
    faces = [f for f in h.faces if all(mask[i] for i in f)]
    ids = sorted({i for f in faces for i in f})
    loc = {g: k for k, g in enumerate(ids)}
    lf = [tuple(loc[i] for i in f) for f in faces]
    src = np.array(ids)
    P0 = h.P[src] + h.N[src] * dd[src][:, None]
    if noise_amp:
        for k in range(len(P0)):
            p = P0[k]
            P0[k] = p + h.N[src[k]] * noise_amp * noise.noise(Vector(p * 18.0 + seed))
    if extra is not None:
        P0 = extra(P0, src)
    E = edges_of(lf)
    dm = dd[src] * 0.8 if dmin is None else np.broadcast_to(np.asarray(dmin, float), (len(src),))
    bnd = np.zeros(len(src), bool)
    for a, b in boundary_loops(lf):
        bnd[a] = bnd[b] = True
    P = P0
    for _ in range(max(1, smooth // 4)):
        P = laplacian(P, E, 4, 0.5, fixed=bnd)
        P = push_out(h, P, dm)
    if taubin:
        # shrink-free smoothing removes toes / nipples / knuckles etc.
        for _ in range(taubin):
            P = laplacian(P, E, 1, 0.5, fixed=bnd)
            P = laplacian(P, E, 1, -0.53, fixed=bnd)
        if push_final:
            P = push_out(h, P, dm * 0.4)
    P = laplacian(P, E, 2, 0.35, fixed=bnd)
    if push_final:
        P = push_out(h, P, dm * (0.4 if taubin else 1.0))
    # smooth hem/neckline curves along the boundary (removes the stair steps of the mesh rows)
    nbr = {}
    for a, b in boundary_loops(lf):
        nbr.setdefault(a, []).append(b)
        nbr.setdefault(b, []).append(a)
    bl = [k for k, v in nbr.items() if len(v) == 2]
    if bl:
        bi_ = np.array(bl)
        n1 = np.array([nbr[k][0] for k in bl]); n2 = np.array([nbr[k][1] for k in bl])
        for _ in range(8):
            P[bi_] = 0.5 * P[bi_] + 0.25 * (P[n1] + P[n2])
    out = {"v": P, "f": lf, "src": src, "rim": np.zeros(len(P), bool)}
    if rim:
        be = boundary_loops(lf)
        bverts = sorted({a for a, b in be} | {b for a, b in be})
        rv = {}
        V = list(P)
        S = list(src)
        for a in bverts:
            s0 = src[a]
            depth = rim_depth if rim_depth is not None else 0.0015
            rv[a] = len(V)
            # rim sits under the (smoothed) hem, folded back to the skin
            V.append(P[a] - h.N[s0] * max(dd[s0] - depth, 0.0))
            S.append(s0)
        F = list(lf)
        for a, b in be:
            F.append((b, a, rv[a], rv[b]))
        out = {"v": np.array(V), "f": F, "src": np.array(S),
               "rim": np.r_[np.zeros(len(P), bool), np.ones(len(rv), bool)]}
    return out


def covered(h, mask, rings=2):
    """Body vertices safely hidden under a shell built from `mask`:
    the mask minus `rings` rings next to its boundary."""
    m = mask.copy()
    E = edges_of(h.faces)
    for _ in range(rings):
        bad = np.zeros(h.nb, bool)
        a, b = E[:, 0], E[:, 1]
        edge_out = m[a] != m[b]
        bad[a[edge_out]] = True
        bad[b[edge_out]] = True
        m &= ~bad
    return m


# ------------------------------------------------------------ UV helpers

def cyl_uv(P, faces, axis_pt, axis_dir, labels=None):
    """Per-corner cylindrical UVs in metres around an axis (seam-safe)."""
    axis_dir = axis_dir / np.linalg.norm(axis_dir)
    ref = np.array([0.0, 1.0, 0.0]) if abs(axis_dir[1]) < 0.9 else np.array([1.0, 0, 0])
    e1 = ref - axis_dir * np.dot(ref, axis_dir); e1 /= np.linalg.norm(e1)
    e2 = np.cross(axis_dir, e1)
    Q = P - axis_pt
    h = Q @ axis_dir
    ang = np.arctan2(Q @ e2, Q @ e1)
    rad = np.linalg.norm(Q - np.outer(h, axis_dir), axis=1)
    R = max(np.median(rad), 0.02)
    uvs = []
    for f in faces:
        a = [ang[i] for i in f]
        a0 = a[0]
        a = [x + 2 * math.pi if x - a0 < -math.pi else (x - 2 * math.pi if x - a0 > math.pi else x) for x in a]
        uvs.append([(a[k] * R, h[f[k]]) for k in range(len(f))])
    return uvs


def pack_islands(islands, margin=0.03):
    """islands: list of lists of per-face corner uv lists (metres).
    Uniformly scales & shelf-packs them into [0,1]^2. Returns the same structure."""
    boxes = []
    for isl in islands:
        pts = np.array([p for f in isl for p in f])
        lo, hi = pts.min(0), pts.max(0)
        boxes.append((lo, hi - lo))
    total = sum(max(s[0], 1e-4) * max(s[1], 1e-4) for _, s in boxes)
    scale = math.sqrt(0.62 / max(total, 1e-9))
    for _ in range(40):
        x = y = rowh = margin
        pos = []
        ok = True
        order = sorted(range(len(boxes)), key=lambda i: -boxes[i][1][1])
        place = {}
        for i in order:
            w, hh = boxes[i][1] * scale
            if x + w + margin > 1:
                x = margin
                y += rowh + margin
                rowh = 0
            if w + 2 * margin > 1 or y + hh + margin > 1:
                ok = False
                break
            place[i] = (x, y)
            x += w + margin
            rowh = max(rowh, hh)
        if ok:
            break
        scale *= 0.93
    out = []
    for i, isl in enumerate(islands):
        lo = boxes[i][0]
        px, py = place[i]
        out.append([[((u - lo[0]) * scale + px, (v - lo[1]) * scale + py) for (u, v) in f] for f in isl])
    return out


def pack_hem(islands, margin=0.012):
    """Garment packer: islands (metres, v up = away from the hem) share one
    row, bottom aligned at the tile's v = margin, so the hem / cuff of every
    garment always lands on the painted stitched hem strip of its tile."""
    boxes = []
    for isl in islands:
        pts = np.array([p for f in isl for p in f])
        lo, hi = pts.min(0), pts.max(0)
        boxes.append((lo, hi - lo))
    n = len(boxes)
    wsum = sum(b[1][0] for b in boxes)
    hmax = max(b[1][1] for b in boxes)
    scale = min((1 - margin * (n + 1)) / max(wsum, 1e-6), (1 - 2 * margin) / max(hmax, 1e-6))
    out = []
    x = margin
    for i, isl in enumerate(islands):
        lo = boxes[i][0]
        out.append([[((u - lo[0]) * scale + x, (v - lo[1]) * scale + margin) for (u, v) in f] for f in isl])
        x += boxes[i][1][0] * scale + margin
    return out


def fullmap_uv(UV, inset=0.0):
    """Both axes stretched to the tile (straps / belts: u along, v across)."""
    pts = np.array([p for f in UV for p in f])
    lo, hi = pts.min(0), pts.max(0)
    sp = np.maximum(hi - lo, 1e-6)
    return [[(inset + (u - lo[0]) / sp[0] * (1 - 2 * inset), inset + (v - lo[1]) / sp[1] * (1 - 2 * inset)) for (u, v) in f] for f in UV]


def sphere_uv(P, faces, centre):
    """Hair UVs: u = azimuth around the vertical axis (seam at the back),
    v = polar angle from the crown, so painted strands radiate from the crown."""
    Q = P - centre
    az = np.arctan2(Q[:, 0], -Q[:, 1])
    th = np.arccos(np.clip(Q[:, 2] / np.maximum(np.linalg.norm(Q, axis=1), 1e-9), -1, 1))
    uvs = []
    for f in faces:
        a = [az[i] for i in f]
        a0 = a[0]
        a = [x + 2 * math.pi if x - a0 < -math.pi else (x - 2 * math.pi if x - a0 > math.pi else x) for x in a]
        uvs.append([(0.02 + 0.96 * (a[k] + math.pi) / (2 * math.pi), min(max(th[f[k]] / 2.3, 0.0), 1.0)) for k in range(len(f))])
    return uvs


def island_uvs(P, faces, groups, hem=False):
    """groups: list of (face_index_list, axis_pt, axis_dir). Cylindrical per group, packed.
    axis_dir None = spherical (hair). hem=True: hem-aligned row packing (cloth)."""
    if all(ad is None for _, _, ad in groups):
        uvs = [None] * len(faces)
        for fl, ap, _ in groups:
            for fi, uv in zip(fl, sphere_uv(P, [faces[i] for i in fl], ap)):
                uvs[fi] = uv
        return uvs
    islands = []
    for fl, ap, ad in groups:
        islands.append(cyl_uv(P, [faces[i] for i in fl], ap, ad))
    packed = pack_hem(islands) if hem else pack_islands(islands)
    uvs = [None] * len(faces)
    for (fl, _, _), isl in zip(groups, packed):
        for fi, uv in zip(fl, isl):
            uvs[fi] = uv
    return uvs


# ------------------------------------------------------------ colour helpers

def dirt(h, P, amount=0.25, hem_z=None, seed=0, knees=True):
    """Multiplicative grime (0..1 darkening) per vertex: low on the garment,
    near hems and knees/elbows, plus blotches."""
    g = np.zeros(len(P))
    z = P[:, 2]
    g += amount * (1 - smoothstep(0.0, 0.35, z)) * 0.45
    if hem_z is not None:
        g += amount * 0.5 * (1 - smoothstep(0.0, 0.08, np.abs(z - hem_z)))
    if knees:
        for b in ("calf_l", "calf_r", "lowerarm_l", "lowerarm_r"):
            g += amount * 0.4 * np.exp(-np.sum((P - h.J[b]) ** 2, axis=1) / 0.004)
    for i in range(len(P)):
        g[i] += amount * 0.25 * max(0.0, noise.noise(Vector(P[i] * 5.0 + seed)))
    return np.clip(g, 0, 0.6)


def paint(base_srgb, n, grime=None, var=0.0, seed=0):
    rng = np.random.default_rng(seed)
    c = srgb2lin(base_srgb) / srgb2lin(0.88)       # atlas fabrics average ~0.88 sRGB
    c = c / max(1.0, c.max() * 1.05)                # Godot stores vertex colours as 8-bit 0-1: keep the hue
    col = np.tile(c, (n, 1))
    if var:
        col *= 1 + (rng.random((n, 1)) - 0.5) * var
    if grime is not None:
        col *= (1 - grime)[:, None] * np.array([1.0, 0.97, 0.93]) + grime[:, None] * np.array([0.0, 0.0, 0.0])
    return np.clip(col, 0, 1.0)


CLOTH_TILES = ("linen", "wool", "coarse", "felt", "quilt")


def weights_from_src(h, src):
    return h.W[src]


def shell_part(h, name, sh, tile, color_srgb, budget, groups_fn, grime=0.2, hem_z=None, seed=0,
               rim_dark=0.85, weights=None):
    P, F = sh["v"], sh["f"]
    groups = groups_fn(P, F, sh)
    uvs = island_uvs(P, F, groups, hem=tile in CLOTH_TILES)
    g = dirt(h, P, grime, hem_z, seed)
    col = paint(color_srgb, len(P), g, 0.04, seed)
    col[sh["rim"]] *= rim_dark
    W = weights if weights is not None else h.W[sh["src"]]
    return Part(name, P, F, uvs, W, col, tile, budget)


def body_axis_groups(h, parts):
    """Face grouping for cylindrical UVs: torso (vertical), each arm (along x),
    each leg (vertical through the thigh)."""
    def fn(P, F, sh):
        src = sh["src"]
        seg = h.seg[src]
        dom = h.dom[src]
        buckets = {}
        for fi, f in enumerate(F):
            segs = [seg[i] for i in f]
            xs = P[list(f), 0].mean()
            s = max(set(segs), key=segs.count)
            if s in ("uarm", "larm", "hand") and "arms" in parts:
                key = "arm_l" if xs > 0 else "arm_r"
            elif s in ("thigh", "calf", "foot") and "legs" in parts:
                key = "leg_l" if xs > 0 else "leg_r"
            elif s == "torso" and "legs" in parts and "torso" not in parts:
                key = "leg_l" if xs > 0 else "leg_r"
            elif s in ("head", "neck") and "head" in parts:
                key = "head"
            else:
                key = "torso"
            buckets.setdefault(key, []).append(fi)
        out = []
        for key, fl in buckets.items():
            if key.startswith("arm"):
                sd = key[-1]
                a = h.J["upperarm_" + sd]; b = h.J["hand_" + sd]
                out.append((fl, a, a - b))
            elif key.startswith("leg"):
                sd = key[-1]
                a = h.J["thigh_" + sd]; b = h.J["foot_" + sd]
                out.append((fl, a, a - b))
            elif key == "head":
                out.append((fl, h.head_c, np.array([0, 0, 1.0])))
            else:
                out.append((fl, np.array([0, h.J["spine_02"][1], 0]), np.array([0, 0, 1.0])))
        return out
    return fn


# ------------------------------------------------------------ garments

def neck_cut(h, P, depth_front=0.04, width=0.07, back=0.012):
    """z threshold for a neckline at points P."""
    nz = h.z("neck_01") - back
    fr = np.clip(-(P[:, 1] - h.J["neck_01"][1]) / 0.05, 0, 1)
    wid = np.clip(1 - (P[:, 0] / width) ** 2, 0, 1)
    return nz - depth_front * fr * wid


def top_mask(h, bottom_z, sleeve, collar=False, neck_depth=0.04, neck_width=0.075):
    """Torso + arms region for tunics / bodices / gambesons."""
    P = h.P[:h.nb]
    m = h.mask("torso", "uarm", "larm", "neck")
    m &= P[:, 2] > bottom_z
    ax = np.abs(P[:, 0])
    m &= ax < sleeve
    if collar:
        m &= P[:, 2] < h.z("neck_01") + 0.035
        m &= ~h.mask("head")
    else:
        m &= P[:, 2] < neck_cut(h, P, neck_depth, neck_width)
    return m


def sleeve_x(h, frac):
    """|x| of a sleeve end: frac 0 = elbow, 1 = wrist."""
    e = abs(h.J["lowerarm_l"][0]); w = abs(h.J["hand_l"][0])
    return e + (w - e) * frac


def envelope(h, z, phis, center, exclude_arms=True, pts=None, ring_h=0.018):
    """Radial envelope of the body (or given points) at height z for angles phis
    (0 = back (+Y), measured towards +X)."""
    if pts is None:
        P = h.P[:h.nb]
        m = np.abs(P[:, 2] - z) < ring_h
        if exclude_arms:
            m &= ~h.mask("uarm", "larm", "hand")
        Q = P[m]
    else:
        Q = pts[np.abs(pts[:, 2] - z) < ring_h]
    r = np.zeros(len(phis))
    if len(Q) == 0:
        return r
    dx = Q[:, 0] - center[0]; dy = Q[:, 1] - center[1]
    ang = np.arctan2(dx, dy)
    rad = np.hypot(dx, dy)
    for k, ph in enumerate(phis):
        dif = np.abs((ang - ph + math.pi) % (2 * math.pi) - math.pi)
        sel = dif < 0.35
        if sel.any():
            # projected extent along this direction
            r[k] = (rad[sel] * np.cos(dif[sel])).max()
    # circular smoothing + fill
    for _ in range(2):
        r = np.maximum(r, 0.5 * (np.roll(r, 1) + np.roll(r, -1)))
    return r


def center_y(h, z, ring_h=0.03):
    """Front-back centre of the body cross-section at height z (no arms)."""
    P = h.P[:h.nb]
    m = (np.abs(P[:, 2] - z) < ring_h) & ~h.mask("uarm", "larm", "hand")
    if not m.any():
        return h.J["spine_02"][1]
    return 0.5 * (P[m, 1].min() + P[m, 1].max())


def loft(rings_pts, closed=True, cap=False):
    """rings_pts: (R, S, 3). Returns verts, faces (quads), per-corner uv (metres)."""
    R, S, _ = rings_pts.shape
    V = rings_pts.reshape(-1, 3)
    F, UV = [], []
    # u from arc length of first ring, v from profile length
    seg = np.linalg.norm(np.diff(rings_pts, axis=1), axis=2)            # (R, S-1)
    if closed:
        seg = np.concatenate([seg, np.linalg.norm(rings_pts[:, :1] - rings_pts[:, -1:], axis=2)], axis=1)
    ucum = np.concatenate([np.zeros((R, 1)), np.cumsum(seg, axis=1)], axis=1).mean(axis=0)
    prof = np.linalg.norm(np.diff(rings_pts, axis=0), axis=2).mean(axis=1)
    vcum = np.concatenate([[0], np.cumsum(prof)])
    ns = S if closed else S - 1
    for i in range(R - 1):
        for j in range(ns):
            j2 = (j + 1) % S
            a, b, c, d = i * S + j, i * S + j2, (i + 1) * S + j2, (i + 1) * S + j
            F.append((a, d, c, b))
            UV.append([(ucum[j], -vcum[i]), (ucum[j], -vcum[i + 1]), (ucum[j + 1], -vcum[i + 1]), (ucum[j + 1], -vcum[i])])
    # orient outward (away from each ring's centre)
    score = 0.0
    for f in F:
        a, b, c = V[f[0]], V[f[1]], V[f[2]]
        n = np.cross(b - a, c - a)
        ring = f[0] // S
        score += np.dot(n, (a + b + c) / 3 - rings_pts[ring].mean(axis=0))
    if score < 0:
        F = [tuple(reversed(f)) for f in F]
        UV = [list(reversed(u)) for u in UV]
    return V, F, UV


def skirt_weights(h, P, z_top, z_hem, long=False):
    W = np.zeros((len(P), len(BONES)))
    t = np.clip((z_top - P[:, 2]) / max(z_top - z_hem, 1e-3), 0, 1)
    wp = np.clip(1 - t * 1.25, 0, 1) ** 1.2
    side = smoothstep(-0.06, 0.06, P[:, 0])
    leg = 1 - wp
    knee = h.z("calf_l")
    calf = np.clip((knee - P[:, 2]) / max(knee - h.z("foot_l"), 1e-3), 0, 1) * 0.55 if long else np.zeros(len(P))
    # keep some pelvis influence everywhere so the skirt doesn't split
    wp = np.maximum(wp, 0.35)
    leg = 1 - wp
    W[:, BI["pelvis"]] = wp
    W[:, BI["thigh_l"]] = leg * side * (1 - calf)
    W[:, BI["thigh_r"]] = leg * (1 - side) * (1 - calf)
    W[:, BI["calf_l"]] = leg * side * calf
    W[:, BI["calf_r"]] = leg * (1 - side) * calf
    return W / W.sum(axis=1, keepdims=True)


def _smooth_ring(v, passes=2):
    """Periodic 1-2-1 smoothing of a per-angle vector."""
    for _ in range(passes):
        v = 0.5 * v + 0.25 * (np.roll(v, 1) + np.roll(v, -1))
    return v


def make_skirt(h, name, z_top, z_hem, tile, color, flare=0.10, ease=0.02, segs=28, rows=8,
               long=False, inner_pts=None, grime=0.25, seed=0, folds=0.012, budget=None, phi_range=None,
               offset=0.0, hem_dark=0.7, pleats=None):
    """Lofted skirt from z_top down to z_hem around the hips/legs.
    A-line profile (never narrower than the hips), gathered pleats that deepen
    towards the hem, a gently wavy hem and rows packed densely near the hem.
    Fold shading is baked into the vertex colours."""
    full = phi_range is None
    if full:
        phis = np.linspace(-math.pi, math.pi, segs, endpoint=False)
    else:
        phis = np.linspace(phi_range[0], phi_range[1], segs)
    tl = np.linspace(0, 1, rows)
    zs = z_top - (z_top - z_hem) * (1 - (1 - tl) ** 1.5)
    cy = center_y(h, z_top)
    rng = np.random.default_rng(seed)
    p1, p2 = rng.random() * 6.28, rng.random() * 6.28
    k1 = pleats if pleats is not None else (8 if long else 7)
    k2 = 3
    env0 = None
    base_r = []
    for i, z in enumerate(zs):
        env = envelope(h, z, phis, (0, cy), pts=inner_pts if (inner_pts is not None and i == 0) else None,
                       ring_h=0.05 if (inner_pts is not None and i == 0) else 0.018)
        if inner_pts is not None and i == 0:
            env = np.maximum(env, envelope(h, z, phis, (0, cy)) + 0.006) - ease + 0.004
        if full:
            env = _smooth_ring(env, 3)
        if env0 is None:
            env0 = env.copy()
        base_r.append(env)
    rings = []
    shade = []
    prev = None
    for i, z in enumerate(zs):
        t = tl[i]
        env = np.maximum(base_r[i], env0 * (0.94 + 0.06 * t))
        r = env + ease + flare * t ** 1.15 + offset
        s = 0.65 * np.cos(phis * k1 + p1 + 0.8 * t) + 0.35 * np.cos(phis * k2 + p2 + 1.7 * t)
        s = np.sign(s) * np.abs(s) ** 0.85
        amp = folds * (t ** 1.25)
        r = r + amp * s
        zz = np.full(len(phis), z) - 0.012 * (t ** 2.5) * (0.5 + 0.5 * s) * (folds > 0)
        pts = np.stack([np.sin(phis) * r, cy + np.cos(phis) * r, zz], axis=1)
        rings.append(pts)
        shade.append(1 + 0.16 * s * (0.15 + 0.85 * t ** 0.8) * (folds > 0))
    rings = np.array(rings)
    # smooth the profile down the rows (removes bell kinks), keep the waist and hem rows
    if rows > 4:
        R = rings.copy()
        for _ in range(2):
            R[1:-1, :, :2] = 0.25 * R[:-2, :, :2] + 0.5 * R[1:-1, :, :2] + 0.25 * R[2:, :, :2]
        # never let the smoothing pull the skirt inside the hips
        cen = np.array([0, cy])
        for i in range(1, rows - 1):
            d0 = np.linalg.norm(rings[i, :, :2] - cen, axis=1)
            d1 = np.linalg.norm(R[i, :, :2] - cen, axis=1)
            k = np.where(d1 < d0, d0 / np.maximum(d1, 1e-6), 1.0)
            R[i, :, :2] = cen + (R[i, :, :2] - cen) * k[:, None]
        rings = R
    shade = np.array(shade).reshape(-1)
    V, F, UV = loft(rings, closed=full)
    S = len(phis)
    last = rings[-1]
    cen = np.array([0, cy, 0])
    inner = last + (cen - last) * np.array([1, 1, 0]) * 0.05 + np.array([0, 0, 0.012])
    base = len(V)
    V = np.concatenate([V, inner])
    ns = S if full else S - 1
    for j in range(ns):
        j2 = (j + 1) % S
        a, b = (rows - 1) * S + j, (rows - 1) * S + j2
        F.append((b, base + j2, base + j, a))
        UV.append([UV[-1][0], UV[-1][0], UV[-1][0], UV[-1][0]])
    uvs = pack_hem([UV])[0]
    W = skirt_weights(h, V, z_top, z_hem, long)
    g = dirt(h, V, grime, z_hem, seed, knees=False)
    col = paint(color, len(V), g, 0.03, seed)
    col[:base] *= shade[:, None]
    col[base:] *= hem_dark
    return Part(name, V, F, uvs, W, col, tile, budget)


def band(h, name, z0, z1, tile, color, pts, extra_r=0.006, segs=32, seed=0, cy=None):
    """Closed band (belt / waistband) hugging `pts` between z0 and z1."""
    phis = np.linspace(-math.pi, math.pi, segs, endpoint=False)
    cy = center_y(h, (z0 + z1) / 2) if cy is None else cy
    zm = (z0 + z1) / 2
    env = np.maximum(envelope(h, zm, phis, (0, cy), pts=pts, ring_h=0.03), envelope(h, zm, phis, (0, cy)))
    prof = [(z0, 0.0), (z0 + 0.003, extra_r * 0.75), (z0 + 0.008, extra_r), (z1 - 0.008, extra_r), (z1 - 0.003, extra_r * 0.75), (z1, 0.0)]
    rings = []
    for z, dr in prof:
        r = env + dr + 0.002
        rings.append(np.stack([np.sin(phis) * r, cy + np.cos(phis) * r, np.full(segs, z)], axis=1))
    V, F, UV = loft(np.array(rings), closed=True)
    if tile == "strap":
        uvs = fullmap_uv(UV, 0.0)
    elif tile in CLOTH_TILES:
        uvs = pack_hem([UV])[0]
    else:
        uvs = pack_islands([UV])[0]
    W = nearest_weights(h, V)
    col = paint(color, len(V), None, 0.05, seed)
    return Part(name, V, F, uvs, W, col, tile, None), env, cy


def box_part(h, name, center, size, tile, color, weights_from=None, rot=0.0):
    sx, sy, sz = np.array(size) / 2
    c = np.array(center)
    corners = np.array([[x, y, z] for z in (-sz, sz) for y in (-sy, sy) for x in (-sx, sx)])
    if rot:
        cr, sr = math.cos(rot), math.sin(rot)
        corners = corners @ np.array([[cr, sr, 0], [-sr, cr, 0], [0, 0, 1]])
    V = corners + c
    F = [tuple(reversed(f)) for f in [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]]
    uvs = [[(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)] for _ in F]
    W = nearest_weights(h, V) if weights_from is None else np.tile(weights_from, (len(V), 1))
    col = paint(color, len(V))
    return Part(name, V, F, uvs, W, col, tile, None)


def nearest_weights(h, V, k=4, restrict=None):
    kd = kdtree.KDTree(h.nb)
    for i in range(h.nb):
        if restrict is None or restrict[i]:
            kd.insert(Vector(h.P[i]), i)
    kd.balance()
    W = np.zeros((len(V), len(BONES)))
    for n, p in enumerate(V):
        res = kd.find_n(Vector(p), k)
        tot = 0
        for co, idx, dist in res:
            w = 1.0 / (dist + 1e-4)
            W[n] += h.W[idx] * w
            tot += w
        W[n] /= max(tot, 1e-9)
    return W


# ------------------------------------------------------------ outfit pieces

def belt_z(h):
    return h.z("pelvis") + 0.35 * (h.z("spine_01") - h.z("pelvis")) + 0.02


def g_tunic(h, r, pal, parts, cov, kind="tunic", key="tunic", skirt=True):
    bz = belt_z(h)
    if kind == "gambeson":
        sl, d, tile, col = sleeve_x(h, 0.97), 0.02, "quilt", pal["gambeson"]
        m = top_mask(h, bz - 0.05, sl, collar=True)
        hem = h.z("pelvis") - 0.55 * (h.z("pelvis") - h.z("calf_l"))
    else:
        sl, d, tile, col = sleeve_x(h, r.get("sleeve", 0.8)), 0.016, r.get("tunic_tile", "linen"), pal[key]
        m = top_mask(h, bz - 0.05, sl, neck_depth=0.035)
        hem = h.z("calf_l") + r.get("tunic_len", 0.16) * (h.z("thigh_l") - h.z("calf_l"))
    P = h.P[:h.nb]
    dd = np.full(h.nb, d)
    # looser over the belly and chest, tighter at the neck
    dd += 0.006 * smoothstep(h.z("neck_01") - 0.02, h.z("spine_02"), P[:, 2])[()] * 0
    sh = shell(h, m, dd, smooth=8 if kind == "gambeson" else 6, taubin=25)
    parts.append(shell_part(h, kind, sh, tile, col, 900 if kind == "gambeson" else 820,
                            body_axis_groups(h, {"arms", "torso"}), grime=0.18, seed=r["seed"]))
    cov |= covered(h, m)
    top_pts = sh["v"]
    if not skirt:
        return top_pts, bz
    flare = r.get("tunic_flare", 0.03 if kind == "gambeson" else 0.04)
    skirt = make_skirt(h, kind + "_skirt", bz + 0.01, hem, tile, col, flare=flare,
                       ease=0.018 + d, segs=r.get("tunic_hem_segs", 36), rows=10, inner_pts=top_pts,
                       seed=r["seed"] + 3,
                       folds=r.get("tunic_hem_folds", 0.006 if kind == "gambeson" else 0.01), budget=r.get("skirt_budget", 560))
    parts.append(skirt)
    # hips/thighs under the skirt stay (trousers cover them)
    return top_pts, bz


def g_belt(h, r, pal, parts, top_pts, bz, pouch=True, pouch_count=1):
    p, env, cy = band(h, "belt", bz - 0.024, bz + 0.024, "strap", pal["belt"], top_pts, extra_r=0.010, seed=r["seed"], segs=28)
    p.budget = 200
    parts.append(p)
    front_r = env[len(env) // 2]
    fy = cy - front_r - 0.014
    brass = (0.8, 0.66, 0.32)
    w_pel = one_hot("spine_01") * 0.5 + one_hot("pelvis") * 0.5
    # buckle: brass frame + tongue, and the strap tail hanging down
    for nm, c, sz in (("buckle_l", (-0.021, fy, bz), (0.007, 0.007, 0.046)), ("buckle_r", (0.021, fy, bz), (0.007, 0.007, 0.046)),
                      ("buckle_t", (0, fy, bz + 0.019), (0.05, 0.007, 0.008)), ("buckle_b", (0, fy, bz - 0.019), (0.05, 0.007, 0.008)),
                      ("buckle_p", (0, fy - 0.002, bz), (0.004, 0.006, 0.036))):
        parts.append(box_part(h, nm, c, sz, "metal", brass, weights_from=w_pel))
    parts.append(box_part(h, "belt_tail", (0.045, fy + 0.002, bz - 0.06), (0.03, 0.007, 0.125), "strap", pal["belt"], weights_from=w_pel))
    if pouch:
        angles = [115] if pouch_count <= 1 else [95, 265][:pouch_count]
        for pi, ang_deg in enumerate(angles):
            ang = math.radians(ang_deg)
            k = int((ang + math.pi) / (2 * math.pi) * len(env)) % len(env)
            rr = env[k] + 0.03
            c = (math.sin(ang) * rr, cy + math.cos(ang) * rr, bz - 0.06)
            pc = pal.get("pouch", pal["belt"])
            parts.append(rbox_part(h, f"pouch_{pi}", c, (0.09, 0.04, 0.09), "bag", pc, weights=w_pel, rot=-ang, bevel=0.008, seed=pi, bev_seg=1))
            fc = (math.sin(ang) * (rr + 0.005), cy + math.cos(ang) * (rr + 0.005), bz - 0.03)
            parts.append(rbox_part(h, f"pouch_flap_{pi}", fc, (0.094, 0.044, 0.05), "bag", tuple(np.clip(np.array(pc) * 1.08, 0, 1)),
                                   weights=w_pel, rot=-ang, bevel=0.008, seed=pi + 5, bev_seg=1))


def g_trousers(h, r, pal, parts, cov, top_z, boot_top):
    P = h.P[:h.nb]
    m = h.mask("torso", "thigh", "calf")
    m &= (P[:, 2] < top_z) & (P[:, 2] > boot_top - 0.15)   # leg rows are ~5 cm apart: overlap well
    sh = shell(h, m, 0.008, smooth=6, taubin=15)
    parts.append(shell_part(h, "trousers", sh, r.get("trouser_tile", "wool"), pal["trousers"], 650,
                            body_axis_groups(h, {"legs"}), grime=0.3, seed=r["seed"] + 5))
    cov |= covered(h, m)


def remesh_closed(V, F, voxel):
    """Fill holes and voxel-remesh (closes toe gaps etc.). Returns (V, F)."""
    me = bpy.data.meshes.new("rm")
    me.from_pydata(np.asarray(V).tolist(), [], [list(f) for f in F])
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.holes_fill(bm, edges=bm.edges[:], sides=0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("rm", me)
    bpy.context.collection.objects.link(ob)
    m = ob.modifiers.new("rm", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.adaptivity = 0.0
    apply_mods(ob)
    me = ob.data
    Vn = np.array([v.co[:] for v in me.vertices])
    Fn = [tuple(p.vertices) for p in me.polygons]
    bpy.data.objects.remove(ob)
    return Vn, Fn


def g_boots(h, r, pal, parts, cov, top):
    P = h.P[:h.nb]
    m = h.mask("foot", "calf") & (P[:, 2] < top)
    faces = [f for f in h.faces if all(m[i] for i in f)]
    ids = sorted({i for f in faces for i in f})
    loc = {g: k for k, g in enumerate(ids)}
    V, F = remesh_closed(P[ids], [tuple(loc[i] for i in f) for f in faces], 0.011)
    N = vertex_normals(V, F)
    z = V[:, 2]
    t = smoothstep(top - 0.08, top, z)
    V = V + N * (0.010 + 0.008 * t)[:, None]
    E = edges_of(F)
    for _ in range(12):
        V = laplacian(V, E, 1, 0.5)
        V = laplacian(V, E, 1, -0.53)
    V[:, 2] = np.maximum(V[:, 2], 0.0)
    W = nearest_weights(h, V, restrict=h.mask("foot", "calf"))
    groups = []
    for sd, sgn in (("l", 1), ("r", -1)):
        fl = [i for i, f in enumerate(F) if V[list(f), 0].mean() * sgn > 0]
        a_ = h.J["calf_" + sd]; b_ = h.J["foot_" + sd]
        groups.append((fl, b_, a_ - b_))
    uvs = island_uvs(V, F, groups)
    g = dirt(h, V, 0.3, None, r["seed"] + 7, knees=False)
    col = paint(pal["boots"], len(V), g, 0.05, r["seed"])
    col[V[:, 2] < 0.012] *= 0.55          # darker sole
    parts.append(Part("boots", V, F, uvs, W, col, "leather", 480))
    cov |= covered(h, m, rings=1)


def g_dress(h, r, pal, parts, cov):
    wz = h.z("spine_01") + 0.01
    sl = sleeve_x(h, r.get("sleeve", 0.95))
    m = top_mask(h, wz - 0.03, sl, neck_depth=0.05, neck_width=0.085)
    sh = shell(h, m, 0.008, smooth=6, taubin=15)
    parts.append(shell_part(h, "bodice", sh, r.get("dress_tile", "wool"), pal["dress"], 760,
                            body_axis_groups(h, {"arms", "torso"}), grime=0.15, seed=r["seed"]))
    cov |= covered(h, m)
    hem = 0.06
    sk = make_skirt(h, "dress_skirt", wz, hem, r.get("dress_tile", "wool"), pal["dress"], flare=0.16, ease=0.03,
                    segs=40, rows=12, long=True, inner_pts=sh["v"], seed=r["seed"] + 1, folds=0.026, budget=720)
    parts.append(sk)
    # legs are hidden under a long skirt: drop thighs and upper calves
    P = h.P[:h.nb]
    legs = h.mask("thigh", "calf", "torso") & (P[:, 2] < wz - 0.02) & (P[:, 2] > 0.16)
    cov |= covered(h, legs, rings=1)
    return sh["v"], wz



# ------------------------------------------------------------ surface helpers, straps, bags

class Surf:
    """Ray casting against the outermost garments built so far."""

    def __init__(self, parts, skip=("eyes", "hair", "hair_locks", "bun", "braid", "beard", "belt", "buckle")):
        Vs, Fs, off = [], [], 0
        for p in parts:
            if p.name in skip or p.name.startswith(("pouch", "satchel", "buckle", "belt")):
                continue
            Vs.append(p.v)
            Fs += [tuple(i + off for i in f) for f in p.f]
            off += len(p.v)
        self.bvh = bvhtree.BVHTree.FromPolygons([tuple(v) for v in np.concatenate(Vs)], Fs)

    def ray(self, origin, direction, dist=3.0):
        d = np.asarray(direction, float)
        d = d / np.linalg.norm(d)
        loc, n, _, _ = self.bvh.ray_cast(Vector(origin), Vector(d), dist)
        if loc is None:
            return None
        n = np.array(n)
        if np.dot(n, d) > 0:
            n = -n
        return np.array(loc), n


def ribbon_part(h, name, pts, nrm, width, thick, tile, color, weights=None, closed=False, seed=0, restrict=None):
    """Flat strap along a path lying on a surface (normals nrm)."""
    pts = np.asarray(pts, float); nrm = np.asarray(nrm, float)
    if closed:
        pts = np.vstack([pts, pts[:1]]); nrm = np.vstack([nrm, nrm[:1]])
    R = len(pts)
    rings = []
    for k in range(R):
        if closed:
            tg = pts[(k + 1) % (R - 1)] - pts[(k - 1) % (R - 1)]
        else:
            tg = pts[min(k + 1, R - 1)] - pts[max(k - 1, 0)]
        tg = tg / max(np.linalg.norm(tg), 1e-9)
        n = nrm[k] - tg * np.dot(nrm[k], tg)
        n /= max(np.linalg.norm(n), 1e-9)
        b = np.cross(n, tg); b /= max(np.linalg.norm(b), 1e-9)
        p = pts[k] + n * 0.002
        w2 = width / 2
        rings.append([p + b * w2 + n * thick * 0.6, p + b * (w2 + thick * 0.4) + n * thick * 0.25,
                      p + b * (w2 + thick * 0.4) + n * 0.0, p - b * (w2 + thick * 0.4) + n * 0.0,
                      p - b * (w2 + thick * 0.4) + n * thick * 0.25, p - b * w2 + n * thick * 0.6])
    V, F, UV = loft(np.array(rings), closed=True)
    UV = [[(v, u) for (u, v) in f] for f in UV]
    uvs = fullmap_uv(UV)
    W = nearest_weights(h, V, restrict=restrict) if weights is None else np.tile(weights, (len(V), 1))
    col = paint(color, len(V), None, 0.05, seed)
    return Part(name, V, F, uvs, W, col, tile, None)


def rbox_part(h, name, center, size, tile, color, weights=None, rot=0.0, bevel=0.006, seed=0, bag_uv=True, bev_seg=2):
    """Bevelled box with per-face planar UVs (whole tile per big face)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = (v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=bev_seg, profile=0.5)
    bm.verts.ensure_lookup_table()
    V = np.array([v.co[:] for v in bm.verts])
    F = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    sx, sy, sz = size
    UV = []
    for f in F:
        q = V[list(f)]
        nn = np.cross(q[1] - q[0], q[2] - q[0])
        ax = int(np.argmax(np.abs(nn)))
        uv = []
        for p in q:
            if ax == 1:
                uv.append((p[0] / sx + 0.5, p[2] / sz + 0.5))
            elif ax == 0:
                uv.append((p[1] / sy + 0.5, p[2] / sz + 0.5))
            else:
                uv.append((p[0] / sx + 0.5, p[1] / sy + 0.5))
        UV.append([(min(max(u, 0.02), 0.98), min(max(v, 0.02), 0.98)) for u, v in uv])
    if rot:
        cr, sr = math.cos(rot), math.sin(rot)
        V = V @ np.array([[cr, sr, 0], [-sr, cr, 0], [0, 0, 1]])
    V = V + np.array(center)
    W = nearest_weights(h, V) if weights is None else np.tile(weights, (len(V), 1))
    col = paint(color, len(V), None, 0.05, seed)
    return Part(name, V, F, UV, W, col, tile, None)


def g_satchel(h, r, pal, parts, bz, side="l"):
    """Leather satchel on the left hip with a bandolier strap over the right
    shoulder and across the chest and back (the hero's bag in the reference)."""
    sf = Surf(parts)
    sgn = 1.0 if side == "l" else -1.0
    cy = center_y(h, bz + 0.1)
    zn = h.z("neck_01")
    z_sh = zn - 0.035
    x_sh = -sgn * 0.105
    bag_top = bz - 0.07
    pts, nrm = [], []

    def add(res):
        if res is not None:
            pts.append(res[0]); nrm.append(res[1])
    # front diagonal (right shoulder -> left hip), rays from the front
    N = 8
    fr = []
    for k in range(N + 1):
        t = k / N
        x = x_sh + (sgn * 0.185 - x_sh) * t
        z = (z_sh - 0.03) + (bag_top - (z_sh - 0.03)) * t
        fr.append(sf.ray((x, cy - 1.0, z), (0, 1, 0)))
    for res in fr:
        add(res)
    # around the hip (left side), from the front to the back
    for yy in (-0.06, 0.0, 0.06):
        add(sf.ray((sgn * 1.0, cy + yy, bag_top), (-sgn, 0, 0)))
    # back diagonal, from the back
    for k in range(N + 1):
        t = 1 - k / N
        x = x_sh + (sgn * 0.185 - x_sh) * t
        z = (z_sh - 0.03) + (bag_top - (z_sh - 0.03)) * t
        add(sf.ray((x, cy + 1.0, z), (0, -1, 0)))
    # over the right shoulder, back -> front
    for yy in (0.045, 0.0, -0.045):
        add(sf.ray((x_sh, cy + yy, zn + 0.3), (0, 0, -1)))
    if len(pts) > 8:
        parts.append(ribbon_part(h, "satchel_strap", pts, nrm, 0.042, 0.011, "strap", pal.get("satchel_strap", pal["belt"]),
                                 closed=True, seed=r["seed"] + 31,
                                 restrict=h.mask("torso", "neck")))
    # bag on the hip, outside the tunic skirt
    res = sf.ray((sgn * 1.0, cy + 0.01, bag_top - 0.09), (-sgn, 0, 0))
    hx = res[0][0] if res is not None else sgn * 0.24
    w = one_hot("pelvis") * 0.7 + one_hot("spine_01") * 0.3
    bc = np.array([hx + sgn * 0.045, cy + 0.01, bag_top - 0.085])
    bagc = pal.get("satchel", pal["belt"])
    parts.append(rbox_part(h, "satchel_bag", bc, (0.07, 0.21, 0.17), "bag", bagc, weights=w, bevel=0.012, seed=r["seed"] + 32))
    parts.append(rbox_part(h, "satchel_flap", bc + np.array([sgn * 0.006, 0, 0.045]), (0.078, 0.218, 0.085), "bag",
                           tuple(np.clip(np.array(bagc) * 1.08, 0, 1)), weights=w, bevel=0.012, seed=r["seed"] + 33))
    # strap loop rising from the bag to the bandolier, and a brass stud
    parts.append(box_part(h, "satchel_stud", bc + np.array([sgn * 0.043, 0.0, 0.03]), (0.008, 0.02, 0.02), "metal",
                          (0.85, 0.68, 0.3), weights_from=w))


def g_boot_cuffs(h, r, pal, parts, top):
    bp = [p for p in parts if p.name == "boots"]
    if not bp:
        return
    B = bp[0]
    for sd, sgn in (("l", 1), ("r", -1)):
        sel = (B.v[:, 0] * sgn > 0) & (B.v[:, 2] > top - 0.045) & (B.v[:, 2] < top + 0.003)
        if sel.sum() < 6:
            continue
        Q = B.v[sel]
        cxy = Q[:, :2].mean(axis=0)
        phis = np.linspace(-math.pi, math.pi, 18, endpoint=False)
        dx = Q[:, 0] - cxy[0]; dy = Q[:, 1] - cxy[1]
        ang = np.arctan2(dx, dy); rad = np.hypot(dx, dy)
        rr = np.zeros(len(phis))
        for k, ph in enumerate(phis):
            dif = np.abs((ang - ph + math.pi) % (2 * math.pi) - math.pi)
            s = dif < 0.4
            rr[k] = rad[s].max() if s.any() else rad.mean()
        rr = _smooth_ring(rr, 2)
        prof = [(top - 0.052, 0.002), (top - 0.048, 0.011), (top - 0.004, 0.012), (top + 0.001, 0.006)]
        rings = [np.stack([cxy[0] + np.sin(phis) * (rr + dr), cxy[1] + np.cos(phis) * (rr + dr), np.full(len(phis), z)], axis=1)
                 for z, dr in prof]
        V, F, UV = loft(np.array(rings), closed=True)
        uvs = fullmap_uv(UV)
        W = nearest_weights(h, V, restrict=h.mask("foot", "calf"))
        col = paint(tuple(np.clip(np.array(pal["boots"]) * 1.12, 0, 1)), len(V), None, 0.05, r["seed"])
        parts.append(Part("boot_cuff_" + sd, V, F, uvs, W, col, "strap", None))


def g_laces(h, r, pal, parts, wz, n=4):
    """Criss-cross lacing over a chemise panel on the bodice front (reference baker)."""
    sf = Surf(parts)
    cy = center_y(h, wz + 0.1)
    z0 = wz + 0.03
    dz = 0.032
    # chemise panel
    pp, pn = [], []
    for k in range(n + 2):
        res = sf.ray((0.0, cy - 1.0, z0 + k * dz - 0.01), (0, 1, 0))
        if res is not None:
            pp.append(res[0]); pn.append(res[1])
    if len(pp) > 3:
        parts.append(ribbon_part(h, "chemise_panel", pp, pn, 0.05, 0.004, "linen", pal.get("undersleeve", (0.92, 0.88, 0.78)),
                                 seed=r["seed"] + 41, restrict=h.mask("torso")))
    lc = pal.get("lace", (0.34, 0.21, 0.11))
    for k in range(n):
        za = z0 + k * dz
        for a, b in ((-0.026, 0.026), (0.026, -0.026)):
            pp, pn = [], []
            for t in (0.0, 0.5, 1.0):
                x = a + (b - a) * t
                z = za + dz * t
                res = sf.ray((x, cy - 1.0, z), (0, 1, 0))
                if res is not None:
                    pp.append(res[0] + res[1] * 0.004); pn.append(res[1])
            if len(pp) == 3:
                parts.append(ribbon_part(h, f"lace_{k}", pp, pn, 0.0065, 0.004, "strap", lc, seed=r["seed"] + 42 + k,
                                         restrict=h.mask("torso")))

def g_apron(h, r, pal, parts, wz, dress_pts):
    ap = make_skirt(h, "apron", wz - 0.004, h.z("calf_l") - 0.12, "linen", pal["apron"], flare=0.12, ease=0.04,
                    segs=18, rows=9, long=True, seed=r["seed"] + 9, folds=0.005, budget=230, phi_range=(math.pi - 1.0, math.pi + 1.0),
                    inner_pts=dress_pts, offset=0.008,
                    grime=0.08, hem_dark=0.95)
    # phi_range around the front: remap angles > pi
    parts.append(ap)
    p, env, cy = band(h, "apron_band", wz - 0.012, wz + 0.018, "linen", pal["apron"], dress_pts, extra_r=0.005,
                      seed=r["seed"], segs=22)
    p.budget = 110
    parts.append(p)


def flatten_torso(h, sh, z_lo, z_hi, straighten=0.5, broaden=0.03, ang_w=0.4, z_w_bump=0.05, z_w_row=0.07):
    """Cylindrifies part of an offset torso shell instead of leaving it follow
    the body surface's own bust/waist curvature. Every vertex's radius (about
    the body's front-back centre) is replaced by a continuous weighted
    average of nearby vertices' radii (weighted by both angular and vertical
    distance -- a 2D blur, not a bucketed average, so it doesn't facet/zigzag
    the result): this kills a localised bust bump (two separate bumps either
    side of the sternum read as breasts even on a male body) while still
    respecting the taper at each height. It's then blended, per point, toward
    a soft (smooth) maximum of that same blurred radius among vertices at a
    similar height, by `straighten` (0 = untouched, 1 = a straight cylinder
    at each height) -- this removes the waist pinch. Finally `broaden` adds
    extra radius at the side angles (shoulders), fading out toward the
    bottom of the band, for broader shoulders. Operates in place on `sh["v"]`
    and re-pushes the result outside the body surface, so it must be called
    before the shell's Part/skirt are built from it."""
    V = sh["v"]
    z = V[:, 2]
    band = (z >= z_lo) & (z <= z_hi)
    if not band.any():
        return sh
    idx = np.where(band)[0]
    cy = center_y(h, 0.5 * (z_lo + z_hi))
    dx = V[idx, 0]
    dy = V[idx, 1] - cy
    ang = np.arctan2(dx, dy)
    rad = np.hypot(dx, dy)
    zz = z[idx]
    adiff = np.abs((ang[:, None] - ang[None, :] + math.pi) % (2 * math.pi) - math.pi)
    zdiff = np.abs(zz[:, None] - zz[None, :])
    w_bump = np.exp(-(adiff / ang_w) ** 2) * np.exp(-(zdiff / z_w_bump) ** 2)
    smoothed = (w_bump @ rad) / w_bump.sum(axis=1)
    if straighten:
        w_row = np.exp(-(zdiff / z_w_row) ** 2)
        p = 10.0
        soft_max = ((w_row @ (smoothed ** p)) / w_row.sum(axis=1)) ** (1.0 / p)
        smoothed = smoothed * (1 - straighten) + soft_max * straighten
    if broaden:
        t = np.clip((zz - z_lo) / max(z_hi - z_lo, 1e-6), 0, 1)
        side = np.abs(np.sin(ang))                  # 1 at the sides (shoulders), 0 front/back
        smoothed = smoothed + broaden * t ** 1.5 * side
    V[idx, 0] = np.sin(ang) * smoothed
    V[idx, 1] = cy + np.cos(ang) * smoothed
    V[idx] = push_out(h, V[idx], 0.004)
    sh["v"] = V
    return sh


def g_vest(h, r, pal, parts, cov, name, pal_key, hem_frac=0.16, offset=0.026, neck_depth=0.05,
           neck_width=0.09, flare=0.06, min_flare=0.09, skirt_ease=0.05, grime=0.15, seed_off=20,
           trim_key=None, tile="wool", skirt=True):
    """Sleeveless overlay garment (waistcoat / tabard / sleeveless overtunic),
    built further off the body than whatever is already on the torso so it
    sits visibly outside it. `hem_frac` is the tunic-style fraction between
    the belt (0) and the calf (1); a small value ~0.16 is knee-length, ~0.5
    is hip-length (waistcoat)."""
    bz = belt_z(h)
    color = pal[pal_key]
    P = h.P[:h.nb]
    m = h.mask("torso", "neck")
    m &= P[:, 2] > bz - 0.06
    m &= P[:, 2] < neck_cut(h, P, neck_depth, neck_width)
    # taubin=25 (matching the base tunic) is needed to flatten the pec bulge on
    # muscular male bodies -- a lightly-smoothed second shell over it reads as
    # a bust. smooth=8 for the same reason.
    sh = shell(h, m, offset, smooth=8, taubin=25)
    if r.get("flat_chest"):
        # Cylindrify the shell instead of leaving it trace the body's own
        # bust/waist curvature: kills the twin chest bumps and the hourglass
        # taper so a male torso reads flat/broad under the garment.
        flatten_torso(h, sh, bz - 0.06, h.z("neck_01") - 0.05,
                      straighten=r.get("chest_straighten", 0.55),
                      broaden=r.get("chest_broaden", 0.03))
    part = shell_part(h, name, sh, tile, color, 450, body_axis_groups(h, {"torso"}),
                      grime=grime, seed=r["seed"] + seed_off)
    if trim_key and trim_key in pal:
        tc = srgb2lin(np.array(pal[trim_key])) / srgb2lin(0.88)
        part.c[sh["rim"]] = part.c[sh["rim"]] * 0.15 + tc * 0.85
    parts.append(part)
    cov |= covered(h, m)
    top_pts = sh["v"]
    if not skirt:
        return top_pts, bz
    hem = h.z("calf_l") + hem_frac * (h.z("thigh_l") - h.z("calf_l"))
    segs, rows = 32, 9
    # A generous, fold-free ease keeps this skirt's radius safely outside
    # whatever wavy under-layer skirt (tunic/gambeson) it's covering at every
    # angle, so the under-layer never pokes through the hem.
    skirt = make_skirt(h, name + "_skirt", bz + 0.01, hem, tile, color, flare=max(flare, min_flare),
                       ease=skirt_ease * 0.6 + offset * 0.6, segs=segs, rows=rows, inner_pts=top_pts,
                       seed=r["seed"] + seed_off + 3, folds=0.0, budget=420)
    if trim_key and trim_key in pal:
        tc = srgb2lin(np.array(pal[trim_key])) / srgb2lin(0.88)
        idxs = np.arange((rows - 1) * segs, rows * segs)
        idxs = idxs[idxs < len(skirt.c)]
        skirt.c[idxs] = skirt.c[idxs] * 0.1 + tc * 0.9
    parts.append(skirt)
    return top_pts, bz


def g_undersleeve(h, r, pal, parts, cov, pal_key, cut_from, cut_to=0.97, tile="linen", grime=0.08, seed_off=40, d=0.010, name="undersleeve"):
    """Contrast chemise sleeve showing beyond a shorter over-garment sleeve
    (cut_from..cut_to are |x| fractions along the arm, elbow..wrist ~ sleeve_x)."""
    color = pal[pal_key]
    P = h.P[:h.nb]
    m = h.mask("uarm", "larm")
    ax = np.abs(P[:, 0])
    m &= (ax > cut_from) & (ax < cut_to)
    if not m.any():
        return
    sh = shell(h, m, d, smooth=5, taubin=10)
    part = shell_part(h, name, sh, tile, color, 260, body_axis_groups(h, {"arms"}),
                      grime=grime, seed=r["seed"] + seed_off)
    parts.append(part)
    cov |= covered(h, m)


def g_apron_full(h, r, pal, parts, top_pts, bz, pal_key="apron"):
    """Full bib apron (blacksmith-style): narrows at the chest, flares toward
    the knee, with a visible neck strap and a waist tie band."""
    color = pal[pal_key]
    chest_z = h.z("neck_01") - 0.02
    hem = h.z("calf_l") + 0.16 * (h.z("thigh_l") - h.z("calf_l"))
    segs, rows = 16, 9
    # Small `ease` hugs the chest (a narrow bib); `flare` only grows toward the hem.
    skirt = make_skirt(h, "apron_full", chest_z, hem, "leather", color, flare=0.13, ease=0.015,
                       segs=segs, rows=rows, inner_pts=top_pts, seed=r["seed"] + 70, folds=0.004,
                       phi_range=(math.pi - 0.9, math.pi + 0.9), offset=0.012, grime=0.18, hem_dark=0.85)
    parts.append(skirt)
    phis = np.linspace(-math.pi, math.pi, 20, endpoint=False)
    cy_chest = center_y(h, chest_z)
    front_chest = envelope(h, chest_z, phis, (0, cy_chest))[len(phis) // 2]
    top_c = np.array([0.0, cy_chest - front_chest - 0.032, chest_z])
    z_neck = h.z("neck_01") - 0.01
    cy_neck = center_y(h, z_neck)
    front_neck = envelope(h, z_neck, phis, (0, cy_neck))[len(phis) // 2]
    neck_c = np.array([0.0, cy_neck - front_neck - 0.016, z_neck])
    mid = (top_c + neck_c) / 2 + np.array([0.0, -0.006, 0.0])
    path = np.array([top_c, mid, neck_c])
    radii = np.array([0.013, 0.012, 0.011])
    parts.append(tube(h, "apron_strap", path, radii, color, r["seed"] + 71, segs=6))
    waist_z = chest_z - 0.62 * (chest_z - hem)
    wb, _, _ = band(h, "apron_tie", waist_z - 0.014, waist_z + 0.014, "leather", color, top_pts,
                   extra_r=0.006, seed=r["seed"] + 72)
    parts.append(wb)


def g_mantle(h, r, pal, parts, pal_key="mantle", drop=0.10, tile="felt", seed_off=50):
    """Short shoulder cape (healer's mantle): a shallow poncho over the chest/back."""
    color = pal[pal_key]
    top = h.z("neck_01") + 0.01
    hem = top - drop
    rows, segs = 6, 20
    cy = center_y(h, h.z("spine_03"))
    zs = np.linspace(top, hem, rows)
    rings = []
    prev = None
    for i, z in enumerate(zs):
        t = i / (rows - 1)
        phis = np.linspace(-math.pi, math.pi, segs, endpoint=False)
        env = envelope(h, z, phis, (0, cy))
        r_ = env + 0.014 + 0.024 * t
        if prev is not None:
            r_ = np.maximum(r_, prev * 0.99)
        prev = r_
        rings.append(np.stack([np.sin(phis) * r_, cy + np.cos(phis) * r_, np.full(segs, z)], axis=1))
    rings = np.array(rings)
    V, F, UV = loft(rings, closed=True)
    uvs = pack_islands([UV])[0]
    W = nearest_weights(h, V, restrict=~h.mask("uarm", "larm", "hand", "head"))
    col = paint(color, len(V), None, 0.03, r["seed"] + seed_off)
    parts.append(Part("mantle", V, F, uvs, W, col, tile, 260))


def g_beard(h, r, pal, parts, pal_key="hair", width_jaw=0.070, width_chin=0.028,
           mouth_gap=0.010, mustache_h=0.011, mustache_w=0.0, bot_pad=0.010):
    """Short beard hugging the jaw: cheek/jaw/chin cover (rising toward the ear along the jaw line,
    wrapping a little under the chin) plus a thin moustache patch above the lip; a real gap sits at
    the lip line so neither piece covers the mouth. A thin shell whose vertex colour is feathered
    toward the skin tone at its edge (soft painted edge), speckled for salt-and-pepper beards."""
    color = pal.get("beard", pal[pal_key])
    P = h.P[:h.nb]
    c = h.head_c
    mouth_z = h.mouth[2]
    top = mouth_z - mouth_gap
    bot = h.chin_z - bot_pad
    front = P[:, 1] < c[1] + 0.015              # front of the face, wrapping slightly under the jaw
    base = h.mask("head") & front & ~h.ear
    ax = np.abs(P[:, 0] - c[0])
    t = np.clip((P[:, 2] - bot) / max(top - bot, 1e-6), 0, 1)
    width = width_chin + (width_jaw - width_chin) * t ** 0.8
    top_x = top + 0.030 * smoothstep(0.038, 0.078, ax)            # the cover climbs the jaw toward the ear
    jaw = base & (P[:, 2] < top_x) & (P[:, 2] > bot) & (ax < width)
    must_top = mouth_z + 0.010 + mustache_h
    must_bot = mouth_z + 0.010
    mustache = base & (P[:, 2] < must_top) & (P[:, 2] > must_bot) & (ax < mustache_w)
    m0 = jaw | mustache
    if not m0.any():
        return
    # signed distance (m) to the analytic beard outline, positive inside: drives the painted soft edge
    mj = np.minimum(np.minimum(width - ax, top_x - P[:, 2]), P[:, 2] - bot)
    mm = np.minimum(np.minimum(mustache_w - ax, must_top - P[:, 2]), P[:, 2] - must_bot)
    margin = np.where(base, np.maximum(mj, mm), -1.0)
    # shell = outline + one ring of vertices beyond it (painted as plain skin), so the visible beard
    # edge is a colour fade instead of the coarse head-mesh boundary
    Ed = edges_of(h.faces)
    ring = np.zeros(h.nb, bool)
    ring[Ed[:, 0]] |= m0[Ed[:, 1]]
    ring[Ed[:, 1]] |= m0[Ed[:, 0]]
    lipband = (np.abs(P[:, 2] - mouth_z) < 0.016) & (ax < 0.048)          # never over the lips
    m = m0 | (ring & base & ~lipband & (P[:, 2] > bot - 0.03) & (P[:, 2] < np.minimum(top_x + 0.035, must_top + 0.01 + 0.1 * (ax > 0.04))))
    sh = shell(h, m, 0.0038, smooth=8, taubin=10, dmin=0.0025, seed=r["seed"] + 80)
    # one level of subdivision: the head mesh is coarse (~1.5 cm), the beard paint needs finer vertices
    bm = bmesh.new()
    bv = [bm.verts.new(tuple(v)) for v in sh["v"]]
    for f in sh["f"]:
        try:
            bm.faces.new([bv[i] for i in f])
        except ValueError:
            pass
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    bm.verts.ensure_lookup_table()
    V = np.array([tuple(v.co) for v in bm.verts])
    Fb = [tuple(v.index for v in f.verts) for f in bm.faces]
    bm.free()
    V = push_out(h, V, 0.0022)
    # skin texels: UV from the nearest head vertices (inverse-distance blend)
    hid = np.nonzero(h.mask("head"))[0]
    kdh = kdtree.KDTree(len(hid))
    for k, i in enumerate(hid):
        kdh.insert(Vector(h.P[i]), k)
    kdh.balance()
    vuv_v = np.zeros((len(V), 2))
    for i, v in enumerate(V):
        nn = kdh.find_n(Vector(v), 3)
        wgt = np.array([1.0 / (d + 1e-4) for (_, _, d) in nn])
        vuv_v[i] = sum(w_ * h.vuv[hid[k]] for w_, (_, k, _) in zip(wgt, nn)) / wgt.sum()
    ax_v = np.abs(V[:, 0] - c[0])
    t_v = np.clip((V[:, 2] - bot) / max(top - bot, 1e-6), 0, 1)
    wd_v = width_chin + (width_jaw - width_chin) * t_v ** 0.8
    tx_v = top + 0.030 * smoothstep(0.038, 0.078, ax_v)
    mj_v = np.minimum(np.minimum(wd_v - ax_v, tx_v - V[:, 2]), V[:, 2] - bot)
    mm_v = np.minimum(np.minimum(mustache_w - ax_v, must_top - V[:, 2]), V[:, 2] - must_bot)
    margin_v = np.maximum(mj_v, mm_v)
    p = Part("beard", V, Fb, [[tuple(vuv_v[i]) for i in f] for f in Fb], np.tile(one_hot("Head"), (len(V), 1)),
             np.ones((len(V), 3)), "skin", r.get("beard_budget", 640))
    f = smoothstep(0.0, r.get("beard_feather", 0.0025), margin_v)
    sc = srgb2lin(skin_color(r)) / srgb2lin(0.93)
    skin_c = np.tile(sc / max(1.0, sc.max()), (len(V), 1))            # identical to the body's vertex colour
    base_c = paint(color, len(V), None, 0.10, r["seed"] + 81)
    sp = r.get("beard_speckle", 0.0)
    nzv = np.array([0.5 + 0.5 * noise.noise(Vector(v * 95.0 + 3.1)) for v in V])
    if sp:                                  # salt and pepper: dark and light flecks
        nz2 = np.array([0.5 + 0.5 * noise.noise(Vector(v * 210.0 + 7.7)) for v in V])
        mixv = smoothstep(0.38, 0.62, 0.6 * nz2 + 0.4 * nzv)
        base_c = base_c * (0.55 + 1.35 * sp / 0.42 * mixv * 0.55)[:, None]
    else:                                                               # faint stubble mottling
        base_c = base_c * (0.8 + 0.4 * nzv)[:, None]
    w = (f * r.get("beard_density", 0.95))[:, None]
    p.c = np.clip(skin_c * (1 - w) + base_c * w, 0, 1.0)
    parts.append(p)


def g_breastplate(h, r, pal, parts, pal_key="armor"):
    """Steel chest plate: sits outside the gambeson but under the tabard,
    covering the same collar/shoulder line as the gambeson's own collar so a
    ring of steel shows above/around the tabard's neckline."""
    color = pal[pal_key]
    P = h.P[:h.nb]
    m = h.mask("torso", "neck")
    m &= P[:, 2] < h.z("neck_01") + 0.035
    m &= P[:, 2] > belt_z(h) + 0.05
    sh = shell(h, m, 0.020, smooth=6, taubin=22)
    parts.append(shell_part(h, "breastplate", sh, "metal", color, 460, body_axis_groups(h, {"torso"}),
                            grime=0.04, seed=r["seed"] + 65))


def g_pauldrons(h, r, pal, parts, pal_key="armor"):
    color = pal[pal_key]
    for sd, sgn in (("l", 1), ("r", -1)):
        c = h.J["upperarm_" + sd] + np.array([0.02 * sgn, 0, 0.025])
        w = one_hot("upperarm_" + sd)
        parts.append(ellipsoid(h, "pauldron_" + sd, c, (0.066, 0.07, 0.05), color, w))
        parts[-1].tile = "metal"


def g_bracers(h, r, pal, parts, pal_key="armor"):
    color = pal[pal_key]
    for sd in "lr":
        c = (h.J["lowerarm_" + sd] + h.J["hand_" + sd]) / 2
        w = one_hot("lowerarm_" + sd)
        parts.append(box_part(h, "bracer_" + sd, c, (0.05, 0.075, 0.05), "metal", color, weights_from=w))


def g_gorget(h, r, pal, parts, pal_key="armor"):
    color = pal[pal_key]
    z0 = h.z("neck_01") - 0.045
    z1 = h.z("neck_01") - 0.015
    pts = h.P[:h.nb][h.mask("neck")]
    p, env, cy = band(h, "gorget", z0, z1, "metal", color, pts, extra_r=0.006, seed=r["seed"] + 60)
    parts.append(p)


def build_emblem_object(h, name, center, right_dir, up_dir, size, weights_bone="spine_03", preview_image=None):
    """A small flat double-sided quad (a tabard/coat emblem decal), rigid to
    one bone. Built directly as a bpy object (not through Part/part_object,
    which remaps UVs into the shared atlas -- this one keeps full 0..1 UVs
    for its own separate emblem texture)."""
    right = right_dir / np.linalg.norm(right_dir)
    up = up_dir / np.linalg.norm(up_dir)
    hw, hh = size[0] / 2, size[1] / 2
    V = np.array([center - right * hw - up * hh, center + right * hw - up * hh,
                  center + right * hw + up * hh, center - right * hw + up * hh])
    F = [(0, 1, 2, 3)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], F)
    me.validate(clean_customdata=False)
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", np.array([(0, 0), (1, 0), (1, 1), (0, 1)], np.float32).ravel())
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    ca.data.foreach_set("color", np.tile([1.0, 1.0, 1.0, 1.0], (4, 1)).astype(np.float32).ravel())
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    vg = ob.vertex_groups.new(name=weights_bone)
    vg.add([0, 1, 2, 3], 1.0, "REPLACE")
    for poly in me.polygons:
        poly.use_smooth = False
    if preview_image and os.path.exists(preview_image):
        m = bpy.data.materials.new(name + "Preview")
        m.use_nodes = True
        try:
            m.blend_method = "CLIP"
        except Exception:
            pass
        nt = m.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = bpy.data.images.load(preview_image, check_existing=True)
        nt.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
        nt.links.new(tx.outputs["Alpha"], bsdf.inputs["Alpha"])
        me.materials.append(m)
    return ob


def build_emblem(h, r, size=(0.09, 0.10), z_above_belt=0.20, stand_off=0.034):
    """Chest emblem quad (e.g. the guard's tower-crown tabard decal), placed
    on the body's front midline just outside the vest/tabard shell."""
    bz = belt_z(h)
    z_ch = bz + z_above_belt
    phis = np.linspace(-math.pi, math.pi, 24, endpoint=False)
    cy = center_y(h, z_ch)
    env = envelope(h, z_ch, phis, (0, cy))
    front_r = env[len(env) // 2]
    y = cy - front_r - stand_off
    center = np.array([0.0, y, z_ch])
    right = np.array([1.0, 0.0, 0.0])
    up = np.array([0.0, 0.0, 1.0])
    img_path = os.path.join(EMBLEM_DIR, r["emblem"] + ".png")
    return build_emblem_object(h, "emblem", center, right, up, size, weights_bone="spine_03",
                               preview_image=img_path)


def g_cloak(h, r, pal, parts, hood="down", pal_key="cloak", collar_roll=True, waist_hug=False):
    """Back-draped cloak with a collar; lined inside (second layer). Drapes
    over everything already built (skirts, belts, pouches)."""
    pts = []
    for p in parts:
        if p.name in ("eyes", "hair", "hair_locks", "bun", "braid"):
            continue
        pts.append(p.v)
        for f in p.f:            # densify: points along each face (skirt rows are ~9 cm apart)
            q = p.v[list(f)]
            c = q.mean(axis=0)
            pts.append(np.vstack([c, (q + c) / 2, (q + np.roll(q, 1, axis=0)) / 2]))
    obst = np.concatenate(pts) if pts else np.zeros((0, 3))
    sleeve = (obst[:, 2] > h.z("upperarm_l") - 0.13) & (np.abs(obst[:, 0]) > abs(h.J["upperarm_l"][0]) - 0.02)
    obst = obst[~sleeve]                                                        # not the (T-posed) sleeves
    top = h.z("neck_01") + 0.005
    # A fitted coat (waist_hug) is knee-length, like the tunic underneath it
    # (same hem convention: a small fraction above the calf/knee joint), not
    # the longer ankle-length drape of a cloak.
    hem = (h.z("calf_l") + 0.16 * (h.z("thigh_l") - h.z("calf_l")) if waist_hug
           else h.z("calf_l") - 0.16 * (h.z("calf_l") - h.z("foot_l")) - 0.12)
    rows, segs = (16, 22) if waist_hug else (11, 22)
    cy = center_y(h, h.z("spine_03"))
    trim_band = pal.get("cloak_trim") is not None and not waist_hug
    if trim_band:
        # dedicated hem row: the trim is its own thin strip (two rings a few mm apart flip the
        # vertex colour), so the band edge is crisp instead of fading across the last long row
        bh = 0.075
        zs = np.concatenate([np.linspace(top, hem + bh, rows - 1), [hem + bh - 0.004, hem]])
        rows = len(zs)
    else:
        zs = np.linspace(top, hem, rows)
    t_waist = np.clip((top - belt_z(h)) / max(top - hem, 1e-6), 0, 1) if waist_hug else 0.0
    rings = []
    prev = None
    zs_, phis_, row_r, row_min = [], [], [], []
    for i, z in enumerate(zs):
        t = i / (rows - 1)
        phmax = math.radians(160 - 55 * min(1, t * 2.2))
        phis = np.linspace(-phmax, phmax, segs)
        env = envelope(h, z, phis, (0, cy))
        if len(obst):
            # Keep the coat safely outside whatever it's covering (waistcoat,
            # tunic skirt): a wider sampling ring and a positive margin so the
            # under-layer never pokes through at a sampled row (a negative
            # margin here let the waistcoat show through as dimples/dark spots).
            margin = 0.015 if waist_hug else -0.01
            ring_h = 0.05 if waist_hug else 0.035
            env = np.maximum(env, envelope(h, z, phis, (0, cy), pts=obst, ring_h=ring_h) + margin)
        if waist_hug:
            # A fitted, straight knee-length coat with only a slight A-line
            # flare toward the hem -- not a bell/sack widening from the waist.
            below = max(0.0, (t - t_waist) / max(1 - t_waist, 1e-6))
            r_ = env + 0.022 + 0.012 * below
        else:
            r_ = env + 0.03 + r.get("cloak_flare", 0.05) * t
        if prev is not None and not waist_hug:
            # A draped cloak only ever gets wider going down; a fitted coat
            # must be free to narrow again below a waistcoat/hem bulge it had
            # to clear higher up, or that bulge propagates into a bell shape
            # all the way to the coat's own hem.
            r_ = np.maximum(r_, prev * 0.985)
        r_ += 0.01 * t * np.sin(phis * 7 + 1.3)
        prev = r_
        row_r.append(r_.copy())
        row_min.append((env + (0.008 if waist_hug else 0.0)).copy())
        zs_.append(z)
        phis_.append(phis)
    if waist_hug:
        # A clean straight panel from the shoulder blades to the knee (reference: market_merchant back
        # view): between the blade row and the hem every direction runs on ONE straight line
        # r(z) = r_top + (r_bot - r_top) * s.  r_bot is the smallest value that still clears the
        # waist / belt / hips at every row, so there is no waist step and no hip balloon; the
        # line's slope is the (slight) A-line flare.
        i_s = int(round(0.2 * (rows - 1)))          # shoulder-blade row
        raw = np.array(row_r)
        rt = raw[i_s].copy()
        rb = rt * 1.03
        for i in range(i_s + 1, rows):
            s_ = (i - i_s) / (rows - 1 - i_s)
            if s_ >= 0.33:      # rows just under the blade line only need local clearance (below)
                rb = np.maximum(rb, (row_min[i] + 0.012 - rt * (1 - s_)) / s_)
        rb0 = rb.copy()
        for _ in range(3):                                      # smooth around the body, never below the need
            rb = np.maximum(rb0, np.convolve(np.pad(rb, 3, mode="edge"), np.ones(7) / 7, mode="valid"))
        rt_s = np.convolve(np.pad(rt, 2, mode="edge"), np.ones(5) / 5, mode="valid")
        rt = np.maximum(rt_s, rt * 0.97)
        for i in range(i_s + 1, rows):
            s_ = (i - i_s) / (rows - 1 - i_s)
            row_r[i] = np.maximum(row_min[i] + 0.004, rt * (1 - s_) + rb * s_)
    for i in range(rows):
        rings.append(np.stack([np.sin(phis_[i]) * row_r[i], cy + np.cos(phis_[i]) * row_r[i], np.full(segs, zs_[i])], axis=1))
    rings = np.array(rings)
    V, F, UV = loft(rings, closed=False)
    n = len(V)
    # lining: second layer slightly inside, reversed winding
    cen = np.array([0, cy, 0])
    Vin = V + (cen - V) * np.array([1, 1, 0]) * 0.03
    Fin = [tuple(n + i for i in reversed(f)) for f in F]
    UVin = [list(reversed(u)) for u in UV]
    V2 = np.concatenate([V, Vin])
    F2 = F + Fin
    UV2 = UV + UVin
    uvs = pack_hem([UV2])[0]
    # weights: top follows the shoulders; lower rows spine/pelvis, a little thigh at the bottom
    Wn = nearest_weights(h, V2, restrict=~h.mask("uarm", "larm", "hand", "head"))
    t = np.clip((top - V2[:, 2]) / (top - hem), 0, 1)
    Wd = np.zeros_like(Wn)
    Wd[:, BI["spine_02"]] = 0.45
    Wd[:, BI["spine_01"]] = 0.25
    Wd[:, BI["pelvis"]] = 0.3
    side = smoothstep(-0.1, 0.1, V2[:, 0])
    legw = 0.25 * smoothstep(0.5, 1.0, t)
    Wd[:, BI["thigh_l"]] = legw * side
    Wd[:, BI["thigh_r"]] = legw * (1 - side)
    a = smoothstep(0.08, 0.35, t)[:, None]
    W = Wn * (1 - a) + Wd * a
    W /= W.sum(axis=1, keepdims=True)
    g = dirt(h, V2, 0.3, hem, r["seed"] + 11, knees=False)
    col = paint(pal[pal_key], len(V2), g, 0.03, r["seed"])
    col[n:] *= 0.62
    if pal.get("cloak_trim") is not None and not waist_hug:
        # contrasting painted edge band along the hem and both front edges (matches the guard tabard trim)
        tc = paint(pal["cloak_trim"], 1, None, 0.0, 0)[0]
        idx = np.arange(n)
        ri, ji = idx // segs, idx % segs
        band_ = (ri >= rows - 2) | (ji <= 0) | (ji >= segs - 1)
        col[:n][band_] = tc
        # inside face of the edge band too
        col[n:][band_] = tc * 0.62
    parts.append(Part(pal_key, V2, F2, uvs, W, col, "felt", r.get("cloak_budget", 900) if waist_hug else None))
    if hood == "down" and collar_roll:
        # bunched hood lying on the shoulders/back (a thick collar roll)
        phis = np.linspace(-math.pi, math.pi, 20, endpoint=False)
        z0 = h.z("neck_01") + 0.02
        rings = []
        cyc = center_y(h, h.z("neck_01"), 0.02)
        for k, (dz, dr, back) in enumerate([(0.0, 0.012, 0.0), (-0.03, 0.045, 0.02), (-0.075, 0.06, 0.05), (-0.11, 0.035, 0.06)]):
            z = z0 + dz
            env = envelope(h, z, phis, (0, cyc), exclude_arms=True)
            bk = np.clip(np.cos(phis), 0, 1)
            rr = env + dr * (0.55 + 0.45 * bk) + back * bk
            zz = z - 0.02 * bk * (k > 0)
            rings.append(np.stack([np.sin(phis) * rr, cyc + np.cos(phis) * rr, np.full(20, 0.0) + zz], axis=1))
        V, F, UV = loft(np.array(rings), closed=True)
        uvs = pack_islands([UV])[0]
        W = nearest_weights(h, V, restrict=~h.mask("uarm", "larm", "hand", "head"))
        col = paint(pal[pal_key], len(V), None, 0.03, r["seed"]) * 0.95
        parts.append(Part("hood_down", V, F, uvs, W, col, "felt", None))
    # clasp at the throat
    zc = h.z("neck_01") - 0.03
    ncy = center_y(h, zc, 0.02)
    parts.append(box_part(h, "clasp", (0, ncy - envelope(h, zc, np.array([math.pi]), (0, ncy))[0] - 0.03, zc),
                          (0.03, 0.01, 0.03), "metal", (0.7, 0.62, 0.45)))


def head_region(h, hairline_front, hairline_side, hairline_back, sideburn=0.0, exclude_ears=True):
    """Scalp mask from a hairline z(phi) (phi 0 = face, pi = back)."""
    P = h.P[:h.nb]
    m = h.mask("head", "neck")
    c = h.head_c
    phi = np.arctan2(P[:, 0] - c[0], -(P[:, 1] - c[1]))       # 0 at the face
    F, S, B = hairline_front, hairline_side, hairline_back
    a1 = (F - B) / 2
    a0 = ((F + B) / 2 + S) / 2
    a2 = ((F + B) / 2 - S) / 2
    zl = a0 + a1 * np.cos(phi) + a2 * np.cos(2 * phi)
    ez0 = (h.eye_l[2] + h.eye_r[2]) / 2
    hv = P[h.mask("head")]
    band = hv[(hv[:, 2] > ez0 - 0.06) & (hv[:, 2] < ez0 + 0.04)]
    xm = np.abs(band[:, 0]).max()
    eq = band[np.abs(band[:, 0]) > xm - 0.012]                         # outermost head verts = the ear
    pm = float(np.median(np.abs(np.arctan2(eq[:, 0] - c[0], -(eq[:, 1] - c[1])))))       # ear azimuth (~2.25 rad)
    h.ear_phi = pm
    if sideburn:
        # thin sideburn strip just in front of the ear
        zl -= sideburn * np.exp(-((np.abs(phi) - (pm - 0.42)) / 0.15) ** 2)
    if exclude_ears:
        # hair follows the head: the edge runs over the top of the ear and then sweeps down behind it
        # to the nape, so the ear itself stays clear (no cup around it)
        ap = np.abs(phi)
        win = smoothstep(pm - 0.24, pm - 0.10, ap) * (1 - smoothstep(pm + 0.22, pm + 0.48, ap))
        zl = np.maximum(zl, zl + win * np.maximum(ez0 + 0.014 - zl, 0.0))
    m &= P[:, 2] > zl
    # never on the face / jaw / throat (under-chin verts sit near the axis where phi is unstable)
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    m &= ~((P[:, 1] < c[1] + 0.01) & (P[:, 2] < ez - 0.005) & (np.abs(P[:, 0]) < 0.055))
    m &= ~((P[:, 1] < c[1] - 0.025) & (P[:, 2] < ez + 0.02))
    m &= ~((P[:, 1] < c[1] + 0.035) & (P[:, 2] < h.chin_z + 0.04))          # under the chin / throat
    if exclude_ears:
        m &= ~h.ear
    return m, phi


def hair_uv_groups(h):
    def fn(P, F, sh):
        return [(list(range(len(F))), np.array([0.0, h.head_c[1], h.head_c[2] - 0.02]), None)]
    return fn


def hair_lock_geom(h, spec, capd, seed):
    """One tapered hair clump (flat lens cross-section) lying on the scalp:
    path = strand direction radiating from the crown (fixed azimuth phi, polar
    angle th0 -> th1), snapped to the skin by ray casting and lifted by the cap
    thickness. The tip narrows to a point and flicks off the scalp (`lift`).
    Returns (V, F, UV, t) with hair-tile UVs (strand grooves run along the lock)
    and t = 0 (root) .. 1 (tip) per vertex, used for the painted root-to-tip gradient."""
    phi, th0, th1, width, thick, lift = spec[:6]
    twist = spec[6] if len(spec) > 6 else 0.0
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    c = Vector((0.0, h.head_c[1], ez + 0.03))
    steps = 4
    pts, nrm = [], []
    for k in range(steps + 1):
        t = k / steps
        th = math.radians(th0 + (th1 - th0) * t)
        ph = math.radians(phi + twist * t)
        d = Vector((math.sin(th) * math.sin(ph), -math.sin(th) * math.cos(ph), math.cos(th)))
        loc, n, _, _ = h.bvh.ray_cast(c + d * 0.5, -d)
        if loc is None or (loc - c).length > 0.17:       # missed the skull (hit a shoulder / arm)
            loc, n = c + d * 0.09, d
        off = (spec[7] if len(spec) > 7 else capd(loc[2]) + 0.004) + lift * t ** 2
        pts.append(np.array(loc) + np.array(n) * off)
        nrm.append(np.array(n))
    pts = np.array(pts); nrm = np.array(nrm)
    rings = []
    A = 4
    for k in range(steps + 1):
        t = k / steps
        tg = pts[min(k + 1, steps)] - pts[max(k - 1, 0)]
        tg /= max(np.linalg.norm(tg), 1e-9)
        n = nrm[k] - tg * np.dot(nrm[k], tg); n /= max(np.linalg.norm(n), 1e-9)
        b = np.cross(n, tg); b /= max(np.linalg.norm(b), 1e-9)
        wk = width * (0.62 + 0.38 * math.sin(min(1, t * 2.0) * math.pi / 2)) * (1 - 0.9 * t ** 2.3)
        tk = thick * (1 - 0.55 * t ** 2)
        ring = [pts[k] + b * wk * math.cos(2 * math.pi * a / A) + n * tk * (0.6 + 0.4 * math.sin(2 * math.pi * a / A)) * (1 if math.sin(2 * math.pi * a / A) > 0 else 0.5)
                for a in range(A)]
        rings.append(ring)
    V, F, UV = loft(np.array(rings), closed=True)
    rng = np.random.default_rng(seed)
    u0 = rng.uniform(0.05, 0.8)
    UV = fullmap_uv(UV)
    UV = [[(u0 + 0.12 * u, 0.1 + 0.6 * (1 - v)) for (u, v) in f] for f in UV]
    tv = np.repeat(np.linspace(0, 1, steps + 1), A)
    return V, F, UV, tv


def hair_locks(h, specs, capd, color, seed, name="hair_locks"):
    if not specs:
        return None
    Vs, Fs, UVs, Ts, off = [], [], [], [], 0
    for i, s in enumerate(specs):
        V, F, UV, tv = hair_lock_geom(h, s, capd, seed + i * 7)
        Vs.append(V); Fs += [tuple(x + off for x in f) for f in F]; UVs += UV
        Ts.append(tv)
        off += len(V)
    V = np.concatenate(Vs)
    tv = np.concatenate(Ts)
    W = np.tile(one_hot("Head"), (len(V), 1))
    col = paint(color, len(V), None, 0.16, seed)
    # painted root-to-tip gradient: darker roots, bright glossy tips (reads as strand highlights)
    gain = 0.72 + 1.0 * tv ** 1.4
    col = np.clip(col * gain[:, None] * np.array([1.0, 1.02, 1.05])[None, :], 0, 1.0)
    return Part(name, V, Fs, UVs, W, col, "hair", None)


def braid_part(h, name, path, r0, r1, color, seed, segs=6, spacing=0.026, bands=True, wt=None):
    """Plaited braid along `path`: rings every `spacing` m, cross-section lumps that rotate
    from ring to ring (diagonal plait ridges) and alternating light/dark bands."""
    path = np.array(path, float)
    seglen = np.linalg.norm(np.diff(path, axis=0), axis=1)
    cum = np.concatenate([[0], np.cumsum(seglen)])
    n = max(4, int(cum[-1] / spacing) + 1)
    ss = np.linspace(0, cum[-1], n)
    pp = np.stack([np.interp(ss, cum, path[:, i]) for i in range(3)], axis=1)
    rings, tvals = [], []
    for k in range(n):
        t = k / (n - 1)
        tg = pp[min(k + 1, n - 1)] - pp[max(k - 1, 0)]
        tg /= max(np.linalg.norm(tg), 1e-9)
        a = np.cross(tg, [1, 0, 0])
        if np.linalg.norm(a) < 1e-3:
            a = np.cross(tg, [0, 1, 0])
        a /= np.linalg.norm(a)
        b = np.cross(tg, a)
        rad = r0 + (r1 - r0) * t
        ring = []
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            lump = 1 + 0.30 * math.cos(ph * 2 - k * 1.25)
            ring.append(pp[k] + (a * math.cos(ph) + b * math.sin(ph)) * rad * lump)
        rings.append(ring)
        tvals.append(t)
    V, F, UV = loft(np.array(rings), closed=True)
    tip = len(V)
    V = np.concatenate([V, pp[-1:] + (pp[-1] - pp[-2]) * 0.5])
    S = segs
    tipF = [((n - 1) * S + j, tip, (n - 1) * S + (j + 1) % S) for j in range(S)]
    a_, b_, c_ = V[tipF[0][0]], V[tipF[0][1]], V[tipF[0][2]]
    if np.dot(np.cross(b_ - a_, c_ - a_), V[tip] - pp[-1]) < 0:
        tipF = [tuple(reversed(f)) for f in tipF]
    for f in tipF:
        F.append(f)
        UV.append([UV[-1][0]] * 3)
    uvs = pack_islands([UV])[0]
    if wt is None:
        W = nearest_weights(h, V, restrict=h.mask("neck", "head", "torso"))
    else:
        W = np.tile(wt, (len(V), 1))
    col = paint(color, len(V), None, 0.06, seed)
    if bands:
        kk = np.concatenate([np.repeat(np.arange(n), S), [n - 1]])
        gain = 0.82 + 0.30 * (0.5 + 0.5 * np.sin(kk * 2.5)) + 0.10 * np.concatenate([np.repeat(np.linspace(0, 1, n), S), [1]])
        col = np.clip(col * gain[:, None], 0, 1.0)
    return Part(name, V, F, uvs, W, col, "hair", None)


def skull_path(h, phis, th, off=0.014, ez_off=0.03):
    """Points on the scalp (ray cast) at polar angle th (deg from crown) for each azimuth phi (deg)."""
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    c = Vector((0.0, h.head_c[1], ez + ez_off))
    out = []
    for ph_, th_ in zip(phis, th if hasattr(th, "__len__") else [th] * len(phis)):
        p, t_ = math.radians(ph_), math.radians(th_)
        d = Vector((math.sin(t_) * math.sin(p), -math.sin(t_) * math.cos(p), math.cos(t_)))
        loc, n, _, _ = h.bvh.ray_cast(c + d * 0.5, -d)
        if loc is None or (loc - c).length > 0.17:
            loc, n = c + d * 0.09, d
        out.append(np.array(loc) + np.array(n) * off)
    return out


def g_helmet(h, r, pal, parts, pal_key="armor"):
    """Steel kettle hat: a dome over the crown with a short flared brim, above the brows."""
    P = h.P[:h.nb]
    hv = P[h.mask("head")]
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    cz = ez + 0.03
    yc = (h.head_back + h.head_front) / 2
    up = hv[hv[:, 2] > cz]
    rx = np.abs(up[:, 0]).max() + 0.016
    ry = (h.head_back - h.head_front) / 2 + 0.016
    rz = h.head_top - cz + 0.016
    segs = 20
    phis = np.linspace(0, 2 * math.pi, segs, endpoint=False)
    rings = []
    for th in (0.0, 14, 28, 42, 56, 68, 78):
        t = math.radians(th)
        rk = math.sin(t)
        rings.append(np.stack([np.sin(phis) * rx * rk, yc - np.cos(phis) * ry * rk, np.full(segs, cz + rz * math.cos(t))], axis=1))
    z_r = cz + rz * math.cos(math.radians(78))
    front_up = 0.006 * np.cos(phis)                                  # brim a touch higher over the forehead
    for dz, k in ((-0.004, 1.06), (-0.012, 1.2), (-0.020, 1.24), (-0.024, 1.17), (-0.014, 1.04)):
        rk = math.sin(math.radians(78)) * k
        rings.append(np.stack([np.sin(phis) * rx * rk, yc - np.cos(phis) * ry * rk, z_r + dz + front_up * 0], axis=1))
    rings[0] = rings[0] + 0.0
    V, F, UV = loft(np.array(rings), closed=True)
    uvs = pack_islands([UV])[0]
    W = np.tile(one_hot("Head"), (len(V), 1))
    col = paint(pal[pal_key], len(V), None, 0.03, r["seed"] + 3)
    parts.append(Part("helmet", V, F, uvs, W, col, "metal", 260))
    # small red-painted crest band across the brow rim is left to the tabard colours; nothing else needed


def g_hair(h, r, pal, parts, cov, style):
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    top = h.head_top
    col = pal["hair"]
    nz = h.z("neck_01")
    seed = r["seed"]
    if style == "helm":
        g_helmet(h, r, pal, parts, pal_key=r.get("armor_key", "armor"))
        capd = lambda z: 0.011 + 0.014 * float(smoothstep(ez, top, z))
        rng = np.random.default_rng(seed + 5)
        sp = []
        for p in (162, 174, 186, 198):
            sp.append((p + rng.uniform(-3, 3), 80, 110, 0.024, 0.007, 0.002, rng.uniform(-4, 4)))
        lk = hair_locks(h, sp, capd, col, seed + 11)
        if lk is not None:
            parts.append(lk)
        return
    if style == "short":
        m, phi = head_region(h, ez + 0.062, ez + 0.02, nz + 0.035, sideburn=0.03)
        P = h.P[:h.nb]
        crown = smoothstep(ez, top, P[:, 2])
        back = np.clip(-np.cos(phi), 0, 1)
        d = 0.009 + 0.026 * crown ** 1.3 + 0.008 * back * crown
        sh = shell(h, m, d, smooth=4, noise_amp=0.011, seed=seed)
        budget = 300
    elif style == "fringe":            # elderly horseshoe
        m, phi = head_region(h, ez + 0.075, ez + 0.02, nz + 0.03, sideburn=0.022)
        P = h.P[:h.nb]
        bald = (P[:, 2] > top - 0.055) & (np.cos(phi) > -0.55)
        m &= ~bald
        sh = shell(h, m, 0.005, smooth=4, noise_amp=0.003, seed=seed)
        budget = 220
    elif style == "child":
        m, phi = head_region(h, ez + 0.045, ez + 0.012, nz + 0.02, sideburn=0.025)
        P = h.P[:h.nb]
        crown = smoothstep(ez, top, P[:, 2])
        front = np.clip(np.cos(phi), 0, 1)
        d = 0.011 + 0.016 * crown + 0.008 * front * smoothstep(ez + 0.03, ez + 0.06, P[:, 2])
        sh = shell(h, m, d, smooth=4, noise_amp=0.008, seed=seed)
        budget = 300
    elif style in ("long", "bob"):
        m, phi = head_region(h, ez + 0.06, ez + 0.0, nz - 0.01 if style == "long" else nz + 0.0, sideburn=0.0,
                             exclude_ears=False)
        P = h.P[:h.nb]
        # hair covers the upper ear when tied back / bob falls over it
        below = smoothstep(ez + 0.01, ez - 0.07, P[:, 2])
        d = 0.011 + (0.026 if style == "bob" else 0.005) * below + 0.014 * smoothstep(ez, top, P[:, 2])
        sh = shell(h, m, d, smooth=5, noise_amp=0.003, seed=seed)
        budget = 320
    elif style == "bun":               # curly hair pulled back into a bun, no braid
        m, phi = head_region(h, ez + 0.06, ez + 0.01, nz + 0.02, sideburn=0.025)
        P = h.P[:h.nb]
        crown = smoothstep(ez, top, P[:, 2])
        d = 0.011 + 0.022 * crown
        sh = shell(h, m, d, smooth=4, noise_amp=0.014, seed=seed)
        budget = 300
    parts.append(shell_part(h, "hair", sh, "hair", tuple(np.array(col) * 0.78), budget, hair_uv_groups(h), grime=0.0, seed=seed,
                            rim_dark=0.7, weights=np.tile(one_hot("Head"), (len(sh["v"]), 1))))
    cov |= covered(h, m, rings=1)
    capd = lambda z: 0.011 + 0.014 * float(smoothstep(ez, top, z))
    rng = np.random.default_rng(seed + 5)
    nl = r.get("hair_locks", 1.0)
    sp = []

    def add(phis, th0, th1, w, t, lift, tw=8, jit=4, base=None):
        for p in phis:
            sp.append((p + rng.uniform(-jit, jit), th0 + rng.uniform(-3, 3), th1 + rng.uniform(-3, 4), w * rng.uniform(0.85, 1.2),
                       t, lift * rng.uniform(0.7, 1.3), rng.uniform(-tw, tw)) + ((base,) if base is not None else ()))

    def thin(lst):
        return lst if nl >= 1 else lst[::2]
    do = r.get("hair_do")
    if style in ("short", "child", "bun"):
        # bangs over the forehead: broad clumps with tapered tips
        add(thin(list(range(-52, 58, 13))), 8, 70, 0.036, 0.012, 0.007, 6)
        # crown clumps, temples over the ear tops, nape
        if style != "bun":
            add(thin(list(range(20, 340, 45))), 4, 40, 0.032, 0.011, 0.006, 16)
        add(thin([162, 174, 186, 198]), 66, 110, 0.026, 0.008, 0.002, 4, 3)      # nape strands only: nothing over the ears
    elif style == "fringe":
        add(thin([168, 180, 192]), 74, 110, 0.024, 0.007, 0.002, 4, 3)
    elif style in ("long", "bob"):
        add(thin(list(range(-48, 52, 14))), 12, 66, 0.036, 0.011, 0.006, 5)
        add(thin([-64, -80, -98, 64, 80, 98]), 40, 104, 0.028, 0.009, 0.007, 4)
        if style == "bob":
            add([-112, -132, 112, 132, 152, 172, 192, 208], 70, 118, 0.03, 0.010, 0.014, 5)
    if r.get("hair_tail"):
        hb = h.head_back
        c = np.array([0.0, hb + 0.012, ez - 0.005])
        b_ = ellipsoid(h, "tail_knot", c, (0.036, 0.034, 0.036), col, one_hot("Head"))
        parts.append(b_)
        path = [c + np.array([0, 0.005, -0.02]), c + np.array([0, 0.03, -0.06]), c + np.array([0, 0.04, -0.11]), c + np.array([0, 0.04, -0.16])]
        parts.append(braid_part(h, "braid", path, 0.021, 0.008, col, seed, segs=6, spacing=0.03))
    lk = hair_locks(h, sp, capd, col, seed + 11)
    if lk is not None:
        parts.append(lk)
    if style == "bun":
        hb = h.head_back
        c = np.array([0.0, hb + 0.022, ez + 0.02])
        parts.append(ellipsoid(h, "bun", c, (0.054, 0.046, 0.05), col, one_hot("Head")))
    if style == "long":
        hb = h.head_back
        back_y = h.P[:h.nb][np.abs(h.P[:h.nb, 0]) < 0.03]

        def down_path(c, n, step=0.04, out=0.03):
            path = [c + np.array([0, 0.006, -0.03])]
            for k in range(1, n):
                z = c[2] - 0.035 - k * step
                sel = back_y[np.abs(back_y[:, 2] - z) < 0.02]
                y = sel[:, 1].max() + out if len(sel) else path[-1][1]
                path.append(np.array([0.0, y, z]))
            return path
        if do == "crown":
            # braid crown: a thick plait laid across the top of the forehead from ear to ear,
            # around the back of the head, with a pinned bun at the nape
            phis = list(np.linspace(-118, 118, 15))
            front = skull_path(h, phis, [60 + 8 * math.sin(abs(p) / 118 * math.pi / 2) for p in phis], off=0.016)
            back = skull_path(h, [118, 140, 160, 180, 200, 220, 242], [84] * 7, off=0.016)
            path = front + back
            parts.append(braid_part(h, "braid", path, 0.0165, 0.0165, col, seed, segs=6, spacing=0.02,
                                    wt=one_hot("Head")))
            c = np.array([0.0, hb + 0.022, ez - 0.012])
            parts.append(ellipsoid(h, "bun", c, (0.048, 0.04, 0.044), col, one_hot("Head")))
        elif do == "silver_braid":
            # long braid over the shoulder blades, tied with a ribbon
            c = np.array([0.0, hb + 0.02, ez - 0.05])
            parts.append(ellipsoid(h, "bun", c, (0.04, 0.034, 0.038), col, one_hot("Head")))
            parts.append(braid_part(h, "braid", down_path(c, 11, 0.042, 0.032), 0.032, 0.014, col, seed, segs=6, spacing=0.03))
        else:
            c = np.array([0.0, hb + 0.024, ez - 0.03])
            parts.append(ellipsoid(h, "bun", c, (0.058, 0.048, 0.052), col, one_hot("Head")))
            parts.append(braid_part(h, "braid", down_path(c, 8, 0.036, 0.032), 0.03, 0.013, col, seed, segs=6, spacing=0.03))


def one_hot(name):
    w = np.zeros(len(BONES)); w[BI[name]] = 1
    return w


def ellipsoid(h, name, c, rad, color, w, segs=10, rows=7):
    V, F, UV = [], [], []
    for i in range(rows + 1):
        th = math.pi * i / rows
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            V.append(c + np.array([math.sin(th) * math.cos(ph) * rad[0], math.sin(th) * math.sin(ph) * rad[1], math.cos(th) * rad[2]]))
    for i in range(rows):
        for j in range(segs):
            j2 = (j + 1) % segs
            a, b, cc, d = i * segs + j, i * segs + j2, (i + 1) * segs + j2, (i + 1) * segs + j
            F.append((a, d, cc, b))
            UV.append([(j / segs, i / rows), (j / segs, (i + 1) / rows), ((j + 1) / segs, (i + 1) / rows), ((j + 1) / segs, i / rows)])
    V = np.array(V)
    col = paint(color, len(V))
    return Part(name, V, F, UV, np.tile(w, (len(V), 1)), col, "hair", 110)


def tube(h, name, path, radii, color, seed, segs=8):
    rings = []
    for k, p in enumerate(path):
        t = path[min(k + 1, len(path) - 1)] - path[max(k - 1, 0)]
        t /= np.linalg.norm(t)
        a = np.cross(t, [1, 0, 0]); a /= np.linalg.norm(a)
        b = np.cross(t, a)
        ring = []
        for j in range(segs):
            ph = 2 * math.pi * j / segs
            braid = 1 + 0.18 * math.sin(ph * 2 + k * 2.2)
            ring.append(p + (a * math.cos(ph) + b * math.sin(ph)) * radii[k] * braid)
        rings.append(ring)
    V, F, UV = loft(np.array(rings), closed=True)
    # close the tip
    tip = len(V)
    V = np.concatenate([V, path[-1:] + (path[-1] - path[-2]) * 0.4])
    S = segs
    tipF = [((len(path) - 1) * S + j, tip, (len(path) - 1) * S + (j + 1) % S) for j in range(S)]
    a_, b_, c_ = V[tipF[0][0]], V[tipF[0][1]], V[tipF[0][2]]
    if np.dot(np.cross(b_ - a_, c_ - a_), V[tip] - path[-1] + (path[-1] - path[-2])) < 0:
        tipF = [tuple(reversed(f)) for f in tipF]
    for f in tipF:
        F.append(f)
        UV.append([UV[-1][0]] * 3)
    uvs = pack_islands([UV])[0]
    W = nearest_weights(h, V, restrict=h.mask("neck", "head", "torso"))
    # top of the braid follows the head
    t = np.linspace(0, 1, len(V))
    col = paint(color, len(V))
    return Part(name, V, F, uvs, W, col, "hair", None)


def g_hood_up(h, r, pal, parts, cov):
    """Hood worn up: shell of head + neck without the face oval."""
    P = h.P[:h.nb]
    c = h.head_c
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    m = h.mask("head", "neck")
    phi = np.arctan2(P[:, 0] - c[0], -(P[:, 1] - c[1]))
    # face opening: an ellipse on the front
    fx = P[:, 0] / 0.075
    fz = (P[:, 2] - (ez - 0.03)) / 0.085
    face = (fx ** 2 + fz ** 2 < 1.0) & (np.cos(phi) > 0.2)
    m &= ~face
    m &= P[:, 2] > h.z("neck_01") - 0.03
    tipz = smoothstep(ez, h.head_top, P[:, 2]) * np.clip(-np.cos(phi), 0, 1)
    d = 0.02 + 0.012 * smoothstep(h.z("neck_01") + 0.05, h.z("neck_01") - 0.02, P[:, 2]) + 0.02 * tipz
    sh = shell(h, m, d, smooth=8, rim_depth=0.004)
    parts.append(shell_part(h, "hood", sh, "felt", pal["cloak"], 520, hair_uv_groups(h), grime=0.1,
                            seed=r["seed"], rim_dark=0.55))
    cov |= covered(h, m, rings=1)


def g_eyes(h, parts, tile="eye"):
    path = os.path.join(mh.MHDATA, "eyes", "low-poly")
    refs = []
    with open(os.path.join(path, "low-poly.mhclo")) as f:
        on = False
        for line in f:
            s = line.strip()
            if s.startswith("verts"):
                on = True
                continue
            if on and s and s[0].isdigit():
                p = s.split()
                if len(p) == 1:
                    refs.append(int(p[0]))
                else:
                    refs.append(int(p[0]))
    vs, vts, fs, fts = [], [], [], []
    with open(os.path.join(path, "low-poly.obj")) as f:
        for line in f:
            if line.startswith("v "):
                vs.append(1)
            elif line.startswith("vt "):
                vts.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("f "):
                a, b = [], []
                for tok in line.split()[1:]:
                    q = tok.split("/")
                    a.append(int(q[0]) - 1); b.append(int(q[1]) - 1)
                fs.append(a); fts.append(b)
    V = h.P[np.array(refs[:len(vs)])].copy()
    # larger, friendlier eyes: grow each eyeball about its own centre (the painted lid ring is wider than the ball)
    for sgn in (1, -1):
        m = (V[:, 0] * sgn) > 0
        if m.sum():
            c = V[m].mean(axis=0)
            V[m] = c + (V[m] - c) * np.array([EYE_SCALE, 1.0, EYE_SCALE])
            V[m, 1] += 0.0015
    # tuck the eyeballs a hair behind the lids
    uvs = [[tuple(vts[t]) for t in ft] for ft in fts]
    W = np.tile(one_hot("Head"), (len(V), 1))
    col = np.ones((len(V), 3))
    parts.append(Part("eyes", V, fs, uvs, W, col, tile, None))


# ============================================================ assembly

def skin_color(r):
    tones = {"caucasian": (0.95, 0.76, 0.62), "african": (0.5, 0.32, 0.22), "asian": (0.93, 0.75, 0.57)}
    c = np.zeros(3)
    tot = sum(r["race"].values())
    for k, w in r["race"].items():
        c += np.array(tones[k]) * w / tot
    c *= r.get("skin_mul", 1.0)
    return c


def build_parts(h, r):
    parts, cov = [], np.zeros(h.nb, bool)
    pal = r["palette"]
    o = r["outfit"]
    boot_top = h.z("foot_l") + (0.075 if "dress" in o else 0.2) * (h.z("calf_l") - h.z("foot_l")) / 0.43
    if "dress" in o:
        dpts, wz = g_dress(h, r, pal, parts, cov)
        if "laces" in o:
            g_laces(h, r, pal, parts, wz)
        if "apron" in o:
            g_apron(h, r, pal, parts, wz, dpts)
        if "undersleeve" in o:
            g_undersleeve(h, r, pal, parts, cov, r.get("undersleeve_key", "undersleeve"),
                          cut_from=sleeve_x(h, r.get("sleeve", 0.5)))
        if "belt" in o:
            g_belt(h, r, pal, parts, dpts, wz, pouch=r.get("pouch", True), pouch_count=r.get("pouch_count", 1))
        if "mantle" in o:
            g_mantle(h, r, pal, parts, pal_key=r.get("mantle_key", "mantle"))
    if "shirt" in o:                     # the hero: cream shirt, green over-tunic, leather vest, bandolier bag
        r2 = dict(r); r2["sleeve"] = 0.97; r2["tunic_tile"] = "linen"
        top_pts, bz = g_tunic(h, r2, pal, parts, cov, "tunic", key="shirt", skirt=False)
        top_pts, bz = g_vest(h, r, pal, parts, cov, "tunic_over", "tunic", hem_frac=0.1, offset=0.024, neck_depth=0.11,
                             neck_width=0.06, flare=0.04, min_flare=0.04, skirt_ease=0.03, seed_off=22, tile="wool")
        top_pts, bz = g_vest(h, r, pal, parts, cov, "vest", "vest", offset=0.036, neck_depth=0.075, neck_width=0.085,
                             seed_off=24, tile="leather", skirt=False, grime=0.2)
        for sd, sgn in (("l", 1), ("r", -1)):
            c = h.J["upperarm_" + sd] + np.array([0.03 * sgn, 0.0, 0.034])
            pad = ellipsoid(h, "pad_" + sd, c, (0.06, 0.062, 0.036), pal["vest"], one_hot("upperarm_" + sd))
            pad.tile = "leather"
            parts.append(pad)
        g_undersleeve(h, r, pal, parts, cov, "bracer", cut_from=sleeve_x(h, 0.52), cut_to=sleeve_x(h, 1.0), tile="leather",
                      seed_off=44, d=0.024, name="bracers")
        g_belt(h, r, pal, parts, top_pts, bz, pouch=False)
        g_satchel(h, r, pal, parts, bz)
        g_trousers(h, r, pal, parts, cov, bz + 0.01, boot_top)
    elif "tunic" in o or "gambeson" in o:
        kind = "gambeson" if "gambeson" in o else "tunic"
        top_pts, bz = g_tunic(h, r, pal, parts, cov, kind)
        if "undersleeve" in o:
            g_undersleeve(h, r, pal, parts, cov, r.get("undersleeve_key", "undersleeve"),
                          cut_from=sleeve_x(h, r.get("sleeve", 0.8)))
        if "breastplate" in o:
            g_breastplate(h, r, pal, parts, pal_key=r.get("armor_key", "armor"))
        if "vest" in o:
            top_pts, bz = g_vest(h, r, pal, parts, cov, r.get("vest_name", "vest"), r.get("vest_key", "vest"),
                                 hem_frac=r.get("vest_len", 0.16), offset=r.get("vest_offset", 0.026),
                                 min_flare=r.get("vest_min_flare", 0.05),
                                 skirt_ease=r.get("vest_skirt_ease", 0.05), trim_key=r.get("vest_trim"))
        if not r.get("no_belt"):
            g_belt(h, r, pal, parts, top_pts, bz, pouch=r.get("pouch", True), pouch_count=r.get("pouch_count", 1))
        if "apron_full" in o:
            g_apron_full(h, r, pal, parts, top_pts, bz, pal_key=r.get("apron_key", "apron"))
        g_trousers(h, r, pal, parts, cov, bz + 0.01, boot_top)
    if "boots" in o:
        g_boots(h, r, pal, parts, cov, boot_top)
        g_boot_cuffs(h, r, pal, parts, boot_top)
    if "coat" in o:
        g_cloak(h, r, pal, parts, hood="down", pal_key="coat", collar_roll=False, waist_hug=True)
    if "cloak" in o:
        g_cloak(h, r, pal, parts, hood="up" if r.get("hood_up") else "down")
    if "pauldrons" in o:
        g_pauldrons(h, r, pal, parts, pal_key=r.get("armor_key", "armor"))
    if "bracers" in o:
        g_bracers(h, r, pal, parts, pal_key=r.get("armor_key", "armor"))
    if "gorget" in o:
        g_gorget(h, r, pal, parts, pal_key=r.get("armor_key", "armor"))
    if "beard" in o:
        g_beard(h, r, pal, parts, pal_key=r.get("beard_key", "hair"))
    if r.get("hood_up"):
        g_hood_up(h, r, pal, parts, cov)
    elif r.get("hair"):
        g_hair(h, r, pal, parts, cov, r["hair"])
    g_eyes(h, parts, r.get("eye", "eye"))
    # body: everything not covered, minus mouth interior
    keep_faces, keep_uv = [], []
    for f, t in zip(h.faces, h.fuv):
        if all(cov[i] for i in f):
            continue
        if all(h.mouth_in[i] for i in f):
            continue
        keep_faces.append(f)
        keep_uv.append([tuple(h.base.uv[k]) for k in t])
    ids = sorted({i for f in keep_faces for i in f})
    loc = {g: k for k, g in enumerate(ids)}
    F = [tuple(loc[i] for i in f) for f in keep_faces]
    src = np.array(ids)
    sc = skin_color(r)
    c = srgb2lin(sc) / srgb2lin(0.93)
    col = np.tile(c / max(1.0, c.max()), (len(src), 1))
    body = Part("body", h.P[src], F, keep_uv, h.W[src], col, "skin", r.get("body_budget", 2900))
    body.src = src
    parts.insert(0, body)
    return parts


def part_object(p):
    me = bpy.data.meshes.new(p.name)
    me.from_pydata(p.v.tolist(), [], p.f)
    me.validate(clean_customdata=False)
    uvl = me.uv_layers.new(name="UVMap")
    u0, v0, u1, v1 = REG[p.tile]
    li = 0
    flat = []
    for poly, uvf in zip(me.polygons, p.uv):
        for k, _ in enumerate(poly.loop_indices):
            u, v = uvf[k]
            flat.append((u0 + (u1 - u0) * min(max(u, 0), 1), v0 + (v1 - v0) * min(max(v, 0), 1)))
    arr = np.array(flat, np.float32)
    if len(arr) == len(uvl.data):
        uvl.data.foreach_set("uv", arr.ravel())
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    c4 = np.concatenate([p.c, np.ones((len(p.c), 1))], axis=1).astype(np.float32)
    ca.data.foreach_set("color", c4.ravel())
    ob = bpy.data.objects.new(p.name, me)
    bpy.context.collection.objects.link(ob)
    for bi in np.nonzero(p.w.max(axis=0) > 1e-4)[0]:
        vg = ob.vertex_groups.new(name=BONES[bi])
        col = p.w[:, bi]
        for vi in np.nonzero(col > 1e-4)[0]:
            vg.add([int(vi)], float(col[vi]), "REPLACE")
    for poly in me.polygons:
        poly.use_smooth = True
    return ob


def tri_count(ob):
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def apply_mods(ob):
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    for m in list(ob.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def decimate(ob, target, symmetric=False, protect=None):
    t = tri_count(ob)
    if target is None or t <= target:
        return
    for attempt in range(4):
        t = tri_count(ob)
        if t <= target * 1.03:
            break
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = min(0.98, target / t) if attempt == 0 else min(0.98, target / t * 0.97)
        m.use_symmetry = symmetric
        m.symmetry_axis = "X"
        m.use_collapse_triangulate = True
        if protect:
            m.vertex_group = protect
            m.vertex_group_factor = 1.0
            m.invert_vertex_group = True
        apply_mods(ob)
        if not protect:
            break


def _zone_decimate(ob, weights, target_zone, zone_now, symmetric=False):
    """Collapse only the vertices with weight>0 (everything else is pinned) until
    the zone holds about target_zone triangles."""
    for attempt in range(4):
        t = tri_count(ob)
        zt = zone_now(ob)
        if zt <= target_zone * 1.04:
            return
        vg = ob.vertex_groups.get("zone") or ob.vertex_groups.new(name="zone")
        vg.add(list(range(len(ob.data.vertices))), 0.0, "REPLACE")
        for i in np.nonzero(weights(ob))[0]:
            vg.add([int(i)], 1.0, "REPLACE")
        m = ob.modifiers.new("dec", "DECIMATE")
        m.decimate_type = "COLLAPSE"
        m.ratio = max(0.02, min(0.98, (t - zt + target_zone * (0.97 ** attempt)) / t))
        m.use_symmetry = symmetric
        m.symmetry_axis = "X"
        m.use_collapse_triangulate = True
        m.vertex_group = "zone"
        m.invert_vertex_group = False
        m.vertex_group_factor = 1.0
        apply_mods(ob)


def decimate_body(ob, h, budget, head_tris=HEAD_TRIS, hand_tris=HAND_TRIS):
    """Body decimation that keeps the face: the head (symmetric collapse) and the hands
    are reduced on their own to a fixed count with all other vertices pinned, then the
    rest of the body takes the remainder of the budget with head and hands pinned."""
    def co(ob):
        n = len(ob.data.vertices)
        a = np.zeros(n * 3); ob.data.vertices.foreach_get("co", a)
        return a.reshape(-1, 3)

    def zone_tris(ob, sel):
        me = ob.data
        c = co(ob)
        n = 0
        for p in me.polygons:
            if all(sel(c[i]) for i in p.vertices):
                n += len(p.vertices) - 2
        return n

    hx = abs(h.J["hand_l"][0]) - 0.02
    head_sel = lambda p: p[2] > h.chin_z - 0.012
    hand_sel = lambda p: abs(p[0]) > hx

    def wfun(sel):
        return lambda ob: np.array([sel(p) for p in co(ob)])
    _zone_decimate(ob, wfun(head_sel), head_tris, lambda o: zone_tris(o, head_sel), symmetric=True)
    _zone_decimate(ob, wfun(hand_sel), hand_tris * 2, lambda o: zone_tris(o, hand_sel), symmetric=True)
    rest_sel = lambda p: not (head_sel(p) or hand_sel(p))
    keep = zone_tris(ob, head_sel) + zone_tris(ob, hand_sel)
    _zone_decimate(ob, wfun(rest_sel), max(300, budget - keep), lambda o: tri_count(o) - zone_tris(o, head_sel) - zone_tris(o, hand_sel))
    ob.vertex_groups.clear()


def triangulate(ob):
    ob.modifiers.new("tri", "TRIANGULATE")
    apply_mods(ob)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def add_face_protect(ob, h, body, wface=0.5):
    """Vertex group 'protect' = face region (decimated less)."""
    vg = ob.vertex_groups.new(name="protect")
    P = body.v
    ez = (h.eye_l[2] + h.eye_r[2]) / 2
    for i, p in enumerate(P):
        w = 0.0
        if p[2] > h.chin_z - 0.01 and p[1] < h.head_c[1] + 0.01:
            w = wface
        if abs(p[0]) > abs(h.J["hand_l"][0]) - 0.02:
            w = 0.3
        if w:
            vg.add([i], w, "REPLACE")


def _hemisphere_dirs(n):
    """Cosine-weighted hemisphere sample directions (local z = normal)."""
    d = []
    for i in range(n):
        u = (i + 0.5) / n
        phi = i * 2.399963
        rr = math.sqrt(u)
        d.append((rr * math.cos(phi), rr * math.sin(phi), math.sqrt(max(0.0, 1 - u))))
    return d


def bake_ao(h, parts, samples=22, dist=0.11, strength=0.68):
    """Baked ambient occlusion into vertex colours (skin, cloth, hair): darkens
    folds, armpits, under the belt, collars, hairline and hems. Rays are cast
    against every part of the character."""
    skip = ("eyes",)
    Vs, Fs, off = [], [], 0
    for p in parts:
        if p.name in skip:
            continue
        Vs.append(p.v)
        Fs += [tuple(i + off for i in f) for f in p.f]
        off += len(p.v)
    V = np.concatenate(Vs)
    bvh = bvhtree.BVHTree.FromPolygons([tuple(v) for v in V], Fs)
    dirs = _hemisphere_dirs(samples)
    for p in parts:
        if p.name in skip or len(p.v) == 0 or (p.name == "body" and os.environ.get("NOAO_BODY")):
            continue
        N = vertex_normals(p.v, p.f)
        ao = np.ones(len(p.v))
        for i in range(len(p.v)):
            n = N[i]
            ref = np.array([0.0, 0.0, 1.0]) if abs(n[2]) < 0.9 else np.array([1.0, 0, 0])
            t = np.cross(n, ref); t /= max(np.linalg.norm(t), 1e-9)
            b = np.cross(n, t)
            o = Vector(p.v[i] + n * 0.004)
            hit = 0.0
            for dx, dy, dz in dirs:
                dv = t * dx + b * dy + n * dz
                loc, nrm, idx, dd = bvh.ray_cast(o, Vector(dv), dist)
                if loc is not None:
                    hit += 1.0 - dd / dist * 0.5
            ao[i] = 1.0 - hit / samples
        occ = np.clip(1 - ao, 0, 1)
        st = np.full(len(p.v), strength)
        if p.name == "body":                      # keep the face clean: little baked AO on the head
            st[p.v[:, 2] > h.chin_z - 0.01] *= 0.4
        shade = 1 - st * occ ** 1.1
        p.ao = ao
        p.c = p.c * (shade[:, None] ** np.array([1.0, 1.08, 1.18])[None, :])


def smooth_head(ob, h, iters=7):
    """Volume-preserving (Taubin) smoothing of the decimated head: rounds the
    facets and nostril / lip-corner slivers the collapse leaves, keeps the eyes,
    and pins the mesh boundary (neck cut) and everything below the chin."""
    me = ob.data
    n = len(me.vertices)
    P = np.zeros(n * 3); me.vertices.foreach_get("co", P); P = P.reshape(-1, 3)
    F = [tuple(p.vertices) for p in me.polygons]
    E = edges_of(F)
    fixed = P[:, 2] < h.chin_z - 0.015
    for a, b in boundary_loops(F):
        fixed[a] = fixed[b] = True
    for eye in (h.eye_l, h.eye_r):
        fixed |= np.linalg.norm(P - eye, axis=1) < 0.036
    fixed |= h.ear_near(P)
    for _ in range(iters):
        P = laplacian(P, E, 1, 0.5, fixed=fixed)
        P = laplacian(P, E, 1, -0.53, fixed=fixed)
    me.vertices.foreach_set("co", P.ravel())
    me.update()
    # soft, stylised shading: blend the head's vertex normals toward the radial direction
    # so the nose underside / lip corners do not read as dark slivers under the sun.
    me.calc_loop_triangles()
    nl = len(me.loops)
    lv = np.zeros(nl, np.int32); me.loops.foreach_get("vertex_index", lv)
    ln = np.zeros(nl * 3, np.float32); me.corner_normals.foreach_get("vector", ln); ln = ln.reshape(-1, 3)
    rad = P - h.head_c[None, :] * np.array([1, 1, 1])[None, :]
    rad = rad / np.maximum(np.linalg.norm(rad, axis=1, keepdims=True), 1e-9)
    wgt = np.clip((P[:, 2] - (h.chin_z - 0.01)) / 0.03, 0, 1)
    wgt = wgt * 0.25
    wl = wgt[lv][:, None]
    nn = ln * (1 - wl) + rad[lv] * wl
    nn = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    me.normals_split_custom_set(nn.astype(np.float32).tolist())


def build_character(base, r, mat):
    t0 = time.time()
    h = Human(base, r)
    parts = build_parts(h, r)
    bake_ao(h, parts)
    objs = []
    for p in parts:
        ob = part_object(p)
        if p.name == "body":
            decimate_body(ob, h, p.budget)
        else:
            decimate(ob, p.budget)
        if p.name == "body":
            smooth_head(ob, h)
        print(f"    {p.name}: {tri_count(ob)} tris")
        objs.append(ob)
    ob = join(objs, r["name"])
    triangulate(ob)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    print(f"{r['name']}: {tri_count(ob)} tris, {time.time() - t0:.1f}s")
    return ob, h


# ============================================================ export

def extract(ob):
    me = ob.data
    me.calc_loop_triangles()
    nv = len(me.vertices)
    co = np.zeros(nv * 3, np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
    nl = len(me.loops)
    lv = np.zeros(nl, np.int32); me.loops.foreach_get("vertex_index", lv)
    ln = np.zeros(nl * 3, np.float32); me.corner_normals.foreach_get("vector", ln); ln = ln.reshape(-1, 3)
    luv = np.zeros(nl * 2, np.float32); me.uv_layers["UVMap"].data.foreach_get("uv", luv); luv = luv.reshape(-1, 2)
    ca = me.color_attributes["Col"]
    vc = np.zeros(len(ca.data) * 4, np.float32); ca.data.foreach_get("color", vc); vc = vc.reshape(-1, 4)
    if ca.domain == "CORNER":
        lc = vc
    else:
        lc = vc[lv]
    # weights
    gi = {g.index: g.name for g in ob.vertex_groups}
    Wv = np.zeros((nv, len(BONES)), np.float32)
    for v in me.vertices:
        for g in v.groups:
            n = gi.get(g.group)
            if n in BI:
                Wv[v.index, BI[n]] = g.weight
    top = np.argsort(-Wv, axis=1)[:, :4]
    tw = np.take_along_axis(Wv, top, axis=1)
    s = tw.sum(axis=1, keepdims=True)
    bad = s[:, 0] <= 0
    tw = np.where(s > 0, tw / np.maximum(s, 1e-9), 0)
    if bad.any():
        print("  warning: unweighted verts", int(bad.sum()))
        top[bad] = BI["pelvis"]; tw[bad] = [1, 0, 0, 0]
    # triangles
    tri_loops = np.zeros(len(me.loop_triangles) * 3, np.int32)
    me.loop_triangles.foreach_get("loops", tri_loops)
    key = np.concatenate([lv[:, None].astype(np.float64), np.round(luv, 5), np.round(ln, 3)], axis=1)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    first = np.zeros(len(uniq), np.int64)
    first[inv[::-1]] = np.arange(nl)[::-1]
    vidx = lv[first]
    return {
        "pos": co[vidx], "nrm": ln[first], "uv": luv[first], "col": lc[first],
        "joints": top[vidx].astype(np.uint16), "weights": tw[vidx].astype(np.float32),
        "idx": inv[tri_loops].astype(np.uint32),
    }


EMBLEM_DIR = os.path.join(KINGDOM, "assets", "art", "emblems")


def export(ob, h, path, decals=None):
    """decals: optional list of (bpy_object, emblem_filename, alpha_mode)."""
    data = extract(ob)
    rel = os.path.relpath(TEX_DIR, os.path.dirname(path)).replace(os.sep, "/")
    extra = None
    if decals:
        erel = os.path.relpath(EMBLEM_DIR, os.path.dirname(path)).replace(os.sep, "/")
        extra = [{"mesh": extract(dob), "images": {"albedo": f"{erel}/{fname}"}, "alpha": alpha, "name": fname}
                 for dob, fname, alpha in decals]
    ual_rig.write_skinned_glb(path, UAL, h.J, data,
                              {"name": "CharacterAtlas", "rough": 1.0, "metal": 1.0, "normal_scale": 0.6},
                              {"albedo": f"{rel}/character_albedo.png", "orm": f"{rel}/character_orm.png",
                               "normal": f"{rel}/character_normal.png"}, name=os.path.splitext(os.path.basename(path))[0],
                              extra=extra)
    return len(data["idx"]) // 3


def make_material(paths):
    m = bpy.data.materials.new("CharacterAtlas")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    ta = nt.nodes.new("ShaderNodeTexImage"); ta.image = bpy.data.images.load(paths["albedo"])
    tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = bpy.data.images.load(paths["normal"])
    tn.image.colorspace_settings.name = "Non-Color"
    to = nt.nodes.new("ShaderNodeTexImage"); to.image = bpy.data.images.load(paths["orm"])
    to.image.colorspace_settings.name = "Non-Color"
    ca = nt.nodes.new("ShaderNodeVertexColor"); ca.layer_name = "Col"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(ta.outputs["Color"], mul.inputs[6])
    nt.links.new(ca.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    sep = nt.nodes.new("ShaderNodeSeparateColor")
    nt.links.new(to.outputs["Color"], sep.inputs[0])
    nt.links.new(sep.outputs[1], bsdf.inputs["Roughness"])
    nt.links.new(sep.outputs[2], bsdf.inputs["Metallic"])
    nm = nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.6
    nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    # a touch of subsurface only where the atlas is skin (roughness ~0.5): keep simple
    bsdf.inputs["Specular IOR Level"].default_value = 0.35
    return m


# ============================================================ recipes

def P(**k):
    return k


RECIPES = [
    P(name="villager_man_a", gender=1.0, age=34, race={"caucasian": 0.92, "asian": 0.04, "african": 0.04},
      muscle=0.62, weight=0.55, height=0.5, proportions=0.65, seed=101,
      outfit=["tunic", "belt", "trousers", "boots"], hair="short", sleeve=0.85,
      extras={"nose/nose-hump-incr": 0.3, "chin/chin-prominent-incr": 0.3, "head/head-square": 0.3},
      palette=dict(tunic=(0.36, 0.52, 0.27), trousers=(0.36, 0.3, 0.25), belt=(0.3, 0.19, 0.11), boots=(0.36, 0.24, 0.15), hair=(0.33, 0.21, 0.12), pouch=(0.5, 0.34, 0.19))),
    P(name="villager_man_b", gender=1.0, age=27, race={"african": 0.7, "caucasian": 0.3},
      muscle=0.55, weight=0.45, height=0.45, proportions=0.7, seed=202,
      outfit=["tunic", "belt", "trousers", "boots"], hair="short", sleeve=0.6, tunic_tile="wool",
      extras={"nose/nose-flaring-incr": 0.3, "mouth/mouth-scale-horiz-incr": 0.2},
      palette=dict(tunic=(0.68, 0.33, 0.2), trousers=(0.42, 0.38, 0.32), belt=(0.24, 0.15, 0.09), boots=(0.3, 0.2, 0.13), hair=(0.07, 0.06, 0.05))),
    P(name="villager_woman_a", gender=0.0, age=30, race={"caucasian": 0.85, "asian": 0.15}, eye="eye_blue",
      muscle=0.45, weight=0.52, height=0.5, proportions=0.75, seed=303,
      outfit=["dress", "laces", "apron", "boots"], hair="long", sleeve=0.9,
      extras={"nose/nose-scale-horiz-decr": 0.3, "eyebrows/eyebrows-angle-up": 0.2},
      palette=dict(dress=(0.3, 0.43, 0.64), apron=(0.9, 0.85, 0.72), boots=(0.32, 0.22, 0.14), hair=(0.5, 0.3, 0.14))),
    P(name="villager_woman_b", gender=0.0, age=24, race={"asian": 0.6, "caucasian": 0.4}, body_budget=2600,
      muscle=0.45, weight=0.45, height=0.45, proportions=0.75, seed=404,
      outfit=["dress", "laces", "boots", "cloak"], hair="long", sleeve=0.95, dress_tile="linen", cloak_flare=0.03,
      palette=dict(dress=(0.7, 0.26, 0.2), cloak=(0.46, 0.33, 0.2), cloak_trim=(0.86, 0.78, 0.55), boots=(0.28, 0.2, 0.14), hair=(0.09, 0.07, 0.05))),
    P(name="elder_man", gender=1.0, age=68, race={"caucasian": 0.8, "african": 0.1, "asian": 0.1}, eye="eye_grey", body_budget=2500, hair_locks=0.5,
      muscle=0.4, weight=0.5, height=0.45, proportions=0.5, seed=505,
      outfit=["tunic", "belt", "trousers", "boots", "cloak"], hair="fringe", sleeve=0.95, tunic_len=0.08, cloak_flare=0.02,
      extras={"nose/nose-scale-vert-incr": 0.3, "head/head-age-incr": 0.5},
      palette=dict(tunic=(0.68, 0.54, 0.31), trousers=(0.38, 0.32, 0.26), belt=(0.26, 0.17, 0.1), boots=(0.32, 0.22, 0.15), hair=(0.78, 0.76, 0.72), cloak=(0.25, 0.38, 0.26), cloak_trim=(0.7, 0.55, 0.2))),
    P(name="elder_woman", gender=0.0, age=70, race={"caucasian": 0.7, "asian": 0.3}, eye="eye_grey",
      muscle=0.35, weight=0.6, height=0.35, proportions=0.5, seed=606,
      outfit=["dress", "apron", "boots", "cloak"], hood_up=True, sleeve=1.0, cloak_flare=0.02,
      palette=dict(dress=(0.45, 0.28, 0.4), apron=(0.86, 0.82, 0.7), boots=(0.27, 0.2, 0.15), cloak=(0.28, 0.31, 0.36), cloak_trim=(0.6, 0.4, 0.55), hair=(0.82, 0.8, 0.76))),
    P(name="child_boy", gender=1.0, age=8, race={"caucasian": 0.6, "african": 0.4}, eye="eye_green",
      muscle=0.5, weight=0.5, height=0.7, proportions=0.6, seed=707, body_budget=2300,
      outfit=["tunic", "belt", "trousers", "boots"], hair="child", sleeve=0.7, pouch=False, tunic_len=0.25,
      palette=dict(tunic=(0.32, 0.46, 0.66), trousers=(0.48, 0.36, 0.24), belt=(0.32, 0.2, 0.12), boots=(0.36, 0.25, 0.16), hair=(0.3, 0.18, 0.1))),
    P(name="child_girl", gender=0.0, age=8, race={"caucasian": 0.9, "asian": 0.1}, eye="eye_blue",
      muscle=0.5, weight=0.5, height=0.7, proportions=0.6, seed=808, body_budget=2300,
      outfit=["dress", "apron", "boots"], hair="bob", sleeve=0.8,
      palette=dict(dress=(0.42, 0.58, 0.3), apron=(0.9, 0.86, 0.74), boots=(0.32, 0.22, 0.15), hair=(0.7, 0.48, 0.24))),
    P(name="guard", gender=1.0, age=30, race={"caucasian": 0.75, "asian": 0.25}, eye="eye_blue", body_budget=1800, hair_locks=0.3, skirt_budget=380,
      muscle=0.8, weight=0.55, height=0.62, proportions=0.75, seed=909,
      outfit=["gambeson", "belt", "trousers", "boots", "breastplate", "vest", "pauldrons", "bracers", "gorget"],
      hair="helm", pouch=False, vest_len=0.16, vest_key="vest", vest_offset=0.03, vest_trim="trim",
      armor_key="armor", emblem="tower_crown",
      extras={"chin/chin-jaw-drop-incr": 0.2, "nose/nose-hump-incr": 0.5},
      palette=dict(gambeson=(0.16, 0.17, 0.2), vest=(0.5, 0.07, 0.08), trim=(0.78, 0.63, 0.22),
                   trousers=(0.2, 0.19, 0.2), belt=(0.26, 0.16, 0.09), boots=(0.26, 0.18, 0.11),
                   hair=(0.2, 0.13, 0.08), armor=(0.62, 0.64, 0.67))),
    P(name="player_young", gender=1.0, age=18, race={"caucasian": 0.7, "asian": 0.15, "african": 0.15},
      muscle=0.6, weight=0.45, height=0.6, proportions=0.8, seed=1010, body_budget=4300,
      outfit=["shirt", "belt", "trousers", "boots"], hair="short", hair_tail=True, flat_chest=True, chest_straighten=0.5,
      chest_broaden=0.02, eye="eye",
      palette=dict(shirt=(0.9, 0.85, 0.72), tunic=(0.34, 0.5, 0.3), vest=(0.34, 0.2, 0.11), bracer=(0.3, 0.19, 0.11),
                   trousers=(0.38, 0.29, 0.22), belt=(0.36, 0.21, 0.11), satchel=(0.52, 0.31, 0.16),
                   satchel_strap=(0.42, 0.25, 0.13), boots=(0.33, 0.21, 0.13), hair=(0.32, 0.2, 0.11))),
    P(name="mother", gender=0.0, age=26, race={"caucasian": 0.8, "african": 0.2}, eye="eye_green",
      muscle=0.45, weight=0.5, height=0.5, proportions=0.8, seed=1111,
      outfit=["dress", "laces", "apron", "boots"], hair="long", sleeve=0.9, dress_tile="linen",
      palette=dict(dress=(0.27, 0.5, 0.46), apron=(0.92, 0.87, 0.76), boots=(0.32, 0.22, 0.15), hair=(0.4, 0.22, 0.11))),
    P(name="father", gender=1.0, age=29, race={"caucasian": 0.8, "african": 0.2},
      muscle=0.65, weight=0.5, height=0.45, proportions=0.7, seed=1212,
      outfit=["tunic", "belt", "trousers", "boots"], hair="short", sleeve=0.75, tunic_tile="wool",
      palette=dict(tunic=(0.6, 0.3, 0.2), trousers=(0.55, 0.45, 0.3), belt=(0.3, 0.19, 0.11), boots=(0.35, 0.24, 0.16), hair=(0.22, 0.14, 0.08))),

    # ---- new villager archetypes (reference sheets, 2026-09-28) ------------
    P(name="villager_farmer", gender=1.0, age=35, race={"caucasian": 0.85, "african": 0.1, "asian": 0.05}, body_budget=2400, hair_locks=0.5,
      muscle=0.62, weight=0.58, height=0.52, proportions=0.65, seed=2001,
      outfit=["tunic", "vest", "belt", "trousers", "boots", "beard"], hair="short", sleeve=0.6,
      tunic_len=0.16, tunic_tile="linen", vest_len=0.16, vest_key="vest", vest_offset=0.024,
      flat_chest=True, chest_straighten=0.6, chest_broaden=0.032,
      extras={"nose/nose-hump-incr": 0.2, "chin/chin-prominent-incr": 0.2},
      beard_density=0.85,
      palette=dict(tunic=(0.85, 0.8, 0.68), vest=(0.4, 0.45, 0.24), trousers=(0.34, 0.28, 0.22),
                   belt=(0.28, 0.18, 0.1), boots=(0.3, 0.21, 0.14), hair=(0.18, 0.11, 0.07), beard=(0.26, 0.17, 0.1),
                   pouch=(0.34, 0.22, 0.13))),
    P(name="villager_merchant", gender=1.0, age=55, race={"caucasian": 0.9, "asian": 0.1}, body_budget=2000, hair_locks=0.5,
      muscle=0.42, weight=0.72, height=0.5, proportions=0.55, seed=2002,
      outfit=["tunic", "vest", "belt", "trousers", "boots", "coat", "beard"], hair="fringe", sleeve=0.9,
      tunic_tile="linen", vest_len=0.5, vest_key="vest", vest_offset=0.024, skin_mul=0.94,
      tunic_hem_segs=36, tunic_hem_folds=0.0, tunic_flare=0.012, vest_min_flare=0.004,
      vest_skirt_ease=0.006, beard_speckle=0.42, beard_density=0.85,
      extras={"nose/nose-scale-vert-incr": 0.2, "head/head-age-incr": 0.3},
      palette=dict(tunic=(0.9, 0.86, 0.74), vest=(0.72, 0.58, 0.22), coat=(0.55, 0.22, 0.14),
                   trousers=(0.22, 0.21, 0.22), belt=(0.3, 0.19, 0.1), boots=(0.32, 0.22, 0.15),
                   hair=(0.55, 0.53, 0.5), beard=(0.56, 0.54, 0.51), pouch=(0.4, 0.27, 0.15))),
    P(name="villager_guard", gender=1.0, age=28, race={"caucasian": 0.8, "asian": 0.2}, eye="eye_grey", body_budget=1800, hair_locks=0.3, skirt_budget=380,
      muscle=0.75, weight=0.52, height=0.6, proportions=0.72, seed=2003,
      outfit=["gambeson", "belt", "trousers", "boots", "breastplate", "vest", "pauldrons", "bracers", "gorget"],
      hair="short", pouch=False, vest_len=0.16, vest_key="vest", vest_offset=0.03, vest_trim="trim",
      armor_key="armor", emblem="tower_crown",
      extras={"chin/chin-jaw-drop-incr": 0.15, "nose/nose-hump-incr": 0.3},
      palette=dict(gambeson=(0.16, 0.17, 0.2), vest=(0.5, 0.07, 0.08), trim=(0.78, 0.63, 0.22),
                   trousers=(0.2, 0.19, 0.2), belt=(0.26, 0.16, 0.09), boots=(0.26, 0.18, 0.11),
                   hair=(0.18, 0.13, 0.09), armor=(0.62, 0.64, 0.67))),
    P(name="villager_smith", gender=0.0, age=40, race={"african": 0.9, "caucasian": 0.1},
      muscle=0.7, weight=0.5, height=0.52, proportions=0.7, seed=2004,
      outfit=["tunic", "apron_full", "trousers", "boots"], hair="bun", sleeve=0.4, tunic_tile="linen",
      no_belt=True, apron_key="apron",
      extras={"nose/nose-flaring-incr": 0.2},
      palette=dict(tunic=(0.82, 0.74, 0.58), trousers=(0.32, 0.35, 0.38), belt=(0.24, 0.14, 0.08),
                   boots=(0.3, 0.2, 0.13), hair=(0.05, 0.045, 0.04), apron=(0.32, 0.16, 0.09))),
    P(name="villager_healer", gender=0.0, age=60, race={"caucasian": 0.6, "asian": 0.4},
      muscle=0.35, weight=0.5, height=0.42, proportions=0.5, seed=2005,
      outfit=["dress", "undersleeve", "belt", "mantle", "boots"], hair="long", hair_do="silver_braid", sleeve=0.35,
      undersleeve_key="undersleeve", mantle_key="mantle", pouch_count=2,
      extras={"head/head-age-incr": 0.4},
      palette=dict(dress=(0.48, 0.55, 0.4), undersleeve=(0.92, 0.88, 0.78), mantle=(0.35, 0.24, 0.15),
                   belt=(0.28, 0.18, 0.1), boots=(0.3, 0.2, 0.13), hair=(0.75, 0.75, 0.74),
                   pouch=(0.32, 0.2, 0.11))),
    P(name="villager_baker", gender=0.0, age=30, race={"caucasian": 0.9, "asian": 0.1}, eye="eye_green",
      muscle=0.42, weight=0.5, height=0.5, proportions=0.75, seed=2006,
      outfit=["dress", "laces", "undersleeve", "apron", "belt", "boots"], hair="long", hair_do="crown", sleeve=0.5,
      undersleeve_key="undersleeve", pouch_count=1,
      extras={"eyebrows/eyebrows-angle-up": 0.15},
      palette=dict(dress=(0.35, 0.47, 0.72), undersleeve=(0.93, 0.9, 0.82), apron=(0.88, 0.84, 0.72),
                   belt=(0.3, 0.2, 0.12), boots=(0.32, 0.22, 0.15), hair=(0.55, 0.28, 0.14),
                   pouch=(0.34, 0.22, 0.14))),
]


# ============================================================ preview

def setup_scene_preview(objs, png, cam_loc, cam_target, lens=50, res=(1600, 700), ground=True, samples=64):
    import addon_utils
    addon_utils.enable("cycles")
    sc = bpy.context.scene
    for o in list(sc.objects):
        if o.type in ("CAMERA", "LIGHT") or o.name.startswith("PreviewGround"):
            bpy.data.objects.remove(o)
    if ground:
        bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
        g = bpy.context.active_object
        g.name = "PreviewGround"
        m = bpy.data.materials.new("PreviewGroundMat")
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*srgb2lin((0.45, 0.47, 0.36)), 1)
        b.inputs["Roughness"].default_value = 1.0
        g.data.materials.append(m)
    cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
    sc.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = cam_loc
    d = Vector(cam_target) - Vector(cam_loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.6
    sun.data.color = (1.0, 0.94, 0.84)
    sun.data.angle = math.radians(4)
    sun.rotation_euler = (math.radians(52), math.radians(6), math.radians(-38))
    sc.collection.objects.link(sun)
    fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
    fill.data.energy = 250
    fill.data.size = 6
    fill.location = (Vector(cam_loc) + Vector((-3, 0, 2)))
    fill.rotation_euler = (Vector(cam_target) - fill.location).to_track_quat("-Z", "Y").to_euler()
    sc.collection.objects.link(fill)
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*srgb2lin((0.66, 0.78, 0.92)), 1)
    bg.inputs["Strength"].default_value = 0.9
    sc.world = world
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 4
    sc.render.resolution_x, sc.render.resolution_y = res
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Base Contrast"
    except Exception:
        pass
    sc.render.filepath = png
    bpy.ops.render.render(write_still=True)
    print("preview", png)


def main():
    args = sys.argv[1:]
    only = None
    if "--only" in args:
        only = set(args[args.index("--only") + 1].split(","))
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    base = mh.BaseMesh()
    os.makedirs(OUT_DIR, exist_ok=True)
    paths = build_atlas(base) if "--no-atlas" not in args or not os.path.exists(os.path.join(TEX_DIR, "character_albedo.png")) \
        else {k: os.path.join(TEX_DIR, f"character_{k}.png") for k in ("albedo", "normal", "orm")}
    mat = make_material(paths)
    report = []
    built = []
    for r in RECIPES:
        if only and r["name"] not in only:
            continue
        ob, h = build_character(base, r, mat)
        decals = None
        decal_obj = None
        if r.get("emblem"):
            decal_obj = build_emblem(h, r)
            decal_obj.parent = ob            # follows ob if it's later moved/rotated for previews
            decals = [(decal_obj, r["emblem"] + ".png", "MASK")]
        out = os.path.join(OUT_DIR, r["name"] + ".glb")
        tris = export(ob, h, out, decals=decals)
        lod = ob.copy()
        lod.data = ob.data.copy()
        bpy.context.collection.objects.link(lod)
        decimate(lod, int(tris * 0.4))
        tris1 = export(lod, h, os.path.join(OUT_DIR, r["name"] + "_lod1.glb"), decals=decals)
        bpy.data.objects.remove(lod)
        report.append((r["name"], tris, tris1, h.native_height, h.native_scale))
        built.append((r["name"], ob, h))
        print(f"  wrote {out}: {tris} tris (lod1 {tris1}); natural height {h.native_height:.2f} m")
    # Merge into build_report.txt (don't clobber rows for variants not in this run: `--only`
    # builds a subset, and other variants' rows must stay byte-identical).
    report_path = os.path.join(OUT_DIR, "build_report.txt")
    rows = {}
    order = []
    if os.path.exists(report_path):
        with open(report_path) as f:
            next(f, None)
            for line in f:
                parts = line.split()
                if len(parts) == 5:
                    rows[parts[0]] = line if line.endswith("\n") else line + "\n"
                    order.append(parts[0])
    for row in report:
        line = "%s %d %d %.3f %.4f\n" % row
        if row[0] not in rows:
            order.append(row[0])
        rows[row[0]] = line
    with open(report_path, "w") as f:
        f.write("name  tris  lod1_tris  natural_height_m  metres_per_model_unit\n")
        for name in order:
            f.write(rows[name])
    if "--no-preview" in args:
        return
    if "--sheetout" in args:
        v2_sheet(built, args[args.index("--sheetout") + 1], tmp_dir="/tmp/claude-0/scr/_sheet_tmp")
        return
    if "--headsheet" in args:
        head_sheet(built, args[args.index("--headsheet") + 1], tmp_dir="/tmp/claude-0/scr/_head_tmp")
        return
    if "--v2sheet" in args:
        tag = args[args.index("--v2sheet") + 1]
        v2_sheet(built, os.path.join(PREVIEW_DIR, f"characters_v2_{tag}.png"),
                 tmp_dir=os.path.join("/tmp/claude-0/scratch", "_v2_tmp"))
        return
    if "--sixsheet" in args:
        six_sheet(built, os.path.join(PREVIEW_DIR, "characters_reference_six.png"))
        return
    lineup(built, "--closeups" in args, "--turn" in args)


def load_img_native(path):
    """Like load_img() but keeps the image's own resolution (no forced square scale)."""
    im = bpy.data.images.load(path, check_existing=False)
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(im)
    return a


def six_sheet(built, out_png, cell=(480, 860)):
    """Renders a front+back turntable of each built character and stitches
    them into one sheet: one column per character, front row on top, back
    row below (docs/kingdom/blender_previews/characters_reference_six.png)."""
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    tmp_dir = os.path.join(PREVIEW_DIR, "_six_tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    cw, ch = cell
    n = len(built)
    sheet = np.zeros((ch * 2, cw * n, 4), np.float32)
    for i, (name, ob, h) in enumerate(built):
        for _, o2, _ in built:
            hide = o2 is not ob
            o2.hide_render = hide
            for c in o2.children:        # e.g. a chest emblem decal parented to o2
                c.hide_render = hide
        world_h = h.head_top + 0.10       # ob has no scale applied: h.P is already in metres
        d = fit_camera(0.85, world_h * 1.12, cell, 50)
        base_rot = ob.rotation_euler.copy()
        for row, rz in enumerate((0, 180)):
            ob.rotation_euler = (base_rot[0], base_rot[1], base_rot[2] + math.radians(rz))
            tmp = os.path.join(tmp_dir, f"{name}_{row}.png")
            setup_scene_preview([], tmp, cam_loc=(0, -d, world_h * 0.5), cam_target=(0, 0, world_h * 0.5),
                                lens=50, res=cell, samples=40)
            img = load_img_native(tmp)
            sheet[row * ch:(row + 1) * ch, i * cw:(i + 1) * cw] = img
        ob.rotation_euler = base_rot
    for _, o2, _ in built:
        o2.hide_render = False
        for c in o2.children:
            c.hide_render = False
    save_png(sheet, out_png)
    print("wrote", out_png)


QUICK = os.environ.get('V2_QUICK') == '1'
FACEONLY = os.environ.get('V2_FACEONLY') == '1'


def v2_sheet(built, out_png, cell=(460, 800), face=(460, 460), tmp_dir=None, samples=36):
    """Front / back / face close-up per character (characters_v2_*.png)."""
    tmp_dir = tmp_dir or os.path.join(os.path.dirname(out_png), "_v2_tmp")
    os.makedirs(tmp_dir, exist_ok=True)
    cw, ch = cell
    fw, fh = face
    n = len(built)
    sheet = np.zeros((ch * 2 + fh, cw * n, 4), np.float32)
    sheet[..., 3] = 1
    for i, (name, ob, h) in enumerate(built):
        for _, o2, _ in built:
            hide = o2 is not ob
            o2.hide_render = hide
            for c in o2.children:
                c.hide_render = hide
        world_h = h.head_top + 0.10
        d = fit_camera(1.2, world_h * 1.12, cell, 50)
        base_rot = ob.rotation_euler.copy()
        for row, rz in enumerate((0, 180)):
            if (QUICK and row == 1) or FACEONLY:
                continue
            ob.rotation_euler = (base_rot[0], base_rot[1], base_rot[2] + math.radians(rz))
            tmp = os.path.join(tmp_dir, f"{name}_{row}.png")
            setup_scene_preview([], tmp, cam_loc=(0.0, -d, world_h * 0.5), cam_target=(0, 0, world_h * 0.5),
                                lens=50, res=cell, samples=samples)
            sheet[row * ch:(row + 1) * ch, i * cw:(i + 1) * cw] = load_img_native(tmp)
        ob.rotation_euler = base_rot
        ez = (h.eye_l[2] + h.eye_r[2]) / 2
        tmp = os.path.join(tmp_dir, f"{name}_face.png")
        setup_scene_preview([], tmp, cam_loc=(0.16, -0.62, ez + 0.02), cam_target=(0, h.head_c[1], ez - 0.03),
                            lens=85, res=(fw, fh), samples=samples + 8)
        img = load_img_native(tmp)
        y0 = ch * 2
        sheet[y0:y0 + fh, i * cw:i * cw + fw] = img
    for _, o2, _ in built:
        o2.hide_render = False
        for c in o2.children:
            c.hide_render = False
    save_png(sheet, out_png)
    print("wrote", out_png)
    import shutil
    shutil.rmtree(tmp_dir, ignore_errors=True)


def head_sheet(built, out_png, tmp_dir, res=(360, 360), angles=(0, 60, 90, 135, 180)):
    """Head close-ups from several angles (rows = characters) to judge hair against the ears."""
    import shutil
    os.makedirs(tmp_dir, exist_ok=True)
    rows = []
    for name, ob, h in built:
        for _, o2, _ in built:
            hide = o2 is not ob
            o2.hide_render = hide
            for c in o2.children:
                c.hide_render = hide
        ez = (h.eye_l[2] + h.eye_r[2]) / 2
        base_rot = ob.rotation_euler.copy()
        cells = []
        for a in angles:
            ob.rotation_euler = (base_rot[0], base_rot[1], base_rot[2] + math.radians(a))
            tmp = os.path.join(tmp_dir, f"{name}_{a}.png")
            setup_scene_preview([], tmp, cam_loc=(0.0, -0.75, ez - 0.02), cam_target=(0, h.head_c[1], ez - 0.04),
                                lens=75, res=res, samples=24)
            cells.append(load_img_native(tmp))
        ob.rotation_euler = base_rot
        rows.append(np.concatenate(cells, axis=1))
    save_png(np.concatenate(rows, axis=0), out_png)
    shutil.rmtree(tmp_dir, ignore_errors=True)
    print("wrote", out_png)


def fit_camera(W, H, res, lens, elev=0.0):
    a = res[0] / res[1]
    if a >= 1:
        hf = 2 * math.atan(18 / lens); vf = 2 * math.atan(math.tan(hf / 2) / a)
    else:
        vf = 2 * math.atan(18 / lens); hf = 2 * math.atan(math.tan(vf / 2) * a)
    return max((H / 2) / math.tan(vf / 2), (W / 2) / math.tan(hf / 2)) * 1.08


def lineup(built, closeups, turnaround=False):
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    n = len(built)
    gap = 0.8
    for i, (name, ob, h) in enumerate(built):
        ob.location.x = (i - (n - 1) / 2) * gap
        s = h.native_scale              # natural relative sizes
        ob.scale = (s, s, s)
    if turnaround:
        # front, 3/4, side and back views of each character (debug)
        for name, ob, h in built:
            s = h.native_scale
            views = []
            for k, rz in enumerate((0, 35, 90, 180)):
                c = ob.copy()
                bpy.context.collection.objects.link(c)
                c.location = ((k - 1.5) * 0.9, 0, 0)
                c.rotation_euler = (0, 0, math.radians(rz))
                views.append(c)
            ob.hide_render = True
            for o2, _, _ in [(b[1], 0, 0) for b in built if b[1] is not ob]:
                o2.hide_render = True
            res = (1600, 900)
            d = fit_camera(3.6, 2.0, res, 50)
            setup_scene_preview([], os.path.join(PREVIEW_DIR, f"characters_turn_{name}.png"),
                                cam_loc=(0, -d, 1.0), cam_target=(0, 0, 0.95), lens=50, res=res, samples=24)
            for c in views:
                bpy.data.objects.remove(c)
            ob.hide_render = False
            for b in built:
                b[1].hide_render = False
        return
    res = (2000, 760)
    width = n * gap + 0.4
    d = fit_camera(width, 2.05, res, 50)
    setup_scene_preview([b[1] for b in built], os.path.join(PREVIEW_DIR, "characters.png"),
                        cam_loc=(0, -d, 1.25), cam_target=(0, 0, 0.95), lens=50, res=res, samples=64)
    if closeups:
        for i, (name, ob, h) in enumerate(built):
            x = ob.location.x
            s = h.native_scale
            hz = h.eye_l[2] * s
            for o2 in [b[1] for b in built]:
                o2.hide_render = o2 is not ob
            setup_scene_preview([], os.path.join(PREVIEW_DIR, f"characters_face_{name}.png"),
                                cam_loc=(x + 0.25, -1.0, hz + 0.02), cam_target=(x, 0, hz - 0.04), lens=85,
                                res=(600, 600), samples=48)
            setup_scene_preview([], os.path.join(PREVIEW_DIR, f"characters_body_{name}.png"),
                                cam_loc=(x + 0.9, -3.2, 1.2 * s + 0.3), cam_target=(x, 0, 0.85 * s / 1.0 * 1.0), lens=50,
                                res=(600, 900), samples=48)
        for o2 in [b[1] for b in built]:
            o2.hide_render = False


if __name__ == "__main__":
    main()
