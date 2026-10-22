# TOWN-LIFE clips, part 1: market, guard, shopkeeper, reading/writing.  (helpers below are shared by
# life_clips_tavern.py / life_clips_rest.py, which import them from here.)
#
# Authoring rules used for every clip in the three town modules:
#   * loops are built with looped(): the last key restores every field the loop touched, and every procedural layer
#     (breathing, micro sway, head drift) uses integer harmonics of the clip length, so frame n == frame 0
#   * feet are IK-pinned: a foot only moves when a key moves it; weight shifts move the pelvis over the planted foot
#   * hands that touch something (counter, table, mug, book) are world targets, so they stay planted while the
#     body breathes / shifts around them
#   * secondary motion: breathing, head drift with an offset phase, a glance now and then, shoulder settle
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V, stance, rel
from life_common import (life_clip, neutral, st, grip_o, wrist_at, grip_of, two_hand, walk_cycle, hold, to_from,
                         breathe, chain, sinw, speed_of)

# ------------------------------------------------------------------ helpers
FPS = 30
PALM_DN = ((0.0, -1.0, 0.0), (0.0, 0.0, -1.0))     # fingers forward, palm down (both hands)
PALM_UP = ((0.0, -1.0, 0.1), (0.0, 0.0, 1.0))      # fingers forward, palm up
HANG_L = ((0.05, 0.0, -1.0), (-1.0, 0.0, 0.0))     # relaxed hanging hands (as neutral())
HANG_R = ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0))


def _F():
    return CC.F


def looped(base, n, keys, post=None, ease_back="smooth"):
    """Loop builder. base = full state at frame 0 and n. keys = [(frame, changes[, ease]), ...] with 0 < frame < n.
    The closing key at n restores every field any key touched, so the loop closes exactly."""
    touched = set()
    for k in keys:
        touched |= set(k[1].keys()) - {"_bow"}
    ks = [(0, dict(base))] + [tuple(k) for k in keys] + [(n, {t: base[t] for t in touched}, ease_back)]
    return _F().build(ks, n, post=post)


def oneshot(base, n, keys, post=None):
    """One-shot builder: start and end at base (a crossfade to/from Idle is then seamless)."""
    return looped(base, n, keys, post=post)


def contra(w, amt=1.0):
    """weight shift over the left (w>0) or right (w<0) leg: pelvis over the planted foot, free hip drops, chest counter"""
    return {"pel": V(0.036 * w * amt, 0, -0.006 * abs(w) * amt), "hip": (0.0, -2.0 * w * amt, -3.4 * w * amt),
            "tor": (2.0, 2.0 * w * amt, 2.6 * w * amt)}


def idle_layer(k=1, head=1.0, pel=0.0035, tor=0.7, sway=0.0, seed=0.0):
    """post(): breathing + slow head drift + optional lateral sway (all integer harmonics -> loops close)"""
    def post(fr, n, s):
        w = sinw(fr, n, k)
        s["pel"] = Vector(s["pel"]) + V(sway * sinw(fr, n, k, 0.25 + seed), 0, pel * w)
        t = s["tor"]
        s["tor"] = (t[0] + tor * w, t[1], t[2])
        h = s["head"]
        s["head"] = (h[0] + head * 0.8 * sinw(fr, n, 2, 0.1 + seed), h[1] + head * 1.6 * sinw(fr, n, k, 0.3 + seed),
                     h[2] + head * 0.5 * sinw(fr, n, k, seed))
    return post


def seat_pose(seat_z, y=0.0, lean=0.0, feet_out=0.13, foot_y=None, knee_out=0.0):
    """sitting pelvis on a seat of height seat_z (pelvis 0.10 above it): pelvis offset, both feet flat on the floor
    slightly behind the knees. y = pelvis offset toward the back (+y = back), lean = torso pitch fwd (deg)."""
    d = {"pel": V(0, y, seat_z + 0.10 - 0.917), "tor": (lean, 0.0, 0.0)}
    hipy = 0.05 + y
    fy = hipy - 0.34 if foot_y is None else foot_y
    d.update({"foot_l": V(feet_out + knee_out, fy, 0.104), "foot_r": V(-feet_out - knee_out, fy, 0.104),
              "fyaw_l": 4.0 + knee_out * 40, "fyaw_r": -4.0 - knee_out * 40, "fpit_l": 0.0, "fpit_r": 0.0})
    return d


# ------------------------------------------------------------------ MARKET
STALL = {"type": "market_stall", "at": [0.0, 0.62, 0.90], "size": [1.4, 0.55, 0.90], "offset": [0.0, 0.0, 0.35],
         "face": "anchor"}

_MC = neutral()
_MC.update(stance(0.15, 0.0, -0.15, 0.05, 8.0, -8.0))
_MC["tor"] = (0.0, 0.0, 0.0)
_MC["hand_l"] = V(0.29, 0.02, 1.02)
_MC["hand_r"] = V(-0.27, 0.04, 0.96)
_MC["elb_l"] = V(0.42, 0.22, 1.12)
_MC["elb_r"] = V(-0.40, 0.22, 1.05)
_MC["ho_r"] = ((-0.1, -0.2, -1.0), (0.9, 0.0, 0.1))
_MC["ho_l"] = ((0.1, -0.3, -1.0), (-1.0, 0.0, 0.0))


@life_clip("Life_Market_Call_Out", loop=True, category="work/market", tags=["vendor", "shout"],
           anchor=dict(STALL), events={"call": [18, 37]},
           note="vendor hawking wares: right hand cupped at the mouth, chest lifts on the inhale and drives on each shout; "
                "left arm beckons twice; head scans the crowd")
