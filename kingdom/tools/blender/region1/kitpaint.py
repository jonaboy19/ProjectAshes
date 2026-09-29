"""Highwatch kit: palette grading of Meshy source textures + procedural painted charts (bricks, cloth, wood, straw...).
Arrays are (h, w, 3) floats in sRGB space, row 0 = top."""
import math
import numpy as np
import paint as P

STONE_L = P.rgb(0.78, 0.71, 0.58)
STONE_D = P.rgb(0.47, 0.41, 0.34)
MORTAR = P.rgb(0.40, 0.35, 0.30)
ROYAL = P.rgb(0.14, 0.30, 0.66)
ROYAL_D = P.rgb(0.08, 0.17, 0.42)
GOLD = P.rgb(0.95, 0.74, 0.22)
GOLD_D = P.rgb(0.70, 0.48, 0.10)
WOOD_L = P.rgb(0.58, 0.39, 0.22)
WOOD_D = P.rgb(0.34, 0.21, 0.12)
STRAW = P.rgb(0.90, 0.74, 0.34)
LUMW = P.rgb(0.30, 0.59, 0.11)


def lum(a):
    return (a * LUMW[None, None, :]).sum(-1)


def hsv(a):
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn + 1e-6
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 1e-4, d / (mx + 1e-6), 0)
    return h, s, mx


def recolor(a, mask, target, lum_gain=1.0):
    """replace colour by `target` (hue) keeping the source luminance structure."""
    l = lum(a)
    tl = float((target * LUMW).sum())
    out = target[None, None, :] * (l[..., None] / max(tl, 1e-3)) ** 0.9 * lum_gain
    return a * (1 - mask[..., None]) + np.clip(out, 0, 1) * mask[..., None]


def grade(a, profile, cov=None):
    """Harmonise a Meshy source tile to the Highwatch palette."""
    a = np.clip(a, 0, 1).astype(np.float32)
    h, s, v = hsv(a)
    l = lum(a)
    ls = l[cov] if cov is not None and cov.any() else l
    p5, p95 = np.percentile(ls, 5), np.percentile(ls, 95)
    ln = np.clip((l - p5) / (p95 - p5 + 1e-3), 0, 1)
    out = a.copy()
    if profile in ('stone', 'stone_flags', 'stone_blue'):
        stone = P.mix(STONE_D, STONE_L, 0.10 + 0.72 * ln ** 0.95)
        w_stone = 1 - P.sstep(0.18, 0.34, s)                      # grey-ish = stone
        # keep dark openings/doors dark
        w_stone *= 1 - P.sstep(0.22, 0.10, ln) * 0.0
        out = out * (1 - w_stone[..., None]) + stone * w_stone[..., None]
        blue = ((h > 0.5) & (h < 0.72) & (s > 0.22)).astype(np.float32)
        red = (((h < 0.045) | (h > 0.90)) & (s > 0.35) & (v > 0.25)).astype(np.float32)
        orange = ((h >= 0.045) & (h < 0.12) & (s > 0.30)).astype(np.float32)
        out = recolor(out, np.clip(blue + red, 0, 1) * (0.9 if profile != 'stone' else 0.9), ROYAL, 1.15)
        # doors / wood: warm oak
        wood = P.mix(WOOD_D, WOOD_L, ln ** 0.9)
        out = out * (1 - orange[..., None] * 0.85) + wood * orange[..., None] * 0.85
        # gold trims from strong yellow
        yellow = ((h >= 0.10) & (h < 0.18) & (s > 0.45) & (v > 0.6)).astype(np.float32)
        out = recolor(out, yellow, GOLD, 1.05)
    elif profile == 'wood':
        wood = P.mix(WOOD_D, WOOD_L, ln ** 0.9)
        w = 1 - P.sstep(0.55, 0.8, s)
        w = np.clip(w * 0.0 + ((h > 0.03) & (h < 0.13) & (s > 0.2)) * 0.6, 0, 1)
        out = out * (1 - w[..., None]) + wood * w[..., None]
        blue = ((h > 0.5) & (h < 0.72) & (s > 0.22)).astype(np.float32)
        red = (((h < 0.045) | (h > 0.90)) & (s > 0.35) & (v > 0.25)).astype(np.float32)
        out = recolor(out, np.clip(blue + red, 0, 1), ROYAL, 1.1)
    elif profile == 'keep':
        pass
    # global storybook lift
    l2 = lum(out)[..., None]
    out = l2 + (out - l2) * 1.10
    out = out * P.rgb(1.02, 1.0, 0.96)[None, None, :]
    return np.clip(out, 0, 1)


