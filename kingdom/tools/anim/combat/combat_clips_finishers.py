# Sword + shield defensive / counter moves and three paired finishers (attacker clip + victim clip).
# World axes (Blender armature space): character faces -Y, +Z up, +X = character's LEFT. 30 fps.
#
# Clips: Sword_Parry, Sword_Riposte, Shield_Bash, and the pairs
#   Finisher_Stab_Through / Finisher_Stab_Through_Victim
#   Finisher_Overhead_Cleave / Finisher_Overhead_Cleave_Victim
#   Finisher_Spin_Slash / Finisher_Spin_Slash_Victim
# PAIR CONTRACT: both clips of a pair have the same length and are frame-synced. Play the victim with its root placed
# exactly 1.2 m in front of the attacker (attacker + 1.2 m along the attacker's forward = -Y in Blender) and rotated
# 180 deg so it faces the attacker. Each clip is authored in its own local frame (faces -Y). In the VICTIM's local frame the
# attacker stands 1.2 m in front of it (at local y = -1.2). A point (x, y, z) in the attacker frame is, in victim
# local coordinates, (-x, -1.2 - y, z).
# Blade length used for the tip estimate: 0.87 m from the wrist along the blade axis.
import math, os
from combat_common import clip, V, stance, rel, TF, shake, blade_o, ready_pose
import combat_common as CC

N = ready_pose()
BL = 0.87
DBG = bool(os.environ.get("COMBAT_DBG"))


def home(dy=0.0):
    """ready pose shifted by dy along Y (root travel): pose relative to the root is exactly ready_pose"""
    H = dict(N)
    for k in ("hand_l", "hand_r", "foot_l", "foot_r"):
        H[k] = N[k] + V(0, dy, 0)
    H["pel"] = V(0, dy, 0)
    H["fpit_l"] = 0.0
    H["fpit_r"] = 0.0
    return H


def root_post(fr, n, s):
    s["root"] = V(0, s["pel"].y, 0)


def ease(kind, t):
    return CC.F._ease(kind, t)


def sm(t):
    return CC.smooth(t)


# ------------------------------------------------------------------------------------------------ debug helpers
def dbg_tips(name, poses, frames):
    """print blade tip (world, attacker frame) for the given frames"""
    if not DBG:
        return
    ax = V(*CC.BLADE_REST["axis"])
    for f in frames:
        P = poses[f]
        d = P.hq["r"] @ ax
        h = P.hand["r"]
        tip = h + d * BL
        print("DBG %s f%d hand=(%.2f,%.2f,%.2f) dir=(%.2f,%.2f,%.2f) tip=(%.2f,%.2f,%.2f) pelvis=(%.2f,%.2f,%.2f)" % (
            name, f, h.x, h.y, h.z, d.x, d.y, d.z, tip.x, tip.y, tip.z, P.pelvis.x, P.pelvis.y, P.pelvis.z))


# ================================================================================================ Sword_Parry
def parry():
    F = CC.F
    k = [(0, dict(N))]
    k.append((1, {"hip": (0, 3, 0), "tor": (4, 4, 0), "pel": V(0.01, -0.01, 0)}, "in2"))
    k.append((2, {"hip": (0, 6, 0), "tor": (5, 9, 0), "pel": V(0.02, -0.02, -0.015),
                  "hand_r": V(-0.19, -0.30, 1.14), "ho_r": blade_o((0.0, -0.35, 0.94), (1, 0, 0)),
                  "hand_l": V(0.30, -0.14, 0.98), "curl_r": 0.9,
                  "_bow": {"hand_r": V(0, 0, 0.05)}}, "in2"))
    k.append((3, {"hand_r": V(-0.09, -0.42, 1.34), "ho_r": blade_o((0.10, -0.15, 0.98), (1, 0, 0)), "head": (-2, 0, 0),
                  "hand_l": V(0.31, -0.22, 1.05), "foot_r": N["foot_r"] + V(0, 0.03, 0.05)}, "in2"))
    # contact: blade angled across, edge out; rear foot steps back
    k.append((4, {"hand_r": V(-0.05, -0.44, 1.36), "ho_r": blade_o((0.50, -0.15, 0.85), (1, 0, 0)),
                  "foot_r": N["foot_r"] + V(0, 0.05, 0.03), "tor": (4, 9, 0)}, "out2"))
    # recoil: the impact pushes the blade ~6 cm and the torso 3 deg back
    k.append((5, {"hand_r": V(-0.02, -0.38, 1.38), "ho_r": blade_o((0.56, -0.05, 0.83), (1, 0, 0)),
                  "tor": (1.0, 7, 0), "pel": V(0.02, 0.035, -0.015), "hip": (0, 5, 0), "head": (1, 0, 0),
                  "foot_r": N["foot_r"] + V(0, 0.05, 0.0)}, "out2"))
    k.append((8, {"hand_r": V(-0.05, -0.40, 1.36), "ho_r": blade_o((0.46, -0.15, 0.88), (1, 0, 0)), "tor": (2, 6, 0),
                  "pel": V(0.015, 0.02, -0.01), "head": (0, 0, 0)}, "smooth"))
    k.append((11, {"hand_r": V(-0.14, -0.30, 1.20), "ho_r": blade_o((0.25, -0.55, 0.75), (1, 0, 0)), "tor": (3, 3, 0),
                   "hand_l": V(0.28, -0.12, 0.96), "hip": (0, 2, 0), "pel": V(0.005, 0.01, 0)}, "smooth"))
    k.append((14, {"foot_r": N["foot_r"] + V(0, 0.03, 0.04), "hand_r": V(-0.22, -0.16, 1.02)}, "smooth"))
    k.append((18, dict(N), "smooth"))
    return F.build(k, 18)


clip("Sword_Parry", events={"parry_active": [2, 6], "contact": 4, "hit": 4, "recoil_end": 8, "cancel_window": [9, 18]},
     note="fast 3-frame snap of the blade up-and-across meeting a blow at f4, small recoil, ready_pose at 0.6 s; "
          "rear foot steps back 5 cm at contact; no root motion")(parry)


