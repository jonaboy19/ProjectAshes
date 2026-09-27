# Rest-pose (T-pose) lineup at real heights with labels.
# usage: blender -b --python lineup.py -- <out.png> <glb::height_m::label::mode> ...
#   mode "body": scale so the top of the head/helmet column (|x| < 0.1) == height
#   mode "game": scale like Assets.mh_character (Head bone rest z * 1.1 == height)
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
out = argv[0]
items = [a.split("::") for a in argv[1:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
spacing = 2.05
x = 0.0
maxh = 0.0
for i, it in enumerate(items):
    path, h, label = it[0], float(it[1]), it[2]
    mode = it[3] if len(it) > 3 else "body"
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path, bone_heuristic="BLENDER")
    objs = [o for o in bpy.data.objects if o not in before]
    for o in [o for o in objs if o.name.startswith("Icosphere")]:
        bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.data.objects if o not in before]
    bpy.context.view_layer.update()
    arm = next(o for o in objs if o.type == "ARMATURE")
    ms = [o for o in objs if o.type == "MESH"]
    if mode == "game":
        native = (arm.matrix_world @ arm.data.bones["Head"].head_local).z * 1.1
    else:
        dg = bpy.context.evaluated_depsgraph_get()
        native = 0.0
        for o in ms:
            me = o.evaluated_get(dg).to_mesh()
            for v in me.vertices:
                w = o.matrix_world @ v.co
                if abs(w.x) < 0.1:
                    native = max(native, w.z)
            o.evaluated_get(dg).to_mesh_clear()
    root = bpy.data.objects.new("R%d" % i, None); sc.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    s = h / native
    root.scale = (s, s, s)
    root.location = (x, 0, 0)
    maxh = max(maxh, h)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in ms)
    cu = bpy.data.curves.new("L", "FONT"); cu.body = "%s\n%.2f m  %.1fk tris" % (label, h, tris / 1000.0)
    cu.size = 0.16; cu.align_x = "CENTER"
    t = bpy.data.objects.new("L", cu); sc.collection.objects.link(t)
    t.location = (x, -0.8, -0.3); t.rotation_euler = (math.radians(90), 0, 0)
    mat = bpy.data.materials.new("lab")
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1)
    cu.materials.append(mat)
    x += spacing
# height guide lines every 0.5 m
for zz in (0.5, 1.0, 1.5, 2.0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=((x - spacing) / 2, 0.5, zz))
    ln = bpy.context.active_object; ln.scale = (x + 1.0, 0.002, 0.004)
    m2 = bpy.data.materials.new("g"); m2.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.3, 0.35, 1)
    ln.data.materials.append(m2)
    cu = bpy.data.curves.new("G", "FONT"); cu.body = "%.1f m" % zz; cu.size = 0.12
    t = bpy.data.objects.new("G", cu); sc.collection.objects.link(t)
    t.location = (-1.25, 0.5, zz + 0.02); t.rotation_euler = (math.radians(90), 0, 0); cu.materials.append(m2)
W = x - spacing
cam_d = bpy.data.cameras.new("C"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("C", cam_d); sc.collection.objects.link(cam)
cam.location = (W / 2, -20, maxh / 2 - 0.1)
cam.rotation_euler = (math.radians(90), 0, 0)
sc.render.resolution_x = 2800; sc.render.resolution_y = 820
cam_d.ortho_scale = W + 3.0
sc.camera = cam
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 3.0; sun.color = (1, 0.95, 0.87)
so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(25))
w = bpy.data.worlds.new("W"); sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.66, 0.71, 0.76, 1)
sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("LINEUP", out)
