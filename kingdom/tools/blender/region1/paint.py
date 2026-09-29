"""numpy painting helpers (runtime: Blender's bundled numpy): noise, SDF strokes, runes, colour ops.
Coordinates: pixel arrays are (h, w[, c]) with row 0 = TOP of the image."""
import numpy as np, math

def smooth(x):
    return x * x * (3 - 2 * x)

def sstep(a, b, x):
    return smooth(np.clip((x - a) / (b - a + 1e-9), 0, 1))

def value_noise(h, w, cell, seed):
    """Smooth value noise, cell = feature size in px."""
    rs = np.random.RandomState(int(seed) % 4294967295)
    gh, gw = int(h / cell) + 3, int(w / cell) + 3
    g = rs.rand(gh, gw).astype(np.float32)
    ys = (np.arange(h, dtype=np.float32) / cell); xs = (np.arange(w, dtype=np.float32) / cell)
    y0 = ys.astype(int); x0 = xs.astype(int); fy = smooth(ys - y0)[:, None]; fx = smooth(xs - x0)[None, :]
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(h, w, cell, octaves=4, seed=0, gain=0.5):
    out = np.zeros((h, w), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += amp * value_noise(h, w, max(cell / (2 ** o), 2.0), seed + o * 101); tot += amp; amp *= gain
    return out / tot

def blur(a, r):
    """Separable gaussian blur (r = sigma in px) via FFT-free convolution; works for 2D or 3D (h,w,c)."""
    if r <= 0.3: return a
    k = int(max(1, math.ceil(r * 3)))
    xs = np.arange(-k, k + 1, dtype=np.float32); ker = np.exp(-(xs ** 2) / (2 * r * r)); ker /= ker.sum()
    def conv_axis(x, axis):
        pad = [(0, 0)] * x.ndim; pad[axis] = (k, k)
        xp = np.pad(x, pad, mode='edge')
        out = np.zeros_like(x, dtype=np.float32)
        for i, kv in enumerate(ker):
            sl = [slice(None)] * x.ndim; sl[axis] = slice(i, i + x.shape[axis])
            out += kv * xp[tuple(sl)]
        return out
    return conv_axis(conv_axis(a.astype(np.float32), 0), 1)

class Canvas:
    """Signed distance field of strokes (pixels). dist = distance to nearest stroke centreline in px."""
    def __init__(self, h, w):
        self.h, self.w = h, w; self.dist = np.full((h, w), 1e4, np.float32)
    def seg(self, p0, p1, reach):
        x0, y0 = p0; x1, y1 = p1
        xa = int(max(0, min(x0, x1) - reach)); xb = int(min(self.w, max(x0, x1) + reach + 1))
        ya = int(max(0, min(y0, y1) - reach)); yb = int(min(self.h, max(y0, y1) + reach + 1))
        if xb <= xa or yb <= ya: return
        yy, xx = np.mgrid[ya:yb, xa:xb].astype(np.float32)
        dx, dy = x1 - x0, y1 - y0; L2 = dx * dx + dy * dy + 1e-9
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / L2, 0, 1)
        d = np.hypot(xx - (x0 + t * dx), yy - (y0 + t * dy))
        sub = self.dist[ya:yb, xa:xb]; np.minimum(sub, d, out=sub)
    def poly(self, pts, reach, closed=False):
        for i in range(len(pts) - 1): self.seg(pts[i], pts[i + 1], reach)
        if closed: self.seg(pts[-1], pts[0], reach)
    def circle(self, cx, cy, r, reach, n=None, a0=0.0, a1=2 * math.pi):
        n = n or max(24, int(r * 0.6))
        pts = [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
        self.poly(pts, reach)
    def dot(self, cx, cy, reach):
        self.seg((cx, cy), (cx, cy), reach)

# Rune strokes in a 1 (w) x 2 (h) box, y up. Each rune = list of polylines.
RUNES = {
 'fehu':  [[(0,0),(0,2)], [(0,1.45),(0.8,1.95)], [(0,0.95),(0.8,1.45)]],
 'uruz':  [[(0,0),(0,2),(0.7,1.5),(0.7,0)]],
 'thur':  [[(0,0),(0,2)], [(0,1.6),(0.7,1.1),(0,0.6)]],
 'ansuz': [[(0,0),(0,2)], [(0,2),(0.75,1.5)], [(0,1.4),(0.75,0.9)]],
 'raido': [[(0,0),(0,2),(0.7,1.55),(0,1.1)], [(0,1.1),(0.75,0)]],
 'kenaz': [[(0.7,1.6),(0,1.0),(0.7,0.4)]],
 'gebo':  [[(0,0.1),(0.8,1.9)], [(0,1.9),(0.8,0.1)]],
 'wunjo': [[(0,0),(0,2),(0.7,1.6),(0,1.2)]],
 'hagal': [[(0,0),(0,2)], [(0.75,0),(0.75,2)], [(0,0.85),(0.75,1.15)]],
 'naud':  [[(0,0),(0,2)], [(-0.3,0.6),(0.4,1.5)]],
 'isa':   [[(0,0),(0,2)]],
 'jera':  [[(0.05,1.5),(0.5,1.0),(0.05,0.5)], [(0.6,1.5),(0.15,1.0),(0.6,0.5)]],
 'sowilo':[[(0.6,1.95),(0,1.45),(0.6,0.75),(0,0.15)]],
 'tiwaz': [[(0,0),(0,2)], [(-0.4,1.5),(0,2),(0.4,1.5)]],
 'berkan':[[(0,0),(0,2),(0.65,1.55),(0,1.05),(0.7,0.5),(0,0)]],
 'ehwaz': [[(0,0),(0,2)], [(0.7,0),(0.7,2)], [(0,2),(0.35,1.4),(0.7,2)]],
 'dagaz': [[(0,0),(0.8,2),(0.8,0),(0,2),(0,0)]],
 'ingwaz':[[(0.4,0.2),(0.8,1.0),(0.4,1.8),(0,1.0),(0.4,0.2)]],
 'othala':[[(0.4,2),(0.8,1.3),(0.4,0.6),(0,1.3),(0.4,2)], [(0.15,0.9),(0,0)], [(0.65,0.9),(0.8,0)]],
}
RUNE_KEYS = list(RUNES)

def rune(cv, key, x, y, h_px, reach, rot=0.0):
    """Draw rune with its bottom-left at (x, y_bottom) where y is pixel row of the rune's BOTTOM (rows grow downward)."""
    s = h_px / 2.0
    c, sn = math.cos(rot), math.sin(rot)
    for line in RUNES[key]:
        pts = []
        for (px, py) in line:
            lx, ly = (px - 0.35) * s, py * s        # local, y up, centred on x
            rx = lx * c - ly * sn; ry = lx * sn + ly * c
            pts.append((x + rx, y - ry))
        cv.poly(pts, reach)

def channel_profile(dist, half_w):
    """0 outside, 1 in the middle of the carved channel; soft rim."""
    return 1.0 - sstep(half_w * 0.55, half_w, dist)

def core_profile(dist, half_w):
    return 1.0 - sstep(half_w * 0.18, half_w * 0.55, dist)

def rgb(a, b, c):
    return np.array([a, b, c], np.float32)

def mix(c0, c1, t):
    return c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]

def normal_from_height(hgt, strength_px):
    """Tangent-space normal map (OpenGL, +Y up in image = row decreasing) from a height map (in px units)."""
    hh = hgt * strength_px
    dx = (np.roll(hh, -1, 1) - np.roll(hh, 1, 1)) * 0.5
    dy = (np.roll(hh, 1, 0) - np.roll(hh, -1, 0)) * 0.5   # row-1 is "up"
    n = np.stack([-dx, -dy, np.ones_like(hh)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5