# ================================================================================================ Sword_Riposte
def riposte():
    F = CC.F
    k = [(0, dict(N))]
    k.append((1, {"hip": (0, 3, 0), "tor": (4, 5, 0)}, "in2"))
    # first frames = the parry (blade up and across), then the blade cocks back
    k.append((2, {"hip": (0, 6, 0), "tor": (2, 8, 0), "hand_r": V(-0.06, -0.43, 1.35),
                  "ho_r": blade_o((0.50, -0.15, 0.85), (1, 0, 0)), "hand_l": V(0.31, -0.22, 1.05), "curl_r": 0.9}, "in2"))
    k.append((6, {"hip": (0, -8, 0), "tor": (6, -14, 0), "pel": V(0, 0.04, -0.03), "hand_r": V(-0.31, -0.10, 1.22),
                  "ho_r": blade_o((0.22, -0.92, 0.30), (1, 0, 0)), "hand_l": V(0.30, -0.18, 1.0), "head": (0, 6, 0),
                  "_bow": {"hand_r": V(-0.03, 0.0, 0.10)}}, "smooth"))
    # hips lead: pelvis rotates + front foot lifts while the arm is still loaded
    k.append((7, {"hip": (0, 4, 0), "pel": V(0.01, -0.06, -0.04), "hand_r": V(-0.32, -0.09, 1.22),
                  "foot_l": N["foot_l"] + V(0, -0.06, 0.10), "tor": (7, -16, 0)}, "in2"))
    k.append((8, {"hip": (0, 12, 0), "tor": (9, -6, 0), "pel": V(0.03, -0.16, -0.07),
                  "foot_l": N["foot_l"] + V(0, -0.24, 0.16), "hand_r": V(-0.27, -0.28, 1.24),
                  "ho_r": blade_o((0.10, -0.95, 0.25), (1, 0, 0)), "hand_l": V(0.34, 0.0, 1.06)}, "in2"))
    # contact
    k.append((9, {"hip": (0, 14, 0), "tor": (13, 12, 0), "pel": V(0.04, -0.23, -0.10),
                  "foot_l": N["foot_l"] + V(0, -0.35, 0), "hand_r": V(-0.09, -0.80, 1.27),
                  "ho_r": blade_o((0.05, -0.99, 0.08), (1, 0, 0)), "head": (3, -6, 0),
                  "_bow": {"hand_r": V(0.0, 0.0, 0.03)}}, "in2"))
    k.append((10, {"hand_r": V(-0.07, -0.87, 1.26), "pel": V(0.04, -0.26, -0.10), "tor": (15, 14, 0), "hip": (0, 10, 0),
                   "ho_r": blade_o((0.05, -0.99, 0.02), (1, 0, 0))}, "out"))
    k.append((13, {"hand_r": V(-0.10, -0.83, 1.21), "ho_r": blade_o((0.10, -0.93, -0.15), (1, 0, 0)), "tor": (12, 8, 0),
                   "pel": V(0.03, -0.26, -0.09), "hip": (0, 6, 0), "hand_l": V(0.30, -0.10, 1.0), "head": (0, 0, 0)}, "smooth"))
    k.append((16, {"hand_r": V(-0.22, -0.60, 1.12), "ho_r": blade_o((0.20, -0.85, 0.15), (1, 0, 0)), "tor": (9, 4, 0),
                   "hip": (0, 3, 0)}, "smooth"))
    k.append((20, {"foot_r": N["foot_r"] + V(0, -0.14, 0.14), "pel": V(0.02, -0.31, -0.06), "tor": (7, 2, 0),
                   "hand_r": V(-0.26, -0.46, 1.0), "ho_r": N["ho_r"], "hip": (0, 1, 0)}, "smooth"))
    k.append((25, {"foot_r": N["foot_r"] + V(0, -0.35, 0.0), "pel": V(0.0, -0.35, -0.02), "tor": (5, 0, 0),
                   "hand_l": N["hand_l"] + V(0, -0.35, 0)}, "smooth"))
    k.append((33, home(-0.35), "smooth"))
    return F.build(k, 33, post=root_post)


def _riposte_wrap():
    P = riposte()
    dbg_tips("Riposte", P, [6, 8, 9, 10, 13])
    return P


clip("Sword_Riposte", events={"windup_end": 6, "hit_start": 8, "hit": 9, "hit_end": 11, "combo_window": [12, 20],
                              "cancel_window": [14, 33], "step_land": 9},
     note="counter after a parry: first frames continue the parry, blade cocks (f2-6), hips lead, front foot steps 0.35 m in "
          "(lands f9 with the thrust), rear foot follows f20-25. Root travel 0.35 m forward, ready_pose (relative to root) at 1.1 s",
     root_motion_m=0.35)(_riposte_wrap)


