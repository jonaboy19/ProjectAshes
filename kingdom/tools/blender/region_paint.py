"""Procedural hand-painted textures for the first-region asset sets (numpy, runs inside Blender 5.x).

Everything is painted from code (no downloads) so the look can be re-tuned and re-run:

  region/textures/foliage_atlas.png   1024 RGBA, 4 x 4 cells of 256 px, alpha-cut sprites:
      r0: oak_a, oak_b, beech, dark_forest     (leaf clusters, card centred)
      r1: spruce spray, pine spray, bush, berry bush
      r2: grass, grass_seed, flowers_warm, flowers_cool   (card base = cell bottom)
      r3: fern frond, bare twigs, hanging moss, wheat
  region/textures/bark_atlas.png      1024 RGB, 4 columns of 256 px, each column tiles in X within
      itself and in Y over the full height: 0 oak/beech bark, 1 pine bark, 2 dead silver bark,
      3 end grain (4 stacked 256 px ring tiles).
  region/textures/<name>.png          512 px tileable (repeat) textures: rock, moss, planks, timber,
      stone_wall, plaster, thatch, shingle, slate, iron, canvas, hay, soil.

Image arrays here are (rows, cols) with row 0 at the TOP; save() flips for Blender.
"""
import os, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
TEX = os.path.join(ROOT, "kingdom", "assets", "generated", "region", "textures")


def hx(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], dtype=np.float32)


def pal(*hs):
    return [hx(h) for h in hs]


def ramp(v, cols):
    """v in 0..1 (any shape) -> colours interpolated along the palette list."""
    v = np.clip(v, 0, 1) * (len(cols) - 1)
    i = np.clip(np.floor(v).astype(int), 0, len(cols) - 2)
    t = (v - i)[..., None]
    C = np.stack(cols)
    return C[i] * (1 - t) + C[i + 1] * t


def ramp1(v, cols):
    return ramp(np.array([v]), cols)[0]


def fnoise(h, w, fu, fv, rng, p=2.0):
    """Periodic band-limited noise (FFT filtered white noise), unit variance.
    fu/fv: cutoff frequency in cycles per pixel along x / y."""
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    wn = rng.standard_normal((h, w))
    f = np.exp(-((np.abs(fx) / fu) ** p + (np.abs(fy) / fv) ** p))
    f[0, 0] = 0
    r = np.real(np.fft.ifft2(np.fft.fft2(wn) * f))
    r -= r.mean()
    return (r / (r.std() + 1e-9)).astype(np.float32)


def norm(a, lo=1, hi=99):
    a0, a1 = np.percentile(a, lo), np.percentile(a, hi)
    return np.clip((a - a0) / (a1 - a0 + 1e-9), 0, 1)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------------------------ stamping
def stamp(rgb, a, x, y, ang, L, W, col, kind="leaf", curv=0.0, grad=(0.78, 1.12), side=0.1,
          wrap=False, alpha=1.0, rib=0.15):
    """Paint one stroke / leaf / blade from base (x, y) along angle `ang` (radians, image space:
    0 = +x, pi/2 = down). L length, W half-width in px. Alpha-over composite."""
    H, Wd = a.shape
    r = L + W + 2
    x0, x1 = int(math.floor(x - r)), int(math.ceil(x + r))
    y0, y1 = int(math.floor(y - r)), int(math.ceil(y + r))
    if not wrap:
        x0, x1 = max(0, x0), min(Wd, x1)
        y0, y1 = max(0, y0), min(H, y1)
        if x1 <= x0 or y1 <= y0:
            return
    X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    dx, dy = X - x, Y - y
    ca, sa = math.cos(ang), math.sin(ang)
    u = dx * ca + dy * sa
    v = -dx * sa + dy * ca
    t = u / L
    v = v - curv * L * t * t
    tc = np.clip(t, 0, 1)
    if kind == "leaf":
        prof = W * np.sin(np.pi * np.clip(tc * 0.92 + 0.04, 0, 1)) ** 0.7 * (1.05 - 0.35 * tc)
    elif kind == "blade":
        prof = W * (1 - tc) ** 0.85
    elif kind == "seg":
        prof = W * (1 - 0.45 * tc)
    elif kind == "oval":
        prof = W * np.sqrt(np.clip(1 - (2 * tc - 1) ** 2, 0, 1))
    else:
        prof = W * np.ones_like(tc)
    inside = prof - np.abs(v)
    ends = np.clip(np.minimum(u, L - u) + 0.6, 0, 1)
    m = np.clip(inside + 0.5, 0, 1) * ends * alpha
    shade = grad[0] + (grad[1] - grad[0]) * tc
    shade = shade * (1 + side * np.tanh(v / max(W * 0.4, 0.5)))
    if kind == "leaf" and W > 3 and rib:
        shade = shade * (1 - rib * np.exp(-(v / 0.9) ** 2) * (tc < 0.9))
    c = np.asarray(col, dtype=np.float32)[None, None, :] * shade[..., None]
    if wrap:
        ri = np.arange(y0, y1) % H
        ci = np.arange(x0, x1) % Wd
        ix = np.ix_(ri, ci)
        sub_rgb, sub_a = rgb[ix], a[ix]
        mm = m[..., None]
        rgb[ix] = c * mm + sub_rgb * (1 - mm)
        a[ix] = m + sub_a * (1 - m)
    else:
        mm = m[..., None]
        rgb[y0:y1, x0:x1] = c * mm + rgb[y0:y1, x0:x1] * (1 - mm)
        a[y0:y1, x0:x1] = m + a[y0:y1, x0:x1] * (1 - m)


