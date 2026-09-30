# Stop-motion preview of LIFE clips on the UAL mannequin, WITH their hand props and smart-object anchor proxy,
# so prop contact (hammer on anvil, hoe in the soil, mug at the mouth) can be judged frame by frame.
#
#   blender -b -P render_life_preview.py -- <lib.glb> <out_dir> [clip,clip,...] [step=1] [views=side,q34,front]
#   -> <out_dir>/<clip>/frames/frame00000000.png ...  (views hstacked by ffmpeg), <clip>.stats.json
#   then: SRC_FPS=30 bash tools/qa/video_to_sheets.sh <out_dir>/<clip>/frames <sheet_dir> 15 6 3 360
#
# Props: <lib.glb>.life.json lists each clip's props ({"id","hand"}) and anchor; the prop GLB comes from
# data/living_world/life_props.json when it exists, otherwise an orange stick shows the grip axis (thumb side, 0.9 m)
# and a blue stub the knuckle axis. The grip frame is computed from the REST bones exactly like
# scripts/living_world/life_props.gd (see life_common.py). Pair clips (pair.partner) render the partner facing the
# character at pair.distance. Anchor: a grey box whose top-centre sits at anchor.at (character frame: +x left,
# +y forward, +z up) with size anchor.size (default 0.5 x 0.4 x at.z).
import bpy, sys, os, math, subprocess, shutil, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
LIB = os.path.abspath(argv[0])
OUT = os.path.abspath(argv[1])
ONLY = argv[2].split(",") if len(argv) > 2 and argv[2] else None
STEP = int(argv[3]) if len(argv) > 3 and argv[3] else 1
VIEWS = argv[4].split(",") if len(argv) > 4 and argv[4] else ["side", "q34", "front"]
HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
UAL = os.path.join(KING, "assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb")
W, H = int(os.environ.get("PW", 340)), int(os.environ.get("PH", 420))
SIDE = json.load(open(LIB + ".life.json")) if os.path.exists(LIB + ".life.json") else {"clips": {}}
PROPS = json.load(open(os.path.join(KING, "data/living_world/life_props.json")))["hand"]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30


def import_ual():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=UAL)
    objs = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in objs if o.type == "ARMATURE"][0]
    for o in objs:
        if o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
    return arm


ual_arm = import_ual()
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=LIB)
for o in [o for o in bpy.data.objects if o not in before]:
    bpy.data.objects.remove(o)
actions = {a.name: a for a in bpy.data.actions}
partner_arm = None


def clear_nla(arm):
    arm.animation_data_create()
    for tr in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(tr)


clear_nla(ual_arm)

# ---- look
for m in bpy.data.materials:
    if m.name == "M_Main":
        m.diffuse_color = (0.86, 0.66, 0.42, 1)
    elif m.name == "M_Joints":
        m.diffuse_color = (0.35, 0.36, 0.42, 1)
scene.render.engine = "BLENDER_WORKBENCH"
sh = scene.display.shading
sh.light = "STUDIO"
sh.color_type = "MATERIAL"
sh.show_object_outline = True
sh.object_outline_color = (0.05, 0.05, 0.05)
scene.display.render_aa = "8"
scene.render.resolution_x, scene.render.resolution_y = W, H
scene.render.image_settings.file_format = "PNG"
w = bpy.data.worlds.new("W")
w.color = (0.80, 0.86, 0.92)
scene.world = w


def mat(name, col):
    m = bpy.data.materials.new(name)
    m.diffuse_color = col
    return m


GRID = mat("grid", (0.55, 0.6, 0.65, 1))
AXY = mat("axy", (0.85, 0.15, 0.1, 1))
AXX = mat("axx", (0.15, 0.6, 0.2, 1))
FLOOR = mat("floor", (0.66, 0.72, 0.62, 1))
STICK = mat("stick", (1.0, 0.55, 0.05, 1))
KNUCK = mat("knuck", (0.1, 0.35, 1.0, 1))
ANCH = mat("anch", (0.45, 0.45, 0.48, 1))


def box(name, sx, sy, sz, loc, m):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (sx, sy, sz)
    o.data.materials.append(m)
    return o


