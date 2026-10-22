"""Quick numpy-only BVH probe for the locomotion-transition sourcing pass.
Prints, per take, the hip speed profile (m/s, cgspeed scale 0.0564 m/unit), heading change and the frames where a
foot is planted, so start / stop / turn / jump windows can be picked without importing the take into Blender.

usage: python bvh_probe.py <bvh> [--csv out.csv] [--step 5]
"""
import sys, re, math
import numpy as np

SCALE = 0.056444  # cgspeed CMU units -> metres


class Bvh:
    def __init__(self, path):
        txt = open(path).read()
        head, data = txt.split("MOTION")
        self.names, self.parent, self.off, self.chan = [], [], [], []
        stack = []
        cur = None
        for line in head.splitlines():
            t = line.split()
            if not t:
                continue
            if t[0] in ("ROOT", "JOINT"):
                self.names.append(t[1]); self.parent.append(stack[-1] if stack else -1)
                self.off.append(None); self.chan.append(None)
                cur = len(self.names) - 1
                stack.append(cur)
            elif t[0] == "End":
                stack.append(-2)
            elif t[0] == "OFFSET" and stack and stack[-1] >= 0:
                self.off[stack[-1]] = np.array([float(x) for x in t[1:4]])
            elif t[0] == "CHANNELS":
                self.chan[stack[-1]] = t[2:]
            elif t[0] == "}":
                stack.pop()
        d = data.strip().splitlines()
        self.nf = int(d[0].split()[1]); self.ft = float(d[1].split()[2])
        self.fps = 1.0 / self.ft
        self.arr = np.array([[float(x) for x in l.split()] for l in d[2:2 + self.nf]])
        self.idx = {n: i for i, n in enumerate(self.names)}
        alias = {"LeftUpLeg": "LeftHip", "RightUpLeg": "RightHip", "LeftFoot": "LeftAnkle", "RightFoot": "RightAnkle",
                 "LeftToeBase": "LeftToe", "RightToeBase": "RightToe"}
        for a, b in alias.items():
            if a not in self.idx and b in self.idx:
                self.idx[a] = self.idx[b]
        self.scale = 0.01 if "Chest4" in self.idx else SCALE

    def fk(self):
        """world positions [nf, nj, 3] (units), hip yaw heading."""
        nf, nj = self.nf, len(self.names)
        pos = np.zeros((nf, nj, 3)); rot = np.zeros((nf, nj, 3, 3))
        col = 0
        loc = []
        for j in range(nj):
            ch = self.chan[j]
            vals = self.arr[:, col:col + len(ch)]; col += len(ch)
            p = np.tile(self.off[j], (nf, 1)); R = np.tile(np.eye(3), (nf, 1, 1))
            for k, c in enumerate(ch):
                v = vals[:, k]
                if c.endswith("position"):
                    ax = "XYZ".index(c[0]); p[:, ax] += v
                else:
                    a = np.radians(v); cs, sn = np.cos(a), np.sin(a)
                    M = np.tile(np.eye(3), (nf, 1, 1))
                    ax = c[0]
                    if ax == "X":
                        M[:, 1, 1] = cs; M[:, 1, 2] = -sn; M[:, 2, 1] = sn; M[:, 2, 2] = cs
                    elif ax == "Y":
                        M[:, 0, 0] = cs; M[:, 0, 2] = sn; M[:, 2, 0] = -sn; M[:, 2, 2] = cs
                    else:
                        M[:, 0, 0] = cs; M[:, 0, 1] = -sn; M[:, 1, 0] = sn; M[:, 1, 1] = cs
                    R = R @ M
            loc.append((p, R))
        for j in range(nj):
            p, R = loc[j]
            pj = self.parent[j]
            if pj < 0:
                pos[:, j] = p; rot[:, j] = R
            else:
                pos[:, j] = pos[:, pj] + np.einsum("nij,nj->ni", rot[:, pj], self.off[j][None].repeat(nf, 0)) * 0 + 0
                rot[:, j] = rot[:, pj] @ R
        # positions: recompute properly (offset in parent frame)
        for j in range(nj):
            pj = self.parent[j]
            if pj < 0:
                pos[:, j] = loc[j][0]
            else:
                pos[:, j] = pos[:, pj] + np.einsum("nij,j->ni", rot[:, pj], self.off[j])
        return pos * self.scale, rot


def probe(path, step=5):
    b = Bvh(path)
    pos, rot = b.fk()
    up = 1  # BVH y up
    hips = pos[:, b.idx["Hips"]]
    lf = pos[:, b.idx["LeftFoot"]]; rf = pos[:, b.idx["RightFoot"]]
    lt = pos[:, b.idx["LeftToeBase"]]; rt = pos[:, b.idx["RightToeBase"]]
    floor = min(np.percentile(lf[:, 1], 3), np.percentile(rf[:, 1], 3))
    fps = b.fps
    hxz = hips[:, [0, 2]]
    k = 5
    v = np.zeros(b.nf)
    v[k:-k] = np.linalg.norm(hxz[2 * k:] - hxz[:-2 * k], axis=1) / (2 * k / fps)
    # heading from hip line (left->right upleg)
    lu = pos[:, b.idx["LeftUpLeg"]]; ru = pos[:, b.idx["RightUpLeg"]]
    lat = (ru - lu)[:, [0, 2]]
    yaw = np.unwrap(np.arctan2(lat[:, 1], lat[:, 0]))
    print(path, "frames", b.nf, "fps %.0f" % fps, "dur %.2fs" % (b.nf / fps), "floor %.3f" % floor, "hipY %.2f" % np.median(hips[:, 1]))
    print(" t     v(m/s) yaw(deg)  L-foot-h R-foot-h  hipH  (planted: L R)")
    for f in range(0, b.nf, max(1, int(round(fps * step / 30)))):
        lh = lf[f, 1] - floor; rh = rf[f, 1] - floor
        print("%5.2f %6.2f %7.0f   %5.2f %5.2f  %5.2f   %s%s" % (f / fps, v[f], math.degrees(yaw[f] - yaw[0]), lh, rh, hips[f, 1] - floor,
                                                          "L" if lh < 0.09 else ".", "R" if rh < 0.09 else "."))
    return b


if __name__ == "__main__":
    st = 5
    if "--step" in sys.argv:
        st = int(sys.argv[sys.argv.index("--step") + 1])
    probe(sys.argv[1], st)
