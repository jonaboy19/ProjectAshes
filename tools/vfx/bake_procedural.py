"""Procedural (numpy) flipbooks: lightning sheet and looping magic swirl.

Run inside Blender's bundled Python (it ships numpy, we have no system Python):
  blender -b --python tools/vfx/bake_procedural.py -- <lightning_sheet|magic_swirl> <out_dir>

Both are drawn at 2x and box-downsampled, coloured with the storybook palette (warm white core,
golden mid, blue-violet edge) and written as straight-alpha sRGB atlases (4x4 frames, 256 px = 1024).
"""
import sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flipbook_common as fc

COLS = ROWS = 4
FS = 256
SS = 2
N = COLS * ROWS


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def lin(c):  # sRGB hex-ish tuple (0..1) -> linear
    c = np.array(c, np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


class VNoise:
    """Tiling value noise on a 256 lattice, smooth-interpolated."""

    def __init__(self, seed):
        self.t = np.random.RandomState(seed).rand(256, 256).astype(np.float32)

    def __call__(self, x, y):
        xi = np.floor(x).astype(np.int32); yi = np.floor(y).astype(np.int32)
        xf = x - xi; yf = y - yi
        xf = xf * xf * (3 - 2 * xf); yf = yf * yf * (3 - 2 * yf)
        t = self.t
        a = t[yi & 255, xi & 255]; b = t[yi & 255, (xi + 1) & 255]
        c = t[(yi + 1) & 255, xi & 255]; d = t[(yi + 1) & 255, (xi + 1) & 255]
        return (a * (1 - xf) + b * xf) * (1 - yf) + (c * (1 - xf) + d * xf) * yf

    def fbm(self, x, y, octaves=4):
        s, amp, tot = 0, 0.5, 0
        for _ in range(octaves):
            s = s + amp * self(x, y); tot += amp
            x = x * 2.03 + 17.1; y = y * 2.03 + 3.7; amp *= 0.5
        return s / tot


# ------------------------------------------------------------------ lightning
def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy + 1e-9
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1)
    return np.hypot(px - (ax + t * dx), py - (ay + t * dy))


def bolt_points(rng, x0, y0, x1, y1, disp, depth):
    pts = [(x0, y0), (x1, y1)]
    for _ in range(depth):
        new = [pts[0]]
        for (ax, ay), (bx, by) in zip(pts[:-1], pts[1:]):
            mx, my = (ax + bx) / 2, (ay + by) / 2
            L = math.hypot(bx - ax, by - ay)
            nx, ny = -(by - ay) / (L + 1e-9), (bx - ax) / (L + 1e-9)
            o = rng.randn() * disp * L * 0.5
            new += [(mx + nx * o, my + ny * o), (bx, by)]
        pts = new
        disp *= 0.85
    return pts


