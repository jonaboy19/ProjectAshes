"""Painted stone charts: albedo, height, emissive core for one atlas rect. Meter-space glyph drawing.
Palette = warm storybook stone, cool violet-blue shadow tint, sunny moss, blue (or ancestor-gold) rune light."""
import math
import numpy as np
import paint as P

STONE_LIGHT = P.rgb(0.72, 0.64, 0.50)
STONE_DARK = P.rgb(0.50, 0.43, 0.35)
STONE_COOL = P.rgb(0.55, 0.56, 0.62)
MOSS_DARK = P.rgb(0.24, 0.40, 0.15)
MOSS_LIGHT = P.rgb(0.50, 0.65, 0.21)

VARIANTS = {
    'blue': dict(groove=P.rgb(0.13, 0.22, 0.34), rim=P.rgb(0.86, 0.90, 0.95), emis=P.rgb(0.22, 0.62, 1.0),
                 emis_hot=P.rgb(0.80, 0.97, 1.0), tint=P.rgb(1.0, 1.0, 1.0), gold_vein=0.0),
    'gold': dict(groove=P.rgb(0.52, 0.34, 0.08), rim=P.rgb(1.0, 0.86, 0.45), emis=P.rgb(1.0, 0.66, 0.16),
                 emis_hot=P.rgb(1.0, 0.94, 0.62), tint=P.rgb(1.04, 0.98, 0.86), gold_vein=1.0),
}


class Ctx:
    def __init__(self, key, w, h, ppm, umin, vmax, seed, variant, z0=0.0, zmax=1.0, part=''):
        self.key, self.w, self.h, self.ppm, self.umin, self.vmax = key, w, h, ppm, umin, vmax
        self.seed, self.variant, self.z0, self.zmax, self.part = seed, variant, z0, zmax, part


class Draw:
    """Meter-space drawing into per-width canvases. u right, v up (chart local)."""
    def __init__(self, ctx):
        self.c = ctx
        self.cv = {}

    def canvas(self, wm, weight=1.0):
        k = (round(wm, 4), round(weight, 3))
        if k not in self.cv:
            self.cv[k] = (P.Canvas(self.c.h, self.c.w), wm, weight)
        return self.cv[k][0]

    def px(self, u, v):
        return ((u - self.c.umin) * self.c.ppm, (self.c.vmax - v) * self.c.ppm)

    def line(self, pts, wm=0.05, weight=1.0, closed=False):
        cv = self.canvas(wm, weight)
        pp = [self.px(*p) for p in pts]
        cv.poly(pp, wm * self.c.ppm * 1.0 + 3, closed=closed)

    def circle(self, cu, cv_, r, wm=0.05, weight=1.0, a0=0.0, a1=2 * math.pi):
        cv = self.canvas(wm, weight)
        x, y = self.px(cu, cv_)
        cv.circle(x, y, r * self.c.ppm, wm * self.c.ppm + 3, a0=-a1, a1=-a0)

    def dot(self, u, v, wm=0.08, weight=1.0):
        cv = self.canvas(wm, weight)
        x, y = self.px(u, v)
        cv.dot(x, y, wm * self.c.ppm + 3)

    def rune(self, key, u, v_bottom, h, wm=0.035, weight=1.0, rot=0.0):
        cv = self.canvas(wm, weight)
        x, y = self.px(u, v_bottom)
        P.rune(cv, key, x, y, h * self.c.ppm, wm * self.c.ppm + 3, rot)

    def diamond(self, u, v, r, wm=0.05, weight=1.0):
        self.line([(u, v + r), (u + r * 0.7, v), (u, v - r), (u - r * 0.7, v)], wm, weight, closed=True)


