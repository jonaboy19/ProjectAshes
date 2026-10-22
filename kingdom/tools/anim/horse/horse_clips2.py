# Horse clips, part 2: transitions (start / stop / turn in place), leaning run turns, idles, situational and action clips.
# Uses the phase-driven stepping generator: a clip gives a root path and a stride-phase rate; hooves lift and land when the
# phase crosses the gait's footfall pattern, and every landing is placed under its neutral point at mid stance.
import math
from mathutils import Vector, Matrix, Quaternion
import horse_gait as G
import horse_clips as HC

V = G.V
Trk = G.Trk
clip = HC.clip
rad = math.radians
TAU = 2 * math.pi
GAITS = HC.GAITS
DT = 1.0 / 240


def xf_of(pos, yaw):
    return lambda t: Matrix.Translation(pos(t)) @ Quaternion((0, 0, 1), yaw(t)).to_matrix().to_4x4()


def integrate(rate, t0, t1, dt=DT):
    """cumulative integral table of rate(t): returns f(t) (linear interpolation)"""
    n = int(math.ceil((t1 - t0) / dt)) + 2
    ts = [t0 + i * dt for i in range(n)]
    acc = [0.0]
    for i in range(1, n):
        acc.append(acc[-1] + 0.5 * (rate(ts[i - 1]) + rate(ts[i])) * dt)

    def f(t):
        if t <= t0:
            return acc[0] + rate(t0) * (t - t0)
        if t >= ts[-1]:
            return acc[-1] + rate(ts[-1]) * (t - ts[-1])
        x = (t - t0) / dt
        i = int(x)
        return acc[i] + (acc[i + 1] - acc[i]) * (x - i)
    return f


def speed_path(speed, t0, t1, yaw=lambda t: 0.0):
    """root position from a forward speed profile (m/s) along the heading yaw(t)"""
    n = int(math.ceil((t1 - t0) / DT)) + 2
    ts = [t0 + i * DT for i in range(n)]
    ps = [V(0, 0, 0)]
    for i in range(1, n):
        tm = ts[i] - DT * 0.5
        d = Quaternion((0, 0, 1), yaw(tm)) @ V(0, -1, 0)
        ps.append(ps[-1] + d * speed(tm) * DT)

    def pos(t):
        if t <= t0:
            return ps[0].copy()
        if t >= ts[-1]:
            return ps[-1].copy()
        x = (t - t0) / DT
        i = int(x)
        return ps[i].lerp(ps[i + 1], x - i)
    return pos


