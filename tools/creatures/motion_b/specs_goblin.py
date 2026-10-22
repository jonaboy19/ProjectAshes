"""Goblin attack: quick crouch, sword hand pulled back over the shoulder, 3-frame tremble, fast slash, follow-through.
Times in seconds (frame = 1 + t*30). Hand targets: (fwd, right, up) in arm lengths from that shoulder.
hips/foot/tremble values are metres for a 1.1 m goblin (scaled by K)."""
from authoring import REST
K = 1.0
OPTS = dict(K=K)
WIND = dict(hips=(-0.07, 0.0, -0.075), hips_rot=(-10, -8, 0), spine=(-14, -38, 3), head=(4, 32, 0),
            rhand=(-0.30, 0.42, 0.80), relbow=(-0.3, 0.9, 0.2), rhand_rot=(-25, 0, 20),
            lhand=(0.55, -0.15, 0.15), lelbow=(0.2, -0.6, -0.6))
HIT = dict(hips=(0.13, 0.0, -0.09), hips_rot=(8, 10, 0), spine=(14, 40, -4), head=(-2, -25, 0),
           rhand=(0.95, -0.10, -0.40), relbow=(0.3, 0.6, -0.8), rhand_rot=(30, 0, -15),
           lhand=(-0.2, -0.55, 0.05), lelbow=(-0.5, -0.7, 0.2), tremble=0.0)
FOLLOW = dict(hips=(0.15, -0.02, -0.10), hips_rot=(10, 16, 0), spine=(18, 50, -4), head=(-2, -30, 0),
              rhand=(0.75, -0.55, -0.55), relbow=(0.2, 0.7, -0.7), rhand_rot=(35, 0, -20),
              lhand=(-0.3, -0.65, 0.15), lelbow=(-0.5, -0.8, 0.2))
T_WIND, T_HOLD0, T_STRIKE, T_IMPACT = 0.20, 0.24, 0.46, 0.55
CLIPS = {
    "attack": dict(base=("attack", 1), duration=1.30, keys=[
        (0.00, {}),
        (T_WIND, dict(WIND, tremble=0.0), 'out'),
        (T_HOLD0, dict(WIND, tremble=0.013), 'lin'),
        (T_STRIKE, dict(WIND, tremble=0.013), 'lin'),
        (T_IMPACT, dict(HIT, tremble=0.0), 'snap'),
        (0.73, FOLLOW, 'out'),
        (0.86, FOLLOW, 'lin'),
        (1.30, REST, 'smooth'),
    ]),
}
IMPACT = {"attack": T_IMPACT}

LOCO_LIFT = ["run"]    # clips whose feet sink below the floor: hips lifted per frame
INPLACE = ["hit"]    # Meshy hit clips travel 0.7-1.8 m and end displaced
