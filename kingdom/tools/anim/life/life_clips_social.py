# SOCIAL clips: talking pairs, reactions, greetings, paired hug / handshake, mourning.
# (Also the helper library shared by life_clips_kids.py / life_clips_ambient.py.)
#
# Body-frame authoring: hs(out, fwd, z, orient, curl, elbow) places a hand relative to the torso: `out` m away from the
# body midline on that hand's own side (so the same numbers mirror to the other hand), `fwd` m in front of the spine
# axis, `z` standing height. mk() then follows the pelvis shift, weight shift, torso lean / roll / yaw, so a
# gesture stays attached to the shoulder when the body moves. hsw() places a hand at a WORLD point instead (paired
# contact, pointing, prop-like touches). Loops are closed with loop(): the last key is the first key, and every
# procedural layer uses integer harmonics of the clip length.
import math
from mathutils import Vector, Matrix, Quaternion
import combat_common as CC
from combat_common import V, rel
import life_common as LC
from life_common import life_clip, neutral, hold, to_from, breathe, chain, sinw, grip_o, wrist_at

RAD = math.radians
SX = {"l": 1, "r": -1}

# hand orientations in the body frame (out, fwd, up): (fingers, palm normal); "out" is away from the midline
OR = {
    "hang": ((0.05, 0, -1), (-1, 0, 0)),
    "palm_up": ((0, 1, 0.1), (0, 0, 1)),        # fingers forward, palm up (offering / explaining)
    "palm_dn": ((0, 1, 0), (0, 0, -1)),         # fingers forward, palm down (flat / calming)
    "palm_in": ((0, 1, 0), (-1, 0, 0)),         # fingers forward, palm to the midline (chop / handshake / box)
    "palm_out": ((0, 1, 0), (1, 0, 0)),
    "stop": ((0, 0.15, 1), (0, 1, 0)),          # fingers up, palm forward (wave / defensive)
    "up_in": ((0, 0.1, 1), (-1, 0, 0)),         # fingers up, palm to the midline
    "hip": ((-0.25, 0.65, -0.7), (-1, 0, 0)),   # hand planted on the hip, fingers forward
    "chest": ((-1, 0.2, 0.3), (0, -1, 0)),      # hand flat on the chest, fingers across
    "point": ((0, 1, 0.12), (-0.3, 0, -1)),     # fist with the finger thrown forward
    "cross": ((-1, 0.3, -0.2), (0, -1, 0)),     # hand tucked around the opposite arm
    "face": ((0, 0.2, 1), (-1, 0, 0)),
    "down_fwd": ((0, 0.6, -0.8), (-1, 0, 0)),
}


def hs(out=0.27, fwd=-0.005, z=0.915, o="hang", c=0.25, e=None):
    if c <= 0.1:
        c = max(-1.0, c - 0.55)     # "open" hands read as open on the chunky mannequin fingers
    return {"out": out, "fwd": fwd, "z": z, "o": OR[o] if isinstance(o, str) else o, "c": c, "e": e, "world": False}


def hsw(x, y, z, o="hang", c=0.25, e=None):
    """hand at a world point (character frame, +x left, -y forward); o = ((f),(n)) in WORLD axes when a tuple,
    or a preset name (interpreted with the right/left mirror by the caller: prefer tuples for world hands)"""
    if c <= 0.1:
        c = max(-1.0, c - 0.55)
    return {"p": (x, y, z), "o": o, "c": c, "e": e, "world": True}


def _conv(v, sx, yaw):
    R = Matrix.Rotation(RAD(yaw), 3, "Z")
    return tuple(R @ Vector((sx * v[0], -v[1], v[2])))


def mk(pel=(0, 0, 0), hip=(0, 0, 0), tor=(2.0, 0, 0), head=(0, 0, 0), L=None, R=None, w=0.0, sh=(0.0, 0.0),
       feet=None, **kw):
    """complete state. w = weight over the left (+) / right (-) leg. Extra keyword args override state keys."""
    s = neutral()
    px, py, pz = pel
    hr = hip[2] - 3.5 * w
    tr = tor[2] + 2.5 * w
    s["pel"] = V(px + 0.04 * w, py, pz - 0.006 * abs(w))
    s["hip"] = (hip[0], hip[1], hr)
    s["tor"] = (tor[0], tor[1], tr)
    s["head"] = tuple(head)
    yaw = tor[1] + hip[1]
    # the shoulders follow the spine chain: the pelvis (hip) rotation has the full 0.52 m lever, the spine (tor) only ~0.26 m
    # (the rotation is spread over spine_01..03, whose joints sit at 1.05 / 1.19 / 1.31 m)
    tp, hp = RAD(tor[0] - 2.0), RAD(hip[0])
    tr_, hr_ = RAD(tr), RAD(hr)
    fsh = 0.26 * math.sin(tp) + 0.52 * math.sin(hp)
    dz = -(0.26 * (1 - math.cos(tp)) + 0.52 * (1 - math.cos(hp)))
    dx = 0.26 * math.sin(tr_) + 0.52 * math.sin(hr_)
    for side, h in (("l", L), ("r", R)):
        h = h or hs()
        sx = SX[side]
        if h["world"]:
            pos = V(*h["p"])
            elb = V(*h["e"]) if h["e"] else None
            f, n = h["o"]
            f, n = tuple(f), tuple(n)
        else:
            pos = rel(sx * h["out"], h["fwd"] + fsh, h["z"] + pz + dz, yaw, (s["pel"].x, py)) + V(dx, 0, 0)
            elb = None
            if h["e"]:
                e = h["e"]
                elb = rel(sx * e[0], e[1] + fsh, e[2] + pz + dz, yaw, (s["pel"].x, py)) + V(dx, 0, 0)
            f, n = _conv(h["o"][0], sx, yaw), _conv(h["o"][1], sx, yaw)
        s["hand_" + side] = pos
        s["elb_" + side] = elb
        s["ho_" + side] = (f, n)
        s["curl_" + side] = h["c"]
        lift = max(0.0, min(1.0, (pos.z - (1.441 + pz)) / 0.45)) * 14.0
        s["shrug_" + side] = lift + sh[0 if side == "l" else 1]
    if feet:
        s.update(feet)
    s.update(kw)
    return s


def K(f, ease="smooth", bow=None, **kw):
    d = mk(**kw)
    if bow:
        d["_bow"] = bow
    return (f, d, ease)


def loop(keys, n, ease="smooth"):
    """close a loop: the last key is the first key"""
    d = dict(keys[0][1])
    d.pop("_bow", None)
    return keys + [(n, d, ease)]


def build(keys, n, post=None):
    return CC.F.build(keys, n, post=post)


def feet(l=(0.13, 0.0), r=(-0.12, 0.06), yl=8.0, yr=-9.0, zl=0.104, zr=0.104, pl=0.0, pr=0.0):
    return {"foot_l": V(l[0], l[1], zl), "foot_r": V(r[0], r[1], zr), "fyaw_l": yl, "fyaw_r": yr,
            "fpit_l": pl, "fpit_r": pr}


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def win(fr, a, b, rise=4.0, fall=6.0):
    """0..1 window: rises over `rise` frames from a, falls over `fall` frames ending at b"""
    return smoothstep((fr - a) / rise) * smoothstep((b - fr) / fall)


def addh(s, d):
    s["head"] = tuple(a + b for a, b in zip(s["head"], d))


def addt(s, d):
    s["tor"] = tuple(a + b for a, b in zip(s["tor"], d))


def addp(s, d):
    s["pel"] = Vector(s["pel"]) + Vector(d)


def addsh(s, l, r):
    s["shrug_l"] = (s["shrug_l"] or 0.0) + l
    s["shrug_r"] = (s["shrug_r"] or 0.0) + r


