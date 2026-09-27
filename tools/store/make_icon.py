# Rising Ashes app icon: the game's own runestone (Meshy landmark, generated for this
# project) in front of the Adventurers' Guild compass-star, over warm ember light.
# Blender 5.x, headless:
#   blender -b --python tools/store/make_icon.py -- <out_dir>
# Writes <out_dir>/icon_fg_1024.png (transparent stone + emblem + embers) and
# <out_dir>/icon_bg_1024.png (navy + ember glow). tools/store/make_icons.sh composes,
# sizes and exports every store/platform variant from these two layers.
import bpy, bmesh, math, os, sys, random
import numpy as np
from mathutils import Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
STONE = os.path.join(REPO, "kingdom/assets/incoming/ai3d/meshy/landmark_runestone_lod0.glb")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.join(REPO, "store/_work")
os.makedirs(OUT, exist_ok=True)
RES = 1024

NAVY = (0.055, 0.063, 0.098)
GOLD = (1.0, 0.62, 0.16)
CYAN = (0.05, 0.85, 1.0)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# --- runestone -----------------------------------------------------------------------
bpy.ops.import_scene.gltf(filepath=STONE)
stone = [o for o in bpy.context.selected_objects if o.type == "MESH"][0]
stone.rotation_euler = (0, 0, math.radians(float(os.environ.get("ICON_ROT", "-12"))))
mat = stone.active_material
nt = mat.node_tree
bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
tex = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
# Runes: the texture's cyan channels become emission (mask = B - R).
sep = nt.nodes.new("ShaderNodeSeparateColor")
nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
sub = nt.nodes.new("ShaderNodeMath"); sub.operation = "SUBTRACT"
nt.links.new(sep.outputs[2], sub.inputs[0]); nt.links.new(sep.outputs[0], sub.inputs[1])
ramp = nt.nodes.new("ShaderNodeMapRange")
ramp.inputs["From Min"].default_value = 0.18
ramp.inputs["From Max"].default_value = 0.45
nt.links.new(sub.outputs[0], ramp.inputs["Value"])
mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
mul.inputs[1].default_value = float(os.environ.get("ICON_GLOW", "3.0"))
nt.links.new(ramp.outputs[0], mul.inputs[0])
bsdf.inputs["Emission Color"].default_value = (*CYAN, 1)
nt.links.new(mul.outputs[0], bsdf.inputs["Emission Strength"])
bsdf.inputs["Roughness"].default_value = 0.75

# --- compass-star emblem behind the stone ----------------------------------------------
def gold_mat(name, rough=0.28):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*GOLD, 1)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    return m

CZ = 1.02          # emblem centre height
EY = 0.95          # emblem depth behind the stone
bm = bmesh.new()
pts = []
for i in range(16):
    a = math.pi / 2 - i * math.pi / 8
    if i % 4 == 0:
        r = 1.45          # N E S W points
    elif i % 2 == 0:
        r = 0.80          # diagonal points
    else:
        r = 0.26
    pts.append((math.cos(a) * r, math.sin(a) * r))
top = bm.verts.new((0, EY - 0.22, CZ))
back = bm.verts.new((0, EY + 0.02, CZ))
ring = [bm.verts.new((x, EY, CZ + z)) for x, z in pts]
for i in range(16):
    bm.faces.new((top, ring[i], ring[(i + 1) % 16]))
    bm.faces.new((back, ring[(i + 1) % 16], ring[i]))
me = bpy.data.meshes.new("Star"); bm.to_mesh(me); bm.free()
star = bpy.data.objects.new("Star", me); sc.collection.objects.link(star)
star.data.materials.append(gold_mat("Gold"))
bpy.ops.mesh.primitive_torus_add(major_radius=1.02, minor_radius=0.075, major_segments=96, minor_segments=16,
    location=(0, EY - 0.05, CZ), rotation=(math.pi / 2, 0, 0))
bpy.context.object.data.materials.append(gold_mat("GoldRing", 0.22))
bpy.ops.mesh.primitive_torus_add(major_radius=0.86, minor_radius=0.03, major_segments=96, minor_segments=12,
    location=(0, EY - 0.05, CZ), rotation=(math.pi / 2, 0, 0))
bpy.context.object.data.materials.append(gold_mat("GoldRing2", 0.3))

# --- embers ---------------------------------------------------------------------------
em = bpy.data.materials.new("Ember")
eb = em.node_tree.nodes["Principled BSDF"]
eb.inputs["Base Color"].default_value = (1, 0.4, 0.08, 1)
eb.inputs["Emission Color"].default_value = (1, 0.28, 0.03, 1)
eb.inputs["Emission Strength"].default_value = float(os.environ.get("ICON_EMBER", "2.5"))
random.seed(4)
for i in range(26):
    x = random.uniform(-1.45, 1.45)
    z = random.uniform(-0.15, 1.2) ** 1.0
    if abs(x) < 0.55 and z > 0.1:
        continue
    y = random.uniform(-0.9, 0.4)
    bpy.ops.mesh.primitive_ico_sphere_add(radius=random.uniform(0.012, 0.03), subdivisions=2, location=(x, y, z))
    bpy.context.object.data.materials.append(em)

