# Key poses of the elemental casting clips (see author_casting_elements.py for the framework).
# World axes: character faces -Y, +Z up, +X = character's LEFT.  30 fps.  Feet are IK-pinned (ankle targets),
# so a foot never moves unless a key moves it.  Each element has Cast_<El>_Charge (loop) and Cast_<El>_Release.
# Release frame 0 == Charge frame 0 (same BASE dict), so the hand-over is seamless.
import math, types, random
from mathutils import Vector

F = None
def init(g):
    global F
    F = types.SimpleNamespace(**g)

def V(x, y, z):
    return Vector((x, y, z))

CLIPS = {}
def clip(name, loop, release=None, note=""):
    def deco(fn):
        CLIPS[name] = {"poses": fn, "loop": loop, "release": release, "note": note}
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

def yaws(total):
    """split a total torso yaw into (hip yaw, spine yaw)"""
    return 0.3 * total, 0.7 * total

def relaxed_end(sx_hand=0.27, hy=-0.04, hz=0.86):
    return dict(hand_l=V(sx_hand, hy, hz), hand_r=V(-sx_hand, hy, hz),
                ho_l=palms("l", (0, 0, -1), (-1, 0, 0)), ho_r=palms("r", (0, 0, -1), (1, 0, 0)), curl_l=0.15, curl_r=0.15,
                tor=(3, 0, 0), head=(0, 0, 0), hip=(0, 0, 0))

# ============================================================================================ FIRE
# Two-hand thrust.  Charge: cupped hands at the chest squeeze and swell.  Release @11: hands fully extended.
FIRE_STANCE = stance(0.21, -0.10, -0.21, 0.22, 8.0, -22.0)
FIRE_BASE = dict(
    pel=V(0, 0.02, -0.08), tor=(12, 0, 0), head=(-10, 0, 0),
    hand_l=V(0.10, -0.33, 1.20), hand_r=V(-0.10, -0.33, 1.20),
    ho_l=palms("l", (0, -1, 0.25), (-1, 0, 0.3)), ho_r=palms("r", (0, -1, 0.25), (1, 0, 0.3)),
    curl_l=0.45, curl_r=0.45, **FIRE_STANCE)

def _fire_charge_post(fr, n, s):
    u = fr / n
    p = sw(u)
    add(s, "hand_l", (-0.035 * p, 0.05 * p, 0.02 * p))
    add(s, "hand_r", (0.035 * p, 0.05 * p, 0.02 * p))
    add(s, "pel", (0, 0.015 * p, 0.02 * sw(u, 2)))
    addt(s, "tor", (3.5 * p, 0, 0))
    j = 0.004 * sw(u, 5)
    add(s, "hand_l", (j, 0, -j))
    add(s, "hand_r", (j, 0, j))

@clip("Cast_Fire_Charge", True, note="two-hand cupped gather, tightening pulse; hands at chest")
def fire_charge():
    n = 36
    return F.build([(0, FIRE_BASE), (n, {})], n, _fire_charge_post)

@clip("Cast_Fire_Release", False, release=11, note="two-hand forward thrust")
def fire_release():
    n = 40
    keys = [
        (0, FIRE_BASE),
        (7, dict(hand_l=V(0.13, -0.10, 1.08), hand_r=V(-0.13, -0.10, 1.08), pel=V(0, 0.10, -0.11), tor=(-6, 0, 0), head=(-2, 0, 0), curl_l=0.75, curl_r=0.75)),
        (11, dict(hand_l=V(0.10, -0.66, 1.30), hand_r=V(-0.10, -0.66, 1.30), pel=V(0, -0.10, -0.10), tor=(24, 0, 0), head=(-22, 0, 0),
                  ho_l=palms("l", (0.05, -1, 0.25), (-1, 0, 0.1)), ho_r=palms("r", (-0.05, -1, 0.25), (1, 0, 0.1)), curl_l=-0.45, curl_r=-0.45), "in"),
        (14, dict(hand_l=V(0.10, -0.69, 1.32), hand_r=V(-0.10, -0.69, 1.32), tor=(26, 0, 0)), "out"),
        (27, dict(hand_l=V(0.24, -0.30, 1.02), hand_r=V(-0.24, -0.30, 1.02), pel=V(0, 0.0, -0.08), tor=(14, 0, 0), head=(-8, 0, 0), curl_l=0.3, curl_r=0.3,
                  ho_l=palms("l", (0, -1, -0.4), (-1, 0, 0)), ho_r=palms("r", (0, -1, -0.4), (1, 0, 0)))),
        (n, relaxed_end()),
    ]
    return F.build(keys, n)

