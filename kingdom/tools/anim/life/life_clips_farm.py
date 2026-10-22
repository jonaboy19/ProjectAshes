# LIFE work clips, part 1: farming (hoe, sow, harvest, milking, chickens, sheaf carry) + the shared "work kit" that
# life_clips_craft.py and life_clips_chores.py import (WK).
#
#   blender -b -P author_life.py -- <out.glb> life_clips_farm,life_clips_craft,life_clips_chores [clip,...]
#
# WORK KIT (tool-centric, fully procedural clips)
#   Every clip is a function state(fr, n) -> complete state dict (see life_common.neutral), evaluated for frames 0..n.
#   Loops are periodic functions (frame n == frame 0). Enter/exit clips are a procedural transition between neutral and
#   the loop's frame-0 state (feet step one after the other, hips shift over the planted foot, hands arrive last).
#   Tools are keyed by the GRIP POINT G (fist centre), the tool direction D (grip axis, thumb side -> working end) and
#   the knuckle direction K (fingers = the tool's front: striking face / blade edge). For a tool swung in the sagittal
#   plane K = X x D (the face leads the swing). grip2 holds the same handle with the left hand.
#   fit() adds forward lean (hip + spine pitch, a little squat, head compensation) until both wrists are inside the
#   arm's reach; the shoulder position comes from a lookup table sampled from the real rig at import time.
#   ASSUMED PROP LENGTHS (grip origin -> working end, m) are constants below: change them if a modelled prop differs.
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V
import life_common as LC
from life_common import life_clip, neutral, grip_o, wrist_at

F = CC.F
FPS = 30
PEL0 = Vector((0, 0.05, 0.917))
XAX = Vector((1, 0, 0))
ZAX = Vector((0, 0, 1))

# grip origin -> working end (metres) of the hand props (assumed until the GLBs exist)
LEN = {"hoe": 1.2, "sickle": 0.30, "smith_hammer": 0.30, "tongs": 0.42, "saw": 0.55, "hammer": 0.27, "axe": 0.24,
       "rod": 2.2, "ladle": 0.36, "knife": 0.20, "broom": 1.05}


def P(x, fwd, z):
    """character-frame point: x left, fwd metres in front of the root, z up  ->  world (armature) vector"""
    return V(x, -fwd, z)


def vec(v):
    return Vector(v)


# ------------------------------------------------------------------ interpolation
def ez(kind, t):
    return F._ease(kind, t)


def mix(a, b, t):
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    if isinstance(a, Vector):
        return a.lerp(Vector(b), t)
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def wp(keys, fr):
    """waypoint track: keys = [(frame, value[, ease])], ease describes the segment ARRIVING at the key"""
    if fr <= keys[0][0]:
        return keys[0][1]
    for a, b in zip(keys, keys[1:]):
        if a[0] <= fr <= b[0]:
            e = b[2] if len(b) > 2 else "smooth"
            return mix(a[1], b[1], ez(e, (fr - a[0]) / float(b[0] - a[0])))
    return keys[-1][1]


def arc(a, b, t, bulge):
    """point on a curved path a->b (t 0..1) bulging by the vector `bulge` at the middle"""
    return Vector(a).lerp(Vector(b), t) + Vector(bulge) * math.sin(math.pi * t)


def sw(fr, n, k=1, ph=0.0):
    return math.sin(2 * math.pi * (k * fr / float(n) + ph))


def cw(fr, n, k=1, ph=0.0):
    return math.cos(2 * math.pi * (k * fr / float(n) + ph))


def pulse(fr, a, b, c, d):
    """0 before a, smooth 0->1 over a..b, 1 until c, smooth 1->0 over c..d"""
    if fr <= a or fr >= d:
        return 0.0
    if fr < b:
        return ez("smooth", (fr - a) / float(b - a))
    if fr <= c:
        return 1.0
    return 1.0 - ez("smooth", (fr - c) / float(d - c))


# ------------------------------------------------------------------ states
def S(**kw):
    """complete neutral-based state; shrug defaults to automatic (raised when the hand is above the shoulder)"""
    s = neutral()
    s["shrug_l"] = None
    s["shrug_r"] = None
    s["root"] = V(0, 0, 0)
    for k, v in kw.items():
        s[k] = v
    return s


