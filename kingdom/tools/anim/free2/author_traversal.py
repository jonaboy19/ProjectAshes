# Author traversal / riding clips directly on the Quaternius UAL skeleton with Blender IK.
#
# There is no free (CC0/commercial-OK) mocap for ladders, ledges, wall climbing, vaulting or horse
# riding, so these clips are hand-authored: hands/feet are world-space IK targets keyed on rungs,
# ledges and stirrups, the pelvis and the `root` bone travel is keyed directly (that travel is the
# root-motion track, same convention as ../../../assets/incoming/animations/README.md), and the
# result is baked to plain FK quaternion keys (no constraints in the exported GLB).
#
#   blender -b -P author_traversal.py -- <out.glb> [clip,clip,...]
# Character faces -Y, +Z up, +X is the character's left (UAL rest pose, T-pose arms).
import bpy, sys, math, json, os
from mathutils import Vector, Quaternion, Matrix, Euler

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1].split(",") if len(argv) > 1 else None
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
before_a = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=UAL)
tgt = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
ual_actions = {a.name: a for a in bpy.data.actions if a not in before_a}
tgt.animation_data_create()
for pb in tgt.pose.bones:
    pb.rotation_mode = "QUATERNION"
tb = tgt.data.bones
ORDER = []
def _walk(b):
    ORDER.append(b.name)
    for c in b.children:
        _walk(c)
for r in [b for b in tb if b.parent is None]:
    _walk(r)
FINGERS = [n for n in ORDER if any(n.startswith(k) for k in ("thumb", "index", "middle", "ring", "pinky"))]

def assign(obj, act):
    obj.animation_data.action = act
    if act is not None and hasattr(obj.animation_data, "action_slot") and len(act.slots):
        obj.animation_data.action_slot = act.slots[0]

def sample_fingers(clip, frac):
    act = ual_actions[clip]
    assign(tgt, act)
    f0, f1 = act.frame_range
    scene.frame_set(int(round(f0 + (f1 - f0) * frac)))
    return {n: tgt.pose.bones[n].rotation_quaternion.copy() for n in FINGERS}
FIST = sample_fingers("Punch_Jab", 0.4)
RELAX = sample_fingers("Idle_Loop", 0.0)
assign(tgt, None)
for tr in list(tgt.animation_data.nla_tracks):
    tgt.animation_data.nla_tracks.remove(tr)
for a in ual_actions.values():
    bpy.data.actions.remove(a)
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
    bpy.data.objects.remove(o)

L = {n: tb[n].matrix_local.copy() for n in ORDER}
Linv = {n: L[n].inverted() for n in ORDER}
REST_Q = {n: L[n].to_quaternion() for n in ORDER}

# ------------------------------------------------------------------ IK rig
def empty(name, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    e.location = loc
    return e

T = {k: empty("T_" + k) for k in ("hand_l", "hand_r", "foot_l", "foot_r", "elbow_l", "elbow_r", "knee_l", "knee_r")}

def add_ik(bone, target, pole, angle):
    c = tgt.pose.bones[bone].constraints.new("IK")
    c.target = target
    c.pole_target = pole
    c.pole_angle = math.radians(angle)
    c.chain_count = 2
    c.use_tail = True
    c.use_stretch = False
    return c
IKC = {
    "hand_l": add_ik("lowerarm_l", T["hand_l"], T["elbow_l"], 0),
    "hand_r": add_ik("lowerarm_r", T["hand_r"], T["elbow_r"], 180),
    "foot_l": add_ik("calf_l", T["foot_l"], T["knee_l"], 0),
    "foot_r": add_ik("calf_r", T["foot_r"], T["knee_r"], 0),
}

# ------------------------------------------------------------------ helpers
def lerp(a, b, t):
    return a + (b - a) * t
def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)
def V(x, y, z):
    return Vector((x, y, z))

def wq(axis, deg):
    """world-space rotation quaternion about an axis"""
    return Quaternion(Vector(axis).normalized(), math.radians(deg))

class Pose:
    """one frame: world positions of targets + pelvis and root, plus extra world rotations"""
    def __init__(self):
        self.t = {}            # target name -> Vector (world)
        self.pelvis = V(0, 0.05, 0.92)   # world position of the pelvis bone head
        self.root = V(0, 0, 0)           # world offset of the root bone
        self.rot = {}          # bone -> world rotation quaternion applied about its head (on top of the solved pose)
        self.fingers = {"hand_l": "fist", "hand_r": "fist"}

