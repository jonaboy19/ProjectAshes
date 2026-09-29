"""Render a clip of a rigged GLB as a PNG sequence (EEVEE) for frame-sheet review.
blender -b --python render_clip.py -- <rigged.glb> <out_dir> <clip> <speed_mps> <view: 3q|side|front> [size=420] [step=1] [loops=1]
The animal is translated at speed_mps over a checker floor so planted feet must stay still on the floor."""
import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index('--') + 1:]
glb, outd, clip, speed, view = a[0], a[1], a[2], float(a[3]), a[4]
size = int(a[5]) if len(a) > 5 else 420
step = int(a[6]) if len(a) > 6 else 1
loops = int(a[7]) if len(a) > 7 else 1
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
meshes = [o for o in bpy.data.objects if o.type == 'MESH' and o.modifiers]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and not o.modifiers]:
    bpy.data.objects.remove(o)
act = [x for x in bpy.data.actions if x.name.startswith(clip)]
act = [x for x in act if x.name == clip] or act
print("actions", [x.name for x in bpy.data.actions])
act = act[0]
ad = arm.animation_data or arm.animation_data_create()
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
ad.action = act
try:
    ad.action_slot = act.slots[0]
except Exception as e:
    print('slot', e)
f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
n = f1 - f0
H = max(o.dimensions.z for o in meshes)
L = max(max(o.dimensions.x, o.dimensions.y) for o in meshes); print('HL', H, L, [o.dimensions[:] for o in meshes], arm.scale[:], arm.dimensions[:])
# floor
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
fl = bpy.context.object
mat = bpy.data.materials.new('f')
mat.use_nodes = True
nt = mat.node_tree
for nd in list(nt.nodes):
    nt.nodes.remove(nd)
out = nt.nodes.new('ShaderNodeOutputMaterial')
bsdf = nt.nodes.new('ShaderNodeBsdfDiffuse')
chk = nt.nodes.new('ShaderNodeTexChecker')
co = nt.nodes.new('ShaderNodeTexCoord')
mp = nt.nodes.new('ShaderNodeMapping')
mp.inputs['Scale'].default_value = (60 / 0.1, 60 / 0.1, 1)   # 0.1 m checks (0.05 m squares would alias)
mp.inputs['Scale'].default_value = (1, 1, 1)
chk.inputs['Scale'].default_value = 60 / (0.25 if L < 0.8 else 0.5)
chk.inputs['Color1'].default_value = (0.35, 0.55, 0.2, 1)
chk.inputs['Color2'].default_value = (0.24, 0.42, 0.14, 1)
nt.links.new(co.outputs['UV'], chk.inputs['Vector'])
nt.links.new(chk.outputs['Color'], bsdf.inputs['Color'])
nt.links.new(bsdf.outputs['BSDF'], out.inputs['Surface'])
fl.data.materials.append(mat)
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True
w.node_tree.nodes['Background'].inputs[0].default_value = (0.6, 0.75, 0.95, 1)
w.node_tree.nodes['Background'].inputs[1].default_value = 1.0
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
sun.data.energy = 2.5
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
sc.collection.objects.link(sun)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 50
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = int(size * 4 / 3)
sc.render.resolution_y = size
sc.view_settings.view_transform = 'Standard'
dist = max(H * 2.6, L * 2.4)
offs = {'3q': Vector((dist * 0.62, -dist * 0.78, H * 0.75)), 'side': Vector((dist * 1.0, 0, H * 0.45)), 'front': Vector((0, -dist * 1.0, H * 0.6))}[view]
os.makedirs(outd, exist_ok=True)
for f in os.listdir(outd):
    if f.endswith('.png'):
        os.remove(os.path.join(outd, f))
idx = 1
total = int(round(n / float(sc.render.fps) * 30)) * loops
for i in range(0, total, step):
    tsec = i / 30.0
    fps_a = float(sc.render.fps)
    fr = f0 + (tsec * fps_a) % n
    sc.frame_set(int(fr), subframe=fr - int(fr))
    # world position: animal walks toward -Y at `speed`; fixed camera follows
    t = i / 30.0
    y = -speed * t
    arm.location = (0, y, 0)
    for m in meshes:
        pass
    tgt = Vector((0, y, H * 0.45))
    cam.location = tgt + offs
    cam.rotation_euler = (tgt - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sun.location = (0, y, 5)
    sc.render.filepath = os.path.join(outd, 'f%08d.png' % idx)
    bpy.ops.render.render(write_still=True)
    idx += 1
print('RENDERED', idx - 1)