# ============================================================================================ WATER
# Flowing wave: hands orbit an invisible orb with a swaying body; release = arm sweep low-left -> front -> high-right.
WATER_STANCE = stance(0.17, -0.10, -0.17, 0.16, 15.0, -25.0)

def _water_hands(s, u):
    # right hand above/left, left hand below/right; both orbit the orb slowly and out of phase
    s["hand_r"] = V(-0.16 + 0.12 * sw(u), -0.28 + 0.06 * cw(u), 1.18 + 0.10 * cw(u))
    s["hand_l"] = V(0.14 - 0.12 * sw(u), -0.24 - 0.06 * cw(u), 1.04 - 0.10 * cw(u))
    orient_to(s, "r", (-0.25 + 0.3 * sw(u), -1, -0.2 * cw(u)), (0.2, 0.1, -1))
    orient_to(s, "l", (0.25 - 0.3 * sw(u), -1, 0.2 * cw(u)), (-0.2, 0.1, 1))

WATER_BASE = dict(
    pel=V(0, 0.02, -0.06), tor=(6, 0, 0), head=(-4, 0, 0),
    hand_r=V(-0.16, -0.22, 1.28), hand_l=V(0.14, -0.30, 0.94),
    ho_r=palms("r", (-0.25, -1, -0.2), (0.2, 0.1, -1)), ho_l=palms("l", (0.25, -1, 0.2), (-0.2, 0.1, 1)),
    curl_l=-0.35, curl_r=-0.35, **WATER_STANCE)

def _water_charge_post(fr, n, s):
    u = fr / n
    _water_hands(s, u)
    s["pel"] = V(0.045 * sw(u), 0.02, -0.06 + 0.018 * sw(u, 2))
    s["tor"] = (6 + 2.5 * sw(u, 2), 13 * sw(u), 7 * sw(u))
    s["head"] = (-4, -5 * sw(u), -3 * sw(u))

@clip("Cast_Water_Charge", True, note="orbiting hands, swaying body (figure-8), soft fingers")
def water_charge():
    n = 42
    return F.build([(0, WATER_BASE), (n, {})], n, _water_charge_post)

@clip("Cast_Water_Release", False, release=12, note="wave sweep of the right arm, low-left -> front -> high-right")
def water_release():
    n = 42
    p8, p12, p18 = (0.06, 0.08), (-0.03, -0.08), (-0.07, -0.04)
    h8, t8 = yaws(30); h12, t12 = yaws(-2); h18, t18 = yaws(-34)
    keys = [
        (0, WATER_BASE),
        (8, dict(hand_r=rel(0.10, 0.30, 0.92, 30, p8), hand_l=rel(0.58, -0.05, 1.26, 30, p8), pel=V(0.06, 0.08, -0.12), tor=(16, t8, 8), hip=(0, h8, 0), head=(-2, 14, 0),
                 ho_r=palms("r", (1, -0.6, 0), (0, 0, 1)), ho_l=palms("l", (1, 0, 0.2), (0, -0.2, -1)), curl_l=0.15, curl_r=0.15)),
        (12, dict(hand_r=rel(-0.14, 0.54, 1.12, -2, p12), hand_l=rel(0.56, 0.0, 1.30, -2, p12), pel=V(-0.03, -0.08, -0.10), tor=(20, t12, -6), hip=(0, h12, 0), head=(-8, -4, 0),
                  ho_r=palms("r", (-0.2, -1, 0.3), (0.3, 0, 1)), curl_r=-0.6), "in2"),
        (15, dict(hand_r=rel(-0.40, 0.50, 1.30, -18, (-0.05, -0.06)), hand_l=rel(0.54, -0.10, 1.25, -18, (-0.05, -0.06)), pel=V(-0.05, -0.06, -0.10), tor=(16, yaws(-18)[1], -8), hip=(0, yaws(-18)[0], 0), head=(-8, -10, 0),
                  ho_r=palms("r", (-0.6, -1, 0.3), (0.25, 0, 1))), "smooth"),
        (18, dict(hand_r=rel(-0.55, 0.32, 1.46, -34, p18), hand_l=rel(0.50, -0.20, 1.20, -34, p18), pel=V(-0.07, -0.04, -0.09), tor=(12, t18, -9), hip=(0, h18, 0), head=(-6, -18, 0),
                  ho_r=palms("r", (-1, -0.4, 0.3), (0.2, -0.2, 1))), "out2"),
        (24, dict(hand_r=rel(-0.58, 0.30, 1.48, -36, p18), tor=(10, yaws(-36)[1], -9), hip=(0, yaws(-36)[0], 0)), "out"),
        (n, dict(relaxed_end(), pel=V(0, 0, -0.04))),
    ]
    return F.build(keys, n)

