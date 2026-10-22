# Horse clips, part 3: idles (standing variants, graze, drink) and actions (rear, buck, spook, hit, death, jump, swim).
# Keyed values use Trk (Hermite through (time s, value) keys; 's' = hold key with zero tangent).
import math
from mathutils import Vector, Matrix, Quaternion
import horse_gait as G
import horse_clips as HC
import horse_clips2 as H2

V = G.V
Trk = G.Trk
clip = HC.clip
rad = math.radians
TAU = 2 * math.pi
Z3 = V(0, 0, 0)
EAR_REST = (rad(-6), rad(5), rad(-6), rad(5))


def stand(name, dur, loop=False):
    """square standing horse, all hooves planted at their neutral points for the whole clip"""
    sc = G.Script(name, dur, loop)
    for leg in G.LEGS:
        p = HC.ENG.neutral[leg].copy()
        p.z = 0.0
        sc.stances[leg] = [(-1000.0, 1000.0, p)]
    sc.neck = lambda t: H2.STAND_NECK
    sc.head = lambda t: H2.STAND_HEAD
    sc.tail_base = lambda t: H2.STAND_TAIL
    sc.ears = lambda t: EAR_REST
    sc.load = {"F": 0.0, "H": 0.0}
    sc.meta = {"gait": "idle"}
    return sc


def breath(T, amp=1.0):
    """breathing: belly and ribcage (spine) at a period that divides T"""
    k = max(1, round(T / 2.2))
    per = T / k
    return (lambda t: V(rad(1.2) * amp * math.sin(TAU * t / per), 0, 0),
            lambda t: V(rad(-0.5) * amp * math.sin(TAU * t / per), 0, 0),
            lambda t: V(0, 0, -0.004 * amp * math.sin(TAU * t / per)))


def trk3(keys, period=None):
    return Trk([(k[0], V(*k[1])) + tuple(k[2:]) for k in keys], period)


def ears_trk(keys, period=None):
    """ears: keys of (t, (Lpitch, Lyaw, Rpitch, Ryaw) degrees)"""
    tr = Trk([(k[0], Vector(tuple(rad(x) for x in k[1]))) + tuple(k[2:]) for k in keys], period)
    return lambda t: tuple(tr(t))


def deg3(x, y, z):
    return (rad(x), rad(y), rad(z))


def dtrk(keys, period=None):
    """Trk of degree triplets -> radians Vector"""
    return Trk([(k[0], V(*deg3(*k[1]))) + tuple(k[2:]) for k in keys], period)


# ------------------------------------------------------------------ idles
@clip
def Idle():
    T = 4.0
    sc = stand("Idle", T, True)
    b, sp, bo = breath(T)
    sc.belly, sc.spine, sc.body_off = b, sp, bo
    sc.neck = lambda t: H2.STAND_NECK + V(rad(1.5) * math.sin(TAU * t / T), 0, rad(3) * math.sin(TAU * t / T + 0.6))
    sc.head = lambda t: H2.STAND_HEAD + V(0, rad(1.5) * math.sin(TAU * t / T), rad(2) * math.sin(TAU * t / T + 1.1))
    sc.ears = ears_trk([(0, (-6, 5, -6, 5)), (1.0, (-4, 9, -6, 2)), (2.0, (-6, 5, -6, 5)), (3.0, (-6, 2, -4, 9)), (4.0, (-6, 5, -6, 5))], T)
    sc.tail_base = lambda t: H2.STAND_TAIL + V(0, 0, rad(3) * math.sin(TAU * t / T))
    return sc


@clip
def Idle_RestHind():
    """resting a hind leg: the left hind cocked on the toe, left hip dropped, head lower, ears relaxed"""
    T = 4.0
    sc = stand("Idle_RestHind", T, True)
    b, sp, bo = breath(T, 0.8)
    sc.belly = b
    sc.spine = lambda t: sp(t) + V(0, rad(-2.5), 0)
    sc.body_rot = lambda t: V(rad(0.6), rad(3.0), 0)
    sc.body_off = lambda t: bo(t) + V(0.02, 0, -0.015)
    toe = HC.ENG.neutral["HL"] + V(0, -0.10, 0)
    toe.z = 0.0
    sc.leg_override["HL"] = lambda t: {"toe": toe, "hoof_pitch": rad(55), "flex": rad(10)}
    sc.neck = lambda t: V(rad(12) + rad(1.5) * math.sin(TAU * t / T), 0, rad(3))
    sc.head = lambda t: V(rad(10), rad(2), 0)
    sc.ears = ears_trk([(0, (15, 28, 15, 28)), (2.0, (10, 32, 18, 24)), (4.0, (15, 28, 15, 28))], T)
    sc.tail_base = lambda t: V(rad(1), 0, 0)
    sc.jaw = lambda t: rad(1.5)
    return sc


