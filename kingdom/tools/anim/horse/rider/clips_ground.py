# Clips where the rider leaves / reaches the ground: mount, dismount, dismount jump (horse at rest), fall off (synced to Buck),
# death (synced to the horse's Death). Free poses are keyed in the WORLD (horse-root frame, rider_lib.Keys / free_pose), blended with
# the seated pose (converted to the world with D) and mapped back to clip space with D^-1 (synced clips keep root = origin; the
# horse-at-rest clips move the root bone between the ground stand point and the horse root = root motion).
from rider_lib import *
from clips_gaits import g_idle

Z_ = V(0, 0, 1)


def Rz(yaw):
    return Quaternion((0, 0, 1), rad(yaw))


def bf(org, yaw, x, y, z):
    """world point from a body-frame offset (x = body left, y = body back (+) / forward (-), z = up) at org with body yaw."""
    return org + Rz(yaw) @ V(x, y, z)


def stance(org, yaw, crouch=0.0, spread=1.0):
    """standing (crouch 0) .. deep crouch (1) at org (ground point), facing yaw (0 = -Y)."""
    c = crouch
    d = dict(pel=bf(org, yaw, 0, 0.03 + 0.10 * c, 0.895 - 0.36 * c), pel_rot=(18.0 * c, 0.0, yaw), spine=(2.0 + 22.0 * c, 0.0, 0.0),
             head=(-3.0 - 18.0 * c, 0.0, 0.0), yaw=0.0,
             foot_l=bf(org, yaw, 0.12 * spread, -0.05, 0.015), foot_r=bf(org, yaw, -0.12 * spread, 0.05, 0.015),
             fyaw_l=6.0, fyaw_r=-6.0, fpitch_l=0.0, fpitch_r=0.0,
             hand_l=bf(org, yaw, 0.27 - 0.07 * c, 0.05 - 0.35 * c, 0.80 - 0.32 * c),
             hand_r=bf(org, yaw, -0.27 + 0.07 * c, 0.05 - 0.35 * c, 0.80 - 0.32 * c),
             kdir_l=V(0.2, -1.0, 0.1), kdir_r=V(-0.2, -1.0, 0.1))
    # free_pose rotates hand / foot orientations and pole directions by 'yaw'; the body yaw lives in pel_rot here, so keep yaw = the body yaw
    d["yaw"] = yaw
    d["pel_rot"] = (18.0 * c, 0.0, 0.0)
    return d


def free_keys_pose(K, f):
    k = K(f)
    return free_pose(k)


def seated_world(S, f, g=None):
    return to_world(seat_pose(S, f, g or dict(lean=8.0, h_pitch=5.0, s_chest=0.3, s_head=0.7)), S, f)


def compose(S, K, w_free, g_seat=None, root_fn=None):
    """per frame: blend(seated (world), free keyed pose (world), w_free(f)) -> clip space."""
    poses = []
    for f in range(S.n):
        Ps = seated_world(S, f, g_seat)
        w = w_free(f)
        P = blend_pose(Ps, free_keys_pose(K, f), w) if w > 0 else Ps
        Pc = to_clip(P, S, f)
        Pc.root = root_fn(f) if root_fn else V(0, 0, 0)
        poses.append(Pc)
    return poses


def seat_vals(S, f, sx=1.0):
    """world values of the seated pose at frame f (to key the free pose continuously out of / into the saddle)."""
    P = seated_world(S, f)
    return P


