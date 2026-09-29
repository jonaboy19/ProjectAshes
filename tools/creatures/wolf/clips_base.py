"""Clip definitions (frame functions) for the wolf. Every clip is a function E -> Clip. Units: metres, seconds, radians.
World frame helpers use (forward, left)."""
import math
from mathutils import Vector
from gait import *

D = math.pi / 180.0


class Clip:
    def __init__(self, name, T, fn, loop=False, world=None, events=None, notes=""):
        self.name, self.T, self.fn, self.loop, self.world = name, T, fn, loop, world
        self.events = events or {}
        self.notes = notes


def home_fl(E):
    """rest paw positions in body (forward, left) metres"""
    return {k: (-E.cen[k][1] * E.s, E.cen[k][0] * E.s) for k in LEGS}


def gait_clip(E, name, T, beta, phases, v_f, v_l, omega, body_fn, lift=0.10, home_shift=None, loop=True, events=None,
              notes="", lifts=None):
    """periodic planted-foot gait: feet are planted in the WORLD (screw motion of the body), body_fn(t, world) -> frame dict"""
    hm = home_fl(E)
    if home_shift:
        for k, (a, b) in home_shift.items():
            hm[k] = (hm[k][0] + a, hm[k][1] + b)
    world = World(v_f, v_l, omega, -4 * T, 3 * T)
    steps = {k: periodic_steps(world, T, beta, phases[k], hm[k], t_end=T) for k in LEGS}

    def fn(t):
        Fr = body_fn(t, world)
        paws = {}
        pl = {}
        for k in LEGS:
            f, l, h, ang = foot_path(steps[k], t, (lifts or {}).get(k, lift))
            bF, bL = world.to_body(t, f, l)
            paws[k] = (E.to_arm(bF, bL, z=E.pz[k] + E.u(h)), ang)
            pl[k] = h < 0.004
        Fr['paw'] = paws
        Fr['planted'] = pl
        return Fr
    return Clip(name, T, fn, loop=loop, world=world, events=events, notes=notes)


def wave(t, T, ph=0.0, n=1):
    return math.sin(2 * math.pi * n * t / T + ph)


def stalk(E):
    T = 1.2
    beta = 0.72
    ph = {"BL": 0.0, "FL": 0.25, "BR": 0.5, "FR": 0.75}
    v = 0.9

    def body(t, w):
        Fr = {}
        Fr['dz'] = -0.13 + 0.012 * wave(t, T, 0.3, 2)
        Fr['bp'] = 0.07 + 0.01 * wave(t, T, 1.0, 2)
        Fr['br'] = 0.02 * wave(t, T, 0.0)
        Fr['spine'] = {"Back": (0.045 * wave(t, T, math.pi), 0, 0), "Torso": (0.03 * wave(t, T, math.pi), 0, 0),
                       "Torso2": (0.03 * wave(t, T, 0), 0, 0), "Torso3": (0.05 * wave(t, T, 0), 0, 0)}
        Fr['neck'] = (0.05 * wave(t, T, 0.5), 0.30)
        Fr['head'] = (-0.04 * wave(t, T, 0.5), 0.05, 0)
        Fr['tail'] = [(0.10 * wave(t, T, -i * 0.6 + 1.0), 0.10 + 0.02 * i) for i in range(8)]
        # blades follow the front paws
        bl = {}
        for k in ("FL", "FR"):
            bl[k] = 0.0
        Fr['blade'] = bl
        return Fr
    return gait_clip(E, "stalk", T, beta, ph, v, 0.0, 0.0, body, lift=0.11)





# ======================================================================================================== helpers
def mirror_leg(k):
    return k[0] + ("R" if k[1] == "L" else "L")


def bell(t, a, b):
    """0 -> 1 -> 0 smooth bump over [a, b]"""
    if t <= a or t >= b:
        return 0.0
    return math.sin(math.pi * (t - a) / (b - a)) ** 2