def finish(s):
    s = dict(s)
    s.setdefault("root", V(0, 0, 0))
    for side in ("l", "r"):
        s["hq_" + side] = F.hand_q(side, *s["ho_" + side])
    return s


def poses(fn, n):
    """Pose list for frames 0..n of a state function fn(fr) -> state"""
    return [F.state_to_pose(finish(fn(fr))) for fr in range(n + 1)]


# ------------------------------------------------------------------ shoulder model (LUT sampled from the rig)
_LUT = {}
_HS = list(range(-30, 91, 10))
_TS = list(range(-40, 71, 10))


def _build_lut():
    for h in _HS:
        for t in _TS:
            s = S()
            s["hip"] = (float(h), 0.0, 0.0)
            s["tor"] = (float(t), 0.0, 0.0)
            F.apply_pose(F.state_to_pose(finish(s)))
            b = F.tgt.pose.bones["upperarm_l"].head
            _LUT[(h, t)] = (b.y, b.z)


def _lut(h, t):
    h = max(_HS[0], min(_HS[-1] - 1e-6, h))
    t = max(_TS[0], min(_TS[-1] - 1e-6, t))
    h0 = int(math.floor(h / 10.0)) * 10
    t0 = int(math.floor(t / 10.0)) * 10
    fh, ft = (h - h0) / 10.0, (t - t0) / 10.0
    r = []
    for i in (0, 1):
        a = _LUT[(h0, t0)][i] * (1 - ft) + _LUT[(h0, t0 + 10)][i] * ft
        b = _LUT[(h0 + 10, t0)][i] * (1 - ft) + _LUT[(h0 + 10, t0 + 10)][i] * ft
        r.append(a * (1 - fh) + b * fh)
    return r


def shoulder(s, side):
    """approximate world position of the shoulder joint (upperarm head) for a state"""
    sx = 1 if side == "l" else -1
    y, z = _lut(s["hip"][0], s["tor"][0])
    yaw = math.radians(s["hip"][1] + s["tor"][1])
    dx, dy = 0.192 * sx, y - 0.005
    x2 = dx * math.cos(yaw) - dy * math.sin(yaw)
    y2 = dx * math.sin(yaw) + dy * math.cos(yaw) + 0.005
    roll = s["hip"][2] + s["tor"][2]
    x2 += 0.0035 * roll
    z += -0.0033 * roll * sx
    return Vector((x2, y2, z)) + Vector(s["pel"])


def fit(s, rmax=0.505, split=0.6, lmax=75.0, back=0.0022, squat=0.0011, headk=0.45):
    """Add forward lean until both wrist targets are within rmax of their shoulders. Mutates s."""
    bh, bt = s["hip"], s["tor"]
    bp, bhd = Vector(s["pel"]), s["head"]

    def apply(lam):
        s["hip"] = (bh[0] + split * lam, bh[1], bh[2])
        s["tor"] = (bt[0] + (1 - split) * lam, bt[1], bt[2])
        s["pel"] = bp + V(0, back * lam, -squat * lam)
        s["head"] = (bhd[0] - headk * lam, bhd[1], bhd[2])

    def over():
        return max((Vector(s["hand_" + sd]) - shoulder(s, sd)).length for sd in "lr") - rmax

    apply(0.0)
    if over() <= 0:
        return 0.0
    lam = 3.0
    prev = 0.0
    while lam <= lmax:
        apply(lam)
        if over() <= 0:
            lo, hi = prev, lam
            for _ in range(7):
                mid = (lo + hi) / 2
                apply(mid)
                if over() <= 0:
                    hi = mid
                else:
                    lo = mid
            apply(hi)
            return hi
        prev = lam
        lam += 3.0
    apply(lmax)
    return lmax


# ------------------------------------------------------------------ grips
def sag_K(D):
    """knuckle direction for a tool swung in the sagittal plane (face leads the swing): X x D"""
    return XAX.cross(Vector(D).normalized())


def auto_K(s, side, G, D):
    sx = 1 if side == "l" else -1
    sh = shoulder(s, side)
    el = (sh + Vector(G)) * 0.5 + V(sx * 0.35, 0.25, -0.30)
    fa = Vector(G) - el
    D = Vector(D).normalized()
    k = fa - D * fa.dot(D)
    if k.length < 0.12:
        k = V(0, -1, 0) - D * D.y * -1.0
    return k.normalized()


