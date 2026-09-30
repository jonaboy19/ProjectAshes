# TOWN-LIFE clips, part 3: resting (bench / ground / chair / doze / sleep), prayer (kneel / stand).
# Helpers (looped, oneshot, idle_layer, seat_pose ...) come from life_clips_market.py.
#
# SEAT FRAME (bench family): the character stands at the origin with the bench BEHIND him; the seat centre is 0.32 m behind the
# origin (anchor.at.y = -0.32 in the anchor's "forward" convention). The pelvis travels back and down onto the seat during the
# Enter clip, the feet stay where they are, so Enter -> loop -> Exit blend with no foot slide.
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V, stance
from life_common import life_clip, neutral, grip_o, wrist_at, sinw
from life_clips_market import (looped, oneshot, idle_layer, chain2, contra, seat_pose, PALM_DN, PALM_UP)

BY = 0.30                                                  # pelvis offset (m, backwards) of the bench family
BENCH = {"type": "bench", "at": [0.0, -0.32, 0.45], "size": [1.3, 0.36, 0.45], "offset": [0.0, 0.0, 0.0], "face": "away",
         "note": "the bench is BEHIND the standing character (seat centre 0.32 m behind the root, top 0.45 m)"}
KNEE_Z = 0.66
HAND_KNEE_L = V(0.17, BY - 0.27 + 0.05, KNEE_Z)
HAND_KNEE_R = V(-0.17, BY - 0.27 + 0.05, KNEE_Z)


def _bench_base():
    b = neutral()
    b.update(seat_pose(0.45, BY, 9.0))
    b.update({"hip": (0.0, 0.0, 0.0), "hand_l": wrist_at("l", HAND_KNEE_L, PALM_DN), "hand_r": wrist_at("r", HAND_KNEE_R, PALM_DN),
              "ho_l": PALM_DN, "ho_r": PALM_DN, "curl_l": 0.15, "curl_r": 0.15, "elb_l": V(0.36, BY + 0.08, 0.86),
              "elb_r": V(-0.36, BY + 0.08, 0.86), "head": (-2.0, 0.0, 0.0)})
    return b


BB = _bench_base()


def _t(s, k):
    return tuple(s[k])


@life_clip("Life_Rest_Sit_Bench", loop=True, category="rest/sit", anchor=dict(BENCH), tags=["rest", "sit", "bench"],
           enter="Life_Rest_Sit_Bench_Enter", exit="Life_Rest_Sit_Bench_Exit", events={"glance": [34, 148], "sigh": [124]},
           note="idle on a bench (seat 0.45 m): hands resting on the knees, glances left and right, leans forward with the forearms on "
                "the thighs for a while, sits back and sighs, drums the fingers on the knee")
def _sit_bench():
    b = BB
    keys = [
        (22, {"head": (0.0, 24.0, 0.0), "tor": (8.0, 5.0, 0.0)}, "smooth"),                     # glance left
        (44, {"head": (-1.0, 30.0, 0.0), "tor": (8.0, 6.0, 0.0)}, "smooth"),
        (58, {"head": (-3.0, -8.0, 0.0), "tor": (9.0, -2.0, 0.0)}, "smooth"),
        # lean forward, forearms on the thighs, hands loosely together between the knees
        (78, {"tor": (26.0, 0.0, 0.0), "head": (-16.0, 6.0, 0.0), "hand_l": V(0.10, BY - 0.33, 0.66),
              "hand_r": V(-0.10, BY - 0.33, 0.64), "elb_l": V(0.26, BY - 0.05, 0.70), "elb_r": V(-0.26, BY - 0.05, 0.70),
              "curl_l": 0.5, "curl_r": 0.6, "ho_l": ((0.25, -1.0, 0.0), (-0.5, 0.0, 0.85)), "ho_r": ((-0.25, -1.0, 0.0), (0.5, 0.0, 0.85))}, "smooth"),
        (108, {"head": (-18.0, -10.0, 0.0)}, "smooth"),
        (120, {"tor": b["tor"], "head": (-2.0, 0.0, 0.0), "hand_l": b["hand_l"], "hand_r": b["hand_r"], "elb_l": b["elb_l"],
               "elb_r": b["elb_r"], "curl_l": 0.15, "curl_r": 0.15, "ho_l": PALM_DN, "ho_r": PALM_DN}, "smooth"),
        (128, {"tor": (4.0, 0.0, 0.0), "head": (-8.0, 0.0, 0.0), "shrug_l": 6.0, "shrug_r": 6.0}, "smooth"),      # breath in
        (140, {"tor": (10.0, 0.0, 0.0), "head": (4.0, 0.0, 0.0), "shrug_l": -2.0, "shrug_r": -2.0}, "smooth"),   # sigh out
        (150, {"shrug_l": 0.0, "shrug_r": 0.0, "head": (0.0, -18.0, 0.0), "tor": (9.0, -4.0, 0.0)}, "smooth"),
        (162, {"curl_r": 0.6}, "in2"), (166, {"curl_r": 0.15}, "out2"), (170, {"curl_r": 0.6}, "in2"), (174, {"curl_r": 0.15}, "out2"),
    ]
    return looped(b, 192, keys, post=idle_layer(1, 0.35, pel=0.003, tor=0.5))


@life_clip("Life_Rest_Sit_Bench_Enter", loop=False, category="rest/sit", anchor=dict(BENCH), tags=["rest", "sit", "bench", "enter"],
           note="stands with the bench behind him, glances back over the shoulder, turns the hips a little, leans forward and lowers "
                "onto the seat (pelvis travels 0.30 m back and 0.37 m down over the planted feet), hands find the knees. "
                "The game turns the character to face away from the bench first.")
