# Stop-motion preview of the casting clips: Blender workbench, UAL mannequin, side + front orthographic views
# side by side, every frame at 30 fps (video_to_sheets.sh samples them).
#
#   blender -b -P render_preview.py -- <lib.glb> <out_dir> [clip,clip,...] [step=1]
#   -> <out_dir>/<clip>/frame00000000.png ...  (side | front hstacked by ffmpeg, if found on PATH)
#
# The mannequin comes from UAL1_Standard.glb; the actions come from <lib.glb>.  A 0.25 m floor grid makes foot
# sliding visible; the red line is the character's forward axis (-Y), the green one the left/right axis.
import bpy, sys, os, math, subprocess, shutil
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
LIB = os.path.abspath(argv[0])
OUT = os.path.abspath(argv[1])
ONLY = argv[2].split(",") if len(argv) > 2 and argv[2] else None
STEP = int(argv[3]) if len(argv) > 3 else 1
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))
W, H = 340, 420

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=UAL)
ual_arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
for o in [o for o in bpy.data.objects if o.name.startswith("Icosphere")]:
    bpy.data.objects.remove(o)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=LIB)
new_objs = [o for o in bpy.data.objects if o not in before]
for o in new_objs:
    bpy.data.objects.remove(o)
actions = {a.name: a for a in bpy.data.actions}
ual_arm.animation_data_create()
for tr in list(ual_arm.animation_data.nla_tracks):
    ual_arm.animation_data.nla_tracks.remove(tr)

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
sh.show_cavity = False
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
CAMS = {
    "side": make_cam("side", (-8, -0.15, 1.05), (0, -0.15, 1.05), 2.5),    # faces +X: character looks to the right
    "front": make_cam("front", (0, -8, 1.05), (0, 0, 1.05), 2.5),
}

def assign(obj, act):
    obj.animation_data.action = act
    if act is not None and hasattr(obj.animation_data, "action_slot") and len(act.slots):
        obj.animation_data.action_slot = act.slots[0]

os.makedirs(OUT, exist_ok=True)
ffmpeg = shutil.which("ffmpeg") or "ffmpeg"
CLOSE = os.environ.get("CLOSE")       # "cx,cy,cz,ortho_scale"  (close-up of one region) with FRAMES="12,17"
if CLOSE:
    cx, cy, cz, sc = [float(v) for v in CLOSE.split(",")]
    for k, cam in CAMS.items():
        cam.data.ortho_scale = sc
        if k == "side":
            cam.location = (-8, cy, cz)
        else:
            cam.location = (cx, -8, cz)
    scene.render.resolution_x = scene.render.resolution_y = 480
    for name, act in actions.items():
        clip = name[:-5] if name.endswith("_Loop") else name
        if ONLY and clip not in ONLY and name not in ONLY:
            continue
        assign(ual_arm, act)
        for fr in [int(v) for v in os.environ.get("FRAMES", "0").split(",")]:
            for v, cam in CAMS.items():
                scene.frame_set(fr)
                scene.camera = cam
                scene.render.filepath = os.path.join(OUT, "%s_f%d_%s.png" % (clip, fr, v))
                bpy.ops.render.render(write_still=True)
    sys.exit(0)
for name, act in actions.items():
    clip = name[:-5] if name.endswith("_Loop") else name
    if ONLY and clip not in ONLY and name not in ONLY:
        continue
    assign(ual_arm, act)
    f0, f1 = act.frame_range
    scene.frame_start, scene.frame_end = int(f0), int(f1)
    scene.frame_step = STEP
    base = os.path.join(OUT, clip)
    # ---- numbers: wrist / palm / foot world positions per frame
    import json
    st = {"frames": []}
    pbs = ual_arm.pose.bones
    for f in range(int(f0), int(f1) + 1):
        scene.frame_set(f)
        bpy.context.view_layer.update()
        row = {}
        for n in ("hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r", "Head", "pelvis"):
            row[n] = [round(x, 4) for x in pbs[n].head]
        for s in ("l", "r"):
            palm = (pbs["hand_" + s].head + pbs["middle_01_" + s].head) * 0.5
            row["palm_" + s] = [round(x, 4) for x in palm]
            row["tip_" + s] = [round(x, 4) for x in pbs["middle_04_leaf_" + s].tail]
        st["frames"].append(row)
    json.dump(st, open(os.path.join(OUT, clip + ".stats.json"), "w"))
    for v, cam in CAMS.items():
        d = os.path.join(base, "_" + v)
        os.makedirs(d, exist_ok=True)
        scene.camera = cam
        scene.render.filepath = os.path.join(d, "f")
        bpy.ops.render.render(animation=True)
    # combine (frames are named f0000.png ...)
    comb = os.path.join(base, "frames")
    os.makedirs(comb, exist_ok=True)
    fr = sorted(os.listdir(os.path.join(base, "_side")))
    first = int(fr[0][1:5])
    subprocess.run([ffmpeg, "-v", "error", "-y", "-start_number", str(first), "-i", os.path.join(base, "_side", "f%04d.png"),
                    "-start_number", str(first), "-i", os.path.join(base, "_front", "f%04d.png"),
                    "-filter_complex", "hstack", "-start_number", "0", os.path.join(comb, "frame%08d.png")], check=False)
    shutil.rmtree(os.path.join(base, "_side"), ignore_errors=True)
    shutil.rmtree(os.path.join(base, "_front"), ignore_errors=True)
    print("RENDERED", clip, len(fr))