def grips(s, gl, fitlean=True, **fk):
    """gl = [(side, G, D, K|None[, curl]), ...]: set hands/orientations for those grips (fist centre G, thumb axis D,
    knuckles K), optionally add reach-fitting lean. Grips may be given for one hand only."""
    def setall():
        for g in gl:
            side, G, D, K = g[0], vec(g[1]), vec(g[2]).normalized(), g[3]
            curl = g[4] if len(g) > 4 else 0.95
            kk = K if K is not None else auto_K(s, side, G, D)
            ho = grip_o(side, D, kk)
            s["ho_" + side] = ho
            s["hand_" + side] = wrist_at(side, G, ho)
            s["curl_" + side] = curl
    setall()
    lam = 0.0
    if fitlean:
        lam = fit(s, **fk)
        setall()
    s["_lean"] = lam
    return s


def tool2(s, G, D, K, dl, **fk):
    """right hand at G, left hand dl metres further along D on the same handle"""
    D = vec(D).normalized()
    return grips(s, [("r", G, D, K), ("l", vec(G) + D * dl, D, K)], **fk)


def from_tip(tip, theta_deg, length, yaw_deg=0.0):
    """grip point and direction of a tool whose working end is at `tip`: D = (sin(yaw)... ) sagittal tilt theta from
    straight up towards forward(-Y); yaw_deg turns the swing plane to the left."""
    th, ya = math.radians(theta_deg), math.radians(yaw_deg)
    Dl = V(0, -math.sin(th), math.cos(th))
    D = V(Dl.x * math.cos(ya) - Dl.y * math.sin(ya), Dl.x * math.sin(ya) + Dl.y * math.cos(ya), Dl.z)
    return vec(tip) - D * length, D


def stance(s, lx=0.15, ly=0.0, rx=-0.15, ry=0.10, yl=6.0, yr=-10.0):
    """foot placement in character terms: ly/ry = metres BEHIND the root line (+ = back; forward is -Y)"""
    s["foot_l"] = V(lx, ly, 0.104)
    s["foot_r"] = V(rx, ry, 0.104)
    s["fyaw_l"] = yl
    s["fyaw_r"] = yr
    return s


def breath(s, fr, n, amp=0.005, k=1, ph=0.0):
    w = sw(fr, n, k, ph)
    s["pel"] = Vector(s["pel"]) + V(0, 0, amp * w)
    s["tor"] = (s["tor"][0] + 0.9 * w, s["tor"][1], s["tor"][2])


def addv(s, key, d):
    s[key] = Vector(s[key]) + Vector(d)


def addt(s, key, d):
    s[key] = tuple(a + b for a, b in zip(s[key], d))


# ------------------------------------------------------------------ transitions (enter / exit)
_BODY = ("pel", "hip", "tor", "head", "hand_l", "hand_r", "elb_l", "elb_r", "curl_l", "curl_r", "shrug_l", "shrug_r")


