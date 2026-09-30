# LIFE work clips, part 2: smithing, carpentry, wood cutting, fishing (uses the work kit in life_clips_farm.py).
import math
from mathutils import Vector
from combat_common import V
import life_common as LC
from life_common import grip_of
from life_clips_farm import (S, P, wp, ez, pulse, sw, cw, mix, stance, grips, tool2, fit, from_tip, sag_K, HOw, hand1, at_sh,
                             breath, work_clip, LEN, shoulder, XAX, edge_G)


def imp(fr, cs, a=2.0, b=7.0):
    """impact envelope: ramps up over `a` frames before each contact frame, decays over `b` frames after"""
    m = 0.0
    for c in cs:
        d = fr - c
        if -a <= d <= 0:
            m = max(m, 1.0 + d / a)
        elif 0 < d < b:
            m = max(m, (1.0 - d / b) ** 2)
    return m


# ======================================================================================== SMITH
ANV_Z = 0.80          # work piece on the anvil top (anvil 0.78)
ANV_Y = 0.56


def smith_hammer(fr, n):
    L = LEN["smith_hammer"] + 0.03
    T = P(0.02, ANV_Y, ANV_Z)
    Gr, _ = from_tip(T, 118, L)
    Gc, _ = from_tip(T, 128, L)
    up = lambda dz, dy=0.0: Gr + V(0, -dy, dz)
    KG = [(0, Gr), (3, Gr + V(0, 0.03, -0.02), "smooth"), (13, P(-0.04, 0.12, 1.40), "smooth"), (14, P(-0.04, 0.11, 1.42), "smooth"),
          (20, Gc, "in2"), (24, Gc + V(0, 0.01, 0.13), "out2"), (31, P(-0.03, 0.16, 1.30), "smooth"), (32, P(-0.03, 0.16, 1.31), "smooth"),
          (36, Gc, "in2"), (40, Gc + V(0, 0.01, 0.10), "out2"), (46, Gc, "in2"), (50, Gc + V(0, 0.005, 0.08), "out2"),
          (56, Gc, "in2"), (60, Gc + V(0, 0.005, 0.06), "out2"), (66, Gr, "smooth"), (72, Gr)]
    KT = [(0, 118.0), (3, 122.0), (13, 28.0), (14, 24.0), (20, 128.0, "in2"), (24, 100.0, "out2"), (31, 35.0), (32, 32.0),
          (36, 128.0, "in2"), (40, 108.0, "out2"), (46, 128.0, "in2"), (50, 112.0, "out2"), (56, 128.0, "in2"), (60, 116.0, "out2"),
          (66, 118.0), (72, 118.0)]
    G = wp(KG, fr)
    th = wp(KT, fr)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    cs = (20, 36, 46, 56)
    e = imp(fr, cs)
    s = S()
    stance(s, 0.16, -0.16, -0.17, 0.14, 10.0, -26.0)
    s["pel"] = V(0.0, -0.01 * e, -0.06 - 0.025 * e)
    s["hip"] = (6.0, 8.0, 0.0)
    s["tor"] = (6.0 + 4.0 * e, -8.0, 0.0)
    s["head"] = (12.0, 4.0, 0.0)
    # tongs: hold the work steady, jolt on every blow
    Tl = P(0.05, ANV_Y + 0.04, ANV_Z - 0.005) + V(0.0, 0.0, -0.007 * e) + V(0.004 * sw(fr, n, 5), 0, 0)
    Dl = V(0.05, -0.95, -0.28).normalized()
    grips(s, [("l", Tl - Dl * (LEN["tongs"] + 0.05), Dl, sag_K(Dl))], fitlean=False)
    grips(s, [("r", G, D, sag_K(D))], fitlean=True, headk=0.15, lmax=50)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Smith_Hammer", 72, smith_hammer, loop=True, enter_exit=True, category="work/smith",
          props=[{"id": "smith_hammer", "hand": "r"}, {"id": "tongs", "hand": "l"}],
          anchor={"type": "anvil", "at": [0.0, ANV_Y, 0.78], "size": [0.30, 0.70, 0.78]},
          events={"contact": [20, 36, 46, 56]},
          note="heavy blow, medium blow, two light rebound taps; tongs hold the work and jolt on each hit",
          tr={"dip": 0.03})


