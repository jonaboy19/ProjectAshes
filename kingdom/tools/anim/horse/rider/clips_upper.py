# Rider actions (B), authored on the seated rider with the horse at REST (synced_to = null). Lower body (root, pelvis, legs) stays
# exactly in the seated stirrup pose, so Codex can layer spine_01 and everything under it (sidecar upper_bones) over any gait clip.
# Weapon convention: a sword blade / bow limb runs along the fist's THUMB direction (in the UAL T-pose rest: armature -Y, forward).
from rider_lib import *

REACH = 0.46
BASE_UP = dict(lean=8.0, h_pitch=5.0, s_chest=0.0, s_head=0.0)
P0 = SEAT


def blade_rot(side, blade, palm):
    """hand rotation whose thumb (weapon axis) points along `blade` and whose palm faces `palm`."""
    b = Vector(blade).normalized()
    n = Vector(palm)
    n = (n - b * n.dot(b)).normalized()
    d = n.cross(b) if side == "r" else b.cross(n)
    return hand_rot(side, d, n)


def R_of(side, spec):
    if isinstance(spec, Quaternion):
        return spec
    if spec == "rein":
        return rein_rot(side)
    kind, a, b = spec
    return blade_rot(side, a, b) if kind == "blade" else hand_rot(side, a, b)


def htrack(side, keys):
    """keys: [(frame, G (clip palm-centre position, tuple), rotation spec, grip), ...] -> seat_pose hand override."""
    fs = [k[0] for k in keys]
    Gt = Trk([(k[0], Vector(k[1])) for k in keys])
    gt = Trk([(k[0], float(k[3])) for k in keys])
    Rs = [R_of(side, k[2]) for k in keys]
    rein = [k[2] == "rein" for k in keys]

    def fn(f, P, sh):
        i = 0
        while i < len(fs) - 2 and f > fs[i + 1]:
            i += 1
        t = smooth((f - fs[i]) / float(fs[i + 1] - fs[i])) if f > fs[i] else 0.0
        t = min(1.0, t)
        R = Rs[i].slerp(qalign(Rs[i + 1], Rs[i]), t)
        G = Gt(f)
        d = G - sh
        if d.length > REACH and not (rein[i] or rein[i + 1]):                     # keep the palm within reach of the (estimated) shoulder: no IK misses
            G = sh + d * (REACH / d.length)
        return G, R, gt(f)
    return fn


def rest_build(n, g):
    S = Sync.rest(n)
    gg = dict(BASE_UP)
    gg.update(g)
    return [seat_pose(S, f, gg) for f in range(n)]


def bmeta(loop=False, layer="upper", ev=None, **kw):
    m = dict(synced_to=None, loop=loop, layer=layer, hands_on_grips=False, seated=True, feet_in_stirrups=True)
    if ev:
        m["events"] = ev
    m.update(kw)
    return m


GL, GR = tuple(GRIP_REST["l"]), tuple(GRIP_REST["r"])


# ------------------------------------------------------------------ reins / aids
def rein_turn(sg):
    n = 31
    open_ = lambda f: pulse(f, 2, 9, None) * (1.0 - pulse(f, 20, 30))
    s_in = "l" if sg > 0 else "r"
    g = dict(h_yaw=lambda f: 28.0 * sg * open_(f), c_yaw=lambda f: 9.0 * sg * open_(f), c_roll=lambda f: 3.0 * sg * open_(f))
    g["h%s_dx" % s_in[0]] = lambda f: 0.17 * sg * open_(f)
    g["h%s_dy" % s_in[0]] = lambda f: 0.06 * open_(f)
    g["h%s_dz" % s_in[0]] = lambda f: -0.02 * open_(f)
    g["grip"] = 0.95
    return rest_build(n, g), bmeta(ev={"rein_open": 9, "rein_release": 20}, hands_on_grips=[[0, 2], [30, 30]])


@clip("Horse_Ride_Rein_Turn_L")
def c_rein_l():
    return rein_turn(1.0)


@clip("Horse_Ride_Rein_Turn_R")
def c_rein_r():
    return rein_turn(-1.0)


@clip("Horse_Ride_Spur")
def c_spur():
    n = 25
    kick = lambda f: pulse(f, 2, 5, 8) + pulse(f, 9, 12, 16)
    g = dict(lean=lambda f: 8.0 + 6.0 * pulse(f, 1, 6, 22), heel=lambda f: -15.0 + 22.0 * kick(f), toe_out=lambda f: 8.0 - 16.0 * kick(f),
             knee_out=lambda f: 0.75 - 0.3 * kick(f), h_pitch=lambda f: 5.0 - 4.0 * pulse(f, 1, 6, 22), grip=0.9)
    m = bmeta(layer="full", ev={"spur": [5, 12]}, hands_on_grips=True)
    m["notes"] = "legs carry the aid (heels squeeze twice): play full-body (idle / walk) or upper_bones only for the forward lean"
    return rest_build(n, g), m