# ------------------------------------------------------------------ mount / dismount (horse at rest: D = identity)
def mount(side):
    sx = SX[side]
    near, far = side, ("r" if side == "l" else "l")
    n = 67
    S = Sync.rest(n)
    yaw0 = -90.0 * sx                               # facing the horse
    org = V(0.56 * sx, -0.18, 0.0)                  # stand point (ground)
    st = stance(org, yaw0)
    stir_n, stir_f = STIR[near], STIR[far]
    withers = V(0.13 * sx, -0.52, 1.70)
    cantle = V(0.10 * sx, 0.06, 1.64)

    def kv(**d):
        out = {}
        for k, v in d.items():
            out[k.replace("_N", "_" + near).replace("_F", "_" + far)] = v
        return out
    K = Keys([
        (0, dict(st), "s"),
        (6, kv(hand_N=bf(org, yaw0, 0.30 * sx, -0.12, 1.15), hand_F=bf(org, yaw0, -0.25 * sx, -0.05, 0.95), spine=(6.0, 0.0, 0.0))),
        (12, kv(hand_N=tuple(withers), hand_F=tuple(cantle), pel=tuple(bf(org, yaw0, 0, 0.03, 0.885)), spine=(10.0, 0.0, 0.0),
                foot_N=tuple(bf(org, yaw0, 0.12 * sx, -0.05, 0.015)), head=(8.0, 0.0, 0.0))),
        (15, kv(foot_N=tuple(bf(org, yaw0, 0.10 * sx, -0.25, 0.55)), fpitch_N=10.0)),
        (19, kv(foot_N=tuple(stir_n), fpitch_N=-5.0, fyaw_N=0.0, pel=tuple(bf(org, yaw0, -0.02 * sx, 0.06, 0.86)), spine=(14.0, 0.0, 0.0),
                hand_N=tuple(withers), hand_F=tuple(cantle))),
        (23, kv(pel=tuple(bf(org, yaw0, -0.02 * sx, 0.08, 0.84)), spine=(20.0, 0.0, 0.0), foot_F=tuple(bf(org, yaw0, -0.12 * sx, 0.05, 0.015)))),
        (27, kv(foot_F=tuple(bf(org, yaw0, -0.14 * sx, 0.14, 0.38)), fpitch_F=40.0)),
        (32, kv(pel=(0.40 * sx, -0.20, 1.73), spine=(26.0, 0.0, 0.0), pel_rot=(18.0, 0.0, 0.0), foot_F=(0.50 * sx, -0.05, 1.02),
                hand_N=tuple(withers), hand_F=(0.02 * sx, -0.02, 1.64), head=(0.0, 0.0, 0.0), kdir_N=V(0.9 * sx, -0.8, 0.1))),
        (36, kv(yaw=yaw0 * 0.8, pel=(0.30 * sx, -0.18, 1.78), foot_F=(0.25 * sx, 0.35, 1.75), fpitch_F=35.0, kdir_F=V(0.0, 0.3, -1.0))),
        (41, kv(yaw=yaw0 * 0.45, pel=(0.14 * sx, -0.20, 1.76), foot_F=(-0.05 * sx, 0.45, 1.95), spine=(18.0, 0.0, 0.0), pel_rot=(10.0, 0.0, 0.0))),
        (46, kv(yaw=yaw0 * 0.12, pel=(0.03 * sx, -0.22, 1.73), foot_F=(-0.48 * sx, 0.02, 1.52), fpitch_F=0.0, kdir_F=V(-1.0 * sx, -0.8, 0.1),
                hand_F=(-0.09 * sx, -0.50, 1.76), spine=(10.0, 0.0, 0.0))),
        (52, kv(yaw=0.0, pel=tuple(SEAT + V(0, 0, 0.008)), foot_F=tuple(stir_f + V(-0.02 * sx, 0.02, 0.03)), pel_rot=(6.0, 0.0, 0.0), spine=(3.0, 0.0, 0.0))),
    ], base=st)
    w = lambda f: 1.0 - pulse(f, 50, 62)
    root = lambda f: V(org.x, org.y, 0.0).lerp(V(0, 0, 0), smooth((f - 24) / 26.0))
    poses = compose(S, K, w, root_fn=root)
    m = dict(synced_to=None, loop=False, layer="full", hands_on_grips=[[62, 66]], seated=[[60, 66]], feet_in_stirrups=[[60, 66]],
             start_stand_point=[round(org.x, 3), round(org.y, 3), 0.0], start_yaw_deg=yaw0,
             events={"grab": 12, "foot_in_stirrup": 19, "spring": 27, "leg_over": 41, "seated": 56, "mount_done": 66},
             contacts=[["ball_" + near, 19, 66, "stirrup_" + near.upper()], ["ball_" + far, 58, 66, "stirrup_" + far.upper()]],
             notes="horse at rest (play with Idle); root bone travels from the stand point (horse-root space) to the horse root; "
                   "ends on Horse_Ride_Idle frame 0")
    return poses, m