# ============================================================================================ EARTH
# Deep horse stance; charge = lift-and-stomp beat; release = raise both fists overhead, slam down with a stomp.
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
    lift = 0.20 * math.sin(math.pi * (u - 0.20) / 0.40) if 0.20 <= u <= 0.60 else 0.0
    s["hand_l"] = V(0.30 - 0.08 * h, -0.22 - 0.12 * h, 0.80 + 0.36 * h)
    s["hand_r"] = V(-0.30 + 0.08 * h, -0.22 - 0.12 * h, 0.80 + 0.36 * h)
    s["foot_r"] = V(-0.30, 0.06, 0.104 + lift)
    tri = max(0.0, 1.0 - abs(u - 0.66) / 0.08)
    sh = 0.05 * math.sin(math.pi * (u - 0.2) / 0.4) if 0.2 <= u <= 0.6 else 0.0
    s["pel"] = V(sh, 0.02, -0.20 + 0.035 * h - 0.03 * tri)
    s["tor"] = (12 - 3 * h + 5 * tri, 0, 0)
    s["curl_l"] = s["curl_r"] = 0.35 + 0.4 * h

@clip("Cast_Earth_Charge", True, note="horse stance, hands lift a boulder, right foot stomps at 60% of the loop")
def earth_charge():
    n = 42
    return F.build([(0, EARTH_BASE), (n, {})], n, _earth_charge_post)

@clip("Cast_Earth_Release", False, release=15, note="lift both fists overhead, stomp + slam to the ground")
def earth_release():
    n = 54
    keys = [
        (0, EARTH_BASE),
        (9, dict(hand_l=V(0.17, -0.10, 1.74), hand_r=V(-0.17, -0.10, 1.74), pel=V(0, 0.05, -0.08), tor=(-14, 0, 0), head=(-22, 0, 0),
                 ho_l=palms("l", (0, -0.2, 1), (-1, 0, 0)), ho_r=palms("r", (0, -0.2, 1), (1, 0, 0)), curl_l=0.85, curl_r=0.85,
                 foot_r=V(-0.30, 0.06, 0.30))),
        (11, dict()),
        (15, dict(hand_l=V(0.17, -0.42, 0.66), hand_r=V(-0.17, -0.42, 0.66), pel=V(0, -0.09, -0.29), tor=(50, 0, 0), head=(-24, 0, 0),
                  ho_l=palms("l", (0, -1, -0.5), (-1, 0, 0)), ho_r=palms("r", (0, -1, -0.5), (1, 0, 0)), foot_r=V(-0.30, 0.06, 0.104)), "in"),
        (32, dict(hand_l=V(0.17, -0.45, 0.64), hand_r=V(-0.17, -0.45, 0.64), tor=(52, 0, 0)), "out"),
        (n, dict(relaxed_end(), pel=V(0, 0.0, -0.08), hand_l=V(0.30, -0.10, 0.84), hand_r=V(-0.30, -0.10, 0.84), tor=(6, 0, 0))),
    ]
    return F.build(keys, n)