# --- lights, camera -------------------------------------------------------------------
def area(name, loc, rot, energy, color, size):
    d = bpy.data.lights.new(name, "AREA"); d.energy = energy; d.color = color; d.size = size
    o = bpy.data.objects.new(name, d); sc.collection.objects.link(o)
    o.location = loc; o.rotation_euler = rot
    o.visible_camera = False
    return o

area("EmberKey", (0.6, -2.4, -0.6), (math.radians(-60), 0, math.radians(15)), 420, (1, 0.55, 0.22), 2.0)
area("CoolFill", (-2.6, -1.8, 2.4), (math.radians(50), 0, math.radians(-50)), 160, (0.55, 0.7, 1), 2.5)
area("TopRim", (0, 1.2, 3.6), (math.radians(20), 0, 0), 300, (1, 0.85, 0.6), 1.5)
area("EmblemLight", (0, -1.0, 2.6), (math.radians(30), 0, 0), 120, (1, 0.8, 0.5), 3.0)

cam_d = bpy.data.cameras.new("Cam"); cam_d.lens = 85
cam = bpy.data.objects.new("Cam", cam_d); sc.collection.objects.link(cam)
cam.location = (0, -float(os.environ.get("ICON_DIST", "7.4")), 0.7)
look = Vector((0, 0, float(os.environ.get("ICON_LOOKZ", "1.0"))))
cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
cam_d.lens = float(os.environ.get("ICON_LENS", "85"))
sc.camera = cam

world = bpy.data.worlds.new("W"); sc.world = world
world.color = (0.02, 0.025, 0.05)

sc.render.engine = "CYCLES"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    sc.cycles.device = "GPU"
except Exception as e:
    print("GPU setup failed:", e)
sc.cycles.samples = 256
sc.cycles.use_denoising = True
sc.render.resolution_x = sc.render.resolution_y = RES
sc.render.film_transparent = True
sc.view_settings.view_transform = "AgX"
sc.view_settings.look = os.environ.get("ICON_LOOK", "AgX - Punchy")
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.render.filepath = os.path.join(OUT, "icon_fg_raw.png")
bpy.ops.render.render(write_still=True)

# --- post: bloom on the foreground, background plate -------------------------------------
img = bpy.data.images.load(os.path.join(OUT, "icon_fg_raw.png"))
px = np.array(img.pixels[:], dtype=np.float32).reshape(RES, RES, 4)   # bottom-up rows


def blur(a, sigma):
    """Gaussian blur of a HxWxC array via FFT."""
    p = int(sigma * 3) + 8
    src = a
    a = np.pad(a, ((p, p), (p, p), (0, 0)))
    h, w = a.shape[:2]
    fy = np.fft.fftfreq(h)[:, None]; fx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    out = np.empty_like(a)
    for c in range(a.shape[2]):
        out[..., c] = np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g))
    return out[p:p + src.shape[0], p:p + src.shape[1]]


rgb = px[..., :3] * px[..., 3:4]            # premultiplied
lum = rgb.max(axis=2, keepdims=True)
bright = rgb * np.clip((lum - 0.55) / 0.45, 0, 1)
glow = blur(bright, 10) * 1.1 + blur(bright, 34) * 0.9
glow_a = np.clip(glow.max(axis=2, keepdims=True), 0, 1)
fg_rgb = rgb + glow * (1 - px[..., 3:4])
fg_a = np.clip(px[..., 3:4] + glow_a * 0.9, 0, 1)
fg = np.concatenate([np.where(fg_a > 1e-4, fg_rgb / np.maximum(fg_a, 1e-4), 0), fg_a], axis=2)
fg = np.clip(fg, 0, 1)

yy, xx = np.mgrid[0:RES, 0:RES].astype(np.float32) / RES    # y = 0 at the bottom
r_c = np.sqrt((xx - 0.5) ** 2 + (yy - 0.55) ** 2)
bg = np.zeros((RES, RES, 4), np.float32); bg[..., 3] = 1
navy = np.array(NAVY); deep = np.array((0.09, 0.11, 0.2))
t = np.clip(1 - r_c / 0.75, 0, 1)[..., None]
bg[..., :3] = navy * (1 - t) + deep * t
ember = np.clip(1 - np.sqrt(((xx - 0.5) / 0.75) ** 2 + ((yy + 0.05) / 0.55) ** 2), 0, 1)[..., None] ** 1.6
bg[..., :3] += np.array((0.95, 0.36, 0.08)) * ember * 0.85
halo = np.clip(1 - r_c / 0.42, 0, 1)[..., None] ** 2
bg[..., :3] += np.array((0.2, 0.5, 0.6)) * halo * 0.22
bg = np.clip(bg, 0, 1)


def save(arr, name):
    im = bpy.data.images.new(name, RES, RES, alpha=True)
    im.pixels.foreach_set(arr.astype(np.float32).ravel())
    im.filepath_raw = os.path.join(OUT, name + ".png")
    im.file_format = "PNG"
    im.save()


save(fg, "icon_fg_1024")
save(bg, "icon_bg_1024")
a = fg[..., 3:4]
save(np.concatenate([fg[..., :3] * a + bg[..., :3] * (1 - a), np.ones_like(a)], axis=2), "icon_master_1024")
# Monochrome: the silhouette as white on transparent.
mono = np.zeros_like(fg); mono[..., :3] = 1; mono[..., 3] = np.clip(px[..., 3] * 1.0, 0, 1)
save(mono, "icon_mono_1024")
print("ICON DONE", OUT)
