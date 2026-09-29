# Bow draw/hold/release/aim clips and weapon-specific deaths, authored with author_combat.py.
# World axes: character faces -Y, +Z up, +X = character's LEFT. 30 fps. Feet IK-pinned unless a key moves them.
#
# NOTE: the framework appends "_Loop" to loop clips, so the clip registered as "Bow_Hold" is exported as track "Bow_Hold_Loop".
# BOW (weapon bow: procedural bow in hand_l; arms are authored here, the string/arrow are game-side):
#   Bow_Draw (0.53 s) -> Bow_Hold_Loop (1.2 s loop, first == last == Draw end) -> Bow_Release (0.6 s) -> bow_ready.
#   Bow_Aim_Up / Bow_Aim_Down are 0.1 s single-pose clips of the FULL DRAW aimed +35 / -30 degrees.
#   Codex hookup: play Bow_Hold_Loop and blend it with Bow_Aim_Up / Bow_Aim_Down by camera pitch as a Blend3
#   (pitch < 0 -> Aim_Down weight = pitch/-30, pitch > 0 -> Aim_Up weight = pitch/35), upper-body filter
#   (spine/arms/head), the legs keep the Hold feet.
# DEATHS: terminal poses (lying on the ground), travel in "root". Events: contact 0, knees, down.
import math
from mathutils import Vector
from combat_common import clip, V, stance, rel, TF, shake, blade_o, ready_pose, smooth

N = ready_pose()
FR = __import__("combat_common")


def rotx(v, deg):
    """rotate a vector about the world X axis (deg; negative = the -Y shot direction tilts UP)"""
    a = math.radians(deg)
    v = Vector(v)
    return V(v.x, v.y * math.cos(a) - v.z * math.sin(a), v.y * math.sin(a) + v.z * math.cos(a))


# ================================================================== BOW
def bow_ready():
    """bow low in the left hand (grip down at the thigh, limbs vertical), arrow hand loose near the right hip/quiver"""
    R = dict(N)
    R.update({"pel": V(0, 0, 0), "hip": (0.0, -8.0, 0.0), "tor": (4.0, -10.0, 0.0), "head": (0.0, 10.0, 0.0),
              "hand_l": V(0.27, -0.20, 0.90), "hand_r": V(-0.25, 0.10, 0.93), "elb_l": V(0.45, 0.05, 1.0), "elb_r": V(-0.50, 0.30, 1.05),
              "ho_l": ((0.0, -0.6, 0.8), (-1.0, 0.0, 0.0)), "ho_r": ((0.0, -0.5, -0.85), (1.0, 0.0, 0.0)),
              "curl_l": 0.7, "curl_r": 0.2})
    R.update(stance(0.11, -0.05, -0.11, 0.13, -25.0, -40.0))
    return R


B = bow_ready()

# full-draw geometry (pitch 0): torso yawed -60 (hip -20, tor -40), left shoulder toward the target
DR = {
    "hand_l": V(0.10, -0.62, 1.50), "hand_r": V(-0.10, 0.00, 1.55),
    "elb_l": V(0.42, -0.30, 1.42), "elb_r": V(-0.40, 0.42, 1.62),
    "ho_l": ((0.0, -0.4, 0.9), (-1.0, 0.0, 0.0)), "ho_r": ((0.0, -1.0, 0.2), (1.0, 0.0, 0.0)),
    "curl_l": 0.9, "curl_r": 0.8,
}
DSTANCE = {"foot_l": V(0.05, -0.16, 0.104), "foot_r": V(-0.05, 0.28, 0.104), "fyaw_l": -70.0, "fyaw_r": -85.0}


def full_draw(pitch=0.0):
    """the full-draw pose aimed `pitch` deg up (+) / down (-). The spine bends (roll away from the target when aiming up),
    the arm line rotates about the chest, the head tilts to keep looking along the arrow."""
    d = {"pel": V(0, 0, 0), "hip": (0.0, -20.0, 0.0), "tor": (2.0, -40.0, 0.0), "head": (0.0, 52.0, 0.0)}
    d.update(DSTANCE)
    d.update({k: v for k, v in DR.items()})
    if pitch:
        piv = V(0.0, 0.05, 1.40)
        for k in ("hand_l", "hand_r", "elb_l", "elb_r"):
            d[k] = piv + rotx(Vector(DR[k]) - piv, -pitch)
        for k in ("ho_l", "ho_r"):
            d[k] = (tuple(rotx(DR[k][0], -pitch)), tuple(rotx(DR[k][1], -pitch)))
        roll = -0.5 * pitch if pitch > 0 else -0.55 * pitch     # up: lean away (roll right), down: lean toward the target
        roll = -0.5 * pitch
        d["hip"] = (0.0, -20.0, 0.35 * roll)
        d["tor"] = (2.0, -40.0, roll)
        d["head"] = (-0.35 * pitch, 52.0, 0.0)
        # the chest swings about the pelvis: shift the pelvis under the load (counter-lean) and move the whole arm line with it
        lean = math.radians(0.9 * roll)
        dx = 0.5 * math.sin(lean) * 0.5           # chest displacement along the torso-left direction (0.5, -0.87)
        for k in ("hand_l", "hand_r", "elb_l", "elb_r"):
            d[k] = Vector(d[k]) + V(0.5 * dx, -0.87 * dx, -0.5 * (1 - math.cos(lean)) * 0.5)
    return d


