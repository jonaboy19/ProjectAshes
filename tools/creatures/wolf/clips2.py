"""Second half of the clip definitions (circle, limp, flinch, howl, lunge). Imported by clips.py."""
import math
from gait import *
from clips_base import *


# ===================================================================================== circle (strafe orbit)
def circle(E, name, sg):
    """sg=+1: sidestep to the wolf's LEFT while its heading turns right (keeps facing the centre of a 5 m orbit)"""
    T = 0.6
    v = 1.4
    R = 5.0
    ph = {"FL": 0.0, "BR": 0.0, "FR": 0.5, "BL": 0.5}

    def body(t, w):
        Fr = {}
        Fr['dz'] = -0.07 + 0.012 * wave(t, T, 0.4, 2)
        Fr['bp'] = 0.03
        Fr['byaw'] = sg * 0.30
        Fr['br'] = -sg * 0.04 + 0.02 * wave(t, T, 0)
        Fr['spine'] = {"Back": (0.05 * wave(t, T, 0.5) - sg * 0.06, 0, 0), "Torso": (-sg * 0.05, 0, 0),
                       "Torso2": (0.03 * wave(t, T, 2.0), 0, 0), "Torso3": (-sg * 0.08, 0, 0)}
        Fr['neck'] = (-sg * 0.34 + 0.03 * wave(t, T, 1.0), 0.28)            # head stays locked on the centre
        Fr['tail'] = [(-sg * (0.20 + 0.03 * i) + 0.08 * wave(t, T, -0.5 * i), 0.05) for i in range(8)]
        return Fr
    shift = {"FL": (0, 0.04), "BL": (0, 0.04), "FR": (0, -0.04), "BR": (0, -0.04)}
    return gait_clip(E, name, T, 0.6, ph, 0.0, sg * v, -sg * v / R, body, lift=0.09, home_shift=shift,
                     notes="ground speed %.2f m/s sideways; yaw rate %.3f rad/s (nominal 5 m orbit)" % (v, v / R))


def circle_l(E): return circle(E, "circle_l", 1.0)
def circle_r(E): return circle(E, "circle_r", -1.0)


# ===================================================================================== limp (wounded foreleg)
def limp(E):
    T = 1.0
    v = 1.1
    ph = {"BL": 0.0, "FL": 0.30, "BR": 0.5, "FR": 0.75}
    hm = home_fl(E)
    betas = {"BL": 0.68, "BR": 0.68, "FR": 0.66, "FL": 0.26}
    world = World(v, 0.0, 0.0, -4 * T, 3 * T)
    steps = {}
    for k in LEGS:
        hk = hm[k] if k != "FL" else (hm[k][0] + 0.07, hm[k][1])
        steps[k] = periodic_steps(world, T, betas[k], ph[k], hk, t_end=T)
    lifts = {"FL": 0.12, "FR": 0.09, "BL": 0.09, "BR": 0.09}

    def fn(t):
        Fr = {}
        fl_st = bell(t % T, ph["FL"] * T, (ph["FL"] + betas["FL"]) * T)
        Fr['dz'] = -0.09 - 0.025 * (1 - math.cos(2 * math.pi * (t / T - 0.78))) / 2 + 0.02 * fl_st
        Fr['bp'] = 0.10
        Fr["br"] = -0.09 * fl_st
        Fr['spine'] = {"Back": (0.04 * wave(t, T, 0.5), 0, 0), "Torso2": (0.03 * wave(t, T, 3.5), 0, 0)}
        Fr['neck'] = (0.05 * wave(t, T, 0), 0.44 - 0.28 * math.cos(2 * math.pi * (t / T - 0.30)))
        Fr['head'] = (0, 0.08, 0)
        Fr['tail'] = [(0.06 * wave(t, T, -0.4 * i), 0.22 + 0.02 * i) for i in range(8)]
        paws = {}
        pl = {}
        for k in LEGS:
            f, l, h, ang = foot_path(steps[k], t, lifts[k])
            bF, bL = world.to_body(t, f, l)
            paws[k] = (E.to_arm(bF, bL, z=E.u(h)), ang)
            pl[k] = h < 0.004
        Fr['paw'] = paws
        Fr['planted'] = pl
        return Fr
    return Clip("limp", T, fn, loop=True, world=world, notes="wounded near foreleg (FL) favoured; ground speed %.2f m/s" % v)


