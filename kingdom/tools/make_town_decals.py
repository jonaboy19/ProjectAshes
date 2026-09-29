"""Painted decal library for towns and villages (Godot Decal nodes), drawn procedurally with PIL/numpy.

Output: kingdom/assets/art/decals/<name>.png (albedo, RGBA: alpha = opacity), <name>_n.png (normal, OpenGL),
<name>_orm.png (only the puddle: occlusion / roughness / metal). 256 px, warm painted palette (no scanned photos).

    moss_base    green moss creeping up a wall foot (wall decal, bottom of the image = ground)
    dirt_base    splashed mud / dirt at a wall foot
    soot         soot stain fanning upward from a door lintel / chimney (top of the image = up)
    plaster      worn plaster patch with the stone showing through at the edges
    ruts         two cart-wheel ruts, long axis along the image height (ground decal)
    puddle       a rain puddle with a glossy ORM (ground decal)

Run: /tmp/claude-0/bpyenv/bin/python kingdom/tools/make_town_decals.py
"""
import os
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "assets", "art", "decals"))
N = 256
rng = np.random.default_rng(1207)


def noise(scale, seed=None, octaves=4):
    """Tileless fBm in [0, 1], shape (N, N)."""
    r = np.random.default_rng(seed) if seed is not None else rng
    out = np.zeros((N, N), dtype=np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(N / (scale / (2 ** o))))
        g = r.random((s, s)).astype(np.float32)
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)
        out += np.asarray(im, dtype=np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(r))
    return np.asarray(im, dtype=np.float32) / 255.0


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0 + 1e-9), 0, 1)
    return t * t * (3 - 2 * t)


def normal_from_height(h, strength=2.0):
    gy, gx = np.gradient(h.astype(np.float32))
    nx, ny, nz = -gx * strength * N * 0.05, gy * strength * N * 0.05, np.ones_like(h)   # +Y up (OpenGL)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    return (n * 255).astype(np.uint8)


