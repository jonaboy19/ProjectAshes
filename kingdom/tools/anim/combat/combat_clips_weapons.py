# Weapon attack clips: 1H sword + shield heavy charge / release / run attack, two-hander overhead chop, spear thrust combo.
# World axes: character faces -Y, +Z up, +X = character's LEFT. 30 fps. Feet IK-pinned unless a key moves them.
#
# Authoring style: every frame is generated from per-channel waypoint tracks (a tiny key-pose engine on top of
# author_combat.build), so the kinetic chain (hips -> chest -> arm -> hand -> blade) is set by giving each channel its own
# key frames. Hands / blade are keyed in the TORSO frame (they turn with the chest) unless a clip needs a straight line in
# the world (spear thrusts: channels HR / BD). The blade edge is derived per frame from the tip velocity (edge leads).
#
# Channels (all optional, default = ready_pose): pel (pelvis world offset, incl. travel), T (root travel, m forward),
# hip/tor/head (deg), hr/hl (wrist, torso frame: out-left, fwd, world z), HR (wrist world), bd (blade dir, torso frame),
# BD (blade dir world), fl/fr (ankle world), fyl/fyr (foot yaw), cl/cr (curl), er/el (elbow offset from shoulder-hand midpoint,
# torso frame), sl (left-hand distance along the shaft from the right hand, for 2h/spear).
# Waypoint: (frame, value[, ease[, bow]]). ease describes the segment ARRIVING at the key; bow = arc bulge offset.
import math
from mathutils import Vector, Matrix
import combat_common as CC
from combat_common import clip, V, TF, rel, ready_pose

N = ready_pose()
DIRS = ("bd", "BD")
SH0 = {"l": Vector((0.192, 0.065, 1.441)), "r": Vector((-0.192, 0.065, 1.441))}
PEL0 = Vector((0, 0.05, 0.917))


def _nrm(v):
    return tuple(Vector(v).normalized())


