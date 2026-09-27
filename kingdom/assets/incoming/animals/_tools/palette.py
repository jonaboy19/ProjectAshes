"""Shared hand-painted palette atlas for all Rising Ashes animals.
Each named colour becomes a 16x64 px cell in a 256x256 atlas with a vertical
warm gradient (shadow at the bottom, sunlit at the top) and faint brush noise.
Meshes pick a cell by colour name and a V coordinate from height/normal, so
every animal shares ONE texture and ONE material."""
import math, random

# sRGB hex, natural warm medieval tones. Order is fixed: never reorder, only append.
PALETTE = [
 ("black",      "241f1c"), ("eye_white", "e8e0cf"), ("hoof",      "3b2f27"), ("horn",      "c9b48a"),
 ("bay",        "74432a"), ("bay_dark",  "4a2a18"), ("chestnut",  "8c5631"), ("mane_black","2c2420"),
 ("grey_horse", "a8a296"), ("grey_dark", "6d675e"), ("cream",     "e6d9bc"), ("wool",      "e9e1cc"),
 ("wool_shade", "c9bfa6"), ("face_dark", "3d3430"), ("pig_pink",  "d9a08a"), ("pig_snout", "c78470"),
 ("cow_brown",  "8a5a36"), ("cow_white", "ece3d0"), ("muzzle",    "c99a80"), ("ox_dark",   "3f332b"),
 ("donkey",     "8c8276"), ("donkey_lt", "c9bfb0"), ("deer",      "a8703f"), ("deer_lt",   "e2cfae"),
 ("antler",     "d8c7a2"), ("fox",       "c0622a"), ("fox_lt",    "eadfcc"), ("fox_dark",  "3a2b24"),
 ("dog_tan",    "b88a55"), ("dog_dark",  "4a3a2e"), ("dog_lt",    "e4d6bb"), ("cat_grey",  "7d746a"),
 ("cat_dark",   "4a423b"), ("cat_ginger","b8804d"), ("rat",       "6b5f55"), ("rat_pink",  "c9938a"),
 ("goat",       "d8cdb6"), ("goat_brown","8f6a48"), ("hen",       "a8683a"), ("hen_dark",  "6e3f22"),
 ("comb_red",   "b8402e"), ("beak",      "d9a441"), ("leg_yellow","d0a24a"), ("rooster_tail","2f3a33"),
 ("rooster_gold","c98a3a"), ("duck_green","3f5e3f"), ("duck_brown","8a6a4a"), ("duck_bill", "d99a3a"),
 ("goose",      "e6e0d2"), ("goose_grey","9a958c"), ("goose_bill","d98a3a"), ("pigeon",   "8e8d91"),
 ("pigeon_dark","5c5a63"), ("pigeon_neck","6a7a6e"), ("crow",     "2a2629"), ("crow_sheen","3b3a45"),
 ("rabbit",     "9a7b5c"), ("rabbit_lt", "ddd0bb"), ("trout",     "7a7a52"), ("trout_belly","e0d6b8"),
 ("carp",       "7f6c3f"), ("fin",       "8a6a4a"), ("pink_ear",  "d8a08e"), ("white",     "f0ead9"),
]
NAMES = [n for n, _ in PALETTE]
ATLAS = 256; CW = 16; CH = 64; COLS = ATLAS // CW; MARGIN = 3

def hex2rgb(h):
    return tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))

def cell_of(name):
    i = NAMES.index(name)
    return i % COLS, i // COLS

def uv_for(name, t):
    """t in 0..1 (0 = shadow bottom, 1 = sunlit top)."""
    cx, cy = cell_of(name)
    u = (cx * CW + CW / 2) / ATLAS
    v0 = (cy * CH + MARGIN) / ATLAS; v1 = ((cy + 1) * CH - MARGIN) / ATLAS
    t = max(0.0, min(1.0, t))
    return u, v0 + (v1 - v0) * t

def shade(rgb, t):
    # warm hand-painted ramp: shadows darker, slightly red-violet; lights warm yellow
    dark = (rgb[0] * 0.60 + 0.025, rgb[1] * 0.56 + 0.01, rgb[2] * 0.60 + 0.035)
    light = (min(1, rgb[0] * 1.10 + 0.045), min(1, rgb[1] * 1.08 + 0.035), min(1, rgb[2] * 1.02 + 0.005))
    s = t * t * (3 - 2 * t)
    mid = 0.5
    if s < mid:
        k = s / mid; a, b = dark, rgb
    else:
        k = (s - mid) / (1 - mid); a, b = rgb, light
    return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))

def build_pixels():
    """Returns flat RGBA float list (bottom row first, Blender convention), sRGB values."""
    rnd = random.Random(7)
    px = [0.0] * (ATLAS * ATLAS * 4)
    # low-frequency brush noise field
    streak = [[rnd.uniform(-1, 1) for _ in range(ATLAS)] for _ in range(ATLAS // 4 + 1)]
    for idx, (name, hx) in enumerate(PALETTE):
        rgb = hex2rgb(hx); cx, cy = idx % COLS, idx // COLS
        for y in range(CH):
            t = min(1, max(0, (y - MARGIN) / (CH - 2 * MARGIN - 1)))
            base = shade(rgb, t)
            for x in range(CW):
                X = cx * CW + x; Y = cy * CH + y
                n = 0.022 * streak[Y // 4][X] + 0.012 * math.sin(X * 0.9 + Y * 0.35)
                o = (Y * ATLAS + X) * 4
                for c in range(3):
                    px[o + c] = max(0.0, min(1.0, base[c] * (1 + n)))
                px[o + 3] = 1.0
    return px