def _market_call():
    b = _MC
    cup = {"hand_r": V(-0.15, -0.11, 1.53), "elb_r": V(-0.36, 0.06, 1.38), "ho_r": ((0.55, -0.55, 0.62), (0.62, 0.15, -0.75)),
           "curl_r": 0.35}
    keys = [
        (5, {"pel": V(0, 0.005, -0.012), "tor": (5.0, 0, 0), "head": (2.0, 12.0, 0), "hand_r": V(-0.25, -0.02, 1.08),
             "elb_r": V(-0.38, 0.14, 1.10)}, "out2"),
        (13, dict(cup, **{"pel": V(0, -0.005, 0.006), "tor": (-6.0, 4.0, 0), "head": (-5.0, 8.0, 0)}), "smooth"),
        (18, {"tor": (3.0, 4.0, 0), "head": (-3.0, 4.0, 0), "pel": V(0, -0.012, -0.004), "hand_r": V(-0.15, -0.12, 1.535)}, "in2"),
        (24, {"tor": (-2.0, -2.0, 0), "head": (-6.0, -6.0, 0), "pel": V(0, -0.004, 0.003)}, "smooth"),
        (31, {"tor": (-6.0, -8.0, 0), "head": (-6.0, -14.0, 0), "pel": V(0, 0.0, 0.006)}, "smooth"),
        (37, {"tor": (3.0, -8.0, 0), "head": (-3.0, -12.0, 0), "pel": V(0, -0.012, -0.004)}, "in2"),
        (46, {"hand_r": V(-0.26, -0.05, 1.12), "elb_r": V(-0.38, 0.14, 1.12), "curl_r": 0.2, "ho_r": _MC["ho_r"],
              "tor": (1.0, 2.0, 0), "head": (0.0, 6.0, 0), "pel": V(0, 0, 0),
              "hand_l": V(0.34, -0.20, 1.12), "elb_l": V(0.46, 0.15, 1.15), "ho_l": ((0.0, -1.0, 0.25), (0.0, 0.0, 1.0)),
              "curl_l": -0.5}, "smooth"),
        (54, {"hand_l": V(0.34, -0.40, 1.22), "elb_l": V(0.48, 0.05, 1.18), "curl_l": -0.7,
              "tor": (0.0, -4.0, 0), "head": (-2.0, -8.0, 0)}, "out2"),
        (59, {"hand_l": V(0.27, -0.20, 1.14), "curl_l": 0.9, "elb_l": V(0.44, 0.15, 1.12)}, "in2"),
        (65, {"hand_l": V(0.34, -0.42, 1.24), "curl_l": -0.7, "elb_l": V(0.48, 0.05, 1.18), "head": (-2.0, 8.0, 0), "tor": (0, 3.0, 0)}, "out2"),
        (70, {"hand_l": V(0.27, -0.20, 1.14), "curl_l": 0.9, "elb_l": V(0.44, 0.15, 1.12)}, "in2"),
        (84, {"hand_l": _MC["hand_l"], "elb_l": _MC["elb_l"], "ho_l": _MC["ho_l"], "curl_l": 0.25, "tor": (0, 0, 0),
              "head": (2.0, 0.0, 0)}, "smooth"),
    ]
    return looped(b, 96, keys, post=idle_layer(1, 0.6))


@life_clip("Life_Market_Hand_Over", loop=False, category="work/market", tags=["vendor", "trade", "give"],
           props=[{"id": "bread", "hand": "r"}, {"id": "coin", "hand": "l"}], anchor=dict(STALL),
           events={"take": [17], "offer": [40], "release": [46], "coin_receive": [58], "pocket": [84]},
           note="vendor takes the item from the stall table (0.9 m), holds it out to a customer 0.8 m in front, "
                "catches the coin in the left palm and pockets it. Hide the bread at 'release', show the coin at 'coin_receive', hide at 'pocket'.")
def _market_hand_over():
    b = _MC
    keys = [
        (7, {"tor": (10.0, -5.0, 0), "head": (14.0, -10.0, 0), "pel": V(0, -0.02, -0.02),
             "hand_r": V(-0.20, -0.36, 1.05), "elb_r": V(-0.40, 0.05, 1.08), "curl_r": 0.0, "ho_r": PALM_DN}, "out2"),
        (13, {"tor": (24.0, -8.0, 0), "head": (20.0, -12.0, 0), "pel": V(0, -0.08, -0.045),
              "hand_r": V(-0.20, -0.44, 0.96), "elb_r": V(-0.42, 0.02, 1.04), "curl_r": 0.0, "ho_r": PALM_DN}, "smooth"),
        (17, {"curl_r": 0.9, "ho_r": ((0.2, -1.0, 0.0), (0.3, 0.0, -0.9))}, "in2"),
        (27, {"tor": (8.0, 4.0, 0), "head": (6.0, 8.0, 0), "pel": V(0, -0.03, -0.015),
              "hand_r": V(-0.15, -0.36, 1.14), "elb_r": V(-0.40, 0.02, 1.16)}, "smooth"),
        (38, {"tor": (6.0, 6.0, 0), "head": (-2.0, 10.0, 0), "pel": V(0, -0.045, -0.008),
              "hand_r": V(-0.08, -0.47, 1.16), "elb_r": V(-0.30, -0.02, 1.15), "ho_r": ((0.05, -1.0, 0.1), (1.0, 0.0, -0.3))}, "out2"),
        (46, {"curl_r": 0.9,
              "hand_l": V(0.14, -0.35, 1.03), "elb_l": V(0.40, 0.02, 1.02), "ho_l": PALM_UP, "curl_l": -0.3}, "smooth"),
        (50, {"hand_r": V(-0.10, -0.46, 1.15)}, "smooth"),
        (58, {"hand_l": V(0.13, -0.38, 1.06), "curl_l": -0.3}, "smooth"),
        (68, {"curl_l": 0.8, "tor": (5.0, 2.0, 0), "head": (6.0, 0.0, 0),
              "hand_r": V(-0.24, -0.06, 1.02), "elb_r": V(-0.40, 0.14, 1.06), "curl_r": 0.3, "ho_r": _MC["ho_r"]}, "smooth"),
        (72, {"hand_l": V(0.26, -0.14, 1.02), "elb_l": V(0.40, 0.14, 1.05), "tor": (10.0, 8.0, 0), "head": (24.0, 8.0, 0),
              "pel": V(0, -0.01, -0.012), "ho_l": ((0.1, -0.3, -1.0), (-1.0, 0.0, 0.0))}, "smooth"),
        (84, {"hand_l": V(0.19, -0.02, 0.92), "elb_l": V(0.36, 0.16, 1.0), "tor": (6.0, 4.0, 0), "head": (20.0, 6.0, 0)}, "smooth"),
        (92, {"curl_l": 0.25, "hand_l": _MC["hand_l"], "elb_l": _MC["elb_l"], "tor": (0.0, 0.0, 0), "head": (0.0, 0.0, 0),
              "pel": V(0, 0, 0)}, "smooth"),
    ]
    return oneshot(b, 100, keys, post=idle_layer(1, 0.4))


# ------------------------------------------------------------------ small pose helpers used below
def grip_hand(side, grip, tool_dir, knuckle):
    """(wrist, ho) that puts the fist centre on `grip` around a handle along tool_dir"""
    ho = grip_o(side, tool_dir, knuckle)
    return wrist_at(side, grip, ho), ho


