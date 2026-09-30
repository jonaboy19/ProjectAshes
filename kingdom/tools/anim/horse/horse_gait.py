# Horse gait engine (Blender 5.2 side): poses the game skeleton (HorseSkeleton) directly from a motion script.
#
# A clip is a Script: a root path (position + yaw over time), a body offset/rotation relative to the root, spine/neck/head
# bends, and per leg a list of STANCES (t_land, t_lift, world toe point). Between stances a leg swings on an arc.
# Planted toes are world-fixed, so hooves never slide by construction (the export is checked by measure_slide()).
# Legs are solved analytically: fore = scapula swing + 2-bone IK (humerus, forearm+cannon with carpal flexion),
# hind = 2-bone IK (femur, tibia+cannon with hock flexion) - stifle and hock flex together like the reciprocal apparatus.
# Pastern and hoof: bottom-up from the planted toe (fetlock sinks under load, breakover about the toe), top-down in swing.
# Tail and mane: verlet chains (gravity, drag in the air stream, stiffness toward the FK pose), simulated over extra cycles
# so loops are seamless. Everything is baked to plain FK quaternion keys (+ root and hips location).
#
# Axes: horse faces -Y, +Z up, +X = the horse's left. Metres, seconds, 30 fps.
import bpy, math
from mathutils import Vector, Matrix, Quaternion

FPS = 30
V = lambda x, y, z: Vector((x, y, z))
LEGS = ("FL", "FR", "HL", "HR")
UP = V(0, 0, 1)


def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def smoother(t):
    t = max(0.0, min(1.0, t))
    return t * t * t * (t * (6 * t - 15) + 10)


def lerp(a, b, t):
    return a + (b - a) * t


def rot(axis, ang):
    return Quaternion(axis, ang)


class Trk:
    """Hermite track through (time, value[, 's']) keys (Catmull-Rom tangents; 's' or equal neighbours = zero tangent = hold)."""

    def __init__(self, keys, period=None):
        ks = sorted([(k[0], k[1], len(k) > 2 and k[2] == "s") for k in keys], key=lambda k: k[0])
        self.period = period
        if period:
            ks = [(f - period, v, s) for f, v, s in ks] + ks + [(f + period, v, s) for f, v, s in ks]
        self.f = [k[0] for k in ks]
        self.v = [k[1] for k in ks]
        n = len(ks)
        self.m = []
        for i in range(n):
            zero = self.v[i] * 0.0
            if ks[i][2] or n == 1:
                self.m.append(zero)
                continue
            i0, i1 = max(i - 1, 0), min(i + 1, n - 1)
            d = lambda a, b: abs(a - b) if isinstance(a, (int, float)) else (a - b).length
            if (i > 0 and d(self.v[i], self.v[i - 1]) < 1e-9) or (i < n - 1 and d(self.v[i], self.v[i + 1]) < 1e-9) or i0 == i1:
                self.m.append(zero)
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


def const(v):
    return lambda t: v


# ------------------------------------------------------------------ skeleton model
class Rig:
    def __init__(self, arm):
        self.arm = arm
        self.bones = arm.data.bones
        self.order = []

        def walk(b):
            self.order.append(b.name)
            for c in b.children:
                walk(c)
        for r in [b for b in self.bones if b.parent is None]:
            walk(r)
        self.L = {n: self.bones[n].matrix_local.copy() for n in self.order}
        self.R0 = {n: self.L[n].to_quaternion() for n in self.order}
        self.parent = {n: (self.bones[n].parent.name if self.bones[n].parent else None) for n in self.order}
        self.length = {n: self.bones[n].length for n in self.order}
        self.head0 = {n: self.bones[n].head_local.copy() for n in self.order}
        self.tail0 = {n: self.bones[n].tail_local.copy() for n in self.order}
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"
        # leg geometry (rest, armature space)
        self.leg = {}
        for leg in LEGS:
            s = leg[1]
            if leg[0] == "F":
                names = ["scapula_" + s, "humerus_" + s, "forearm_" + s, "cannon_F_" + s, "pastern_F_" + s, "hoof_F_" + s]
            else:
                names = ["thigh_" + s, "gaskin_" + s, "cannon_H_" + s, "pastern_H_" + s, "hoof_H_" + s]
            self.leg[leg] = names
        self.neutral = {}
        for leg in LEGS:
            hoof = self.leg[leg][-1]
            self.neutral[leg] = self.tail0[hoof].copy()          # rest toe point (on the ground)
            # mid-stance hoof point: cannon vertical under the hip / shoulder joint (the rest pose stands a little camped out)
            self.neutral[leg].y += -0.05 if leg[0] == "F" else -0.11

    def local_offset(self, n):
        p = self.parent[n]
        return self.L[p].inverted() @ self.L[n] if p else self.L[n]


