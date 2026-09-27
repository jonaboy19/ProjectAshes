# (copy of characters/_tools/render_poses.py with a larger tile: env PW/PH px per tile)
# Pose sheet: plays clips from UAL-skeleton libraries on a character that uses the
# UAL skeleton (e.g. a MakeHuman villager) and renders a labelled grid.
# usage: blender -b --python render_poses.py -- <character.glb> <out.png> <cols> <lib.glb::Clip::frac> ...
# Both files are imported with bone_heuristic=BLENDER so bone rests are the raw glTF
# rests; because the villager rest rotations equal UAL's, the pose basis transfers 1:1.
import bpy, sys, math, os
from mathutils import Vector
argv = sys.argv[sys.argv.index("--") + 1:]
char, out, cols = argv[0], argv[1], int(argv[2])
items = [a.split("::") for a in argv[3:]]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def imp(p):
    before = set(bpy.data.objects); ba = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=p, bone_heuristic="BLENDER")
    for o in [o for o in bpy.data.objects if o not in before and o.name.startswith("Icosphere")]:
        bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.data.objects if o not in before]
    acts = [a for a in bpy.data.actions if a not in ba]
    return objs, acts

cobjs, _ = imp(char)
carm = [o for o in cobjs if o.type == "ARMATURE"][0]
libs = {}
for it in items:
    lib = it[0]
    if lib not in libs:
        objs, acts = imp(lib)
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        libs[lib] = {a.name.split("|")[0]: a for a in acts}
        # glTF importer may name actions "Clip_Armature" -> index by prefix too
        for a in acts:
            libs[lib].setdefault(a.name.rsplit("_Armature", 1)[0], a)

GF = 1000
rows = math.ceil(len(items) / cols)
dx, dz = 1.5, 2.5
for i, (lib, clip, frac) in enumerate(items):
    act = libs[lib].get(clip) or next((a for n, a in libs[lib].items() if n.startswith(clip)), None)
    if act is None:
        print("MISSING clip", clip, "available:", sorted(libs[lib])[:200]); continue
    # duplicate character
    new = {}
    for o in cobjs:
        c = o.copy()
        if o.type == "ARMATURE":
            c.data = o.data.copy()
        sc.collection.objects.link(c); new[o] = c
    for o, c in new.items():
        if o.parent in new:
            c.parent = new[o.parent]
        for m in c.modifiers:
            if m.type == "ARMATURE" and m.object == carm:
                m.object = new[carm]
    arm = new[carm]
    top = arm if arm.parent is None else [c for o, c in new.items() if o.parent is None][0]
    r, col = divmod(i, cols)
    top.location = (col * dx, 0, -r * dz)
    top.rotation_euler.z = math.radians(25)
    arm.animation_data_create()
    fr = act.frame_range
    local = fr[0] + (fr[1] - fr[0]) * float(frac)
    tr = arm.animation_data.nla_tracks.new()
    st = tr.strips.new(clip, int(fr[0]), act)
    st.frame_start = GF - (local - fr[0])
    st.frame_end = st.frame_start + (fr[1] - fr[0])
    st.extrapolation = "HOLD"
    # label
    cu = bpy.data.curves.new("L", "FONT"); cu.body = clip; cu.size = 0.13; cu.align_x = "CENTER"
    t = bpy.data.objects.new("L", cu); sc.collection.objects.link(t)
    t.location = (col * dx, -0.6, -r * dz - 0.3); t.rotation_euler = (math.radians(90), 0, 0)
    mat = bpy.data.materials.new("lab"); mat.use_nodes = True
    mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1)
    cu.materials.append(mat)
for o in cobjs:
    o.hide_render = True; o.hide_set(True)
sc.frame_set(GF)
W = (cols - 1) * dx; H = (rows - 1) * dz
cam_d = bpy.data.cameras.new("C"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("C", cam_d); sc.collection.objects.link(cam)
cam.location = (W / 2, -20, -H / 2 + 0.9 + 20 * math.tan(math.radians(6)))
cam.rotation_euler = (math.radians(84), 0, 0)
sc.render.resolution_x = int(os.environ.get("PW", "420")) * cols; sc.render.resolution_y = int(int(os.environ.get("PH", "620")) * rows)
cam_d.ortho_scale = max(W + dx, (H + dz) * sc.render.resolution_x / sc.render.resolution_y)
sc.camera = cam
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 3.0; sun.color = (1, 0.95, 0.87)
so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(45), 0, math.radians(25))
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.66, 0.71, 0.76, 1)
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng; break
    except Exception:
        pass
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("POSES", out)
