# Mantle clips over a wall (Mantle_Low 1.0 m, Mantle_High 1.8 m). Part of author_traversal_v2.py.
# Geometry: character faces -Y, starts at the origin. Low wall: box x +-1.0, y -1.6..-0.85, top z = 1.0. High wall: box x +-1.2, y -1.5..-0.6, top z = 1.8.
# Root motion: yes. Low: y -1.27, z +1.0 (the standing point on the wall top); High: y -0.9, z +1.8 (same choreography as Ledge_Climb_Up shifted onto the
# 1.8 m wall). Hands / feet are world-fixed IK targets during contacts.
from trav_lib import *
import clips_ledge as LG

LOW_TOP, LOW_FACE = 1.0, -0.85
HIGH_TOP, HIGH_FACE = 1.8, -0.60
BOXES = {"Mantle_Low": ((-1.0, 1.0), (-1.6, LOW_FACE), (0.0, LOW_TOP)),
         "Mantle_High": ((-1.2, 1.2), (-1.5, HIGH_FACE), (0.0, HIGH_TOP))}


def shift_pose(P, dy, dz, floor_ankle=0.105):
    """translate a whole pose (pelvis, all IK targets) by (0, dy, dz); ankles are kept above the floor"""
    s = V(0, dy, dz)
    P.pelvis = P.pelvis + s
    for k in list(P.t):
        P.t[k] = P.t[k] + s
        if k.startswith("foot_") and P.t[k].z < floor_ankle:
            P.t[k].z = floor_ankle
    return P


