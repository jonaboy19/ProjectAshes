"""Grey weathered ruin stone (RG_Ruin): the region stone_wall.png repainted cooler and lighter, with pale lime
mortar, chipped edges, lichen and a little moss, so the collapsed watchtower reads as old grey masonry like
the gate towers of the main art reference instead of brown plank-like brick.

Run: /tmp/claude-0/bpyenv/bin/python kingdom/tools/blender/make_ruin_stone_texture.py
Output: kingdom/assets/generated/region/textures/ruin_stone.png (512, tileable like its source)
"""
import os
import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.abspath(os.path.join(HERE, "..", "..", "assets", "generated", "region", "textures"))
rng = np.random.default_rng(88)


def fbm(n, scale, octaves=4):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = max(2, int(n / (scale / (2 ** o))))
        g = rng.random((s, s)).astype(np.float32)
        # tileable: wrap by tiling 3x3 then cropping the centre after resize
        big = np.tile(g, (3, 3))
        im = Image.fromarray((big * 255).astype(np.uint8)).resize((n * 3, n * 3), Image.BICUBIC)
        out += np.asarray(im, np.float32)[n:2 * n, n:2 * n] / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


src = Image.open(os.path.join(TEX, "stone_wall.png")).convert("RGB")
a = np.asarray(src, np.float32) / 255.0
n = a.shape[0]
lum = (a * np.array([0.299, 0.587, 0.114], np.float32)).sum(-1)
mortar = np.clip((0.30 - lum) / 0.16, 0, 1)                    # 1 in the dark joints
stone = 1.0 - mortar
grey = np.repeat(lum[..., None], 3, -1)
col = grey * 0.72 + a * 0.28                                    # pull the stone hues toward neutral grey
col = col * np.array([1.03, 1.0, 0.95], np.float32)             # neutral-to-warm grey (the shaded side turns blue by itself)
col = np.clip(col * 1.32 + 0.07, 0, 1)                          # lighter: the sun is warm, so go pale
mortar_col = np.array([0.55, 0.53, 0.50], np.float32)           # lime mortar, light and weathered
col = col * stone[..., None] + mortar_col * mortar[..., None] * (0.85 + 0.3 * fbm(n, 12, 3))[..., None]
# weathering: darker rain streaks, pale chipped edges, lichen and moss patches
streak = fbm(n, 40, 3)
streak = np.clip((streak - 0.5) * 2.2 + 0.5, 0, 1)
col *= (0.86 + 0.20 * streak)[..., None]
edge = np.clip((lum - np.asarray(src.filter(ImageFilter.GaussianBlur(3)).convert("L"), np.float32) / 255.0) * 5.0, 0, 1)
col += edge[..., None] * 0.10
lichen = np.clip((fbm(n, 9, 4) - 0.70) * 6.0, 0, 1) * stone
col = col * (1 - lichen[..., None] * 0.4) + np.array([0.62, 0.66, 0.44], np.float32) * lichen[..., None] * 0.4
moss = np.clip((fbm(n, 30, 3) - 0.74) * 7.0, 0, 1)
col = col * (1 - moss[..., None] * 0.6) + np.array([0.36, 0.52, 0.22], np.float32) * moss[..., None] * 0.6
out = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
out.save(os.path.join(TEX, "ruin_stone.png"))
print("ruin_stone.png mean", np.asarray(out).reshape(-1, 3).mean(0))