@clip("Horse_Ride_Stop_Pull")
def c_stop_pull():
    n = 31
    p = lambda f: pulse(f, 2, 9, None) * (1.0 - pulse(f, 20, 30))
    g = dict(lean=lambda f: 8.0 - 12.0 * p(f), hl_dy=lambda f: 0.13 * p(f), hr_dy=lambda f: 0.13 * p(f), hl_dz=lambda f: -0.03 * p(f),
             hr_dz=lambda f: -0.03 * p(f), grip=lambda f: 0.85 + 0.15 * p(f), clav=lambda f: 6.0 - 12.0 * p(f),
             elbow_back=lambda f: 0.55 + 0.6 * p(f), h_pitch=lambda f: 5.0 - 3.0 * p(f), hand_pitch=lambda f: -20.0 * p(f))
    return rest_build(n, g), bmeta(ev={"pull": 9, "release": 20}, hands_on_grips=[[0, 2], [30, 30]])


# ------------------------------------------------------------------ sword (right hand; both reins in the left hand)
REINS_ONE = (0.035, -0.585, 1.735)
READY = (-0.30, -0.47, 1.86)
READY_R = ("blade", (0.05, -0.55, 1.0), (1.0, 0.0, 0.0))


def reins_one_hand(n, extra=None):
    keys = [(0, GL, "rein", 0.85), (6, REINS_ONE, "rein", 0.95), (n - 1, REINS_ONE, "rein", 0.95)]
    return htrack("l", keys)


@clip("Horse_Ride_Sword_Idle")
def c_sword_idle():
    n = 61
    br = lambda f: math.sin(TAU_ * f / (n - 1))
    hr = lambda f, P, sh: (V(*READY) + V(0.0, 0.0, 0.01 * br(f)), R_of("r", READY_R), 1.0)
    hl = lambda f, P, sh: (V(*REINS_ONE), rein_rot("l"), 0.95)
    g = dict(hand_r=hr, hand_l=hl, lean=lambda f: 10.0 + 0.8 * br(f), c_yaw=-6.0, h_yaw=lambda f: 4.0 * math.sin(TAU_ * f / (n - 1) + 1.0),
             elbow_out=0.7)
    return rest_build(n, g), bmeta(loop=True, ev={}, weapon="sword_r")


TAU_ = 2 * math.pi


