"""Storybook cel-shaded smoke puff and dust/earth burst flipbooks (numpy, no render engine).

Run:  blender -b --python tools/vfx/bake_puffs.py -- <smoke_puff|dust_burst> <out_dir>

Why not a volume sim for these: the Mantaflow volume renders (tools/vfx/bake_gas_sims.py, kept for
fire) are grainy at 128 px and read as photoreal fog. Our art direction is painted cumulus: chunky
lumps, 3-band warm light / cool blue-violet shadow, soft rims. So the puffs are clusters of spheres
depth-sorted per pixel (creases where lumps meet), cel-shaded, eroded by animated noise at the end.
8x8 frames of 128 px = 1024 atlas, 64 frames.
"""
import sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flipbook_common as fc
from bake_procedural import VNoise, smoothstep, lin

COLS = ROWS = 8
FS = 128
SS = 3
N = COLS * ROWS
NZ = VNoise(3)


def ease_out(t, p=2.2):
    return 1 - (1 - np.clip(t, 0, 1)) ** p


def render_spheres(spheres, s, tones, light=(0.55, 0.7, 0.55), erosion=None, edge_soft=1.4):
    """spheres: list of dict(cx, cy, cz, r, a, seed). Frame space: x,y in [-1,1] (y up).
    tones: (shadow, mid, light, rim) linear-RGB triples. Returns premultiplied RGBA float image."""
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    px = (xx + 0.5) / s * 2 - 1
    py = 1 - (yy + 0.5) / s * 2
    zbuf = np.full((s, s), -9.0, np.float32)
    nx = np.zeros((s, s), np.float32); ny = np.zeros((s, s), np.float32); nz = np.ones((s, s), np.float32)
    alpha = np.zeros((s, s), np.float32)
    tone = np.zeros((s, s, 3), np.float32); has_tone = np.zeros((s, s), np.float32)
    aa = edge_soft * 2.0 / s
    for sp in spheres:
        if sp["a"] <= 0.001 or sp["r"] <= 0.001:
            continue
        dx = px - sp["cx"]; dy = py - sp["cy"]
        d = np.hypot(dx, dy)
        ang = np.arctan2(dy, dx)
        wob = 1 + 0.12 * (NZ(np.cos(ang) * 2.2 + sp["seed"], np.sin(ang) * 2.2 + sp["seed"] * 0.7 + 40) - 0.5) * 2
        re = sp["r"] * wob
        cov = np.clip((re - d) / aa, 0, 1) * sp["a"]
        inside = re > d
        z = sp["cz"] + np.sqrt(np.maximum(re * re - d * d, 0))
        take = inside & (z > zbuf) & (cov > 0)
        zbuf = np.where(take, z, zbuf)
        rr = np.maximum(re, 1e-4)
        nx = np.where(take, dx / rr, nx); ny = np.where(take, dy / rr, ny)
        nz = np.where(take, np.sqrt(np.maximum(1 - (d / rr) ** 2, 0)), nz)
        if "tone" in sp:
            tone[take] = np.array(sp["tone"], np.float32); has_tone = np.where(take, 1.0, has_tone)
        else:
            has_tone = np.where(take, 0.0, has_tone)
        alpha = np.maximum(alpha, np.where(inside, cov, 0))
    L = np.array(light, np.float32); L /= np.linalg.norm(L)
    ndl = nx * L[0] + ny * L[1] + nz * L[2]
    t = ndl * 0.5 + 0.5
    # crevice darkening where lumps overlap: depth relative to a blurred depth
    zb = np.where(alpha > 0.01, zbuf, np.nan)
    band1 = smoothstep(0.42, 0.52, t)
    band2 = smoothstep(0.70, 0.80, t)
    sh, mid, li, rim = [np.array(c, np.float32) for c in tones]
    col = sh[None, None] * (1 - band1[..., None]) + mid[None, None] * band1[..., None]
    col = col * (1 - band2[..., None]) + li[None, None] * band2[..., None]
    # soft warm rim on the sun-side silhouette
    edge = smoothstep(0.62, 0.95, 1 - nz) * smoothstep(0.1, 0.5, ndl + 0.2)
    col = col + rim[None, None] * edge[..., None] * 0.35
    # small painterly texture so flat bands do not look vector-flat
    grain = (NZ(xx * 0.35, yy * 0.35) - 0.5) * 0.10
    col = col * (1 + grain[..., None])
    if (has_tone > 0).any():
        col = np.where(has_tone[..., None] > 0, tone * (0.55 + 0.75 * band1[..., None] * 0.6 + 0.35 * band2[..., None]), col)
    if erosion is not None:
        alpha = alpha * erosion
    return np.concatenate([col * alpha[..., None], alpha[..., None]], -1)


