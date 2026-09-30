# Shared helpers for the LIFE clip modules (life_clips_*.py), built with author_life.py on top of the
# combat key-pose framework (../combat/author_combat.py + combat_common.py): same axes, same IK bake, same easing.
#
# World axes (Blender armature space): the character faces -Y, +Z is up, +X is the character's LEFT. 30 fps.
# Feet are IK-pinned (ankle targets): a foot never moves unless a key moves it.
#
# PROP GRIP CONTRACT (identical in Godot, scripts/living_world/life_props.gd):
#   hand frame, measured on the REST skeleton:
#     f = fingers   = normalize(middle_01.head - hand.head)
#     t = thumb/grip axis = normalize(index_01.head - pinky_01.head), made orthogonal to f
#     n = palm normal: right hand n = t x f, left hand n = f x t   (points out of the palm)
#   grip point (centre of the closed fist) = wrist + f * GRIP_ALONG + n * GRIP_PALM
#   A prop is modelled with its grip at the origin; its catalogue entry (data/living_world/life_props.json) names the
#   native axis that follows t ("grip_axis", e.g. the handle, pointing to the working end) and the native axis that
#   follows f ("front_axis", the knuckle side: a hammer's striking face, a hoe blade's edge).
#   grip_o(side, tool_dir, knuckle_dir) returns the ho_<side> key value that points the prop's grip axis along tool_dir.
#   wrist_at(side, grip_pos, ho) returns the wrist target that puts the fist centre on grip_pos.
#
# Neutral: NEUTRAL is the relaxed standing pose (close to UAL Idle frame 0) every life clip that is not a loop starts
# and ends in, so any clip blends from/to Idle with a 0.2-0.3 s crossfade and no foot slide.
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V, clip

LIFE = {}          # name -> sidecar entry (see life_clip)
GRIP_ALONG = 0.082  # m along the fingers from the wrist to the fist centre (overwritten from the rig in _measure)
GRIP_PALM = 0.030   # m from the hand axis to the palm surface / handle centre


def _measure():
    """fist-centre offsets from the UAL rest bones (the framework's rest matrices F.L)"""
    global GRIP_ALONG, GRIP_PALM
    F = CC.F
    if F is None:
        return
    L = F.L
    k = (L["middle_01_r"].translation - L["hand_r"].translation).length
    GRIP_ALONG = round(k * 0.68, 4)
    GRIP_PALM = round(k * 0.30, 4)


def life_clip(name, loop=False, category="", layer="full", props=None, enter=None, exit=None, blend_in=0.25,
              blend_out=0.3, events=None, anchor=None, note="", speed_mps=0.0, pair=None, ik_l_on_prop=None,
              mask_from="spine_01", tags=None):
    """Register a clip for baking (combat_common.clip) and describe it for the living-world sidecar (.life.json).

    category   "work/smith", "social/talk", "walk/style", "ambient/fidget", "kid/play" ...
    layer      "full" or "upper" (upper = only spine_01 and above are meant to play, over locomotion)
    props      [{"id": "hammer", "hand": "r"}, ...]   ids from data/living_world/life_props.json
    enter/exit clip names (or None when a crossfade of blend_in / blend_out is enough)
    events     {"contact": [frames], "release": [frames], ...}  30 fps frame numbers inside this clip
    anchor     {"type": "anvil", "offset": [x, y, z] metres in the ANCHOR frame (+z = the anchor's front),
                "face": "anchor"} where the character stands relative to the smart object
    pair       {"partner": "Life_Social_Hug_B", "distance": 0.45}  paired clips: partners face each other at distance
    ik_l_on_prop  metres along the right-hand prop's grip axis where the left hand holds it (two-handed tools)
    speed_mps  in-place walk clips: ground speed the cycle was authored for (play at body_speed / speed_mps)
    """
    LIFE[name] = {"category": category, "loop": loop, "layer": layer, "props": props or [], "enter": enter,
                  "exit": exit, "blend_in": blend_in, "blend_out": blend_out, "events": events or {},
                  "anchor": anchor, "note": note, "speed_mps": speed_mps, "pair": pair,
                  "ik_l_on_prop": ik_l_on_prop, "mask_from": mask_from if layer == "upper" else None,
                  "tags": tags or [], "source": "authored (Blender key poses, tools/anim/life)"}
    return clip(name, loop=loop, events=events or {}, note=note)


