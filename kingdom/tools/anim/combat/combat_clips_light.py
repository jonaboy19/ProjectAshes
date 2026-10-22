# Player light combo, 1H sword + shield: Sword_Light_1..4 (authored with author_combat.py).
#   L1 forehand diagonal (high right -> low left)   L2 backhand rising (low left -> high right)
#   L3 flat horizontal (right -> left, chest)        L4 lunging thrust finisher
# Directional alternation right/left, and each hit's follow-through pose P_n is the next hit's frame 0, so a chained
# press (combo window) blends into the next wind-up with no detour through idle.
# AIM: every hit is authored against a target standing at the game's lunge standoff (1.3 m in front, player.gd
# LUNGE_STANDOFF): the blade passes through that target ON the contact frame (verified by combat_studio target_contact).
# Feet: the lead (left) foot steps in on the strike, the trailing foot catches up in the follow-through, so every clip
# starts and ends with the ready stance RELATIVE TO THE ROOT; the forward travel is in the root (in-game: the capsule
# lunge must match root_motion_m over the step frames, sidecar markers).
# Body mechanics: hips (hip yaw) turn 1 frame before the chest, the hand/blade arrive a frame after the chest (wrist
# lag), head counter-rotates to keep the eyes on the target, shield arm counter-balances. Axes: faces -Y, +X = left.
import math
from mathutils import Vector
from combat_common import clip, V, blade_o, ready_pose, stance

R0 = ready_pose()
FOOT_L, FOOT_R = R0["foot_l"], R0["foot_r"]


def bl(dirv, sweep):
    """ho_r for a blade pointing along dirv while travelling along sweep: flat normal = plane normal, edge leads"""
    d = Vector(dirv).normalized()
    sw = Vector(sweep).normalized()
    n = d.cross(sw)
    if n.length < 1e-4:
        n = Vector((1, 0, 0))
    return blade_o(tuple(d), tuple(n.normalized()))


def K(hip=0.0, chest=0.0, pitch=4.0, roll=0.0, **kw):
    """key dict: hip yaw and TOTAL chest yaw (world, left +); tor yaw = chest - hip (spine is relative to the pelvis)"""
    d = {"hip": (0.0, hip, 0.0), "tor": (pitch, chest - hip, roll)}
    d.update(kw)
    return d


def head_on_target(fr, n, s):
    """eyes stay on the target: the head counter-rotates the chest turn (70 %) - keeps the silhouette readable"""
    chest = s["hip"][1] + s["tor"][1]
    s["head"] = (s["head"][0], -chest * 0.7, s["head"][2])


def root_follow(fr, n, s):
    s["root"] = V(0, s["pel"].y, 0)


def post_std(fr, n, s):
    head_on_target(fr, n, s)
    root_follow(fr, n, s)


# ---------------------------------------------------------------- follow-through poses (= next hit's frame 0)
def P1():
    d = K(hip=18, chest=38, pitch=10, roll=4, hand_r=V(0.22, -0.34, 0.98), ho_r=bl((0.62, 0.15, -0.77), (0.3, 0.9, -0.2)),
          hand_l=V(0.30, 0.10, 1.00), curl_l=0.6, pel=V(0, 0, -0.05))
    d.update(stance())
    d["foot_l"], d["foot_r"] = FOOT_L, FOOT_R
    return d


def P2():
    d = K(hip=-18, chest=-36, pitch=2, roll=-4, hand_r=V(-0.42, -0.10, 1.50), ho_r=bl((-0.55, 0.30, 0.78), (-0.3, 0.8, 0.5)),
          hand_l=V(0.34, -0.25, 1.05), pel=V(0, 0, -0.03))
    d["foot_l"], d["foot_r"] = FOOT_L, FOOT_R
    return d


def P3():
    d = K(hip=22, chest=44, pitch=6, roll=2, hand_r=V(0.30, -0.24, 1.08), ho_r=bl((0.55, 0.72, -0.2), (0.4, 0.9, 0)),
          hand_l=V(0.26, 0.12, 1.00), pel=V(0, 0, -0.04))
    d["foot_l"], d["foot_r"] = FOOT_L, FOOT_R
    return d


def ready_keys(f):
    d = dict(R0)
    return (f, d, "smooth")


