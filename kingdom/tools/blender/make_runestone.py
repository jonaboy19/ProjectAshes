"""Generates the runestone model (standing stone + glowing rune inlays) as glTF.
Run: python3 make_runestone.py <out.glb>   (uses the bpy module, Blender 5.x)."""
import sys, math, random
import bpy, bmesh
from mathutils import Vector, noise

out = sys.argv[-1] if sys.argv[-1].endswith(".glb") else "runestone.glb"
random.seed(7)
bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, color, rough=0.9, emission=None, strength=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if emission:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m

stone_mat = material("Stone", (0.30, 0.31, 0.30), 0.95)
moss_mat = material("Moss", (0.17, 0.25, 0.10), 1.0)
rune_mat = material("Rune", (0.2, 0.7, 0.9), 0.4, emission=(0.25, 0.85, 1.0), strength=6.0)

# Standing stone: tapered, subdivided box displaced by noise for a weathered shape.
bm = bmesh.new()
bmesh.ops.create_cube(bm, size=1.0)
for v in bm.verts:
    v.co.x *= 0.85; v.co.y *= 0.45; v.co.z = (v.co.z + 0.5) * 3.2
    taper = 1.0 - 0.35 * (v.co.z / 3.2)
    v.co.x *= taper; v.co.y *= taper
bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=6, use_grid_fill=True)
for v in bm.verts:
    n = noise.noise(v.co * 1.7) * 0.12 + noise.noise(v.co * 5.0) * 0.03
    d = Vector((v.co.x, v.co.y, 0)).normalized() if (v.co.x or v.co.y) else Vector((0, 0, 1))
    v.co += d * n
    if v.co.z > 3.0:  # rounded, chipped top
        v.co.z -= (abs(v.co.x) * 0.25 + random.uniform(0, 0.08))
me = bpy.data.meshes.new("Runestone")
bm.to_mesh(me); bm.free()
stone = bpy.data.objects.new("Runestone", me)
bpy.context.collection.objects.link(stone)
stone.data.materials.append(stone_mat)
stone.data.materials.append(moss_mat)
# Moss on the lower, upward-facing faces.
for poly in me.polygons:
    c = poly.center
    if c.z < 0.9 and random.random() < 0.55 or (poly.normal.z > 0.5 and random.random() < 0.7):
        poly.material_index = 1
    poly.use_smooth = True

# Rune inlays: small emissive glyph bars on the front face, stacked vertically.
glyphs = []
for row in range(6):
    z = 0.6 + row * 0.38
    w = 0.34 * (1.0 - 0.25 * z / 3.2)
    for seg in range(random.randint(2, 3)):
        bpy.ops.mesh.primitive_cube_add(size=1)
        g = bpy.context.active_object
        horiz = random.random() < 0.5
        g.scale = (random.uniform(0.08, w) if horiz else 0.025, 0.02, 0.025 if horiz else random.uniform(0.08, 0.2))
        g.location = (random.uniform(-w * 0.6, w * 0.6), -0.26 * (1.0 - 0.35 * z / 3.2) - 0.005, z + random.uniform(-0.08, 0.08))
        g.rotation_euler = (0, random.choice([0, 0.5, -0.5, 0]), 0)
        g.data.materials.append(rune_mat)
        glyphs.append(g)
bpy.ops.object.select_all(action="DESELECT")
for g in glyphs:
    g.select_set(True)
bpy.context.view_layer.objects.active = glyphs[0]
bpy.ops.object.join()
glyphs[0].name = "Runes"

# Base: a ring of half-buried rocks.
for i in range(7):
    a = i / 7 * math.tau + random.uniform(-0.2, 0.2)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=random.uniform(0.18, 0.32),
        location=(math.cos(a) * 0.95, math.sin(a) * 0.7, 0.02))
    r = bpy.context.active_object
    r.scale.z = 0.6
    r.data.materials.append(stone_mat)

bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_apply=True)
print("wrote", out)