# ================================================================================================ Shield_Bash
def bash():
    F = CC.F
    k = [(0, dict(N))]
    k.append((2, {"tor": (3, 6, 0), "hip": (0, 3, 0), "pel": V(0.01, 0.02, -0.02),
                  "hand_l": V(0.31, -0.02, 1.02), "elb_l": V(0.55, 0.10, 1.05)}, "smooth"))
    # anticipation: coil (chest turns left, shield pulled to the chest), sword hand goes forward as the counterweight
    k.append((5, {"tor": (2, 15, 0), "hip": (0, 9, 0), "pel": V(0.02, 0.05, -0.04),
                  "hand_l": V(0.30, 0.04, 1.18), "elb_l": V(0.58, 0.30, 1.10), "curl_l": 1.0,
                  "ho_l": ((0.0, -0.5, 0.85), (-1.0, 0.0, 0.0)),
                  "hand_r": V(-0.33, -0.22, 1.00), "ho_r": blade_o((0.15, -0.90, 0.40), (1, 0, 0))}, "smooth"))
    # hips lead: pelvis turns the other way, front foot lifts
    k.append((6, {"hip": (0, -8, 0), "pel": V(0.0, -0.06, -0.05), "foot_l": N["foot_l"] + V(0, -0.10, 0.10)}, "in2"))
    k.append((7, {"hip": (0, -12, 0), "tor": (5, 4, 0), "pel": V(-0.01, -0.14, -0.07),
                  "foot_l": N["foot_l"] + V(0, -0.22, 0.13), "hand_l": V(0.27, -0.10, 1.20)}, "in2"))
    k.append((8, {"tor": (8, -8, 0), "hand_l": V(0.22, -0.34, 1.26), "elb_l": V(0.52, -0.05, 1.10),
                  "hand_r": V(-0.35, -0.10, 1.03)}, "in2"))
    # contact f10: shield at head / chest height, front foot landed 0.30 m ahead
    k.append((10, {"foot_l": N["foot_l"] + V(0, -0.30, 0.0), "pel": V(-0.02, -0.24, -0.08), "tor": (13, -20, 0),
                   "hip": (0, -16, 0), "hand_l": V(0.10, -0.78, 1.32), "elb_l": V(0.48, -0.38, 1.12),
                   "ho_l": ((0.0, -0.6, 0.8), (-1.0, 0.0, 0.0)), "curl_l": 1.0, "head": (2, 8, 0),
                   "hand_r": V(-0.38, 0.06, 1.06), "ho_r": blade_o((0.20, -0.55, 0.80), (1, 0, 0)),
                   "_bow": {"hand_l": V(0.03, 0.0, 0.05)}}, "in2"))
    k.append((11, {"pel": V(-0.02, -0.27, -0.09), "tor": (15, -24, 0), "hand_l": V(0.08, -0.84, 1.33),
                   "hand_r": V(-0.40, 0.09, 1.08)}, "out"))
    k.append((14, {"tor": (10, -14, 0), "hip": (0, -10, 0), "hand_l": V(0.18, -0.70, 1.26), "pel": V(-0.01, -0.27, -0.08),
                   "hand_r": V(-0.35, -0.05, 1.03), "head": (0, 3, 0)}, "smooth"))
    k.append((18, {"foot_r": N["foot_r"] + V(0, -0.15, 0.13), "pel": V(0.0, -0.29, -0.05), "tor": (8, -6, 0), "hip": (0, -4, 0),
                   "hand_l": V(0.27, -0.45, 1.05), "hand_r": V(-0.30, -0.35, 1.0), "head": (0, 0, 0),
                   "ho_l": N["ho_l"], "curl_l": 0.5}, "smooth"))
    k.append((22, {"foot_r": N["foot_r"] + V(0, -0.30, 0.0), "pel": V(0.0, -0.30, -0.02), "tor": (5, 0, 0), "hip": (0, 0, 0),
                   "hand_r": N["hand_r"] + V(0, -0.30, 0), "ho_r": N["ho_r"], "elb_l": None}, "smooth"))
    k.append((27, home(-0.30), "smooth"))
    return F.build(k, 27, post=root_post)


clip("Shield_Bash_Step", events={"windup_end": 5, "hit_start": 8, "hit": 10, "hit_end": 12, "combo_window": [13, 20],
                            "cancel_window": [15, 27], "step_land": 10},
     note="shield arm drives forward at head/chest height with a 0.30 m step-in, shoulder leads, hips turn first, sword arm "
          "pulls back as counterweight; contact f10; root travel 0.30 m; ready_pose (relative to root) at 0.9 s",
     root_motion_m=0.30)(bash)


# ================================================================================================ victim building blocks
VN = dict(N)
VN.update({"hand_r": V(-0.27, -0.06, 0.88), "ho_r": ((0.0, -0.3, -1.0), (1.0, 0.0, 0.0)), "curl_r": 0.5,
           "foot_l": N["foot_l"], "foot_r": N["foot_r"]})


def kneel(**over):
    d = {"pel": V(0, 0.0, -0.415), "hip": (0, 0, 0), "tor": (16, 0, 0), "head": (18, 0, 0),
         "foot_l": V(0.10, 0.50, 0.10), "foot_r": V(-0.10, 0.50, 0.10), "fyaw_l": 0.0, "fyaw_r": 0.0,
         "fpit_l": -80.0, "fpit_r": -80.0,
         "hand_l": V(0.20, -0.06, 0.58), "hand_r": V(-0.20, -0.06, 0.58), "elb_l": None, "elb_r": None,
         "curl_l": 0.4, "curl_r": 0.4}
    d.update(over)
    return d


def prone(**over):
    """face-down on the ground, head toward -Y (toward the attacker)"""
    d = {"pel": V(0, 0.30, -0.75), "hip": (86, 0, 0), "tor": (2, 0, 0), "head": (-14, 0, 0),
         "foot_l": V(0.12, 1.15, 0.10), "foot_r": V(-0.12, 1.15, 0.10), "fyaw_l": 0.0, "fyaw_r": 0.0,
         "fpit_l": -70.0, "fpit_r": -70.0,
         "hand_l": V(0.42, -0.25, 0.12), "hand_r": V(-0.42, -0.25, 0.12), "elb_l": None, "elb_r": None,
         "curl_l": 0.3, "curl_r": 0.3}
    d.update(over)
    return d


# ================================================================================================ Stab through
STAB_N = 60


