# CHILDREN clips (the same skeleton is scaled to ~1.2 m in game: everything is bouncier, wider, less controlled than the adult
# clips). In-place gaits are built one key per frame from the procedural foot / arm functions below, so the planted foot slides
# back at exactly the ground speed `speed_mps` (= 2 * stride / stance time). speed_mps is in authored (adult-skeleton) metres;
# scale by the child's scale factor for the child's ground speed.
import math
from mathutils import Vector
import combat_common as CC
from combat_common import V
from life_common import life_clip, neutral, sinw
from life_clips_social import (mk, hs, hsw, K, loop, build, feet, addp, addt, addh, addsh, win, smoothstep, OR)

TAU = 2 * math.pi


def foot_at(q, sf, stride, lift, width, sx, heel=14.0, toe=22.0, y0=0.0):
    """ankle target + pitch for a foot at gait phase q (0 = contact); stance sf of the cycle, then a swing that lifts `lift`"""
    if q < sf:
        u = q / sf
        y = -stride + 2 * stride * u
        z = 0.104 + 0.045 * max(0.0, (u - 0.78) / 0.22)
        pit = heel * max(0.0, 1 - u / 0.15) - toe * max(0.0, (u - 0.75) / 0.25)
    else:
        u = (q - sf) / (1 - sf)
        e = 0.5 - 0.5 * math.cos(math.pi * u)
        y = stride - 2 * stride * e
        z = 0.104 + lift * math.sin(math.pi * min(1.0, u * 1.0)) ** 0.9
        pit = -toe * (1 - u) * 0.6 + heel * max(0.0, (u - 0.7) / 0.3)
    return V(sx * width + 0.0, y0 + y, z), pit


def frames(n, fn, ease="lin"):
    """keys from a per-frame kwargs function (fn(fr) -> mk kwargs)"""
    return [(fr, mk(**fn(fr)), ease) for fr in range(n + 1)]


def two_feet(p, sf, stride, lift, width, heel=14.0, toe=22.0, yaw=5.0):
    fl, pl = foot_at(p % 1.0, sf, stride, lift, width, 1, heel, toe)
    fr_, pr = foot_at((p + 0.5) % 1.0, sf, stride, lift, width, -1, heel, toe)
    return {"foot_l": fl, "foot_r": fr_, "fpit_l": pl, "fpit_r": pr, "fyaw_l": yaw, "fyaw_r": -yaw}


# ------------------------------------------------------------------ run
RUN_N = 40                      # two 20-frame strides: the second differs a little (a kid never runs metronomically)
RUN_SF = 0.36
RUN_STRIDE = 0.32


def _run(fr):
    n = RUN_N
    p2 = fr / float(n)                     # 0..1 over the two-stride loop
    p = (p2 * 2.0) % 1.0                   # gait phase (left contact at 0)
    alt = 0.5 + 0.5 * math.cos(TAU * p2)   # 1 on the first stride, 0 on the second
    ft = two_feet(p, RUN_SF, RUN_STRIDE + 0.02 * alt, 0.27 - 0.04 * alt, 0.09, 12.0, 26.0, 6.0)
    ql = p
    qr = (p + 0.5) % 1.0
    bob = -0.035 * math.cos(TAU * 2 * (p - 0.18)) - 0.09
    sway = 0.03 * math.sin(TAU * p)
    args = {}
    for side, q_opp in (("l", qr), ("r", ql)):
        # arm is forward when the OPPOSITE leg is forward at contact; flail = second harmonic + a lagging phase + loose elbows
        a = math.cos(TAU * (q_opp - 0.06))
        b = math.sin(TAU * (2 * q_opp + 0.2 * (1 if side == "l" else -1)))
        fwd = 0.08 + (0.24 + 0.03 * alt) * a + 0.04 * b
        z = 1.02 + 0.13 * max(0.0, a) - 0.05 * max(0.0, -a) + 0.05 * b
        out = 0.38 + 0.06 * math.sin(TAU * (q_opp + 0.25)) + 0.04 * b
        args["L" if side == "l" else "R"] = hs(out, fwd, z, "palm_in", 0.35, e=(out + 0.24, fwd - 0.25, z - 0.06))
    d = dict(pel=(sway, 0.0, bob), tor=(11.0 + 2 * math.cos(TAU * 2 * p), -9.0 * math.cos(TAU * ql), 5.0 * math.sin(TAU * p)),
             hip=(0.0, 7.0 * math.cos(TAU * ql), 0.0),
             head=(-4.0 + 3.0 * math.cos(TAU * 2 * (p - 0.18)), 5.0 * math.cos(TAU * (ql + 0.3)), -5.0 * math.sin(TAU * p)), feet=ft, **args)
    return d


