"""Soft biome weights for the ground (phase W3): biome_ids.png (1024 px, 12 m) -> two 256 px RGBA PNGs of per-biome weights, each one-hot
class blurred with a Gaussian (sigma 150 m) so ground/tint transitions span >= 150 m, then downsampled to 48 m cells.
Outputs kingdom/data/world/macro/biome_soft_a.png (biomes 0-3 = grass forest meadow farmland) and biome_soft_b.png (4-7 = marsh highland rift snow).
Re-run after gen_valencious.py:  py -E -B kingdom/tools/world/make_biome_soft.py
"""
import os
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

HERE = os.path.dirname(os.path.abspath(__file__))
MACRO = os.path.join(HERE, "..", "..", "data", "world", "macro")
ids = np.array(Image.open(os.path.join(MACRO, "biome_ids.png")).convert("L"))
SIGMA_PX = 150.0 / 12.0
chans = []
for b in range(8):
    f = gaussian_filter((ids == b).astype(np.float32), SIGMA_PX, mode="nearest")
    chans.append(f)
stack = np.stack(chans, axis=-1)
stack /= np.maximum(stack.sum(axis=-1, keepdims=True), 1e-6)
# 1024 -> 256 by 4x4 box average
small = stack.reshape(256, 4, 256, 4, 8).mean(axis=(1, 3))
q = np.clip(np.round(small * 255.0), 0, 255).astype(np.uint8)
Image.fromarray(q[..., 0:4], "RGBA").save(os.path.join(MACRO, "biome_soft_a.png"))
Image.fromarray(q[..., 4:8], "RGBA").save(os.path.join(MACRO, "biome_soft_b.png"))
print("wrote biome_soft_a/b.png", q.shape)