def stab_attacker():
    F = CC.F
    S = (1.0, 0.0, 0.0)
    k = [(0, dict(N))]
    # anticipation f0-9: sword drawn back to the hip, body coils right, weight to the rear foot
    k.append((3, {"hip": (0, -5, 0), "tor": (5, -7, 0), "pel": V(0.0, 0.03, -0.02), "hand_l": V(0.30, -0.20, 1.05)}, "smooth"))
    k.append((6, {"hip": (0, -10, 0), "tor": (6, -14, 0), "pel": V(0.0, 0.05, -0.04),
                  "hand_r": V(-0.30, 0.10, 1.05), "ho_r": blade_o((0.10, -0.95, 0.30), S), "hand_l": V(0.28, -0.30, 1.16),
                  "_bow": {"hand_r": V(-0.03, 0.05, 0.06)}}, "smooth"))
    k.append((9, {"hip": (0, -16, 0), "tor": (7, -28, 0), "pel": V(0.0, 0.08, -0.07), "head": (0, 10, 0),
                  "hand_r": V(-0.32, 0.26, 1.02), "ho_r": blade_o((0.10, -0.99, 0.08), S), "elb_r": V(-0.55, 0.42, 1.00)}, "smooth"))
    k.append((10, {"hand_r": V(-0.32, 0.28, 1.02), "tor": (7, -30, 0)}, "smooth"))     # moving hold, blade drawn right back
    # hips lead
    k.append((11, {"hip": (0, 2, 0), "pel": V(0.02, -0.08, -0.07), "foot_l": N["foot_l"] + V(0, -0.14, 0.14),
                   "tor": (8, -22, 0), "elb_r": None}, "in2"))
    k.append((12, {"hip": (0, 10, 0), "pel": V(0.03, -0.20, -0.10), "foot_l": N["foot_l"] + V(0, -0.34, 0.16),
                   "tor": (12, -4, 0), "hand_r": V(-0.29, -0.28, 1.12), "ho_r": blade_o((0.06, -0.97, 0.22), S),
                   "hand_l": V(0.34, -0.10, 1.10)}, "in2"))
    # contact f14: lunge landed, blade tip 0.3 m past the victim's back line
    k.append((14, {"hip": (0, 14, 0), "pel": V(0.04, -0.36, -0.13), "foot_l": N["foot_l"] + V(0, -0.50, 0.0),
                   "tor": (16, 12, 0), "hand_r": V(-0.10, -0.86, 1.24), "ho_r": blade_o((0.03, -0.995, 0.05), S),
                   "head": (2, -6, 0), "hand_l": V(0.36, -0.02, 1.08)}, "in2"))
    # hold with a slight twist of the blade and body
    k.append((20, {"hand_r": V(-0.10, -0.89, 1.24), "tor": (16, 17, 0), "hip": (0, 17, 0), "pel": V(0.04, -0.37, -0.14),
                   "ho_r": blade_o((0.03, -0.995, 0.05), (0.7, 0, 0.7)), "head": (2, -3, 0)}, "smooth"))
    k.append((27, {"hand_r": V(-0.10, -0.89, 1.24), "tor": (16, 19, 0), "hip": (0, 18, 0),
                   "ho_r": blade_o((0.03, -0.995, 0.05), (0.0, 0, 1.0))}, "smooth"))
    # pull out (blade goes back along its own line), front foot steps back
    k.append((33, {"hand_r": V(-0.13, -0.55, 1.22), "ho_r": blade_o((0.05, -0.99, 0.10), (0.0, 0, 1.0)),
                   "tor": (14, 8, 0), "hip": (0, 8, 0), "pel": V(0.03, -0.30, -0.10),
                   "foot_l": N["foot_l"] + V(0, -0.36, 0.10)}, "in2"))
    k.append((38, {"hand_r": V(-0.26, -0.36, 1.06), "ho_r": blade_o((0.25, -0.65, -0.70), S),
                   "foot_l": N["foot_l"] + V(0, -0.24, 0.0), "pel": V(0.02, -0.26, -0.07), "tor": (12, 0, 0), "hip": (0, 2, 0),
                   "head": (0, 0, 0), "_bow": {"hand_r": V(-0.05, 0.0, 0.10)}}, "smooth"))
    k.append((42, {"foot_l": N["foot_l"] + V(0, -0.22, 0.0), "pel": V(0.0, -0.22, -0.04), "tor": (7, 0, 0), "hip": (0, 0, 0),
                   "hand_r": V(-0.29, -0.28, 0.98), "ho_r": blade_o((0.25, -0.85, 0.2), S),
                   "foot_r": N["foot_r"] + V(0, -0.11, 0.13), "hand_l": N["hand_l"] + V(0, -0.22, 0)}, "smooth"))
    k.append((47, {"foot_r": N["foot_r"] + V(0, -0.22, 0.0), "pel": V(0, -0.22, -0.01)}, "smooth"))
    k.append((52, home(-0.22), "smooth"))
    return F.build(k, STAB_N, post=root_post)


def _stab_wrap():
    P = stab_attacker()
    dbg_tips("Stab", P, [12, 14, 20, 27, 33])
    return P


clip("Finisher_Stab_Through", events={"victim_dist_m": 1.35, "windup_end": 10, "hit_start": 12, "hit": 14, "hit_end": 27, "victim_react": 14,
                                      "victim_down": 56, "cancel_window": [52, 60]},
     note="PAIR with Finisher_Stab_Through_Victim (same 61 frames). Victim root at attacker +1.2 m forward, rotated 180 deg. "
          "Thrust through the chest at f14 (tip ~0.3 m past the victim's back), 13 f hold with a twist, pull out + step back. "
          "Root travel 0.22 m net (lunge 0.36, steps back to 0.22).", root_motion_m=0.22)(_stab_wrap)


