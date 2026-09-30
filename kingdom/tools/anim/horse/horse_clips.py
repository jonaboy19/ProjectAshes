# Horse clip definitions for the gait engine (horse_gait.py). Real gait references (footfall order and timing):
#   walk    4-beat lateral sequence  LH, LF, RH, RF   (each beat 25 % of the stride, duty ~0.62, 1.6 m/s)
#   trot    2-beat diagonal          LH+RF, RH+LF      (duty ~0.42 -> two short suspensions, 3.6 m/s)
#   canter  3-beat (left lead)       RH, LH+RF, LF, suspension     (5.8 m/s)
#   gallop  4-beat (left lead)       RH, LH, RF, LF, suspension     (11 m/s)
# Leg keys: FL/FR = fore left/right, HL/HR = hind left/right. Horse left = +X. Forward = -Y.
import math
from mathutils import Vector, Matrix, Quaternion
import horse_gait as G

V = G.V
Trk = G.Trk
CLIPS = {}
ENG = None
TAU = 2 * math.pi
rad = math.radians


def setup(eng):
    global ENG
    ENG = eng


def clip(fn):
    CLIPS[fn.__name__] = fn
    return fn


def root_line(speed, yaw_rate=0.0):
    """root path: straight (yaw_rate 0) or a circular arc at constant speed; returns pos(t), yaw(t), xf(t)"""
    if abs(yaw_rate) < 1e-6:
        pos = lambda t: V(0, -speed * t, 0)
        yaw = lambda t: 0.0
    else:
        R = speed / yaw_rate
        # heading -Y at t=0, turning left (+yaw) curves toward +X
        pos = lambda t: V(R * (1 - math.cos(yaw_rate * t)), -R * math.sin(yaw_rate * t), 0)
        yaw = lambda t: yaw_rate * t
    xf = lambda t: Matrix.Translation(pos(t)) @ Quaternion((0, 0, 1), yaw(t)).to_matrix().to_4x4()
    return pos, yaw, xf


# ------------------------------------------------------------------ gait tables
GAITS = {
    # frames per stride, speed m/s, landing phase per leg, duty, swing height of the fetlock
    "walk": dict(frames=34, speed=1.5, pattern={"HL": 0.0, "FL": 0.25, "HR": 0.5, "FR": 0.75}, duty=0.60,
                 swing={"F": 0.11, "H": 0.10}, flex={"F": 0.8, "H": 0.5}, fflex={"F": 0.95, "H": 0.85}, load={"F": 0.18, "H": 0.14},
                 breakover=0.45),
    "trot": dict(frames=22, speed=3.6, pattern={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5}, duty=0.42,
                 swing={"F": 0.22, "H": 0.17}, flex={"F": 1.55, "H": 0.85}, fflex={"F": 1.45, "H": 1.2}, load={"F": 0.35, "H": 0.28},
                 breakover=0.6),
    "canter": dict(frames=18, speed=5.8, pattern={"HR": 0.0, "HL": 0.20, "FR": 0.24, "FL": 0.44}, duty={"HR": 0.36, "HL": 0.36, "FR": 0.33, "FL": 0.34},
                   swing={"F": 0.26, "H": 0.20}, flex={"F": 1.7, "H": 1.0}, fflex={"F": 1.6, "H": 1.3}, load={"F": 0.42, "H": 0.32},
                   breakover=0.7),
    "gallop": dict(frames=14, speed=11.0, pattern={"HR": 0.0, "HL": 0.11, "FR": 0.30, "FL": 0.41}, duty={"HR": 0.26, "HL": 0.26, "FR": 0.25, "FL": 0.26},
                   swing={"F": 0.30, "H": 0.24}, flex={"F": 1.9, "H": 1.15}, fflex={"F": 1.7, "H": 1.4}, load={"F": 0.5, "H": 0.38},
                   breakover=0.8),
    "backup": dict(frames=40, speed=-0.7, pattern={"HL": 0.0, "FR": 0.0, "HR": 0.5, "FL": 0.5}, duty=0.66,
                   swing={"F": 0.09, "H": 0.08}, flex={"F": 0.8, "H": 0.5}, fflex={"F": 0.9, "H": 0.8}, load={"F": 0.12, "H": 0.1},
                   breakover=0.3),
}


