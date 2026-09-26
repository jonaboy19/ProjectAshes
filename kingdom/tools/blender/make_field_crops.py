"""Field crops: a 10 x 10 m tile of ripening wheat in drilled rows, made of
alpha-cut CARDS: a generated wheat texture (stalks shading from olive to
gold, bearded ears, darker at the foot) embedded in the GLB, on upright
double-sided quads along the rows plus yawed and short cross cards for
volume from every direction. Tilled soil underneath, and a scatter of
poppies and cornflowers.

Run: python3 make_field_crops.py <out.glb> [preview.png]   (bpy, Blender 5.x)

Scale/facing: metres. Tile spans x, y in [-5, 5] exactly. 20 drill rows run
along X at y = -4.75 + 0.5 i (0.5 m pitch, continuing across the Y seam);
along each row the main cards cover x = -5..5 exactly with no overhang, so
tiles placed on a 10 m grid join seamlessly (any rotation by 90 degrees
also tiles). Crop height ~0.9-1.15 m. Origin at ground centre.
Material "Wheat": baseColor texture x COLOR_0 (tint / foot shading),
alphaMode MASK (cutoff 0.4), double-sided. The texture is embedded (no
external files).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
import bpy, bmesh
from mathutils import Vector, Matrix
from town_kit import TK, palette
from ra_kit import hexc, vary, mix, srgb

k = TK("FieldCrops", seed=9191, pal=palette())
PL, MA = k.M("Plant"), k.M("Matte")
k.grime = 0.3
k.grime_amt = 0.0
S = 5.0
rng = np.random.default_rng(9191)

# ---------------------------------------------------------------- wheat texture (generated)
TW, THH = 512, 512
col = np.zeros((THH, TW, 3))
alp = np.zeros((THH, TW))


def stamp(cx, cy, r, c, a=1.0):
    x0, x1 = int(max(0, cx - r - 1)), int(min(TW, cx + r + 2))
    y0, y1 = int(max(0, cy - r - 1)), int(min(THH, cy + r + 2))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    aa = np.clip(r + 0.5 - d, 0, 1) * a
    dst = alp[y0:y1, x0:x1]
    col[y0:y1, x0:x1] = col[y0:y1, x0:x1] * (1 - aa[..., None]) + np.array(c) * aa[..., None]
    alp[y0:y1, x0:x1] = aa + dst * (1 - aa)


def stamp_ellipse(cx, cy, rx, ry, ang, c):
    r = max(rx, ry)
    x0, x1 = int(max(0, cx - r - 1)), int(min(TW, cx + r + 2))
    y0, y1 = int(max(0, cy - r - 1)), int(min(THH, cy + r + 2))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dx, dy = xx - cx, yy - cy
    ca, sa = math.cos(ang), math.sin(ang)
    u, v = dx * ca + dy * sa, -dx * sa + dy * ca
    d = np.sqrt((u / rx) ** 2 + (v / ry) ** 2)
    aa = np.clip((1.0 - d) * max(rx, ry), 0, 1)
    shade = np.clip(1.0 - 0.35 * (u / rx), 0.6, 1.2)[..., None]       # rounded grain
    dst = alp[y0:y1, x0:x1]
    col[y0:y1, x0:x1] = col[y0:y1, x0:x1] * (1 - aa[..., None]) + np.array(c) * shade * aa[..., None]
    alp[y0:y1, x0:x1] = aa + dst * (1 - aa)


def lin(c):
    return np.array(srgb(c))


STALK_LO, STALK_HI = lin(hexc("5f6331")), lin(hexc("b99f58"))
EAR = [lin(hexc("d6b865")), lin(hexc("c9a654")), lin(hexc("e0c47a")), lin(hexc("bf9d4d"))]
UNRIPE = lin(hexc("a8a85a"))
order = rng.permutation(78)
for n in order:
    x0 = (n + rng.uniform(0.1, 0.9)) / 78 * TW
    hh = rng.uniform(0.66, 0.9) * THH
    lean = rng.uniform(-28, 28)
    top = (x0 + lean, THH - hh)
    green = rng.random() < 0.12
    steps = int(hh / 1.6)
    for i in range(steps):
        t = i / steps
        x = x0 + lean * t * t + math.sin(t * 3 + n) * 2.0
        y = THH - 1 - hh * t
        c = STALK_LO * (1 - t) + STALK_HI * t
        if green:
            c = c * 0.6 + UNRIPE * 0.4
        stamp(x, y, 1.1 if t < 0.8 else 0.95, c)
        if 0.2 < t < 0.7 and i % 60 == 17:           # a leaf blade peeling off the stalk
            sd = rng.choice((-1, 1))
            for j in range(22):
                stamp(x + sd * j * 0.9, y + j * 0.5 + (j / 22) ** 2 * 10, 1.3 * (1 - j / 26), c * 0.85)
    # the ear: two ranks of grains up the rachis, with awns
    ang = math.atan2(-(hh * 0.04), lean * 0.04 + 1e-4)
    dirv = np.array([lean * 2 * 0.99 / hh, -1.0])
    dirv /= np.linalg.norm(dirv)
    ear_len = rng.uniform(34, 50)
    ec = EAR[rng.integers(len(EAR))] * rng.uniform(0.9, 1.08)
    if green:
        ec = ec * 0.5 + UNRIPE * 0.5
    ex, ey = top
    ngr = int(ear_len / 4.2)
    for g in range(ngr):
        tt = g / max(1, ngr - 1)
        px, py = ex + dirv[0] * g * 4.2, ey + dirv[1] * g * 4.2
        for sd in (-1, 1):
            off = np.array([-dirv[1], dirv[0]]) * sd * 2.6 * (1 - 0.35 * tt)
            gx, gy = px + off[0], py + off[1]
            stamp_ellipse(gx, gy, 3.4 * (1 - 0.3 * tt), 2.1, math.atan2(dirv[1], dirv[0]) + sd * 0.35,
                          ec * rng.uniform(0.9, 1.1))
            # awn: thin bristle angled up and out
            aw = rng.uniform(14, 24)
            adir = np.array([dirv[0] + off[0] * 0.12, dirv[1]])
            adir /= np.linalg.norm(adir)
            for j in range(int(aw)):
                stamp(gx + adir[0] * j, gy + adir[1] * j, 0.45, ec * 1.05, 0.7)
# foot shading (AO) and dilated colour under transparent texels (clean mips)
down = np.linspace(0.0, 1.0, THH)[:, None]            # 0 at the top row of the card, 1 at the foot
col *= (0.45 + 0.55 * np.clip((1.0 - down) * 1.7, 0, 1))[..., None]
mean = (col * alp[..., None]).sum(axis=(0, 1)) / max(1e-3, alp.sum())
col = col + (1 - alp[..., None]) * mean                 # premultiplied-ish fill
rgba = np.concatenate([np.clip(col, 0, 1), alp[..., None]], axis=2)[::-1]   # Blender rows start at the bottom
img = bpy.data.images.new("wheat_cards", TW, THH, alpha=True, float_buffer=False)
img.colorspace_settings.name = "sRGB"
# pixels expects linear->stored as sRGB for byte images: convert linear to sRGB before writing
lin2s = lambda x: np.where(x <= 0.0031308, x * 12.92, 1.055 * np.power(np.clip(x, 0, 1), 1 / 2.4) - 0.055)
rgba[..., :3] = lin2s(rgba[..., :3])
img.pixels.foreach_set(rgba.astype(np.float32).ravel())
img.pack()

# ---------------------------------------------------------------- material
m = bpy.data.materials.new("FieldCrops_Wheat")
m.use_nodes = True
nt = m.node_tree
bsdf = nt.nodes["Principled BSDF"]
tex = nt.nodes.new("ShaderNodeTexImage")
tex.image = img
vc = nt.nodes.new("ShaderNodeVertexColor")
vc.layer_name = "Col"
mx = nt.nodes.new("ShaderNodeMix")
mx.data_type = "RGBA"
mx.blend_type = "MULTIPLY"
mx.inputs[0].default_value = 1.0
nt.links.new(tex.outputs["Color"], next(s for s in mx.inputs if s.identifier == "A_Color"))
nt.links.new(vc.outputs["Color"], next(s for s in mx.inputs if s.identifier == "B_Color"))
nt.links.new(next(s for s in mx.outputs if s.identifier == "Result_Color"), bsdf.inputs["Base Color"])
lt = nt.nodes.new("ShaderNodeMath")
lt.operation = "LESS_THAN"
lt.inputs[1].default_value = 0.4
nt.links.new(tex.outputs["Alpha"], lt.inputs[0])
sub = nt.nodes.new("ShaderNodeMath")
sub.operation = "SUBTRACT"
sub.inputs[0].default_value = 1.0
nt.links.new(lt.outputs[0], sub.inputs[1])
nt.links.new(sub.outputs[0], bsdf.inputs["Alpha"])
bsdf.inputs["Roughness"].default_value = 0.85
bsdf.inputs["Specular IOR Level"].default_value = 0.25
m.use_backface_culling = False
try:
    m.surface_render_method = "DITHERED"
except Exception:
    pass
k.mats["Wheat"] = (len(k.mats), m)

# ---------------------------------------------------------------- soil
k.quads([((-S, -S, 0.015), (S, -S, 0.015), (S, S, 0.015), (-S, S, 0.015))], [hexc("5a4632")], MA, grime=False)
for r in range(20):          # slightly raised drill ridges (darker furrows between)
    y = -S + 0.25 + r * 0.5
    k.quads([((-S, y - 0.14, 0.04), (S, y - 0.14, 0.04), (S, y + 0.14, 0.04), (-S, y + 0.14, 0.04))],
            [vary(hexc("6a5440"), 0.05)], MA, grime=False)

# ---------------------------------------------------------------- cards
uvl = k.bm.loops.layers.uv.new("UVMap")
W_IDX = k.mats["Wheat"][0]


def card(cx, cy, yaw, w, h, lean=0.0, u0=0.0, u1=1.0, tint=1.0):
    ca, sa = math.cos(yaw), math.sin(yaw)
    ax = Vector((ca, sa, 0)) * (w / 2)
    nrm = Vector((-sa, ca, 0))
    base = Vector((cx, cy, -0.02))
    topo = Vector((0, 0, h)) + nrm * lean
    ps = [base - ax, base + ax, base + ax + topo, base - ax + topo]
    vs = [k.bm.verts.new(p) for p in ps]
    f = k.bm.faces.new(vs)
    f.material_index = W_IDX
    f.smooth = True
    uvs = [(u0, 0.0), (u1, 0.0), (u1, 1.0), (u0, 1.0)]
    t = tint * random.uniform(0.92, 1.06)
    warm = random.uniform(-0.04, 0.04)
    for l, uv, lo in zip(f.loops, uvs, (True, True, False, False)):
        l[uvl].uv = uv
        k_ = t * (0.8 if lo else 1.0)
        l[k.col] = (*srgb((min(1, k_ * (1 + warm)), min(1, k_), min(1, k_ * (1 - warm)))), 1.0)


for r in range(20):
    y = -S + 0.25 + r * 0.5
    # main cards along the row: exactly tile x = -5..5
    for i in range(10):
        x = -S + 0.5 + i
        card(x, y + random.uniform(-0.04, 0.04), 0.0 if i in (0, 9) else random.uniform(-0.05, 0.05), 1.0,
             random.uniform(1.0, 1.18),
             lean=random.uniform(-0.08, 0.08), u0=0.0 if i % 2 == 0 else 1.0, u1=1.0 if i % 2 == 0 else 0.0)
    # yawed cards between them for volume
    for i in range(10):
        x = -S + 1.0 + i if i < 9 else -S + 0.5 + i
        card(x, y + random.uniform(-0.06, 0.06), random.choice((-1, 1)) * random.uniform(0.35, 0.6), 0.7,
             random.uniform(0.95, 1.12), lean=random.uniform(-0.06, 0.06), u0=0.2, u1=0.9, tint=0.95)
    # short cross cards so the rows don't vanish when looking straight down them
    for i in range(6):
        x = -S + 0.9 + i * 1.65
        card(x, y, math.pi / 2 + random.uniform(-0.2, 0.2), 0.36, random.uniform(0.95, 1.1), u0=0.3, u1=0.6,
             tint=0.92)

# poppies and cornflowers
for n in range(22):
    r = random.randrange(20)
    y = -S + 0.25 + r * 0.5 + random.uniform(-0.15, 0.15)
    x = random.uniform(-S + 0.3, S - 0.3)
    c = hexc("c8322a") if random.random() < 0.7 else hexc("4a6fc0")
    k.cyl(0.05, 0.05, (x, y, random.uniform(0.7, 0.95)), PL, vary(c, 0.08), segs=3, r2=0.0, rot=(math.pi, 0, 0),
          smooth=None, grime=False)

k.finish_checked((10.0, 10.06), 3000, cam_dir=(0.7, -1.4, 0.7), fit=0.72)