def smith_quench(fr, n):
    """one shot (neutral -> neutral): lift the work on the tongs, swing to the trough at the left, dip, steam lean-back, lift out"""
    L = LEN["tongs"] + 0.05
    trough = P(0.44, 0.34, 0.62)             # jaws in the water
    hover = P(0.44, 0.34, 0.92)
    s = S()
    stance(s, 0.15, -0.06, -0.14, 0.08, 6.0, -10.0)
    Gn = grip_of("l", P(0.27, 0.07, 0.915), ((0.05, 0.0, -1.0), (-1.0, 0.0, 0.0)))
    jaw = wp([(0, Gn + V(0, -L, 0.0)), (14, hover + V(-0.10, 0.10, 0.0), "smooth"), (22, hover, "smooth"), (30, trough, "in2"),
              (34, trough - V(0, 0, 0.02), "out2"), (46, trough + V(0.02, 0.0, 0.0), "smooth"), (54, hover + V(0, 0, 0.02), "smooth"),
              (64, hover + V(-0.10, 0.10, -0.1), "smooth"), (74, Gn + V(0, -L, 0.0), "smooth")], fr)
    Dv = wp([(0, V(0.0, -1.0, 0.0)), (14, V(0.15, -0.6, -0.2)), (30, V(0.2, -0.45, -0.87)), (46, V(0.2, -0.45, -0.87)),
             (60, V(0.15, -0.6, -0.2)), (74, V(0.0, -1.0, 0.0))], fr).normalized()
    steam = pulse(fr, 28, 33, 40, 50)
    lean = wp([(0, 0.0), (22, 6.0), (30, 10.0), (34, -14.0, "out2"), (46, -8.0), (60, 0.0), (74, 0.0)], fr)
    yaw = wp([(0, 0.0), (14, 18.0), (30, 24.0), (54, 20.0), (74, 0.0)], fr)
    s["pel"] = V(0.02 * yaw / 20.0, 0.0, -0.03 * pulse(fr, 8, 22, 54, 66))
    s["hip"] = (0.0, yaw * 0.35, 0.0)
    s["tor"] = (2.0 + lean, yaw * 0.65, 0.0)
    s["head"] = (6.0 - 20.0 * steam * (fr > 33), 6.0 * steam, 0.0)
    active = pulse(fr, 0, 10, 60, 74)
    Gl = jaw - Dv * L
    Gl = Gl.lerp(Gn, 1.0 - active) if False else Gl
    grips(s, [("l", Gl, Dv, sag_K(Dv), 0.5 + 0.45 * active)], fitlean=False)
    # right hand: guard / balance (raised to the chest when the steam comes)
    hr = P(-0.27, 0.07, 0.915).lerp(P(-0.22, 0.24, 1.25), steam)
    hand1(s, "r", hr, HOw([(0, ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0))), (40, ((0.0, -0.7, 0.7), (0.5, 0.0, 0.3)))], 40 * steam), 0.3 - 0.4 * steam)
    if fr <= 6 or fr >= 68:
        pass
    fit(s, rmax=0.5, headk=0.0, lmax=25)
    return s


def _quench_poses():
    from life_clips_farm import poses
    n = 74
    return poses(lambda fr: smith_quench(fr, n), n)


LC.life_clip("Life_Smith_Quench", loop=False, category="work/smith", props=[{"id": "tongs", "hand": "l"}],
             anchor={"type": "trough", "at": [0.44, 0.34, 0.62], "size": [0.6, 0.4, 0.62]},
             events={"dip": [30], "steam": [34], "lift": [50]},
             note="one shot: work on the tongs to the trough at the left, dip, lean back from the steam, lift out")(_quench_poses)


def bellows(fr, n):
    z = wp([(0, 1.13), (24, 0.76, "smooth"), (29, 0.74), (53, 1.13, "smooth"), (60, 1.13)], fr)
    fwd = 0.42 - 0.07 * (1.13 - z) / 0.4
    d = (1.13 - z) / 0.4
    s = S()
    stance(s, 0.16, -0.06, -0.16, 0.10, 8.0, -12.0)
    s["pel"] = V(0, 0.02 - 0.03 * d, -0.04 - 0.05 * d)
    s["hip"] = (6.0 + 8.0 * d, 0.0, 0.0)
    s["tor"] = (8.0, 0.0, 0.0)
    s["head"] = (8.0 + 3.0 * sw(fr, n, 1, 0.2), 4.0 * sw(fr, n, 1, 0.4), 0.0)
    Kb = V(0, -0.5, -0.85)
    grips(s, [("r", P(-0.14, fwd, z), V(1, 0, 0), Kb), ("l", P(0.14, fwd, z), V(-1, 0, 0), Kb)], fitlean=True, headk=0.1, lmax=45)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Smith_Bellows", 60, bellows, loop=True, category="work/smith", props=[{"id": "bellows_handle", "hand": "r"}],
          anchor={"type": "bellows", "at": [0.0, 0.50, 0.90], "size": [0.6, 0.5, 0.9]}, events={"push": [24], "pull": [53]},
          note="both hands on a bar, down stroke with the body weight, lighter return; the knees dip on the down stroke")


