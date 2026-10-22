# Rider clip helpers: horse sync data (D(t), rein grips), world stabilisation, seated / free pose builders.
# Built on ../../traversal/trav_lib.py (which imports ../../free2/author_traversal.py: UAL import + IK rig + bake).
#
# SYNC CONTRACT. A rider clip is authored in RIDER CLIP SPACE = the horse at rest, horse root at the origin, horse armature axes
# (-Y forward, +X = horse's left, +Z up; the UAL character faces -Y too). In game the rider node is moved rigidly by the saddle
# delta D(t) = saddle_pose(t) * saddle_rest^-1 (relative to the horse root) and plays its clip at the same normalised time as
# the horse clip. Anything that must be smooth in the WORLD is authored in the world (horse-root frame) and mapped back with D^-1.
import os, sys, math, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "traversal")))
import trav_lib as TL
from trav_lib import (A, tgt, Pose, Trk, smooth, lerp, V, rad, hand_rot, foot_rot, ankle_from_ball, wrist_from_grip, rot_zxy,
                      blend_pose, BALL_OFF, HAND_AXIS, GRIP_OFF)
from mathutils import Vector, Quaternion, Matrix

KINGDOM = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
TRACKS = json.load(open(os.path.join(HERE, "..", "source", "rider_tracks.json")))
HCLIPS = {c["name"]: c for c in json.load(open(os.path.join(KINGDOM, "assets", "generated", "horses", "Horse_Anims.glb.clips.json")))}

# ------------------------------------------------------------------ horse geometry at rest (clip space)
SADDLE_TOP = 1.561                    # saddle seat top (lowest point of the seat) at y -0.24
SEAT = V(0.0, -0.225, 1.646)          # pelvis head when seated (0.085 above the seat top: the ischia sit on the saddle)
STIR = {"l": Vector(TRACKS["stirrup_L"]), "r": Vector(TRACKS["stirrup_R"])}    # stirrup tread = ball of the foot (from rider_tracks.json)
GRIP_REST = {"l": V(0.09, -0.60, 1.7212), "r": V(-0.09, -0.60, 1.7212)}
SX = {"l": 1.0, "r": -1.0}
HIP_OFF = V(0.089, -0.051, 0.015)     # pelvis head -> thigh head (x mirrored)
SH_OFF = V(0.19, 0.015, 0.524)        # pelvis head -> shoulder (upperarm head), upright torso


