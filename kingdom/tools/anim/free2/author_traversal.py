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

def clamp01(x):
    return max(0.0, min(1.0, x))

def limb_track(u, ph, base, rise, y_contact, y_swing_out):
    """world z,y of a hand/foot on a ladder-like structure: stationary in the world while in contact
    (first half of its cycle), then swung up by `rise` to the next hold."""
    k = math.floor(u + ph)
    s = cyc(u + ph)
    z = base + rise * k
    y = y_contact
    if s >= 0.5:
        w = (s - 0.5) / 0.5
        z += rise * smooth(w)
        y = y_contact - y_swing_out * math.sin(math.pi * w)
    return z, y

def climb(n, rise, hx=0.21, fx=0.11, yh=-0.30, yf=-0.22, sway=0.0, hand_base=1.45, foot_base=0.30):
    """ladder / wall climbing cycle. Stationary hands and feet in world space; root Z carries the climb."""
    poses = []
    for i in range(n + 1):
        u = i / n
        P = Pose()
        P.root = V(0, 0, rise * u)
        P.pelvis = V(sway * math.sin(2 * math.pi * u), 0.03, 0.80 + 0.015 * math.sin(4 * math.pi * u)) + P.root
        for side, sx, ph in (("l", 1, 0.0), ("r", -1, 0.5)):
            hz, hy = limb_track(u, ph, hand_base, rise, yh, 0.05)
            P.t["hand_" + side] = V(sx * hx, hy, hz)
            P.t["elbow_" + side] = V(sx * (hx + 0.30), 0.10, hz - 0.30)
            fz, fy = limb_track(u, ph + 0.5, foot_base, rise, yf, 0.12)
            P.t["foot_" + side] = V(sx * fx, fy + 0.08, fz)
            P.t["knee_" + side] = V(sx * (fx + 0.05), -0.75, fz + 0.30)
            P.rot["hand_" + side] = wq((1, 0, 0), -35)
            P.rot["foot_" + side] = wq((1, 0, 0), -35)
        P.rot["spine_02"] = wq((1, 0, 0), -5)
        P.rot["spine_03"] = wq((1, 0, 0), -5)
        P.rot["Head"] = wq((1, 0, 0), 20)
        poses.append(P)
    return poses

def reverse_shift(poses, dz):
    """play a climb backwards (descending); world positions shifted so the clip starts at root 0"""
    out = poses[::-1]
    off = V(0, 0, dz)
    for P in out:
        P.root = P.root + off
        P.pelvis = P.pelvis + off
        for k in P.t:
            P.t[k] = P.t[k] + off
    return out

@clip
def Ladder_Climb_Up():
    return climb(36, 0.6), True

@clip
def Ladder_Climb_Down():
    return reverse_shift(climb(36, 0.6), -0.6), True

@clip
def Wall_Climb_Up():
    return climb(42, 0.5, hx=0.30, fx=0.22, yh=-0.28, yf=-0.18, sway=0.05, hand_base=1.75, foot_base=0.55), True

def hang_pose(t, sway_amp=0.03):
    P = Pose()
    sw = math.sin(2 * math.pi * t)
    P.pelvis = V(0, sway_amp * sw, 0.90)
    for side, sx in (("l", 1), ("r", -1)):
        P.t["hand_" + side] = V(sx * 0.22, -0.24, 2.12)
        P.t["elbow_" + side] = V(sx * 0.42, 0.20, 1.75)
        P.t["foot_" + side] = V(sx * 0.10, 0.06 + 0.10 * sw * (1 if side == "l" else -1), 0.16 + 0.03 * abs(sw))
        P.t["knee_" + side] = V(sx * 0.12, -0.8, 0.5)
        P.rot["hand_" + side] = wq((1, 0, 0), -80)
        P.rot["foot_" + side] = wq((1, 0, 0), 25)
    P.rot["spine_02"] = wq((1, 0, 0), 4)
    P.rot["Head"] = wq((1, 0, 0), 15)
    return P

@clip
def Ledge_Hang_Idle():
    n = 60
    return [hang_pose(i / n) for i in range(n + 1)], True

def shimmy(direction):
    n = 30
    dist = 0.5 * direction
    poses = []
    for i in range(n + 1):
        u = i / n
        P = hang_pose(u * 2, 0.02)
        P.root = V(dist * u, 0, 0)
        P.pelvis = P.pelvis + P.root
        for side, sx, ph in (("l", 1, 0.0), ("r", -1, 0.5)):
            k = math.floor(u + ph)
            s = cyc(u + ph)
            x = sx * 0.22 + dist * k
            z = 2.12
            if s >= 0.5:
                w = (s - 0.5) / 0.5
                x += dist * smooth(w)
                z += 0.03 * math.sin(math.pi * w)
            P.t["hand_" + side] = V(x, -0.24, z)
            P.t["elbow_" + side] = V(x + 0.2 * sx, 0.20, 1.75)
            P.t["foot_" + side] = P.t["foot_" + side] + P.root
            P.t["knee_" + side] = P.t["knee_" + side] + P.root
        poses.append(P)
    return poses

@clip
def Ledge_Shimmy_L():
    return shimmy(1), True

@clip
def Ledge_Shimmy_R():
    return shimmy(-1), True