def stepping(sc, pattern, duty, phase, rate, t_stop, t_end, xf, neutral, square=True, step_time=0.34, order=("HL", "HR", "FL", "FR"),
             place_off=None, moving=False):
    """stance intervals from phase crossings. All hooves start planted square at xf(0); a leg that is in its swing phase at
    t=0 lifts at once. After t_stop no new lift starts; hooves in the air land at their next crossing under xf(t_end).
    square=True adds single steps at the end for hooves left more than 5 cm off the final square stance."""
    end_xf = xf(t_end)
    lands = {}
    for leg, ph in pattern.items():
        d = duty[leg] if isinstance(duty, dict) else duty
        st = []
        p0 = phase(0.0)
        frac = (p0 - ph) % 1.0
        planted = frac < d
        pos = xf(0.0) @ neutral[leg]
        pos.z = 0.0
        start = -1000.0
        if moving:
            # already in the gait at t=0: the current (or last) stance comes from the previous footfall crossing
            r0 = max(rate(0.0), 1e-3)
            tl = -frac / r0
            tu = tl + d / r0
            M = xf(tl + 0.5 * d / r0)
            pos = M @ neutral[leg]
            pos.z = 0.0
            start = tl
            if not planted:
                st.append((tl, tu, pos))
        elif not planted:
            st.append((start, 0.0, pos))
        t = 0.0
        prev = p0
        while t < t_stop - 1e-9:
            t += DT
            cur = phase(t)
            for x, kind in ((ph, "land"), (ph + d, "lift")):
                if math.floor(cur - x) > math.floor(prev - x):
                    if kind == "lift" and planted:
                        st.append((start, t, pos))
                        planted = False
                    elif kind == "land" and not planted:
                        r = max(rate(t), 1e-3)
                        tm = min(t + 0.5 * d / r, t_end)
                        M = xf(tm)
                        loc = neutral[leg].copy()
                        if place_off:
                            loc += place_off(leg, tm)
                        pos = M @ loc
                        pos.z = 0.0
                        start = t
                        planted = True
            prev = cur
        if not planted:
            # land at the next crossing (at the current rate), under the final square stance
            r = max(rate(t), 0.4)
            k = math.ceil(prev - ph)
            tl = t + max(0.12, (ph + k - prev) / r)
            pos = end_xf @ neutral[leg]
            pos.z = 0.0
            start = tl
        st.append((start, 1000.0, pos))
        sc.stances[leg] = st
        lands[leg] = start
    if square:
        tk = max(max(s[0] for s in sc.stances[l][-1:]) for l in pattern) + 0.06
        tk = max(tk, t_stop)
        for leg in order:
            tgt = end_xf @ neutral[leg]
            tgt.z = 0.0
            last = sc.stances[leg][-1]
            if (last[2] - tgt).length > 0.05:
                s0 = max(tk, last[0] + 0.2)
                sc.stances[leg][-1] = (last[0], s0, last[2])
                sc.stances[leg].append((s0 + step_time, 1000.0, tgt))
                tk = s0 + step_time * 0.55
    return sc


def gait_body_fn(kind, lead="L"):
    """the gait's body profile functions evaluated per phase (period 1)"""
    tmp = G.Script("tmp", 1.0, True)
    HC.run_body(tmp, 1.0, kind, lead)
    return tmp


def blend_body(sc, prof, phase, w):
    """body/neck/head/ears/tail of a gait profile driven by phase(t), faded in by w(t) (0 = standing still)"""
    z3 = V(0, 0, 0)
    sc.body_off = lambda t: prof.body_off(phase(t)) * w(t)
    sc.body_rot = lambda t: prof.body_rot(phase(t)) * w(t)
    sc.spine = lambda t: prof.spine(phase(t)) * w(t)
    sc.neck = lambda t: prof.neck(phase(t)) * w(t) + STAND_NECK * (1 - w(t))
    sc.head = lambda t: prof.head(phase(t)) * w(t) + STAND_HEAD * (1 - w(t))
    sc.tail_base = lambda t: prof.tail_base(phase(t)) * w(t) + STAND_TAIL * (1 - w(t))
    sc.tail_lift = lambda t: prof.tail_lift(phase(t)) * w(t)
    sc.ears = lambda t: tuple(a * w(t) + b * (1 - w(t)) for a, b in zip(prof.ears(phase(t)), (rad(-6), rad(5), rad(-6), rad(5))))


STAND_NECK = V(rad(-4), 0, 0)
STAND_HEAD = V(rad(4), 0, 0)
STAND_TAIL = V(rad(2), 0, 0)