# ============================================================================================ WIND
# Arms sweep circles at their own side; release = torso whip, right arm arc from behind-right to far left.
WIND_STANCE = stance(0.15, -0.08, -0.15, 0.12, 10.0, -20.0)

def _wind_orbit(u, side):
    th = TAU * u + (0.0 if side == "l" else math.pi)
    sx = 1 if side == "l" else -1
    return V(sx * (0.34 + 0.12 * math.cos(th)), -0.24 - 0.17 * math.sin(th), 1.28 + 0.13 * math.sin(th)), th

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
    s["tor"] = (4, 12 * sw(u), 4 * cw(u) - 4)
    s["hip"] = (0, 5 * sw(u), 0)
    s["head"] = (-3, -6 * sw(u), 0)
    s["pel"] = V(0.02 * sw(u), 0.02, -0.05 + 0.01 * sw(u, 2))

@clip("Cast_Wind_Charge", True, note="both arms orbit at chest height (opposite phases), torso follows")
def wind_charge():
    n = 42
    return F.build([(0, WIND_BASE), (n, {})], n, _wind_charge_post)

@clip("Cast_Wind_Release", False, release=12, note="torso whip, right arm sweeps a wide arc from behind-right to far left")
def wind_release():
    n = 42
    P8, P12, P17 = (0, 0.07), (0, -0.03), (0, -0.03)
    Y8, Y12, Y17 = -58.0, 4.0, 56.0
    keys = [
        (0, WIND_BASE),
        (8, dict(hand_r=rel(-0.58, -0.05, 1.36, Y8, P8), hand_l=rel(0.02, 0.32, 1.26, Y8, P8), tor=(4, yaws(Y8)[1], 0), hip=(0, yaws(Y8)[0], 0), head=(-2, -30, 0), pel=V(0, 0.07, -0.08),
                 ho_r=palms("r", (-1, 0.3, 0.1), (0, 0, -1)), ho_l=palms("l", (-1, -0.2, 0), (0, 1, 0)), curl_l=0.0, curl_r=-0.6)),
        (10, dict(hand_r=rel(-0.62, 0.22, 1.40, -28, (0, 0.03)), hand_l=rel(0.30, 0.20, 1.26, -28, (0, 0.03)), tor=(8, yaws(-28)[1], 0), hip=(0, yaws(-28)[0], 0), head=(-3, -14, 0), pel=V(0, 0.02, -0.09),
                  ho_r=palms("r", (-0.3, -1, 0.1), (0, 0, -1)), ho_l=palms("l", (1, 0, 0), (0, 0, -1))), "in2"),
        (12, dict(hand_r=rel(-0.20, 0.50, 1.36, Y12, P12), hand_l=rel(0.52, 0.0, 1.26, Y12, P12), tor=(10, yaws(Y12)[1], 0), hip=(0, yaws(Y12)[0], 0), head=(-4, 8, 0), pel=V(0, -0.03, -0.09),
                  ho_r=palms("r", (0, -1, 0.1), (0, 0, -1)), ho_l=palms("l", (1, 0, 0), (0, 0, -1))), "in"),
        (17, dict(hand_r=rel(-0.20, 0.50, 1.36, Y17, P17), hand_l=rel(0.58, -0.22, 1.24, Y17, P17), tor=(10, yaws(Y17)[1], 0), hip=(0, yaws(Y17)[0], 0), head=(-4, 34, 0),
                  ho_r=palms("r", (0, -1, 0.1), (0, 0, -1)), ho_l=palms("l", (1, 0.3, 0), (0, 0, -1))), "out2"),
        (22, dict(tor=(10, yaws(60)[1], 0), hip=(0, yaws(60)[0], 0), hand_r=rel(-0.20, 0.50, 1.36, 60, P17), hand_l=rel(0.58, -0.22, 1.24, 60, P17)), "out"),
        (n, dict(relaxed_end(), tor=(3, 0, 0), hip=(0, 0, 0), pel=V(0, 0.0, -0.04))),
    ]
    return F.build(keys, n)