def stab_victim():
    F = CC.F
    k = [(0, dict(VN))]
    k.append((5, {"pel": V(0.01, 0.0, -0.01), "head": (0, 3, 0), "tor": (5, 2, 0)}, "smooth"))
    k.append((10, {"head": (-3, 0, 0), "tor": (2, 0, 0), "pel": V(0.0, 0.03, 0.0), "hand_l": V(0.29, -0.16, 1.05),
                   "hand_r": V(-0.29, -0.16, 1.05), "curl_l": 0.2, "curl_r": 0.2}, "smooth"))
    k.append((12, {"tor": (0, 0, 0), "pel": V(0.0, 0.05, 0.0), "head": (-6, 0, 0)}, "in2"))
    # impact f14: chest driven back onto the blade, head whips back, hands fly out, then the body folds over the blade
    k.append((14, {"tor": (-6, 0, 0), "head": (-16, 0, 0), "pel": V(0.0, 0.10, -0.01), "hand_l": V(0.48, 0.0, 1.30),
                   "hand_r": V(-0.48, 0.0, 1.30), "curl_l": -0.4, "curl_r": -0.4}, "in2"))
    k.append((16, {"tor": (24, 0, 2), "head": (12, 0, 0), "pel": V(0.0, 0.12, -0.03), "hip": (6, 0, 0),
                   "hand_l": V(0.12, -0.14, 1.20), "hand_r": V(-0.12, -0.14, 1.20), "curl_l": 1.0, "curl_r": 1.0}, "out2"))
    # pinned on the blade (tremble)
    k.append((22, {"tor": (27, 0, -2), "head": (16, 0, 0), "pel": V(0.0, 0.13, -0.05), "hip": (8, 0, 0)}, "smooth"))
    k.append((28, {"tor": (25, 0, 3), "head": (14, 0, 0), "pel": V(0.0, 0.12, -0.07), "hip": (7, 0, 0)}, "smooth"))
    # blade pulled out: jerk forward, knees buckle
    k.append((31, {"tor": (36, 0, 4), "head": (24, 0, 0), "pel": V(0.0, 0.06, -0.17), "hip": (10, 0, 0),
                   "hand_l": V(0.12, -0.10, 1.05), "hand_r": V(-0.12, -0.10, 1.05)}, "in2"))
    k.append((35, kneel(**{"pel": V(0, 0.0, -0.415), "tor": (32, 0, 3), "head": (24, 0, 0), "hip": (4, 0, 0),
                           "foot_l": V(0.11, 0.30, 0.16), "foot_r": V(-0.11, 0.30, 0.16), "fpit_l": -30.0, "fpit_r": -30.0,
                           "hand_l": V(0.10, -0.16, 0.85), "hand_r": V(-0.10, -0.16, 0.85)}), "in2"))
    k.append((38, kneel(**{"tor": (26, 0, 5), "head": (20, 0, 0), "hand_l": V(0.08, -0.18, 0.80), "hand_r": V(-0.08, -0.18, 0.80),
                           "curl_l": 0.8, "curl_r": 0.8}), "out2"))
    k.append((44, kneel(**{"tor": (22, 0, -3), "head": (26, 0, 0), "pel": V(0, -0.02, -0.415), "hand_l": V(0.10, -0.18, 0.78),
                           "hand_r": V(-0.10, -0.18, 0.78)}), "smooth"))
    # topples face-down
    k.append((49, kneel(**{"pel": V(0, -0.10, -0.42), "hip": (30, 0, 0), "tor": (30, 0, 0), "head": (10, 0, 0),
                           "hand_l": V(0.25, -0.35, 0.45), "hand_r": V(-0.25, -0.35, 0.45)}), "in2"))
    k.append((53, kneel(**{"pel": V(0, 0.05, -0.70), "hip": (68, 0, 0), "tor": (10, 0, 0), "head": (-15, 0, 0),
                           "foot_l": V(0.11, 0.80, 0.14), "foot_r": V(-0.11, 0.80, 0.14), "fpit_l": -60.0, "fpit_r": -60.0,
                           "hand_l": V(0.40, -0.45, 0.20), "hand_r": V(-0.40, -0.45, 0.20)}), "in2"))
    k.append((56, prone(**{"pel": V(0, 0.28, -0.75)}), "out2"))
    k.append((58, prone(**{"pel": V(0, 0.29, -0.755), "hip": (85, 0, 0), "tor": (1, 0, 0)}), "smooth"))
    k.append((60, prone(**{"pel": V(0, 0.29, -0.755), "hip": (85, 0, 0), "tor": (1, 0, 0)}), "smooth"))

    def post(fr, n, s):
        if 16 <= fr <= 28:
            w = 1.0 if fr < 26 else (28 - fr) / 2.0
            e = shake(fr, 3, 0.012 * w, every=1, dim=3)
            s["pel"] = V(s["pel"].x + e.x, s["pel"].y + e.y * 0.5, s["pel"].z)
            s["tor"] = (s["tor"][0] + e.z * 60, s["tor"][1], s["tor"][2] + e.x * 50)
    return F.build(k, STAB_N, post=post)


clip("Finisher_Stab_Through_Victim", events={"victim_dist_m": 1.35, "hit": 14, "victim_react": 14, "victim_down": 56, "cancel_window": [56, 60]},
     note="PAIR victim of Finisher_Stab_Through (61 frames). Authored in its own frame (faces -Y). The attacker stands 1.2 m in front "
          "of it, at local y = -1.2; the blade enters the chest at f14 and its tip ends ~0.5 m behind the victim's pelvis "
          "(local +Y). Ends face-down on the ground with the head toward the attacker (local -Y), terminal.")(stab_victim)


# ================================================================================================ Overhead cleave
CLV_N = 54