# ------------------------------------------------------------------ geometry helpers
def ik2(root, goal, a, b, pole):
    """2-bone IK: joint position between root and goal with segment lengths a, b, bending toward `pole` (a direction)."""
    d = goal - root
    dist = d.length
    lo, hi = abs(a - b) + 1e-4, a + b - 1e-4
    over = max(0.0, dist - hi)
    dist = max(lo, min(hi, dist))
    u = d.normalized()
    x = (a * a - b * b + dist * dist) / (2 * dist)
    h = math.sqrt(max(a * a - x * x, 0.0))
    v = pole - u * pole.dot(u)
    if v.length < 1e-6:
        v = u.orthogonal()
    v.normalize()
    return root + u * x + v * h, over


def signed_angle(a, b, n):
    """angle from a to b about axis n"""
    a2 = (a - n * a.dot(n)).normalized()
    b2 = (b - n * b.dot(n)).normalized()
    return math.atan2(n.dot(a2.cross(b2)), a2.dot(b2))


# ------------------------------------------------------------------ motion script
class Script:
    """Everything that defines one clip. Callables of time t (s) unless stated."""

    def __init__(self, name, duration, loop=False):
        self.name = name
        self.duration = duration
        self.loop = loop
        self.frames = int(round(duration * FPS)) + (1 if not loop else 1)
        # root path
        self.root_pos = const(V(0, 0, 0))     # world position of the root bone (ground)
        self.root_yaw = const(0.0)            # radians, + = turn left (toward +X)
        # body relative to the root frame (pivot = mid barrel)
        self.body_off = const(V(0, 0, 0))     # translation (horse space)
        self.body_rot = const(V(0, 0, 0))     # (pitch, roll, yaw) radians, pitch + = nose down, roll + = top to the left (+X)
        self.pivot = V(0, -0.05, 1.20)
        # spine bends (pitch, roll, yaw) radians distributed over the bones
        self.spine = const(V(0, 0, 0))        # lumbar + thoracic (hips -> chest)
        self.neck = const(V(0, 0, 0))         # withers -> neck_4
        self.neck_w = NECK_W                  # how the neck bend is spread (base -> poll)
        self.head = const(V(0, 0, 0))         # head relative to the neck
        self.head_world_pitch = None          # optional: callable -> weight 0..1 to keep the head's world pitch at head_level
        self.jaw = const(0.0)                 # open angle (rad)
        self.ears = const((0.0, 0.0, 0.0, 0.0))   # (L pitch back, L yaw out, R pitch back, R yaw out) radians
        self.tail_base = const(V(0, 0, 0))    # tail_1 bend (pitch up - / down +, roll, yaw) radians on top of the rest (hanging)
        self.tail_lift = const(0.0)           # extra carriage up (radians spread over tail_1..2)
        self.belly = const(V(0, 0, 0))
        # legs
        self.stances = {leg: [] for leg in LEGS}   # (t_land, t_lift, toe world point, yaw of the hoof)
        self.swing_h = {leg: 0.12 for leg in LEGS}  # swing arc height of the fetlock (m)
        self.flex = {"F": 1.2, "H": 0.8}      # peak carpal / hock extra flexion in swing (rad)
        self.fetlock_flex = {"F": 1.2, "H": 1.1}
        self.load = {"F": 0.25, "H": 0.18}    # fetlock extension at mid stance (rad)
        self.breakover = 0.55                 # hoof pitch at lift-off (rad)
        self.breakover_start = 0.66           # fraction of the stance where the heel starts to lift
        self.leg_override = {}                # leg -> callable(t) -> None or dict(toe=Vector world, hoof_pitch, carpal/hock flex, fetlock flex)
        self.support_max = 0.06              # at most this much lowering (m)
        self.support_fixed = None            # callable t -> (dz, dpitch): pre-smoothed support (set by author_horse)
        self.support = True                   # lower the body when a stance leg cannot reach its planted hoof
        self.sim_secondary = True
        self.wind = const(V(0, 0, 0))         # extra air stream (world) for the hair
        self.events = {}                      # name -> [frames]
        self.rein = lambda t, side: V(0, 0, 0)   # extra rein grip offset (withers space) per side
        self.meta = {}

    def t_of(self, f):
        return f / FPS