# ============================================================================================ LIGHTNING
# Right arm to the sky (jittery), left fist at the hip; release = arm snaps down to point at the target.
LIGHTNING_STANCE = stance(0.17, -0.06, -0.17, 0.10, 12.0, -18.0)
LIGHTNING_BASE = dict(
    pel=V(0, 0.03, -0.07), tor=(-6, 0, -3), head=(-32, 0, 0),
    hand_r=V(-0.13, -0.02, 1.97), hand_l=V(0.24, -0.10, 0.98),
    ho_r=palms("r", (0.0, -0.1, 1), (0, -1, 0.1)), ho_l=palms("l", (0.3, -1, -0.6), (0, 0, 1)),
    curl_r=-0.7, curl_l=0.75, **LIGHTNING_STANCE)

def _lightning_charge_post(fr, n, s):
    u = fr / n
    j = snapnoise(fr, n, 1, 2, 0.010)
    add(s, "hand_r", j)
    add(s, "hand_l", snapnoise(fr, n, 2, 3, 0.006))
    addt(s, "tor", tuple(snapnoise(fr, n, 3, 2, 0.7)))
    addt(s, "head", tuple(snapnoise(fr, n, 4, 4, 1.2)))
    add(s, "hand_r", (0, 0, 0.02 * sw(u)))
    s["curl_r"] = -0.7 + 0.25 * sw(u, 3) if fr % n else -0.7

@clip("Cast_Lightning_Charge", True, note="right arm raised to the sky, snapped jitter, left fist at the hip, head up")
def lightning_charge():
    n = 36
    return F.build([(0, LIGHTNING_BASE), (n, {})], n, _lightning_charge_post)

@clip("Cast_Lightning_Release", False, release=9, note="arm snaps from the sky down to a pointed strike, recoil jitter")
def lightning_release():
    n = 40
    def post(fr, n, s):
        if fr >= 9:
            k = max(0.0, 1.0 - (fr - 9) / 9.0)
            add(s, "hand_r", snapnoise(fr, 9999, 5, 1, 0.02 * k))
            addt(s, "tor", tuple(snapnoise(fr, 9999, 6, 1, 1.5 * k)))
    keys = [
        (0, LIGHTNING_BASE),
        (5, dict(hand_r=V(-0.15, 0.08, 1.90), hand_l=V(0.30, -0.28, 1.10), tor=(-20, 0, -4), head=(-38, 0, 0), pel=V(0, 0.08, -0.09),
                 ho_r=palms("r", (0, 0.3, 1), (0, -1, 0)), curl_r=-0.9, curl_l=0.4)),
        (9, dict(hand_r=V(-0.10, -0.66, 1.24), hand_l=V(0.52, 0.12, 1.20), tor=(22, 0, -4), head=(-18, 0, 0), pel=V(0, -0.09, -0.10),
                 ho_r=palms("r", (0, -1, -0.15), (1, 0, 0)), curl_r=0.35, curl_l=-0.2,
                 ho_l=palms("l", (1, 0.2, 0), (0, 0, -1))), "in"),
        (20, dict(hand_r=V(-0.16, -0.52, 1.12), tor=(16, 0, 0), head=(-10, 0, 0), pel=V(0, -0.04, -0.08)), "out"),
        (n, relaxed_end()),
    ]
    return F.build(keys, n, post)

# ============================================================================================ ICE
# Rigid: arms crossed in front of the chest (fine frost tremor), release = crossed arms burst out into a hard palm push.
ICE_STANCE = stance(0.14, -0.05, -0.14, 0.06, 4.0, -4.0)
ICE_BASE = dict(
    pel=V(0, 0.02, -0.03), tor=(2, 0, 0), head=(0, 0, 0),
    hand_r=V(0.12, -0.30, 1.30), hand_l=V(-0.12, -0.22, 1.30),
    ho_r=palms("r", (0.6, -0.2, 1), (0, 1, 0.3)), ho_l=palms("l", (-0.6, -0.2, 1), (0, 1, 0.3)),
    curl_l=-0.8, curl_r=-0.8, shrug_l=9.0, shrug_r=9.0, **ICE_STANCE)

