# LIFE work clips, part 3: cooking, laundry, sweeping, well, carrying (upper layers, pick up / put down), cart push.
import math
from mathutils import Vector
from combat_common import V
import combat_common as CC
import life_common as LC
from life_clips_farm import (S, P, wp, ez, pulse, sw, cw, mix, stance, grips, tool2, fit, from_tip, sag_K, HOw, hand1, at_sh,
                             breath, work_clip, LEN, shoulder, XAX, poses)

NEUT_R = P(-0.27, 0.07, 0.915)
NEUT_L = P(0.27, 0.07, 0.915)
HO_NR = ((-0.05, 0.0, -1.0), (1.0, 0.0, 0.0))
HO_NL = ((0.05, 0.0, -1.0), (-1.0, 0.0, 0.0))


def oneshot(name, n, fn, **meta):
    LC.life_clip(name, loop=False, **meta)(lambda: poses(lambda fr: fn(fr, n), n))


# ======================================================================================== COOKING
def cook_stir(fr, n):
    turns = 2.0
    ph = 2 * math.pi * turns * fr / n
    rr = 0.065 + 0.02 * (0.5 - 0.5 * math.cos(2 * math.pi * fr / n))      # the second turn is wider (per-cycle variation)
    T = P(0.0, 0.50, 0.53)                                                 # bowl of the ladle inside the pot
    tip = T + V(rr * math.cos(ph), -rr * 0.8 * math.sin(ph), 0.01 * math.sin(2 * ph))
    # the handle pivots on the rim: the hand circles the other way with a smaller radius
    D = V(-0.22 * math.cos(ph), -0.60 - 0.12 * math.sin(ph), -0.80).normalized()
    G = tip - D * LEN["ladle"] * 1.05
    s = S()
    stance(s, 0.15, -0.10, -0.15, 0.02, 6.0, -10.0)
    s["pel"] = V(0.01 * sw(fr, n, 2), -0.08, -0.13)                       # knees bent, hips forward over the feet
    s["hip"] = (8.0, 0.0, 0.0)
    s["tor"] = (8.0, 3.0 * sw(fr, n, 2, 0.1), 0.0)
    s["head"] = (14.0, 4.0 * sw(fr, n, 1, 0.3), 0.0)
    tang = V(-math.sin(ph), -0.8 * math.cos(ph), 0.0)
    K = (tang - D * tang.dot(D)).normalized()
    hand1(s, "l", P(0.24, 0.02, 1.0), ((0.0, -0.6, -0.8), (-1.0, 0.0, 0.0)), 0.7)
    grips(s, [("r", G, D, K)], fitlean=True, headk=0.1, lmax=35, rmax=0.44, squat=0.0016)
    breath(s, fr, n, 0.004)
    return s


work_clip("Life_Cook_Stir", 60, cook_stir, loop=True, category="work/cook", props=[{"id": "ladle", "hand": "r"}],
          anchor={"type": "cook_pot", "at": [0.0, 0.50, 0.60], "size": [0.6, 0.6, 0.60]}, events={"stir": [0, 30]},
          note="two stirs per loop (the second is wider), the ladle pivots on the pot rim, left hand on the hip")


def cook_chop(fr, n):
    m = 12
    k, sub = fr // m, fr % m
    tip = P(-0.02, 0.32, 0.80)
    Dc = V(0, -0.90, -0.43).normalized()
    Gc = tip - Dc * 0.12
    u = wp([(0, 0.0), (6, 1.0, "smooth"), (9, 0.6, "smooth"), (10, 0.0, "in2"), (12, 0.0)], sub) if fr < n else 0.0
    G = Gc + V(0.0, 0.02 * u, 0.075 * u)
    th = 0.0
    D = (Dc + V(0, 0.25 * u, 0.30 * u)).normalized()
    # left hand feeds the food: creeps back 2 cm per chop, then resets over the last chop
    ys = wp([(0, 0.0), (10, 0.0), (12, 0.02, "smooth"), (22, 0.02), (24, 0.04, "smooth"), (34, 0.04), (36, 0.06, "smooth"),
             (46, 0.06), (48, 0.08, "smooth"), (52, 0.08), (60, 0.0, "smooth")], fr)
    s = S()
    stance(s, 0.14, -0.04, -0.14, 0.06, 6.0, -8.0)
    s["pel"] = V(0.0, 0.0, -0.02 - 0.006 * (1 - u))
    s["tor"] = (8.0 + 1.0 * u, 3.0, 0.0)
    s["head"] = (14.0, -3.0, 0.0)
    hand1(s, "l", P(0.06, 0.28 - ys, 0.87 + 0.004 * (1 - u)), ((0.0, -0.75, -0.65), (-1.0, 0.0, 0.0)), 0.75)
    grips(s, [("r", G, D, sag_K(D))], fitlean=True, headk=0.1, lmax=35, rmax=0.46)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Cook_Chop", 60, cook_chop, loop=True, category="work/cook", props=[{"id": "knife", "hand": "r"}],
          anchor={"type": "table", "at": [0.0, 0.34, 0.80], "size": [1.0, 0.6, 0.8]}, events={"contact": [10, 22, 34, 46, 58]},
          note="five rocking chops, the claw-gripped left hand creeps back after every chop and resets at the end")


