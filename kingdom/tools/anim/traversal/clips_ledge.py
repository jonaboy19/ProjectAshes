# Ledge helper clips (grab, climb up, drop down). Part of author_traversal_v2.py.
# Geometry (same contract as clips_climb.py): ledge top z = 2.12, front face y = -0.20 (ledge box y -0.9..-0.2), the character starts in
# front of the face (root at the origin, faces -Y). The hang pose is the first frame of Ledge_Hang_Idle_Loop (hang_pose(0)).
# Hands are IK targets on the ledge top (world-fixed while gripping), feet are world-fixed while planted.
from trav_lib import *
from clips_climb import hang_pose, LEDGE_TOP, LEDGE_FACE, ledge_hands, TAU

HX = 0.21                                           # hand x on the ledge
HAND_Y = -0.27
TOPZ = LEDGE_TOP
BOX = ((-3.0, 3.0), (-0.9, LEDGE_FACE), (-1.0, LEDGE_TOP))     # the ledge block (penetration check)


def hand_on_ledge(sx, dz=0.0, dy=0.0, dx=0.0, grip=0.15, palm_dy=0.0):
    G = V(sx * HX + dx, HAND_Y + dy, TOPZ + 0.02 + dz)
    return (G, V(0, -1.0, -0.05), V(0, palm_dy, -1.0), grip)


CONTACTS["Ledge_Grab"] = [["hand_l", 15, 40], ["hand_r", 15, 40]]
CONTACTS["Ledge_Climb_Up"] = [["hand_l", 0, 28], ["hand_r", 0, 28], ["ball_r", 28, 52], ["ball_l", 41, 52]]
CONTACTS["Ledge_Drop_Down"] = [["hand_l", 0, 6], ["hand_r", 0, 6], ["ball_l", 11, 32], ["ball_r", 11, 32]]
EVENTS["Ledge_Grab"] = {"crouch_low": 8, "toe_off": 12, "hands_contact": 15, "pendulum_peak": 19, "settled_hang": 34, "chain_to_hang_idle": 40}
EVENTS["Ledge_Climb_Up"] = {"pull_start": 7, "chin_over_ledge": 17, "chest_over_lip": 24, "foot_on_ledge": 28, "hands_release": 29, "left_foot_up": 41, "stand": 46, "settled": 52}
EVENTS["Ledge_Drop_Down"] = {"release": 6, "touch_down": 11, "absorb_low_point": 15, "settled": 28}