# ------------------------------------------------------------------ poses
def neutral():
    """relaxed stand, hands loose at the thighs (UAL Idle-like). A fresh dict every call."""
    return {"pel": V(0, 0, 0), "hip": (0.0, 0.0, 0.0), "tor": (2.0, 0.0, 0.0), "head": (0.0, 0.0, 0.0),
            "hand_l": V(0.27, 0.07, 0.915), "hand_r": V(-0.27, 0.07, 0.915), "elb_l": None, "elb_r": None,
            "ho_l": ((0.05, 0.0, -1.0), (-1.0, 0.0, 0.0)), "ho_r": ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0)),
            "curl_l": 0.25, "curl_r": 0.25,
            "foot_l": V(0.12, 0.0, 0.104), "foot_r": V(-0.12, 0.07, 0.104),
            "fyaw_l": 6.0, "fyaw_r": -6.0, "fpit_l": 0.0, "fpit_r": 0.0,
            "shrug_l": 0.0, "shrug_r": 0.0}


NEUTRAL = neutral()


def _orth(a, b):
    a = Vector(a).normalized()
    b = Vector(b)
    b = b - a * b.dot(a)
    if b.length < 1e-6:
        b = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
        b = b - a * b.dot(a)
    return a, b.normalized()


def grip_o(side, tool_dir, knuckle_dir):
    """ho_<side> value: the hand grips a handle that points along tool_dir (thumb side -> working end),
    knuckles facing knuckle_dir (made orthogonal to tool_dir). Returns (fingers, palm) world vectors."""
    t, f = _orth(tool_dir, knuckle_dir)
    n = t.cross(f) if side == "r" else f.cross(t)
    return (tuple(f), tuple(n))


def grip_frame(side, ho):
    """(f, t, n) for a ho value"""
    f = Vector(ho[0]).normalized()
    n = Vector(ho[1])
    n = (n - f * n.dot(f)).normalized()
    t = n.cross(f) if side == "r" else f.cross(n)
    return f, t, n


def wrist_at(side, grip_pos, ho):
    """wrist (hand_<side> key) that puts the fist centre on grip_pos for hand orientation ho"""
    f, t, n = grip_frame(side, ho)
    return Vector(grip_pos) - f * GRIP_ALONG - n * GRIP_PALM


def grip_of(side, wrist, ho):
    """fist centre for a wrist position and hand orientation"""
    f, t, n = grip_frame(side, ho)
    return Vector(wrist) + f * GRIP_ALONG + n * GRIP_PALM


def two_hand(tool_grip_r, tool_dir, knuckle_r, dist_l, knuckle_l=None):
    """keys for a two-handed tool held in the right hand at tool_grip_r, pointing along tool_dir; the left hand
    grips the same handle dist_l metres further along tool_dir (negative = behind the right hand)."""
    ho_r = grip_o("r", tool_dir, knuckle_r)
    ho_l = grip_o("l", tool_dir, knuckle_l if knuckle_l is not None else knuckle_r)
    g_l = Vector(tool_grip_r) + Vector(tool_dir).normalized() * dist_l
    return {"hand_r": wrist_at("r", tool_grip_r, ho_r), "ho_r": ho_r,
            "hand_l": wrist_at("l", g_l, ho_l), "ho_l": ho_l, "curl_r": 0.95, "curl_l": 0.95}


def st(**kw):
    """neutral() with overrides (handy for key dicts that must be complete)"""
    d = neutral()
    d.update(kw)
    return d


def cycle(fr, n, phase=0.0):
    """0..1 phase of frame fr in an n-frame loop"""
    return ((fr / float(n)) + phase) % 1.0


def sinw(fr, n, k=1, phase=0.0):
    return math.sin(2 * math.pi * (k * fr / float(n) + phase))


