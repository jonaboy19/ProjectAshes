"""Orc attack: weight back on the rear foot, axe raised high in both hands and held with a tremble, fast chop, follow-through.
Metres are for a 1.1 m goblin and scaled by K (orc = 2.0 m -> 1.8)."""
from authoring import REST
K = 1.8
OPTS = dict(K=K, hand_ground=0.0)
WIND = dict(hips=(-0.11, 0.0, 0.0), hips_rot=(-12, -6, 0), spine=(-24, -30, 2), head=(10, 22, 0),
            rhand=(0.0, 0.25, 1.05), relbow=(0.0, 0.9, 0.3), lhand=(0.15, 0.6, 0.9), lelbow=(0.0, -0.8, 0.3),
            grip=(0.05, 0.0, 0.95, 0.14), gripw=1.0)
HIT = dict(hips=(0.10, 0.0, -0.09), hips_rot=(14, 10, 0), spine=(32, 26, 0), head=(-8, -18, 0),
           grip=(0.90, 0.0, -0.55, 0.14), gripw=1.0, relbow=(0.0, 0.9, -0.3), lelbow=(0.0, -0.9, -0.3), tremble=0.0)
FOLLOW = dict(hips=(0.13, 0.0, -0.12), hips_rot=(16, 10, 0), spine=(40, 24, 0), head=(-8, -16, 0),
              grip=(0.75, 0.0, -0.90, 0.14), gripw=1.0)
T_WIND, T_HOLD0, T_STRIKE, T_IMPACT = 0.36, 0.42, 0.73, 0.85
CLIPS = {
    "attack": dict(base=("attack", 1), duration=2.10, keys=[
        (0.00, {}),
        (T_WIND, dict(WIND, tremble=0.0), 'smooth'),
        (T_HOLD0, dict(WIND, tremble=0.010), 'lin'),
        (T_STRIKE, dict(WIND, tremble=0.010), 'lin'),
        (T_IMPACT, dict(HIT, tremble=0.0), 'snap'),
        (1.02, FOLLOW, 'out'),
        (1.30, FOLLOW, 'lin'),
        (2.10, dict(REST, gripw=0.0), 'smooth'),
    ]),
}
WINDC = dict(WIND, hips=(-0.13, 0.0, 0.02), spine=(-30, -32, 2), hips_rot=(-14, -6, 0), grip=(0.05, 0.0, 1.0, 0.14))
HITC = dict(HIT, hips=(0.11, 0.0, -0.14), hips_rot=(16, 10, 0), spine=(36, 26, 0))
FOLLOWC = dict(FOLLOW, hips=(0.14, 0.0, -0.18), spine=(44, 24, 0))
CLIPS["attack_charged"] = dict(base=("attack_charged", 103), prefix=("attack_charged", 103), duration=2.9, keys=[
    (0.00, {}),
    (0.90, dict(WINDC, tremble=0.0), 'smooth'),
    (1.05, dict(WINDC, tremble=0.006), 'lin'),
    (1.60, dict(WINDC, tremble=0.016), 'lin'),
    (1.72, dict(HITC, tremble=0.0), 'snap'),
    (1.95, FOLLOWC, 'out'),
    (2.25, FOLLOWC, 'lin'),
    (2.90, dict(REST, gripw=0.0), 'smooth'),
])
IMPACT = {"attack": T_IMPACT, "attack_charged": 3.4 + 1.72}

LOCO_LIFT = []    # clips whose feet sink below the floor: hips lifted per frame
DEATH_LIFT = ["death"]
INPLACE = ["hit"]    # Meshy hit clips travel 0.7-1.8 m and end displaced