@clip
def Idle_ShiftWeight():
    """weight shift: the hips sway left then right, the right hind picks up and sets down again"""
    T = 3.0
    sc = stand("Idle_ShiftWeight", T, False)
    p = sc.stances["HR"][0][2]
    sc.stances["HR"] = [(-1000.0, 1.05, p), (1.45, 1000.0, p.copy())]
    sc.swing_h["HR"] = 0.06
    sc.flex = {"F": 0.6, "H": 0.5}
    sc.fetlock_flex = {"F": 0.8, "H": 0.7}
    sc.breakover = 0.35
    sc.body_rot = dtrk([(0, (0, 0, 0), "s"), (0.9, (0, -2.5, 1)), (1.6, (0, 2.0, -1)), (2.4, (0, -0.5, 0)), (3.0, (0, 0, 0), "s")])
    sc.body_off = trk3([(0, (0, 0, 0), "s"), (0.9, (-0.03, 0, -0.01)), (1.6, (0.025, 0, -0.005)), (3.0, (0, 0, 0), "s")])
    sc.neck = lambda t: H2.STAND_NECK + V(0, 0, rad(4) * math.sin(TAU * t / T))
    sc.events = {"hoof_HR": [44]}
    return sc


@clip
def Idle_EarFlick():
    T = 2.0
    sc = stand("Idle_EarFlick", T, False)
    sc.ears = ears_trk([(0, (-6, 5, -6, 5), "s"), (0.25, (-6, 5, -6, 5)), (0.35, (40, 55, -6, 5)), (0.55, (-10, 0, -6, 5)),
                        (0.9, (-6, 5, -6, 5)), (1.1, (-6, 5, 35, 60)), (1.25, (-6, 5, -12, -5)), (1.45, (-6, 5, 30, 50)),
                        (1.7, (-6, 5, -6, 5)), (2.0, (-6, 5, -6, 5), "s")])
    sc.head = dtrk([(0, (4, 0, 0), "s"), (0.35, (3, -3, 0)), (1.15, (4, 3, 0)), (2.0, (4, 0, 0), "s")])
    return sc


@clip
def Idle_TailSwish():
    """swatting a fly: two quick tail swishes, a skin twitch at the flank (belly), head turns toward the flank"""
    T = 2.5
    sc = stand("Idle_TailSwish", T, False)
    sc.tail_base = dtrk([(0, (2, 0, 0), "s"), (0.3, (15, 0, 38)), (0.6, (18, 0, -34)), (0.95, (15, 0, 36)), (1.3, (12, 0, -20)),
                         (1.8, (4, 0, 6)), (2.5, (2, 0, 0), "s")])
    sc.belly = dtrk([(0, (0, 0, 0), "s"), (0.35, (0, 3, 0)), (0.45, (0, -3, 0)), (0.55, (0, 2, 0)), (0.7, (0, 0, 0), "s")])
    sc.neck = dtrk([(0, (-4, 0, 0), "s"), (0.6, (-2, 3, 14)), (1.5, (-3, 2, 10)), (2.5, (-4, 0, 0), "s")])
    sc.ears = ears_trk([(0, (-6, 5, -6, 5), "s"), (0.5, (20, 30, 25, 35)), (1.6, (15, 25, 15, 25)), (2.5, (-6, 5, -6, 5), "s")])
    sc.events = {"tail_swish": [9, 28]}
    return sc


@clip
def Idle_HeadToss():
    T = 2.0
    sc = stand("Idle_HeadToss", T, False)
    sc.neck = dtrk([(0, (-4, 0, 0), "s"), (0.25, (4, 0, 0)), (0.55, (-26, 0, 3)), (0.8, (-12, 0, -2)), (1.05, (-18, 0, 1)),
                    (1.5, (-5, 0, 0)), (2.0, (-4, 0, 0), "s")])
    sc.head = dtrk([(0, (4, 0, 0), "s"), (0.25, (12, 0, 0)), (0.55, (-10, 8, 0)), (0.7, (-4, -9, 0)), (0.85, (0, 6, 0)),
                    (1.05, (2, -3, 0)), (1.5, (4, 0, 0)), (2.0, (4, 0, 0), "s")])
    sc.ears = ears_trk([(0, (-6, 5, -6, 5), "s"), (0.5, (25, 20, 25, 20)), (1.2, (-4, 6, -4, 6)), (2.0, (-6, 5, -6, 5), "s")])
    sc.body_off = trk3([(0, (0, 0, 0), "s"), (0.55, (0, 0.02, 0.01)), (1.2, (0, 0, 0), "s")])
    sc.jaw = Trk([(0, 0.0, "s"), (0.55, rad(4)), (0.9, 0.0, "s")])
    return sc


