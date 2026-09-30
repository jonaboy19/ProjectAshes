

# ------------------------------------------------------------------ BRIDLE + REINS
HEAD_C0 = V(0, -1.20, 1.76)
HEAD_C1 = V(0, -1.42, 1.52)
HEAD_A = (HEAD_C1 - HEAD_C0).normalized()
HEAD_F = (V(0, 0, 1) - HEAD_A * HEAD_A.z).normalized()        # up-forward, perpendicular to the head axis


def head_c(t):
    return HEAD_C0.lerp(HEAD_C1, t)


def head_ring(t, thetas, reach=0.45):
    """surface points around the head at axis station t (theta 0 = front of the face, +90 = left side)"""
    c = head_c(t)
    out = []
    for th in thetas:
        d = HEAD_F * math.cos(math.radians(th)) + V(1, 0, 0) * math.sin(math.radians(th))
        h, n = ray(c + d * reach, -d)
        if h is not None:
            out.append(h)
    return out


def catmull(pts, n_per=2, closed=False):
    P = list(pts)
    out = []
    cnt = len(P)
    for i in range(cnt if closed else cnt - 1):
        p0 = P[(i - 1) % cnt] if closed else P[max(i - 1, 0)]
        p1 = P[i]
        p2 = P[(i + 1) % cnt]
        p3 = P[(i + 2) % cnt] if closed else P[min(i + 2, cnt - 1)]
        for k in range(n_per):
            u = k / n_per
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u + (-p0 + 3 * p1 - 3 * p2 + p3) * u ** 3))
    if not closed:
        out.append(P[-1])
    return out


def side_pts(side, ctrl):
    """points on the side of the head/neck (ray along -x), from (y, z) control points"""
    out = []
    for y, z in ctrl:
        x = env_x(y, z, side)
        out.append(V(x if x is not None else 0.1 * side, y, z))
    return out


def build_bridle():
    m = M("horse_tack_bridle")
    m.tag = "head"
    off = 0.008
    # noseband (full ring round the muzzle)
    ring = head_ring(0.78, range(0, 360, 30))
    strap(m, ring, 0.026, 0.005, "LEATHER", closed=True, off=off, solid=False)
    # browband: front arc under the ears
    arc = head_ring(0.10, range(-100, 101, 25))
    strap(m, arc, 0.022, 0.005, "RED", off=off, solid=False)
    # crown piece: over the poll behind the ears, plane y = -1.135
    cc = V(0, -1.135, 1.72)
    crown = []
    for phi in range(-100, 101, 25):
        d = V(math.sin(math.radians(phi)), 0, math.cos(math.radians(phi)))
        h, n = ray(cc + d * 0.5, -d)
        if h is not None:
            crown.append(h)
    strap(m, crown, 0.024, 0.005, "LEATHER", off=off, solid=False)
    # cheek pieces (crown side end -> bit ring) + rosettes
    for side in (1.0, -1.0):
        ctrl = [(-1.135, 1.66), (-1.19, 1.61), (-1.25, 1.555), (-1.31, 1.51), (-1.375, 1.495)]
        pts = catmull(side_pts(side, ctrl), 2)
        strap(m, pts, 0.020, 0.005, "LEATHER", off=off, solid=False)
        e = env_x(-1.20, 1.66, side)
        sphere(m, V((e or 0.12 * side) + side * 0.012, -1.20, 1.66), 0.010, 0.014, 0.014, "BRASS", 6, 3)
        # bit ring (in the y-z plane) at the mouth corner
        rc = V(0.088 * side, -1.385, 1.475)
        torus(m, rc, V(0, 1, 0), V(0, 0, 1), V(1, 0, 0), 0.026, 0.026, 0.0042, "STEEL", seg=10, sides=4)
    tube(m, [V(-0.09, -1.385, 1.475), V(0.09, -1.385, 1.475)], 0.0055, "STEEL", sides=4, up=V(0, 0, 1))
    return m.finish("horse_tack_bridle", w_surface({"head", "jaw"}, ["head"]))


def build_reins():
    m = M("horse_tack_reins")
    N = 12
    for side, sname in ((1.0, "L"), (-1.0, "R")):
        p0 = V(0.088 * side, -1.385, 1.502)         # top of the bit ring
        p1 = V(0.09 * side, -0.60, 1.721)           # rein_grip
        pts = []
        for i in range(N + 1):
            t = i / N
            p = p0.lerp(p1, t)
            p.z += -0.105 * math.sin(math.pi * t)                # slight sag
            tz = top_z(0.0, p.y)
            e = env_x(p.y, min(p.z, (tz - 0.01) if tz else p.z), side)
            need = (abs(e) + 0.035) if e is not None else 0.0
            if 0.05 < t < 0.97 and abs(p.x) < need:
                p.x = need * side
            pts.append(p)
        for _ in range(3):                                         # smooth the outward push
            pts = [pts[0]] + [(pts[i - 1] + pts[i] * 2 + pts[i + 1]) * 0.25 for i in range(1, N)] + [pts[-1]]
        i0 = len(m.tags)
        tube(m, pts, 0.0065, "DARK", sides=4, up=V(0, 0, 1))
        for j in range(i0, len(m.tags)):
            k = j - i0
            ring = min(k // 4, N)
            m.tags[j] = (sname, ring / N)

    def wf(co, tag):
        sname, t = tag
        s = smooth(0.0, 1.0, t)
        if s <= 0.0:
            return {"head": 1.0}
        if s >= 1.0:
            return {"rein_grip_" + sname: 1.0}
        return {"head": 1.0 - s, "rein_grip_" + sname: s}
    return m.finish("horse_tack_reins", wf)