def sm(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def _slerp(a, b, t):
    a = Vector(a).normalized()
    b = Vector(b).normalized()
    d = max(-1.0, min(1.0, a.dot(b)))
    if d > 0.9995:
        return a.lerp(b, t).normalized()
    if d < -0.999:
        p = a.cross(Vector((0, 0, 1)))
        if p.length < 1e-3:
            p = a.cross(Vector((1, 0, 0)))
        p.normalize()
        b = p
        d = 0.0
    th = math.acos(d)
    return (a * math.sin((1 - t) * th) + b * math.sin(t * th)).normalized()


def _lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    if isinstance(a, Vector):
        return a.lerp(b, t)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def _add(a, b, w):
    if isinstance(a, Vector):
        return a + Vector(b) * w
    return tuple(x + y * w for x, y in zip(a, b))


def ev(ws, f, name=""):
    if callable(ws):
        return ws(f)
    if not isinstance(ws, list):
        return ws
    if f <= ws[0][0]:
        return ws[0][1]
    if f >= ws[-1][0]:
        return ws[-1][1]
    for i in range(len(ws) - 1):
        a, b = ws[i], ws[i + 1]
        if a[0] <= f <= b[0]:
            kind = b[2] if len(b) > 2 and b[2] else "smooth"
            bow = b[3] if len(b) > 3 else None
            t = CC.F._ease(kind, (f - a[0]) / float(b[0] - a[0]))
            if name in DIRS:
                v = _slerp(a[1], b[1], t)
                if bow is not None:
                    v = (Vector(v) + Vector(bow) * math.sin(math.pi * t)).normalized()
                return tuple(v)
            v = _lerp(a[1], b[1], t)
            if bow is not None:
                v = _add(v, bow, math.sin(math.pi * t))
            return v
    return ws[-1][1]


def READY():
    return dict(pel=V(0, 0, 0), hip=(0.0, 0.0, 0.0), tor=(4.0, 0.0, 0.0), head=(0.0, 0.0, 0.0),
                hr=(-0.27, 0.145, 0.90), hl=(0.27, 0.125, 0.88), bd=_nrm((0.25, 0.85, 0.45)),
                fl=V(0.13, 0.02, 0.104), fr=V(-0.13, 0.06, 0.104), fyl=6.0, fyr=-10.0, fpl=0.0, fpr=0.0,
                cl=0.5, cr=0.9, er=(-0.35, -0.25, -0.30), el=(0.35, -0.25, -0.30), T=0.0, sl=0.5, lw=1.0)


def _frame_lh(bd, n_pal):
    """left-hand grip on a shaft: thumb along the shaft (toward the tip), palm normal n_pal (perp to shaft)"""
    t = Vector(bd).normalized()
    n = Vector(n_pal)
    n = (n - t * n.dot(t)).normalized()
    f = t.cross(n)
    return (tuple(f), tuple(n))


def compute(n, ch, tip_len=0.75, lhand=None, edge="auto", nstart=None, nend=None, nanch=None, nrot=None, post=None):
    """per-frame states from channel tracks"""
    D = READY()
    out = []
    for f in range(n + 1):
        s = {}
        for k in list(D.keys()) + [k for k in ch if k not in D]:
            s[k] = ev(ch.get(k, D.get(k)), f, k)
        s["_f"] = f
        if post:
            post(f, s)
        yaw = s["hip"][1] + s["tor"][1]
        s["yaw"] = yaw
        P = Vector(s["pel"])
        s["P"] = P
        s["root"] = V(0, -s["T"], 0)
        if "HR" in s:
            hr = Vector(s["HR"])
        else:
            hr = rel(s["hr"][0], s["hr"][1], s["hr"][2], yaw, (P.x, P.y))
        s["hrw"] = hr
        if "BD" in s:
            bd = Vector(s["BD"]).normalized()
        else:
            bd = Vector(TF(s["bd"][0], s["bd"][1], s["bd"][2], yaw)).normalized()
        s["bdw"] = bd
        out.append(s)
    # blade flat normal
    if edge == "auto":
        tips = [s["hrw"] + s["bdw"] * tip_len for s in out]
        ns = [None] * (n + 1)
        for f in range(n + 1):
            v = tips[min(f + 1, n)] - tips[max(f - 1, 0)]
            c = out[f]["bdw"].cross(v)
            if c.length > 0.03:
                ns[f] = c.normalized()
        first = next((i for i, x in enumerate(ns) if x is not None), None)
        if first is None:
            ns = [Vector((1, 0, 0))] * (n + 1)
        else:
            for f in range(first):
                ns[f] = ns[first]
            for f in range(first + 1, n + 1):
                if ns[f] is None:
                    ns[f] = ns[f - 1]
                elif ns[f].dot(ns[f - 1]) < 0:
                    ns[f] = -ns[f]
        # smooth the flat normal a little (no popping between fast and slow frames)
        sm_ns = []
        for f in range(n + 1):
            acc = Vector((0, 0, 0))
            for d, w in ((-1, 1), (0, 2), (1, 1)):
                acc += ns[min(n, max(0, f + d))] * w
            sm_ns.append(acc.normalized() if acc.length > 1e-6 else ns[f])
        ns = sm_ns
        if nstart is not None:
            for f in range(n + 1):
                w = 1.0 - sm(f / float(nstart[0]))
                if w > 0:
                    v = Vector(nstart[1])
                    if v.dot(ns[f]) < 0:
                        v = -v
                    ns[f] = (ns[f] * (1 - w) + v * w).normalized()
        if nend is not None:
            for f in range(n + 1):
                w = sm((f - nend[0]) / float(n - nend[0]))
                if w > 0:
                    v = Vector(nend[1])
                    if v.dot(ns[f]) < 0:
                        v = -v
                    ns[f] = (ns[f] * (1 - w) + v * w).normalized()
    elif edge == "anch":
        ns = []
        for f in range(n + 1):
            ns.append(Vector(ev([(a, tuple(b)) for a, b in nanch], f)).normalized())
    else:   # "rot": flat normal = world up (perp to the shaft) rotated about the shaft by nrot(f) degrees
        ns = []
        for f in range(n + 1):
            b = out[f]["bdw"]
            base = Vector((0, 0, 1))
            base = (base - b * base.dot(b)).normalized() if abs(b.z) < 0.95 else Vector((1, 0, 0))
            th = math.radians(ev(nrot, f))
            ns.append(base * math.cos(th) + b.cross(base) * math.sin(th))
    for f in range(n + 1):
        out[f]["n"] = ns[f]
    return out


def to_keys(n, states, lhand=None):
    keys = []
    Bh = CC._frame(CC.BLADE_REST["axis"], CC.BLADE_REST["flat"])
    for s in states:
        f = s["_f"]
        yaw, P = s["yaw"], s["P"]
        d = {}
        d["pel"] = P
        d["root"] = s["root"]
        d["hip"], d["tor"], d["head"] = s["hip"], s["tor"], s["head"]
        d["hand_r"] = s["hrw"]
        d["ho_r"] = CC.blade_o(s["bdw"], s["n"])
        d["curl_r"], d["curl_l"] = s["cr"], s["cl"]
        if lhand:
            sl = s["sl"]
            if lhand == "spear":
                # the front hand is a guide: it stays at a body-relative point and the shaft slides through it
                G = rel(0.05, 0.52, 1.22, yaw, (P.x, P.y))
                sl = max(0.18, min(0.60, (G - s["hrw"]).dot(s["bdw"])))
            hd = s["hrw"] + s["bdw"] * sl
            hc = rel(s["hl"][0], s["hl"][1], s["hl"][2], yaw, (P.x, P.y))
            w = s.get("lw", 1.0)
            hl = hc.lerp(hd, w)
            npal = Vector(TF(-1.0, 0.0, 0.0, yaw))
            if abs(npal.dot(s["bdw"])) > 0.95:
                npal = Vector((0, 0, 1))
            fd, nd = _frame_lh(s["bdw"], npal)
            fc, nc = Vector(TF(0.0, 0.3, -1.0, yaw)), Vector(TF(-1.0, 0.0, 0.0, yaw))
            d["ho_l"] = (tuple((fc * (1 - w) + Vector(fd) * w).normalized()), tuple((nc * (1 - w) + Vector(nd) * w).normalized()))
        else:
            if "HL" in s:
                hl = Vector(s["HL"])
            else:
                hl = rel(s["hl"][0], s["hl"][1], s["hl"][2], yaw, (P.x, P.y))
            d["ho_l"] = (TF(0.0, 0.3, -1.0, yaw), TF(-1.0, 0.0, 0.0, yaw))
        d["hand_l"] = hl
        for side, hand in (("r", s["hrw"]), ("l", hl)):
            sx = 1 if side == "l" else -1
            sh = SH0[side] + (P - PEL0)
            mid = (sh + hand) * 0.5
            eo = s["e" + side]
            d["elb_" + side] = mid + Vector(TF(eo[0], eo[1], eo[2], yaw))
        d["foot_l"], d["foot_r"] = s["fl"], s["fr"]
        d["fyaw_l"], d["fyaw_r"] = s["fyl"], s["fyr"]
        d["fpit_l"], d["fpit_r"] = s["fpl"], s["fpr"]
        keys.append((f, d, "lin"))
    return keys


def gen(n, ch, **kw):
    lh = kw.get("lhand")
    return CC.F.build(to_keys(n, compute(n, ch, **kw), lh), n)


def _ph(fr, k, n):
    return math.sin(2 * math.pi * k * fr / float(n))


# ==================================================================== 1H sword + shield: heavy charge
# charge pose C: sword drawn back over the right shoulder, hips/chest wound 35/55 deg away from the target, weight sunk on
# the rear (right) leg, shield hand forward.
C = dict(pel=V(-0.09, 0.14, -0.13), hip=(8.0, -35.0, 0.0), tor=(-3.0, -20.0, -8.0), head=(0.0, 45.0, 2.0),
         hr=(-0.30, -0.10, 1.50), hl=(0.28, 0.34, 1.13), bd=_nrm((-0.45, -0.35, 0.82)),
         fl=V(0.18, -0.06, 0.104), fr=V(-0.22, 0.24, 0.104), fyl=18.0, fyr=-45.0,
         er=(-0.30, -0.15, -0.10), el=(0.35, -0.25, -0.25), cr=1.0, cl=0.7)


def release_spec():
    R = READY()
    z = 0.104
    ch = dict(
        pel=[(0, C["pel"]), (2, V(-0.06, 0.02, -0.17), "in2"), (5, V(-0.02, -0.25, -0.22), "in2"),
             (7, V(0.0, -0.32, -0.24), "out"), (15, V(0.0, -0.35, -0.22), "smooth"),
             (24, V(0.0, -0.41, -0.08), "smooth"), (36, V(0.0, -0.45, 0.0), "smooth")],
        T=[(0, 0.0), (1, 0.0), (6, 0.45, "in2")],
        hip=[(0, C["hip"]), (4, (4.0, 18.0, 0.0), "in2"), (7, (5.0, 30.0, 2.0), "out"), (15, (6.0, 22.0, 1.0), "smooth"),
             (36, R["hip"], "smooth")],
        tor=[(0, C["tor"]), (2, C["tor"]), (5, (6.0, -10.0, 3.0), "in2"), (8, (14.0, 8.0, 6.0), "out"),
             (16, (10.0, 4.0, 2.0), "smooth"), (36, R["tor"], "smooth")],
        head=[(0, C["head"]), (4, (4.0, 5.0, 0.0), "in2"), (8, (3.0, -22.0, 0.0), "out"), (16, (2.0, -10.0, 0.0), "smooth"),
              (36, R["head"], "smooth")],
        hr=[(0, C["hr"]), (2, (-0.29, -0.10, 1.55), "smooth"), (5, (-0.12, 0.46, 1.30), "in2", (0.0, 0.0, 0.14)),
            (8, (0.10, 0.34, 0.90), "out"), (16, (0.12, 0.32, 0.86), "smooth"), (36, R["hr"], "smooth", (0.0, 0.0, 0.18))],
        bd=[(0, C["bd"]), (2, _nrm((-0.42, -0.30, 0.86))), (5, _nrm((0.10, 0.85, -0.40)), "in2"),
            (8, _nrm((0.55, 0.35, -0.75)), "out"), (16, _nrm((0.5, 0.4, -0.6)), "smooth"), (36, R["bd"], "smooth")],
        hl=[(0, C["hl"]), (5, (0.42, 0.05, 1.10), "in2"), (9, (0.45, 0.20, 1.05), "out"), (20, (0.34, 0.14, 0.95), "smooth"),
            (36, R["hl"], "smooth")],
        fl=[(0, C["fl"]), (1, C["fl"]), (5, V(0.20, -0.51, z), "smooth", (0, 0, 0.10)), (15, V(0.20, -0.51, z)),
            (20, V(0.13, -0.43, z), "smooth", (0, 0, 0.05)), (36, V(0.13, -0.43, z))],
        fr=[(0, C["fr"]), (3, C["fr"]), (7, V(-0.22, 0.02, z), "smooth", (0, 0, 0.08)), (20, V(-0.22, 0.02, z)), (31, V(-0.13, -0.39, z), "smooth", (0, 0, 0.14)), (36, V(-0.13, -0.39, z))],
        fyl=[(0, C["fyl"]), (5, 12.0, "smooth"), (15, 12.0), (20, R["fyl"], "smooth")],
        fyr=[(0, C["fyr"]), (20, C["fyr"]), (31, R["fyr"], "smooth")],
        er=[(0, C["er"]), (5, (-0.30, -0.30, -0.25), "in2"), (36, R["er"], "smooth")],
        el=[(0, C["el"]), (36, R["el"], "smooth")],
        cr=[(0, 1.0), (16, 1.0), (36, R["cr"], "smooth")], cl=[(0, 0.7), (36, R["cl"], "smooth")],
    )
    return ch


def _cn():
    """flat normal of the charge pose = the edge plane at the start of the release swing"""
    return compute(36, release_spec(), tip_len=0.75, nend=(22, N["ho_r"][1]))[0]["n"]


CN = None


def charge_n():
    global CN
    if CN is None:
        CN = _cn()
    return CN


def charge_start():
    R = READY()
    ch = dict(
        pel=[(0, R["pel"]), (8, C["pel"], "smooth")],
        hip=[(0, R["hip"]), (8, (8.0, -37.0, 0.0), "smooth"), (10, C["hip"], "smooth")],
        tor=[(0, R["tor"]), (1, R["tor"]), (9, (-3.0, -21.0, -8.5), "smooth"), (10, C["tor"], "smooth")],
        head=[(0, R["head"]), (8, C["head"], "smooth")],
        hr=[(0, R["hr"]), (2, R["hr"]), (9, (-0.31, -0.11, 1.52), "out", (-0.06, -0.02, 0.0)), (10, C["hr"], "smooth")],
        bd=[(0, R["bd"]), (3, R["bd"]), (9, C["bd"], "out"), (10, C["bd"])],
        hl=[(0, R["hl"]), (3, R["hl"]), (10, C["hl"], "smooth")],
        fl=[(0, R["fl"]), (3, R["fl"]), (8, C["fl"], "smooth", (0, 0, 0.05)), (10, C["fl"])],
        fr=[(0, R["fr"]), (2, R["fr"]), (7, C["fr"], "smooth", (0, 0, 0.06)), (10, C["fr"])],
        fyl=[(0, R["fyl"]), (8, C["fyl"], "smooth")], fyr=[(0, R["fyr"]), (8, C["fyr"], "smooth")],
        er=[(0, R["er"]), (9, C["er"], "smooth")], el=[(0, R["el"]), (9, C["el"], "smooth")],
        cr=[(0, R["cr"]), (10, C["cr"], "smooth")], cl=[(0, R["cl"]), (10, C["cl"], "smooth")],
    )
    nA = Vector(N["ho_r"][1])
    return gen(10, ch, tip_len=0.75, edge="anch", nanch=[(0, tuple(nA)), (3, tuple(nA)), (9, tuple(charge_n()))])


clip("Sword_Heavy_Charge_Start", events={"windup_end": 10, "charge_ready": 10},
     note="ready -> deep coiled charge pose (0.33 s); start of the hold loop")(charge_start)


def charge_hold():
    ch = {k: v for k, v in C.items()}

    def post(f, s):
        ph = _ph(f, 1, 30)
        s["pel"] = Vector(s["pel"]) + V(0.0, 0.004 * ph, 0.007 * ph)
        s["tor"] = (s["tor"][0] + 1.4 * ph, s["tor"][1], s["tor"][2] + 0.6 * ph)
        s["head"] = (s["head"][0] - 1.0 * ph, s["head"][1], s["head"][2])
        # tremor in the sword arm (integer cycles per loop, zero at the ends): keeps the loop closed
        tr = Vector((0.005 * _ph(f, 5, 30), 0.004 * _ph(f, 7, 30), 0.006 * _ph(f, 4, 30)))
        s["hr"] = tuple(a + b for a, b in zip(s["hr"], tr))
        b = Vector(s["bd"]) + Vector((0.012 * _ph(f, 6, 30), 0.010 * _ph(f, 3, 30), 0.012 * _ph(f, 8, 30)))
        s["bd"] = tuple(b.normalized())
        s["hl"] = tuple(a + c for a, c in zip(s["hl"], (0.004 * _ph(f, 3, 30), 0.006 * ph, 0.003 * _ph(f, 5, 30))))
    return gen(30, ch, tip_len=0.75, edge="anch", nanch=[(0, tuple(charge_n()))], post=post)


clip("Sword_Heavy_Charge_Hold_Loop", loop=True, events={"loop": [0, 30]},
     note="charge hold: breathing + arm tremor; first frame == last frame == Charge_Start end pose")(charge_hold)


def heavy_release():
    return gen(36, release_spec(), tip_len=0.75, nend=(22, N["ho_r"][1]))


clip("Sword_Heavy_Release", events={"windup_end": 1, "hit_start": 3, "hit": 5, "hit_end": 7, "combo_window": [16, 26],
                                   "cancel_window": [12, 36]},
     note="release from the charge pose: hips-led unwind, overhead diagonal cut, lunge 0.45 m", root_motion_m=0.45)(heavy_release)


# ==================================================================== 1H sword + shield: run attack
def _Trun(f):
    u = min(f, 16) / 16.0
    return 1.6 * (1 - (1 - u) ** 2)


def _rr(ws):
    """root-relative track -> world (adds the root travel)"""
    return lambda f: Vector(ev(ws, f)) + V(0, -_Trun(f), 0)


def _run_R():
    z = 0.104
    T1, T4 = _Trun(1), _Trun(4)
    wy = -0.42 - T1
    rel_a = [(0, V(-0.13, -0.48, 0.22)), (1, V(-0.14, -0.42, z), "smooth")]

    def fr(f):
        if f <= 1:
            return Vector(ev(rel_a, f)) + V(0, -_Trun(f), 0)
        if f <= 4:
            return V(-0.14, wy, z)
        r = ev([(4, V(-0.14, wy + T4, z)), (24, V(-0.13, 0.06, z), "smooth")], f)
        return r + V(0, -_Trun(f), 0)
    return fr


def run_attack():
    R = READY()
    z = 0.104
    ch = dict(
        T=_Trun,
        pel=_rr([(0, V(0, 0.03, -0.06)), (2, V(0, 0.0, -0.08)), (5, V(0, -0.04, -0.20), "smooth"), (8, V(0, -0.06, -0.22)),
                 (16, V(0, -0.04, -0.16), "smooth"), (30, V(0, 0, 0), "smooth")]),
        hip=[(0, (5.0, 6.0, 0.0)), (5, (6.0, -25.0, 0.0), "smooth"), (7, (4.0, 20.0, 0.0), "in2"), (10, (5.0, 32.0, 2.0), "out"),
             (17, (5.0, 20.0, 0.0), "smooth"), (30, R["hip"], "smooth")],
        tor=[(0, (10.0, -8.0, 0.0)), (5, (6.0, -15.0, -6.0), "smooth"), (6, (6.0, -15.0, -6.0)), (8, (4.0, 0.0, 4.0), "in2"),
             (10, (6.0, 8.0, 6.0), "out"), (17, (8.0, 6.0, 2.0), "smooth"), (30, R["tor"], "smooth")],
        head=[(0, (-4.0, 0.0, 0.0)), (5, (0.0, 30.0, 0.0), "smooth"), (9, (3.0, -12.0, 0.0), "out"), (30, R["head"], "smooth")],
        hr=[(0, (-0.28, -0.12, 0.95)), (3, (-0.30, -0.18, 0.85), "smooth"), (5, (-0.32, -0.10, 0.80), "smooth"),
            (8, (0.05, 0.50, 1.35), "in2", (-0.05, 0.05, -0.12)), (11, (0.15, 0.34, 1.55), "out"),
            (17, (0.20, 0.32, 1.45), "smooth"), (30, R["hr"], "smooth", (0.0, 0.0, 0.15))],
        bd=[(0, _nrm((-0.15, -0.55, -0.65))), (5, _nrm((-0.30, -0.45, -0.75)), "smooth"), (8, _nrm((0.30, 0.85, 0.45)), "in2"),
            (11, _nrm((0.55, 0.30, 0.80)), "out"), (17, _nrm((0.5, 0.3, 0.6)), "smooth"), (30, R["bd"], "smooth")],
        hl=[(0, (0.30, 0.40, 1.20)), (5, (0.38, 0.10, 1.05), "smooth"), (9, (0.45, 0.15, 1.0), "out"), (30, R["hl"], "smooth")],
        fr=_run_R(),
        fl=_rr([(0, V(0.13, 0.42, 0.30)), (2, V(0.13, -0.05, 0.30), "smooth"), (5, V(0.16, -0.42, z), "in2"),
                (18, V(0.16, -0.42, z)), (24, V(0.13, 0.02, z), "smooth", (0, 0, 0.06))]),
        fyl=[(0, 6.0), (5, 15.0, "smooth"), (18, 15.0), (24, R["fyl"], "smooth")],
        fyr=[(0, -10.0), (5, -35.0, "smooth"), (18, -35.0), (26, R["fyr"], "smooth")],
        er=[(0, R["er"])], cr=[(0, 0.9)], cl=[(0, 0.7), (30, R["cl"], "smooth")],
    )
    return gen(30, ch, tip_len=0.75, nend=(20, N["ho_r"][1]))


clip("Sword_Run_Attack", events={"windup_end": 5, "hit_start": 6, "hit": 8, "hit_end": 10, "combo_window": [17, 26],
                                 "cancel_window": [14, 30], "skid_end": 16},
     note="played at ~6 m/s: starts mid-stride (right foot forward), jump-step, skid 1.6 m decelerating, rising diagonal cut; "
          "first frame is a running pose (blend from the run cycle), last frame == ready_pose", root_motion_m=1.6)(run_attack)


# ==================================================================== two-hander overhead chop
def twohand_overhead():
    R = READY()
    z = 0.104
    ch = dict(
        T=[(0, 0.0), (13, 0.0), (17, 0.35, "in2")],
        pel=[(0, R["pel"]), (12, V(0, 0.08, 0.02), "smooth"), (14, V(0, 0.09, 0.03)), (17, V(0, -0.27, -0.16), "in2"),
             (20, V(0, -0.30, -0.19), "out"), (28, V(0, -0.30, -0.15), "smooth"), (45, V(0, -0.35, 0.0), "smooth")],
        hip=[(0, R["hip"]), (12, (-8.0, -6.0, 0.0), "smooth"), (14, (-9.0, -8.0, 0.0)), (16, (16.0, 8.0, 0.0), "in2"),
             (20, (20.0, 8.0, 0.0), "out"), (28, (10.0, 4.0, 0.0), "smooth"), (45, R["hip"], "smooth")],
        tor=[(0, R["tor"]), (12, (-14.0, -3.0, 0.0), "smooth"), (15, (-15.0, -4.0, 0.0)), (18, (24.0, 4.0, 0.0), "in2"),
             (21, (30.0, 4.0, 0.0), "out"), (30, (14.0, 2.0, 0.0), "smooth"), (45, R["tor"], "smooth")],
        head=[(0, R["head"]), (12, (18.0, 0.0, 0.0), "smooth"), (17, (-8.0, 0.0, 0.0), "in2"), (24, (-4.0, 0.0, 0.0), "smooth"),
              (45, R["head"], "smooth")],
        hr=[(0, R["hr"]), (12, (-0.12, 0.00, 1.92), "smooth", (0.0, 0.05, -0.10)), (15, (-0.11, -0.05, 1.95), "smooth"),
            (17, (-0.06, 0.42, 1.45), "in2", (0.0, 0.0, 0.15)), (20, (-0.05, 0.46, 1.22), "out"),
            (22, (-0.05, 0.44, 1.30), "smooth"), (26, (-0.05, 0.46, 1.24), "smooth"), (45, R["hr"], "smooth", (0.0, 0.0, 0.12))],
        bd=[(0, R["bd"]), (12, _nrm((-0.05, -0.60, 0.80)), "smooth"), (15, _nrm((-0.05, -0.75, 0.66)), "smooth"),
            (17, _nrm((0.0, 0.85, -0.53)), "in2"), (20, _nrm((0.0, 0.35, -0.94)), "out"), (22, _nrm((0.0, 0.5, -0.85)), "smooth"),
            (26, _nrm((0.0, 0.38, -0.92)), "smooth"), (45, R["bd"], "smooth")],
        sl=-0.11,
        lw=[(0, 0.0), (5, 1.0, "smooth"), (34, 1.0), (45, 0.0, "smooth")],
        fl=[(0, R["fl"]), (13, R["fl"]), (17, V(0.13, -0.33, z), "in2", (0, 0, 0.12)), (45, V(0.13, -0.33, z))],
        fr=[(0, R["fr"]), (30, R["fr"]), (41, V(-0.13, -0.29, z), "smooth", (0, 0, 0.14)), (45, V(-0.13, -0.29, z))],
        er=[(0, R["er"]), (12, (-0.28, -0.05, 0.0), "smooth"), (17, (-0.30, -0.25, -0.20), "smooth"), (45, R["er"], "smooth")],
        el=[(0, R["el"]), (12, (0.28, -0.05, 0.0), "smooth"), (17, (0.30, -0.25, -0.20), "smooth"), (45, R["el"], "smooth")],
        cl=[(0, 0.5), (5, 1.0, "smooth"), (34, 1.0), (45, 0.5, "smooth")],
    )
    return gen(45, ch, tip_len=0.95, lhand="2h", nend=(34, N["ho_r"][1]))


clip("TwoHand_Overhead", events={"windup_end": 14, "hit_start": 15, "hit": 17, "hit_end": 19, "bounce_end": 24,
                                "combo_window": [30, 40], "cancel_window": [26, 45]},
     note="two-hander overhead chop: 12 f rising anticipation, moving hold, 3 f chop with 0.35 m step-in, ground bounce; "
          "left hand grabs the hilt 0.11 m below the right during the wind-up and lets go in the recovery",
     root_motion_m=0.35)(twohand_overhead)


# ==================================================================== spear
Z0 = 0.104
SR = dict(pel=V(-0.09, 0.03, -0.07), hip=(3.0, -20.0, 0.0), tor=(3.0, -10.0, 0.0), head=(0.0, 25.0, 0.0),
          fl=V(0.05, -0.15, Z0), fr=V(-0.28, 0.20, Z0), fyl=10.0, fyr=-55.0)
SR_W = rel(-0.20, 0.05, 1.05, -30.0, (-0.09, 0.03))
SR_BD = tuple(Vector(TF(0.5, 0.85, 0.30, -30.0)).normalized())
BD_THR = _nrm((0.0, -0.98, 0.17))


def spear_ready():
    """spear guard: side-on, shaft forward and slightly up, left hand forward on the shaft"""
    d = dict(SR)
    d.update(HR=SR_W, BD=SR_BD, sl=0.52, cl=1.0, cr=1.0)
    return d


def _W(out, fwd, z, yaw, pel):
    return rel(out, fwd, z, yaw, pel)


def _line(p0, d, ss):
    """straight world path: p0 + d*s for consecutive frames"""
    return [(f, p0 + Vector(d) * s, "lin") for f, s in ss]


def _spear_common(ch):
    ch.setdefault("cl", 1.0)
    ch.setdefault("cr", 1.0)
    ch.setdefault("er", (-0.35, -0.25, -0.30))
    ch.setdefault("el", (0.35, -0.25, -0.30))
    return ch


def _sgen(n, ch, nrot):
    return gen(n, _spear_common(ch), tip_len=1.7, lhand="spear", edge="rot", nrot=nrot)


def thrust1():
    S = SR
    d = Vector(BD_THR)
    p0 = SR_W + V(0, 0.28, 0)
    ch = dict(
        T=[(0, 0.0), (3, 0.0), (7, 0.25, "in2")],
        pel=[(0, S["pel"]), (3, V(-0.10, 0.07, -0.06), "smooth"), (7, V(-0.07, -0.20, -0.13), "in2"),
             (9, V(-0.07, -0.22, -0.13), "out"), (16, V(-0.08, -0.20, -0.10), "smooth"), (24, V(-0.09, -0.22, -0.07), "smooth")],
        hip=[(0, S["hip"]), (3, (3.0, -30.0, 0.0), "smooth"), (6, (4.0, -6.0, 0.0), "in2"), (9, (4.0, -2.0, 0.0), "out"),
             (24, S["hip"], "smooth")],
        tor=[(0, S["tor"]), (3, (3.0, -12.0, 0.0)), (7, (6.0, -4.0, 0.0), "in2"), (9, (6.0, 0.0, 0.0), "out"), (24, S["tor"], "smooth")],
        head=[(0, S["head"]), (7, (0.0, 5.0, 0.0), "smooth"), (24, S["head"], "smooth")],
        HR=[(0, SR_W), (3, p0, "smooth")] + _line(p0, d, [(4, 0.05), (5, 0.30), (6, 0.58), (7, 0.80)]) +
           [(8, p0 + d * 0.85, "out"), (14, p0 + d * 0.55, "smooth"), (24, SR_W + V(0, -0.25, 0), "smooth")],
        BD=[(0, SR_BD), (3, SR_BD), (4, BD_THR, "smooth"), (10, BD_THR), (24, SR_BD, "smooth")],
        sl=[(0, 0.52), (4, 0.50), (7, 0.30), (10, 0.30), (24, 0.52, "smooth")],
        fl=[(0, S["fl"]), (3, S["fl"]), (7, V(0.05, -0.40, Z0), "in2", (0, 0, 0.10)), (24, V(0.05, -0.40, Z0))],
        fr=[(0, S["fr"]), (14, S["fr"]), (22, V(-0.28, -0.05, Z0), "smooth", (0, 0, 0.12)), (24, V(-0.28, -0.05, Z0))],
        fyl=S["fyl"], fyr=S["fyr"],
    )
    return _sgen(24, ch, [(0, 90.0)])


clip("Spear_Thrust_1", events={"windup_end": 3, "hit_start": 5, "hit": 7, "hit_end": 9, "combo_window": [11, 20],
                               "cancel_window": [10, 24]},
     note="quick jab from the spear guard, 0.25 m step-in", root_motion_m=0.25)(thrust1)


def thrust2():
    S = SR
    d = Vector(BD_THR)
    p0 = SR_W + V(0.0, 0.30, -0.10)
    ch = dict(
        T=[(0, 0.0), (5, 0.0), (8, 0.35, "in2")],
        pel=[(0, S["pel"]), (5, V(-0.13, 0.10, -0.10), "smooth"), (8, V(-0.05, -0.25, -0.18), "in2"),
             (10, V(-0.05, -0.28, -0.18), "out"), (20, V(-0.08, -0.30, -0.10), "smooth"), (28, V(-0.09, -0.32, -0.07), "smooth")],
        hip=[(0, S["hip"]), (5, (4.0, -48.0, 0.0), "smooth"), (7, (5.0, -2.0, 0.0), "in2"), (10, (5.0, 4.0, 0.0), "out"),
             (28, S["hip"], "smooth")],
        tor=[(0, S["tor"]), (5, (3.0, -18.0, 0.0), "smooth"), (6, (3.0, -18.0, 0.0)), (8, (7.0, -2.0, 0.0), "in2"),
             (10, (7.0, 4.0, 0.0), "out"), (28, S["tor"], "smooth")],
        head=[(0, S["head"]), (5, (0.0, 40.0, 0.0), "smooth"), (8, (0.0, 0.0, 0.0), "in2"), (28, S["head"], "smooth")],
        HR=[(0, SR_W), (5, p0, "smooth", (0.0, 0.0, 0.05))] + _line(p0, d, [(6, 0.15), (7, 0.48), (8, 0.82)]) +
           [(10, p0 + d * 0.90, "out"), (18, p0 + d * 0.55, "smooth"), (28, SR_W + V(0, -0.35, 0), "smooth")],
        BD=[(0, SR_BD), (5, _nrm((0.10, -0.94, 0.35)), "smooth"), (6, BD_THR, "smooth"), (12, BD_THR), (28, SR_BD, "smooth")],
        sl=[(0, 0.52), (5, 0.52), (8, 0.30), (12, 0.30), (28, 0.52, "smooth")],
        fl=[(0, S["fl"]), (4, S["fl"]), (8, V(0.05, -0.50, Z0), "in2", (0, 0, 0.10)), (28, V(0.05, -0.50, Z0))],
        fr=[(0, S["fr"]), (18, S["fr"]), (26, V(-0.28, -0.15, Z0), "smooth", (0, 0, 0.12)), (28, V(-0.28, -0.15, Z0))],
        fyl=S["fyl"], fyr=S["fyr"],
    )
    return _sgen(28, ch, [(0, 90.0), (5, 90.0), (8, 270.0, "in2")])


clip("Spear_Thrust_2", events={"windup_end": 5, "hit_start": 6, "hit": 8, "hit_end": 10, "combo_window": [13, 24],
                               "cancel_window": [12, 28]},
     note="retract to the hip, hip-driven twisting thrust, 0.35 m step-in", root_motion_m=0.35)(thrust2)


def thrust3():
    S = SR
    d = Vector(BD_THR)
    p0 = _W(-0.22, 0.18, 1.10, -20.0, (-0.07, 0.05))
    hr5 = _W(-0.22, 0.02, 0.95, -48.0, (-0.12, 0.12))
    bd5 = _nrm((-0.25, -0.85, -0.30))
    ch = dict(
        T=[(0, 0.0), (7, 0.0), (12, 0.50, "in2")],
        pel=[(0, S["pel"]), (5, V(-0.12, 0.12, -0.17), "smooth"), (12, V(-0.03, -0.40, -0.22), "in2"),
             (14, V(-0.03, -0.44, -0.22), "out"), (26, V(-0.06, -0.45, -0.12), "smooth"), (40, V(-0.09, -0.47, -0.07), "smooth")],
        hip=[(0, S["hip"]), (5, (6.0, -36.0, 0.0), "smooth"), (8, (6.0, -6.0, 0.0), "in2"), (12, (6.0, 6.0, 0.0), "out"),
             (40, S["hip"], "smooth")],
        tor=[(0, S["tor"]), (5, (4.0, -12.0, 0.0), "smooth"), (6, (4.0, -12.0, 0.0)), (10, (8.0, -8.0, 0.0), "in2"),
             (12, (8.0, 0.0, 0.0), "out"), (40, S["tor"], "smooth")],
        head=[(0, S["head"]), (5, (0.0, 42.0, 0.0), "smooth"), (10, (0.0, 0.0, 0.0), "in2"), (40, S["head"], "smooth")],
        HR=[(0, SR_W), (5, hr5, "smooth"), (9, p0, "smooth", (0.0, 0.0, 0.22))] + _line(p0, d, [(10, 0.14), (11, 0.38), (12, 0.66)]) +
           [(14, p0 + d * 0.72, "out"), (24, p0 + d * 0.60, "smooth"), (40, SR_W + V(0, -0.5, 0), "smooth")],
        BD=[(0, SR_BD), (5, bd5, "smooth"), (8, _nrm((0.10, -0.92, 0.35)), "in2"), (9, BD_THR, "smooth"), (16, BD_THR),
            (40, SR_BD, "smooth")],
        sl=[(0, 0.52), (9, 0.50), (12, 0.34), (16, 0.34), (40, 0.52, "smooth")],
        fl=[(0, S["fl"]), (5, S["fl"]), (12, V(0.05, -0.65, Z0), "in2", (0, 0, 0.12)), (40, V(0.05, -0.65, Z0))],
        fr=[(0, S["fr"]), (6, S["fr"]), (12, V(-0.28, 0.02, Z0), "smooth", (0, 0, 0.10)), (28, V(-0.28, 0.02, Z0)),
            (37, V(-0.28, -0.30, Z0), "smooth", (0, 0, 0.14)), (40, V(-0.28, -0.30, Z0))],
        fyl=S["fyl"], fyr=S["fyr"],
    )
    return _sgen(40, ch, [(0, 90.0), (9, 90.0), (12, 90.0)])


clip("Spear_Thrust_3", events={"windup_end": 5, "sweep_start": 5, "hit_start": 10, "hit": 12, "hit_end": 14,
                               "combo_window": [20, 34], "cancel_window": [16, 40]},
     note="finisher: low-to-high sweeping arc into a lunging long thrust, 0.5 m step", root_motion_m=0.5)(thrust3)