def _sit_bench_enter():
    n = 66
    b = BB
    s0 = neutral()
    keys = [
        (8, {"head": (0.0, -40.0, 0.0), "tor": (2.0, -18.0, 0.0), "hip": (0.0, -8.0, 0.0)}, "smooth"),           # look back over the shoulder
        (14, {"head": (0.0, -46.0, 0.0), "tor": (3.0, -22.0, 0.0), "hip": (0.0, -10.0, 0.0), "hand_r": V(-0.26, 0.10, 0.90),
              "elb_r": V(-0.40, 0.24, 0.98)}, "smooth"),                                                          # hand reaches back
        (22, {"head": (4.0, -10.0, 0.0), "tor": (14.0, -4.0, 0.0), "hip": (0.0, -3.0, 0.0), "pel": V(0, 0.02, -0.03),
              "hand_r": V(-0.27, -0.10, 0.90), "elb_r": None}, "smooth"),                                        # weight forward, ready
        (36, {"pel": V(0, BY * 0.55, -0.30), "tor": (26.0, 0.0, 0.0), "hip": (0.0, 0.0, 0.0), "head": (-6.0, 0.0, 0.0),
              "hand_l": V(0.24, -0.16, 0.86), "hand_r": V(-0.24, -0.16, 0.86), "_bow": {"pel": V(0, 0.0, 0.03)}}, "smooth"),
        (46, {"pel": V(0, BY, b["pel"].z - 0.012), "tor": (14.0, 0.0, 0.0)}, "in2"),                             # touch down (small overshoot)
        (52, {"pel": b["pel"], "tor": b["tor"], "head": b["head"], "hand_l": b["hand_l"], "hand_r": b["hand_r"], "elb_l": b["elb_l"],
              "elb_r": b["elb_r"], "curl_l": b["curl_l"], "curl_r": b["curl_r"]}, "out2"),
        (66, {"foot_l": b["foot_l"], "foot_r": b["foot_r"], "fyaw_l": b["fyaw_l"], "fyaw_r": b["fyaw_r"]}, "smooth"),
    ]
    st = dict(s0)
    ks = [(0, st)] + keys
    return CC.F.build(ks, n, post=None)


@life_clip("Life_Rest_Sit_Bench_Exit", loop=False, category="rest/sit", anchor=dict(BENCH), tags=["rest", "sit", "bench", "exit"],
           note="stands up from the bench: a beat of preparation, leans forward pressing on the knees, pelvis moves forward over the "
                "feet and rises, torso straightens, hands release, settles into the neutral stand")
def _sit_bench_exit():
    n = 54
    b = BB
    s1 = neutral()
    keys = [
        (6, {"tor": (18.0, 0.0, 0.0), "head": (-8.0, 0.0, 0.0), "pel": V(0, BY, b["pel"].z - 0.005)}, "in2"),
        (14, {"tor": (30.0, 0.0, 0.0), "pel": V(0, BY * 0.6, -0.26), "head": (-14.0, 0.0, 0.0),
              "hand_l": V(0.19, BY - 0.20, 0.72), "hand_r": V(-0.19, BY - 0.20, 0.72), "elb_l": None, "elb_r": None}, "out2"),
        (24, {"pel": V(0, BY * 0.18, -0.10), "tor": (22.0, 0.0, 0.0), "head": (-6.0, 0.0, 0.0),
              "hand_l": V(0.27, 0.0, 0.92), "hand_r": V(-0.27, 0.0, 0.92)}, "smooth"),
        (34, {"pel": V(0, 0.0, 0.004), "tor": (4.0, 0.0, 0.0), "head": (0.0, 0.0, 0.0), "hand_l": s1["hand_l"], "hand_r": s1["hand_r"],
              "ho_l": s1["ho_l"], "ho_r": s1["ho_r"], "curl_l": s1["curl_l"], "curl_r": s1["curl_r"]}, "out2"),
        (46, {"pel": V(0, 0, 0), "tor": s1["tor"]}, "smooth"),
    ]
    ks = [(0, dict(b))] + keys
    ks[-1][1].update({"foot_l": s1["foot_l"], "foot_r": s1["foot_r"], "fyaw_l": s1["fyaw_l"], "fyaw_r": s1["fyaw_r"]})
    return CC.F.build(ks, n, post=None)


# ------------------------------------------------------------------ SIT ON THE GROUND (legs out, leaning back on the hands)
GY = 0.05                                                  # pelvis offset (m, backwards) of the ground-sit family
GROUND = {"type": "ground", "at": [0.0, 0.0, 0.0], "size": [1.2, 1.4, 0.02], "offset": [0.0, 0.0, 0.0], "face": "anchor"}


def _ground_base():
    b = neutral()
    b.update({"pel": V(0, GY, -0.805), "tor": (-20.0, 0.0, 0.0), "hip": (-8.0, 0.0, 0.0), "head": (16.0, 0.0, 0.0)})
    b.update({"foot_l": V(0.17, GY - 0.68, 0.085), "foot_r": V(-0.17, GY - 0.68, 0.085), "fyaw_l": 14.0, "fyaw_r": -14.0,
              "fpit_l": -8.0, "fpit_r": -8.0})
    ho = ((0.0, -0.2, -1.0), (0.0, 0.0, -1.0))
    b.update({"hand_l": V(0.27, GY + 0.31, 0.045), "hand_r": V(-0.27, GY + 0.31, 0.045), "ho_l": PALM_DN, "ho_r": PALM_DN,
              "curl_l": -0.3, "curl_r": -0.3, "elb_l": V(0.42, GY + 0.35, 0.30), "elb_r": V(-0.42, GY + 0.35, 0.30)})
    return b


