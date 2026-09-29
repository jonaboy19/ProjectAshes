"""Region 1 L4: rift-touched texture variants (recolours of the shipped region nature + creature textures).

    blender -b --python make_rift_textures.py

The rift look is the SUNNY storybook look with a violet/cyan tint, not grimdark: leaves go lavender
(shadows) to periwinkle-cyan (highlights) at full brightness, bark goes warm violet-grey, and a subtle
emissive vein mask (leaf highlight ridges, bark cracks, fur crevices) is written next to each albedo.
The Godot materials (rift_*.tres, shaders rift_foliage / rift_bark) do the rest: see rift/README.md.

-> kingdom/assets/incoming/region1/rift/textures/
"""
import bpy, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r1_common as C

OUT = os.path.join(C.R1, "rift", "textures")
os.makedirs(OUT, exist_ok=True)
NAT_TEX = os.path.join(C.GEN, "region", "textures")
CREA = os.path.join(C.KINGDOM, "assets", "incoming", "ai3d", "meshy", "creatures")


def load(path):
    im = bpy.data.images.load(path, check_existing=False)
    im.colorspace_settings.name = "sRGB"
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    return a


def save(a, name, fmt="PNG", q=90):
    h, w = a.shape[:2]
    im = bpy.data.images.new(name, w, h, alpha=True)
    im.pixels = a.ravel()
    im.filepath_raw = os.path.join(OUT, name)
    im.file_format = fmt
    if fmt == "JPEG":
        bpy.context.scene.render.image_settings.quality = q
    im.save()
    print("WROTE", name, w, h)


def box_blur(x, r):
    """Separable box blur with edge clamping, x: HxW."""
    k = 2 * r + 1
    p = np.pad(x, ((r, r), (r, r)), mode="edge")
    c = np.cumsum(p, axis=0, dtype=np.float64)
    c = np.concatenate([np.zeros((1, c.shape[1])), c], axis=0)
    y = (c[k:] - c[:-k]) / k
    c = np.cumsum(y, axis=1)
    c = np.concatenate([np.zeros((c.shape[0], 1)), c], axis=1)
    return ((c[:, k:] - c[:, :-k]) / k).astype(np.float32)


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def vein_mask(V, S_green, alpha, r=5, lo=0.05, hi=0.16):
    """Thin bright ridges: value above its local blur, only where the source was leafy and opaque."""
    hp = V - box_blur(V, r)
    m = smooth(hp, lo, hi) * S_green * (alpha > 0.5)
    return np.clip(m, 0, 1)


# ------------------------------------------------------------------ foliage atlas (leaf cards)
def foliage():
    a = load(os.path.join(NAT_TEX, "foliage_atlas.png"))
    H, S, V = C.rgb2hsv(a[..., :3])
    green = smooth(1 - np.abs(H - 0.27) / 0.16, 0.0, 0.5) * (S > 0.18)          # leafy pixels
    # dark/mid leaf -> lavender-violet, sunlit leaf -> cool periwinkle / cyan (hue by value)
    t = np.clip((V - 0.25) / 0.6, 0, 1)
    nh = 0.80 - 0.33 * t ** 1.2                    # 0.80 magenta-violet ... 0.47 cyan
    ns = np.clip(0.38 + 0.30 * (1 - t) + 0.08 * S, 0, 0.75)
    nv = np.clip(V * 1.12 + 0.10, 0, 1)             # keep it bright and sunny
    H2 = np.where(green > 0.5, nh, H)
    S2 = np.where(green > 0.5, ns, S)
    V2 = np.where(green > 0.5, nv, V)
    # wheat / seed cells (warm hues): a soft lilac-gold so they still read as crop-like grass
    warm = (H > 0.06) & (H < 0.16) & (S > 0.2)
    H2 = np.where(warm, 0.86, H2)
    S2 = np.where(warm, np.clip(S * 0.6, 0, 0.6), S2)
    rgb = C.hsv2rgb(H2 % 1.0, S2, V2)
    out = a.copy()
    out[..., :3] = rgb
    save(out, "rift_foliage_atlas.png")
    m = vein_mask(V2, green, a[..., 3], r=5)
    vm = np.zeros_like(a); vm[..., 0] = vm[..., 1] = vm[..., 2] = m; vm[..., 3] = 1.0
    save(vm, "rift_foliage_vein.png")