# ----------------------------------------------------------------- procedural charts
def bricks(h, w, ppm, seed, z_base=0.0, slits=(), moss=1.0, rowh=0.40):
    """Warm chunky block wall. v (metres above ground) grows upward; row 0 is the top."""
    rs = np.random.RandomState(seed)
    img = np.zeros((h, w, 3), np.float32)
    img[:] = MORTAR
    n_big = P.fbm(h, w, max(3.0, 0.9 * ppm), 3, seed)
    n_mid = P.fbm(h, w, max(2.0, 0.22 * ppm), 3, seed + 3)
    bot = h  # row index of v=0 is bottom
    y = bot
    row = 0
    while y > 0:
        rh = rowh * rs.uniform(0.85, 1.15)
        y1 = y
        y0 = max(0, int(y - rh * ppm))
        x = -int(rs.uniform(0, 0.8) * ppm)
        while x < w:
            bw = rs.uniform(0.55, 1.15) * ppm
            xa = max(0, int(x)); xb = min(w, int(x + bw))
            if xb > xa + 1 and y1 > y0 + 1:
                t = rs.uniform(0.15, 0.85)
                c = P.mix(STONE_D, STONE_L, np.full((1, 1), t, np.float32))[0, 0]
                c = c * (1 + rs.uniform(-0.05, 0.05, 3) * np.array([1.0, 0.5, -0.8]))
                gap = max(1, int(0.03 * ppm))
                ya, yb = y0 + gap // 2, y1 - (gap + 1) // 2
                xa2, xb2 = xa + gap // 2, xb - (gap + 1) // 2
                if yb > ya and xb2 > xa2:
                    img[ya:yb, xa2:xb2] = c
                    hl = max(1, int(0.035 * ppm))
                    img[ya:min(yb, ya + hl), xa2:xb2] = np.clip(c * 1.16 + 0.03, 0, 1)      # lit top edge
                    img[max(ya, yb - hl):yb, xa2:xb2] = c * 0.80                            # shaded bottom edge
                    img[ya:yb, xa2:min(xb2, xa2 + max(1, hl // 2))] = np.clip(c * 1.06, 0, 1)
            x += bw
        y = y0
        row += 1
    img = P.blur(img, 0.6)
    mott = (n_big - 0.5) * 0.22 + (n_mid - 0.5) * 0.12
    img = np.clip(img * (1 + mott[..., None]), 0, 1)
    # base grime / moss
    v = (bot - np.arange(h, dtype=np.float32) - 0.5)[:, None] / ppm
    zl = v - z_base
    grime = (1 - P.sstep(0.0, 1.4, zl)) * (0.5 + 0.5 * n_big)
    img = img * (1 - 0.30 * grime[..., None])
    m = ((1 - P.sstep(0.0, 0.9, zl)) * 1.2 + (n_mid - 0.5) * 1.1) * moss
    mm = P.sstep(0.55, 0.62, m)
    mcol = P.mix(P.rgb(0.26, 0.42, 0.16), P.rgb(0.52, 0.66, 0.22), P.sstep(0.3, 0.8, n_mid))
    img = img * (1 - mm[..., None]) + mcol * mm[..., None]
    for (su, sv, sw, sh) in slits:       # arrow slits (metres from left / above ground)
        x0 = int(su * ppm); x1 = int((su + sw) * ppm); y1_ = int(bot - sv * ppm); y0_ = int(bot - (sv + sh) * ppm)
        fr = max(2, int(0.07 * ppm))
        img[max(0, y0_ - fr):y1_ + fr, max(0, x0 - fr):x1 + fr] = STONE_L * 0.92
        img[max(0, y0_):y1_, x0:x1] = P.rgb(0.10, 0.09, 0.09)
    return img


def flagstone(h, w, ppm, seed, moss=0.6):
    img = bricks(h, w, ppm, seed, z_base=-9, moss=0.0, rowh=0.55)
    n = P.fbm(h, w, max(2.0, 0.5 * ppm), 3, seed + 9)
    m = P.sstep(0.56, 0.62, n + 0.10 * moss)
    mcol = P.mix(P.rgb(0.28, 0.44, 0.16), P.rgb(0.55, 0.68, 0.24), P.sstep(0.3, 0.8, n))
    return img * (1 - m[..., None] * 0.7) + mcol * (m[..., None] * 0.7)


def tree_crest(img, ppm, cu, cv, size):
    """Valencious sigil: golden tree with root-crown, drawn into img around pixel (cu, cv)."""
    h, w = img.shape[:2]
    cvv = P.Canvas(h, w)
    s = size
    def p(x, y):
        return (cu + x * s, cv - y * s)
    lw = max(1.5, 0.045 * s)
    cvv.poly([p(0, -0.9), p(0, 0.15)], lw * 2.2)
    for (dx, dy, ex, ey) in ((0, 0.1, -0.55, 0.65), (0, 0.1, 0.55, 0.65), (0, 0.0, -0.75, 0.3), (0, 0.0, 0.75, 0.3), (0, 0.3, 0, 0.95)):
        cvv.poly([p(dx, dy), p(dx * 0.5 + ex * 0.4, dy + (ey - dy) * 0.5 + 0.1), p(ex, ey)], lw * 2)
    for (dx, dy, ex, ey) in ((0, -0.8, -0.5, -1.0), (0, -0.8, 0.5, -1.0), (0, -0.85, -0.22, -1.1), (0, -0.85, 0.22, -1.1)):
        cvv.poly([p(dx, dy), p(ex, ey)], lw * 1.6)
    ang = np.linspace(0, 2 * math.pi, 40)
    cvv.poly([p(0.62 * math.cos(a), 0.55 + 0.55 * math.sin(a)) for a in ang], lw * 1.2)
    for (lx, ly) in ((-0.55, 0.65), (0.55, 0.65), (-0.75, 0.3), (0.75, 0.3), (0, 0.95), (-0.3, 0.8), (0.3, 0.8)):
        cvv.dot(*p(lx, ly), lw * 3.4)
    a = 1 - P.sstep(lw * 0.9, lw * 1.9, cvv.dist)
    col = P.mix(GOLD_D, GOLD, np.clip(P.blur(1 - a, 2) * 0 + 0.85, 0, 1))
    return img * (1 - a[..., None]) + col * a[..., None]


def banner_cloth(h, w, ppm, seed):
    """Blue cloth, gold border + tree crest; row 0 = top."""
    n = P.fbm(h, w, max(2.0, 0.15 * ppm), 3, seed)
    img = P.mix(ROYAL_D, ROYAL, P.sstep(0.2, 0.8, n * 0.6 + 0.35))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    b = max(3, int(0.06 * ppm))
    e = np.minimum(np.minimum(xx, w - 1 - xx), yy)
    border = (e < b) & (e >= b * 0.4)
    img = np.where(border[..., None], GOLD[None, None, :] * (0.9 + 0.1 * n[..., None]), img)
    img = tree_crest(img, ppm, w * 0.5, h * 0.36, w * 0.30)
    # gold stripe band under crest
    band = (np.abs(yy - h * 0.72) < b * 0.9)
    img = np.where(band[..., None], GOLD[None, None, :] * 0.95, img)
    return img


def wood(h, w, ppm, seed, dark=0.0):
    n = P.fbm(h, w, max(2.0, 0.6 * ppm), 3, seed)
    yy = np.arange(h, dtype=np.float32)[:, None]
    grain = 0.5 + 0.5 * np.sin(yy * 0.7 + n * 9)
    t = np.clip(0.35 + 0.35 * n + 0.2 * grain - dark, 0, 1)
    return P.mix(WOOD_D, WOOD_L, t)


def straw(h, w, ppm, seed):
    n = P.fbm(h, w, max(2.0, 0.25 * ppm), 3, seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    st = 0.5 + 0.5 * np.sin(xx * 1.7 + n * 12) * np.sin(yy * 0.3 + n * 5)
    return P.mix(P.rgb(0.62, 0.46, 0.2), STRAW, np.clip(0.4 + 0.45 * n + 0.15 * st, 0, 1))


def dirt(h, w, ppm, seed, ring=None):
    n_b = P.fbm(h, w, max(3.0, 1.2 * ppm), 3, seed)
    n_m = P.fbm(h, w, max(2.0, 0.3 * ppm), 3, seed + 4)
    base = P.mix(P.rgb(0.55, 0.41, 0.26), P.rgb(0.76, 0.62, 0.42), np.clip(n_b * 0.8 + n_m * 0.4, 0, 1))
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # scattered straw + pebbles
    rs = np.random.RandomState(seed)
    for _ in range(int(h * w / 900)):
        x, y = rs.randint(0, w), rs.randint(0, h)
        ln = rs.randint(3, 8)
        if x + ln < w:
            base[y, x:x + ln] = np.clip(base[y, x:x + ln] * 0.5 + STRAW * 0.5, 0, 1)
    if ring:
        cu, cv, r = ring
        d = np.hypot(xx - cu, yy - cv)
        rr = P.sstep(r, r - 3, d) * 0.0 + (1 - P.sstep(1.5, 4.0, np.abs(d - r)))
        base = base * (1 - rr[..., None] * 0.35) + P.rgb(0.40, 0.30, 0.20) * rr[..., None] * 0.35
    return base


def target_rings(h, w, ppm, seed):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot(xx - w / 2, yy - h / 2) / (min(h, w) / 2)
    img = straw(h, w, ppm, seed)
    cols = [(0.35, ROYAL), (0.6, P.rgb(0.95, 0.93, 0.88)), (0.8, ROYAL), (1.0, P.rgb(0.95, 0.93, 0.88))]
    out = img.copy()
    band = 1.0
    ring_cols = [(0.16, GOLD), (0.34, ROYAL), (0.55, P.rgb(0.95, 0.93, 0.88)), (0.78, ROYAL), (0.94, P.rgb(0.95, 0.93, 0.88))]
    for r, c in reversed(ring_cols):
        m = (d < r).astype(np.float32)
        out = out * (1 - m[..., None]) + c[None, None, :] * m[..., None] * (0.92 + 0.08 * P.fbm(h, w, 4, 2, seed)[..., None])
    out = np.where((d > 0.94)[..., None], img * 0.85, out)
    return out


def roof_tiles(h, w, ppm, seed):
    """royal blue scalloped roof tiles; row 0 = top (apex side of the chart is v max)."""
    rs = np.random.RandomState(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    n = P.fbm(h, w, max(2.0, 0.3 * ppm), 3, seed)
    img = np.zeros((h, w, 3), np.float32)
    rowh = max(6.0, 0.30 * ppm)
    tw = max(6.0, 0.42 * ppm)
    r = np.floor(yy / rowh)
    off = (r % 2) * tw * 0.5
    fx = ((xx + off) % tw) / tw
    fy = (yy % rowh) / rowh
    scallop = np.sqrt(((fx - 0.5) * 1.0) ** 2 + (fy - 0.1) ** 2 * 0.6)
    edge = P.sstep(0.42, 0.55, scallop)
    base = P.mix(ROYAL_D, ROYAL, np.clip(0.35 + 0.5 * n + 0.25 * (1 - fy), 0, 1))
    hi = np.clip(P.sstep(0.0, 0.25, 1 - fy) * 0.0 + (1 - P.sstep(0.02, 0.18, fy)) * 0.5, 0, 1)
    img = base * (1 - hi[..., None] * 0.0)
    img = img * (1 - 0.35 * edge[..., None]) + np.clip(ROYAL * 1.45, 0, 1) * (hi[..., None] * 0.4)
    band = (yy > h - 0.34 * ppm)
    img = np.where(band[..., None], KP_GOLD_TRIM(h, w, xx, yy, ppm), img)
    return np.clip(img, 0, 1)


def KP_GOLD_TRIM(h, w, xx, yy, ppm):
    stripe = 0.5 + 0.5 * np.sin(xx / max(2.0, 0.12 * ppm))
    return P.mix(GOLD_D, GOLD, stripe.astype(np.float32))
