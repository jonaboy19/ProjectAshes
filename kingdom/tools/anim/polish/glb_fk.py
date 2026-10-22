# Forward kinematics + two-bone leg IK on the animation tracks of a UAL-skeleton clip GLB (pure numpy, no Blender).
# glTF space: +Y up, the character faces +Z. Quaternions are xyzw. Used by the polish scripts (foot pinning, floor fix, knee straightening).
import os, sys, math
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from glb_edit_clips import Glb, sample, clip_len   # noqa: E402

FPS = 30.0


# ---------------------------------------------------------------- quaternion helpers (xyzw)
def qmul(a, b):
    ax, ay, az, aw = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    bx, by, bz, bw = b[..., 0], b[..., 1], b[..., 2], b[..., 3]
    return np.stack([aw * bx + ax * bw + ay * bz - az * by,
                     aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw,
                     aw * bw - ax * bx - ay * by - az * bz], axis=-1)


def qconj(q):
    return q * np.array([-1, -1, -1, 1.0])


def qnorm(q):
    return q / np.linalg.norm(q, axis=-1, keepdims=True)


def qrot(q, v):
    """rotate vectors v (...,3) by quaternions q (...,4)"""
    qv = q[..., :3]
    t = 2 * np.cross(qv, v)
    return v + q[..., 3:4] * t + np.cross(qv, t)


def qaxis(axis, ang):
    axis = np.asarray(axis, float)
    axis = axis / np.linalg.norm(axis, axis=-1, keepdims=True)
    s = np.sin(ang / 2)
    return np.concatenate([axis * np.asarray(s)[..., None], np.cos(ang / 2)[..., None] if np.ndim(ang) else np.array([math.cos(ang / 2)])], axis=-1)


def q_from_two(a, b):
    """shortest rotation taking direction a to b (both (...,3))"""
    a = a / np.linalg.norm(a, axis=-1, keepdims=True)
    b = b / np.linalg.norm(b, axis=-1, keepdims=True)
    c = np.cross(a, b)
    d = np.sum(a * b, axis=-1, keepdims=True)
    q = np.concatenate([c, 1 + d], axis=-1)
    bad = (1 + d[..., 0]) < 1e-6
    if np.any(bad):
        # opposite vectors: rotate 180 degrees about any perpendicular axis
        perp = np.cross(a, np.array([1.0, 0, 0]))
        alt = np.cross(a, np.array([0, 1.0, 0]))
        perp = np.where((np.linalg.norm(perp, axis=-1, keepdims=True) < 1e-6), alt, perp)
        perp = perp / np.linalg.norm(perp, axis=-1, keepdims=True)
        q = np.where(bad[..., None], np.concatenate([perp, np.zeros_like(d)], axis=-1), q)
    return qnorm(q)


def qslerp(a, b, w):
    d = np.sum(a * b, axis=-1, keepdims=True)
    b = np.where(d < 0, -b, b); d = np.abs(d)
    th = np.arccos(np.clip(d, -1, 1)); s = np.sin(th)
    use_lin = s < 1e-5
    wa = np.where(use_lin, 1 - w, np.sin((1 - w) * th) / np.where(use_lin, 1, s))
    wb = np.where(use_lin, w, np.sin(w * th) / np.where(use_lin, 1, s))
    return qnorm(wa * a + wb * b)


# ---------------------------------------------------------------- skeleton + clip
class Rig:
    def __init__(self, g):
        J = g.J
        self.g = g
        self.names = [n["name"] for n in J["nodes"]]
        self.idx = {n: i for i, n in enumerate(self.names)}
        N = len(self.names)
        self.parent = [-1] * N
        for i, n in enumerate(J["nodes"]):
            for c in n.get("children", []):
                self.parent[c] = i
        self.rest_t = np.array([n.get("translation", [0, 0, 0]) for n in J["nodes"]], float)
        self.rest_q = np.array([n.get("rotation", [0, 0, 0, 1]) for n in J["nodes"]], float)
        # topological order (parents first)
        order, seen = [], set()

        def visit(i):
            if i in seen:
                return
            if self.parent[i] >= 0:
                visit(self.parent[i])
            seen.add(i); order.append(i)
        for i in range(N):
            visit(i)
        self.order = order

    def dense(self, chans, nf):
        """per-frame local T (F,N,3) and Q (F,N,4) for frames 0..nf at 30 fps"""
        F = nf + 1
        T = np.broadcast_to(self.rest_t, (F,) + self.rest_t.shape).copy()
        Q = np.broadcast_to(self.rest_q, (F,) + self.rest_q.shape).copy()
        times = np.arange(F) / FPS
        for c in chans:
            n = c["node"]
            if c["path"] == "translation":
                for f in range(F):
                    T[f, n] = sample(c["t"], c["v"], "translation", times[f])
            elif c["path"] == "rotation":
                for f in range(F):
                    Q[f, n] = sample(c["t"], c["v"], "rotation", times[f])
        return T, Q

    def fk(self, T, Q):
        """world positions (F,N,3) and rotations (F,N,4)"""
        F, N = T.shape[0], T.shape[1]
        P = np.zeros((F, N, 3)); R = np.zeros((F, N, 4))
        for i in self.order:
            p = self.parent[i]
            if p < 0:
                P[:, i] = T[:, i]; R[:, i] = Q[:, i]
            else:
                P[:, i] = P[:, p] + qrot(R[:, p], T[:, i])
                R[:, i] = qmul(R[:, p], Q[:, i])
        return P, R

    def to_chans(self, T, Q, nodes_t=(), nodes_q=()):
        """channel dicts for the given nodes, dense at 30 fps"""
        F = T.shape[0]
        t = np.arange(F) / FPS
        out = []
        for n in nodes_t:
            out.append({"node": n, "path": "translation", "t": t.copy(), "v": T[:, n].copy()})
        for n in nodes_q:
            out.append({"node": n, "path": "rotation", "t": t.copy(), "v": qnorm(Q[:, n]).copy()})
        return out


def replace_channels(chans, new):
    """replace (node, path) channels of a clip by the new ones (added if missing)"""
    key = {(c["node"], c["path"]): i for i, c in enumerate(chans)}
    for c in new:
        k = (c["node"], c["path"])
        if k in key:
            chans[key[k]] = c
        else:
            chans.append(c)
    return chans


# ---------------------------------------------------------------- two-bone IK
def leg_ik(rig, T, Q, side, target, weight, P=None, R=None, keep_foot_world=True, pole_hint=None):
    """Move the ankle of leg `side` ('l'/'r') to `target` (F,3) with blend weight (F,) (0 keeps the source). Modifies Q in place
    (thigh, calf and, to keep its world orientation, foot local rotations) and returns the new world position/rotation arrays.
    The knee keeps its current bend plane; a target beyond leg reach is clamped to the reach (leg stays straight)."""
    th, ca, fo = (rig.idx[n + "_" + side] for n in ("thigh", "calf", "foot"))
    ba = rig.idx["ball_" + side]
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
    foot_w = R[:, fo] if keep_foot_world else qmul(r3, qmul(D, R[:, fo]))
    p_th = rig.parent[th]
    Q[:, th] = qnorm(qmul(qconj(R[:, p_th]), thigh_w))
    Q[:, ca] = qnorm(qmul(qconj(thigh_w), calf_w))
    Q[:, fo] = qnorm(qmul(qconj(calf_w), foot_w))
    if not keep_foot_world:
        pass
    return rig.fk(T, Q)


def ankle_rest_height(rig):
    P, _ = rig.fk(rig.rest_t[None], rig.rest_q[None])
    return float(P[0, rig.idx["foot_l"], 1])