# ------------------------------------------------------------------ Mantle_Low
def low_pose(f):
    top = LOW_TOP
    P = Pose()
    st = stand_pose(V(0.0, -1.27, top))                       # the end pose
    y = Trk([(0, 0.03), (3, -0.15), (6, -0.36), (10, -0.58), (14, -0.72), (18, -0.82), (22, -0.93), (26, -1.02), (30, -1.08),
             (34, -1.18), (38, -1.235), (40, st.pelvis.y)])(f)
    z = Trk([(0, 0.875), (3, 0.865), (6, 0.85), (8, 0.80), (10, 0.84), (13, 0.92), (16, 1.02), (19, 1.12), (22, 1.26), (24, 1.36), (27, 1.55),
             (30, 1.72), (33, 1.83), (36, 1.885), (40, st.pelvis.z)])(f)
    x = Trk([(0, 0.0), (10, 0.0), (20, 0.06), (30, 0.04), (40, 0.0)])(f)
    P.pelvis = V(x, y, z)
    P.root = V(0, -1.27 * smooth(f / 36.0), top * smooth((f - 12.0) / 24.0))
    # ---- hands: run arms, reach for the top (contact 12), pressed flat until 23, then swing down to the sides
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        base = V(sx * 0.17, -1.03, top + 0.02)
        if side == "l":
            pre = [(0, V(0.27, -0.25, 1.05)), (4, V(0.30, -0.15, 0.95)), (8, V(0.32, -0.40, 0.92)), (11, V(0.24, -0.90, 1.08)), (12, base)]
        else:
            pre = [(0, V(-0.27, 0.15, 0.95)), (4, V(-0.30, -0.25, 1.00)), (8, V(-0.32, -0.55, 0.95)), (11, V(-0.22, -0.96, 1.08)), (12, base)]
        post = [(19, base), (22, V(sx * 0.26, -1.10, top + 0.25)), (29, V(sx * 0.30, -1.18, top + 0.55)), (36, V(sx * 0.28, -1.22, top + 0.80)),
                (40, V(sx * 0.27, -1.22, top + 0.80))]
        g = Trk(pre + post)(f)
        hp = smooth((f - 10.0) / 2.0) * (1.0 - smooth((f - 19.0) / 3.0))      # 1 while gripping the wall top
        rel = smooth((f - 19.0) / 8.0)
        d0 = V(0.15 * sx, -1.0, -0.15)
        d = d0.lerp(V(0, -1.0, -0.05), hp).lerp(V(0.06 * sx, -0.10, -1.0), rel)
        pn = V(0, 0, -1.0)
        HR = hand_stages(side, [(d0, V(0, 0.2, -1.0)), (V(0, -1.0, -0.05), V(0, 0, -1.0)), (V(0.06 * sx, -0.10, -1.0), V(-1.0 * sx, 0.0, -0.1))], [smooth((f - 10.0) / 2.0), rel])
        grip = lerp(0.6, 0.05, hp) if f < 30 else 0.35
        hands[side] = (g, d, pn, grip, HR)
    # ---- feet: L lands 4 (near step), R lands 10 (plant in front of the wall = pivot), L drives up over the top (plant 23), R follows (plant 36)
    lk = Trk([(0, V(0.10, -0.30, 0.22)), (2, V(0.10, -0.40, 0.10)), (4, V(0.10, -0.44, ZB0)), (9, V(0.10, -0.44, ZB0)), (12, V(0.11, -0.58, 0.30)),
              (14, V(0.14, -0.68, 0.66)), (16, V(0.18, -0.80, 1.02)), (17, V(0.20, -0.88, 1.16)), (18, V(0.24, -0.98, 1.26)), (20, V(0.30, -1.08, 1.17)), (22, V(0.30, -1.12, top + 0.05)),
              (23, V(0.30, -1.12, top + ZB0)), (37, V(0.30, -1.12, top + ZB0)), (39, V(0.20, -1.22, top + 0.05)), (41, V(0.11, -1.32, top + ZB0)), (60, V(0.11, -1.32, top + ZB0))])
    rk = Trk([(0, V(-0.10, 0.12, ZB0)), (2, V(-0.10, 0.12, ZB0)), (3, V(-0.10, 0.10, 0.05)), (4, V(-0.10, 0.06, 0.08)), (6, V(-0.10, -0.25, 0.28)), (8, V(-0.10, -0.52, 0.15)),
              (10, V(-0.10, -0.66, ZB0)), (14, V(-0.10, -0.66, ZB0)), (16, V(-0.10, -0.68, 0.20)), (19, V(-0.10, -0.72, 0.50)), (23, V(-0.10, -0.74, 0.72)), (27, V(-0.10, -0.80, 0.95)), (30, V(-0.10, -0.92, top + 0.20)), (32, V(-0.10, -0.98, top + 0.35)), (34, V(-0.10, -1.15, top + 0.12)),
              (36, V(-0.11, -1.22, top + ZB0)), (60, V(-0.11, -1.22, top + ZB0))])
    lp = Trk([(0, 25.0), (3, 10.0), (4, 0.0), (9, 0.0), (12, 40.0), (16, 30.0), (20, 15.0), (23, 0.0), (37, 0.0), (39, 20.0), (41, 0.0), (60, 0.0)])
    rp = Trk([(0, 0.0), (3, 0.0), (4, 40.0), (6, 20.0), (8, 10.0), (10, 0.0), (14, 0.0), (16, 30.0), (30, 40.0), (34, 20.0), (36, 0.0), (60, 0.0)])
    feet = {"l": (lk(f), 6.0, lp(f), 0.0), "r": (rk(f), -6.0, rp(f), 0.0)}
    kl = Trk([(0, V(0.15, -1.0, 0.1)), (10, V(0.15, -1.0, 0.1)), (14, V(0.7, -0.3, 0.8)), (18, V(0.8, -0.2, 0.8)), (23, V(0.40, -0.9, 0.5)),
              (30, V(0.20, -1.0, 0.3)), (40, V(0.15, -1.0, 0.1))])(f)
    kr = Trk([(0, V(-0.15, -1.0, 0.1)), (10, V(-0.15, -1.0, 0.2)), (16, V(-0.5, -0.5, 0.6)), (26, V(-0.7, -0.3, 0.7)), (32, V(-0.30, -0.7, 0.7)), (36, V(-0.2, -1.0, 0.2)),
              (40, V(-0.15, -1.0, 0.1))])(f)
    ed = Trk([(0, V(0.4, 0.9, -0.4)), (8, V(0.5, 0.8, -0.3)), (12, V(0.7, 0.7, -0.1)), (23, V(0.7, 0.8, -0.1)), (30, V(0.6, 0.9, -0.3)), (40, V(0.7, 0.9, -0.2))])(f)
    set_limbs(P, hands, feet, {"l": V(kl.x, kl.y, kl.z), "r": V(kr.x, kr.y, kr.z)}, {"l": V(ed.x, ed.y, ed.z), "r": V(-ed.x, ed.y, ed.z)})
    sp = Trk([(0, V(8.0, 0, 0)), (6, V(26.0, 0, 0)), (10, V(38.0, 0, 0)), (14, V(46.0, 0, 0)), (20, V(50.0, 0, 0)), (26, V(44.0, 0, 0)), (32, V(26.0, 0, 0)),
              (37, V(8.0, 0, 0)), (40, st_sp())])(f)
    pl = Trk([(0, V(4.0, 0, 0)), (10, V(10.0, 0, 0)), (16, V(18.0, 0, 0)), (24, V(14.0, 0, 0)), (34, V(4.0, 0, 0)), (40, V(0, 0, 0))])(f)
    hd = Trk([(0, V(-8.0, 0, 0)), (8, V(-28.0, 0, 0)), (14, V(-40.0, 0, 0)), (22, V(-40.0, 0, 0)), (32, V(-26.0, 0, 0)), (40, V(-3.0, 0, 0))])(f)
    set_torso(P, (pl.x, pl.y, pl.z), (sp.x, sp.y, sp.z), (hd.x, hd.y, hd.z))
    return P