@clip("Horse_Ride_Mount_L")
def c_mount_l():
    return mount("l")


@clip("Horse_Ride_Mount_R")
def c_mount_r():
    return mount("r")


def dismount(side):
    sx = SX[side]
    near, far = side, ("r" if side == "l" else "l")
    n = 61
    S = Sync.rest(n)
    yaw_h = -90.0 * sx
    org = V(0.66 * sx, -0.20, 0.0)
    end = stance(org, 0.0)
    withers = V(0.10 * sx, -0.52, 1.72)

    def kv(**d):
        return {k.replace("_N", "_" + near).replace("_F", "_" + far): v for k, v in d.items()}
    start = dict(pel=tuple(SEAT), pel_rot=(6.0, 0.0, 0.0), spine=(3.0, 0.0, 0.0), head=(-1.0, 0.0, 0.0), yaw=0.0,
                 foot_l=tuple(STIR["l"]), foot_r=tuple(STIR["r"]), fpitch_l=-15.0, fpitch_r=-15.0, fyaw_l=8.0, fyaw_r=-8.0,
                 hand_l=tuple(GRIP_REST["l"]), hand_r=tuple(GRIP_REST["r"]), kdir_l=V(0.75, -0.75, 0.0), kdir_r=V(-0.75, -0.75, 0.0))
    K = Keys([
        (0, dict(start), "s"),
        (6, kv(hand_N=tuple(withers), hand_F=(0.0, -0.46, 1.72), foot_F=tuple(STIR[far] + V(-0.06 * sx, 0.10, 0.05)), fpitch_F=0.0)),
        (12, kv(pel=tuple(SEAT + V(0.04 * sx, 0.0, 0.08)), spine=(14.0, 0.0, 0.0), foot_F=(-0.45 * sx, 0.22, 1.50), kdir_F=V(-1.0 * sx, -0.3, 0.2))),
        (18, kv(yaw=yaw_h * 0.2, pel=(0.10 * sx, -0.22, 1.76), foot_F=(-0.10 * sx, 0.45, 1.90), fpitch_F=35.0, kdir_F=V(0.0, 0.3, -1.0),
                spine=(20.0, 0.0, 0.0), pel_rot=(12.0, 0.0, 0.0))),
        (24, kv(yaw=yaw_h * 0.6, pel=(0.28 * sx, -0.20, 1.80), foot_F=(0.30 * sx, 0.34, 1.78), hand_F=(0.02 * sx, -0.30, 1.68))),
        (29, kv(yaw=yaw_h, pel=(0.50 * sx, -0.20, 1.72), foot_F=(0.52 * sx, -0.08, 1.02), fpitch_F=20.0, kdir_F=V(0.2 * sx, -1.0, 0.1),
                foot_N=tuple(STIR[near]), spine=(22.0, 0.0, 0.0), pel_rot=(15.0, 0.0, 0.0), hand_N=tuple(withers), hand_F=(0.08 * sx, -0.05, 1.64))),
        (33, kv(foot_N=tuple(STIR[near] + V(0.14 * sx, 0.03, -0.06)), fpitch_N=10.0, pel=(0.60 * sx, -0.20, 1.55))),
        (40, kv(yaw=yaw_h, pel=tuple(bf(org, yaw_h, 0, 0.14, 0.70)), foot_N=tuple(bf(org, yaw_h, 0.12 * sx, 0.0, 0.015)), foot_F=tuple(bf(org, yaw_h, -0.12 * sx, 0.06, 0.015)),
                fpitch_N=0.0, fpitch_F=0.0, fyaw_N=6.0 * sx, fyaw_F=-6.0 * sx, spine=(24.0, 0.0, 0.0), pel_rot=(18.0, 0.0, 0.0),
                hand_N=(0.20 * sx, -0.50, 1.55), hand_F=(0.20 * sx, 0.0, 1.50), kdir_N=V(0.2 * sx, -1.0, 0.1), kdir_F=V(-0.2 * sx, -1.0, 0.1))),
        (46, kv(yaw=yaw_h, pel=tuple(bf(org, yaw_h, 0, 0.05, 0.86)), spine=(8.0, 0.0, 0.0), pel_rot=(4.0, 0.0, 0.0),
                hand_N=tuple(bf(org, yaw_h, 0.25 * sx, 0.0, 0.85)), hand_F=tuple(bf(org, yaw_h, -0.25 * sx, 0.05, 0.82)),
                foot_N=tuple(bf(org, yaw_h, 0.12 * sx, 0.0, 0.015)), foot_F=tuple(bf(org, yaw_h, -0.12 * sx, 0.06, 0.015)))),
        (60, dict(end), "s"),
    ], base=start)
    # the stance keys are in body terms with 'yaw'; interpolating 'yaw' from yaw_h to 0 over 46..60 turns the rider to face forward
    root = lambda f: V(0, 0, 0).lerp(V(org.x, org.y, 0.0), smooth((f - 28) / 22.0))
    poses = compose(S, K, lambda f: pulse(f, 0, 3), root_fn=root)
    m = dict(synced_to=None, loop=False, layer="full", hands_on_grips=[[0, 0]], seated=[[0, 0]], feet_in_stirrups=[[0, 0]],
             end_stand_point=[round(org.x, 3), round(org.y, 3), 0.0], end_yaw_deg=0.0,
             events={"leg_over": 18, "foot_out": 32, "land": 40, "dismount_done": 60},
             contacts=[["ball_" + near, 0, 31, "stirrup_" + near.upper()], ["ball_" + far, 0, 4, "stirrup_" + far.upper()]],
             notes="horse at rest; root bone travels from the horse root to the ground stand point (root motion); ends standing, facing forward")
    return poses, m