def transition(name, kind, dur, v0, v1, t_ramp0, t_ramp1, stop=False, lead="L", pattern=None, rate0=None, rate1=None):
    g = GAITS[kind]
    T = g["frames"] / G.FPS
    sc = G.Script(name, dur, False)
    speed = lambda t: HC_lerp(v0, v1, G.smooth((t - t_ramp0) / max(t_ramp1 - t_ramp0, 1e-6)))
    pos0 = speed_path(speed, -1.0, dur + 1.0)
    o0 = pos0(0.0)
    pos = lambda t: pos0(t) - o0
    yaw = lambda t: 0.0
    sc.root_pos, sc.root_yaw = pos, yaw
    f_g = 1.0 / T
    r0 = f_g * 0.45 if rate0 is None else rate0
    r1 = f_g * 0.45 if rate1 is None else rate1
    rate = lambda t: HC_lerp(r0, r1, G.smooth((t - t_ramp0) / max(t_ramp1 - t_ramp0, 1e-6)))
    ph0 = {"walk": 0.0, "trot": 0.21, "canter": 0.30}.get(kind, 0.0) if v0 == 0 else 0.0
    ph_i = integrate(rate, -0.5, dur + 1.0)
    phase = lambda t: ph_i(t) + ph0
    pat = pattern or (g["pattern"] if lead == "L" else HC.mirror_pattern(g["pattern"]))
    duty = g["duty"] if not isinstance(g["duty"], dict) or lead == "L" else HC.mirror_pattern(g["duty"])
    t_stop = (t_ramp1 + 0.05) if stop else dur
    stepping(sc, pat, duty, phase, rate, t_stop, dur, xf_of(pos, yaw), HC.ENG.neutral, square=stop, moving=v0 > 0)
    for leg in G.LEGS:
        sc.swing_h[leg] = g["swing"][leg[0]]
    sc.flex, sc.fetlock_flex, sc.load, sc.breakover = dict(g["flex"]), dict(g["fflex"]), dict(g["load"]), g["breakover"]
    prof = gait_body_fn(kind, lead)
    vmax = abs(g["speed"])
    w = lambda t: min(1.0, abs(speed(t)) / vmax)
    blend_body(sc, prof, phase, w)
    sc.meta = {"gait": kind, "transition": True, "speed_in": v0, "speed_out": v1}
    return sc, speed, phase


def HC_lerp(a, b, t):
    return a + (b - a) * t


def add_hoof_events(sc):
    n = int(round(sc.duration * G.FPS))
    for leg in G.LEGS:
        fr = sorted(set(int(round(s[0] * G.FPS)) for s in sc.stances[leg] if 0 <= s[0] * G.FPS <= n))
        if fr:
            sc.events["hoof_" + leg] = fr


# ------------------------------------------------------------------ starts and stops
@clip
def Walk_Start():
    sc, sp, ph = transition("Walk_Start", "walk", 1.5, 0.0, 1.5, 0.05, 1.25, rate0=0.35, rate1=1 / (34 / 30))
    add_hoof_events(sc)
    return sc


@clip
def Walk_Stop():
    sc, sp, ph = transition("Walk_Stop", "walk", 1.8, 1.5, 0.0, 0.0, 0.9, stop=True, rate0=1 / (34 / 30), rate1=0.5)
    add_hoof_events(sc)
    return sc


@clip
def Trot_Start():
    sc, sp, ph = transition("Trot_Start", "trot", 1.2, 0.0, 3.6, 0.05, 1.0, rate0=0.7, rate1=30 / 22)
    add_hoof_events(sc)
    return sc


@clip
def Trot_Stop():
    sc, sp, ph = transition("Trot_Stop", "trot", 1.6, 3.6, 0.0, 0.0, 0.85, stop=True, rate0=30 / 22, rate1=0.9)
    add_hoof_events(sc)
    return sc


@clip
def Canter_Start_L():
    sc, sp, ph = transition("Canter_Start_L", "canter", 1.2, 0.0, 5.8, 0.05, 1.05, rate0=0.9, rate1=30 / 18)
    add_hoof_events(sc)
    return sc


