# Towns medieval pass: split the Quaternius village Mill.fbx into a static body and spinning sails (origin at the hub),
# and build a waterwheel for river mills. blender -b --factory-startup -P split_mill.py -- <Mill.fbx> <out_dir>
# Godot axes: sails spin about their local Z (Blender -Y). Waterwheel: radius 1.6 m, axle along local X, origin at the hub.
import bpy, bmesh, sys, math
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:]
src, out = args[0], args[1]


def export(obs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.export_scene.gltf(filepath=f"{out}/{name}.glb", use_selection=True, export_format="GLB", export_yup=True, export_apply=True)


bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src)
body = bpy.data.objects["Mill"]
blades = bpy.data.objects["Mill_Blades"]
for o in (body, blades):
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.select_set(False)
vs = [blades.matrix_world @ v.co for v in blades.data.vertices]
hub = Vector(((min(v.x for v in vs) + max(v.x for v in vs)) * 0.5, (min(v.y for v in vs) + max(v.y for v in vs)) * 0.5,
              (min(v.z for v in vs) + max(v.z for v in vs)) * 0.5))
blades.data.transform(Matrix.Translation(-hub))
blades.location = (0, 0, 0)
export([body], "mill_body")
export([blades], "mill_sails")
print("HUB", tuple(round(x, 4) for x in hub))

# waterwheel
bpy.ops.wm.read_factory_settings(use_empty=True)
bm = bmesh.new()


def box(c, s, rx=0.0):
    r = bmesh.ops.create_cube(bm, size=1.0)
    M = Matrix.Translation(Vector(c)) @ Matrix.Rotation(rx, 4, "X") @ Matrix.Diagonal((*s, 1.0))
    bmesh.ops.transform(bm, matrix=M, verts=r["verts"])


R = 1.6
n = 16
for side in (-0.35, 0.35):
    for k in range(n):
        a = 2 * math.pi * k / n
        box((side, math.cos(a) * R, math.sin(a) * R), (0.1, 2 * math.pi * R / n + 0.04, 0.12), rx=a + math.pi / 2)
    for k in range(4):
        box((side, 0, 0), (0.08, 0.08, 2 * R), rx=math.pi * k / 4)
for k in range(n):                     # paddles between the rims
    a = 2 * math.pi * k / n
    box((0, math.cos(a) * (R - 0.2), math.sin(a) * (R - 0.2)), (0.7, 0.06, 0.45), rx=a)
box((0, 0, 0), (1.2, 0.22, 0.22))     # axle
me = bpy.data.meshes.new("waterwheel")
bm.to_mesh(me)
m = bpy.data.materials.new("RA_timber")
m.use_nodes = True
m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.21, 0.13, 1.0)
me.materials.append(m)
ob = bpy.data.objects.new("waterwheel", me)
bpy.context.scene.collection.objects.link(ob)
export([ob], "waterwheel")
print("MILL_DONE")