def sword_swing(side):
    """anticipation (slow coil / windup 0-10), fast strike 11-15 (hit 14), follow-through 15-21, recover to the ready pose by 36."""
    n = 37
    sg = 1.0 if side == "L" else -1.0     # L: backhand cut to the rider's left (across the neck), R: forehand cut to the right side
    if side == "R":
        keys = [(0, READY, READY_R, 1.0),
                (4, (-0.22, -0.38, 1.98), ("blade", (0.1, 0.2, 1.0), (1.0, 0.0, 0.0)), 1.0),
                (10, (0.02, -0.12, 2.36), ("blade", (0.35, 0.8, 0.3), (0.2, -0.3, -1.0)), 1.0),
                (12, (-0.30, -0.42, 2.18), ("blade", (-0.6, -0.5, 0.6), (0.0, 0.3, -1.0)), 1.0),
                (14, (-0.52, -0.44, 1.80), ("blade", (-0.8, -0.3, -0.5), (0.3, 0.3, -1.0)), 1.0),
                (16, (-0.50, -0.28, 1.58), ("blade", (-0.5, 0.4, -0.75), (0.6, 0.2, -0.8)), 1.0),
                (21, (-0.44, -0.28, 1.62), ("blade", (-0.2, 0.85, -0.5), (0.7, 0.0, -0.7)), 1.0),
                (26, (-0.34, -0.38, 1.74), ("blade", (-0.1, 0.4, 0.9), (1.0, 0.0, 0.0)), 1.0),
                (36, READY, READY_R, 1.0)]
        yaw = T1([(0, -6), (4, 4), (10, 30), (12, 8), (14, -30), (16, -38), (21, -40), (26, -26), (36, -6)])
        roll = T1([(0, 0), (10, 5), (14, -10), (21, -12), (28, -3), (36, 0)])
        lean = T1([(0, 10), (10, 2), (14, 16), (21, 20), (28, 12), (36, 10)])
    else:
        keys = [(0, READY, READY_R, 1.0),
                (4, (-0.34, -0.36, 1.98), ("blade", (-0.2, 0.2, 1.0), (1.0, 0.0, 0.0)), 1.0),
                (10, (-0.40, -0.08, 2.32), ("blade", (-0.3, 0.7, 0.65), (1.0, 0.2, -0.2)), 1.0),
                (12, (-0.12, -0.52, 2.18), ("blade", (0.7, -0.5, 0.5), (0.0, 0.3, -1.0)), 1.0),
                (14, (0.22, -0.60, 1.88), ("blade", (0.85, -0.3, -0.4), (-0.3, 0.3, -1.0)), 1.0),
                (16, (0.30, -0.50, 1.66), ("blade", (0.6, 0.3, -0.75), (-0.6, 0.1, -0.8)), 1.0),
                (21, (0.24, -0.30, 1.58), ("blade", (0.3, 0.8, -0.5), (-0.7, 0.0, -0.7)), 1.0),
                (27, (-0.12, -0.46, 1.72), ("blade", (0.0, -0.4, 1.0), (1.0, 0.0, 0.0)), 1.0),
                (36, READY, READY_R, 1.0)]
        yaw = T1([(0, -6), (4, -14), (10, -36), (12, -12), (14, 26), (16, 36), (21, 42), (27, 14), (36, -6)])
        roll = T1([(0, 0), (10, -5), (14, 9), (21, 11), (28, 2), (36, 0)])
        lean = T1([(0, 10), (10, 3), (14, 18), (21, 17), (28, 11), (36, 10)])
    hit = 14
    g = dict(hand_r=htrack("r", keys), hand_l=lambda f, P, sh: (V(*REINS_ONE), rein_rot("l"), 0.95), c_yaw=yaw, c_roll=roll, lean=lean,
             h_yaw=lambda f: 0.6 * yaw(f) + 14.0 * sg * pulse(f, 6, 12, 26), h_pitch=lambda f: 5.0 + 6.0 * pulse(f, 11, 14, 26),
             shrug=lambda f: 8.0 * pulse(f, 4, 10, 13), elbow_out=1.0, elbow_back=0.2, elbow_down=0.4)
    return rest_build(n, g), bmeta(ev={"windup": 10, "hit": hit, "follow_through": 21, "recover": 27}, weapon="sword_r",
                                   notes="starts/ends on Horse_Ride_Sword_Idle; reins in the left hand; blade = thumb direction")


@clip("Horse_Ride_Sword_Swing_L")
def c_sw_l():
    return sword_swing("L")


@clip("Horse_Ride_Sword_Swing_R")
def c_sw_r():
    return sword_swing("R")


# ------------------------------------------------------------------ bow (left hand bow, right hand draws; reins dropped on the neck)
AIM = V(math.sin(math.radians(70)), -math.cos(math.radians(70)), 0.03).normalized()       # 70 deg to the left of forward
RIGHT_OF_AIM = AIM.cross(V(0, 0, 1)).normalized()
ANCHOR = V(0.036, -0.30, 2.30)
BOW = ANCHOR + AIM * 0.70
BOW_R = ("blade", (0.08, 0.0, 1.0), tuple(RIGHT_OF_AIM))
DRAW_R = ("hand", tuple(AIM), tuple(-RIGHT_OF_AIM + V(0, 0, -0.3)))
AIM_YAW = 70.0


def bow_upper(f_turn0, f_turn1, back=False):
    w = (lambda f: 1.0 - pulse(f, f_turn0, f_turn1)) if back else (lambda f: pulse(f, f_turn0, f_turn1))
    return dict(c_yaw=lambda f: -20.0 * w(f), h_yaw=lambda f: AIM_YAW * w(f), lean=lambda f: 8.0 - 4.0 * w(f),
                h_pitch=lambda f: 5.0 - 5.0 * w(f), h_roll=lambda f: 6.0 * w(f), clav_l=lambda f: 6.0 - 4.0 * w(f))


def aim_hands(f, sway=0.0):
    s = V(0, 0, 0.004 * sway) + RIGHT_OF_AIM * 0.004 * sway
    return (lambda f_, P, sh: (BOW + s, R_of("l", BOW_R), 1.0)), (lambda f_, P, sh: (ANCHOR + s * 0.5, R_of("r", DRAW_R), 0.75))


