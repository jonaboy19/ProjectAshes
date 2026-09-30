# TOWN-LIFE clips, part 2: tavern (drink / toast / cheer / bar / table), music (lute / flute) and eating.
# Helpers (looped, oneshot, idle_layer, seat_pose ...) come from life_clips_market.py.
#
# MUG GRIP (model data/living_world/life_props.json "mug"): the handle loop's axis is the finger axis, the mug body lies on the
# BACK-of-hand side (-n) of the fist, native +Z (rim) = thumb axis t. With the right hand, fingers pointing to the character's
# left (f = +X), thumb up, the body sits in front of the fist and the palm faces the drinker: the natural hold. Tipping t
# backwards (alpha) about the finger axis brings the rim to the mouth (mug_geo below computes rim / body centre).
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V, stance
from life_common import life_clip, neutral, grip_o, wrist_at, sinw
from life_clips_market import (looped, oneshot, idle_layer, chain2, contra, seat_pose, PALM_DN, PALM_UP, grip_hand)

MOUTH = V(0.0, -0.105, 1.585)


def mug_geo(grip, alpha, fdir=(1.0, -0.25, 0.0)):
    """right hand holding the mug: fist centre `grip`, mug axis tipped back by alpha degrees.
    returns dict(wrist, ho, body, rim)"""
    a = math.radians(alpha)
    t = Vector((0.0, math.sin(a), math.cos(a)))
    ho = grip_o("r", tuple(t), fdir)
    from life_common import grip_frame
    f, _t, n = grip_frame("r", ho)
    n = Vector(ho[1])
    g = Vector(grip)
    # n from grip_o is the palm normal
    body = g - n.normalized() * 0.086 + t * 0.01
    rim = body + t * 0.09
    return {"wrist": wrist_at("r", g, ho), "ho": ho, "body": body, "rim": rim, "t": t}


def mug_key(grip, alpha, fdir=(1.0, -0.25, 0.0), **kw):
    m = mug_geo(grip, alpha, fdir)
    d = {"hand_r": m["wrist"], "ho_r": m["ho"], "curl_r": 0.9}
    d.update(kw)
    return d


def grip_for_rim(rim, alpha, fdir=(1.0, -0.25, 0.0)):
    m = mug_geo(V(0, 0, 0), alpha, fdir)
    return Vector(rim) - m["rim"]


R_MUG_LOW = V(-0.20, -0.22, 1.02)       # mug held low in front of the belly
TAV = neutral()
TAV.update(stance(0.14, 0.0, -0.14, 0.04, 6.0, -6.0))
TAV.update(mug_key(R_MUG_LOW, 0.0, elb_r=V(-0.36, 0.10, 1.08)))
TAV.update({"hand_l": V(0.26, 0.02, 0.98), "elb_l": V(0.40, 0.18, 1.10), "curl_l": 0.4, "tor": (3.0, 0.0, 0.0)})


def _sip_keys(f0, base, alpha_hi=68, hold=14, rim=None):
    """mug from the low hold to the lips, tip, hold (swallow), and back down. returns keys"""
    rim = rim if rim is not None else V(0.0, -0.13, 1.645)
    up_g = grip_for_rim(rim, alpha_hi - 22)
    lip_g = grip_for_rim(rim, alpha_hi)
    k = [
        (f0, mug_key(V(-0.24, -0.20, 1.10), 4, elb_r=V(-0.40, 0.08, 1.16),
                     tor=(5.0, 0, 0), head=(2.0, 0.0, 0)), "smooth"),
        (f0 + 10, mug_key(up_g, alpha_hi - 22, elb_r=V(-0.34, 0.02, 1.36), tor=(2.0, 0, 0), head=(-2.0, 0, 0)), "smooth"),
        (f0 + 16, mug_key(lip_g, alpha_hi, elb_r=V(-0.34, 0.04, 1.36), tor=(-2.0, 0, 0), head=(-8.0, 0, 0)), "out2"),
        (f0 + 16 + hold, mug_key(grip_for_rim(rim, alpha_hi + 6), alpha_hi + 6, elb_r=V(-0.34, 0.06, 1.40), head=(-13.0, 0, 0)), "smooth"),
        (f0 + 22 + hold, mug_key(lip_g, alpha_hi - 6, elb_r=V(-0.34, 0.04, 1.36), head=(-3.0, 0, 0)), "smooth"),
        (f0 + 32 + hold, mug_key(V(-0.24, -0.20, 1.10), 4, elb_r=V(-0.40, 0.08, 1.16), head=(4.0, 0.0, 0), tor=(3.0, 0, 0)), "smooth"),
    ]
    return k


@life_clip("Life_Tavern_Drink", loop=False, category="social/tavern", props=[{"id": "mug", "hand": "r"}],
           tags=["tavern", "drink"], events={"sip": [30], "wipe": [76], "swallow": [40]},
           note="lifts the tankard, tips it to the lips (head goes back, throat swallow), lowers it with an exhale, then wipes "
                "the mouth with the back of the left hand and settles")