@life_clip("Life_Kid_Run_Play", loop=True, category="kid/play", speed_mps=round(2 * (RUN_STRIDE + 0.01) / (RUN_SF * 20 / 30.0), 3),
           tags=["kid", "excited"], events={"foot_l": [0, 20], "foot_r": [10, 30]}, blend_in=0.2, blend_out=0.2,
           note="excited in-place run: flight phase, high knees, arms flailing loosely, body rolling with every stride, head bobbing. speed_mps on the authored skeleton")
def _kid_run():
    return build(frames(RUN_N, _run), RUN_N)


# ------------------------------------------------------------------ chase the chicken: crouched, grabbing low
CH_N = 56
CH_SF = 0.46
CH_STRIDE = 0.30


def _chase(fr):
    n = CH_N
    p2 = fr / float(n)
    p = (p2 * 2.0) % 1.0
    ft = two_feet(p, CH_SF, CH_STRIDE, 0.16, 0.13, 8.0, 14.0, 8.0)
    bob = -0.03 * math.cos(TAU * 2 * (p - 0.2))
    args = {}
    # one grabbing lunge per arm per double-stride: left arm at p2 ~ 0.2, right arm at p2 ~ 0.7
    for side, c in (("L", 0.2), ("R", 0.7)):
        w = win(fr, c * n - 8, c * n + 8, 4.0, 5.0)
        peak = smoothstep(1 - abs(fr - c * n) / 4.0)
        sw = 0.5 + 0.5 * math.cos(TAU * ((p + (0.5 if side == "L" else 0.0)) % 1.0))
        base_out, base_fwd, base_z = 0.30, 0.20 + 0.06 * sw, 1.22 - 0.05 * sw
        out = base_out * (1 - w) + 0.13 * w
        fwd = base_fwd * (1 - w) + 0.17 * w
        z = base_z * (1 - w) + 1.14 * w
        curl = 0.4 * (1 - w) + (-0.7 * (1 - peak) + 0.95 * peak) * w
        args[side] = hs(out, fwd, z, "down_fwd", curl, e=(out + 0.30, fwd - 0.3, z + 0.05))
    lunge = max(win(fr, 0.2 * n - 8, 0.2 * n + 8, 4.0, 5.0), win(fr, 0.7 * n - 8, 0.7 * n + 8, 4.0, 5.0))
    d = dict(pel=(0.02 * math.sin(TAU * p), 0.05 - 0.09 * lunge, -0.20 + bob - 0.03 * lunge),
             tor=(34.0 + 9.0 * lunge, -10.0 * math.cos(TAU * p), 5.0 * math.sin(TAU * p)), hip=(6.0, 6.0 * math.cos(TAU * p), 0.0),
             head=(-24.0, 4.0 * math.cos(TAU * (p + 0.3)), -4.0 * math.sin(TAU * p)), feet=ft, **args)
    return d


@life_clip("Life_Kid_Chase_Chicken", loop=True, category="kid/play", speed_mps=round(2 * CH_STRIDE / (CH_SF * 28 / 30.0), 3),
           tags=["kid", "chase"], events={"grab_l": [11], "grab_r": [39]}, blend_in=0.2, blend_out=0.2,
           note="crouched scurrying run, head up on the target, one low two-handed-style grab lunge per arm every second stride")
def _kid_chase():
    return build(frames(CH_N, _chase), CH_N)


# ------------------------------------------------------------------ skip
SK_N = 36
SK_STRIDE = 0.26


