# Author the elemental casting clips (Cast_<Element>_Charge / Cast_<Element>_Release) directly on the
# Quaternius UAL skeleton with Blender IK, then bake to plain FK quaternion keys (same recipe as
# ../free2/author_traversal.py).  Pose data lives in casting_clips.py (key poses per clip); this file is the
# rig / interpolation / bake / export framework.
#
#   blender -b -P author_casting_elements.py -- <out.glb> [clip,clip,...]
#   then:  python ../glb_reduce_anim.py <out.glb>
#
# Coordinates: armature space == world. The character faces -Y, +Z is up, +X is the character's LEFT.
# Standing pelvis head = (0, 0.05, 0.917); standing ankles = (+-0.089, 0.036, 0.104).
import bpy, sys, math, json, os
from mathutils import Vector, Quaternion, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1].split(",") if len(argv) > 1 else None
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
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
    scene.frame_set(int(f1) + 7)      # force a re-evaluation (the same frame number would keep the previous action's pose)
    bpy.context.view_layer.update()
    scene.frame_set(int(round(f0 + (f1 - f0) * frac)))
    bpy.context.view_layer.update()
    return {n: tgt.pose.bones[n].rotation_quaternion.copy() for n in FINGERS}
FIST = sample_fingers("Punch_Jab", 0.4)
OPEN = sample_fingers("A_TPose", 0.0)     # UAL hands are loose fists in almost every clip; A_TPose has the flat open hand
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
PELVIS0 = Vector((0, 0.05, 0.917))
SHOULDER0 = {"l": Vector((0.192, 0.065, 1.441)), "r": Vector((-0.192, 0.065, 1.441))}

def V(x, y, z):
    return Vector((x, y, z))

# ------------------------------------------------------------------ IK rig
def empty(name):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    return e
T = {k: empty("T_" + k) for k in ("hand_l", "hand_r", "foot_l", "foot_r", "elbow_l", "elbow_r", "knee_l", "knee_r")}

def add_ik(bone, target, pole):
    c = tgt.pose.bones[bone].constraints.new("IK")
    c.target = target
    c.pole_target = pole
    c.pole_angle = 0
    c.chain_count = 2
    c.use_tail = True
    c.use_stretch = False
    return c
IKC = {
    "hand_l": add_ik("lowerarm_l", T["hand_l"], T["elbow_l"]),
    "hand_r": add_ik("lowerarm_r", T["hand_r"], T["elbow_r"]),
    "foot_l": add_ik("calf_l", T["foot_l"], T["knee_l"]),
    "foot_r": add_ik("calf_r", T["foot_r"], T["knee_r"]),
}

def wq(axis, deg):
    return Quaternion(Vector(axis).normalized(), math.radians(deg))

def frame_q(f, n):
    """rotation whose columns are the orthonormal frame built from finger axis f and palm normal n"""
    f = Vector(f).normalized()
    n = Vector(n)
    n = (n - f * n.dot(f))
    if n.length < 1e-6:
        n = Vector((0, 0, 1)) if abs(f.z) < 0.9 else Vector((1, 0, 0))
        n = n - f * n.dot(f)
    n.normalize()
    t = n.cross(f)
    return Matrix(((f.x, t.x, n.x), (f.y, t.y, n.y), (f.z, t.z, n.z))).to_quaternion()

def hand_q(side, fdir, pdir):
    """rotation (relative to the T-pose rest hand: fingers along +-X, palm down, thumb forward) that points the fingers
    along fdir with the palm facing pdir; both are world vectors"""
    sx = 1 if side == "l" else -1
    q0 = frame_q((sx, 0, 0), (0, 0, -1))
    return frame_q(fdir, pdir) @ q0.inverted()

class Pose:
    def __init__(self):
        self.pelvis = PELVIS0.copy()
        self.hip = (0, 0, 0)        # pelvis pitch, yaw, roll (deg)
        self.tor = (0, 0, 0)        # spine chain total pitch (fwd +), yaw (left +), roll (left +)
        self.head = (0, 0, 0)       # neck + head
        self.hand = {}              # side -> wrist world position
        self.elb = {}               # side -> elbow hint (world) or None
        self.hq = {}                # side -> hand rotation (relative to rest)
        self.curl = {"l": 0.0, "r": 0.0}
        self.foot = {}              # side -> ankle world position
        self.fyaw = {"l": 0.0, "r": 0.0}
        self.fpit = {"l": 0.0, "r": 0.0}   # toe-up positive
        self.knee = {}
        self.shrug = {"l": None, "r": None}