def _bow_arm_kw(**kw):
    return kw


@clip("Bow_Draw", events={"contact": 0, "nock": 7, "anchor_frame": 16}, note="ready -> nock -> full draw side-on (0.53 s); ends at the Hold pose")
def bow_draw():
    F = FR.F
    D = full_draw(0.0)
    keys = [(0, dict(B))]
    # f1-2: hips start the turn, bow arm starts up, arrow hand leaves the hip
    keys.append((2, {"hip": (0.0, -8.0, 0.0), "tor": (3.0, -14.0, 0.0), "head": (0.0, 18.0, 0.0),
                     "hand_l": V(0.24, -0.34, 1.12), "hand_r": V(-0.26, 0.06, 1.02), "elb_l": V(0.45, -0.10, 1.10),
                     "ho_l": ((0.0, -0.4, 0.9), (-1.0, 0.0, 0.0)), "curl_l": 0.9, "_bow": {"hand_l": V(0.0, 0.0, 0.05)}}, "in2"))
    # f4: bow arm high, torso turned, back foot steps around (lifted)
    keys.append((4, {"hip": (0.0, -16.0, 0.0), "tor": (2.0, -30.0, 0.0), "head": (0.0, 35.0, 0.0),
                     "hand_l": V(0.14, -0.46, 1.42), "elb_l": V(0.40, -0.20, 1.34),
                     "hand_r": V(-0.24, -0.02, 1.16), "elb_r": V(-0.50, 0.35, 1.05),
                     "foot_r": V(-0.09, 0.22, 0.17), "fyaw_r": -60.0, "foot_l": V(0.08, -0.10, 0.104), "fyaw_l": -50.0,
                     "_bow": {"hand_r": V(0.0, 0.0, -0.03)}}, "smooth"))
    # f7: NOCK - arrow hand reaches the string beside the bow hand (moving hold), feet set
    keys.append((7, {"hip": (0.0, -20.0, 0.0), "tor": (2.0, -38.0, 0.0), "head": (0.0, 48.0, 0.0),
                     "hand_l": V(0.12, -0.50, 1.47), "elb_l": V(0.40, -0.25, 1.40),
                     "hand_r": V(-0.02, -0.28, 1.45), "elb_r": V(-0.42, 0.20, 1.50),
                     "foot_r": DSTANCE["foot_r"], "fyaw_r": DSTANCE["fyaw_r"], "foot_l": DSTANCE["foot_l"], "fyaw_l": DSTANCE["fyaw_l"],
                     "curl_r": 0.9, "_bow": {"hand_r": V(-0.05, -0.05, 0.06)}}, "smooth"))
    keys.append((8, {"hand_r": V(-0.02, -0.26, 1.46), "curl_r": 1.0}, "lin"))
    # f9-16: draw back along the arrow line to the anchor, bow arm extends, elbow rises behind the line, blades squeeze
    keys.append((12, {"hand_l": V(0.11, -0.58, 1.49), "hand_r": V(-0.07, -0.10, 1.52), "elb_r": V(-0.42, 0.34, 1.60),
                      "tor": (2.0, -40.0, 0.0), "head": (0.0, 52.0, 0.0), "curl_l": 0.9}, "smooth"))
    keys.append((16, {k: D[k] for k in ("hand_l", "hand_r", "elb_l", "elb_r", "ho_l", "ho_r", "curl_l", "curl_r", "hip", "tor", "head")}, "out2"))
    return F.build(keys, 16)


@clip("Bow_Hold", loop=True, events={"anchor_frame": 0}, note="full draw held, breathing + 1-2 mm tremor; first == last == Bow_Draw end", root_motion_m=0.0)
def bow_hold():
    F = FR.F
    D = full_draw(0.0)
    keys = [(0, dict(D))]
    n = 36

    def post(fr, n_, s):
        u = fr / float(n_)
        s2 = lambda k, ph=0.0: math.sin(2 * math.pi * (u * k + ph))
        # sin terms only -> exactly zero at fr 0 and n (loop closes on the Draw end pose)
        s["hand_r"] = Vector(s["hand_r"]) + V(0.0012 * s2(7), 0.0010 * s2(5), 0.0012 * s2(9))
        s["hand_l"] = Vector(s["hand_l"]) + V(0.0010 * s2(6), 0.0006 * s2(4), 0.0015 * s2(8))
        s["elb_r"] = Vector(s["elb_r"]) + V(0.0, 0.0015 * s2(3), 0.0015 * s2(5))
        b = s2(1)                                # breathing: 1 cycle / 1.2 s
        s["tor"] = (s["tor"][0] + 0.5 * b, s["tor"][1], s["tor"][2])
        s["pel"] = Vector(s["pel"]) + V(0, 0, 0.0025 * b)
        s["head"] = (s["head"][0] - 0.3 * b, s["head"][1] + 0.4 * s2(2), s["head"][2])
    return F.build(keys, n, post=post)


@clip("Bow_Loose", events={"contact": 0, "release": 1, "extreme": 3, "recovered": 18},
      note="string released on f1: draw hand flies back past the ear, bow arm kicks forward/down 2-3 deg, follow-through, then back to bow_ready (0.6 s)")