# ======================================================================================== LAUNDRY
def kneel2(s, y=0.40):
    s["foot_l"] = V(0.12, y, 0.19)
    s["foot_r"] = V(-0.12, y, 0.19)
    s["fpit_l"] = s["fpit_r"] = -75.0
    s["fyaw_l"] = s["fyaw_r"] = 0.0
    s["pel"] = V(0.0, 0.10, -0.46)
    s["hip"] = (14.0, 0.0, 0.0)
    return s


def scrub(fr, n):
    per = n / 3.0
    a = 0.5 - 0.5 * math.cos(2 * math.pi * 3.0 * fr / n)          # 0 top .. 1 bottom
    amp = 0.085 + 0.02 * sw(fr, n, 1, 0.2)
    Sl = V(0, 0.55, -0.83)                                     # down the board (towards the worker)
    C = P(0.0, 0.34, 0.60)
    s = S()
    kneel2(s)
    s["tor"] = (8.0 + 3.0 * a, 3.0 * sw(fr, n, 3, 0.25), 0.0)
    s["hip"] = (4.0, 0.0, 0.0)
    s["pel"] = Vector(s["pel"]) + V(0.006 * sw(fr, n, 3), -0.11 - 0.02 * (1 - a), 0.0)
    s["head"] = (14.0, 0.0, 0.0)
    for side in ("l", "r"):
        sx = 1 if side == "l" else -1
        ph = 0.15 * sx * sw(fr, n, 3, 0.3)                      # the two hands are slightly out of phase
        pos = C + V(sx * 0.10, 0.0, 0.0) + Sl * (amp * (a - 0.5) * 2 + ph * 0.02)
        ho = ((sx * -0.2, -0.85, -0.5), (-sx * 0.15, 0.5, -0.85))
        hand1(s, side, pos, ho, 0.8)
    fit(s, rmax=0.5, headk=0.0, squat=0.0, lmax=22)
    return s


work_clip("Life_Chore_Laundry_Scrub", 60, scrub, loop=True, enter_exit=True, n_enter=26, n_exit=24, category="work/laundry",
          props=[{"id": "laundry", "hand": "r"}], anchor={"type": "wash_tub", "at": [0.0, 0.34, 0.45], "size": [0.7, 0.5, 0.45]},
          events={"scrub_down": [15, 35, 55]}, note="kneeling at the tub, three scrub strokes down and up the washboard per loop",
          tr={"lift": 0.05, "dip": 0.0, "sway": 0.02, "t_body": (0.15, 0.95), "t_hands": (0.5, 1.0), "t_feet": (0.05, 0.6)})