def paint_chart(ctx, layout, opts=None):
    """returns albedo (h,w,3), height(px units, h,w), emissive (h,w,3)"""
    opts = opts or {}
    h, w, ppm = ctx.h, ctx.w, ctx.ppm
    var = VARIANTS[ctx.variant]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = ctx.umin + (xx + 0.5) / ppm
    v = ctx.vmax - (yy + 0.5) / ppm
    s = ctx.seed
    n_big = P.fbm(h, w, max(2.0, 0.8 * ppm), 4, s)
    n_mid = P.fbm(h, w, max(2.0, 0.17 * ppm), 3, s + 11)
    n_fine = P.fbm(h, w, max(2.0, 0.04 * ppm), 2, s + 23)
    n_patch = P.fbm(h, w, max(2.0, 0.5 * ppm), 3, s + 37)

    # ---- stone base colour: warm light/dark mottling, some cool violet patches, painterly strata
    strata = 0.5 + 0.5 * np.sin((v * 5.0 + n_big * 3.0) * 2.4)
    t = np.clip(n_big * 0.75 + n_mid * 0.35 + strata * 0.12, 0, 1)
    stone = P.mix(STONE_DARK, STONE_LIGHT, P.sstep(0.25, 0.75, t))
    cool = P.sstep(0.58, 0.78, n_patch) * 0.4
    stone = stone * (1 - cool[..., None]) + STONE_COOL[None, None, :] * cool[..., None] * (0.9 + 0.2 * n_mid[..., None])
    stone *= var['tint'][None, None, :]

    # ---- cracks + chips (height)
    ridge = np.abs(P.fbm(h, w, max(2.0, 0.32 * ppm), 3, s + 51) - 0.5) * 2
    crack = (1.0 - P.sstep(0.006, 0.02, ridge)) * P.sstep(0.55, 0.7, n_patch)
    height = (n_big - 0.5) * 0.10 * ppm + (n_mid - 0.5) * 0.03 * ppm + (n_fine - 0.5) * 0.006 * ppm - crack * 0.015 * ppm
    stone *= (1 - 0.35 * crack[..., None])

    # ---- height-above-ground shading (vertical charts) + moss
    key = ctx.key
    zabs = v if key in ('F', 'B', 'L', 'R', 'C') else np.zeros_like(v)
    zloc = zabs - ctx.z0
    moss_amt = opts.get('moss', 1.0)
    if key in ('F', 'B', 'L', 'R', 'C'):
        m = (1.0 - P.sstep(0.0, opts.get('moss_h', 1.1), zloc)) * 1.25 + (n_patch - 0.5) * 0.9
    elif key == 'T':
        m = 0.18 + (n_patch - 0.5) * 1.3
    else:
        m = 0.30 + (n_patch - 0.5) * 1.4
    m = m * moss_amt
    moss = P.sstep(0.42, 0.50, m)                      # crisp painted edge
    rim = np.clip(P.sstep(0.36, 0.50, m) - P.sstep(0.50, 0.62, m), 0, 1) * moss_amt   # bright rim
    mcol = P.mix(MOSS_DARK, MOSS_LIGHT, P.sstep(0.3, 0.8, n_mid * 0.6 + n_fine * 0.4 + rim * 0.5))
    alb = stone * (1 - moss[..., None]) + mcol * moss[..., None]
    height += moss * 0.012 * ppm

    if key in ('F', 'B', 'L', 'R', 'C'):
        ao = 0.70 + 0.30 * P.sstep(0.0, 0.9, zloc)
        alb *= ao[..., None]

    # ---- glyph channels
    d = Draw(ctx)
    layout(d, ctx)
    chan = np.zeros((h, w), np.float32)
    core = np.zeros((h, w), np.float32)
    rimh = np.zeros((h, w), np.float32)
    for (cv, wm, weight) in d.cv.values():
        hw = max(1.6, wm * ppm * 0.5)
        dist = cv.dist
        chan = np.maximum(chan, P.channel_profile(dist, hw) * min(1.0, weight * 1.2))
        core = np.maximum(core, P.core_profile(dist, hw) * weight)
        rimh = np.maximum(rimh, (P.sstep(hw * 0.85, hw * 1.25, dist) * (1 - P.sstep(hw * 1.25, hw * 1.9, dist))) * min(1.0, weight * 1.2))
    depth = opts.get('depth', 0.022) * ppm
    height = height - chan * depth + rimh * depth * 0.35
    alb = alb * (1 - rimh[..., None] * 0.30) + var['rim'][None, None, :] * rimh[..., None] * 0.30
    gv = var['gold_vein']
    if gv:
        # ancestor-gold: warm gilded halo + speckle around channels
        halo = P.blur(chan, 0.03 * ppm)
        speck = P.sstep(0.70, 0.80, n_fine + n_mid * 0.3) * halo * 1.3
        alb = alb * (1 - np.clip(speck, 0, 1)[..., None]) + P.rgb(0.95, 0.74, 0.26)[None, None, :] * np.clip(speck, 0, 1)[..., None]
    alb = alb * (1 - chan[..., None]) + var['groove'][None, None, :] * chan[..., None] * (0.75 + 0.25 * n_mid[..., None])
    # channel floor picks up rune colour even when unlit (so dim state still reads)
    floor = P.mix(var['groove'], var['emis'], np.clip(core, 0, 1) * 0.55)
    alb = alb * (1 - core[..., None] * 0.9) + floor * core[..., None] * 0.9

    # ---- saturation lift + warm grade (storybook)
    lum = (alb * P.rgb(0.3, 0.59, 0.11)[None, None, :]).sum(-1, keepdims=True)
    alb = np.clip(lum + (alb - lum) * 1.14, 0, 1)

    # ---- emissive: core in emissive colour, hot white centre, small halo bleed
    hot = P.sstep(0.55, 1.0, core)
    ecol = P.mix(var['emis'], var['emis_hot'], hot)
    halo = P.blur(core, 0.012 * ppm + 0.8)
    emis = ecol * np.clip(core * 1.0 + halo * 0.35, 0, 1)[..., None]
    return alb.astype(np.float32), height.astype(np.float32), emis.astype(np.float32)