def bow_release():
    F = FR.F
    D = full_draw(0.0)
    keys = [(0, dict(D))]
    # f1: release - hand already leaving, fingers open (curl -1), bow arm starts kicking
    keys.append((1, {"hand_r": V(-0.125, 0.06, 1.55), "curl_r": -1.0, "hand_l": V(0.10, -0.635, 1.485), "elb_r": V(-0.44, 0.50, 1.63),
                     "tor": (2.0, -37.0, 0.0), "hip": (0.0, -19.0, 0.0), "ho_r": ((0.0, -0.8, 0.3), (1.0, 0.0, 0.0)),
                     "_bow": {"hand_r": V(0.0, 0.0, 0.0)}}, "out2"))
    # f3: extreme - hand 13 cm behind the anchor past the ear, bow arm overshoots forward/down
    keys.append((3, {"hand_r": V(-0.18, 0.15, 1.57), "elb_r": V(-0.48, 0.58, 1.60), "hand_l": V(0.10, -0.645, 1.465),
                     "ho_l": ((0.0, -0.4, 0.85), (-1.0, 0.0, 0.0)), "head": (0.0, 52.0, 0.0), "tor": (2.0, -35.0, 0.0),
                     "ho_r": ((0.1, -0.6, 0.4), (1.0, 0.1, 0.0)), "_bow": {"hand_r": V(-0.02, 0.0, 0.03)}}, "out2"))
    # f6: bow arm settles back a touch, hand relaxes (follow-through hold)
    keys.append((7, {"hand_r": V(-0.21, 0.13, 1.50), "hand_l": V(0.10, -0.635, 1.48), "elb_r": V(-0.5, 0.50, 1.50),
                     "curl_r": -0.6, "tor": (2.0, -34.0, 0.0), "hip": (0.0, -18.0, 0.0)}, "smooth"))
    keys.append((10, {"hand_r": V(-0.24, 0.16, 1.40), "hand_l": V(0.11, -0.60, 1.43)}, "smooth"))
    # f10-18: lower the bow, arrow hand back to the hip, feet return, everything ends at bow_ready
    keys.append((14, {"hand_l": V(0.20, -0.36, 1.10), "hand_r": V(-0.27, 0.10, 1.10), "hip": (0.0, -12.0, 0.0), "tor": (3.0, -20.0, 0.0),
                      "head": (0.0, 28.0, 0.0), "foot_r": V(-0.09, 0.22, 0.16), "fyaw_r": -60.0, "curl_r": 0.0, "curl_l": 0.7,
                      "elb_l": V(0.45, -0.10, 1.10), "elb_r": V(-0.5, 0.3, 1.1),
                      "ho_l": ((0.0, -0.5, 0.85), (-1.0, 0.0, 0.0)), "ho_r": ((0.0, -0.5, -0.85), (1.0, 0.0, 0.0))}, "smooth"))
    keys.append((18, dict(B), "smooth"))
    return F.build(keys, 18)


def _aim(pitch):
    F = FR.F
    return F.build([(0, full_draw(pitch))], 3)


clip("Bow_Aim_Up", events={"pitch_deg": 35}, note="full draw aimed +35 deg up (spine bends), 0.1 s pose")(lambda: _aim(35.0))
clip("Bow_Aim_Down", events={"pitch_deg": -30}, note="full draw aimed -30 deg down, 0.1 s pose")(lambda: _aim(-30.0))


# ================================================================== DEATHS
_PATCHED = []


def _patch_knees():
    """author_combat has no knee-hint key: wrap state_to_pose so a state may carry knee_w (0..1) and knee_l / knee_r
    (world hint targets); the hint is blended from the automatic knee hint (no pop). Harmless for clips that do not use it."""
    if _PATCHED:
        return
    g = FR.F.build.__globals__
    orig = g["state_to_pose"]

    def sp(s):
        P = orig(s)
        w = s.get("knee_w", 0.0)
        if w > 0.0:
            for side in ("l", "r"):
                a = g["auto_knee"](P, side)
                P.knee[side] = a.lerp(Vector(s["knee_" + side]), w)
        return P
    g["state_to_pose"] = sp
    _PATCHED.append(1)


def _mk_post(knee=None):
    """root follows the pelvis xy travel (pose stays relative); knee = (f0, f1, target_l, target_r): knee hints fade in f0..f1"""
    def post(fr, n, s):
        _patch_knees()
        s["root"] = V(s["pel"].x, s["pel"].y, 0.0)
        if knee:
            # knee = [(frame, weight, target_l, target_r), ...] piecewise-linear
            ks = knee
            if fr <= ks[0][0]:
                a = b = ks[0]; t = 0.0
            elif fr >= ks[-1][0]:
                a = b = ks[-1]; t = 0.0
            else:
                for i in range(len(ks) - 1):
                    if ks[i][0] <= fr <= ks[i + 1][0]:
                        a, b = ks[i], ks[i + 1]
                        t = smooth((fr - a[0]) / float(b[0] - a[0]))
                        break
            s["knee_w"] = a[1] + (b[1] - a[1]) * t
            s["knee_l"] = Vector(a[2]).lerp(Vector(b[2]), t)
            s["knee_r"] = Vector(a[3]).lerp(Vector(b[3]), t)
    return post


def _travel_root(fr, n, s):
    _mk_post()(fr, n, s)


