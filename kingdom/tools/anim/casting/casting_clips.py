# Key poses of the elemental casting clips, v2 (see author_casting_elements.py for the framework).
# World axes: character faces -Y, +Z up, +X = character's LEFT.  30 fps.  Feet are IK-pinned (ankle targets),
# so a foot never moves unless a key moves it.  Each element has Cast_<El>_Charge (loop) and Cast_<El>_Release,
# plus two shared clips: Cast_AoE_Slam and Cast_Channel_Beam (loop).
# Release frame 0 == Charge frame 0 (same BASE dict), so the hand-over is seamless.
#
# Every Release follows the same animation skeleton (12 principles, not a punch):
#   1. anticipation  - weight shift back / down, torso coil, hands drawn in (slow in, 8-14 frames)
#   2. hold          - 1-3 frames at the top of the wind-up with a tremor (the energy is "loaded")
#   3. snap          - 3-4 frames, accelerating ("in" / "in2" easing), hips lead the shoulders, a foot steps
#   4. RELEASE frame - the pose the VFX spawns on (spec "release"); fastest, most extended pose
#   5. overshoot     - 2-4 frames past the release pose ("out" easing)
#   6. follow-through- secondary motion (hands lag, ripple, drift) and settle, then a recovery step to idle
# Arcs: hands never travel on straight lines, keys carry "_bow" offsets (see build()).
import math, types, random
from mathutils import Vector

F = None
def init(g):
    global F
    F = types.SimpleNamespace(**g)

def V(x, y, z):
    return Vector((x, y, z))

CLIPS = {}
def clip(name, loop, release=None, note="", events=None):
    def deco(fn):
        CLIPS[name] = {"poses": fn, "loop": loop, "release": release, "note": note, "events": events or {}}
        return fn
    return deco

TAU = 2 * math.pi

def sw(u, cycles=1, ph=0.0):
    return math.sin(TAU * (u * cycles + ph))

def cw(u, cycles=1, ph=0.0):
    return math.cos(TAU * (u * cycles + ph))

def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

def stance(lx=0.15, ly=0.0, rx=-0.15, ry=0.10, yl=8.0, yr=-15.0):
    return {"foot_l": V(lx, ly, 0.104), "foot_r": V(rx, ry, 0.104), "fyaw_l": yl, "fyaw_r": yr}

def palms(side, fdir, pdir):
    return (tuple(fdir), tuple(pdir))

def add(s, key, dv):
    s[key] = Vector(s[key]) + Vector(dv)

def addt(s, key, d):
    s[key] = tuple(a + b for a, b in zip(s[key], d))

def orient_to(s, side, fdir, pdir):
    s["hq_" + side] = F.hand_q(side, fdir, pdir)

