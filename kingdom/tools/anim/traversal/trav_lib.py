# Shared helpers for author_traversal_v2.py: keyframe tracks, hand/foot/pose helpers, bake + validation.
# Reuses the rig setup (UAL import, IK empties, pole calibration) of ../free2/author_traversal.py by importing it.
# Character faces -Y, +Z up, +X is the character's left. All world units are metres, 30 fps.
import os, sys, math, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "free2")))
import author_traversal as A          # runs the UAL import + IK rig, reads argv[0]=out.glb, argv[1]=clip filter
import bpy
from mathutils import Vector, Quaternion, Matrix

tgt, T, IKC, L, ORDER, FINGERS = A.tgt, A.T, A.IKC, A.L, A.ORDER, A.FINGERS
FIST, RELAX = A.FIST, A.RELAX
FPS = 30
V = A.V
rad = math.radians


# ------------------------------------------------------------------ keyframe tracks
def _d(a, b):
    return abs(a - b) if isinstance(a, (int, float)) else (a - b).length


class Trk:
    """Hermite track through keys (frame, value[, 's']) with Catmull-Rom tangents. A tangent is zero at a key flagged 's'
    or whose neighbour has the same value (so plants / holds stay exactly still). period=N makes it cyclic."""

    def __init__(self, keys, period=None):
        ks = [(k[0], k[1], len(k) > 2 and k[2] == "s") for k in keys]
        ks.sort(key=lambda k: k[0])
        self.period = period
        if period:
            ext = [(f - period, v, s) for f, v, s in ks] + ks + [(f + period, v, s) for f, v, s in ks]
            ks = ext
        self.f = [k[0] for k in ks]
        self.v = [k[1] for k in ks]
        n = len(ks)
        self.m = []
        for i in range(n):
            if ks[i][2]:
                self.m.append(self.v[i] * 0.0)
                continue
            i0, i1 = max(i - 1, 0), min(i + 1, n - 1)
            if i0 == i1:
                self.m.append(self.v[i] * 0.0)
                continue
            if (i > 0 and _d(self.v[i], self.v[i - 1]) < 1e-9) or (i < n - 1 and _d(self.v[i], self.v[i + 1]) < 1e-9):
                self.m.append(self.v[i] * 0.0)
                continue
            self.m.append((self.v[i1] - self.v[i0]) * (1.0 / (self.f[i1] - self.f[i0])))

    def __call__(self, x):
        f = self.f
        if self.period:
            x = x % self.period
        if x <= f[0]:
            return self.v[0] * 1.0
        if x >= f[-1]:
            return self.v[-1] * 1.0
        lo, hi = 0, len(f) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if f[mid] <= x:
                lo = mid
            else:
                hi = mid
        dt = f[hi] - f[lo]
        t = (x - f[lo]) / dt
        t2, t3 = t * t, t * t * t
        return (self.v[lo] * (2 * t3 - 3 * t2 + 1) + self.m[lo] * (dt * (t3 - 2 * t2 + t))
                + self.v[hi] * (-2 * t3 + 3 * t2) + self.m[hi] * (dt * (t3 - t2)))


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# ------------------------------------------------------------------ hand / foot geometry
BALL_OFF = Vector((0, -0.149, -0.089))        # ankle -> ball of the foot in the rest pose (foot flat, toes to -Y)
HAND_AXIS = {"l": Vector((1, 0, 0)), "r": Vector((-1, 0, 0))}   # wrist -> fingers in the rest (T) pose
PALM_REST = Vector((0, 0, -1))                # palm normal in the rest pose
GRIP_OFF = 0.075                              # wrist -> palm centre


def foot_rot(yaw=0.0, pitch=0.0, roll=0.0):
    """world rotation of the foot relative to 'flat, toes -Y'. pitch > 0 = toes down (heel up), yaw > 0 = toes turn to +X."""
    return Quaternion((0, 0, 1), rad(yaw)) @ Quaternion((1, 0, 0), rad(pitch)) @ Quaternion((0, 1, 0), rad(roll))


def ankle_from_ball(B, R):
    return B - R @ BALL_OFF


