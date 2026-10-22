"""Convert the horse bake's per-frame socket tracks (source/Horse_Anims.saddle.json, root-bone space) into RIDER CLIP SPACE:
horse armature axes (-Y forward, +X horse left, +Z up), horse root at the origin, horse at REST. The rider clip is authored
against the resting saddle; in game the rider is moved rigidly by the saddle delta D(t) = saddle_pose(t) * saddle_rest^-1.
Output source/rider_tracks.json: per clip, per frame: D (pos, quat wxyz) in armature space, and the rein grips / bit in
rider clip space (= D^-1 * world), which is where the rider's hands must be.   usage: py -3 rider_tracks.py"""
import json, os, math
HERE = os.path.dirname(os.path.abspath(__file__))


def qmul(a, b):
    w1, x1, y1, z1 = a; w2, x2, y2, z2 = b
    return (w1*w2-x1*x2-y1*y2-z1*z2, w1*x2+x1*w2+y1*z2-z1*y2, w1*y2-x1*z2+y1*w2+z1*x2, w1*z2+x1*y2-y1*x2+z1*w2)


def qinv(q):
    return (q[0], -q[1], -q[2], -q[3])


def qrot(q, v):
    r = qmul(qmul(q, (0.0,) + tuple(v)), qinv(q))
    return r[1:]


def to_arm(p):              # root-bone space -> armature space (root bone rest = 180 deg about Z)
    return (-p[0], -p[1], p[2])


def q_to_arm(q):
    c = (0.0, 0.0, 0.0, 1.0)
    return qmul(qmul(c, q), qinv(c))


src = json.load(open(os.path.join(HERE, "source", "Horse_Anims.saddle.json")))
rest = src["Idle"][0]["saddle"]
S0p = to_arm(rest[:3]); S0q = q_to_arm(tuple(rest[3:]))
out = {"_doc": __doc__, "saddle_rest": S0p,
       "stirrup_L": [round(x, 4) for x in to_arm(src["Idle"][0]["stirrup_L"][:3])],
       "stirrup_R": [round(x, 4) for x in to_arm(src["Idle"][0]["stirrup_R"][:3])]}
for clip, frames in src.items():
    rows = []
    for fr in frames:
        root_p = fr["root"][:3]; root_q = tuple(fr["root"][3:])
        s = fr["saddle"]
        Sp = to_arm(s[:3]); Sq = q_to_arm(tuple(s[3:]))
        # D = S * S0^-1  (position part: Sp - Dq*S0p)
        Dq = qmul(Sq, qinv(S0q))
        r = qrot(Dq, S0p)
        Dp = tuple(a - b for a, b in zip(Sp, r))
        Dinv_q = qinv(Dq)
        row = {"D": [round(x, 5) for x in Dp] + [round(x, 6) for x in Dq]}
        for k in ("rein_grip_L", "rein_grip_R", "bit"):
            w = to_arm(fr[k][:3])
            local = qrot(Dinv_q, tuple(a - b for a, b in zip(w, Dp)))
            row[k] = [round(x, 4) for x in local]
        rows.append(row)
    out[clip] = rows
json.dump(out, open(os.path.join(HERE, "source", "rider_tracks.json"), "w"))
print("clips", len(src), "e.g. Trot f5", out["Trot"][5])