def alive(a=1.0, sd=0.0, oneshot=False, br=0.0035):
    """post(): breathing + slow head / chest drift, all integer harmonics of the clip (loops close)"""
    def post(fr, n, s):
        e = a * ((math.sin(math.pi * fr / n)) ** 2 if oneshot else 1.0)
        w = sinw(fr, n, 1)
        addp(s, V(0, 0, br * w * e))
        addt(s, (0.7 * w * e, 0.9 * sinw(fr, n, 2, 0.21 + sd) * e, 0.5 * sinw(fr, n, 1, 0.4 + sd) * e))
        addh(s, (0.9 * sinw(fr, n, 3, 0.17 + sd) * e, 1.5 * sinw(fr, n, 2, 0.33 + sd) * e + 0.7 * sinw(fr, n, 5, sd) * e,
                 0.8 * sinw(fr, n, 1, 0.5 + sd) * e))
    return post


def pt(side, d, reach=0.53, o_palm=(0, 0, -1), c=-0.4, tor_yaw=0.0, pel=(0, 0, 0), e=None):
    """arm pointing along world direction d: hand spec at a world point (wrist = shoulder + d * reach)"""
    d = Vector(d).normalized()
    sx = SX[side]
    sh = rel(sx * 0.192, 0.0, 1.441 + pel[2], tor_yaw, (pel[0], pel[1]))
    p = sh + d * reach
    n = Vector(o_palm)
    n = (n - d * n.dot(d)).normalized()
    return hsw(p.x, p.y, p.z, (tuple(d), tuple(n)), c, e)


# ---- knee pole for kneeling: the framework's automatic knee hint (in front of and above the ankle) is ambiguous for a
# shin that lies flat behind a kneeling hip (the knee flips backwards). When the foot is toe-down (fpit <= -10) the hint
# is blended toward "ahead of the ankle, near the floor", which bends the knee the natural way. Other clips are untouched.
_ORIG_AUTO_KNEE = CC.F.build.__globals__["auto_knee"]


def _auto_knee_kneel(P, side):
    h = _ORIG_AUTO_KNEE(P, side)
    t = max(0.0, min(1.0, (-P.fpit[side] - 10.0) / 25.0))
    if t <= 0.0:
        return h
    f = P.foot[side]
    return h.lerp(f + V(0, -0.45, -0.05), t)


CC.F.build.__globals__["auto_knee"] = _auto_knee_kneel


# ================================================================== talking (pairs, ~1.1 m apart)
FT_TALK = feet((0.15, 0.0), (-0.13, 0.06), 8.0, -10.0)
D_TALK = 1.1
CROSS_R = hs(-0.05, 0.20, 1.18, "cross", 0.3, e=(0.25, 0.09, 1.12))
CROSS_L = hs(-0.05, 0.26, 1.27, "cross", 0.3, e=(0.25, 0.09, 1.20))


@life_clip("Life_Talk_Explain", loop=True, category="social/talk", tags=["talker"], events={"beat": [20, 64, 96, 112]},
           pair={"partner": "Life_Talk_Listen_Nod", "distance": D_TALK}, blend_in=0.3, blend_out=0.3,
           note="speaker: both hands shape ideas (wide 'the whole thing', a box that grows and shrinks, counting beats)")
def _talk_explain():
    n = 150
    rest_l = hs(0.22, 0.17, 1.02, "palm_up", 0.0)
    rest_r = hs(0.22, 0.17, 1.00, "palm_up", 0.0)
    k = [
        K(0, L=rest_l, R=rest_r, tor=(3, 2, 0), head=(3, 5, 0), w=0.5, feet=FT_TALK),
        K(20, "out2", L=hs(0.46, 0.30, 1.17, "palm_up", -0.2, e=(0.50, -0.02, 1.05)),
          R=hs(0.46, 0.28, 1.13, "palm_up", -0.2, e=(0.50, -0.02, 1.02)), tor=(6, -3, 0), head=(-2, 0, 4), w=0.3, feet=FT_TALK),
        K(34, L=hs(0.40, 0.27, 1.10, "palm_up", -0.1), R=hs(0.41, 0.25, 1.08, "palm_up", -0.1), tor=(5, -2, 0), head=(2, 2, 3), w=0.2, feet=FT_TALK),
        K(52, L=hs(0.10, 0.36, 1.10, "palm_in", 0.1, e=(0.36, 0.05, 1.04)), R=hs(0.10, 0.36, 1.10, "palm_in", 0.1, e=(0.36, 0.05, 1.04)),
          tor=(9, 2, 0), head=(6, 0, 0), w=-0.2, feet=FT_TALK, pel=(0, -0.02, 0)),
        K(64, "out2", L=hs(0.24, 0.38, 1.13, "palm_in", 0.1, e=(0.40, 0.05, 1.06)), R=hs(0.24, 0.38, 1.13, "palm_in", 0.1, e=(0.40, 0.05, 1.06)),
          tor=(8, 0, 0), head=(3, 0, -3), w=-0.3, feet=FT_TALK, pel=(0, -0.02, 0)),
        K(80, "out2", L=hs(0.08, 0.34, 1.08, "palm_in", 0.1), R=hs(0.08, 0.34, 1.08, "palm_in", 0.1),
          tor=(10, 3, 0), head=(9, 3, 3), w=-0.3, feet=FT_TALK, pel=(0, -0.03, 0)),
        K(96, "out2", L=hs(0.15, 0.27, 1.04, "palm_dn", -0.5, e=(0.40, 0.05, 0.98)), R=hs(0.12, 0.30, 1.34, "up_in", 0.5, e=(0.34, 0.03, 1.20)),
          tor=(6, -3, 0), head=(4, -2, 0), w=0.0, feet=FT_TALK),
        K(104, "in2", L=hs(0.15, 0.27, 1.00, "palm_dn", -0.5), R=hs(0.12, 0.33, 1.27, "up_in", 0.5), tor=(8, -3, 0), head=(9, -2, 0), w=0.0, feet=FT_TALK),
        K(112, "out2", L=hs(0.15, 0.27, 1.04, "palm_dn", -0.5), R=hs(0.12, 0.30, 1.35, "up_in", 0.5), tor=(6, -3, 0), head=(3, -2, 0), w=0.1, feet=FT_TALK),
        K(120, "in2", L=hs(0.15, 0.27, 1.00, "palm_dn", -0.5), R=hs(0.12, 0.33, 1.28, "up_in", 0.5), tor=(8, -3, 0), head=(9, -2, 0), w=0.2, feet=FT_TALK),
        K(138, L=hs(0.22, 0.19, 1.02, "palm_up", 0.0), R=hs(0.22, 0.18, 1.00, "palm_up", 0.0), tor=(4, 1, 0), head=(3, 4, 0), w=0.5, feet=FT_TALK),
    ]
    return build(loop(k, n), n, post=alive(1.0, 0.1))


@life_clip("Life_Talk_Emphatic", loop=True, category="social/talk", tags=["talker"], events={"chop": [18, 48, 78]},
           pair={"partner": "Life_Talk_Listen_Hips", "distance": D_TALK},
           note="speaker: hand on hip, right hand chops the air three times, leaning into every stroke")
def _talk_emphatic():
    n = 120
    hipL = hs(0.24, 0.02, 0.98, "hip", 0.5, e=(0.52, -0.05, 1.03))
    base_r = hs(0.20, 0.26, 1.15, "palm_in", 0.3)

    def chop(f, top, dip, lean, extra=0.0):
        return [
            K(f - 8, L=hipL, R=hs(0.17, 0.18, top, "palm_in", 0.3, e=(0.40, -0.02, top - 0.14)), tor=(0, -3, -1), head=(-2, 2, 0),
              w=0.3, feet=FT_TALK, pel=(0, 0.02, 0)),
            K(f, "in2", bow={"hand_r": V(0, -0.05, 0.06)}, L=hipL, R=hs(0.13, 0.35 + extra, dip, "palm_in", 0.3, e=(0.34, 0.06, dip + 0.02)),
              tor=(lean, 3, 1), head=(lean + 3, 0, 0), w=0.0, feet=FT_TALK, pel=(0, -0.05 - extra * 0.3, -0.012)),
            K(f + 4, "out2", L=hipL, R=hs(0.13, 0.33 + extra, dip + 0.05, "palm_in", 0.3), tor=(lean - 3, 2, 0), head=(lean - 1, 0, 0),
              w=0.0, feet=FT_TALK, pel=(0, -0.04, 0)),
        ]
    k = [K(0, L=hipL, R=base_r, tor=(3, -3, 0), head=(0, 2, 0), w=0.5, feet=FT_TALK)]
    k += chop(24, 1.46, 1.12, 9)
    k += chop(52, 1.50, 1.10, 11)
    k += chop(80, 1.54, 1.10, 13, 0.0)
    k += [
        K(94, L=hipL, R=hs(0.14, 0.34, 1.10, "palm_dn", 0.0), tor=(10, 0, 0), head=(6, 0, 0), w=-0.2, feet=FT_TALK, pel=(0, -0.04, 0)),
        K(102, "out2", L=hipL, R=hs(0.36, 0.33, 1.08, "palm_dn", 0.0, e=(0.48, 0.02, 1.02)), tor=(7, -4, 0), head=(1, -5, 3), w=-0.3, feet=FT_TALK, pel=(0, -0.02, 0)),
        K(112, L=hipL, R=base_r, tor=(4, -3, 0), head=(0, 2, 0), w=0.4, feet=FT_TALK),
    ]

    def post(fr, nn, s):
        # a small stomp of weight on each stroke
        for f in (24, 52, 80):
            e = win(fr, f - 1, f + 6, 1.5, 4.0)
            addp(s, V(0, 0, -0.012 * e))
    return build(loop(k, n), n, post=chain(alive(0.8, 0.3), post))