def _rxyz(pitch, yaw, roll, w=1.0):
    return wq((0, 0, 1), yaw * w) @ wq((0, 1, 0), roll * w) @ wq((1, 0, 0), pitch * w)

SPINE_W = {"spine_01": 0.30, "spine_02": 0.35, "spine_03": 0.35}
def torso_rots(P):
    rots = {}
    rots["pelvis"] = _rxyz(*P.hip)
    for n, w in SPINE_W.items():
        rots[n] = _rxyz(*P.tor, w=w)
    rots["neck_01"] = _rxyz(*P.head, w=0.4)
    rots["Head"] = _rxyz(*P.head, w=0.6)
    return rots

def auto_elbow(P, side):
    sx = 1 if side == "l" else -1
    s = SHOULDER0[side] + (P.pelvis - PELVIS0)
    h = P.hand[side]
    mid = (s + h) * 0.5
    return mid + V(sx * 0.35, 0.25, -0.30)

def auto_knee(P, side):
    sx = 1 if side == "l" else -1
    f = P.foot[side]
    yaw = math.radians(P.fyaw[side])
    fwd = V(-math.sin(yaw), -math.cos(yaw), 0)   # foot forward direction (yaw + = turn left)
    return f + fwd * 0.75 + V(sx * 0.10, 0, 0.55)

def apply_pose(P):
    for side in ("l", "r"):
        T["hand_" + side].location = P.hand[side]
        T["elbow_" + side].location = P.elb.get(side) if P.elb.get(side) is not None else auto_elbow(P, side)
        T["foot_" + side].location = P.foot[side]
        T["knee_" + side].location = P.knee.get(side) if P.knee.get(side) is not None else auto_knee(P, side)
    rp = tgt.pose.bones["root"]
    rp.location = (0, 0, 0)
    pp = tgt.pose.bones["pelvis"]
    pp.location = Linv["pelvis"].to_3x3() @ (P.pelvis - L["pelvis"].translation)
    for n, q in torso_rots(P).items():
        pb = tgt.pose.bones[n]
        pb.rotation_quaternion = REST_Q[n].inverted() @ q @ REST_Q[n]
    # shoulder shrug: raise the clavicle when the hand is above shoulder level
    for side in ("l", "r"):
        sx = 1 if side == "l" else -1
        s = SHOULDER0[side] + (P.pelvis - PELVIS0)
        lift = P.shrug[side]
        if lift is None:
            lift = max(0.0, min(1.0, (P.hand[side].z - s.z) / 0.45)) * 14.0
        q = wq((0, 1, 0), -sx * lift)
        pb = tgt.pose.bones["clavicle_" + side]
        pb.rotation_quaternion = REST_Q["clavicle_" + side].inverted() @ q @ REST_Q["clavicle_" + side]
    bpy.context.view_layer.update()

def pole_calibrate():
    P = Pose()
    P.hand = {"l": V(0.3, -0.5, 1.3), "r": V(-0.3, -0.5, 1.3)}
    P.foot = {"l": V(0.1, -0.2, 0.104), "r": V(-0.1, -0.2, 0.104)}
    P.pelvis = PELVIS0 + V(0, 0, -0.15)
    P.elb = {"l": V(0.6, 0.3, 1.1), "r": V(-0.6, 0.3, 1.1)}
    joint = {"hand_l": "lowerarm_l", "hand_r": "lowerarm_r", "foot_l": "calf_l", "foot_r": "calf_r"}
    pole = {"hand_l": "elbow_l", "hand_r": "elbow_r", "foot_l": "knee_l", "foot_r": "knee_r"}
    for k, c in IKC.items():
        best = None
        for ang in (0, 90, 180, -90):
            c.pole_angle = math.radians(ang)
            apply_pose(P)
            j = tgt.pose.bones[joint[k]].head
            d = (j - T[pole[k]].location).length
            if best is None or d < best[0]:
                best = (d, ang)
        c.pole_angle = math.radians(best[1])
        print("POLE", k, best)