GB = _ground_base()


@life_clip("Life_Rest_Sit_Ground", loop=True, category="rest/sit", anchor=dict(GROUND), tags=["rest", "sit", "ground"],
           enter="Life_Rest_Sit_Ground_Enter", exit="Life_Rest_Sit_Ground_Exit", events={"look_up": [50]},
           note="sits on the grass with the legs out in front and leans back on the hands: gazes at the sky, rocks a little, one foot "
                "flops and wiggles, weight shifts from hand to hand, leans forward to stretch and comes back")
def _sit_ground():
    b = GB
    keys = [
        (26, {"head": (-8.0, 6.0, 0.0), "tor": (-22.0, 2.0, 0.0)}, "smooth"),                      # look up at the sky
        (52, {"head": (-14.0, -8.0, 0.0), "tor": (-23.0, -2.0, 1.0)}, "smooth"),
        (74, {"head": (12.0, -20.0, 0.0), "tor": (-20.0, -3.0, 0.0), "fpit_r": -30.0, "fyaw_r": -26.0}, "smooth"),   # right foot flops out
        (86, {"fpit_r": -14.0, "fyaw_r": -20.0}, "smooth"), (94, {"fpit_r": -32.0}, "smooth"), (102, {"fpit_r": -12.0}, "smooth"),
        (118, {"tor": (-19.0, 0.0, -3.0), "head": (14.0, 8.0, 0.0), "hand_r": V(-0.25, GY + 0.25, 0.045),
               "fpit_r": b["fpit_r"], "fyaw_r": b["fyaw_r"]}, "smooth"),                             # weight onto the left hand, rocks
        (140, {"tor": (2.0, 0.0, 0.0), "hip": (0.0, 0.0, 0.0), "head": (20.0, 0.0, 0.0), "hand_l": V(0.20, -0.16, 0.22),
               "hand_r": V(-0.20, -0.16, 0.22), "elb_l": V(0.36, 0.05, 0.40), "elb_r": V(-0.36, 0.05, 0.40)}, "smooth"),     # leans forward, hands on the thighs
        (166, {"tor": b["tor"], "hip": b["hip"], "head": b["head"], "hand_l": b["hand_l"], "hand_r": b["hand_r"],
               "elb_l": b["elb_l"], "elb_r": b["elb_r"]}, "smooth"),
    ]
    return looped(b, 180, keys, post=idle_layer(1, 0.4, pel=0.002, tor=0.6))


@life_clip("Life_Rest_Sit_Ground_Enter", loop=False, category="rest/sit", anchor=dict(GROUND), tags=["rest", "sit", "ground", "enter"],
           note="lowers to the ground: bends, squats with the hands on the thighs, drops the hips, reaches the hands back and slides the legs out in front")
def _sit_ground_enter():
    n = 84
    b = GB
    s0 = neutral()
    keys = [
        (10, {"pel": V(0, 0.03, -0.14), "tor": (12.0, 0.0, 0.0), "head": (10.0, 0.0, 0.0), "hand_l": V(0.24, -0.06, 0.76),
              "hand_r": V(-0.24, -0.06, 0.76)}, "in2"),
        (22, {"pel": V(0, 0.08, -0.50), "tor": (24.0, 0.0, 0.0), "head": (8.0, 0.0, 0.0), "foot_l": V(0.14, 0.02, 0.104),
              "foot_r": V(-0.14, 0.05, 0.104), "hand_l": V(0.22, -0.10, 0.50), "hand_r": V(-0.22, -0.10, 0.50),
              "elb_l": V(0.36, 0.10, 0.60), "elb_r": V(-0.36, 0.10, 0.60)}, "smooth"),                               # deep squat
        (34, {"pel": V(0, 0.16, -0.72), "tor": (0.0, 0.0, 0.0), "head": (12.0, 0.0, 0.0), "hand_l": V(0.26, 0.12, 0.30),
              "hand_r": V(-0.26, 0.12, 0.30), "elb_l": V(0.40, 0.26, 0.40), "elb_r": V(-0.40, 0.26, 0.40)}, "smooth"),     # hips drop, hands go back
        (46, {"pel": V(0, GY + 0.06, -0.80), "tor": (-20.0, 0.0, 0.0), "hip": (-8.0, 0.0, 0.0), "head": (14.0, 0.0, 0.0),
              "hand_l": V(0.27, GY + 0.31, 0.045), "hand_r": V(-0.27, GY + 0.31, 0.045), "ho_l": PALM_DN, "ho_r": PALM_DN,
              "curl_l": -0.3, "curl_r": -0.3, "elb_l": b["elb_l"], "elb_r": b["elb_r"]}, "smooth"),                    # sit, hands down behind
        (60, {"foot_l": V(0.16, -0.32, 0.085), "foot_r": V(-0.16, -0.32, 0.085), "fpit_l": -6.0, "fpit_r": -6.0,
              "tor": (-18.0, 0.0, 0.0)}, "smooth"),                                                                     # legs slide out
        (72, {"pel": b["pel"], "tor": b["tor"], "hip": b["hip"], "head": b["head"], "foot_l": b["foot_l"], "foot_r": b["foot_r"],
              "fyaw_l": b["fyaw_l"], "fyaw_r": b["fyaw_r"], "fpit_l": b["fpit_l"], "fpit_r": b["fpit_r"]}, "out2"),
    ]
    return CC.F.build([(0, s0)] + keys, n)