def transit(a, b, n, first="r", lift=0.07, sway=0.05, t_body=(0.10, 0.95), t_hands=(0.30, 1.0), t_feet=(0.05, 0.75),
            dip=0.03, hand_bow=0.0):
    """Pose list (n+1) blending state a -> b: the feet step one after the other (first = which foot goes first) with a
    lift arc, the pelvis shifts over the planted foot before each step, then torso, head and hands arrive."""
    a, b = finish(a), finish(b)
    out = []
    f2 = "l" if first == "r" else "r"
    for fr in range(n + 1):
        u = fr / float(n)
        tb = ez("smooth", (u - t_body[0]) / (t_body[1] - t_body[0]))
        th = ez("smooth", (u - t_hands[0]) / (t_hands[1] - t_hands[0]))
        s = F.interp_state(a, b, tb)
        h = F.interp_state(a, b, th)
        for k in ("hand_l", "hand_r", "elb_l", "elb_r", "curl_l", "curl_r", "ho_l", "ho_r"):
            pass
        for side in ("l", "r"):
            s["hand_" + side] = h["hand_" + side]
            s["hq_" + side] = h["hq_" + side]
            s["curl_" + side] = h["curl_" + side]
            s["elb_" + side] = h["elb_" + side]
        if hand_bow:
            for side in ("l", "r"):
                s["hand_" + side] = s["hand_" + side] + V(0, 0, hand_bow) * math.sin(math.pi * th)
        # feet: two windows (first foot early, second foot later)
        span = t_feet[1] - t_feet[0]
        w1 = (t_feet[0], t_feet[0] + span * 0.55)
        w2 = (t_feet[0] + span * 0.40, t_feet[1])
        bump = 0.0
        for side, w in ((first, w1), (f2, w2)):
            fa, fb = Vector(a["foot_" + side]), Vector(b["foot_" + side])
            moved = (fa - fb).length > 0.01 or abs(a["fyaw_" + side] - b["fyaw_" + side]) > 2
            q = ez("smooth", (u - w[0]) / (w[1] - w[0]))
            p = fa.lerp(fb, q)
            if moved:
                p.z += lift * math.sin(math.pi * q) if 0 < q < 1 else 0.0
                bump += math.sin(math.pi * q) if 0 < q < 1 else 0.0
            s["foot_" + side] = p
            s["fyaw_" + side] = a["fyaw_" + side] + (b["fyaw_" + side] - a["fyaw_" + side]) * q
            s["fpit_" + side] = a["fpit_" + side] + (b["fpit_" + side] - a["fpit_" + side]) * q
            if moved and 0 < q < 1:   # weight over the other foot while this one lifts
                sh = 1 if side == "r" else -1
                s["pel"] = Vector(s["pel"]) + V(sway * sh * math.sin(math.pi * q), 0, -dip * math.sin(math.pi * q))
        out.append(F.state_to_pose(s))
    return out


def register_pair(name, fn, n, n_enter=15, n_exit=13, first_in="r", first_out="l", **tk):
    """Enter (neutral -> fn(0)) and Exit (fn(0) -> neutral) clips for a loop; returns their names"""
    a = fn(0, n)

    @life_clip(name + "_Enter", category=LC.LIFE[name]["category"], props=LC.LIFE[name]["props"],
               ik_l_on_prop=LC.LIFE[name]["ik_l_on_prop"], anchor=LC.LIFE[name]["anchor"], blend_in=0.2, blend_out=0.15)
    def _e():
        return transit(neutral(), fn(0, n), n_enter, first=first_in, **tk)

    @life_clip(name + "_Exit", category=LC.LIFE[name]["category"], props=LC.LIFE[name]["props"],
               ik_l_on_prop=LC.LIFE[name]["ik_l_on_prop"], anchor=LC.LIFE[name]["anchor"], blend_in=0.15, blend_out=0.25)
    def _x():
        tx = dict(tk)
        for kk, dv in (("t_body", (0.10, 0.95)), ("t_hands", (0.30, 1.0)), ("t_feet", (0.05, 0.75))):
            w = tk.get(kk, dv)
            tx[kk] = (1.0 - w[1], 1.0 - w[0])          # time-mirrored windows: hands leave first, feet last
        return transit(fn(0, n), neutral(), n_exit, first=first_out, **tx)
    return name + "_Enter", name + "_Exit"


def work_clip(name, n, fn, loop=True, enter_exit=False, n_enter=15, n_exit=13, tr=None, **meta):
    """Register a procedural clip. fn(fr, n) -> state. With enter_exit the _Enter/_Exit clips are registered too."""
    if enter_exit:
        meta["enter"] = name + "_Enter"
        meta["exit"] = name + "_Exit"
    life_clip(name, loop=loop, **meta)(lambda: poses(lambda fr: fn(fr, n), n))
    if enter_exit:
        register_pair(name, fn, n, n_enter, n_exit, **(tr or {}))


_build_lut()
# ============================================================================================ FARM


# ---------------------------------------------------------------------------------------------- hoe
# hoe.glb (round 3): grip origin = right hand, 0.50 m above the butt; handle end 0.88 m along +Z, blade extends 0.27 m along the front axis (-Y = K)
HOE_LH, HOE_LB, HOE_DL = 0.88, 0.27, -0.40
# (the right fist sits at the prop origin next to the butt, so the left hand can only sit just above it: DL = -0.14.
#  A wider two-hand grip needs the prop origin moved ~0.35 m along the handle and HOE_DL = -0.35.)