def apply_pose(P):
    for k, e in T.items():
        if k in P.t:
            e.location = P.t[k]
    # root translation (root bone local axes are the armature axes mapped through its rest matrix)
    rp = tgt.pose.bones["root"]
    rp.location = (L["root"].to_3x3().inverted() @ P.root)
    # pelvis: location is expressed in the pelvis rest frame, parent (root) shifted by P.root
    pp = tgt.pose.bones["pelvis"]
    pp.location = Linv["pelvis"].to_3x3() @ (P.pelvis - P.root - L["pelvis"].translation)
    for n, q in P.rot.items():
        if n in ("spine_01", "spine_02", "spine_03", "neck_01", "Head", "pelvis", "clavicle_l", "clavicle_r"):
            pb = tgt.pose.bones[n]
            pb.rotation_quaternion = REST_Q[n].inverted() @ q @ REST_Q[n]
    bpy.context.view_layer.update()

def pole_calibrate():
    """choose pole angles so the joint bends toward the pole target at a test pose"""
    P = Pose()
    P.t = {"hand_l": V(0.3, -0.5, 1.3), "hand_r": V(-0.3, -0.5, 1.3), "foot_l": V(0.1, -0.35, 0.5), "foot_r": V(-0.1, -0.35, 0.5),
           "elbow_l": V(0.6, 0.3, 1.2), "elbow_r": V(-0.6, 0.3, 1.2), "knee_l": V(0.1, -0.9, 0.7), "knee_r": V(-0.1, -0.9, 0.7)}
    joint = {"hand_l": "lowerarm_l", "hand_r": "lowerarm_r", "foot_l": "calf_l", "foot_r": "calf_r"}
    pole = {"hand_l": "elbow_l", "hand_r": "elbow_r", "foot_l": "knee_l", "foot_r": "knee_r"}
    for k, c in IKC.items():
        best = None
        for ang in (0, 90, 180, -90):
            c.pole_angle = math.radians(ang)
            apply_pose(P)
            j = (tgt.matrix_world @ tgt.pose.bones[joint[k]].head)
            d = (j - P.t[pole[k]]).length
            if best is None or d < best[0]:
                best = (d, ang)
        c.pole_angle = math.radians(best[1])
        print("POLE", k, best)

# ------------------------------------------------------------------ bake
def bake(name, poses, loop=False):
    """Solve every frame first (no action assigned, so nothing overrides the manual values), then key."""
    pbs = tgt.pose.bones
    assign(tgt, None)
    frames = []
    for i, P in enumerate(poses):
        apply_pose(P)
        final = {}
        fin = {}
        for n in ORDER:
            pb = pbs[n]
            M = pb.matrix.copy()
            b = pb.bone
            if n in P.rot and n in ("hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r"):
                head = M.translation.copy()
                M = Matrix.Translation(head) @ P.rot[n].to_matrix().to_4x4() @ Matrix.Translation(-head) @ M
            final[n] = M
            if b.parent is None:
                basis = b.convert_local_to_pose(M, b.matrix_local, invert=True)
            else:
                basis = b.convert_local_to_pose(M, b.matrix_local, parent_matrix=final[b.parent.name],
                                                parent_matrix_local=b.parent.matrix_local, invert=True)
            fin[n] = basis
        frames.append((fin, P))
    for c in IKC.values():
        c.mute = True
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    assign(tgt, act)
    for f, (fin, P) in enumerate(frames):
        for n in ORDER:
            pb = pbs[n]
            basis = fin[n]
            pb.rotation_quaternion = basis.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if n in ("root", "pelvis"):
                pb.location = basis.to_translation()
                pb.keyframe_insert("location", frame=f)
        for side in ("l", "r"):
            pose = FIST if P.fingers.get("hand_" + side) == "fist" else RELAX
            for n in FINGERS:
                if n.endswith("_" + side):
                    pbs[n].rotation_quaternion = pose[n]
                    pbs[n].keyframe_insert("rotation_quaternion", frame=f)
    assign(tgt, None)
    for c in IKC.values():
        c.mute = False
    return act

def clean_pose_after():
    for c in IKC.values():
        c.mute = True

# ------------------------------------------------------------------ clip definitions
CLIPS = {}
def clip(fn):
    CLIPS[fn.__name__] = fn
    return fn

def cyc(u):
    return u - math.floor(u)