@life_clip("Life_Rest_Sit_Ground_Exit", loop=False, category="rest/sit", anchor=dict(GROUND), tags=["rest", "sit", "ground", "exit"],
           note="gets up from the ground: pulls the legs in, hands to the thighs, rocks forward onto the feet and rises")
def _sit_ground_exit():
    n = 78
    b = GB
    s1 = neutral()
    keys = [
        (10, {"foot_l": V(0.16, -0.30, 0.085), "foot_r": V(-0.16, -0.30, 0.085), "head": (10.0, 0.0, 0.0)}, "smooth"),
        (22, {"foot_l": V(0.15, 0.10, 0.104), "foot_r": V(-0.15, 0.12, 0.104), "fyaw_l": 6.0, "fyaw_r": -6.0, "fpit_l": 0.0, "fpit_r": 0.0,
              "pel": V(0, 0.16, -0.76), "tor": (2.0, 0.0, 0.0), "hip": (0.0, 0.0, 0.0), "hand_l": V(0.26, 0.10, 0.30),
              "hand_r": V(-0.26, 0.10, 0.30), "elb_l": V(0.40, 0.24, 0.40), "elb_r": V(-0.40, 0.24, 0.40)}, "smooth"),
        (34, {"pel": V(0, 0.10, -0.52), "tor": (26.0, 0.0, 0.0), "head": (4.0, 0.0, 0.0), "hand_l": V(0.22, -0.10, 0.50),
              "hand_r": V(-0.22, -0.10, 0.50), "elb_l": V(0.36, 0.10, 0.60), "elb_r": V(-0.36, 0.10, 0.60)}, "out2"),
        (46, {"pel": V(0, 0.03, -0.16), "tor": (14.0, 0.0, 0.0), "hand_l": V(0.24, -0.06, 0.76), "hand_r": V(-0.24, -0.06, 0.76),
              "head": (2.0, 0.0, 0.0), "foot_l": s1["foot_l"], "foot_r": s1["foot_r"], "fyaw_l": s1["fyaw_l"], "fyaw_r": s1["fyaw_r"]}, "out2"),
        (58, {"pel": V(0, 0, 0), "tor": s1["tor"], "hand_l": s1["hand_l"], "hand_r": s1["hand_r"], "ho_l": s1["ho_l"], "ho_r": s1["ho_r"],
              "curl_l": s1["curl_l"], "curl_r": s1["curl_r"], "head": (0.0, 0.0, 0.0), "elb_l": None, "elb_r": None}, "smooth"),
    ]
    return CC.F.build([(0, dict(b))] + keys, n)


# ------------------------------------------------------------------ SEATED AT A TABLE (chair 0.46, table 0.75)
CHAIR = {"type": "table_chair", "at": [0.0, 0.62, 0.75], "size": [1.4, 0.72, 0.75], "offset": [0.0, 0.0, 0.0], "face": "anchor",
         "extra": [{"at": [0.0, 0.0, 0.46], "size": [0.42, 0.42, 0.46]}]}


def _chair_base():
    b = neutral()
    b.update(seat_pose(0.46, 0.0, 26.0))
    b.update({"pel": V(0, -0.03, 0.46 + 0.10 - 0.917), "hip": (0.0, 0.0, 0.0), "head": (-10.0, 0.0, 0.0)})
    b.update({"hand_l": wrist_at("l", V(0.24, -0.34, 0.80), PALM_DN), "ho_l": PALM_DN, "curl_l": 0.1,
              "hand_r": wrist_at("r", V(-0.24, -0.34, 0.80), PALM_DN), "ho_r": PALM_DN, "curl_r": 0.1,
              "elb_l": V(0.32, -0.02, 0.80), "elb_r": V(-0.32, -0.02, 0.80)})
    return b


CB = _chair_base()


@life_clip("Life_Rest_Sit_Chair", loop=True, category="rest/sit", anchor=dict(CHAIR), tags=["rest", "sit", "table", "chair"],
           events={"chin_rest": [70], "glance": [30, 128]},
           note="idle at a table (top 0.75 m), leaning on both forearms; rests the chin in the right hand for a while, glances around, "
                "taps the fingers, sits back and stretches the neck")
def _sit_chair():
    b = CB
    chin = {"hand_r": V(-0.09, -0.30, 1.03), "elb_r": V(-0.26, -0.30, 0.80), "ho_r": ((0.3, -0.5, 0.8), (0.9, -0.1, -0.35)),
            "curl_r": 0.7}
    keys = [
        (24, {"head": (-8.0, 22.0, 0.0), "tor": (25.0, 4.0, 0.0)}, "smooth"),
        (44, {"head": (-8.0, 26.0, 0.0)}, "smooth"),
        (60, dict(chin, **{"head": (4.0, -6.0, 6.0), "tor": (30.0, -3.0, 0.0)}), "smooth"),                      # chin into the hand
        (100, {"head": (6.0, -14.0, 8.0)}, "smooth"),
        (112, {"head": (4.0, -6.0, 6.0)}, "smooth"),
        (124, {"hand_r": b["hand_r"], "elb_r": b["elb_r"], "ho_r": b["ho_r"], "curl_r": 0.1, "head": (-8.0, 10.0, 0.0), "tor": b["tor"]}, "smooth"),
        (140, {"tor": (14.0, 0.0, 0.0), "head": (-18.0, 0.0, 0.0), "hand_l": wrist_at("l", V(0.26, -0.30, 0.80), PALM_DN)}, "smooth"),   # sit back, stretch neck
        (152, {"head": (-4.0, -16.0, 8.0), "tor": (16.0, -2.0, 0.0)}, "smooth"),
        (164, {"tor": (24.0, 0.0, 0.0), "head": b["head"]}, "smooth"),
        (170, {"curl_l": 0.7}, "in2"), (174, {"curl_l": 0.1}, "out2"), (178, {"curl_l": 0.7}, "in2"), (182, {"curl_l": 0.1}, "out2"),
    ]
    return looped(b, 192, keys, post=idle_layer(1, 0.35, pel=0.002, tor=0.5))