def gait_stances(script, pattern, T, duty, t0, t1, root_xf, neutral, place_off=None, lat_off=None):
    """Generate stance intervals for a periodic gait over [t0, t1] from a footfall pattern {leg: landing phase}.
    Toe planted at root_xf(t_mid) * (neutral + offsets) so the hoof is under its neutral point at mid stance."""
    for leg, ph in pattern.items():
        d = duty[leg] if isinstance(duty, dict) else duty
        k0 = math.floor((t0 - (ph + d) * T) / T) - 1
        k = k0
        while True:
            tl = (ph + k) * T
            if tl > t1 + T:
                break
            tu = tl + d * T
            tm = (tl + tu) * 0.5
            M = root_xf(tm)
            loc = neutral[leg].copy()
            if place_off:
                loc += place_off(leg, tm)
            p = M @ loc
            p.z = 0.0
            script.stances[leg].append((tl, tu, p))
            k += 1


# ------------------------------------------------------------------ the solver
class Solver:
    def __init__(self, rig):
        self.rig = rig
        R = rig
        L = R.L
        self.len = R.length
        # sign conventions measured on the rest pose
        n = V(1, 0, 0)
        self.n = n

    # -------- FK helpers
    def child_world(self, W, n, basis):
        p = self.rig.parent[n]
        base = W[p] @ self.rig.local_offset(n) if p else self.rig.L[n]
        return base @ basis

    def rot_basis(self, n, q_hs, W):
        """basis quaternion that rotates bone n by q (given in horse/armature axes) about its head, in its parent's posed frame"""
        R0 = self.rig.R0[n]
        return R0.inverted() @ q_hs @ R0

    def aim(self, W, n, target_tail, twist_ref=None):
        """world matrix for bone n: head fixed by the parent, Y axis aimed at target_tail with minimal swing from the
        un-rotated (basis identity) orientation"""
        base = self.child_world(W, n, Matrix.Identity(4))
        head = base.translation
        y0 = base.to_3x3().col[1].normalized()
        d = (target_tail - head)
        if d.length < 1e-6:
            return base
        sw = y0.rotation_difference(d.normalized())
        rot3 = sw.to_matrix() @ base.to_3x3()
        M = rot3.to_4x4()
        M.translation = head
        return M

    def basis_from_world(self, W, n, M):
        p = self.rig.parent[n]
        b = self.rig.bones[n]
        if p is None:
            return b.convert_local_to_pose(M, b.matrix_local, invert=True)
        return b.convert_local_to_pose(M, b.matrix_local, parent_matrix=W[p], parent_matrix_local=self.rig.bones[p].matrix_local, invert=True)


def spread(names, v, weights=None):
    w = weights or [1.0 / len(names)] * len(names)
    return {n: v * k for n, k in zip(names, w)}


def q_pry(v):
    """(pitch, roll, yaw) radians about horse X, Y, Z (applied yaw * pitch * roll)"""
    return rot(UP, v.z) @ rot(V(1, 0, 0), v.x) @ rot(V(0, 1, 0), v.y)


SPINE = ["hips", "spine_1", "spine_2", "spine_3", "chest"]
SPINE_W = [0.10, 0.25, 0.25, 0.22, 0.18]
NECK = ["withers", "neck_1", "neck_2", "neck_3", "neck_4"]
NECK_W = [0.14, 0.26, 0.24, 0.20, 0.16]
TAIL = ["tail_1", "tail_2", "tail_3", "tail_4", "tail_5"]


class Pose:
    """one evaluated frame: world matrices W of every bone and pose-basis matrices B"""
    pass