def seg(rgb, a, p0, p1, w0, w1, col, **kw):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = max(1.0, math.hypot(dx, dy))
    stamp(rgb, a, p0[0], p0[1], math.atan2(dy, dx), L, w0, col, kind="seg", grad=(1.0, 1.0), side=0.15,
          **kw)


def disc(rgb, a, x, y, r, col, shade=0.25):
    H, W = a.shape
    x0, x1 = max(0, int(x - r - 2)), min(W, int(x + r + 2))
    y0, y1 = max(0, int(y - r - 2)), min(H, int(y + r + 2))
    if x1 <= x0 or y1 <= y0:
        return
    X, Y = np.meshgrid(np.arange(x0, x1) + 0.5, np.arange(y0, y1) + 0.5)
    d = np.hypot(X - x, Y - y)
    m = np.clip(r - d + 0.5, 0, 1)
    lit = 1 + shade * np.clip(((x - X) + (y - Y)) / (r * 1.4 + 1e-6), -1, 1)
    c = np.asarray(col)[None, None, :] * lit[..., None]
    mm = m[..., None]
    rgb[y0:y1, x0:x1] = c * mm + rgb[y0:y1, x0:x1] * (1 - mm)
    a[y0:y1, x0:x1] = m + a[y0:y1, x0:x1] * (1 - m)


def bleed(rgb, a):
    """Transparent texels take the mean sprite colour so mips/filtering never fringe dark."""
    w = a[..., None]
    straight = rgb / np.maximum(w, 1e-4)          # stamps composite premultiplied over black
    mean = rgb.sum(axis=(0, 1)) / max(1e-6, a.sum())
    return np.where(w > 0.02, straight, mean[None, None, :] * 0.9)


# ------------------------------------------------------------------------------------ foliage
OAK = pal("1f3a1d", "2f5226", "43702e", "5f8d36", "82ad45", "a9c95c")
OAK_B = pal("233d1a", "36592a", "4d7a30", "6d9a38", "93b847", "bdd36a")
BEECH = pal("24421e", "37622a", "4f8634", "6ea43e", "98c250", "c3dc72")
DARK = pal("101d1a", "172b25", "21392f", "2e4a39", "416046", "5b7a52")
BUSH = pal("1f361a", "2e4d22", "42692c", "5b8835", "7ea747", "a6c562")
BERRY = pal("1c3219", "294a22", "3a622b", "527f34", "6f9b40", "92b556")
PINE = pal("22421f", "33612a", "4a8032", "68a03a", "8cc04a", "b5d668")   # warm saturated green, yellow-green tips (art reference)
PINE_B = pal("264a20", "3a6c2b", "55903a", "74ac40", "9acb50", "c2df6e")
GRASS = pal("2c4a1b", "3f6424", "577f2e", "729b38", "90b546", "b3cc62")


def leaf_cluster(rng, cols, leafL=(24, 38), leafW=(8, 12), n_sub=10, per=17, spread=0.29, twig="4a3a2c",
                 extra=None):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    c = S / 2
    subs = []
    for i in range(n_sub):
        ang = rng.uniform(0, 2 * math.pi)
        rr = spread * S * math.sqrt(rng.uniform(0.05, 1))
        subs.append((c + math.cos(ang) * rr, c + math.sin(ang) * rr * 0.9))
    # twigs from the lower centre out to the sub-clusters
    for sx, sy in subs:
        seg(rgb, a, (c + rng.normal(0, 4), c + 30), (sx, sy), 2.2, 1.0, hx(twig))
    leaves = []
    for sx, sy in subs:
        for j in range(per):
            la = rng.uniform(0, 2 * math.pi)
            dist = rng.uniform(0, 16)
            bx, by = sx + math.cos(la) * dist, sy + math.sin(la) * dist
            L = rng.uniform(*leafL)
            W = rng.uniform(*leafW)
            # keep inside the cell
            tipx, tipy = bx + math.cos(la) * L, by + math.sin(la) * L
            if max(abs(tipx - c), abs(tipy - c)) > S / 2 - 7:
                L *= 0.6
            ang = la + rng.normal(0, 0.35)
            tx, ty = bx + math.cos(ang) * L * 0.6, by + math.sin(ang) * L * 0.6
            rx, ry = (tx - c) / (S * 0.42), (ty - c) / (S * 0.42)
            light = 0.5 + 0.5 * (-0.55 * rx - 0.83 * ry) / max(0.35, math.hypot(rx, ry))
            rad = min(1.0, math.hypot(rx, ry))
            lum = 0.22 + 0.72 * light * (0.5 + 0.5 * rad) + rng.normal(0, 0.07)
            leaves.append((lum, bx, by, ang, L, W))
    leaves.sort(key=lambda t: t[0])
    for lum, bx, by, ang, L, W in leaves:
        col = ramp1(np.clip(lum, 0, 1), cols) * rng.uniform(0.95, 1.05)
        stamp(rgb, a, bx, by, ang, L, W, col, kind="leaf", curv=rng.normal(0, 0.12), side=0.12)
    if extra:
        extra(rgb, a, subs)
    return rgb, a


