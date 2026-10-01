# Put the rider clips on the UAL mannequin riding the horse (Horse_LOD0 on the Horse_Anims.glb skeleton) exactly as the game does:
# the horse plays its clip, the rider armature is moved rigidly by the saddle delta (saddle bone pose * saddle rest^-1, world) and plays
# its clip at the same frame. Measures in WORLD space every frame: ball of the foot vs stirrup bone, palm centre vs rein_grip bone,
# rider capsules (thigh / calf / foot / pelvis / spine / arms) penetrating the evaluated horse mesh (BVH). Optionally renders Workbench
# frames (side view from the horse's left + 3/4 front-left view, camera follows the horse root).
#   blender -b --factory-startup -P render_rider.py -- <rider.glb> <out_dir> [--clips=A,B] [--metrics] [--render] [--every=N] [--size=300]
# --metrics merges the world checks into <rider.glb>.clips.json ("world": {...}); frames go to <out_dir>/<clip>/s_####.png, q_####.png.
import bpy, sys, os, json, math
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
GLB = os.path.abspath(argv[0])
OUT = os.path.abspath(argv[1])
opt = {}
for a in argv[2:]:
    if a.startswith("--"):
        k, _, v = a[2:].partition("=")
        opt[k] = v or "1"
ONLY = opt["clips"].split(",") if "clips" in opt else None
EVERY = int(opt.get("every", 1))
SIZE = int(opt.get("size", 300))
HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
UAL = os.path.join(KING, "assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb")
HGLB = os.path.join(KING, "assets/generated/horses/Horse_Anims.glb")
HBLEND = os.path.join(HERE, "..", "source", "horse_rig.blend")
HCLIPS = {c["name"]: c for c in json.load(open(HGLB + ".clips.json"))}
SIDE = json.load(open(GLB + ".clips.json"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30


def import_glb(path):
    before_o, before_a = set(bpy.data.objects), set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before_o], {a.name: a for a in bpy.data.actions if a not in before_a}


# ---- horse: Horse_Anims.glb skeleton + actions, Horse_LOD0 mesh (from the rig blend) deformed by it
hobjs, hacts = import_glb(HGLB)
harm = [o for o in hobjs if o.type == "ARMATURE"][0]
for o in hobjs:
    if o.type != "ARMATURE":
        bpy.data.objects.remove(o)
harm.name = "HorseArm"
with bpy.data.libraries.load(HBLEND, link=False) as (src, dst):
    dst.objects = ["Horse_LOD0"]
horse = dst.objects[0]
sc.collection.objects.link(horse)
mw = horse.matrix_world.copy()
horse.parent = None
horse.matrix_world = mw
for m in horse.modifiers:
    if m.type == "ARMATURE":
        m.object = harm
for o in list(bpy.data.objects):
    if o.name.startswith("HorseSkeleton"):
        bpy.data.objects.remove(o)
harm.animation_data_create()
for a in hacts.values():
    a.use_fake_user = True

# ---- rider: UAL mannequin + the rider clip actions
robjs, _ = import_glb(UAL)
rarm = [o for o in robjs if o.type == "ARMATURE"][0]
mann = [o for o in robjs if o.name.startswith("Mannequin")][0]
for o in robjs:
    if o not in (rarm, mann):
        bpy.data.objects.remove(o)
for a in [a for a in bpy.data.actions if a.name not in hacts]:
    bpy.data.actions.remove(a)
xobjs, racts = import_glb(GLB)
for o in xobjs:
    bpy.data.objects.remove(o)
for a in racts.values():
    a.use_fake_user = True
rarm.animation_data_create()


def assign(arm, act):
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
    arm.animation_data.action = act
    if act is not None and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]


def horse_action(name):
    if name is None:
        return None
    for k in (name + "_Loop", name):
        if k in hacts:
            return hacts[k]
    raise KeyError(name)


REST = {n: harm.data.bones[n].matrix_local.copy() for n in ("root", "saddle", "stirrup_L", "stirrup_R", "rein_grip_L", "rein_grip_R", "bit")}


def hbone(n):
    return harm.matrix_world @ harm.pose.bones[n].matrix


def saddle_delta():
    return hbone("saddle") @ REST["saddle"].inverted()