@clip
def Gallop_Stop():
    """gallop to halt in ~1.2 s: canter footfalls slowing, haunches lowered, forehand up, head raised"""
    sc, sp, ph = transition("Gallop_Stop", "canter", 2.0, 11.0, 0.0, 0.0, 1.15, stop=True, rate0=30 / 14, rate1=1.0)
    base_rot = sc.body_rot
    brake = lambda t: math.sin(math.pi * G.smooth(t / 1.3)) if t < 1.3 else 0.0
    sc.body_rot = lambda t: base_rot(t) + V(rad(-9) * brake(t), 0, 0)
    base_off = sc.body_off
    sc.body_off = lambda t: base_off(t) + V(0, 0.06 * brake(t), -0.06 * brake(t))
    base_neck = sc.neck
    sc.neck = lambda t: base_neck(t) + V(rad(-12) * brake(t), 0, 0)
    sc.support_max = 0.14
    add_hoof_events(sc)
    sc.meta["gait"] = "gallop"
    return sc


def turn_in_place(name, sign):
    """90 degree turn on the haunches: the forehand steps around, the hind feet step small, the hindquarters stay put"""
    dur = 1.9
    sc = G.Script(name, dur, False)
    ang = lambda t: sign * rad(90) * G.smoother((t - 0.1) / 1.35)
    hind_c = V(0, 0.60, 0)
    sc.root_yaw = ang
    sc.root_pos = lambda t: hind_c - Quaternion((0, 0, 1), ang(t)) @ hind_c
    rate = lambda t: 1.25 if t < 1.45 else 0.8
    phase = integrate(rate, -0.5, dur + 1)
    g = GAITS["walk"]
    stepping(sc, g["pattern"], 0.55, lambda t: phase(t) + 0.3, rate, 1.45, dur, xf_of(sc.root_pos, sc.root_yaw), HC.ENG.neutral,
             square=True, order=("FL", "FR", "HL", "HR"))
    for leg in G.LEGS:
        sc.swing_h[leg] = 0.10 if leg[0] == "F" else 0.07
    sc.flex = {"F": 0.8, "H": 0.45}
    sc.fetlock_flex = {"F": 0.9, "H": 0.8}
    sc.load = {"F": 0.12, "H": 0.12}
    sc.breakover = 0.4
    bend = lambda t: math.sin(math.pi * G.smooth((t - 0.05) / 1.5))
    sc.neck = lambda t: V(rad(-4), sign * rad(4) * bend(t), sign * rad(14) * bend(t))
    sc.head = lambda t: V(rad(5), 0, sign * rad(8) * bend(t))
    sc.spine = lambda t: V(0, 0, sign * rad(6) * bend(t))
    sc.body_rot = lambda t: V(0, -sign * rad(2) * bend(t), 0)
    sc.ears = lambda t: (rad(-6), rad(5) + sign * rad(10) * bend(t), rad(-6), rad(5) - sign * rad(10) * bend(t))
    sc.tail_base = lambda t: V(rad(2), 0, -sign * rad(8) * bend(t))
    add_hoof_events(sc)
    sc.meta = {"gait": "turn", "turn_deg": 90 * sign}
    return sc


@clip
def Turn_InPlace_L():
    return turn_in_place("Turn_InPlace_L", 1)


@clip
def Turn_InPlace_R():
    return turn_in_place("Turn_InPlace_R", -1)