# ======================================================================================== CARPENTRY
def carp_saw(fr, n):
    m = n // 2
    i = fr % n
    c, sub = i // m, i - (i // m) * m
    amp = (0.10, 0.13)[c]
    kerf = P(-0.10, 0.50, 0.60)
    th = 122.0
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    off = wp([(0, -amp), (20, amp, "smooth"), (36, -amp, "smooth")], sub)
    push = (off + amp) / (2 * amp)
    G = kerf - D * 0.27 + D * off + V(0, 0, -0.012 * (1 - abs(2 * push - 1) * 0) * (1.0 if 4 < sub < 20 else 0.0))
    s = S()
    stance(s, 0.17, -0.20, -0.17, 0.16, 12.0, -28.0)
    s["pel"] = V(0.0, -0.045 * push, -0.08)
    s["hip"] = (10.0, 10.0 * (push - 0.5), 0.0)
    s["tor"] = (8.0 + 5.0 * push, -14.0 + 6.0 * push, 0.0)
    s["head"] = (12.0, 6.0, 0.0)
    hand1(s, "l", P(0.10, 0.42 + 0.004 * sw(fr, n, 2), 0.63), ((0.0, -1.0, -0.1), (0.0, 0.0, -1.0)), 0.1)
    grips(s, [("r", G, D, sag_K(D))], fitlean=True, headk=0.1, lmax=55)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Carp_Saw", 72, carp_saw, loop=True, enter_exit=True, category="work/carpentry", props=[{"id": "saw", "hand": "r"}],
          anchor={"type": "sawhorse", "at": [0.0, 0.50, 0.60], "size": [0.30, 0.90, 0.60]}, events={"push": [20, 56], "pull": [2, 38]},
          note="two strokes per cycle (the second is longer), push on the forward stroke with hip drive; left hand braces the plank",
          tr={"dip": 0.03})


def carp_nail(fr, n):
    T = P(0.06, 0.40, 0.10)                    # nail head, the plank lies on the ground
    L = LEN["hammer"] + 0.02
    Gr, _ = from_tip(T, 150, L)
    Gc, _ = from_tip(T, 158, L)
    KG = [(0, Gr), (8, Gr + V(0.0, 0.05, 0.20), "smooth"), (12, Gc, "in2"), (14, Gc + V(0, 0, 0.06), "out2"), (22, Gr + V(0, 0.08, 0.32), "smooth"),
          (27, Gc, "in2"), (30, Gc + V(0, 0, 0.07), "out2"), (44, Gr + V(0, 0.12, 0.42), "smooth"), (45, Gr + V(0, 0.12, 0.43), "smooth"),
          (50, Gc + V(0, 0, -0.005), "in2"), (54, Gc + V(0, 0, 0.05), "out2"), (62, Gr, "smooth"), (72, Gr)]
    KT = [(0, 150.0), (8, 105.0), (12, 158.0, "in2"), (14, 140.0, "out2"), (22, 90.0), (27, 158.0, "in2"), (30, 138.0, "out2"),
          (44, 70.0), (45, 68.0), (50, 158.0, "in2"), (54, 140.0, "out2"), (62, 150.0), (72, 150.0)]
    G = wp(KG, fr)
    th = wp(KT, fr)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    e = imp(fr, (12, 27, 50), 2, 5)
    s = S()
    # kneel on the right knee, left foot forward
    s["foot_l"] = V(0.15, -0.30, 0.104)
    s["fyaw_l"] = 8.0
    s["foot_r"] = V(-0.13, 0.32, 0.20)
    s["fyaw_r"] = 0.0
    s["fpit_r"] = -75.0
    s["pel"] = V(0.02, 0.10, -0.60 - 0.006 * e)
    s["hip"] = (30.0, 8.0, 0.0)
    s["tor"] = (8.0 + 3.0 * e, -6.0, 0.0)
    s["head"] = (16.0, 0.0, 0.0)
    hand1(s, "l", P(0.10, 0.36, 0.17 - 0.004 * e), ((0.0, -0.35, -0.93), (-1.0, 0.0, 0.0)), 0.75)
    grips(s, [("r", G, D, sag_K(D))], fitlean=True, headk=0.05, lmax=40)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Carp_Nail", 72, carp_nail, loop=True, enter_exit=True, n_enter=26, n_exit=24, category="work/carpentry",
          props=[{"id": "hammer", "hand": "r"}], anchor={"type": "plank", "at": [0.06, 0.40, 0.05], "size": [0.3, 1.0, 0.05]},
          events={"contact": [12, 27, 50]}, note="kneeling on the right knee, three blows: seat, drive, heavy finish",
          tr={"lift": 0.05, "dip": 0.0, "sway": 0.03, "t_body": (0.15, 0.95), "t_hands": (0.45, 1.0), "t_feet": (0.05, 0.7)})


