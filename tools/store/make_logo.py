# Rising Ashes title logo: "RISING ASHES" in Cinzel (OFL, kingdom/assets/incoming/fonts/cinzel)
# as bevelled gold lettering with ember light, rendered with a transparent background.
#   blender -b --python tools/store/make_logo.py -- <out_png> [width]
import bpy, math, os, sys, random
import numpy as np
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(REPO, "kingdom/assets/incoming/fonts/cinzel/Cinzel[wght].ttf")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.join(REPO, "store/logo/rising_ashes_logo.png")
W = int(argv[1]) if len(argv) > 1 else 3000
H = int(W * 0.30)
os.makedirs(os.path.dirname(OUT), exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
font = bpy.data.fonts.load(FONT)


def text(body, size, y, extrude=0.08, bevel=0.011, spacing=1.08):
    cu = bpy.data.curves.new(body, "FONT")
    cu.body = body
    cu.font = font
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_character = spacing
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    cu.offset = 0.0
    ob = bpy.data.objects.new(body, cu)
    sc.collection.objects.link(ob)
    ob.rotation_euler = (math.pi / 2, 0, 0)
    ob.location = (0, 0, y)
    return ob


gold = bpy.data.materials.new("Gold")
nt = gold.node_tree
b = nt.nodes["Principled BSDF"]
b.inputs["Metallic"].default_value = 1.0
b.inputs["Roughness"].default_value = 0.3
# Warm gradient over the height: ember orange at the foot of the letters, pale gold on top.
tc = nt.nodes.new("ShaderNodeTexCoord")
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
nt.links.new(tc.outputs["Object"], sep.inputs[0])
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.0
ramp.color_ramp.elements[0].color = (0.95, 0.36, 0.05, 1)
ramp.color_ramp.elements[1].position = 1.0
ramp.color_ramp.elements[1].color = (1.0, 0.9, 0.55, 1)
mr = nt.nodes.new("ShaderNodeMapRange")
mr.inputs["From Min"].default_value = -0.35
mr.inputs["From Max"].default_value = 0.4
nt.links.new(sep.outputs["Y"], mr.inputs["Value"])
nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
nt.links.new(ramp.outputs["Color"], b.inputs["Base Color"])

t = text("RISING ASHES", 1.0, 0.0)
t.data.materials.append(gold)
bpy.context.view_layer.update()


def light(name, loc, energy, color, size):
    d = bpy.data.lights.new(name, "AREA"); d.energy = energy; d.color = color; d.size = size
    o = bpy.data.objects.new(name, d); sc.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (Vector((0, 0, 0)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    o.visible_camera = False


light("Key", (-3, -5, 4), 900, (1, 0.8, 0.5), 4)
light("Ember", (1.5, -3, -3.5), 700, (1, 0.45, 0.12), 4)
light("Rim", (4, 3, 2), 500, (0.5, 0.85, 1), 3)
light("Top", (0, -1, 6), 300, (1, 0.95, 0.85), 6)
world = bpy.data.worlds.new("W"); sc.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.55, 0.36, 0.16, 1)
bg.inputs["Strength"].default_value = 0.9

cam_d = bpy.data.cameras.new("Cam"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam)
cam.location = (0, -10, 0)
cam.rotation_euler = (math.pi / 2, 0, 0)
dims = t.dimensions
cam_d.ortho_scale = dims.x * 1.16
sc.camera = cam
sc.render.resolution_x = W
sc.render.resolution_y = H
sc.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"; prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
except Exception as e:
    print("GPU setup failed", e)
sc.cycles.samples = 128
sc.render.film_transparent = True
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = "AgX - Punchy"
raw = OUT.replace(".png", "_raw.png")
sc.render.filepath = raw
sc.render.image_settings.color_mode = "RGBA"
bpy.ops.render.render(write_still=True)

# Post: dark soft shadow for legibility on any background + an ember glow halo.
img = bpy.data.images.load(raw)
px = np.array(img.pixels[:], np.float32).reshape(H, W, 4)


def blur(a, sigma):
    p = int(sigma * 3) + 8
    src = a
    a = np.pad(a, ((p, p), (p, p), (0, 0)))
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]; fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * math.pi ** 2 * sigma ** 2 * (fx ** 2 + fy ** 2))
    out = np.empty_like(a)
    for c in range(a.shape[2]):
        out[..., c] = np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g))
    return out[p:p + src.shape[0], p:p + src.shape[1]]


s = W / 3000.0
alpha = px[..., 3:4]
shadow = np.clip(blur(alpha, 14 * s) * 1.4, 0, 1)
shadow = np.roll(shadow, int(-6 * s), axis=0)            # rows are bottom-up: shift down
glow = np.clip(blur(alpha, 40 * s) * 0.9, 0, 1)
out = np.zeros_like(px)
# layer: glow (ember), then shadow (near-black navy), then the letters.
ember = np.array((1.0, 0.42, 0.1))
out[..., :3] = ember
out[..., 3:4] = glow * 0.8
sh_col = np.array((0.03, 0.03, 0.06))
a2 = shadow * 0.85
out[..., :3] = (out[..., :3] * out[..., 3:4] * (1 - a2) + sh_col * a2) / np.maximum(out[..., 3:4] * (1 - a2) + a2, 1e-5)
out[..., 3:4] = out[..., 3:4] * (1 - a2) + a2
a3 = alpha
out[..., :3] = (out[..., :3] * out[..., 3:4] * (1 - a3) + px[..., :3] * a3) / np.maximum(out[..., 3:4] * (1 - a3) + a3, 1e-5)
out[..., 3:4] = out[..., 3:4] * (1 - a3) + a3
out = np.clip(out, 0, 1)
# Trim to the visible bounds plus a small margin.
ys, xs = np.where(out[..., 3] > 0.02)
m = int(24 * s)
y0, y1 = max(0, ys.min() - m), min(H, ys.max() + m + 1)
x0, x1 = max(0, xs.min() - m), min(W, xs.max() + m + 1)
out = np.ascontiguousarray(out[y0:y1, x0:x1])
res = bpy.data.images.new("logo", x1 - x0, y1 - y0, alpha=True)
res.pixels.foreach_set(out.ravel())
res.filepath_raw = OUT
res.file_format = "PNG"
res.save()
os.remove(raw)
print("LOGO DONE", OUT)