@clip
def Idle_Snort():
    """snort: neck stretches forward and down, quick head shake with the lips flapping (jaw), ears flick"""
    T = 1.8
    sc = stand("Idle_Snort", T, False)
    sh = lambda t: rad(9) * math.sin(TAU * 7.0 * (t - 0.55)) * max(0.0, 1.0 - abs(t - 0.75) / 0.25) if 0.5 < t < 1.0 else 0.0
    nk = dtrk([(0, (-4, 0, 0), "s"), (0.45, (10, 0, 0)), (0.75, (12, 0, 0)), (1.2, (2, 0, 0)), (1.8, (-4, 0, 0), "s")])
    sc.neck = nk
    sc.head = lambda t: V(rad(-4) if 0.3 < t < 1.2 else rad(4), sh(t) * 0.6, sh(t)) * 1.0 + V(rad(8) * (0 if 0.3 < t < 1.2 else 0), 0, 0)
    hd = dtrk([(0, (4, 0, 0), "s"), (0.45, (-6, 0, 0)), (1.2, (-4, 0, 0)), (1.8, (4, 0, 0), "s")])
    sc.head = lambda t: hd(t) + V(0, sh(t) * 0.6, sh(t))
    sc.jaw = lambda t: rad(3) + rad(3) * abs(math.sin(TAU * 7.0 * t)) if 0.55 < t < 0.95 else 0.0
    sc.ears = ears_trk([(0, (-6, 5, -6, 5), "s"), (0.6, (10, 30, 10, 30)), (1.0, (-10, 0, -10, 0)), (1.8, (-6, 5, -6, 5), "s")])
    sc.body_off = trk3([(0, (0, 0, 0), "s"), (0.6, (0, 0, -0.012)), (0.8, (0, 0, 0.005)), (1.2, (0, 0, 0), "s")])
    sc.events = {"snort": [18]}
    return sc


# graze / drink: the forehand reaches down, one fore steps forward, muzzle on the ground
GRAZE_NECK = V(rad(80), 0, rad(4))
GRAZE_HEAD = V(rad(-30), 0, 0)
DOWN_W = [0.60, 0.30, 0.10, 0.0, 0.0]


def head_down_enter(name, down_neck, down_head, step_leg="FL", step=0.30, dur=1.6, reverse=False, water=False):
    sc = stand(name, dur, False)
    p = sc.stances[step_leg][0][2]
    q = p + V(0, -step, 0)
    t0, t1 = (0.25, 0.65) if not reverse else (0.85, 1.25)
    a, b = (p, q) if not reverse else (q, p)
    sc.stances[step_leg] = [(-1000.0, t0, a), (t1, 1000.0, b)]
    sc.swing_h[step_leg] = 0.07
    sc.flex = {"F": 0.6, "H": 0.4}
    sc.fetlock_flex = {"F": 0.8, "H": 0.6}
    sc.breakover = 0.35
    u = (lambda t: G.smoother((t - 0.15) / 1.2)) if not reverse else (lambda t: 1.0 - G.smoother((t - 0.2) / 1.2))
    sc.neck = lambda t: H2.STAND_NECK.lerp(down_neck, u(t))
    sc.head = lambda t: H2.STAND_HEAD.lerp(down_head, u(t))
    sc.neck_w = DOWN_W
    sc.pivot = V(0, 0.6, 1.2)
    sc.body_rot = lambda t: V(rad(12) * u(t), 0, 0)
    sc.body_off = lambda t: V(0, -0.03 * u(t), -0.06 * u(t))
    sc.ears = lambda t: tuple(a_ * (1 - u(t)) + b_ * u(t) for a_, b_ in zip(EAR_REST, (rad(5), rad(18), rad(5), rad(18))))
    sc.support_max = 0.10
    sc.events = {"hoof_" + step_leg: [int(round(t1 * G.FPS))]}
    return sc


@clip
def Graze_Enter():
    return head_down_enter("Graze_Enter", GRAZE_NECK, GRAZE_HEAD)


@clip
def Graze_Exit():
    return head_down_enter("Graze_Exit", GRAZE_NECK, GRAZE_HEAD, reverse=True)


