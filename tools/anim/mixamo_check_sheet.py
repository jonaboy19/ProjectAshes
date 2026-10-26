"""Check sheet for a UAL clip-library GLB: one row per clip, N evenly spaced frames, the UAL mannequin on a 25 cm
checker floor (feet sinking into the floor / hovering / sliding against the checker show directly).

  blender -b --python tools/anim/mixamo_check_sheet.py -- <library.glb> <out.png> [yaw_deg=90] [frames=8] [clip_substr]

yaw 0 = side view (profile, character faces right), 90 = front, 25 = three-quarter. Frame label: clip name + frame index.
"""
import bpy, sys, math, os
argv = sys.argv[sys.argv.index("--") + 1:]
lib, out = argv[0], argv[1]
yaw = float(argv[2]) if len(argv) > 2 else 0.0
N = int(argv[3]) if len(argv) > 3 else 8
only = argv[4] if len(argv) > 4 else ""
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UAL = os.path.join(REPO, "kingdom/assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb")
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene


def imp(p):
    before = set(bpy.data.objects); ba = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=p, bone_heuristic="BLENDER")
    return [o for o in bpy.data.objects if o not in before], [a for a in bpy.data.actions if a not in ba]


cobjs, cacts = imp(UAL)
ico = [o for o in cobjs if o.name.startswith("Icosphere")]
cobjs = [o for o in cobjs if o not in ico]
for o in ico:
    bpy.data.objects.remove(o, do_unlink=True)
for a in cacts:
    bpy.data.actions.remove(a)
carm = [o for o in cobjs if o.type == "ARMATURE"][0]
if carm.animation_data:
    carm.animation_data_clear()
lobjs, acts = imp(lib)
for o in lobjs:
    bpy.data.objects.remove(o, do_unlink=True)
acts = sorted([a for a in acts if only.lower() in a.name.lower()], key=lambda a: a.name)

fig_mat = bpy.data.materials.new("fig"); fig_mat.use_nodes = True
fig_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.62, 0.45, 1)
gm = bpy.data.materials.new("grid"); gm.use_nodes = True
nt = gm.node_tree
chk = nt.nodes.new("ShaderNodeTexChecker"); chk.inputs["Scale"].default_value = 1.0
chk.inputs["Color1"].default_value = (0.25, 0.27, 0.3, 1); chk.inputs["Color2"].default_value = (0.42, 0.45, 0.5, 1)
tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
mp.inputs["Scale"].default_value = (2.0, 2.0, 2.0)   # object coords in m -> 0.5 m checker period -> 25 cm squares
nt.links.new(tc.outputs["Object"], mp.inputs["Vector"]); nt.links.new(mp.outputs["Vector"], chk.inputs["Vector"])
nt.links.new(chk.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
lab_mat = bpy.data.materials.new("lab"); lab_mat.use_nodes = True
lab_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.02, 0.03, 1)

GF = 1000
dx, dz = 1.7, 2.6
for r, act in enumerate(acts):
    f0, f1 = act.frame_range
    name = act.name.split("|")[0].rsplit("_Armature", 1)[0]
    for c in range(N):
        local = f0 + (f1 - f0) * c / max(1, N - 1)
        new = {}
        for o in cobjs:
            cp = o.copy()
            if o.type == "ARMATURE":
                cp.data = o.data.copy()
            sc.collection.objects.link(cp); new[o] = cp
        for o, cp in new.items():
            if o.parent in new:
                cp.parent = new[o.parent]
            for m in cp.modifiers:
                if m.type == "ARMATURE" and m.object == carm:
                    m.object = new[carm]
            if cp.type == "MESH":
                cp.data.materials.clear(); cp.data.materials.append(fig_mat)
        arm = new[carm]
        top = arm if arm.parent is None else [cp for o, cp in new.items() if o.parent is None][0]
        top.location = (c * dx, 0, -r * dz)
        top.rotation_euler.z = math.radians(yaw)
        arm.animation_data_create()
        tr = arm.animation_data.nla_tracks.new()
        st = tr.strips.new(name, int(f0), act)
        st.frame_start = GF - (local - f0)
        st.frame_end = st.frame_start + (f1 - f0)
        st.extrapolation = "HOLD"
        bpy.ops.mesh.primitive_plane_add(size=1.5, location=(c * dx, 0, -r * dz))
        pl = bpy.context.active_object; pl.data.materials.append(gm)
        cu = bpy.data.curves.new("L", "FONT"); cu.body = "%s  f%d" % (name if c == 0 else "", int(round(local - f0)))
        cu.size = 0.11; cu.materials.append(lab_mat)
        t = bpy.data.objects.new("L", cu); sc.collection.objects.link(t)
        t.location = (c * dx - 0.75, -0.8, -r * dz + 2.05); t.rotation_euler = (math.radians(90), 0, 0)
for o in cobjs:
    o.hide_render = True; o.hide_set(True)
sc.frame_set(GF)
rows = len(acts)
W = (N - 1) * dx; H = (rows - 1) * dz
cam_d = bpy.data.cameras.new("C"); cam_d.type = "ORTHO"
cam = bpy.data.objects.new("C", cam_d); sc.collection.objects.link(cam)
el = math.radians(8)
cam.location = (W / 2, -30 * math.cos(el), -H / 2 + 0.95 + 30 * math.sin(el))
cam.rotation_euler = (math.radians(90) - el, 0, 0)
sc.render.resolution_x = 230 * N; sc.render.resolution_y = 350 * rows
rx, ry = sc.render.resolution_x, sc.render.resolution_y
cam_d.ortho_scale = max(W + dx, (H + dz) * rx / ry) if rx >= ry else max((W + dx) * ry / rx, H + dz)
sc.camera = cam
sun = bpy.data.lights.new("S", "SUN"); sun.energy = 1.6
so = bpy.data.objects.new("S", sun); sc.collection.objects.link(so); so.rotation_euler = (math.radians(50), 0, math.radians(30))
w = bpy.data.worlds.new("W"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.7, 0.74, 0.78, 1)
sc.render.engine = "BLENDER_EEVEE"
sc.view_settings.view_transform = "Standard"
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("SHEET", out, rows, "clips")