def cleave_attacker():
    F = CC.F
    S = (1.0, 0.0, 0.0)
    up = {"foot_l": N["foot_l"] + V(0, 0, 0.045), "foot_r": N["foot_r"] + V(0, 0, 0.045), "fpit_l": -22.0, "fpit_r": -22.0}
    k = [(0, dict(N))]
    k.append((3, {"tor": (2, -2, 0), "pel": V(0, 0.01, 0.005), "hand_l": V(0.32, -0.18, 1.10)}, "smooth"))
    k.append((6, {"tor": (-2, -3, 0), "pel": V(0, 0.02, 0.01), "hand_r": V(-0.24, -0.20, 1.32),
                  "ho_r": blade_o((0.10, -0.30, 0.95), S), "hand_l": V(0.36, -0.20, 1.30),
                  "_bow": {"hand_r": V(-0.05, 0.05, 0.0)}}, "smooth"))
    k.append((10, {"tor": (-8, -2, 0), "pel": V(0, 0.03, 0.03), "hand_r": V(-0.17, -0.10, 1.78),
                   "ho_r": blade_o((0.05, 0.45, 0.89), S), "hand_l": V(0.40, -0.10, 1.45), "hip": (-2, -2, 0), "head": (-6, 0, 0)}, "smooth"))
    k.append((14, dict({"tor": (-14, -2, 0), "hip": (-4, -3, 0), "pel": V(0, 0.04, 0.05), "hand_r": V(-0.14, -0.08, 1.96),
                        "ho_r": blade_o((0.05, 0.65, 0.76), S), "hand_l": V(0.42, -0.05, 1.55), "head": (-10, 0, 0)}, **up), "smooth"))
    k.append((16, {"hand_r": V(-0.14, -0.06, 1.98), "tor": (-15, -2, 0), "pel": V(0, 0.05, 0.055),
                   "ho_r": blade_o((0.05, 0.70, 0.71), S)}, "smooth"))       # moving hold at the top
    # hips lead: pelvis drives, front foot steps 0.35 m
    k.append((17, {"pel": V(0.01, -0.06, 0.02), "hip": (2, 5, 0), "foot_l": N["foot_l"] + V(0, -0.10, 0.14), "fpit_l": 0.0,
                   "fpit_r": -10.0, "foot_r": N["foot_r"] + V(0, 0, 0.025)}, "in2"))
    k.append((18, {"pel": V(0.02, -0.20, -0.03), "hip": (4, 8, 0), "foot_l": N["foot_l"] + V(0, -0.26, 0.12), "tor": (-4, 3, 0),
                   "hand_r": V(-0.11, -0.12, 1.95), "ho_r": blade_o((0.05, 0.60, 0.80), S), "head": (0, 0, 0)}, "in2"))
    k.append((19, {"tor": (10, 10, 0), "hand_r": V(-0.09, -0.36, 1.92), "ho_r": blade_o((0.0, 0.0, 1.0), S),
                   "_bow": {"hand_r": V(0.0, 0.0, 0.12)}}, "in2"))
    # contact f20: blade onto the victim's shoulder / neck line
    k.append((20, {"pel": V(0.02, -0.30, -0.10), "hip": (5, 4, 0), "foot_l": N["foot_l"] + V(0, -0.35, 0.0),
                   "tor": (20, 6, 0), "hand_r": V(-0.05, -0.64, 1.70), "ho_r": blade_o((0.0, -0.60, -0.80), S),
                   "hand_l": V(0.36, -0.05, 1.20), "head": (6, 0, 0)}, "in2"))
    # overshoot to the ground side
    k.append((22, {"pel": V(0.02, -0.33, -0.15), "tor": (28, 4, 0), "hand_r": V(-0.05, -0.66, 1.27),
                   "ho_r": blade_o((0.0, -0.45, -0.89), S), "head": (10, 0, 0), "hip": (7, 3, 0),
                   "_bow": {"hand_r": V(0.0, -0.04, 0.0)}}, "out"))
    k.append((27, {"hand_r": V(-0.10, -0.70, 1.08), "ho_r": blade_o((0.05, -0.40, -0.91), S), "tor": (29, 3, 0), "head": (10, 0, 0),
                   "pel": V(0.02, -0.34, -0.16)}, "smooth"))
    # recover
    k.append((33, {"tor": (18, 0, 0), "head": (2, 0, 0), "hand_r": V(-0.22, -0.55, 1.02), "ho_r": blade_o((0.15, -0.90, -0.30), S),
                   "pel": V(0.01, -0.34, -0.10), "foot_r": N["foot_r"] + V(0, -0.14, 0.13), "hand_l": V(0.30, -0.12, 1.05), "hip": (3, 1, 0)}, "smooth"))
    k.append((40, {"tor": (8, 0, 0), "pel": V(0, -0.35, -0.03), "foot_r": N["foot_r"] + V(0, -0.35, 0.0), "hip": (0, 0, 0),
                   "hand_r": N["hand_r"] + V(0, -0.35, 0), "ho_r": N["ho_r"], "hand_l": N["hand_l"] + V(0, -0.35, 0), "head": (0, 0, 0)}, "smooth"))
    k.append((48, home(-0.35), "smooth"))
    return F.build(k, CLV_N, post=root_post)


def _cleave_wrap():
    P = cleave_attacker()
    dbg_tips("Cleave", P, [16, 18, 19, 20, 22, 27])
    return P


clip("Finisher_Overhead_Cleave", events={"victim_dist_m": 1.2, "windup_end": 17, "hit_start": 18, "hit": 20, "hit_end": 23, "victim_react": 20,
                                         "victim_down": 42, "cancel_window": [40, 54]},
     note="PAIR with Finisher_Overhead_Cleave_Victim (same 55 frames). Victim (kneeling) root at attacker +1.2 m forward rotated 180 deg. "
          "Long overhead windup on the toes (f0-16), 3-frame cleave, blade meets the victim's shoulder/neck line at f20 "
          "(tip ~1.15 m ahead of the attacker origin at z ~1.0), overshoot to the ground side. Root travel 0.35 m.",
     root_motion_m=0.35)(_cleave_wrap)


def cleave_victim():
    F = CC.F
    k = [(0, kneel())]
    k.append((5, kneel(**{"tor": (19, 0, 3), "head": (24, 4, 3), "pel": V(0.015, 0.0, -0.415)}), "smooth"))
    k.append((10, kneel(**{"tor": (13, 0, -3), "head": (16, -4, -3), "pel": V(-0.015, 0.0, -0.41)}), "smooth"))
    k.append((15, kneel(**{"tor": (10, 0, 2), "head": (-6, 0, 2), "pel": V(0.0, 0.0, -0.405),
                           "hand_r": V(-0.24, -0.20, 0.72), "curl_r": 0.0}), "smooth"))
    k.append((19, kneel(**{"tor": (6, 0, 0), "head": (-14, 0, 0), "pel": V(0.0, 0.01, -0.40),
                           "hand_r": V(-0.26, -0.30, 1.02), "curl_r": 0.0, "hand_l": V(0.22, -0.10, 0.62)}), "smooth"))
    # blow f20: shoulder / neck line driven down and to the victim's left
    k.append((20, kneel(**{"tor": (16, 6, 12), "head": (12, 0, 22), "pel": V(0.03, 0.02, -0.43),
                           "hand_r": V(-0.36, -0.15, 0.90), "hand_l": V(0.30, 0.0, 0.70), "curl_r": 0.8}), "in2"))
    k.append((22, kneel(**{"tor": (24, 8, 34), "head": (14, 0, 20), "pel": V(0.09, 0.03, -0.45), "hip": (0, 0, 10),
                           "hand_r": V(-0.30, 0.05, 0.75), "hand_l": V(0.50, -0.10, 0.55), "curl_r": 0.5}), "out2"))
    k.append((28, kneel(**{"tor": (16, 4, 30), "head": (10, 0, 15), "pel": V(0.18, 0.04, -0.55), "hip": (0, 0, 38),
                           "hand_l": V(0.62, -0.10, 0.35), "hand_r": V(0.12, -0.05, 0.50)}), "smooth"))
    k.append((36, kneel(**{"tor": (10, 0, 12), "head": (5, 0, 6), "pel": V(0.28, 0.05, -0.72), "hip": (0, 0, 72),
                           "hand_l": V(0.70, -0.20, 0.14), "hand_r": V(0.42, -0.10, 0.34)}), "in2"))
    k.append((42, kneel(**{"tor": (6, 0, 8), "head": (0, 0, 8), "pel": V(0.34, 0.05, -0.77), "hip": (0, 0, 82),
                           "hand_l": V(0.75, -0.25, 0.10), "hand_r": V(0.50, -0.12, 0.28), "curl_l": 0.2, "curl_r": 0.2}), "out2"))
    k.append((46, kneel(**{"tor": (6, 0, 8), "head": (0, 0, 8), "pel": V(0.34, 0.05, -0.775), "hip": (0, 0, 83),
                           "hand_l": V(0.75, -0.25, 0.10), "hand_r": V(0.52, -0.12, 0.28), "curl_l": 0.2, "curl_r": 0.2}), "smooth"))
    k.append((54, kneel(**{"tor": (6, 0, 8), "head": (0, 0, 8), "pel": V(0.34, 0.05, -0.775), "hip": (0, 0, 83),
                           "hand_l": V(0.75, -0.25, 0.10), "hand_r": V(0.52, -0.12, 0.28), "curl_l": 0.2, "curl_r": 0.2}), "smooth"))
    return F.build(k, CLV_N)