def conifer_spray(rng, cols, needle=(9, 15), dense=1.0, droop=0.0, lean=0.0):
    """Spray pointing UP in the cell (base at the bottom centre). Triangular silhouette."""
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    base = (S / 2, S - 8)
    tip = (S / 2 + lean * 20, 10)
    twigc = hx("3b2a20")
    # main twig
    pts = [(base[0] + (tip[0] - base[0]) * t + math.sin(t * 3) * 3, base[1] + (tip[1] - base[1]) * t)
           for t in np.linspace(0, 1, 12)]
    twigs = [(pts, 1.0)]
    for k in range(1, 10):
        t = k / 10.5
        px, py = base[0] + (tip[0] - base[0]) * t, base[1] + (tip[1] - base[1]) * t
        for sgn in (-1, 1):
            Ls = (1 - t) ** 0.8 * 105 * rng.uniform(0.8, 1.1)
            ang = -math.pi / 2 + sgn * rng.uniform(0.75, 1.05) + droop * sgn * 0.3
            e = (px + math.cos(ang) * Ls, py + math.sin(ang) * Ls + droop * Ls * 0.3)
            e = (min(S - 8, max(8, e[0])), min(S - 8, max(8, e[1])))
            twigs.append(([(px + (e[0] - px) * s, py + (e[1] - py) * s) for s in np.linspace(0, 1, 6)], 1 - t))
    for tp, w in twigs:
        for i in range(len(tp) - 1):
            seg(rgb, a, tp[i], tp[i + 1], 1.6 + w, 1.2 + w * 0.8, twigc)
    ndl = []
    for tp, w in twigs:
        L = sum(math.hypot(tp[i + 1][0] - tp[i][0], tp[i + 1][1] - tp[i][1]) for i in range(len(tp) - 1))
        n = int(L / 3.2 * dense)
        for i in range(n):
            s = i / max(1, n - 1)
            f = s * (len(tp) - 1)
            j = min(len(tp) - 2, int(f))
            q = f - j
            x = tp[j][0] + (tp[j + 1][0] - tp[j][0]) * q
            y = tp[j][1] + (tp[j + 1][1] - tp[j][1]) * q
            d = math.atan2(tp[j + 1][1] - tp[j][1], tp[j + 1][0] - tp[j][0])
            for sgn in (-1, 1):
                ang = d + sgn * rng.uniform(0.6, 1.1)
                L2 = rng.uniform(*needle) * (0.75 + 0.35 * (1 - s))
                ex, ey = x + math.cos(ang) * L2, y + math.sin(ang) * L2
                if not (4 < ex < S - 4 and 4 < ey < S - 4):
                    continue
                rx, ry = (ex - S / 2) / (S * 0.5), (ey - S / 2) / (S * 0.5)
                lum = 0.2 + 0.45 * s + 0.25 * (0.5 - 0.5 * ry) + rng.normal(0, 0.08)
                ndl.append((lum, x, y, ang, L2))
    ndl.sort(key=lambda t: t[0])
    for lum, x, y, ang, L2 in ndl:
        stamp(rgb, a, x, y, ang, L2, 1.5, ramp1(np.clip(lum, 0, 1), cols), kind="blade", grad=(0.85, 1.15),
              side=0.0)
    return rgb, a


def grass_card(rng, cols, n=38, hmin=0.45, seeds=False, flowers=None):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    blades = []
    for i in range(n):
        x = rng.uniform(40, S - 40)
        h = rng.uniform(hmin, 0.95) * (S - 12)
        lean = rng.normal(0, 0.28) + (x - S / 2) / S * 0.6
        ang = -math.pi / 2 + lean
        blades.append((rng.uniform(0, 1), x, h, ang))
    blades.sort(key=lambda t: t[0])
    for lum, x, h, ang in blades:
        col = ramp1(0.25 + 0.7 * lum, cols)
        if rng.random() < 0.15:
            col = col * 0.6 + hx("b0b05a") * 0.4
        # keep the tip inside the card
        tipx = x + math.cos(ang) * h
        if tipx < 6 or tipx > S - 6:
            ang = -math.pi / 2 + (ang + math.pi / 2) * 0.4
        stamp(rgb, a, x, S - 2, ang, h, rng.uniform(3.0, 5.0), col, kind="blade", curv=rng.normal(0, 0.1),
              grad=(0.45, 1.2), side=0.15)
    if seeds:
        for i in range(9):
            x = rng.uniform(60, S - 60)
            h = rng.uniform(0.7, 0.95) * (S - 16)
            ang = -math.pi / 2 + rng.normal(0, 0.15)
            ex, ey = x + math.cos(ang) * h, S - 2 + math.sin(ang) * h
            stamp(rgb, a, x, S - 2, ang, h, 1.4, hx("8e9a4a"), kind="seg", grad=(0.7, 1.1))
            for k in range(6):
                t = 0.78 + k * 0.04
                sx, sy = x + math.cos(ang) * h * t, S - 2 + math.sin(ang) * h * t
                for sgn in (-1, 1):
                    stamp(rgb, a, sx, sy, ang + sgn * 0.5, 9, 2.6, hx("c9b36a") * rng.uniform(0.85, 1.1),
                          kind="oval", grad=(0.9, 1.1))
    if flowers:
        for i in range(11):
            x = rng.uniform(50, S - 50)
            h = rng.uniform(0.4, 0.9) * (S - 30)
            ang = -math.pi / 2 + rng.normal(0, 0.18)
            ex, ey = x + math.cos(ang) * h, S - 2 + math.sin(ang) * h
            stamp(rgb, a, x, S - 2, ang, h, 1.6, hx("4f7a2c"), kind="seg", grad=(0.6, 1.1))
            pc = flowers[rng.integers(len(flowers))]
            r = rng.uniform(5, 8)
            for k in range(5):
                pa = k / 5 * 2 * math.pi + rng.uniform(0, 1)
                stamp(rgb, a, ex, ey, pa, r * 1.3, r * 0.55, hx(pc) * rng.uniform(0.9, 1.08), kind="oval",
                      grad=(0.85, 1.1), side=0.05)
            disc(rgb, a, ex, ey, r * 0.35, hx("f0c030"))
    return rgb, a


