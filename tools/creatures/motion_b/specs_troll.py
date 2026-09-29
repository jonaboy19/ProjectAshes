"""Troll attack and slam: huge slow two-arm raise, chest expands, lean back, hold with a tremble, fast slam, fists stop at the floor.
Metres are for a 1.1 m goblin and scaled by K (troll = 3.0 m -> 2.7)."""
from authoring import REST
K = 2.7
OPTS = dict(K=K, hand_ground=0.0)      # skinned fist vertices never below the floor: fists rest on it instead of sinking in
WIND = dict(hips=(-0.05, 0.0, 0.02), hips_rot=(-8, 0, 0), spine=(-26, -8, 0), head=(12, 6, 0),
            grip=(0.05, 0.0, 1.0, 0.16), gripw=1.0, relbow=(0.0, 0.9, 0.4), lelbow=(0.0, -0.9, 0.4))
HIT = dict(hips=(0.12, 0.0, -0.16), hips_rot=(22, 0, 0), spine=(50, 6, 0), head=(-6, -6, 0),
           grip=(0.55, 0.0, -1.5, 0.16), gripw=1.0, relbow=(0.0, 0.9, -0.2), lelbow=(0.0, -0.9, -0.2), tremble=0.0)
SQUASH = dict(HIT, hips=(0.14, 0.0, -0.21), hips_rot=(26, 0, 0), spine=(58, 6, 0), grip=(0.55, 0.0, -1.5, 0.16))
WIND_A = dict(hips=(-0.05, 0.0, 0.02), hips_rot=(-8, -6, 0), spine=(-24, -30, 0), head=(10, 24, 0),
              rhand=(-0.15, 0.35, 1.0), relbow=(-0.2, 0.9, 0.4), lhand=(0.6, -0.3, 0.25), lelbow=(0.0, -0.8, -0.4),
              rhand_rot=(-20, 0, 15), gripw=0.0)
HIT_A = dict(hips=(0.16, 0.0, -0.15), hips_rot=(22, 14, 0), spine=(52, 36, 0), head=(-6, -22, 0),
             rhand=(0.30, 0.15, -1.60), relbow=(0.0, 0.9, -0.2), lhand=(0.35, -0.75, -0.2), lelbow=(0.0, -0.9, -0.2),
             rhand_rot=(30, 0, -10), tremble=0.0, gripw=0.0)
SQUASH_A = dict(HIT_A, hips=(0.17, 0.0, -0.18), hips_rot=(25, 14, 0), spine=(56, 36, 0))
CLIPS = {
    "attack": dict(base=("attack", 1), duration=2.60, keys=[
        (0.00, {}),
        (0.76, dict(WIND_A, tremble=0.0), 'smooth'),
        (0.82, dict(WIND_A, tremble=0.012), 'lin'),
        (1.05, dict(WIND_A, tremble=0.012), 'lin'),
        (1.15, HIT_A, 'snap'),
        (1.25, SQUASH_A, 'out'),
        (1.55, SQUASH_A, 'lin'),
        (2.60, dict(REST, gripw=0.0), 'smooth'),
    ]),
    "slam": dict(base=("slam", 1), duration=3.40, keys=[
        (0.00, {}),
        (1.20, dict(WIND, hips=(-0.06, 0.0, 0.05), spine=(-34, -10, 0), grip=(0.05, 0.0, 1.1, 0.16), tremble=0.0), 'smooth'),
        (1.28, dict(WIND, hips=(-0.06, 0.0, 0.05), spine=(-34, -10, 0), grip=(0.05, 0.0, 1.1, 0.16), tremble=0.015), 'lin'),
        (1.60, dict(WIND, hips=(-0.06, 0.0, 0.05), spine=(-34, -10, 0), grip=(0.05, 0.0, 1.1, 0.16), tremble=0.015), 'lin'),
        (1.75, dict(HIT, tremble=0.0), 'snap'),
        (1.87, SQUASH, 'out'),
        (2.30, SQUASH, 'lin'),
        (3.40, dict(REST, gripw=0.0), 'smooth'),
    ]),
}
IMPACT = {"attack": 1.15, "slam": 1.75}

LOCO_LIFT = ["walk", "run"]    # clips whose feet sink below the floor: hips lifted per frame
DEATH_LIFT = ["death"]
LOOP_CLOSE = ["idle"]
INPLACE = ["hit"]    # Meshy hit clips travel 0.7-1.8 m and end displaced