# ---- probes (rider capsules): thigh / calf / foot / pelvis / spine / upper arm radii of the mannequin
PROBE = [("thigh_l", "calf_l", 0.070), ("calf_l", "foot_l", 0.050), ("foot_l", "ball_l", 0.035),
         ("thigh_r", "calf_r", 0.070), ("calf_r", "foot_r", 0.050), ("foot_r", "ball_r", 0.035),
         ("pelvis", "spine_01", 0.10), ("spine_01", "spine_02", 0.11), ("spine_02", "spine_03", 0.12),
         ("upperarm_l", "lowerarm_l", 0.045), ("upperarm_r", "lowerarm_r", 0.045)]


def rb(n):
    return rarm.matrix_world @ rarm.pose.bones[n].head


def penetration(bvh):
    worst = (0.0, "")
    for a, b, r in PROBE:
        pa, pb_ = rb(a), rb(b)
        for i in range(6):
            p = pa.lerp(pb_, i / 5.0)
            loc, nrm, idx, d = bvh.find_nearest(p)
            if loc is None:
                continue
            inside = (p - loc).dot(nrm) < 0
            pen = (r + d) if (inside and d < 0.12) else (r - d)
            if pen > worst[0]:
                worst = (pen, a)
    return worst


def grip_point(s):
    M = rarm.matrix_world @ rarm.pose.bones["hand_" + s].matrix
    return M.translation + M.col[1].xyz.normalized() * 0.075


# ---- render setup
def mk_obj(name, verts, faces, color):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob); ob.color = color
    return ob


def box_v(x0, x1, y0, y1, z0, z1):
    v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return v, f


RENDER = "render" in opt
if RENDER:
    S = 60.0
    mk_obj("floor", [(-S, -S, 0), (S, -S, 0), (S, S, 0), (-S, S, 0)], [(0, 1, 2, 3)], (0.62, 0.72, 0.55, 1))
    v, f = [], []
    k = -S
    while k <= S:
        w = 0.012 if abs(k - round(k)) < 1e-6 else 0.006
        for (x0, y0, x1, y1) in ((k - w, -S, k + w, S), (-S, k - w, S, k + w)):
            i = len(v); v.extend([(x0, y0, 0.002), (x1, y0, 0.002), (x1, y1, 0.002), (x0, y1, 0.002)]); f.append((i, i + 1, i + 2, i + 3))
        k += 0.5
    mk_obj("lines", v, f, (0.16, 0.22, 0.14, 1))
    mann.color = (0.98, 0.78, 0.55, 1)
    horse.color = (0.55, 0.36, 0.22, 1)
    # saddle proxy (rigid with the saddle bone): seat top 1.561, flaps down the barrel; stirrup + rein markers
    v, f = box_v(-0.17, 0.17, -0.47, 0.02, 1.47, 1.561)
    saddle = mk_obj("saddle_proxy", v, f, (0.35, 0.18, 0.10, 1))
    v, f = box_v(-0.05, 0.05, -0.06, 0.06, -0.012, 0.0)
    stir = {s: mk_obj("stir_" + s, v, f, (0.2, 0.2, 0.25, 1)) for s in "LR"}
    v, f = box_v(-0.012, 0.012, -0.012, 0.012, -0.012, 0.012)
    grips = {s: mk_obj("grip_" + s, v, f, (0.9, 0.1, 0.1, 1)) for s in "LR"}
    reins = None
    sc.render.engine = "BLENDER_WORKBENCH"
    sh = sc.display.shading
    sh.light = "STUDIO"; sh.color_type = "OBJECT"; sh.show_shadows = True; sh.shadow_intensity = 0.5
    sh.show_object_outline = True; sh.object_outline_color = (0.05, 0.05, 0.05)
    sc.display.render_aa = "8"
    sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.66, 0.80, 0.95)
    sc.render.resolution_x, sc.render.resolution_y = SIZE, SIZE
    sc.render.image_settings.file_format = "PNG"

    def mk_cam(name, scale):
        cd = bpy.data.cameras.new(name); cd.type = "ORTHO"; cd.ortho_scale = scale; cd.clip_end = 200
        co = bpy.data.objects.new(name, cd); sc.collection.objects.link(co)
        return co
    camS, camQ = mk_cam("camS", float(opt.get("scale", 2.7))), mk_cam("camQ", float(opt.get("scale", 2.7)))


def place_cam(cam, target, offset):
    cam.location = target + offset
    cam.rotation_euler = (-offset).to_track_quat("-Z", "Y").to_euler()