def st_sp():
    return V(1.0, 0, 0)


@clip
def Mantle_Low():
    n = 44
    st = stand_pose(V(0.0, -1.27, LOW_TOP))
    poses = []
    for f in range(n + 1):
        if f <= 40:
            P = low_pose(f)
        else:                                          # settle: breathing on the top, exactly the stand pose
            P = stand_pose(V(0.0, -1.27, LOW_TOP), breath=0.6 * smooth((f - 40) / 4.0))
        P.root = V(0, -1.27 * smooth(f / 36.0), LOW_TOP * smooth((f - 12.0) / 24.0))
        poses.append(P)
    TL_EVENTS("Mantle_Low", hands_contact=12, foot_on_top=23, hands_release=24, stand=40)
    return poses, False


def TL_EVENTS(name, **kw):
    EVENTS[name] = kw


CONTACTS["Mantle_Low"] = [["hand_l", 12, 19], ["hand_r", 12, 19], ["ball_l", 4, 9], ["ball_l", 23, 36], ["ball_l", 41, 44],
                          ["ball_r", 10, 13], ["ball_r", 36, 44]]
CONTACTS["Mantle_High"] = [["hand_l", 12, 35], ["hand_r", 12, 35], ["ball_l", 2, 8], ["ball_r", 5, 8], ["ball_r", 35, 59], ["ball_l", 48, 59]]