def _tav_drink():
    b = TAV
    keys = [
        (6, {"tor": (0.0, 0, 0), "head": (0.0, 0.0, 0), "pel": V(0, 0.004, 0.004)}, "out2"),      # inhale, small anticipation
    ] + _sip_keys(10, b) + [
        (54, {"tor": (1.0, 0, 0), "head": (0.0, 3.0, 0), "pel": V(0, 0, -0.004)}, "smooth"),       # exhale, look around
        (62, {"hand_l": V(0.14, -0.12, 1.30), "elb_l": V(0.40, 0.10, 1.28), "ho_l": ((-0.3, -0.3, 0.9), (0.2, -0.9, 0.2)), "curl_l": 0.9,
              "head": (5.0, -6.0, 0)}, "smooth"),
        (70, {"hand_l": V(0.10, -0.13, 1.60), "elb_l": V(0.36, 0.06, 1.46), "head": (2.0, -6.0, 0)}, "smooth"),
        (76, {"hand_l": V(-0.03, -0.15, 1.61), "head": (2.0, 6.0, 0)}, "in2"),
        (84, {"hand_l": V(0.16, -0.10, 1.20), "elb_l": V(0.40, 0.14, 1.14), "head": (0.0, 0.0, 0)}, "smooth"),
        (96, {"hand_l": b["hand_l"], "elb_l": b["elb_l"], "ho_l": b["ho_l"], "curl_l": b["curl_l"], "tor": b["tor"]}, "smooth"),
    ]
    return oneshot(b, 108, keys, post=idle_layer(1, 0.3, pel=0.002, tor=0.4))


@life_clip("Life_Tavern_Toast", loop=False, category="social/tavern", props=[{"id": "mug", "hand": "r"}],
           tags=["tavern", "toast", "cheers"], events={"raise": [16], "cheers": [26], "clink": [32], "sip": [64]},
           note="anticipation (mug cocked back, chest dips), thrusts the tankard up and out for 'cheers' with a clink push, "
                "left hand open in a gesture, then drains a long sip and lowers it")
def _tav_toast():
    b = TAV
    hi = V(-0.22, -0.34, 1.62)
    rim = V(0.0, -0.13, 1.645)
    keys = [
        (7, mug_key(V(-0.28, -0.05, 1.02), 0, elb_r=V(-0.42, 0.22, 1.02), tor=(6.0, 0, 0), head=(4.0, 0, 0), pel=V(0, 0.01, -0.03),
                    hand_l=V(0.30, -0.02, 1.02)), "in2"),
        (15, mug_key(hi, 0, shrug_r=14.0, shrug_l=8.0, elb_r=V(-0.52, -0.02, 1.36), tor=(-7.0, 2.0, 0), head=(-8.0, 3.0, 0), pel=V(0, -0.01, 0.012),
                     hand_l=V(0.40, -0.26, 1.24), elb_l=V(0.46, 0.08, 1.16), ho_l=((0.2, -0.9, 0.3), (0.1, 0.3, 0.95)), curl_l=-0.4), "out2"),
        (19, mug_key(hi + V(0.02, -0.04, 0.05), 0, shrug_r=14.0, elb_r=V(-0.52, -0.02, 1.38), tor=(-6.0, 2.0, 0)), "smooth"),
        (26, mug_key(hi + V(0.0, -0.02, 0.0), 0, shrug_r=14.0), "smooth"),
        (32, mug_key(hi + V(0.05, -0.12, -0.03), 0, shrug_r=14.0, elb_r=V(-0.52, -0.08, 1.36), tor=(-3.0, 4.0, 0)), "in2"),      # clink push
        (36, mug_key(hi + V(0.0, -0.02, 0.0), 0, shrug_r=14.0, tor=(-6.0, 2.0, 0)), "out2"),
        (46, mug_key(grip_for_rim(rim, 40), 40, shrug_r=2.0, shrug_l=0.0, elb_r=V(-0.34, 0.03, 1.44), tor=(1.0, 0, 0), head=(-2.0, 0, 0),
                     hand_l=V(0.30, -0.06, 1.06), elb_l=V(0.42, 0.14, 1.10), ho_l=b["ho_l"], curl_l=0.5), "smooth"),
        (54, mug_key(grip_for_rim(rim, 72), 72, elb_r=V(-0.34, 0.06, 1.40), head=(-9.0, 0, 0)), "out2"),
        (76, mug_key(grip_for_rim(rim, 82), 82, elb_r=V(-0.34, 0.08, 1.42), head=(-15.0, 0, 0)), "smooth"),
        (86, mug_key(grip_for_rim(rim, 55), 55, elb_r=V(-0.34, 0.04, 1.38), head=(-4.0, 0, 0)), "smooth"),
        (98, mug_key(V(-0.24, -0.20, 1.10), 4, elb_r=V(-0.40, 0.08, 1.16), head=(3.0, 0, 0), tor=(3.0, 0, 0), pel=V(0, 0, 0)), "smooth"),
        (110, {"head": b["head"], "tor": b["tor"], "hand_l": b["hand_l"], "elb_l": b["elb_l"], "curl_l": b["curl_l"]}, "smooth"),
    ]
    return oneshot(b, 122, keys, post=idle_layer(1, 0.25, pel=0.002, tor=0.4))