def hand_rot(side, dirv, palm):
    """world rotation relative to the rest pose so that the fingers point along dirv and the palm faces `palm`."""
    a = HAND_AXIS[side]
    s = a.cross(PALM_REST)
    d = Vector(dirv).normalized()
    n = Vector(palm)
    n = (n - d * n.dot(d)).normalized()
    s2 = d.cross(n)
    M0 = Matrix((a, PALM_REST, s)).transposed()
    M1 = Matrix((d, n, s2)).transposed()
    return (M1 @ M0.inverted()).to_quaternion()


def hand_stages(side, stages, ts):
    """hand rotation through several (fingers dir, palm normal) stages, blended with slerp between neighbours: ts[i] in 0..1 blends stage i -> i+1.
    (Lerping the two direction vectors passes through near-parallel finger / palm vectors and flips the wrist by 100+ degrees in one frame.)"""
    R = hand_rot(side, *stages[0])
    for st, t in zip(stages[1:], ts):
        R = R.slerp(hand_rot(side, *st), t)
    return R


def wrist_from_grip(G, R, side):
    return G - (R @ HAND_AXIS[side]) * GRIP_OFF


def rot_zxy(pitch=0.0, roll=0.0, yaw=0.0):
    """pitch about X (+ = lean forward, toward -Y), roll about Y (+ = top to +X, the character's left), yaw about Z (+ = turn left)"""
    return Quaternion((0, 0, 1), rad(yaw)) @ Quaternion((1, 0, 0), rad(pitch)) @ Quaternion((0, 1, 0), rad(roll))


class Pose(A.Pose):
    def __init__(self):
        super().__init__()
        self.abs = {}                 # end bone (hand_l, foot_r ...) -> world rotation relative to rest
        self.grip = {"l": 0.6, "r": 0.6}   # 0 = open hand, 1 = fist
        self.anchor = None            # (bone, world target, weight): the pelvis is solved to put that bone head at the target (blend by weight)
        self.probe = {}


def set_torso(P, pelvis=(0, 0, 0), spine=(0, 0, 0), head=(0, 0, 0), clav=0.0):
    """pelvis/spine/head are (pitch, roll, yaw) degrees; spine is the total split over the three spine bones, head over neck+Head"""
    P.rot["pelvis"] = rot_zxy(*pelvis)
    for n, w in (("spine_01", 0.30), ("spine_02", 0.35), ("spine_03", 0.35)):
        P.rot[n] = rot_zxy(spine[0] * w, spine[1] * w, spine[2] * w)
    P.rot["neck_01"] = rot_zxy(head[0] * 0.4, head[1] * 0.4, head[2] * 0.4)
    P.rot["Head"] = rot_zxy(head[0] * 0.6, head[1] * 0.6, head[2] * 0.6)


def set_limbs(P, hands=None, feet=None, kdir=None, edir=None, pelvis_rot=None):
    """hands: {side: (G grip point, dir, palm, grip)}, feet: {side: (B ball, yaw, pitch, roll)}
    kdir/edir: {side: direction the knee / elbow points}"""
    kdir = kdir or {}
    edir = edir or {}
    for side, sx in (("l", 1), ("r", -1)):
        if hands and side in hands:
            G, d, palm, grip = hands[side][:4]
            R = hands[side][4] if len(hands[side]) > 4 else hand_rot(side, d, palm)      # a 5th entry = ready-made rotation (slerped stages)
            w = wrist_from_grip(G, R, side)
            P.t["hand_" + side] = w
            P.abs["hand_" + side] = R
            P.grip[side] = grip
            sh = P.pelvis + V(sx * 0.19, 0.0, 0.52)
            e = edir.get(side, V(sx * 0.8, 0.55, -0.1)).normalized()
            P.t["elbow_" + side] = (sh + w) * 0.5 + e * 0.6
        if feet and side in feet:
            B, yaw, pitch, roll = feet[side]
            R = foot_rot(yaw, pitch, roll)
            a = ankle_from_ball(B, R)
            P.t["foot_" + side] = a
            P.abs["foot_" + side] = R
            hip = P.pelvis + V(sx * 0.09, -0.05, 0.015)
            k = kdir.get(side, V(sx * 0.15, -1.0, 0.15)).normalized()
            P.t["knee_" + side] = (hip + a) * 0.5 + k * 0.6