def _skip(fr):
    n = SK_N
    p = fr / float(n)
    ft = {}
    pl = p % 1.0
    for side, ph, sx in (("l", 0.0, 1), ("r", 0.5, -1)):
        q = (p + ph) % 1.0
        # step-hop: the foot lands (q = 0), slides back through the stance while a small hop lifts it clear at q ~ 0.33-0.46,
        # then the free leg swings forward with a high knee
        if q < 0.5:
            u = q / 0.5
            y = -SK_STRIDE + 2 * SK_STRIDE * u
            z = 0.104 + 0.10 * math.sin(math.pi * max(0.0, min(1.0, (q - 0.30) / 0.16))) ** 0.8 if 0.30 < q < 0.46 else 0.104
            pit = 10.0 * max(0.0, 1 - u / 0.2) - 18.0 * max(0.0, (u - 0.6) / 0.4)
        else:
            u = (q - 0.5) / 0.5
            e = 0.5 - 0.5 * math.cos(math.pi * u)
            y = SK_STRIDE - 2 * SK_STRIDE * e
            z = 0.104 + 0.26 * math.sin(math.pi * u) ** 0.9
            pit = -14.0 * (1 - u) + 8.0 * u * u
        ft["foot_" + side] = V(sx * 0.09, y, z)
        ft["fpit_" + side] = pit
        ft["fyaw_" + side] = sx * 5.0
    bob = 0.05 * math.cos(TAU * 2 * (p - 0.37 + 0.0)) - 0.005
    args = {}
    for side, q_opp in (("L", (p + 0.5) % 1.0), ("R", p % 1.0)):
        a = math.cos(TAU * q_opp)
        hop = max(0.0, math.cos(TAU * 2 * (q_opp - 0.37)))
        fwd = 0.08 + 0.30 * a
        z = 1.04 + 0.12 * max(0.0, a) + 0.10 * hop
        out = 0.34 + 0.05 * hop
        args[side] = hs(out, fwd, z, "palm_in", 0.3, e=(out + 0.22, fwd - 0.22, z - 0.08))
    return dict(pel=(0.025 * math.sin(TAU * p), 0.0, bob - 0.03), tor=(6.0, -7.0 * math.cos(TAU * p), 4.0 * math.sin(TAU * p)), hip=(0.0, 6.0 * math.cos(TAU * p), 0.0),
                head=(-2.0, 3.0 * math.cos(TAU * p), -6.0 * math.sin(TAU * p) + 2.0 * math.cos(TAU * 2 * p)), feet=ft, **args)


@life_clip("Life_Kid_Skip", loop=True, category="kid/play", speed_mps=round(2 * SK_STRIDE / (0.5 * SK_N / 30.0), 3),
           tags=["kid", "happy"], events={"foot_l": [0], "foot_r": [18]}, blend_in=0.2, blend_out=0.2,
           note="in-place skipping: long-short step-hop rhythm, the free knee lifts high, arms swing wide, head rolls with the beat")
def _kid_skip():
    return build(frames(SK_N, _skip), SK_N)


# ------------------------------------------------------------------ tag: lunge, touch, flee
@life_clip("Life_Kid_Tag_Touch", category="kid/play", events={"lunge": [14], "touch": [17], "flee": [34]}, blend_in=0.15, blend_out=0.25,
           note="one-shot: coiled crouch, lunge with an outstretched hand (touch at frame 17: partner is ~0.75 m ahead), gleeful recoil, twists away and bolts; back to neutral")
