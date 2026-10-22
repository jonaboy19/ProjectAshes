"""Pose engine for the wolf clips: frame description -> pose-bone basis (via wrig), plus planted-foot gait utilities.
Coordinates: ground/armature frame in RIG UNITS (Z up, forward = -Y, left = +X). World 2D helper coords are (F, L) = (forward, left)
in METRES; body frame at time t = world rotated by heading psi (left turn positive) and translated by c(t).
"""
import math
import numpy as np
from mathutils import Vector, Quaternion, Matrix
from wrig import WRig, yaw, pitch, roll, rot_about

SPINE_CHAIN = ["Back", "Torso", "Torso2", "Torso3", "Neck1", "Neck2", "Neck3", "Head"]
TAIL = [f"Tail{i}" for i in range(1, 9)]
NECK_W = {"Neck1": 0.22, "Neck2": 0.30, "Neck3": 0.30, "Head": 0.18}
LEGS = ("FL", "FR", "BL", "BR")


def clamp(x, a=0.0, b=1.0):
    return max(a, min(b, x))


def sstep(x):
    x = clamp(x)
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


class Track:
    """Smooth 1-D curve through (t, v) keys (cardinal Hermite, zero end tangents; ease=True -> flat tangents at every key)."""
    def __init__(self, keys, ease=False, loop=None):
        self.k = sorted(keys)
        self.ease = ease
        self.loop = loop
        ts = [a for a, _ in self.k]
        vs = [b for _, b in self.k]
        n = len(ts)
        self.t = ts
        self.v = vs
        self.m = [0.0] * n
        if not ease:
            for i in range(n):
                if 0 < i < n - 1:
                    self.m[i] = (vs[i + 1] - vs[i - 1]) / (ts[i + 1] - ts[i - 1])

    def __call__(self, t):
        if self.loop:
            t = t % self.loop
        ts, vs = self.t, self.v
        if t <= ts[0]:
            return vs[0]
        if t >= ts[-1]:
            return vs[-1]
        i = max(j for j in range(len(ts) - 1) if ts[j] <= t)
        h = ts[i + 1] - ts[i]
        x = (t - ts[i]) / h
        if self.ease:
            return lerp(vs[i], vs[i + 1], sstep(x))
        x2, x3 = x * x, x * x * x
        return ((2 * x3 - 3 * x2 + 1) * vs[i] + (x3 - 2 * x2 + x) * h * self.m[i]
                + (-2 * x3 + 3 * x2) * vs[i + 1] + (x3 - x2) * h * self.m[i + 1])