def fern_card(rng):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    cols = pal("2a4c1c", "3d6a25", "57892f", "76a83c", "9cc553")
    base = np.array([S / 2, S - 4.0])
    pts = []
    for t in np.linspace(0, 1, 40):
        pts.append(base + np.array([math.sin(t * 2.2) * 26 * t, -t * (S - 14)]))
    for i in range(len(pts) - 1):
        seg(rgb, a, pts[i], pts[i + 1], 2.2 * (1 - i / 40) + 0.8, 2.0 * (1 - i / 40) + 0.7, hx("4d6e2a"))
    for i in range(3, len(pts) - 1, 2):
        t = i / (len(pts) - 1)
        L = 62 * math.sin(math.pi * min(1, t * 1.15 + 0.08)) ** 0.9 * (1 - 0.25 * t) + 6
        d = pts[i + 1] - pts[i]
        da = math.atan2(d[1], d[0])
        for sgn in (-1, 1):
            ang = da + sgn * (1.25 - 0.3 * t)
            lum = 0.3 + 0.55 * t + rng.normal(0, 0.06) + (0.1 if sgn < 0 else 0)
            stamp(rgb, a, pts[i][0], pts[i][1], ang, L, 6.5 - 2.5 * t, ramp1(np.clip(lum, 0, 1), cols),
                  kind="leaf", curv=0.15 * sgn, side=0.18, rib=0.2)
    return rgb, a


def twigs_card(rng):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    col = hx("4d443c")

    def br(p, ang, L, w, depth):
        e = (p[0] + math.cos(ang) * L, p[1] + math.sin(ang) * L)
        e = (min(S - 6, max(6, e[0])), min(S - 6, max(6, e[1])))
        seg(rgb, a, p, e, w, w * 0.7, col * rng.uniform(0.85, 1.15))
        if depth > 0:
            for k in range(2):
                br(e, ang + rng.uniform(-0.7, 0.7), L * rng.uniform(0.55, 0.75), max(0.9, w * 0.65), depth - 1)
            if rng.random() < 0.5:
                mid = (p[0] + (e[0] - p[0]) * 0.5, p[1] + (e[1] - p[1]) * 0.5)
                br(mid, ang + rng.choice([-1, 1]) * rng.uniform(0.6, 1.0), L * 0.5, max(0.9, w * 0.55), depth - 1)
    br((S / 2, S - 4), -math.pi / 2, 95, 5.0, 4)
    return rgb, a


def moss_card(rng):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    cols = pal("4a5638", "66734c", "83906a", "a2ad86")
    for i in range(46):
        x = rng.uniform(20, S - 20)
        L = rng.uniform(0.35, 0.95) * (S - 14)
        ang = math.pi / 2 + rng.normal(0, 0.06)
        for k in range(3):
            stamp(rgb, a, x + rng.normal(0, 3), 4, ang + rng.normal(0, 0.05), L * rng.uniform(0.7, 1.0),
                  rng.uniform(1.5, 3.2), ramp1(rng.uniform(0.1, 1), cols), kind="blade", grad=(1.1, 0.7),
                  curv=rng.normal(0, 0.05), side=0.1)
    return rgb, a


def wheat_card(rng):
    S = 256
    rgb = np.zeros((S, S, 3), np.float32)
    a = np.zeros((S, S), np.float32)
    stalks = []
    for i in range(22):
        x = rng.uniform(30, S - 30)
        h = rng.uniform(0.72, 0.95) * (S - 10)
        stalks.append((rng.uniform(0, 1), x, h, -math.pi / 2 + rng.normal(0, 0.1)))
    stalks.sort(key=lambda t: t[0])
    for lum, x, h, ang in stalks:
        k = 0.75 + 0.35 * lum
        stamp(rgb, a, x, S - 2, ang, h, 1.7, hx("b89a4a") * k, kind="seg", grad=(0.6, 1.1))
        for j in range(2):
            la = ang + (0.6 if j else -0.6)
            stamp(rgb, a, x + math.cos(ang) * h * 0.3, S - 2 + math.sin(ang) * h * 0.3, la, 40, 2.5,
                  hx("a89344") * k, kind="blade", grad=(0.8, 1.1))
        ex, ey = x + math.cos(ang) * h, S - 2 + math.sin(ang) * h
        for j in range(7):
            t = 0.74 + j * 0.035
            sx, sy = x + math.cos(ang) * h * t, S - 2 + math.sin(ang) * h * t
            for sgn in (-1, 1):
                stamp(rgb, a, sx, sy, ang + sgn * 0.35, 12, 3.2, hx("dcb85c") * k * rng.uniform(0.9, 1.1),
                      kind="oval", grad=(0.85, 1.12))
        for j in range(4):   # awns
            stamp(rgb, a, ex, ey, ang + rng.normal(0, 0.25), 18, 0.7, hx("e6cf86") * k, kind="seg")
    return rgb, a


def berries(rgb, a, subs, rng=None):
    rng = rng or np.random.default_rng(3)
    for sx, sy in subs:
        for k in range(2):
            disc(rgb, a, sx + rng.normal(0, 14), sy + rng.normal(0, 14), rng.uniform(4, 6),
                 hx("b3242e") * rng.uniform(0.8, 1.1), shade=0.5)