@life_clip("Life_Tavern_Cheer", loop=True, category="social/tavern", props=[{"id": "mug", "hand": "r"}],
           tags=["tavern", "cheer", "song", "loop"], events={"beat": [0, 15, 30, 45]},
           note="drinking song: tankard raised beside the head and swung side to side, knees bouncing on the beat (4 beats per loop), "
                "left arm swaying, head thrown back and nodding")
def _tav_cheer():
    b = dict(TAV)
    b.update(stance(0.16, 0.0, -0.16, 0.03, 8.0, -8.0))
    b.update({"pel": V(0, 0, -0.03)})
    n = 60

    def post(fr, nn, s):
        ph = 2 * math.pi * fr / n
        beat = math.cos(4 * ph)              # 1 at the beat (deepest crouch)
        sway = math.sin(2 * ph)
        s["pel"] = V(0.02 * sway, 0.0, -0.03 - 0.018 * beat)
        s["tor"] = (-4.0 + 3.0 * beat, 3.0 * sway, -4.0 * sway)
        s["head"] = (-8.0 + 5.0 * beat, 8.0 * sway, 3.0 * sway)
        grip = V(-0.34 + 0.10 * sway, -0.18 + 0.03 * math.sin(4 * ph), 1.64 + 0.05 * (-beat))
        s.update(mug_key(grip, 6.0 * sway + 8.0 * beat, elb_r=V(-0.58, 0.02, 1.42 + 0.03 * sway)))
        s["hand_l"] = V(0.40 + 0.10 * sway, -0.22, 1.50 + 0.06 * (-beat))
        s["elb_l"] = V(0.56, 0.02, 1.28)
        s["curl_l"] = 0.2
        s["shrug_r"] = 12.0
        s["shrug_l"] = 8.0
        s["ho_l"] = ((0.3, -0.7, 0.6), (0.3, 0.3, 0.9))
    return _F_build(b, n, post)


def _F_build(b, n, post):
    return CC.F.build([(0, b), (n, b)], n, post=post)


BAR = {"type": "bar_counter", "at": [0.0, 0.52, 1.05], "size": [2.0, 0.60, 1.05], "offset": [0.0, 0.0, 0.0], "face": "anchor"}
BAR["note"] = "bar_counter model: top 1.05 m; the character stands with the counter edge 0.22 m in front of him and leans over it"

_LB = neutral()
_LB.update({"foot_l": V(0.19, -0.01, 0.104), "foot_r": V(-0.13, 0.12, 0.104), "fyaw_l": 10.0, "fyaw_r": -8.0})
_LB.update({"pel": V(0.03, 0.0, -0.012), "tor": (29.0, -4.0, 6.0), "hip": (7.0, -4.0, -2.0), "head": (-26.0, 10.0, -4.0)})
_LB.update({"hand_l": wrist_at("l", V(0.10, -0.47, 1.10), PALM_DN), "ho_l": PALM_DN, "curl_l": 0.2, "elb_l": V(0.28, -0.28, 0.95)})
_LB.update(mug_key(V(-0.24, -0.46, 1.14), 0, elb_r=V(-0.42, -0.05, 1.16)))


@life_clip("Life_Tavern_Lean_Bar", loop=True, category="social/tavern", props=[{"id": "mug", "hand": "r"}], anchor=dict(BAR),
           tags=["tavern", "bar", "idle"], events={"sip": [86]},
           note="leaning over the bar counter (top 1.05 m, edge 0.22 m in front) on the left elbow, tankard in the right hand on the counter; "
                "weight shifts, he watches the room, straightens up for one sip")
def _tav_bar():
    b = _LB
    rim = V(0.02, -0.30, 1.53)
    sip_t = {"tor": (17.0, -3.0, 4.0), "pel": V(0.03, 0.0, -0.01)}
    keys = [
        (24, {"head": (-22.0, -16.0, 3.0), "tor": (28.0, -8.0, 6.0)}, "smooth"),
        (46, {"head": (-21.0, -20.0, 3.0), "pel": V(0.04, 0.0, -0.012)}, "smooth"),
        (60, {"head": (-26.0, 10.0, -4.0), "pel": V(0.03, 0.0, -0.012), "tor": b["tor"]}, "smooth"),
        (70, mug_key(V(-0.26, -0.40, 1.26), 4, elb_r=V(-0.42, -0.04, 1.24), head=(-16.0, 6.0, 0), **sip_t), "smooth"),
        (80, mug_key(grip_for_rim(rim, 52), 52, elb_r=V(-0.36, -0.02, 1.36), head=(-14.0, 2.0, 0), **sip_t), "smooth"),
        (90, mug_key(grip_for_rim(rim, 70), 70, elb_r=V(-0.36, 0.0, 1.38), head=(-22.0, 1.0, 0), **sip_t), "smooth"),
        (98, mug_key(grip_for_rim(rim, 60), 60, elb_r=V(-0.36, 0.0, 1.38), head=(-16.0, 1.0, 0), **sip_t), "smooth"),
        (108, mug_key(V(-0.26, -0.40, 1.26), 4, elb_r=V(-0.42, -0.04, 1.24), head=(-16.0, 6.0, 0), **sip_t), "smooth"),
        (118, mug_key(V(-0.24, -0.46, 1.14), 0, elb_r=V(-0.42, -0.05, 1.16), head=(-26.0, 10.0, -4.0), tor=b["tor"], pel=b["pel"]), "smooth"),
        (132, {"head": (-20.0, -10.0, 2.0)}, "smooth"),
    ]
    return looped(b, 144, keys, post=idle_layer(1, 0.35, pel=0.0025, tor=0.5))


