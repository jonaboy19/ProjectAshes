"""Normalize a static mesh (feet at z=0, centred in x/y, scaled) and render front/side/top ortho views with a metric grid.
args: mesh.glb out_prefix mode(height|width) value
"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from common import *
from mathutils import Vector, Matrix
a = sys.argv[sys.argv.index('--') + 1:]
src, outp, mode, val = a[0], a[1], a[2], float(a[3])
reset(30)
objs, _ = import_new(src)
m = [o for o in objs if o.type == 'MESH'][0]
bpy.context.view_layer.objects.active = m
for o in bpy.data.objects: o.select_set(o == m)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
mn, mx = world_bbox([m])
m.data.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
dims = mx - mn
k = val / (dims.z if mode == 'height' else dims.x)
m.data.transform(Matrix.Scale(k, 4)); m.data.update()
mn, mx = world_bbox([m])
print("NORMALIZED", [round(x, 3) for x in mn], [round(x, 3) for x in mx])
sc = bpy.context.scene
red = bpy.data.materials.new("r"); red.diffuse_color = (0.9, 0.1, 0.1, 1)
blue = bpy.data.materials.new("b"); blue.diffuse_color = (0.1, 0.3, 0.9, 1)
R = max(mx.x - mn.x, mx.y - mn.y, mx.z) * 0.6 + 0.2
def bar(loc, scale, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); c = bpy.context.object; c.scale = scale; c.data.materials.append(mat)
    c.display_type = 'SOLID'
    return c
def text(s, loc, rot, size=0.05):
    cu = bpy.data.curves.new("t", 'FONT'); cu.body = s; cu.size = size
    o = bpy.data.objects.new("t", cu); sc.collection.objects.link(o); o.location = loc; o.rotation_euler = rot
    o.data.materials.append(red)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'
sc.render.engine = 'BLENDER_WORKBENCH'
sh = sc.display.shading; sh.light = 'STUDIO'; sh.color_type = 'TEXTURE'; sh.show_xray = True; sh.xray_alpha = 0.6
sc.world = bpy.data.worlds.new("w"); sc.world.color = (1, 1, 1)
sc.render.resolution_x = sc.render.resolution_y = 1400
step = 0.1
n = int(R / step) + 1
views = {
    # name: (cam loc, cam rot, axis-u, axis-v, plane offset)
    "front": ((0, -20, R * 0.8), (math.radians(90), 0, 0), 'x', 'z'),
    "side": ((20, 0, R * 0.8), (math.radians(90), 0, math.radians(90)), 'y', 'z'),
    "top": ((0, 0, 20), (0, 0, 0), 'x', 'y'),
}
for vname, (loc, rot, u, v) in views.items():
    grid = []
    for i in range(-n, n + 1):
        w = 0.004 if i % 5 else 0.01
        mat = blue if i % 5 else red
        # lines of constant u and constant v, placed on a plane behind the model
        def P(uu, vv, depth):
            p = {'x': 0, 'y': 0, 'z': 0}; p[u] = uu; p[v] = vv
            other = ({'x', 'y', 'z'} - {u, v}).pop(); p[other] = depth
            return (p['x'], p['y'], p['z'])
        depth = {"front": 3, "side": -3, "top": -1}[vname]
        s1 = {'x': w, 'y': w, 'z': w}; s1[u] = w; s1[v] = 2 * R + 1
        grid.append(bar(P(i * step, R * 0.8 if v == 'z' else 0, depth), (s1['x'], s1['y'], s1['z']), mat))
        s2 = {'x': w, 'y': w, 'z': w}; s2[u] = 2 * R + 1; s2[v] = w
        vv = i * step + (0 if v != 'z' else 0)
        if v == 'z' and vv < 0: continue
        grid.append(bar(P(0, vv, depth), (s2['x'], s2['y'], s2['z']), mat))
        if i % 5 == 0:
            t = text(f"{i*step:.1f}", P(i * step, -0.08 if v == 'z' else -R + 0.1, depth * 0.9), rot)
            if not (v == 'z' and vv < 0):
                text(f"{vv:.1f}", P(-R + 0.05, vv + 0.01, depth * 0.9), rot)
    cam.location = loc; cam.rotation_euler = rot; cam.data.ortho_scale = 2 * R
    sc.render.filepath = f"{outp}_{vname}.png"
    bpy.ops.render.render(write_still=True)
    for g in grid: bpy.data.objects.remove(g)
    for o in [o for o in bpy.data.objects if o.type == 'FONT']: bpy.data.objects.remove(o)
