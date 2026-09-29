"""Find turn events (heading change with little travel) in long CMU takes, numpy only.
usage: python scan_turns.py <bvh> [<bvh> ...]  -> prints [t0, t1] dyaw(deg, + = left/CCW) mean speed, foot planted state at both ends
"""
import sys, os, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bvh_probe import Bvh


def smooth(x, k):
    if k < 1:
        return x
    p = np.pad(x, (k, k), mode="edge")
    return np.convolve(p, np.ones(2 * k + 1) / (2 * k + 1), mode="valid")


for path in sys.argv[1:]:
    b = Bvh(path)
    pos, rot = b.fk()
    fps = b.fps
    lu = pos[:, b.idx["LeftUpLeg"]]; ru = pos[:, b.idx["RightUpLeg"]]
    lat = (ru - lu)[:, [0, 2]]
    # BVH is y-up; x right-handed with z: heading of the left->right hip line, +CCW seen from above (y up) is atan2(-z... ) sign fixed below
    yaw = np.unwrap(np.arctan2(lat[:, 1], lat[:, 0]))
    yaw = -np.degrees(yaw)          # y-up: rotating about +y CCW (seen from above) decreases atan2(z, x)
    hips = pos[:, b.idx["Hips"]][:, [0, 2]]
    k = int(0.1 * fps)
    v = np.zeros(b.nf); v[k:-k] = np.linalg.norm(hips[2 * k:] - hips[:-2 * k], axis=1) / (2 * k / fps)
    ys = smooth(yaw, int(0.15 * fps))
    rate = np.gradient(ys) * fps
    lf = pos[:, b.idx["LeftFoot"]][:, 1]; rf = pos[:, b.idx["RightFoot"]][:, 1]
    floor = min(np.percentile(lf, 3), np.percentile(rf, 3))
    both = (lf - floor < 0.09) & (rf - floor < 0.09)
    active = (np.abs(rate) > 45) & (v < 1.2)
    ev = []
    i = 0
    n = b.nf
    while i < n:
        if active[i]:
            j = i
            while j < n and (active[j] or (j + int(0.25 * fps) < n and active[j:j + int(0.25 * fps)].any())):
                j += 1
            ev.append((i, j)); i = j
        else:
            i += 1
    print(os.path.basename(path), "%.1fs" % (n / fps))
    for a, c in ev:
        if c - a < 0.3 * fps:
            continue
        d = ys[min(n - 1, c)] - ys[a]
        if abs(d) < 40:
            continue
        # extend to the previous / next moment with both feet planted and low speed
        a2 = a
        while a2 > 0 and not (both[a2] and v[a2] < 0.35):
            a2 -= 1
        c2 = c
        while c2 < n - 1 and not (both[c2] and v[c2] < 0.35):
            c2 += 1
        print("  turn %+5.0f deg  core %.2f-%.2f s  window %.2f-%.2f s  mean v %.2f  path %.2f m" % (
            ys[min(n - 1, c2)] - ys[a2], a / fps, c / fps, a2 / fps, c2 / fps, v[a:c].mean(),
            np.linalg.norm(hips[min(n - 1, c2)] - hips[a2]) * 1.0 * b.scale))
