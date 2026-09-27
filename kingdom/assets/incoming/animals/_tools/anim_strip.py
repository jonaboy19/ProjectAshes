"""Render one GLB several times side by side, each copy posed in a different action at a given phase.
blender -b --python anim_strip.py -- out.png model.glb [phase=0.5]"""
import bpy, sys, math, mathutils
args = sys.argv[sys.argv.index("--") + 1:]
out, path = args[0], args[1]
phase = float(args[2]) if len(args) > 2 else 0.5
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=path)
for o in list(sc.objects):
    if o.type == "MESH" and o.name.startswith("Icosphere"): bpy.data.objects.remove(o, do_unlink=True)
acts = sorted(a.name for a in bpy.data.actions)
src = [o for o in sc.objects]
arm = [o for o in src if o.type == "ARMATURE"][0]
dims = max(o.dimensions.length for o in src if o.type == "MESH") * max(arm.scale)
step = max(1.2, 0) * 1.0
copies = []
for i, an in enumerate(acts):
    if i == 0:
        objs = src
    else:
        objs = []
        m = {}
        for o in src:
            c = o.copy(); c.data = o.data.copy() if o.type == "ARMATURE" else o.data
            sc.collection.objects.link(c); m[o] = c; objs.append(c)
        for o in src:
            c = m[o]
            if o.parent in m: c.parent = m[o.parent]
            for md in c.modifiers:
                if md.type == "ARMATURE" and md.object in m: md.object = m[md.object]
    a = [o for o in objs if o.type == "ARMATURE"][0]
    a.animation_data_create()
    act = bpy.data.actions[an]
    a.animation_data.action = act
    if act.slots: a.animation_data.action_slot = act.slots[0]
    copies.append((a, act))
# evaluate each armature at its own phase by baking pose into a static copy is complex; instead use NLA-free trick:
# set scene frame per action is impossible simultaneously -> use action frame offset via NLA strips
for a, act in copies:
    a.animation_data.action = None
    tr = a.animation_data.nla_tracks.new()
    fs, fe = act.frame_range
    st = tr.strips.new(act.name, 1000, act)
    st.action_frame_start = fs + (fe - fs) * phase
    st.action_frame_end = st.action_frame_start + 1
    st.frame_end = 1001
for a, act in copies:
    a.rotation_mode = "XYZ"; a.rotation_euler.z += math.radians(-70)
sc.frame_set(1000)
bpy.context.view_layer.update()
# layout along X
dg = bpy.context.evaluated_depsgraph_get()
L = []
for idx, (a, act) in enumerate(copies):
    a.location.x += 0
x = 0
labels = []
for a, act in copies:
    meshes = [o for o in sc.objects if o.type == "MESH" and o.parent == a]
    mn = mathutils.Vector((1e9,) * 3); mx = -mn
    for o in meshes:
        oe = o.evaluated_get(dg); me = oe.to_mesh()
        for v in me.vertices:
            w = oe.matrix_world @ v.co; mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
        oe.to_mesh_clear()
    wdt = max(mx.y - mn.y, mx.x - mn.x)
    a.location.x += x - mn.x
    t = bpy.data.curves.new("t", "FONT"); t.body = act.name; t.size = wdt * 0.12 + 0.02; t.align_x = "LEFT"
    to = bpy.data.objects.new("t", t); sc.collection.objects.link(to); to.location = (x, mn.y - 0.1, 0); to.rotation_euler = (math.radians(90), 0, 0)
    x += (mx.x - mn.x) + wdt * 0.4
    labels.append(to)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
mn = mathutils.Vector((1e9,) * 3); mx = -mn
for o in sc.objects:
    if o.type != "MESH": continue
    oe = o.evaluated_get(dg); me = oe.to_mesh()
    for v in me.vertices:
        w = oe.matrix_world @ v.co; mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    oe.to_mesh_clear()
for l in labels: l.location.z = mn.z - (mx.z - mn.z) * 0.18
sun = bpy.data.lights.new("s", "SUN"); sun.energy = 3; so = bpy.data.objects.new("s", sun); sc.collection.objects.link(so); so.rotation_euler = (0.8, 0, 0.6)
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.8, 0.82, 0.85, 1)
cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
co.rotation_euler = (math.radians(90), 0, 0)
Wd = mx.x - mn.x; Hd = (mx.z - mn.z) * 1.45
co.location = ((mn.x + mx.x) / 2, mn.y - 50, (mn.z + mx.z) / 2 - (mx.z - mn.z) * 0.12)
sc.render.resolution_x = 2000; sc.render.resolution_y = max(200, min(1000, int(2000 * Hd / Wd)))
cam.ortho_scale = max(Wd, Hd * 2000 / sc.render.resolution_y) * 1.04; cam.clip_end = 200
sc.render.engine = "BLENDER_EEVEE"; sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