# ------------------------------------------------------------------ leaning turn loops
def turn_loop(name, kind, yaw_deg_s, lead, lean_deg):
    g = GAITS[kind]
    w = rad(yaw_deg_s)
    sgn = 1.0 if w > 0 else -1.0
    T = g["frames"] / G.FPS
    sc = G.Script(name, T, True)
    pos, yaw, xf = HC.root_line(g["speed"], w)
    sc.root_pos, sc.root_yaw = pos, yaw
    pat = g["pattern"] if lead == "L" else HC.mirror_pattern(g["pattern"])
    duty = g["duty"] if not isinstance(g["duty"], dict) or lead == "L" else HC.mirror_pattern(g["duty"])
    lean = rad(lean_deg) * sgn
    # the body leans in over the hooves: hooves land a little to the outside, inside legs slightly shorter steps
    off = lambda leg, t: V(-sgn * 1.05 * math.sin(abs(lean)) * 0.55, 0, 0)
    G.gait_stances(sc, pat, T, duty, -3 * T, 3 * T, xf, HC.ENG.neutral, place_off=off)
    for leg in G.LEGS:
        sc.swing_h[leg] = g["swing"][leg[0]]
    sc.flex, sc.fetlock_flex, sc.load, sc.breakover = dict(g["flex"]), dict(g["fflex"]), dict(g["load"]), g["breakover"]
    HC.run_body(sc, T, kind, lead)
    br, nk, hd, sp = sc.body_rot, sc.neck, sc.head, sc.spine
    sc.body_rot = lambda t: br(t) + V(0, lean, 0)
    sc.spine = lambda t: sp(t) + V(0, 0, sgn * rad(5))
    sc.neck = lambda t: nk(t) + V(0, -lean * 0.4, sgn * rad(10))
    sc.head = lambda t: hd(t) + V(0, -lean * 0.3, sgn * rad(6))
    sc.meta = {"gait": kind, "turn_deg_s": yaw_deg_s, "lean_deg": lean_deg * sgn, "lead": lead,
               "radius_m": round(abs(g["speed"] / w), 2), "stride_m": round(abs(g["speed"]) * T, 3)}
    for leg in G.LEGS:
        lands = sorted(set(int(round((tl % T) * G.FPS)) % g["frames"] for tl, tu, p in sc.stances[leg]))
        sc.events["hoof_" + leg] = lands
    return sc


@clip
def Walk_Turn_L():
    return turn_loop("Walk_Turn_L", "walk", 35, "L", 3)


@clip
def Walk_Turn_R():
    return turn_loop("Walk_Turn_R", "walk", -35, "L", 3)


@clip
def Trot_Turn_L():
    return turn_loop("Trot_Turn_L", "trot", 40, "L", 7)


@clip
def Trot_Turn_R():
    return turn_loop("Trot_Turn_R", "trot", -40, "L", 7)


@clip
def Canter_Turn_L():
    return turn_loop("Canter_Turn_L", "canter", 40, "L", 12)


@clip
def Canter_Turn_R():
    return turn_loop("Canter_Turn_R", "canter", -40, "R", 12)


@clip
def Gallop_Turn_L():
    return turn_loop("Gallop_Turn_L", "gallop", 32, "L", 16)


@clip
def Gallop_Turn_R():
    return turn_loop("Gallop_Turn_R", "gallop", -32, "R", 16)


@clip
def Cart_Pull_Walk():
    """pulling a loaded cart: shorter, heavier walk, leaning into the collar, head lower"""
    g = dict(GAITS["walk"])
    g.update(frames=36, speed=1.25, duty=0.64)
    sc, T, pat = HC.base_script("Cart_Pull_Walk", g)
    HC.run_body(sc, T, "walk")
    br, nk, hd, bo = sc.body_rot, sc.neck, sc.head, sc.body_off
    sc.body_rot = lambda t: br(t) + V(rad(3.0), 0, 0)
    sc.body_off = lambda t: bo(t) + V(0, -0.05, -0.02)
    sc.neck = lambda t: nk(t) + V(rad(10), 0, 0)
    sc.head = lambda t: hd(t) + V(rad(4), 0, 0)
    sc.load = {"F": 0.24, "H": 0.22}
    sc.meta["gait"] = "cart_walk"
    return sc


@clip
def Cart_Pull_Trot():
    g = dict(GAITS["trot"])
    g.update(frames=24, speed=3.0)
    sc, T, pat = HC.base_script("Cart_Pull_Trot", g)
    HC.run_body(sc, T, "trot")
    br, nk = sc.body_rot, sc.neck
    sc.body_rot = lambda t: br(t) + V(rad(2.5), 0, 0)
    sc.neck = lambda t: nk(t) + V(rad(8), 0, 0)
    sc.meta["gait"] = "cart_trot"
    return sc


import horse_clips3  # noqa: E402,F401  (idles and actions)