@life_clip("Life_Talk_Casual", loop=True, category="social/talk", tags=["talker"], events={"beat": [20, 62, 76]},
           pair={"partner": "Life_Talk_Listen_Nod", "distance": D_TALK},
           note="speaker: left hand on hip, weight on one leg, right hand gestures loosely (so-so wobble, across the body)")
def _talk_casual():
    n = 150
    hipL = hs(0.24, 0.02, 0.98, "hip", 0.5, e=(0.52, -0.05, 1.03))
    ft = feet((0.16, 0.02), (-0.14, 0.08), 10.0, -12.0)
    k = [
        K(0, L=hipL, R=hs(0.22, 0.24, 1.06, "palm_up", 0.1), tor=(3, 2, 0), head=(2, 3, 0), w=-0.7, feet=ft),
        K(20, "out2", L=hipL, R=hs(0.42, 0.22, 1.10, "palm_up", 0.0, e=(0.50, 0.0, 1.02)), tor=(4, -3, 0), head=(1, -3, 4), w=-0.7, feet=ft),
        K(32, L=hipL, R=hs(0.38, 0.24, 1.08, "palm_dn", 0.0), tor=(4, -2, 0), head=(3, -1, 4), w=-0.6, feet=ft),
        K(44, L=hipL, R=hs(0.40, 0.24, 1.12, "palm_up", 0.0), tor=(4, -3, 0), head=(1, -2, 4), w=-0.6, feet=ft),
        K(62, "out2", L=hipL, R=hs(0.16, 0.32, 1.28, "up_in", 0.4, e=(0.36, 0.05, 1.14)), tor=(6, 2, 0), head=(6, 2, -2), w=-0.3, feet=ft, pel=(0, -0.02, 0)),
        K(76, "out2", bow={"hand_r": V(0, -0.05, 0.04)}, L=hipL, R=hs(-0.08, 0.30, 1.16, "palm_dn", 0.0), tor=(5, 10, 0), head=(2, 18, 0), w=-0.1, feet=ft),
        K(96, L=hipL, R=hs(0.20, 0.24, 1.08, "palm_up", 0.1), tor=(3, 0, 0), head=(4, 2, 0), w=0.3, feet=ft),
        K(114, L=hipL, R=hs(0.30, 0.26, 1.12, "palm_up", 0.0, e=(0.44, 0.0, 1.04)), tor=(3, -1, 0), head=(0, 4, 2), w=0.5, feet=ft),
        K(134, L=hipL, R=hs(0.23, 0.24, 1.05, "palm_up", 0.1), tor=(3, 2, 0), head=(2, 3, 0), w=-0.4, feet=ft),
    ]
    k = loop(k, n)
    k[-1][1].update(mk(L=hipL, R=hs(0.22, 0.24, 1.06, "palm_up", 0.1), tor=(3, 2, 0), head=(2, 3, 0), w=-0.7, feet=ft))
    return build(k, n, post=alive(1.0, 0.7))


@life_clip("Life_Talk_Gossip", loop=True, category="social/talk", tags=["talker"], events={"glance": [25, 60, 135]},
           pair={"partner": "Life_Talk_Listen_Nod", "distance": D_TALK},
           note="speaker: leans in, right hand cupped beside the mouth, glances around to check nobody hears; a suppressed giggle")
def _talk_gossip():
    n = 150
    cup = hs(0.16, 0.13, 1.40, "up_in", 0.2, e=(0.30, 0.08, 1.22))
    belly = hs(0.10, 0.21, 1.03, "palm_dn", 0.4)
    k = [
        K(0, L=belly, R=cup, tor=(13, -5, -2), head=(3, -3, -7), w=0.3, feet=FT_TALK, pel=(0, -0.04, 0)),
        K(25, "out2", L=belly, R=cup, tor=(11, 8, -2), head=(-2, 40, -3), w=0.3, feet=FT_TALK, pel=(0, -0.03, 0)),
        K(45, L=belly, R=cup, tor=(11, 8, -2), head=(0, 38, -3), w=0.3, feet=FT_TALK, pel=(0, -0.03, 0)),
        K(62, "out2", L=belly, R=cup, tor=(12, -12, -2), head=(-1, -38, 2), w=0.3, feet=FT_TALK, pel=(0, -0.03, 0)),
        K(80, L=belly, R=cup, tor=(15, -4, -2), head=(6, -4, -9), w=0.3, feet=FT_TALK, pel=(0, -0.05, 0)),
        K(100, "out2", L=belly, R=hs(0.20, 0.16, 1.34, "up_in", 0.2, e=(0.34, 0.08, 1.20)), tor=(11, -2, -2), head=(8, -2, -7), w=0.3, feet=FT_TALK,
          pel=(0, -0.03, 0), sh=(4, 4)),
        K(108, L=belly, R=cup, tor=(14, -3, -2), head=(3, -3, -7), w=0.3, feet=FT_TALK, pel=(0, -0.04, 0), sh=(1, 1)),
        K(124, L=belly, R=cup, tor=(13, 3, -2), head=(2, 8, -7), w=0.3, feet=FT_TALK, pel=(0, -0.04, 0)),
        K(135, "out2", L=belly, R=cup, tor=(11, 8, -2), head=(-1, 28, -3), w=0.3, feet=FT_TALK, pel=(0, -0.03, 0)),
    ]
    k = loop(k, n)
    k[-1][1].update(mk(L=belly, R=cup, tor=(13, -5, -2), head=(3, -3, -7), w=0.3, feet=FT_TALK, pel=(0, -0.04, 0)))

    def giggle(fr, nn, s):
        e = win(fr, 100, 116, 2, 6)
        v = math.sin(2 * math.pi * fr / 5.0) * e
        addsh(s, 3.0 * v, 3.0 * v)
        addt(s, (0.8 * v, 0, 0))
    return build(k, n, post=chain(alive(0.6, 0.5), giggle))


@life_clip("Life_Talk_Listen_Nod", loop=True, category="social/talk", tags=["listener"], events={"nod": [28, 40, 100, 108]},
           pair={"partner": "Life_Talk_Explain", "distance": D_TALK},
           note="listener: arms crossed, two clear nod pairs, weight shifts from foot to foot")