def lunge(f_lift, f_land, f_catch_lift, f_catch_land, dist, lead="l"):
    """step-in keys: lead foot forward `dist`, trailing foot catches up; pelvis travels with it (root follows)"""
    L0, R_ = (FOOT_L, FOOT_R) if lead == "l" else (FOOT_R, FOOT_L)
    lk, tk = "foot_" + lead, "foot_" + ("r" if lead == "l" else "l")
    return [
        (f_lift, {lk: L0 + V(0, -dist * 0.45, 0.09)}),
        (f_land, {lk: L0 + V(0, -dist, 0)}),
        (f_catch_lift, {tk: R_ + V(0, -dist * 0.55, 0.07)}),
        (f_catch_land, {tk: R_ + V(0, -dist, 0)}),
    ]


def merge(*lists):
    """merge key lists by frame (later dicts override), keep the ease of the first entry that names one"""
    out = {}
    ease = {}
    for lst in lists:
        for item in lst:
            f, d = item[0], item[1]
            out.setdefault(f, {}).update(d)
            if len(item) > 2 and f not in ease:
                ease[f] = item[2]
    return [(f, out[f], ease.get(f, "smooth")) for f in sorted(out)]


# ---------------------------------------------------------------- L1: forehand diagonal, high right -> low left
def light_1():
    F = __import__("combat_common").F
    sweep = (1.0, -0.2, -0.7)
    keys = [
        (0, dict(R0)),
        # anticipation: coil right, blade up behind the right shoulder, weight back and down (slow in)
        (5, K(hip=-14, chest=-52, pitch=-2, roll=-6, pel=V(0, 0.05, -0.04), hand_r=V(-0.42, 0.10, 1.46),
              ho_r=bl((-0.35, 0.50, 0.79), sweep), elb_r=V(-0.62, 0.22, 1.38), hand_l=V(0.22, -0.32, 1.12), curl_l=0.4,
              _bow={"hand_r": (-0.10, 0.05, 0.08)}), "smooth"),
        # moving hold: the coil keeps tightening 2 more degrees
        (6, K(hip=-16, chest=-55, pitch=-2, roll=-6, pel=V(0, 0.05, -0.05), hand_r=V(-0.43, 0.12, 1.48)), "smooth"),
        # hips snap first (chest still back = x-factor)
        (7, K(hip=6, chest=-36, pitch=4, roll=-3, pel=V(0, -0.06, -0.06), hand_r=V(-0.44, 0.00, 1.44),
              ho_r=bl((-0.62, 0.20, 0.76), sweep), elb_r=None), "in2"),
        (8, K(hip=16, chest=-8, pitch=10, pel=V(0, -0.13, -0.08), hand_r=V(-0.32, -0.40, 1.30),
              ho_r=bl((-0.70, -0.62, 0.35), sweep), _bow={"hand_r": (-0.06, 0.0, 0.05)}), "in"),
        # CONTACT: blade forward and slightly down-left through the target
        (9, K(hip=18, chest=16, pitch=14, roll=2, pel=V(0, -0.17, -0.08), hand_r=V(-0.06, -0.62, 1.12),
              ho_r=bl((0.28, -0.90, -0.30), sweep), hand_l=V(0.32, -0.10, 1.05)), "lin"),
        (10, K(hip=19, chest=30, pitch=14, roll=3, pel=V(0, -0.19, -0.08), hand_r=V(0.18, -0.52, 1.00),
               ho_r=bl((0.85, -0.30, -0.42), sweep)), "out2"),
        # overshoot past the follow-through pose, then settle back (damped)
        (12, K(hip=21, chest=44, pitch=12, roll=5, pel=V(0, -0.21, -0.07), hand_r=V(0.25, -0.32, 0.93),
               ho_r=bl((0.70, 0.30, -0.65), (0.2, 1, 0)), hand_l=V(0.34, 0.12, 1.00)), "out2"),
    ]
    p1 = P1()
    p1["pel"] = V(0, -0.22, -0.05)
    keys.append((15, p1, "smooth"))
    rec = dict(R0)
    rec["pel"] = V(0, -0.22, 0)
    keys.append((30, rec, "smooth"))
    steps = lunge(7, 9, 12, 15, 0.22)
    # everything after the step keeps the stepped feet
    for f in (15, 30):
        steps.append((f, {"foot_l": FOOT_L + V(0, -0.22, 0), "foot_r": FOOT_R + V(0, -0.22, 0)}))
    return F.build(merge(keys, steps), 30, post=post_std)


