# Firewood bundle carry prop (villager carry errand): 7 split logs + 2 rope bands, firewood_stack textures (CC0 Poly Haven bakes).
#   blender -b --python tools/blender/props/build_firewood_bundle.py -- <out.glb> <kingdom/assets/props_refined/firewood_stack/>
import bpy, bmesh, math, random, sys
from mathutils import Vector
out = sys.argv[sys.argv.index("--")+1]; tex = sys.argv[sys.argv.index("--")+2]
bpy.ops.wm.read_factory_settings(use_empty=True)
random.seed(7)
mat = bpy.data.materials.new("firewood_bundle"); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
def img(name, nonc):
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(tex + name)
    if nonc: t.image.colorspace_settings.name = "Non-Color"
    return t
a = img("firewood_stack_firewood_stack_albedo.jpg", False); nt.links.new(a.outputs[0], bsdf.inputs["Base Color"])
n = img("firewood_stack_firewood_stack_normal.jpg", True); nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(n.outputs[0], nm.inputs["Color"]); nt.links.new(nm.outputs[0], bsdf.inputs["Normal"])
bsdf.inputs["Roughness"].default_value = 0.85
rope = bpy.data.materials.new("rope"); rope.use_nodes = True
rope.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.42, 0.33, 0.2, 1)
rope.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
objs = []
# 7 split logs (half / quarter rounds) in a hex bundle, long axis -Z from the gripped end (origin)
offs = [(0, 0)] + [(math.cos(k * math.pi / 3) * 0.075, math.sin(k * math.pi / 3) * 0.075) for k in range(6)]
for i, (x, y) in enumerate(offs):
    L = random.uniform(0.55, 0.66); r = random.uniform(0.032, 0.045)
    bpy.ops.mesh.primitive_cylinder_add(vertices=9, radius=r, depth=L, location=(x, y, -0.02 - L / 2 + random.uniform(-0.03, 0.03)))
    o = bpy.context.active_object
    o.rotation_euler = (random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), random.uniform(0, math.tau))
    if i % 2:      # split face: flatten one side
        o.scale = (1.0, 0.72, 1.0)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cylinder_project(direction="ALIGN_TO_OBJECT", scale_to_bounds=True); bpy.ops.object.mode_set(mode="OBJECT")
    o.data.materials.append(mat); objs.append(o)
for z in (-0.16, -0.46):
    bpy.ops.mesh.primitive_torus_add(major_radius=0.13, minor_radius=0.011, major_segments=20, minor_segments=6, location=(0, 0, z))
    t = bpy.context.active_object; t.data.materials.append(rope); objs.append(t)
for o in objs: o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join(); ob = bpy.context.active_object; ob.name = "firewood_bundle"
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.ops.object.shade_flat()
print("TRIS", sum(len(p.vertices) - 2 for p in ob.data.polygons))
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True)
