"""Generates the textures used by the procedural nature set (make_nature.py).

Run from anywhere:  python3 make_nature_textures.py [out_dir]
(default out_dir: kingdom/assets/generated/nature/textures). Needs numpy and the
bpy module (Blender 5.x, used only to read/scale/write images - no PIL needed).

Outputs (all CC0 / generated):
  bark_oak_color.jpg, bark_oak_normal.jpg     ambientCG Bark001 (CC0), 2K -> 1K
  bark_pine_color.jpg, bark_pine_normal.jpg   ambientCG Bark012 (CC0), 2K -> 1K
  bark_birch_color.png, bark_birch_normal.png generated: white birch, lenticels, dark marks
  leaves_broadleaf.png  1024^2 RGBA atlas, 2x2 cells of leafy sprigs (twig enters at the
                        bottom centre of each cell):  [0] oak A  [1] oak B
                                                       [2] birch [3] hazel / generic bush
                        (cell index: 0 = bottom-left, 1 = bottom-right, 2 = top-left, 3 = top-right)
  needles_conifer.png   1024^2 RGBA atlas: [0],[1] Scots-pine brush tufts, [2],[3] spruce sprays
  meadow_atlas.png      1024^2 RGBA atlas: bottom row 2 cells of grass blades (512x512 each:
                        [0] short, [1] tall); top row 4 cells of 256x512 wildflowers:
                        daisy (white), buttercup (yellow), cornflower (blue), campion (pink).
                        Blades run from a dark base (bottom edge) to light tips.
Leaf / needle / grass textures are drawn bright-ish on purpose: the meshes multiply them by a
per-vertex tint + fake ambient occlusion (COLOR_0) for trees, see make_nature.py.
Transparent texels carry dilated leaf colour so mipmaps don't grow dark fringes.
"""
import os, sys, math
import numpy as np
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ACG = os.path.join(ROOT, "kingdom", "assets", "incoming", "ambientcg")
OUT = next((a for a in sys.argv[1:] if not a.startswith("-")),
           os.path.join(ROOT, "kingdom", "assets", "generated", "nature", "textures"))


# ----------------------------------------------------------------------------- image io
def save_png(path, rgba):
    """rgba: float array (H, W, 3|4) in 0..1, row 0 = TOP of the image."""
    h, w = rgba.shape[:2]
    if rgba.shape[2] == 3:
        rgba = np.concatenate([rgba, np.ones((h, w, 1))], axis=2)
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.pixels.foreach_set(np.clip(rgba[::-1], 0, 1).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    print("wrote", path)


def resize_copy(src, dst, size=1024, normal=False):
    img = bpy.data.images.load(src)
    if normal:
        img.colorspace_settings.name = "Non-Color"
    img.scale(size, size)
    img.filepath_raw = dst
    img.file_format = "JPEG"
    img.save()
    bpy.data.images.remove(img)
    print("wrote", dst)


# ----------------------------------------------------------------------------- helpers
def tile_noise(h, w, beta=2.0, seed=0, ax=1.0, ay=1.0):
    """Seamlessly tiling 1/f^beta noise in 0..1 (ax/ay stretch the spectrum)."""
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None] * ay
    fx = np.fft.fftfreq(w)[None, :] * ax
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    F *= f ** (-beta / 2)
    F[0, 0] = 0
    n = np.real(np.fft.ifft2(F))
    return (n - n.min()) / (n.max() - n.min())


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