TABLE_T = {"type": "table", "at": [0.0, 0.62, 0.75], "size": [1.4, 0.80, 0.75], "offset": [0.0, 0.0, 0.0], "face": "anchor",
           "extra": [{"at": [0.0, 0.0, 0.46], "size": [0.42, 0.42, 0.46]}]}
_SD = neutral()
_SD.update(seat_pose(0.46, 0.0, 12.0))
_SD.update(mug_key(V(-0.24, -0.40, 0.83), 0, elb_r=V(-0.40, 0.10, 0.88)))
_SD.update({"hand_l": wrist_at("l", V(0.20, -0.30, 0.80), PALM_DN), "ho_l": PALM_DN, "curl_l": -0.2, "elb_l": V(0.36, 0.12, 0.86),
            "head": (8.0, 0.0, 0.0), "tor": (12.0, 0.0, 0.0), "hip": (0, 0, 0)})


@life_clip("Life_Tavern_Sit_Drink", loop=True, category="social/tavern", props=[{"id": "mug", "hand": "r"}], anchor=dict(TABLE_T),
           tags=["tavern", "sit", "drink", "laugh"], events={"sip": [58], "set_down": [84], "laugh": [104]},
           note="seated at a tavern table (0.75 m), right hand around the tankard on the table; a sip, the mug set down with a thunk, "
                "then a laugh (head back, shoulders bounce, left hand slaps the table)")
def _tav_sit_drink():
    b = _SD
    rim = V(0.0, -0.13, 1.30)
    dn = mug_key(V(-0.24, -0.40, 0.83), 0, elb_r=V(-0.40, 0.10, 0.88))
    up = mug_key(V(-0.24, -0.34, 0.98), 4, elb_r=V(-0.40, 0.08, 1.00), tor=(8.0, 0, 0), head=(4.0, 0.0, 0))
    lip = mug_key(V(-0.02, -0.30, 1.33), 62, elb_r=V(-0.36, 0.04, 1.14), tor=(4.0, 0, 0), head=(-10.0, 0, 0))
    lip2 = mug_key(V(-0.02, -0.30, 1.33), 74, elb_r=V(-0.36, 0.04, 1.14), tor=(2.0, 0, 0), head=(-14.0, 0, 0))
    keys = [
        (22, {"head": (10.0, 14.0, 2.0), "tor": (11.0, 5.0, 0)}, "smooth"),
        (40, {"head": (8.0, -8.0, 0.0), "tor": (13.0, -2.0, 0)}, "smooth"),
        (48, up, "smooth"),
        (58, lip, "smooth"),
        (64, lip2, "smooth"),
        (72, lip, "smooth"),
        (82, dict(up, tor=(10.0, 0, 0)), "smooth"),
        (88, dict(dn, tor=(13.0, 0, 0), head=(9.0, 0, 0)), "in2"),           # set down: the thunk
        (94, {"pel": V(0, 0, b["pel"].z + 0.004)}, "out2"),
        (100, {"head": (2.0, 8.0, 0), "tor": (8.0, 0, 0)}, "smooth"),
        (108, {"head": (-16.0, 6.0, 4.0), "tor": (4.0, 3.0, 0), "hand_l": wrist_at("l", V(0.22, -0.30, 0.90), PALM_DN)}, "out2"),
        (112, {"hand_l": wrist_at("l", V(0.22, -0.30, 0.805), PALM_DN), "tor": (7.0, 3.0, 0)}, "in2"),          # slap
        (118, {"hand_l": wrist_at("l", V(0.22, -0.30, 0.86), PALM_DN), "head": (-12.0, -6.0, 4.0)}, "out2"),
        (122, {"hand_l": wrist_at("l", V(0.22, -0.30, 0.805), PALM_DN)}, "in2"),
        (134, {"head": (0.0, -6.0, 0), "tor": (11.0, 0, 0), "hand_l": b["hand_l"]}, "smooth"),
        (150, {"head": b["head"], "tor": b["tor"]}, "smooth"),
    ]

    def laugh(fr, n, s):
        w = max(0.0, min(1.0, min((fr - 102) / 6.0, (130 - fr) / 10.0)))
        if w > 0:
            k = math.sin(2 * math.pi * fr / 6.0)
            t = s["tor"]
            s["tor"] = (t[0] + 2.2 * w * k, t[1], t[2])
            s["pel"] = Vector(s["pel"]) + V(0, 0, 0.004 * w * k)
            s["shrug_l"] = 8.0 * w * (0.5 + 0.5 * k)
            s["shrug_r"] = 8.0 * w * (0.5 + 0.5 * k)
    return looped(b, 180, keys, post=chain2(idle_layer(1, 0.3, pel=0.0025, tor=0.5), laugh))