# ------------------------------------------------------------------ bake with absolute hand/foot orientations + validation
def mid_shoulder():
    pb = tgt.pose.bones
    return (pb["upperarm_l"].head + pb["upperarm_r"].head) * 0.5


def solve_pose(P):
    A.apply_pose(P)
    if P.anchor is not None:
        bone, S, w = P.anchor
        if w > 0:
            e = S - tgt.pose.bones[bone].head
            P.pelvis = P.pelvis + e * w
            A.apply_pose(P)
            # IK targets follow the world, not the pelvis, so one correction is exact (translation only)


POLE_LIMB = {"knee_l": ("thigh_l", "calf_l", "foot_l"), "knee_r": ("thigh_r", "calf_r", "foot_r"),
             "elbow_l": ("upperarm_l", "lowerarm_l", "hand_l"), "elbow_r": ("upperarm_r", "lowerarm_r", "hand_r")}
POLE_STEP = 0.10          # max knee / elbow travel (relative to its hip / shoulder) per 30 fps frame before the pole is pulled toward the previous knee


def solve_continuous(P, prev):
    """solve_pose + pole continuity. A 2-bone IK knee / elbow can swing around the hip-ankle axis by 0.3-0.5 m in one frame when the authored
    pole direction changes quickly near a folded limb (the 0.36 m calf snap of the first Vault_Low), and the bend plane / twist of an
    (almost) straight limb is undefined (upper arms rolling 120+ degrees in one frame right before a hand releases the wall).
      * folded limb: after the solve, a joint that moved more than POLE_STEP relative to its parent since the previous frame gets its pole
        target pulled toward the previous joint direction (half-way per iteration) and the pose is solved again;
      * straight limb (hip-end distance above 90 % of the limb length): the pole direction is frozen to the previous frame's, blended in
        with the straightness, so the plane cannot flip.
    `prev` is the state dict carried from frame to frame."""
    solve_pose(P)
    pbs = tgt.pose.bones
    for pole, (root_b, mid_b, end_b) in POLE_LIMB.items():
        if pole not in P.t:
            continue
        last = 9.0
        for it in range(8):
            hip = pbs[root_b].head
            end = P.t[end_b]
            ax = (end - hip)
            full = (pbs[mid_b].head - hip).length + (pbs[end_b].head - pbs[mid_b].head).length
            if ax.length < 1e-4:
                break
            axn = ax.normalized()
            mid = (hip + end) * 0.5
            ratio = ax.length / full
            if ratio > 0.90:                                   # near straight: keep the previous bend plane
                pd = prev.get(pole + "_dir")
                if pd is not None:
                    w = smooth((ratio - 0.90) / 0.06)
                    cur = P.t[pole] - mid
                    cur = cur - axn * cur.dot(axn)
                    pdp = pd - axn * pd.dot(axn)
                    if cur.length > 1e-5 and pdp.length > 1e-5 and w > 0:
                        P.t[pole] = mid + cur.normalized().lerp(pdp.normalized(), w).normalized() * 0.6
                        solve_pose(P)
                break
            rel = pbs[mid_b].head - hip
            jump = (rel - prev[pole]).length if pole in prev else 0.0
            if jump <= POLE_STEP or jump > 0.95 * last:      # fine, or the limb cannot follow (the end target itself moves that fast)
                break
            last = jump
            kp = prev[pole] - axn * prev[pole].dot(axn)
            if kp.length < 1e-4:
                break
            cur = P.t[pole] - mid
            cur = cur - axn * cur.dot(axn)
            if cur.length < 1e-4:
                cur = kp
            new = cur.normalized().lerp(kp.normalized(), 0.5).normalized()
            P.t[pole] = mid + new * 0.6
            solve_pose(P)
    for pole, (root_b, mid_b, end_b) in POLE_LIMB.items():
        prev[pole] = (pbs[mid_b].head - pbs[root_b].head).copy()
        if pole in P.t:
            hip = pbs[root_b].head
            axn = (P.t[end_b] - hip).normalized() if (P.t[end_b] - hip).length > 1e-4 else Vector((0, 0, 1))
            mid = (hip + P.t[end_b]) * 0.5
            d = P.t[pole] - mid
            d = d - axn * d.dot(axn)
            if d.length > 1e-5:
                prev[pole + "_dir"] = d.normalized()