# ------------------------------------------------------------------ Ledge_Grab
def grab_swing_pose(f):
    """jump from the floor, catch the ledge top with both hands (contact f14), swing / settle. Standing start, hang at the end."""
    P = Pose()
    z = Trk([(0, 0.895), (3, 0.86), (6, 0.74), (8, 0.68), (9, 0.70), (10, 0.78), (11, 0.90), (12, 1.02), (13, 1.14), (14, 1.25), (15, 1.30),
             (16, 1.30), (17, 1.27), (19, 1.19), (21, 1.14), (23, 1.135), (26, 1.14), (29, 1.13), (34, 1.125)])(f)
    y = Trk([(0, 0.20), (4, 0.22), (8, 0.30), (12, 0.18), (14, 0.10), (15, 0.06), (18, 0.08), (21, 0.02), (24, -0.02), (28, -0.02), (34, -0.02)])(f)
    x = Trk([(0, 0.0), (34, 0.0, "s")])(f)
    P.pelvis = V(x, y, z)
    # arms: hang -> swing back (anticipation) -> throw up over the ledge -> slap on the top
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        hk = Trk([(0, V(sx * 0.26, 0.21, 0.83)), (4, V(sx * 0.27, 0.31, 0.82)), (7, V(sx * 0.27, 0.44, 0.80)), (9, V(sx * 0.32, 0.30, 0.95)),
                  (10, V(sx * 0.38, 0.0, 1.10)), (11, V(sx * 0.36, -0.25, 1.38)), (12, V(sx * 0.32, -0.34, 1.72)), (13, V(sx * 0.26, -0.32, 2.02)), (14, V(sx * 0.22, -0.27, 2.20)),
                  (15, V(sx * HX, HAND_Y, TOPZ + 0.02)), (40, V(sx * HX, HAND_Y, TOPZ + 0.02))])
        g = hk(f)
        c = smooth((f - 8.0) / 5.0)                       # arms straighten / palms turn down while swinging up
        c2 = smooth((f - 12.5) / 2.5)
        d, pn = V(0, -1.0, 0), V(0, 0, -1.0)
        HR = hand_stages(side, [(V(0.06 * sx, -0.10, -1.0), V(-1.0 * sx, 0.0, -0.1)), (V(0.0, -0.35, 1.0), V(0, -1.0, 0.2)), (V(0, -1.0, -0.05), V(0, 0, -1.0))], [c, c2])
        grip = lerp(0.35, 0.05, c) if f < 15 else lerp(0.05, 0.55, smooth((f - 15) / 3.0))
        hands[side] = (g, d, pn, grip, HR)
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        fk = Trk([(0, V(sx * 0.11, 0.15, ZB0)), (11, V(sx * 0.11, 0.15, ZB0)), (12, V(sx * 0.11, 0.14, 0.10)), (13, V(sx * 0.11, 0.12, 0.30)),
                  (14, V(sx * 0.11, 0.10, 0.48)), (15, V(sx * 0.11, 0.10, 0.58)), (18, V(sx * 0.11, 0.10, 0.40)), (21, V(sx * 0.10, 0.14, 0.26)),
                  (24, V(sx * 0.10, 0.10, 0.21)), (28, V(sx * 0.10, 0.11, 0.20))])
        pk = Trk([(0, 0.0), (10, 0.0), (12, 55.0), (14, 45.0), (18, 35.0), (23, 40.0), (28, 40.0)])
        feet[side] = (fk(f), sx * 6.0, pk(f), 0.0)
    kd = Trk([(0, V(0.15, -1.0, 0.1)), (10, V(0.15, -1.0, 0.1)), (14, V(0.55, -0.6, 0.6)), (17, V(0.55, -0.6, 0.6)), (23, V(0.15, -1.0, 0.1))])(f)
    ed = Trk([(0, V(1.0, 0.3, -0.1)), (8, V(0.9, 0.5, -0.3)), (10, V(0.6, 0.6, -0.7)), (13, V(0.7, 0.4, -0.5)), (15, V(1.0, 0.3, -0.1))])(f)
    set_limbs(P, hands, feet, {"l": V(kd.x, kd.y, kd.z), "r": V(-kd.x, kd.y, kd.z)},
              {"l": V(ed.x, ed.y, ed.z), "r": V(-ed.x, ed.y, ed.z)})
    sp = Trk([(0, V(1.0, 0, 0)), (8, V(20.0, 0, 0)), (11, V(10.0, 0, 0)), (13, V(-8.0, 0, 0)), (15, V(-12.0, 0, 0)), (18, V(-4.0, 0, 0)),
              (23, V(-5.0, 0, 0)), (28, V(-4.0, 0, 0))])(f)
    pl = Trk([(0, V(0, 0, 0)), (8, V(10.0, 0, 0)), (12, V(0, 0, 0)), (28, V(0, 0, 0))])(f)
    hd = Trk([(0, V(-22.0, 0, 0)), (8, V(-38.0, 0, 0)), (13, V(-28.0, 0, 0)), (17, V(-18.0, 0, 0)), (28, V(-16.0, 0, 0))])(f)
    set_torso(P, (pl.x, pl.y, pl.z), (sp.x, sp.y, sp.z), (hd.x, hd.y, hd.z))
    return P


@clip
def Ledge_Grab():
    n = 40
    poses = []
    for f in range(n + 1):
        S = grab_swing_pose(min(f, 34))
        I = hang_pose(((f - n) / 60.0) % 1.0)       # ends exactly on frame 0 of Ledge_Hang_Idle_Loop
        poses.append(blend_pose(S, I, smooth((f - 24.0) / (n - 24.0))))
    return poses, False


# ------------------------------------------------------------------ Ledge_Climb_Up
FOOT_TOP = V(0.0, 0.0, TOPZ + ZB0)