def mirror_pattern(p):
    sw = {"FL": "FR", "FR": "FL", "HL": "HR", "HR": "HL"}
    return {sw[k]: v for k, v in p.items()}


def base_script(name, g, loop=True, yaw_rate=0.0, lead="L"):
    T = g["frames"] / G.FPS
    sc = G.Script(name, T, loop)
    pos, yaw, xf = root_line(g["speed"], yaw_rate)
    sc.root_pos, sc.root_yaw = pos, yaw
    pat = g["pattern"] if lead == "L" else mirror_pattern(g["pattern"])
    duty = g["duty"]
    if isinstance(duty, dict) and lead != "L":
        duty = mirror_pattern(duty)
    G.gait_stances(sc, pat, T, duty, -3 * T, 3 * T, xf, ENG.neutral)
    for leg in G.LEGS:
        sc.swing_h[leg] = g["swing"][leg[0]]
    sc.flex = dict(g["flex"])
    sc.fetlock_flex = dict(g["fflex"])
    sc.load = dict(g["load"])
    sc.breakover = g["breakover"]
    sc.meta = {"gait": name.split("_")[0].lower(), "stride_m": round(abs(g["speed"]) * T, 3), "stride_s": round(T, 3),
               "footfall_phase": pat, "duty": duty, "lead": lead}
    sc.events = {}
    for leg in G.LEGS:
        lands = sorted(set(int(round((tl % T) * G.FPS)) % g["frames"] for tl, tu, p in sc.stances[leg]))
        sc.events["hoof_" + leg] = lands
    return sc, T, pat


def per(T, f):
    """periodic helper: f(phase 0..1) -> callable of t"""
    return lambda t: f((t / T) % 1.0)


# ------------------------------------------------------------------ loops
@clip
def Walk():
    sc, T, pat = base_script("Walk", GAITS["walk"])
    run_body(sc, T, "walk")
    return sc