PROBE = [("thigh_l", "calf_l", 0.075), ("calf_l", "foot_l", 0.055), ("foot_l", "ball_l", 0.04),
         ("thigh_r", "calf_r", 0.075), ("calf_r", "foot_r", 0.055), ("foot_r", "ball_r", 0.04),
         ("pelvis", "spine_01", 0.11), ("spine_01", "spine_02", 0.11), ("spine_02", "spine_03", 0.12),
         ("upperarm_l", "lowerarm_l", 0.045), ("lowerarm_l", "hand_l", 0.04),
         ("upperarm_r", "lowerarm_r", 0.045), ("lowerarm_r", "hand_r", 0.04), ("neck_01", "Head", 0.09)]


def bake2(name, poses, log=None):
    pbs = tgt.pose.bones
    A.assign(tgt, None)
    for pb in pbs:                       # start every clip from the rest pose so the IK solution never depends on the previous clip
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    frames = []
    diag = []
    prev = {}
    for fi, P in enumerate(poses):
        solve_continuous(P, prev)
        final = {}
        fin = {}
        adj = {}
        row = {}
        # reach error of the IK effectors
        errs = {}
        for k, bn in (("hand_l", "hand_l"), ("hand_r", "hand_r"), ("foot_l", "foot_l"), ("foot_r", "foot_r")):
            if k in P.t:
                errs[k] = (pbs[bn].head - P.t[k]).length
        row["err"] = errs
        for n in ORDER:
            pb = pbs[n]
            M = pb.matrix.copy()
            b = pb.bone
            if n in P.abs:
                cur = M.to_3x3()
                des = P.abs[n].to_matrix() @ L[n].to_3x3()
                d = des @ cur.inverted()
                head = M.translation.copy()
                adj[n] = Matrix.Translation(head) @ d.to_4x4() @ Matrix.Translation(-head)
            else:
                adj[n] = adj[b.parent.name] if b.parent else Matrix.Identity(4)
            M = adj[n] @ M
            final[n] = M
            if b.parent is None:
                basis = b.convert_local_to_pose(M, b.matrix_local, invert=True)
            else:
                basis = b.convert_local_to_pose(M, b.matrix_local, parent_matrix=final[b.parent.name],
                                                parent_matrix_local=b.parent.matrix_local, invert=True)
            fin[n] = basis
        # world probe points (segments) for collision tests: head/tail of the pre-adjust matrices are close enough
        row["seg"] = {}
        for a, bn, r in PROBE:
            row["seg"][a + ">" + bn] = (pbs[a].head.copy(), pbs[bn].head.copy(), r)
        row["pelvis"] = pbs["pelvis"].head.copy()
        row["sh"] = mid_shoulder().copy()
        diag.append(row)
        frames.append((fin, P))
    for c in IKC.values():
        c.mute = True
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    A.assign(tgt, act)
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
            g = P.grip[side]
            for n in FINGERS:
                if n.endswith("_" + side):
                    pbs[n].rotation_quaternion = RELAX[n].slerp(FIST[n], g)
                    pbs[n].keyframe_insert("rotation_quaternion", frame=f)
    A.assign(tgt, None)
    for c in IKC.values():
        c.mute = False
    return act, diag


# ------------------------------------------------------------------ box collision report
def box_pen(p, r, box):
    (x0, x1), (y0, y1), (z0, z1) = box
    dx = max(x0 - p.x, 0, p.x - x1)
    dy = max(y0 - p.y, 0, p.y - y1)
    dz = max(z0 - p.z, 0, p.z - z1)
    if dx == 0 and dy == 0 and dz == 0:
        ins = min(p.x - x0, x1 - p.x, p.y - y0, y1 - p.y, p.z - z0, z1 - p.z)
        return r + ins
    d = math.sqrt(dx * dx + dy * dy + dz * dz)
    return max(0.0, r - d)