def carry_plank(fr, n):
    s = S()
    Gr = P(-0.20, 0.02, 1.58) + V(0.003 * sw(fr, n, 2), 0.0, 0.004 * sw(fr, n))
    hand1(s, "r", Gr, ((-1.0, 0.0, 0.0), (0.0, 0.0, -1.0)), 0.9)
    hand1(s, "l", P(-0.12, 0.30, 1.50), ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)), 0.8)
    s["tor"] = (2.0, 0.0, 3.0)
    s["head"] = (0.0, 0.0, -3.0)
    s["shrug_r"] = 8.0
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Carry_Plank_Upper", 60, carry_plank, loop=True, category="carry/upper", layer="upper",
          props=[{"id": "plank", "hand": "r"}], ik_l_on_prop=0.3,
          note="long plank on the right shoulder, right hand on top, left hand steadies it 0.3 m ahead")


# ======================================================================================== WOOD
AXE_LH, AXE_LB, AXE_DL = 0.42, 0.17, -0.22      # axe.glb: head centre 0.42 m along the handle, edge 0.17 m along K


def wood_chop(fr, n):
    Ec = P(0.0, 0.52, 0.60)                      # the log top
    Gc = edge_G(Ec, 95, AXE_LH, AXE_LB)          # at the strike the handle is ~horizontal and the edge points DOWN
    Gb = edge_G(Ec + V(0, 0, -0.025), 100, AXE_LH, AXE_LB)
    Gf = edge_G(P(0.0, 0.44, 0.72), 120, AXE_LH, AXE_LB)
    KG = [(0, P(-0.02, 0.30, 1.12)), (9, P(-0.02, 0.22, 1.30), "smooth"), (18, P(-0.02, 0.02, 1.80), "smooth"),
          (21, P(-0.02, -0.02, 1.86), "smooth"), (27, Gc, "in2"), (30, Gb, "out2"), (34, Gb + V(0, 0, 0.005), "smooth"),
          (44, Gf, "smooth"), (58, P(-0.02, 0.34, 1.10), "smooth"), (66, P(-0.02, 0.32, 1.10), "smooth"), (72, P(-0.02, 0.30, 1.12), "smooth")]
    KT = [(0, 62.0), (9, 30.0), (18, -35.0), (21, -42.0), (27, 95.0, "in2"), (30, 100.0, "out2"), (34, 100.0), (44, 120.0),
          (58, 66.0), (72, 62.0)]
    G = wp(KG, fr)
    th = wp(KT, fr)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    e = imp(fr, (27,), 1, 8)
    up = pulse(fr, 3, 18, 22, 27)
    s = S()
    stance(s, 0.20, -0.10, -0.18, 0.17, 14.0, -30.0)
    s["pel"] = V(0.0, 0.06 * up - 0.03 * e, -0.09 + 0.05 * up - 0.03 * e)
    s["hip"] = (4.0 - 6.0 * up, 0.0, 0.0)
    s["tor"] = (4.0 - 12.0 * up + 4.0 * e, 0.0, 0.0)
    s["head"] = (8.0 - 8.0 * up, 0.0, 0.0)
    tool2(s, G, D, sag_K(D), AXE_DL, headk=0.05, lmax=50)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Wood_Chop", 72, wood_chop, loop=True, enter_exit=True, category="work/wood", props=[{"id": "axe", "hand": "r"}],
          ik_l_on_prop=AXE_DL, anchor={"type": "chopping_block", "at": [0.0, 0.52, 0.45], "size": [0.4, 0.4, 0.45]},
          events={"contact": [27], "free": [44]}, note="lean back with the axe overhead, drop the weight, bite, lever the axe free",
          tr={"dip": 0.03})


