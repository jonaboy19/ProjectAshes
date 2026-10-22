# Builders that make a new, closed clip out of a truncated mocap take (numpy only).
#   handstand_kicks: MA_Acro_HandstandKicks ends in a handstand (9.5 s take, never comes back).  Keep the stand -> handstand entry and a few
#   kick cycles, then play the entry backwards (handstand -> stand) after a pose-matched cross-fade, so the clip starts AND ends standing.
import numpy as np
from cmu_acro_lib import *   # noqa

JOINTS = ["pelvis", "spine_03", "Head", "foot_l", "foot_r", "calf_l", "calf_r", "hand_l", "hand_r", "lowerarm_l", "lowerarm_r", "ball_l", "ball_r"]


def _desc(c):
    I = c.rig.idx
    hm = (c.P[:, I["hand_l"]] + c.P[:, I["hand_r"]]) / 2
    return np.concatenate([c.P[:, I[j]] - hm for j in JOINTS], axis=1), hm


def _smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def handstand_kicks(rig, chans, entry=(70, 90), mid_end=(128, 152), blend=8, tail_hold=0):
    c = Clip(rig, chans)
    I = rig.idx
    D, hm = _desc(c)
    best = None
    for i in range(entry[0], entry[1] + 1):
        for k in range(mid_end[0], mid_end[1] + 1):
            d = np.linalg.norm(D[k] - D[i])
            if best is None or d < best[0]:
                best = (d, i, k)
    _, i, k = best
    B = blend
    F = k + 1 + i - B + 1          # forward frames 0..k, then entry[i-B .. 0] (B blended frames overlap the tail of the forward part)
    T = np.zeros((F,) + c.T.shape[1:]); Q = np.zeros((F,) + c.Q.shape[1:])
    T[:k + 1] = c.T[:k + 1]; Q[:k + 1] = c.Q[:k + 1]
    # world offset that puts the reversed entry on the hands of the forward part
    off = hm[k] - hm[i]; off[1] = 0
    r = I["root"]
    Te = c.T.copy(); Te[:, r] = Te[:, r] + off
    for t in range(B):                                    # cross-fade: forward frame (k - B + 1 + t) with entry frame (i - t)
        f = k - B + 1 + t
        w = _smooth((t + 1) / (B + 1))
        T[f] = c.T[f] * (1 - w) + Te[i - t] * w
        Q[f] = qslerp(c.Q[f], c.Q[i - t], w)
    for m in range(1, i - B + 2):                         # entry backwards: entry frame (i - B - m + 1) ... 0
        f = k + m
        e = i - B - m + 1
        if e < 0:
            break
        T[f] = Te[e]; Q[f] = c.Q[e]
    nodes_t = [n for n, p in c.tracks if p == "translation"]
    nodes_q = [n for n, p in c.tracks if p == "rotation"]
    out = rig.to_chans(T, Q, nodes_t=nodes_t, nodes_q=nodes_q)
    print("handstand_kicks: entry frame %d joined to mid frame %d (pose distance %.2f), %d frames" % (i, k, best[0], F))
    return out
