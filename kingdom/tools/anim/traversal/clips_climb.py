# Ladder, wall and ledge clips. Part of author_traversal_v2.py.
# Ladder: rungs every 0.3 m at z = 0.3k (first hand rung 1.5 m above the root start), rung plane 0.31 m in front of
# the root (y = -0.31), 0.6 m rise (two rungs) per 1.2 s loop, cross pattern (left hand + right foot move together).
# Wall: hold heights every 0.25 m per limb line, wall face y = -0.36, holds 6 cm deep, 0.5 m rise per 1.4 s loop.
# Ledge: top surface z = 2.12, front face y = -0.20 (ledge box y -0.9..-0.2).
from trav_lib import *

TAU = 2 * math.pi


def hold_move(u, m, rise):
    """A limb holds still, then steps `rise` up during half of the cycle. Move window = [m, m+0.5) (mod 1).
    Returns (dz relative to the hold height at u == m, w in 0..1 while moving else None)."""
    v = u - m
    k = math.floor(v)
    s = v - k
    if s < 0.5:
        w = s / 0.5
        return rise * (k + smooth(w)), w
    return rise * (k + 1), None


def grip_curve(w):
    """1 = fist. Open the hand right after the release, close it just before the grab."""
    if w is None:
        return 1.0
    a = smooth(w / 0.18)
    b = smooth((w - 0.78) / 0.22)
    return 1.0 - a * (1.0 - b)


LADDER = dict(rise=0.6, n=36, hx=0.20, fx=0.13, yc=-0.31, P0=0.86, py=0.02,
              hz=(1.80, 1.50), fz=(0.035, 0.335),        # (left, right) z of the hold at the start of the limb's move window
              hand_lift=0.05, foot_lift=0.12, sway=0.028, twist=6.0, head_up=-16.0, look=8.0,
              spine_pitch=5.0, hand_dir=V(0, -0.35, 1.0), foot_pitch=-18.0, knee_dir=V(0.75, -0.6, 0.10))
WALL = dict(rise=0.5, n=42, hx=0.30, fx=0.22, yc=-0.33, P0=0.885, py=0.06,
            hz=(1.75, 1.50), fz=(0.10, 0.34),
            hand_lift=0.05, foot_lift=0.10, sway=0.04, twist=7.0, head_up=-14.0, look=9.0,
            spine_pitch=3.0, hand_dir=V(0, -0.25, 1.0), foot_pitch=-30.0, knee_dir=V(1.0, -0.55, 0.05))


def climb_pose(u, c, dz_shift=0.0, head_bias=0.0):
    rise = c["rise"]
    P = Pose()
    root_z = rise * u + dz_shift
    P.root = V(0, 0, root_z)
    s1 = math.sin(TAU * u)
    P.pelvis = V(-c["sway"] * s1, c["py"] + 0.012 * math.cos(2 * TAU * u), c["P0"] + root_z + 0.010 * math.sin(2 * TAU * u + 0.6))
    hands, feet = {}, {}
    for side, sx, mh, mf, i in (("l", 1, 0.5, 0.0, 0), ("r", -1, 0.0, 0.5, 1)):
        dz, w = hold_move(u, mh, rise)
        z = c["hz"][i] + dz
        y = c["yc"]
        x = sx * c["hx"]
        if w is not None:
            y += c["hand_lift"] * math.sin(math.pi * w)
            x += sx * 0.03 * math.sin(math.pi * w)
            z += 0.04 * math.sin(math.pi * w)          # a little arc over the next hold
        d = c["hand_dir"]
        hands[side] = (V(x, y, z + dz_shift), V(d.x, d.y, d.z), V(0, -1, 0.15), grip_curve(w))
        dzf, wf = hold_move(u, mf, rise)
        zf = c["fz"][i] + dzf
        yf = c["yc"]
        xf = sx * c["fx"]
        pitch = c["foot_pitch"]
        if wf is not None:
            yf += c["foot_lift"] * math.sin(math.pi * wf)
            xf += sx * 0.04 * math.sin(math.pi * wf)
            zf += 0.05 * math.sin(math.pi * wf)
            pitch = lerp(c["foot_pitch"], 25.0, math.sin(math.pi * wf))
        feet[side] = (V(xf, yf, zf + dz_shift), sx * 12.0, pitch, 0.0)
    kd = c["knee_dir"]
    set_limbs(P, hands, feet, {"l": V(kd.x, kd.y, kd.z), "r": V(-kd.x, kd.y, kd.z)},
              {"l": V(0.9, 0.35, -0.5), "r": V(-0.9, 0.35, -0.5)})
    # secondary motion: twist to the reaching shoulder, look up to the reaching hand, hips roll with the weight
    set_torso(P, (0, 2.0 * s1, 0), (c["spine_pitch"], -1.5 * s1, c["twist"] * s1),
              (c["head_up"] + head_bias - 3.0 * math.cos(2 * TAU * u), 0, -c["look"] * s1))
    return P


def climb_poses(c, down=False):
    n = c["n"]
    out = []
    for i in range(n + 1):
        u = i / n
        if down:
            out.append(climb_pose(1.0 - u, c, dz_shift=-c["rise"], head_bias=24.0))
        else:
            out.append(climb_pose(u, c))
    return out


@clip
def Ladder_Climb_Up():
    return climb_poses(LADDER), True


@clip
def Ladder_Climb_Down():
    return climb_poses(LADDER, down=True), True


@clip
def Wall_Climb_Up():
    return climb_poses(WALL), True


