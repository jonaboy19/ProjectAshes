# Vault clips (obstacle 0.92 m tall, near face 0.9 m ahead). Part of author_traversal_v2.py.
from trav_lib import *

BOX = ((-0.9, 0.9), (-1.4, -0.9), (0.0, 0.92))     # the obstacle of the handoff: 0.92 m tall, near face 0.9 m ahead
BOX_TOP = 0.92
VN = 60                                            # frames - 1
ZB = 0.015                                         # ball-of-foot height when the foot is flat on the floor


def vault_tracks():
    """Speed / lazy vault over the box, one-handed at the apex. Both palms land on the top at f17, the lead (left) hand
    lifts at f19, the right hand pushes until f27 while hips and legs swing over to the character's left.
    Timeline @30 fps: 0 run-up stride, 7 takeoff foot lands, 10 gather (crouch, arms back), 14 toe-off, 17 hands land,
    24 apex, 27 push-off, 33-34 landing, 36 absorb, 37-53 two recovery steps, 60 settled. Root travels 2.7 m in Y."""
    K = {}
    K["root_y"] = Trk([(0, 0.0), (7, -0.28), (10, -0.40), (14, -0.50), (18, -0.66), (21, -0.86), (24, -1.10), (27, -1.34),
                       (30, -1.68), (33, -2.02), (36, -2.14), (40, -2.30), (44, -2.42), (48, -2.53), (54, -2.65), (58, -2.70),
                       (60, -2.70, "s")])
    K["pelvis"] = Trk([(0, V(0, 0.0, 0.875)), (4, V(0, -0.13, 0.875)), (7, V(0, -0.28, 0.86)), (10, V(0.0, -0.36, 0.79)),
                       (13, V(0.03, -0.44, 0.93)), (16, V(0.05, -0.54, 1.03)), (20, V(0.16, -0.86, 1.12)), (24, V(0.17, -1.05, 1.15)), (27, V(0.16, -1.19, 1.08)), (30, V(0.16, -1.53, 1.05)),
                       # landing: touch-down 33/34, knees absorb to the low point at 36 (torso dips), weight goes over the left foot
                       # (38), then the right (45), rise and settle to a run-ready stance at 56-60
                       (33, V(0.05, -2.05, 0.90)), (34, V(0.05, -2.09, 0.82)), (36, V(0.03, -2.15, 0.72)), (38, V(0.06, -2.22, 0.76)),
                       (41, V(0.03, -2.31, 0.82)), (45, V(-0.04, -2.43, 0.86)), (48, V(-0.03, -2.54, 0.88)),
                       (52, V(0.02, -2.62, 0.895)), (56, V(0.0, -2.68, 0.90)), (60, V(0.0, -2.73, 0.90))])
    # the pelvis is solved so that the right shoulder sits over the planted right hand (reach guarantee)
    K["sh"] = Trk([(17, V(-0.22, -0.88, 1.38)), (21, V(-0.22, -0.98, 1.42)), (24, V(-0.23, -1.08, 1.44)),
                   (27, V(-0.23, -1.20, 1.40))])
    K["sh_w"] = Trk([(0, 0.0), (14, 0.0), (17, 1.0), (27, 1.0), (30, 0.0), (60, 0.0)])
    gy = -1.05
    Lp = V(0.06, gy, BOX_TOP + 0.02)
    Rp = V(-0.22, gy, BOX_TOP + 0.02)
    K["hand"] = {
        "l": Trk([(0, V(0.26, 0.05, 1.05)), (5, V(0.25, -0.22, 1.05)), (9, V(0.28, -0.26, 1.06)), (13, V(0.27, -0.60, 1.15)),
                  (15, V(0.27, -0.85, 1.15)), (16, V(Lp.x, -0.95, 1.05)), (17, Lp), (18, Lp), (19, V(0.20, -1.08, 1.02)), (21, V(0.42, -1.10, 1.28)), (26, V(0.52, -1.10, 1.50)),
                  (30, V(0.46, -1.62, 1.38)), (34, V(0.48, -2.03, 1.22))]),
        "r": Trk([(0, V(-0.24, -0.42, 1.22)), (5, V(-0.23, -0.45, 1.20)), (9, V(-0.28, -0.26, 1.06)), (13, V(-0.27, -0.60, 1.15)),
                  (15, V(-0.27, -0.85, 1.15)), (16, V(Rp.x, -0.95, 1.05)), (17, Rp), (26, Rp), (28, V(-0.25, -1.30, 1.15)),
                  (30, V(-0.46, -1.68, 1.30)), (34, V(-0.48, -2.03, 1.20))])}
    # after touch-down the hands are keyed relative to the pelvis (x, dy, z): arms out for balance at 33, thrown forward-down with the
    # absorb (36), then opposite-arm swing with the two recovery steps and a bent-elbow run-ready carry (53-60)
    K["hand_rel"] = {
        "l": Trk([(33, V(0.50, 0.05, 1.25)), (35, V(0.42, -0.10, 1.05)), (36, V(0.34, -0.21, 0.90)), (39, V(0.30, -0.28, 1.08)),
                  (42, V(0.28, -0.27, 1.12)), (46, V(0.27, -0.04, 1.00)), (49, V(0.27, -0.05, 1.02)), (53, V(0.27, -0.22, 1.10)),
                  (56, V(0.27, -0.23, 1.10)), (60, V(0.27, -0.23, 1.10))]),
        "r": Trk([(33, V(-0.50, 0.05, 1.20)), (35, V(-0.42, -0.10, 1.02)), (36, V(-0.34, -0.22, 0.90)), (39, V(-0.29, -0.03, 1.02)),
                  (42, V(-0.28, -0.04, 1.03)), (46, V(-0.27, -0.27, 1.14)), (49, V(-0.27, -0.28, 1.13)), (53, V(-0.27, -0.23, 1.10)),
                  (56, V(-0.27, -0.23, 1.10)), (60, V(-0.27, -0.23, 1.10))])}
    K["plant"] = {"l": Trk([(0, 0.0), (15, 0.0), (17, 1.0), (18, 1.0), (20, 0.0), (60, 0.0)]),
                  "r": Trk([(0, 0.0), (15, 0.0), (17, 1.0), (26, 1.0), (28, 0.0), (60, 0.0)])}
    K["grip"] = Trk([(0, 0.7), (10, 0.7), (14, 0.2), (17, 0.0), (29, 0.0), (34, 0.4), (40, 0.5), (60, 0.45)])
    F = {}
    F["l"] = (Trk([(0, V(0.10, -0.32, 0.30)), (4, V(0.10, -0.40, 0.14)), (6, V(0.10, -0.45, ZB)), (7, V(0.10, -0.45, ZB)),
                   (12, V(0.10, -0.45, ZB)), (14, V(0.10, -0.46, ZB)), (15, V(0.10, -0.47, 0.08)), (17, V(0.12, -0.48, 0.30)),
                   (19, V(0.22, -0.55, 0.62)), (21, V(0.42, -0.72, 0.98)), (23, V(0.68, -1.00, 1.24)), (24, V(0.80, -1.10, 1.30)), (27, V(0.74, -1.40, 1.16)),
                   (28, V(0.68, -1.52, 1.00)), (29, V(0.61, -1.65, 0.82)), (30, V(0.52, -1.80, 0.64)), (31, V(0.40, -1.97, 0.45)), (32, V(0.26, -2.14, 0.26)), (33, V(0.12, -2.30, ZB)), (40, V(0.12, -2.30, ZB)),
                   (42, V(0.12, -2.38, 0.07)), (44, V(0.11, -2.55, 0.14)), (46, V(0.10, -2.72, 0.06)), (47, V(0.09, -2.79, ZB)),
                   (60, V(0.09, -2.79, ZB))]),
              Trk([(0, 25.0), (5, 15.0), (7, 0.0), (12, 0.0), (14, 30.0), (16, 50.0), (24, 20.0), (30, 10.0), (33, 0.0),
                   (40, 0.0), (42, 25.0), (45, 10.0), (47, 0.0), (60, 0.0)]))
    F["r"] = (Trk([(0, V(-0.10, -0.02, ZB)), (3, V(-0.10, -0.02, ZB)), (4, V(-0.10, -0.06, 0.05)), (7, V(-0.10, -0.30, 0.28)),
                   (10, V(-0.08, -0.40, 0.45)), (14, V(-0.06, -0.46, 0.52)), (16, V(-0.05, -0.50, 0.60)), (18, V(-0.03, -0.56, 0.72)),
                   (19, V(0.05, -0.63, 0.82)), (20, V(0.16, -0.72, 0.93)), (21, V(0.28, -0.83, 1.04)), (22, V(0.40, -0.93, 1.14)), (23, V(0.52, -1.03, 1.23)), (24, V(0.62, -1.12, 1.30)), (27, V(0.58, -1.36, 1.14)),
                   (29, V(0.50, -1.55, 0.98)), (30, V(0.42, -1.72, 0.80)), (31, V(0.32, -1.90, 0.60)), (32, V(0.18, -2.10, 0.40)), (33, V(0.02, -2.32, 0.22)), (34, V(-0.06, -2.42, ZB)), (36, V(-0.06, -2.42, ZB)),
                   (38, V(-0.06, -2.50, 0.08)), (40, V(-0.07, -2.62, 0.13)), (42, V(-0.08, -2.68, ZB)), (60, V(-0.08, -2.68, ZB))]),
              Trk([(0, 0.0), (3, 0.0), (4, 30.0), (8, 15.0), (14, 25.0), (20, 20.0), (24, 20.0), (30, 10.0), (34, 0.0), (36, 0.0),
                   (38, 25.0), (40, 10.0), (42, 0.0), (60, 0.0)]))
    K["feet"] = F
    K["kdir"] = {"l": Trk([(0, V(0.05, -1.0, 0.0)), (10, V(0.2, -1.0, 0.1)), (16, V(0.2, -1.0, 0.0)), (18, V(0.5, -0.5, 0.0)), (20, V(0.5, -0.5, 0.2)), (22, V(0.4, -0.6, 0.5)), (24, V(0.3, -0.6, 0.8)),
                           (27, V(0.2, -0.6, 0.8)), (29, V(0.15, -0.75, 0.6)), (31, V(0.12, -0.95, 0.35)), (33, V(0.10, -1.0, 0.15)), (36, V(0.25, -1.0, 0.2)), (46, V(0.15, -1.0, 0.15)), (60, V(0.10, -1.0, 0.1))]),
                 "r": Trk([(0, V(-0.1, -1.0, 0.0)), (7, V(-0.15, -1.0, 0.3)), (10, V(-0.2, -1.0, 0.4)), (16, V(-0.25, -0.9, 0.6)), (19, V(-0.15, -0.65, 0.9)),
                           (22, V(0.2, -0.5, 1.0)), (27, V(0.2, -0.6, 0.8)), (29, V(0.1, -0.75, 0.6)), (31, V(0.0, -0.9, 0.4)), (33, V(-0.1, -1.0, 0.2)), (36, V(-0.25, -1.0, 0.2)), (46, V(-0.15, -1.0, 0.15)), (60, V(-0.10, -1.0, 0.1))])}
    K["edir"] = Trk([(0, V(0.3, 0.9, -0.2)), (10, V(0.3, 0.9, -0.2)), (14, V(0.8, 0.5, 0.0)), (30, V(0.8, 0.5, 0.0)),
                     (33, V(0.9, 0.3, -0.1)), (36, V(0.5, 0.6, -0.5)), (42, V(0.5, 0.7, -0.6)), (60, V(0.5, 0.6, -0.7))])
    K["pel_rot"] = Trk([(0, V(6, 0, 4)), (10, V(15, 0, -4)), (17, V(20, -8, 0)), (21, V(10, -20, 0)), (24, V(0, -15, 0)),
                        (28, V(0, -15, 0)), (31, V(5, -5, 0)), (34, V(12, 0, 0)), (36, V(20, 2, 0)), (38, V(12, 4, -3)),
                        (42, V(8, 0, 3)), (45, V(6, -4, 3)), (49, V(4, -2, -3)), (53, V(3, 2, 0)), (57, V(3, 0, 0)), (60, V(3, 0, 0))])
    K["spine_rot"] = Trk([(0, V(10, 0, -8)), (7, V(16, 0, 6)), (10, V(30, 0, 0)), (14, V(34, 0, 0)), (17, V(38, -6, 0)),
                          (21, V(28, -25, 0)), (24, V(14, -35, 0)), (28, V(10, -25, 0)), (31, V(14, -8, 0)), (34, V(24, 0, 0)),
                          (36, V(34, 0, 0)), (39, V(26, -3, 4)), (42, V(18, 0, -4)), (46, V(14, 3, 4)), (50, V(10, 0, -2)),
                          (54, V(8, 0, 0)), (60, V(8, 0, 0))])
    # head keeps the eyes on the target: box in the run-up, the hands on the top, the landing spot, then the horizon
    K["head_rot"] = Trk([(0, V(-8, 0, 0)), (7, V(-14, 0, 0)), (10, V(-28, 0, 0)), (14, V(-32, 0, 0)), (17, V(-38, 0, 0)),
                         (24, V(-14, 34, 0)), (30, V(-22, 10, 0)), (36, V(-34, 0, 0)), (40, V(-30, 0, 0)), (44, V(-22, 0, 0)),
                         (50, V(-14, 0, 0)), (56, V(-10, 0, 0)), (60, V(-9, 0, 0))])
    return K