def wring(fr, n):
    s = S()
    stance(s, 0.14, 0.0, -0.14, 0.05, 6.0, -8.0)
    up = pulse(fr, 0, 12, 46, 58)
    C = P(0.0, 0.30, 1.02)
    tw = wp([(0, 0.0), (14, 0.0), (26, 200.0, "smooth"), (30, 190.0, "smooth"), (42, 400.0, "smooth"), (46, 400.0)], fr)
    sq = pulse(fr, 14, 20, 40, 46)
    for side in ("l", "r"):
        sx = 1 if side == "l" else -1
        a = math.radians(tw * sx)
        w = 0.12 - 0.015 * sq
        off = V(sx * w, 0.035 * math.cos(a) * sq, 0.035 * math.sin(a) * sq)
        Dh = V(sx, 0, 0)
        f = V(0, -math.cos(a) * 0.8 - 0.2, math.sin(a) * 0.8 - 0.4)
        pos = (NEUT_L if side == "l" else NEUT_R).lerp(C + off + V(0, 0.0, 0.01 * sw(fr, n, 6) * sq), up)
        noh = HO_NL if side == "l" else HO_NR
        ho = HOw([(0, noh), (1, (tuple(f), (-sx * 0.9, 0.0, -0.1)))], min(1.0, up * 1.0)) if up > 0.0 else noh
        hand1(s, side, pos, ho, 0.3 + 0.65 * up)
    shake = 0.8 * sw(fr, n, 6) * sq
    s["pel"] = V(0, 0.0, -0.02 * up)
    s["tor"] = (6.0 * up + shake, 6.0 * sw(fr, n, 3, 0.1) * sq, 0.0)
    s["head"] = (12.0 * up, 0.0, 0.0)
    fit(s, rmax=0.5, headk=0.0, lmax=20)
    return s


oneshot("Life_Chore_Laundry_Wring", 60, wring, category="work/laundry", props=[{"id": "laundry", "hand": "r"}],
        events={"twist": [26, 42]}, note="one shot: lift the wet cloth to the chest, twist, squeeze, twist again, lower")


def hang(fr, n):
    m = n // 2
    c, sub = fr // m, fr % m
    if fr >= n:
        c, sub = 1, m
    xb = wp([(0, 0.0), (28, 0.0), (45, 0.26, "smooth"), (73, 0.26), (90, 0.0, "smooth")], fr)
    fl = wp([(0, 0.0), (28, 0.0), (38, 0.26, "smooth"), (80, 0.26), (90, 0.0, "smooth")], fr)
    frr = wp([(0, 0.0), (35, 0.0), (45, 0.26, "smooth"), (73, 0.26), (83, 0.0, "smooth")], fr)

    def liftz(fr_, a, b):
        return 0.07 * math.sin(math.pi * (fr_ - a) / float(b - a)) if a < fr_ < b else 0.0
    lz_l = liftz(fr, 28, 38) + liftz(fr, 80, 90)
    lz_r = liftz(fr, 35, 45) + liftz(fr, 73, 83)
    s = S()
    s["foot_l"] = V(0.15 + fl, 0.0, 0.104 + lz_l)
    s["foot_r"] = V(-0.15 + frr, 0.06, 0.104 + lz_r)
    s["fyaw_l"], s["fyaw_r"] = 8.0, -8.0
    lineY = 0.26
    chest_r, chest_l = P(-0.14, 0.26, 1.20), P(0.14, 0.26, 1.20)
    line_r, line_l = P(-0.06, lineY, 1.80), P(0.12, lineY + 0.02, 1.74)
    basket_r, basket_l = P(0.20 - 0.06, 0.32, 0.50), P(0.20 + 0.06, 0.32, 0.50)
    pin = 0.02 * pulse(sub, 12, 14, 15, 17) + 0.02 * pulse(sub, 17, 19, 20, 22)
    hr = wp([(0, chest_r), (8, line_r, "smooth"), (12, line_r), (17, line_r + V(0, 0, -0.01)), (22, line_r, "smooth"),
             (33, basket_r, "smooth"), (38, basket_r + V(0, 0, 0.005)), (45, chest_r, "smooth")], sub)
    hl = wp([(0, chest_l), (8, line_l, "smooth"), (22, line_l), (33, basket_l, "smooth"), (38, basket_l + V(0, 0, 0.005)),
             (45, chest_l, "smooth")], sub)
    hr = hr + V(xb, 0, 0) - V(0, 0, pin)
    hl = hl + V(xb, 0, 0)
    reach = pulse(sub, 4, 9, 22, 28)
    low = pulse(sub, 24, 33, 38, 44)
    s["pel"] = V(xb + 0.01 * sw(fr, n, 2), 0.0 - 0.02 * low, -0.02 - 0.16 * low)
    s["hip"] = (4.0 + 30.0 * low, 0.0, 0.0)
    s["tor"] = (2.0 - 6.0 * reach + 8.0 * low, 0.0, 0.0)
    s["head"] = (-14.0 * reach + 10.0 * low, 8.0 * pulse(sub, 12, 16, 20, 24), 0.0)
    hand1(s, "r", hr, HOw([(0, ((0.0, -0.9, 0.3), (0.0, -0.3, -0.9))), (8, ((0.0, -0.5, 0.85), (0.0, -0.85, -0.5))),
                          (22, ((0.0, -0.5, 0.85), (0.0, -0.85, -0.5))), (33, ((0.0, -0.7, -0.7), (1.0, 0.0, 0.0))),
                          (45, ((0.0, -0.9, 0.3), (0.0, -0.3, -0.9)))], sub), 0.85 - 0.3 * pulse(sub, 12, 13, 17, 18))
    hand1(s, "l", hl, HOw([(0, ((0.0, -0.9, 0.3), (0.0, -0.3, -0.9))), (8, ((0.0, -0.5, 0.85), (0.0, -0.85, -0.5))),
                          (22, ((0.0, -0.5, 0.85), (0.0, -0.85, -0.5))), (33, ((0.0, -0.7, -0.7), (-1.0, 0.0, 0.0))),
                          (45, ((0.0, -0.9, 0.3), (0.0, -0.3, -0.9)))], sub), 0.85)
    fit(s, rmax=0.46, headk=0.0, lmax=40, squat=0.0)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Chore_Hang_Washing", 90, hang, loop=True, category="work/laundry", props=[{"id": "laundry", "hand": "r"}],
          anchor={"type": "washing_line", "at": [0.0, 0.26, 1.80], "size": [1.2, 0.05, 0.05]}, events={"pin": [15, 60], "step": [40, 80]},
          note="hang a cloth on the line at 1.8 m and pin it, side-step left, bend to the basket, hang the next, side-step back")