def lightning_frame(k, size):
    """One frame of the 16-frame strike: leader (0-1), full bolt + flash (2-6), flicker, fade."""
    env = [0.30, 0.65, 1.0, 1.0, 0.95, 1.0, 0.80, 0.90, 0.65, 0.55, 0.38, 0.28, 0.17, 0.10, 0.05, 0.02][k]
    s = size
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    px, py = xx / s, yy / s
    base = np.random.RandomState(7)                    # the strike keeps its shape...
    rng = np.random.RandomState(100 + k // 2)          # ...with fine jitter that changes every 2 frames
    top = (0.52, -0.02)
    hit = (0.47, 0.80)
    main = bolt_points(base, *top, *hit, 0.16, 5)
    fine = bolt_points(rng, *top, *hit, 0.018, 5)
    main = [((a[0] * 0.85 + b[0] * 0.15), (a[1] * 0.85 + b[1] * 0.15)) for a, b in zip(main, fine[:len(main)])] if len(main) == len(fine) else main
    reveal = 0.35 + 0.65 * min(1.0, (k + 1) / 3.0)     # leader grows down the path in the first frames
    n_show = max(2, int(len(main) * reveal))
    segs = [(main[i], main[i + 1], 1.0) for i in range(n_show - 1)]
    # branches: fork from random points on the main bolt, drift outward/downward
    brng = np.random.RandomState(31)
    for i in range(6):
        j = brng.randint(len(main) // 6, len(main) - len(main) // 5)
        if j >= n_show:
            continue
        sx, sy = main[j]
        d = 1 if brng.rand() > 0.5 else -1
        ex, ey = sx + d * (0.10 + 0.12 * brng.rand()), sy + 0.10 + 0.14 * brng.rand()
        bp = bolt_points(np.random.RandomState(60 + i + 5 * (k // 3)), sx, sy, ex, ey, 0.22, 3)
        for a, b in zip(bp[:-1], bp[1:]):
            segs.append((a, b, 0.5))
    core = np.zeros_like(px); glow = np.zeros_like(px); halo = np.zeros_like(px)
    for (a, b, w) in segs:
        dd = seg_dist(px, py, a[0], a[1], b[0], b[1])
        wc = 0.0055 * w; wg = 0.017 * w; wh = 0.055 * w
        core = np.maximum(core, np.exp(-(dd / wc) ** 2))
        glow = np.maximum(glow, np.exp(-(dd / wg) ** 2))
        halo = np.maximum(halo, np.exp(-(dd / wh) ** 2))
    # ground strike: flash disc + star rays, strongest in frames 2-8
    hx, hy = hit
    r = np.hypot(px - hx, (py - hy) * 1.6)
    ang = np.arctan2(py - hy, px - hx)
    hf = max(0.0, 1.0 - abs(k - 4) / 6.0)
    star = np.exp(-(r / 0.05) ** 2) + 0.7 * np.exp(-r / 0.07) * (0.5 + 0.5 * np.cos(7 * ang + 0.5)) ** 4
    ring = np.exp(-((r - (0.04 + 0.02 * k)) / 0.012) ** 2) * (0.8 * max(0.0, 1 - k / 9.0))
    core = np.clip(core * env + 0.9 * hf * star, 0, 1)
    glow = np.clip(glow * env + 0.6 * hf * np.exp(-(r / 0.10) ** 2) + ring, 0, 1)
    halo = np.clip(halo * env * 0.75 + 0.35 * hf * np.exp(-(r / 0.2) ** 2), 0, 1)
    white = lin((1.0, 0.99, 0.93)); gold = lin((1.0, 0.86, 0.42)); violet = lin((0.50, 0.42, 0.98))
    rgb = (violet[None, None] * halo[..., None] * 0.9 + gold[None, None] * glow[..., None] * 0.9)
    rgb = rgb / np.maximum(halo * 0.9 + glow * 0.9, 1e-4)[..., None]
    rgb = rgb * (1 - core[..., None]) + white[None, None] * core[..., None]
    a = np.clip(halo * 0.55 + glow * 0.9 + core, 0, 1)
    return np.concatenate([rgb * a[..., None], a[..., None]], -1).astype(np.float32)


# ------------------------------------------------------------------ magic swirl
def swirl_frame(k, size):
    """Looping vortex: 3 log-spiral arms, rigid rotation of 1/3 turn over 16 frames, gold core, violet rim."""
    s = size
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    u = (xx + 0.5) / s * 2 - 1
    v = (yy + 0.5) / s * 2 - 1
    v = v * 1.0
    r = np.hypot(u, v)
    th = np.arctan2(v, u)
    ph = 2 * math.pi / 3 * (k / N)                     # arms are 3-fold symmetric -> seamless loop
    nz = VNoise(5)
    tt = th - ph
    ln = np.log(r + 0.06)
    # domain warp in the rotating frame so the wobble travels with the arms
    wx = (np.cos(tt) * r * 3 + 8); wy = (np.sin(tt) * r * 3 + 8)
    warp = nz.fbm(wx * 1.6, wy * 1.6, 4) - 0.5
    arm = 0.5 + 0.5 * np.cos(3 * (tt + 1.9 * ln) + 2.2 * warp)
    body = smoothstep(0.42, 0.9, arm)
    env = smoothstep(0.03, 0.22, r) * (1 - smoothstep(0.62, 0.93, r + 0.06 * warp))
    band = body * env
    rim = np.exp(-((r - 0.83) / 0.028) ** 2) * (0.6 + 0.4 * np.cos(9 * tt + 2 * ph * 3))
    core = np.exp(-(r / 0.16) ** 2)
    # sparkles: fixed random stars that orbit with the arms and twinkle in a loop
    sp = np.zeros_like(r)
    rs = np.random.RandomState(11)
    for i in range(26):
        rr = 0.18 + 0.7 * rs.rand(); aa = rs.rand() * 2 * math.pi + ph * (1.0 + 0.3 * rs.rand())
        cx, cy = rr * math.cos(aa), rr * math.sin(aa)
        tw = 0.5 + 0.5 * math.sin(2 * math.pi * (k / N) * (1 + i % 2) + i)
        dd = np.hypot(u - cx, v - cy)
        sz = 0.012 + 0.012 * rs.rand()
        sp = np.maximum(sp, tw * (np.exp(-(dd / sz) ** 2) + 0.35 * np.exp(-(np.abs(u - cx) / (sz * 0.35)) ** 2 - ((v - cy) / (sz * 4)) ** 2)))
    glow = np.exp(-(r / 0.55) ** 2) * 0.18 * env
    halo = np.clip(band * 0.95 + glow, 0, 1)
    hot = np.clip(band * smoothstep(0.75, 1.0, arm) + core * 0.9 + sp, 0, 1)
    white = lin((1.0, 0.98, 0.88)); gold = lin((1.0, 0.78, 0.32)); violet = lin((0.52, 0.36, 0.95))
    # colour by radius: gold near the middle, violet toward the rim
    tcol = smoothstep(0.15, 0.85, r)[..., None]
    base = gold[None, None] * (1 - tcol) + violet[None, None] * tcol
    rgb = base * (1 - hot[..., None] * 0.85) + white[None, None] * hot[..., None] * 0.85
    a = np.clip(halo + rim * 0.8 + core * 0.9 + sp, 0, 1)
    rgb = rgb * (1 - 0.0)
    return np.concatenate([rgb * a[..., None], a[..., None]], -1).astype(np.float32)


EFFECTS = {
    "lightning_sheet": (lightning_frame, (1.0, 0.92, 0.6), 0.25),
    "magic_swirl": (swirl_frame, (0.8, 0.6, 0.9), 0.35),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name, out_dir = argv[0], argv[1]
    fn, fill, toon = EFFECTS[name]
    frames = []
    for k in range(N):
        px = fc.box_down(fn(k, FS * SS), SS)
        frames.append(fc.finish_frame(px, fill, toon, 5))
    path = os.path.join(out_dir, name + ".png")
    fc.write_atlas(path, frames, COLS, ROWS)
    fc.report(path, frames, COLS, ROWS)


if __name__ == "__main__":
    main()