def erosion_mask(s, k, start, seed=9):
    """Animated noise dissolve: 1 = solid. threshold rises with time after `start` (0..1)."""
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    n = 0.65 * NZ(xx * 0.012 + seed + k * 0.05, yy * 0.012 + seed) + 0.35 * NZ(xx * 0.03 + 7, yy * 0.03 + k * 0.07)
    tt = np.clip((k / (N - 1) - start) / (1 - start), 0, 1)
    thr = tt * 1.05
    return smoothstep(thr - 0.35, thr + 0.02, n) * (1 - 0.6 * tt * tt) if tt > 0 else np.ones_like(n)


# ------------------------------------------------------------------ smoke puff
SMOKE_TONES = (lin((0.52, 0.50, 0.74)), lin((0.84, 0.78, 0.76)), lin((1.0, 0.95, 0.86)), lin((1.0, 0.85, 0.62)))


def smoke_frame(k, s):
    t = k / (N - 1)
    rng = np.random.RandomState(4)
    sph = []
    for i in range(26):
        a = math.radians(rng.uniform(-75, 75))
        delay = rng.uniform(0, 0.25)
        lt = np.clip((t - delay) / (1 - delay), 0, 1)
        e = ease_out(lt, 2.4)
        dist = rng.uniform(0.15, 0.75) * 1.12
        cx = math.sin(a) * dist * e * 1.1 + rng.uniform(-0.05, 0.05)
        cy = -0.72 + math.cos(a) * dist * e * 1.0 + 0.10 * lt + 0.06 * rng.rand()
        r = (0.11 + rng.uniform(0.05, 0.12)) * (0.35 + 0.65 * e) * (1 + 0.42 * lt)
        cz = rng.uniform(-0.3, 0.3) + 0.4 * (1 - dist)          # bigger/closer lumps toward the middle sit in front
        a_ = smoothstep(0.0, 0.06, lt) * 0.96
        sph.append(dict(cx=cx, cy=cy, cz=cz, r=r, a=a_, seed=float(i * 3.7)))
    return render_spheres(sph, s, SMOKE_TONES, erosion=erosion_mask(s, k, 0.50))


# ------------------------------------------------------------------ dust / earth burst
DUST_TONES = (lin((0.50, 0.36, 0.42)), lin((0.86, 0.66, 0.44)), lin((1.0, 0.86, 0.60)), lin((1.0, 0.80, 0.50)))
ROCK_TONE = lin((0.42, 0.29, 0.20))
ELEV = math.radians(18)


def dust_frame(k, s):
    t = k / (N - 1)
    rng = np.random.RandomState(12)
    sph = []
    ground = -0.62
    for i in range(30):
        th = rng.uniform(0, 2 * math.pi)
        delay = rng.uniform(0, 0.12)
        lt = np.clip((t - delay) / (1 - delay), 0, 1)
        e = ease_out(lt, 2.6)
        R = (0.10 + rng.uniform(0.26, 0.60) * e)
        wx = math.cos(th) * R
        wz = math.sin(th) * R                                    # +z toward the camera
        r = (0.105 + rng.uniform(0.03, 0.10)) * (0.5 + 0.5 * e) * (1 + 0.6 * lt)
        cx = wx
        cy = ground + wz * math.sin(ELEV) * 0.9 + r * 0.7 + 0.34 * ease_out(lt, 1.6) * rng.uniform(0.5, 1.0) - 0.05 * lt
        a_ = smoothstep(0.0, 0.05, lt) * 0.95
        sph.append(dict(cx=cx, cy=cy, cz=wz, r=r, a=a_, seed=float(i * 5.3)))
    # a few rocks thrown up in arcs
    for i in range(9):
        ang = rng.uniform(-70, 70)
        v = rng.uniform(1.3, 2.0)
        vx = math.sin(math.radians(ang)) * v * 0.55
        vy = math.cos(math.radians(ang)) * v
        tt = t * 0.85
        cx = vx * tt
        cy = ground + 0.05 + vy * tt - 1.35 * tt * tt * 1.1
        r = rng.uniform(0.035, 0.075)
        vis = 1.0 if cy > ground + 0.02 else 0.0
        a_ = vis * (1 - smoothstep(0.7, 0.98, t))
        sph.append(dict(cx=cx, cy=cy, cz=rng.uniform(0.0, 0.8), r=r, a=a_, seed=float(i * 9.1), tone=ROCK_TONE))
    return render_spheres(sph, s, DUST_TONES, light=(0.5, 0.75, 0.5), erosion=erosion_mask(s, k, 0.55, 21))


EFFECTS = {"smoke_puff": (smoke_frame, (0.8, 0.75, 0.75), 0.0), "dust_burst": (dust_frame, (0.85, 0.65, 0.45), 0.0)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    name, out_dir = argv[0], argv[1]
    fn, fill, toon = EFFECTS[name]
    frames = [fc.finish_frame(fc.box_down(fn(k, FS * SS), SS), fill, toon) for k in range(N)]
    path = os.path.join(out_dir, name + ".png")
    fc.write_atlas(path, frames, COLS, ROWS)
    fc.report(path, frames, COLS, ROWS)


if __name__ == "__main__":
    main()