@clip("Horse_Ride_Dismount_L")
def c_dis_l():
    return dismount("l")


@clip("Horse_Ride_Dismount_R")
def c_dis_r():
    return dismount("r")


@clip("Horse_Ride_Dismount_Jump")
def c_dis_jump():
    n = 41
    S = Sync.rest(n)
    org = V(0.88, -0.28, 0.0)
    yaw_h = -90.0
    crouch = stance(org, 0.0, crouch=0.75, spread=1.4)
    start = dict(pel=tuple(SEAT), pel_rot=(6.0, 0.0, 0.0), spine=(3.0, 0.0, 0.0), head=(-1.0, 0.0, 0.0), yaw=0.0,
                 foot_l=tuple(STIR["l"]), foot_r=tuple(STIR["r"]), fpitch_l=-15.0, fpitch_r=-15.0, fyaw_l=8.0, fyaw_r=-8.0,
                 hand_l=tuple(GRIP_REST["l"]), hand_r=tuple(GRIP_REST["r"]), kdir_l=V(0.75, -0.75, 0.0), kdir_r=V(-0.75, -0.75, 0.0))
    K = Keys([
        (0, dict(start), "s"),
        (4, dict(foot_l=tuple(STIR["l"] + V(0.10, 0.12, 0.02)), foot_r=tuple(STIR["r"] + V(-0.10, 0.12, 0.02)), fpitch_l=10.0, fpitch_r=10.0,
                 hand_l=(0.10, -0.50, 1.72), hand_r=(-0.06, -0.48, 1.72), spine=(12.0, 0.0, 0.0))),
        (9, dict(pel=tuple(SEAT + V(0.05, 0.02, 0.10)), spine=(26.0, 0.0, 0.0), pel_rot=(20.0, 0.0, 0.0), foot_r=(-0.30, 0.25, 1.30),
                 foot_l=(0.36, 0.05, 1.10), kdir_r=V(-0.3, 0.2, -1.0))),
        (14, dict(yaw=yaw_h * 0.35, pel=(0.18, -0.20, 1.86), foot_r=(-0.02, 0.50, 1.98), foot_l=(0.40, 0.25, 1.40), fpitch_r=40.0,
                  kdir_r=V(0.0, 0.3, -1.0), hand_l=(0.10, -0.50, 1.72), hand_r=(-0.02, -0.46, 1.72))),
        (19, dict(yaw=yaw_h * 0.8, pel=(0.48, -0.24, 1.66), foot_r=(0.62, 0.05, 1.20), foot_l=(0.70, -0.15, 1.05), fpitch_r=20.0, fpitch_l=20.0,
                  kdir_r=V(-0.2, -1.0, 0.0), kdir_l=V(0.2, -1.0, 0.0), hand_l=(0.14, -0.50, 1.70), hand_r=(0.10, -0.22, 1.66), spine=(20.0, 0.0, 0.0))),
        (24, dict(yaw=yaw_h * 0.7, pel=(0.80, -0.26, 0.95), foot_l=tuple(bf(org, 0, 0.17, -0.07, 0.10)), foot_r=tuple(bf(org, 0, -0.17, 0.07, 0.10)),
                  fpitch_l=0.0, fpitch_r=0.0, hand_l=(0.55, -0.60, 1.30), hand_r=(0.45, -0.10, 1.25))),
        (27, dict(crouch)),
        (32, dict(crouch)),
        (40, dict(stance(org, 0.0, crouch=0.45, spread=1.3)), "s"),
    ], base=start)
    root = lambda f: V(0, 0, 0).lerp(V(org.x, org.y, 0.0), smooth((f - 10) / 16.0))
    poses = compose(S, K, lambda f: pulse(f, 0, 3), root_fn=root)
    m = dict(synced_to=None, loop=False, layer="full", hands_on_grips=[[0, 0]], seated=[[0, 0]], feet_in_stirrups=[[0, 0]],
             end_stand_point=[round(org.x, 3), round(org.y, 3), 0.0], end_yaw_deg=0.0,
             events={"push_off": 9, "land": 26, "dismount_done": 40},
             notes="horse at rest; vaults off to the left (both hands on the withers), lands in a crouch; root bone -> ground point")
    return poses, m