def ride_pose(t, bob, pitch_amp, lean=0.0, fwd=0.0, stand=0.0):
    """t in cycles. Seated on a saddle at z=1.0 (horse faces -Y like the rider); stirrups at z=0.55."""
    P = Pose()
    b = bob * math.sin(2 * math.pi * t * 2)
    pitch = pitch_amp * math.sin(2 * math.pi * t)
    P.pelvis = V(0, 0.02 - 0.03 * fwd, 1.20 + b + 0.10 * stand)
    for side, sx in (("l", 1), ("r", -1)):
        P.t["foot_" + side] = V(sx * 0.40, -0.16, 0.70 + 0.05 * stand)
        P.t["knee_" + side] = V(sx * 0.55, -0.60, 0.95)
        P.t["hand_" + side] = V(sx * 0.16, -0.62 - 0.10 * fwd, 1.28 + 0.03 * b + 0.05 * fwd)
        P.t["elbow_" + side] = V(sx * 0.40, -0.10, 1.05)
        P.rot["hand_" + side] = wq((1, 0, 0), -20)
        P.rot["foot_" + side] = wq((1, 0, 0), 20)
    lean_a = 25 * fwd + pitch
    P.rot["spine_01"] = wq((1, 0, 0), -lean_a * 0.3) @ wq((0, 1, 0), lean * 0.3)
    P.rot["spine_02"] = wq((1, 0, 0), -lean_a * 0.3) @ wq((0, 1, 0), lean * 0.4)
    P.rot["spine_03"] = wq((1, 0, 0), -lean_a * 0.4) @ wq((0, 1, 0), lean * 0.3)
    P.rot["Head"] = wq((1, 0, 0), 12 * fwd)
    return P

@clip
def Ride_Idle():
    n = 60
    return [ride_pose(i / n, 0.004, 1.0) for i in range(n + 1)], True

@clip
def Ride_Walk():
    n = 36
    return [ride_pose(i / n, 0.012, 2.5) for i in range(n + 1)], True

@clip
def Ride_Trot():
    n = 20
    return [ride_pose(i / n, 0.035, 3.0, fwd=0.2) for i in range(n + 1)], True

@clip
def Ride_Gallop():
    n = 16
    return [ride_pose(i / n, 0.03, 4.0, fwd=1.0, stand=1.0) for i in range(n + 1)], True

@clip
def Ride_Lean_L():
    return [ride_pose(0, 0.0, 0.0, lean=14) for i in range(2)], True

@clip
def Ride_Lean_R():
    return [ride_pose(0, 0.0, 0.0, lean=-14) for i in range(2)], True

@clip
def Vault_Low():
    """Side vault over a 0.9 m obstacle (box top at z=0.92, y from -0.9 to -1.4): run-up, hands on the top,
    legs swing over to the character's left, land 2.7 m further on. Root Y carries the travel."""
    n = 42
    poses = []
    box_top = 0.92
    for i in range(n + 1):
        u = i / n
        P = Pose()
        ry = -2.7 * (u * u * (3 - 2 * u) * 0.35 + u * 0.65)
        P.root = V(0, ry, 0)
        arc = math.sin(math.pi * clamp01((u - 0.2) / 0.55))
        P.pelvis = V(0.10 * arc, ry, 0.90 + 0.42 * arc)
        for side, sx in (("l", 1), ("r", -1)):
            if u < 0.25:
                w = smooth(u / 0.25)
                hp = V(sx * 0.30, lerp(ry - 0.1, -1.05, w), lerp(1.1, box_top + 0.02, w))
            elif u < 0.6:
                hp = V(sx * 0.22, -1.05, box_top + 0.02)
            else:
                w = smooth((u - 0.6) / 0.25)
                hp = V(sx * 0.22, lerp(-1.05, ry - 0.25, w), lerp(box_top + 0.02, 0.95, w))
            P.t["hand_" + side] = hp
            P.t["elbow_" + side] = V(sx * 0.55, hp.y + 0.35, hp.z + 0.2)
            P.rot["hand_" + side] = wq((1, 0, 0), -60)
        for side, sx, lag in (("l", 1, 0.0), ("r", -1, 0.10)):
            ground_a = V(sx * 0.11, -0.25, 0.10)
            over = V(0.45, -1.10, 1.22)
            land = V(sx * 0.11 + 0.05, -2.05, 0.10)
            if u < 0.2 + lag:
                fp = ground_a
            elif u < 0.5 + lag * 0.5:
                w = smooth((u - 0.2 - lag) / (0.3 - lag * 0.5))
                a = ground_a.lerp(over, w)
                fp = V(a.x, a.y, a.z + 0.12 * math.sin(math.pi * w))
            elif u < 0.78:
                w = smooth((u - 0.5 - lag * 0.5) / (0.28 - lag * 0.5))
                fp = over.lerp(land, w) + V(0, 0, 0.10 * math.sin(math.pi * w))
            else:
                fp = land
            P.t["foot_" + side] = fp
            P.t["knee_" + side] = V(fp.x + 0.1, fp.y - 0.5, fp.z + 0.6)
            P.rot["foot_" + side] = wq((1, 0, 0), 15)
        P.rot["spine_02"] = wq((1, 0, 0), 15 * arc)
        P.rot["spine_03"] = wq((1, 0, 0), 15 * arc)
        P.rot["Head"] = wq((1, 0, 0), -10 * arc)
        poses.append(P)
    return poses, False

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
