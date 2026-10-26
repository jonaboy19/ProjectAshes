# Preview render of the small house kit in a row (workbench, material colours). blender -b -P preview_kit.py -- <kit_dir> <out.png>
import bpy, sys, os, math
from mathutils import Vector
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
x = 0.0
for f in sorted(os.listdir(a[0])):
    if not f.endswith(".glb"):
        continue
    bpy.ops.import_scene.gltf(filepath=os.path.join(a[0], f))
    for ob in bpy.context.selected_objects:
        ob.location.x += x
    x += 6.0
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
bpy.context.scene.collection.objects.link(cam)
cam.location = (x * 0.5 - 3, 26, 9)
cam.rotation_euler = (math.radians(74), 0, math.radians(180))
bpy.context.scene.camera = cam
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
bpy.context.scene.collection.objects.link(sun)
sun.rotation_euler = (0.8, 0.2, 2.5)
s = bpy.context.scene
s.render.engine = "BLENDER_WORKBENCH"
s.display.shading.color_type = "MATERIAL"
s.display.shading.light = "STUDIO"
s.display.shading.show_shadows = True
s.render.resolution_x, s.render.resolution_y = 1600, 600
s.render.filepath = a[1]
bpy.ops.render.render(write_still=True)