clip("Sword_Light_1", events={"windup_end": 6, "hit_start": 8, "hit": 9, "hit_end": 10, "follow_end": 15,
                               "combo_window": [11, 20], "cancel_window": [15, 30], "step": [7, 14]},
     note="light 1: forehand diagonal R->L; frame 15 == Sword_Light_2 frame 0", root_motion_m=0.22)(light_1)


# ---------------------------------------------------------------- L2: backhand rising, low left -> high right
def light_2():
    F = __import__("combat_common").F
    sweep = (-1.0, -0.1, 0.55)
    keys = [
        (0, P1()),
        # anticipation: wind further left and low, blade trailing back-left
        (4, K(hip=24, chest=56, pitch=12, roll=6, pel=V(0, 0.04, -0.07), hand_r=V(0.26, -0.16, 0.98),
              ho_r=bl((0.62, 0.55, -0.55), sweep), hand_l=V(0.30, 0.18, 1.02), _bow={"hand_r": (0.06, 0.0, -0.04)}), "smooth"),
        (5, K(hip=24, chest=58, pitch=12, roll=6, pel=V(0, 0.04, -0.07), hand_r=V(0.27, -0.15, 0.98)), "smooth"),
        (6, K(hip=4, chest=40, pitch=8, pel=V(0, -0.06, -0.07), hand_r=V(0.28, -0.32, 1.02),
              ho_r=bl((0.85, -0.25, 0.10), sweep)), "in2"),
        (7, K(hip=-14, chest=12, pitch=6, pel=V(0, -0.14, -0.06), hand_r=V(0.22, -0.50, 1.10),
              ho_r=bl((0.55, -0.82, 0.18), sweep), _bow={"hand_r": (0.05, -0.04, 0)}), "in"),
        # CONTACT: blade forward and rising
        (8, K(hip=-20, chest=-12, pitch=4, pel=V(0, -0.19, -0.05), hand_r=V(-0.06, -0.63, 1.24),
              ho_r=bl((-0.18, -0.95, 0.26), sweep), hand_l=V(0.36, -0.05, 1.02)), "lin"),
        (9, K(hip=-22, chest=-28, pitch=2, pel=V(0, -0.22, -0.04), hand_r=V(-0.34, -0.46, 1.40),
              ho_r=bl((-0.80, -0.38, 0.45), sweep)), "out2"),
        (11, K(hip=-22, chest=-44, pitch=0, roll=-5, pel=V(0, -0.24, -0.03), hand_r=V(-0.46, -0.06, 1.56),
               ho_r=bl((-0.58, 0.36, 0.73), (-0.3, 0.8, 0.5)), hand_l=V(0.36, -0.28, 1.08)), "out2"),
    ]
    p2 = P2()
    p2["pel"] = V(0, -0.24, -0.03)
    keys.append((14, p2, "smooth"))
    rec = dict(R0)
    rec["pel"] = V(0, -0.24, 0)
    keys.append((30, rec, "smooth"))
    # backhand: the trailing (right) foot passes forward? No - keep left lead, shorter step, right catches up
    steps = lunge(6, 8, 11, 14, 0.24)
    for f in (14, 30):
        steps.append((f, {"foot_l": FOOT_L + V(0, -0.24, 0), "foot_r": FOOT_R + V(0, -0.24, 0)}))
    return F.build(merge(keys, steps), 30, post=post_std)


clip("Sword_Light_2", events={"windup_end": 5, "hit_start": 7, "hit": 8, "hit_end": 9, "follow_end": 14,
                               "combo_window": [10, 19], "cancel_window": [14, 30], "step": [6, 13]},
     note="light 2: backhand rising L->R; frame 0 == Sword_Light_1 frame 15, frame 14 == Sword_Light_3 frame 0",
     root_motion_m=0.24)(light_2)


