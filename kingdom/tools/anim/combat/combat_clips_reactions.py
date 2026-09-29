# Directional hit reactions (light + heavy, front/back/left/right) and staggers, authored with author_combat.py.
# World axes: character faces -Y, +Z up, +X = character's LEFT. 30 fps. Feet IK-pinned unless a key moves them.
#
# Design (why these read as hits, not as poses):
#   * contact is frame 0: the body is ALREADY moving on frame 1 (no anticipation for the victim - the hit is the cause)
#   * the head and chest whip first and furthest (they are light), the pelvis follows a frame later (heavier): overlap
#   * a 2-frame snap to the extreme ("out2"), then an overshoot the other way while the body catches itself, then a
#     slow settle ("smooth") - a damped spring, not a linear blend
#   * the push direction matches the hit: front hit -> chest back, back hit -> chest forward, left hit -> bend right
#   * heavy hits add a catch step with the foot on the push side and a knee dip; staggers take 2-3 steps
#   * arms fling opposite to the push and lag the torso by ~1 frame (secondary motion)
# Every clip starts and ends in the same neutral pose (N) so it blends from/to idle at any time.
import math
from combat_common import clip, V, stance, rel, TF, shake, blade_o, ready_pose

N = ready_pose()

# push direction per hit side, in world (x left, y back): a hit FROM the front pushes the body back (+Y)
PUSH = {"Front": (0.0, 1.0), "Back": (0.0, -1.0), "Left": (-1.0, 0.0), "Right": (1.0, 0.0)}


def _tor_for(px, py, k):
    """torso lean (pitch fwd +, yaw, roll left +) that follows a push (px left, py back)"""
    return (-py * k, 0.0, -px * k * 0.8)


def reaction(side, heavy):
    px, py = PUSH[side]
    F = __import__("combat_common").F
    k = 30.0 if heavy else 15.0          # peak torso lean (deg)
    d = 0.14 if heavy else 0.045         # pelvis push (m)
    hd = 16.0 if heavy else 11.0         # extra head whip (deg)
    n = 26 if heavy else 15
    tp = _tor_for(px, py, k)
    to = _tor_for(px, py, -k * 0.22)     # overshoot the other way
    head_p = (-py * hd, px * 6.0, -px * hd * 0.7)
    arm_fling = V(-px * 0.10, py * 0.16, 0.10 if heavy else 0.05)
    keys = [(0, dict(N))]
    # f1: chest + head already whipping, pelvis only starting (overlap)
    keys.append((1, {"tor": (N["tor"][0] + tp[0] * 0.55, tp[1], tp[2] * 0.55), "head": tuple(h * 0.7 for h in head_p),
                     "pel": V(px * d * 0.25, py * d * 0.25, -0.005)}, "out2"))
    # extreme (f2 light / f3 heavy)
    ext = 2 if not heavy else 3
    kx = {"tor": (N["tor"][0] + tp[0], tp[1], tp[2]), "head": head_p,
          "pel": V(px * d, py * d, -0.02 if heavy else -0.008),
          "hand_l": N["hand_l"] + arm_fling + V(0.05, 0, 0), "hand_r": N["hand_r"] + arm_fling + V(-0.05, 0, 0),
          "curl_l": 0.1, "curl_r": 0.95}
    if heavy:
        kx["hip"] = (-py * 8.0, px * 6.0, -px * 6.0)
    keys.append((ext, kx, "out2"))
    if heavy:
        # catch step: the foot on the push side steps with the push, the knees dip
        step = V(px * 0.22, py * 0.26, 0.0)
        lead = "foot_r" if (py > 0 or px < 0) else "foot_l"
        keys.append((6, {"tor": (N["tor"][0] + tp[0] * 0.8, 0.0, tp[2] * 0.8), "pel": V(px * d * 1.4, py * d * 1.4, -0.07),
                         "head": (py * 8.0, 0.0, px * 6.0),
                         lead: N[lead] + step * 0.5 + V(0, 0, 0.08),
                         "_bow": {}}, "smooth"))
        keys.append((9, {lead: N[lead] + step, "pel": V(px * d * 1.6, py * d * 1.6, -0.09),
                         "tor": (N["tor"][0] + tp[0] * 0.45, 0.0, tp[2] * 0.45), "head": tuple(h * 0.3 for h in head_p)}, "in2"))
        keys.append((14, {"tor": (N["tor"][0] + to[0], to[1], to[2]), "head": tuple(-h * 0.2 for h in head_p),
                          "pel": V(px * d * 1.2, py * d * 1.2, -0.05), "hip": (0.0, 0.0, 0.0),
                          "hand_l": N["hand_l"], "hand_r": N["hand_r"], "curl_l": 0.5}, "smooth"))
        # recover: bring the stepped foot back under the body
        keys.append((20, {lead: N[lead] + V(0, 0, 0.05), "pel": V(px * d * 0.4, py * d * 0.4, -0.02),
                          "tor": N["tor"], "head": N["head"]}, "smooth"))
        keys.append((n, {lead: N[lead], "pel": N["pel"]}, "smooth"))
    else:
        keys.append((6, {"tor": (N["tor"][0] + to[0], to[1], to[2]), "head": tuple(-h * 0.25 for h in head_p),
                         "pel": V(px * d * 0.6, py * d * 0.6, -0.004),
                         "hand_l": N["hand_l"], "hand_r": N["hand_r"], "curl_l": 0.5}, "smooth"))
        keys.append((n, {"tor": N["tor"], "head": N["head"], "pel": N["pel"]}, "smooth"))
    return F.build(keys, n)


