# AMBIENT clips: idle fidgets (one-shots that start and end at neutral, triggered by the villager AI at random or by weather /
# time of day via tags), the rain layer, and the elder's cane walk.
import math
from mathutils import Vector
import combat_common as CC
import life_common as LC
from combat_common import V
from life_common import life_clip, neutral, grip_o, wrist_at
from life_clips_social import (mk, hs, hsw, K, loop, build, feet, alive, addp, addt, addh, addsh, win, smoothstep, OR, FT_TALK)
from life_clips_kids import foot_at, frames

TAU = 2 * math.pi
_N = neutral()
NF = {k: _N[k] for k in ("foot_l", "foot_r", "fyaw_l", "fyaw_r", "fpit_l", "fpit_r")}    # the neutral feet
HIPR = hs(0.24, 0.02, 0.98, "hip", 0.5, e=(0.52, -0.05, 1.03))


def nf(**over):
    d = dict(NF)
    d.update(over)
    return d


@life_clip("Life_Ambient_Look_Around", category="ambient/fidget", tags=["idle"], events={"look_l": [14], "look_r": [46]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: the head leads a slow look over the left shoulder, then a longer look to the right, the chest follows a beat late, back to neutral")
def _look_around():
    n = 96
    k = [K(0),
         K(12, "smooth", head=(-5, 34, 0), tor=(2, 6, 0)),
         K(22, "smooth", head=(-2, 42, 2), tor=(2, 11, 0), w=0.2),
         K(34, "smooth", head=(-2, 40, 2), tor=(2, 12, 0), w=0.2),
         K(50, "smooth", head=(2, -36, -2), tor=(2, -8, 0), w=-0.2),
         K(62, "smooth", head=(4, -46, -2), tor=(2, -13, 0), w=-0.3),
         K(74, "smooth", head=(1, -40, 0), tor=(2, -12, 0), w=-0.2),
         K(88, "smooth", head=(0, 4, 0), tor=(2, 1, 0)),
         K(n)]
    return build(k, n, post=alive(0.5, 0.2, True))


@life_clip("Life_Ambient_Scratch_Head", category="ambient/fidget", tags=["idle", "puzzled"], events={"scratch": [18, 50]}, blend_in=0.25, blend_out=0.3,
           note="one-shot: right hand up to the back of the head, scratches with a curling hand, head tilts into it, drops and shrugs it off")
def _scratch_head():
    n = 90
    up = hs(0.15, 0.02, 1.57, "up_in", 0.5, e=(0.40, 0.0, 1.56))
    k = [K(0),
         K(8, "smooth", R=hs(0.24, 0.08, 1.26, "up_in", 0.4, e=(0.38, 0.0, 1.12)), head=(1, 0, -2), tor=(2, 0, 0)),
         K(18, "out2", R=up, head=(2, -6, -8), tor=(1, -3, 0), w=0.3, sh=(0, 5)),
         K(58, "smooth", R=up, head=(4, -4, -8), tor=(1, -3, 0), w=0.3, sh=(0, 5)),
         K(68, "smooth", R=hs(0.24, 0.08, 1.26, "up_in", 0.4, e=(0.38, 0.0, 1.12)), head=(2, 0, -2), tor=(2, 0, 0)),
         K(76, "smooth", head=(1, 0, 0), sh=(4, 4), w=0.0),
         K(n)]

    def scratch(fr, nn, s):
        e = win(fr, 20, 56, 4, 5)
        v = math.sin(TAU * 5 * (fr - 20) / 36.0)
        s["hand_r"] = Vector(s["hand_r"]) + V(0.0, 0.022 * v * e, 0.012 * v * e)
        s["curl_r"] = s["curl_r"] + 0.25 * v * e
        addh(s, (0.8 * v * e, 0, 0.8 * v * e))
    return build(k, n, post=CC_chain(scratch, alive(0.5, 0.3, True)))


def CC_chain(*posts):
    return LC.chain(*posts)


@life_clip("Life_Ambient_Shift_Weight", category="ambient/fidget", tags=["idle"], events={"shift": [16], "back": [58]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: sighs, moves the weight onto the left leg while the right foot re-plants wider, holds the cocked hip, and settles back")
def _shift_weight():
    n = 84
    wide = nf(foot_r=V(-0.19, 0.11, 0.104), fyaw_r=-14.0)
    lift = nf(foot_r=V(-0.16, 0.09, 0.16), fyaw_r=-10.0)
    k = [K(0),
         K(8, "smooth", w=0.5, tor=(4, 0, 0), head=(3, 0, 0), feet=nf(), sh=(3, 3)),
         K(16, "smooth", w=0.8, tor=(3, 2, 0), head=(2, 3, 0), feet=lift, sh=(0, 0)),
         K(24, "smooth", w=0.9, tor=(2, 3, 0), head=(0, 4, 0), feet=wide, L=hs(0.29, 0.02, 0.93, "hang", 0.3), R=hs(0.25, 0.04, 0.95, "hang", 0.3)),
         K(46, "smooth", w=0.9, tor=(2, 3, 0), head=(0, 5, 0), feet=wide),
         K(58, "smooth", w=0.4, tor=(3, 0, 0), head=(2, 0, 0), feet=lift),
         K(68, "smooth", w=0.0, tor=(2, 0, 0), head=(0, 0, 0), feet=nf()),
         K(n)]
    return build(k, n, post=alive(0.5, 0.1, True))


@life_clip("Life_Ambient_Stretch_Morning", category="ambient/fidget", tags=["morning"], events={"peak": [40], "release": [70]}, blend_in=0.3, blend_out=0.35,
           note="one-shot: inhales, both arms up with the fingers laced and palms to the sky, back arches and head tips back, side lean, then the arms fall wide and the shoulders roll out")
def _stretch():
    n = 132
    o = ((-0.5, 0.2, 0.85), (0, -0.2, 1))
    up = lambda z=1.94, ou=0.05, fw=0.10: dict(L=hs(ou, fw, z, o, 0.8, e=(0.30, -0.05, 1.70)), R=hs(ou, fw, z, o, 0.8, e=(0.30, -0.05, 1.70)))
    wide = dict(L=hs(0.50, 0.04, 1.30, "palm_dn", -0.3, e=(0.52, -0.05, 1.12)), R=hs(0.50, 0.04, 1.30, "palm_dn", -0.3, e=(0.52, -0.05, 1.12)))
    k = [K(0),
         K(10, "smooth", tor=(-1, 0, 0), head=(-3, 0, 0), L=hs(0.30, 0.10, 1.10, "palm_up", 0.3), R=hs(0.30, 0.10, 1.10, "palm_up", 0.3), sh=(3, 3)),
         K(28, "smooth", tor=(-10, 0, 0), hip=(-3, 0, 0), head=(-20, 0, 0), pel=(0, 0.02, 0), sh=(4, 4), **up()),
         K(40, "smooth", tor=(-14, 0, 5), hip=(-4, 0, 0), head=(-22, 0, 3), pel=(0.01, 0.03, 0), sh=(5, 5), **up(1.97, 0.05, 0.08)),
         K(54, "smooth", tor=(-14, 0, -5), hip=(-4, 0, 0), head=(-22, 0, -3), pel=(-0.01, 0.03, 0), sh=(5, 5), **up(1.97, 0.05, 0.08)),
         K(68, "out2", tor=(0, 0, 0), hip=(0, 0, 0), head=(4, 0, 0), sh=(2, 2), **wide),
         K(80, "smooth", tor=(6, 0, 0), head=(6, 0, 0), sh=(-3, -3), L=hs(0.32, 0.04, 1.02, "palm_dn", 0.2), R=hs(0.32, 0.04, 1.02, "palm_dn", 0.2)),
         K(96, "smooth", tor=(3, 0, 0), head=(0, 0, 0), sh=(4, 0), L=hs(0.29, 0.02, 0.94, "hang", 0.3), R=hs(0.29, 0.02, 0.94, "hang", 0.3)),
         K(108, "smooth", tor=(2, 0, 0), head=(0, 0, 0), sh=(0, 4)),
         K(n)]
    return build(k, n, post=alive(0.4, 0.0, True))


@life_clip("Life_Ambient_Yawn", category="ambient/fidget", tags=["evening"], events={"yawn": [18], "rub": [58]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: a big yawn behind the right hand, head tipping back, chest opening, then a sagging exhale and a rub of the eye with the left hand")
def _yawn():
    n = 96
    mouth = hs(0.05, 0.21, 1.41, "up_in", 0.2, e=(0.30, 0.03, 1.26))
    eyeL = hs(0.05, 0.16, 1.44, "face", 0.4, e=(0.30, 0.0, 1.26))
    k = [K(0),
         K(8, "smooth", tor=(-3, 0, 0), head=(-6, 0, 0), sh=(3, 3), R=hs(0.24, 0.10, 1.20, "up_in", 0.2)),
         K(18, "out2", tor=(-8, 0, 0), head=(-15, 0, 2), sh=(8, 8), R=mouth, pel=(0, 0.01, 0)),
         K(40, "smooth", tor=(-9, 0, 0), head=(-17, 0, 2), sh=(9, 9), R=mouth, pel=(0, 0.01, 0)),
         K(50, "smooth", tor=(6, 0, 0), head=(10, 0, -2), sh=(-3, -3), R=hs(0.25, 0.10, 1.10, "up_in", 0.3)),
         K(60, "smooth", tor=(5, 0, 0), head=(9, -3, 2), sh=(-2, -2), L=eyeL),
         K(78, "smooth", tor=(4, 0, 0), head=(6, -3, 2), L=eyeL),
         K(88, "smooth", tor=(3, 0, 0), head=(2, 0, 0)),
         K(n)]

    def rub(fr, nn, s):
        e = win(fr, 60, 80, 4, 4)
        v = math.sin(TAU * 3 * (fr - 60) / 20.0)
        s["hand_l"] = Vector(s["hand_l"]) + V(0.014 * v * e, 0, 0.008 * v * e)
    return build(k, n, post=CC_chain(rub, alive(0.5, 0.4, True)))


@life_clip("Life_Ambient_Check_Sky", category="ambient/fidget", tags=["weather"], events={"look": [16]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: tips the head back to read the sky, the chest opens, a slow sweep from one side to the other, then back down")
def _check_sky():
    n = 84
    k = [K(0),
         K(14, "smooth", tor=(-4, 0, 0), head=(-30, 8, 0), R=HIPR, sh=(2, 2), w=0.3),
         K(28, "smooth", tor=(-6, 3, 0), head=(-38, 16, 3), R=HIPR, sh=(3, 3), w=0.3),
         K(46, "smooth", tor=(-6, -3, 0), head=(-36, -18, -3), R=HIPR, sh=(3, 3), w=0.3),
         K(60, "smooth", tor=(-4, 0, 0), head=(-30, -6, 0), R=HIPR, w=0.2),
         K(72, "smooth", tor=(2, 0, 0), head=(4, 0, 0), R=hs(0.26, 0.02, 0.96, "hang", 0.3), w=0.0),
         K(n)]
    return build(k, n, post=alive(0.5, 0.0, True))


@life_clip("Life_Ambient_Shade_Eyes", category="ambient/fidget", tags=["sun"], events={"shade": [16]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: flat right hand to the brow against the glare, squints along the horizon left to right, drops the hand")
def _shade_eyes():
    n = 102
    brow = hs(0.05, 0.13, 1.55, "palm_dn", -0.6, e=(0.28, 0.0, 1.42))
    k = [K(0),
         K(10, "smooth", R=hs(0.22, 0.14, 1.24, "palm_dn", -0.5, e=(0.34, 0.0, 1.12)), head=(-2, 0, 0)),
         K(18, "out2", R=brow, head=(-6, 14, 0), tor=(-1, 6, 0), sh=(0, 4)),
         K(40, "smooth", R=brow, head=(-5, 24, 3), tor=(-1, 10, 0), sh=(0, 4), w=0.2),
         K(66, "smooth", R=brow, head=(-5, -24, -3), tor=(-1, -10, 0), sh=(0, 4), w=-0.2),
         K(78, "smooth", R=brow, head=(-4, -10, 0), tor=(0, -4, 0), sh=(0, 3)),
         K(90, "smooth", R=hs(0.24, 0.10, 1.10, "palm_dn", -0.3), head=(0, 0, 0), tor=(2, 0, 0)),
         K(n)]
    return build(k, n, post=alive(0.4, 0.2, True))


@life_clip("Life_Ambient_Wipe_Brow", category="ambient/fidget", tags=["heat"], events={"wipe": [26], "flick": [44]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: heavy sigh, right forearm wipes across the forehead, flicks the sweat off the hand, sags and breathes out")
def _wipe_brow():
    n = 84
    tR = hs(0.14, 0.10, 1.57, "palm_in", 0.0, e=(0.36, 0.0, 1.42))
    tL = hs(-0.12, 0.13, 1.58, "palm_in", 0.0, e=(0.20, 0.10, 1.45))
    k = [K(0),
         K(8, "smooth", tor=(9, 0, 0), head=(9, 0, 0), sh=(-2, -2), pel=(0, -0.01, -0.005)),
         K(16, "smooth", tor=(9, 0, 0), head=(6, 0, 0), R=hs(0.24, 0.10, 1.30, "palm_in", 0.0, e=(0.38, 0.0, 1.16)), pel=(0, -0.01, -0.005)),
         K(22, "smooth", tor=(8, 0, 0), head=(8, -4, -3), R=tR, pel=(0, -0.01, -0.005)),
         K(31, "smooth", tor=(8, 0, 0), head=(8, 4, 3), R=tL, pel=(0, -0.01, -0.005)),
         K(38, "smooth", tor=(8, 0, 0), head=(8, 0, 0), R=hs(0.30, 0.10, 1.34, "palm_in", 0.0, e=(0.44, 0.0, 1.20))),
         K(45, "out2", tor=(8, -2, 0), head=(10, -6, 0), R=hs(0.44, 0.14, 1.00, "palm_dn", -0.9, e=(0.50, 0.0, 1.05))),
         K(52, "smooth", tor=(7, 0, 0), head=(9, 0, 0), R=hs(0.30, 0.04, 0.95, "hang", 0.3)),
         K(64, "smooth", tor=(5, 0, 0), head=(6, 0, 0), sh=(-3, -3), pel=(0, 0, -0.01)),
         K(74, "smooth", tor=(3, 0, 0), head=(2, 0, 0)),
         K(n)]

    def heave(fr, nn, s):
        e = win(fr, 4, 70, 6, 10)
        v = math.sin(TAU * 3.5 * fr / 30.0)
        addt(s, (1.4 * v * e, 0, 0))
        addsh(s, 1.5 * v * e, 1.5 * v * e)
    return build(k, n, post=CC_chain(heave, alive(0.4, 0.0, True)))


@life_clip("Life_Ambient_Rub_Arms", category="ambient/fidget", tags=["cold"], events={"rub": [22, 40, 58, 76]}, blend_in=0.3, blend_out=0.3,
           note="one-shot: hunches, hugs itself and rubs both upper arms briskly while the body shudders, releases with a shiver")
def _rub_arms():
    n = 108
    hugR = hsw(0.19, -0.10, 1.31, ((-1, 0.3, -0.2), (0, -1, 0)), 0.7, e=(-0.25, -0.18, 1.14))
    hugL = hsw(-0.19, -0.13, 1.35, ((1, 0.3, -0.2), (0, -1, 0)), 0.7, e=(0.25, -0.18, 1.18))
    k = [K(0),
         K(10, "smooth", tor=(6, 0, 0), head=(8, 0, 0), sh=(9, 9), L=hs(0.24, 0.16, 1.10, "cross", 0.5), R=hs(0.24, 0.16, 1.10, "cross", 0.5)),
         K(20, "out2", tor=(9, 0, 0), head=(12, 0, 0), sh=(10, 10), pel=(0, -0.01, -0.01), L=hugL, R=hugR),
         K(82, "smooth", tor=(9, 0, 0), head=(12, 0, 0), sh=(10, 10), pel=(0, -0.01, -0.01), L=hugL, R=hugR),
         K(94, "smooth", tor=(5, 0, 0), head=(4, 0, 0), sh=(4, 4), L=hs(0.28, 0.06, 0.95, "hang", 0.4), R=hs(0.28, 0.06, 0.95, "hang", 0.4)),
         K(n)]

    def rub(fr, nn, s):
        e = win(fr, 22, 80, 4, 6)
        v = math.sin(TAU * 4 * (fr - 22) / 58.0)
        v2 = math.sin(TAU * 4 * (fr - 22) / 58.0 + 1.2)
        s["hand_r"] = Vector(s["hand_r"]) + V(0, 0, 0.055 * v * e)
        s["hand_l"] = Vector(s["hand_l"]) + V(0, 0, 0.055 * v2 * e)
        sh = math.sin(TAU * 8 * fr / 30.0)
        z = win(fr, 6, 100, 8, 10)
        addt(s, (0.8 * sh * z, 1.2 * sh * z, 0))
        addsh(s, 2.5 * sh * z, 2.5 * sh * z)
    return build(k, n, post=CC_chain(rub, alive(0.4, 0.0, True)))


def _glance(name, sgn):
    n = 36

    @life_clip(name, category="ambient/react", tags=["react"], events={"peak": [12]}, blend_in=0.12, blend_out=0.2,
               note="one-shot 1.2 s glance to the %s: the head snaps round first, the chest follows a few frames later, hold, and back" % ("left" if sgn > 0 else "right"))
    def _g():
        k = [K(0),
             K(6, "out2", head=(1, 42 * sgn, 2 * sgn), tor=(2, 5 * sgn, 0), sh=(2, 2)),
             K(11, "out2", head=(2, 58 * sgn, 3 * sgn), tor=(2, 17 * sgn, 0), hip=(0, 3 * sgn, 0), sh=(3, 3)),
             K(22, "smooth", head=(2, 56 * sgn, 3 * sgn), tor=(2, 16 * sgn, 0), hip=(0, 3 * sgn, 0), sh=(2, 2)),
             K(30, "smooth", head=(0, 10 * sgn, 0), tor=(2, 3 * sgn, 0)),
             K(n)]
        return build(k, n)
    return _g


_glance("Life_Ambient_Glance_L", 1)
_glance("Life_Ambient_Glance_R", -1)


# ------------------------------------------------------------------ rain (upper-body layer)
@life_clip("Life_Ambient_Rain_Hunch_Upper", loop=True, layer="upper", category="ambient/weather", tags=["rain"], blend_in=0.5, blend_out=0.5,
           note="upper-body layer over locomotion or idle (spine_01 and up): shoulders up, head down, left forearm held flat above the head as a shield, right hand pulling the collar shut; small shudders")
def _rain_hunch():
    n = 120
    shield = hsw(0.10, -0.10, 1.73, ((-0.7, -0.7, 0.0), (0, 0, -1)), -0.4, e=(0.40, 0.02, 1.62))
    collar = hs(0.08, 0.14, 1.36, "chest", 0.9, e=(0.30, 0.02, 1.16))
    base = dict(tor=(13, 0, 0), head=(20, 0, 3), sh=(14, 15), L=shield, R=collar)
    k = [K(0, **base),
         K(30, **dict(base, tor=(14, 3, 0), head=(23, -4, 5))),
         K(60, **dict(base, tor=(12, 0, 0), head=(18, 2, 2))),
         K(90, **dict(base, tor=(14, -3, 0), head=(22, 5, 4)))]
    k = loop(k, n)

    def shudder(fr, nn, s):
        v = math.sin(TAU * 10 * fr / n)
        v2 = math.sin(TAU * 6 * fr / n + 0.7)
        addt(s, (0.5 * v, 0.8 * v2, 0))
        addsh(s, 1.5 * v, 1.5 * v)
        addh(s, (0.7 * v2, 0, 0))
    return build(k, n, post=CC_chain(shudder, alive(0.5, 0.6)))


# ------------------------------------------------------------------ elder walk with a cane
CANE_LEN = 0.90          # the life_props cane: fist at the top, shaft along -thumb axis down to the ground (length 0.90 m measured from cane.glb)
CN_N = 52
CN_SF = 0.62
CN_STRIDE = 0.15


def _cane(fr):
    n = CN_N
    p = fr / float(n)
    ft = {}
    for side, ph, sx in (("l", 0.0, 1), ("r", 0.5, -1)):
        f, pit = foot_at((p + ph) % 1.0, CN_SF, CN_STRIDE, 0.05, 0.11, sx, 10.0, 12.0)
        ft["foot_" + side] = f
        ft["fpit_" + side] = pit
        ft["fyaw_" + side] = sx * 7.0
    # tip of the cane (planted with the LEFT foot, x = right of the body, ahead of the fist), z = height of the tip
    tip_f, _ = foot_at(p % 1.0, CN_SF, CN_STRIDE, 0.07, 0.30, -1, 0.0, 0.0, y0=-0.30)
    tip = V(tip_f.x, tip_f.y, tip_f.z - 0.104)
    d = 0.22                                       # tip is d ahead of the fist
    hz = math.sqrt(CANE_LEN ** 2 - d ** 2 - 0.03 ** 2)
    grip = V(tip.x + 0.03, tip.y + d, tip.z + hz)
    u = (grip - tip).normalized()                  # thumb axis: from the tip up to the fist
    ho = grip_o("r", tuple(u), (0.0, -1.0, 0.0))
    wr = wrist_at("r", grip, ho)
    sway = 0.028 * math.sin(TAU * p)               # pelvis rolls over the left stance foot first
    bob = -0.010 * math.cos(TAU * 2 * p)
    ql = p
    a = math.cos(TAU * ql)                         # left arm swings a little against the cane arm
    return dict(pel=(sway, 0.02, -0.06 + bob), tor=(19.0, 5.0 * math.sin(TAU * p), 3.0 * math.sin(TAU * p)), hip=(3.0, -5.0 * math.sin(TAU * p), 0.0),
                head=(8.0 + 2.0 * math.cos(TAU * 2 * p), 3.0 * math.sin(TAU * p + 0.4), 0.0), feet=ft,
                R=hsw(wr.x, wr.y, wr.z, ho, 0.95), L=hs(0.29, 0.02 - 0.08 * a, 0.96 + 0.02 * max(0, a), "hang", 0.35))


@life_clip("Life_Walk_Cane", loop=True, category="walk/style", speed_mps=round(2 * CN_STRIDE / (CN_SF * CN_N / 30.0), 3), tags=["elder", "cane"],
           props=[{"id": "cane", "hand": "r"}], events={"plant": [0], "lift": [32], "foot_l": [0], "foot_r": [26]}, blend_in=0.3, blend_out=0.3,
           note="elder walk, bent spine, short shuffling steps, cane in the right hand planted with every LEFT step (tip on the ground from frame 0 to 32, then swings forward). Cane length 0.90 m (measured from cane.glb)")
def _walk_cane():
    return build(frames(CN_N, _cane), CN_N)