def walk_loop(n=44, stride=0.34, lift=0.08, bob=0.022, sway=0.025, arm_l=0.10, arm_r=0.10, lean=2.0, width=0.10,
              hip_yaw=5.0, tor_yaw=-4.0, heel=12.0, toe=18.0, arm_lift=0.02, base=None, hand_follow_r=False):
    """In-place walk loop like life_common.walk_cycle but with a separate arm swing per hand (arm_r = 0 keeps the
    right hand on a carried prop). Stance lasts 60% of the cycle, so the authored ground speed is
    2*stride / (0.6 * n / 30) (see walk_speed)."""
    b = neutral()
    if base:
        b.update(base)

    def post(fr, nn, s):
        p = (fr % n) / float(n)
        for side, ph in (("l", 0.0), ("r", 0.5)):
            q = (p + ph) % 1.0
            sx = 1 if side == "l" else -1
            if q < 0.6:
                u = q / 0.6
                y = -stride + 2 * stride * u
                z = 0.104
                pit = heel * max(0.0, 1 - u / 0.15) - toe * max(0.0, (u - 0.8) / 0.2)
            else:
                u = (q - 0.6) / 0.4
                e = 0.5 - 0.5 * math.cos(math.pi * u)
                y = stride - 2 * stride * e
                z = 0.104 + lift * math.sin(math.pi * u)
                pit = -toe * (1 - u) * 0.6 + heel * max(0.0, (u - 0.7) / 0.3)
            s["foot_" + side] = V(sx * width, y, z)
            s["fpit_" + side] = pit
            s["fyaw_" + side] = sx * 4.0
            a = math.cos(2 * math.pi * q)
            other = "r" if side == "l" else "l"
            amp = arm_r if other == "r" else arm_l
            s["hand_" + other] = Vector(b["hand_" + other]) + V(0, -amp * a, arm_lift * max(0.0, a) * (amp > 0))
        dz = -bob * 0.5 + bob * 0.5 * math.cos(4 * math.pi * p)
        dx = sway * math.sin(2 * math.pi * p)
        s["pel"] = Vector(b["pel"]) + V(dx, 0, dz)
        s["hip"] = (b["hip"][0], hip_yaw * math.sin(2 * math.pi * p), b["hip"][2] + 3.0 * math.sin(2 * math.pi * p))
        s["tor"] = (b["tor"][0] + lean, tor_yaw * math.sin(2 * math.pi * p), b["tor"][2])
        if hand_follow_r:      # carried prop: the right hand and elbow ride with the pelvis
            s["hand_r"] = Vector(b["hand_r"]) + V(dx, 0, dz)
            if b.get("elb_r") is not None:
                s["elb_r"] = Vector(b["elb_r"]) + V(dx, 0, dz)
    return _F().build([(0, b), (n, b)], n, post=post)


def walk_speed(stride, n):
    return round(2 * stride / (0.6 * n / 30.0), 3)


# ------------------------------------------------------------------ GUARD
SPEAR_KN = (0.5, -0.85, 0.0)

_GA = neutral()
_GA.update(stance(0.11, 0.0, -0.11, 0.0, 5.0, -5.0))
_w, _h = grip_hand("r", V(-0.27, -0.03, 0.89), (0.0, 0.0, 1.0), SPEAR_KN)
_GA.update({"hand_r": _w, "ho_r": _h, "curl_r": 0.95, "elb_r": V(-0.40, 0.10, 1.12),
            "hand_l": V(0.245, 0.05, 0.93), "curl_l": 0.85, "elb_l": None,
            "pel": V(0, 0, -0.02), "tor": (-1.0, 0.0, -3.0)})


@life_clip("Life_Guard_Attention", loop=True, category="work/guard", props=[{"id": "spear", "hand": "r"}],
           tags=["guard", "post"], events={"glance": [38]},
           note="guard at attention: spear upright in the right hand beside the hip, chest up, chin level, a rare glance and a small "
                "heel-shift. The spear model puts the grip 0.75 m above the butt, so at this hand height (0.89 m) the butt hovers ~0.14 m "
                "above the ground: move the prop origin ~0.2 m toward the tip to ground it")
def _guard_attention():
    keys = [
        (26, {"head": (0.0, -7.0, 0.0), "tor": (-1.0, -2.0, -3.0)}, "smooth"),
        (52, {"head": (0.0, -8.0, 0.0), "tor": (-1.0, -2.0, -3.0)}, "smooth"),
        (64, {"head": (1.0, 3.0, 0.0), "tor": (-1.0, 1.0, -3.0), "pel": V(0.006, 0, -0.02)}, "smooth"),
        (100, {"pel": V(-0.005, 0, -0.018), "hip": (0.0, 0.0, 0.8)}, "smooth"),
    ]
    return looped(_GA, 120, keys, post=idle_layer(1, 0.25, pel=0.003, tor=0.5))


_GL = neutral()
_GL.update(contra(0.8))
_GL.update({"foot_l": V(0.14, 0.02, 0.104), "foot_r": V(-0.21, -0.07, 0.104), "fyaw_l": 6.0, "fyaw_r": -18.0})
_GL.update(two_hand(V(-0.17, -0.15, 0.90), (0.0, 0.0, 1.0), SPEAR_KN, 0.32, (0.35, -0.9, 0.0)))
_GL.update({"tor": (5.0, 3.0, 2.6), "head": (2.0, 0.0, 0.0), "pel": V(0.03, -0.015, -0.012),
            "elb_r": V(-0.38, 0.05, 1.05), "elb_l": V(0.36, 0.10, 1.12)})


@life_clip("Life_Guard_Lean_Spear", loop=True, category="work/guard", props=[{"id": "spear", "hand": "r"}],
           ik_l_on_prop=0.32, tags=["guard", "idle"], events={"glance": [34, 100]},
           note="guard leaning his weight on a planted spear, both hands on the shaft, weight on the left leg, right foot "
                "relaxed forward; two glances and a shift of the chest over the spear")
def _guard_lean():
    g = _GL
    keys = [
        (16, {"pel": V(0.03, -0.02, -0.016), "tor": (7.0, 3.0, 2.6), "head": (3.0, 0.0, 0.0)}, "smooth"),
        (30, {"head": (2.0, -24.0, 2.0), "tor": (9.0, -3.0, 2.6)}, "smooth"),
        (52, {"head": (3.0, -26.0, 2.0), "tor": (9.0, -3.0, 2.6)}, "smooth"),
        (64, {"head": (4.0, 4.0, 0.0), "tor": (6.0, 3.0, 2.6), "pel": V(0.03, -0.015, -0.012)}, "smooth"),
        (84, {"pel": V(0.006, -0.01, -0.006), "hip": (0.0, 0.0, -1.0), "tor": (4.0, 1.0, 0.5), "head": (3.0, 8.0, 0.0)}, "smooth"),
        (98, {"head": (-3.0, 22.0, -2.0), "tor": (5.0, 6.0, 0.5)}, "smooth"),
        (114, {"head": (-3.0, 24.0, -2.0)}, "smooth"),
        (128, {"pel": V(0.03, -0.015, -0.012), "hip": g["hip"], "tor": g["tor"], "head": g["head"]}, "smooth"),
    ]
    return looped(g, 144, keys, post=idle_layer(1, 0.4, pel=0.003, tor=0.6))