# ======================================================================================== SWEEP
def sweep(fr, n):
    m = n // 4
    i = fr % n
    k, sub = i // m, i - (i // m) * m
    L = LEN["broom"]
    # bristle-tip path on the ground: a drag towards the body and to the left (odd strokes) / right (even strokes)
    dirs = (1.0, -1.0, 1.0, -1.0)
    d = dirs[k]
    u = ez("smooth", sub / float(m - 1)) if sub < m else 1.0
    drag = wp([(0, 0.0), (3, 0.0), (m - 5, 1.0, "smooth"), (m - 2, 1.0), (m, 0.0, "out")], sub)
    xs = wp([(0, -0.20 * d), (m - 4, 0.25 * d, "smooth"), (m, 0.25 * d)], sub)
    # after each stroke the bristles swing back; alternate sides
    x0 = 0.0
    B = P(xs - 0.04 * d, 0.62 - 0.14 * math.sin(math.pi * min(1.0, sub / float(m - 4))) , 0.0 + 0.05 * (1 - drag))
    G = P(0.4 * xs + 0.05, 0.14 + 0.04 * (0.5 - 0.5 * math.cos(2 * math.pi * fr / n * 2)), 0.0)
    hz = math.sqrt(max(0.05, L * L - (G.x - B.x) ** 2 - (G.y - B.y) ** 2))
    G = V(G.x, G.y, B.z + hz)
    D = (G - B).normalized()
    s = S()
    stance(s, 0.16, -0.06, -0.16, 0.10, 8.0, -12.0)
    # small step every other stroke: the left foot replants a little forward on strokes 2 and 4 alternate
    st = wp([(0, 0.0), (m + 4, 0.0), (m + 10, 1.0, "smooth"), (3 * m + 4, 1.0), (3 * m + 10, 0.0, "smooth"), (n, 0.0)], fr)
    lz = 0.05 * math.sin(math.pi * (fr - (m + 4)) / 6.0) if (m + 4) < fr < (m + 10) else 0.0
    lz += 0.05 * math.sin(math.pi * (fr - (3 * m + 4)) / 6.0) if (3 * m + 4) < fr < (3 * m + 10) else 0.0
    s["foot_l"] = V(0.16, -0.06 - 0.10 * st, 0.104 + lz)
    s["pel"] = V(-0.02 * xs, -0.03 * st, -0.03)
    s["hip"] = (8.0, 8.0 * xs / 0.25 * 0.5, 0.0)
    s["tor"] = (10.0 + 3.0 * drag, -10.0 * xs / 0.25, 0.0)
    s["head"] = (14.0, 4.0 * xs / 0.25, 0.0)
    tool2(s, G, D, V(1.0, 0.0, 0.0) if False else None, 0.38, headk=0.1, lmax=30)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Chore_Sweep", 88, sweep, loop=True, category="work/chores", props=[{"id": "broom", "hand": "r"}],
          ik_l_on_prop=0.38, events={"stroke": [18, 40, 62, 84]},
          note="four short strokes (left, right, left, right) with a small step of the left foot after strokes 1 and 3")