# ------------------------------------------------------------------ fall off (synced to the horse's Buck) and death (synced to Death)
@clip("Horse_Ride_FallOff")
def c_falloff():
    S = Sync("Buck")
    lie = V(-1.30, -1.55, 0.0)
    g_seat = dict(lean=lambda f: 8.0 + 20.0 * pulse(f, 12, 20), h_pitch=5.0, s_chest=0.5, s_head=0.8, up_w=1.0, grip=1.0,
                  pz=lambda f: 0.04 * pulse(f, 14, 20), py=lambda f: -0.04 * pulse(f, 14, 20))
    P18 = seated_world(S, 20, g_seat)
    lying = dict(pel=tuple(lie + V(0, 0, 0.13)), pel_rot=(-88.0, 0.0, 90.0), spine=(-4.0, 0.0, 0.0), head=(8.0, 0.0, 12.0), yaw=0.0,
                 foot_l=tuple(lie + V(0.78, -0.18, 0.08)), foot_r=tuple(lie + V(0.72, 0.16, 0.05)), fpitch_l=-50.0, fpitch_r=-60.0,
                 fyaw_l=-90.0, fyaw_r=-90.0, kdir_l=V(0.0, 0.3, 1.0), kdir_r=V(0.0, -0.3, 1.0),
                 hand_l=tuple(lie + V(-0.25, -0.38, 0.03)), hand_r=tuple(lie + V(-0.10, 0.40, 0.03)), grip_l=0.3, grip_r=0.3,
                 edir_l=V(0.3, 0.0, -1.0), edir_r=V(-0.3, 0.0, -1.0))
    K = Keys([
        (20, dict(pel=tuple(P18.pelvis), pel_rot=(20.0, 0.0, 0.0), spine=(20.0, 0.0, 0.0), foot_l=tuple(S.D[20] @ STIR["l"]),
                  foot_r=tuple(S.D[20] @ STIR["r"]), hand_l=tuple(S.D[20] @ GRIP_REST["l"]), hand_r=tuple(S.D[20] @ GRIP_REST["r"]),
                  fpitch_l=-15.0, fpitch_r=-15.0, kdir_l=V(0.75, -0.75, 0.0), kdir_r=V(-0.75, -0.75, 0.0))),
        (25, dict(pel=(-0.35, -0.75, 1.95), pel_rot=(40.0, -25.0, 10.0), spine=(25.0, -10.0, 0.0), foot_l=(0.05, -0.05, 1.75), foot_r=(-0.45, 0.10, 1.55),
                  hand_l=(-0.30, -1.05, 2.10), hand_r=(-0.80, -0.80, 1.90), fpitch_l=10.0, fpitch_r=10.0, kdir_l=V(0.3, -1.0, 0.2), kdir_r=V(-0.3, -1.0, 0.2))),
        (30, dict(pel=(-0.95, -1.25, 1.15), pel_rot=(-10.0, -70.0, 60.0), spine=(15.0, -10.0, 0.0), foot_l=(-0.35, -0.70, 1.75), foot_r=(-0.70, -0.45, 1.50),
                  hand_l=(-1.25, -1.65, 0.85), hand_r=(-1.45, -1.25, 0.65), head=(10.0, 0.0, 0.0))),
        (35, dict(lying, pel=tuple(lie + V(0, 0, 0.20)), foot_l=tuple(lie + V(0.60, -0.10, 0.40)), foot_r=tuple(lie + V(0.55, 0.20, 0.55)))),
        (40, dict(lying, head=(-10.0, 0.0, 5.0), foot_l=tuple(lie + V(0.70, -0.15, 0.20)))),
        (57, dict(lying), "s"),
    ], base=lying)
    poses = compose(S, K, lambda f: pulse(f, 18, 23), g_seat=g_seat)
    m = dict(synced_to="Buck", loop=False, layer="full", hands_on_grips=[[0, 16]], seated=[[0, 13]], feet_in_stirrups=[[0, 17]],
             end_ground_point=[round(lie.x, 3), round(lie.y, 3), 0.0],
             events={"thrown": 21, "hit_ground": 34, "lying": 45},
             notes="rider catapulted forward-right by the buck, lands on his back beside the horse (head away from it). root stays at the "
                   "clip origin: the rider's world pose = horse root * D(t) * clip; after the clip re-parent the rider to the ground at "
                   "end_ground_point (horse-root space)")
    return poses, m


