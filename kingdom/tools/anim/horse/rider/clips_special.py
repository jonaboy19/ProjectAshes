# Synced transition / action clips (A): starts, stops, turns in place, rear, buck, spook, horse hit, jump (+ splits), swim, graze, drink.
from rider_lib import *
from clips_gaits import (g_idle, g_walk, g_trot_post, g_trot_sit, g_twopoint, g_gallop, trot_up, turn_mod, build, meta, add, cyc, TAU)


def fv(g, k, f):
    return val(g, k, f)


def mix(ga, gb, w):
    """parameter dict blending ga -> gb with weight w(f) (numbers / callables). 'sig' is taken from ga."""
    out = {}
    for k in set(ga) | set(gb):
        if k in ("sig", "hand_l", "hand_r", "foot_l", "foot_r"):
            out[k] = ga.get(k, gb.get(k))
            continue
        out[k] = (lambda f, k=k: (1 - w(f)) * fv(ga, k, f) + w(f) * fv(gb, k, f))
    return out


def over(g, **kw):
    h = dict(g)
    h.update(kw)
    return h


def damp(f0, amp, decay=5.0, freq=0.42):
    """damped jolt starting at f0 (0 before)."""
    return lambda f: 0.0 if f < f0 else amp * math.exp(-(f - f0) / decay) * math.sin((f - f0) * freq + 0.35) / math.sin(0.35 + freq)


# ------------------------------------------------------------------ starts / stops / turns in place
@clip("Horse_Ride_Walk_Start")
def c_walk_start():
    S = Sync("Walk_Start")
    gi, gw = g_idle(S), g_walk(S)
    w = lambda f: pulse(f, 6, 24)
    g = mix(gi, gw, w)
    kick = lambda f: pulse(f, 1, 5, 10)
    g["heel"] = lambda f: -15.0 - 12.0 * kick(f)
    g["knee_out"] = lambda f: 0.95 - 0.12 * kick(f)
    g["lean"] = lambda f: (1 - w(f)) * fv(gi, "lean", f) + w(f) * 8.0 + 4.0 * pulse(f, 2, 8, 22)
    m = meta(S)
    m["events"] = {"leg_aid": 5}
    return build(S, g), m


@clip("Horse_Ride_Walk_Stop")
def c_walk_stop():
    S = Sync("Walk_Stop")
    gi, gw = g_idle(S), g_walk(S)
    w = lambda f: pulse(f, 14, 44)
    g = mix(gw, gi, w)
    halt = lambda f: pulse(f, 4, 12, 34)
    g["lean"] = lambda f: (1 - w(f)) * 8.0 + w(f) * fv(gi, "lean", f) - 6.0 * halt(f)
    g["grip"] = lambda f: 0.85 + 0.15 * halt(f)
    g["clav"] = lambda f: 6.0 - 8.0 * halt(f)
    g["elbow_back"] = lambda f: 0.55 + 0.4 * halt(f)
    g["pel_pitch"] = lambda f: 6.0 - 5.0 * halt(f)
    m = meta(S)
    m["events"] = {"half_halt": 10}
    return build(S, g), m


@clip("Horse_Ride_Trot_Stop")
def c_trot_stop():
    S = Sync("Trot_Stop")
    post = g_trot_post(S, trot_up(S, 0, 8))
    sit = over(g_trot_sit(S), lean=-2.0, pel_pitch=-2.0, grip=1.0, clav=-3.0, elbow_back=0.9, s_chest=0.6)
    gi = g_idle(S)
    w1 = lambda f: pulse(f, 7, 14)
    w2 = lambda f: pulse(f, 30, 48)
    g = mix(mix(post, sit, w1), gi, w2)
    m = meta(S, seated=[[9, 48]])
    m["events"] = {"sit": 9, "half_halt": 16}
    return build(S, g), m