clip("Finisher_Overhead_Cleave_Victim", events={"victim_dist_m": 1.2, "hit": 20, "victim_react": 20, "victim_down": 42, "cancel_window": [42, 54]},
     note="PAIR victim of Finisher_Overhead_Cleave (55 frames). Own frame (faces -Y); starts kneeling and swaying; the attacker "
          "stands 1.2 m in front (local y = -1.2). Shoulder/neck line at local (x~0, y~-0.1, z~1.0). Collapses sideways onto its "
          "left side (+X), terminal.")(cleave_victim)


# ================================================================================================ Spin slash
SPN_N = 50


def _C(f):
    """chest yaw (deg, left +) over the spin: coil right, 360 deg spin, contact slows it, overshoot, settle"""
    if f <= 0:
        return 0.0
    if f <= 4:
        return -30.0 * sm(f / 4.0)
    if f <= 16:
        return -30.0 + 422.0 * ((f - 4) / 12.0) ** 1.5
    if f <= 19:
        return 392.0 + 28.0 * ease("out2", (f - 16) / 3.0)
    if f <= 26:
        return 420.0 - 60.0 * sm((f - 19) / 7.0)
    return 360.0


def _alpha(f):
    """blade radial direction in the chest frame (deg, left +): trails at the right (-90), whips forward at the hit"""
    if f <= 11:
        return -90.0
    if f <= 16:
        return -90.0 + 84.0 * ease("in2", (f - 11) / 5.0)
    if f <= 19:
        return -6.0 + 10.0 * ease("out2", (f - 16) / 3.0)
    return 4.0 - 29.0 * sm((f - 19) / 7.0)


SPIN_ALPHA_HIT = -32.0


def spin_state(f):
    C = _C(f)
    Yh = _C(f + 1)
    Ch = _C(f - 0.25)
    Cb = _C(f - 0.5)
    al = _alpha(f)
    alh = _alpha(f - 0.5)
    a = math.radians
    # pelvis: step-in over f0-5, then planted over the pivot foot
    u = sm(min(1.0, f / 5.0))
    pel = V(0.09 * u, -0.25 * u, -0.05 * (1 - abs(2 * sm(min(1.0, f / 6.0)) - 1)) - 0.03 * u)
    st = {"pel": pel, "curl_r": 1.0, "curl_l": 0.6}
    tor_rel = C - Yh
    R = 0.50 + 0.13 * sm((f - 4) / 6.0) - 0.10 * sm((f - 16) / 4.0)
    z = 1.28 + 0.17 * sm((f - 4) / 10.0)
    st["hand_r"] = rel(R * math.sin(a(alh)), R * math.cos(a(alh)), z, Ch, (pel.x, pel.y))
    dz = 0.35 - 0.40 * sm((f - 3) / 8.0)
    dvec = TF(math.sin(a(al)), math.cos(a(al)), dz, Cb)
    st["ho_r"] = blade_o(dvec, (0, 0, 1))
    st["hand_l"] = rel(0.28, 0.34, 1.16, C, (pel.x, pel.y))
    st["elb_l"] = None
    hy = max(-50.0, min(50.0, _C(f + 2) - C))
    st["head"] = (0.0, hy, 0.0)
    pv = N["foot_l"] + V(0, -0.25, 0)
    fyl = 6.0
    if f < 5:
        s5 = sm(f / 5.0)
        st["foot_l"] = N["foot_l"] + V(0, -0.25 * s5, 0.12 * math.sin(math.pi * s5))
    else:
        st["foot_l"] = pv
        if f >= 6:
            fyl = Yh + 36.0 - 30.0 * sm((f - 6) / 14.0)
    off0 = (-0.26, 0.29)
    off1 = (-0.26, 0.04)
    fyr = N["fyaw_r"]
    if f <= 6:
        st["foot_r"] = N["foot_r"]
    else:
        Yh6 = _C(7)
        A = min(360.0, (Yh - Yh6) * 360.0 / 390.0)
        s = sm(min(1.0, (f - 6) / 9.0))
        ox = off0[0] + (off1[0] - off0[0]) * s
        oy = off0[1] + (off1[1] - off0[1]) * s
        c, sn = math.cos(a(A)), math.sin(a(A))
        lift = 0.13 * math.sin(math.pi * min(1.0, (f - 6) / 9.0)) if f < 15 else 0.0
        st["foot_r"] = V(pv.x + ox * c - oy * sn, pv.y + ox * sn + oy * c, 0.104 + lift)
        fyr = N["fyaw_r"] + (A if A < 359.99 else 0.0)
    if f >= 25:            # wrap the full turn (poses are sampled per frame, so this is a pure re-labelling)
        Yh -= 360.0
        fyl -= 360.0
    st["hip"] = (0.0, Yh, 0.0)
    st["tor"] = (7.0, tor_rel, 0.0)
    st["fyaw_l"] = fyl
    st["fyaw_r"] = fyr
    st["fpit_l"] = 0.0
    st["fpit_r"] = 0.0
    return st