def make_foliage_atlas(path, seed=11):
    rng = np.random.default_rng(seed)
    S, N = 256, 4
    rgb = np.zeros((S * N, S * N, 3), np.float32)
    a = np.zeros((S * N, S * N), np.float32)
    cells = [
        [lambda: leaf_cluster(rng, OAK), lambda: leaf_cluster(rng, OAK_B, leafL=(20, 32), per=19),
         lambda: leaf_cluster(rng, BEECH, leafL=(26, 40), leafW=(10, 14), per=15),
         lambda: leaf_cluster(rng, DARK, leafL=(24, 36), leafW=(6, 9), per=19, twig="2c2622")],
        [lambda: conifer_spray(rng, PINE, needle=(9, 14), dense=1.3),
         lambda: conifer_spray(rng, PINE_B, needle=(13, 20), dense=1.0, droop=0.4),
         lambda: leaf_cluster(rng, BUSH, leafL=(18, 28), leafW=(7, 10), n_sub=12, per=17, spread=0.31),
         lambda: leaf_cluster(rng, BERRY, leafL=(18, 28), leafW=(7, 10), n_sub=12, per=15, spread=0.31,
                              extra=lambda r, aa, s: berries(r, aa, s, rng))],
        [lambda: grass_card(rng, GRASS), lambda: grass_card(rng, GRASS, n=30, seeds=True),
         lambda: grass_card(rng, GRASS, n=24, hmin=0.3, flowers=["f6f1e4", "f7d046", "fbfbf2", "f2b632"]),
         lambda: grass_card(rng, GRASS, n=24, hmin=0.3, flowers=["e05a8a", "b070d8", "7c9ce8", "f08aa8"])],
        [lambda: fern_card(rng), lambda: twigs_card(rng), lambda: moss_card(rng), lambda: wheat_card(rng)],
    ]
    for r in range(N):
        for c in range(N):
            cr, ca = cells[r][c]()
            cr = bleed(cr, ca)
            rgb[r * S:(r + 1) * S, c * S:(c + 1) * S] = cr
            a[r * S:(r + 1) * S, c * S:(c + 1) * S] = ca
    save_rgba(path, np.clip(rgb, 0, 1), np.clip(a, 0, 1))


# ------------------------------------------------------------------------------------ bark
def voronoi_periodic(h, w, n, rng, sx=1.0, sy=1.0):
    """Nearest / second-nearest distance and id for n random points on a torus (anisotropic)."""
    px = rng.uniform(0, w, n)
    py = rng.uniform(0, h, n)
    Y, X = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    d1 = np.full((h, w), 1e9, np.float32)
    d2 = np.full((h, w), 1e9, np.float32)
    ids = np.zeros((h, w), np.int32)
    for i in range(n):
        dx = np.abs(X - px[i])
        dx = np.minimum(dx, w - dx) * sx
        dy = np.abs(Y - py[i])
        dy = np.minimum(dy, h - dy) * sy
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        ids = np.where(closer, i, ids)
        d1 = np.where(closer, d, d1)
    return d1, d2, ids


def bark_oak(rng, h=1024, w=256):
    n = fnoise(h, w, 0.07, 0.004, rng) + 0.3 * fnoise(h, w, 0.12, 0.015, rng)
    groove = smooth(-0.35, -1.1, n)
    blot = norm(fnoise(h, w, 0.012, 0.006, rng))
    lit = np.clip(np.roll(groove, 3, axis=1) - groove, 0, 1)
    lum = 0.25 + 0.45 * norm(n) + 0.25 * blot - 0.45 * groove + 0.2 * lit + 0.04 * fnoise(h, w, 0.2, 0.1, rng)
    return ramp(norm(lum, 0.5, 99.5), pal("211811", "35281e", "4c3b2d", "65513f", "7f6a54", "98836a"))


def bark_pine(rng, h=1024, w=256):
    d1, d2, ids = voronoi_periodic(h, w, 70, rng, sx=1.0, sy=0.45)
    gap = smooth(9, 2, d2 - d1)
    per = rng.uniform(0.35, 1, 70)[ids]
    fine = fnoise(h, w, 0.15, 0.05, rng)
    lum = 0.35 + 0.45 * per + 0.08 * fine - 0.75 * gap
    lit = np.roll(gap, -3, axis=0) - gap   # light upper plate edges
    lum = lum + 0.25 * np.clip(-lit, 0, 1)
    return ramp(norm(lum, 0.5, 99.5), pal("24160f", "4a2c1d", "6e402a", "8b5536", "a56a42", "c08658"))


def bark_dead(rng, h=1024, w=256):
    n = fnoise(h, w, 0.025, 0.003, rng) + 0.3 * fnoise(h, w, 0.08, 0.01, rng)
    groove = smooth(-0.7, -1.6, n)
    lit = np.clip(np.roll(groove, 3, axis=1) - groove, 0, 1)
    lum = 0.3 + 0.5 * norm(n) - 0.5 * groove + 0.2 * lit + 0.05 * fnoise(h, w, 0.2, 0.2, rng)
    return ramp(norm(lum, 0.5, 99.5), pal("2e2a26", "4c4640", "6c655b", "8a8275", "a69e8f", "c2baa9"))