# ------------------------------------------------------------------ bark atlas
def bark():
    a = load(os.path.join(NAT_TEX, "bark_atlas.png"))
    H, S, V = C.rgb2hsv(a[..., :3])
    # warm violet bark: keep the value structure (grain, cracks), swap hue to a red-violet, lift the darks
    nv = np.clip(0.18 + V * 0.95, 0, 1)
    ns = np.clip(0.20 + S * 0.55, 0, 0.62)
    rgb = C.hsv2rgb(np.full_like(H, 0.76), ns, nv)
    out = a.copy(); out[..., :3] = rgb
    save(out, "rift_bark_atlas.png")
    # emissive veins = the crack network (dark lines) of the voronoi bark cell (column 2) + heavy furrows elsewhere
    dark = smooth(0.24 - V, 0.0, 0.16)
    x = np.arange(a.shape[1])[None, :] / a.shape[1]
    cell2 = ((x > 0.25) & (x < 0.5)).astype(np.float32) * np.ones_like(V)
    m = dark * (0.4 + 0.6 * cell2) * (x < 0.75)
    vm = np.zeros_like(a); vm[..., 0] = vm[..., 1] = vm[..., 2] = m; vm[..., 3] = 1.0
    save(vm, "rift_bark_vein.png")


def impostors():
    """LOD2 tree impostor cards (tree_impostors.png): same recolour as the leaf atlas, bark browns to warm violet."""
    a = load(os.path.join(NAT_TEX, "tree_impostors.png"))
    H, S, V = C.rgb2hsv(a[..., :3])
    green = smooth(1 - np.abs(H - 0.27) / 0.16, 0.0, 0.5) * (S > 0.15)
    t = np.clip((V - 0.2) / 0.65, 0, 1)
    nh = 0.80 - 0.33 * t ** 1.2
    ns = np.clip(0.38 + 0.30 * (1 - t) + 0.08 * S, 0, 0.75)
    nv = np.clip(V * 1.04 + 0.06, 0, 1)
    brown = ((H < 0.14) | (H > 0.95)) & (S > 0.18)
    H2 = np.where(green > 0.5, nh, np.where(brown, 0.76, H))
    S2 = np.where(green > 0.5, ns, np.where(brown, np.clip(S * 0.5 + 0.1, 0, 0.5), S))
    V2 = np.where(green > 0.5, nv, np.where(brown, np.clip(V * 0.95 + 0.12, 0, 1), V))
    out = a.copy(); out[..., :3] = C.hsv2rgb(H2 % 1.0, S2, V2)
    save(out, "rift_tree_impostors.png")


def moss():
    a = load(os.path.join(NAT_TEX, "moss.png"))
    H, S, V = C.rgb2hsv(a[..., :3])
    rgb = C.hsv2rgb(np.full_like(H, 0.68), np.clip(S * 0.8 + 0.1, 0, 0.7), np.clip(V * 1.05 + 0.06, 0, 1))
    out = a.copy(); out[..., :3] = rgb
    save(out, "rift_moss.png")


# ------------------------------------------------------------------ creature fur
def fur(src, name, hue, sat_add, val_mul):
    a = load(os.path.join(CREA, src))
    H, S, V = C.rgb2hsv(a[..., :3])
    # violet-tinted, slightly lighter; keep the strand structure. Highlights drift cool.
    nh = hue - 0.06 * np.clip((V - 0.5) / 0.5, 0, 1)
    ns = np.clip(S * 0.55 + sat_add, 0, 0.7)
    nv = np.clip(V * val_mul + 0.05, 0, 1)
    rgb = C.hsv2rgb(nh % 1.0, ns, nv)
    out = a.copy(); out[..., :3] = rgb
    save(out, name + ".jpg", "JPEG", 90)
    # glow: crevices between fur clumps (very dark + small) -> cyan veins, kept sparse and thin
    dark = smooth(0.06 - V, 0.0, 0.05)
    dark = box_blur(dark, 1) * (dark > 0.2)
    vm = np.zeros_like(a); vm[..., 0] = vm[..., 1] = vm[..., 2] = np.clip(dark * 1.2, 0, 1); vm[..., 3] = 1
    save(vm, name + "_vein.png")


if __name__ == "__main__":
    foliage(); bark(); moss(); impostors()
    for src, nm, hue, sadd, vm_ in (("wolf_lod1_Image_0.jpg", "rift_wolf_lod1", 0.75, 0.38, 0.85),
                                    ("wolf_Image_0.jpg", "rift_wolf", 0.75, 0.38, 0.85),
                                    ("boar_lod1_Image_0.jpg", "rift_boar_lod1", 0.80, 0.30, 1.35),
                                    ("boar_Image_0.jpg", "rift_boar", 0.80, 0.30, 1.35)):
        fur(src, nm, hue, sadd, vm_)