def _tw(s, key, d):
    s[key] = tuple(a + b for a, b in zip(s[key], d))


@clip("Death_1H_Front", events={"contact": 0, "knees": 14, "down": 25, "bounce": 28},
      note="sword+shield: hit from the front. Recoil, knees buckle, twist, sword hand opens, falls on the back (1.6 s); 0.56 m of pelvis travel backwards; terminal: lying on the back, head +Y",
      root_motion_m=0.56)
def death_1h_front():
    F = FR.F
    keys = [(0, dict(N))]
    keys.append((1, {"tor": (-10.0, 6.0, 2.0), "head": (-9.0, 0.0, 0.0), "pel": V(0, 0.02, -0.004),
                     "hand_l": V(0.36, 0.0, 0.98), "hand_r": V(-0.36, 0.06, 1.02), "curl_r": 0.8,
                     "ho_r": blade_o((-0.1, -0.4, 0.9), (1, 0, 0))}, "out2"))
    keys.append((3, {"tor": (-24.0, 18.0, 6.0), "hip": (-4.0, 6.0, 0.0), "head": (-14.0, 8.0, 3.0), "pel": V(0.0, 0.07, -0.03),
                     "hand_l": V(0.56, 0.22, 1.20), "hand_r": V(-0.52, 0.28, 1.14), "curl_r": 0.3, "curl_l": 0.1,
                     "ho_r": blade_o((-0.6, 0.3, 0.8), (1, 0, 0)), "foot_r": N["foot_r"] + V(-0.02, 0.05, 0.04), "_bow": {"hand_r": V(-0.05, 0, 0.06)}}, "out2"))
    keys.append((7, {"tor": (-16.0, 28.0, 8.0), "hip": (-8.0, 14.0, 0.0), "head": (-6.0, 10.0, 0.0), "pel": V(0.0, 0.16, -0.12),
                     "hand_l": V(0.52, 0.30, 1.0), "hand_r": V(-0.50, 0.32, 0.94), "curl_r": -0.5,
                     "ho_r": blade_o((-0.8, 0.3, -0.2), (0, 0, 1)),
                     "foot_r": N["foot_r"] + V(-0.06, 0.16, 0.0), "foot_l": N["foot_l"] + V(0.0, 0.03, 0.0)}, "smooth"))
    keys.append((11, {"tor": (-8.0, 22.0, 4.0), "hip": (-12.0, 16.0, 0.0), "head": (2.0, 6.0, 0.0), "pel": V(0.0, 0.28, -0.30),
                      "hand_l": V(0.44, 0.42, 0.76), "hand_r": V(-0.46, 0.46, 0.74), "curl_r": -1.0, "curl_l": -0.4,
                      "ho_r": blade_o((-0.9, 0.0, -0.4), (0, 0, 1)), "foot_l": V(0.16, 0.10, 0.104), "foot_r": V(-0.20, 0.24, 0.104)}, "in2"))
    keys.append((14, {"tor": (-4.0, 16.0, 2.0), "hip": (-22.0, 14.0, 0.0), "head": (4.0, 4.0, 0.0), "pel": V(0.0, 0.36, -0.46),
                      "hand_l": V(0.44, 0.50, 0.58), "hand_r": V(-0.46, 0.52, 0.56), "ho_r": blade_o((-0.9, -0.2, -0.3), (0, 0, 1)),
                      "foot_l": V(0.16, 0.16, 0.104), "foot_r": V(-0.20, 0.20, 0.104), "fyaw_l": 20.0, "fyaw_r": -25.0}, "in2"))
    keys.append((18, {"tor": (-14.0, 10.0, 0.0), "hip": (-46.0, 12.0, 0.0), "head": (-10.0, 4.0, 0.0), "pel": V(0.0, 0.46, -0.64),
                      "hand_l": V(0.52, 0.80, 0.30), "hand_r": V(-0.58, 0.82, 0.30), "elb_l": None, "elb_r": None,
                      "ho_r": blade_o((-0.6, -0.8, -0.2), (0, 0, 1))}, "in2"))
    keys.append((22, {"tor": (-6.0, 4.0, 0.0), "hip": (-76.0, 12.0, 4.0), "head": (-22.0, 2.0, 0.0), "pel": V(0.0, 0.54, -0.75),
                      "hand_l": V(0.50, 0.96, 0.18), "hand_r": V(-0.56, 0.98, 0.18), "elb_l": V(0.40, 1.22, 0.08), "elb_r": V(-0.42, 1.22, 0.08),
                      "ho_r": blade_o((-0.4, -0.9, -0.05), (0, 0, 1)), "foot_l": V(0.16, 0.20, 0.10), "foot_r": V(-0.20, 0.10, 0.10),
                      "fpit_l": 30.0, "fpit_r": 20.0}, "in2"))
    keys.append((25, {"tor": (2.0, 0.0, 0.0), "hip": (-92.0, 12.0, 4.0), "head": (-26.0, 0.0, 0.0), "pel": V(0.0, 0.56, -0.785),
                      "hand_l": V(0.46, 0.90, 0.075), "hand_r": V(-0.56, 0.92, 0.075),
                      "elb_l": V(0.42, 1.24, 0.07), "elb_r": V(-0.44, 1.24, 0.07),
                      "ho_r": blade_o((-0.3, -0.95, 0.0), (0, 0, 1)), "foot_l": V(0.16, 0.24, 0.10), "foot_r": V(-0.22, 0.02, 0.10)}, "in2"))
    # bounce: chest rebounds a little, the head lands last, arms flop
    keys.append((27, {"hip": (-86.0, 12.0, 4.0), "head": (-6.0, 0.0, 0.0), "pel": V(0.0, 0.55, -0.775),
                      "hand_l": V(0.48, 0.90, 0.14), "hand_r": V(-0.58, 0.92, 0.14), "ho_r": blade_o((-0.3, -0.95, 0.15), (0, 0, 1))}, "out2"))
    keys.append((30, {"hip": (-91.0, 12.0, 4.0), "head": (-16.0, -3.0, 0.0), "pel": V(0.0, 0.56, -0.785),
                      "hand_l": V(0.46, 0.90, 0.075), "hand_r": V(-0.56, 0.92, 0.075), "ho_r": blade_o((-0.3, -0.95, 0.0), (0, 0, 1))}, "in2"))
    keys.append((38, {"head": (-12.0, -2.0, 0.0), "foot_r": V(-0.24, 0.0, 0.10), "curl_l": -0.6}, "smooth"))
    keys.append((48, {}, "smooth"))
    return F.build(keys, 48, post=_travel_root)