@clip("Horse_Ride_Gallop_Stop")
def c_gallop_stop():
    S = Sync("Gallop_Stop")
    gg = g_gallop(S)
    gg = over(gg, sig=4.0, s_pel=0.3)
    stop = dict(s_pel=0.2, s_chest=0.7, up_w=0.8, s_head=0.9, lean=-4.0, pel_pitch=-5.0, pz=-0.006, grip=1.0, clav=-2.0,
                elbow_back=1.0, elbow_down=0.5, heel=-26.0, knee_fwd=1.1, h_pitch=2.0)
    gi = over(g_idle(S), s_pel=0.2, up_w=0.8, s_chest=0.5)
    w1 = lambda f: pulse(f, 4, 16)
    w2 = lambda f: pulse(f, 42, 60)
    g = mix(mix(gg, stop, w1), gi, w2)
    g["sig"] = 4.0
    m = meta(S, seated=[[16, 60]])
    m["events"] = {"sit_deep": 16, "pull": 18, "halt": 46}
    return build(S, g), m


def inplace(horse, side):
    S = Sync(horse)
    sg = 1.0 if side == "L" else -1.0
    w = lambda f: pulse(f, 0, 10, None) * (1.0 - pulse(f, 44, 57))
    g = g_idle(S)
    g.update(h_yaw=lambda f: 32.0 * sg * w(f), c_yaw=lambda f: 10.0 * sg * w(f), c_roll=lambda f: 3.0 * sg * w(f),
             px=lambda f: 0.008 * sg * w(f), heel_l=lambda f: (-4.0 if sg > 0 else 3.0) * w(f), heel_r=lambda f: (3.0 if sg > 0 else -4.0) * w(f))
    return build(S, g), meta(S)


@clip("Horse_Ride_Turn_InPlace_L")
def c_tip_l():
    return inplace("Turn_InPlace_L", "L")


@clip("Horse_Ride_Turn_InPlace_R")
def c_tip_r():
    return inplace("Turn_InPlace_R", "R")


# ------------------------------------------------------------------ rear / buck / spook / horse hit
@clip("Horse_Ride_Rear")
def c_rear():
    S = Sync("Rear")
    w = lambda f: pulse(f, 5, 22) * (1.0 - pulse(f, 62, 82))
    g = g_idle(S)
    g.update(sig=3.0, up_w=1.0, s_chest=lambda f: 0.9 * w(f), s_head=lambda f: 0.3 + 0.65 * w(f), s_pelrot=lambda f: 0.35 * w(f),
             lean=lambda f: 8.0 + 14.0 * w(f), pel_pitch=lambda f: 6.0 + 10.0 * w(f), pz=lambda f: 0.02 * w(f), py=lambda f: -0.05 * w(f),
             grip=lambda f: 0.85 + 0.15 * w(f), clav=lambda f: 6.0 + 10.0 * w(f), h_pitch=lambda f: 4.0 - 10.0 * w(f),
             heel=lambda f: -15.0 - 10.0 * w(f), knee_out=lambda f: 0.75 - 0.2 * w(f), elbow_out=lambda f: 0.45 + 0.4 * w(f))
    m = meta(S)
    m["events"] = {"grab_mane": 14, "top": 36, "front_hooves_down": 68}
    m["notes"] = "hands stay on the rein grips at the base of the neck (fists closed = grabbing the mane), torso folds onto the neck"
    return build(S, g), m


@clip("Horse_Ride_Buck")
def c_buck():
    S = Sync("Buck")
    thrown = lambda f: pulse(f, 15, 21, 30)
    back = lambda f: pulse(f, 24, 32, None) * (1.0 - pulse(f, 40, 55))
    w = lambda f: pulse(f, 10, 18) * (1.0 - pulse(f, 44, 57))
    g = g_idle(S)
    g.update(sig=3.0, up_w=1.0, s_chest=lambda f: 0.8 * w(f), s_head=lambda f: 0.3 + 0.6 * w(f),
             lean=lambda f: 8.0 + 22.0 * thrown(f) - 8.0 * back(f), pel_pitch=lambda f: 6.0 + 10.0 * thrown(f) - 8.0 * back(f),
             pz=lambda f: 0.045 * thrown(f), py=lambda f: -0.05 * thrown(f), h_pitch=lambda f: 4.0 + 18.0 * thrown(f) - 6.0 * back(f),
             grip=lambda f: 0.85 + 0.15 * w(f), heel=lambda f: -15.0 - 10.0 * back(f), knee_fwd=lambda f: 0.75 + 0.4 * back(f),
             clav=lambda f: 6.0 + 8.0 * thrown(f) - 6.0 * back(f), elbow_back=lambda f: 0.55 + 0.4 * back(f))
    m = meta(S, seated=[[0, 14], [32, 57]])
    m["events"] = {"thrown_forward": 21, "recover": 32}
    return build(S, g), m