_GP = neutral()
_GP["tor"] = (0.0, 0.0, 0.0)
_GP["pel"] = V(0, 0, -0.075)
_w, _h = grip_hand("r", V(-0.27, -0.10, 1.17), (-0.10, 0.62, 0.78), (0.4, -0.9, 0.0))
_GP.update({"hand_r": _w, "ho_r": _h, "curl_r": 0.95, "elb_r": V(-0.42, 0.10, 1.10),
            "hand_l": V(0.27, 0.05, 0.85), "curl_l": 0.7})
_GUARD_N = 40


@life_clip("Life_Guard_Patrol_Walk", loop=True, category="walk/style", props=[{"id": "spear", "hand": "r"}],
           speed_mps=walk_speed(0.30, _GUARD_N), tags=["guard", "walk", "in_place"], events={"step_l": [0], "step_r": [20]},
           note="measured guard patrol stride, spear resting on the right shoulder (right hand steady in front of the chest, "
                "left arm swinging short), upright chest, chin level")
def _guard_walk():
    return walk_loop(_GUARD_N, stride=0.30, lift=0.075, bob=0.02, sway=0.02, arm_l=0.09, arm_r=0.0, lean=1.5,
                     hip_yaw=4.0, tor_yaw=-3.5, base=_GP, hand_follow_r=True)


_GK = neutral()
_GK.update(stance(0.12, 0.0, -0.12, 0.02, 5.0, -5.0))
_w, _h = grip_hand("r", V(-0.27, -0.03, 0.93), (0.0, 0.0, 1.0), SPEAR_KN)
_GK.update({"hand_r": _w, "ho_r": _h, "curl_r": 0.95, "elb_r": V(-0.40, 0.10, 1.12), "tor": (-1.0, 0.0, -3.0), "pel": V(0, 0, -0.02),
            "hand_l": V(0.25, 0.05, 0.93), "curl_l": 0.7})
_SHADE_HO = ((-0.85, -0.5, 0.1), (0.0, 0.1, -1.0))


@life_clip("Life_Guard_Look_Out", loop=False, category="work/guard", props=[{"id": "spear", "hand": "r"}],
           tags=["guard", "scan"], events={"scan_left": [40], "scan_right": [62]},
           note="guard shades his eyes with the left hand (spear planted in the right) and scans left then right")
def _guard_lookout():
    hand_up = {"hand_l": V(0.09, -0.14, 1.665), "elb_l": V(0.36, 0.05, 1.56), "ho_l": _SHADE_HO, "curl_l": -0.6}
    keys = [
        (6, {"tor": (-3.0, 0.0, -3.0), "head": (-2.0, 0.0, 0.0), "pel": V(0, 0.005, -0.016)}, "out2"),
        (20, dict(hand_up, **{"tor": (-3.0, 0.0, -3.0), "head": (-6.0, 6.0, 0.0)}), "smooth"),
        (26, {"head": (-8.0, 22.0, 0.0), "tor": (-3.0, 10.0, 0.0), "pel": V(0.01, 0.005, 0.004)}, "smooth"),
        (40, {"head": (-8.0, 40.0, 0.0), "tor": (-3.0, 22.0, 0.0), "hip": (0.0, 8.0, 0.0)}, "smooth"),
        (48, {"head": (-9.0, 48.0, 0.0)}, "smooth"),
        (62, {"head": (-8.0, -38.0, 0.0), "tor": (-3.0, -22.0, 0.0), "hip": (0.0, -8.0, 0.0), "pel": V(-0.01, 0.005, 0.004)}, "smooth"),
        (70, {"head": (-9.0, -46.0, 0.0)}, "smooth"),
        (80, {"head": (-4.0, 0.0, 0.0), "tor": (-2.0, 0.0, -3.0), "hip": (0.0, 0.0, 0.0), "pel": V(0, 0.003, -0.018)}, "smooth"),
        (92, {"hand_l": _GK["hand_l"], "elb_l": None, "ho_l": _GK["ho_l"], "curl_l": 0.7, "head": (0.0, 0.0, 0.0),
              "tor": _GK["tor"], "pel": _GK["pel"]}, "smooth"),
    ]
    return oneshot(_GK, 104, keys, post=idle_layer(1, 0.2, pel=0.002, tor=0.4))


# ------------------------------------------------------------------ SHOPKEEPER
COUNTER = {"type": "shop_counter", "at": [0.0, 0.70, 1.00], "size": [1.6, 0.70, 1.00], "offset": [0.0, 0.0, 0.35],
           "face": "anchor"}
CT_Z = 1.035          # wrist height for a flat hand on the counter top
_SC = neutral()
_SC.update(stance(0.13, 0.0, -0.13, 0.03, 6.0, -6.0))
_SC.update({"hand_l": V(0.29, -0.36, CT_Z), "hand_r": V(-0.29, -0.36, CT_Z), "ho_l": PALM_DN, "ho_r": PALM_DN,
            "curl_l": -0.3, "curl_r": -0.3, "elb_l": V(0.50, 0.05, 1.12), "elb_r": V(-0.50, 0.05, 1.12),
            "pel": V(0, -0.045, -0.022), "tor": (16.0, 0.0, 0.0), "head": (-6.0, 0.0, 0.0)})


@life_clip("Life_Shop_Counter_Lean", loop=True, category="work/shop", anchor=dict(COUNTER), tags=["shopkeeper", "idle"],
           events={"tap": [86, 92, 98]},
           note="shopkeeper waiting at the counter: both palms flat on the top (planted), weight rocks from foot to foot, "
                "glances at the street, drums the right fingers once")
def _shop_lean():
    b = _SC
    def shift(w, pitch=16.0):
        c = contra(w, 0.9)
        return {"pel": V(c["pel"].x, -0.045, -0.022 - 0.006 * abs(w)), "hip": c["hip"], "tor": (pitch, c["tor"][1], c["tor"][2] * 1.2)}
    keys = [
        (24, dict(shift(0.9), head=(-3.0, 10.0, 2.0)), "smooth"),
        (48, dict(shift(0.9), head=(-2.0, 14.0, 2.0)), "smooth"),
        (62, dict(shift(0.0, 17.0), head=(-8.0, -6.0, 0.0)), "smooth"),
        (86, dict(shift(-0.9, 15.0), head=(-2.0, -20.0, -2.0), curl_r=-0.3), "smooth"),
        (90, {"curl_r": 0.6}, "in2"), (94, {"curl_r": -0.3}, "out2"), (98, {"curl_r": 0.6}, "in2"), (102, {"curl_r": -0.3}, "out2"),
        (108, {"head": (-2.0, -22.0, -2.0)}, "smooth"),
        (128, dict(shift(-0.4, 16.0), head=(-6.0, 0.0, 0.0)), "smooth"),
    ]
    return looped(b, 144, keys, post=idle_layer(1, 0.4, pel=0.003, tor=0.6))


