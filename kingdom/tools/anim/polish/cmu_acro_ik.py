# Two-bone limb IK (legs and arms) on the UAL skeleton, generalised from glb_fk.leg_ik (which it reuses the helpers of); numpy only.
import numpy as np
from glb_fk import qmul, qconj, qnorm, qrot, q_from_two, qslerp


def limb_ik(rig, T, Q, chain, target, weight, P=None, R=None, keep_end_world=True, pole_hint=None):
    """Two-bone IK for a limb chain = (top, mid, end) bone names, e.g. ("thigh_l", "calf_l", "foot_l") or ("upperarm_r", "lowerarm_r", "hand_r").
    Moves the end joint to `target` (F,3) with blend weight (F,) (0 keeps the source). Modifies Q in place (top, mid and, to keep its world
    orientation, the end bone) and returns the new world position/rotation arrays. The mid joint keeps its current bend plane; a target
    beyond reach is clamped (limb stays straight). Copy of glb_fk.leg_ik generalised to arms."""
    th, ca, fo = (rig.idx[n] for n in chain)
    if P is None:
        P, R = rig.fk(T, Q)
    H, K, A = P[:, th].copy(), P[:, ca].copy(), P[:, fo].copy()
    l1 = np.linalg.norm(K - H, axis=-1); l2 = np.linalg.norm(A - K, axis=-1)
    tgt = A + (target - A) * weight[:, None]
    v = tgt - H
    d = np.linalg.norm(v, axis=-1)
    dmax = (l1 + l2) * 0.999
    dmin = np.abs(l1 - l2) * 1.001 + 1e-3
    dc = np.clip(d, dmin, dmax)
    u = v / np.maximum(d, 1e-9)[:, None]
    # current bend direction (perpendicular part of knee offset)
    cur = A - H
    cu = cur / np.maximum(np.linalg.norm(cur, axis=-1, keepdims=True), 1e-9)
    kv = K - H
    perp = kv - np.sum(kv * cu, axis=-1, keepdims=True) * cu
    pn = np.linalg.norm(perp, axis=-1, keepdims=True)
    fwd = qrot(R[:, th], np.array([0, 0, 1.0]))            # fallback: character-forward-ish
    if pole_hint is not None:
        fwd = np.broadcast_to(pole_hint, perp.shape)
    perp = np.where(pn > 1e-4, perp / np.maximum(pn, 1e-9), fwd)
    perp = perp - np.sum(perp * u, axis=-1, keepdims=True) * u
    perp = perp / np.maximum(np.linalg.norm(perp, axis=-1, keepdims=True), 1e-9)
    a = (l1 ** 2 - l2 ** 2 + dc ** 2) / (2 * dc)
    h = np.sqrt(np.maximum(l1 ** 2 - a ** 2, 0))
    K2 = H + u * a[:, None] + perp * h[:, None]
    A2 = H + u * dc[:, None]
    # thigh: align (K-H) -> (K2-H), then align the bend-plane normals
    r1 = q_from_two(K - H, K2 - H)
    n_old = np.cross(K - H, A - K); n_new = np.cross(K2 - H, A2 - K2)
    n1 = qrot(r1, n_old)
    ax = (K2 - H) / np.linalg.norm(K2 - H, axis=-1, keepdims=True)
    n1p = n1 - np.sum(n1 * ax, axis=-1, keepdims=True) * ax
    n2p = n_new - np.sum(n_new * ax, axis=-1, keepdims=True) * ax
    ok = (np.linalg.norm(n1p, axis=-1) > 1e-7) & (np.linalg.norm(n2p, axis=-1) > 1e-7)
    ang = np.arctan2(np.sum(np.cross(n1p, n2p) * ax, axis=-1), np.sum(n1p * n2p, axis=-1))
    ang = np.where(ok, ang, 0.0)
    r2 = np.concatenate([ax * np.sin(ang / 2)[:, None], np.cos(ang / 2)[:, None]], axis=-1)
    D = qmul(r2, r1)
    thigh_w = qmul(D, R[:, th])
    calf_w0 = qmul(D, R[:, ca])
    A1 = K2 + qrot(D, A - K)
    r3 = q_from_two(A1 - K2, A2 - K2)
    calf_w = qmul(r3, calf_w0)
    foot_w = R[:, fo] if keep_end_world else qmul(r3, qmul(D, R[:, fo]))
    p_th = rig.parent[th]
    Q[:, th] = qnorm(qmul(qconj(R[:, p_th]), thigh_w))
    Q[:, ca] = qnorm(qmul(qconj(thigh_w), calf_w))
    Q[:, fo] = qnorm(qmul(qconj(calf_w), foot_w))
    return rig.fk(T, Q)