# ------------------------------------------------------------------ ledge
LEDGE_TOP = 2.12
LEDGE_FACE = -0.20


def ledge_hands(x, z_lift=0.0, lift_w=0.0):
    """hand on the ledge top: palm down, fingers over the edge"""
    G = V(x, -0.27, LEDGE_TOP + 0.02 + z_lift)
    return (G, V(0, -1.0, -0.05), V(0, 0.0, -1.0), 0.15)


def hang_body(P, sway_x, sway_y, u, look_amp=10.0):
    """pelvis + feet + torso of the hanging body, arms reach the ledge"""
    P.pelvis = V(sway_x, sway_y - 0.02, 1.125 + 0.006 * math.sin(TAU * u * 2))
    ph = TAU * u
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        lag = 0.05 * math.sin(ph - 0.9 + (0.0 if side == "l" else 0.5))
        feet[side] = (V(sx * 0.10 + sway_x * 0.5, 0.10 + sway_y * -0.9 + lag, 0.20 + 0.012 * math.sin(2 * ph + (0 if side == "l" else 1.7))),
                      sx * 8.0, 40.0, 0.0)
    return feet


def hang_pose(u, n_dx=0.0):
    P = Pose()
    ph = TAU * u
    sway_x = 0.012 * math.sin(ph + 0.5)
    sway_y = 0.022 * math.sin(ph)
    hands = {"l": ledge_hands(0.21), "r": ledge_hands(-0.21)}
    feet = hang_body(P, sway_x, sway_y, u)
    set_limbs(P, hands, feet, {"l": V(0.15, -1.0, 0.1), "r": V(-0.15, -1.0, 0.1)},
              {"l": V(1.0, 0.3, -0.1), "r": V(-1.0, 0.3, -0.1)})
    # breathing + pendulum: chest pitch, glance up to the ledge and to both sides
    set_torso(P, (-2.0 * math.sin(ph), 0, 0), (-4.0 + 1.2 * math.sin(2 * ph), 1.5 * math.sin(ph + 0.5), 3.0 * math.sin(ph)),
              (-16.0 + 4.0 * math.sin(2 * ph + 1.0), 0, 14.0 * math.sin(ph - 0.4)))
    return P


@clip
def Ledge_Hang_Idle():
    n = 60
    return [hang_pose(i / n) for i in range(n + 1)], True


def shimmy_pose(u, sign):
    """Four hand steps per 1 s cycle (lead hand, trail hand, lead hand, trail hand), 0.25 m each, so every hand moves 0.5 m
    per cycle and the body travels 0.5 m (root X). Hands lift 3 cm and place; feet drag and swing behind the body."""
    P = Pose()
    ph = TAU * u
    step_len = 0.25
    starts = {"lead": (0.00, 0.50), "trail": (0.25, 0.75)}
    dur = 0.22
    hx = {}
    lifts = {}
    grips = {}
    for side, sx in (("l", 1), ("r", -1)):
        role = "lead" if sx * sign > 0 else "trail"
        lift = 0.0
        x = sx * 0.21
        for s0 in starts[role]:
            if u >= s0 + dur:
                x += sign * step_len
            elif u >= s0:
                w = (u - s0) / dur
                x += sign * step_len * smooth(w)
                lift = math.sin(math.pi * w)
        hx[side] = x
        lifts[side] = lift
        grips[side] = 0.15 + 0.4 * lift
    travel = sign * 0.5 * u
    P.root = V(travel, 0, 0)
    mean_x = (hx["l"] + hx["r"]) * 0.5
    # body follows the mean hand position with a little lag; leans into the move
    lag = 0.03 * sign
    P.pelvis = V(mean_x - lag * math.cos(2 * ph) * 0.5, -0.02 + 0.012 * math.sin(2 * ph), 1.125 + 0.006 * math.sin(4 * ph))
    hands = {}
    for side, sx in (("l", 1), ("r", -1)):
        G = V(hx[side], -0.27, LEDGE_TOP + 0.02 + 0.02 * lifts[side])
        hands[side] = (G, V(0, -1.0, -0.05), V(0, 0.0, -1.0), grips[side])
    feet = {}
    for side, sx in (("l", 1), ("r", -1)):
        drag = -sign * 0.10
        feet[side] = (V(mean_x + sx * 0.10 + drag * (1 if side == "l" else 0.8) + 0.03 * sign * math.sin(2 * ph + (0 if side == "l" else 1.5)),
                        0.10 + 0.04 * math.sin(2 * ph + (0.3 if side == "l" else 1.9)),
                        0.20 + 0.02 * math.sin(2 * ph + (0.0 if side == "l" else 1.7))), sx * 8.0, 40.0, 0.0)
    set_limbs(P, hands, feet, {"l": V(0.15, -1.0, 0.1), "r": V(-0.15, -1.0, 0.1)},
              {"l": V(1.0, 0.3, -0.1), "r": V(-1.0, 0.3, -0.1)})
    set_torso(P, (-2.0, 0, 0), (-3.0, 4.0 * sign * math.sin(2 * ph - 0.6) + 2.0 * sign, 3.0 * math.sin(2 * ph)),
              (-14.0, 0, 8.0 * sign * math.sin(2 * ph - 0.6)))
    return P


@clip
def Ledge_Shimmy_L():
    n = 30
    return [shimmy_pose(i / n, 1) for i in range(n + 1)], True


@clip
def Ledge_Shimmy_R():
    n = 30
    return [shimmy_pose(i / n, -1) for i in range(n + 1)], True
