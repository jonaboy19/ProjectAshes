# Horse riding clips (rider only, the horse is a static frame: saddle top 1.12-1.17 m, seat = pelvis about 1.20 m above the
# ground, stirrup treads 0.65 m, reins held just ahead of the pommel). Part of author_traversal_v2.py.
# Feet stay in the stirrups (world-fixed), hands stay on the reins (they follow the horse's head nod a few cm), the pelvis
# stays on the saddle (a few cm of absorption), the torso counter-rotates so the head stays calm.
from trav_lib import *

TAU = 2 * math.pi
SEAT_Z = 1.205
STIRRUP = (0.37, -0.10, 0.665)                 # ball of the foot on the stirrup tread (x is mirrored)


def ride_pose(u, g):
    """u in cycles (0..1). g: gait parameter dict."""
    ph = TAU * u
    P = Pose()
    S = lambda k, off=0.0: math.sin(k * ph + off)          # k cycles per loop
    if g.get("hump"):
        # rising trot: the horse's diagonal A lands at ph = 0 and pushes the rider up (rise 0..0.25 cycle, top 0.25, back in the saddle at
        # 0.5 = diagonal B), then the rider stays seated through the second beat and the suspension (0.5..1.0): one hump per stride
        u_up = max(0.0, math.sin(ph)) ** g.get("hump", 1.25)
        up = g.get("post", 0.0) * u_up
    else:
        u_up = 0.5 - 0.5 * math.cos(ph)
        up = g.get("post", 0.0) * u_up    # (old shape) 0 sitting .. 1 standing (one rise per stride)
    stand = g.get("stand", 0.0)
    fwd = g.get("fwd", 0.0) + g.get("post_pitch", 0.0) * u_up   # torso forward lean (deg)
    lean = g.get("lean", 0.0)
    z = SEAT_Z + g.get("bob", 0.0) * (-math.cos(2 * ph) if g.get("hump") else S(2, g.get("bob_ph", 0.0))) + 0.075 * up + stand + g.get("z_osc", 0.0) * S(1, g.get("z_ph", 0.0))
    y = 0.02 - 0.03 * up - g.get("stand_y", 0.0) * min(1.0, stand / 0.10 if stand else 0.0) + g.get("y_osc", 0.0) * S(1, g.get("y_ph", 0.5)) + g.get("fore", 0.0) * S(2, 0.4)
    x = g.get("x_shift", 0.0) + g.get("x_osc", 0.0) * S(1, 1.0)
    P.pelvis = V(x, y, z)
    # ---- torso: pelvis rocks with the horse, the spine counter-rotates so the shoulders / head stay quiet
    p_pitch = g.get("p_pitch", 0.0) * S(2, 0.2) + fwd * 0.35 + g.get("pitch_osc", 0.0) * S(1, g.get("pitch_ph", 1.0))
    p_roll = g.get("p_roll", 0.0) * S(1, 0.0) + lean * 0.25 + g.get("roll_osc", 0.0) * S(1, 0.6)
    p_yaw = g.get("p_yaw", 0.0) * S(1, 1.4)
    keep = g.get("keep", 0.8)               # how much of the pelvis rock the spine cancels
    s_pitch = fwd * 0.65 - keep * g.get("p_pitch", 0.0) * S(2, 0.2) + g.get("breath", 0.8) * S(g.get("breath_k", 1), 0.3)
    s_roll = lean * 0.75 - keep * g.get("p_roll", 0.0) * S(1, 0.0) - 0.5 * g.get("roll_osc", 0.0) * S(1, 0.6)
    s_yaw = -keep * p_yaw + g.get("s_yaw", 0.0) * S(1, 2.0)
    h_pitch = -(p_pitch + s_pitch) * g.get("head_comp", 0.8) + g.get("h_pitch", 0.0) * S(2, 1.1)
    h_roll = -0.5 * (p_roll + s_roll)
    h_yaw = g.get("look", 0.0) * S(1, g.get("look_ph", 0.0)) + g.get("look_bias", 0.0)
    set_torso(P, (p_pitch, p_roll, p_yaw), (s_pitch, s_roll, s_yaw), (h_pitch, h_roll, h_yaw))
    # ---- hands on the reins
    hands = {}
    nod = g.get("nod", 0.0)
    for side, sx in (("l", 1), ("r", -1)):
        gx = sx * g.get("hand_x", 0.11) + g.get("hand_shift_" + side, 0.0)
        gy = g.get("hand_y", -0.34) + nod * S(1, -0.6) + g.get("hand_dy_" + side, 0.0)
        gz = g.get("hand_z", 1.27) + 0.012 * nod / 0.02 * 0.0 + g.get("hand_bob", 0.0) * S(2, 0.9) + g.get("hand_dz_" + side, 0.0)
        gz += g.get("hand_follow", 0.0) * 0.075 * up          # the hands follow the rising shoulders part of the way (elbows open, reins stay taut)
        gy += g.get("hand_follow", 0.0) * (-0.03 * up)
        hands[side] = (V(gx, gy, gz), V(0.0, -1.0, -0.25), V(sx * 0.6, 0.0, -1.0) if not g.get("hands_on_neck") else V(sx * 0.9, 0.0, -0.4), 0.9)
    # ---- feet in the stirrups (world-fixed), heels down, toes forward
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        hd = g.get("heel_" + side, 0.0)
        feet[side] = (V(sx * STIRRUP[0], STIRRUP[1], STIRRUP[2]), sx * 5.0, -12.0 + hd, 0.0)
    set_limbs(P, hands, feet, {"l": V(0.45, -1.0, 0.0), "r": V(-0.45, -1.0, 0.0)},
              {"l": V(0.75, 0.75, -0.35), "r": V(-0.75, 0.75, -0.35)})
    return P