# ------------------------------------------------------------------ MUSIC
# LUTE (model: neck along native +Z = thumb axis t, soundboard normal = native -Y = finger axis f, body 0.4 x 0.37 x 0.6 m, back bulge
# 0.18 m behind the fist): the left fist holds the neck, the soundboard faces the way the fingers point (forward), the back of the
# lute rests on the belly. The right hand strums across the strings (perpendicular to t) in front of the soundboard.
NECK = Vector((0.75, -0.20, 0.63)).normalized()


def _lute_base(dz=0.0, dy=0.0):
    ho_l = grip_o("l", tuple(NECK), (0.0, -1.0, 0.0))
    grip = V(0.20, -0.30 + dy, 1.25 + dz)
    f, _t, n = None, None, None
    return {"grip": grip, "ho_l": ho_l, "wrist_l": wrist_at("l", grip, ho_l)}


def _lute_frame(dz=0.0, dy=0.0):
    b = _lute_base(dz, dy)
    ho = b["ho_l"]
    f = Vector(ho[0]).normalized()
    t = NECK
    centre = Vector(b["grip"]) - t * 0.30 - f * 0.05           # body centre (behind the fist, down the neck)
    u = t.cross(f).normalized()                                 # across the strings, in the soundboard plane
    return b, f, t, u, centre


STRUM_HO = ((0.55, -0.35, -0.75), (-0.2, 0.8, -0.55))


