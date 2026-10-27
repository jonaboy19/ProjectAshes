"""Render a lookdev still of the generated trees (Eevee, sun + sky): blender -b -P preview_trees.py -- <dir> <out.png>"""
import bpy, math, os, sys
args = sys.argv[sys.argv.index("--") + 1:]
d, out = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
x = -22.0
for f in sorted(os.listdir(d)):
    if f.endswith((".glb", ".gltf")):
        bpy.ops.import_scene.gltf(filepath=os.path.join(d, f))
        for o in bpy.context.selected_objects:
            if o.parent is None:
                o.location.x = x
            if o.name.startswith(("LOD1", "LOD2")):
                o.hide_render = True
        x += 9.0
bpy.ops.mesh.primitive_plane_add(size=200)
g = bpy.data.materials.new("ground"); g.use_nodes = True
g.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.25, 0.1, 1)
bpy.context.object.data.materials.append(g)
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); bpy.context.scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sun.data.energy = 4
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); bpy.context.scene.collection.objects.link(cam)
cam.location = (0, -80, 12); cam.rotation_euler = (math.radians(88), 0, 0)
bpy.context.scene.camera = cam
w = bpy.data.worlds.new("w"); bpy.context.scene.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.7, 0.9, 1)
sc = bpy.context.scene
sc.render.resolution_x, sc.render.resolution_y = 1280, 540
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