class Canvas:
    """RGB + alpha float canvas, row 0 = TOP. Coordinates (x right, y DOWN) in pixels."""

    def __init__(self, w, h, bg=(0.2, 0.3, 0.1)):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3)) + np.array(bg)
        self.a = np.zeros((h, w))
        self.mottle = 0.86 + 0.28 * tile_noise(h, w, 2.2, seed=99)

    def region(self, x0, y0, x1, y1, clip):
        cx0, cy0, cx1, cy1 = clip
        x0, y0 = max(int(x0), cx0), max(int(y0), cy0)
        x1, y1 = min(int(x1) + 1, cx1), min(int(y1) + 1, cy1)
        if x1 <= x0 or y1 <= y0:
            return None
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float64) + 0.5
        return (slice(y0, y1), slice(x0, x1)), xs, ys

    def over(self, sl, col, al):
        al = np.clip(al, 0, 1)
        self.rgb[sl] = self.rgb[sl] * (1 - al[..., None]) + col * al[..., None]
        self.a[sl] = self.a[sl] + al * (1 - self.a[sl])

    def disc_path(self, pts, radii, cols, clip):
        """Stamp a tapered stroke along a polyline (pts Nx2, radii N, cols Nx3)."""
        pts = np.asarray(pts, float)
        for i in range(len(pts) - 1):
            self.segment(pts[i], pts[i + 1], radii[i], radii[i + 1], cols[i], cols[i + 1], clip)

    def segment(self, p0, p1, r0, r1, c0, c1, clip, shade_edge=0.25):
        rmax = max(r0, r1) + 1.5
        reg = self.region(min(p0[0], p1[0]) - rmax, min(p0[1], p1[1]) - rmax,
                          max(p0[0], p1[0]) + rmax, max(p0[1], p1[1]) + rmax, clip)
        if reg is None:
            return
        sl, xs, ys = reg
        d = np.array(p1) - np.array(p0)
        L2 = max(d @ d, 1e-6)
        t = np.clip(((xs - p0[0]) * d[0] + (ys - p0[1]) * d[1]) / L2, 0, 1)
        px, py = p0[0] + t * d[0], p0[1] + t * d[1]
        dist = np.hypot(xs - px, ys - py)
        r = r0 + (r1 - r0) * t
        al = np.clip(r - dist + 0.5, 0, 1)
        col = np.array(c0) + (np.array(c1) - np.array(c0)) * t[..., None]
        edge = np.clip(dist / np.maximum(r, 0.5), 0, 1)
        col = col * (1 - shade_edge * edge[..., None] ** 2)
        self.over(sl, col, al)

    def finish(self):
        """Dilate colour into transparent texels (premultiplied pyramid fill)."""
        rgb, a = self.rgb.copy(), self.a.copy()
        prem, al = rgb * a[..., None], a.copy()
        levels = []
        while min(prem.shape[:2]) > 4:
            levels.append((prem, al))
            h, w = prem.shape[0] // 2 * 2, prem.shape[1] // 2 * 2
            prem = prem[:h, :w].reshape(h // 2, 2, w // 2, 2, 3).mean((1, 3))
            al = al[:h, :w].reshape(h // 2, 2, w // 2, 2).mean((1, 3))
        fill = prem / np.maximum(al, 1e-6)[..., None]
        for prem_l, al_l in reversed(levels):
            up = np.repeat(np.repeat(fill, 2, 0), 2, 1)[:prem_l.shape[0], :prem_l.shape[1]]
            mine = prem_l / np.maximum(al_l, 1e-6)[..., None]
            k = np.clip(al_l * 4, 0, 1)[..., None]
            fill = mine * k + up * (1 - k)
        k = a[..., None]
        out = rgb * k + fill * (1 - k)
        return np.concatenate([out, a[..., None]], axis=2)


# ----------------------------------------------------------------------------- leaves
def shape_oak(u):
    uc = np.clip(u, 0, 1)
    base = 0.53 * uc ** 0.55 * (1 - uc) ** 0.33
    lobes = 0.58 + 0.42 * np.abs(np.sin(np.pi * (uc * 4.6 + 0.08))) ** 0.55
    return np.where((u > 0) & (u < 1), base * lobes, -1)


def shape_birch(u):
    uc = np.clip(u, 0, 1)
    base = 0.95 * uc ** 0.42 * (1 - uc) ** 1.05
    serr = 1 + 0.07 * (np.abs(np.sin(uc * np.pi * 16)) - 0.5)
    return np.where((u > 0) & (u < 1), base * serr, -1)


def shape_hazel(u):
    uc = np.clip(u, 0, 1)
    base = 0.62 * uc ** 0.5 * (1 - uc) ** 0.75
    serr = 1 + 0.05 * (np.abs(np.sin(uc * np.pi * 22)) - 0.5)
    return np.where((u > 0) & (u < 1), base * serr, -1)


def draw_leaf(cv, cx, cy, ang, L, shape, col, clip, rng, shade=1.0, veins=7):
    """Leaf with petiole at (cx, cy) pointing along angle ang (radians, y down)."""
    r = L * 1.1
    reg = cv.region(cx - r, cy - r, cx + r, cy + r, clip)
    if reg is None:
        return
    sl, xs, ys = reg
    dx, dy = xs - cx, ys - cy
    ca, sa = math.cos(ang), math.sin(ang)
    u = (dx * ca + dy * sa) / L
    v = (-dx * sa + dy * ca) / L
    bend = rng.uniform(-0.12, 0.12)          # curved midrib
    v = v - bend * u * u
    u2 = (u + 0.12) / 1.12                   # leaf blade starts after the petiole
    w = shape(u2) * 1.12
    blade = np.clip((w - np.abs(v)) * L + 0.5, 0, 1)
    pet = np.clip(0.011 * L + 0.6 - np.abs(v) * L, 0, 1) * (u > -0.02) * (u < 0.16)
    al = np.maximum(blade, pet)
    if not al.any():
        return
    wsafe = np.maximum(w, 1e-3)
    edge = np.clip(np.abs(v) / wsafe, 0, 1)
    c = np.array(col) * shade
    g = c * (0.80 + 0.32 * np.clip(u2, 0, 1))[..., None]
    g = g * (1 - 0.22 * edge ** 2.5)[..., None]
    g = g * np.where(v > 0, 1.0, 0.88)[..., None]            # folded along midrib
    g = g * cv.mottle[sl][..., None]
    mid = np.clip(1.2 - np.abs(v) * L / (0.9 + 0.012 * L), 0, 1) * (u2 < 0.92)
    f = (np.clip(u2, 0, 1) - 0.85 * np.abs(v)) * veins
    dvein = np.abs(f - np.round(f)) * L / veins
    lat = np.clip(1.1 - dvein / (0.5 + 0.006 * L), 0, 1) * (edge < 0.85) * (np.abs(v) * L > 2)
    vein_c = c * np.array([1.25, 1.22, 0.95])
    g = g * (1 - 0.45 * lat[..., None]) + vein_c * 0.95 * 0.45 * lat[..., None]
    g = g * (1 - 0.75 * mid[..., None]) + vein_c * 1.1 * 0.75 * mid[..., None]
    pc = np.array([0.33, 0.30, 0.14]) * shade
    g = np.where((blade < 0.5)[..., None], pc, g)
    cv.over(sl, g, al)


def bezier(p0, p1, p2, n):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * np.array(p0) + 2 * (1 - t) * t * np.array(p1) + t * t * np.array(p2)


def sprig(cv, ox, oy, S, shape, base_col, rng, leaf_len, n_side=3, per_twig=5,
          tip_cluster=(3, 5), veins=7, col_var=0.10, twig_col=(0.30, 0.24, 0.17), spread=1.0):
    """A leafy twig filling cell (ox, oy, S) - twig enters at the bottom centre."""
    clip = (ox + 2, oy + 2, ox + S - 2, oy + S - 2)
    leaves = []   # (x, y, ang, L)

    def twig(p0, ang, length, r0, depth):
        tipx = p0[0] + math.cos(ang) * length
        tipy = p0[1] + math.sin(ang) * length
        side = rng.uniform(-0.25, 0.25) * length
        mid = ((p0[0] + tipx) / 2 - math.sin(ang) * side, (p0[1] + tipy) / 2 + math.cos(ang) * side)
        pts = bezier(p0, mid, (tipx, tipy), 14)
        radii = np.linspace(r0, max(1.2, r0 * 0.3), 14)
        cols = [np.array(twig_col) * rng.uniform(0.9, 1.1)] * 14
        cv.disc_path(pts, radii, cols, clip)
        # leaves along the twig, alternating sides
        n = per_twig if depth > 0 else max(2, per_twig - 1)
        for i in range(n):
            t = 0.25 + 0.6 * (i + rng.uniform(-0.3, 0.3)) / max(n - 1, 1)
            k = int(np.clip(t * 13, 0, 13))
            p = pts[k]
            d = pts[min(k + 1, 13)] - pts[max(k - 1, 0)]
            a0 = math.atan2(d[1], d[0])
            s = 1 if i % 2 == 0 else -1
            leaves.append((p[0], p[1], a0 + s * rng.uniform(0.6, 1.2) * spread,
                           leaf_len * rng.uniform(0.7, 1.05)))
        d = pts[-1] - pts[-3]
        a0 = math.atan2(d[1], d[0])
        nt = rng.integers(tip_cluster[0], tip_cluster[1] + 1)
        for j in range(nt):
            leaves.append((pts[-1][0], pts[-1][1], a0 + (j - (nt - 1) / 2) * 0.55 * spread
                           + rng.uniform(-0.15, 0.15), leaf_len * rng.uniform(0.85, 1.15)))
        return pts

    base = (ox + S / 2 + rng.uniform(-8, 8), oy + S - 3)
    main_ang = -math.pi / 2 + rng.uniform(-0.18, 0.18)
    pts = twig(base, main_ang, S * 0.66, 4.2, 0)
    for i in range(n_side):
        t = 0.22 + 0.55 * (i + rng.uniform(-0.2, 0.2)) / max(n_side - 1, 1)
        k = int(t * 13)
        s = 1 if i % 2 == 0 else -1
        twig(tuple(pts[k]), main_ang + s * rng.uniform(0.5, 0.85), S * rng.uniform(0.28, 0.38),
             2.6, 1)
    order = rng.permutation(len(leaves))
    for rank, i in enumerate(order):
        x, y, a, L = leaves[i]
        tx, ty = x + math.cos(a) * L, y + math.sin(a) * L
        m = L * 0.3
        if not (ox + m < tx < ox + S - m and oy + m < ty < oy + S - m):
            L *= 0.6          # shrink leaves that would poke out, drop if still out
            tx, ty = x + math.cos(a) * L, y + math.sin(a) * L
            if not (ox + m < tx < ox + S - m and oy + m < ty < oy + S - m):
                continue
        shade = 0.72 + 0.28 * rank / max(len(order) - 1, 1)     # later = on top = brighter
        c = np.array(base_col) * (1 + rng.uniform(-col_var, col_var))
        c[0] *= 1 + rng.uniform(-col_var, col_var) * 1.5          # yellow/blue-green variation
        draw_leaf(cv, x, y, a, L, shape, c, clip, rng, shade, veins)


def make_leaf_atlas(path):
    S = 512
    cv = Canvas(2 * S, 2 * S, bg=(0.25, 0.33, 0.12))
    rng = np.random.default_rng(11)
    # cells: y=S row is the BOTTOM of the image (row 0 = top)  -> cell index as documented
    cells = {0: (0, S), 1: (S, S), 2: (0, 0), 3: (S, 0)}
    oak = (0.36, 0.50, 0.17)
    sprig(cv, *cells[0], S, shape_oak, oak, rng, leaf_len=92, n_side=3, per_twig=4,
          tip_cluster=(4, 6), veins=6)
    sprig(cv, *cells[1], S, shape_oak, (0.40, 0.52, 0.18), rng, leaf_len=84, n_side=4, per_twig=4,
          tip_cluster=(4, 5), veins=6)
    sprig(cv, *cells[2], S, shape_birch, (0.50, 0.62, 0.20), rng, leaf_len=58, n_side=5,
          per_twig=6, tip_cluster=(2, 3), veins=8, twig_col=(0.28, 0.20, 0.16), spread=0.8)
    sprig(cv, *cells[3], S, shape_hazel, (0.38, 0.54, 0.19), rng, leaf_len=84, n_side=3,
          per_twig=4, tip_cluster=(2, 3), veins=7)
    save_png(path, cv.finish())


# ----------------------------------------------------------------------------- needles
def needle(cv, p, ang, L, w, c0, c1, clip):
    q = (p[0] + math.cos(ang) * L, p[1] + math.sin(ang) * L)
    cv.segment(p, q, w, w * 0.45, c0, c1, clip, shade_edge=0.35)


def pine_tuft(cv, ox, oy, S, rng):
    clip = (ox + 2, oy + 2, ox + S - 2, oy + S - 2)
    dark, light = np.array([0.15, 0.25, 0.14]), np.array([0.32, 0.43, 0.22])
    shoots = []
    base = (ox + S / 2 + rng.uniform(-6, 6), oy + S - 3)
    a = -math.pi / 2 + rng.uniform(-0.12, 0.12)
    shoots.append((base, a, S * 0.55, 4.5))
    for s in (-1, 1):
        k = rng.uniform(0.25, 0.4)
        p = (base[0] + math.cos(a) * S * 0.55 * k, base[1] + math.sin(a) * S * 0.55 * k)
        shoots.append((p, a + s * rng.uniform(0.5, 0.8), S * rng.uniform(0.33, 0.42), 3.0))
    for p0, ang, length, r in shoots:
        tip = (p0[0] + math.cos(ang) * length, p0[1] + math.sin(ang) * length)
        cv.segment(p0, tip, r, r * 0.5, (0.36, 0.22, 0.13), (0.42, 0.28, 0.16), clip)
        n = int(length * 0.9)
        for i in range(n):
            t = (i / n) ** 0.6                               # denser toward the tip
            if t < 0.18:
                continue
            p = (p0[0] + (tip[0] - p0[0]) * t, p0[1] + (tip[1] - p0[1]) * t)
            side = rng.choice([-1, 1])
            spread = rng.uniform(0.35, 0.95) * (1.25 - 0.4 * t)
            Ln = S * rng.uniform(0.11, 0.17)
            shade = rng.uniform(0.75, 1.1)
            old = rng.random() < 0.04
            c0 = (np.array([0.40, 0.33, 0.16]) if old else dark) * shade
            c1 = (np.array([0.55, 0.45, 0.22]) if old else light) * shade
            needle(cv, p, ang + side * spread, Ln, rng.uniform(1.3, 1.9), c0, c1, clip)
        for j in range(26):                                   # terminal brush
            aa = ang + rng.uniform(-1.3, 1.3)
            needle(cv, tip, aa, S * rng.uniform(0.09, 0.15), 1.6, dark * 1.05, light * 1.1, clip)
        cv.segment((tip[0] - math.cos(ang) * 6, tip[1] - math.sin(ang) * 6), tip, 3.2, 2.4,
                   (0.45, 0.30, 0.18), (0.52, 0.36, 0.22), clip)   # bud


def spruce_spray(cv, ox, oy, S, rng):
    clip = (ox + 2, oy + 2, ox + S - 2, oy + S - 2)
    dark, light = np.array([0.12, 0.22, 0.13]), np.array([0.26, 0.38, 0.22])
    base = (ox + S / 2 + rng.uniform(-6, 6), oy + S - 3)
    a = -math.pi / 2 + rng.uniform(-0.1, 0.1)
    length = S * 0.9

    def shoot(p0, ang, length, r, depth):
        tip = (p0[0] + math.cos(ang) * length, p0[1] + math.sin(ang) * length)
        cv.segment(p0, tip, r, r * 0.4, (0.34, 0.24, 0.15), (0.38, 0.27, 0.17), clip)
        n = int(length / 2.2)
        for i in range(n):
            t = i / n
            p = (p0[0] + (tip[0] - p0[0]) * t, p0[1] + (tip[1] - p0[1]) * t)
            for side in (-1, 1):
                sh = rng.uniform(0.75, 1.1)
                needle(cv, p, ang + side * rng.uniform(0.6, 1.2), S * rng.uniform(0.035, 0.05),
                       1.4, dark * sh, light * sh, clip)
        if depth == 0:
            k = 0.08
            s = 1
            while k < 0.9:
                p = (p0[0] + (tip[0] - p0[0]) * k, p0[1] + (tip[1] - p0[1]) * k)
                shoot(p, ang + s * rng.uniform(0.75, 1.0), length * (0.42 * (1 - k) + 0.06), 2.0, 1)
                s = -s
                k += rng.uniform(0.07, 0.11)
    shoot(base, a, length, 3.5, 0)


def make_needle_atlas(path):
    S = 512
    cv = Canvas(2 * S, 2 * S, bg=(0.18, 0.28, 0.15))
    rng = np.random.default_rng(23)
    pine_tuft(cv, 0, S, S, rng)
    pine_tuft(cv, S, S, S, rng)
    spruce_spray(cv, 0, 0, S, rng)
    spruce_spray(cv, S, 0, S, rng)
    save_png(path, cv.finish())


# ----------------------------------------------------------------------------- meadow
def blade(cv, x0, y0, height, width, bend, clip, rng, base_c, tip_c, n=24):
    t = np.linspace(0, 1, n)
    xs = x0 + bend * height * t ** 2
    ys = y0 - height * t
    radii = width * (1 - t) ** 0.85 + 0.6
    cols = [base_c + (tip_c - base_c) * (tt ** 0.8) for tt in t]
    for i in range(n - 1):
        cv.segment((xs[i], ys[i]), (xs[i + 1], ys[i + 1]), radii[i], radii[i + 1], cols[i], cols[i + 1],
                   clip, shade_edge=0.08)


def grass_cell(cv, ox, oy, W, H, rng, n, hmin, hmax, wmax):
    clip = (ox + 1, oy + 2, ox + W - 1, oy + H)
    for i in range(n):
        x0 = ox + W * (0.12 + 0.76 * rng.random())
        h = H * rng.uniform(hmin, hmax)
        dry = rng.random() < 0.18
        base_c = np.array([0.10, 0.17, 0.05]) * rng.uniform(0.85, 1.1)
        tip_c = (np.array([0.62, 0.62, 0.32]) if dry else np.array([0.46, 0.62, 0.22])) \
            * rng.uniform(0.85, 1.12)
        bend = rng.uniform(-0.35, 0.35) * (1 if abs(x0 - ox - W / 2) > 0 else 1)
        bend += (x0 - ox - W / 2) / W * 0.5                    # splay outward
        blade(cv, x0, oy + H + 2, h, rng.uniform(0.45, 1.0) * wmax, bend, clip, rng, base_c, tip_c)


def flower_head(cv, cx, cy, kind, R, clip, rng):
    if kind == "daisy":
        for k in range(14):
            a = k / 14 * 2 * math.pi + rng.uniform(-0.1, 0.1)
            q = (cx + math.cos(a) * R, cy + math.sin(a) * R * 0.75)
            cv.segment((cx, cy), q, R * 0.22, R * 0.18, (0.93, 0.93, 0.90), (1.0, 1.0, 0.98), clip, 0.3)
        cv.segment((cx - 0.5, cy), (cx + 0.5, cy), R * 0.36, R * 0.36, (0.92, 0.72, 0.12),
                   (0.95, 0.78, 0.2), clip, 0.5)
    elif kind == "buttercup":
        for k in range(5):
            a = k / 5 * 2 * math.pi + rng.uniform(-0.2, 0.2)
            q = (cx + math.cos(a) * R * 0.6, cy + math.sin(a) * R * 0.5)
            cv.segment((cx, cy), q, R * 0.42, R * 0.5, (0.85, 0.66, 0.05), (1.0, 0.86, 0.15), clip, 0.3)
        cv.segment((cx - 0.5, cy), (cx + 0.5, cy), R * 0.2, R * 0.2, (0.7, 0.6, 0.1), (0.8, 0.7, 0.2), clip)
    elif kind == "cornflower":
        for k in range(11):
            a = k / 11 * 2 * math.pi + rng.uniform(-0.15, 0.15)
            q = (cx + math.cos(a) * R, cy + math.sin(a) * R * 0.7)
            cv.segment((cx, cy), q, R * 0.18, R * 0.30, (0.22, 0.30, 0.70), (0.35, 0.50, 0.95), clip, 0.3)
        cv.segment((cx - 0.5, cy), (cx + 0.5, cy), R * 0.28, R * 0.28, (0.20, 0.15, 0.40),
                   (0.25, 0.2, 0.5), clip)
    else:  # campion
        for k in range(5):
            a = k / 5 * 2 * math.pi + rng.uniform(-0.2, 0.2)
            q = (cx + math.cos(a) * R * 0.7, cy + math.sin(a) * R * 0.55)
            cv.segment((cx, cy), q, R * 0.3, R * 0.45, (0.72, 0.22, 0.42), (0.92, 0.42, 0.62), clip, 0.3)
        cv.segment((cx - 0.5, cy), (cx + 0.5, cy), R * 0.16, R * 0.16, (0.9, 0.85, 0.85), (1, 1, 1), clip)


def flower_cell(cv, ox, oy, W, H, kind, rng):
    clip = (ox + 1, oy + 2, ox + W - 1, oy + H)
    grass_cell(cv, ox, oy, W, H, rng, 7, 0.18, 0.45, 5)
    stem_c = np.array([0.20, 0.32, 0.10])
    for i in range(rng.integers(3, 5)):
        x0 = ox + W * (0.22 + 0.56 * rng.random())
        h = H * rng.uniform(0.45, 0.88)
        bend = rng.uniform(-0.25, 0.25)
        t = np.linspace(0, 1, 18)
        xs, ys = x0 + bend * h * t ** 2, oy + H + 2 - h * t
        cv.disc_path(np.stack([xs, ys], 1), np.linspace(2.4, 1.5, 18), [stem_c * 0.8, *[stem_c] * 17], clip)
        for j in range(2):   # small stem leaves
            k = rng.integers(3, 9)
            s = 1 if j == 0 else -1
            draw_leaf(cv, xs[k], ys[k], -math.pi / 2 + s * 0.9, H * 0.09, shape_hazel,
                      (0.28, 0.42, 0.14), clip, rng, 0.9, 4)
        R = {"daisy": 27, "buttercup": 21, "cornflower": 24, "campion": 23}[kind] * rng.uniform(0.85, 1.15)
        flower_head(cv, xs[-1], ys[-1] - R * 0.3, kind, R, clip, rng)


def make_meadow_atlas(path):
    cv = Canvas(1024, 1024, bg=(0.25, 0.35, 0.12))
    rng = np.random.default_rng(5)
    grass_cell(cv, 0, 512, 512, 512, rng, 46, 0.45, 0.95, 9)       # [0] short (bottom-left)
    grass_cell(cv, 512, 512, 512, 512, rng, 40, 0.60, 0.99, 10)    # [1] tall  (bottom-right)
    for i, kind in enumerate(["daisy", "buttercup", "cornflower", "campion"]):
        flower_cell(cv, i * 256, 0, 256, 512, kind, rng)
    save_png(path, cv.finish())


# ----------------------------------------------------------------------------- birch bark
def make_birch_bark(path_col, path_nrm, W=1024, H=1024):
    """u = around the trunk (x), v = along it (y). Tiles in both directions."""
    rng = np.random.default_rng(3)
    base = np.array([0.86, 0.85, 0.80])
    n1 = tile_noise(H, W, 2.4, seed=1, ax=0.35, ay=1.0)       # horizontal streaks
    n2 = tile_noise(H, W, 1.6, seed=2)
    col = base * (0.86 + 0.16 * n1[..., None]) * (0.94 + 0.08 * n2[..., None])
    col = col * np.where(n2[..., None] > 0.62, np.array([0.97, 0.93, 0.86]), 1.0)  # warm peel
    height = 0.5 + 0.2 * n1
    ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)

    def wrap_d(a, b, period):
        d = np.abs(a - b)
        return np.minimum(d, period - d)

    # lenticels: thin dark horizontal dashes
    for i in range(170):
        cx, cy = rng.uniform(0, W), rng.uniform(0, H)
        lw, lh = rng.uniform(10, 55), rng.uniform(1.0, 2.6)
        x0, x1 = int(cx - lw - 3), int(cx + lw + 3)
        y0, y1 = int(cy - lh - 3), int(cy + lh + 3)
        yy = np.arange(y0, y1) % H
        xx = np.arange(x0, x1) % W
        dx = wrap_d(xs[np.ix_(yy, xx)], cx, W) / lw
        dy = wrap_d(ys[np.ix_(yy, xx)], cy, H) / lh
        m = np.clip((1 - np.sqrt(dx ** 2 + dy ** 2)) * 3, 0, 1)
        dark = rng.uniform(0.35, 0.8)
        sub = col[np.ix_(yy, xx)]
        col[np.ix_(yy, xx)] = sub * (1 - m[..., None]) + np.array([0.36, 0.33, 0.30]) * dark * m[..., None] + sub * (1 - dark) * m[..., None]
        height[np.ix_(yy, xx)] -= 0.25 * m
    # dark blotches and branch "eyes"
    blot = tile_noise(H, W, 2.6, seed=7, ax=0.6, ay=1.0)
    m = smooth(0.70, 0.80, blot)
    col = col * (1 - 0.85 * m[..., None]) + np.array([0.12, 0.11, 0.10]) * 0.85 * m[..., None]
    height -= 0.3 * m
    for i in range(3):
        cx, cy = rng.uniform(0, W), rng.uniform(0, H)
        dx = wrap_d(xs, cx, W) / 60
        dy = (ys - cy) / 40
        chevron = smooth(0.25, 0.1, np.abs(dy + 0.55 * np.abs(dx) ** 1.2)) * smooth(1.6, 0.6, np.abs(dx))
        chevron *= (np.abs(ys - cy) < 150)
        col = col * (1 - 0.9 * chevron[..., None]) + np.array([0.08, 0.07, 0.07]) * 0.9 * chevron[..., None]
        height -= 0.3 * chevron
    save_png(path_col, np.clip(col, 0, 1))
    # normal map (OpenGL, +Y up the image). Image row 0 is the top -> flip dy.
    s = 6.0
    gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5
    gy = -(np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5
    n = np.stack([-gx * s, -gy * s, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    save_png(path_nrm, n * 0.5 + 0.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = [a[2:] for a in sys.argv[1:] if a.startswith("--") and a != "--"]
    def want(k):
        return not only or k in only
    if want("bark"):
        resize_copy(os.path.join(ACG, "Bark001", "Bark001_2K-JPG_Color.jpg"), os.path.join(OUT, "bark_oak_color.jpg"))
        resize_copy(os.path.join(ACG, "Bark001", "Bark001_2K-JPG_NormalGL.jpg"), os.path.join(OUT, "bark_oak_normal.jpg"), normal=True)
        resize_copy(os.path.join(ACG, "Bark012", "Bark012_2K-JPG_Color.jpg"), os.path.join(OUT, "bark_pine_color.jpg"))
        resize_copy(os.path.join(ACG, "Bark012", "Bark012_2K-JPG_NormalGL.jpg"), os.path.join(OUT, "bark_pine_normal.jpg"), normal=True)
    if want("birch"):
        make_birch_bark(os.path.join(OUT, "bark_birch_color.png"), os.path.join(OUT, "bark_birch_normal.png"))
    if want("leaves"):
        make_leaf_atlas(os.path.join(OUT, "leaves_broadleaf.png"))
    if want("needles"):
        make_needle_atlas(os.path.join(OUT, "needles_conifer.png"))
    if want("meadow"):
        make_meadow_atlas(os.path.join(OUT, "meadow_atlas.png"))


if __name__ == "__main__":
    main()