def edge_G(E, th, lh, lb):
    """grip point of a sagittal-plane tool whose cutting edge is at E: handle tilted th deg from straight up towards
    forward, edge extends lb along K = X x D from the handle end (lh along D)"""
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    return Vector(E) - D * lh - sag_K(D) * lb


def hoe(fr, n):
    half = n // 2
    i = fr % n
    c, sub = i // half, i - (i // half) * half
    xs = (-0.05, 0.12)
    xc, xp = xs[c], xs[(c - 1) % 2]
    Gd = edge_G(P(xp, 0.32, 0.03), 150, HOE_LH, HOE_LB)
    Gm = P((xp + xc) * 0.5, 0.05, 1.22)
    Gr = P(xc - 0.02, 0.10, 1.38)                      # ready: hands at shoulder height, blade forward and down
    Gr2 = P(xc - 0.02, 0.11, 1.40)
    Gc = edge_G(P(xc, 0.60, -0.005), 142, HOE_LH, HOE_LB)
    Gb = edge_G(P(xc, 0.60, -0.03), 145, HOE_LH, HOE_LB)
    Ge = edge_G(P(xc, 0.32, 0.03), 150, HOE_LH, HOE_LB)
    keys_g = [(0, Gd), (9, Gm, "smooth"), (17, Gr, "smooth"), (19, Gr2, "smooth"), (25, Gc, "in2"), (27, Gb, "out2"),
              (40, Ge, "smooth"), (42, Ge, "smooth")]
    keys_t = [(0, 150.0), (9, 100.0), (17, 52.0), (19, 48.0), (25, 142.0, "in2"), (27, 145.0, "out2"), (40, 150.0), (42, 150.0)]
    G = wp(keys_g, sub)
    th = wp(keys_t, sub)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    s = S()
    stance(s, 0.18, -0.13, -0.16, 0.13, 12.0, -22.0)
    up = pulse(sub, 0, 15, 20, 26)                      # body straightens for the lift
    hit = pulse(sub, 20, 25, 27, 34)
    s["pel"] = V(0.02 * (xc * 6), -0.02 * hit, -0.07 + 0.03 * up - 0.03 * hit)
    s["hip"] = (10.0 - 6.0 * up + 6.0 * hit, 8.0 * (xc * 4) * 0.6, 0.0)
    s["tor"] = (6.0 - 6.0 * up + 4.0 * hit, -8.0 * (xc * 4) * 0.6, 0.0)
    s["head"] = (12.0 - 8.0 * up, 0.0, 0.0)
    tool2(s, G, D, sag_K(D), HOE_DL, headk=0.3, lmax=40)
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Farm_Hoe", 84, hoe, loop=True, enter_exit=True, category="work/farm", props=[{"id": "hoe", "hand": "r"}],
          ik_l_on_prop=HOE_DL, anchor={"type": "field_row", "at": [0.0, 0.60, 0.0], "size": [1.0, 0.5, 0.06]},
          events={"contact": [25, 67]}, note="two calm strokes per 2.8 s: lift to shoulder height, blade forward and down, chop, drag back to the feet; the second lands 0.17 m to the left")


def HOw(keys, fr):
    """hand-orientation track: keys = [(frame, (fingers, palm)[, ease])] -> (fingers, palm) tuples (lerp + normalise)"""
    ks = [(k[0], (Vector(k[1][0]).normalized(), Vector(k[1][1]).normalized())) + tuple(k[2:]) for k in keys]
    f = wp([(k[0], k[1][0]) + tuple(k[2:]) for k in ks], fr)
    p = wp([(k[0], k[1][1]) + tuple(k[2:]) for k in ks], fr)
    return (tuple(f.normalized()), tuple(p.normalized()))


def at_sh(s, side, dx, dfwd, dz):
    """point relative to a shoulder (dx to the character's left, dfwd forward, dz up): a hand that rides with the body"""
    return shoulder(s, side) + V(dx, -dfwd, dz)


def hand1(s, side, wrist, ho, curl=None):
    s["hand_" + side] = Vector(wrist)
    s["ho_" + side] = ho
    if curl is not None:
        s["curl_" + side] = curl