def report_box(name, diag, box, skip=("lowerarm_l>hand_l", "lowerarm_r>hand_r")):
    worst = []
    for fi, row in enumerate(diag):
        w = (0.0, "")
        for k, (a, b, r) in row["seg"].items():
            if k in skip:
                continue
            for i in range(5):
                p = a.lerp(b, i / 4.0)
                pen = box_pen(p, r, box)
                if pen > w[0]:
                    w = (pen, k)
        worst.append(w)
    bad = [(fi, round(w[0], 3), w[1]) for fi, w in enumerate(worst) if w[0] > 0.012]
    print("BOX", name, "max pen %.3f" % max(w[0] for w in worst), "frames with >1.2 cm:", bad[:40], flush=True)
    return worst


def report_reach(name, diag, tol=0.02):
    worst = {}
    for fi, row in enumerate(diag):
        for k, e in row["err"].items():
            if e > worst.get(k, (0, 0))[0]:
                worst[k] = (e, fi)
    bad = {k: (round(v[0], 3), v[1]) for k, v in worst.items() if v[0] > tol}
    print("REACH", name, "IK misses >%.0f cm (max err, frame):" % (tol * 100), bad if bad else "none", flush=True)
    return bad


# ------------------------------------------------------------------ clip registry
CLIPS = {}
EVENTS = {}      # clip name -> {event: frame} (written to the .clips.json sidecar)
CONTACTS = {}    # clip name -> [[bone, frame0, frame1], ...] world-locked hand (wrist) / foot (ball) windows; scan_motion.py checks the drift on the exported GLB


def clip(fn):
    CLIPS[fn.__name__] = fn
    return fn


# ------------------------------------------------------------------ pose blending / standing pose (used by the ledge + mantle clips)
def blend_pose(P0, P1, w):
    """pose interpolation: vectors lerp, world rotations slerp, grip lerp. Anchors are not blended (take P0's if w < 0.5)."""
    w = max(0.0, min(1.0, w))
    if w <= 0.0:
        return P0
    if w >= 1.0:
        return P1
    P = Pose()
    P.pelvis = P0.pelvis.lerp(P1.pelvis, w)
    P.root = P0.root.lerp(P1.root, w)
    for d, a, b in ((P.t, P0.t, P1.t), (P.rot, P0.rot, P1.rot), (P.abs, P0.abs, P1.abs)):
        for k in set(a) | set(b):
            if k in a and k in b:
                d[k] = a[k].lerp(b[k], w) if hasattr(a[k], "lerp") and not isinstance(a[k], Quaternion) else a[k].slerp(b[k], w)
            else:
                d[k] = (a[k] if k in a else b[k]).copy()
    for s in ("l", "r"):
        P.grip[s] = lerp(P0.grip[s], P1.grip[s], w)
    P.anchor = P0.anchor if w < 0.5 else P1.anchor
    return P


def stand_pose(org, breath=0.0, head_pitch=-3.0, yaw=0.0):
    """relaxed idle stand at the world point org (feet on org.z): pelvis 0.895 above the floor, arms hanging with soft elbows,
    a small stagger. `breath` (-1..1) lifts the chest a few mm. yaw is not used (the character always faces -Y)."""
    P = Pose()
    P.root = V(0, 0, 0)
    P.pelvis = org + V(0.0, 0.03, 0.895 + 0.004 * breath)
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        G = org + V(sx * 0.27, 0.05 - 0.02 * breath, 0.80)
        hands[side] = (G, V(0.06 * sx, -0.10, -1.0), V(-1.0 * sx, 0.0, -0.1), 0.35)
    feet = {"l": (org + V(0.11, -0.05, ZB0), 6.0, 0.0, 0.0), "r": (org + V(-0.11, 0.05, ZB0), -6.0, 0.0, 0.0)}
    set_limbs(P, hands, feet, {"l": V(0.15, -1.0, 0.1), "r": V(-0.15, -1.0, 0.1)}, {"l": V(0.7, 0.9, -0.2), "r": V(-0.7, 0.9, -0.2)})
    set_torso(P, (0, 0, 0), (1.0 + 0.6 * breath, 0, 0), (head_pitch, 0, 0))
    return P


ZB0 = 0.015