def _ice_charge_post(fr, n, s):
    u = fr / n
    j = 0.0035 * sw(u, 9)
    add(s, "hand_r", (j, 0, 0.5 * j))
    add(s, "hand_l", (-j, 0, 0.5 * j))
    addt(s, "tor", (0.4 * sw(u, 9), 0, 0))
    add(s, "hand_r", (0, 0.012 * sw(u), 0.01 * sw(u)))
    add(s, "hand_l", (0, 0.012 * sw(u), 0.01 * sw(u)))

@clip("Cast_Ice_Charge", True, note="rigid crossed forearms at the chest, tiny frost tremor, shoulders raised")
def ice_charge():
    n = 36
    return F.build([(0, ICE_BASE), (n, {})], n, _ice_charge_post)

@clip("Cast_Ice_Release", False, release=9, note="crossed arms burst out into a stiff two-hand palm push, then hold frozen")
def ice_release():
    n = 40
    keys = [
        (0, ICE_BASE),
        (5, dict(hand_r=V(0.14, -0.14, 1.34), hand_l=V(-0.14, -0.10, 1.34), tor=(-4, 0, 0), pel=V(0, 0.05, -0.05), head=(0, 0, 0), shrug_l=12.0, shrug_r=12.0), "lin"),
        (9, dict(hand_r=V(-0.20, -0.52, 1.30), hand_l=V(0.20, -0.52, 1.30), tor=(12, 0, 0), pel=V(0, -0.02, -0.06), head=(-8, 0, 0),
                 ho_r=palms("r", (0, -0.4, 1), (0, -1, 0.3)), ho_l=palms("l", (0, -0.4, 1), (0, -1, 0.3)), shrug_l=None, shrug_r=None), "lin"),
        (24, dict(hand_r=V(-0.22, -0.53, 1.30), hand_l=V(0.22, -0.53, 1.30)), "lin"),
        (n, relaxed_end()),
    ]
    def post(fr, n, s):
        if 9 <= fr <= 26:
            add(s, "hand_r", (0.003 * sw(fr, 0.5), 0, 0)); add(s, "hand_l", (-0.003 * sw(fr, 0.5), 0, 0))
    return F.build(keys, n, post)

# ============================================================================================ LIGHT
# Raised open palms in a V, chest lifted, slow swell; release = hands meet overhead, then sweep forward into a blessing.
LIGHT_STANCE = stance(0.11, -0.04, -0.11, 0.04, 6.0, -6.0)
LIGHT_BASE = dict(
    pel=V(0, 0.02, -0.02), tor=(-8, 0, 0), head=(-22, 0, 0),
    hand_l=V(0.44, -0.04, 1.86), hand_r=V(-0.44, -0.04, 1.86),
    ho_l=palms("l", (0.3, 0, 1), (0, -0.7, 0.7)), ho_r=palms("r", (-0.3, 0, 1), (0, -0.7, 0.7)),
    curl_l=-0.9, curl_r=-0.9, **LIGHT_STANCE)

def _light_charge_post(fr, n, s):
    u = fr / n
    add(s, "hand_l", (0.02 * sw(u), 0.0, 0.035 * sw(u)))
    add(s, "hand_r", (-0.02 * sw(u), 0.0, 0.035 * sw(u)))
    add(s, "pel", (0, 0, 0.012 * sw(u)))
    addt(s, "tor", (-2.0 * sw(u), 0, 0))
    addt(s, "head", (-2.5 * sw(u), 0, 0))

@clip("Cast_Light_Charge", True, note="open palms raised in a V, slow rising swell")
def light_charge():
    n = 48
    return F.build([(0, LIGHT_BASE), (n, {})], n, _light_charge_post)