@life_clip("Life_Shop_Wipe", loop=True, category="work/shop", anchor=dict(COUNTER), tags=["shopkeeper", "clean"],
           events={"stroke": [0, 18, 36, 54]},
           note="shopkeeper wipes the counter in wide circles with a cloth in the right hand (palm flat on the top), the whole "
                "chest and head follow the hand, the left hand steadies on the counter")
def _shop_wipe():
    b = dict(_SC)
    b["hand_l"] = V(0.31, -0.40, CT_Z)
    b["tor"] = (21.0, 0.0, 0.0)
    b["pel"] = V(0, -0.09, -0.035)

    def post(fr, n, s):
        ph = 2 * math.pi * 2 * fr / n
        drift = 0.07 * math.sin(2 * math.pi * fr / n)
        cx, cy = -0.08 + drift, -0.44
        rx, ry = 0.13, 0.07
        c, sn = math.cos(ph), math.sin(ph)
        x, y = cx + rx * c, cy + ry * sn
        s["hand_r"] = V(x, y, CT_Z)
        s["elb_r"] = V(-0.48 + 0.6 * (x - cx), 0.04 + 0.5 * (y - cy), 1.12)
        u = (x - cx) / rx
        v = (y - cy) / ry
        t = s["tor"]
        s["tor"] = (t[0] - 3.5 * v + 0.6 * math.sin(2 * math.pi * fr / n), t[1] + 9.0 * u + 4.0 * drift / 0.07, t[2] - 2.0 * u)
        s["pel"] = Vector(s["pel"]) + V(0.018 * u + 0.02 * drift / 0.07, -0.012 * v, 0.0)
        h = s["head"]
        s["head"] = (h[0] - 4.0 * v, h[1] + 8.0 * u, h[2])
    return _F().build([(0, b), (72, b)], 72, post=post)


# quill helper (used by Life_Shop_Tally and Life_Write_Desk)
QDIR = Vector((-0.30, 0.50, 0.81)).normalized()
QKN = (0.55, -0.65, -0.2)
QHO = grip_o("r", tuple(QDIR), QKN)


def nib_hand(p):
    """wrist target that puts the quill nib (0.07 m from the fist centre against the thumb axis) on point p"""
    return wrist_at("r", Vector(p) + QDIR * 0.07, QHO)


