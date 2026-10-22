# Hand-painted tack atlas (512 px): 4 x 4 cells of 128 px, the heraldic emblem takes 2 x 2 cells.
# Cell layout is defined by horse_tack.CELL (key -> cell x, cell y from the bottom, w, h in cells).
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hx_common as X

CELL = {
    "EMBLEM": (0, 2, 2, 2), "RED": (2, 3, 1, 1), "GOLD": (3, 3, 1, 1), "LEATHER": (2, 2, 1, 1), "DARK": (3, 2, 1, 1),
    "STEEL": (0, 1, 1, 1), "BRASS": (1, 1, 1, 1), "WOOD": (2, 1, 1, 1), "WOODD": (3, 1, 1, 1), "CREAM": (0, 0, 1, 1),
    "IRON": (1, 0, 1, 1), "PAINT": (2, 0, 1, 1), "STRAW": (3, 0, 1, 1)}


def _noise(rng, h, w, k):
    a = rng.random((h // k + 2, w // k + 2)).astype(np.float32)
    ys = np.linspace(0, a.shape[0] - 2, h)
    xs = np.linspace(0, a.shape[1] - 2, w)
    yi, xi = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = (ys - yi)[:, None], (xs - xi)[None, :]
    a00 = a[yi][:, xi]; a01 = a[yi][:, xi + 1]; a10 = a[yi + 1][:, xi]; a11 = a[yi + 1][:, xi + 1]
    return (a00 * (1 - fx) + a01 * fx) * (1 - fy) + (a10 * (1 - fx) + a11 * fx) * fy


def paint_atlas(size=512):
    """vertical light gradient (cool shadow at the bottom -> warm highlight at the top), mottling, painted specular bands"""
    rng = np.random.default_rng(7)
    img = np.zeros((size, size, 4), np.float32)
    img[..., 3] = 1.0
    cs = size // 4

    def blockp(key, base, hi, lo=None, mott=0.10, grain=0.0, band=None, weave=0.0, streak=0.0):
        cx, cy, cw, ch = CELL[key]
        w, h = cw * cs, ch * cs
        t = np.linspace(0, 1, h)[:, None, None] * np.ones((1, w, 1), np.float32)
        base, hi = np.array(base, np.float32), np.array(hi, np.float32)
        lo_ = np.array(lo if lo is not None else base * np.array([0.55, 0.55, 0.75]), np.float32)
        col = np.where(t < 0.5, lo_ + (base - lo_) * (t / 0.5), base + (hi - base) * ((t - 0.5) / 0.5)).astype(np.float32)
        nz = _noise(rng, h, w, 8)[..., None] * 0.6 + _noise(rng, h, w, 3)[..., None] * 0.4
        col = col * (1 + mott * (nz - 0.5) * 2)
        if grain:
            g = _noise(rng, h, w, 2)[..., None]
            col = col * (1 + grain * (np.tile(_noise(rng, 1, w, 3), (h, 1))[..., None] - 0.5) * 2 + 0.3 * grain * (g - 0.5))
        if streak:
            col = col * (1 + streak * (np.tile(_noise(rng, h, 1, 2), (1, w))[..., None] - 0.5) * 2)
        if weave:
            yy, xx = np.mgrid[0:h, 0:w]
            col = col * (1 + weave * (((xx // 2 + yy // 2) % 2) - 0.5))[..., None]
        if band:
            ty = np.linspace(0, 1, h)[:, None]
            b = np.exp(-((ty - band[0]) / band[1]) ** 2)[..., None] * np.ones((1, w, 1), np.float32)
            col = col + b * band[2]
        img[cy * cs:cy * cs + h, cx * cs:cx * cs + w, :3] = np.clip(col, 0, 1)

    blockp("RED", (.70, .09, .10), (.93, .26, .18), mott=0.07, weave=0.05)
    blockp("GOLD", (.95, .74, .18), (1.0, .93, .55), lo=(.62, .42, .10), mott=0.05, band=(0.75, 0.08, 0.15), streak=0.05)
    blockp("LEATHER", (.55, .32, .15), (.76, .50, .26), mott=0.16, grain=0.05)
    blockp("DARK", (.30, .17, .09), (.48, .30, .16), mott=0.14, grain=0.04)
    blockp("STEEL", (.55, .58, .66), (.90, .93, 1.0), lo=(.28, .31, .44), mott=0.05, band=(0.78, 0.07, 0.20), streak=0.04)
    blockp("BRASS", (.86, .66, .26), (1.0, .90, .55), lo=(.55, .38, .12), mott=0.05, band=(0.75, 0.08, 0.18))
    blockp("WOOD", (.68, .47, .24), (.88, .66, .38), mott=0.10, grain=0.16)
    blockp("WOODD", (.44, .28, .14), (.62, .42, .22), mott=0.10, grain=0.14)
    blockp("CREAM", (.93, .86, .70), (1.0, .96, .84), mott=0.05, weave=0.03)
    blockp("IRON", (.24, .25, .30), (.52, .55, .64), lo=(.10, .10, .17), mott=0.06, band=(0.80, 0.06, 0.12))
    blockp("PAINT", (.20, .36, .72), (.42, .62, .95), lo=(.09, .14, .42), mott=0.06)
    blockp("STRAW", (.90, .74, .34), (1.0, .92, .55), lo=(.55, .40, .22), mott=0.10, grain=0.12)

    # ---- heraldic emblem (2 x 2 cells): red field, gold border, crown over a lion's head badge
    cx, cy, cw, ch = CELL["EMBLEM"]
    w, h = cw * cs, ch * cs
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    s, t = xx / (w - 1), yy / (h - 1)
    field = np.array([.70, .09, .10], np.float32)
    col = field * (0.75 + 0.35 * t[..., None]) * (1 + 0.06 * (_noise(rng, h, w, 6)[..., None] - 0.5) * 2)
    gold = np.array([.96, .76, .20], np.float32)
    goldl = np.array([1.0, .92, .55], np.float32)
    golddk = np.array([.66, .45, .10], np.float32)
    aa = 1.6 / w

    def paint(mask, c):
        nonlocal col
        m_ = np.clip(mask, 0, 1)[..., None]
        col = col * (1 - m_) + np.array(c, np.float32) * m_

    def sm(d):
        return np.clip(0.5 - d / aa, 0, 1)
    bx = np.minimum(np.minimum(s, 1 - s), np.minimum(t, 1 - t))
    paint(sm(np.abs(bx - 0.06) - 0.022), gold)
    paint(sm(np.abs(bx - 0.115) - 0.006), goldl)
    r = np.hypot(s - 0.5, t - 0.42)
    paint(sm(np.abs(r - 0.335) - 0.016), gold)
    paint(sm(r - 0.322) * 0.30, (.45, .04, .07))
    ang = np.arctan2(t - 0.42, s - 0.5)
    rm = 0.235 + 0.035 * np.sin(11 * ang) ** 2 + 0.012 * np.sin(5 * ang)
    paint(sm(r - rm), golddk)
    paint(sm(r - (rm - 0.035)), gold)
    for ex in (-0.13, 0.13):
        paint(sm(np.hypot(s - 0.5 - ex * 1.35, t - 0.585) - 0.042), gold)
    paint(sm(np.hypot(s - 0.5, t - 0.40) - 0.135), (1.0, .84, .38))
    for ex in (-0.05, 0.05):
        paint(sm(np.hypot(s - 0.5 - ex, t - 0.445) - 0.016), (.15, .06, .05))
    paint(sm(np.hypot(s - 0.5, t - 0.395) - 0.030), (.95, .70, .45))
    nose = (np.abs(s - 0.5) < 0.024) & (t > 0.345) & (t < 0.395)
    paint(nose.astype(np.float32), (.35, .10, .10))
    paint(sm(np.hypot(s - 0.5, t - 0.335) - 0.030), (.98, .90, .70))
    paint(sm(np.hypot(s - 0.5, t - 0.32) - 0.014), (.12, .05, .05))
    base_y = 0.755
    paint(sm(np.maximum(np.abs(s - 0.5) - 0.135, np.abs(t - base_y) - 0.024)), gold)
    for px in (-0.115, 0.0, 0.115):
        top = 0.90 if px == 0.0 else 0.865
        tri2 = np.maximum(np.abs(s - 0.5 - px) - 0.05 * np.clip((top - t) / (top - base_y), 0, 1), np.maximum(t - top, base_y - t))
        paint(sm(tri2), gold)
        paint(sm(np.hypot(s - 0.5 - px, t - top - 0.012) - 0.020), goldl)
    for px in (-0.07, 0.07, 0.0):
        paint(sm(np.hypot(s - 0.5 - px, t - base_y) - 0.012), (.75, .08, .16))
    img[cy * cs:cy * cs + h, cx * cs:cx * cs + w, :3] = np.clip(col, 0, 1)
    return img


def write_atlas(path=None):
    path = path or os.path.join(X.OUT, "horse_tack_atlas.png")
    X.write_png(path, paint_atlas())
    X.write_tres(os.path.join(X.OUT, "horse_tack.tres"), "horse_tack_atlas.png", 0.7, "cull_mode = 2\n")
    return path