def breathe(amp=0.006, tor_amp=0.8, k=1):
    """post() layer: subtle breathing (pelvis bob + chest pitch), loops cleanly over the clip length"""
    def post(fr, n, s):
        w = sinw(fr, n, k)
        s["pel"] = Vector(s["pel"]) + V(0, 0, amp * w)
        s["tor"] = (s["tor"][0] + tor_amp * w, s["tor"][1], s["tor"][2])
    return post


def chain(*posts):
    def post(fr, n, s):
        for p in posts:
            if p:
                p(fr, n, s)
    return post


def walk_cycle(n=40, stride=0.30, lift=0.09, bob=0.025, sway=0.03, arm=0.16, lean=4.0, width=0.10, hip_yaw=6.0,
               tor_yaw=-5.0, heel=12.0, toe=18.0, arm_lift=0.03, base=None):
    """In-place walk loop (the body stays over the root; a planted foot slides back at the ground speed
    speed_mps = 2*stride / (n/30)). Returns (keys-less) poses via a post-only build: every frame is procedural.
    Style knobs: stride (m, half of a step pair), lift (swing foot height), bob, sway (side), arm (swing m),
    lean (fwd pitch deg), heel/toe pitch (deg). base: extra state overrides (e.g. a hunched torso)."""
    F = CC.F
    b = neutral()
    if base:
        b.update(base)

    def post(fr, nn, s):
        p = (fr % n) / float(n)             # 0..1, left heel strike at 0, right heel strike at 0.5
        for side, ph in (("l", 0.0), ("r", 0.5)):
            q = (p + ph) % 1.0              # 0 = heel strike of this foot
            sx = 1 if side == "l" else -1
            if q < 0.6:                     # stance: foot moves back from +stride to -stride (forward is -Y)
                u = q / 0.6
                y = -stride + 2 * stride * u
                z = 0.104
                pit = heel * max(0.0, 1 - u / 0.15) - toe * max(0.0, (u - 0.8) / 0.2)
            else:                           # swing: lift and bring forward
                u = (q - 0.6) / 0.4
                e = 0.5 - 0.5 * math.cos(math.pi * u)
                y = stride - 2 * stride * e
                z = 0.104 + lift * math.sin(math.pi * u)
                pit = -toe * (1 - u) * 0.6 + heel * max(0.0, (u - 0.7) / 0.3)
            s["foot_" + side] = V(sx * width, y, z)
            s["fpit_" + side] = pit
            s["fyaw_" + side] = sx * 4.0
            # arms swing opposite to the legs
            a = math.cos(2 * math.pi * (q))  # +1 when this foot strikes (forward) -> opposite arm forward
            hx = Vector(b["hand_" + side])
            s["hand_" + ("r" if side == "l" else "l")] = Vector(b["hand_" + ("r" if side == "l" else "l")]) + \
                V(0, -arm * a, arm_lift * max(0.0, a))
        s["pel"] = Vector(b["pel"]) + V(sway * math.sin(2 * math.pi * p), 0, -bob * 0.5 + bob * 0.5 * math.cos(4 * math.pi * p))
        s["hip"] = (b["hip"][0], hip_yaw * math.sin(2 * math.pi * p), b["hip"][2] + 3.0 * math.sin(2 * math.pi * p))
        s["tor"] = (b["tor"][0] + lean, tor_yaw * math.sin(2 * math.pi * p), b["tor"][2])
    keys = [(0, b), (n, b)]
    return F.build(keys, n, post=post)


def hold(state, n, post=None):
    """a loop that holds one pose (plus a post layer, e.g. breathe())"""
    return CC.F.build([(0, state), (n, state)], n, post=post)


def to_from(a, b, n, ease="smooth", post=None):
    """transition clip from state a to state b over n frames (enter/exit clips)"""
    return CC.F.build([(0, a), (n, b, ease)], n, post=post)


def speed_of(stride, n):
    """ground speed of walk_cycle(n, stride): a planted foot travels 2*stride during the 60 % stance phase"""
    return round(2 * stride / (0.6 * n / 30.0), 3)


_measure()