def M4(p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4()


def qpow(q, t):
    q = q.copy()
    if q.w < 0:
        q.negate()
    return Quaternion().slerp(q, t)


def qalign(q, ref):
    return q if q.dot(ref) >= 0 else -q


class Sync:
    """Per-frame horse data for one horse clip (or the horse at rest: Sync.rest(n))."""

    def __init__(self, clip=None, n=None, frames=None):
        self.clip = clip
        if clip is None:
            self.n = n
            self.Dp = [V(0, 0, 0) for _ in range(n)]
            self.Dq = [Quaternion() for _ in range(n)]
            self.grip = {s: [GRIP_REST[s].copy() for _ in range(n)] for s in "lr"}
            self.bit = [V(0, -1.36, 1.475) for _ in range(n)]
            self.loop = False
            self.meta = {}
        else:
            rows = TRACKS[clip]
            if frames:
                rows = rows[frames[0]:frames[1] + 1]
            self.n = len(rows)
            self.Dp = [Vector(r["D"][:3]) for r in rows]
            self.Dq = [Quaternion(r["D"][3:]).normalized() for r in rows]
            self.grip = {"l": [Vector(r["rein_grip_L"]) for r in rows], "r": [Vector(r["rein_grip_R"]) for r in rows]}
            self.bit = [Vector(r["bit"]) for r in rows]
            self.meta = HCLIPS.get(clip, {})
            self.loop = bool(self.meta.get("loop")) and not frames
        self.D = [M4(p, q) for p, q in zip(self.Dp, self.Dq)]
        self.Dinv = [m.inverted() for m in self.D]
        self._sm = {}

    @staticmethod
    def rest(n):
        return Sync(None, n=n)

    def smoothed(self, sigma):
        """Gaussian low-pass of D over time (cyclic for loops, clamped ends otherwise). sigma None = the cycle mean (loops) / sigma 6."""
        key = sigma
        if key in self._sm:
            return self._sm[key]
        n = self.n
        per = n - 1 if self.loop else None
        if sigma is None:
            sigma = 1e9 if self.loop else 6.0
        out = []
        for f in range(n):
            ps, qs, ws = V(0, 0, 0), Quaternion((0, 0, 0, 0)), 0.0
            ref = self.Dq[f]
            if per and sigma > per:
                idx = [(j, 1.0) for j in range(per)]
            else:
                R = int(min(3 * sigma, (per or n) // 2 if per else 3 * sigma)) + 1
                idx = []
                for d in range(-R, R + 1):
                    j = f + d
                    if per:
                        j %= per
                    else:
                        j = min(max(j, 0), n - 1)
                    idx.append((j, math.exp(-0.5 * (d / sigma) ** 2)))
            for j, w in idx:
                ps += self.Dp[j] * w
                q = qalign(self.Dq[j], ref)
                qs = Quaternion((qs.w + q.w * w, qs.x + q.x * w, qs.y + q.y * w, qs.z + q.z * w))
                ws += w
            out.append((ps / ws, qs.normalized()))
        self._sm[key] = out
        return out


# ------------------------------------------------------------------ pose transforms
def xform_pose(P, M, q):
    """rigidly transform a pose (world targets / pelvis / pelvis rotation / absolute hand-foot rotations) by (M, q)."""
    Q = Pose()
    Q.root = M @ P.root
    Q.pelvis = M @ P.pelvis
    Q.t = {k: M @ v for k, v in P.t.items()}
    Q.rot = {k: v.copy() for k, v in P.rot.items()}
    if "pelvis" in Q.rot:
        Q.rot["pelvis"] = q @ Q.rot["pelvis"]
    else:
        Q.rot["pelvis"] = q.copy()
    Q.abs = {k: q @ v for k, v in P.abs.items()}
    Q.grip = dict(P.grip)
    Q.anchor = None
    return Q


def to_world(P, S, f):
    return xform_pose(P, S.D[f], S.Dq[f])


def to_clip(P, S, f):
    return xform_pose(P, S.Dinv[f], S.Dq[f].inverted())


def chain(P, pel_q, chest_q, head_q, clav=0.0, shrug=0.0, clav_l=None, clav_r=None):
    """pelvis / chest (spine_03) / head world rotations -> the relative bone rotations the framework keys (split evenly over
    spine_01..03 and neck (40 %) + Head (60 %)). clav = shoulder protraction (deg, + = shoulders forward), shrug = lift (deg)."""
    P.rot["pelvis"] = pel_q
    rel = pel_q.inverted() @ chest_q
    s = qpow(rel, 1.0 / 3.0)
    for n in ("spine_01", "spine_02", "spine_03"):
        P.rot[n] = s.copy()
    relh = chest_q.inverted() @ head_q
    P.rot["neck_01"] = qpow(relh, 0.4)
    P.rot["Head"] = qpow(relh, 0.6)
    cl = clav if clav_l is None else clav_l
    cr = clav if clav_r is None else clav_r
    P.rot["clavicle_l"] = rot_zxy(0, -shrug, -cl)
    P.rot["clavicle_r"] = rot_zxy(0, shrug, cr)


def body_points(P, pel_q, chest_q):
    hip = {s: P.pelvis + pel_q @ V(SX[s] * HIP_OFF.x, HIP_OFF.y, HIP_OFF.z) for s in "lr"}
    sp1 = V(0.0, -0.034, 0.134)
    sh = {s: P.pelvis + pel_q @ sp1 + chest_q @ (V(SX[s] * SH_OFF.x, SH_OFF.y, SH_OFF.z) - sp1) for s in "lr"}
    return hip, sh


def put_hand(P, side, G, R, grip, sh, edir_world):
    w = wrist_from_grip(G, R, side)
    P.probe["grip_" + side] = G.copy()
    P.t["hand_" + side] = w
    P.abs["hand_" + side] = R
    P.grip[side] = grip
    P.t["elbow_" + side] = (sh + w) * 0.5 + edir_world.normalized() * 0.6


def put_foot(P, side, B, R, hip, kdir_world):
    a = ankle_from_ball(B, R)
    P.t["foot_" + side] = a
    P.abs["foot_" + side] = R
    P.t["knee_" + side] = (hip + a) * 0.5 + kdir_world.normalized() * 0.6


# ------------------------------------------------------------------ rein hand orientation (thumbs up, fists slightly inward)
def rein_rot(side, pitch=0.0, yaw=0.0):
    sx = SX[side]
    d = V(-sx * 0.30, -0.80, -0.52)
    palm = V(-sx * 0.95, -0.05, -0.30)
    R = hand_rot(side, d, palm)
    return rot_zxy(pitch, 0, yaw) @ R


# ------------------------------------------------------------------ seated pose (clip space)
BASE = dict(px=0.0, py=0.0, pz=0.0, s_pel=0.0, sig=None, pel_pitch=6.0, pel_roll=0.0, pel_yaw=0.0, s_pelrot=0.0,
            lean=9.0, c_roll=0.0, c_yaw=0.0, s_chest=0.5, h_pitch=4.0, h_roll=0.0, h_yaw=0.0, s_head=0.85,
            clav=6.0, shrug=0.0, clav_l=None, clav_r=None, grip=0.85, on_grip=1.0,
            hl_dx=0.0, hl_dy=0.0, hl_dz=0.0, hr_dx=0.0, hr_dy=0.0, hr_dz=0.0, hand_pitch=0.0,
            heel=-15.0, heel_l=0.0, heel_r=0.0, toe_out=13.0, knee_out=1.25, knee_fwd=0.75, knee_up=0.0,
            elbow_out=0.45, elbow_back=0.55, elbow_down=0.65, foot_on=1.0, up_w=0.0)


def val(g, k, f):
    v = g[k] if k in g else BASE[k]
    return v(f) if callable(v) else v


def seat_pose(S, f, g):
    """One frame of a riding pose in clip space. g: parameters (numbers or callables of the frame, see BASE).
    Stabilisation s_* in 0..1 blends a quantity from 'rigid with the saddle' (0) to 'follows the low-passed saddle' (1), i.e. it is
    authored in the world and mapped back with D^-1. Hands on the rein grips of the horse clip (on_grip = 1), feet on the stirrups.
    Optional callables g['hand_l'/'hand_r'](f, P, sh) -> (G, R, grip) and g['foot_l'/'foot_r'](f) -> (B, R) override hands / feet (clip)."""
    sig = val(g, "sig", f)
    sp, sq = S.smoothed(sig)[f]
    D, Dinv, Dq = S.D[f], S.Dinv[f], S.Dq[f]
    Ds = M4(sp, sq)
    x = SEAT + V(val(g, "px", f), val(g, "py", f), val(g, "pz", f))
    s = val(g, "s_pel", f)
    P = Pose()
    P.pelvis = Dinv @ ((D @ x).lerp(Ds @ x, s))
    if P.pelvis.z < SEAT.z - 0.004:                 # a stabilised pelvis never sinks into the saddle
        P.pelvis.z = SEAT.z - 0.004

    up_w = val(g, "up_w", f)
    tq = qalign(sq, Dq).slerp(Quaternion(), up_w) if up_w > 0 else qalign(sq, Dq)

    def stabq(sv, q):
        return Dq.inverted() @ Dq.slerp(qalign(tq, Dq), sv) @ q
    pel_q = stabq(val(g, "s_pelrot", f), rot_zxy(val(g, "pel_pitch", f), val(g, "pel_roll", f), val(g, "pel_yaw", f)))
    chest_q = stabq(val(g, "s_chest", f), rot_zxy(val(g, "lean", f), val(g, "c_roll", f), val(g, "c_yaw", f)))
    head_q = stabq(val(g, "s_head", f), rot_zxy(val(g, "h_pitch", f), val(g, "h_roll", f), val(g, "h_yaw", f)))
    chain(P, pel_q, chest_q, head_q, val(g, "clav", f), val(g, "shrug", f), val(g, "clav_l", f), val(g, "clav_r", f))
    hip, sh = body_points(P, pel_q, chest_q)
    for side in "lr":
        sx = SX[side]
        c = side[0]
        edir = chest_q @ V(sx * val(g, "elbow_out", f), val(g, "elbow_back", f), -val(g, "elbow_down", f))
        if ("hand_" + side) in g:
            G, R, gr = g["hand_" + side](f, P, sh[side])
        else:
            G = S.grip[side][f] + V(val(g, "h%s_dx" % c, f), val(g, "h%s_dy" % c, f), val(g, "h%s_dz" % c, f))
            G = GRIP_REST[side].lerp(G, val(g, "on_grip", f)) if val(g, "on_grip", f) < 1.0 else G
            R = rein_rot(side, val(g, "hand_pitch", f))
            gr = val(g, "grip", f)
        put_hand(P, side, G, R, gr, sh[side], edir)
        kdir = pel_q @ V(sx * val(g, "knee_out", f), -val(g, "knee_fwd", f), val(g, "knee_up", f))
        if ("foot_" + side) in g:
            B, R = g["foot_" + side](f)
        else:
            R = foot_rot(sx * val(g, "toe_out", f), val(g, "heel", f) + val(g, "heel_" + side, f), 0.0)
            B = STIR[side]
        put_foot(P, side, B, R, hip[side], kdir)
    return P


# ------------------------------------------------------------------ free (world) pose from keyed values
FREE0 = dict(root=V(0, 0, 0), pel=V(0, 0.03, 0.895), pel_rot=(0.0, 0.0, 0.0), spine=(2.0, 0.0, 0.0), head=(-3.0, 0.0, 0.0),
             yaw=0.0, clav=0.0, shrug=0.0,
             hand_l=V(0.27, 0.05, 0.80), hand_r=V(-0.27, 0.05, 0.80),
             hdir_l=V(0.06, -0.10, -1.0), hdir_r=V(-0.06, -0.10, -1.0), palm_l=V(-1.0, 0.0, -0.1), palm_r=V(1.0, 0.0, -0.1),
             grip_l=0.35, grip_r=0.35,
             foot_l=V(0.11, -0.05, 0.015), foot_r=V(-0.11, 0.05, 0.015), fyaw_l=6.0, fyaw_r=-6.0, fpitch_l=0.0, fpitch_r=0.0,
             froll_l=0.0, froll_r=0.0,
             kdir_l=V(0.15, -1.0, 0.1), kdir_r=V(-0.15, -1.0, 0.1), edir_l=V(0.7, 0.9, -0.2), edir_r=V(-0.7, 0.9, -0.2))


FREE_REACH = 0.52
LEG_REACH = 0.79


def free_pose(k):
    """World pose from a dict of values (FREE0 keys). Angles: (pitch, roll, yaw) degrees; 'yaw' turns the whole body (pelvis, chest,
    head, hand / foot orientations and the knee / elbow pole directions, which are given in the body frame). Hand/foot positions
    are world. spine = total pelvis->chest rotation, head = total chest->head rotation."""
    g = dict(FREE0)
    g.update(k)
    Y = Quaternion((0, 0, 1), rad(g["yaw"]))
    P = Pose()
    P.root = g["root"].copy()
    P.pelvis = g["pel"].copy()
    pel_q = Y @ rot_zxy(*g["pel_rot"])
    chest_q = pel_q @ rot_zxy(*g["spine"])
    head_q = chest_q @ rot_zxy(*g["head"])
    chain(P, pel_q, chest_q, head_q, g["clav"], g["shrug"])
    hip, sh = body_points(P, pel_q, chest_q)
    for s in "lr":
        R = g.get("hrot_" + s)
        if R is None:
            R = Y @ hand_rot(s, g["hdir_" + s], g["palm_" + s])
        G = Vector(g["hand_" + s])
        d = G - sh[s]
        if d.length > FREE_REACH:
            G = sh[s] + d * (FREE_REACH / d.length)
        put_hand(P, s, G, R, g["grip_" + s], sh[s], Y @ g["edir_" + s])
        Rf = g.get("frot_" + s)
        if Rf is None:
            Rf = Y @ foot_rot(g["fyaw_" + s], g["fpitch_" + s], g["froll_" + s])
        B = Vector(g["foot_" + s])
        a = ankle_from_ball(B, Rf)
        d = a - hip[s]
        if d.length > LEG_REACH:                         # airborne / dangling legs: keep the ankle within reach (no locked knees)
            B = B + (hip[s] + d * (LEG_REACH / d.length) - a)
        put_foot(P, s, B, Rf, hip[s], Y @ g["kdir_" + s])
    return P


class Keys:
    """Keyframed free-pose values: Keys([(frame, {key: value, ...}), ...]). Each key gets its own Hermite track through the frames that
    set it (tuples are tracked as vectors). Frames flagged with 's' as 3rd element hold (zero tangents)."""

    def __init__(self, keys, base=None):
        self.base = dict(FREE0)
        if base:
            self.base.update(base)
        per = {}
        for kf in keys:
            f, d = kf[0], kf[1]
            hold = len(kf) > 2 and kf[2] == "s"
            for k, v in d.items():
                if isinstance(v, tuple):
                    v = Vector(v)
                per.setdefault(k, []).append((f, v, "s") if hold else (f, v))
        self.trk = {k: Trk(v) for k, v in per.items()}
        self.tup = {k for kf in keys for k, v in kf[1].items() if isinstance(v, tuple)}

    def __call__(self, f):
        d = dict(self.base)
        for k, t in self.trk.items():
            d[k] = t(f)
        return d


def T1(keys, hold_all=False):
    """float track from [(frame, value), ...] (callable of the frame)."""
    t = Trk([(k[0], float(k[1]), "s") if hold_all else k for k in keys])
    return lambda f: float(t(f))


def pulse(f, f0, f1, f2=None, shape=1.0):
    """0 before f0, rises smoothly to 1 at f1, back to 0 at f2 (or stays 1)."""
    if f <= f0:
        return 0.0
    if f < f1:
        return smooth((f - f0) / float(f1 - f0)) ** shape
    if f2 is None or f <= f1:
        return 1.0
    return 1.0 - smooth((f - f1) / float(f2 - f1)) if f < f2 else 0.0


def blend_seq(Pa, Pb, w):
    return blend_pose(Pa, Pb, w)


# ------------------------------------------------------------------ registry
CLIPS = {}      # name -> fn() -> (poses, meta dict)


def clip(name=None):
    def deco(fn):
        CLIPS[name or fn.__name__] = fn
        return fn
    return deco


UPPER_BONES = None


def upper_bones():
    """spine_01 and everything below it in the hierarchy (the layer mask for the B clips)."""
    out = []

    def walk(b):
        out.append(b.name)
        for c in b.children:
            walk(c)
    walk(tgt.data.bones["spine_01"])
    return out