def _kid_tag():
    n = 66
    ftc = feet((0.14, 0.02), (-0.14, 0.14), 10.0, -14.0)
    ftl = feet((0.13, -0.32), (-0.12, 0.18), 6.0, -12.0, zr=0.106)
    ftl_r = dict(ftl, foot_l=V(0.13, -0.34, 0.104))
    ftf = feet((0.20, -0.05), (-0.12, 0.34), 60.0, 10.0, zr=0.16)
    hand_r = lambda fw, z, c=-0.6: hs(0.12, fw, z, "palm_dn", c)
    k = [
        K(0),
        K(8, "smooth", pel=(0.0, 0.05, -0.16), tor=(20, 8, 0), hip=(0, 0, 0), head=(-10, 4, 0), feet=ftc,
          R=hs(0.30, 0.06, 1.0, "hang", 0.7), L=hs(0.32, 0.05, 1.03, "hang", 0.6)),
        K(14, "out2", bow={"hand_r": V(0, 0, 0.04)}, pel=(-0.02, -0.28, -0.14), tor=(28, -4, 0), hip=(6, 0, 0), head=(-8, 0, 0), feet=ftl,
          R=hand_r(0.30, 1.20), L=hs(0.34, -0.06, 0.98, "hang", 0.7)),
        K(17, "out2", pel=(-0.02, -0.33, -0.15), tor=(31, -4, 0), hip=(8, 0, 0), head=(-6, 0, 0), feet=ftl_r,
          R=hand_r(0.33, 1.20), L=hs(0.36, -0.08, 0.98, "hang", 0.7)),
        K(24, "smooth", pel=(0.0, -0.15, -0.06), tor=(14, 4, 0), hip=(0, 0, 0), head=(4, 8, 4), feet=dict(ftl, foot_l=V(0.13, -0.20, 0.104)),
          R=hs(0.34, 0.16, 1.22, "stop", -0.5, e=(0.44, 0.0, 1.10)), L=hs(0.36, 0.08, 1.20, "stop", -0.5), sh=(6, 6)),
        K(34, "smooth", pel=(0.02, 0.0, -0.18), tor=(22, 42, 6), hip=(0, 30, 0), head=(-6, 70, 0), feet=ftf,
          R=hs(0.26, 0.10, 1.04, "hang", 0.5), L=hs(0.34, 0.03, 1.10, "hang", 0.5)),
        K(44, "out2", pel=(0.02, 0.06, -0.06), tor=(16, 24, 3), hip=(0, 18, 0), head=(-4, 40, 0), feet=dict(ftf, foot_r=V(-0.14, 0.16, 0.104), foot_l=V(0.18, -0.02, 0.104)),
          R=hs(0.30, 0.20, 1.06, "hang", 0.5), L=hs(0.34, 0.08, 1.08, "hang", 0.5)),
        K(56, "smooth", pel=(0.0, 0.0, -0.01), tor=(6, 4, 0), hip=(0, 4, 0), head=(2, 8, 0), feet=feet(),
          R=hs(0.28, 0.02, 0.94, "hang", 0.3), L=hs(0.28, 0.02, 0.94, "hang", 0.3)),
        K(n),
    ]

    def post(fr, nn, s):
        # a giggling bounce after the tag
        e = win(fr, 20, 46, 3, 6)
        v = math.sin(TAU * 4 * fr / 30.0)
        addp(s, V(0, 0, 0.012 * v * e))
        addsh(s, 2 * v * e, 2 * v * e)
    return build(k, n, post=post)


# ------------------------------------------------------------------ hopscotch (in place)
def _hop(f, sup, h=0.13, free_back=0.30, dur=16):
    """keys for one single-leg hop on foot `sup` starting at frame f: crouch, launch, apex, land, settle"""
    fr_free = "r" if sup == "l" else "l"
    sx_s = 1 if sup == "l" else -1
    sx_f = -sx_s
    stand = feet()
    fs = lambda z, off=0.0: {"foot_" + sup: V(sx_s * 0.09, off, z), "fyaw_" + sup: sx_s * 4.0, "fpit_" + sup: 0.0,
                             "foot_" + fr_free: V(sx_f * 0.10, free_back, 0.36), "fyaw_" + fr_free: sx_f * 4.0, "fpit_" + fr_free: -25.0}
    arms = lambda z: dict(L=hs(0.40, 0.06, z, "hang", 0.3), R=hs(0.40, 0.06, z, "hang", 0.3))
    return [
        K(f, "smooth", pel=(sx_s * 0.03, 0, -0.06), tor=(10, 0, 0), head=(-4, 0, 0), feet=fs(0.104), **arms(0.97), sh=(0, 0)),
        K(f + 5, "out2", pel=(sx_s * 0.02, 0, h - 0.02), tor=(4, 0, 0), head=(-3, 0, 0), feet=fs(0.104 + h), **arms(1.14), sh=(6, 6)),
        K(f + 9, "smooth", pel=(sx_s * 0.02, 0, h - 0.01), tor=(4, 0, 0), head=(-3, 0, 0), feet=fs(0.104 + h * 0.85), **arms(1.16), sh=(6, 6)),
        K(f + 12, "in2", pel=(sx_s * 0.03, 0, -0.07), tor=(12, 0, 0), head=(3, 0, 0), feet=fs(0.104), **arms(0.97)),
        K(f + dur, "smooth", pel=(sx_s * 0.03, 0, -0.02), tor=(6, 0, 0), head=(0, 0, 0), feet=fs(0.104), **arms(0.97)),
    ]