def head_down_loop(name, down_neck, down_head, T, chew_hz, sweep_deg, step_leg="FL", step=0.30, nibble=True):
    sc = stand(name, T, True)
    p = sc.stances[step_leg][0][2] + V(0, -step, 0)
    sc.stances[step_leg] = [(-1000.0, 1000.0, p)]
    sc.neck_w = DOWN_W
    sc.pivot = V(0, 0.6, 1.2)
    sc.body_rot = lambda t: V(rad(12), 0, 0)
    sc.body_off = lambda t: V(0, -0.03, -0.06)
    sweep = lambda t: rad(sweep_deg) * math.sin(TAU * t / T)
    nib = (lambda t: rad(2.5) * max(0.0, math.sin(TAU * 2 * t / T)) ** 4) if nibble else (lambda t: 0.0)
    sc.neck = lambda t: down_neck + V(nib(t), 0, sweep(t))
    sc.head = lambda t: down_head + V(0, sweep(t) * 0.4, sweep(t) * 0.3)
    sc.jaw = lambda t: rad(3.5) * (0.5 - 0.5 * math.cos(TAU * chew_hz * t))
    sc.ears = ears_trk([(0, (5, 18, 5, 18)), (1.2, (-10, 5, 10, 25)), (2.6, (8, 22, -8, 8)), (T, (5, 18, 5, 18))], T)
    sc.tail_base = lambda t: V(rad(2), 0, rad(5) * math.sin(TAU * t / T * 2))
    b, sp, bo = breath(T, 0.7)
    sc.belly = b
    return sc


@clip
def Graze():
    sc = head_down_loop("Graze", GRAZE_NECK, GRAZE_HEAD, 4.0, 1.5, 7)
    sc.events = {"chew": [int(round(i / 1.5 * G.FPS)) for i in range(6)]}
    return sc


DRINK_NECK = V(rad(78), 0, 0)
DRINK_HEAD = V(rad(-22), 0, 0)


@clip
def Drink_Enter():
    return head_down_enter("Drink_Enter", DRINK_NECK, DRINK_HEAD, step=0.24, water=True)


@clip
def Drink_Exit():
    return head_down_enter("Drink_Exit", DRINK_NECK, DRINK_HEAD, step=0.24, reverse=True, water=True)


@clip
def Drink():
    sc = head_down_loop("Drink", DRINK_NECK, DRINK_HEAD, 3.0, 1.0, 1.5, step=0.24, nibble=False)
    sc.jaw = lambda t: rad(1.5) * (0.5 - 0.5 * math.cos(TAU * 2.0 * t / 3.0 * 3))
    sc.events = {"swallow": [15, 45, 75]}
    return sc


# ------------------------------------------------------------------ actions
@clip
def Rear():
    """rearing: hindquarters sink, forehand rises to ~45 degrees around the hind feet, fore legs tucked and pawing, then down"""
    T = 2.8
    sc = stand("Rear", T, False)
    sc.pivot = V(0, 0.55, 1.05)
    up = Trk([(0, 0.0, "s"), (0.35, 0.08), (0.95, 1.0), (1.55, 1.0), (2.25, 0.05), (2.5, 0.0, "s")])
    sc.body_rot = lambda t: V(rad(-48) * up(t), 0, 0)
    sc.body_off = lambda t: V(0, 0.10 * up(t), -0.12 * up(t))
    sc.spine = lambda t: V(rad(-6) * up(t), 0, 0)
    sc.neck = lambda t: V(rad(-4) + rad(24) * up(t), 0, rad(5) * math.sin(TAU * t * 0.7) * up(t))
    sc.head = lambda t: V(rad(4) + rad(10) * up(t), rad(4) * math.sin(TAU * 1.4 * t) * up(t), 0)
    sc.ears = lambda t: tuple(a * (1 - up(t)) + b * up(t) for a, b in zip(EAR_REST, (rad(30), rad(25), rad(30), rad(25))))
    sc.tail_base = lambda t: V(rad(2) - rad(10) * up(t), 0, 0)
    sc.jaw = lambda t: rad(6) * up(t)
    lift = Trk([(0, 0.0, "s"), (0.35, 0.0), (0.55, 1.0), (2.05, 1.0), (2.3, 0.0), (2.8, 0.0, "s")])
    for leg, ph in (("FL", 0.0), ("FR", 0.5)):
        def ov(t, ph=ph):
            w = lift(t)
            if w <= 0:
                return None
            paw = math.sin(TAU * 1.6 * (t - 0.6) + ph * TAU)
            return {"rel": V(0, -0.20 - 0.12 * paw, -0.55 + 0.10 * paw), "flex": rad(95 + 20 * paw), "fflex": rad(60), "cflex": rad(20), "w": w}
        sc.leg_override[leg] = ov
    for leg in ("FL", "FR"):
        p = sc.stances[leg][0][2]
        sc.stances[leg] = [(-1000.0, 0.45, p), (2.25, 1000.0, p)]
    sc.load = {"F": 0.2, "H": 0.3}
    sc.support_max = 0.2
    sc.events = {"neigh": [30], "hoof_FL": [68], "hoof_FR": [68]}
    sc.meta = {"gait": "action"}
    return sc