class Engine:
    def __init__(self, arm, sole0, paw_verts):
        self.arm = arm
        self.pv = {k: np.array(v, dtype=np.float64) for k, v in paw_verts.items()}      # rest paw vertex cloud, rig units
        self.cen = {k: self.pv[k].mean(0) for k in LEGS}
        self.zmin0 = {k: self.pv[k][:, 2].min() for k in LEGS}
        self.R = WRig(arm)
        R = self.R
        self.s = R.s
        self.sole0 = sole0            # rig units the rest sole sits above z=0 is subtracted from paw targets
        self.home = {}
        for k in LEGS:
            endb = ("IKFrontLeg." if k[0] == "F" else "IKBackLeg.") + k[1]
            h = R.head[endb].copy()
            self.home[k] = h
        self.pz = {k: 0.0 for k in LEGS}
        self.cen_xy = {k: (self.cen[k][0], self.cen[k][1]) for k in LEGS}
        self.blade_pivot = {}
        for k in ("FL", "FR"):
            b = R.head["FrontShoulder." + k[1]]
            self.blade_pivot[k] = Vector((b.x * 0.4, b.y, 1.92))

    # unit helpers
    def u(self, m):
        return m / self.s

    def to_arm(self, f, l, z=None):
        """body-frame (forward, left) metres -> armature xy (rig units) ; z in rig units"""
        return Vector((self.u(l), -self.u(f), 0.0 if z is None else z))

    # ------------------------------------------------------------------------------------
    def pose(self, F):
        """F: dict describing the frame. keys (all optional):
        dz (m, +up), dx_f/dx_l (body shift fwd/left, m), bp/br/byaw (body pitch nose-down / roll left / yaw left, rad, about COM)
        spine: {bone: (yaw, pitch, roll)}, neck: (yaw, pitch) distributed over Neck1..Head, head: (yaw, pitch, roll) extra on Head
        tail: list of 8 (yaw, pitch) or (yaw, pitch) for all, blade: {'FL': angle, 'FR': angle}
        paw: {leg: (Vector target in armature space, foot_dir_angle)}    -> IK
        returns (basis dict, max IK miss in rig units)"""
        R = self.R
        rots = {}
        trans = {}
        g = F.get
        q = yaw(g('byaw', 0.0)) @ pitch(g('bp', 0.0)) @ roll(g('br', 0.0))
        rots['Body'] = (q, R.com)
        trans['Body'] = Vector((self.u(g('dx_l', 0.0)), -self.u(g('dx_f', 0.0)), self.u(g('dz', 0.0))))
        for b, (a_y, a_p, a_r) in g('spine', {}).items():
            piv = R.pelvis if b == "Back" else R.head[b]
            rots[b] = (yaw(a_y) @ pitch(a_p) @ roll(a_r), piv)
        ny, np_ = g('neck', (0.0, 0.0))
        for b, w in NECK_W.items():
            a = rots.get(b)
            qn = yaw(ny * w) @ pitch(np_ * w)
            if a is not None:
                qn = a[0] @ qn
            rots[b] = (qn, R.head[b])
        hy, hp, hr = g('head', (0.0, 0.0, 0.0))
        if hy or hp or hr:
            q0 = rots["Head"][0]
            rots["Head"] = (q0 @ yaw(hy) @ pitch(hp) @ roll(hr), R.head["Head"])
        tl = g('tail', None)
        if tl is not None:
            for i, b in enumerate(TAIL):
                a = tl[i] if isinstance(tl[0], (tuple, list)) else tl
                rots[b] = (yaw(a[0]) @ pitch(a[1]), R.head[b])
        for k, a in g('blade', {}).items():
            rots["FrontShoulder." + k[1]] = (pitch(a), self.blade_pivot[k])
        for k, (ang) in g('pelvis_hip', {}).items():          # hind hip drop/raise per side (roll about the pelvis)
            rots["BackShoulder." + k[1]] = (pitch(ang), R.head["BackShoulder." + k[1]])
        for b, m in g('own', {}).items():                    # measured source pose (matrices) with the extras above composed on top
            if b in rots:
                q, piv = rots[b] if isinstance(rots[b], tuple) else (rots[b], R.head[b])
                m = rot_about(q, piv) @ m
            rots[b] = m
        for b, m in g('own_leg', {}).items():
            if b not in rots: rots[b] = m
        A = R.fk(rots, trans)
        miss = 0.0
        for k, (tgt, fda) in g('paw', {}).items():
            fd = None
            if isinstance(fda, Vector):
                fd = fda
            elif k[0] == "B":
                J = R.leg[k]["joints"]
                fd0 = (J[2] - J[3]).normalized()
                fd = Quaternion((1, 0, 0), fda) @ fd0
            endb = ("IKFrontLeg." if k[0] == "F" else "IKBackLeg.") + k[1]
            P0 = R.head[endb]
            off = Vector((P0.x - self.cen[k][0], P0.y - self.cen[k][1], P0.z - self.zmin0[k]))      # paw joint minus (centroid xy, sole z)
            anchor = Vector(tgt)                                                                     # wanted: centroid xy + sole z
            Pt = anchor + off
            lower = R.leg[k]["chain"][-1]
            for it in range(4):
                rr = dict(rots)
                _pos, e = R.solve_leg(k, A, rr, Pt, foot_dir=fd)
                # actual paw cloud under this leg pose
                Al = R.fk(rr, trans)[lower]
                M = np.array(Al)
                Q = self.pv[k] @ M[:3, :3].T + M[:3, 3]
                cen = Q.mean(0)
                dxy = Vector((anchor.x - cen[0], anchor.y - cen[1], anchor.z - Q[:, 2].min()))
                Pt = Pt + dxy
                if dxy.length < 1e-4:
                    break
            wk = g('paw_w', {}).get(k, 1.0)
            for b in R.leg[k]["chain"][1:]:
                q, piv = rr[b]
                m_ik = rot_about(q, piv)
                if wk < 0.999 and b in g('own_leg', {}):
                    m_src = g('own_leg')[b]
                    l0, q0, _ = m_src.decompose()
                    l1, q1, _ = m_ik.decompose()
                    qq = q0.slerp(q1, wk)
                    m_ik = Matrix.Translation(l0.lerp(l1, wk)) @ qq.to_matrix().to_4x4()
                rots[b] = m_ik
            miss = max(miss, dxy.length)
        A = R.fk(rots, trans)
        return R.basis(A), miss