def quill_clip(n, z, xa, xb, y, ink, base, head_pitch, torso_yaw_range=8.0, ink_frames=(72, 96), elb_z=None):
    """macro keys + micro post for a writing loop: write a line from xa to xb, lift, dip in the ink pot, come back"""
    zl = z + 0.07
    ez = elb_z if elb_z is not None else z + 0.10
    def K_(f, p, extra=None, ease="smooth"):
        d = {"hand_r": nib_hand(p), "elb_r": V(-0.42 + (p[0] + 0.05) * 0.5, 0.02, ez), "ho_r": QHO, "curl_r": 0.75}
        if extra:
            d.update(extra)
        return (f, d, ease)
    base = dict(base)         # frame 0 / n: the hand hovers over the start of the line, ready to write
    base.update({"hand_r": nib_hand(V(xa, y, z + 0.03)), "elb_r": V(-0.42 + (xa + 0.05) * 0.5, 0.02, ez), "ho_r": QHO, "curl_r": 0.75})
    a = V(xa, y, z + 0.018)
    b_ = V(xb, y - 0.012, z + 0.002)
    i0, i1 = ink_frames
    keys = [
        K_(6, V(xa, y, z + 0.002), {"head": (head_pitch, 0, 0)}, "smooth"),
        K_(int(n * 0.14), V(xa + (xb - xa) * 0.25, y - 0.003, z + 0.002), None, "lin"),
        K_(int(n * 0.27), V(xa + (xb - xa) * 0.55, y - 0.008, z + 0.002), {"tor": (base["tor"][0] + 1.5, torso_yaw_range * -0.5, 0)}, "lin"),
        K_(int(n * 0.41), b_, {"tor": (base["tor"][0] + 2.5, -torso_yaw_range, 0), "head": (head_pitch + 2, -6, 0)}, "lin"),
        K_(int(n * 0.46), V(xb - 0.02, y - 0.012, z + 0.05), None, "out2"),
        K_(i0, V(ink[0], ink[1], z + 0.06), {"tor": (base["tor"][0] - 1.0, torso_yaw_range * -1.6, 0), "head": (head_pitch - 4, -14, 0)}, "smooth"),
        K_(i0 + 6, V(ink[0], ink[1], z + 0.012), None, "in2"),
        K_(i0 + 11, V(ink[0], ink[1], z + 0.05), None, "out2"),
        K_(i1, V(ink[0] * 0.5 + xa * 0.5, ink[1] * 0.5 + y * 0.5, z + 0.06), {"tor": base["tor"], "head": (head_pitch, 4, 0)}, "smooth"),
        K_(int(n * 0.86), V(xa, y, z + 0.03), {"head": (head_pitch - 4, 8, 0)}, "smooth"),
    ]
    def post(fr, nn, s):
        # writing tremor: small strokes while the nib is on the paper
        a0, a1 = 8, int(n * 0.42)
        on = max(0.0, min(1.0, min((fr - a0) / 4.0, (a1 - fr) / 4.0)))
        k = max(1, n // 6)
        s["hand_r"] = Vector(s["hand_r"]) + V(0.006 * on * math.sin(2 * math.pi * k * fr / n),
                                                0.004 * on * math.sin(2 * math.pi * k * fr / n + 0.9), 0)
        w = math.sin(2 * math.pi * fr / n)
        s["pel"] = Vector(s["pel"]) + V(0, 0, 0.003 * w)
        t = s["tor"]
        s["tor"] = (t[0] + 0.6 * w, t[1], t[2])
    return looped(base, n, keys, post=post)


LEDGER = {"type": "shop_counter", "at": [0.0, 0.70, 1.00], "size": [1.6, 0.70, 1.00], "offset": [0.0, 0.0, 0.35],
          "face": "anchor", "note": "the ledger is a scene object lying flat on the counter (top 1.03 m, centre 0.5 m in front, 0.3 x 0.38 m); "
                                   "the left palm rests on its left edge, the quill writes on it",
          "extra": [{"at": [0.02, 0.50, 1.03], "size": [0.30, 0.38, 0.03]}]}
_ST = dict(_SC)
_ST.update({"hand_l": wrist_at("l", V(0.20, -0.40, 1.062), PALM_DN), "ho_l": PALM_DN, "curl_l": -0.25, "elb_l": V(0.48, 0.05, 1.12), "tor": (15.0, 0.0, 0.0),
            "head": (14.0, 0.0, 0.0), "pel": V(0, -0.07, -0.03)})
_ST["tor"] = (20.0, 0.0, 0.0)


@life_clip("Life_Shop_Tally", loop=True, category="work/shop", props=[{"id": "quill", "hand": "r"}],
           anchor=dict(LEDGER), tags=["shopkeeper", "write"], events={"dip": [78], "write_start": [6]},
           note="shopkeeper writing in the ledger (a flat scene object: with the prop grip contract a left-hand book cannot lie flat under the palm), left palm on its edge, right hand writes a line with the quill, "
                "lifts, dips it in the ink and comes back; head follows the nib")
def _shop_tally():
    return quill_clip(150, 1.03, 0.02, -0.16, -0.48, (-0.27, -0.40), _ST, 16.0, 7.0, (74, 98), elb_z=1.14)


# ------------------------------------------------------------------ READING / WRITING
# The book model (data/living_world/life_props.json) is 0.22 m wide x 0.38 m tall, its spine at the grip, and its body extends
# from the fist along the PALM normal (native +X -> t x f, which is the palm side of the RIGHT hand), so books are held in the
# right hand: thumb up the spine, palm toward the book body, front cover toward f.
BOOK_W, BOOK_H0 = 0.22, -0.225        # body width from the spine; the spine spans z -0.225..0.155 around the grip


def book_pose(grip, t_dir, out=(1.0, 0.0, 0.0)):
    """right-hand keys that hold the book with its spine at `grip`, spine axis t_dir (top edge), body extending along `out`
    (world direction of the palm normal); returns (wrist, ho, book_centre, book_bottom_centre)"""
    t = Vector(t_dir).normalized()
    o = Vector(out)
    f = o.cross(t)                      # right hand: n = t x f = o  ->  f = o x t
    ho = grip_o("r", tuple(t), tuple(f))
    w = wrist_at("r", grip, ho)
    g = Vector(grip)
    centre = g + o * (BOOK_W * 0.5) + t * (-0.035)
    bottom = g + o * (BOOK_W * 0.5) + t * BOOK_H0
    return w, ho, centre, bottom


_BT = (0.0, -0.50, 0.87)                # book spine axis: top edge tipped away from the reader
_bw, _bh, _bc, _bb = book_pose(V(-0.16, -0.30, 1.27), _BT)
_RS = neutral()
_RS.update(stance(0.13, 0.0, -0.13, 0.05, 6.0, -6.0))
_RS.update({"hand_r": _bw, "ho_r": _bh, "curl_r": 0.9, "elb_r": V(-0.33, 0.02, 1.16),
            "hand_l": V(0.10, _bb.y - 0.01, _bb.z - 0.03), "ho_l": ((-1.0, 0.0, 0.1), (0.0, 0.0, 1.0)), "curl_l": -0.1,
            "elb_l": V(0.30, 0.10, 1.05), "tor": (6.0, 0.0, 0.0), "head": (26.0, 0.0, 0.0), "pel": V(0, -0.01, -0.004)})


def _read_eyes(cycles):
    """post(): the head sweeps along the lines of text (a fast small yaw + a slow pitch step per line)"""
    def post(fr, n, s):
        h = s["head"]
        sweep = math.sin(2 * math.pi * cycles * fr / n)
        s["head"] = (h[0] + 1.6 * math.sin(2 * math.pi * fr / n * 2), h[1] + 2.4 * sweep, h[2])
    return post


def chain2(*posts):
    def post(fr, n, s):
        for p in posts:
            p(fr, n, s)
    return post


def _page_turn(b, hand_edge, hand_top, hand_over, f0, dur=26):
    """left-hand page-turn keys: pinch the near page corner, swing it over the top, settle back under the book"""
    return [
        (f0, {"hand_l": hand_edge, "curl_l": 0.4, "elb_l": V(0.32, 0.10, hand_edge.z - 0.02)}, "smooth"),
        (f0 + 6, {"curl_l": 0.75}, "in2"),
        (f0 + 14, {"hand_l": hand_top, "curl_l": 0.75, "_bow": {"hand_l": V(0, -0.02, 0.05)}}, "smooth"),
        (f0 + 20, {"hand_l": hand_over, "curl_l": 0.1}, "smooth"),
        (f0 + dur, {"hand_l": b["hand_l"], "curl_l": b["curl_l"], "elb_l": b["elb_l"]}, "smooth"),
    ]


@life_clip("Life_Read_Stand", loop=True, category="ambient/read", props=[{"id": "book", "hand": "r"}], tags=["read", "stand"],
           events={"page_turn": [98]},
           note="standing reader: book held by its edge in the right hand at the chest, the left hand cradles it from below, "
                "eyes sweep the lines, weight shifts, the left hand turns a page (book model: spine axis = thumb, body along the palm)")
def _read_stand():
    b = _RS
    edge = V(0.07, _bc.y - 0.02, _bc.z + 0.02)
    top = V(-0.02, _bc.y - 0.03, _bc.z + 0.12)
    over = V(-0.08, _bc.y - 0.03, _bc.z + 0.04)
    keys = [
        (30, dict(contra(0.5, 0.7), head=(24.0, 3.0, 0.0)), "smooth"),
        (58, dict(contra(0.5, 0.7), head=(26.0, -2.0, 0.0), pel=V(0.018, -0.01, -0.006)), "smooth"),
    ] + _page_turn(b, edge, top, over, 84) + [
        (118, {"head": (26.0, 0.0, 0.0), "pel": V(0, -0.01, -0.004), "hip": (0, 0, 0), "tor": b["tor"]}, "smooth"),
        (134, {"head": (24.0, -4.0, 0.0)}, "smooth"),
    ]
    return looped(b, 156, keys, post=chain2(idle_layer(1, 0.3, pel=0.003, tor=0.6), _read_eyes(6)))


_BT2 = (0.0, -0.62, 0.78)
_bw2, _bh2, _bc2, _bb2 = book_pose(V(-0.15, -0.25, 0.80), _BT2)
_RB = neutral()
_RB.update(seat_pose(0.45, 0.0, 6.0))
_RB.update({"hip": (0.0, 0.0, 0.0), "hand_r": _bw2, "ho_r": _bh2, "curl_r": 0.9, "elb_r": V(-0.33, 0.10, 0.75),
            "hand_l": V(0.10, _bb2.y - 0.01, _bb2.z - 0.03), "ho_l": ((-1.0, 0.0, 0.1), (0.0, 0.0, 1.0)), "curl_l": -0.1,
            "elb_l": V(0.30, 0.12, 0.72), "head": (32.0, 0.0, 0.0), "tor": (8.0, 0.0, 0.0)})
BENCH = {"type": "bench", "at": [0.0, 0.0, 0.45], "size": [1.3, 0.36, 0.45], "offset": [0.0, 0.05, 0.0], "face": "anchor"}


@life_clip("Life_Read_Sit", loop=True, category="ambient/read", props=[{"id": "book", "hand": "r"}], anchor=dict(BENCH),
           tags=["read", "sit", "bench"], events={"page_turn": [92]},
           note="reader seated on a bench (seat 0.45 m), book resting on the lap and steadied by the right hand at its edge, the left "
                "hand supports it and turns one page; head down, a neck stretch at the end")
def _read_sit():
    b = _RB
    edge = V(0.07, _bc2.y - 0.02, _bc2.z + 0.02)
    top = V(-0.02, _bc2.y - 0.03, _bc2.z + 0.12)
    over = V(-0.08, _bc2.y - 0.03, _bc2.z + 0.04)
    keys = [
        (34, {"head": (30.0, 5.0, 0.0), "tor": (9.0, 1.5, 0.0)}, "smooth"),
        (60, {"head": (33.0, -4.0, 0.0), "tor": (7.0, -1.0, 0.0)}, "smooth"),
    ] + _page_turn(b, edge, top, over, 84) + [
        (118, {"head": (31.0, 0.0, 0.0), "tor": b["tor"]}, "smooth"),
        (128, {"head": (16.0, 0.0, 4.0), "tor": (2.0, 0.0, 0.0)}, "smooth"),
        (138, {"head": (14.0, -10.0, 4.0), "tor": (2.0, -3.0, 0.0)}, "smooth"),
        (148, {"head": b["head"], "tor": b["tor"]}, "smooth"),
    ]
    return looped(b, 160, keys, post=chain2(idle_layer(1, 0.3, pel=0.003, tor=0.5), _read_eyes(6)))


TABLE = {"type": "table", "at": [0.0, 0.62, 0.75], "size": [1.4, 0.80, 0.75], "offset": [0.0, 0.0, 0.0], "face": "anchor",
         "extra": [{"at": [0.0, 0.0, 0.45], "size": [0.45, 0.42, 0.45]}, {"at": [0.0, 0.42, 0.757], "size": [0.30, 0.30, 0.014]}]}
_WD = neutral()
_WD.update(seat_pose(0.45, 0.0, 14.0))
_WD.update({"hand_l": wrist_at("l", V(0.24, -0.40, 0.80), PALM_DN), "ho_l": PALM_DN, "curl_l": -0.25,
            "elb_l": V(0.50, 0.10, 0.90), "head": (18.0, 0.0, 0.0), "tor": (15.0, 0.0, 0.0), "hip": (0, 0, 0)})


@life_clip("Life_Write_Desk", loop=True, category="ambient/write", props=[{"id": "quill", "hand": "r"}], anchor=dict(TABLE),
           tags=["write", "sit", "desk"], events={"dip": [76], "write_start": [6]},
           note="writer seated at a table (top 0.75 m): left palm holds the page, right hand writes with the quill, "
                "lifts, dips it in the ink pot at the right, returns; head follows the nib")
def _write_desk():
    return quill_clip(156, 0.765, 0.02, -0.17, -0.42, (-0.34, -0.34), _WD, 18.0, 6.0, (76, 100), elb_z=0.86)


# ------------------------------------------------------------------ MARKET (part 2: arranging goods / browsing)
_BR_HO_LOW = grip_o("r", (0.35, 0.10, 0.93), (0.3, -0.9, 0.0))
_BR_HO_FLAT = grip_o("r", (1.0, 0.0, 0.0), (0.0, -0.3, -0.95))
_BR_HO_TURN = grip_o("r", (-0.4, -0.2, 0.9), (0.4, -0.9, 0.2))
_BR_HO_SIDE = grip_o("r", (0.1, 0.6, 0.8), (0.4, -0.8, 0.4))

_AR = neutral()
_AR.update(stance(0.16, 0.0, -0.16, 0.05, 8.0, -8.0))
_AR.update({"pel": V(0, -0.05, -0.035), "tor": (20.0, 0.0, 0.0), "head": (10.0, 0.0, 0.0),
            "hand_r": wrist_at("r", V(-0.32, -0.40, 0.98), _BR_HO_FLAT), "ho_r": _BR_HO_FLAT, "curl_r": 0.4, "elb_r": V(-0.46, 0.05, 1.05),
            "hand_l": wrist_at("l", V(0.24, -0.40, 0.96), PALM_DN), "ho_l": PALM_DN, "curl_l": 0.1, "elb_l": V(0.44, 0.05, 1.02)})


@life_clip("Life_Market_Arrange", loop=True, category="work/market", props=[{"id": "bread", "hand": "r"}], anchor=dict(STALL),
           tags=["vendor", "arrange"], events={"pick": [20, 92], "place": [46, 118]},
           note="vendor arranging goods on the stall: picks a loaf from the pile on the right, sets it in the row, nudges it straight "
                "with a pat of the left hand, then a second loaf to another spot; head follows the hands, weight shifts on the feet")
def _market_arrange():
    b = _AR
    P0 = V(-0.34, -0.42, 0.98)       # pile
    def g(p, ho, **kw):
        d = {"hand_r": wrist_at("r", p, ho), "ho_r": ho}
        d.update(kw)
        return d
    keys = [
        (10, g(V(-0.34, -0.42, 1.06), _BR_HO_FLAT, curl_r=0.0, head=(14.0, -14.0, 0), tor=(22.0, -4.0, 0)), "smooth"),
        (20, g(P0, _BR_HO_LOW, curl_r=0.9, head=(16.0, -16.0, 0), tor=(23.0, -5.0, 0)), "in2"),                 # grab
        (34, g(V(-0.16, -0.40, 1.14), _BR_HO_LOW, head=(14.0, -4.0, 0), tor=(20.0, 0.0, 0), **{"_bow": {"hand_r": V(0, 0, 0.05)}}), "smooth"),
        (46, g(V(0.04, -0.44, 1.00), _BR_HO_LOW, head=(16.0, 4.0, 0), tor=(22.0, 3.0, 0)), "in2"),             # place
        (52, g(V(0.04, -0.44, 1.00), _BR_HO_FLAT, curl_r=0.2), "smooth"),
        (58, g(V(0.09, -0.44, 0.985), _BR_HO_FLAT, curl_r=0.2, hand_l=wrist_at("l", V(0.20, -0.42, 0.985), PALM_DN)), "smooth"),   # nudge
        (66, g(V(0.06, -0.44, 0.985), _BR_HO_FLAT, curl_r=0.2, hand_l=wrist_at("l", V(0.20, -0.40, 0.985), PALM_DN),
               head=(16.0, 10.0, 0), tor=(21.0, 5.0, 0)), "smooth"),
        (74, g(V(-0.20, -0.40, 1.08), _BR_HO_FLAT, curl_r=0.1, head=(12.0, -6.0, 0), tor=(20.0, -2.0, 0)), "smooth"),   # back to the pile
        (86, g(V(-0.30, -0.40, 1.04), _BR_HO_FLAT, curl_r=0.0, head=(15.0, -14.0, 0), tor=(22.0, -5.0, 0)), "smooth"),
        (92, g(P0 + V(0.03, 0.0, 0.0), _BR_HO_LOW, curl_r=0.9), "in2"),                                         # grab #2
        (106, g(V(-0.22, -0.38, 1.14), _BR_HO_LOW, head=(14.0, 0.0, 0), tor=(20.0, 2.0, 0), **{"_bow": {"hand_r": V(0, 0, 0.05)}}), "smooth"),
        (118, g(V(-0.12, -0.44, 1.00), _BR_HO_LOW, head=(16.0, -6.0, 0), tor=(22.0, -2.0, 0)), "in2"),           # place #2
        (124, g(V(-0.12, -0.44, 1.00), _BR_HO_FLAT, curl_r=0.2), "smooth"),
        (134, {"head": (8.0, 0.0, 0), "tor": (14.0, 0.0, 0), "hand_l": b["hand_l"], "elb_l": b["elb_l"]}, "smooth"),   # step back and look at the display
        (146, dict(g(b["hand_r"] * 0 + V(-0.32, -0.40, 0.98), _BR_HO_FLAT, curl_r=0.4), head=b["head"], tor=b["tor"]), "smooth"),
    ]
    return looped(b, 156, keys, post=idle_layer(1, 0.4, pel=0.003, tor=0.6))


_BB = neutral()
_BB.update(stance(0.15, 0.0, -0.15, 0.06, 8.0, -8.0))
_BB.update({"pel": V(0, -0.02, -0.01), "tor": (8.0, 0.0, 0.0), "head": (12.0, 12.0, 0.0),
            "hand_l": V(0.03, -0.14, 1.50), "elb_l": V(0.30, 0.04, 1.26), "ho_l": ((-0.6, -0.5, 0.6), (0.3, 0.7, 0.6)), "curl_l": 0.6,   # chin-stroking pose
            "hand_r": V(-0.26, 0.02, 0.98), "elb_r": V(-0.40, 0.14, 1.06), "curl_r": 0.3})


@life_clip("Life_Market_Browse", loop=True, category="social/market", props=[{"id": "bread", "hand": "r"}], anchor=dict(STALL),
           tags=["customer", "browse"], events={"pick": [40], "inspect": [56, 84], "put_back": [112]},
           note="customer at a stall: studies the goods with a hand at the chin, picks up a loaf, turns it over in front of the face, "
                "sets it back a little to one side, shrugs and glances along the stall")
def _market_browse():
    b = _BB
    def g(p, ho, **kw):
        d = {"hand_r": wrist_at("r", p, ho), "ho_r": ho}
        d.update(kw)
        return d
    keys = [
        (22, {"head": (14.0, -18.0, 2.0), "tor": (10.0, -4.0, 0)}, "smooth"),
        (34, dict(g(V(-0.20, -0.40, 1.08), _BR_HO_FLAT, curl_r=0.0), head=(18.0, -8.0, 0), tor=(16.0, -3.0, 0), pel=V(0, -0.05, -0.03)), "smooth"),
        (42, dict(g(V(-0.16, -0.42, 0.98), _BR_HO_LOW, curl_r=0.9), head=(20.0, -6.0, 0), tor=(18.0, -2.0, 0)), "in2"),           # pick up
        (56, dict(g(V(-0.08, -0.30, 1.30), _BR_HO_TURN, curl_r=0.9, elb_r=V(-0.34, 0.06, 1.24)), head=(10.0, 0.0, 3.0), tor=(6.0, 0.0, 0),
                  pel=V(0, -0.02, -0.01), hand_l=V(0.12, -0.26, 1.16), curl_l=0.4, ho_l=((-0.6, -0.5, 0.6), (0.4, 0.5, 0.7)), elb_l=V(0.30, 0.04, 1.10)), "smooth"),
        (70, dict(g(V(-0.06, -0.30, 1.32), _BR_HO_SIDE, curl_r=0.9), head=(8.0, -5.0, -4.0)), "smooth"),                     # turn it over
        (84, dict(g(V(-0.06, -0.30, 1.32), _BR_HO_TURN, curl_r=0.9), head=(10.0, 5.0, 4.0)), "smooth"),
        (98, dict(g(V(-0.14, -0.38, 1.16), _BR_HO_LOW, curl_r=0.9), head=(16.0, -6.0, 0), tor=(14.0, -2.0, 0), pel=V(0, -0.04, -0.02),
                  hand_l=b["hand_l"], ho_l=b["ho_l"], curl_l=b["curl_l"]), "smooth"),
        (112, dict(g(V(-0.02, -0.42, 0.98), _BR_HO_LOW, curl_r=0.9), head=(18.0, 4.0, 0), tor=(17.0, 3.0, 0)), "in2"),        # put it back, a bit to the side
        (118, g(V(-0.02, -0.42, 0.98), _BR_HO_FLAT, curl_r=0.1), "smooth"),
        (130, dict(g(V(-0.26, -0.10, 1.00), _BR_HO_FLAT, curl_r=0.3), head=(4.0, 0.0, 0), tor=(6.0, 0.0, 0), pel=b["pel"],
                   shrug_l=8.0, shrug_r=8.0), "smooth"),                                                                       # shrug
        (142, dict(g(b["hand_r"] * 0 + V(-0.26, 0.02, 0.98), _BR_HO_FLAT, curl_r=0.3), head=(8.0, 26.0, 0), tor=(6.0, 8.0, 0),
                   shrug_l=0.0, shrug_r=0.0), "smooth"),
        (160, {"head": b["head"], "tor": b["tor"], "hand_r": b["hand_r"], "ho_r": HANG_R if False else _BR_HO_FLAT}, "smooth"),
    ]
    return looped(b, 180, keys, post=idle_layer(1, 0.35, pel=0.003, tor=0.6))