def spin_attacker():
    F = CC.F
    S = (1.0, 0.0, 0.0)
    k = [(0, dict(N))]
    for f in range(3, 28):
        k.append((f, spin_state(f), "smooth" if f == 3 else "lin"))
    # flourish: blade drawn up beside the face, then flicked down to the ready position
    k.append((31, {"hand_r": V(-0.26, -0.42, 1.40), "ho_r": blade_o((0.15, -0.20, 0.97), S), "tor": (6, -4, 0),
                   "head": (0, 0, 0), "pel": V(0.0, -0.25, -0.03),
                   "hand_l": V(0.30, -0.42, 1.02), "curl_r": 1.0, "_bow": {"hand_r": V(-0.05, 0.0, 0.10)}}, "smooth"))
    k.append((34, {"hand_r": V(-0.30, -0.55, 1.16), "ho_r": blade_o((0.35, -0.75, -0.55), S)}, "in2"))
    k.append((37, {"hand_r": V(-0.28, -0.42, 1.02), "ho_r": blade_o((0.30, -0.85, 0.10), S), "tor": (5, 0, 0)}, "out2"))
    k.append((44, home(-0.25), "smooth"))
    return F.build(k, SPN_N, post=root_post)


def _spin_wrap():
    P = spin_attacker()
    dbg_tips("Spin", P, [12, 14, 15, 16, 17, 18, 19])
    return P


clip("Finisher_Spin_Slash", events={"victim_dist_m": 1.35, "windup_end": 5, "hit_start": 14, "hit": 16, "hit_end": 19, "victim_react": 16,
                                    "victim_down": 34, "cancel_window": [44, 50]},
     note="PAIR with Finisher_Spin_Slash_Victim (same 51 frames). Victim root at attacker +1.2 m forward rotated 180 deg. "
          "0.25 m step-in with the front foot, then a 360 deg spin on that planted foot (hips lead, chest lags 1 f, arm whips), "
          "horizontal slash through neck/chest height at f16, flourish (blade flick) f26-37. Root travel 0.25 m.",
     root_motion_m=0.25)(_spin_wrap)


def spin_victim():
    F = CC.F
    k = [(0, dict(VN))]
    k.append((6, {"pel": V(0.01, 0.0, -0.01), "head": (0, 3, 0)}, "smooth"))
    k.append((11, {"hand_l": V(0.30, -0.18, 1.10), "hand_r": V(-0.30, -0.18, 1.10), "curl_l": 0.2, "curl_r": 0.2,
                   "head": (-3, 0, 0), "pel": V(0.0, 0.03, -0.02), "tor": (2, 0, 0)}, "smooth"))
    k.append((14, {"pel": V(0.0, 0.05, -0.03), "tor": (0, 0, 0)}, "smooth"))
    # blade crosses the neck / chest at f16 from the victim's left to right: torso twists to the right, head whips
    k.append((16, {"tor": (-4, -8, -4), "head": (-10, -14, -6), "pel": V(0.0, 0.07, -0.02)}, "in2"))
    k.append((18, {"tor": (-14, -38, -10), "hip": (-6, -22, 0), "head": (-22, -34, -12), "pel": V(-0.03, 0.14, -0.03),
                   "hand_l": V(0.50, 0.08, 1.50), "hand_r": V(-0.38, 0.12, 1.25), "curl_l": -0.5, "curl_r": -0.5,
                   "foot_r": VN["foot_r"] + V(-0.02, 0.10, 0.06)}, "out2"))
    k.append((22, {"tor": (-16, -30, -8), "hip": (-18, -34, 0), "head": (-18, -20, -8), "pel": V(-0.05, 0.28, -0.14),
                   "hand_l": V(0.55, 0.30, 1.35), "hand_r": V(-0.42, 0.22, 1.05),
                   "foot_r": VN["foot_r"] + V(-0.03, 0.22, 0.10), "foot_l": VN["foot_l"] + V(0.02, 0.06, 0.05)}, "smooth"))
    k.append((27, {"tor": (-8, -12, -4), "hip": (-50, -16, 0), "head": (-10, -6, 0), "pel": V(-0.03, 0.42, -0.40),
                   "hand_l": V(0.55, 0.40, 1.00), "hand_r": V(-0.46, 0.38, 0.85),
                   "foot_r": VN["foot_r"] + V(-0.04, 0.10, 0.10), "foot_l": VN["foot_l"] + V(0.02, 0.10, 0.10)}, "in2"))
    # lands on its back
    k.append((32, {"tor": (-2, 0, 0), "hip": (-86, 0, 0), "head": (14, 0, 0), "pel": V(0.0, 0.62, -0.77),
                   "foot_l": V(0.14, -0.08, 0.10), "foot_r": V(-0.14, -0.10, 0.10), "fpit_l": 20.0, "fpit_r": 20.0,
                   "hand_l": V(0.50, 0.85, 0.10), "hand_r": V(-0.52, 0.90, 0.10)}, "in2"))
    k.append((34, {"hip": (-84, 0, 0), "head": (10, 0, 0), "pel": V(0.0, 0.66, -0.775), "tor": (-1, 0, 0),
                   "hand_l": V(0.52, 0.95, 0.10), "hand_r": V(-0.54, 1.0, 0.10)}, "out2"))
    k.append((38, {"pel": V(0.0, 0.66, -0.775), "head": (8, 5, 0), "fpit_l": 15.0, "fpit_r": 15.0}, "smooth"))
    k.append((50, {"pel": V(0.0, 0.66, -0.775), "head": (8, 5, 0)}, "smooth"))
    return F.build(k, SPN_N)


clip("Finisher_Spin_Slash_Victim", events={"victim_dist_m": 1.35, "hit": 16, "victim_react": 16, "victim_down": 34, "cancel_window": [34, 50]},
     note="PAIR victim of Finisher_Spin_Slash (51 frames). Own frame (faces -Y); the attacker stands 1.2 m in front at local y = -1.2. "
          "Neck/chest line at local z ~1.3-1.5. Twists right on the slash, then falls backwards (+Y local) onto its back, "
          "terminal (head at local y ~ +1.3).")(spin_victim)
