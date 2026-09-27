"""Labelled to-scale contact sheet, 3/4 view.
blender -b --python contact_sheet.py -- out.png rows.json
rows.json: [[ [label, glb_or_HUMAN], ... ], ...]  (one inner list per row; first row is nearest the camera)"""
import bpy, sys, os, math, json, mathutils
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
out, spec = args[0], args[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rows = json.load(open(spec))
YAW = math.radians(-38)

def bounds(objs):
    dg = bpy.context.evaluated_depsgraph_get(); mn = Vector((1e9,) * 3); mx = -mn
    for o in objs:
        if o.type != "MESH": continue
        oe = o.evaluated_get(dg); m = oe.to_mesh()
        for v in m.vertices:
            w = oe.matrix_world @ v.co
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
        oe.to_mesh_clear()
    return mn, mx

def load(label, path):
    before = set(bpy.data.objects); acts_before = set(bpy.data.actions)
    if path == "HUMAN":
        bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.22, depth=1.75, location=(0, 0, 0.875))
        o = bpy.context.object; m = bpy.data.materials.new("hum"); m.diffuse_color = (0.5, 0.5, 0.55, 1)
        o.data.materials.append(m)
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            new.remove(o); bpy.data.objects.remove(o, do_unlink=True)
    acts = [a for a in bpy.data.actions if a not in acts_before]
    idle = next((a for a in acts if a.name.split(".")[0] == "Idle"), None)
    for o in new:
        if o.type == "ARMATURE":
            o.animation_data_create()
            if idle:
                o.animation_data.action = idle
                if idle.slots: o.animation_data.action_slot = idle.slots[0]
    root = bpy.data.objects.new("R_" + label, None); sc.collection.objects.link(root)
    for o in new:
        if o.parent is None: o.parent = root
    root.rotation_euler = (0, 0, YAW)
    return root, new

txt = bpy.data.materials.new("txt"); txt.use_nodes = True
txt.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.025, 0.02, 1)
txt.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
cam_rot = mathutils.Euler((math.radians(62), 0, 0))
sc.frame_set(10)
y = 0.0
allobjs = []
for row in rows:
    loaded = [(lab, *load(lab, p)) for lab, p in row]
    sc.frame_set(10); bpy.context.view_layer.update()
    x = 0.0; ymin_row = 1e9; depth = 0
    info = []
    size = float(os.environ.get("LABEL", "0.14"))
    for lab, root, objs in loaded:
        mn, mx = bounds(objs)
        w = mx.x - mn.x
        adv = max(w, len(lab) * size * 0.62)
        x += (adv - w) / 2
        root.location = (x - mn.x, y - (mn.y + mx.y) / 2, -mn.z)
        info.append((lab, x + w / 2, mx.z - mn.z, w))
        x += w + (adv - w) / 2 + max(size * 1.5, w * 0.2)
        depth = max(depth, mx.y - mn.y)
        allobjs += objs
    for lab, cx, h, w in info:
        t = bpy.data.curves.new("T", "FONT"); t.body = "%s\n%.2f m" % (lab, h)
        t.size = size; t.align_x = "CENTER"; t.materials.append(txt)
        to = bpy.data.objects.new("T", t); sc.collection.objects.link(to)
        to.location = (cx, y - depth / 2 - size * 1.2, 0.005); to.rotation_euler = (0, 0, 0)
        allobjs.append(to)
    y += depth * 1.6 + size * 6

bpy.ops.mesh.primitive_plane_add(size=500, location=(0, 0, 0))
g = bpy.context.object; gm = bpy.data.materials.new("g"); gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.42, 0.25, 1)
gm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
g.data.materials.append(gm)
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.4; sun.angle = 0.15
so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(42), 0, math.radians(30))
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.75, 0.72, 0.62, 1); bg.inputs[1].default_value = 0.9

bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
pts = []
for o in allobjs:
    if o.type in ("MESH", "FONT"):
        oe = o.evaluated_get(dg)
        try: me = oe.to_mesh()
        except Exception: continue
        pts += [oe.matrix_world @ v.co for v in me.vertices]
        oe.to_mesh_clear()
cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"; cam.clip_end = 500
co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co); sc.camera = co
co.rotation_euler = cam_rot; co.location = (0, 0, 0)
bpy.context.view_layer.update()
inv = co.matrix_world.inverted()
lp = [inv @ p for p in pts]
x0, x1 = min(p.x for p in lp), max(p.x for p in lp); y0, y1 = min(p.y for p in lp), max(p.y for p in lp)
W, H = (x1 - x0) * 1.04, (y1 - y0) * 1.06
co.location = co.matrix_world @ Vector(((x0 + x1) / 2, (y0 + y1) / 2, 100))
RX = 2400
sc.render.resolution_x = RX; sc.render.resolution_y = max(400, min(3000, int(RX * H / W)))
cam.ortho_scale = max(W, H * RX / sc.render.resolution_y)
sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