def spook(horse, side):
    S = Sync(horse)
    sg = 1.0 if side == "L" else -1.0           # threat side (horse jumps away from it)
    lurch = lambda f: pulse(f, 2, 7, 22)
    look = lambda f: pulse(f, 2, 8, None) * (1.0 - pulse(f, 26, 42))
    g = g_idle(S)
    g.update(sig=3.0, s_chest=0.6, s_head=0.8, px=lambda f: 0.03 * sg * lurch(f), c_roll=lambda f: 10.0 * sg * lurch(f),
             pel_roll=lambda f: 4.0 * sg * lurch(f), lean=lambda f: 8.0 - 6.0 * lurch(f) + 4.0 * look(f),
             h_yaw=lambda f: 38.0 * sg * look(f), c_yaw=lambda f: 10.0 * sg * look(f), grip=lambda f: 0.85 + 0.15 * look(f),
             heel=lambda f: -15.0 - 8.0 * lurch(f), clav=lambda f: 6.0 - 6.0 * lurch(f), shrug=lambda f: 8.0 * lurch(f))
    m = meta(S)
    m["events"] = {"lurch": 5, "recovered": 34}
    return build(S, g), m


@clip("Horse_Ride_Spook_L")
def c_spook_l():
    return spook("Spook_L", "L")


@clip("Horse_Ride_Spook_R")
def c_spook_r():
    return spook("Spook_R", "R")


def horse_hit(horse, side):
    S = Sync(horse)
    sg = 1.0 if side == "L" else -1.0
    j = damp(1, 1.0, 4.5, 0.5)
    g = g_idle(S)
    g.update(sig=3.0, s_chest=0.5, s_head=0.8, c_roll=lambda f: 9.0 * sg * j(f), h_roll=lambda f: -6.0 * sg * j(f),
             lean=lambda f: 8.0 + 7.0 * j(f), px=lambda f: 0.012 * sg * j(f), h_pitch=lambda f: 4.0 + 10.0 * j(f),
             grip=lambda f: 0.85 + 0.15 * pulse(f, 0, 3, 18), shrug=lambda f: 6.0 * pulse(f, 0, 3, 14))
    m = meta(S)
    m["events"] = {"jolt": 2}
    return build(S, g), m


@clip("Horse_Ride_Hit_L")
def c_hit_l():
    return horse_hit("Hit_L", "L")


@clip("Horse_Ride_Hit_R")
def c_hit_r():
    return horse_hit("Hit_R", "R")