# ---------------------------------------------------------------------------------------------- sow
def sow(fr, n):
    s = S()
    stance(s, 0.16, -0.10, -0.16, 0.10, 8.0, -16.0)
    KP = [(0, P(0.12, 0.17, 0.98)), (7, P(0.13, 0.15, 0.93), "smooth"), (17, P(-0.30, 0.08, 1.12), "smooth"),
          (28, P(-0.48, -0.10, 1.20), "smooth"), (33, P(-0.30, 0.30, 1.14), "in2"), (37, P(-0.08, 0.42, 1.10), "lin"),
          (46, P(0.10, 0.46, 1.00), "out"), (64, P(0.20, 0.30, 1.00), "smooth"), (84, P(0.12, 0.17, 0.98), "smooth")]
    hr = wp(KP, fr)
    KC = [(0, 0.3), (7, 0.3), (9, 0.85, "out2"), (28, 0.8), (36, 0.8), (38, 0.0, "out2"), (60, 0.2), (84, 0.3)]
    HO = [(0, ((0.5, -0.3, -0.8), (0.6, 0.0, -0.3))), (7, ((0.5, -0.3, -0.8), (0.6, 0.0, -0.3))),
          (17, ((0.0, -0.4, -0.5), (0.0, 0.2, 1.0))), (28, ((0.0, -0.6, -0.3), (0.0, 0.0, 1.0))),
          (38, ((0.15, -1.0, 0.15), (0.0, 0.0, 1.0))), (60, ((0.3, -0.7, -0.5), (0.3, 0.0, 0.9))),
          (84, ((0.5, -0.3, -0.8), (0.6, 0.0, -0.3)))]
    hand1(s, "r", hr, HOw(HO, fr), wp(KC, fr))
    dip = wp([(0, 1.0), (9, 1.0), (17, 0.0), (68, 0.0), (84, 1.0)], fr)
    offl = V(0.06, -0.10, -0.41).lerp(V(-0.06, -0.24, -0.36), min(1.0, dip))
    # body: wind up (turn right, sink), throw (turn left, weight to the front foot), recover
    yaw = wp([(0, 8.0), (10, 0.0), (28, -26.0), (37, 28.0, "in2"), (48, 22.0, "out"), (70, 10.0), (84, 8.0)], fr)
    wt = wp([(0, 0.0), (28, -0.05), (37, 0.05), (52, 0.05), (84, 0.0)], fr)
    fwd = wp([(0, 0.0), (28, 0.03), (37, -0.05, "in2"), (52, -0.04), (84, 0.0)], fr)
    s["pel"] = V(wt, fwd, -0.05 - 0.02 * pulse(fr, 20, 28, 30, 37))
    s["hip"] = (6.0, yaw * 0.4, 0.0)
    s["tor"] = (10.0 + 4 * pulse(fr, 0, 6, 12, 18) - 6 * pulse(fr, 30, 37, 44, 56), yaw * 0.7, 0.0)
    s["head"] = (6.0, -yaw * 0.25, 0.0)
    for _ in range(2):
        hand1(s, "l", at_sh(s, "l", offl.x, -offl.y, offl.z) + V(0, 0, 0.006 * sw(fr, n, 2)), ((0.0, -0.05, -1.0), (1.0, 0.0, 0.0)), 0.95)
        fit(s, headk=0.2)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Farm_Sow", 84, sow, loop=True, category="work/farm",
          props=[{"id": "seed_bag", "hand": "l"}], events={"contact": [37], "grab": [8]},
          note="dip the right hand in the bag on the left hip, wind up, broadcast palm-up, follow through")