REACH_LOG = []
def bake(name, poses):
    """Solve every frame first (no action assigned), then key plain FK quaternions."""
    pbs = tgt.pose.bones
    assign(tgt, None)
    for pb in pbs:      # start every clip from the rest pose so the IK solve does not depend on the previous clip
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    frames = []
    worst = {"arm": 0.0, "leg": 0.0}
    for i, P in enumerate(poses):
        apply_pose(P)
        final = {}
        fin = {}
        for side in ("l", "r"):
            e = (pbs["lowerarm_" + side].tail - P.hand[side]).length
            worst["arm"] = max(worst["arm"], e)
            if e > 0.02:
                REACH_LOG.append((name, i, "arm_" + side, round(e, 3)))
            e = (pbs["calf_" + side].tail - P.foot[side]).length
            worst["leg"] = max(worst["leg"], e)
            if e > 0.02:
                REACH_LOG.append((name, i, "leg_" + side, round(e, 3)))
        delta = {}
        for n in ORDER:
            pb = pbs[n]
            M0 = pb.matrix.copy()
            M = M0
            b = pb.bone
            for side in ("l", "r"):
                if n == "hand_" + side and side in P.hq:
                    R = P.hq[side]
                    M = Matrix.Translation(M0.translation) @ (R.to_matrix() @ L[n].to_3x3()).to_4x4()
                if n == "foot_" + side:
                    R = wq((0, 0, 1), P.fyaw[side]) @ wq((1, 0, 0), -P.fpit[side])
                    M = Matrix.Translation(M0.translation) @ (R.to_matrix() @ L[n].to_3x3()).to_4x4()
            if M is not M0:
                delta[n] = M @ M0.inverted()
            else:   # children of an overridden hand / foot (fingers, toes) follow it
                anc = b.parent
                while anc is not None and anc.name not in delta:
                    anc = anc.parent
                if anc is not None:
                    M = delta[anc.name] @ M0
            final[n] = M
            if b.parent is None:
                basis = b.convert_local_to_pose(M, b.matrix_local, invert=True)
            else:
                basis = b.convert_local_to_pose(M, b.matrix_local, parent_matrix=final[b.parent.name],
                                                parent_matrix_local=b.parent.matrix_local, invert=True)
            fin[n] = basis
        frames.append((fin, P))
    print("REACH", name, {k: round(v, 3) for k, v in worst.items()})
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
            c = P.curl[side]
            for n in FINGERS:
                if n.endswith("_" + side):
                    q = OPEN[n].slerp(FIST[n], 0.5 + 0.5 * max(-1.0, min(1.0, c)))   # curl -1 = flat open hand, 0 = relaxed half curl, +1 = fist
                    pbs[n].rotation_quaternion = q
                    pbs[n].keyframe_insert("rotation_quaternion", frame=f)
    assign(tgt, None)
    for c in IKC.values():
        c.mute = False
    return act

# ------------------------------------------------------------------ key-pose interpolation
def _ease(kind, t):
    t = max(0.0, min(1.0, t))
    if kind == "lin":
        return t
    if kind == "in":
        return t * t * t
    if kind == "in2":
        return t * t
    if kind == "out":
        return 1 - (1 - t) ** 3
    if kind == "out2":
        return 1 - (1 - t) ** 2
    if kind == "hold":
        return 0.0 if t < 1.0 else 1.0
    return t * t * (3 - 2 * t)   # smooth

def default_state():
    return {
        "pel": V(0, 0, 0), "hip": (0.0, 0.0, 0.0), "tor": (0.0, 0.0, 0.0), "head": (0.0, 0.0, 0.0),
        "hand_l": V(0.30, 0.05, 0.85), "hand_r": V(-0.30, 0.05, 0.85),
        "elb_l": None, "elb_r": None,
        "ho_l": ((0, 0, -1), (-1, 0, 0)), "ho_r": ((0, 0, -1), (1, 0, 0)),
        "curl_l": 0.15, "curl_r": 0.15,
        "foot_l": V(0.089, 0.036, 0.104), "foot_r": V(-0.089, 0.036, 0.104),
        "fyaw_l": 0.0, "fyaw_r": 0.0, "fpit_l": 0.0, "fpit_r": 0.0,
        "shrug_l": None, "shrug_r": None,
    }

VEC_KEYS = ("pel", "hand_l", "hand_r", "foot_l", "foot_r")
TUP_KEYS = ("hip", "tor", "head")
SCAL_KEYS = ("curl_l", "curl_r", "fyaw_l", "fyaw_r", "fpit_l", "fpit_r")
OPT_KEYS = ("elb_l", "elb_r", "shrug_l", "shrug_r")

def _lerp(a, b, t):
    return a + (b - a) * t