@clip("Horse_Ride_Bow_Draw")
def c_bow_draw():
    n = 31
    hl = htrack("l", [(0, GL, "rein", 0.85), (5, (0.12, -0.55, 1.80), BOW_R, 1.0), (12, tuple(BOW * 0.7 + V(0.12, -0.55, 1.80) * 0.3), BOW_R, 1.0),
                      (18, tuple(BOW), BOW_R, 1.0), (30, tuple(BOW), BOW_R, 1.0)])
    nock = BOW - AIM * 0.12
    hr = htrack("r", [(0, GR, "rein", 0.85), (6, (-0.12, -0.45, 1.85), ("hand", (0.2, -0.6, -0.4), (0.8, 0.0, -0.4)), 0.6),
                      (14, tuple(nock), DRAW_R, 0.75), (17, tuple(nock), DRAW_R, 0.75), (26, tuple(ANCHOR), DRAW_R, 0.75),
                      (30, tuple(ANCHOR), DRAW_R, 0.75)])
    g = bow_upper(4, 18)
    g.update(hand_l=hl, hand_r=hr, elbow_out=0.8, elbow_back=0.7, elbow_down=0.2)
    return rest_build(n, g), bmeta(ev={"drop_reins": 4, "nock": 15, "full_draw": 26}, weapon="bow_l",
                                   notes="aim 70 deg to the left of forward, slightly up; ends on Horse_Ride_Bow_Aim frame 0",
                                   aim_dir_clip=[round(x, 3) for x in AIM])


@clip("Horse_Ride_Bow_Aim")
def c_bow_aim():
    n = 41
    g = bow_upper(-10, -5)
    g.update(elbow_out=0.8, elbow_back=0.7, elbow_down=0.2)
    g["hand_l"] = lambda f, P, sh: (BOW + V(0, 0, 0.004 * math.sin(TAU_ * f / (n - 1))), R_of("l", BOW_R), 1.0)
    g["hand_r"] = lambda f, P, sh: (ANCHOR + V(0, 0, 0.003 * math.sin(TAU_ * f / (n - 1))), R_of("r", DRAW_R), 0.75)
    g["lean"] = lambda f: 4.0 + 0.6 * math.sin(TAU_ * f / (n - 1))
    return rest_build(n, g), bmeta(loop=True, weapon="bow_l", aim_dir_clip=[round(x, 3) for x in AIM])


@clip("Horse_Ride_Bow_Release")
def c_bow_release():
    n = 37
    rel = ANCHOR - AIM * 0.12 + RIGHT_OF_AIM * 0.10 + V(0, 0, 0.03)
    hr = htrack("r", [(0, tuple(ANCHOR), DRAW_R, 0.75), (2, tuple(ANCHOR), DRAW_R, 0.75), (5, tuple(rel), DRAW_R, 0.3), (13, tuple(rel), DRAW_R, 0.3),
                      (26, (-0.12, -0.45, 1.80), ("hand", (0.2, -0.6, -0.4), (0.8, 0.0, -0.4)), 0.6), (36, GR, "rein", 0.85)])
    hl = htrack("l", [(0, tuple(BOW), BOW_R, 1.0), (2, tuple(BOW), BOW_R, 1.0), (6, tuple(BOW + AIM * 0.02 - V(0, 0, 0.03)), BOW_R, 1.0),
                      (14, tuple(BOW + AIM * 0.02 - V(0, 0, 0.03)), BOW_R, 1.0), (27, (0.14, -0.55, 1.80), BOW_R, 1.0), (36, GL, "rein", 0.85)])
    g = bow_upper(14, 32, back=True)
    g.update(hand_l=hl, hand_r=hr, elbow_out=0.8, elbow_back=0.7, elbow_down=0.2)
    return rest_build(n, g), bmeta(ev={"release": 2, "reins": 36}, weapon="bow_l", hands_on_grips=[[36, 36]])


# ------------------------------------------------------------------ rider hit while mounted (stays seated)
def hit_react(sg):
    n = 25
    j = lambda f: 0.0 if f < 1 else math.exp(-(f - 1) / 5.0) * math.sin((f - 1) * 0.38 + 0.5) / math.sin(0.88)
    g = dict(c_roll=lambda f: -13.0 * sg * j(f), c_yaw=lambda f: -9.0 * sg * j(f), lean=lambda f: 8.0 - 7.0 * j(f),
             h_roll=lambda f: -10.0 * sg * j(f), h_yaw=lambda f: -16.0 * sg * j(f), h_pitch=lambda f: 5.0 - 8.0 * j(f),
             shrug=lambda f: 7.0 * j(f), grip=lambda f: 0.85 + 0.15 * pulse(f, 0, 2, 16))
    return rest_build(n, g), bmeta(ev={"hit": 1}, hands_on_grips=True)


@clip("Horse_Ride_Hit_React_L")
def c_hr_l():
    return hit_react(1.0)


@clip("Horse_Ride_Hit_React_R")
def c_hr_r():
    return hit_react(-1.0)