def ladder(direction):
    """Ladder cycle. 1.2 s per full cycle, rungs every 0.3 m, two rungs (0.6 m) of travel per cycle.
    Hands and feet are stationary on the rungs (world space) during contact; the root bone carries the climb."""
    n = 36
    rise = 0.6 * direction
    poses = []
    for i in range(n + 1):
        u = i / n
        if direction < 0:
            u = 1 - u          # descend = reversed ascent, root offset handled below
        P = Pose()
        base_root = 0.6 * u
        P.root = V(0, 0, base_root if direction > 0 else 0.6 * (1 - i / n) * -1 + 0.6)
        P.root = V(0, 0, 0.6 * (i / n) * (1 if direction > 0 else -1))
        P.pelvis = V(0, -0.04, 0.88 + 0.015 * math.sin(4 * math.pi * u)) + P.root
        for side, sx, ph in (("l", 1, 0.0), ("r", -1, 0.5)):
            s_h = (u + ph) % 1.0
            k = math.floor(u + ph)
            hz = 1.80 + 0.6 * k
            hy = -0.27
            if s_h >= 0.5:
                w = (s_h - 0.5) / 0.5
                hz += 0.6 * smooth(w)
                hy -= 0.0
            P.t["hand_" + side] = V(sx * 0.21, hy, hz)
            P.t["elbow_" + side] = V(sx * 0.62, 0.30, hz - 0.5)
            s_f = (u + ph + 0.5) % 1.0
            kf = math.floor(u + ph + 0.5)
            fz = 0.40 + 0.6 * kf - 0.6
            fy = -0.15
            if s_f >= 0.5:
                w = (s_f - 0.5) / 0.5
                fz += 0.6 * smooth(w)
                fy += 0.12 * math.sin(math.pi * w)      # swing the foot back off the rungs
            P.t["foot_" + side] = V(sx * 0.11, fy, fz + 0.60 + 0.0 - 0.60 + 0.0)
            P.t["knee_" + side] = V(sx * 0.20, -0.95, fz + 0.55)
            P.rot["hand_" + side] = wq((1, 0, 0), -40)
            P.rot["foot_" + side] = wq((1, 0, 0), -35)
        P.rot["spine_02"] = wq((1, 0, 0), -5)
        P.rot["spine_03"] = wq((1, 0, 0), -5)
        P.rot["Head"] = wq((1, 0, 0), 18)
        poses.append(P)
    return poses

@clip
def Ladder_Climb_Up():
    return ladder(1), True

@clip
def Ladder_Climb_Down():
    return ladder(-1), True

if __name__ == "__main__":
    pole_calibrate()
    report = []
    made = []
    for name, fn in CLIPS.items():
        if ONLY and name not in ONLY:
            continue
        poses, loop = fn()
        act = bake(name, poses, loop)
        made.append((name, act))
        report.append({"name": name, "loop": loop, "frames": len(poses), "seconds": round((len(poses) - 1) / FPS, 2)})
        print("CLIP", name, len(poses))
    # export
    assign(tgt, None)
    for k, e in T.items():
        bpy.data.objects.remove(e)
    for c in IKC.values():
        pass
    for pb in tgt.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.rotation_quaternion = Quaternion(); pb.location = Vector()
    me = bpy.data.meshes.new("UAL_Skin_Stub")
    me.from_pydata([(0, 0, 0.9), (0.01, 0, 0.9), (0, 0.01, 0.9)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("UAL_Skin_Stub", me)
    scene.collection.objects.link(ob)
    ob.parent = tgt
    vg = ob.vertex_groups.new(name="pelvis"); vg.add([0, 1, 2], 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE"); mod.object = tgt
    tgt.name = "Armature"
    for name, a in made:
        tr = tgt.animation_data.nla_tracks.new(); tr.name = name + ("_Loop" if dict((r["name"], r["loop"]) for r in report)[name] else "")
        tr.strips.new(tr.name, 0, a)
    bpy.ops.object.select_all(action="DESELECT")
    tgt.select_set(True); ob.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=False,
                              export_optimize_animation_size=False, export_draco_mesh_compression_enable=False,
                              export_materials="NONE", export_apply=False, export_yup=True, export_def_bones=False,
                              export_anim_single_armature=True, export_reset_pose_bones=True)
    json.dump(report, open(OUT + ".clips.json", "w"), indent=1)
    print("EXPORTED", OUT, len(made))