def end_grain(rng, S=256):
    Y, X = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    n = fnoise(S, S, 0.02, 0.02, rng)
    r = np.hypot(X - S / 2, Y - S / 2) + n * 3.5
    rings = 0.5 + 0.5 * np.sin(r * 0.62)
    lum = 0.55 + 0.25 * rings - 0.3 * smooth(10, 0, r) + 0.05 * fnoise(S, S, 0.2, 0.2, rng)
    ang = np.arctan2(Y - S / 2, X - S / 2)
    crack = smooth(0.03, 0.0, np.abs(np.sin(ang * 1.5 + 0.7))) * smooth(20, 60, r) * smooth(118, 95, r)
    lum -= 0.4 * crack
    col = ramp(norm(lum), pal("7a5534", "9c7046", "b98b5a", "d2a672", "e3be8a"))
    barkring = smooth(111, 116, r)[..., None]
    return col * (1 - barkring) + hx("3e2f22")[None, None, :] * barkring


def make_bark_atlas(path, seed=5):
    rng = np.random.default_rng(seed)
    img = np.zeros((1024, 1024, 3), np.float32)
    img[:, 0:256] = bark_oak(rng)
    img[:, 256:512] = bark_pine(rng)
    img[:, 512:768] = bark_dead(rng)
    eg = end_grain(rng)
    for k in range(4):
        img[k * 256:(k + 1) * 256, 768:1024] = eg
    save_rgb(path, img)


# ------------------------------------------------------------------------------------ tileables
def rock_tex(rng, S=512):
    b = fnoise(S, S, 0.008, 0.008, rng) + 0.55 * fnoise(S, S, 0.03, 0.03, rng) + 0.2 * fnoise(S, S, 0.12, 0.12, rng)
    cr = 1 - np.abs(fnoise(S, S, 0.01, 0.01, rng))
    cracks = smooth(0.965, 1.0, cr) * 0.7
    lit = np.clip(np.roll(cracks, 2, axis=0) - cracks, 0, 1)
    lum = 0.5 + 0.22 * b - 0.45 * cracks + 0.15 * lit
    col = ramp(norm(lum, 0.5, 99.5), pal("383531", "4f4b45", "67625a", "7e786e", "948d80", "aaa292"))
    lich = smooth(1.7, 2.3, fnoise(S, S, 0.05, 0.05, rng))[..., None]
    return col * (1 - lich * 0.35) + hx("8f935e")[None, None, :] * lich * 0.35


def moss_tex(rng, S=512):
    b = fnoise(S, S, 0.02, 0.02, rng) + 0.6 * fnoise(S, S, 0.07, 0.07, rng) + 0.3 * fnoise(S, S, 0.2, 0.2, rng)
    return ramp(norm(b), pal("22341a", "304822", "40602a", "547a32", "6d9140", "89a852"))


def board_rows(rng, S, rows, cols, grain_c, seam=0.35, knots=True, joints=True):
    img = np.zeros((S, S, 3), np.float32)
    g = fnoise(S, S, 0.25, 0.006, rng).T if False else fnoise(S, S, 0.004, 0.12, rng)
    g2 = fnoise(S, S, 0.02, 0.3, rng)
    Y, X = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    edges = np.linspace(0, S, rows + 1).astype(int)
    for i in range(rows):
        y0, y1 = edges[i], edges[i + 1]
        base = rng.uniform(0.35, 0.75)
        lum = base + 0.2 * g[y0:y1] + 0.08 * g2[y0:y1]
        yy = (Y[y0:y1] - y0) / (y1 - y0)
        lum = lum + 0.12 * smooth(0.25, 0.0, yy) - seam * smooth(0.12, 0.0, 1 - yy) - seam * smooth(0.04, 0.0, yy)
        if joints:
            for j in range(rng.integers(1, 3)):
                jx = rng.uniform(0, S)
                dx = np.abs(X[y0:y1] - jx)
                dx = np.minimum(dx, S - dx)
                lum = lum - 0.4 * smooth(2.5, 0.5, dx) + 0.1 * smooth(5, 2.5, dx) * (X[y0:y1] > jx)
        if knots and rng.random() < 0.5:
            kx, ky = rng.uniform(0, S), rng.uniform(y0 + 6, y1 - 6)
            d = np.hypot((X[y0:y1] - kx) * 0.6, Y[y0:y1] - ky)
            lum = lum - 0.3 * smooth(7, 2, d) + 0.08 * np.sin(d * 1.4) * smooth(14, 6, d)
        img[y0:y1] = ramp(np.clip(lum, 0, 1), grain_c)
    return img


def planks_tex(rng, S=512):
    return board_rows(rng, S, 5, None, pal("3f2819", "5f3f27", "7a5434", "93683f", "ad814f", "c49a64"))


def timber_tex(rng, S=512):
    g = fnoise(S, S, 0.003, 0.08, rng)
    g2 = fnoise(S, S, 0.02, 0.2, rng)
    lines = smooth(0.9, 1.0, np.abs(np.sin(fnoise(S, S, 0.002, 0.04, rng) * 3.0)))
    lum = 0.5 + 0.25 * g + 0.1 * g2 - 0.2 * lines
    return ramp(norm(lum), pal("33200f", "4d321d", "68462b", "825a38", "9d6f46", "b78656"))


def rounded_rect_mask(X, Y, x0, y0, x1, y1, rad):
    cx = np.clip(X, x0 + rad, x1 - rad)
    cy = np.clip(Y, y0 + rad, y1 - rad)
    d = rad - np.hypot(X - cx, Y - cy)       # >0 inside
    return d