def snapnoise(fr, n, seed, every=2, amp=1.0, dim=3):
    """deterministic stepped noise, zero at the loop point (frame 0 and n), changes every `every` frames"""
    if fr % n == 0:
        return Vector((0,) * dim)
    k = (fr // every)
    rng = random.Random(seed * 1000 + k)
    return Vector([rng.uniform(-1, 1) * amp for _ in range(dim)])

def rel(out, fwd, z, yaw=0.0, pel=(0.0, 0.0)):
    """world point given in the torso frame: `out` metres to the character's left of the spine axis, `fwd` metres in front
    of it, height z; `yaw` = total torso yaw (deg, left +), `pel` = pelvis xy offset."""
    a = math.radians(yaw)
    x = out * math.cos(a) + fwd * math.sin(a)
    y = out * math.sin(a) - fwd * math.cos(a)
    return V(pel[0] + x, 0.065 + pel[1] + y, z)

def TF(out, fwd, up, yaw=0.0):
    """direction vector given in the torso frame (no origin)"""
    a = math.radians(yaw)
    return (out * math.cos(a) + fwd * math.sin(a), out * math.sin(a) - fwd * math.cos(a), up)

def pl(side, f, p, yaw=0.0):
    """hand orientation from torso-frame finger direction f and palm normal p (each an (out, fwd, up) triple)"""
    return palms(side, TF(*f, yaw=yaw), TF(*p, yaw=yaw))

def B(pitch, yaw=0.0, roll=0.0, hp=0.0, split=0.3):
    """body key: spine pitch / yaw / roll plus the hip share of the yaw (hips lead: split > 0.3)"""
    return dict(tor=(pitch, (1 - split) * yaw, roll), hip=(hp, split * yaw, 0.0))

def relaxed_end(sx_hand=0.27, hy=-0.04, hz=0.86):
    return dict(hand_l=V(sx_hand, hy, hz), hand_r=V(-sx_hand, hy, hz),
                ho_l=palms("l", (0, 0, -1), (-1, 0, 0)), ho_r=palms("r", (0, 0, -1), (1, 0, 0)), curl_l=0.15, curl_r=0.15,
                tor=(3, 0, 0), head=(0, 0, 0), hip=(0, 0, 0), elb_l=None, elb_r=None, shrug_l=None, shrug_r=None,
                fpit_l=0.0, fpit_r=0.0, pel=V(0, 0, -0.03))

IDLE_FEET = dict(foot_l=V(0.13, 0.036, 0.104), foot_r=V(-0.13, 0.036, 0.104), fyaw_l=4.0, fyaw_r=-4.0)

def recover(n, ease="smooth", extra=None):
    """(recovery key list): the last key relaxes the arms and the recovery step brings both feet back near idle"""
    k = dict(relaxed_end(), **IDLE_FEET)
    k["_bow"] = {"foot_l": V(0, 0, 0.035), "foot_r": V(0, 0, 0.02)}
    if extra:
        k.update(extra)
    return (n, k, ease)

def tremble(s, fr, a, b, amp=0.006, tor=0.8, seed=11, every=1):
    """hand + torso shake between frames a and b (stepped noise, envelope 1)"""
    if a <= fr <= b:
        for side, sd in (("hand_l", 1), ("hand_r", 2)):
            add(s, side, snapnoise(fr, 99999, seed + sd, every, amp))
        addt(s, "tor", tuple(snapnoise(fr, 99999, seed + 5, every, tor)))

def decay_shake(s, fr, start, length, amp=0.02, tor=1.5, seed=21):
    """decaying recoil jitter after the release frame"""
    if start <= fr < start + length:
        k = 1.0 - (fr - start) / float(length)
        for side, sd in (("hand_l", 1), ("hand_r", 2)):
            add(s, side, snapnoise(fr, 99999, seed + sd, 1, amp * k))
        addt(s, "tor", tuple(snapnoise(fr, 99999, seed + 5, 1, tor * k)))

# ============================================================================================ FIRE
# Aggressive two-hand thrust.  Charge: cupped hands at the chest squeeze and swell.
# Release: sink + draw both hands back to the right hip (torso coiled -40), hold, hips lead, left foot steps, hands
# blast up-forward at eye height (f17), overshoot, follow-through with a held arm-up, recovery step.
FIRE_STANCE = stance(0.21, -0.10, -0.21, 0.22, 8.0, -22.0)
FIRE_BASE = dict(
    pel=V(0, 0.02, -0.08), tor=(12, 0, 0), head=(-10, 0, 0),
    hand_l=V(0.10, -0.33, 1.20), hand_r=V(-0.10, -0.33, 1.20),
    ho_l=palms("l", (0, -1, 0.25), (-1, 0, 0.3)), ho_r=palms("r", (0, -1, 0.25), (1, 0, 0.3)),
    curl_l=0.45, curl_r=0.45, **FIRE_STANCE)

def _fire_charge_post(fr, n, s):
    u = fr / n
    p = sw(u)
    add(s, "hand_l", (-0.08 * p, 0.11 * p, 0.05 * p))
    add(s, "hand_r", (0.08 * p, 0.11 * p, 0.05 * p))
    add(s, "pel", (0.03 * sw(u), 0.05 * p, 0.04 * sw(u, 2)))
    addt(s, "tor", (8 * p, 7 * sw(u), 3 * sw(u)))
    addt(s, "head", (3 * p, 0, 0))
    j = 0.005 * sw(u, 5)
    add(s, "hand_l", (j, 0, -j))
    add(s, "hand_r", (j, 0, j))

@clip("Cast_Fire_Charge", True, note="two-hand cupped gather: hands squeeze and swell (one pulse per loop), body breathes, weight rocks back")
def fire_charge():
    n = 36
    return F.build([(0, FIRE_BASE), (n, {})], n, _fire_charge_post)

@clip("Cast_Fire_Release", False, release=17,
      note="sink + coil right (hands drawn to the right hip, f0-11), tremor hold (f11-13), hips lead, left foot steps, two-hand blast at eye height f17, overshoot f20, held arm-up to f30, recovery step",
      events={"anticipation_peak": 11, "step_land": 17, "overshoot": 20})
def fire_release():
    n = 48
    Y = -42
    pr = (0.06, 0.12)
    A = dict(hand_r=rel(-0.30, 0.02, 0.98, Y, pr), hand_l=rel(-0.10, 0.20, 1.06, Y, pr), pel=V(0.05, 0.12, -0.19),
             ho_r=pl("r", (0.2, 1, 0.1), (1, 0, 0.2), Y), ho_l=pl("l", (0.2, 1, 0.1), (-1, 0, 0.2), Y),
             curl_l=0.85, curl_r=0.85, head=(-2, 26, 0), elb_r=rel(-0.48, -0.30, 1.02, Y, pr), fpit_l=10.0,
             **B(-4, Y, 3, split=0.3))
    RL = dict(hand_r=rel(-0.11, 0.90, 1.26, 8), hand_l=rel(0.11, 0.90, 1.26, 8), pel=V(0, -0.16, -0.22),
              ho_r=pl("r", (0, 1, 0.15), (1, 0, 0.1), 8), ho_l=pl("l", (0, 1, 0.15), (-1, 0, 0.1), 8), curl_l=-0.6, curl_r=-0.6,
              head=(-24, -6, 0), elb_r=None, fpit_l=0.0, **B(34, 8, 0, split=0.4))
    keys = [
        (0, FIRE_BASE),
        (3, dict(pel=V(0, 0.05, -0.13), tor=(14, 0, 0), curl_l=0.7, curl_r=0.7,
                 hand_l=V(0.13, -0.28, 1.13), hand_r=V(-0.13, -0.28, 1.13))),                 # squash: the tiny dip before the pull
        (11, dict(A, _bow={"hand_r": V(-0.05, 0.0, -0.09), "hand_l": V(0.0, 0.0, -0.07)})),    # coil, arms sweep back on an arc
        (13, dict()),                                                                           # loaded: hold + tremor
        (15, dict(foot_l=V(0.21, -0.20, 0.17), pel=V(0.03, 0.0, -0.15), hip=(0, 4, 0), tor=(10, -12, 0),
                  hand_r=rel(-0.24, 0.30, 1.16, -16, (0.03, 0)), hand_l=rel(0.00, 0.44, 1.24, -16, (0.03, 0))), "in2"),
        (17, dict(RL, foot_l=V(0.21, -0.32, 0.104)), "in"),
        (20, dict(hand_r=rel(-0.11, 0.96, 1.30, 8), hand_l=rel(0.11, 0.96, 1.30, 8), pel=V(0, -0.21, -0.25), head=(-28, -6, 0), **B(40, 8, 0, split=0.4)), "out"),
        (28, dict(hand_r=rel(-0.16, 0.70, 1.30, 4), hand_l=rel(0.16, 0.70, 1.30, 4), pel=V(0, -0.17, -0.21), head=(-22, 0, 0),
                  curl_l=-0.3, curl_r=-0.3, **B(32, 4, 0, split=0.3), _bow={"hand_r": V(0, 0.0, 0.05), "hand_l": V(0, 0.0, 0.05)}), "smooth"),
        (34, dict(hand_r=rel(-0.20, 0.44, 1.22, 0), hand_l=rel(0.20, 0.44, 1.22, 0), pel=V(0, -0.10, -0.14), curl_l=0.2, curl_r=0.2, head=(-12, 0, 0), **B(18, 0)), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        tremble(s, fr, 11, 14, 0.006, 0.9, 3)
        decay_shake(s, fr, 17, 7, 0.012, 1.2, 31)
    return F.build(keys, n, post)

# ============================================================================================ WATER
# Flowing wave: hands orbit an invisible orb with a swaying body; release = sink low right, then a big rising S-wave of both
# arms (left hand lags the right by 2 frames) from low-right through the front (release, f18) to high-left, then two ripples.
WATER_STANCE = stance(0.17, -0.10, -0.17, 0.16, 15.0, -25.0)

def _water_hands(s, u):
    s["hand_r"] = V(-0.18 + 0.15 * sw(u), -0.28 + 0.07 * cw(u), 1.18 + 0.13 * cw(u))
    s["hand_l"] = V(0.16 - 0.15 * sw(u), -0.24 - 0.07 * cw(u), 1.02 - 0.13 * cw(u))
    orient_to(s, "r", (-0.25 + 0.3 * sw(u), -1, -0.2 * cw(u)), (0.2, 0.1, -1))
    orient_to(s, "l", (0.25 - 0.3 * sw(u), -1, 0.2 * cw(u)), (-0.2, 0.1, 1))

WATER_BASE = dict(
    pel=V(0, 0.02, -0.06), tor=(6, 0, 0), head=(-4, 0, 0),
    hand_r=V(-0.18, -0.21, 1.31), hand_l=V(0.16, -0.31, 0.89),
    ho_r=palms("r", (-0.25, -1, -0.2), (0.2, 0.1, -1)), ho_l=palms("l", (0.25, -1, 0.2), (-0.2, 0.1, 1)),
    curl_l=-0.35, curl_r=-0.35, **WATER_STANCE)

def _water_charge_post(fr, n, s):
    u = fr / n
    _water_hands(s, u)
    s["pel"] = V(0.07 * sw(u), 0.02, -0.06 + 0.025 * sw(u, 2))
    s["tor"] = (6 + 3 * sw(u, 2), 17 * sw(u), 10 * sw(u))
    s["head"] = (-4, -7 * sw(u), -4 * sw(u))

@clip("Cast_Water_Charge", True, note="orbiting hands, whole body sways in a figure-8 (weight rocks foot to foot), soft fingers")
def water_charge():
    n = 42
    return F.build([(0, WATER_BASE), (n, {})], n, _water_charge_post)

@clip("Cast_Water_Release", False, release=18,
      note="sink low-right and draw both hands back on a dipping arc (f0-11), breath (f11-13), rising S-wave of both arms through the front (release f18, left hand lags 2 frames), crest high-left f24, two decaying ripples, recovery step",
      events={"anticipation_peak": 11, "crest": 24, "ripple_1": 34, "ripple_2": 42})
def water_release():
    n = 56
    Y0, Y1, Y2, Y3 = -34, 4, 36, 20
    p0, p1, p2 = (-0.10, 0.10), (0.04, -0.06), (0.10, -0.04)
    keys = [
        (0, WATER_BASE),
        (11, dict(hand_r=rel(-0.44, 0.10, 0.72, Y0, p0), hand_l=rel(-0.16, 0.26, 0.88, Y0, p0), pel=V(-0.10, 0.10, -0.22),
                  **B(14, Y0, -12, split=0.35), head=(-4, 22, 4), elb_l=None,
                  ho_r=pl("r", (-0.3, 1, -0.4), (0, 0, 1), Y0), ho_l=pl("l", (0.3, 1, -0.3), (0, 0, 1), Y0), curl_l=-0.2, curl_r=-0.2,
                  _bow={"hand_r": V(-0.05, 0.05, -0.12), "hand_l": V(0.0, 0.05, -0.10)}), "smooth"),
        (13, dict()),
        (16, dict(hand_r=rel(-0.24, 0.42, 1.02, -12, (-0.02, 0.0)), hand_l=rel(0.02, 0.36, 1.00, -12, (-0.02, 0.0)), pel=V(-0.04, 0.0, -0.17),
                  **B(16, -12, -4, split=0.4), head=(-6, 8, 0), curl_l=-0.5, curl_r=-0.5,
                  ho_r=pl("r", (0, 1, 0.4), (0, -0.2, 1), -12), ho_l=pl("l", (0, 1, 0.4), (0, -0.2, 1), -12)), "in2"),
        (18, dict(hand_r=rel(-0.05, 0.58, 1.24, Y1, p1), hand_l=rel(0.20, 0.44, 1.04, Y1, p1), pel=V(0.04, -0.05, -0.12), foot_l=V(0.17, -0.16, 0.104), fyaw_l=15.0,
                  **B(16, Y1, 6, split=0.4), head=(-10, 0, 0),
                  ho_r=pl("r", (0, 1, 0.5), (0, 0.3, 1), Y1), ho_l=pl("l", (0, 1, 0.2), (0, 0.2, 1), Y1), curl_l=-0.6, curl_r=-0.7,
                  _bow={"hand_r": V(0.0, 0.05, 0.03), "hand_l": V(0.05, 0.0, -0.04)}), "lin"),
        (24, dict(hand_r=rel(0.48, 0.34, 1.72, Y2, p2), hand_l=rel(0.62, 0.14, 1.40, Y2, p2), pel=V(0.09, -0.03, -0.08), **B(6, Y2, 12, split=0.4), head=(-6, -22, 0),
                  ho_r=pl("r", (0.5, 0.5, 1), (0, 1, 0.2), Y2), ho_l=pl("l", (1, 0.4, 0.7), (0, 1, 0), Y2), curl_l=-0.8, curl_r=-0.8,
                  _bow={"hand_r": V(-0.08, 0.0, 0.10), "hand_l": V(0.0, 0.0, 0.08)}), "out"),
        (34, dict(hand_r=rel(0.20, 0.48, 1.00, Y3, (0.06, -0.05)), hand_l=rel(0.36, 0.30, 0.94, Y3, (0.06, -0.05)), pel=V(0.06, -0.05, -0.12), **B(12, Y3, 6, split=0.35), head=(-6, -10, 0),
                  curl_l=-0.4, curl_r=-0.4, _bow={"hand_r": V(0.05, 0.0, 0.10), "hand_l": V(0.05, 0.0, 0.08)}), "smooth"),
        (42, dict(hand_r=rel(0.10, 0.46, 1.42, 8, (0.02, -0.04)), hand_l=rel(0.24, 0.30, 1.30, 8, (0.02, -0.04)), pel=V(0.02, -0.02, -0.09), **B(8, 8, 2, split=0.35), head=(-4, -4, 0),
                  _bow={"hand_r": V(0.0, 0.0, -0.05), "hand_l": V(0.0, 0.0, -0.06)}), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        if 18 <= fr <= 46:
            k = max(0.0, 1.0 - (fr - 18) / 28.0)
            w = sw((fr - 18) / 20.0)
            add(s, "hand_r", (0, 0, 0.05 * k * w))
            add(s, "hand_l", (0, 0, 0.05 * k * sw((fr - 20) / 20.0)))
    return F.build(keys, n, post)

# ============================================================================================ EARTH
# Deep horse stance; charge = lift-and-stomp beat; release = weight onto the left leg, right knee hauled up with the fists
# at the shoulders, a heavy STOMP (f18, ground impact: pelvis squashes), then a slow heavy LIFT of both hands from the
# ground to overhead (peak f36), hang, lower.
EARTH_STANCE = stance(0.30, -0.02, -0.30, 0.06, 25.0, -25.0)
EARTH_BASE = dict(
    pel=V(0, 0.02, -0.20), tor=(12, 0, 0), head=(-10, 0, 0),
    hand_l=V(0.30, -0.22, 0.80), hand_r=V(-0.30, -0.22, 0.80),
    ho_l=palms("l", (0.3, -1, 0), (0, 0, 1)), ho_r=palms("r", (-0.3, -1, 0), (0, 0, 1)),
    curl_l=0.35, curl_r=0.35, **EARTH_STANCE)

def _earth_charge_post(fr, n, s):
    u = fr / n
    if u < 0.45:
        h = smooth(u / 0.45)
    elif u < 0.60:
        h = 1.0
    elif u < 0.68:
        h = 1.0 - smooth((u - 0.60) / 0.08)
    else:
        h = 0.0
    lift = 0.24 * math.sin(math.pi * (u - 0.20) / 0.40) if 0.20 <= u <= 0.60 else 0.0
    s["hand_l"] = V(0.30 - 0.10 * h, -0.22 - 0.14 * h, 0.80 + 0.42 * h)
    s["hand_r"] = V(-0.30 + 0.10 * h, -0.22 - 0.14 * h, 0.80 + 0.42 * h)
    s["foot_r"] = V(-0.30, 0.06, 0.104 + lift)
    tri = max(0.0, 1.0 - abs(u - 0.66) / 0.08)
    sh = 0.07 * math.sin(math.pi * (u - 0.2) / 0.4) if 0.2 <= u <= 0.6 else 0.0
    s["pel"] = V(sh, 0.02, -0.20 + 0.045 * h - 0.05 * tri)
    s["tor"] = (12 - 4 * h + 7 * tri, 0, 4 * sh / 0.07 if sh else 0)
    s["curl_l"] = s["curl_r"] = 0.35 + 0.4 * h

@clip("Cast_Earth_Charge", True, note="horse stance, hands heave a boulder up, weight shifts left and the right foot stomps at 66% of the loop (foot plants about f28)")
def earth_charge():
    n = 42
    return F.build([(0, EARTH_BASE), (n, {})], n, _earth_charge_post)

@clip("Cast_Earth_Release", False, release=18,
      note="weight onto the left leg, right knee hauled up, fists to the shoulders (f0-12, slow in), hang f12-14, STOMP f14-18 with a pelvis squash (release = ground impact f18), heavy scoop-lift of both hands from the ground to overhead (peak f36), tremor hang, slow lower",
      events={"anticipation_peak": 12, "stomp_impact": 18, "lift_peak": 36, "lift_release": 40})
def earth_release():
    n = 68
    keys = [
        (0, EARTH_BASE),
        (12, dict(pel=V(0.14, 0.03, -0.14), tor=(-4, 0, -7), head=(-6, 0, 0), foot_r=V(-0.34, 0.08, 0.46), fpit_r=-10.0, fyaw_r=-35.0,
                  hand_l=V(0.30, -0.10, 1.30), hand_r=V(-0.32, -0.10, 1.34), curl_l=0.9, curl_r=0.9,
                  ho_l=palms("l", (0, -0.4, 1), (-1, 0, 0.3)), ho_r=palms("r", (0, -0.4, 1), (1, 0, 0.3)),
                  elb_l=V(0.62, 0.25, 1.25), elb_r=V(-0.65, 0.20, 1.28)), "in2"),
        (14, dict(pel=V(0.13, 0.03, -0.10), tor=(-8, 0, -8), hand_l=V(0.30, -0.08, 1.38), hand_r=V(-0.32, -0.08, 1.42)), "out2"),
        (18, dict(pel=V(0.0, -0.06, -0.34), tor=(38, 0, 0), head=(-26, 0, 0), foot_r=V(-0.30, 0.06, 0.104), fpit_r=0.0, fyaw_r=-25.0,
                  hand_l=V(0.30, -0.36, 0.72), hand_r=V(-0.30, -0.36, 0.72), curl_l=0.6, curl_r=0.6, elb_l=None, elb_r=None,
                  ho_l=palms("l", (0.2, -1, -0.3), (-1, 0, 0)), ho_r=palms("r", (-0.2, -1, -0.3), (1, 0, 0)),
                  _bow={"hand_l": V(0.0, -0.05, 0.0), "hand_r": V(0.0, -0.05, 0.0)}), "in"),
        (21, dict(pel=V(0, -0.03, -0.30), tor=(34, 0, 0), head=(-22, 0, 0),
                  hand_l=V(0.36, -0.40, 0.56), hand_r=V(-0.36, -0.40, 0.56)), "out"),
        (28, dict(pel=V(0, 0.0, -0.24), tor=(22, 0, 0), head=(-14, 0, 0), hand_l=V(0.34, -0.50, 0.78), hand_r=V(-0.34, -0.50, 0.78), curl_l=-0.3, curl_r=-0.3,
                  ho_l=palms("l", (0, -1, 0.1), (0, 0, 1)), ho_r=palms("r", (0, -1, 0.1), (0, 0, 1))), "in2"),
        (36, dict(pel=V(0, 0.04, -0.04), tor=(-14, 0, 0), head=(-30, 0, 0), hand_l=V(0.36, -0.30, 1.72), hand_r=V(-0.36, -0.30, 1.72), curl_l=-0.7, curl_r=-0.7,
                  ho_l=palms("l", (0.2, -0.3, 1), (0, -0.6, 0.8)), ho_r=palms("r", (-0.2, -0.3, 1), (0, -0.6, 0.8)),
                  foot_l=V(0.30, -0.02, 0.104), fpit_l=-6.0, fpit_r=-6.0, _bow={"hand_l": V(0.10, -0.12, 0.0), "hand_r": V(-0.10, -0.12, 0.0)}), "out2"),
        (44, dict(tor=(-12, 0, 0), hand_l=V(0.34, -0.28, 1.74), hand_r=V(-0.34, -0.28, 1.74)), "smooth"),
        (54, dict(pel=V(0, 0.0, -0.14), tor=(8, 0, 0), head=(-8, 0, 0), hand_l=V(0.34, -0.20, 1.10), hand_r=V(-0.34, -0.20, 1.10), curl_l=0.3, curl_r=0.3, fpit_l=0.0, fpit_r=0.0), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        tremble(s, fr, 36, 46, 0.008, 0.8, 41, 2)
        if 18 <= fr <= 24:   # ground shock rattles the upper body
            k = 1.0 - (fr - 18) / 7.0
            addt(s, "head", tuple(snapnoise(fr, 99999, 43, 1, 2.5 * k)))
    return F.build(keys, n, post)

# ============================================================================================ WIND
# Arms sweep circles at their own side; release = crouch + coil to -76 (right arm swept back wide), hips lead the
# unwind, a spinning whip that sweeps the right arm at chest height through the front (f15) to +70, then unwind.
WIND_STANCE = stance(0.15, -0.08, -0.15, 0.12, 10.0, -20.0)

def _wind_orbit(u, side):
    th = TAU * u + (0.0 if side == "l" else math.pi)
    sx = 1 if side == "l" else -1
    return V(sx * (0.36 + 0.14 * math.cos(th)), -0.24 - 0.19 * math.sin(th), 1.28 + 0.15 * math.sin(th)), th

WIND_BASE = dict(
    pel=V(0, 0.02, -0.05), tor=(4, 0, 0), head=(-3, 0, 0),
    hand_l=_wind_orbit(0, "l")[0], hand_r=_wind_orbit(0, "r")[0],
    ho_l=palms("l", (1, -0.5, 0.2), (0, 0, -1)), ho_r=palms("r", (-1, -0.5, 0.2), (0, 0, -1)),
    curl_l=-0.6, curl_r=-0.6, **WIND_STANCE)

def _wind_charge_post(fr, n, s):
    u = fr / n
    for side in ("l", "r"):
        p, th = _wind_orbit(u, side)
        s["hand_" + side] = p
        sh = Vector((0.19 if side == "l" else -0.19, 0.065, 1.44))
        orient_to(s, side, p - sh, (0, 0, -1))
    s["tor"] = (4, 16 * sw(u), 5 * cw(u) - 5)
    s["hip"] = (0, 8 * sw(u), 0)
    s["head"] = (-3, -8 * sw(u), 0)
    s["pel"] = V(0.03 * sw(u), 0.02, -0.05 + 0.015 * sw(u, 2))

@clip("Cast_Wind_Charge", True, note="both arms orbit at chest height (opposite phases), torso and hips twist with them")
def wind_charge():
    n = 42
    return F.build([(0, WIND_BASE), (n, {})], n, _wind_charge_post)

@clip("Cast_Wind_Release", False, release=15,
      note="crouch + coil to -80 with both arms swung wide behind (f0-10), hips lead the unwind, spinning whip: right arm sweeps through the front at f15 (arms in a wide line), body spins on to +80 (f21) with the feet pivoting, left arm counter-flares, unwind and recovery step",
      events={"anticipation_peak": 10, "release": 15, "overshoot": 21})
def wind_release():
    n = 52
    Y0, Y1, Y2 = -80, 12, 82
    pr = (-0.05, 0.08)
    keys = [
        (0, WIND_BASE),
        (10, dict(hand_r=rel(-0.62, -0.14, 1.40, Y0, pr), hand_l=rel(0.44, 0.24, 1.30, Y0, pr), pel=V(-0.05, 0.08, -0.20),
                  **B(8, Y0, 5, split=0.35), head=(-2, 44, 0), fyaw_r=-45.0, fyaw_l=-15.0, curl_l=-0.3, curl_r=-0.6,
                  ho_r=pl("r", (-1, 0.1, 0.1), (0, 0, -1), Y0), ho_l=pl("l", (1, 0.5, 0), (0, 0, -1), Y0),
                  _bow={"hand_r": V(0, 0.0, -0.10), "hand_l": V(0, 0.0, -0.06)}), "smooth"),
        (12, dict(hand_r=rel(-0.66, -0.20, 1.42, Y0 - 5, pr), tor=(8, -0.60 * 85, 5), hip=(0, -0.40 * 85, 0), head=(-2, 48, 0)), "out2"),   # a hair more coil, then go
        (15, dict(hand_r=rel(-0.32, 0.66, 1.36, Y1, (0, -0.02)), hand_l=rel(0.62, -0.02, 1.42, Y1, (0, -0.02)), pel=V(0, -0.02, -0.14),
                  **B(10, Y1, 0, split=0.5), head=(-6, -12, 0), fyaw_r=-30.0, fyaw_l=25.0,
                  ho_r=pl("r", (-0.3, 1, 0.1), (0, 0, -1), Y1), ho_l=pl("l", (1, 0.1, 0), (0, 0, -1), Y1), curl_r=-0.8, curl_l=-0.4,
                  _bow={"hand_r": V(0.0, 0.12, 0.06)}), "in"),
        (21, dict(hand_r=rel(-0.56, 0.40, 1.42, Y2, (0, -0.02)), hand_l=rel(0.62, -0.14, 1.40, Y2, (0, -0.02)),
                  **B(8, Y2, 4, split=0.5), head=(-4, -34, 0), fyaw_l=65.0, fyaw_r=15.0, pel=V(0, -0.03, -0.12),
                  ho_r=pl("r", (-0.4, 1, 0), (0, 0, -1), Y2), ho_l=pl("l", (1, -0.1, 0), (0, 0, -1), Y2)), "out"),
        (32, dict(hand_r=rel(-0.40, 0.30, 1.30, 50, (0, -0.02)), hand_l=rel(0.42, -0.10, 1.20, 50, (0, -0.02)), **B(8, 50, 0, split=0.4), head=(-4, -18, 0),
                  fyaw_l=35.0, fyaw_r=-10.0, pel=V(0, 0.0, -0.09), curl_l=-0.3, curl_r=-0.3), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        tremble(s, fr, 10, 12, 0.004, 0.6, 51)
    return F.build(keys, n, post)

# ============================================================================================ LIGHTNING
# Right arm to the sky (jittery), left fist at the hip; release = quick crouch (compress), spring up on the toes with both
# arms flung skyward (call), tremor hold, then a hard snap of the arm down to point at the target with a lunge.
LIGHTNING_STANCE = stance(0.17, -0.06, -0.17, 0.10, 12.0, -18.0)
LIGHTNING_BASE = dict(
    pel=V(0, 0.03, -0.07), tor=(-6, 0, -3), head=(-32, 0, 0),
    hand_r=V(-0.13, -0.02, 1.97), hand_l=V(0.24, -0.10, 0.98),
    ho_r=palms("r", (0.0, -0.1, 1), (0, -1, 0.1)), ho_l=palms("l", (0.3, -1, -0.6), (0, 0, 1)),
    curl_r=-0.7, curl_l=0.75, **LIGHTNING_STANCE)

def _lightning_charge_post(fr, n, s):
    u = fr / n
    add(s, "hand_r", snapnoise(fr, n, 1, 2, 0.014))
    add(s, "hand_l", snapnoise(fr, n, 2, 3, 0.008))
    addt(s, "tor", tuple(snapnoise(fr, n, 3, 2, 1.0)))
    addt(s, "head", tuple(snapnoise(fr, n, 4, 4, 1.6)))
    add(s, "hand_r", (0, 0, 0.03 * sw(u)))
    s["pel"] = V(0, 0.03, -0.07 + 0.015 * sw(u, 2))
    s["curl_r"] = -0.7 + 0.25 * sw(u, 3) if fr % n else -0.7

@clip("Cast_Lightning_Charge", True, note="right arm straight up to the sky, snapped jitter, left fist at the hip, head up, body shudders")
def lightning_charge():
    n = 36
    return F.build([(0, LIGHTNING_BASE), (n, {})], n, _lightning_charge_post)

@clip("Cast_Lightning_Release", False, release=19,
      note="compress (crouch, arm cocked, f0-5), spring up on the toes with both arms flung skyward (f9), tremor hold f9-14 (sky call), arm snaps down to a lunging point in 4 frames (release f19), decaying recoil jitter, hold, recovery step",
      events={"compress": 5, "sky_call": 9, "release": 19})
def lightning_release():
    n = 48
    keys = [
        (0, LIGHTNING_BASE),
        (5, dict(pel=V(0, 0.05, -0.24), tor=(18, 0, -3), head=(-6, 0, 0), hand_r=V(-0.17, 0.10, 1.62), hand_l=V(0.30, 0.02, 0.86),
                 ho_r=palms("r", (0, 0.2, 1), (0, -1, 0.1)), curl_r=-0.3, curl_l=0.9,
                 foot_l=V(0.19, -0.06, 0.104), foot_r=V(-0.19, 0.10, 0.104)), "out2"),
        (9, dict(pel=V(0, 0.02, 0.01), tor=(-22, 0, -4), head=(-44, 0, 0), hand_r=V(-0.12, -0.02, 2.14), hand_l=V(0.46, 0.00, 1.86),
                 ho_r=palms("r", (0, 0, 1), (0, -1, 0)), ho_l=palms("l", (0.3, 0, 1), (0, -1, 0.1)), curl_r=-1.0, curl_l=-0.8,
                 foot_l=V(0.15, -0.06, 0.15), foot_r=V(-0.15, 0.10, 0.15), fpit_l=-32.0, fpit_r=-32.0, shrug_l=18.0, shrug_r=18.0), "in2"),
        (14, dict()),
        (19, dict(pel=V(0, -0.14, -0.20), tor=(28, 0, -4), head=(-22, 0, 0), hand_r=V(-0.10, -0.74, 1.26), hand_l=V(0.58, 0.34, 1.12),
                  ho_r=palms("r", (0, -1, -0.2), (1, 0, 0)), ho_l=palms("l", (1, 0.3, 0), (0, 0, -1)), curl_r=0.4, curl_l=-0.3,
                  foot_l=V(0.19, -0.34, 0.104), foot_r=V(-0.19, 0.12, 0.104), fpit_l=0.0, fpit_r=0.0, shrug_l=None, shrug_r=None,
                  _bow={"hand_r": V(-0.10, 0.05, 0.10)}), "in"),
        (22, dict(hand_r=V(-0.10, -0.80, 1.22), pel=V(0, -0.17, -0.22), tor=(32, 0, -4)), "out"),
        (32, dict(hand_r=V(-0.14, -0.62, 1.16), hand_l=V(0.52, 0.20, 1.14), tor=(22, 0, 0), head=(-14, 0, 0), pel=V(0, -0.10, -0.16)), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        tremble(s, fr, 9, 14, 0.014, 1.6, 61)
        decay_shake(s, fr, 19, 10, 0.03, 2.2, 63)
    return F.build(keys, n, post)

# ============================================================================================ ICE
# Rigid, exact: arms crossed in front of the chest (fine frost tremor).  Release = crossed forearms lift to an X guard at
# the face with the body rising precisely (slow, linear, f0-10), rigid hold, a 4-frame hard linear snap into a two-palm
# push (stop-hands, release f17, left foot steps), frozen hold on 3s, thaw.
ICE_STANCE = stance(0.14, -0.05, -0.14, 0.06, 4.0, -4.0)
ICE_BASE = dict(
    pel=V(0, 0.02, -0.03), tor=(2, 0, 0), head=(0, 0, 0),
    hand_r=V(0.12, -0.30, 1.30), hand_l=V(-0.12, -0.22, 1.30),
    ho_r=palms("r", (0.6, -0.2, 1), (0, 1, 0.3)), ho_l=palms("l", (-0.6, -0.2, 1), (0, 1, 0.3)),
    curl_l=-0.8, curl_r=-0.8, shrug_l=9.0, shrug_r=9.0, **ICE_STANCE)

def _ice_charge_post(fr, n, s):
    u = fr / n
    j = 0.004 * sw(u, 9)
    add(s, "hand_r", (j, 0, 0.5 * j))
    add(s, "hand_l", (-j, 0, 0.5 * j))
    addt(s, "tor", (0.5 * sw(u, 9), 0, 0))
    add(s, "hand_r", (0, 0.02 * sw(u), 0.02 * sw(u)))
    add(s, "hand_l", (0, 0.02 * sw(u), 0.02 * sw(u)))
    s["pel"] = V(0, 0.02, -0.03 + 0.012 * sw(u))

@clip("Cast_Ice_Charge", True, note="rigid crossed forearms at the chest, tiny frost tremor, shoulders raised, slow chest breath")
def ice_charge():
    n = 36
    return F.build([(0, ICE_BASE), (n, {})], n, _ice_charge_post)

@clip("Cast_Ice_Release", False, release=17,
      note="crossed forearms lift to an X guard at the face and the body rises on straight lines (f0-10), rigid hold with frost tremor (f10-13), 4-frame linear snap into a wide two-palm stop-push (release f17, left foot steps), frozen hold on 3s to f34, thaw",
      events={"anticipation_peak": 10, "release": 17, "frozen_until": 34})
def ice_release():
    n = 50
    keys = [
        (0, ICE_BASE),
        (10, dict(hand_r=V(0.16, -0.24, 1.60), hand_l=V(-0.16, -0.18, 1.60), pel=V(0, 0.06, 0.0), tor=(-8, -10, 0), hip=(0, -3, 0), head=(-6, 8, 0),
                  ho_r=palms("r", (0.4, -0.2, 1), (0, 1, 0.2)), ho_l=palms("l", (-0.4, -0.2, 1), (0, 1, 0.2)), shrug_l=16.0, shrug_r=16.0,
                  foot_l=V(0.14, -0.05, 0.104), fpit_l=0.0, fpit_r=-10.0), "smooth"),
        (13, dict()),
        (15, dict(hand_r=V(-0.10, -0.20, 1.44), hand_l=V(0.10, -0.20, 1.44), pel=V(0, 0.0, -0.05), tor=(6, 4, 0), hip=(0, 3, 0), foot_l=V(0.14, -0.14, 0.15),
                  shrug_l=9.0, shrug_r=9.0), "lin"),
        (17, dict(hand_r=V(-0.34, -0.60, 1.46), hand_l=V(0.34, -0.60, 1.46), pel=V(0, -0.10, -0.09), tor=(18, 0, 0), hip=(0, 0, 0), head=(-14, 0, 0),
                  ho_r=palms("r", (0, -0.3, 1), (0, -1, 0.2)), ho_l=palms("l", (0, -0.3, 1), (0, -1, 0.2)), curl_l=-1.0, curl_r=-1.0,
                  foot_l=V(0.14, -0.26, 0.104), shrug_l=None, shrug_r=None, fpit_r=0.0), "lin"),
        (34, dict(hand_r=V(-0.35, -0.62, 1.47), hand_l=V(0.35, -0.62, 1.47), pel=V(0, -0.10, -0.09)), "lin"),
        (n, dict(recover(n)[1], curl_l=0.15, curl_r=0.15), "smooth"),
    ]
    def post(fr, n, s):
        tremble(s, fr, 10, 13, 0.004, 0.5, 71, 2)
        if 17 <= fr <= 34:
            add(s, "hand_r", (0.003 * sw(fr / 3.0, 0.5), 0, 0)); add(s, "hand_l", (-0.003 * sw(fr / 3.0, 0.5), 0, 0))
        if fr == 18:   # hard-stop kick: one frame of overshoot on the push
            add(s, "hand_r", (-0.01, -0.03, 0)); add(s, "hand_l", (0.01, -0.03, 0))
    return F.build(keys, n, post, step=(19, 40, 3))

# ============================================================================================ LIGHT
# Raised open palms in a V; release = humble gather (arms cross low, head bowed, knees bend), then both arms open wide in a
# rising arc to a big V on tiptoe (release f22, chest lifted), hang, arms lower slowly, palms up.
LIGHT_STANCE = stance(0.11, -0.04, -0.11, 0.04, 6.0, -6.0)
LIGHT_BASE = dict(
    pel=V(0, 0.02, -0.02), tor=(-8, 0, 0), head=(-22, 0, 0),
    hand_l=V(0.44, -0.04, 1.86), hand_r=V(-0.44, -0.04, 1.86),
    ho_l=palms("l", (0.3, 0, 1), (0, -0.7, 0.7)), ho_r=palms("r", (-0.3, 0, 1), (0, -0.7, 0.7)),
    curl_l=-0.9, curl_r=-0.9, **LIGHT_STANCE)

def _light_charge_post(fr, n, s):
    u = fr / n
    add(s, "hand_l", (0.04 * sw(u), 0.0, 0.05 * sw(u)))
    add(s, "hand_r", (-0.04 * sw(u), 0.0, 0.05 * sw(u)))
    add(s, "pel", (0, 0, 0.018 * sw(u)))
    addt(s, "tor", (-3.0 * sw(u), 0, 0))
    addt(s, "head", (-3.5 * sw(u), 0, 0))

@clip("Cast_Light_Charge", True, note="open palms raised in a V, chest lifted, slow rising swell")
def light_charge():
    n = 48
    return F.build([(0, LIGHT_BASE), (n, {})], n, _light_charge_post)

@clip("Cast_Light_Release", False, release=23,
      note="arms sweep down and cross low, head bowed, knees bend (humble gather, f0-11), hold, both arms open in a rising arc out to the sides and up into a wide V on tiptoe (release f23), overshoot f27, floating hang to f36 (slow sway), arms lower with palms up",
      events={"anticipation_peak": 11, "release": 23, "overshoot": 27, "hang_until": 36})
def light_release():
    n = 64
    keys = [
        (0, LIGHT_BASE),
        (11, dict(hand_l=V(-0.10, -0.26, 0.86), hand_r=V(0.10, -0.24, 0.90), pel=V(0, 0.03, -0.14), tor=(16, 0, 0), head=(14, 0, 0),
                  ho_l=palms("l", (-0.4, -0.5, -0.5), (0, 0, 1)), ho_r=palms("r", (0.4, -0.5, -0.5), (0, 0, 1)), curl_l=0.3, curl_r=0.3,
                  shrug_l=0.0, shrug_r=0.0, _bow={"hand_l": V(0.10, -0.05, -0.06), "hand_r": V(-0.10, -0.05, -0.06)}), "smooth"),
        (13, dict()),
        (19, dict(hand_l=V(0.56, -0.14, 1.12), hand_r=V(-0.56, -0.14, 1.12), pel=V(0, 0.02, -0.07), tor=(0, 0, 0), head=(-6, 0, 0),
                  ho_l=palms("l", (1, -0.2, 0.3), (0, -0.3, 1)), ho_r=palms("r", (-1, -0.2, 0.3), (0, -0.3, 1)), curl_l=-0.8, curl_r=-0.8,
                  _bow={"hand_l": V(0.05, -0.10, 0.0), "hand_r": V(-0.05, -0.10, 0.0)}), "smooth"),
        (23, dict(hand_l=V(0.76, -0.04, 1.80), hand_r=V(-0.76, -0.04, 1.80), pel=V(0, 0.03, 0.01), tor=(-13, 0, 0), head=(-24, 0, 0),
                  ho_l=palms("l", (0.5, 0, 1), (0, -0.6, 0.8)), ho_r=palms("r", (-0.5, 0, 1), (0, -0.6, 0.8)), curl_l=-1.0, curl_r=-1.0,
                  foot_l=V(0.11, -0.04, 0.15), foot_r=V(-0.11, 0.04, 0.15), fpit_l=-30.0, fpit_r=-30.0, shrug_l=16.0, shrug_r=16.0,
                  _bow={"hand_l": V(0.08, 0.0, -0.05), "hand_r": V(-0.08, 0.0, -0.05)}), "in2"),
        (27, dict(hand_l=V(0.80, -0.02, 1.90), hand_r=V(-0.80, -0.02, 1.90), pel=V(0, 0.03, 0.03), tor=(-16, 0, 0), head=(-26, 0, 0)), "out"),
        (36, dict(hand_l=V(0.74, -0.08, 1.84), hand_r=V(-0.74, -0.08, 1.84), pel=V(0, 0.03, 0.02), tor=(-15, 0, 0), head=(-30, 0, 0)), "smooth"),
        (50, dict(hand_l=V(0.52, -0.22, 1.10), hand_r=V(-0.52, -0.22, 1.10), pel=V(0, 0.02, -0.05), tor=(2, 0, 0), head=(-8, 0, 0),
                  ho_l=palms("l", (0.4, -0.3, 0.2), (0, -0.2, 1)), ho_r=palms("r", (-0.4, -0.3, 0.2), (0, -0.2, 1)), curl_l=-0.3, curl_r=-0.3,
                  foot_l=V(0.11, -0.04, 0.104), foot_r=V(-0.11, 0.04, 0.104), fpit_l=0.0, fpit_r=0.0, shrug_l=None, shrug_r=None,
                  _bow={"hand_l": V(0.05, 0.0, 0.04), "hand_r": V(-0.05, 0.0, 0.04)}), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        if 27 <= fr <= 40:
            k = 1.0 - (fr - 27) / 14.0
            add(s, "hand_l", (0, 0, 0.03 * k * sw((fr - 27) / 10.0)))
            add(s, "hand_r", (0, 0, 0.03 * k * sw((fr - 27) / 10.0, 1, 0.25)))
    return F.build(keys, n, post)

# ============================================================================================ DARK
# Hunched, right claw low at the hip, left arm wrapped across the chest like a cloak; release = right arm reaches out with
# a spread claw, slow-in PULL of the claw to the chest (body folds back, resisting), clench + shake, then a burst: both
# arms flung wide as the chest snaps open.
DARK_STANCE = stance(0.22, -0.04, -0.22, 0.14, 20.0, -30.0)
DARK_BASE = dict(
    pel=V(0, 0.03, -0.13), tor=(20, 0, 0), head=(14, 0, 0),
    hand_r=V(-0.30, -0.26, 0.92), hand_l=V(-0.14, -0.24, 1.24),
    ho_r=palms("r", (0, -0.5, -0.8), (1, -0.2, 0.2)), ho_l=palms("l", (-1, -0.1, 0.3), (0, 1, 0)),
    curl_r=0.55, curl_l=0.3, **DARK_STANCE)

def _dark_charge_post(fr, n, s):
    u = fr / n
    add(s, "hand_r", (0.0, 0.07 * sw(u), 0.04 * sw(u, 2)))
    add(s, "hand_l", (0.0, 0.0, 0.02 * sw(u, 2)))
    s["pel"] = V(0.05 * sw(u), 0.03, -0.13 + 0.016 * sw(u, 2))
    s["tor"] = (20 + 2 * sw(u, 2), 9 * sw(u), -6 * sw(u))
    s["head"] = (14 + 3 * sw(u, 2), -6 * sw(u), 0)
    s["curl_r"] = 0.55 + 0.15 * sw(u, 2)

@clip("Cast_Dark_Charge", True, note="hunched, low right claw creeping, left arm wrapped across the chest, slow predatory sway")
def dark_charge():
    n = 42
    return F.build([(0, DARK_BASE), (n, {})], n, _dark_charge_post)

@clip("Cast_Dark_Release", False, release=27,
      note="right claw reaches out with spread fingers (f0-9), hold, slow-in PULL to the chest as the body folds back and resists (f11-21), clench + shake (f21-24), burst: both arms flung wide, chest snaps open (release f27), overshoot f30, droop, recovery step",
      events={"reach": 9, "pull_end": 21, "release": 27, "overshoot": 30})
def dark_release():
    n = 58
    keys = [
        (0, DARK_BASE),
        (9, dict(hand_r=V(-0.34, -0.72, 1.12), hand_l=V(-0.06, -0.22, 1.26), pel=V(0.02, -0.12, -0.16), tor=(32, 14, 0), hip=(0, 6, 0), head=(6, -8, 0),
                 ho_r=palms("r", (-0.2, -1, 0.1), (0.3, 0, -1)), curl_r=-0.8, foot_l=V(0.22, -0.14, 0.104),
                 _bow={"hand_r": V(-0.08, -0.05, 0.10)}), "smooth"),
        (11, dict(hand_r=V(-0.36, -0.75, 1.15), curl_r=-0.9), "out2"),
        (21, dict(hand_r=V(-0.16, -0.20, 1.06), hand_l=V(-0.30, -0.22, 1.16), pel=V(0.0, 0.14, -0.20), tor=(16, -30, 6), hip=(0, -12, 0), head=(20, 18, 0),
                  ho_r=palms("r", (0, -0.6, -0.6), (1, -0.2, 0.2)), ho_l=palms("l", (-1, -0.1, 0.4), (0, 1, 0)), curl_r=1.0, curl_l=0.8, elb_r=V(-0.62, 0.05, 1.20),
                  foot_l=V(0.22, -0.02, 0.104),
                  _bow={"hand_r": V(0.0, 0.0, -0.14)}), "in2"),
        (24, dict(hand_r=V(-0.16, -0.18, 1.04)), "smooth"),
        (27, dict(hand_r=rel(-0.80, 0.06, 1.14, 4), hand_l=rel(0.80, 0.06, 1.14, 4), pel=V(0.0, -0.08, -0.06), tor=(-12, 4, 0), hip=(0, 2, 0), head=(-14, 0, 0),
                  ho_r=pl("r", (-1, 0.1, 0.1), (0.3, 0, 1), 4), ho_l=pl("l", (1, 0.1, 0.1), (-0.3, 0, 1), 4), curl_r=-1.0, curl_l=-1.0, elb_r=None,
                  foot_l=V(0.24, -0.10, 0.104), fyaw_l=15.0,
                  _bow={"hand_r": V(0.0, -0.08, 0.05), "hand_l": V(0.0, -0.08, 0.05)}), "in"),
        (31, dict(hand_r=rel(-0.86, 0.04, 1.22, 4), hand_l=rel(0.86, 0.04, 1.22, 4), pel=V(0.0, -0.06, -0.03), tor=(-16, 2, 0), head=(-18, 0, 0)), "out"),
        (42, dict(hand_r=rel(-0.62, 0.06, 0.94, 0), hand_l=rel(0.62, 0.06, 0.94, 0), pel=V(0, 0.0, -0.12), tor=(14, 0, 0), head=(6, 0, 0), curl_r=0.0, curl_l=0.0), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        tremble(s, fr, 21, 24, 0.012, 2.2, 81)
        decay_shake(s, fr, 27, 6, 0.014, 1.5, 83)
    return F.build(keys, n, post)

# ============================================================================================ SHARED: AoE SLAM
# Crouch (anticipation), spring up with both fists overhead, hang at the apex, drive both fists into the ground on landing.
@clip("Cast_AoE_Slam", False, release=27,
      note="deep crouch, fists swung back (f0-8), leap with both fists swept up overhead (feet clear f11-24, apex hang f17-21), slam: fists hammer the ground on landing (release f27 = ground contact, pelvis squash, deep knees), shockwave shake, slow rise",
      events={"crouch": 8, "takeoff": 11, "apex": 18, "land": 27, "rise_start": 40})
def aoe_slam():
    n = 66
    ST = stance(0.24, -0.02, -0.24, 0.02, 12.0, -12.0)
    keys = [
        (0, dict(pel=V(0, 0.02, -0.06), tor=(6, 0, 0), head=(-5, 0, 0), hand_l=V(0.28, -0.14, 0.84), hand_r=V(-0.28, -0.14, 0.84),
                 ho_l=palms("l", (0.2, -1, 0), (-1, 0, 0.3)), ho_r=palms("r", (-0.2, -1, 0), (1, 0, 0.3)), curl_l=0.6, curl_r=0.6, **ST)),
        (8, dict(pel=V(0, 0.12, -0.34), tor=(34, 0, 0), head=(-12, 0, 0), hand_l=V(0.30, 0.34, 0.66), hand_r=V(-0.30, 0.34, 0.66),
                 ho_l=palms("l", (0.2, 0.6, -1), (-1, 0, 0)), ho_r=palms("r", (-0.2, 0.6, -1), (1, 0, 0)), curl_l=0.9, curl_r=0.9,
                 _bow={"hand_l": V(0, 0.08, -0.06), "hand_r": V(0, 0.08, -0.06)}), "in2"),
        (10, dict(), "lin"),
        (14, dict(pel=V(0, 0.0, 0.30), tor=(-14, 0, 0), head=(-26, 0, 0), hand_l=V(0.24, -0.26, 2.26), hand_r=V(-0.24, -0.26, 2.26),
                  ho_l=palms("l", (0, -0.2, 1), (-1, 0, 0)), ho_r=palms("r", (0, -0.2, 1), (1, 0, 0)), curl_l=0.9, curl_r=0.9,
                  foot_l=V(0.22, -0.02, 0.30), foot_r=V(-0.22, 0.02, 0.26), fpit_l=-25.0, fpit_r=-25.0,
                  _bow={"hand_l": V(0.10, 0.34, 0.0), "hand_r": V(-0.10, 0.34, 0.0)}), "out"),
        (18, dict(pel=V(0, 0.0, 0.34), tor=(-18, 0, 0), hand_l=V(0.22, -0.20, 2.34), hand_r=V(-0.22, -0.20, 2.34),
                  foot_l=V(0.22, -0.06, 0.38), foot_r=V(-0.22, 0.02, 0.32)), "out2"),
        (21, dict(pel=V(0, -0.02, 0.30), tor=(-10, 0, 0), foot_l=V(0.24, -0.06, 0.34), foot_r=V(-0.24, 0.02, 0.28)), "smooth"),
        (27, dict(pel=V(0, -0.14, -0.46), tor=(48, 0, 0), hip=(32, 0, 0), head=(-40, 0, 0), hand_l=V(0.26, -0.66, 0.30), hand_r=V(-0.26, -0.66, 0.30),
                  ho_l=palms("l", (0, -1, -0.6), (-1, 0, 0)), ho_r=palms("r", (0, -1, -0.6), (1, 0, 0)), curl_l=0.6, curl_r=0.6,
                  foot_l=V(0.28, -0.02, 0.104), foot_r=V(-0.28, 0.04, 0.104), fpit_l=0.0, fpit_r=0.0,
                  _bow={"hand_l": V(0.0, -0.22, 0.10), "hand_r": V(0.0, -0.22, 0.10)}), "in"),
        (30, dict(pel=V(0, -0.08, -0.40), hand_l=V(0.34, -0.70, 0.30), hand_r=V(-0.34, -0.70, 0.30)), "out"),
        (40, dict(pel=V(0, -0.04, -0.36), head=(-28, 0, 0)), "smooth"),
        (52, dict(pel=V(0, 0.0, -0.14), tor=(22, 0, 0), hip=(4, 0, 0), hand_l=V(0.30, -0.30, 0.62), hand_r=V(-0.30, -0.30, 0.62), head=(-10, 0, 0), curl_l=0.3, curl_r=0.3), "smooth"),
        recover(n),
    ]
    def post(fr, n, s):
        if 27 <= fr < 36:
            k = 1.0 - (fr - 27) / 9.0
            addt(s, "tor", tuple(snapnoise(fr, 99999, 91, 1, 1.8 * k)))
            addt(s, "head", tuple(snapnoise(fr, 99999, 92, 1, 2.5 * k)))
    return F.build(keys, n, post)

# ============================================================================================ SHARED: CHANNEL BEAM (loop)
# Braced lunge, right arm thrust to the target at eye level, left arm hauled back at the hip (archer silhouette: reads from
# the front as an asymmetric wide pose), constant strain vibration, chest breathing.
def _beam_post(fr, n, s):
    u = fr / n
    v = 0.006
    add(s, "hand_r", (v * sw(u, 7), 0.010 * sw(u, 5), v * cw(u, 6)))
    add(s, "hand_l", (0.006 * cw(u, 5), 0.008 * sw(u, 6), 0.006 * sw(u, 7)))
    addt(s, "tor", (1.2 * sw(u, 2), 0.8 * sw(u, 3), 0.8 * cw(u, 5)))
    addt(s, "head", (0.8 * sw(u, 4), 0, 0))
    add(s, "pel", (0.004 * sw(u, 5), 0.010 * sw(u, 2), 0.010 * sw(u, 3)))

@clip("Cast_Channel_Beam", True, note="braced lunge, right arm thrust to the target at eye level with strain vibration, left arm hauled back at the hip, chest breathing (loop)")
def channel_beam():
    n = 36
    Y = 26
    base = dict(pel=V(0, 0.10, -0.26), head=(-18, 0, 0), **B(16, Y, 3, split=0.4),
                hand_r=rel(-0.06, 0.70, 1.36, Y), hand_l=rel(0.34, -0.06, 1.02, Y),
                ho_r=pl("r", (0, 1, 0.15), (1, 0, 0.3), Y), ho_l=pl("l", (0.2, 1, -0.2), (-1, 0, 0.3), Y),
                curl_r=-0.9, curl_l=0.85, elb_l=rel(0.62, -0.20, 1.10, Y),
                foot_l=V(0.26, -0.34, 0.104), foot_r=V(-0.28, 0.24, 0.104), fyaw_l=26.0, fyaw_r=-40.0)
    return F.build([(0, base), (n, {})], n, _beam_post)
