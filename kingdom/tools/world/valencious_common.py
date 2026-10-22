"""Shared helpers for the Valencious world tools (bible builder, macro generator). numpy/scipy only, deterministic.

World space: metres from Ashford, x east, z south (north = -z), +-6144 m. Raster space: row = z, col = x, row 0 = north edge.
"""
import hashlib
import json
import os

import numpy as np
from scipy import ndimage

SEED = 1066
HALF = 6144.0
WORLD = 2.0 * HALF
HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.abspath(os.path.join(HERE, "..", ".."))
REPO = os.path.abspath(os.path.join(KINGDOM, ".."))
REGIONS_JSON = os.path.join(KINGDOM, "data", "world", "valencious_regions.json")
PLACES_JSON = os.path.join(REPO, "docs", "world", "valencious_places.json")
MACRO_DIR = os.path.join(KINGDOM, "data", "world", "macro")


def load_json(path):
    with open(path, encoding="utf8") as f:
        return json.load(f)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        h.update(f.read())
    return h.hexdigest()


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def lattice_noise(n, period_px, seed, shape=None):
    """Smooth zero-mean unit-ish noise on an n x n grid: a random lattice (one value per `period_px`) cubic-upsampled.
    Deterministic for a given (n, period_px, seed)."""
    shape = shape or (n, n)
    rng = np.random.default_rng(seed)
    ly = int(np.ceil(shape[0] / period_px)) + 4
    lx = int(np.ceil(shape[1] / period_px)) + 4
    lat = rng.standard_normal((ly, lx)).astype(np.float32)
    big = ndimage.zoom(lat, period_px, order=3, mode="reflect", grid_mode=True)
    oy = int(period_px * 1.5)
    ox = int(period_px * 1.5)
    out = big[oy:oy + shape[0], ox:ox + shape[1]]
    return out.astype(np.float32)


def fbm(n, base_period_px, octaves, seed, gain=0.5, shape=None):
    """Sum of lattice noises, each octave half the period; normalised to roughly [-1, 1]."""
    shape = shape or (n, n)
    acc = np.zeros(shape, np.float32)
    amp = 1.0
    tot = 0.0
    p = float(base_period_px)
    for o in range(octaves):
        if p < 1.5:
            break
        acc += amp * lattice_noise(n, p, seed + 101 * o, shape)
        tot += amp
        amp *= gain
        p /= 2.0
    return acc / (tot * 0.55)


def ridged(n, base_period_px, octaves, seed, shape=None):
    """Ridged multifractal in 0..1 (sharp crests)."""
    shape = shape or (n, n)
    acc = np.zeros(shape, np.float32)
    amp = 1.0
    tot = 0.0
    weight = np.ones(shape, np.float32)
    p = float(base_period_px)
    for o in range(octaves):
        if p < 1.5:
            break
        s = lattice_noise(n, p, seed + 211 * o, shape)
        r = 1.0 - np.abs(np.tanh(s * 0.9))
        r = r * r
        r = r * weight
        weight = np.clip(r * 1.6, 0.0, 1.0)
        acc += amp * r
        tot += amp
        amp *= 0.5
        p /= 2.0
    return acc / tot


def region_index(regions, xs, zs, warp=None):
    """Index of the region for every point (arrays of metres): the lobe with the smallest distance / radius.
    `warp` = (dx, dz) arrays of metres added to the point first (organic borders). Returns (idx, score_of_best)."""
    if warp is not None:
        xs = xs + warp[0]
        zs = zs + warp[1]
    best = np.full(xs.shape, np.inf, np.float32)
    idx = np.zeros(xs.shape, np.int16)
    for ri, r in enumerate(regions):
        for lx, lz, lr in r["lobes"]:
            d = np.hypot(xs - lx, zs - lz) / lr
            m = d < best
            best = np.where(m, d, best)
            idx = np.where(m, ri, idx)
    return idx, best


def warp_fields(npx, seed, amp_m):
    """Smooth domain-warp offsets (metres) on an npx grid."""
    wx = fbm(npx, npx / 6.0, 3, seed + 7) * amp_m
    wz = fbm(npx, npx / 6.0, 3, seed + 19) * amp_m
    return wx.astype(np.float32), wz.astype(np.float32)


def px_to_m(npx):
    """Metre coordinates of pixel centres of an npx grid covering the world (cell-centred)."""
    c = (np.arange(npx, dtype=np.float32) + 0.5) * (WORLD / npx) - HALF
    return c


def region_of_points(regions, pts, blend_cfg):
    """Region id for a list of (x, z) world points using the same warped partition as the generator (1024 grid)."""
    npx = 1024
    wx, wz = warp_fields(npx, SEED, blend_cfg["border_warp"])
    c = px_to_m(npx)
    out = []
    for x, z in pts:
        ix = int(np.clip((x + HALF) / WORLD * npx, 0, npx - 1))
        iz = int(np.clip((z + HALF) / WORLD * npx, 0, npx - 1))
        i, _ = region_index(regions, np.array([x], np.float32), np.array([z], np.float32),
                            (np.array([wx[iz, ix]], np.float32), np.array([wz[iz, ix]], np.float32)))
        out.append(regions[int(i[0])]["id"])
    return out