@clip("Cast_Light_Release", False, release=17, note="hands meet overhead, sweep down and forward: blessing / beam")
def light_release():
    n = 48
    keys = [
        (0, LIGHT_BASE),
        (9, dict(hand_l=V(0.07, -0.08, 1.92), hand_r=V(-0.07, -0.08, 1.92), tor=(-14, 0, 0), head=(-28, 0, 0), pel=V(0, 0.04, -0.03),
                 ho_l=palms("l", (0, 0, 1), (-1, 0, 0)), ho_r=palms("r", (0, 0, 1), (1, 0, 0)))),
        (17, dict(hand_l=V(0.20, -0.50, 1.46), hand_r=V(-0.20, -0.50, 1.46), tor=(12, 0, 0), head=(-8, 0, 0), pel=V(0, -0.05, -0.07),
                  ho_l=palms("l", (0.1, -0.3, 1), (0, -1, 0.3)), ho_r=palms("r", (-0.1, -0.3, 1), (0, -1, 0.3))), "in2"),
        (30, dict(hand_l=V(0.24, -0.52, 1.50), hand_r=V(-0.24, -0.52, 1.50), tor=(10, 0, 0), pel=V(0, -0.04, -0.05)), "out"),
        (n, relaxed_end()),
    ]
    return F.build(keys, n)

# ============================================================================================ DARK
# Hunched, right claw low at the hip, left arm wrapped across the chest like a cloak; release = claw grabs forward and
# drags back while the left arm flares wide.
DARK_STANCE = stance(0.22, -0.04, -0.22, 0.14, 20.0, -30.0)
DARK_BASE = dict(
    pel=V(0, 0.03, -0.13), tor=(20, 0, 0), head=(14, 0, 0),
    hand_r=V(-0.30, -0.26, 0.92), hand_l=V(-0.14, -0.24, 1.24),
    ho_r=palms("r", (0, -0.5, -0.8), (1, -0.2, 0.2)), ho_l=palms("l", (-1, -0.1, 0.3), (0, 1, 0)),
    curl_r=0.55, curl_l=0.3, **DARK_STANCE)

def _dark_charge_post(fr, n, s):
    u = fr / n
    add(s, "hand_r", (0.0, 0.05 * sw(u), 0.03 * sw(u, 2)))
    add(s, "hand_l", (0.0, 0.0, 0.015 * sw(u, 2)))
    s["pel"] = V(0.03 * sw(u), 0.03, -0.13 + 0.012 * sw(u, 2))
    s["tor"] = (20 + 1.5 * sw(u, 2), 6 * sw(u), -4 * sw(u))
    s["head"] = (14 + 2 * sw(u, 2), -4 * sw(u), 0)
    s["curl_r"] = 0.55 + 0.1 * sw(u, 2)

@clip("Cast_Dark_Charge", True, note="hunched, low right claw creeping, left arm wrapped across the chest")
def dark_charge():
    n = 42
    return F.build([(0, DARK_BASE), (n, {})], n, _dark_charge_post)

@clip("Cast_Dark_Release", False, release=12, note="claw thrust forward then drag-pull, left arm cloak flare")
def dark_release():
    n = 46
    keys = [
        (0, DARK_BASE),
        (8, dict(hand_r=V(-0.34, 0.10, 0.86), hand_l=V(0.02, -0.28, 1.28), tor=(22, 26, 0), hip=(0, 10, 0), head=(12, 18, 0), pel=V(0.02, 0.08, -0.15),
                 ho_r=palms("r", (0, 0.3, -1), (1, 0, 0)), curl_r=0.35)),
        (12, dict(hand_r=V(-0.20, -0.62, 0.96), hand_l=V(0.34, -0.10, 1.20), tor=(38, -14, 0), hip=(0, -8, 0), head=(6, -8, 0), pel=V(0, -0.12, -0.17),
                  ho_r=palms("r", (0, -1, -0.4), (1, 0, 0)), curl_r=0.75, ho_l=palms("l", (1, 0, 0), (0, 0, -1))), "in"),
        (20, dict(hand_r=V(-0.30, -0.20, 0.96), hand_l=V(0.68, 0.0, 1.06), tor=(28, -8, 0), pel=V(0, -0.02, -0.15), curl_r=0.85), "smooth"),
        (28, dict(hand_r=V(-0.30, -0.06, 0.90), hand_l=V(0.66, 0.02, 1.02), tor=(24, 0, 0), hip=(0, 0, 0), head=(10, 0, 0)), "smooth"),
        (n, dict(relaxed_end(), pel=V(0, 0.02, -0.06), tor=(6, 0, 0))),
    ]
    return F.build(keys, n)