# ---------------------------------------------------------------- L3: flat horizontal, right -> left, chest height
def light_3():
    F = __import__("combat_common").F
    sweep = (1.0, 0.0, 0.0)
    keys = [
        (0, P2()),
        # anticipation: drop the blade to horizontal behind the right side, big coil, sink
        (5, K(hip=-22, chest=-62, pitch=0, roll=-4, pel=V(0, 0.05, -0.08), hand_r=V(-0.50, 0.08, 1.18),
              ho_r=bl((-0.70, 0.70, 0.05), sweep), hand_l=V(0.24, -0.34, 1.10), elb_r=V(-0.66, 0.24, 1.10),
              _bow={"hand_r": (-0.08, 0.04, 0.10)}), "smooth"),
        (6, K(hip=-24, chest=-65, pitch=0, roll=-4, pel=V(0, 0.05, -0.09), hand_r=V(-0.51, 0.10, 1.18)), "smooth"),
        (7, K(hip=2, chest=-44, pitch=4, pel=V(0, -0.06, -0.09), hand_r=V(-0.50, -0.14, 1.18),
              ho_r=bl((-0.95, -0.20, 0.05), sweep), elb_r=None), "in2"),
        (8, K(hip=18, chest=-14, pitch=6, pel=V(0, -0.15, -0.09), hand_r=V(-0.30, -0.52, 1.15),
              ho_r=bl((-0.55, -0.83, 0.02), sweep), _bow={"hand_r": (-0.06, -0.05, 0)}), "in"),
        # CONTACT: blade straight forward, chest height
        (9, K(hip=22, chest=14, pitch=8, pel=V(0, -0.20, -0.08), hand_r=V(0.04, -0.64, 1.14),
              ho_r=bl((0.18, -0.98, 0.0), sweep), hand_l=V(0.38, -0.02, 1.04)), "lin"),
        (10, K(hip=24, chest=34, pitch=8, pel=V(0, -0.23, -0.07), hand_r=V(0.26, -0.48, 1.12),
               ho_r=bl((0.86, -0.50, 0.0), sweep)), "out2"),
        (12, K(hip=26, chest=52, pitch=6, roll=3, pel=V(0, -0.25, -0.06), hand_r=V(0.34, -0.20, 1.10),
               ho_r=bl((0.60, 0.78, -0.05), sweep), hand_l=V(0.26, 0.14, 1.00)), "out2"),
    ]
    p3 = P3()
    p3["pel"] = V(0, -0.26, -0.04)
    keys.append((15, p3, "smooth"))
    keys.append((22, K(hip=10, chest=14, pitch=4, pel=V(0, -0.26, -0.02), hand_r=V(0.02, -0.36, 1.22),
                       ho_r=bl((0.2, -0.45, 0.87), (1, 0, 0)), hand_l=V(0.27, -0.06, 0.92)), "smooth"))
    rec = dict(R0)
    rec["pel"] = V(0, -0.26, 0)
    keys.append((32, rec, "smooth"))
    steps = lunge(7, 9, 12, 15, 0.26)
    for f in (15, 22, 32):
        steps.append((f, {"foot_l": FOOT_L + V(0, -0.26, 0), "foot_r": FOOT_R + V(0, -0.26, 0)}))
    return F.build(merge(keys, steps), 32, post=post_std)


clip("Sword_Light_3", events={"windup_end": 6, "hit_start": 8, "hit": 9, "hit_end": 10, "follow_end": 15,
                               "combo_window": [11, 21], "cancel_window": [15, 32], "step": [7, 14]},
     note="light 3: horizontal R->L at chest height; frame 0 == Sword_Light_2 frame 14, frame 15 == Sword_Light_4 frame 0",
     root_motion_m=0.26)(light_3)