# ------------------------------------------------------------------ Mantle_High
def high_prefix(f):
    """approach step, crouch, jump (leave the floor 9) and catch the top with both hands (contact 12)"""
    top = HIGH_TOP
    hy = LG.HAND_Y - 0.40
    P = Pose()
    z = Trk([(0, 0.875), (3, 0.86), (6, 0.74), (8, 0.72), (9, 0.80), (10, 0.92), (11, 0.99), (12, 1.00), (14, 0.93)])(f)
    y = Trk([(0, 0.03), (4, -0.06), (8, -0.12), (11, -0.24), (14, -0.34)])(f)
    P.pelvis = V(0.0, y, z)
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        pre = Trk([(0, V(sx * 0.27, -0.20 if side == "l" else 0.10, 1.10)), (4, V(sx * 0.27, 0.0 if side == "l" else -0.25, 0.95)),
                   (8, V(sx * 0.27, -0.05, 1.00)), (9, V(sx * 0.40, -0.30, 1.15)), (10, V(sx * 0.36, -0.50, 1.45)), (11, V(sx * 0.28, hy + 0.05, top + 0.05)),
                   (12, V(sx * LG.HX, hy, top + 0.02)), (20, V(sx * LG.HX, hy, top + 0.02))])(f)
        c = smooth((f - 7.0) / 5.0)
        d, pn = V(0, -1.0, 0), V(0, 0, -1.0)
        HR = hand_stages(side, [(V(0.15 * sx, -1.0, -0.15), V(0, 0.2, -1.0)), (V(0, -0.35, 1.0), V(0, -1.0, 0.2)), (V(0, -1.0, -0.05), V(0, 0, -1.0))],
                         [c, smooth((f - 10.0) / 2.0)])
        hands[side] = (pre, d, pn, 0.15 + 0.4 * smooth((f - 12.0) / 2.0) if f >= 12 else 0.6 * (1 - c), HR)
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        if side == "l":
            k = Trk([(0, V(0.10, -0.05, 0.16)), (2, V(0.10, -0.10, ZB0)), (8, V(0.10, -0.10, ZB0)), (9, V(0.10, -0.13, 0.10)), (10, V(0.10, -0.16, 0.34)),
                     (12, V(0.10, -0.30, 0.42)), (14, V(0.10, -0.38, 0.46))])
        else:
            k = Trk([(0, V(-0.10, 0.10, ZB0)), (2, V(-0.10, 0.10, ZB0)), (3, V(-0.10, 0.04, 0.12)), (4, V(-0.10, -0.06, 0.14)), (5, V(-0.10, -0.15, ZB0)),
                     (8, V(-0.10, -0.15, ZB0)), (9, V(-0.10, -0.16, 0.10)), (10, V(-0.10, -0.20, 0.34)), (12, V(-0.10, -0.30, 0.44)), (14, V(-0.10, -0.34, 0.44))])
        pk = Trk([(0, 0.0), (2, 0.0), (3, 30.0), (5, 0.0), (8, 0.0), (10, 50.0), (14, 30.0)])
        feet[side] = (k(f), sx * 6.0, pk(f), 0.0)
    set_limbs(P, hands, feet, {"l": V(0.15, -1.0, 0.1), "r": V(-0.15, -1.0, 0.1)}, {"l": V(1.0, 0.3, -0.1), "r": V(-1.0, 0.3, -0.1)})
    sp = Trk([(0, V(8.0, 0, 0)), (6, V(26.0, 0, 0)), (8, V(28.0, 0, 0)), (10, V(0.0, 0, 0)), (12, V(-10.0, 0, 0)), (14, V(-8.0, 0, 0))])(f)
    pl = Trk([(0, V(4.0, 0, 0)), (8, V(12.0, 0, 0)), (11, V(0, 0, 0)), (14, V(0, 0, 0))])(f)
    hd = Trk([(0, V(-8.0, 0, 0)), (8, V(-34.0, 0, 0)), (12, V(-30.0, 0, 0)), (14, V(-28.0, 0, 0))])(f)
    set_torso(P, (pl.x, pl.y, pl.z), (sp.x, sp.y, sp.z), (hd.x, hd.y, hd.z))
    return P


@clip
def Mantle_High():
    """approach, jump, hang from the top of a 1.8 m wall, pull, chest over, knee up, stand: the pull / climb part is Ledge_Climb_Up
    (frames 7..52) translated onto the 1.8 m wall (0.4 m forward, 0.32 m down)."""
    dy, dz = HIGH_FACE - LG.LEDGE_FACE, HIGH_TOP - LG.TOPZ
    c0 = 7                                          # first frame of the Ledge_Climb_Up part
    join = 14
    n = join + (52 - c0)
    poses = []
    for f in range(n + 1):
        if f >= join:
            P = shift_pose(LG.climb_pose(c0 + f - join), dy, dz)
        else:
            P0 = high_prefix(f)
            P1 = shift_pose(LG.climb_pose(c0), dy, dz)
            P = blend_pose(P0, P1, smooth((f - 9.0) / (join - 9.0)))
        P.root = V(0, (LG.climb_root(52).y + dy) * smooth((f - 30.0) / 22.0), HIGH_TOP * smooth((f - 16.0) / 38.0))
        poses.append(P)
    TL_EVENTS("Mantle_High", jump=9, hands_contact=12, pull_start=join, chest_over=join + 15, foot_on_top=join + 21, hands_release=join + 25, stand=n)
    return poses, False