def _listen_nod():
    n = 150
    ft = feet((0.14, 0.0), (-0.13, 0.05), 8.0, -9.0)
    k = [
        K(0, L=CROSS_L, R=CROSS_R, tor=(3, -2, 0), head=(2, -3, 0), w=-0.5, feet=ft),
        K(28, "out2", L=CROSS_L, R=CROSS_R, tor=(5, -2, 0), head=(13, -3, 0), w=-0.5, feet=ft),
        K(34, L=CROSS_L, R=CROSS_R, tor=(3, -2, 0), head=(1, -3, 0), w=-0.5, feet=ft),
        K(40, "out2", L=CROSS_L, R=CROSS_R, tor=(4, -2, 0), head=(9, -3, 0), w=-0.4, feet=ft),
        K(48, L=CROSS_L, R=CROSS_R, tor=(3, -2, 0), head=(2, 2, 3), w=-0.3, feet=ft),
        K(72, L=CROSS_L, R=CROSS_R, tor=(2, 2, 0), head=(0, 4, 5), w=0.5, feet=ft),
        K(92, L=CROSS_L, R=CROSS_R, tor=(3, 0, 0), head=(2, 0, 0), w=0.5, feet=ft),
        K(100, "out2", L=CROSS_L, R=CROSS_R, tor=(6, 0, 0), head=(14, 0, 0), w=0.5, feet=ft),
        K(106, L=CROSS_L, R=CROSS_R, tor=(3, 0, 0), head=(1, 0, 0), w=0.4, feet=ft),
        K(112, "out2", L=CROSS_L, R=CROSS_R, tor=(5, 0, 0), head=(10, 0, 0), w=0.3, feet=ft),
        K(122, L=CROSS_L, R=CROSS_R, tor=(3, -1, 0), head=(3, -2, 0), w=0.0, feet=ft),
        K(138, L=CROSS_L, R=CROSS_R, tor=(3, -2, 0), head=(2, -3, 0), w=-0.4, feet=ft),
    ]
    k = loop(k, n)
    k[-1][1].update(mk(L=CROSS_L, R=CROSS_R, tor=(3, -2, 0), head=(2, -3, 0), w=-0.5, feet=ft))
    return build(k, n, post=alive(0.6, 0.9))


@life_clip("Life_Talk_Listen_Hips", loop=True, category="social/talk", tags=["listener"], events={"tilt": [30, 76], "nod": [104]},
           pair={"partner": "Life_Talk_Emphatic", "distance": D_TALK},
           note="listener: hands on hips, head tilts side to side as if weighing it, one nod, weight shifts")
def _listen_hips():
    n = 150
    hl = hs(0.24, 0.02, 0.98, "hip", 0.5, e=(0.52, -0.05, 1.03))
    hr = hs(0.24, 0.02, 0.98, "hip", 0.5, e=(0.52, -0.05, 1.03))
    ft = feet((0.16, 0.0), (-0.14, 0.05), 9.0, -10.0)
    k = [
        K(0, L=hl, R=hr, tor=(3, 0, 0), head=(2, 0, 0), w=0.6, feet=ft),
        K(30, "out2", L=hl, R=hr, tor=(3, 3, 1), head=(0, 6, 10), w=0.5, feet=ft),
        K(52, L=hl, R=hr, tor=(3, 2, 1), head=(0, 4, 9), w=0.0, feet=ft),
        K(76, "out2", L=hl, R=hr, tor=(4, -3, -1), head=(-1, -5, -9), w=-0.6, feet=ft),
        K(96, L=hl, R=hr, tor=(3, -2, 0), head=(1, -2, -3), w=-0.6, feet=ft),
        K(104, "out2", L=hl, R=hr, tor=(6, 0, 0), head=(12, 0, 0), w=-0.5, feet=ft),
        K(112, L=hl, R=hr, tor=(4, 0, 0), head=(2, 0, 0), w=-0.3, feet=ft),
        K(132, L=hl, R=hr, tor=(3, 0, 0), head=(2, 0, 0), w=0.3, feet=ft),
    ]
    k = loop(k, n)
    return build(k, n, post=alive(0.7, 0.2))


# ================================================================== reactions
def _shake_post(t0, t1, hz, tor_p=3.0, pel_z=0.010, sh=6.0, head_p=3.0, lag=1.5):
    def post(fr, n, s):
        e = win(fr, t0, t1, 6, 12)
        v = math.sin(2 * math.pi * hz * fr / 30.0)
        v2 = math.sin(2 * math.pi * hz * (fr - lag) / 30.0)
        addt(s, (tor_p * v * e, 0, 0))
        addp(s, V(0, 0, pel_z * v * e))
        addsh(s, sh * v2 * e, sh * v2 * e)
        addh(s, (head_p * v2 * e, 0, 0))
    return post


@life_clip("Life_Social_Laugh", category="social/react", events={"burst": [12], "peak": [40]}, blend_in=0.2, blend_out=0.3,
           note="one-shot belly laugh: inhale, head back, shoulders shake at 5 Hz, folds forward, wipes the eye, recovers")
def _laugh():
    n = 96
    belly = hs(0.10, 0.21, 1.03, "palm_in", 0.3)
    k = [
        K(0),
        K(6, "in2", tor=(-2, 0, 0), head=(-3, 0, 0), sh=(4, 4), L=hs(0.26, 0.05, 0.95, "hang", 0.3), R=hs(0.26, 0.05, 0.95, "hang", 0.3)),
        K(13, "out2", tor=(-14, 0, 0), hip=(-4, 0, 0), head=(-32, 0, 4), pel=(0, 0.03, 0.0), L=belly, R=hs(0.42, 0.10, 1.05, "palm_up", 0.0, e=(0.50, 0.0, 1.0)), sh=(5, 5)),
        K(34, tor=(-10, 0, 2), hip=(-3, 0, 0), head=(-26, 0, 5), pel=(0, 0.03, -0.01), L=belly, R=hs(0.40, 0.12, 1.02, "palm_up", 0.0, e=(0.48, 0.0, 1.0)), sh=(4, 4)),
        K(50, "smooth", tor=(12, 0, 0), hip=(4, 0, 0), head=(12, 0, -4), pel=(0, -0.01, -0.04), L=belly, R=hs(0.30, 0.18, 1.0, "palm_dn", 0.3), sh=(3, 3)),
        K(64, tor=(2, 0, 0), head=(-6, 0, 0), pel=(0, 0, -0.01), L=hs(0.14, 0.18, 1.02, "palm_in", 0.3), R=hs(0.10, 0.14, 1.46, "face", 0.3, e=(0.30, 0.0, 1.30)), sh=(2, 2)),
        K(72, tor=(3, 0, 0), head=(0, 0, 0), L=hs(0.14, 0.18, 1.0, "palm_in", 0.3), R=hs(0.10, 0.14, 1.46, "face", 0.3, e=(0.30, 0.0, 1.30))),
        K(n, "smooth"),
    ]
    return build(k, n, post=chain(_shake_post(14, 62, 5.0, tor_p=4.5, pel_z=0.014, sh=9.0, head_p=4.0), alive(0.5, 0.0, True)))


@life_clip("Life_Social_Laugh_Slap", category="social/react", events={"slap": [26, 40], "burst": [10]}, blend_in=0.2, blend_out=0.3,
           note="one-shot: doubles over laughing and slaps the right knee twice")
def _laugh_slap():
    n = 96
    bend = dict(tor=(36, 0, 0), hip=(16, 0, 0), pel=(0, 0.10, -0.15))
    k = [
        K(0),
        K(8, "in2", tor=(-3, 0, 0), head=(-8, 0, 0), sh=(4, 4)),
        K(16, "out2", head=(-12, 0, 0), L=hsw(0.17, -0.10, 0.74, ((0, -0.5, -1), (-1, 0, 0)), 0.2),
          R=hsw(-0.15, -0.13, 0.76, ((0, -0.5, -1), (1, 0, 0)), -0.2), **bend),
        K(26, "in2", head=(-3, 0, 0), L=hsw(0.17, -0.10, 0.72, ((0, -0.5, -1), (-1, 0, 0)), 0.2),
          R=hsw(-0.145, -0.125, 0.70, ((0, -0.5, -1), (1, 0, 0)), -0.4), **bend),
        K(30, "out2", head=(-10, 0, 0), L=hsw(0.17, -0.10, 0.74, ((0, -0.5, -1), (-1, 0, 0)), 0.2),
          R=hsw(-0.22, -0.20, 0.98, ((0, -0.5, -1), (1, 0, 0)), -0.2), **bend),
        K(40, "in2", head=(-3, 0, 0), L=hsw(0.17, -0.10, 0.72, ((0, -0.5, -1), (-1, 0, 0)), 0.2),
          R=hsw(-0.145, -0.125, 0.70, ((0, -0.5, -1), (1, 0, 0)), -0.4), **bend),
        K(45, "out2", head=(-8, 0, 0), L=hsw(0.17, -0.10, 0.74, ((0, -0.5, -1), (-1, 0, 0)), 0.2),
          R=hsw(-0.21, -0.17, 0.92, ((0, -0.5, -1), (1, 0, 0)), -0.2), **bend),
        K(62, tor=(14, 0, 0), hip=(4, 0, 0), pel=(0, 0.02, -0.06), head=(6, 0, 0), L=hs(0.24, 0.05, 0.99, "hang", 0.3),
          R=hs(0.30, 0.05, 0.99, "hang", 0.3)),
        K(76, tor=(1, 0, 0), head=(-6, 0, 0), sh=(2, 2)),
        K(n),
    ]
    post = chain(_shake_post(16, 70, 5.0, tor_p=2.0, pel_z=0.006, sh=4.0, head_p=2.0), alive(0.4, 0.0, True))
    return build(k, n, post=post)