def timed_steps(E, world, home, plan, t_end, lead=None):
    """plan: {leg: [(t_lift, t_land), ...]} explicit swings (leg planted at its home world spot before the first lift, and at
    body-frame home again at t_end after the last landing). Each landing spot is placed so the foot passes its body-frame home
    at mid-stance (plus an optional forward lead in metres)."""
    steps = {}
    for k in LEGS:
        sw = plan.get(k, [])
        Q0 = world.from_body(0.0, home[k][0], home[k][1])
        st = [Step(-10.0, sw[0][0] if sw else 1e9, Q0)]
        for j, (tl, tland) in enumerate(sw):
            nxt_lift = sw[j + 1][0] if j + 1 < len(sw) else None
            if nxt_lift is None:
                tm = t_end
                Q = world.from_body(t_end, home[k][0], home[k][1])
            else:
                tm = 0.5 * (tland + nxt_lift)
                Q = world.from_body(tm, home[k][0] + (lead or 0.0), home[k][1])
            st.append(Step(tland, nxt_lift if nxt_lift is not None else 1e9, Q))
        steps[k] = st
    return steps


def frame_from_steps(E, world, steps, t, lift):
    paws = {}
    pl = {}
    for k in LEGS:
        f, l, h, ang = foot_path(steps[k], t, lift)
        bF, bL = world.to_body(t, f, l)
        paws[k] = (E.to_arm(bF, bL, z=E.u(h)), ang)
        pl[k] = h < 0.004
    return paws, pl


# ========================================================================================================= turn in place
def turn_in_place(E, name, deg, T, n_steps, lift=0.075, notes=""):
    d = math.radians(deg)
    sg = 1.0 if deg > 0 else -1.0
    ap = abs(d)
    psi_t = Track([(0, 0), (0.12 * T, 0.04 * d), (0.5 * T, 0.5 * d), (0.88 * T, 0.96 * d), (T, d)])
    head_t = Track([(0, 0), (0.06 * T, 0.10 * d), (0.32 * T, 0.78 * d), (0.58 * T, 1.02 * d), (0.78 * T, d), (T, d)])
    eps = 1 / 300.0
    om = lambda t: (psi_t(min(t + eps, T)) - psi_t(max(t - eps, 0.0))) / (min(t + eps, T) - max(t - eps, 0.0)) if 0 < t < T else 0.0
    world = World(0.0, 0.0, om, -1.0, T + 1.0)
    hm = home_fl(E)
    # pair A steps first: left turn -> FL & BR (front-left leads out); right turn -> FR & BL
    pairA = ("FL", "BR") if sg > 0 else ("FR", "BL")
    pairB = tuple(k for k in LEGS if k not in pairA)
    slots = 2 * n_steps
    t0 = 0.03
    ds = (T - 0.06 - 0.16) / slots
    sw_len = 0.78 * ds + 0.06
    plan = {k: [] for k in LEGS}
    for j in range(slots):
        for k in (pairA if j % 2 == 0 else pairB):
            a = t0 + j * ds
            plan[k].append((a, min(a + sw_len, T - 0.05)))
    steps = timed_steps(E, world, hm, plan, T, lead=0.0)

    def fn(t):
        Fr = {}
        pt, ph = psi_t(t), head_t(t)
        lead = ph - pt
        b = bell(t, 0.0, T)
        Fr['dz'] = -0.05 * b
        Fr['bp'] = 0.04 * b
        Fr['br'] = sg * 0.07 * b
        Fr['spine'] = {"Back": (-0.10 * lead, 0, 0), "Torso2": (0.08 * lead, 0, 0), "Torso3": (0.12 * lead, 0, 0)}
        Fr['neck'] = (0.72 * lead, 0.10 * b)
        Fr['tail'] = [(-sg * 0.4 * bell(t, 0.05, T) * (0.4 + 0.1 * i), 0.1 * b) for i in range(8)]
        paws, pl = frame_from_steps(E, world, steps, t, lift)
        Fr['paw'] = paws
        Fr['planted'] = pl
        return Fr
    return Clip(name, T, fn, loop=False, world=world, notes=notes,
                events={"yaw_total_deg": deg, "swing_pairs": "first pair: %s" % (pairA,)})


def turn_l90(E): return turn_in_place(E, "turn_l90", 90, 29 / 30.0, 2)
def turn_r90(E): return turn_in_place(E, "turn_r90", -90, 29 / 30.0, 2)
def turn_l180(E): return turn_in_place(E, "turn_l180", 180, 1.4, 3)
def turn_r180(E): return turn_in_place(E, "turn_r180", -180, 1.4, 3)