# ------------------------------------------------------------------ jump (full + the horse clip's splits)
def jump_poses():
    S = Sync("Jump_Full")
    k = lambda keys: T1(keys)
    g = dict(sig=3.0, up_w=0.5,
             lean=k([(0, 14), (6, 18), (12, 36), (22, 40), (29, 34), (34, 20), (44, 12), (57, 10)]),
             pel_pitch=k([(0, 8), (12, 20), (22, 22), (30, 14), (44, 7), (57, 6)]),
             pz=k([(0, 0.01), (6, 0.02), (13, 0.045), (24, 0.05), (30, 0.03), (35, 0.005), (57, 0.0)]),
             py=k([(0, 0.0), (8, 0.03), (14, 0.07), (26, 0.07), (32, 0.04), (42, 0.0), (57, 0.0)]),
             s_pel=k([(0, 0.2), (10, 0.45), (26, 0.5), (34, 0.3), (46, 0.2), (57, 0.2)]),
             s_chest=k([(0, 0.6), (12, 0.75), (28, 0.75), (40, 0.6), (57, 0.6)]),
             s_pelrot=k([(0, 0.0), (12, 0.35), (28, 0.35), (40, 0.0), (57, 0.0)]),
             s_head=0.92, h_pitch=k([(0, 4), (14, -8), (28, -4), (40, 4), (57, 4)]),
             heel=k([(0, -18), (12, -24), (30, -22), (34, -28), (42, -18), (57, -16)]),
             knee_fwd=k([(0, 0.8), (12, 1.2), (30, 1.2), (44, 0.8), (57, 0.75)]),
             clav=k([(0, 6), (12, 12), (28, 12), (40, 6), (57, 6)]), elbow_back=k([(0, 0.55), (12, 0.2), (28, 0.2), (40, 0.55), (57, 0.55)]),
             grip=0.9)
    return S, build(S, g)


@clip("Horse_Ride_Jump_Full")
def c_jump_full():
    S, P = jump_poses()
    m = meta(S, seated=[[0, 4], [44, 57]])
    m["events"] = {"fold": 10, "takeoff": 13, "land": 30, "seated": 44}
    return P, m


def jump_split(name, a, b, ev):
    S, P = jump_poses()
    Ss = Sync(name)
    assert Ss.n == b - a + 1
    m = meta(Ss, seated=False)
    m["split_of"] = ["Horse_Ride_Jump_Full", a, b]
    m["events"] = ev
    return P[a:b + 1], m


@clip("Horse_Ride_Jump_Takeoff")
def c_jump_to():
    return jump_split("Jump_Takeoff", 0, 14, {"fold": 10, "takeoff": 13})


@clip("Horse_Ride_Jump_Air")
def c_jump_air():
    return jump_split("Jump_Air", 14, 31, {"land": 16})


@clip("Horse_Ride_Jump_Land")
def c_jump_land():
    return jump_split("Jump_Land", 31, 57, {"seated": 13})


# ------------------------------------------------------------------ swim / graze / drink
@clip("Horse_Ride_Swim")
def c_swim():
    S = Sync("Swim")
    g = dict(up_w=0.7, s_chest=0.7, s_head=0.9, s_pel=0.3, lean=18.0, pel_pitch=10.0, pz=0.02, py=-0.02, h_pitch=-2.0,
             clav=12.0, heel=-10.0, knee_fwd=1.0, elbow_back=0.25, elbow_down=0.8, elbow_out=0.6)
    return build(S, g), meta(S)


def rest_hands(S, dz=-0.07, dy=0.09):
    br = cyc(S, 1.0)

    def hand(side):
        def fn(f, P, sh):
            G = GRIP_REST[side] + V(SX[side] * 0.03, dy, dz + 0.004 * br(f))
            return G, rein_rot(side, 25.0), 0.45
        return fn
    return hand("l"), hand("r")


def graze_like(horse):
    S = Sync(horse)
    hl, hr = rest_hands(S)
    br = cyc(S, 2.0)
    g = dict(up_w=1.0, s_chest=0.85, s_head=0.8, s_pelrot=0.3, lean=lambda f: 3.0 + 0.8 * br(f), pel_pitch=2.0, h_pitch=22.0,
             h_yaw=lambda f: 6.0 * math.sin(TAU * f / (S.n - 1)), heel=-10.0, clav=0.0, hand_l=hl, hand_r=hr,
             elbow_back=0.8, elbow_down=0.5)
    m = meta(S, hands_on_grips=False)
    m["notes"] = ("loose reins: the horse's head is down (rein grips move ~0.25 m forward/down); the hands rest low on the withers. "
                  "The rein grips are out of reach here: IK the reins' rein_grip bones to the rider's palms in game.")
    return build(S, g), m


@clip("Horse_Ride_Graze")
def c_graze():
    return graze_like("Graze")


@clip("Horse_Ride_Drink")
def c_drink():
    return graze_like("Drink")