@clip
def Buck():
    T = 1.9
    sc = stand("Buck", T, False)
    sc.pivot = V(0, -0.55, 1.05)
    up = Trk([(0, 0.0, "s"), (0.25, -0.15), (0.6, 1.0), (0.85, 0.9), (1.25, 0.1), (1.5, 0.0, "s")])
    sc.body_rot = lambda t: V(rad(24) * up(t), 0, 0)
    sc.body_off = lambda t: V(0, -0.05 * up(t), -0.05 * max(0, -up(t)) * 4)
    sc.spine = lambda t: V(rad(-6) * up(t), 0, 0)
    sc.neck = lambda t: V(rad(-4) + rad(34) * max(0.0, up(t)), 0, 0)
    sc.head = lambda t: V(rad(4) + rad(15) * max(0.0, up(t)), 0, 0)
    sc.ears = lambda t: tuple(a * (1 - abs(up(t))) + b * abs(up(t)) for a, b in zip(EAR_REST, (rad(60), rad(10), rad(60), rad(10))))
    sc.tail_base = lambda t: V(rad(2) + rad(35) * max(0.0, up(t)), 0, 0)
    kick = Trk([(0, 0.0, "s"), (0.32, 0.0), (0.5, 0.6), (0.68, 1.0), (0.9, 0.7), (1.2, 0.0), (1.9, 0.0, "s")])
    for leg in ("HL", "HR"):
        def ov(t, leg=leg):
            w = kick(t)
            if w <= 0:
                return None
            k = w * (1.0 if leg == "HL" else 0.9)
            return {"rel": V(0, 0.25 + 0.55 * k, -0.95 + 0.45 * k), "flex": rad(10 + 30 * (1 - k)), "fflex": rad(25), "cflex": rad(10),
                    "w": min(1.0, w * 2.5)}
        sc.leg_override[leg] = ov
        p = sc.stances[leg][0][2]
        sc.stances[leg] = [(-1000.0, 0.40, p), (1.22, 1000.0, p)]
    sc.support_max = 0.2
    sc.events = {"kick": [20], "hoof_HL": [37], "hoof_HR": [37]}
    sc.meta = {"gait": "action"}
    return sc


def spook(name, side):
    """shy away from a threat on `side` (+1 = left): crouch, leap sideways and away with a quick scramble of steps"""
    T = 1.5
    sc = G.Script(name, T, False)
    away = -side
    lat = Trk([(0, 0.0, "s"), (0.12, 0.0), (0.55, 0.9), (0.9, 1.15), (1.2, 1.2, "s")])
    yw = Trk([(0, 0.0, "s"), (0.12, 0.0), (0.6, rad(28)), (1.0, rad(32), "s")])
    sc.root_yaw = lambda t: away * yw(t)
    sc.root_pos = lambda t: V(away * lat(t), -0.25 * lat(t), 0)
    rate = lambda t: 2.6 if t < 0.95 else 1.2
    phase = H2.integrate(rate, -0.5, T + 1)
    H2.stepping(sc, HC.GAITS["trot"]["pattern"], 0.45, lambda t: phase(t) + 0.55, rate, 0.9, T, H2.xf_of(sc.root_pos, sc.root_yaw),
                HC.ENG.neutral, square=True, step_time=0.22)
    for leg in G.LEGS:
        sc.swing_h[leg] = 0.12
    sc.flex = {"F": 1.1, "H": 0.7}
    sc.fetlock_flex = {"F": 1.1, "H": 0.9}
    sc.load = {"F": 0.25, "H": 0.25}
    crouch = Trk([(0, 0.0, "s"), (0.12, 1.0), (0.3, -0.3), (0.55, 0.2), (1.0, 0.0, "s")])
    sc.body_off = lambda t: V(0, 0, -0.07 * crouch(t))
    sc.body_rot = lambda t: V(rad(-4) * max(0, crouch(t)), away * rad(-5) * lat(t) * (1 - G.smooth((t - 0.6) / 0.6)), 0)
    look = Trk([(0, 0.0, "s"), (0.1, 1.0), (1.0, 0.8), (1.5, 0.4, "s")])
    sc.neck = lambda t: V(rad(-4) - rad(26) * look(t), 0, side * rad(14) * look(t))
    sc.head = lambda t: V(rad(4) - rad(6) * look(t), 0, side * rad(10) * look(t))
    sc.ears = lambda t: (rad(-15) * look(t), side * rad(-10) * look(t) + rad(5), rad(-15) * look(t), side * rad(10) * look(t) + rad(5))
    sc.tail_base = lambda t: V(rad(2) + rad(25) * look(t), 0, 0)
    sc.support_max = 0.12
    H2.add_hoof_events(sc)
    sc.events["startle"] = [3]
    sc.meta = {"gait": "action", "threat_side": "L" if side > 0 else "R"}
    return sc