@life_clip("Life_Social_Argue_A", loop=True, category="social/react", tags=["talker"], events={"jab": [16, 42, 66], "stomp": [42]},
           pair={"partner": "Life_Social_Argue_B", "distance": 1.0},
           note="aggressor: leaning in, jabbing finger three times per cycle, one stamp of weight, fist clenched at the side")
def _argue_a():
    n = 90
    ft = feet((0.17, -0.05), (-0.15, 0.10), 10.0, -14.0)
    fistL = hs(0.30, 0.06, 1.0, "hang", 1.0)

    lift = dict(ft, foot_l=ft["foot_l"] + V(0, -0.03, 0.13), fpit_l=-12.0)

    def jab(f, big, pre=ft):
        return [
            K(f - 6, "smooth", L=fistL, R=hs(0.21, 0.16, 1.28, "point", 0.7, e=(0.34, 0.02, 1.12)), tor=(4, 6, 0), head=(0, 4, 0), w=0.3,
              feet=pre, pel=(0, 0.02, 0.0)),
            K(f, "out2", bow={"hand_r": V(0, 0, 0.03)}, L=fistL, R=hs(0.15, 0.50, 1.30 + big * 0.03, "point", 0.7, e=(0.33, 0.18, 1.18)),
              tor=(10 + big * 2, -2, 0), head=(9, -2, 0), w=0.0, feet=ft, pel=(0, -0.07 - big * 0.01, -0.02)),
            K(f + 5, "smooth", L=fistL, R=hs(0.18, 0.40, 1.28, "point", 0.7, e=(0.34, 0.12, 1.14)), tor=(8, 1, 0), head=(6, 0, 0), w=-0.2, feet=ft,
              pel=(0, -0.05, 0.0)),
        ]
    k = [K(0, L=fistL, R=hs(0.22, 0.30, 1.22, "point", 0.7, e=(0.34, 0.08, 1.10)), tor=(6, 3, 0), head=(4, 2, 0), w=0.3, feet=ft, pel=(0, -0.03, 0))]
    k += jab(16, 0)
    k += jab(42, 2, lift)     # the stamp: the left foot lifts on the wind-up and comes down with the jab
    k += jab(66, 1)
    k += [K(84, L=fistL, R=hs(0.22, 0.30, 1.22, "point", 0.7, e=(0.34, 0.08, 1.10)), tor=(6, 3, 0), head=(4, 2, 0), w=0.3, feet=ft, pel=(0, -0.03, 0))]
    k = loop(k, n)

    def rage(fr, nn, s):
        v = math.sin(2 * math.pi * 9 * fr / n)
        addt(s, (0, 0.8 * v, 0))
    return build(k, n, post=chain(alive(0.6, 0.4), rage))


@life_clip("Life_Social_Argue_B", loop=True, category="social/react", tags=["listener"], events={"step_back": [36], "step_fwd": [84]},
           pair={"partner": "Life_Social_Argue_A", "distance": 1.0},
           note="defender: palms out, head shakes, steps back half a step and forward again")
def _argue_b():
    n = 120
    ft = feet((0.14, -0.02), (-0.13, 0.08), 8.0, -10.0)
    ftb = dict(ft)
    ftb["foot_l"] = V(0.14, 0.09, 0.104)
    mid = dict(ft)
    mid["foot_l"] = V(0.14, 0.03, 0.20)
    palms = lambda z=1.30, fw=0.36, o=0.24: (hs(o, fw, z, "stop", -0.3, e=(o + 0.16, fw - 0.15, z - 0.22)),
                                              hs(o, fw, z - 0.02, "stop", -0.3, e=(o + 0.16, fw - 0.15, z - 0.24)))
    a = palms()
    b = palms(1.36, 0.30, 0.26)
    c = palms(1.30, 0.44, 0.22)
    k = [
        K(0, L=a[0], R=a[1], tor=(-3, 0, 0), head=(0, 0, 0), w=0.0, feet=ft, pel=(0, 0.0, 0)),
        K(26, L=b[0], R=b[1], tor=(-6, 0, 0), head=(0, 0, 2), w=0.2, feet=ft, pel=(0, 0.02, 0.0)),
        K(33, "smooth", L=b[0], R=b[1], tor=(-8, 0, 0), head=(0, 0, 2), w=-0.6, feet=mid, pel=(0.0, 0.05, -0.01)),
        K(40, "in2", L=b[0], R=b[1], tor=(-8, 0, 0), head=(0, 0, 2), w=-0.5, feet=ftb, pel=(0, 0.08, -0.02)),
        K(70, L=b[0], R=b[1], tor=(-7, 0, 0), head=(0, 0, 2), w=-0.5, feet=ftb, pel=(0, 0.08, -0.01)),
        K(82, "smooth", L=b[0], R=b[1], tor=(-4, 0, 0), head=(0, 0, 0), w=-0.3, feet=dict(mid, foot_l=V(0.14, 0.05, 0.20)), pel=(0, 0.05, -0.02)),
        K(88, "in2", L=c[0], R=c[1], tor=(3, 0, 0), head=(5, 0, 0), w=0.2, feet=ft, pel=(0, -0.01, -0.01)),
        K(100, L=c[0], R=c[1], tor=(2, 0, 0), head=(4, 0, 0), w=0.3, feet=ft, pel=(0, -0.01, 0)),
        K(112, L=a[0], R=a[1], tor=(-3, 0, 0), head=(0, 0, 0), w=0.0, feet=ft, pel=(0, 0, 0)),
    ]
    k = loop(k, n)

    def shakes(fr, nn, s):
        e = 1.0
        addh(s, (0, 17 * math.sin(2 * math.pi * 5 * fr / n) * e, 0))
        addt(s, (0, 3.0 * math.sin(2 * math.pi * 5 * fr / n - 0.6), 0))
        d = 0.02 * math.sin(2 * math.pi * 5 * fr / n + 1.0)
        s["hand_l"] = Vector(s["hand_l"]) + V(d, 0, 0)
        s["hand_r"] = Vector(s["hand_r"]) + V(-d, 0, 0)
    return build(k, n, post=chain(alive(0.4, 0.6), shakes))


def _look(s):
    return s


@life_clip("Life_Social_Point_Directions", category="social/react", events={"raise": [50], "point": [58], "sweep": [74], "lower": [98]},
           note="one-shot: listens with a thoughtful hand at the chin, then turns and points far off to the right, sweeps the arm along a road, turns back and nods")