# ===================================================================================== flinch
def flinch(E):
    T = 0.40
    e = Track([(0, 0), (0.07, 1.0), (0.14, 0.7), (0.26, 0.2), (0.40, 0)], ease=True)
    hm = home_fl(E)
    world = World(0.0, 0.0, 0.0, -1.0, 1.0)
    steps = timed_steps(E, world, hm, {}, T)

    def fn(t):
        x = e(t)
        Fr = {}
        Fr['dz'] = -0.10 * x
        Fr['dx_f'] = -0.12 * x
        Fr['bp'] = -0.10 * x
        Fr['byaw'] = -0.20 * x
        Fr['br'] = -0.12 * x
        Fr['spine'] = {"Torso2": (-0.22 * x, 0, 0), "Torso3": (-0.28 * x, 0.08 * x, 0), "Back": (0.14 * x, 0, 0)}
        Fr['neck'] = (-0.85 * x, -0.40 * x)
        Fr['head'] = (-0.25 * x, -0.20 * x, 0)
        Fr['tail'] = [(0.30 * x, 0.40 * x) for i in range(8)]
        Fr['paw'], Fr['planted'] = frame_from_steps(E, world, steps, t, 0.0)
        return Fr
    return Clip("flinch", T, fn, loop=False, world=world, events={"peak": 0.07}, notes="quick recoil, feet planted")


# ===================================================================================== howl
def howl(E):
    T = 2.9
    rise = Track([(0, 0), (0.70, 1.0), (2.2, 1.0), (2.9, 0)], ease=True)
    hm = home_fl(E)
    world = World(0.0, 0.0, 0.0, -1.0, 4.0)
    steps = timed_steps(E, world, hm, {}, T)

    def fn(t):
        r = rise(t)
        hold = sstep((t - 0.55) / 0.3) * (1 - sstep((t - 2.2) / 0.3))
        b = (0.5 - 0.5 * math.cos(2 * math.pi * (t - 0.7) / 1.5)) * hold        # breath: one period = 1.5 s = the hold loop
        Fr = {}
        Fr['dz'] = -0.03 * r + 0.010 * b
        Fr['bp'] = 0.0
        Fr['dx_f'] = 0.0
        Fr['spine'] = {"Torso2": (0, -0.10 * r - 0.035 * b, 0), "Torso3": (0, -0.16 * r - 0.05 * b, 0), "Back": (0, 0.05 * r, 0)}
        Fr['neck'] = (0.02 * wave(t, T, 0) * hold, -1.15 * r - 0.05 * b)
        Fr['head'] = (0, -0.32 * r, 0)
        Fr['tail'] = [(0.04 * wave(t, 1.5, -0.3 * i), 0.18 * r + 0.04 * i * r) for i in range(8)]
        Fr['paw'], Fr['planted'] = frame_from_steps(E, world, steps, t, 0.0)
        return Fr
    return Clip("howl", T, fn, loop=False, world=world,
                events={"audio": 0.55, "hold_loop_start": 0.70, "hold_loop_end": 2.20},
                notes="rise 0-0.7, hold+breath 0.7-2.2 (loop range), lower 2.2-2.9")