@clip
def Spook_L():
    return spook("Spook_L", 1)


@clip
def Spook_R():
    return spook("Spook_R", -1)


def hit(name, side):
    """hit from `side` (+1 = left): flinch away, head jerks up and away, ears pinned, a short stagger step"""
    T = 0.8
    sc = stand(name, T, False)
    k = Trk([(0, 0.0, "s"), (0.07, 1.0), (0.25, 0.6), (0.8, 0.0, "s")])
    sc.body_off = lambda t: V(-side * 0.07 * k(t), 0, -0.03 * k(t))
    sc.body_rot = lambda t: V(rad(-3) * k(t), -side * rad(5) * k(t), -side * rad(4) * k(t))
    sc.spine = lambda t: V(0, 0, side * rad(6) * k(t))
    sc.neck = lambda t: V(rad(-4) - rad(16) * k(t), 0, -side * rad(12) * k(t))
    sc.head = lambda t: V(rad(4), side * rad(8) * k(t), 0)
    sc.ears = lambda t: tuple(a * (1 - k(t)) + b * k(t) for a, b in zip(EAR_REST, (rad(55), rad(10), rad(55), rad(10))))
    sc.tail_base = lambda t: V(rad(2) + rad(15) * k(t), 0, -side * rad(15) * k(t))
    leg = "FR" if side > 0 else "FL"
    p = sc.stances[leg][0][2]
    sc.stances[leg] = [(-1000.0, 0.12, p), (0.40, 1000.0, p + V(-side * 0.10, 0, 0))]
    sc.swing_h[leg] = 0.06
    sc.flex = {"F": 0.7, "H": 0.4}
    sc.fetlock_flex = {"F": 0.8, "H": 0.6}
    sc.events = {"hit": [0], "hoof_" + leg: [12]}
    sc.meta = {"gait": "action", "hit_side": "L" if side > 0 else "R"}
    return sc


@clip
def Hit_L():
    return hit("Hit_L", 1)


@clip
def Hit_R():
    return hit("Hit_R", -1)


@clip
def Death():
    """collapse: knees buckle (fore first), hindquarters fold, the horse rolls onto its right side and lies still"""
    T = 3.4
    sc = stand("Death", T, False)
    kneel = Trk([(0, 0.0, "s"), (0.25, 0.0), (0.9, 1.0), (3.4, 1.0, "s")])
    sit = Trk([(0, 0.0, "s"), (0.7, 0.0), (1.35, 1.0), (3.4, 1.0, "s")])
    roll = Trk([(0, 0.0, "s"), (1.25, 0.0), (2.05, 1.0), (2.2, 0.96), (2.35, 1.0, "s")])
    head = Trk([(0, 0.0, "s"), (0.3, 0.3), (1.4, 0.4), (2.2, 0.8), (2.9, 1.0, "s")])
    sc.body_off = lambda t: V(-0.30 * roll(t), -0.05 * kneel(t), -0.42 * kneel(t) * (1 - sit(t)) - 0.62 * sit(t) - 0.10 * roll(t))
    sc.body_rot = lambda t: V(rad(16) * kneel(t) * (1 - sit(t)) + rad(3) * sit(t), -rad(78) * roll(t), 0)
    sc.pivot = V(0, 0.0, 0.9)
    sc.neck = lambda t: V(rad(-4) + rad(30) * head(t), rad(20) * roll(t), rad(-15) * roll(t))
    sc.head = lambda t: V(rad(4) + rad(10) * head(t), 0, 0)
    sc.ears = lambda t: tuple(a * (1 - head(t)) + b * head(t) for a, b in zip(EAR_REST, (rad(40), rad(35), rad(40), rad(35))))
    sc.tail_base = lambda t: V(rad(2), 0, rad(-20) * roll(t))
    sc.jaw = lambda t: rad(8) * head(t)
    sc.support = False
    for leg in G.LEGS:
        fore = leg[0] == "F"
        w0 = kneel if fore else sit

        def ov(t, fore=fore, w0=w0, leg=leg):
            w = w0(t)
            if w <= 0:
                return None
            r = roll(t)
            folded = V(0, 0.18 if fore else -0.35, -0.55 if fore else -0.45)
            lying = V(0, -0.35 if fore else 0.10, -0.80 if fore else -0.78)
            rel = folded.lerp(lying, r)
            return {"rel": rel, "flex": rad(150 if fore else 70) * (1 - r) + rad(15) * r, "fflex": rad(60) * (1 - r) + rad(10) * r,
                    "cflex": rad(20), "w": min(1.0, w * 1.6)}
        sc.leg_override[leg] = ov
    sc.events = {"knees": [27], "body_ground": [60], "roll": [62]}
    sc.meta = {"gait": "action"}
    return sc