def vault_poses(mirror=False, n=VN):
    """mirror=False: legs swing over to the character's left (lead hand = left, pivot on the right hand);
    mirror=True: the whole clip mirrored in X (right-side vault, pivot on the left hand)."""
    K = vault_tracks()
    m = -1.0 if mirror else 1.0
    swap = {"l": "r", "r": "l"} if mirror else {"l": "l", "r": "r"}
    mx = lambda v: V(m * v.x, v.y, v.z)
    poses = []
    for f in range(n + 1):
        P = Pose()
        P.root = V(0, K["root_y"](f), 0)
        P.pelvis = mx(K["pelvis"](f))
        w = K["sh_w"](f)
        if w > 0:
            # the shoulder target follows the keyed pelvis after the last key (27), otherwise the release of the anchor drags the pelvis
            # back by up to 0.5 m and the legs snap (was the 0.36 m calf jump at f30)
            S = K["sh"](f) if f <= 27 else K["sh"](27) + (K["pelvis"](f) - K["pelvis"](27))
            P.anchor = ("upperarm_l" if mirror else "upperarm_r", mx(S), w)
        pr = K["pel_rot"](f); sr = K["spine_rot"](f); hr = K["head_rot"](f)
        set_torso(P, (pr.x, m * pr.y, m * pr.z), (sr.x, m * sr.y, m * sr.z), (hr.x, m * hr.y, m * hr.z))
        hands = {}
        for side in ("l", "r"):
            ss = swap[side]
            sx = 1.0 if side == "l" else -1.0
            hp = K["plant"][ss](f)
            g = K["hand"][ss](f)
            lp = smooth((f - 31) / 6.0)                     # landing: hands keyed relative to the pelvis, open palms turn inward
            if f > 30:
                hr = K["hand_rel"][ss](f)
                b = smooth((f - 31) / 3.0)
                g = g.lerp(V(hr.x, K["pelvis"](f).y + hr.y, hr.z), b)
            g = mx(g)
            HR = hand_stages(side, [(V(0.15 * sx, -1.0, -0.15), V(0, 0.2, -1.0)), (V(0, -1, 0), V(0, 0, -1)), (V(0.05 * sx, -1.0, -0.35), V(-0.9 * sx, 0.0, -0.3))], [hp, lp])
            hands[side] = (g, V(0, -1, 0), V(0, 0, -1), K["grip"](f) * (1 - hp), HR)
        feet = {}
        kd = {}
        for side in ("l", "r"):
            ss = swap[side]
            b, pitch = K["feet"][ss]
            feet[side] = (mx(b(f)), 0.0, pitch(f), 0.0)
            kd[side] = mx(K["kdir"][ss](f))
        e = K["edir"](f)
        set_limbs(P, hands, feet, kd, {"l": V(e.x, e.y, e.z), "r": V(-e.x, e.y, e.z)})
        poses.append(P)
    return poses


CONTACTS["Vault_Low"] = [["hand_l", 17, 18], ["hand_r", 17, 26], ["ball_l", 6, 14], ["ball_l", 33, 40], ["ball_l", 47, 60],
                         ["ball_r", 0, 3], ["ball_r", 34, 36], ["ball_r", 42, 60]]
CONTACTS["Vault_Low_B"] = [[b.replace("_l", "_X").replace("_r", "_l").replace("_X", "_r"), a, c] for b, a, c in CONTACTS["Vault_Low"]]
EVENTS["Vault_Low"] = EVENTS["Vault_Low_B"] = {"run_up_takeoff_foot_plant": 7, "toe_off": 14, "hands_on_box": 17, "apex": 24, "push_off_end": 27,
                                               "touch_down": 33, "absorb_low_point": 36, "recovery_steps_end": 53, "settled": 60}


@clip
def Vault_Low():
    return vault_poses(False), False


@clip
def Vault_Low_B():
    """right-side variant: legs swing over to the character's right, pivot on the left hand"""
    return vault_poses(True), False