box("floor", 5, 5, 0.01, (0, 0, -0.006), FLOOR)
for i in range(-8, 9):
    p = i * 0.25
    box("gx%d" % i, 0.008, 4.0, 0.004, (p, 0, 0.001), AXX if i == 0 else GRID)
    box("gy%d" % i, 4.0, 0.008, 0.004, (0, p, 0.001), AXY if i == 0 else GRID)


def make_cam(name, loc, target, scale):
    cd = bpy.data.cameras.new(name)
    cd.type = "ORTHO"
    cd.ortho_scale = scale
    co = bpy.data.objects.new(name, cd)
    scene.collection.objects.link(co)
    co.location = loc
    d = Vector(target) - Vector(loc)
    co.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    return co


SC = float(os.environ.get("ORTHO", 2.75))
CZ = float(os.environ.get("CAMZ", 1.0))
CAMS = {
    "side": make_cam("side", (-8, -0.15, CZ), (0, -0.15, CZ), SC),
    "front": make_cam("front", (0, -8, CZ), (0, 0, CZ), SC),
    "q34": make_cam("q34", (-5.0, -5.0, CZ + 0.1), (0, 0, CZ), SC + 0.1),
    "top": make_cam("top", (0, -0.2, 8), (0, -0.2, 0), SC),
}


def assign(obj, act):
    obj.animation_data.action = act
    if act is not None and hasattr(obj.animation_data, "action_slot") and len(act.slots):
        obj.animation_data.action_slot = act.slots[0]


def rest_grip(arm, side):
    """(origin, f, t, n) of the fist in armature space at rest (life_common / life_props.gd contract)"""
    b = arm.data.bones
    hand = b["hand_" + side].head_local
    f = (b["middle_01_" + side].head_local - hand).normalized()
    t = b["index_01_" + side].head_local - b["pinky_01_" + side].head_local
    t = (t - f * t.dot(f)).normalized()
    n = t.cross(f) if side == "r" else f.cross(t)
    k = (b["middle_01_" + side].head_local - hand).length
    g = hand + f * (k * 0.68) + n * (k * 0.30)
    return g, f, t, n


def frame_matrix(g, f, t, n, grip_axis, front_axis):
    """world matrix that maps the prop's native grip_axis -> t and front_axis -> f, origin -> g"""
    ga = Vector(grip_axis).normalized()
    fa = Vector(front_axis).normalized()
    na = ga.cross(fa)
    src = Matrix((ga, fa, na)).transposed()        # columns = native axes
    tn = t.cross(f)
    dst = Matrix((t, f, tn)).transposed()
    R = dst @ src.inverted()
    M = R.to_4x4()
    M.translation = g
    return M


def import_prop(pid):
    e = PROPS.get(pid)
    if e is None:
        return None, None
    path = os.path.join(KING, e["file"].replace("res://", ""))
    if not os.path.exists(path):
        return None, e
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects if o not in before]
    root = bpy.data.objects.new("prop_" + pid, None)
    scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    return root, e


def stick(pid):
    root = bpy.data.objects.new("stick_" + pid, None)
    scene.collection.objects.link(root)
    # native +Z = grip axis (orange, 0.9 m, a little behind the fist too), native -Y = knuckles (blue)
    for nm, sx, sy, sz, loc, m in (("s", 0.025, 0.025, 1.2, (0, 0, 0.3), STICK), ("k", 0.02, 0.12, 0.02, (0, -0.06, 0), KNUCK)):
        o = box(nm + pid, sx, sy, sz, loc, m)
        o.parent = root
    return root, {"grip_axis": [0, 0, 1], "front_axis": [0, -1, 0]}


def attach(arm, pid, side):
    root, e = import_prop(pid)
    if root is None:
        root, e2 = stick(pid)
        e = e2 if e is None or True else e
        ga, fa = e["grip_axis"], e["front_axis"]
    else:
        ga, fa = e["grip_axis"], e["front_axis"]
    g, f, t, n = rest_grip(arm, side)
    M = frame_matrix(g, f, t, n, ga, fa)
    # parent to the hand bone at rest
    root.parent = arm
    root.parent_type = "BONE"
    root.parent_bone = "hand_" + side
    bpy.context.view_layer.update()
    bone = arm.data.bones["hand_" + side]
    # bone-parent space: child world = arm.matrix_world @ bone.matrix_local @ Translation(0, length, 0) @ basis
    P = arm.matrix_world @ bone.matrix_local @ Matrix.Translation((0, bone.length, 0))
    root.matrix_parent_inverse = Matrix.Identity(4)
    root.matrix_basis = P.inverted() @ M
    return root


