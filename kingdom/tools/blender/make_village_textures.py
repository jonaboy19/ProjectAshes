"""Shared tileable DETAIL textures for the Blender village / town set.

Run from anywhere:  python3 make_village_textures.py [out_dir]
(default out_dir: kingdom/assets/generated/village_tex). Needs numpy and the bpy
module (Blender 5.x; bpy only reads/scales/writes images, no PIL needed).

Seven surface families, each as three 512x512 maps that tile seamlessly:

    ra_<family>_alb.png   detail albedo, sRGB. Near-neutral and bright (mean ~0.86): the
                          mesh vertex colour (COLOR_0 = palette tint x baked weathering)
                          is multiplied over it, so every house variant recolours for free.
    ra_<family>_nrm.png   OpenGL tangent-space normal map (+Y up the image, as glTF wants).
    ra_<family>_mr.png    glTF metallicRoughness: G = roughness, B = metalness, R = 1.

    family   source                                         tile (m, set in ra_polish.py)
    plaster  generated: lime blotches, trowel strokes, sand grain, hairline cracks   2.4
    wood     generated: long grain + growth lines, checks and a few knots            1.2
    stone    generated: pitted, mottled rock grain with fine fractures               1.1
    roof     generated: split-slate / riven-shingle grain running down the slope     1.0
    thatch   generated: combed straw strands running down the slope                  0.9
    cloth    ambientCG Fabric061 (CC0) weave + generated wrinkles/fading             0.7
    iron     generated: hammer dimples, scale, rust blooms (rust is non-metal)       0.6

The block / shingle / plank SHAPES are still modelled (they carry the silhouette); these
maps only add the surface grain the flat vertex colours lacked. Textures stay 512^2 so the
whole set (21 maps, VRAM-compressed with mipmaps) is ~7 MB on desktop, ~4 MB with ETC2.
"""
import os, sys, math
import numpy as np
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ACG = os.path.join(ROOT, "kingdom", "assets", "incoming", "ambientcg")
OUT = next((a for a in sys.argv[1:] if not a.startswith("-")),
           os.path.join(ROOT, "kingdom", "assets", "generated", "village_tex"))
N = 512
MEAN = 0.86          # detail albedo mean (sRGB); ra_polish.py divides vertex colours by it


# ----------------------------------------------------------------------------- io
def save_png(path, rgb):
    """rgb: float (H, W, 3|4) 0..1, row 0 = TOP of the image."""
    h, w = rgb.shape[:2]
    if rgb.shape[2] == 3:
        rgb = np.concatenate([rgb, np.ones((h, w, 1))], axis=2)
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    img.pixels.foreach_set(np.clip(rgb[::-1], 0, 1).astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    print("wrote", path)


def load_np(path, size=N, noncolor=False):
    img = bpy.data.images.load(path)
    if noncolor:
        img.colorspace_settings.name = "Non-Color"
    img.scale(size, size)
    a = np.empty(size * size * 4, np.float32)
    img.pixels.foreach_get(a)
    bpy.data.images.remove(img)
    a = a.reshape(size, size, 4)[::-1, :, :3]
    if not noncolor:        # Blender gives linear floats for sRGB images -> back to sRGB values
        a = np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(np.clip(a, 0, None), 1 / 2.4) - 0.055)
    return a.astype(np.float64)


# ----------------------------------------------------------------------------- noise
def tile_noise(beta=2.0, seed=0, ax=1.0, ay=1.0, n=N):
    """Seamless 1/f^beta noise in 0..1; ax/ay > 1 squash features along x / y."""
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n)[:, None] * ay
    fx = np.fft.fftfreq(n)[None, :] * ax
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    F *= f ** (-beta / 2)
    F[0, 0] = 0
    r = np.real(np.fft.ifft2(F))
    return (r - r.min()) / (r.max() - r.min())


def band_noise(lo, hi, seed, ax=1.0, ay=1.0, n=N):
    """Seamless noise keeping only spatial frequencies lo..hi (cycles per tile)."""
    rng = np.random.default_rng(seed)
    F = np.fft.fft2(rng.standard_normal((n, n)))
    fy = np.fft.fftfreq(n, 1 / n)[:, None] * ay
    fx = np.fft.fftfreq(n, 1 / n)[None, :] * ax
    f = np.sqrt(fx ** 2 + fy ** 2)
    F *= (f >= lo) & (f <= hi)
    r = np.real(np.fft.ifft2(F))
    return (r - r.min()) / (r.max() - r.min() + 1e-9)