def climb_root(f):
    """capsule path: from the floor below the hang to the standing point on the ledge top (0.5 m forward, ledge top 2.12 m up)"""
    t = smooth((f - 12.0) / 34.0)
    return V(0.0, -0.50 * smooth((f - 24.0) / 22.0), TOPZ * t)


def climb_pose(f):
    P = Pose()
    top = TOPZ
    pz = Trk([(0, 1.125), (4, 1.10), (7, 1.20), (11, 1.42), (14, 1.62), (17, 1.80), (20, 1.92), (23, 2.00), (26, 2.10), (30, 2.36), (34, 2.62),
              (38, 2.82), (42, 2.96), (46, top + 0.905), (52, top + 0.90)])(f)
    py = Trk([(0, -0.02), (4, -0.03), (8, 0.08), (14, 0.15), (20, 0.16), (24, 0.10), (28, 0.0), (32, -0.16), (36, -0.30), (40, -0.42),
              (44, -0.50), (48, -0.50), (52, -0.50)])(f)
    px = Trk([(0, 0.006), (4, 0.0), (28, 0.0), (34, -0.05), (40, -0.03), (46, 0.0), (52, 0.0)])(f)
    P.pelvis = V(px, py, pz)
    P.root = climb_root(f)
    # ---- hands: fixed on the ledge until the push (lift at 33), then swing to the sides of the body
    pushing = smooth((f - 28.0) / 5.0)
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        base = V(sx * HX, HAND_Y, top + 0.02)
        if f <= 28:
            g = base
            d, pn, grip = V(0, -1.0, -0.05), V(0, 0, -1.0), 0.15 + 0.35 * smooth((f - 3.0) / 8.0)
            HR = None
        else:
            stand_hand = V(sx * 0.27, -0.45, top + 0.84)
            g = Trk([(28, base), (31, base + V(sx * 0.02, -0.04, 0.12)), (36, V(sx * 0.30, -0.36, top + 0.80)), (41, V(sx * 0.30, -0.42, top + 1.00)), (48, stand_hand), (52, stand_hand)])(f)
            d, pn = V(0, -1.0, 0), V(0, 0, -1.0)
            HR = hand_stages(side, [(V(0, -1.0, -0.05), V(0, 0, -1.0)), (V(0.06 * sx, -0.10, -1.0), V(-1.0 * sx, 0.0, -0.1))], [pushing])
            grip = lerp(0.5, 0.35, pushing)
        hands[side] = (g, d, pn, grip) if HR is None else (g, d, pn, grip, HR)
    # ---- feet: legs swing for momentum, scramble against the wall, the right foot goes up onto the ledge (plant 27), the left follows (plant 41)
    lk = Trk([(0, V(0.10, 0.10, 0.20)), (3, V(0.10, 0.24, 0.30)), (7, V(0.10, 0.02, 0.44)), (11, V(0.10, 0.04, 0.72)), (16, V(0.12, 0.02, 1.00)),
              (22, V(0.12, 0.0, 1.30)), (28, V(0.12, -0.02, 1.62)), (34, V(0.12, -0.16, 2.02)), (38, V(0.12, -0.40, 2.30)),
              (40, V(0.10, -0.55, top + 0.22)), (41, V(0.10, -0.58, top + ZB0)), (60, V(0.10, -0.58, top + ZB0, ))])
    rk = Trk([(0, V(-0.10, 0.10, 0.20)), (3, V(-0.10, 0.20, 0.34)), (7, V(-0.10, 0.06, 0.60)), (11, V(-0.14, 0.04, 1.00)), (15, V(-0.20, 0.03, 1.40)),
              (18, V(-0.28, 0.02, 1.70)), (20, V(-0.34, -0.02, 1.95)), (22, V(-0.36, -0.12, 2.26)), (25, V(-0.30, -0.40, 2.32)), (27, V(-0.18, -0.52, top + 0.03)),
              (28, V(-0.12, -0.54, top + ZB0)), (60, V(-0.12, -0.54, top + ZB0))])
    lp = Trk([(0, 40.0), (7, 20.0), (16, -20.0), (30, -30.0), (38, 20.0), (41, 0.0), (60, 0.0)])
    rp = Trk([(0, 40.0), (7, 20.0), (14, -20.0), (20, -20.0), (24, 15.0), (28, 0.0), (60, 0.0)])
    feet = {"l": (lk(f), 6.0, lp(f), 0.0), "r": (rk(f), -6.0, rp(f), 0.0)}
    kl = Trk([(0, V(0.15, -1.0, 0.1)), (6, V(0.4, -0.7, 0.5)), (12, V(0.6, -0.5, 0.6)), (24, V(0.6, -0.5, 0.6)), (34, V(0.30, -0.8, 0.7)), (42, V(0.2, -1.0, 0.2)), (52, V(0.15, -1.0, 0.1))])(f)
    kr = Trk([(0, V(-0.15, -1.0, 0.1)), (6, V(-0.4, -0.7, 0.5)), (12, V(-0.6, -0.5, 0.6)), (18, V(-0.6, -0.4, 0.9)), (23, V(-0.5, -0.3, 1.1)), (27, V(-0.55, -0.5, 0.9)), (34, V(-0.35, -0.9, 0.3)),
              (42, V(-0.2, -1.0, 0.2)), (52, V(-0.15, -1.0, 0.1))])(f)
    # ---- elbows: out at the start, fold back behind the body while pulling, straight again at the end
    ed = Trk([(0, V(1.0, 0.3, -0.1)), (7, V(0.9, 0.5, -0.3)), (14, V(0.7, 0.9, -0.5)), (24, V(0.5, 0.9, -0.5)), (32, V(0.6, 0.9, -0.4)),
              (40, V(0.6, 0.9, -0.3)), (48, V(0.7, 0.9, -0.2))])(f)
    set_limbs(P, hands, feet, {"l": V(kl.x, kl.y, kl.z), "r": V(kr.x, kr.y, kr.z)}, {"l": V(ed.x, ed.y, ed.z), "r": V(-ed.x, ed.y, ed.z)})
    # ---- torso: arch back for the swing, curl over the lip (chest forward), then straighten to stand
    sp = Trk([(0, V(-4.0, 0, 0)), (4, V(-12.0, 0, 0)), (9, V(-2.0, 0, 0)), (14, V(6.0, 0, 0)), (20, V(30.0, 0, 0)), (26, V(48.0, 0, 0)), (32, V(50.0, 0, 0)),
              (38, V(32.0, 0, 0)), (44, V(8.0, 0, 0)), (52, V(1.0, 0, 0))])(f)
    pl = Trk([(0, V(0, 0, 0)), (14, V(6.0, 0, 0)), (26, V(18.0, 0, 0)), (34, V(14.0, 0, 0)), (44, V(2.0, 0, 0)), (52, V(0, 0, 0))])(f)
    hd = Trk([(0, V(-16.0, 0, 0)), (14, V(-30.0, 0, 0)), (24, V(-48.0, 0, 0)), (32, V(-45.0, 0, 0)), (40, V(-28.0, 0, 0)), (48, V(-8.0, 0, 0)), (52, V(-3.0, 0, 0))])(f)
    set_torso(P, (pl.x, pl.y, pl.z), (sp.x, sp.y, sp.z), (hd.x, hd.y, hd.z))
    return P