def rest_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)


os.makedirs(OUT, exist_ok=True)
ffmpeg = shutil.which("ffmpeg") or "ffmpeg"
temp = []
for name, act in actions.items():
    clip = name[:-5] if name.endswith("_Loop") else name
    if ONLY and clip not in ONLY and name not in ONLY:
        continue
    for o in temp:
        bpy.data.objects.remove(o, do_unlink=True)
    temp = []
    info = SIDE["clips"].get(clip, {})
    rest_pose(ual_arm)
    assign(ual_arm, None)
    bpy.context.view_layer.update()
    for p in info.get("props", []):
        r = attach(ual_arm, p["id"], p.get("hand", "r"))
        temp.append(r)
        temp.extend(r.children_recursive)
    an = info.get("anchor")
    if an and an.get("at"):
        at = an["at"]
        sz = an.get("size", [0.5, 0.4, max(0.05, at[2])])
        # character frame (+x left, +y forward) -> Blender world (+x left, -y forward)
        temp.append(box("anchor", sz[0], sz[1], sz[2], (at[0], -at[1], at[2] - sz[2] * 0.5), ANCH))
    pr = info.get("pair")
    if pr and pr.get("partner") in [a[:-5] if a.endswith("_Loop") else a for a in actions]:
        if partner_arm is None:
            partner_arm = import_ual()
            clear_nla(partner_arm)
        pa = actions.get(pr["partner"]) or actions.get(pr["partner"] + "_Loop")
        partner_arm.hide_render = False
        for c in partner_arm.children:
            c.hide_render = False
        partner_arm.location = (0, -pr.get("distance", 1.0), 0)
        partner_arm.rotation_mode = "XYZ"
        partner_arm.rotation_euler = (0, 0, math.pi)
        rest_pose(partner_arm)
        assign(partner_arm, pa)
    elif partner_arm is not None:
        partner_arm.hide_render = True
        for c in partner_arm.children:
            c.hide_render = True
    assign(ual_arm, act)
    f0, f1 = act.frame_range
    scene.frame_start, scene.frame_end = int(f0), int(f1)
    scene.frame_step = STEP
    base = os.path.join(OUT, clip)
    st = {"frames": []}
    pbs = ual_arm.pose.bones
    for f in range(int(f0), int(f1) + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        row = {}
        for n in ("hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r", "Head", "pelvis"):
            row[n] = [round(x, 4) for x in pbs[n].head]
        for o in temp:
            if o.name.startswith(("prop_", "stick_")):
                row[o.name] = [round(x, 4) for x in o.matrix_world.translation]
        st["frames"].append(row)
    json.dump(st, open(os.path.join(OUT, clip + ".stats.json"), "w"))
    for v in VIEWS:
        d = os.path.join(base, "_" + v)
        os.makedirs(d, exist_ok=True)
        scene.camera = CAMS[v]
        scene.render.filepath = os.path.join(d, "f")
        bpy.ops.render.render(animation=True)
    comb = os.path.join(base, "frames")
    os.makedirs(comb, exist_ok=True)
    if STEP > 1:
        for v in VIEWS:
            names = sorted(os.listdir(os.path.join(base, "_" + v)))
            for i, nm in enumerate(names):
                os.rename(os.path.join(base, "_" + v, nm), os.path.join(base, "_" + v, "t%04d.png" % i))
            for i in range(len(names)):
                os.rename(os.path.join(base, "_" + v, "t%04d.png" % i), os.path.join(base, "_" + v, "f%04d.png" % i))
    first = int(f0) if STEP == 1 else 0
    cmd = [ffmpeg, "-v", "error", "-y"]
    for v in VIEWS:
        cmd += ["-start_number", str(first), "-i", os.path.join(base, "_" + v, "f%04d.png")]
    if len(VIEWS) > 1:
        cmd += ["-filter_complex", "hstack=inputs=%d" % len(VIEWS)]
    cmd += ["-start_number", "0", os.path.join(comb, "frame%08d.png")]
    subprocess.run(cmd, check=False)
    for v in VIEWS:
        shutil.rmtree(os.path.join(base, "_" + v), ignore_errors=True)
    print("RENDERED", clip, int(f1 - f0) + 1)
