"""Stills of a wolf GLB over a GREEN grassy ground with the real albedo.
blender -b --python render_still.py -- <glb> <out_prefix> [clip] [frame]
Writes <prefix>_side.png, _three.png, _front.png (close) and <prefix>_far.png (12 m phone-size, 1080p-equivalent crop)
"""
import bpy, sys, os, math, mathutils, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_lib import *
args = sys.argv[sys.argv.index('--') + 1:]
glb, prefix = os.path.abspath(args[0]), args[1]
clip = args[2] if len(args) > 2 else 'idle'; frame = int(args[3]) if len(args) > 3 else 0
if glb.endswith('.blend'):
    bpy.ops.wm.open_mainfile(filepath=glb)
    for o in list(bpy.data.objects):
        if o.type == 'CAMERA' or o.type == 'LIGHT': bpy.data.objects.remove(o)
    bpy.context.scene.render.fps = 30
    sc, cam = setup_scene((900, 650), ground=True)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    sc, cam = setup_scene((900, 650))
    bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
ms = [o for o in sc.objects if o.type == 'MESH' and o.name != 'ground' and o.parent == arm]
for o in list(sc.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere'): bpy.data.objects.remove(o)
acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
arm.animation_data_create()
if clip != 'rest':
    arm.animation_data.action = acts[clip]
    if acts[clip].slots: arm.animation_data.action_slot = acts[clip].slots[0]
else:
    arm.animation_data.action = None
workbench_style(sc); activate_albedo()
# grassy ground texture (blotchy greens like the game's meadow)
rng = np.random.default_rng(3); n = 512
base = np.zeros((n, n, 3), np.float32) + np.array([0.66, 0.82, 0.28])
for s, amp in ((8, .10), (32, .08), (128, .07)):
    g = rng.random((s, s, 3)).astype(np.float32); big = np.kron(g, np.ones((n // s, n // s, 1), np.float32)); base += (big - .5) * amp * np.array([1, 1, .6])
base = np.clip(base, 0, 1)
img = bpy.data.images.new("grass", n, n); px = np.ones((n, n, 4), np.float32); px[..., :3] = base; img.pixels.foreach_set(px.ravel())
for o in sc.objects:
    if o.name == 'ground':
        # workbench texture mode needs a material with an image node
        m = bpy.data.materials.new("gg"); m.use_nodes = True
        t = m.node_tree.nodes.new('ShaderNodeTexImage'); t.image = img
        uv = o.data.uv_layers.active
        for l in uv.data: l.uv *= 12
        m.node_tree.links.new(t.outputs[0], m.node_tree.nodes['Principled BSDF'].inputs[0]); t.select = True; m.node_tree.nodes.active = t
        o.data.materials.clear(); o.data.materials.append(m)
    if o.type == 'MESH' and o.name.startswith('Cube'): o.hide_render = True    # no grid lines in stills
sc.frame_set(frame)
mn, mx = bbox(ms)
print("BBOX", tuple(round(v, 3) for v in mn), tuple(round(v, 3) for v in mx))
ctr = mathutils.Vector((0, (mn.y + mx.y) / 2, mx.z * 0.45)); size = max(mx.y - mn.y, mx.z)
for name, yaw, mul, res in (("side", 90, 2.3, (900, 650)), ("three", 55, 2.5, (900, 650)), ("front", 12, 2.6, (900, 650))):
    sc.render.resolution_x, sc.render.resolution_y = res
    aim(cam, ctr, yaw, size * mul, 10); sc.render.filepath = f"{prefix}_{name}.png"; bpy.ops.render.render(write_still=True)
# far: 12 m, vertical fov 45 deg at 1920x1080 (phone-scale), wolf 3/4 view, crop later
cam.data.sensor_fit = 'VERTICAL'; cam.data.sensor_height = 24; cam.data.lens = 12 / math.tan(math.radians(22.5)) * 0 + 24 / (2 * math.tan(math.radians(22.5)))
sc.render.resolution_x, sc.render.resolution_y = 1920, 1080
for name, yaw in (("far", 45),):
    a = math.radians(yaw); tgt = mathutils.Vector((0, (mn.y + mx.y) / 2, mx.z * 0.4))
    cam.location = tgt + mathutils.Vector((math.sin(a), -math.cos(a), 0)) * 12 + mathutils.Vector((0, 0, 1.3))
    cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.render.filepath = f"{prefix}_{name}.png"; bpy.ops.render.render(write_still=True)
