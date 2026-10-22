# Synced riding clips (A): one rider clip per horse clip, same frame count, played at the same normalised time.
# Every clip is seat_pose() (rider_lib) with gait parameters; periodic terms use whole horse cycles so loops close.
from rider_lib import *

TAU = 2 * math.pi


def cyc(S, k=1.0, off=0.0):
    """sin of k cycles over the clip (loops: period = frames - 1)."""
    per = float(S.n - 1)
    return lambda f: math.sin(TAU * k * f / per + off)


def zdev(S, gain, sig=None, axis=2):
    """saddle displacement (clip axis) relative to its low-passed mean, times gain (for absorption terms)."""
    sm = S.smoothed(sig)
    return lambda f: gain * (S.Dp[f][axis] - sm[f][0][axis])


def pitchdev(S, gain, sig=None):
    sm = S.smoothed(sig)

    def fn(f):
        q = sm[f][1].inverted() @ S.Dq[f]
        return gain * math.degrees(q.to_euler("XYZ").x)
    return fn


def build(S, g):
    return [seat_pose(S, f, g) for f in range(S.n)]


def meta(S, **kw):
    m = dict(synced_to=S.clip, loop=S.loop, layer="full", hands_on_grips=True, seated=True, feet_in_stirrups=True)
    m.update(kw)
    return m


def add(a, b):
    """sum of two parameters (numbers or callables)."""
    fa = a if callable(a) else (lambda f, a=a: a)
    fb = b if callable(b) else (lambda f, b=b: b)
    return lambda f: fa(f) + fb(f)


# ------------------------------------------------------------------ parameter sets
def g_idle(S):
    br = cyc(S, 2.0)                      # two breaths per 4 s loop
    return dict(s_chest=0.3, s_head=0.7, lean=add(8.0, lambda f: 0.8 * br(f)), h_yaw=lambda f: 7.0 * math.sin(TAU * f / (S.n - 1) + 0.6),
                h_pitch=add(5.0, lambda f: 1.5 * math.sin(TAU * f / (S.n - 1) * 1.0 + 2.0)), shrug=lambda f: 1.0 * br(f))


def g_walk(S):
    return dict(s_pel=0.35, sig=None, s_chest=0.6, s_head=0.9, lean=8.0, h_pitch=5.0, pz=0.004,
                pel_pitch=add(6.0, pitchdev(S, -0.4)), heel_l=cyc(S, 1.0, 0.0), heel_r=cyc(S, 1.0, math.pi))


def trot_up(S, f0=0, f1=11, per=None):
    """posting: rise out of the saddle on the diagonal FR+HL (stance 0..9, thrust -> up), back in the saddle when FL+HR lands (11)."""
    per = per or (S.n - 1)

    def up(f):
        u = (f % per if S.loop else f)
        if f0 <= u <= f1:
            return math.sin(math.pi * (u - f0) / (f1 - f0)) ** 1.3
        return 0.0
    return up


def g_trot_post(S, up=None):
    up = up or trot_up(S)
    return dict(s_pel=lambda f: 0.25 + 0.35 * up(f), sig=None, s_chest=0.6, s_head=0.9,
                pz=lambda f: 0.092 * up(f), py=lambda f: -0.040 * up(f), lean=lambda f: 11.0 + 8.0 * up(f),
                pel_pitch=lambda f: 6.0 + 8.0 * up(f), heel=lambda f: -16.0 + 7.0 * up(f), h_pitch=4.0,
                knee_fwd=lambda f: 0.75 + 0.35 * up(f))


def g_trot_sit(S):
    return dict(s_pel=0.2, sig=None, s_chest=0.7, s_head=0.92, lean=5.0, pz=-0.004, pel_pitch=add(4.0, zdev(S, -110.0)),
                heel=-19.0, h_pitch=4.0, clav=4.0)


def g_canter(S, lead):
    return dict(s_pel=0.25, sig=None, s_chest=0.75, s_head=0.92, lean=10.0, pel_pitch=add(7.0, pitchdev(S, 0.35)), h_pitch=4.0,
                c_roll=lambda f: 0.0, heel=-17.0, h_yaw=3.0 * (1 if lead == "L" else -1))


def g_twopoint(S, lean=26.0, lift=0.075, back=0.07, s=0.6):
    return dict(s_pel=s, sig=None, s_pelrot=0.5, s_chest=0.85, s_head=0.95, lean=lean, pz=lift, py=back,
                pel_pitch=lean * 0.55, h_pitch=0.0, heel=-24.0, knee_fwd=1.1, knee_out=1.45, clav=10.0,
                elbow_back=0.2, elbow_down=0.9, elbow_out=0.55)


def g_gallop(S):
    return g_twopoint(S, lean=38.0, lift=0.085, back=0.085, s=0.7)


def turn_mod(g, side, look=24.0, chest=9.0, roll=4.0):
    sg = 1.0 if side == "L" else -1.0
    g = dict(g)
    g["h_yaw"] = add(g.get("h_yaw", 0.0), look * sg)
    g["c_yaw"] = add(g.get("c_yaw", 0.0), chest * sg)
    g["c_roll"] = add(g.get("c_roll", 0.0), roll * sg)
    g["px"] = add(g.get("px", 0.0), 0.008 * sg)
    return g