def place_log(fr, n):
    s = S()
    stance(s, 0.15, -0.02, -0.15, 0.06, 6.0, -8.0)
    ground = P(0.0, 0.36, 0.26)
    block = P(0.0, 0.48, 0.63)
    chest = P(0.0, 0.28, 0.98)
    c = wp([(0, P(0.0, 0.10, 0.90)), (14, ground + V(0, 0, 0.10), "smooth"), (18, ground, "smooth"), (22, ground + V(0, 0, 0.005)),
            (36, chest, "smooth"), (46, block + V(0, 0, 0.04), "smooth"), (50, block, "smooth"), (54, block + V(0, 0, 0.005)),
            (62, P(0.0, 0.30, 0.90), "smooth"), (72, P(0.0, 0.10, 0.90), "smooth")], fr)
    w = 0.13 + 0.03 * pulse(fr, 8, 14, 20, 24) + 0.03 * pulse(fr, 46, 50, 56, 62)   # half width between the hands (opens to release)
    grab = pulse(fr, 12, 18, 52, 58)
    bend = pulse(fr, 0, 14, 20, 34) + 0.5 * pulse(fr, 34, 40, 48, 54)
    s["pel"] = V(0.0, 0.10 * bend, -0.30 * bend - 0.03 * pulse(fr, 40, 46, 52, 58))
    s["hip"] = (34.0 * bend + 4.0, 0.0, 0.0)
    s["tor"] = (5.0, 0.0, 0.0)
    s["head"] = (8.0, 0.0, 0.0)
    cl = 0.25 + 0.7 * grab
    ho_r = ((0.0, -0.6, -0.6), (1.0, 0.0, 0.0))
    ho_l = ((0.0, -0.6, -0.6), (-1.0, 0.0, 0.0))
    idle_r = P(-0.27, 0.07, 0.915)
    idle_l = P(0.27, 0.07, 0.915)
    ah = pulse(fr, 0, 12, 60, 72)
    hand1(s, "r", idle_r.lerp(c + V(-w, 0, 0), ah), ho_r if ah > 0.5 else ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0)), cl)
    hand1(s, "l", idle_l.lerp(c + V(w, 0, 0), ah), ho_l if ah > 0.5 else ((0.05, 0.0, -1.0), (-1.0, 0.0, 0.0)), cl)
    fit(s, rmax=0.455, headk=0.0, lmax=65)
    return s


LC.life_clip("Life_Wood_Place_Log", loop=False, category="work/wood", anchor={"type": "chopping_block", "at": [0.0, 0.48, 0.45], "size": [0.4, 0.4, 0.45]},
             events={"pick": [18], "place": [50], "release": [54]},
             note="one shot: squat to the log on the ground, lift it to the chest, set it upright on the block, release (the log is a scene prop)")(
    lambda: __import__("life_clips_farm").poses(lambda fr: place_log(fr, 72), 72))


# ======================================================================================== FISHING
FISH_D = V(0, -0.87, 0.50)


def fish_idle(fr, n):
    tipbob = 1.6 * sw(fr, n, 1, 0.2) + 0.9 * sw(fr, n, 3, 0.7)
    nibble = pulse(fr, 50, 52, 54, 60) * 2.0 * sw(fr, n, 6)
    th = 76.0 + tipbob + nibble
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    s = S()
    stance(s, 0.15, -0.02, -0.15, 0.08, 6.0, -12.0)
    s["pel"] = V(0.008 * sw(fr, n, 1), 0.0, -0.01)
    s["tor"] = (3.0, 4.0 * sw(fr, n, 1, 0.1), 0.0)
    s["head"] = (5.0 + 2.0 * sw(fr, n, 2), 8.0 * sw(fr, n, 1, 0.6) * pulse(fr, 10, 25, 50, 70), 0.0)
    Gr = P(-0.17, 0.27, 1.06) + V(0.004 * sw(fr, n, 2), 0, 0.006 * sw(fr, n, 3))
    tool2(s, Gr, D, sag_K(D), -0.30, fitlean=False)
    fit(s, rmax=0.5, headk=0.0, lmax=15)
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Fish_Idle_Rod", 90, fish_idle, loop=True, category="work/fish", props=[{"id": "fishing_rod", "hand": "r"}],
          ik_l_on_prop=-0.30, note="rod held out over the water, tiny bobbing, a glance to the side, a nibble twitch")