# ------------------------------------------------------------------ DOZING ON THE BENCH
@life_clip("Life_Rest_Doze_Bench", loop=True, category="rest/sit", anchor=dict(BENCH), tags=["rest", "sit", "bench", "doze"],
           events={"jerk": [118]},
           note="dozing on the bench with folded arms and the legs stretched out: the head sinks slowly with the chest, then snaps up "
                "with a startled breath, blinks around, and starts to sink again")
def _doze_bench():
    b = dict(BB)
    b.update({"hand_l": V(-0.13, BY - 0.20, 1.00 - 0.0), "hand_r": V(0.13, BY - 0.20, 1.02 - 0.0)})
    b["hand_l"] = V(-0.14, BY - 0.24, 0.96)
    b["hand_r"] = V(0.14, BY - 0.26, 0.98)
    b.update({"ho_l": ((-0.9, -0.3, 0.1), (0.1, 0.3, 0.9)), "ho_r": ((0.9, -0.3, 0.1), (-0.1, 0.3, 0.9)), "curl_l": 0.7, "curl_r": 0.7,
              "elb_l": V(0.34, BY - 0.02, 0.88), "elb_r": V(-0.34, BY - 0.02, 0.88), "tor": (4.0, 0.0, 0.0), "head": (-4.0, 0.0, 0.0),
              "foot_l": V(0.15, BY - 0.62, 0.104), "foot_r": V(-0.15, BY - 0.62, 0.104), "fpit_l": -10.0, "fpit_r": -10.0,
              "fyaw_l": 10.0, "fyaw_r": -10.0})
    keys = [
        (30, {"head": (8.0, 2.0, 2.0), "tor": (7.0, 0.0, 0.0)}, "smooth"),
        (60, {"head": (22.0, -3.0, -4.0), "tor": (10.0, 0.0, 0.0)}, "smooth"),
        (92, {"head": (36.0, -5.0, -7.0), "tor": (14.0, 0.0, -1.0), "pel": V(0, BY, b["pel"].z - 0.006)}, "in2"),         # deep nod
        (108, {"head": (39.0, -6.0, -8.0), "tor": (16.0, 0.0, -1.0)}, "smooth"),
        (114, {"head": (40.0, -6.0, -8.0), "tor": (16.0, 0.0, -1.0)}, "lin"),
        (119, {"head": (-8.0, 6.0, 2.0), "tor": (-2.0, 0.0, 0.0), "shrug_l": 7.0, "shrug_r": 7.0, "pel": b["pel"]}, "out"),  # jerk awake
        (126, {"head": (-4.0, 22.0, 0.0), "tor": (2.0, 5.0, 0.0), "shrug_l": 3.0, "shrug_r": 3.0}, "smooth"),
        (140, {"head": (-2.0, -20.0, 0.0), "tor": (2.0, -5.0, 0.0), "shrug_l": 0.0, "shrug_r": 0.0}, "smooth"),
        (152, {"head": (2.0, -2.0, 0.0), "tor": (3.0, 0.0, 0.0)}, "smooth"),
        (166, {"head": (4.0, 0.0, 1.0), "tor": (5.0, 0.0, 0.0)}, "smooth"),
    ]
    return looped(b, 180, keys, post=idle_layer(1, 0.15, pel=0.004, tor=0.9))


# ------------------------------------------------------------------ PRAYER
CLASP_L = ((-0.15, -0.55, 0.82), (-0.98, 0.1, 0.1))
CLASP_R = ((0.15, -0.55, 0.82), (0.98, 0.1, 0.1))


def _clasp(dz=0.0, dy=0.0):
    return {"hand_l": V(0.072, -0.20 + dy, 1.13 + dz), "hand_r": V(-0.072, -0.20 + dy, 1.13 + dz), "ho_l": CLASP_L, "ho_r": CLASP_R,
            "curl_l": 0.65, "curl_r": 0.65, "elb_l": V(0.30, 0.04, 1.02 + dz), "elb_r": V(-0.30, 0.04, 1.02 + dz)}


_PS = neutral()
_PS.update(stance(0.10, 0.0, -0.10, 0.02, 4.0, -4.0))
_PS.update(_clasp())
_PS.update({"tor": (5.0, 0.0, 0.0), "head": (22.0, 0.0, 0.0), "pel": V(0, -0.005, 0.0)})


@life_clip("Life_Pray_Stand", loop=True, category="ritual/pray", tags=["pray", "stand", "chapel"],
           note="standing prayer: feet together, hands clasped at the chest, head bowed; the bow deepens slowly on the breath out and "
                "lifts a little on the breath in, a barely visible sway")
