"""Builds the Style G weathering pack (1K RGBA, tileable) from Poly Haven CC0 displacement maps.
R = plaster relief (damaged_plaster), G = wood grain (medieval_wood), B = large grime/stain noise, A = stone relief (medieval_blocks_02).
Each channel is high-passed and normalised around 0.5 so the shader can use (x - 0.5) as a signed detail.
Usage: py make_weather_pack.py <kingdom dir>"""
import sys, numpy as np
from PIL import Image, ImageFilter
K = sys.argv[1]
T = K + "/assets/incoming/polyhaven/textures/%s/%s_%s_2k.jpg"
N = 1024
def chan(name, kind="disp", blur=24):
    im = Image.open(T % (name, name, kind)).convert("L").resize((N, N), Image.LANCZOS)
    a = np.asarray(im, np.float32)
    lo = np.asarray(im.filter(ImageFilter.GaussianBlur(blur)), np.float32)
    d = a - lo
    d = d / (np.percentile(np.abs(d), 98) + 1e-3)
    return np.clip(0.5 + 0.5 * d, 0, 1)
def grime():
    rng = np.random.default_rng(7)
    acc = np.zeros((N, N), np.float32)
    for oct_, amp in ((8, 1.0), (16, 0.5), (32, 0.25), (64, 0.12)):
        g = rng.random((oct_, oct_)).astype(np.float32)
        g = np.tile(g, (2, 2))  # tileable via wrap
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((N * 2, N * 2), Image.BICUBIC)
        acc += amp * np.asarray(im, np.float32)[N // 2:N // 2 + N, N // 2:N // 2 + N] / 255.0
    acc = (acc - acc.min()) / (acc.max() - acc.min())
    return acc
r = chan("damaged_plaster"); g = chan("medieval_wood", blur=40); b = grime(); a = chan("medieval_blocks_02", blur=30)
out = np.stack([r, g, b, a], -1)
Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(K + "/assets/generated/style_g/weather_pack.png")
print("ok")