# ---------------------------------------------------------------- L4: lunging thrust finisher
def light_4():
    F = __import__("combat_common").F
    keys = [
        (0, P3()),
        # lift the blade up and over (tip up) on its way to the right hip - never through the torso
        (6, K(hip=-6, chest=-10, pitch=0, pel=V(0, 0.03, -0.06), hand_r=V(-0.10, -0.36, 1.42),
              ho_r=bl((-0.1, -0.2, 0.97), (-1, 0, 0)), hand_l=V(0.24, -0.30, 1.12)), "smooth"),
        # long anticipation (finisher): draw back to the right hip, point at the target, shield aims, sink on the back leg
        (11, K(hip=-22, chest=-46, pitch=-4, roll=-3, pel=V(0, 0.08, -0.10), hand_r=V(-0.30, 0.26, 1.04),
               ho_r=bl((0.08, -1.0, 0.06), (0, 0, 1)), elb_r=V(-0.52, 0.40, 1.00), hand_l=V(0.18, -0.40, 1.22), curl_l=0.3,
               _bow={"hand_r": (-0.10, 0.10, 0.08)}), "smooth"),
        (13, K(hip=-24, chest=-49, pitch=-5, roll=-3, pel=V(0, 0.09, -0.11), hand_r=V(-0.31, 0.28, 1.05)), "smooth"),
        # drive: hips first, long lunge
        (14, K(hip=0, chest=-34, pitch=6, pel=V(0, -0.08, -0.12), hand_r=V(-0.28, 0.10, 1.10),
               ho_r=bl((0.06, -1.0, 0.04), (0, 0, 1)), elb_r=None, hand_l=V(0.30, -0.10, 1.12)), "in2"),
        (15, K(hip=10, chest=-12, pitch=12, pel=V(0, -0.24, -0.13), hand_r=V(-0.18, -0.40, 1.18)), "in"),
        # CONTACT: arm fully extended, tip 0.5 m through the target line
        (16, K(hip=14, chest=6, pitch=18, pel=V(0, -0.36, -0.13), hand_r=V(-0.07, -0.98, 1.20),
               ho_r=bl((0.02, -1.0, 0.0), (0, 0, 1)), hand_l=V(0.36, 0.08, 1.04), curl_l=0.7), "lin"),
        # overshoot: the body keeps travelling 4 cm and the tip dips, then holds (impale beat)
        (18, K(hip=16, chest=10, pitch=21, pel=V(0, -0.40, -0.14), hand_r=V(-0.05, -1.04, 1.16),
               ho_r=bl((0.02, -1.0, -0.06), (0, 0, 1))), "out2"),
        (23, K(hip=14, chest=8, pitch=16, pel=V(0, -0.40, -0.12), hand_r=V(-0.06, -0.98, 1.18)), "smooth"),
        # withdraw the blade, square up
        (29, K(hip=4, chest=-4, pitch=8, pel=V(0, -0.40, -0.05), hand_r=V(-0.22, -0.42, 1.02),
               ho_r=bl((0.2, -0.9, 0.35), (1, 0, 0))), "smooth"),
    ]
    rec = dict(R0)
    rec["pel"] = V(0, -0.40, 0)
    keys.append((41, rec, "smooth"))
    steps = lunge(14, 16, 23, 29, 0.40)
    for f in (29, 41):
        steps.append((f, {"foot_l": FOOT_L + V(0, -0.40, 0), "foot_r": FOOT_R + V(0, -0.40, 0)}))
    return F.build(merge(keys, steps), 41, post=post_std)


clip("Sword_Light_4", events={"windup_end": 13, "hit_start": 15, "hit": 16, "hit_end": 18, "follow_end": 23,
                               "combo_window": [], "cancel_window": [29, 41], "step": [14, 29]},
     note="light 4 (finisher): lunging thrust; frame 0 == Sword_Light_3 frame 15; commit, no chain", root_motion_m=0.40)(light_4)


# ---------------------------------------------------------------- upper-body variants
# CharacterAnimator plays attacks on the upper-body OneShot (pelvis + legs from locomotion). A clip whose hips turn
# would lose that turn there and miss the target, so every hit also exists as <name>_Upper: pelvis yaw 0, the yaw moved
# into the spine, the IK hand/blade targets unchanged (same world arc, same contact frame). Use <name> full-body at a
# standstill, <name>_Upper while moving (docs/anim/patches/P9_upper_lower_layering.md).
def _upper(fn):
    def post_upper(fr, n, s):
        post_std(fr, n, s)
        hp, hy, hr = s["hip"]
        tp, ty, tr = s["tor"]
        s["tor"] = (tp, ty + hy, tr)
        s["hip"] = (hp, 0.0, hr)
    return post_upper


def _build_upper(builder):
    import combat_common
    F = combat_common.F
    orig = F.build

    def wrapped(keys, n, post=None, step=None):
        return orig(keys, n, post=_upper(post), step=step)
    F.build = wrapped
    try:
        return builder()
    finally:
        F.build = orig


for _nm, _fn in (("Sword_Light_1", light_1), ("Sword_Light_2", light_2), ("Sword_Light_3", light_3), ("Sword_Light_4", light_4)):
    import combat_common as _cc
    _src = _cc.CLIPS[_nm]
    clip(_nm + "_Upper", events=_src["events"], note=_src["note"] + " | upper-body layer variant (hip yaw folded into the spine)",
         root_motion_m=_src["root_motion_m"])((lambda f: (lambda: _build_upper(f)))(_fn))
