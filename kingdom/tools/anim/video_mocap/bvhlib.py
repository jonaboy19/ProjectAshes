"""Minimal BVH reader / FK / writer (numpy). Right-handed, Y-up, metres. Channel order per joint is read from the file."""
import numpy as np

def rot_x(a): c, s = np.cos(a), np.sin(a); return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])
def rot_y(a): c, s = np.cos(a), np.sin(a); return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])
def rot_z(a): c, s = np.cos(a), np.sin(a); return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])
ROT = {"X": rot_x, "Y": rot_y, "Z": rot_z}

def mat_to_euler_zxy(R):
    """R = Rz(z) @ Rx(x) @ Ry(y)  ->  (z, x, y) radians."""
    x = np.arcsin(np.clip(R[2, 1], -1, 1))
    if abs(R[2, 1]) < 0.99999:
        y = np.arctan2(-R[2, 0], R[2, 2]); z = np.arctan2(-R[0, 1], R[1, 1])
    else:  # gimbal
        y = 0.0; z = np.arctan2(R[1, 0], R[0, 0])
    return z, x, y

class BVH:
    def __init__(self):
        self.names, self.parent, self.offset, self.channels = [], [], [], []
        self.end_sites = {}      # joint index -> offset of its End Site
        self.frames = None       # [T, nchan]
        self.fps = 30.0

    @staticmethod
    def load(path):
        b = BVH(); toks = open(path).read().replace("{", " { ").replace("}", " } ").split()
        i = 0; stack = []; cur = None
        while i < len(toks):
            t = toks[i]
            if t in ("ROOT", "JOINT"):
                b.names.append(toks[i + 1]); b.parent.append(stack[-1] if stack else -1)
                b.offset.append(None); b.channels.append([]); cur = len(b.names) - 1; i += 2
            elif t == "End":     # End Site { OFFSET x y z }
                b.end_sites[cur] = [float(toks[i + 4]), float(toks[i + 5]), float(toks[i + 6])]; i += 8
            elif t == "{":
                stack.append(cur if cur is not None else -1); i += 1
            elif t == "}":
                stack.pop(); cur = stack[-1] if stack else None; i += 1
            elif t == "OFFSET":
                v = [float(toks[i + 1]), float(toks[i + 2]), float(toks[i + 3])]
                b.offset[cur] = v; i += 4
            elif t == "CHANNELS":
                n = int(toks[i + 1]); b.channels[cur] = toks[i + 2:i + 2 + n]; i += 2 + n
            elif t == "MOTION":
                nf = int(toks[i + 2]); ft = float(toks[i + 5]); b.fps = 1 / ft
                vals = np.array(toks[i + 6:], float); nch = sum(len(c) for c in b.channels)
                b.frames = vals[:nf * nch].reshape(nf, nch); break
            else:
                i += 1
        b.offset = [np.array(o) for o in b.offset]
        return b

    def fk(self, upto=None):
        """Global joint positions [T, J, 3] and rotation matrices [T, J, 3, 3]."""
        T, J = len(self.frames), len(self.names)
        P = np.zeros((T, J, 3)); R = np.zeros((T, J, 3, 3)); c0 = 0
        for j in range(J):
            ch = self.channels[j]; vals = self.frames[:, c0:c0 + len(ch)]; c0 += len(ch)
            pos = np.tile(self.offset[j], (T, 1)); Rl = np.tile(np.eye(3), (T, 1, 1))
            posch = {n[0]: vals[:, k] for k, n in enumerate(ch) if n.endswith("position")}
            if posch:
                for a, v in posch.items(): pos[:, "XYZ".index(a)] = v
            for k, n in enumerate(ch):
                if n.endswith("rotation"):
                    a = np.radians(vals[:, k]); M = np.array([ROT[n[0]](x) for x in a]); Rl = Rl @ M
            p = self.parent[j]
            if p < 0:
                P[:, j] = pos; R[:, j] = Rl
            else:
                P[:, j] = P[:, p] + np.einsum("tij,tj->ti", R[:, p], pos); R[:, j] = R[:, p] @ Rl
        return P, R

def write_bvh(path, names, parent, offset, end_sites, root_pos, local_R, fps):
    """local_R [T,J,3,3]; root_pos [T,3] (metres). Channels: root Xpos Ypos Zpos Zrot Xrot Yrot, others Zrot Xrot Yrot. Units: metres."""
    T, J = local_R.shape[:2]
    kids = [[j for j in range(J) if parent[j] == i] for i in range(J)]
    out = ["HIERARCHY"]
    def emit(j, d):
        ind = "  " * d
        out.append("%s%s %s" % (ind, "ROOT" if parent[j] < 0 else "JOINT", names[j]))
        out.append(ind + "{")
        o = offset[j]; out.append("%s  OFFSET %.5f %.5f %.5f" % (ind, *o))
        out.append(ind + "  CHANNELS " + ("6 Xposition Yposition Zposition Zrotation Xrotation Yrotation" if parent[j] < 0 else "3 Zrotation Xrotation Yrotation"))
        for k in kids[j]: emit(k, d + 1)
        if not kids[j]:
            e = end_sites.get(j, (0, 0.05, 0))
            out.append(ind + "  End Site"); out.append(ind + "  {"); out.append("%s    OFFSET %.5f %.5f %.5f" % (ind, *e)); out.append(ind + "  }")
        out.append(ind + "}")
    emit(0, 0)
    out.append("MOTION"); out.append("Frames: %d" % T); out.append("Frame Time: %.8f" % (1.0 / fps))
    prev = [None] * J
    rows = []
    for t in range(T):
        row = []
        for j in range(J):
            z, x, y = mat_to_euler_zxy(local_R[t, j])
            e = np.array([z, x, y])
            if prev[j] is not None:
                e = prev[j] + (e - prev[j] + np.pi) % (2 * np.pi) - np.pi     # unwrap
            prev[j] = e
            if j == 0: row += list(root_pos[t])
            row += list(np.degrees(e))
        rows.append(" ".join("%.4f" % v for v in row))
    out += rows
    open(path, "w").write("\n".join(out) + "\n")