def save(name, rgb, alpha, height=None, strength=2.0, orm=None):
    a = np.clip(alpha, 0, 1)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    if height is not None:      # flat decals (soot, puddle) carry no normal map
        Image.fromarray(normal_from_height(height * a, strength), "RGB").save(os.path.join(OUT, name + "_n.png"))
    if orm is not None:
        Image.fromarray((np.clip(orm, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + "_orm.png"))


yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / (N - 1)   # yy: 0 = top, 1 = bottom


def moss_base():
    """Bottom of the image is the ground line; moss creeps up with a ragged, tufted edge."""
    n1, n2 = noise(24, 11), noise(6, 12)
    reach = 0.42 + 0.34 * noise(40, 13, 2)                      # how far up the moss climbs per column
    edge = (1.0 - yy) - reach + (n1 - 0.5) * 0.22 + (n2 - 0.5) * 0.06
    a = 1.0 - smooth(-0.02, 0.06, edge)
    a *= smooth(0.0, 0.10, xx) * smooth(1.0, 0.90, xx)          # rounded ends
    a = np.clip(a * (0.55 + 0.6 * n1), 0, 1)
    tuft = noise(3, 14, 2)
    r = 0.34 + 0.20 * tuft
    g = 0.50 + 0.20 * tuft
    b = 0.15 + 0.08 * tuft
    rgb = np.dstack([r, g, b])
    dark = 0.75 + 0.25 * smooth(0.2, 0.9, yy)                   # darker toward the wet ground
    rgb = rgb * dark[..., None]
    h = 0.5 * tuft + 0.5 * n2
    save("moss_base", rgb, a * 0.90, h, 0.9)


def dirt_base():
    n1, n2, n3 = noise(16, 21), noise(5, 22), noise(2.5, 23, 2)
    edge = (1.0 - yy) - (0.30 + 0.22 * noise(34, 24, 2)) + (n1 - 0.5) * 0.3
    a = 1.0 - smooth(0.0, 0.14, edge)
    a *= smooth(0.0, 0.12, xx) * smooth(1.0, 0.88, xx)
    # splatter flecks above the main stain
    speck = smooth(0.78, 0.86, n3) * smooth(0.55, 0.15, (1.0 - yy))
    a = np.clip(a * (0.65 + 0.5 * n2) + speck * 0.7, 0, 1)
    base = np.dstack([0.34 + 0.12 * n2, 0.23 + 0.09 * n2, 0.13 + 0.06 * n2])
    save("dirt_base", base, a * 0.88, n2 * 0.6 + n3 * 0.4, 0.8)


def soot():
    """Soot fanning up from the middle of the bottom edge: dense at the source, wispy tongues."""
    n1, n2 = noise(10, 31), noise(4, 32, 3)
    cx = xx - 0.5
    spread = 0.10 + 0.34 * (1.0 - yy)                          # widest at the source (bottom), narrows going up
    core = 1.0 - smooth(0.0, 1.0, np.abs(cx + (n1 - 0.5) * 0.25) / (spread + 0.02))
    fade = smooth(0.0, 0.85, 1.0 - (1.0 - yy) * 1.05)          # thins with height
    a = np.clip(core * (0.45 + 1.0 * fade) * (0.6 + 0.6 * n2), 0, 1)
    a *= 0.9
    rgb = np.dstack([0.10 + 0.05 * n2, 0.085 + 0.04 * n2, 0.075 + 0.03 * n2])
    save("soot", rgb, a, None)


def plaster():
    """Lighter plaster patch, irregular outline, bricks/stone peeking at the torn edge."""
    n1, n2 = noise(14, 41), noise(4, 42, 3)
    cx, cy = xx - 0.5, yy - 0.5
    d = np.sqrt((cx / 0.44) ** 2 + (cy / 0.40) ** 2) + (n1 - 0.5) * 0.55
    inner = 1.0 - smooth(0.72, 0.86, d)                          # plaster body
    torn = smooth(0.80, 0.98, d) * (1.0 - smooth(0.98, 1.12, d))   # exposed stone rim
    body = np.dstack([0.93 + 0.04 * n2, 0.86 + 0.05 * n2, 0.70 + 0.06 * n2])
    # rim: stone blocks
    blocks = ((np.floor(xx * 9 + (np.floor(yy * 6) % 2) * 0.5)) + np.floor(yy * 6) * 3.7) % 5 / 5.0
    stone = np.dstack([0.55 + 0.2 * blocks, 0.50 + 0.17 * blocks, 0.43 + 0.14 * blocks])
    t = torn[..., None]
    rgb = body * (1 - t) + stone * t
    a = np.clip(inner + torn * 0.95, 0, 1) * 0.94
    h = inner * 0.5 + torn * 0.15 + n2 * 0.1
    save("plaster", rgb, a, h, 2.5)


def ruts():
    """Two shallow wheel ruts along the image height, with mud banking between and beside."""
    n1, n2, n3 = noise(30, 51, 3), noise(6, 52), noise(3, 53, 2)
    wob = (n1 - 0.5) * 0.06
    lane = np.zeros((N, N), np.float32)
    height = np.zeros((N, N), np.float32)
    for c in (0.30, 0.70):
        d = np.abs(xx - c + wob)
        w = 0.055
        lane = np.maximum(lane, 1.0 - smooth(w * 0.4, w * 1.5, d))
        height -= (1.0 - smooth(0.0, w * 1.4, d)) * 0.9
        height += smooth(w * 1.0, w * 1.9, d) * (1.0 - smooth(w * 1.9, w * 3.0, d)) * 0.25   # banked lip
    a = lane * (0.55 + 0.45 * n2) * smooth(0.0, 0.12, yy) * smooth(1.0, 0.88, yy)   # fade in/out at the ends
    a *= 0.85
    mud = np.dstack([0.25 + 0.06 * n3, 0.17 + 0.04 * n3, 0.10 + 0.03 * n3])
    save("ruts", mud, a, height + n3 * 0.08, 2.4)


def puddle():
    n1, n2 = noise(9, 61), noise(3, 62, 3)
    cx, cy = (xx - 0.5) / 0.45, (yy - 0.5) / 0.36
    d = np.sqrt(cx * cx + cy * cy) + (n1 - 0.5) * 0.7
    a = 1.0 - smooth(0.72, 0.98, d)
    a = np.clip(a * 0.82, 0, 1)
    water = np.dstack([0.20 + 0.06 * n2, 0.28 + 0.06 * n2, 0.34 + 0.08 * n2])   # sky-tinted murky water
    orm = np.dstack([np.ones((N, N), np.float32), np.full((N, N), 0.04, np.float32), np.zeros((N, N), np.float32)])
    save("puddle", water, a, None, 1.0, orm)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for f in (moss_base, dirt_base, soot, plaster, ruts, puddle):
        f()
    # Normal maps must import as normal maps (Decals do not trigger Godot's auto-detect).
    for fn in os.listdir(OUT):
        if fn.endswith("_n.png") or fn.endswith("_orm.png"):
            imp = os.path.join(OUT, fn + ".import")
            if not os.path.exists(imp):
                nm = 1 if fn.endswith("_n.png") else 0
                open(imp, "w").write(
                    '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[deps]\n\nsource_file="res://assets/art/decals/%s"\n\n[params]\n\n'
                    'compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/uastc_level=0\ncompress/rdo_quality_loss=0.0\n'
                    'compress/hdr_compression=1\ncompress/normal_map=%d\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n'
                    'roughness/mode=0\nroughness/src_normal=""\nprocess/channel_remap/red=0\nprocess/channel_remap/green=1\nprocess/channel_remap/blue=2\n'
                    'process/channel_remap/alpha=3\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\nprocess/normal_map_invert_y=false\n'
                    'process/hdr_as_srgb=false\nprocess/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n' % (fn, nm))
    print("decals ->", OUT)