def stone_tex(rng, S=512, cols=None, mortar="4a443d", rows=(40, 72), widths=(56, 130), rad=11):
    cols = cols or pal("7c7b78", "8d8a83", "9a978e", "85827f", "a7a397", "8f8b86", "76777a", "9d9486")
    img = np.zeros((S, S, 3), np.float32) + hx(mortar)
    img *= (0.85 + 0.15 * norm(fnoise(S, S, 0.1, 0.1, rng)))[..., None]
    fine = fnoise(S, S, 0.12, 0.12, rng)
    blot = fnoise(S, S, 0.03, 0.03, rng)
    wob = fnoise(S, S, 0.04, 0.04, rng)
    hs = []
    tot = 0
    while tot < S:
        hh = int(rng.uniform(*rows))
        hs.append(hh)
        tot += hh
    hs[-1] -= tot - S
    if hs[-1] < rows[0] * 0.6 and len(hs) > 1:
        hs[-2] += hs[-1]
        hs.pop()
    y = 0
    for hh in hs:
        ws, t = [], 0
        while t < S:
            ww = int(rng.uniform(*widths))
            ws.append(ww)
            t += ww
        ws[-1] -= t - S
        if ws[-1] < widths[0] * 0.5 and len(ws) > 1:
            ws[-2] += ws[-1]
            ws.pop()
        x = rng.uniform(0, S)
        for ww in ws:
            gap = 3.0
            x0, x1, y0, y1 = x + gap, x + ww - gap, y + gap + rng.uniform(0, 2), y + hh - gap - rng.uniform(0, 2)
            # draw with wrap in x (y rows never wrap: they tile exactly)
            bx0, bx1 = int(math.floor(x0)) - 2, int(math.ceil(x1)) + 2
            by0, by1 = int(max(0, math.floor(y0) - 2)), int(min(S, math.ceil(y1) + 2))
            Yg, Xg = np.mgrid[by0:by1, bx0:bx1].astype(np.float32) + 0.5
            d = rounded_rect_mask(Xg, Yg, x0, y0, x1, y1, min(rad, (y1 - y0) / 2.2, (x1 - x0) / 2.2))
            d = d + 2.6 * wob[np.ix_(np.arange(by0, by1), np.arange(bx0, bx1) % S)]
            m = np.clip(d * 0.8, 0, 1)
            # painted bevel: bright upper-left rim, dark lower-right rim
            rim = smooth(7, 0, d)
            nx = (Xg - (x0 + x1) / 2) / ((x1 - x0) / 2)
            ny = (Yg - (y0 + y1) / 2) / ((y1 - y0) / 2)
            dirl = np.clip(-0.5 * nx - 0.9 * ny, -1, 1)
            ci = np.arange(bx0, bx1) % S
            ix = np.ix_(np.arange(by0, by1), ci)
            base = cols[rng.integers(len(cols))] * rng.uniform(0.9, 1.08)
            if rng.random() < 0.05:
                base = base * 0.75 + hx("7d8a5c") * 0.25
            if rng.random() < 0.1:
                base = base * 0.8 + hx("b89a78") * 0.2
            lum = 1 + 0.035 * fine[ix] + 0.05 * blot[ix] + 0.26 * rim * dirl - 0.05 * (1 - rim) * ny
            c = base[None, None, :] * lum[..., None]
            mm = m[..., None]
            img[ix] = c * mm + img[ix] * (1 - mm)
            x += ww
        y += hh
    return img


def plaster_tex(rng, S=512):
    b = norm(fnoise(S, S, 0.01, 0.01, rng) + 0.5 * fnoise(S, S, 0.04, 0.04, rng))
    lum = 0.55 + 0.35 * b + 0.05 * fnoise(S, S, 0.2, 0.2, rng)
    col = ramp(np.clip(lum, 0, 1), pal("b8a888", "d2c3a2", "e6d9ba", "f1e7cc"))
    cr = smooth(0.985, 1.0, 1 - np.abs(fnoise(S, S, 0.01, 0.01, rng)))
    return col * (1 - 0.35 * cr[..., None])


def fibres(rng, S, n, cols, L=(50, 110), W=(1.6, 2.8), ang_fn=None, bands=0, band_dark=0.35):
    rgb = np.zeros((S, S, 3), np.float32) + cols[0]
    a = np.zeros((S, S), np.float32)
    for i in range(n):
        x, y = rng.uniform(0, S), rng.uniform(0, S)
        ang = ang_fn(x, y) if ang_fn else rng.uniform(0, 2 * math.pi)
        L_ = rng.uniform(*L)
        lum = rng.uniform(0, 1)
        if bands:
            bh = S / bands
            yy = (y % bh) / bh
            lum = lum * (0.55 + 0.45 * yy)
        stamp(rgb, a, x, y, ang, L_, rng.uniform(*W), ramp1(lum, cols), kind="blade", grad=(0.8, 1.1),
              side=0.1, wrap=True, curv=rng.normal(0, 0.05))
    if bands:
        Y = (np.arange(S)[:, None] + 0.5) % (S / bands) / (S / bands)
        rgb *= (1 - band_dark * smooth(0.12, 0.0, Y))[..., None]
    return rgb


def thatch_tex(rng, S=512):
    cols = pal("5e4524", "7d5f31", "9d7b40", "b89450", "cfae66", "e0c47e")
    return fibres(rng, S, 3200, cols, L=(70, 140), W=(1.6, 2.6),
                  ang_fn=lambda x, y: math.pi / 2 + rng.normal(0, 0.12), bands=4, band_dark=0.45)


def hay_tex(rng, S=512):
    cols = pal("8a6c30", "a88840", "c4a450", "d9bb66", "e8d088")
    return fibres(rng, S, 2600, cols, L=(40, 90), W=(1.2, 2.2))