def _point_dirs():
    n = 138
    chinR = hs(0.05, 0.13, 1.38, "up_in", 0.4, e=(0.28, 0.02, 1.16))
    r_hang = hs(0.27, -0.005, 0.915, "hang", 0.25)

    def turned(dv, yaw, hyaw, head, reach=0.53, **kw):
        return dict(tor=(4, yaw, 0), hip=(0, hyaw, 0), head=head, R=pt("r", dv, reach, tor_yaw=yaw + hyaw, c=-0.5), **kw)
    d1 = (-0.85, -0.45, 0.10)
    d2 = (-0.42, -0.90, 0.02)
    ftt = feet((0.12, 0.0), (-0.12, 0.07), 6.0, -6.0)
    k = [
        K(0),
        K(8, tor=(3, 0, 0), head=(1, 0, 6)),
        K(18, R=chinR, tor=(3, -2, 0), head=(-5, -6, 8), w=0.3),
        K(32, R=chinR, tor=(3, -3, 0), head=(-8, -14, 8), w=0.3),
        K(42, "out2", tor=(4, -20, 0), hip=(0, -8, 0), head=(0, -34, 0), R=hs(0.20, 0.10, 1.10, "palm_up", 0.2), w=0.0, feet=ftt),
        K(50, "smooth", **turned(d1, -30, -12, (-2, -50, 0), 0.30, feet=ftt)),
        K(58, "out2", **turned(d1, -34, -13, (-2, -55, 0), 0.545, feet=ftt)),
        K(66, "smooth", **turned(d1, -34, -13, (-2, -55, 0), 0.545, feet=ftt)),
        K(80, "smooth", **turned(d2, -34, -13, (-3, -46, 0), 0.545, feet=ftt)),
        K(90, "smooth", **turned(d2, -34, -13, (-3, -46, 0), 0.545, feet=ftt)),
        K(104, tor=(3, -6, 0), hip=(0, -2, 0), head=(3, -6, 0), R=hs(0.22, 0.12, 1.0, "palm_dn", 0.3), feet=ftt),
        K(112, "out2", tor=(3, 0, 0), head=(9, 2, 2)),
        K(118, tor=(3, 0, 0), head=(0, 0, 0)),
        K(124, tor=(3, 0, 0), head=(6, 0, 0)),
        K(n),
    ]
    return build(k, n, post=chain(alive(0.5, 0.0, True)))


def _wave_post(t0, t1, cycles, amp, tilt=0.6):
    def post(fr, n, s):
        if t0 <= fr <= t1:
            u = (fr - t0) / float(t1 - t0)
            e = smoothstep(u * 5) * smoothstep((1 - u) * 5)
            ph = math.sin(2 * math.pi * cycles * u)
            ph2 = math.sin(2 * math.pi * cycles * u - 0.7)
            s["hand_r"] = Vector(s["hand_r"]) + V(amp * ph * e, 0, 0)
            s["hq_r"] = Quaternion((0, 1, 0), tilt * ph2 * e) @ s["hq_r"]
    return post


@life_clip("Life_Social_Wave_Greet", category="social/react", events={"wave": [14]}, blend_in=0.2, blend_out=0.3,
           note="one-shot friendly wave: the hand comes up beside the head, waves three times with the fingers leading, lowers")
def _wave_greet():
    n = 72
    up = hs(0.27, 0.20, 1.50, "stop", -0.2, e=(0.40, -0.02, 1.32))
    k = [
        K(0),
        K(10, "out2", R=up, head=(-1, 3, -6), tor=(1, 3, 0), sh=(0, 3)),
        K(52, R=up, head=(1, 3, -6), tor=(1, 3, 0), sh=(0, 3)),
        K(64, "smooth", head=(0, 0, -2), tor=(2, 0, 0)),
        K(n),
    ]
    return build(k, n, post=chain(_wave_post(12, 50, 3, 0.07), alive(0.5, 0.0, True)))


@life_clip("Life_Social_Wave_Far", category="social/react", events={"wave": [16]}, blend_in=0.2, blend_out=0.3,
           note="one-shot big overhead wave for calling across the square: whole arm sweeps, body sways under it")
def _wave_far():
    n = 90
    up = hs(0.16, 0.06, 1.90, "stop", -0.3, e=(0.36, -0.05, 1.62))
    k = [
        K(0),
        K(8, "smooth", R=hs(0.26, 0.10, 1.40, "stop", -0.3), tor=(-1, 0, 2), head=(-4, 0, 3)),
        K(14, "out2", R=up, tor=(-3, 0, 5), head=(-6, 0, 6), pel=(0.02, 0, 0.012), sh=(0, 4), L=hs(0.34, 0.03, 0.96, "hang", 0.0)),
        K(72, R=up, tor=(-3, 0, 5), head=(-6, 0, 6), pel=(0.02, 0, 0.012), sh=(0, 4), L=hs(0.34, 0.03, 0.96, "hang", 0.0)),
        K(84, "smooth", R=hs(0.26, 0.10, 1.30, "stop", -0.3), tor=(1, 0, 1), head=(-1, 0, 2)),
        K(n),
    ]

    def post(fr, nn, s):
        if 14 <= fr <= 72:
            u = (fr - 14) / 58.0
            e = smoothstep(u * 6) * smoothstep((1 - u) * 6)
            ph = math.sin(2 * math.pi * 4 * u)
            ph2 = math.sin(2 * math.pi * 4 * u - 0.9)
            s["hand_r"] = Vector(s["hand_r"]) + V(0.17 * ph * e, 0, 0.0)
            s["hq_r"] = Quaternion((0, 1, 0), 0.7 * ph2 * e) @ s["hq_r"]
            addt(s, (0, 0, -3.5 * ph * e))
            addp(s, V(-0.015 * ph * e, 0, 0))
            addh(s, (0, 0, -3 * ph * e))
    return build(k, n, post=chain(post, alive(0.4, 0.0, True)))


@life_clip("Life_Social_Shrug", category="social/react", events={"peak": [16]}, blend_in=0.2, blend_out=0.3,
           note="one-shot 'who knows': shoulders up, palms out and up, head tilts, hold, drop with a small rebound")
def _shrug():
    n = 60
    o1 = dict(sh=(18, 18), tor=(-1, 0, 0), head=(-4, 0, 9), pel=(0, 0.01, 0.0),
              L=hs(0.40, 0.20, 1.04, "palm_up", -0.3, e=(0.46, -0.02, 0.98)), R=hs(0.40, 0.20, 1.04, "palm_up", -0.3, e=(0.46, -0.02, 0.98)))
    o2 = dict(o1)
    o2["sh"] = (14, 14)
    k = [
        K(0),
        K(4, "in2", tor=(3, 0, 0), head=(2, 0, 0), sh=(0, 0), L=hs(0.30, 0.10, 0.95, "palm_dn", 0.2), R=hs(0.30, 0.10, 0.95, "palm_dn", 0.2)),
        K(14, "out2", **o1),
        K(20, **o2),
        K(36, **o2),
        K(44, "smooth", tor=(3, 0, 0), sh=(-2, -2), head=(1, 0, 2), L=hs(0.30, 0.05, 0.93, "hang", 0.2), R=hs(0.30, 0.05, 0.93, "hang", 0.2)),
        K(n),
    ]
    return build(k, n, post=alive(0.4, 0.0, True))


@life_clip("Life_Social_Nod", category="social/react", events={"nod": [10, 26]}, blend_in=0.2, blend_out=0.25,
           note="one-shot: two clear nods, the second bigger, with a small chest dip")
def _nod():
    n = 48
    k = [K(0), K(8, "in2", head=(16, 0, 0), tor=(5, 0, 0), pel=(0, 0, -0.008)), K(14, "out2", head=(-2, 0, 0), tor=(2, 0, 0)),
         K(22, "in2", head=(19, 0, 0), tor=(6, 0, 0), pel=(0, 0, -0.012)), K(30, "out2", head=(-3, 0, 0), tor=(2, 0, 0)),
         K(38, "smooth", head=(2, 0, 0)), K(n)]
    return build(k, n, post=alive(0.3, 0.0, True))


@life_clip("Life_Social_Shake_Head", category="social/react", events={"shake": [8, 18, 28]}, blend_in=0.2, blend_out=0.25,
           note="one-shot: 'no' - three head swings with a counter-turn of the chest, small shoulder drop at the end")
def _shake_head():
    n = 54
    def hd(y, r=0):
        return dict(head=(1, y, r), tor=(3, -y * 0.16, 0))
    k = [K(0), K(6, "out2", **hd(22, 3)), K(14, "smooth", **hd(-24, -3)), K(22, "smooth", **hd(19, 3)), K(30, "smooth", **hd(-16, -3)),
         K(38, "smooth", head=(6, 3, 0), tor=(3, 0, 0), sh=(-2, -2)), K(46, "smooth", head=(2, 0, 0)), K(n)]
    return build(k, n, post=alive(0.3, 0.0, True))