def update_props(Sd):
    saddle.matrix_world = Sd
    for s in "LR":
        stir[s].matrix_world = hbone("stirrup_" + s)
        grips[s].matrix_world = Matrix.Translation(hbone("rein_grip_" + s).translation)
    if reins is None:
        return
    b = hbone("bit").translation
    me = reins.data
    for i, s in enumerate("LR"):
        g = hbone("rein_grip_" + s).translation
        bs = b + Vector((0.07 if s == "L" else -0.07, 0, 0))
        side = Vector((0, 0, 0.008))
        for j, p in enumerate((bs - side, g - side, g + side, bs + side)):
            me.vertices[i * 4 + j].co = p
    me.update()


metrics = {}
for e in SIDE:
    name = e["name"]
    if ONLY and name not in ONLY:
        continue
    hname = e.get("synced_to")
    assign(harm, horse_action(hname))
    assign(rarm, racts.get(e["glb_name"]))
    n = e["frames"]
    hn = HCLIPS[hname]["frames"] if hname in HCLIPS else None
    worst = {"stirrup": [0.0, 0], "grip": [0.0, 0], "pen": [0.0, 0, ""]}
    feet_on = e.get("feet_in_stirrups", False)
    hands_on = e.get("hands_on_grips", False)
    d = os.path.join(OUT, name)
    if RENDER:
        os.makedirs(d, exist_ok=True)
    for fi in range(n):
        sc.frame_set(fi)
        Sd = saddle_delta() if hname else Matrix.Identity(4)
        rarm.matrix_world = Sd
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        bvh = BVHTree.FromObject(horse.evaluated_get(dg), dg)
        pen = penetration(bvh)
        if pen[0] > worst["pen"][0]:
            worst["pen"] = [round(pen[0], 4), fi, pen[1]]

        def on(spec):
            if spec is True:
                return True
            if isinstance(spec, list):
                return any(a <= fi <= b for a, b in spec)
            if isinstance(spec, str) and "11-22" in spec:
                return fi >= 11
            return False
        if on(feet_on):
            for s in "lr":
                err = (rb("ball_" + s) - hbone("stirrup_" + s.upper()).translation).length
                if err > worst["stirrup"][0]:
                    worst["stirrup"] = [round(err, 4), fi]
        if on(hands_on) and hname:
            for s in "lr":
                err = (grip_point(s) - hbone("rein_grip_" + s.upper()).translation).length
                if err > worst["grip"][0]:
                    worst["grip"] = [round(err, 4), fi]
        if RENDER and fi % EVERY == 0:
            update_props(Sd)
            tgt = (Sd @ Vector((0, -0.24, 1.56))).copy()
            if "ground" in opt:
                tgt = hbone("root").translation + Vector((0.5, -0.2, 0.9))
            elif "close" in opt:
                tgt = tgt + Vector((0, -0.05, 0.42))
            else:
                tgt.z = tgt.z * 0.5 + 0.62
            place_cam(camS, tgt + Vector((0, -0.2, 0)), Vector((8.0, 0.0, 0.8)))
            place_cam(camQ, tgt + Vector((0, -0.2, 0.05)), Vector((5.5, -5.5, 2.6)))
            if "front" in opt:
                place_cam(camQ, tgt + Vector((0.6, 0, 0)), Vector((0.8, -8.0, 1.2)))
            for cam, pre in ((camS, "s"), (camQ, "q")):
                sc.camera = cam
                sc.render.filepath = os.path.join(d, "%s_%04d.png" % (pre, fi))
                bpy.ops.render.render(write_still=True)
    metrics[name] = {"stirrup_miss_max_m": worst["stirrup"] if feet_on else None, "grip_miss_max_m": worst["grip"] if (hands_on and hname) else None,
                     "penetration_max_m": worst["pen"], "horse_frames": hn}
    print("WORLD", name, json.dumps(metrics[name]), flush=True)

if "metrics" in opt:
    for e in SIDE:
        if e["name"] in metrics:
            e["world_check"] = metrics[e["name"]]
    json.dump(SIDE, open(GLB + ".clips.json", "w"), indent=1)
    print("MERGED", GLB + ".clips.json")
os.makedirs(OUT, exist_ok=True)
json.dump(metrics, open(os.path.join(OUT, "world_metrics.json"), "w"), indent=1)