@life_clip("Life_Kid_Hopscotch", category="kid/play", events={"land": [16, 36, 58, 90, 109, 124]}, blend_in=0.2, blend_out=0.25,
           note="one-shot in place: hop, hop on the left foot, straddle-jump landing on both, hop, hop on the right foot, jump turn and land; neutral at both ends")
def _kid_hopscotch():
    n = 132
    k = [K(0)]
    k += _hop(4, "l")
    k += _hop(24, "l")
    # straddle jump: both feet off, land wide apart, arms out for balance
    wide = feet((0.30, 0.0), (-0.30, 0.0), 20.0, -20.0)
    air = feet((0.16, 0.05), (-0.16, 0.05), 6.0, -6.0, zl=0.28, zr=0.28)
    k += [
        K(48, "smooth", pel=(0, 0, -0.10), tor=(14, 0, 0), head=(-4, 0, 0), feet=feet(), L=hs(0.36, 0.0, 0.97, "hang", 0.3), R=hs(0.36, 0.0, 0.97, "hang", 0.3)),
        K(53, "out2", pel=(0, 0, 0.17), tor=(2, 0, 0), head=(-4, 0, 0), feet=air, L=hs(0.44, 0.10, 1.20, "palm_dn", -0.3), R=hs(0.44, 0.10, 1.20, "palm_dn", -0.3), sh=(6, 6)),
        K(58, "in2", pel=(0, 0, -0.16), tor=(14, 0, 0), head=(4, 0, 0), feet=wide, L=hs(0.48, 0.10, 1.04, "palm_dn", -0.3), R=hs(0.48, 0.10, 1.04, "palm_dn", -0.3)),
        K(64, "out2", pel=(0, 0, -0.14), tor=(12, 0, 0), head=(0, 0, 0), feet=wide, L=hs(0.50, 0.08, 1.06, "palm_dn", -0.3), R=hs(0.50, 0.08, 1.06, "palm_dn", -0.3)),
        K(74, "smooth", pel=(0, 0, -0.04), tor=(6, 0, 0), head=(0, 0, 0), feet=feet(), L=hs(0.34, 0.02, 0.94, "hang", 0.3), R=hs(0.34, 0.02, 0.94, "hang", 0.3)),
    ]
    k += _hop(78, "r")
    k += _hop(97, "r")
    # jump turn: the chest and head lead, the feet follow, land a quarter turn round then untwist
    turn_air = feet((0.16, 0.02), (-0.16, 0.02), 40.0, 20.0, zl=0.28, zr=0.28)
    turn_land = feet((0.18, 0.0), (-0.10, 0.10), 60.0, 30.0)
    k += [
        K(115, "smooth", pel=(0, 0, -0.10), tor=(12, -14, 0), hip=(0, -10, 0), head=(-2, -20, 0), feet=feet(), L=hs(0.36, 0.0, 0.97, "hang", 0.3), R=hs(0.36, 0.0, 0.97, "hang", 0.3)),
        K(120, "out2", pel=(0, 0, 0.18), tor=(3, 26, 0), hip=(0, 30, 0), head=(-2, 54, 0), feet=turn_air, L=hs(0.44, 0.06, 1.16, "palm_dn", -0.3), R=hs(0.44, 0.06, 1.16, "palm_dn", -0.3), sh=(6, 6)),
        K(124, "in2", pel=(0, 0, -0.10), tor=(10, 22, 0), hip=(0, 26, 0), head=(4, 44, 0), feet=turn_land, L=hs(0.46, 0.06, 1.0, "palm_dn", -0.3), R=hs(0.46, 0.06, 1.0, "palm_dn", -0.3)),
        K(129, "smooth", pel=(0, 0, -0.02), tor=(5, 4, 0), hip=(0, 4, 0), head=(0, 8, 0), feet=feet(), L=hs(0.30, 0.02, 0.94, "hang", 0.3), R=hs(0.30, 0.02, 0.94, "hang", 0.3)),
        K(n),
    ]
    k = sorted(k, key=lambda x: x[0])
    return build(k, n)