# ======================================================================================== WELL
def well_crank(fr, n):
    turns = 2.0
    ph = -2 * math.pi * turns * fr / n            # counter-clockwise seen from the character's right: up at the front
    r = 0.25
    C = P(-0.14, 0.32, 1.04)
    hand = C + V(0.0, -r * math.cos(ph), r * math.sin(ph))
    s = S()
    stance(s, 0.19, -0.08, -0.19, 0.10, 10.0, -14.0)
    near = 0.5 - 0.5 * math.cos(ph)
    s["pel"] = V(0.012 * math.sin(ph), -0.06 - 0.02 * math.cos(ph), -0.04 - 0.01 * math.sin(2 * ph))
    s["hip"] = (6.0, -6.0 * math.cos(ph), 0.0)
    s["tor"] = (8.0 + 5.0 * math.cos(ph), -6.0 * math.sin(ph) * 0.5, 0.0)
    s["head"] = (6.0, 8.0, 0.0)
    hand1(s, "l", P(0.30, 0.50, 0.93) + V(0.004 * sw(fr, n, 2), 0.0, 0.0), ((0.2, -1.0, -0.1), (0.0, 0.0, -1.0)), 0.25)
    grips(s, [("r", hand, V(1.0, 0.0, 0.0), None)], fitlean=True, headk=0.1, lmax=30, rmax=0.5)
    breath(s, fr, n, 0.003)
    return s


work_clip("Life_Chore_Well_Crank", 72, well_crank, loop=True, category="work/chores", props=[],
          anchor={"type": "well", "at": [0.15, 0.50, 0.93], "size": [1.0, 0.8, 0.93]}, events={"turn": [0, 36]},
          note="right hand turns the crank in a 0.25 m radius circle at 1.02 m (two turns per loop), left hand rests on the rim")


def well_lift(fr, n):
    rim = P(-0.05, 0.44, 1.02)
    side = P(-0.30, 0.22, 0.26)
    s = S()
    stance(s, 0.16, -0.04, -0.16, 0.08, 8.0, -12.0)
    hr = wp([(0, NEUT_R), (10, rim + V(0, 0, 0.06), "smooth"), (14, rim, "smooth"), (18, rim), (30, P(-0.20, 0.26, 1.16), "smooth"),
             (40, P(-0.32, 0.20, 0.80), "smooth"), (52, side + V(0, 0, 0.04), "smooth"), (56, side), (60, side), (68, P(-0.28, 0.14, 0.75), "smooth"),
             (78, NEUT_R, "smooth")], fr)
    grab = pulse(fr, 11, 15, 56, 60)
    ho = HOw([(0, HO_NR), (14, ((0.0, -0.3, -0.95), (1.0, 0.0, 0.0))), (56, HO_NR), (78, HO_NR)], fr)
    hand1(s, "r", hr, ho, 0.25 + 0.7 * grab)
    bend = pulse(fr, 0, 12, 14, 24) * 0.25 + pulse(fr, 34, 52, 60, 72)
    s["pel"] = V(-0.02 * bend, 0.06 * bend, -0.30 * bend)
    s["hip"] = (30.0 * bend + 6.0 * pulse(fr, 0, 12, 20, 30), 0.0, 0.0)
    s["tor"] = (6.0 * bend + 4.0 * pulse(fr, 8, 14, 20, 30), -12.0 * pulse(fr, 30, 40, 52, 66), 0.0)
    s["head"] = (8.0, 0.0, 0.0)
    hand1(s, "l", NEUT_L.lerp(P(0.26, 0.2, 0.65), 0.8 * bend), HO_NL, 0.3)
    fit(s, rmax=0.46, headk=0.0, lmax=50)
    return s