def blur(a, r=1):
    out = a.copy()
    for _ in range(r):
        out = (out + np.roll(out, 1, 0) + np.roll(out, -1, 0) + np.roll(out, 1, 1) + np.roll(out, -1, 1)) / 5
    return out


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def ridged(beta, seed, **kw):
    """Thin dark lines where a noise field crosses 0.5 (cracks / fractures)."""
    return 1.0 - np.abs(tile_noise(beta, seed, **kw) - 0.5) * 2.0


def normal_from_height(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = -(np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5      # row 0 = top: flip for +Y up
    n = np.stack([-gx * strength, -gy * strength, np.ones_like(gx)], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def finish_albedo(lum, tint=(1.0, 0.99, 0.965), chroma=None, mean=MEAN, lo=0.35, contrast=1.0):
    """Scale a luminance map to the shared mean, soft-posterize it (hand-painted feel),
    clamp, apply a faint warm tint/chroma."""
    lum = (lum - lum.mean()) * contrast + mean
    # painterly pass: soft posterize (flat brush-like value bands) blended with the source,
    # then a gentle blur so the steps read as strokes, not print banding
    q = np.round((lum - lo) / (1.0 - lo) * 7) / 7 * (1.0 - lo) + lo
    lum = blur(0.55 * lum + 0.45 * q, 1)
    lum = np.clip(lum, lo, 1.0)
    rgb = lum[..., None] * np.array(tint)[None, None, :]
    if chroma is not None:
        rgb = rgb * chroma
    return np.clip(rgb, 0, 1)


def write_set(name, alb, height, nstrength, rough, metal=None, nrm=None):
    save_png(os.path.join(OUT, f"ra_{name}_alb.png"), alb)
    if nrm is None:
        nrm = normal_from_height(height, nstrength)
    save_png(os.path.join(OUT, f"ra_{name}_nrm.png"), nrm)
    mr = np.stack([np.ones_like(rough), np.clip(rough, 0.02, 1), np.zeros_like(rough) if metal is None else metal],
                  -1)
    save_png(os.path.join(OUT, f"ra_{name}_mr.png"), mr)
    print(f"  {name}: albedo mean {alb.mean():.3f}, roughness {rough.mean():.2f}")


# ----------------------------------------------------------------------------- families
def plaster():
    low = tile_noise(2.6, 1)
    mid = tile_noise(1.8, 2)
    # trowel strokes: soft arcs, stretched diagonally
    strokes = band_noise(3, 14, 3, ax=0.35, ay=1.0)
    strokes = np.roll(strokes, 0, 1)
    sand = blur(np.random.default_rng(4).random((N, N)), 1)
    cracks = smooth(0.965, 0.995, ridged(2.2, 5)) * smooth(0.55, 0.75, tile_noise(2.4, 6))
    h = 0.35 * low + 0.25 * strokes + 0.15 * sand - 0.5 * cracks
    lum = 0.07 * (low - 0.5) + 0.05 * (mid - 0.5) + 0.03 * (strokes - 0.5) + 0.05 * (sand - 0.5) - 0.28 * cracks
    lum = lum + MEAN
    alb = finish_albedo(lum, tint=(1.0, 0.985, 0.96), contrast=1.7)
    rough = 0.9 + 0.08 * (sand - 0.5) - 0.06 * (low - 0.5)
    write_set("plaster", alb, h, 3.0, rough)


def wood():
    # grain runs along U (image x). Long, thin features: squash x frequencies.
    fib = tile_noise(1.6, 11, ax=1.0, ay=0.06)
    fine = tile_noise(1.0, 12, ax=1.0, ay=0.03)
    warp = tile_noise(2.4, 13, ax=5.0) * 60.0
    ys = np.mgrid[0:N, 0:N][0].astype(np.float64)
    rings = 0.5 + 0.5 * np.sin((ys + warp + 12 * tile_noise(2.0, 14, ax=3.0)) * 2 * math.pi / 32.0)
    rings = smooth(0.8, 0.99, rings) * (0.5 + 0.5 * tile_noise(2.2, 18, ax=2.0))
    checks = smooth(0.975, 0.997, ridged(1.8, 15, ax=1.0, ay=0.04)) * smooth(0.6, 0.8, tile_noise(2.2, 16))
    # knots: a few dark elliptical whorls (wrapped)
    rng = np.random.default_rng(17)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    knots = np.zeros((N, N))
    for _ in range(2):
        cx, cy = rng.uniform(0, N), rng.uniform(0, N)
        dx = np.minimum(np.abs(xx - cx), N - np.abs(xx - cx)) / rng.uniform(12, 18)
        dy = np.minimum(np.abs(yy - cy), N - np.abs(yy - cy)) / rng.uniform(5, 8)
        d = np.sqrt(dx ** 2 + dy ** 2)
        knots = np.maximum(knots, smooth(1.0, 0.25, d) * 0.8 + 0.2 * smooth(2.5, 1.0, d) * (0.5 + 0.5 * np.sin(d * 9)))
    h = 0.35 * fib + 0.2 * fine + 0.12 * rings - 0.6 * checks - 0.25 * knots
    lum = MEAN + 0.2 * (fib - 0.5) + 0.1 * (fine - 0.5) - 0.09 * rings - 0.35 * checks - 0.3 * knots
    chroma = np.ones((N, N, 3))
    chroma[..., 0] += 0.02 * (rings - 0.5)
    chroma[..., 2] -= 0.04 * (rings - 0.5)
    alb = finish_albedo(lum, tint=(1.0, 0.975, 0.94), chroma=chroma, contrast=1.3)
    rough = 0.72 + 0.12 * (fib - 0.5) + 0.2 * checks + 0.08 * knots
    write_set("wood", alb, h, 4.0, rough)


def stone():
    low = tile_noise(2.4, 21)
    mid = tile_noise(1.7, 22)
    grain = blur(np.random.default_rng(23).random((N, N)), 1)
    pits = smooth(0.62, 0.8, tile_noise(0.9, 24)) * smooth(0.5, 0.7, tile_noise(2.0, 25))
    frac = smooth(0.975, 0.995, ridged(2.0, 26)) * smooth(0.45, 0.7, tile_noise(2.2, 27))
    speck = smooth(0.8, 0.95, tile_noise(0.6, 28))                     # pale lichen / mica specks
    h = 0.4 * low + 0.3 * mid + 0.15 * grain - 0.35 * pits - 0.5 * frac
    lum = MEAN + 0.1 * (low - 0.5) + 0.08 * (mid - 0.5) + 0.06 * (grain - 0.5) - 0.18 * pits - 0.3 * frac + 0.08 * speck
    chroma = np.ones((N, N, 3))
    warm = tile_noise(2.8, 29) - 0.5
    chroma[..., 0] += 0.05 * warm
    chroma[..., 2] -= 0.05 * warm
    alb = finish_albedo(lum, chroma=chroma, contrast=1.5)
    rough = 0.82 + 0.1 * (grain - 0.5) - 0.12 * (low - 0.5) + 0.1 * pits
    write_set("stone", alb, h, 5.0, rough)


def roof():
    # riven slate / split shingle: long streaks down the slope (along V = image y), flaky edges
    streak = tile_noise(1.5, 31, ax=0.07, ay=1.0)
    fine = tile_noise(0.9, 32, ax=0.05, ay=1.0)
    flake = smooth(0.6, 0.85, tile_noise(1.6, 33, ax=0.4, ay=1.0))
    lichen = smooth(0.78, 0.92, tile_noise(1.2, 34)) * smooth(0.4, 0.7, tile_noise(2.6, 35))
    h = 0.35 * streak + 0.25 * fine + 0.2 * flake - 0.2 * lichen
    lum = MEAN + 0.12 * (streak - 0.5) + 0.08 * (fine - 0.5) - 0.08 * flake + 0.14 * lichen
    chroma = np.ones((N, N, 3))
    chroma[..., 0] += 0.06 * lichen
    chroma[..., 1] += 0.08 * lichen
    chroma[..., 2] -= 0.02 * lichen
    alb = finish_albedo(lum, chroma=chroma, contrast=1.5)
    rough = 0.62 + 0.15 * (fine - 0.5) + 0.25 * lichen + 0.08 * flake
    write_set("roof", alb, h, 4.5, rough)


def thatch():
    # straw strands along V (image y). Sum of very anisotropic noise at two scales + gaps.
    s1 = tile_noise(1.2, 41, ax=0.025, ay=1.0)
    s2 = tile_noise(0.8, 42, ax=0.02, ay=1.0)
    clumps = tile_noise(2.2, 43, ax=0.35, ay=1.0)
    strands = 0.55 * s1 + 0.45 * s2
    gaps = smooth(0.38, 0.15, strands)
    tips = smooth(0.7, 0.9, tile_noise(1.4, 44, ax=0.12, ay=1.0))     # bleached straw ends
    h = 0.6 * strands + 0.25 * clumps - 0.4 * gaps
    lum = MEAN + 0.2 * (strands - 0.5) + 0.08 * (clumps - 0.5) - 0.3 * gaps + 0.08 * tips
    chroma = np.ones((N, N, 3))
    chroma[..., 2] -= 0.05 * (strands - 0.5)
    alb = finish_albedo(lum, tint=(1.0, 0.97, 0.9), chroma=chroma, lo=0.3, contrast=2.2)
    rough = 0.95 + 0.04 * (strands - 0.5)
    write_set("thatch", alb, h, 6.0, rough)


def cloth():
    src = os.path.join(ACG, "Fabric061")
    col = load_np(os.path.join(src, "Fabric061_2K-JPG_Color.jpg"))
    nrm = load_np(os.path.join(src, "Fabric061_2K-JPG_NormalGL.jpg"), noncolor=True)
    rgh = load_np(os.path.join(src, "Fabric061_2K-JPG_Roughness.jpg"), noncolor=True)[..., 0]
    lum = col @ np.array([0.2126, 0.7152, 0.0722])
    lum = (lum - lum.mean()) * 0.6                                     # weave, toned down
    wrinkles = band_noise(2, 9, 51, ax=0.4, ay=1.0)
    fade = tile_noise(2.6, 52)
    lum = MEAN + lum + 0.06 * (wrinkles - 0.5) + 0.07 * (fade - 0.5)
    alb = finish_albedo(lum, tint=(1.0, 0.99, 0.97))
    # add the wrinkles to the normal map as well
    wn = normal_from_height(wrinkles, 2.0) * 2 - 1
    n = nrm * 2 - 1
    n = np.stack([n[..., 0] + wn[..., 0], n[..., 1] + wn[..., 1], n[..., 2]], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    rough = np.clip(0.85 + (rgh - rgh.mean()) * 0.5, 0.6, 1.0)
    write_set("cloth", alb, None, 0, rough, nrm=n * 0.5 + 0.5)


def iron():
    dimple = band_noise(10, 28, 61)
    scale = tile_noise(1.8, 62)
    rust_m = smooth(0.6, 0.78, tile_noise(2.2, 63)) * (0.6 + 0.4 * tile_noise(0.8, 64))
    pits = smooth(0.8, 0.95, tile_noise(0.7, 65)) * rust_m
    h = 0.4 * dimple + 0.2 * scale + 0.25 * rust_m - 0.3 * pits
    lum = 0.8 + 0.08 * (dimple - 0.5) + 0.1 * (scale - 0.5)
    rgb = lum[..., None] * np.array([1.0, 1.0, 1.0])
    rust = np.array([1.0, 0.62, 0.38]) * (0.95 + 0.1 * tile_noise(1.0, 66)[..., None])
    rgb = rgb * (1 - rust_m[..., None]) + rust * rust_m[..., None]
    rgb = rgb * (1 - 0.4 * pits[..., None])
    alb = np.clip(rgb - rgb.mean() + MEAN, 0.3, 1.0)
    rough = 0.42 + 0.1 * (scale - 0.5) + 0.45 * rust_m
    metal = np.clip(1.0 - 1.2 * rust_m, 0, 1)
    write_set("iron", alb, h, 3.5, rough, metal=metal)


def main():
    os.makedirs(OUT, exist_ok=True)
    only = [a[2:] for a in sys.argv[1:] if a.startswith("--")]
    for fn in (plaster, wood, stone, roof, thatch, cloth, iron):
        if not only or fn.__name__ in only:
            fn()


if __name__ == "__main__":
    main()