@life_clip("Life_Social_Bow", category="social/react", events={"low": [34]}, blend_in=0.25, blend_out=0.3,
           note="one-shot polite bow: right hand to the chest, folds from the hips, holds a beat, rises")
def _bow():
    n = 96
    chest = hs(0.06, 0.13, 1.28, "chest", 0.2, e=(0.28, 0.05, 1.10))
    k = [
        K(0),
        K(14, "smooth", R=chest, L=hs(0.28, 0.0, 0.92, "hang", 0.3), tor=(4, 0, 0), head=(2, 0, 0)),
        K(34, "smooth", R=chest, L=hs(0.26, 0.04, 1.03, "hang", 0.3), tor=(30, 0, 0), hip=(24, 0, 0), head=(14, 0, 0), pel=(0, 0.11, -0.03)),
        K(52, "smooth", R=chest, L=hs(0.26, 0.04, 1.03, "hang", 0.3), tor=(30, 0, 0), hip=(24, 0, 0), head=(14, 0, 0), pel=(0, 0.11, -0.03)),
        K(72, "smooth", R=chest, L=hs(0.28, 0.0, 0.92, "hang", 0.3), tor=(3, 0, 0), head=(-3, 0, 0)),
        K(84, "smooth", R=hs(0.27, 0.0, 0.93, "hang", 0.3), head=(0, 0, 0)),
        K(n),
    ]
    return build(k, n, post=alive(0.3, 0.0, True))


# ================================================================== paired contact (author in ONE character frame)
def _hug(role):
    n = 78
    b = role == "B"
    d0 = 2 if b else 0                                # B starts its arms a fraction later
    step = feet((0.13, -0.08), (-0.12, 0.06), 6.0, -6.0)
    step0 = feet((0.12, 0.0), (-0.12, 0.07), 6.0, -6.0)
    stepm = feet((0.13, -0.04), (-0.12, 0.06), 6.0, -6.0, zl=0.15)
    o_over = ((0.2, -1, 0.1), (-1, 0, 0))            # right hand over the partner's shoulder: fingers forward, palm in
    o_under = ((0.2, -1, 0.1), (1, 0, 0))
    def hugs(zr, zl, xr=-0.16, xl=0.11, y=-0.50):
        return dict(R=hsw(xr, y, zr, ((0.3, 0, -1), (0, -1, 0)), 0.5, e=(-0.40, -0.10, zr - 0.10)),
                    L=hsw(xl, y + 0.04, zl, ((-0.3, 0, -1), (0, -1, 0)), 0.5, e=(0.36, -0.08, zl - 0.05)))
    open_arms = dict(R=hs(0.40, 0.30, 1.28, "palm_in", 0.0, e=(0.55, -0.02, 1.16)), L=hs(0.40, 0.30, 1.16, "palm_in", 0.0, e=(0.55, -0.02, 1.05)))
    k = [
        K(0),
        K(8 + d0, "smooth", tor=(4, 0, 0), head=(-2, 0, 0), pel=(0, -0.02, -0.005), feet=stepm, **open_arms),
        K(15 + d0, "smooth", tor=(7, 0, 0), head=(0, 0, 0), pel=(0, -0.04, -0.01), feet=step, **open_arms),
        K(24 + d0, "out2", tor=(8, 0, 0), head=(-3, 26, 6) if not b else (-3, 26, 6), pel=(0, -0.06, -0.015), feet=step, **hugs(1.40, 1.16)),
        K(30 + d0, "smooth", tor=(8, 0, 0), pel=(0, -0.06, -0.012), head=(-1, 26, 6), feet=step, **hugs(1.38, 1.15)),
    ]
    # pats: the over-hand pats twice (A) / the under-hand pats twice (B)
    pat = [(34, 0.045), (40, 0.045)] if not b else [(37, 0.045), (43, 0.045)]
    for f, a in pat:
        g1 = hugs(1.38 - (a if not b else 0), 1.15 - (a if b else 0))
        k.append(K(f, "in2", tor=(8, 0, 0), pel=(0, -0.06, -0.012), head=(-1, 26, 6), feet=step, **g1))
        g2 = hugs(1.40, 1.16)
        k.append(K(f + 3, "out2", tor=(8, 0, 0), pel=(0, -0.06, -0.012), head=(-1, 26, 6), feet=step, **g2))
    k += [
        K(52, tor=(8, 0, 0), pel=(0, -0.06, -0.012), head=(-1, 24, 5), feet=step, **hugs(1.40, 1.16)),
        K(60 + d0, "smooth", tor=(6, 0, 0), pel=(0, -0.04, -0.01), head=(0, 10, 2), feet=stepm, **open_arms),
        K(68, "smooth", tor=(3, 0, 0), pel=(0, -0.02, 0), head=(0, 3, 0), feet=step0,
          L=hs(0.28, 0.02, 0.92, "hang", 0.3), R=hs(0.28, 0.02, 0.92, "hang", 0.3)),
        K(n),
    ]
    k = sorted(k, key=lambda x: x[0])
    return build(k, n, post=alive(0.35, 0.0, True))


for _r, _p in (("A", "B"), ("B", "A")):
    life_clip("Life_Social_Hug_" + _r, category="social/pair", events={"embrace": [24], "pat": [34, 40] if _r == "A" else [37, 43], "release": [60]},
              pair={"partner": "Life_Social_Hug_" + _p, "distance": 0.40}, blend_in=0.2, blend_out=0.3,
              note="paired hug %s: half-step in, arms wrap (right over the partner's left shoulder, left under), head to the partner's right shoulder, two pats, release. Author distance 0.40 m." % _r)(
        (lambda r: (lambda: _hug(r)))(_r))


def _handshake(role):
    n = 72
    b = role == "B"
    d0 = 1 if b else 0
    ho = ((0, -1, 0.15), (1, 0, 0))
    g = lambda z, x=-0.028, y=-0.40: dict(R=hsw(*tuple(wrist_at("r", V(x, y, z), ho)), ho, 0.7))
    r_open = lambda z, x=-0.028, y=-0.40: dict(R=hsw(*tuple(wrist_at("r", V(x, y, z), ho)), ho, -0.5))
    pump_hi, pump_lo = 1.06, 0.97
    ft = feet((0.12, -0.03), (-0.12, 0.07), 6.0, -6.0)
    lean = dict(tor=(8, 0, 0), pel=(0, -0.09, -0.005))
    k = [
        K(0),
        K(8 + d0, "smooth", R=hs(0.25, 0.18, 1.0, "palm_in", -0.5), tor=(5, 0, 0), head=(0, 0, 0), pel=(0, -0.04, 0), feet=ft),
        K(15 + d0, "out2", head=(3, 0, 0), feet=ft, **lean, **r_open(1.02, -0.045)),
        K(20 + d0, "smooth", head=(3, 0, 0), feet=ft, **lean, **g(1.02)),
        K(26 + d0, "in2", head=(6, 0, 0), feet=ft, **lean, **g(pump_lo)),
        K(31 + d0, "out2", head=(2, 0, 0), feet=ft, **lean, **g(pump_hi)),
        K(37 + d0, "in2", head=(6, 0, 0), feet=ft, **lean, **g(pump_lo)),
        K(42 + d0, "out2", head=(2, 0, 0), feet=ft, **lean, **g(pump_hi)),
        K(48 + d0, "smooth", head=(3, 0, 0), feet=ft, **lean, **g(1.02)),
        K(54 + d0, "smooth", head=(1, 0, 0), feet=ft, R=hs(0.25, 0.18, 1.0, "palm_in", -0.3), tor=(4, 0, 0), pel=(0, -0.03, 0)),
        K(64, "smooth", head=(0, 0, 0), feet=ft),
        K(n),
    ]
    return build(k, n, post=alive(0.35, 0.0, True))


for _r, _p in (("A", "B"), ("B", "A")):
    life_clip("Life_Social_Handshake_" + _r, category="social/pair", events={"clasp": [20], "pump": [26, 31, 37, 42], "release": [54]},
              pair={"partner": "Life_Social_Handshake_" + _p, "distance": 0.80}, blend_in=0.2, blend_out=0.3,
              note="paired handshake %s: right hands meet at ~1.0 m in the middle, two firm pumps, release. Author distance 0.80 m." % _r)(
        (lambda r: (lambda: _handshake(r)))(_r))