class Engine:
    def __init__(self, arm):
        self.rig = Rig(arm)
        self.S = Solver(self.rig)
        R = self.rig
        self.neutral = R.neutral
        # leg rest vectors in armature space
        self.rest = {}
        for leg in LEGS:
            nm = R.leg[leg]
            pts = [R.head0[nm[0]]] + [R.tail0[x] for x in nm]
            self.rest[leg] = pts
        # distal rest angles (about +X) and flexion signs
        n = V(1, 0, 0)
        self.distal = {}
        for leg in LEGS:
            pts = self.rest[leg]
            T, C, F = pts[-1], pts[-2], pts[-3]
            K = pts[-4]
            c = (F - K).normalized(); p = (C - F).normalized(); h = (T - C).normalized()
            self.distal[leg] = dict(a_cp=signed_angle(c, p, n), a_ph=signed_angle(p, h, n),
                                    lp=(C - F).length, lh=(T - C).length, lc=(F - K).length)
        # flexion sign: rotating the pastern toward -a_cp (straightening past the cannon line) vs flexing it back.
        # For every horse joint here, "flexion" (the hoof comes back and up in swing) is a POSITIVE rotation about +X
        # of the distal segment when viewed from the left (toe goes from -Y (front) toward +Z (up)) ... verified below.
        self.flex_sign = 1.0
        test = rot(n, 0.5) @ V(0, -1, 0)
        if test.z < 0:
            self.flex_sign = -1.0

    # ---------------- legs
    def fore_SH(self, W, leg, F, n):
        """shoulder joint after the scapula swing, which follows the limb angle (protraction when the hoof is ahead)"""
        sc_name = self.rig.leg[leg][0]
        Wsc0 = self.S.child_world(W, sc_name, Matrix.Identity(4))
        S_top = Wsc0.translation
        SH0 = Wsc0 @ V(0, self.rig.length[sc_name], 0)
        ang = signed_angle(V(0, 0, -1), (F - SH0), n)
        return S_top + rot(n, 0.30 * ang) @ (SH0 - S_top)

    def stance_params(self, sc, leg, stt):
        """fetlock load (extension) and breakover (heel lift about the toe) for a stance state"""
        if stt[4] < 0:
            return 0.0, 0.0
        s = stt[2]
        load = sc.load[leg[0]] * math.sin(math.pi * s)
        b0 = sc.breakover_start
        return load, sc.breakover * smooth((s - b0) / (1 - b0)) ** 1.3

    def leg_state(self, sc, leg, t):
        """returns ('stance', toe, s_in_stance, stance_len) or ('swing', lift_toe, land_toe, s, swing duration) or ('free', ...)"""
        st = sc.stances[leg]
        if not st:
            return ("free",)
        for i, (tl, tu, p) in enumerate(st):
            if tl <= t <= tu:
                return ("stance", p, (t - tl) / max(tu - tl, 1e-6), tu - tl, i)
        prev = [s for s in st if s[1] < t]
        nxt = [s for s in st if s[0] > t]
        if prev and nxt:
            a, b = prev[-1], nxt[0]
            return ("swing", a[2], b[2], (t - a[1]) / max(b[0] - a[1], 1e-6), b[0] - a[1])
        if prev:
            return ("stance", prev[-1][2], 1.0, 1.0, -1)       # stays planted after the last step
        return ("stance", nxt[0][2], 0.0, 1.0, -1)              # planted before the first step

    def distal_stance(self, leg, toe, yaw_q, load, brk):
        """bottom-up from a planted toe: coronet, fetlock (horse-space rotation yaw_q applied to rest vectors)"""
        D = self.distal[leg]
        pts = self.rest[leg]
        n = yaw_q @ V(1, 0, 0)
        h0 = yaw_q @ (pts[-1] - pts[-2])            # coronet -> toe
        h = rot(n, -self.flex_sign * brk) @ h0 if brk else h0
        C = toe - h
        p0 = yaw_q @ (pts[-2] - pts[-3])            # fetlock -> coronet
        # rest pastern relative to the rest hoof, then the load extends the fetlock (pastern more horizontal)
        p = rot(n, -self.flex_sign * brk) @ p0 if brk else p0.copy()
        p = rot(n, self.flex_sign * load) @ p
        F = C - p
        return F, C

    def solve_leg(self, sc, leg, t, W, yaw_q, basis):
        R = self.rig
        names = R.leg[leg]
        fore = leg[0] == "F"
        D = self.distal[leg]
        n = yaw_q @ V(1, 0, 0)
        fwd = yaw_q @ V(0, -1, 0)
        ov = sc.leg_override.get(leg)
        o = ov(t) if ov else None
        stt = self.leg_state(sc, leg, t)
        flex = fflex = cflex = 0.0
        C = toe = None
        if o is not None and "toe" in o:
            # scripted planted / resting hoof (e.g. a cocked hind resting on its toe)
            toe = o["toe"]
            F, C = self.distal_stance(leg, toe, yaw_q, o.get("load", 0.0), o.get("hoof_pitch", 0.0))
            flex = o.get("flex", 0.0)
            mode = "stance"
        elif stt[0] == "stance":
            toe = stt[1].copy()
            load, brk = self.stance_params(sc, leg, stt)
            F, C = self.distal_stance(leg, toe, yaw_q, load, brk)
            mode = "stance"
        elif stt[0] == "free":
            pbn = "chest" if fore else "hips"
            drot = W[pbn].to_3x3() @ self.rig.L[pbn].to_3x3().inverted()
            top0 = self.rest[leg][1] if fore else self.rest[leg][0]
            if fore:
                top = self.S.child_world(W, names[0], Matrix.Identity(4)) @ V(0, self.rig.length[names[0]], 0)
            else:
                top = self.S.child_world(W, names[0], Matrix.Identity(4)).translation
            F = top + drot @ (self.rest[leg][-3] - top0)
            mode = "free"
        else:
            _, a, b, s, dur = stt
            # fetlock path: from the lift-off fetlock to the landing fetlock, arc up, quick first half
            Fa, _ = self.distal_stance(leg, a, yaw_q, 0.0, sc.breakover)
            Fb, _ = self.distal_stance(leg, b, yaw_q, 0.0, 0.0)
            u = smoother(min(1.0, s * 1.08))
            F = Fa.lerp(Fb, u)
            hgt = sc.swing_h[leg] * math.sin(math.pi * min(1.0, s ** 0.85)) ** 1.2
            F += V(0, 0, hgt)
            # a little inward tracking at mid swing
            F += n * (-math.copysign(1, (F - W["root"].translation).dot(n)) * 0.02 * math.sin(math.pi * s))
            pk = 0.38 if fore else 0.42
            env = math.sin(math.pi * min(1.0, s / (2 * pk))) if s < pk else math.cos(0.5 * math.pi * min(1.0, (s - pk) / (0.86 - pk)))
            env = max(0.0, env)
            flex = sc.flex[leg[0]] * env
            fflex = sc.fetlock_flex[leg[0]] * max(0.0, math.sin(math.pi * min(1.0, s / 0.8))) ** 0.9
            cflex = 0.35 * max(0.0, math.sin(math.pi * min(1.0, s / 0.8)))
            mode = "swing"
            # continuity at lift-off and touch-down: the distal chain starts from the broken-over hoof and ends flat on the
            # landing hoof (both carried along with the fetlock), blended with the free top-down swing shape
            Fa2, Ca2 = self.distal_stance(leg, a, yaw_q, 0.0, sc.breakover)
            Fb2, Cb2 = self.distal_stance(leg, b, yaw_q, 0.0, 0.0)
            swing_ends = (smooth(1.0 - s / 0.22), Ca2 - Fa2, a - Fa2, smooth((s - 0.80) / 0.20), Cb2 - Fb2, b - Fb2)
        wfree = 0.0
        if o is not None and "rel" in o:
            # free leg posed relative to the body (rear, buck, jump, swim, fall), blended in by o["w"] (default 1)
            wfree = max(0.0, min(1.0, o.get("w", 1.0)))
            pbn = "chest" if fore else "hips"
            drot = W[pbn].to_3x3() @ self.rig.L[pbn].to_3x3().inverted()
            if fore:
                top = self.S.child_world(W, names[0], Matrix.Identity(4)) @ V(0, self.rig.length[names[0]], 0)
            else:
                top = self.S.child_world(W, names[0], Matrix.Identity(4)).translation
            Ff = top + drot @ o["rel"]
            F = F.lerp(Ff, wfree)
            flex = lerp(flex, o.get("flex", 0.0), wfree)
            ff_free, cf_free = o.get("fflex", 0.0), o.get("cflex", 0.0)
            if wfree >= 0.5:
                mode = "free"
        else:
            ff_free = cf_free = 0.0
        # ---- upper leg
        if fore:
            sc_name, hu, fa, ca, pa, ho = names
            # scapula swing follows the limb angle (protraction when the hoof is forward)
            SH = self.fore_SH(W, leg, F, n)
            Msc = self.S.aim(W, sc_name, SH)
            W[sc_name] = Msc
            basis[sc_name] = self.S.basis_from_world(W, sc_name, Msc)
            a = self.rig.length[hu]
            b = self.rig.length[fa]
            c = self.rig.length[ca]
            kap = flex
            vlen = math.sqrt(max(1e-6, b * b + c * c + 2 * b * c * math.cos(kap)))
            E, over = ik2(SH, F, a, vlen, (yaw_q @ V(0, 1, 0)))         # elbow points back
            K, _ = ik2(E, F, b, c, fwd)                                  # knee bulges forward when flexed
            if kap < 1e-3:
                K = E + (F - E).normalized() * b
            chain = [(hu, E), (fa, K), (ca, F)]
        else:
            th_name, ga, ca, pa, ho = names
            HJ = self.S.child_world(W, th_name, Matrix.Identity(4)).translation
            a = self.rig.length[th_name]
            b = self.rig.length[ga]
            c = self.rig.length[ca]
            pts = self.rest[leg]
            hock0 = math.pi - (pts[2] - pts[1]).angle(pts[3] - pts[2]) if False else (pts[2] - pts[1]).angle(pts[3] - pts[2])
            kap = hock0 + flex + (sc.load["H"] * 0.6 * (1.0 if mode == "stance" else 0.0))
            vlen = math.sqrt(max(1e-6, b * b + c * c + 2 * b * c * math.cos(kap)))
            need = (F - HJ).length - a + 0.004
            if mode == "stance" and need > vlen:
                kmin = math.radians(6)
                vmax = math.sqrt(b * b + c * c + 2 * b * c * math.cos(kmin))
                vlen = min(need, vmax)
                kap = math.acos(max(-1.0, min(1.0, (vlen * vlen - b * b - c * c) / (2 * b * c))))
            ST, over = ik2(HJ, F, a, vlen, fwd)                          # stifle forward
            H, _ = ik2(ST, F, b, c, (yaw_q @ V(0, 1, 0)))                # hock back
            chain = [(th_name, ST), (ga, H), (ca, F)]
        for nm, tgt in chain:
            M = self.S.aim(W, nm, tgt)
            W[nm] = M
            basis[nm] = self.S.basis_from_world(W, nm, M)
        # ---- distal (planted: bottom-up targets; swing/free: top-down from the cannon with fetlock/coffin flexion)
        cdir = (F - W[chain[-1][0]].translation).normalized()

        def topdown(ff, cf):
            p = rot(n, D["a_cp"] + self.flex_sign * ff) @ cdir
            Cq = F + p * D["lp"]
            hq = rot(n, D["a_ph"] + self.flex_sign * cf) @ p
            return Cq, Cq + hq * D["lh"]
        if C is not None:
            Cb, Tb = C, toe
        else:
            Cb, Tb = topdown(fflex, cflex)
            if mode == "swing":
                wa, dCa, dTa, wb, dCb, dTb = swing_ends
                if wa > 0:
                    Cb, Tb = Cb.lerp(F + dCa, wa), Tb.lerp(F + dTa, wa)
                if wb > 0:
                    Cb, Tb = Cb.lerp(F + dCb, wb), Tb.lerp(F + dTb, wb)
        if wfree > 0.0:
            Cf, Tf = topdown(ff_free, cf_free)
            Cb, Tb = Cb.lerp(Cf, wfree), Tb.lerp(Tf, wfree)
        M = self.S.aim(W, pa, Cb)
        W[pa] = M
        basis[pa] = self.S.basis_from_world(W, pa, M)
        M = self.S.aim(W, ho, Tb)
        W[ho] = M
        basis[ho] = self.S.basis_from_world(W, ho, M)
        toe_now = W[ho] @ V(0, self.rig.length[ho], 0)
        return over, toe_now, mode

    # ---------------- one frame
    def evaluate(self, sc, t, sec=None, dbg=None):
        R = self.rig
        S = self.S
        W, basis = {}, {}
        rp = sc.root_pos(t)
        yaw = sc.root_yaw(t)
        yq = rot(UP, yaw)
        RF = Matrix.Translation(rp) @ yq.to_matrix().to_4x4()
        # root
        W["root"] = RF @ R.L["root"]
        basis["root"] = R.L["root"].inverted() @ RF @ R.L["root"]
        body_extra = V(0, 0, 0)
        pitch_extra = 0.0
        fixed = sc.support_fixed(t) if sc.support_fixed else None
        if fixed is not None:
            body_extra = V(0, 0, fixed[0])
            pitch_extra = fixed[1]
        for it in range(3 if (sc.support and fixed is None) else 1):
            off = sc.body_off(t) + body_extra
            br = sc.body_rot(t) + V(pitch_extra, 0, 0)
            Mb = Matrix.Translation(sc.pivot + off) @ q_pry(br).to_matrix().to_4x4() @ Matrix.Translation(-sc.pivot)
            B = R.L["hips"].inverted() @ Mb @ R.L["hips"]
            W["hips"] = RF @ R.L["hips"] @ B
            basis["hips"] = B
            sp = sc.spine(t)
            for n_, w in zip(SPINE[1:], SPINE_W[1:]):
                q = q_pry(sp * w)
                bq = S.rot_basis(n_, q, W).to_matrix().to_4x4()
                W[n_] = S.child_world(W, n_, bq)
                basis[n_] = bq
            if not sc.support or fixed is not None:
                break
            # stance legs that cannot reach: lower that end of the body
            need = {}
            for leg in LEGS:
                stt = self.leg_state(sc, leg, t)
                if stt[0] != "stance" or (sc.leg_override.get(leg) and sc.leg_override[leg](t) is not None):
                    continue
                F, C = self.distal_stance(leg, stt[1], yq, *self.stance_params(sc, leg, stt))
                if leg[0] == "F":
                    SH = self.fore_SH(W, leg, F, yq @ V(1, 0, 0))
                    reach = R.length[R.leg[leg][1]] + R.length[R.leg[leg][2]] + R.length[R.leg[leg][3]] - 0.012
                    d = (F - SH).length
                else:
                    HJ = S.child_world(W, R.leg[leg][0], Matrix.Identity(4)).translation
                    pts = self.rest[leg]
                    hock0 = math.radians(6)
                    b, c = R.length[R.leg[leg][1]], R.length[R.leg[leg][2]]
                    reach = R.length[R.leg[leg][0]] + math.sqrt(b * b + c * c + 2 * b * c * math.cos(hock0)) - 0.012
                    d = (F - HJ).length
                if dbg is not None:
                    dbg.append((leg, round(d - reach, 3)))
                if d > reach:
                    need[leg[0]] = max(need.get(leg[0], 0.0), d - reach)
            if not need:
                break
            dF, dH = need.get("F", 0.0), need.get("H", 0.0)
            body_extra = body_extra + V(0, 0, -(dF + dH) * 0.5 - 0.002)
            pitch_extra += (dF - dH) / 1.4
            body_extra.z = max(body_extra.z, -sc.support_max)
            pitch_extra = max(-0.08, min(0.08, pitch_extra))
        # neck & head
        nk = sc.neck(t)
        for n_, w in zip(NECK, sc.neck_w):
            bq = S.rot_basis(n_, q_pry(nk * w), W).to_matrix().to_4x4()
            W[n_] = S.child_world(W, n_, bq)
            basis[n_] = bq
        hq = S.rot_basis("head", q_pry(sc.head(t)), W).to_matrix().to_4x4()
        W["head"] = S.child_world(W, "head", hq)
        basis["head"] = hq
        jq = S.rot_basis("jaw", rot(V(1, 0, 0), sc.jaw(t)), W).to_matrix().to_4x4()
        W["jaw"] = S.child_world(W, "jaw", jq)
        basis["jaw"] = jq
        e = sc.ears(t)
        for s, pitch, yw in (("L", e[0], e[1]), ("R", e[2], -e[3])):
            q = rot(UP, yw) @ rot(V(1, 0, 0), -pitch)
            bq = S.rot_basis("ear_1_" + s, q, W).to_matrix().to_4x4()
            W["ear_1_" + s] = S.child_world(W, "ear_1_" + s, bq)
            basis["ear_1_" + s] = bq
            bq = S.rot_basis("ear_2_" + s, rot(V(1, 0, 0), -pitch * 0.3), W).to_matrix().to_4x4()
            W["ear_2_" + s] = S.child_world(W, "ear_2_" + s, bq)
            basis["ear_2_" + s] = bq
        bq = S.rot_basis("belly", q_pry(sc.belly(t)), W).to_matrix().to_4x4()
        W["belly"] = S.child_world(W, "belly", bq)
        basis["belly"] = bq
        # legs
        info = {}
        for leg in LEGS:
            info[leg] = self.solve_leg(sc, leg, t, W, yq, basis)
        # tail + mane FK targets (the secondary pass replaces them)
        # tail: tail_base pitch + = carried back/up (the rest tail hangs), lift spread over the dock
        tb = sc.tail_base(t)
        lift = sc.tail_lift(t)
        for i, n_ in enumerate(TAIL):
            w = (0.55, 0.25, 0.12, 0.05, 0.03)[i]
            wl = (0.50, 0.30, 0.12, 0.05, 0.03)[i]
            v = tb * w + V(lift * wl, 0, 0)
            bq = S.rot_basis(n_, q_pry(v), W).to_matrix().to_4x4()
            W[n_] = S.child_world(W, n_, bq)
            basis[n_] = bq
        # rein grips: the rider's following hand gives with the horse's mouth (a fraction of the bit's motion relative to the
        # withers), plus optional script offsets (rein turns, stop pull)
        bit_rest = self.rig.head0["bit"]
        Wb = S.child_world(W, "bit", Matrix.Identity(4))
        Ww = W["withers"]
        rel = Ww.inverted() @ Wb.translation - self.rig.L["withers"].inverted() @ bit_rest
        for s_, sx in (("L", 1), ("R", -1)):
            n_ = "rein_grip_" + s_
            ra = self.rig.L["withers"].to_3x3() @ rel          # horse axes
            off = V(ra.x * 0.15, ra.y * 0.35, ra.z * 0.25) + sc.rein(t, s_)
            B0 = Matrix.Translation(self.rig.L[n_].to_3x3().inverted() @ off)
            W[n_] = S.child_world(W, n_, B0)
            basis[n_] = B0
        # everything not posed yet: identity basis (mane, sockets)
        for n_ in R.order:
            if n_ not in W:
                W[n_] = S.child_world(W, n_, Matrix.Identity(4))
                basis[n_] = Matrix.Identity(4)
        info["_support"] = (body_extra.z, pitch_extra)
        return W, basis, info