def run_body(sc, T, kind, lead="L"):
    """body, neck, head, tail profiles for the faster gaits (phase p in 0..1 of the stride)"""
    c = math.cos; s = math.sin
    sg = 1.0 if lead == "L" else -1.0
    if kind == "walk":
        # two small bobs per stride on top of the support constraint, roll toward the loaded hind, gentle yaw;
        # head and neck nod twice per stride: down as each fore lands and loads, up during its swing
        sc.body_off = per(T, lambda p: V(0.006 * s(TAU * p), 0.0, -0.012 + 0.010 * c(2 * TAU * (p - 0.12))))
        sc.body_rot = per(T, lambda p: V(rad(0.8) * c(2 * TAU * (p - 0.2)), rad(2.2) * s(TAU * (p - 0.05)), rad(1.6) * s(TAU * (p + 0.2))))
        sc.spine = per(T, lambda p: V(0, rad(1.0) * s(TAU * p), rad(2.5) * s(TAU * (p + 0.15))))
        sc.neck = per(T, lambda p: V(rad(-6) + rad(5.5) * c(2 * TAU * (p - 0.37)), rad(1.5) * s(TAU * p), rad(2.5) * s(TAU * (p + 0.1))))
        sc.head = per(T, lambda p: V(rad(4) + rad(2.5) * c(2 * TAU * (p - 0.30)), 0, rad(-1.5) * s(TAU * (p + 0.1))))
        sc.ears = per(T, lambda p: (rad(-8), rad(6) + rad(3) * s(TAU * p), rad(-8), rad(6) - rad(3) * s(TAU * p)))
        sc.tail_base = per(T, lambda p: V(rad(4), 0, rad(6) * s(TAU * (p - 0.1))))
    elif kind == "trot":
        sc.body_off = per(T, lambda p: V(0, 0, -0.03 - 0.028 * c(2 * TAU * (p - 0.21))))
        sc.body_rot = per(T, lambda p: V(rad(0.8) * c(2 * TAU * (p - 0.25)), rad(1.4) * c(TAU * (p - 0.2)), rad(1.2) * s(TAU * p)))
        sc.spine = per(T, lambda p: V(rad(0.8) * c(2 * TAU * (p - 0.3)), 0, rad(1.2) * s(TAU * (p + 0.1))))
        sc.neck = per(T, lambda p: V(rad(-4) + rad(2.2) * c(2 * TAU * (p - 0.30)), 0, rad(1.0) * s(TAU * p)))
        sc.head = per(T, lambda p: V(rad(6) + rad(1.5) * c(2 * TAU * (p - 0.35)), 0, 0))
        sc.ears = per(T, lambda p: (rad(-5), rad(4), rad(-5), rad(4)))
        sc.tail_base = per(T, lambda p: V(rad(4), 0, rad(3) * s(TAU * p)))
        sc.tail_lift = const(rad(10))
    elif kind == "canter":
        sc.body_off = per(T, lambda p: V(sg * 0.01, 0, -0.035 - 0.035 * c(TAU * (p - 0.36))))
        sc.body_rot = per(T, lambda p: V(rad(6.5) * s(TAU * (p - 0.22)), sg * rad(2.0) * s(TAU * (p - 0.1)), sg * rad(2.5)))
        sc.spine = per(T, lambda p: V(rad(2.5) * c(TAU * (p - 0.85)), 0, sg * rad(2.0)))
        sc.neck = per(T, lambda p: V(rad(-3) + rad(8) * c(TAU * (p - 0.52)), 0, sg * rad(3)))
        sc.head = per(T, lambda p: V(rad(8) - rad(3) * c(TAU * (p - 0.55)), 0, sg * rad(2)))
        sc.ears = per(T, lambda p: (rad(-2), rad(6), rad(-2), rad(6)))
        sc.tail_base = per(T, lambda p: V(rad(6) + rad(5) * c(TAU * (p - 0.3)), 0, sg * rad(-3)))
        sc.tail_lift = const(rad(22))
        sc.support_max = 0.10
    elif kind == "gallop":
        sc.body_off = per(T, lambda p: V(0, 0, -0.05 - 0.035 * c(TAU * (p - 0.33))))
        sc.body_rot = per(T, lambda p: V(rad(4) + rad(5) * s(TAU * (p - 0.25)), sg * rad(1.5) * s(TAU * (p - 0.1)), sg * rad(1.5)))
        sc.spine = per(T, lambda p: V(rad(4.5) * c(TAU * (p - 0.88)), 0, 0))
        sc.neck = per(T, lambda p: V(rad(8) + rad(8) * c(TAU * (p - 0.48)), 0, sg * rad(2)))
        sc.head = per(T, lambda p: V(rad(-4) - rad(4) * c(TAU * (p - 0.5)), 0, 0))
        sc.ears = per(T, lambda p: (rad(18), rad(10), rad(18), rad(10)))
        sc.tail_base = per(T, lambda p: V(rad(14) + rad(4) * c(TAU * (p - 0.4)), 0, 0))
        sc.tail_lift = const(rad(35))
        sc.support_max = 0.12


def const(v):
    return lambda t: v


@clip
def Trot():
    sc, T, pat = base_script("Trot", GAITS["trot"])
    run_body(sc, T, "trot")
    return sc


@clip
def Canter_L():
    sc, T, pat = base_script("Canter_L", GAITS["canter"])
    run_body(sc, T, "canter", "L")
    return sc


@clip
def Canter_R():
    sc, T, pat = base_script("Canter_R", GAITS["canter"], lead="R")
    run_body(sc, T, "canter", "R")
    return sc


@clip
def Gallop_L():
    sc, T, pat = base_script("Gallop_L", GAITS["gallop"])
    run_body(sc, T, "gallop", "L")
    return sc


@clip
def Gallop_R():
    sc, T, pat = base_script("Gallop_R", GAITS["gallop"], lead="R")
    run_body(sc, T, "gallop", "R")
    return sc


@clip
def BackUp():
    g = GAITS["backup"]
    sc, T, pat = base_script("BackUp", g)
    c = math.cos; s = math.sin
    sc.body_off = per(T, lambda p: V(0, 0.02, -0.015 + 0.008 * c(2 * TAU * p)))
    sc.body_rot = per(T, lambda p: V(rad(-1.5), rad(1.2) * s(TAU * p), 0))
    sc.neck = per(T, lambda p: V(rad(-10), 0, 0))
    sc.head = per(T, lambda p: V(rad(12) + rad(2) * c(2 * TAU * p), 0, 0))
    sc.ears = per(T, lambda p: (rad(25), rad(15), rad(25), rad(15)))
    sc.tail_base = const(V(rad(6), 0, 0))
    return sc


import horse_clips2  # noqa: E402,F401  (transitions, turns, idles, actions register themselves in CLIPS)