def shingle_tex(rng, S=512, cols=None, rows=8, w=(38, 70)):
    cols = cols or pal("5b3f2a", "6c4b31", "7b5638", "8a6443", "6a4a36", "94714e")
    img = np.zeros((S, S, 3), np.float32) + hx("2a1d14")
    rh = S / rows
    Y, X = np.mgrid[0:S, 0:S].astype(np.float32) + 0.5
    fine = fnoise(S, S, 0.25, 0.03, rng)
    for r in range(rows):
        y0 = r * rh
        x = rng.uniform(0, S)
        t = 0
        while t < S:
            ww = rng.uniform(*w)
            ww = min(ww, S - t) if S - t > w[0] * 0.5 else ww
            x0, x1 = x + 1.5, x + ww - 1.5
            bx0, bx1 = int(math.floor(x0)) - 1, int(math.ceil(x1)) + 1
            by0, by1 = int(y0), int(min(S, y0 + rh + 1))
            Yg, Xg = np.mgrid[by0:by1, bx0:bx1].astype(np.float32) + 0.5
            yy = (Yg - y0) / rh           # 0 top (up-slope) .. 1 butt (down-slope)
            d = rounded_rect_mask(Xg, Yg, x0, y0 - 20, x1, y0 + rh - 1.5, 7)
            m = np.clip(d, 0, 1)
            base = cols[rng.integers(len(cols))] * rng.uniform(0.88, 1.1)
            if rng.random() < 0.06:
                base = base * 0.65 + hx("6b7a45") * 0.35
            ix = np.ix_(np.arange(by0, by1), np.arange(bx0, bx1) % S)
            lum = 0.72 + 0.35 * yy + 0.08 * fine[ix] + 0.18 * smooth(4, 0, d) * (yy > 0.7)
            c = base[None, None, :] * lum[..., None]
            img[ix] = c * m[..., None] + img[ix] * (1 - m[..., None])
            x += ww
            t += ww
    return img


def slate_tex(rng, S=512):
    return shingle_tex(rng, S, pal("3a4b63", "455871", "506684", "3f5570", "5d7493", "4b5a6e", "56697f"),
                       rows=9, w=(44, 76))


def iron_tex(rng, S=512):
    b = norm(fnoise(S, S, 0.02, 0.02, rng) + 0.4 * fnoise(S, S, 0.1, 0.1, rng))
    col = ramp(b, pal("26241f", "36332f", "47433d", "5a554d"))
    rust = smooth(1.2, 2.0, fnoise(S, S, 0.04, 0.04, rng))[..., None]
    return col * (1 - rust * 0.7) + hx("6e4428")[None, None, :] * rust * 0.7


def canvas_tex(rng, S=512):
    Y, X = np.mgrid[0:S, 0:S].astype(np.float32)
    weave = 0.5 + 0.25 * (np.sin(X * math.pi / 2) * np.sin(Y * math.pi / 2))
    b = norm(fnoise(S, S, 0.015, 0.015, rng))
    lum = 0.65 + 0.2 * b + 0.12 * weave
    stain = smooth(1.0, 2.2, fnoise(S, S, 0.02, 0.02, rng))
    lum -= 0.12 * stain
    return ramp(np.clip(lum, 0, 1), pal("a39578", "c5b797", "ddd0b2", "ece2c8"))


def soil_tex(rng, S=512):
    b = fnoise(S, S, 0.02, 0.02, rng) + 0.6 * fnoise(S, S, 0.08, 0.08, rng) + 0.35 * fnoise(S, S, 0.25, 0.25, rng)
    col = ramp(norm(b), pal("2e2017", "44301f", "5a4029", "725235", "8a6842"))
    img = col.copy()
    a = np.zeros((S, S), np.float32)
    for i in range(160):
        x, y = rng.uniform(4, S - 4), rng.uniform(4, S - 4)
        disc(img, a, x, y, rng.uniform(1.5, 4), hx("8f8475") * rng.uniform(0.7, 1.1), shade=0.4)
    return img


TILEABLES = {
    "rock": rock_tex, "moss": moss_tex, "planks": planks_tex, "timber": timber_tex, "stone_wall": stone_tex,
    "plaster": plaster_tex, "thatch": thatch_tex, "shingle": shingle_tex, "slate": slate_tex,
    "iron": iron_tex, "canvas": canvas_tex, "hay": hay_tex, "soil": soil_tex,
}


# ------------------------------------------------------------------------------------ io
def save_rgba(path, rgb, a):
    import bpy
    h, w = a.shape
    px = np.concatenate([np.clip(rgb, 0, 1), np.clip(a, 0, 1)[..., None]], axis=2)[::-1]
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    im.pixels.foreach_set(px.astype(np.float32).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("texture", path)


def save_rgb(path, rgb):
    h, w = rgb.shape[:2]
    save_rgba(path, rgb, np.ones((h, w), np.float32))


def make_all(force=False, only=None):
    os.makedirs(TEX, exist_ok=True)
    jobs = [("foliage_atlas", lambda p: make_foliage_atlas(p)), ("bark_atlas", lambda p: make_bark_atlas(p))]
    for i, (name, fn) in enumerate(TILEABLES.items()):
        jobs.append((name, lambda p, fn=fn, i=i: save_rgb(p, fn(np.random.default_rng(100 + i)))))
    for name, fn in jobs:
        if only and name not in only:
            continue
        p = os.path.join(TEX, name + ".png")
        if force or only or not os.path.exists(p):
            fn(p)