def interp_state(a, b, t):
    s = {}
    for k in VEC_KEYS:
        s[k] = Vector(a[k]).lerp(Vector(b[k]), t)
    for k in TUP_KEYS:
        s[k] = tuple(_lerp(x, y, t) for x, y in zip(a[k], b[k]))
    for k in SCAL_KEYS:
        s[k] = _lerp(a[k], b[k], t)
    for k in OPT_KEYS:
        if a[k] is None and b[k] is None:
            s[k] = None
        elif a[k] is None:
            s[k] = b[k]
        elif b[k] is None:
            s[k] = a[k]
        elif k.startswith("elb"):
            s[k] = Vector(a[k]).lerp(Vector(b[k]), t)
        else:
            s[k] = _lerp(a[k], b[k], t)
    for side in ("l", "r"):
        qa = hand_q(side, *a["ho_" + side])
        qb = hand_q(side, *b["ho_" + side])
        s["hq_" + side] = qa.slerp(qb, t)
    return s

def build(keys, n, post=None):
    """keys: list of (frame, dict of changes[, ease]); values persist until changed. Returns n+1 Poses (frame 0..n).
    `ease` describes the segment ARRIVING at this key. post(fr, n, state) may add procedural layers."""
    st = default_state()
    ks = []
    for item in keys:
        f, d = item[0], item[1]
        ease = item[2] if len(item) > 2 else "smooth"
        st = dict(st)
        for k, v in d.items():
            st[k] = Vector(v) if k in VEC_KEYS else v
        ks.append((f, st, ease))
    poses = []
    for fr in range(n + 1):
        if fr <= ks[0][0]:
            s = interp_state(ks[0][1], ks[0][1], 0)
        elif fr >= ks[-1][0]:
            s = interp_state(ks[-1][1], ks[-1][1], 0)
        else:
            for i in range(len(ks) - 1):
                if ks[i][0] <= fr <= ks[i + 1][0]:
                    f0, s0, _ = ks[i]
                    f1, s1, e1 = ks[i + 1]
                    t = _ease(e1, (fr - f0) / float(f1 - f0))
                    s = interp_state(s0, s1, t)
                    break
        s["_fr"] = fr
        if post:
            post(fr, n, s)
        poses.append(state_to_pose(s))
    return poses

def state_to_pose(s):
    P = Pose()
    P.pelvis = PELVIS0 + s["pel"]
    P.hip, P.tor, P.head = s["hip"], s["tor"], s["head"]
    for side in ("l", "r"):
        P.hand[side] = Vector(s["hand_" + side])
        e = s["elb_" + side]
        P.elb[side] = Vector(e) if e is not None else None
        P.hq[side] = s["hq_" + side]
        P.curl[side] = s["curl_" + side]
        P.foot[side] = Vector(s["foot_" + side])
        P.fyaw[side] = s["fyaw_" + side]
        P.fpit[side] = s["fpit_" + side]
        P.shrug[side] = s["shrug_" + side]
    return P

def hand_o(side, fdir, pdir):
    return (tuple(fdir), tuple(pdir))

def orient(side, fdir, pdir):
    """key value for ho_<side>: fingers along fdir, palm facing pdir (world vectors)"""
    return (tuple(fdir), tuple(pdir))

# ------------------------------------------------------------------ main
if __name__ == "__main__":
    import casting_clips as CC
    CC.init(globals())
    pole_calibrate()
    report = []
    made = []
    for name, spec in CC.CLIPS.items():
        if ONLY and name not in ONLY:
            continue
        poses = spec["poses"]()
        act = bake(name, poses)
        made.append((name, spec["loop"], act))
        report.append({"name": name, "loop": spec["loop"], "frames": len(poses), "seconds": round((len(poses) - 1) / FPS, 3),
                       "release_frame": spec.get("release"), "note": spec.get("note", "")})
        print("CLIP", name, len(poses))
    grp = {}
    for (cn, fi, lim, e) in REACH_LOG:
        g = grp.setdefault((cn, lim), [fi, fi, e])
        g[1] = fi; g[2] = max(g[2], e)
    for (cn, lim), (a, b, e) in grp.items():
        print("REACHWARN", cn, lim, "frames", a, "-", b, "max err", e)
    assign(tgt, None)
    for k, e in T.items():
        bpy.data.objects.remove(e)
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
    for name, loop, a in made:
        tr = tgt.animation_data.nla_tracks.new(); tr.name = name + ("_Loop" if loop else "")
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