@clip
def Jump_Full():
    """canter jump over a ~1 m fence: last fore strides, hind push-off together, arc, fore landing, canter away.
    Root motion carries the arc (root Z) as well as the forward travel. Split: Jump_Takeoff / Jump_Air / Jump_Land."""
    T = 1.9
    v = 5.4
    sc = G.Script("Jump_Full", T, False)
    t_off, t_land = 0.46, 1.02
    H = 1.05
    def zarc(t):
        if t <= t_off or t >= t_land:
            return 0.0
        u = (t - t_off) / (t_land - t_off)
        return H * 4 * u * (1 - u) * (1.0 - 0.15 * u)
    sc.root_pos = lambda t: V(0, -v * t, zarc(t))
    sc.root_yaw = lambda t: 0.0
    xf = H2.xf_of(lambda t: V(0, -v * t, 0), sc.root_yaw)
    nt = HC.ENG.neutral

    def plant(leg, t):
        p = xf(t) @ nt[leg]
        p.z = 0.0
        return p
    # approach: the canter stride before (left lead), then take-off and landing footfalls
    sc.stances["HR"] = [(-0.40, -0.18, plant("HR", -0.29)), (0.24, 0.44, plant("HR", 0.33))]
    sc.stances["HL"] = [(-0.28, -0.06, plant("HL", -0.17)), (0.27, 0.46, plant("HL", 0.36))]
    sc.stances["FR"] = [(-0.25, -0.05, plant("FR", -0.15)), (0.02, 0.20, plant("FR", 0.11))]
    sc.stances["FL"] = [(-0.13, 0.08, plant("FL", -0.02)), (0.10, 0.30, plant("FL", 0.18))]
    sc.stances["FL"] = [(0.10, 0.30, plant("FL", 0.18))]
    sc.stances["FL"].insert(0, (-0.55, -0.35, plant("FL", -0.45)))
    # landing: leading fore first, hinds under, then canter strides away
    sc.stances["FL"].append((t_land, t_land + 0.17, plant("FL", t_land + 0.05)))
    sc.stances["FR"].append((t_land + 0.07, t_land + 0.25, plant("FR", t_land + 0.14)))
    sc.stances["HR"].append((t_land + 0.24, t_land + 0.44, plant("HR", t_land + 0.32)))
    sc.stances["HL"].append((t_land + 0.30, t_land + 0.50, plant("HL", t_land + 0.38)))
    c0 = t_land + 0.24
    Tc = 18 / 30.0
    for leg, ph, d in (("HR", 0.0, 0.36), ("HL", 0.20, 0.36), ("FR", 0.24, 0.33), ("FL", 0.44, 0.34)):
        for k in (1, 2):
            tl = c0 + (ph + k) * Tc - 0.35 * Tc
            if tl > sc.stances[leg][-1][1] + 0.12:
                sc.stances[leg].append((tl, tl + d * Tc, plant(leg, tl + d * Tc * 0.5)))
    for leg in G.LEGS:
        sc.stances[leg].sort(key=lambda s: s[0])
        sc.swing_h[leg] = 0.22
    sc.flex = {"F": 1.6, "H": 0.9}
    sc.fetlock_flex = {"F": 1.5, "H": 1.2}
    sc.load = {"F": 0.40, "H": 0.35}
    sc.breakover = 0.7
    # flight: fore legs folded tight, hind legs trail then tuck
    air = lambda t: G.smooth((t - (t_off - 0.10)) / 0.14) * (1 - G.smooth((t - (t_land - 0.16)) / 0.14))
    fore_air = lambda t: G.smooth((t - 0.24) / 0.12) * (1 - G.smooth((t - (t_land - 0.22)) / 0.18))
    for leg in ("FL", "FR"):
        sc.leg_override[leg] = (lambda t, leg=leg: None if fore_air(t) <= 0 else
                                {"rel": V(0, -0.18, -0.36), "flex": rad(135), "fflex": rad(75), "cflex": rad(25), "w": fore_air(t)})
    trail = lambda t: 1.0 - G.smooth((t - 0.62) / 0.22)
    for leg in ("HL", "HR"):
        sc.leg_override[leg] = (lambda t, leg=leg: None if air(t) <= 0 else
                                {"rel": V(0, 0.55, -0.72).lerp(V(0, -0.12, -0.55), 1 - trail(t)),
                                 "flex": rad(10) * trail(t) + rad(70) * (1 - trail(t)), "fflex": rad(20) + rad(50) * (1 - trail(t)),
                                 "cflex": rad(15), "w": air(t)})
    pitch = Trk([(0, 0.0), (0.30, rad(4)), (0.44, rad(-18)), (0.62, rad(-6)), (0.78, rad(8)), (0.98, rad(16)), (1.15, rad(4)),
                 (1.35, rad(-3)), (1.6, 0.0), (1.9, 0.0, "s")])
    sc.pivot = V(0, 0.0, 1.1)
    sc.body_rot = lambda t: V(pitch(t), 0, 0)
    sq = Trk([(0, 0.0), (0.38, -0.08), (0.46, 0.0), (1.02, 0.0), (1.12, -0.10), (1.35, -0.02), (1.6, -0.04), (1.9, -0.04)])
    sc.body_off = lambda t: V(0, 0, sq(t))
    sc.spine = lambda t: V(rad(6) * air(t), 0, 0)
    nk = Trk([(0, rad(0)), (0.3, rad(-10)), (0.5, rad(18)), (0.75, rad(24)), (1.0, rad(-4)), (1.2, rad(-8)), (1.5, rad(2)), (1.9, rad(0))])
    sc.neck = lambda t: V(nk(t), 0, 0)
    sc.head = lambda t: V(rad(6), 0, 0)
    sc.ears = lambda t: (rad(-15), rad(5), rad(-15), rad(5))
    sc.tail_base = lambda t: V(rad(10) + rad(20) * air(t), 0, 0)
    sc.tail_lift = lambda t: rad(15)
    sc.support_max = 0.12
    H2.add_hoof_events(sc)
    sc.events["takeoff"] = [int(t_off * G.FPS)]
    sc.events["land"] = [int(t_land * G.FPS)]
    fo, fl = int(round(t_off * G.FPS)), int(round(t_land * G.FPS))
    sc.meta = {"gait": "jump", "height_m": H, "splits": [["Jump_Takeoff", 0, fo], ["Jump_Air", fo, fl], ["Jump_Land", fl, int(T * G.FPS)]]}
    return sc


