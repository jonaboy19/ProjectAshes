# Labelled 3/4-view contact sheet: one tile per model, montaged with ffmpeg.
# blender -b --factory-startup --python render_sheet.py -- spec.json
# spec: {"out": "x.jpg", "cols": 6, "px": 320,
#        "normalize": true,              # fit every model to its tile (label shows real size in m)
#        "reference": "guard.glb",       # optional: drawn in every tile at real scale (then normalize is ignored)
#        "items": [{"file": "a.glb", "label": "a", "scale": 1.0, "offset": [0,0,0]}]}
import bpy, sys, json, os, math, mathutils, subprocess, tempfile, shutil

spec = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
px = spec.get("px", 320)
cols = spec.get("cols", 6)
ref = spec.get("reference")
tmp = tempfile.mkdtemp(prefix="sheet_")


def import_file(path):
    path = os.path.abspath(path)
    before = set(bpy.data.objects)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = [n for n in src.objects]
        for o in dst.objects:
            if o is not None and o.type in ("MESH", "ARMATURE"):
                bpy.context.scene.collection.objects.link(o)
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o)
    new = [o for o in bpy.data.objects if o not in before]
    shapes = {pb.custom_shape for o in new if o.type == "ARMATURE" for pb in o.pose.bones if pb.custom_shape}
    for o in list(new):
        if o in shapes or (o.type == "MESH" and o.name.startswith("Icosphere") and o.parent is None):
            new.remove(o); bpy.data.objects.remove(o)
    for o in new:
        if o.type == "ARMATURE":
            o.data.pose_position = "REST"
        if o.animation_data:
            o.animation_data.action = None
    bpy.context.view_layer.update()
    return new


def world_bbox(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    mn = mathutils.Vector((1e18,) * 3); mx = -mn
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.evaluated_get(dg).bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    return mn, mx


def setup_scene(frame_h):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"; cam.ortho_scale = frame_h
    co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co)
    az, el, d = math.radians(35), math.radians(22), 20
    tgt = mathutils.Vector((0, 0, frame_h * 0.40))
    co.location = tgt + mathutils.Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el))) * d
    co.rotation_euler = (tgt - co.location).to_track_quat("-Z", "Y").to_euler()
    sc.camera = co
    sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 3.0; sun.angle = 0.4
    so = bpy.data.objects.new("sun", sun); sc.collection.objects.link(so)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(20))
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.80, 0.78, 0.72, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = px; sc.render.resolution_y = px
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.render.image_settings.file_format = "PNG"
    # label, parented to camera
    cu = bpy.data.curves.new("lbl", "FONT"); cu.size = frame_h * 0.052; cu.align_x = "CENTER"
    t = bpy.data.objects.new("lbl", cu); sc.collection.objects.link(t)
    t.parent = co; t.location = (0, -frame_h * 0.43, -1)
    m = bpy.data.materials.new("lbl"); m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    bsdf.inputs["Emission Color"].default_value = (0, 0, 0, 1)
    cu.materials.append(m)
    return sc, cu


items = spec["items"]
for i, it in enumerate(items):
    frame_h = 2.3 if ref else 1.5
    sc, cu = setup_scene(frame_h)
    if ref:
        robjs = import_file(ref)
        rmn, rmx = world_bbox(robjs)
        rr = bpy.data.objects.new("refroot", None); sc.collection.objects.link(rr)
        for o in robjs:
            if o.parent is None:
                o.parent = rr
        rr.location = (it.get("ref_x", -0.45) - (rmn.x + rmx.x) / 2, -(rmn.y + rmx.y) / 2, -rmn.z)
    try:
        objs = import_file(it["file"])
        mn, mx = world_bbox(objs)
        size = mx - mn
        root = bpy.data.objects.new("root", None); sc.collection.objects.link(root)
        for o in objs:
            if o.parent is None:
                o.parent = root
        if ref and it.get("raw"):
            pass
        elif ref:
            s = it.get("scale", 1.0)
            off = mathutils.Vector(it.get("offset", (0.45, 0, 0)))
            root.scale = (s,) * 3
            root.location = off + mathutils.Vector((-(mn.x + mx.x) / 2 * s, -(mn.y + mx.y) / 2 * s, -mn.z * s if "offset" not in it else 0))
        else:
            s = 1.0 / max(size.x, size.y, size.z, 1e-6)
            root.scale = (s,) * 3
            root.location = (-(mn.x + mx.x) / 2 * s, -(mn.y + mx.y) / 2 * s, -mn.z * s + 0.12)
        lab = it.get("label", os.path.basename(it["file"]))
        extra = it.get("note", "")
        cu.body = lab + ("\n" + extra if extra else "") + ("" if ref else "\n%.2f x %.2f x %.2f" % (size.x, size.y, size.z))
    except Exception as e:
        cu.body = "ERROR " + os.path.basename(it["file"]) + "\n" + str(e)[:40]
    sc.render.filepath = os.path.join(tmp, "t_%04d.png" % i)
    bpy.ops.render.render(write_still=True)

n = len(items)
rows = math.ceil(n / cols)
blank = os.path.join(tmp, "t_%04d.png" % n)
for j in range(n, rows * cols):
    shutil.copy(os.path.join(tmp, "t_0000.png"), os.path.join(tmp, "t_%04d.png" % j))
    # grey out filler tiles
if rows * cols > n:
    for j in range(n, rows * cols):
        img = bpy.data.images.load(os.path.join(tmp, "t_%04d.png" % j))
        img.pixels = [0.8] * len(img.pixels)
        img.save()
ff = spec.get("ffmpeg", "ffmpeg")
subprocess.check_call([ff, "-y", "-loglevel", "error", "-i", os.path.join(tmp, "t_%04d.png"),
                       "-vf", "tile=%dx%d" % (cols, rows), "-frames:v", "1", "-q:v", "3", os.path.abspath(spec["out"])])
shutil.rmtree(tmp, ignore_errors=True)
print("WROTE", spec["out"])