# ---------------------------------------------------------------------------------------------- harvest
def harvest(fr, n):
    L = LEN["sickle"]
    half = n // 2
    i = fr % n
    c, sub = i // half, i - (i // half) * half
    xs = (-0.02, 0.16)
    xc, xp = xs[c], xs[(c - 1) % 2]
    s = S()
    stance(s, 0.17, -0.10, -0.15, 0.12, 8.0, -14.0)
    # left hand: reach the stalks, hold them through the cut, carry the cut bundle to the left side, drop, come back
    KL = [(0, P(xp + 0.30, 0.20, 0.72)), (7, P(xc + 0.10, 0.48, 0.56), "smooth"), (17, P(xc + 0.10, 0.47, 0.56), "smooth"),
          (22, P(xc + 0.10, 0.44, 0.58), "smooth"), (31, P(0.34, 0.16, 0.78), "smooth"), (36, P(0.38, 0.12, 0.70), "smooth"),
          (40, P(0.34, 0.16, 0.76), "smooth"), (45, P(xc + 0.30, 0.20, 0.72), "smooth")]
    KLc = [(0, 0.2), (6, 0.2), (8, 0.95, "out2"), (33, 0.95), (35, 0.0, "out2"), (45, 0.2)]
    hl = wp(KL, sub)
    hand1(s, "l", hl, HOw([(0, ((0.0, -1.0, -0.2), (1.0, 0.0, 0.0))), (22, ((0.0, -1.0, -0.3), (1.0, 0.0, 0.0))),
                           (33, ((0.0, -0.5, -0.9), (1.0, 0.0, 0.0))), (45, ((0.0, -1.0, -0.2), (1.0, 0.0, 0.0)))], sub),
          wp(KLc, sub))
    # sickle: hooks past the stalks, is drawn through them (contact), then withdrawn out to the side
    tipK = [(0, P(xp - 0.10, 0.30, 0.42)), (6, P(xc - 0.10, 0.36, 0.44), "smooth"), (9, P(xc - 0.02, 0.66, 0.40), "smooth"),
            (11, P(xc + 0.02, 0.66, 0.36), "smooth"), (15, P(xc - 0.06, 0.44, 0.34), "in2"), (20, P(xc - 0.20, 0.36, 0.42), "out"),
            (34, P(xc - 0.30, 0.30, 0.56), "smooth"), (45, P(xc - 0.10, 0.30, 0.42), "smooth")]
    thK = [(0, 165.0), (9, 125.0), (15, 100.0, "in2"), (22, 120.0), (34, 150.0), (45, 165.0)]
    tip = wp(tipK, sub)
    th = wp(thK, sub)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    s["pel"] = V(0.02 * xc * 6, 0.05, -0.20 + 0.03 * pulse(sub, 20, 30, 34, 44))
    s["hip"] = (48.0, 10.0 * xc * 4, 0.0)
    s["tor"] = (14.0, -8.0 * xc * 4, 0.0)
    s["head"] = (-10.0, 0.0, 0.0)
    grips(s, [("r", tip - D * L, D, sag_K(D))], fitlean=True, headk=0.1, lmax=25, rmax=0.47)
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Farm_Harvest", 90, harvest, loop=True, enter_exit=True, category="work/farm",
          props=[{"id": "sickle", "hand": "r"}], anchor={"type": "field_row", "at": [0.0, 0.55, 0.45], "size": [1.0, 0.4, 0.05]},
          events={"contact": [15, 60]}, note="two cuts per cycle, bent at hips and knees; left hand gathers the stalks, drops the bundle at its side",
          tr={"dip": 0.06, "lift": 0.06})


# ---------------------------------------------------------------------------------------------- milking (seated)
def milk(fr, n):
    s = S()
    s["pel"] = V(0, 0.20, -0.545)
    s["hip"] = (-4.0, 0.0, 0.0)
    s["foot_l"] = V(0.17, -0.10, 0.104)
    s["foot_r"] = V(-0.17, -0.10, 0.104)
    s["fyaw_l"], s["fyaw_r"] = 10.0, -10.0
    a = 0.85 + 0.15 * sw(fr, n, 1, 0.1)
    for side, ph in (("l", 0.0), ("r", 0.5)):
        sx = 1 if side == "l" else -1
        q = 0.5 - 0.5 * math.cos(2 * math.pi * (3.0 * fr / n + ph))          # 0 open .. 1 squeeze
        w = 0.5 - 0.5 * math.cos(2 * math.pi * (3.0 * fr / n + ph + 0.5))
        pos = P(sx * 0.10, 0.11 + 0.02 * w, 0.42 - 0.035 * q * a)
        ho = ((sx * -0.15, -0.9, -0.35 - 0.3 * q), (-sx * 1.0, 0.0, 0.1))
        hand1(s, side, pos, ho, 0.45 + 0.5 * q * a)
    s["tor"] = (20.0 + 1.0 * sw(fr, n, 3), 2.0 * sw(fr, n, 3), 2.0)
    s["head"] = (6.0 + 1.5 * sw(fr, n, 1, 0.3), -8.0, -9.0)
    s["pel"] = Vector(s["pel"]) + V(0.006 * sw(fr, n, 3), 0, 0.003 * sw(fr, n, 6))
    fit(s, rmax=0.47, headk=0.0, squat=0.0, back=0.0)
    return s