def _lute_clip(n, dz, dy, seated):
    b, f, t, u, centre = _lute_frame(dz, dy)
    board = centre + f * 0.10                                   # soundboard surface near the bridge
    pr0 = board + f * 0.05 + t * (-0.02)
    base = neutral()
    if seated:
        base.update(seat_pose(0.47, 0.02, 4.0, feet_out=0.17, knee_out=0.03))
    else:
        base.update(stance(0.15, 0.0, -0.15, 0.10, 8.0, -8.0))
        base["tor"] = (2.0, 0.0, 0.0)
    base.update({"hand_l": b["wrist_l"], "ho_l": b["ho_l"], "curl_l": 0.9, "elb_l": V(0.42, 0.10, 1.10 + dz),
                 "hand_r": pr0 + V(0, 0, 0), "ho_r": STRUM_HO, "curl_r": 0.35, "elb_r": V(-0.36, 0.06, 1.12 + dz),
                 "head": (10.0, 8.0, 0.0)})
    pel0 = Vector(base["pel"])
    per = 12
    k = n // per
    kb = n // 24

    def post(fr, nn, s):
        ph = 2 * math.pi * fr / n
        strum = math.cos(2 * math.pi * k * fr / n)
        acc = 1.0 + 0.35 * math.cos(2 * math.pi * fr / (n / 2.0)) + 0.15 * math.cos(2 * math.pi * fr / (n / 4.0) + 1.0)
        sway = math.sin(ph * kb / 2.0 * 1.0)
        beat = math.cos(2 * math.pi * kb * fr / n)
        dx = 0.010 * math.sin(2 * math.pi * (kb // 2) * fr / n)
        s["pel"] = Vector(s["pel"]) + V(dx, 0.0, 0.004 * beat)
        t0 = s["tor"]
        s["tor"] = (t0[0] + 1.6 * beat * 0.5, t0[1] + 2.5 * math.sin(2 * math.pi * (kb // 2) * fr / n), t0[2] - 2.0 * math.sin(2 * math.pi * (kb // 2) * fr / n))
        h = s["head"]
        s["head"] = (h[0] + 2.4 * beat * 0.6, h[1] + 4.0 * math.sin(2 * math.pi * (kb // 2) * fr / n + 0.6), h[2] + 1.5 * math.sin(2 * math.pi * (kb // 2) * fr / n))
        s["hand_l"] = Vector(s["hand_l"]) + V(dx, 0, 0.004 * beat)
        # strumming hand: swings along u across the strings, wrist flick
        p = pr0 + u * (0.075 * acc * strum) + V(dx, 0, 0.004 * beat)
        s["hand_r"] = p
        s["elb_r"] = V(-0.36, 0.06, 1.12 + dz) + u * (0.03 * strum)
        s["curl_r"] = 0.35 + 0.25 * max(0.0, -strum)
        if not seated:               # right foot taps the beat (heel lifts)
            tap = max(0.0, math.cos(2 * math.pi * kb * fr / n)) ** 2
            fr_ = Vector(s["foot_r"])
            s["foot_r"] = V(fr_.x, fr_.y, 0.104 + 0.03 * tap)
            s["fpit_r"] = -22.0 * tap
    return base, post, b, t


@life_clip("Life_Music_Lute", loop=True, category="social/music", props=[{"id": "lute", "hand": "l"}],
           tags=["music", "lute", "stand"], events={"strum": [0, 12, 24, 36, 48, 60, 72, 84], "chord": [22, 46, 70]},
           note="standing lute player: the lute rests on the belly with the neck up to the left (left fist on the neck), the right hand "
                "strums 8 times in the loop with accents, the left hand changes chord three times (slide + finger flick), body sways "
                "and the right foot taps the beat")
def _lute_stand():
    n = 96
    base, post, b, t = _lute_clip(n, 0.06, 0.09, False)
    slide = lambda d, curl: {"hand_l": Vector(base["hand_l"]) + t * d, "curl_l": curl}
    keys = [
        (20, slide(0.0, 0.9), "lin"), (22, slide(-0.07, 0.6), "out2"), (26, slide(-0.07, 0.95), "smooth"),
        (44, slide(-0.07, 0.95), "lin"), (46, slide(0.03, 0.6), "out2"), (50, slide(0.03, 0.95), "smooth"),
        (68, slide(0.03, 0.95), "lin"), (70, slide(0.0, 0.6), "out2"), (74, slide(0.0, 0.95), "smooth"),
    ]
    return looped(base, n, keys, post=post)


@life_clip("Life_Music_Lute_Sit", loop=True, category="social/music", props=[{"id": "lute", "hand": "l"}],
           tags=["music", "lute", "sit", "stool"], events={"strum": [0, 12, 24, 36, 48, 60, 72, 84], "chord": [22, 46, 70]},
           anchor={"type": "stool", "at": [0.0, 0.0, 0.47], "size": [0.4, 0.4, 0.47], "offset": [0.0, 0.05, 0.0], "face": "anchor"},
           note="seated lute player (stool seat 0.47 m): lute on the lap and belly, strumming, chord changes and a swaying torso")
def _lute_sit():
    n = 96
    base, post, b, t = _lute_clip(n, -0.30, 0.12, True)
    slide = lambda d, curl: {"hand_l": Vector(base["hand_l"]) + t * d, "curl_l": curl}
    keys = [
        (20, slide(0.0, 0.9), "lin"), (22, slide(-0.07, 0.6), "out2"), (26, slide(-0.07, 0.95), "smooth"),
        (44, slide(-0.07, 0.95), "lin"), (46, slide(0.03, 0.6), "out2"), (50, slide(0.03, 0.95), "smooth"),
        (68, slide(0.03, 0.95), "lin"), (70, slide(0.0, 0.6), "out2"), (74, slide(0.0, 0.95), "smooth"),
    ]
    return looped(base, n, keys, post=post)


# FLUTE (model: 0.45 m, grip at the centre, along native Z): a transverse flute blown at the right side of the mouth
FL_T = Vector((0.85, -0.20, 0.48)).normalized()           # from the far end toward the embouchure end
FL_END = V(-0.02, -0.13, 1.63)
FL_GRIP = FL_END - FL_T * 0.24
_flh = grip_o("r", tuple(FL_T), (0.0, -0.4, -0.9))
_fl_left = FL_END - FL_T * 0.11
_fll = grip_o("l", tuple(FL_T), (0.0, -0.5, -0.85))


@life_clip("Life_Music_Flute", loop=True, category="social/music", props=[{"id": "flute", "hand": "r"}],
           tags=["music", "flute", "stand"], events={"phrase": [0, 48]},
           note="standing flute player: transverse flute at the right side of the mouth held by both hands (elbows out), fingers "
                "flutter through a tune, head and chest sway gently and the head lifts on the long notes")
def _flute():
    n = 96
    base = neutral()
    base.update(stance(0.14, 0.0, -0.14, 0.06, 6.0, -6.0))
    base.update({"hand_r": wrist_at("r", FL_GRIP, _flh), "ho_r": _flh, "curl_r": 0.8, "elb_r": V(-0.40, 0.12, 1.25),
                 "hand_l": wrist_at("l", _fl_left, _fll), "ho_l": _fll, "curl_l": 0.8, "elb_l": V(0.30, 0.06, 1.30),
                 "tor": (-1.0, 0.0, 0.0), "head": (0.0, -12.0, 0.0), "shrug_r": 2.0, "shrug_l": 4.0})
    keys = [
        (24, {"head": (2.0, -9.0, 3.0), "tor": (-2.0, 2.0, -2.0)}, "smooth"),
        (48, {"head": (-3.0, -14.0, -3.0), "tor": (-3.0, -2.0, 2.0), "hand_r": Vector(base["hand_r"]) + V(0.0, 0.0, 0.02),
              "hand_l": Vector(base["hand_l"]) + V(0.0, 0.0, 0.02)}, "smooth"),
        (72, {"head": (1.0, -8.0, 3.0), "tor": (-1.0, 1.0, -2.0)}, "smooth"),
    ]

    def post(fr, nn, s):
        w = math.sin(2 * math.pi * fr / n)
        s["curl_r"] = 0.78 + 0.16 * math.sin(2 * math.pi * 6 * fr / n) * math.sin(2 * math.pi * 2 * fr / n + 0.5)
        s["curl_l"] = 0.78 + 0.16 * math.sin(2 * math.pi * 5 * fr / n + 1.0) * math.cos(2 * math.pi * 3 * fr / n)
        s["pel"] = Vector(s["pel"]) + V(0.008 * math.sin(2 * math.pi * 2 * fr / n), 0, 0.003 * w)
        t0 = s["tor"]
        s["tor"] = (t0[0] + 0.7 * w, t0[1], t0[2])
    return looped(base, n, keys, post=post)


# ------------------------------------------------------------------ EATING
BREAD_T = Vector((0.0, 0.55, 0.83)).normalized()          # loaf axis when it points at the mouth (end toward the mouth)
_bho = grip_o("r", tuple(BREAD_T), (0.0, -0.9, 0.4))
_bread_low_t = Vector((0.35, 0.10, 0.93)).normalized()
_bho_low = grip_o("r", tuple(_bread_low_t), (0.3, -0.9, 0.0))


@life_clip("Life_Eat_Bread_Stand", loop=True, category="ambient/eat", props=[{"id": "bread", "hand": "r"}],
           tags=["eat", "stand"], events={"bite": [22], "chew": [30, 40, 50, 60, 70], "swallow": [80]},
           note="standing snack: loaf lifted to the mouth, a bite with a small tearing pull, lowered while chewing (jaw = head pitch "
                "pulses), a swallow, a glance around; left hand cups under the chin/loaf")
def _eat_bread():
    n = 132
    base = neutral()
    base.update(stance(0.13, 0.0, -0.13, 0.05, 6.0, -6.0))
    low_g = V(-0.22, -0.22, 1.12)
    mouth_end = V(0.0, -0.135, 1.57)
    bite_g = mouth_end - BREAD_T * 0.128
    base.update({"hand_r": wrist_at("r", low_g, _bho_low), "ho_r": _bho_low, "curl_r": 0.9, "elb_r": V(-0.40, 0.10, 1.08),
                 "hand_l": V(0.24, -0.10, 1.02), "curl_l": 0.4, "elb_l": V(0.40, 0.14, 1.08), "head": (6.0, 0.0, 0.0),
                 "tor": (4.0, 0.0, 0.0)})

    def r(g, ho, **kw):
        d = {"hand_r": wrist_at("r", g, ho), "ho_r": ho}
        d.update(kw)
        return d
    keys = [
        (8, r(low_g + V(0.02, 0.02, 0.06), _bho_low, tor=(2.0, 0, 0), head=(2.0, 0, 0)), "smooth"),
        (20, r(bite_g + V(0.0, 0.03, -0.01), _bho, elb_r=V(-0.36, 0.04, 1.34), head=(-3.0, 0, 0), tor=(2.0, 0, 0)), "smooth"),
        (24, r(bite_g + V(0.0, -0.02, 0.0), _bho, head=(4.0, 0, 0), tor=(6.0, 0, 0)), "in2"),                  # lean in and bite
        (29, r(bite_g + V(0.04, 0.07, -0.03), _bho, head=(-4.0, 0, 0), tor=(3.0, 0, 0)), "out2"),             # tear away
        (40, r(low_g + V(0.02, 0.02, 0.10), _bho_low, elb_r=V(-0.40, 0.10, 1.14), head=(6.0, 3.0, 0), tor=(4.0, 0, 0)), "smooth"),
        (48, {"head": (7.0, -3.0, 0)}, "smooth"),
        (84, {"head": (-3.0, 0.0, 0), "tor": (2.0, 0, 0)}, "smooth"),                                            # swallow
        (92, r(low_g, _bho_low, head=(5.0, 0.0, 0)), "smooth"),
        (108, {"head": (0.0, -14.0, 2.0), "tor": (3.0, -4.0, 0), "hand_l": V(0.26, -0.08, 1.02)}, "smooth"),
        (122, {"head": (6.0, 0.0, 0), "tor": (4.0, 0, 0)}, "smooth"),
    ]

    def post(fr, nn, s):
        # chewing: fast small head-pitch / yaw pulses between the bite and the swallow (period 6 frames)
        w = max(0.0, min(1.0, min((fr - 32) / 5.0, (82 - fr) / 5.0)))
        if w > 0:
            c = math.sin(2 * math.pi * fr / 6.0)
            h = s["head"]
            s["head"] = (h[0] + 2.2 * w * c, h[1] + 1.2 * w * math.sin(2 * math.pi * fr / 12.0), h[2])
        b_ = math.sin(2 * math.pi * fr / n)
        s["pel"] = Vector(s["pel"]) + V(0, 0, 0.003 * b_)
        t0 = s["tor"]
        s["tor"] = (t0[0] + 0.6 * b_, t0[1], t0[2])
    return looped(base, n, keys, post=post)


BOWL_T = Vector((0.7, 0.7, 0.0)).normalized()
_bwl_ho = grip_o("l", tuple(BOWL_T), (0.0, 0.0, 1.0))
BENCH_E = {"type": "bench", "at": [0.0, 0.0, 0.45], "size": [1.3, 0.36, 0.45], "offset": [0.0, 0.05, 0.0], "face": "anchor"}
SPOON_L = 0.26                                            # grip -> bowl of the spoon (model)


def spoon_tip(tip, tdir, kn=(0.6, -0.8, 0.0), **kw):
    """right-hand keys that put the spoon's bowl (0.26 m from the fist along the thumb axis) on `tip`"""
    t = Vector(tdir).normalized()
    ho = grip_o("r", tuple(t), kn)
    d = {"hand_r": wrist_at("r", Vector(tip) - t * SPOON_L, ho), "ho_r": ho}
    d.update(kw)
    return d


@life_clip("Life_Eat_Bowl_Sit", loop=True, category="ambient/eat", props=[{"id": "bowl", "hand": "l"}, {"id": "spoon", "hand": "r"}],
           anchor=dict(BENCH_E), tags=["eat", "sit", "bench"], events={"scoop": [12, 84], "bite": [32, 104], "swallow": [60, 124]},
           note="seated meal: bowl held by the rim in the left hand in front of the belly, the spoon scoops, lifts to the mouth "
                "(head dips to meet it), lowers; two spoonfuls per loop with a chew and a glance up")
def _eat_bowl():
    n = 144
    base = neutral()
    base.update(seat_pose(0.45, 0.0, 10.0))
    bowl_g = V(0.14, -0.20, 0.95)
    bowl_c = Vector(bowl_g) - BOWL_T * 0.13                       # bowl centre
    dip = bowl_c + V(0.0, 0.0, 0.02)
    T_DIP = (0.10, -0.75, -0.65)
    T_MOUTH = (0.0, 0.55, 0.83)
    mouth = V(0.0, -0.24, 1.19)
    base.update({"hand_l": wrist_at("l", bowl_g, _bwl_ho), "ho_l": _bwl_ho, "curl_l": 0.8, "elb_l": V(0.40, 0.10, 0.85),
                 "curl_r": 0.8, "elb_r": V(-0.38, 0.10, 0.88),
                 "head": (22.0, 0.0, 0.0), "tor": (10.0, 0.0, 0.0)})
    base.update(spoon_tip(dip + V(0, 0, 0.09), T_DIP))

    def cycle(f0):
        return [
            (f0, spoon_tip(dip + V(0.0, 0.0, 0.05), T_DIP, head=(26.0, 0.0, 0), tor=(12.0, 0, 0)), "smooth"),
            (f0 + 6, spoon_tip(dip + V(-0.01, 0.0, -0.01), (0.0, -0.3, -0.95)), "smooth"),
            (f0 + 12, spoon_tip(dip + V(-0.03, 0.02, 0.05), (0.0, -0.05, -1.0)), "smooth"),
            (f0 + 22, spoon_tip(mouth, T_MOUTH, head=(24.0, 0.0, 0), tor=(8.0, 0, 0), elb_r=V(-0.36, 0.06, 1.0)), "smooth"),
            (f0 + 26, spoon_tip(mouth + V(0.0, -0.02, 0.0), T_MOUTH, head=(30.0, 0.0, 0), tor=(10.0, 0, 0)), "in2"),
            (f0 + 32, spoon_tip(mouth + V(0.0, 0.03, -0.01), T_MOUTH, head=(18.0, 0.0, 0), tor=(7.0, 0, 0)), "out2"),
            (f0 + 46, spoon_tip(dip + V(0.0, 0.0, 0.10), T_DIP, head=(20.0, 4.0, 0), tor=(9.0, 0, 0), elb_r=base["elb_r"]), "smooth"),
        ]
    keys = cycle(6) + [(60, {"head": (14.0, -12.0, 2.0), "tor": (6.0, -3.0, 0)}, "smooth")] + cycle(78)[1:] + [
        (126, {"head": (12.0, 10.0, 0.0), "tor": (6.0, 2.0, 0)}, "smooth"), (136, {"head": base["head"], "tor": base["tor"]}, "smooth")]

    def post(fr, nn, s):
        w = max(0.0, min(1.0, min((fr - 40) / 4.0, (62 - fr) / 4.0))) + max(0.0, min(1.0, min((fr - 112) / 4.0, (132 - fr) / 4.0)))
        if w > 0:
            c = math.sin(2 * math.pi * fr / 6.0)
            h = s["head"]
            s["head"] = (h[0] + 1.6 * w * c, h[1], h[2])
        b_ = math.sin(2 * math.pi * fr / n)
        s["pel"] = Vector(s["pel"]) + V(0, 0, 0.003 * b_)
        t0 = s["tor"]
        s["tor"] = (t0[0] + 0.6 * b_, t0[1], t0[2])
    return looped(base, n, keys, post=post)