oneshot("Life_Chore_Well_Lift_Bucket", 78, well_lift, category="work/chores", props=[{"id": "bucket", "hand": "r"}],
        anchor={"type": "well", "at": [0.15, 0.50, 0.93], "size": [1.0, 0.8, 0.93]}, events={"grab": [14], "release": [58]},
        note="one shot: reach the bucket on the rim, pull it up and to the side, set it on the ground (bucket prop shows from the grab)")


# ======================================================================================== CARRY (upper layers)
def upper(name, fn, n=60, **meta):
    work_clip(name, n, fn, loop=True, category="carry/upper", layer="upper", **meta)


def carry_bucket(fr, n):
    s = S()
    hand1(s, "r", P(-0.31, 0.02, 0.93) + V(0.008 * sw(fr, n), 0.006 * sw(fr, n, 2), 0.0), HO_NR, 0.98)
    hand1(s, "l", NEUT_L + V(0.02 * sw(fr, n, 1, 0.1), 0.01 * sw(fr, n, 2), 0), HO_NL, 0.25)
    s["tor"] = (2.0, 0.0, 5.0)
    s["head"] = (0.0, 0.0, -3.0)
    s["shrug_r"] = -3.0
    breath(s, fr, n, 0.004)
    return s


upper("Life_Carry_Bucket_Upper", carry_bucket, props=[{"id": "bucket", "hand": "r"}],
      note="bucket by the bail in the right hand, arm straight, torso leans left, right shoulder drops")


def carry_two(fr, n):
    s = S()
    hand1(s, "r", P(-0.31, 0.02, 0.89) + V(0.008 * sw(fr, n), 0.006 * sw(fr, n, 2), 0.0), HO_NR, 0.98)
    hand1(s, "l", P(0.31, 0.02, 0.89) + V(-0.008 * sw(fr, n), 0.006 * sw(fr, n, 2, 0.5), 0.0), HO_NL, 0.98)
    s["tor"] = (1.0, 0.0, 0.0)
    s["head"] = (0.0, 0.0, 0.0)
    s["shrug_r"] = -3.0
    s["shrug_l"] = -3.0
    breath(s, fr, n, 0.004)
    return s


upper("Life_Carry_Two_Buckets_Upper", carry_two, props=[{"id": "bucket", "hand": "r"}, {"id": "bucket", "hand": "l"}],
      note="a bucket in each hand, arms straight and slightly out, both shoulders drop, torso upright")


def carry_sack(fr, n):
    s = S()
    hand1(s, "l", P(0.26, 0.0, 1.50) + V(0.004 * sw(fr, n, 2), 0.0, 0.005 * sw(fr, n)), ((0.0, -1.0, 0.0), (0.0, 0.0, 1.0)), 0.95)
    hand1(s, "r", P(0.10, 0.02, 1.38), ((0.7, -0.6, 0.0), (0.0, 0.0, -1.0)), 0.5)
    s["tor"] = (8.0, 0.0, -4.0)
    s["head"] = (-4.0, 0.0, 5.0)
    s["shrug_l"] = 6.0
    breath(s, fr, n, 0.004)
    return s


upper("Life_Carry_Sack_Upper", carry_sack, props=[{"id": "sack", "hand": "l"}],
      note="sack on the left shoulder held by the left hand, right hand steadies it, torso pitched forward")


CR = 0.21


def carry_crate(fr, n):
    s = S()
    y = 0.26 + 0.004 * sw(fr, n, 2)
    hand1(s, "r", P(-CR, y, 1.08) + V(0, 0, 0.004 * sw(fr, n)), ((1.0, 0.0, 0.0), (0.0, 0.0, 1.0)), 0.6)
    hand1(s, "l", P(CR, y, 1.08) + V(0, 0, 0.004 * sw(fr, n)), ((-1.0, 0.0, 0.0), (0.0, 0.0, 1.0)), 0.6)
    s["tor"] = (-6.0, 0.0, 0.0)
    s["head"] = (3.0, 0.0, 0.0)
    breath(s, fr, n, 0.004)
    return s


upper("Life_Carry_Crate_Upper", carry_crate, props=[{"id": "crate_small", "hand": "r"}],
      note="crate at chest height, both palms under its lower edge, torso leans back a little")


