"""Side-by-side LOD check: renders the given GLBs next to each other from a front
3/4 and a back 3/4 view (two rows) so shredding or lost silhouettes are easy to spot.

Usage: blender -b --python tools/meshy/compare_lods.py -- <out.png> <a.glb> <b.glb> [<c.glb> ...]
"""
import bpy, sys, math, mathutils, os

args = sys.argv[sys.argv.index("--") + 1:]
out, files = args[0], args[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
groups = []
for f in files:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    groups.append([o for o in bpy.data.objects if o not in before and o.type == 'MESH'])


def bounds(objs):
    pts = [o.matrix_world @ mathutils.Vector(c) for o in objs for c in o.bound_box]
    mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
    mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx


w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.78, 0.85, 0.95, 1); bg.inputs[1].default_value = 1.1
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", 'SUN')); sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 50
engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items]
sc.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = 520; sc.render.resolution_y = 440; sc.view_settings.view_transform = 'Standard'

tiles = []
for row, ang in enumerate([-35, 145]):
    for k, g in enumerate(groups):
        for j, other in enumerate(groups):
            for o in other:
                o.hide_render = j != k
        mn, mx = bounds(g)
        ctr = (mn + mx) / 2; rad = (mx - mn).length / 2
        a = math.radians(ang); dist = rad * 2.9
        cam.location = ctr + mathutils.Vector((math.sin(a) * dist, -math.cos(a) * dist, rad * 0.9))
        cam.rotation_euler = (ctr - cam.location).to_track_quat('-Z', 'Y').to_euler()
        p = out.replace(".png", f"_{row}_{k}.png"); sc.render.filepath = p
        bpy.ops.render.render(write_still=True); tiles.append((row, k, p))

W, H = sc.render.resolution_x, sc.render.resolution_y
cols, rows = len(groups), 2
big = bpy.data.images.new("grid", W * cols, H * rows)
buf = [0.0] * (W * cols * H * rows * 4)
for row, k, p in tiles:
    im = bpy.data.images.load(p)
    px = list(im.pixels)
    r = rows - 1 - row          # Blender images are bottom-up: row 0 at the top
    for y in range(H):
        s = y * W * 4; d = ((r * H + y) * W * cols + k * W) * 4
        buf[d:d + W * 4] = px[s:s + W * 4]
    os.remove(p)
big.pixels = buf; big.filepath_raw = out; big.file_format = 'PNG'; big.save()
print("DONE", out)