def _pray_stand():
    b = _PS
    keys = [
        (50, {"head": (30.0, 0.0, 0.0), "tor": (8.0, 0.0, 0.0)}, "smooth"),
        (92, {"head": (32.0, 2.0, 0.0), "tor": (9.0, 0.0, 0.0), "pel": V(0.004, -0.005, -0.002)}, "smooth"),
        (128, {"head": (18.0, -2.0, 0.0), "tor": (3.0, 0.0, 0.0), "pel": V(-0.003, -0.005, 0.0)}, "smooth"),
        (150, {"head": (22.0, 0.0, 0.0), "tor": (5.0, 0.0, 0.0), "pel": V(0, -0.005, 0)}, "smooth"),
    ]
    return looped(b, 180, keys, post=idle_layer(1, 0.2, pel=0.003, tor=0.6, sway=0.003))


KNEEL_Y = 0.10                                             # pelvis offset (m, backwards) when kneeling on both knees


def _kneel_base():
    b = neutral()
    b.update({"pel": V(0, KNEEL_Y, -0.475), "hip": (0.0, 0.0, 0.0), "tor": (0.0, 0.0, 0.0), "head": (20.0, 0.0, 0.0)})
    b.update({"foot_l": V(0.11, 0.05 + KNEEL_Y + 0.24, 0.165), "foot_r": V(-0.11, 0.05 + KNEEL_Y + 0.24, 0.165), "fyaw_l": 0.0, "fyaw_r": 0.0,
              "fpit_l": -55.0, "fpit_r": -55.0})
    b.update(_clasp(-0.465, KNEEL_Y - 0.03))
    return b


KB = _kneel_base()


@life_clip("Life_Pray_Kneel", loop=True, category="ritual/pray", tags=["pray", "kneel", "chapel"],
           enter="Life_Pray_Kneel_Enter", exit="Life_Pray_Kneel_Exit",
           note="kneeling prayer on both knees (toes tucked): hands clasped at the chest, head bowed, very slow breathing; the head sinks "
                "on the breath out, the shoulders settle, a tiny sway")
def _pray_kneel():
    b = KB
    keys = [
        (56, {"head": (30.0, 0.0, 0.0), "tor": (3.0, 0.0, 0.0)}, "smooth"),
        (100, {"head": (34.0, 2.0, 0.0), "tor": (5.0, 0.0, 0.0), "pel": V(0.004, KNEEL_Y, b["pel"].z - 0.003)}, "smooth"),
        (140, {"head": (20.0, -2.0, 0.0), "tor": (1.0, 0.0, 0.0), "pel": V(-0.003, KNEEL_Y, b["pel"].z)}, "smooth"),
        (170, {"head": b["head"], "tor": b["tor"], "pel": b["pel"]}, "smooth"),
    ]
    return looped(b, 216, keys, post=idle_layer(1, 0.2, pel=0.003, tor=0.7, sway=0.003))


@life_clip("Life_Pray_Kneel_Enter", loop=False, category="ritual/pray", tags=["pray", "kneel", "enter"],
           note="stands, brings the hands together, steps the right foot back, lowers onto the right knee and then the left, "
                "settles upright with the head bowed")
def _pray_kneel_enter():
    n = 78
    b = KB
    s0 = neutral()
    keys = [
        (10, dict(_clasp(), **{"head": (10.0, 0.0, 0.0), "tor": (3.0, 0.0, 0.0)}), "smooth"),
        (20, dict(_clasp(-0.03, 0.0), **{"head": (14.0, 0.0, 0.0), "tor": (5.0, 0.0, 0.0), "pel": V(0.03, 0.06, -0.05),
                                         "foot_r": V(-0.12, 0.20, 0.104), "fyaw_r": -6.0}), "smooth"),                # right foot steps back
        (34, dict(_clasp(-0.30, 0.02), **{"head": (16.0, 0.0, 0.0), "tor": (6.0, 0.0, 0.0), "pel": V(0.03, 0.11, -0.32),
                                          "foot_r": V(-0.12, 0.36, 0.165), "fpit_r": -55.0}), "in2"),                  # right knee down
        (48, dict(_clasp(-0.42, 0.06), **{"head": (18.0, 0.0, 0.0), "pel": V(0.02, 0.10, -0.43), "hip": (2.0, 0.0, 0.0),
                                          "foot_l": V(0.11, 0.30, 0.165), "fpit_l": -50.0}), "smooth"),                # left foot slides back
        (60, {"pel": b["pel"], "hip": b["hip"], "tor": b["tor"], "head": b["head"], "foot_l": b["foot_l"], "foot_r": b["foot_r"],
              "fyaw_l": 0.0, "fyaw_r": 0.0, "fpit_l": b["fpit_l"], "fpit_r": b["fpit_r"]}, "out2"),
        (78, {"hand_l": b["hand_l"], "hand_r": b["hand_r"], "elb_l": b["elb_l"], "elb_r": b["elb_r"]}, "smooth"),
    ]
    return CC.F.build([(0, s0)] + keys, n)


@life_clip("Life_Pray_Kneel_Exit", loop=False, category="ritual/pray", tags=["pray", "kneel", "exit"],
           note="lifts the head, releases the hands, rocks forward onto the left foot, pushes up and stands")
