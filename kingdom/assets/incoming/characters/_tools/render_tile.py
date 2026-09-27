# Render one labelled-ready tile (3/4 view, feet at origin, scaled to a target height).
# usage: blender -b --python render_tile.py -- <entry.json> <out.png>
# entry: {"label":..., "files":[...], "show": regex (keep only matching mesh names, optional),
#         "hide": regex (optional), "height": 1.75, "rest": true, "yaw": 0,
#         "action": name (optional, pose at "frame_frac"), "scale_mode": "height"|"native"}
import bpy, sys, json, os, re, math
from mathutils import Vector, Matrix
argv = sys.argv[sys.argv.index("--") + 1:]
e = json.load(open(argv[0], encoding="utf-8")); out = argv[1]
files = e["files"]
first = files[0]
if first.lower().endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=first)
    files = files[1:]
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
for f in files:
    x = os.path.splitext(f)[1].lower()
    if x == ".fbx":
        bpy.ops.import_scene.fbx(filepath=f)
    else:
        bpy.ops.import_scene.gltf(filepath=f)
sc = bpy.context.scene
for o in list(sc.objects):
    if o.type in ("LIGHT", "CAMERA"):
        bpy.data.objects.remove(o)
def _unexclude(lc):
    lc.exclude = False; lc.hide_viewport = False
    lc.collection.hide_render = False
    for c in lc.children:
        _unexclude(c)
_unexclude(bpy.context.view_layer.layer_collection)
show = re.compile(e["show"]) if e.get("show") else None
hide = re.compile(e.get("hide", r"^(Icosphere|Plane|Cube)(\.\d+)?$"))
meshes = []
for o in sc.objects:
    if o.type != "MESH":
        continue
    vis = not o.hide_render and not o.hide_get()
    if show is not None:
        vis = bool(show.search(o.name))
    if hide.search(o.name):
        vis = False
    o.hide_render = not vis
    o.hide_set(not vis)
    if vis:
        meshes.append(o)
if e.get("autotex"):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import autotex
    for o in meshes:
        print("autotex", o.name, autotex.fix(o))
arms = [o for o in sc.objects if o.type == "ARMATURE"]
act_name = e.get("action")
for a in arms:
    if act_name:
        act = next((x for x in bpy.data.actions if x.name == act_name or x.name.startswith(act_name)), None)
        if act:
            a.animation_data_create(); a.animation_data.action = act
            if len(act.slots):
                a.animation_data.action_slot = act.slots[0]
            fr = act.frame_range
            sc.frame_set(int(fr[0] + (fr[1] - fr[0]) * e.get("frame_frac", 0.5)))
    elif e.get("rest", True):
        a.data.pose_position = "REST"
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
tris = 0
pts = []
for o in meshes:
    ev = o.evaluated_get(dg); me = ev.to_mesh()
    tris += sum(len(p.vertices) - 2 for p in me.polygons)
    mw = o.matrix_world
    pts += [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
h = mx.z - mn.z
# Parent everything under an empty to normalise scale/position.
root = bpy.data.objects.new("ROOT", None); sc.collection.objects.link(root)
s = 1.0 if e.get("scale_mode") == "native" else e.get("height", 1.75) / max(h, 1e-6)
for o in sc.objects:
    if o.parent is None and o is not root:
        o.parent = root
root.location = (-(mn.x + mx.x) / 2 * s, -(mn.y + mx.y) / 2 * s, -mn.z * s)
root.scale = (s, s, s)
root.rotation_euler.z = math.radians(e.get("yaw", 0))
if e.get("yaw", 0):
    # rotate about the figure centre: recompute location after rotation
    c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z)) * s
    rot = Matrix.Rotation(math.radians(e["yaw"]), 3, "Z")
    root.location = -(rot @ c)
H = h * s
# camera 3/4 front (front = -Y)
cam_d = bpy.data.cameras.new("C"); cam_d.type = "ORTHO"; Wd = max(mx.x - mn.x, mx.y - mn.y) * s
cam_d.ortho_scale = max(H * 1.1, Wd * 1.45, 0.5)
cam = bpy.data.objects.new("C", cam_d); sc.collection.objects.link(cam)
az = math.radians(-35); el = math.radians(12); dist = 10
cam.location = (math.sin(-az) * dist * -1 * -1 * math.cos(el) * 1, -math.cos(az) * dist * math.cos(el), H * 0.5 + dist * math.sin(el))
cam.location.x = dist * math.cos(el) * math.sin(math.radians(35))
look = Vector((0, 0, H * 0.5)) - cam.location
cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()
sc.camera = cam
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 3.2; sun.color = (1.0, 0.94, 0.85)
so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(30))
fill = bpy.data.lights.new("F", "SUN"); fill.energy = 0.8; fill.color = (0.75, 0.85, 1.0)
fo = bpy.data.objects.new("F", fill); sc.collection.objects.link(fo); fo.rotation_euler = (math.radians(60), 0, math.radians(200))
w = sc.world or bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
bg = w.node_tree.nodes.get("Background"); bg.inputs[0].default_value = (0.62, 0.68, 0.74, 1); bg.inputs[1].default_value = 0.9
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng; break
    except Exception:
        pass
sc.render.resolution_x = e.get("w", 320); sc.render.resolution_y = e.get("h", 480)
sc.render.film_transparent = False
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("TILE", json.dumps({"label": e["label"], "tris": tris, "native_h": round(h, 3), "out": out}))