work_clip("Life_Farm_Milk_Cow", 72, milk, loop=True, enter_exit=True, n_enter=26, n_exit=24, category="work/farm",
          props=[],
          anchor={"type": "milking_stool", "at": [0.0, -0.25, 0.30], "size": [0.34, 0.34, 0.30]},
          events={"squeeze_l": [0, 24, 48], "squeeze_r": [12, 36, 60]},
          note="seated on a 0.30 m stool, alternate squeezes every 12 frames, head against the flank",
          tr={"lift": 0.05, "sway": 0.02, "dip": 0.0, "t_body": (0.15, 0.95), "t_hands": (0.5, 1.0), "t_feet": (0.05, 0.6)})


# ---------------------------------------------------------------------------------------------- feed chickens
def feed(fr, n):
    half = n // 2
    i = fr % n
    c, sub = i // half, i - (i // half) * half
    wide = (0.0, 0.12)[c]
    s = S()
    stance(s, 0.15, -0.05, -0.15, 0.10, 8.0, -14.0)
    bowl_ho = ((0.0, -1.0, 0.1), (0.0, 0.05, 1.0))
    KP = [(0, P(0.16, 0.24, 1.02)), (6, P(0.16, 0.25, 0.98), "smooth"), (16, P(-0.12, 0.26, 0.86 - wide * 0.3), "smooth"),
          (22, P(-0.32 - wide, 0.30, 0.62), "smooth"), (28, P(-0.40 - wide * 0.8, 0.44, 0.52), "out"),
          (36, P(-0.20, 0.36, 0.72), "smooth"), (45, P(0.16, 0.24, 1.02), "smooth")]
    KC = [(0, 0.3), (5, 0.3), (8, 0.9, "out2"), (22, 0.9), (26, 0.0, "out2"), (40, 0.25), (45, 0.3)]
    HO = [(0, ((0.4, -0.5, -0.75), (0.6, 0.0, -0.2))), (16, ((0.0, -0.5, -0.5), (0.0, 0.3, 0.9))),
          (26, ((-0.1, -1.0, -0.1), (0.0, 0.0, 1.0))), (45, ((0.4, -0.5, -0.75), (0.6, 0.0, -0.2)))]
    hand1(s, "r", wp(KP, sub), HOw(HO, sub), wp(KC, sub))
    yaw = wp([(0, 0.0), (16, 8.0), (26, -14.0, "out"), (45, 0.0)], sub)
    s["pel"] = V(0, 0.02, -0.06)
    s["hip"] = (14.0, -yaw * 0.3, 0.0)
    s["tor"] = (16.0 + 3.0 * pulse(sub, 18, 26, 30, 40), yaw * 0.6, 0.0)
    s["head"] = (14.0, 0.0, 0.0)
    for _ in range(2):
        hand1(s, "l", at_sh(s, "l", 0.01, 0.20, -0.40) + V(0, 0, 0.008 * sw(fr, n, 2)), bowl_ho, 0.6)
        fit(s, headk=0.1, rmax=0.47)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Farm_Feed_Chickens", 90, feed, loop=True, category="work/farm",
          props=[{"id": "grain_bowl", "hand": "l"}], events={"release": [26, 71]},
          note="stooped, bowl in the left hand; grab, low underhand scatter to the right; the second throw goes wider")


# ---------------------------------------------------------------------------------------------- carry layers
def carry_sheaf(fr, n):
    s = S()
    hand1(s, "l", P(0.30, -0.02, 1.53) + V(0.004 * sw(fr, n, 2), 0, 0.005 * sw(fr, n)), ((0.0, -1.0, 0.0), (0.0, 0.0, 1.0)), 0.95)
    hand1(s, "r", P(-0.27, 0.08, 0.92) + V(-0.02 * sw(fr, n), 0.01 * sw(fr, n, 2), 0), ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0)), 0.3)
    s["tor"] = (3.0, 0.0, -4.0)
    s["head"] = (0.0, 0.0, 2.0)
    s["shrug_l"] = 6.0
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Carry_Sheaf_Upper", 60, carry_sheaf, loop=True, category="carry/upper", layer="upper",
          props=[{"id": "sheaf", "hand": "l"}], note="sheaf resting on the left shoulder, right arm swings free")