# ----------------------------------------------------------------------------------------
class World:
    """Body trajectory in the world: heading psi(t) (rad, left +) and position c(t)=(F,L) metres, from body-frame velocity
    (vf, vl) and yaw-rate (numbers or functions of t), integrated numerically from t_min. World coordinates are arbitrary rigid
    frames: only the body-relative foot positions and the root motion (relative to t=0) matter."""
    def __init__(self, vf, vl, omega, t_min, t_max, dt=1 / 600.0):
        n = int(round((t_max - t_min) / dt)) + 2
        self.dt, self.t_min = dt, t_min
        self.t = t_min + np.arange(n) * dt
        vf_a = np.array([vf(x) if callable(vf) else vf for x in self.t])
        vl_a = np.array([vl(x) if callable(vl) else vl for x in self.t])
        om_a = np.array([omega(x) if callable(omega) else omega for x in self.t])
        psi = np.zeros(n)
        cF = np.zeros(n)
        cL = np.zeros(n)
        for i in range(1, n):
            psi[i] = psi[i - 1] + om_a[i - 1] * dt
            pm = 0.5 * (psi[i] + psi[i - 1])
            cF[i] = cF[i - 1] + (math.cos(pm) * vf_a[i - 1] - math.sin(pm) * vl_a[i - 1]) * dt
            cL[i] = cL[i - 1] + (math.sin(pm) * vf_a[i - 1] + math.cos(pm) * vl_a[i - 1]) * dt
        self.psi, self.cF, self.cL = psi, cF, cL

    def at(self, t):
        f = (t - self.t_min) / self.dt
        i = int(min(max(f, 0), len(self.t) - 2))
        a = f - i
        return (self.psi[i] * (1 - a) + self.psi[i + 1] * a, self.cF[i] * (1 - a) + self.cF[i + 1] * a,
                self.cL[i] * (1 - a) + self.cL[i + 1] * a)

    def to_body(self, t, QF, QL):
        psi, cF, cL = self.at(t)
        dF, dL = QF - cF, QL - cL
        c, s = math.cos(psi), math.sin(psi)
        return (c * dF + s * dL, -s * dF + c * dL)          # rotate by -psi

    def from_body(self, t, bF, bL):
        psi, cF, cL = self.at(t)
        c, s = math.cos(psi), math.sin(psi)
        return (cF + c * bF - s * bL, cL + s * bF + c * bL)

    def root_motion(self, t):
        """game-space root motion at t relative to t=0: (forward m, left m, heading rad) in the frame of the body at t=0"""
        p0, f0, l0 = self.at(0.0)
        psi, cF, cL = self.at(t)
        dF, dL = cF - f0, cL - l0
        c, s = math.cos(p0), math.sin(p0)
        return (c * dF + s * dL, -s * dF + c * dL, psi - p0)


class Step:
    """one planted period of one foot: lands at t0 at world (F,L) Q and lifts at t1; the swing goes to the next Step's t0"""
    def __init__(self, t0, t1, Q):
        self.t0, self.t1, self.Q = t0, t1, Q


def foot_path(steps, t, lift_m, ang_swing=(0.5, 0.7)):
    """world (F, L, height m, foot_dir angle) of a foot at t. Before the first / after the last Step the plant holds."""
    st = steps[0]
    if t < st.t1:
        return st.Q[0], st.Q[1], 0.0, 0.0
    for i, st in enumerate(steps):
        nxt = steps[i + 1] if i + 1 < len(steps) else None
        if t < st.t1:
            return st.Q[0], st.Q[1], 0.0, 0.0
        if nxt is None:
            return st.Q[0], st.Q[1], 0.0, 0.0
        if t < nxt.t0:
            u = (t - st.t1) / (nxt.t0 - st.t1)
            e = sstep(u)
            hh = lift_m * math.sin(math.pi * clamp(u ** 0.85))
            ang = ang_swing[0] * math.sin(2 * math.pi * u) * (1.0 if u < 0.5 else ang_swing[1])
            return lerp(st.Q[0], nxt.Q[0], e), lerp(st.Q[1], nxt.Q[1], e), hh, ang
    return steps[-1].Q[0], steps[-1].Q[1], 0.0, 0.0


def periodic_steps(world, T, beta, phase, home_fl, t_end, t_start=None):
    """Steps of one foot for a periodic gait: touchdown at (n+phase)*T, stance lasts beta*T, planted so that at mid-stance the foot
    is at body-frame `home_fl` = (forward, left) metres."""
    steps = []
    n = -4
    while True:
        t0 = (n + phase) * T
        if t0 > t_end + 2 * T:
            break
        tm = t0 + beta * T * 0.5
        Q = world.from_body(tm, home_fl[0], home_fl[1])
        steps.append(Step(t0, t0 + beta * T, Q))
        n += 1
    return steps
