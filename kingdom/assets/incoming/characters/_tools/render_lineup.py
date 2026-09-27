# Scale/style check: characters at real heights in an idle pose, standing in front of an
# accepted asset (a Meshy building), rendered 3/4 with warm light.
# usage: blender -b --python render_lineup.py -- <out.png> <building.glb> <idle_lib.glb::Clip> <char.glb::height_m::label> ...
import bpy, sys, math
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
out, building, idle = argv[0], argv[1], argv[2]
bsize = float(building.split("::")[1]) if "::" in building else 0.0
building = building.split("::")[0]
chars = [a.split("::") for a in argv[3:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
def imp(p, heur="BLENDER"):
    before = set(bpy.data.objects); ba = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=p, bone_heuristic=heur)
    for o in [o for o in bpy.data.objects if o not in before and o.name.startswith("Icosphere")]:
        bpy.data.objects.remove(o, do_unlink=True)
    return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in ba]
bobjs, _ = imp(building, "TEMPERANCE")
# building: put its footprint behind the line of characters
pts = [o.matrix_world @ Vector(c) for o in bobjs if o.type == "MESH" for c in o.bound_box]
bmin = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
bmax = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
broot = bpy.data.objects.new("B", None); sc.collection.objects.link(broot)
for o in bobjs:
    if o.parent is None:
        o.parent = broot
bs = bsize / max(bmax.x - bmin.x, bmax.y - bmin.y) if bsize else 1.0
broot.scale = (bs, bs, bs)
broot.location = (-(bmin.x + bmax.x) / 2 * bs, 1.0 - bmin.y * bs, -bmin.z * bs)
print("building size", bmax - bmin)
lib, clip = idle.split("::")
lobjs, lacts = imp(lib)
for o in lobjs:
    bpy.data.objects.remove(o, do_unlink=True)
act = next(a for a in lacts if a.name.startswith(clip))
n = len(chars); spacing = 0.85
for i, (path, h, label) in enumerate(chars):
    objs, _ = imp(path)
    arm = next(o for o in objs if o.type == "ARMATURE")
    arm.animation_data_create(); arm.animation_data.action = act
    if len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    sc.frame_set(int(act.frame_range[0]) + 5)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    zs = []
    for o in objs:
        if o.type == "MESH":
            me = o.evaluated_get(dg).to_mesh()
            zs += [(o.matrix_world @ v.co).z for v in me.vertices]
            o.evaluated_get(dg).to_mesh_clear()
    s = float(h) / (max(zs) - min(zs))
    arm.scale = (s, s, s)
    arm.location = ((i - (n - 1) / 2) * spacing, -0.6, -min(zs) * s)
    arm.rotation_euler.z = math.radians(15)
    cu = bpy.data.curves.new("L", "FONT"); cu.body = "%s\n%.2f m" % (label, float(h)); cu.size = 0.09; cu.align_x = "CENTER"
    t = bpy.data.objects.new("L", cu); sc.collection.objects.link(t)
    t.location = ((i - (n - 1) / 2) * spacing, -1.2, 0.02); t.rotation_euler = (math.radians(70), 0, 0)
# ground
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
g = bpy.context.object; m = bpy.data.materials.new("g"); m.use_nodes = True
m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.47, 0.33, 1); g.data.materials.append(m)
cam_d = bpy.data.cameras.new("C"); cam_d.lens = 35
cam = bpy.data.objects.new("C", cam_d); sc.collection.objects.link(cam)
W = n * spacing
cam.location = (W * 0.35, -max(7.5, W * 1.1), 2.2)
look = Vector((0, 0.3, 1.9)) - cam.location
cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler(); sc.camera = cam
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 3.5; sun.color = (1, 0.93, 0.8); sun.angle = 0.1
so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(35))
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.9, 1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng; break
    except Exception:
        pass
sc.view_settings.view_transform = "Standard"
sc.render.resolution_x = 1920; sc.render.resolution_y = 1080
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("LINEUP", out)