@clip
def Swim():
    """deep water: root = water surface. Body low (only the back of the neck and the head out), diagonal paddling, tail floating."""
    T = 1.2
    v = 1.1
    sc = G.Script("Swim", T, True)
    sc.root_pos = lambda t: V(0, -v * t, 0)
    sc.support = False
    sc.pivot = V(0, 0, 1.2)
    sc.body_off = lambda t: V(0, 0, -1.10 + 0.025 * math.sin(2 * TAU * t / T))
    sc.body_rot = lambda t: V(rad(-12) + rad(1.5) * math.sin(2 * TAU * t / T + 0.5), rad(2) * math.sin(TAU * t / T), 0)
    sc.neck = lambda t: V(rad(-22) + rad(3) * math.sin(2 * TAU * t / T + 1.2), 0, 0)
    sc.head = lambda t: V(rad(22), 0, 0)
    sc.ears = lambda t: (rad(-10), rad(8), rad(-10), rad(8))
    sc.tail_base = lambda t: V(rad(70), 0, rad(8) * math.sin(TAU * t / T))
    for leg, ph in (("FL", 0.5), ("FR", 0.0), ("HL", 0.0), ("HR", 0.5)):
        fore = leg[0] == "F"

        def ov(t, ph=ph, fore=fore):
            a = TAU * (t / T + ph)
            if fore:
                return {"rel": V(0, -0.20 - 0.22 * math.cos(a), -0.52 + 0.14 * math.sin(a)), "flex": rad(70) + rad(55) * (0.5 + 0.5 * math.sin(a)),
                        "fflex": rad(50), "cflex": rad(15)}
            return {"rel": V(0, 0.05 - 0.25 * math.cos(a), -0.72 + 0.14 * math.sin(a)), "flex": rad(20) + rad(35) * (0.5 + 0.5 * math.sin(a)),
                    "fflex": rad(40), "cflex": rad(15)}
        sc.leg_override[leg] = ov
    sc.events = {"stroke": [0, 18]}
    sc.meta = {"gait": "swim", "root_is_water_surface": True, "stride_m": round(v * T, 3)}
    return sc