# ------------------------------------------------------------------ clap jump
@life_clip("Life_Kid_Clap_Jump", category="kid/play", events={"takeoff": [10], "clap": [16], "land": [22]}, blend_in=0.15, blend_out=0.25,
           note="one-shot: crouch, jump with both arms swinging up to clap overhead at the apex, land bouncy, small second clap of joy")
def _kid_clap_jump():
    n = 54
    air = feet((0.13, 0.02), (-0.13, 0.05), 6.0, -6.0, zl=0.30, zr=0.32, pl=-25.0, pr=-25.0)
    clap = lambda z=1.90, o=0.06: dict(L=hsw(o, -0.10, z, ((-0.1, 0, 1), (-1, 0, 0)), -0.4), R=hsw(-o, -0.10, z, ((0.1, 0, 1), (1, 0, 0)), -0.4))
    k = [
        K(0),
        K(8, "smooth", pel=(0, 0.02, -0.15), tor=(16, 0, 0), head=(-6, 0, 0), L=hs(0.24, -0.10, 0.98, "hang", 0.4), R=hs(0.24, -0.10, 0.98, "hang", 0.4)),
        K(11, "out2", pel=(0, 0, 0.02), tor=(0, 0, 0), head=(-14, 0, 0), L=hs(0.44, 0.10, 1.30, "palm_in", -0.2), R=hs(0.44, 0.10, 1.30, "palm_in", -0.2), feet=feet(zl=0.12, zr=0.12), sh=(6, 6)),
        K(16, "out2", pel=(0, 0, 0.17), tor=(-3, 0, 0), head=(-18, 0, 0), feet=air, **clap(), sh=(8, 8)),
        K(19, "smooth", pel=(0, 0, 0.15), tor=(-2, 0, 0), head=(-14, 0, 0), feet=air, **clap(1.86), sh=(8, 8)),
        K(23, "in2", pel=(0, 0, -0.13), tor=(14, 0, 0), head=(4, 0, 0), L=hs(0.30, 0.04, 0.96, "hang", 0.4), R=hs(0.30, 0.04, 0.96, "hang", 0.4)),
        K(28, "out2", pel=(0, 0, 0.0), tor=(6, 0, 0), head=(-2, 0, 0), L=hs(0.14, 0.34, 1.16, "palm_in", -0.3), R=hs(0.14, 0.34, 1.16, "palm_in", -0.3)),
        K(32, "smooth", pel=(0, 0, -0.02), tor=(6, 0, 0), head=(2, 0, 0), L=hs(0.06, 0.34, 1.16, "palm_in", -0.3), R=hs(0.06, 0.34, 1.16, "palm_in", -0.3)),
        K(36, "smooth", pel=(0, 0, -0.03), tor=(8, 0, 0), head=(2, 0, 0), L=hs(0.15, 0.32, 1.12, "palm_in", -0.3), R=hs(0.15, 0.32, 1.12, "palm_in", -0.3)),
        K(44, "smooth", pel=(0, 0, 0), tor=(3, 0, 0), head=(0, 0, 0), L=hs(0.28, 0.04, 0.94, "hang", 0.3), R=hs(0.28, 0.04, 0.94, "hang", 0.3)),
        K(n),
    ]
    return build(k, n)