# ===================================================================================== lunge (bite leap)
def lunge(E):
    T = 38 / 30.0
    LO_F, LO_H, LD_F, LD_H = 0.40, 0.44, 0.62, 0.70
    IMPACT = 0.57
    vf = lambda t: 7.0 * bell(t, 0.38, 0.68) + 0.5 * bell(t, 0.60, 0.90)
    world = World(vf, 0.0, 0.0, -1.0, T + 1.0)
    hm = home_fl(E)
    print("LUNGE travel total %.2f at land_front %.2f at land_hind %.2f" % (world.at(T)[1], world.at(LD_F)[1], world.at(LD_H)[1]))
    Q0 = {k: world.from_body(0.0, *hm[k]) for k in LEGS}
    Q1 = {k: world.from_body(T, hm[k][0] + (0.07 if k[0] == "F" else 0.03), hm[k][1]) for k in LEGS}
    air = {"FL": (0.56, 0.155, 0.30), "FR": (0.56, -0.155, 0.30), "BL": (-0.98, 0.17, 0.32), "BR": (-0.98, -0.17, 0.32)}
    dz_t = Track([(0, 0), (0.18, -0.10), (0.34, -0.17), (0.44, -0.05), (0.52, 0.09), (0.62, -0.05), (0.72, -0.11), (0.90, -0.03), (1.2667, 0)])
    bp_t = Track([(0, 0), (0.34, 0.05), (0.44, -0.10), (0.54, -0.18), (0.62, 0.06), (0.72, 0.14), (0.95, 0.03), (1.2667, 0)])
    dxf_t = Track([(0, 0), (0.34, -0.11), (0.44, -0.05), (1.25, 0)])
    neck_p = Track([(0, 0), (0.30, 0.40), (0.40, 0.25), (0.50, -0.30), (0.57, -0.45), (0.64, -0.05), (0.80, 0.15), (1.25, 0)])
    head_p = Track([(0, 0), (0.30, 0.15), (0.50, -0.25), (0.55, -0.42), (0.60, 0.35), (0.66, 0.05), (0.85, 0.0), (1.25, 0)])
    back_p = Track([(0, 0), (0.34, -0.14), (0.50, 0.22), (0.70, -0.05), (1.25, 0)])
    tail_p = Track([(0, 0), (0.34, 0.20), (0.5, 0.05), (0.6, -0.25), (0.8, 0.15), (1.25, 0)])
    lift_t = {"F": (LO_F, LD_F), "B": (LO_H, LD_H)}

    def fn(t):
        Fr = {}
        Fr['dz'] = dz_t(t)
        Fr['dx_f'] = dxf_t(t)
        Fr['bp'] = bp_t(t)
        Fr['spine'] = {"Back": (0, back_p(t), 0), "Torso2": (0, -0.5 * back_p(t), 0)}
        Fr['neck'] = (0.0, neck_p(t))
        Fr['head'] = (0, head_p(t), 0)
        Fr['tail'] = [(0.10 * math.sin(6 * t - 0.5 * i) * bell(t, 0.4, 1.0), tail_p(t)) for i in range(8)]
        paws = {}
        pl = {}
        for k in LEGS:
            lo, ld = lift_t[k[0]]
            w = sstep((t - lo) / 0.07) * (1 - sstep((t - (ld - 0.08)) / 0.08))
            Q = Q0[k] if t < 0.5 * (lo + ld) else Q1[k]
            bF, bL = world.to_body(t, *Q)
            aF, aL, aZ = air[k]
            zair = aZ * math.sin(math.pi * clamp((t - lo) / (ld - lo))) ** 0.7
            F_ = lerp(bF, aF, w)
            L_ = lerp(bL, aL, w)
            Z_ = w * zair
            ang = 0.4 * w if k[0] == "B" else 0.0
            paws[k] = (E.to_arm(F_, L_, z=E.u(Z_)), ang)
            pl[k] = (w < 1e-6) and (t < lo or t >= ld)
        Fr['paw'] = paws
        Fr['planted'] = pl
        Fr['blade'] = {"FL": -0.25 * bell(t, LO_F, LD_F + 0.1), "FR": -0.25 * bell(t, LO_F, LD_F + 0.1)}
        return Fr
    return Clip("lunge", T, fn, loop=False, world=world,
                events={"impact": IMPACT, "liftoff_front": LO_F, "liftoff_hind": LO_H, "land_front": LD_F,
                        "land_hind": LD_H, "crouch_deepest": 0.34},
                notes="root motion yes: forward travel from the world table (about 1.4 m)")