def _pray_kneel_exit():
    n = 66
    b = KB
    s1 = neutral()
    keys = [
        (8, {"head": (2.0, 0.0, 0.0), "tor": (6.0, 0.0, 0.0)}, "smooth"),
        (20, dict(_clasp(-0.40, 0.04), **{"pel": V(0.03, 0.10, -0.40), "tor": (12.0, 0.0, 0.0), "head": (4.0, 0.0, 0.0),
                                          "foot_l": V(0.12, 0.02, 0.104), "fpit_l": 0.0, "fyaw_l": 6.0}), "out2"),      # left foot forward
        (34, dict(_clasp(-0.10, 0.02), **{"pel": V(0.02, 0.10, -0.12), "tor": (12.0, 0.0, 0.0), "head": (4.0, 0.0, 0.0),
                                          "foot_r": V(-0.12, 0.18, 0.104), "fpit_r": 0.0, "fyaw_r": -6.0}), "out2"),
        (46, {"pel": V(0, 0.03, -0.01), "tor": (4.0, 0.0, 0.0), "foot_r": s1["foot_r"], "fyaw_r": s1["fyaw_r"], "fpit_r": 0.0,
              "foot_l": s1["foot_l"], "fyaw_l": s1["fyaw_l"], "hand_l": s1["hand_l"], "hand_r": s1["hand_r"], "ho_l": s1["ho_l"],
              "ho_r": s1["ho_r"], "curl_l": s1["curl_l"], "curl_r": s1["curl_r"], "elb_l": None, "elb_r": None, "head": (0.0, 0.0, 0.0)}, "smooth"),
        (58, {"pel": V(0, 0, 0), "tor": s1["tor"]}, "smooth"),
    ]
    return CC.F.build([(0, dict(b))] + keys, n)


# ------------------------------------------------------------------ SLEEP ON THE GROUND (lying on the left side, curled up)
SLEEP = {"type": "ground", "at": [0.0, 0.0, 0.0], "size": [1.6, 1.0, 0.02], "offset": [0.0, 0.0, 0.0], "face": "anchor",
         "note": "lies along the character's X axis: head toward +X (the character's left), feet toward -X, face toward -Y"}


def _sleep_base():
    b = neutral()
    px = -0.10
    b.update({"pel": V(px, 0.0, -0.765), "hip": (10.0, -6.0, 76.0), "tor": (20.0, 0.0, 4.0), "head": (10.0, 0.0, -6.0)})
    b.update({"foot_l": V(px - 0.66, 0.20, 0.06), "foot_r": V(px - 0.62, 0.15, 0.17), "fyaw_l": 0.0, "fyaw_r": 0.0,
              "fpit_l": 0.0, "fpit_r": 0.0})
    b.update({"hand_l": V(px + 0.66, -0.25, 0.07), "ho_l": ((-0.9, -0.4, 0.0), (0.0, 0.0, 1.0)), "curl_l": 0.4, "elb_l": V(px + 0.40, -0.05, 0.05),
              "hand_r": V(px + 0.30, -0.36, 0.20), "ho_r": ((0.4, -0.9, 0.0), (0.0, 0.3, -0.95)), "curl_r": 0.4, "elb_r": V(px + 0.30, -0.05, 0.42),
              "shrug_l": 0.0, "shrug_r": 0.0})
    return b


SB = _sleep_base()


@life_clip("Life_Rest_Sleep_Ground", loop=True, category="rest/sleep", anchor=dict(SLEEP), tags=["rest", "sleep", "ground"],
           enter="Life_Rest_Sleep_Ground_Enter", exit="Life_Rest_Sleep_Ground_Exit", events={"breath": [0, 90]},
           note="asleep on the left side, curled up, left arm under the head: slow deep breathing (chest and shoulder rise), a small "
                "settling shift and a twitch of the free hand")
def _sleep_ground():
    b = SB
    keys = [
        (60, {"curl_r": 0.55, "hand_r": Vector(b["hand_r"]) + V(0.0, -0.01, 0.0)}, "smooth"),
        (78, {"curl_r": 0.25}, "in2"), (84, {"curl_r": 0.5}, "out2"),
        (110, {"tor": (24.0, 0.0, 4.0), "head": (13.0, 2.0, -6.0), "hip": (12.0, -6.0, 76.0)}, "smooth"),
        (150, {"tor": b["tor"], "head": b["head"], "hip": b["hip"], "curl_r": 0.4}, "smooth"),
    ]

    def post(fr, n, s):
        w = math.sin(2 * math.pi * 2 * fr / n)
        t0 = s["tor"]
        s["tor"] = (t0[0] + 1.6 * w, t0[1], t0[2] + 1.2 * w)
        s["pel"] = Vector(s["pel"]) + V(0, 0, 0.003 * w)
        s["shrug_r"] = 2.5 * w
        h = s["head"]
        s["head"] = (h[0] + 0.6 * w, h[1], h[2])
    return looped(b, 180, keys, post=post)


@life_clip("Life_Rest_Sleep_Ground_Enter", loop=False, category="rest/sleep", anchor=dict(SLEEP), tags=["rest", "sleep", "ground", "enter"],
           note="lies down to sleep: squats, sits down on the hip supporting on the left hand, lowers onto the left elbow, then the "
                "shoulder, tucks the legs up and settles the head onto the arm")