GAIT = {
    "idle": dict(n=60, bob=0.002, p_roll=0.7, p_yaw=0.6, p_pitch=0.3, breath=1.1, breath_k=2, look=10.0, look_ph=0.0, nod=0.008,
                 hand_bob=0.004, head_comp=0.6),
    "walk": dict(n=36, bob=0.007, bob_ph=0.5, p_roll=3.0, p_yaw=3.5, p_pitch=2.0, fore=0.008, nod=0.022, hand_bob=0.010, breath=0.6,
                 breath_k=2, look=4.0, look_ph=1.0, heel_l=2.0, heel_r=-2.0, head_comp=0.9, keep=0.85),
    # rising trot (posting): two beats per stride (diagonal pairs at ph 0 and 0.5), one rise per stride, upper body quiet, hands steady
    # (a few mm of give), heels down, knees soft. Loops on whole cycles.
    "trot": dict(n=20, hump=1.25, bob=0.007, post=1.55, post_pitch=7.0, fwd=8.0, hand_follow=0.6, p_roll=0.8, p_yaw=1.0, p_pitch=1.0, nod=0.010, hand_bob=0.006,
                 breath=0.3, breath_k=2, look=1.5, heel_l=-6.0, heel_r=-6.0, head_comp=0.95, keep=0.9, hand_z=1.26, y_osc=0.0),
    "gallop": dict(n=16, stand=0.115, stand_y=0.0, fwd=30.0, z_osc=0.028, z_ph=0.2, y_osc=0.035, y_ph=1.6, pitch_osc=3.5, pitch_ph=1.6,
                   p_roll=0.8, p_yaw=0.8, nod=0.028, hand_z=1.38, hand_y=-0.57, hand_x=0.10, hands_on_neck=True, breath=0.4,
                   head_comp=0.85, keep=0.6, heel_l=6.0, heel_r=6.0, hand_bob=0.014, bob=0.006),
}


def lean_gait(sign):
    """Ride_Lean: sustained turn lean (about 13 degrees) into the turn with walk-rhythm rocking so it never freezes."""
    g = dict(GAIT["walk"])
    g.update(n=30, lean=17.0 * sign, x_shift=0.03 * sign, x_osc=0.006, roll_osc=2.2, p_roll=2.0, look_bias=16.0 * sign, look=3.0,
             hand_shift_l=0.04 * sign, hand_shift_r=0.04 * sign, hand_dy_l=0.03 if sign > 0 else -0.02, hand_dy_r=-0.02 if sign > 0 else 0.03,
             heel_l=(-6.0 if sign > 0 else 5.0), heel_r=(5.0 if sign > 0 else -6.0), nod=0.02, p_yaw=2.5, fwd=3.0)
    return g


def poses_of(g):
    n = g["n"]
    return [ride_pose(i / n, g) for i in range(n + 1)]


@clip
def Ride_Idle():
    return poses_of(GAIT["idle"]), True


@clip
def Ride_Walk():
    return poses_of(GAIT["walk"]), True


@clip
def Ride_Trot():
    return poses_of(GAIT["trot"]), True


@clip
def Ride_Gallop():
    return poses_of(GAIT["gallop"]), True


@clip
def Ride_Lean_L():
    return poses_of(lean_gait(1)), True


@clip
def Ride_Lean_R():
    return poses_of(lean_gait(-1)), True
