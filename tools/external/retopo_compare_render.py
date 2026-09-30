"""Render original (left) vs retopo (right) OBJ, both with wireframe overlay.
  tools/external/blender.sh tools/external/retopo_compare_render.py -- orig.obj retopo.obj out.png
"""
import bpy, sys, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
objs = []
for i, p in enumerate(a[:2]):
    bpy.ops.wm.obj_import(filepath=p)
    o = bpy.context.selected_objects[0]
    objs.append(o)
bpy.context.view_layer.update()
def bb(o):
    c = [o.matrix_world @ Vector(v) for v in o.bound_box]
    return [min(v[i] for v in c) for i in range(3)], [max(v[i] for v in c) for i in range(3)]
lo, hi = bb(objs[0]); w = (hi[0] - lo[0]) * 1.15
for i, o in enumerate(objs):
    l, h_ = bb(o)
    o.location.x += (-w / 2 if i == 0 else w / 2) - (l[0] + h_[0]) / 2
    o.location.z -= l[2]
bpy.context.view_layer.update()
for o in objs:
    m = o.modifiers.new("wf", "WIREFRAME"); m.thickness = 0.0025; m.use_replace = False
    mat = bpy.data.materials.new("m"); mat.diffuse_color = (0.75, 0.72, 0.65, 1); o.data.materials.append(mat)
    # second slot = wireframe material
    mw = bpy.data.materials.new("w"); mw.diffuse_color = (0.05, 0.05, 0.05, 1); o.data.materials.append(mw); m.material_offset = 1
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "MATERIAL"; sc.display.shading.light = "STUDIO"
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
h = max(bb(o)[1][2] for o in objs)
cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = max(w * 2.2, h * 1.8 * 16 / 9)
cz = h / 2
cam.location = (0, -10, cz); cam.rotation_euler = (math.radians(90), 0, 0)
sc.render.filepath = a[2]
bpy.ops.render.render(write_still=True)

