"""Tiny numpy FK / quaternion helpers for UAL-skeleton clip GLBs (glTF space, quaternions are x, y, z, w). Used by pivot180_rebuild.py.
The GLB is read with tools/anim/glb_edit_clips.py (Glb.anims / Glb.write)."""
import os, sys, math
import numpy as np
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import glb_edit_clips as G


def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])


def qinv(a):
    return np.array([-a[0], -a[1], -a[2], a[3]]) / float(np.dot(a, a))


def qrot(q, v):
    u = q[:3]; w = q[3]
    return 2.0 * np.dot(u, v) * u + (w * w - np.dot(u, u)) * v + 2.0 * w * np.cross(u, v)


def qaxis(axis, deg):
    axis = np.asarray(axis, float); axis = axis / np.linalg.norm(axis)
    h = math.radians(deg) / 2.0
    return np.concatenate([axis * math.sin(h), [math.cos(h)]])


def qfromto(a, b):
    a = a / np.linalg.norm(a); b = b / np.linalg.norm(b)
    d = float(np.dot(a, b))
    if d < -0.999999:
        ax = np.cross(a, [1, 0, 0]) if abs(a[0]) < 0.9 else np.cross(a, [0, 1, 0])
        return qaxis(ax, 180.0)
    q = np.concatenate([np.cross(a, b), [1.0 + d]])
    return q / np.linalg.norm(q)


def qslerp(a, b, w):
    return G.slerp(np.asarray(a, float), np.asarray(b, float), w)


def qnorm(q):
    return q / np.linalg.norm(q)


def q_to_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


class Rig:
    def __init__(self, path):
        self.g = G.Glb(path)
        J = self.g.J
        self.n = len(J["nodes"])
        self.name = [nd.get("name", "") for nd in J["nodes"]]
        self.idx = {n: i for i, n in enumerate(self.name)}
        self.parent = [-1] * self.n
        for i, nd in enumerate(J["nodes"]):
            for c in nd.get("children", []):
                self.parent[c] = i
        self.rest_t = np.array([nd.get("translation", [0, 0, 0]) for nd in J["nodes"]], float)
        self.rest_r = np.array([nd.get("rotation", [0, 0, 0, 1]) for nd in J["nodes"]], float)
        self.rest_s = np.array([nd.get("scale", [1, 1, 1]) for nd in J["nodes"]], float)
        # top-down order
        order, seen = [], set()

        def visit(i):
            if i in seen:
                return
            if self.parent[i] >= 0:
                visit(self.parent[i])
            seen.add(i); order.append(i)
        for i in range(self.n):
            visit(i)
        self.order = order

    def sample_clip(self, chans, nframes, fps=30.0):
        """local t / r arrays per frame: (nframes, n, 3), (nframes, n, 4); unkeyed nodes stay at rest"""
        T = np.tile(self.rest_t, (nframes, 1, 1)); R = np.tile(self.rest_r, (nframes, 1, 1))
        for c in chans:
            i = c["node"]
            for f in range(nframes):
                v = G.sample(c["t"], c["v"], c["path"], f / fps)
                if c["path"] == "rotation":
                    R[f, i] = v
                elif c["path"] == "translation":
                    T[f, i] = v
        return T, R

    def fk(self, T, R):
        """world positions (n,3) and rotations (n,4) for one frame (scale ignored: all 1 except a few finger nodes)"""
        P = np.zeros((self.n, 3)); Q = np.zeros((self.n, 4))
        for i in self.order:
            p = self.parent[i]
            if p < 0:
                P[i] = T[i]; Q[i] = R[i]
            else:
                P[i] = P[p] + qrot(Q[p], T[i] * self.rest_s[p] if False else T[i]); Q[i] = qmul(Q[p], R[i])
        return P, Q