@clip("Death_1H_Back", events={"contact": 0, "step": 9, "knees": 15, "down": 25, "bounce": 28},
      note="sword+shield: hit from behind. Arches, arms fly back, one stumbling step forward, knees, falls face-down (1.8 s); 0.5 m of pelvis travel forward; terminal: lying face-down, head -Y",
      root_motion_m=0.5)
def death_1h_back():
    F = FR.F
    keys = [(0, dict(N))]
    keys.append((1, {"tor": (-18.0, 0.0, 0.0), "head": (-14.0, 0.0, 0.0), "pel": V(0, -0.02, 0.0), "hip": (4.0, 0.0, 0.0),
                     "hand_l": V(0.40, 0.18, 1.10), "hand_r": V(-0.38, 0.20, 1.14), "curl_r": 0.6, "curl_l": 0.2,
                     "ho_r": blade_o((-0.2, 0.3, 0.9), (1, 0, 0))}, "out2"))
    keys.append((3, {"tor": (-30.0, -8.0, 0.0), "head": (-22.0, -6.0, 0.0), "pel": V(0, -0.07, -0.02), "hip": (8.0, 0.0, 0.0),
                     "hand_l": V(0.44, 0.24, 1.30), "hand_r": V(-0.46, 0.26, 1.28), "curl_r": 0.2, "curl_l": -0.2,
                     "ho_r": blade_o((-0.5, 0.5, 0.7), (1, 0, 0)), "_bow": {"hand_r": V(-0.05, 0.0, 0.05)}}, "out2"))
    # stumble step: left foot reaches forward
    keys.append((6, {"tor": (-4.0, -14.0, -4.0), "head": (-6.0, -4.0, 0.0), "pel": V(0.03, -0.16, -0.07), "hip": (8.0, -10.0, 0.0),
                     "hand_l": V(0.50, 0.15, 1.05), "hand_r": V(-0.50, 0.12, 1.00), "curl_r": -0.6,
                     "ho_r": blade_o((-0.8, 0.2, -0.3), (0, 0, 1)),
                     "foot_l": V(0.14, -0.22, 0.17)}, "smooth"))
    keys.append((9, {"tor": (12.0, -6.0, 0.0), "head": (8.0, 0.0, 0.0), "pel": V(0.02, -0.30, -0.12), "hip": (10.0, -6.0, 0.0),
                     "hand_l": V(0.40, -0.16, 0.90), "hand_r": V(-0.40, -0.16, 0.86), "curl_r": -1.0,
                     "ho_r": blade_o((-0.9, -0.2, -0.4), (0, 0, 1)),
                     "foot_l": V(0.14, -0.30, 0.104)}, "in2"))
    keys.append((12, {"tor": (24.0, 0.0, 0.0), "head": (14.0, 0.0, 0.0), "pel": V(0.0, -0.36, -0.28), "hip": (14.0, 0.0, 0.0),
                     "hand_l": V(0.40, -0.40, 0.72), "hand_r": V(-0.36, -0.30, 0.66), "curl_l": -0.5,
                     "ho_r": blade_o((-0.9, -0.4, -0.3), (0, 0, 1)),
                     "foot_r": V(-0.15, 0.10, 0.20), "foot_l": V(0.13, 0.02, 0.20), "fyaw_l": 175.0, "fyaw_r": -175.0}, "smooth"))
    keys.append((15, {"tor": (30.0, 0.0, 0.0), "head": (16.0, 4.0, 0.0), "pel": V(0.0, -0.40, -0.42), "hip": (18.0, 0.0, 0.0),
                      "hand_l": V(0.36, -0.60, 0.50), "hand_r": V(-0.34, -0.52, 0.46),
                      "foot_l": V(0.12, 0.05, 0.10), "foot_r": V(-0.12, 0.05, 0.10), "fyaw_l": 175.0, "fyaw_r": -175.0, "fpit_l": 0.0, "fpit_r": 0.0}, "in2"))
    keys.append((20, {"tor": (24.0, 0.0, 0.0), "head": (10.0, 20.0, 0.0), "pel": V(0.0, -0.46, -0.66), "hip": (50.0, 0.0, 0.0),
                      "hand_l": V(0.42, -0.90, 0.28), "hand_r": V(-0.46, -0.86, 0.26),
                      "foot_l": V(0.12, 0.20, 0.10), "foot_r": V(-0.12, 0.20, 0.10), "fyaw_l": 175.0, "fyaw_r": -175.0, "fpit_l": 0.0, "fpit_r": 0.0}, "in2"))
    keys.append((23, {"tor": (10.0, 0.0, 0.0), "head": (10.0, 40.0, 0.0), "pel": V(0.0, -0.48, -0.76), "hip": (80.0, 0.0, 0.0),
                      "hand_l": V(0.44, -1.05, 0.13), "hand_r": V(-0.48, -1.02, 0.13),
                      "elb_l": V(0.60, -0.80, 0.10), "elb_r": V(-0.62, -0.80, 0.10),
                      "ho_r": blade_o((-0.2, -0.95, 0.05), (0, 0, 1)),
                      "foot_l": V(0.12, 0.30, 0.10), "foot_r": V(-0.14, 0.30, 0.10)}, "in2"))
    keys.append((25, {"tor": (-2.0, 0.0, 0.0), "head": (0.0, 55.0, 0.0), "pel": V(0.0, -0.50, -0.785), "hip": (92.0, 0.0, 0.0),
                      "hand_l": V(0.46, -1.10, 0.075), "hand_r": V(-0.50, -1.08, 0.075),
                      "elb_l": V(0.60, -0.85, 0.07), "elb_r": V(-0.62, -0.85, 0.07),
                      "ho_r": blade_o((-0.2, -0.95, 0.0), (0, 0, 1)),
                      "foot_l": V(0.12, 0.33, 0.09), "foot_r": V(-0.15, 0.36, 0.09)}, "in2"))
    keys.append((27, {"hip": (86.0, 0.0, 0.0), "head": (-8.0, 60.0, 0.0), "pel": V(0.0, -0.49, -0.775),
                      "hand_l": V(0.46, -1.10, 0.12), "hand_r": V(-0.50, -1.08, 0.12)}, "out2"))
    keys.append((30, {"hip": (91.0, 0.0, 0.0), "head": (8.0, 62.0, 0.0), "pel": V(0.0, -0.50, -0.785),
                      "hand_l": V(0.46, -1.10, 0.075), "hand_r": V(-0.50, -1.08, 0.075)}, "in2"))
    keys.append((40, {"head": (4.0, 60.0, 0.0), "curl_l": -0.7}, "smooth"))
    keys.append((54, {}, "smooth"))
    return F.build(keys, 54, post=_mk_post([(0, 0.0, V(0.13, -0.42, 0.08), V(-0.13, -0.42, 0.08)), (11, 0.0, V(0.13, -0.55, 0.25), V(-0.13, -0.55, 0.25)),
                                            (15, 1.0, V(0.13, -0.55, 0.25), V(-0.13, -0.55, 0.25)), (20, 1.0, V(0.13, -0.55, 0.25), V(-0.13, -0.55, 0.25)),
                                            (24, 0.0, V(0.13, -0.55, 0.25), V(-0.13, -0.55, 0.25))]))