# ================================================================== mourning
FT_KNEEL = {"foot_l": V(0.14, -0.27, 0.104), "foot_r": V(-0.11, 0.50, 0.21), "fyaw_l": 4.0, "fyaw_r": -4.0, "fpit_l": 0.0, "fpit_r": -42.0}
O_FACE_R = ((0.3, 0, 1), (0, 1, 0))
O_FACE_L = ((-0.3, 0, 1), (0, 1, 0))


def _kneel(**over):
    """head in hands, kneeling on the right knee (left foot forward), torso folded"""
    d = dict(pel=(0, -0.02, -0.45), hip=(6, 0, 0), tor=(26, 0, 0), head=(14, 0, 0), feet=FT_KNEEL,
             R=hsw(-0.075, -0.40, 1.02, O_FACE_R, 0.6, e=(-0.30, -0.10, 0.75)), L=hsw(0.075, -0.40, 1.03, O_FACE_L, 0.6, e=(0.30, -0.10, 0.75)))
    d.update(over)
    return d


_LOWR = hsw(-0.17, -0.30, 0.72, ((0, -0.4, -1), (1, 0, 0)), 0.4)
_LOWL = hsw(0.17, -0.30, 0.72, ((0, -0.4, -1), (-1, 0, 0)), 0.4)


def _mourn_shake(hz, amp, t0=0, t1=1e9):
    def post(fr, n, s):
        e = win(fr, t0, min(t1, n), 4, 4) if (t0 > 0 or t1 < 1e8) else 1.0
        v = math.sin(2 * math.pi * hz * fr / float(n))
        v2 = math.sin(2 * math.pi * hz * fr / float(n) - 0.9)
        addt(s, (amp * 1.6 * v * e, 0, 0))
        addp(s, V(0, 0, 0.004 * amp * v * e))
        addsh(s, 3.0 * amp * v2 * e, 3.0 * amp * v2 * e)
        addh(s, (1.4 * amp * v2 * e, 0, 0))
        for side, sg in (("hand_l", 1), ("hand_r", 1)):
            s[side] = Vector(s[side]) + V(0, 0, 0.006 * amp * v2 * e)
    return post


@life_clip("Life_Social_Mourn_Kneel", loop=True, category="social/mourn", enter="Life_Social_Mourn_Kneel_Enter",
           exit="Life_Social_Mourn_Kneel_Exit", tags=["grief"], blend_in=0.3, blend_out=0.3,
           note="loop: kneeling on the right knee, face in both hands, shoulders shake with sobs, a slow deep breath every 2 s")
def _mourn_kneel():
    n = 120
    a = _kneel()
    k = [K(0, **a), K(30, **_kneel(tor=(29, 0, 1), head=(17, 0, 2))), K(60, **_kneel(tor=(24, 0, -1), head=(12, 3, -2))),
         K(90, **_kneel(tor=(28, 0, 1), head=(16, -3, 2)))]
    k = loop(k, n)
    return build(k, n, post=chain(_mourn_shake(14, 1.0), alive(0.5, 0.2, br=0.006)))


@life_clip("Life_Social_Mourn_Kneel_Enter", category="social/mourn", note="drops to the right knee, folds forward and lifts the hands to the face; ends on the first frame of Mourn_Kneel",
           blend_in=0.25, blend_out=0.0)
def _mourn_kneel_in():
    n = 40
    k = [
        K(0),
        K(8, "smooth", head=(10, 0, 0), tor=(8, 0, 0), pel=(0.02, 0, -0.10), w=0.0, L=hs(0.28, 0.06, 0.93, "hang", 0.3), R=hs(0.28, 0.06, 0.93, "hang", 0.3),
          feet=dict(FT_KNEEL, foot_r=V(-0.12, 0.20, 0.10), fpit_r=-10.0, foot_l=V(0.13, -0.10, 0.104))),
        K(18, "smooth", head=(12, 0, 0), tor=(16, 0, 0), hip=(4, 0, 0), pel=(0.0, 0.0, -0.30), L=hs(0.24, 0.05, 0.98, "hang", 0.4), R=hs(0.24, 0.05, 0.98, "hang", 0.4),
          feet=dict(FT_KNEEL, foot_r=V(-0.11, 0.42, 0.20), fpit_r=-35.0, foot_l=V(0.14, -0.22, 0.104))),
        K(28, "out", **_kneel(R=_LOWR, L=_LOWL)),
        K(n, "smooth", **_kneel()),
    ]
    return build(k, n)


@life_clip("Life_Social_Mourn_Kneel_Exit", category="social/mourn", note="from Mourn_Kneel: hands drop, pushes up off the knee and stands; ends at neutral",
           blend_in=0.0, blend_out=0.3)
def _mourn_kneel_out():
    n = 40
    k = [
        K(0, **_kneel()),
        K(8, "smooth", **_kneel(R=_LOWR, L=_LOWL, head=(8, 0, 0), tor=(22, 0, 0))),
        K(20, "smooth", head=(6, 0, 0), tor=(16, 0, 0), hip=(4, 0, 0), pel=(0.0, -0.01, -0.28), L=hs(0.24, 0.05, 0.98, "hang", 0.4), R=hs(0.24, 0.05, 0.98, "hang", 0.4),
          feet=dict(FT_KNEEL, foot_r=V(-0.11, 0.42, 0.20), fpit_r=-35.0, foot_l=V(0.14, -0.22, 0.104))),
        K(32, "smooth", head=(2, 0, 0), tor=(6, 0, 0), pel=(0.0, 0.0, -0.08), feet=dict(FT_KNEEL, foot_r=V(-0.12, 0.16, 0.10), fpit_r=-8.0, foot_l=V(0.13, -0.06, 0.104))),
        K(n, "smooth"),
    ]
    return build(k, n)


@life_clip("Life_Social_Mourn_Stand", loop=True, category="social/mourn", tags=["grief"], events={"wipe": [96, 106, 116, 126]},
           note="loop: standing, head bowed, hands clasped low; small sobbing breaths, and now and then the right hand wipes the eyes")
def _mourn_stand():
    n = 180
    ft = feet((0.10, 0.0), (-0.10, 0.04), 4.0, -4.0)
    cl = ((-0.2, 0.7, -0.6), (-1, 0, 0))
    hands = dict(L=hs(0.06, 0.17, 1.00, cl, 0.9), R=hs(0.06, 0.18, 1.01, cl, 0.9))
    base = dict(tor=(11, 0, 0), head=(24, 2, 3), pel=(0, 0.0, -0.005), feet=ft, sh=(-2, -2), **hands)
    wipe = dict(tor=(13, 0, 0), head=(26, 2, 5), pel=(0, 0.0, -0.005), feet=ft, sh=(0, 3), L=hands["L"],
                R=hs(0.045, 0.18, 1.46, "face", 0.3, e=(0.30, 0.0, 1.27)))
    k = [K(0, **base), K(60, **dict(base, tor=(12, 0, 0), head=(27, -2, 4))), K(78, **dict(base, tor=(10, 0, 0), head=(21, 3, 3))),
         K(96, "smooth", **wipe), K(126, "smooth", **wipe), K(144, "smooth", **dict(base, head=(26, 0, 4))),]
    k = loop(k, n)

    def post(fr, nn, s):
        # eye wipe
        e = win(fr, 98, 126, 6, 6)
        v = math.sin(2 * math.pi * 3.0 * (fr - 98) / 28.0)
        s["hand_r"] = Vector(s["hand_r"]) + V(0.028 * v * e, 0, 0)
        # sniffs
        for f in (60, 150):
            q = win(fr, f - 2, f + 8, 2, 6)
            addsh(s, 6 * q, 6 * q)
            addt(s, (1.5 * q, 0, 0))
        addt(s, (0.6 * math.sin(2 * math.pi * 9 * fr / n), 0, 0))
    return build(k, n, post=chain(alive(0.5, 0.3), post))