def fish_cast(fr, n):
    Gi = P(-0.17, 0.27, 1.06)
    KG = [(0, Gi), (4, Gi + V(0, 0.02, -0.03), "smooth"), (12, P(-0.20, -0.04, 1.62), "smooth"), (16, P(-0.20, -0.08, 1.66), "smooth"),
          (23, P(-0.16, 0.42, 1.28), "in2"), (26, P(-0.14, 0.48, 1.20), "out2"), (36, P(-0.15, 0.44, 1.10), "smooth"), (60, Gi, "smooth"), (66, Gi)]
    KT = [(0, 76.0), (4, 80.0), (12, 15.0), (16, 0.0), (23, 70.0, "in2"), (26, 96.0, "out2"), (36, 74.0), (60, 76.0), (66, 76.0)]
    G = wp(KG, fr)
    th = wp(KT, fr)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    dl = -0.30
    s = S()
    stance(s, 0.15, -0.02, -0.15, 0.08, 6.0, -12.0)
    back = pulse(fr, 3, 14, 17, 23)
    s["pel"] = V(0.0, 0.04 * back - 0.03 * pulse(fr, 20, 26, 30, 40), -0.01)
    s["hip"] = (-4.0 * back + 2.0 * pulse(fr, 22, 27, 30, 40), 0.0, 0.0)
    s["tor"] = (3.0 - 10.0 * back + 8.0 * pulse(fr, 22, 27, 32, 46), 4.0, 0.0)
    s["head"] = (5.0 + 6.0 * back, 0.0, 0.0)
    tool2(s, G, D, sag_K(D), dl, fitlean=False)
    fit(s, rmax=0.5, headk=0.0, lmax=25)
    return s


LC.life_clip("Life_Fish_Cast", loop=False, category="work/fish", props=[{"id": "fishing_rod", "hand": "r"}], ik_l_on_prop=-0.30,
             events={"release": [23]}, note="one shot: starts and ends in Life_Fish_Idle_Rod frame 0; back-cast over the shoulder, snap forward, line flies at frame 23")(
    lambda: __import__("life_clips_farm").poses(lambda fr: fish_cast(fr, 66), 66))


def fish_reel(fr, n):
    th = 76.0 + 0.8 * sw(fr, n, 4)
    D = V(0, -math.sin(math.radians(th)), math.cos(math.radians(th)))
    s = S()
    stance(s, 0.15, -0.02, -0.15, 0.08, 6.0, -12.0)
    s["pel"] = V(0.0, 0.005 * sw(fr, n, 4), -0.012)
    s["tor"] = (4.0 + 1.0 * sw(fr, n, 4), 3.0, 0.0)
    s["head"] = (6.0, 0.0, 0.0)
    Gr = P(-0.17, 0.27, 1.06) + V(0.003 * sw(fr, n, 4), 0.004 * sw(fr, n, 4), 0.005 * sw(fr, n, 4, 0.25))
    grips(s, [("r", Gr, D, sag_K(D))], fitlean=False)
    # the left hand cranks the reel just behind / below the right hand: a 0.05 m circle in the rod's plane
    ph = 2 * math.pi * 4.0 * fr / n
    C = P(0.03, 0.15, 1.06)
    hl = C + V(0.0, -0.055 * math.cos(ph), 0.055 * math.sin(ph))
    hand1(s, "l", hl, ((0.5, -0.4 * math.cos(ph) - 0.2, 0.4 * math.sin(ph) - 0.3), (-0.9, 0.2, 0.0)), 0.9)
    fit(s, rmax=0.46, headk=0.0, lmax=25)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Fish_Reel", 60, fish_reel, loop=True, category="work/fish", props=[{"id": "fishing_rod", "hand": "r"}],
          note="rod in the right hand exactly as in Life_Fish_Idle_Rod (same grip point, similar tilt), left hand cranks the reel, 4 turns per loop")