@clip("Death_2H_Knees", events={"contact": 0, "knees": 14, "plant": 22, "down": 50, "bounce": 54},
      note="two-hand sword: gut hit, drops to both knees, leans on the sword planted point-down for a beat, slides off to the left and lies on its side (2.2 s); 0.4 m travel; terminal: lying on the left side, head +X",
      root_motion_m=0.4)
def death_2h_knees():
    F = FR.F
    keys = [(0, dict(N))]
    keys.append((1, {"tor": (12.0, 0.0, 0.0), "head": (10.0, 0.0, 0.0), "pel": V(0, 0.02, -0.02), "hip": (6.0, 0.0, 0.0),
                     "hand_l": V(0.20, -0.22, 0.98), "hand_r": V(-0.20, -0.24, 1.0), "curl_l": 0.9, "curl_r": 1.0}, "out2"))
    keys.append((3, {"tor": (26.0, 0.0, 0.0), "head": (16.0, 0.0, 0.0), "pel": V(0, 0.05, -0.08), "hip": (10.0, 0.0, 0.0),
                     "hand_l": V(0.16, -0.30, 0.90), "hand_r": V(-0.16, -0.32, 0.92),
                     "ho_r": blade_o((0.0, -0.5, 0.85), (1, 0, 0))}, "out2"))
    keys.append((8, {"tor": (24.0, 0.0, 0.0), "head": (14.0, 0.0, 0.0), "pel": V(0, 0.08, -0.26), "hip": (14.0, 0.0, 0.0),
                     "hand_l": V(0.10, -0.40, 0.85), "hand_r": V(-0.08, -0.40, 0.88),
                     "ho_r": blade_o((0.0, -0.4, -0.9), (1, 0, 0))}, "in2"))
    keys.append((11, {"pel": V(0, 0.06, -0.38), "foot_l": V(0.12, 0.12, 0.17), "foot_r": V(-0.12, 0.12, 0.17), "fyaw_l": 175.0, "fyaw_r": -175.0,
                      "tor": (22.0, 0.0, 0.0), "hip": (10.0, 0.0, 0.0)}, "smooth"))
    keys.append((14, {"pel": V(0, 0.04, -0.42), "foot_l": V(0.12, 0.50, 0.10), "foot_r": V(-0.12, 0.50, 0.10), "fyaw_l": 175.0, "fyaw_r": -175.0,
                      "tor": (18.0, 0.0, 0.0), "hip": (4.0, 0.0, 0.0), "head": (10.0, 0.0, 0.0)}, "in2"))
    # bounce on the knees, sword tip planted in front, leaning on it
    keys.append((17, {"pel": V(0, 0.04, -0.41), "tor": (14.0, 0.0, 0.0)}, "out2"))
    keys.append((22, {"pel": V(0, 0.02, -0.42), "tor": (22.0, 0.0, 0.0), "head": (24.0, 0.0, 0.0),
                      "hand_l": V(0.06, -0.42, 0.84), "hand_r": V(-0.04, -0.42, 0.90), "ho_r": blade_o((0.0, -0.1, -1.0), (1, 0, 0))}, "smooth"))
    keys.append((30, {"pel": V(0, 0.0, -0.43), "tor": (28.0, 0.0, 0.0), "head": (30.0, 0.0, 0.0)}, "smooth"))     # lean-on-it beat
    # slides off: hands let go, body tips to the left, hip first
    keys.append((36, {"pel": V(0.06, 0.02, -0.43), "hip": (4.0, 0.0, 20.0), "tor": (26.0, 0.0, 22.0), "head": (30.0, 0.0, 12.0),
                      "hand_l": V(0.16, -0.38, 0.74), "hand_r": V(-0.02, -0.44, 0.86), "curl_l": 0.0,
                      "ho_r": blade_o((0.15, -0.2, -1.0), (1, 0, 0))}, "in2"))
    keys.append((42, {"pel": V(0.20, 0.06, -0.60), "hip": (-6.0, 0.0, 55.0), "tor": (20.0, 0.0, 30.0), "head": (10.0, 0.0, 10.0),
                      "hand_l": V(0.40, -0.30, 0.40), "hand_r": V(0.45, -0.30, 0.55), "curl_r": -0.4,
                      "ho_r": blade_o((0.3, -0.7, -0.7), (0, 0, 1)),
                      "foot_l": V(0.12, 0.45, 0.10), "foot_r": V(-0.12, 0.45, 0.10)}, "in2"))
    keys.append((45, {"foot_l": V(0.22, 0.30, 0.20), "foot_r": V(0.10, 0.34, 0.26)}, "smooth"))
    keys.append((47, {"pel": V(0.36, 0.08, -0.72), "hip": (-14.0, 0.0, 72.0), "tor": (10.0, 0.0, 6.0), "head": (0.0, 0.0, -8.0),
                      "hand_l": V(0.80, -0.12, 0.16), "hand_r": V(0.88, -0.30, 0.36),
                      "ho_r": blade_o((0.1, -0.95, -0.25), (0, 0, 1)),
                      "foot_l": V(0.26, 0.20, 0.10), "foot_r": V(0.14, 0.24, 0.20)}, "in2"))
    keys.append((50, {"pel": V(0.40, 0.08, -0.735), "hip": (-16.0, 0.0, 78.0), "tor": (6.0, 0.0, 2.0), "head": (0.0, 0.0, -14.0),
                      "hand_l": V(0.86, -0.12, 0.09), "hand_r": V(0.92, -0.20, 0.26),
                      "elb_l": V(0.80, 0.10, 0.06), "elb_r": V(0.70, -0.05, 0.42),
                      "ho_r": blade_o((0.05, -0.95, -0.25), (0, 0, 1)),
                      "foot_l": V(0.22, 0.15, 0.10), "foot_r": V(0.12, 0.18, 0.20)}, "in2"))
    keys.append((54, {"hand_r": V(0.92, -0.20, 0.30), "head": (0.0, 0.0, -6.0), "hip": (-14.0, 0.0, 76.0)}, "out2"))
    keys.append((58, {"hand_r": V(0.92, -0.20, 0.26), "head": (0.0, 0.0, -14.0), "hip": (-16.0, 0.0, 78.0)}, "in2"))
    keys.append((66, {"curl_r": -0.8}, "smooth"))
    return F.build(keys, 66, post=_mk_post([(0, 0.0, V(0.13, -0.15, 0.25), V(-0.13, -0.15, 0.25)), (8, 0.0, V(0.13, -0.15, 0.25), V(-0.13, -0.15, 0.25)),
                                   (13, 1.0, V(0.13, -0.15, 0.25), V(-0.13, -0.15, 0.25)), (40, 1.0, V(0.13, -0.15, 0.25), V(-0.13, -0.15, 0.25)),
                                   (50, 1.0, V(0.30, -0.28, 0.14), V(0.22, -0.30, 0.30))]))