for _side in PUSH:
    for _heavy in (False, True):
        _name = "Hit_%s_%s" % ("Heavy" if _heavy else "Light", _side)
        clip(_name, events={"contact": 0, "extreme": 3 if _heavy else 2, "recovered": 20 if _heavy else 10},
             note="victim reaction to a hit from the %s (push %s)" % (_side.lower(), PUSH[_side]))(
            (lambda s, h: (lambda: reaction(s, h)))(_side, _heavy))


def stagger(back):
    """long heavy stagger: 3 stumbling steps, arms flailing, then regain balance (guard broken / heavy blow)"""
    F = __import__("combat_common").F
    sy = 1.0 if back else -1.0        # +Y = backwards
    L0, R0 = N["foot_l"], N["foot_r"]
    keys = [(0, dict(N))]
    keys.append((2, {"tor": (4 - sy * 26, 0, 4), "head": (-sy * 12, 0, 6), "pel": V(0, sy * 0.08, -0.03),
                     "hand_l": V(0.42, sy * 0.10, 1.10), "hand_r": V(-0.40, sy * 0.14, 1.05), "curl_l": 0.0}, "out2"))
    # step 1 (right foot)
    keys.append((6, {"foot_r": R0 + V(-0.03, sy * 0.18, 0.10), "pel": V(0.02, sy * 0.20, -0.06), "tor": (4 - sy * 22, 6, -6),
                     "head": (sy * 10, 0, 0)}, "smooth"))
    keys.append((9, {"foot_r": R0 + V(-0.05, sy * 0.36, 0.0), "pel": V(-0.03, sy * 0.30, -0.10), "hip": (0, 8, -4),
                     "hand_l": V(0.50, sy * 0.25, 1.25), "hand_r": V(-0.30, sy * 0.30, 0.95)}, "in2"))
    # step 2 (left foot)
    keys.append((13, {"foot_l": L0 + V(0.04, sy * 0.40, 0.10), "pel": V(0.03, sy * 0.44, -0.08), "tor": (4 - sy * 16, -6, 8),
                      "hip": (0, -6, 4)}, "smooth"))
    keys.append((16, {"foot_l": L0 + V(0.06, sy * 0.62, 0.0), "pel": V(0.04, sy * 0.54, -0.12),
                      "hand_l": V(0.36, sy * 0.45, 1.05), "hand_r": V(-0.46, sy * 0.40, 1.20)}, "in2"))
    # step 3 (right, small, the catch)
    keys.append((20, {"foot_r": R0 + V(-0.04, sy * 0.58, 0.08), "pel": V(0.0, sy * 0.60, -0.10), "tor": (4 - sy * 6, 0, 0), "hip": (0, 0, 0)}, "smooth"))
    keys.append((23, {"foot_r": R0 + V(-0.02, sy * 0.66, 0.0), "pel": V(0.0, sy * 0.62, -0.14), "tor": (4 + sy * 8, 0, 0),
                      "head": (sy * 6, 0, 0), "hand_l": V(0.30, sy * 0.60, 0.90), "hand_r": V(-0.30, sy * 0.58, 0.92)}, "in2"))
    # regain: settle, straighten over the new feet
    keys.append((32, {"pel": V(0.0, sy * 0.62, -0.03), "tor": (6, 0, 0), "head": (0, 0, 0), "curl_l": 0.5}, "smooth"))
    keys.append((40, {"pel": V(0.0, sy * 0.63, 0.0), "tor": N["tor"],
                      "hand_l": N["hand_l"] + V(0, sy * 0.63, 0), "hand_r": N["hand_r"] + V(0, sy * 0.63, 0)}, "smooth"))

    def post(fr, n, s):
        # root motion: the root follows the pelvis travel, so the pose relative to the root ends neutral (blend-safe)
        s["root"] = V(0, s["pel"].y, 0)
        # shaky balance on the steps (small stepped noise on the torso), fades out by the regain
        if 2 <= fr <= 26:
            w = 1.0 - (fr - 2) / 24.0
            e = shake(fr, 7 if back else 9, 2.5 * w, every=2)
            s["tor"] = (s["tor"][0] + e.x, s["tor"][1] + e.y, s["tor"][2] + e.z)
    return F.build(keys, 40, post=post)


clip("Stagger_Back", events={"contact": 0, "steps": [9, 16, 23], "recovered": 32},
     note="heavy stagger backwards, 0.63 m of pelvis travel (feet travel with it): drive the capsule 0.63 m back over 0.8 s or use root motion",
     root_motion_m=0.63)(lambda: stagger(True))
clip("Stagger_Forward", events={"contact": 0, "steps": [9, 16, 23], "recovered": 32},
     note="heavy stagger forwards (hit from behind), 0.63 m of pelvis travel", root_motion_m=0.63)(lambda: stagger(False))