# ------------------------------------------------------------------ secondary motion (spring chains)
CHAINS = [TAIL] + [["mane_%d_a" % i, "mane_%d_b" % i] for i in range(0, 6)]
# k: spring toward the animated (FK) point (1/s^2), zeta: damping ratio, drag: air drag (1/s), grav: extra sag (m/s^2)
CHAIN_P = {"tail": dict(k=140.0, zeta=0.35, drag=3.2, grav=1.5), "mane": dict(k=420.0, zeta=0.45, drag=1.6, grav=1.0)}


def simulate_secondary(eng, sc, frames_W, dt, sub=6):
    """Spring-damper particles on each chain's joints (world), pulled toward the animated pose, pushed by the air stream
    (still air: the horse's own velocity makes the wind), length-constrained. Returns per frame {bone: tail point}."""
    out = [dict() for _ in frames_W]
    h = dt / sub
    for chain in CHAINS:
        kind = "tail" if chain[0].startswith("tail") else "mane"
        P = CHAIN_P[kind]
        k = P["k"]; c = 2.0 * P["zeta"] * math.sqrt(k)
        lens = [eng.rig.length[n] for n in chain]
        pts = vel = None
        prev_anim = None
        for fi, W in enumerate(frames_W):
            anim = [W[chain[0]].translation.copy()] + [W[n] @ V(0, eng.rig.length[n], 0) for n in chain]
            if pts is None:
                pts = [p.copy() for p in anim]
                vel = [V(0, 0, 0) for _ in anim]
                prev_anim = [p.copy() for p in anim]
            avel = [(a - b) / dt for a, b in zip(anim, prev_anim)]
            air = sc.wind(fi / FPS)
            for si in range(sub):
                w = (si + 1) / sub
                tgt = [pa.lerp(a, w) for pa, a in zip(prev_anim, anim)]
                pts[0] = tgt[0]
                vel[0] = avel[0]
                for i in range(1, len(pts)):
                    acc = (tgt[i] - pts[i]) * k - (vel[i] - avel[i]) * c + (air - vel[i]) * P["drag"] + V(0, 0, -P["grav"])
                    vel[i] = vel[i] + acc * h
                    pts[i] = pts[i] + vel[i] * h
                for i in range(1, len(pts)):
                    d = pts[i] - pts[i - 1]
                    if d.length > 1e-6:
                        np_ = pts[i - 1] + d.normalized() * lens[i - 1]
                        vel[i] = vel[i] + (np_ - pts[i]) / h * 0.0
                        pts[i] = np_
            prev_anim = anim
            for i, n in enumerate(chain):
                out[fi][n] = pts[i + 1].copy()
    return out