B0 = bow_ready()


@clip("Death_Bow_Side", events={"contact": 0, "knees": 15, "down": 24, "bounce": 27},
      note="bow: arrow/hit from the left. Body spins 90 deg away (chest first), bow flies out, legs fold, collapses on the right side (1.5 s); 0.43 m travel; terminal: lying on the right side, head +Y",
      root_motion_m=0.43)
def death_bow_side():
    F = FR.F
    K = dict(B0)
    keys = [(0, K)]
    keys.append((1, {"tor": (4.0, -14.0, -12.0), "head": (0.0, -6.0, -10.0), "pel": V(-0.02, 0.0, -0.01),
                     "hand_l": rel(0.50, 0.0, 1.20, -14, (-0.02, 0)), "hand_r": rel(-0.25, 0.10, 1.05, -14, (-0.02, 0)), "curl_l": -0.5,
                     "ho_l": ((0.2, -0.6, 0.6), (-1.0, 0.0, 0.0))}, "out2"))
    keys.append((3, {"tor": (6.0, -46.0, -14.0), "hip": (0.0, -18.0, -4.0), "head": (0.0, -20.0, -12.0), "pel": V(-0.09, 0.0, -0.04),
                     "hand_l": rel(0.55, 0.05, 1.32, -64, (-0.09, 0)), "hand_r": rel(-0.40, 0.05, 1.15, -64, (-0.09, 0)), "curl_l": -1.0,
                     "ho_l": ((0.5, -0.5, 0.6), (-1.0, 0.0, 0.0)), "_bow": {"hand_l": V(0.05, 0.0, 0.06)}}, "out2"))
    keys.append((6, {"tor": (8.0, -50.0, -8.0), "hip": (0.0, -58.0, -6.0), "head": (0.0, -10.0, -6.0), "pel": V(-0.16, 0.02, -0.10),
                     "hand_l": rel(0.50, -0.20, 1.25, -108, (-0.16, 0.02)), "hand_r": rel(-0.40, 0.10, 1.05, -108, (-0.16, 0.02)),
                     "foot_l": V(-0.02, 0.10, 0.17), "fyaw_l": -80.0, "foot_r": V(-0.26, 0.06, 0.104), "fyaw_r": -95.0}, "smooth"))
    keys.append((9, {"tor": (10.0, -34.0, -4.0), "hip": (0.0, -74.0, -4.0), "head": (0.0, 0.0, 0.0), "pel": V(-0.22, 0.05, -0.20),
                     "hand_l": rel(0.45, -0.25, 1.05, -108, (-0.22, 0.05)), "hand_r": rel(-0.40, 0.10, 0.90, -108, (-0.22, 0.05)),
                     "foot_l": V(-0.06, 0.20, 0.104), "fyaw_l": -80.0}, "in2"))
    keys.append((12, {"tor": (16.0, -20.0, -6.0), "hip": (0.0, -68.0, -8.0), "pel": V(-0.27, 0.10, -0.34),
                      "hand_l": rel(0.30, -0.10, 0.90, -88, (-0.27, 0.10)), "hand_r": rel(-0.40, 0.10, 0.82, -88, (-0.27, 0.10)), "curl_l": -0.6}, "smooth"))
    keys.append((15, {"tor": (18.0, -16.0, -10.0), "hip": (0.0, -80.0, -18.0), "head": (10.0, 10.0, -6.0), "pel": V(-0.30, 0.16, -0.50),
                      "hand_l": rel(0.20, -0.10, 0.70, -96, (-0.30, 0.16)), "hand_r": rel(-0.30, 0.10, 0.62, -96, (-0.30, 0.16)),
                      "foot_l": V(-0.18, 0.30, 0.15), "foot_r": V(-0.38, 0.32, 0.104)}, "in2"))
    keys.append((20, {"tor": (12.0, -10.0, -14.0), "hip": (-2.0, -88.0, -60.0), "head": (10.0, 12.0, -6.0), "pel": V(-0.34, 0.24, -0.66),
                      "hand_l": V(-0.30, 0.55, 0.22), "hand_r": V(-0.44, 0.90, 0.16),
                      "elb_l": V(-0.36, 0.85, 0.24), "elb_r": V(-0.52, 0.75, 0.08),
                      "foot_l": V(-0.36, -0.15, 0.20), "foot_r": V(-0.46, -0.05, 0.12)}, "in2"))
    keys.append((24, {"tor": (4.0, -6.0, -6.0), "hip": (0.0, -90.0, -86.0), "head": (10.0, 14.0, -4.0), "pel": V(-0.34, 0.26, -0.715),
                      "hand_l": V(-0.36, 0.60, 0.10), "hand_r": V(-0.36, 1.06, 0.075),
                      "elb_l": V(-0.42, 0.90, 0.20), "elb_r": V(-0.46, 0.85, 0.07),
                      "foot_l": V(-0.40, -0.25, 0.16), "foot_r": V(-0.46, -0.22, 0.09)}, "in2"))
    keys.append((26, {"hip": (0.0, -90.0, -80.0), "head": (0.0, 10.0, 8.0), "pel": V(-0.34, 0.26, -0.70), "hand_l": V(-0.36, 0.60, 0.16)}, "out2"))
    keys.append((29, {"hip": (0.0, -90.0, -86.0), "head": (10.0, 14.0, -8.0), "pel": V(-0.34, 0.26, -0.715), "hand_l": V(-0.36, 0.60, 0.10)}, "in2"))
    keys.append((45, {"curl_l": -0.5}, "smooth"))
    return F.build(keys, 45, post=_mk_post([(14, 0.0, V(-0.62, 0.02, 0.22), V(-0.60, 0.05, 0.10)), (22, 1.0, V(-0.62, 0.02, 0.22), V(-0.60, 0.05, 0.10))]))