@clip
def Ledge_Climb_Up():
    n = 52
    poses = []
    for f in range(n + 1):
        P = climb_pose(f)
        if f <= 3:                                  # chain from the hang: same pose as Ledge_Hang_Idle frame 0, blended out
            P = blend_pose(hang_pose(0.0), P, smooth(f / 3.0))
            P.root = climb_root(f)
        poses.append(P)
    return poses, False


# ------------------------------------------------------------------ Ledge_Drop_Down
def drop_pose(f):
    """release from the hang (f6), push away from the wall, fall 0.2 m, land absorbing (touch-down f11), settle into a stand"""
    P = Pose()
    R = Trk([(0, V(0, 0, 0)), (6, V(0, 0, 0)), (11, V(0, 0.34, 0)), (16, V(0, 0.36, 0)), (20, V(0, 0.36, 0, ))])(f)
    P.root = R
    pz = Trk([(0, 1.125), (3, 1.14), (6, 1.145), (8, 1.05), (10, 0.93), (11, 0.86), (13, 0.74), (15, 0.72), (18, 0.79), (22, 0.86), (28, 0.895), (32, 0.895)])(f)
    py = Trk([(0, -0.02), (5, -0.04), (8, 0.02), (11, 0.24), (14, 0.30), (18, 0.32), (24, 0.32), (32, 0.33)])(f)
    P.pelvis = V(0.0, py, pz)
    rel = smooth((f - 6.0) / 2.0)                    # hands leave the ledge
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        base = V(sx * HX, HAND_Y, TOPZ + 0.02)
        lk = Trk([(6, base), (7, V(sx * 0.24, -0.22, 2.08)), (9, V(sx * 0.30, -0.12, 1.90)), (11, V(sx * 0.34, 0.05, 1.55)), (14, V(sx * 0.42, 0.34, 1.05)), (17, V(sx * 0.36, 0.30, 0.90)),
                  (22, V(sx * 0.30, 0.42, 0.98)), (28, V(sx * 0.27, 0.40, 0.86)), (32, V(sx * 0.27, 0.40, 0.84))])
        if f < 6:
            g, d, pn, grip = base, V(0, -1.0, -0.05), V(0, 0, -1.0), 0.15
            HR = None
        else:
            g = lk(f)
            d, pn = V(0, -1.0, 0), V(0, 0, -1.0)
            HR = hand_stages(side, [(V(0, -1.0, -0.05), V(0, 0, -1.0)), (V(0.06 * sx, -0.10, -1.0), V(-1.0 * sx, 0.0, -0.1))], [rel])
            grip = lerp(0.15, 0.4, rel)
        hands[side] = (g, d, pn, grip) if HR is None else (g, d, pn, grip, HR)
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        fk = Trk([(0, V(sx * 0.10, 0.10, 0.20)), (5, V(sx * 0.10, 0.12, 0.22)), (8, V(sx * 0.10, 0.20, 0.30)), (10, V(sx * 0.11, 0.30, 0.12)),
                  (11, V(sx * 0.11, 0.34, ZB0)), (32, V(sx * 0.11, 0.34, ZB0))])
        pk = Trk([(0, 40.0), (8, 40.0), (10, 15.0), (11, 0.0), (32, 0.0)])
        feet[side] = (fk(f), sx * 6.0, pk(f), 0.0)
    kd = Trk([(0, V(0.15, -1.0, 0.1)), (11, V(0.15, -1.0, 0.1)), (14, V(0.30, -1.0, 0.2)), (22, V(0.18, -1.0, 0.1))])(f)
    ed = Trk([(0, V(1.0, 0.3, -0.1)), (11, V(0.9, 0.4, -0.2)), (16, V(0.6, 0.8, -0.4)), (32, V(0.7, 0.9, -0.2))])(f)
    set_limbs(P, hands, feet, {"l": V(kd.x, kd.y, kd.z), "r": V(-kd.x, kd.y, kd.z)}, {"l": V(ed.x, ed.y, ed.z), "r": V(-ed.x, ed.y, ed.z)})
    sp = Trk([(0, V(-4.0, 0, 0)), (6, V(-6.0, 0, 0)), (10, V(4.0, 0, 0)), (14, V(24.0, 0, 0)), (18, V(14.0, 0, 0)), (24, V(4.0, 0, 0)), (32, V(1.0, 0, 0))])(f)
    pl = Trk([(0, V(0, 0, 0)), (11, V(0, 0, 0)), (14, V(12.0, 0, 0)), (20, V(3.0, 0, 0)), (32, V(0, 0, 0))])(f)
    hd = Trk([(0, V(-16.0, 0, 0)), (8, V(-10.0, 0, 0)), (14, V(-24.0, 0, 0)), (22, V(-8.0, 0, 0)), (32, V(-3.0, 0, 0))])(f)
    set_torso(P, (pl.x, pl.y, pl.z), (sp.x, sp.y, sp.z), (hd.x, hd.y, hd.z))
    return P


@clip
def Ledge_Drop_Down():
    n = 32
    poses = []
    for f in range(n + 1):
        P = drop_pose(f)
        if f <= 3:
            P = blend_pose(hang_pose(0.0), P, smooth(f / 3.0))
            P.root = drop_pose(f).root
        poses.append(P)
    return poses, False
