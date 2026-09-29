"""Shared helpers for the Rising Ashes flipbook bakers (runs inside Blender's Python, numpy only).

Frames are float32 arrays (H, W, 4), linear RGB, PREMULTIPLIED alpha, as they come from
Blender's Render Result. `finish_frame` turns them into straight-alpha sRGB uint8 with
fringe-free colour, `write_atlas` tiles them into one PNG (no PIL needed).
"""
import os, zlib, struct
import numpy as np


def srgb_encode(x):
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def box_down(a, f):
    """Average f x f blocks (supersampling -> anti-aliasing)."""
    if f == 1:
        return a
    h, w, c = a.shape
    return a.reshape(h // f, f, w // f, f, c).mean(axis=(1, 3))


def finish_frame(prem, fill_rgb=(0.5, 0.5, 0.5), toon=0.0, bands=4):
    """premult linear -> straight sRGB uint8. toon>0 blends in a soft cel-banded colour ramp
    (luminance posterised into `bands` smooth steps) for the hand-painted storybook look."""
    a = prem[..., 3:4]
    rgb = np.where(a > 1e-4, prem[..., :3] / np.maximum(a, 1e-4), 0.0)
    rgb = np.clip(rgb, 0, 4.0)
    if toon > 0:
        lum = (rgb * np.array([0.2126, 0.7152, 0.0722])).sum(-1, keepdims=True)
        q = lum * bands
        f = np.floor(q)
        t = q - f
        t = np.clip((t - 0.35) / 0.3, 0, 1)          # soft step, not a hard posterise
        t = t * t * (3 - 2 * t)
        ql = (f + t) / bands
        gain = np.where(lum > 1e-4, ql / np.maximum(lum, 1e-4), 1.0)
        rgb = rgb * (1 - toon + toon * gain)
    rgb = np.clip(rgb, 0, 1)
    fill = np.array(fill_rgb, dtype=np.float32)
    rgb = np.where(a > 1e-3, rgb, fill)               # no black fringes when filtered
    out = np.concatenate([srgb_encode(rgb), a], axis=-1)
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def write_png(path, img):
    h, w, c = img.shape
    assert c in (3, 4)
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(t, d):
        c_ = struct.pack(">I", len(d)) + t + d
        return c_ + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6 if c == 4 else 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def write_atlas(path, frames, cols, rows):
    """frames: list of uint8 (fs, fs, 4). Fills row-major, left to right, top to bottom."""
    fs = frames[0].shape[0]
    atlas = np.zeros((rows * fs, cols * fs, 4), np.uint8)
    for i, fr in enumerate(frames[: cols * rows]):
        r, c = divmod(i, cols)
        atlas[r * fs:(r + 1) * fs, c * fs:(c + 1) * fs] = fr
    write_png(path, atlas)
    return atlas


def report(path, frames, cols, rows):
    fs = frames[0].shape[0]
    print("ATLAS %s  %dx%d  frames=%d grid=%dx%d frame=%dpx  size=%d KB" % (
        os.path.basename(path), cols * fs, rows * fs, len(frames), cols, rows, fs, os.path.getsize(path) // 1024))