# ------------------------------------------------------------------ clips
@clip("Horse_Ride_Idle")
def c_idle():
    S = Sync("Idle")
    return build(S, g_idle(S)), meta(S)


@clip("Horse_Ride_Idle_LookAround")
def c_lookaround():
    S = Sync("Idle")
    g = g_idle(S)
    hy = T1([(0, 0), (8, 0), (24, 58), (38, 58), (52, 0), (58, -8), (72, -60), (82, -60), (90, -95), (104, -95), (120, 0)])
    cy = T1([(0, 0), (8, 0), (24, 10), (38, 10), (52, 0), (72, -10), (82, -10), (90, -32), (104, -32), (120, 0)])
    hp = T1([(0, 5), (24, 2), (38, 4), (72, 2), (90, 8), (104, 8), (120, 5)])
    base_y = g["h_yaw"]
    g.update(h_yaw=lambda f: hy(f) + base_y(f) * (1.0 if f < 4 or f > 116 else 0.0), c_yaw=cy, h_pitch=hp,
             clav_r=lambda f: 6.0 - 10.0 * pulse(f, 82, 92, 108))
    m = meta(S, loop=False)
    m["events"] = {"look_left": 24, "look_right": 72, "look_back": 92}
    return build(S, g), m


@clip("Horse_Ride_Walk")
def c_walk():
    S = Sync("Walk")
    return build(S, g_walk(S)), meta(S)


@clip("Horse_Ride_Trot")
def c_trot():
    S = Sync("Trot")
    m = meta(S, seated="sit phase only (frames 11-22)")
    m["events"] = {"rise": 1, "sit": 11}
    m["notes"] = "posting (rising) trot: rise with diagonal FR+HL (frames 0-10), sit on FL+HR (11-22); one rise per stride"
    return build(S, g_trot_post(S)), m


@clip("Horse_Ride_Trot_Sit")
def c_trot_sit():
    S = Sync("Trot")
    return build(S, g_trot_sit(S)), meta(S)


@clip("Horse_Ride_Canter_L")
def c_canter_l():
    S = Sync("Canter_L")
    return build(S, g_canter(S, "L")), meta(S)


@clip("Horse_Ride_Canter_R")
def c_canter_r():
    S = Sync("Canter_R")
    return build(S, g_canter(S, "R")), meta(S)


@clip("Horse_Ride_Canter_TwoPoint_L")
def c_canter_2p():
    S = Sync("Canter_L")
    return build(S, g_twopoint(S)), meta(S, seated=False)


@clip("Horse_Ride_Gallop_L")
def c_gallop_l():
    S = Sync("Gallop_L")
    return build(S, g_gallop(S)), meta(S, seated=False)


@clip("Horse_Ride_Gallop_R")
def c_gallop_r():
    S = Sync("Gallop_R")
    return build(S, g_gallop(S)), meta(S, seated=False)


@clip("Horse_Ride_BackUp")
def c_backup():
    S = Sync("BackUp")
    g = g_walk(S)
    g.update(lean=4.0, hl_dy=0.0, grip=1.0, h_yaw=lambda f: 10.0 * math.sin(TAU * f / (S.n - 1)), clav=2.0, s_pel=0.2)
    return build(S, g), meta(S)


def turn_clip(horse, base, side):
    S = Sync(horse)
    return build(S, turn_mod(base(S), side)), meta(S)


@clip("Horse_Ride_Walk_Turn_L")
def c_wtl():
    return turn_clip("Walk_Turn_L", g_walk, "L")


@clip("Horse_Ride_Walk_Turn_R")
def c_wtr():
    return turn_clip("Walk_Turn_R", g_walk, "R")


@clip("Horse_Ride_Trot_Turn_L")
def c_ttl():
    S = Sync("Trot_Turn_L")
    m = meta(S, seated="sit phase only (frames 11-22)")
    return build(S, turn_mod(g_trot_post(S), "L")), m


@clip("Horse_Ride_Trot_Turn_R")
def c_ttr():
    S = Sync("Trot_Turn_R")
    m = meta(S, seated="sit phase only (frames 11-22)")
    return build(S, turn_mod(g_trot_post(S), "R")), m


@clip("Horse_Ride_Canter_Turn_L")
def c_ctl():
    return turn_clip("Canter_Turn_L", lambda S: g_canter(S, "L"), "L")


@clip("Horse_Ride_Canter_Turn_R")
def c_ctr():
    return turn_clip("Canter_Turn_R", lambda S: g_canter(S, "R"), "R")


@clip("Horse_Ride_Gallop_Turn_L")
def c_gtl():
    S = Sync("Gallop_Turn_L")
    return build(S, turn_mod(g_gallop(S), "L", look=18.0, chest=6.0, roll=3.0)), meta(S, seated=False)


@clip("Horse_Ride_Gallop_Turn_R")
def c_gtr():
    S = Sync("Gallop_Turn_R")
    return build(S, turn_mod(g_gallop(S), "R", look=18.0, chest=6.0, roll=3.0)), meta(S, seated=False)