@clip("Horse_Ride_Death")
def c_death():
    S = Sync("Death")
    land = V(1.55, -0.30, 0.0)
    kneel = V(1.80, -0.15, 0.0)
    yk = -90.0                                   # kneeling, facing the fallen horse (-X)
    g_seat = dict(lean=lambda f: 8.0 - 10.0 * pulse(f, 4, 14), h_pitch=lambda f: 5.0 + 12.0 * pulse(f, 6, 16), s_chest=0.6, s_head=0.85,
                  up_w=0.8, grip=1.0)
    P22 = seated_world(S, 22, g_seat)
    kn = dict(pel=tuple(bf(kneel, yk, 0.0, 0.02, 0.56)), pel_rot=(8.0, 0.0, 0.0), spine=(12.0, 0.0, 0.0), head=(10.0, 0.0, 0.0), yaw=yk,
              foot_l=tuple(bf(kneel, yk, 0.13, -0.42, 0.015)), fpitch_l=0.0, fyaw_l=5.0, kdir_l=V(0.15, -1.0, 0.4),
              foot_r=tuple(bf(kneel, yk, -0.13, 0.50, 0.035)), fpitch_r=62.0, fyaw_r=0.0, kdir_r=V(-0.1, -0.3, -1.0),
              hand_l=tuple(bf(kneel, yk, 0.16, -0.30, 0.62)), hand_r=tuple(bf(kneel, yk, -0.24, -0.02, 0.52)),
              edir_l=V(0.6, 0.6, -0.4), edir_r=V(-0.6, 0.6, -0.4), grip_l=0.4, grip_r=0.4)
    crouch = stance(land, -30.0, crouch=0.8, spread=1.4)
    K = Keys([
        (22, dict(pel=tuple(P22.pelvis), pel_rot=(5.0, 0.0, 0.0), spine=(0.0, 0.0, 0.0), foot_l=tuple(S.D[22] @ STIR["l"]),
                  foot_r=tuple(S.D[22] @ STIR["r"]), hand_l=tuple(S.D[22] @ GRIP_REST["l"]), hand_r=tuple(S.D[22] @ GRIP_REST["r"]),
                  fpitch_l=-15.0, fpitch_r=-15.0, kdir_l=V(0.75, -0.75, 0.0), kdir_r=V(-0.75, -0.75, 0.0), yaw=0.0)),
        (27, dict(pel=tuple(P22.pelvis + V(0.25, -0.05, 0.22)), spine=(18.0, 12.0, 0.0), pel_rot=(15.0, 10.0, 0.0),
                  foot_l=tuple(S.D[27] @ STIR["l"] + V(0.30, 0.05, 0.25)), foot_r=(0.25, 0.05, 1.85), kdir_r=V(0.0, 0.3, -1.0), fpitch_r=30.0,
                  hand_l=tuple(S.D[27] @ GRIP_REST["l"] + V(0.18, 0.10, 0.12)), hand_r=tuple(S.D[27] @ GRIP_REST["l"] + V(0.0, 0.16, 0.14)))),
        (34, dict(yaw=-25.0, pel=(1.05, -0.28, 1.45), pel_rot=(5.0, 12.0, 0.0), spine=(10.0, 5.0, 0.0), foot_l=(1.25, -0.40, 0.80),
                  foot_r=(1.05, -0.05, 0.95), fpitch_l=10.0, fpitch_r=10.0, kdir_l=V(0.2, -1.0, 0.1), kdir_r=V(-0.2, -1.0, 0.1),
                  hand_l=(1.35, -0.75, 1.55), hand_r=(0.75, -0.55, 1.65), head=(5.0, 0.0, 0.0))),
        (40, dict(crouch, pel=tuple(bf(land, -30.0, 0, 0.10, 0.70)))),
        (46, dict(crouch)),
        (58, dict(stance(land + V(0.12, 0.08, 0), -60.0, crouch=0.4, spread=1.2), head=(4.0, 0.0, -25.0))),
        (72, dict(kn, head=(4.0, 0.0, 0.0))),
        (102, dict(kn, head=(12.0, 0.0, 6.0)), "s"),
    ], base=kn)
    poses = compose(S, K, lambda f: pulse(f, 20, 26), g_seat=g_seat)
    m = dict(synced_to="Death", loop=False, layer="full", hands_on_grips=[[0, 18]], seated=[[0, 20]], feet_in_stirrups=[[0, 19]],
             end_ground_point=[round(kneel.x, 3), round(kneel.y, 3), 0.0], end_yaw_deg=yk,
             events={"feet_out": 21, "jump": 27, "land": 40, "kneel": 72},
             notes="horse collapses onto its right side; the rider jumps clear to the left, lands in a crouch and kneels facing the "
                   "horse. root stays at the clip origin (world = horse root * D(t) * clip); re-parent to the ground at end_ground_point")
    return poses, m
