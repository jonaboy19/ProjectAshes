"""Foot planting for quadruped / multi-leg creatures: re-solves the leg chains (CCD on the real skinned foot point) so that
stance feet stay put on the ground while the root travels at ground speed v (m/s, along the facing direction -Y).
The body, spine, head and tail channels of the clip are NOT touched; only the leg bones of feet that slid change."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qrig import *


class Foot:
    """A foot = set of mesh vertices (rest) + the bones that skin them. point(P) is the skinned centroid (arm space)."""
    def __init__(self, rig, name, vidx, chain):
        self.name, self.chain = name, chain
        self.terms = []                        # (bone, homogeneous rest vector already multiplied by R_bone^-1)
        mesh = rig.mesh
        rest = rig.rest_points(vidx)
        acc = {}
        for k, vi in enumerate(vidx):
            for g in mesh.data.vertices[int(vi)].groups:
                b = mesh.vertex_groups[g.group].name
                a = acc.setdefault(b, np.zeros(4)); a[:3] += g.weight * rest[k]; a[3] += g.weight
        n = float(len(vidx))
        for b, a in acc.items():
            if a[3] / n < 0.01: continue
            h = Vector((a[0] / n, a[1] / n, a[2] / n, a[3] / n))
            self.terms.append((b, rig.R[b].inverted() @ h))
        self.bones = [b for b, _ in self.terms]

    def point(self, P):
        v = Vector((0, 0, 0))
        for b, h in self.terms:
            w = P[b] @ h                          # 4-vector (homogeneous weighted point)
            v += Vector((w[0], w[1], w[2]))
        return v


def quad_feet(rig, chains):
    """chains: {'FL': [...bones], 'FR':..., 'BL':..., 'BR':...} -> {name: Foot} (feet vertices = lowest 9% of the rest mesh by quadrant)"""
    n = len(rig.mesh.data.vertices)
    rig.arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
    V0 = eval_verts(rig.mesh); rig.arm.data.pose_position = 'POSE'; bpy.context.view_layer.update()
    H = V0[:, 2].max() - V0[:, 2].min()
    low = np.where(V0[:, 2] < V0[:, 2].min() + 0.09 * H)[0]; ym = np.median(V0[low, 1])
    feet = {}
    for k, ch in chains.items():
        sx = 1 if k[1] == 'L' else -1; front = k[0] == 'F'
        m = (np.sign(V0[low, 0]) == sx) & ((V0[low, 1] < ym) == front)
        feet[k] = Foot(rig, k, low[m], ch)
    return feet, H


def runs_cyclic(st):
    m = len(st)
    if not st.any(): return []
    if st.all(): return [list(range(m))]
    start = int(np.where(~st)[0][0]); runs = []; cur = []
    for j in [(start + i) % m for i in range(m)]:
        if st[j]: cur.append(j)
        elif cur: runs.append(cur); cur = []
    if cur: runs.append(cur)
    return runs


def detect_stance(Fz, Fy, dt, thr, vfrac=0.0):
    vy = np.gradient(Fy, dt)
    return (Fz < Fz.min() + thr) & (vy > vfrac * max(vy.max(), 1e-6))


def lock_clip(rig, feet, clip, v, dt=1 / 30.0, thr_frac=0.04, H=1.0, verbose=True, ground=None, min_run=2, base_channels=None):
    """returns list of channel dicts (n frames, last == first) with planted stance feet.
    v in m/s (metres of ground travel per second along -Y)."""
    a = rig.acts[clip]; n = int(round(a.frame_range[1] - a.frame_range[0])) + 1; m = n - 1
    base = base_channels or [rig.read(clip, f) for f in range(n)]
    Ps = [rig.fk(base[f]) for f in range(m)]
    s = rig.s
    out = [None] * m
    info = {}
    targets = {}
    for k, ft in feet.items():
        F = np.array([list(ft.point(P)) for P in Ps]) * s              # metres, frame x 3
        y = F[:, 1]; z = F[:, 2]
        st = detect_stance(z, y, dt, thr_frac * H)
        runs = [r for r in runs_cyclic(st) if len(r) >= min_run]
        tgt = F.copy()
        if not runs: targets[k] = (F, tgt, np.zeros(m, bool)); continue
        zg = z.min() if ground is None else ground
        # plant points (unwrapped time so a run crossing the loop seam is consistent)
        planted = np.zeros(m, bool); plant = []
        for r in runs:
            wraps = 0; ys = []; xs = []; ts = []
            for t, i in enumerate(r):
                if t and i < r[t - 1]: wraps += 1
                ts.append(i + wraps * m); ys.append(y[i] - v * dt * (i + wraps * m)); xs.append(F[i, 0])
            yp = float(np.mean(ys)); xp = float(np.mean(xs))
            plant.append((r, ts, yp, xp))
            for i, tt in zip(r, ts):
                tgt[i] = (xp, yp + v * dt * tt, zg + max(0.0, F[i, 2] - zg) * 0.0)
                planted[i] = True
        # swing: original path + offset blended between the two neighbouring plants
        idx = [r[0] for r in runs]
        order = sorted(range(len(plant)), key=lambda q: plant[q][0][0])
        for qi, q in enumerate(order):
            r_end = plant[q][0][-1]; nxt = plant[order[(qi + 1) % len(order)]]
            r_start = nxt[0][0]
            gap = (r_start - r_end - 1) % m                      # swing frames between them
            if gap <= 0: continue
            o0 = tgt[r_end] - F[r_end]
            i1 = r_start
            o1 = tgt[i1] - F[i1]
            # the next plant may sit across the seam: its target continues along the ground line
            for g in range(1, gap + 1):
                i = (r_end + g) % m
                u = smooth(g / (gap + 1.0))
                tgt[i] = F[i] + o0 * (1 - u) + o1 * u
        targets[k] = (F, tgt, planted)
    # solve
    for f in range(m):
        P = {n_: mm.copy() for n_, mm in Ps[f].items()}
        for k, ft in feet.items():
            F, tgt, planted = targets[k]
            if np.abs(tgt[f] - F[f]).max() < 1e-5: continue
            T_ = Vector(tgt[f] / s)
            err = rig.ccd(P, ft.chain, ft.chain[-1], None, T_, ft) if False else ccd_foot(rig, P, ft, T_)
            info.setdefault(k, []).append(err * s)
        out[f] = rig.channels(P, prev=(out[f - 1] if f else base[0]))
    out.append({n_: (c[0].copy(), c[1].copy(), c[2].copy()) for n_, c in out[0].items()})
    if verbose:
        for k, l in info.items(): print(f"LOCK {clip} {k}: solved {len(l)} frames, max residual {max(l) * 100:.2f} cm")
    return out


def ccd_foot(rig, P, ft, target, iters=80, tol=1e-6):
    chain = ft.chain
    for it in range(iters):
        if (ft.point(P) - target).length < tol: break
        for k in range(len(chain) - 1, -1, -1):
            h = P[chain[k]].translation
            a_ = ft.point(P) - h; b_ = target - h
            if a_.length < 1e-9 or b_.length < 1e-9: continue
            q = a_.rotation_difference(b_)
            rig.rotate_subtree_q(P, chain[k], h, q)
    return (ft.point(P) - target).length