def _sleep_enter():
    n = 108
    b = SB
    s0 = neutral()
    px = -0.10
    keys = [
        (12, {"pel": V(0, 0.05, -0.30), "tor": (20.0, 0.0, 0.0), "head": (8.0, 0.0, 0.0), "hand_l": V(0.24, -0.10, 0.62),
              "hand_r": V(-0.24, -0.10, 0.62), "elb_l": V(0.36, 0.08, 0.70), "elb_r": V(-0.36, 0.08, 0.70)}, "in2"),
        (26, {"pel": V(0.06, 0.12, -0.66), "tor": (12.0, 0.0, 36.0), "hip": (0.0, 0.0, 14.0), "foot_l": V(0.14, 0.03, 0.104),
              "foot_r": V(-0.16, 0.12, 0.10), "hand_l": V(0.44, 0.02, 0.05), "hand_r": V(0.14, -0.14, 0.40),
              "elb_l": V(0.52, 0.10, 0.30), "elb_r": V(-0.10, 0.02, 0.46), "head": (6.0, -6.0, 8.0)}, "smooth"),     # sit-squat, left hand down
        (44, {"pel": V(0.02, 0.10, -0.78), "hip": (0.0, -10.0, 34.0), "tor": (8.0, -6.0, 26.0), "foot_l": V(-0.30, -0.05, 0.05),
              "foot_r": V(-0.36, 0.18, 0.09), "hand_l": V(0.42, -0.02, 0.04), "hand_r": V(0.05, -0.26, 0.30),
              "elb_l": V(0.46, 0.10, 0.20), "elb_r": V(-0.15, 0.0, 0.36), "head": (4.0, -8.0, 10.0)}, "smooth"),                                    # sits on the hip, legs folded aside
        (62, {"pel": V(px + 0.06, 0.06, -0.80), "hip": (6.0, -6.0, 56.0), "tor": (12.0, -3.0, 12.0), "hand_l": V(px + 0.30, -0.20, 0.05),
              "elb_l": V(px + 0.20, -0.02, 0.06), "foot_l": V(px - 0.45, 0.16, 0.06), "foot_r": V(px - 0.45, 0.14, 0.14),
              "hand_r": V(px + 0.22, -0.34, 0.22), "head": (6.0, 0.0, 0.0)}, "smooth"),                              # onto the elbow, rolling
        (80, {"pel": V(px, 0.0, -0.77), "hip": (10.0, -6.0, 72.0), "tor": (18.0, 0.0, 6.0), "head": (10.0, 0.0, -4.0),
              "foot_l": b["foot_l"], "foot_r": b["foot_r"], "hand_l": b["hand_l"], "elb_l": b["elb_l"], "hand_r": b["hand_r"]}, "in2"),   # down
        (92, {"pel": b["pel"], "hip": b["hip"], "tor": b["tor"], "head": b["head"], "ho_l": b["ho_l"], "ho_r": b["ho_r"],
              "curl_l": b["curl_l"], "curl_r": b["curl_r"], "elb_r": b["elb_r"]}, "out2"),
    ]
    return CC.F.build([(0, s0)] + keys, n)


@life_clip("Life_Rest_Sleep_Ground_Exit", loop=False, category="rest/sleep", anchor=dict(SLEEP), tags=["rest", "sleep", "ground", "exit"],
           note="wakes up: a deep breath, the head lifts, pushes up on the left hand into a sitting position, rubs the face, squats and stands")
def _sleep_exit():
    n = 96
    b = SB
    s1 = neutral()
    px = -0.10
    keys = [
        (10, {"head": (14.0, 0.0, -2.0), "tor": (14.0, 0.0, 4.0), "curl_r": 0.8}, "smooth"),
        (26, {"pel": V(px + 0.06, 0.06, -0.80), "hip": (6.0, -6.0, 56.0), "tor": (12.0, -3.0, 12.0), "hand_l": V(px + 0.30, -0.20, 0.05),
              "elb_l": V(px + 0.20, -0.02, 0.06), "foot_l": V(px - 0.45, 0.16, 0.06), "foot_r": V(px - 0.45, 0.14, 0.14),
              "hand_r": V(px + 0.22, -0.34, 0.22), "head": (6.0, 0.0, 0.0)}, "smooth"),
        (44, {"pel": V(0.02, 0.10, -0.78), "hip": (0.0, -10.0, 34.0), "tor": (8.0, -6.0, 26.0), "foot_l": V(-0.30, -0.05, 0.05),
              "foot_r": V(-0.36, 0.18, 0.09), "hand_l": V(0.42, -0.02, 0.04), "hand_r": V(0.05, -0.26, 0.30),
              "elb_l": V(0.46, 0.10, 0.20), "elb_r": V(-0.15, 0.0, 0.36), "head": (4.0, -8.0, 10.0)}, "out2"),
        (60, {"pel": V(0.06, 0.12, -0.66), "tor": (12.0, 0.0, 36.0), "hip": (0.0, 0.0, 14.0), "foot_l": V(0.14, 0.03, 0.104),
              "foot_r": V(-0.16, 0.12, 0.10), "hand_l": V(0.44, 0.02, 0.05), "hand_r": V(0.14, -0.14, 0.40),
              "elb_l": V(0.52, 0.10, 0.30), "elb_r": V(-0.10, 0.02, 0.46), "head": (6.0, -6.0, 8.0)}, "smooth"),
        (74, {"pel": V(0, 0.05, -0.30), "hip": (0.0, 0.0, 0.0), "tor": (20.0, 0.0, 0.0), "head": (8.0, 0.0, 0.0), "hand_l": V(0.24, -0.10, 0.62),
              "hand_r": V(-0.24, -0.10, 0.62), "elb_l": V(0.36, 0.08, 0.70), "elb_r": V(-0.36, 0.08, 0.70), "foot_l": s1["foot_l"],
              "foot_r": s1["foot_r"], "fyaw_l": s1["fyaw_l"], "fyaw_r": s1["fyaw_r"]}, "out2"),
        (88, {"pel": V(0, 0, 0), "tor": s1["tor"], "head": (0.0, 0.0, 0.0), "hand_l": s1["hand_l"], "hand_r": s1["hand_r"], "ho_l": s1["ho_l"],
              "ho_r": s1["ho_r"], "curl_l": s1["curl_l"], "curl_r": s1["curl_r"], "elb_l": None, "elb_r": None}, "smooth"),
    ]
    return CC.F.build([(0, dict(b))] + keys, n)