def carry_basket(fr, n):
    s = S()
    hand1(s, "l", P(0.30, 0.28, 1.02) + V(0.004 * sw(fr, n, 2), 0.004 * sw(fr, n), 0.005 * sw(fr, n, 2)),
          ((0.0, -0.15, -1.0), (-1.0, 0.0, 0.0)), 0.9)
    s["elb_l"] = P(0.36, 0.02, 1.0)
    hand1(s, "r", NEUT_R + V(-0.02 * sw(fr, n, 1, 0.3), 0.01 * sw(fr, n, 2), 0), HO_NR, 0.25)
    s["tor"] = (2.0, 0.0, -2.0)
    breath(s, fr, n, 0.004)
    return s


upper("Life_Carry_Basket_Upper", carry_basket, props=[{"id": "basket", "hand": "l"}],
      note="basket on the left forearm, elbow bent and pressed to the side, right arm free")


# --- full-body pick up / put down of the small crate
def _crate_at(u):
    base = carry_crate(0, 60)
    gr_r, gr_l = P(-0.22, 0.40, 0.12), P(0.22, 0.40, 0.12)
    ca_r, ca_l = Vector(base["hand_r"]), Vector(base["hand_l"])
    bend = wp([(0.0, 0.0), (0.28, 1.0, "smooth"), (0.42, 1.0), (0.85, 0.0, "smooth"), (1.0, 0.0)], u)
    ramp = ez("smooth", (u - 0.45) / 0.55)
    s = S()
    for side, ng, gg, cc, sx in (("r", NEUT_R, gr_r, ca_r, -1), ("l", NEUT_L, gr_l, ca_l, 1)):
        pos = wp([(0.0, ng), (0.28, gg, "smooth"), (0.42, gg), (0.85, cc, "smooth"), (1.0, cc)], u)
        ho = HOw([(0.0, HO_NR if side == "r" else HO_NL), (0.28, base["ho_" + side]), (1.0, base["ho_" + side])], u)
        cur = wp([(0.0, 0.25), (0.28, 0.3), (0.42, 0.85), (0.85, 0.6), (1.0, 0.6)], u)
        hand1(s, side, pos, ho, cur)
    s["pel"] = V(0.0, 0.12 * bend, -0.42 * bend)
    s["hip"] = (48.0 * bend, 0.0, 0.0)
    s["tor"] = (2.0 + (base["tor"][0] - 2.0) * ramp + 6.0 * bend, 0.0, 0.0)
    s["head"] = (3.0 * ramp + 10.0 * bend * 0, 0.0, 0.0)
    if bend > 0.02:
        fit(s, rmax=0.5, headk=0.0, lmax=25)
    return s


def pick_up(fr, n):
    return _crate_at(fr / float(n))


def put_down(fr, n):
    return _crate_at(1.0 - fr / float(n))


oneshot("Life_Carry_Pick_Up", 48, pick_up, category="carry/full", props=[{"id": "crate_small", "hand": "r"}],
        events={"grab": [17]}, note="squat to a crate on the ground 0.4 m ahead, back straight, lift it to the Life_Carry_Crate_Upper carry pose (ends on its frame 0)")
oneshot("Life_Carry_Put_Down", 48, put_down, category="carry/full", props=[{"id": "crate_small", "hand": "r"}],
        events={"release": [30]}, note="reverse: from the Life_Carry_Crate_Upper carry pose squat and set the crate on the ground")


# ======================================================================================== CART
def _cart():
    F = CC.F
    hx = 0.30
    hr, hl = P(-hx, 0.36, 1.0), P(hx, 0.36, 1.0)
    base = {"hip": (8.0, 0.0, 0.0), "tor": (6.0, 0.0, 0.0), "hand_r": hr, "hand_l": hl, "ho_r": HO_NR, "ho_l": HO_NL,
            "curl_r": 0.9, "curl_l": 0.9}
    ps = LC.walk_cycle(n=44, stride=0.22, lift=0.05, bob=0.02, sway=0.02, arm=0.0, lean=6.0, arm_lift=0.0, hip_yaw=4.0, tor_yaw=-3.0,
                       heel=8.0, toe=14.0, base=base)
    return ps


LC.life_clip("Life_Cart_Push", loop=True, category="carry/full", speed_mps=LC.speed_of(0.22, 44), ik_l_on_prop=None,
             props=[], note="in-place walk leaning into cart handles held at hip height (hands fixed in the body frame); play at body_speed / speed_mps")(_cart)
