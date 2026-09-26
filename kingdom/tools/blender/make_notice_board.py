"""Generates the village notice board (two posts, plank board, little roof,
pinned notices) as glTF. Run: python3 make_notice_board.py <out.glb>  (bpy, Blender 5.x)."""
import sys, random
import bpy, bmesh
from mathutils import Vector

out = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "notice_board.glb"
random.seed(11)
bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, color, rough=0.85):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    return m

wood = material("Wood", (0.30, 0.19, 0.10))
plank = material("Plank", (0.42, 0.29, 0.17))
roof = material("Shingle", (0.22, 0.15, 0.11), 0.95)
paper = material("Paper", (0.86, 0.80, 0.64), 0.95)
wax = material("Wax", (0.55, 0.08, 0.06), 0.5)

def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.01):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=bevel, segments=1, affect='EDGES')
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = rot
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob

# Posts
for x in (-0.85, 0.85):
    box("Post", (0.12, 0.12, 2.5), (x, 0, 1.25), wood, bevel=0.015)
# Board of slightly uneven planks
for i in range(5):
    z = 1.05 + i * 0.2
    box("Plank", (1.8, 0.05, 0.19), (random.uniform(-0.01, 0.01), 0.07, z), plank,
        rot=(0, random.uniform(-0.01, 0.01), 0), bevel=0.008)
# Frame
box("FrameTop", (1.95, 0.08, 0.08), (0, 0.08, 2.0), wood)
box("FrameBottom", (1.95, 0.08, 0.08), (0, 0.08, 0.95), wood)
# Roof: two sloped panels
for side in (-1, 1):
    box("Roof", (2.3, 0.45, 0.05), (0, side * 0.19, 2.62), roof, rot=(side * 0.55, 0, 0), bevel=0.01)
box("Ridge", (2.35, 0.07, 0.07), (0, 0, 2.74), wood)
# Pinned notices with wax seals
for i in range(6):
    w, h = random.uniform(0.28, 0.38), random.uniform(0.32, 0.42)
    x = -0.62 + i % 3 * 0.62 + random.uniform(-0.06, 0.06)
    z = 1.2 + (i // 3) * 0.48 + random.uniform(-0.04, 0.04)
    box("Notice", (w, 0.006, h), (x, 0.105, z), paper, rot=(0, random.uniform(-0.12, 0.12), 0), bevel=0)
    box("Seal", (0.04, 0.01, 0.04), (x, 0.11, z + h * 0.4), wax, bevel=0.005)

bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_apply=True)
print("wrote", out)
