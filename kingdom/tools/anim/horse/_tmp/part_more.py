

# ------------------------------------------------------------------ helpers for the body-wrapping pieces
def env_up(y, z, side, tries=14):
    """env_x, but if nothing is hit (below the belly) look upward until the body is found"""
    for k in range(tries):
        x = env_x(y, z + 0.02 * k, side)
        if x is not None:
            return x
    return 0.0


def wrap_rows(ys, hem_fn, ncol, bias=1.6, off=0.012, zcap=0.004):
    """rows of (2*ncol+1) points from the left hem over the back to the right hem, outermost body surface + off"""
    rows = []
    for y in ys:
        zt = top_z(0.0, y) or 1.45
        zh = hem_fn(y, zt)
        lv = [zt - (zt - zh) * ((1.0 - i / ncol) ** bias) for i in range(ncol + 1)]      # hem -> top
        left = [V(env_up(y, min(z, zt - zcap), 1.0) + off, y, z) for z in lv]
        right = [V(-env_up(y, min(z, zt - zcap), -1.0) - off, y, z) for z in lv[::-1]]
        rows.append(left[:-1] + [V(0.0, y, zt + off)] + right[1:])
    return rows


def grid_faces(m, rows, keyfn, flip=False):
    vr = [[m.v(p) for p in r] for r in rows]
    for i in range(len(vr) - 1):
        for j in range(len(vr[0]) - 1):
            q = (vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1])
            m.face(q[::-1] if flip else q, keyfn(i, j, rows))
    return vr


def ring_cast_h(center, dirs, reach=1.2):
    """horizontal (x-y plane) or any ring: rays from outside toward the centre, first surface hit for each dir"""
    out = []
    for d in dirs:
        h, n = ray(center + d * reach, -d)
        if h is not None:
            out.append(h)
    return out


# ------------------------------------------------------------------ SADDLEBAGS
def build_saddlebags():
    m = M("horse_tack_saddlebags")
    yc, zc, ay, az, depth = 0.235, 1.20, 0.17, 0.18, 0.115
    N = 8
    for side in (1.0, -1.0):
        rows = []
        for i in range(N + 1):
            u = -1 + 2 * i / N
            row = []
            for j in range(N + 1):
                v = -1 + 2 * j / N
                ru = u * (1 - 0.55 * (1 - math.sqrt(max(0.0, 1 - v * v / 2))))
                rv = v * (1 - 0.55 * (1 - math.sqrt(max(0.0, 1 - u * u / 2))))
                y, z = yc + ru * ay, zc + rv * az
                xi = env_up(y, z, side)
                sq = max(abs(u), abs(v))
                d = depth * math.sqrt(max(0.0, 1.0 - sq ** 4)) + 0.004
                row.append(V(xi + side * (0.014 + d), y, z))
            rows.append(row)
        vr = [[m.v(p) for p in r] for r in rows]
        for i in range(N):
            for j in range(N):
                v_mid = -1 + 2 * (j + 0.5) / N
                key = "DARK" if v_mid > 0.42 else "LEATHER"           # lid (top) darker
                q = (vr[i][j], vr[i + 1][j], vr[i + 1][j + 1], vr[i][j + 1])
                m.face(q if side > 0 else q[::-1], key)
        # buckle on the lid
        bp = V(rows[N // 2][N - 2].x + side * 0.012, yc, zc + az * 0.30)
        box(m, bp, (0.014, 0.05, 0.05), "BRASS")
        box(m, V(bp.x, yc, zc + az * 0.05), (0.010, 0.020, 0.10), "DARK")
    # strap over the back joining the two bags (with the girth-side buckle)
    cc = V(0, 0.235, 1.10)
    pts = []
    for phi in range(-80, 81, 10):
        d = V(math.sin(math.radians(phi)), 0, math.cos(math.radians(phi)))
        h, n = ray(cc + d * 0.9, -d)
        if h is not None:
            pts.append(h)
    strap(m, pts, 0.040, 0.008, "DARK", off=0.014, solid=True)

    def wf(co, tag):
        s = smooth(0.05, 0.42, co.y)
        return {"spine_2": 1.0 - s, "spine_1": s}
    return m.finish("horse_tack_saddlebags", wf)


# ------------------------------------------------------------------ CART HARNESS
def build_cart_harness():
    m = M("horse_tack_cart_harness")
    X_ = V(1, 0, 0)
    # ---- collar: tall padded oval round the neck base, in a plane leaning with the neck
    m.tag = "collar"
    cc = V(0, -0.80, 1.40)
    D = V(0, 0.55, 0.83).normalized()
    pts = []
    for k in range(20):
        ph = 2 * math.pi * k / 20
        d = D * math.cos(ph) + X_ * math.sin(ph)
        h, n = ray(cc + d * 1.3, -d)
        if h is None:
            continue
        pts.append((h, d, ph))
    ring = [h + d * 0.046 for h, d, ph in pts]
    tube(m, ring, 0.038, "LEATHER", sides=6, closed=True, up=lambda i, p: X_)
    # hames: metal bars on both sides of the collar, brass knobs on top, draught rings at mid height
    for side in (1.0, -1.0):
        sel = [(h, d) for h, d, ph in pts if d.x * side > 0.35]
        sel.sort(key=lambda hd: -hd[0].z)
        hp = [h + d * 0.084 for h, d in sel]
        if len(hp) >= 3:
            strap(m, hp, 0.022, 0.012, "BRASS", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
            sphere(m, hp[0] + V(0, 0, 0.02), 0.020, 0.020, 0.020, "BRASS", 6, 3)
            mid = hp[len(hp) // 2]
            torus(m, mid + V(side * 0.012, 0.015, -0.006), V(0, 1, 0), V(0, 0, 1), X_, 0.022, 0.022, 0.0055, "IRON", seg=8, sides=4)
    # ---- harness back pad with terret, belly band, tug loops
    m.tag = "pad"
    ys = [-0.16 + 0.32 * i / 3.0 for i in range(4)]
    rows = wrap_rows(ys, lambda y, zt: 1.30, 3, 1.4, 0.014)
    vr = grid_faces(m, rows, lambda i, j, r: "DARK")
    # pad borders (red piping)
    for i in (0, len(rows) - 1):
        strap(m, catmull(rows[i], 2), 0.016, 0.004, "RED", off=0.019, solid=False, maxd=0.12)
    tp, tn = snap(V(0, 0.0, 1.55), 0.02)
    torus(m, tp + V(0, 0, 0.03), V(1, 0, 0), V(0, 0, 1), V(0, 1, 0), 0.026, 0.030, 0.0065, "BRASS", seg=8, sides=4)
    box(m, tp + V(0, 0, 0.004), (0.03, 0.05, 0.016), "BRASS")
    gy = 0.03
    gp = []
    for i in range(19):
        phi = math.radians(14 - 208 * i / 18.0)
        d = V(math.cos(phi), 0, math.sin(phi))
        h, nn = ray(V(0, gy, 1.17) + d * 1.2, -d)
        if h is not None:
            gp.append(h)
    strap(m, gp, 0.060, 0.010, "DARK", off=0.016, solid=True)
    for side in (1.0, -1.0):
        tug = V(0.27 * side, 0.02, 1.10)
        torus(m, tug, X_, V(0, 0, 1), V(0, 1, 0), 0.034, 0.030, 0.0075, "IRON", seg=8, sides=4)
        # hanger strap pad edge -> tug loop
        top = V(env_up(0.02, 1.28, side) * 1.0, 0.02, 1.28)
        pts_ = []
        for k in range(5):
            z = 1.28 + (1.13 - 1.28) * k / 4
            x = max(abs(env_up(0.02, z, side)) + 0.022, 0.0)
            pts_.append(V(x * side, 0.02, z))
        strap(m, pts_, 0.030, 0.008, "DARK", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0))
    # ---- traces: collar draught ring -> tug loop along the barrel side
    m.tag = "trace"
    for side in (1.0, -1.0):
        ys_ = [-0.84 + 0.86 * k / 9.0 for k in range(10)]
        pts_ = []
        for k, y in enumerate(ys_):
            t = k / 9.0
            z = 1.34 + (1.10 - 1.34) * t
            x = abs(env_up(y, z, side)) + 0.026
            if k == 9:
                x = 0.27
            pts_.append(V(x * side, y, z))
        strap(m, pts_, 0.030, 0.009, "LEATHER", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
    # ---- breeching round the hindquarters, hip straps, crupper
    m.tag = "breech"
    c = V(0, 0.45, 1.13)
    dirs = [V(math.sin(math.radians(a)), math.cos(math.radians(a)), 0) for a in range(-100, 101, 12)]
    bp = ring_cast_h(c, dirs)
    strap(m, bp, 0.070, 0.011, "LEATHER", off=0.018, solid=True)
    for side in (1.0, -1.0):
        ang = 100 * side
        e = ring_cast_h(c, [V(math.sin(math.radians(ang)), math.cos(math.radians(ang)), 0)])
        y_end = e[0].y if e else 0.45
        pts_ = []
        for k in range(8):
            y = y_end + (0.02 - y_end) * k / 7.0
            x = abs(env_up(y, 1.12, side)) + 0.024
            pts_.append(V(x * side, y, 1.13))
        strap(m, pts_, 0.040, 0.009, "LEATHER", off=0.0, snapto=False, up=lambda i, p, s=side: V(s, 0, 0), solid=True)
        # hip strap: over the loin down the flank to the breeching
        hp = []
        for k in range(8):
            t = k / 7.0
            y = 0.30 + 0.22 * t
            zt = top_z(0.06 * side, y) or 1.45
            z = zt + (1.14 - zt) * (t ** 1.2)
            x = abs(env_up(y, min(z, zt - 0.02), side)) + 0.016 if t > 0.05 else 0.05
            hp.append(V(x * side, y, z))
        strap(m, hp, 0.028, 0.008, "LEATHER", off=0.016, solid=False, maxd=0.12)
    # crupper along the topline to the tail dock
    cp = []
    for k in range(9):
        y = 0.10 + 0.56 * k / 8.0
        cp.append(V(0, y, (top_z(0.0, y) or 1.45)))
    strap(m, cp, 0.030, 0.008, "LEATHER", off=0.014, solid=False)

    def wf(co, tag):
        if tag == "collar":
            return bone_dist_weights(co, ["neck_1", "withers", "chest", "neck_2"], 3)
        if tag == "trace":
            return bone_dist_weights(co, ["withers", "chest", "spine_3", "spine_2"], 3)
        if tag == "breech":
            d = surface_weights(co, {"hips", "thigh_L", "thigh_R", "spine_1", "spine_2", "tail_1"})
            return d or {"hips": 1.0}
        d = surface_weights(co, {"spine_1", "spine_2", "spine_3", "belly", "chest"})
        return d or bone_dist_weights(co, ["spine_2", "spine_3"], 2)
    return m.finish("horse_tack_cart_harness", wf)


# ------------------------------------------------------------------ BARDING (knight's warhorse)
def build_barding():
    m = M("horse_tack_barding")
    # ---- caparison: cloth over the body from the withers to the croup, hem near the knees / hocks
    ys = [-0.70 + 1.56 * i / 21.0 for i in range(22)]
    belly = {}
    for y in ys:
        b = None
        for k in range(60):
            zz = 0.45 + 0.015 * k
            if env_x(y, zz, 1.0) is not None and (zz > 0.55):
                b = zz
                break
        belly[y] = b if b is not None else 0.7

    def hem(y, zt):
        lowest = belly[y]
        return max(0.66, lowest + 0.10 if lowest > 0.78 else 0.66)
    rows = wrap_rows(ys, hem, 6, 1.7, 0.026)
    ny, nc = len(rows), len(rows[0])
    e_y0, e_y1 = -0.34, 0.10
    e_z0, e_z1 = 0.92, 1.34

    def keyfn(i, j, r):
        c = (r[i][j] + r[i + 1][j + 1]) * 0.5
        if abs(c.x) > 0.12 and e_y0 <= c.y <= e_y1 and e_z0 <= c.z <= e_z1:
            return "EMBLEM"
        return "RED"
    grid_faces(m, rows, keyfn)

    def emb(co):
        if co.x >= 0:
            return ((co.y - e_y0) / (e_y1 - e_y0), (co.z - e_z0) / (e_z1 - e_z0))
        return ((e_y1 - co.y) / (e_y1 - e_y0), (co.z - e_z0) / (e_z1 - e_z0))
    m.emb = emb
    border = [rows[0][j] for j in range(nc)] + [rows[i][nc - 1] for i in range(1, ny)] + \
             [rows[ny - 1][j] for j in range(nc - 2, -1, -1)] + [rows[i][0] for i in range(ny - 2, 0, -1)]
    strap(m, catmull(border, 1, closed=True), 0.022, 0.004, "GOLD", closed=True, off=0.030, solid=False, maxd=0.12)
    # gold stripe along the spine
    strap(m, [V(0, y, (top_z(0.0, y) or 1.4)) for y in ys[::2]], 0.026, 0.004, "GOLD", off=0.030, solid=False, maxd=0.12)
    n_cap = len(m.tags)
    m.tag = "head"
    # ---- chanfron: steel face plate hugging the front of the face
    X_ = V(1, 0, 0)
    prow = []
    NT, NS = 9, 6
    for a in range(NT + 1):
        t = 0.04 + 0.90 * a / NT
        w = 0.080 - 0.036 * smooth(0.1, 0.9, t)
        row = []
        for b in range(NS + 1):
            s = -w + 2 * w * b / NS
            o = head_c(t) + X_ * s + HEAD_F * 0.5
            h, n = ray(o, -HEAD_F)
            if h is None:
                h = head_c(t) + X_ * s
                n = HEAD_F
            _, nn = snap(h, 0.0)
            row.append(h + (nn if nn is not None else n) * 0.014)
        prow.append(row)
    grid_faces(m, prow, lambda i, j, r: "STEEL", flip=True)
    edge = prow[0] + [prow[i][NS] for i in range(1, NT + 1)] + prow[NT][::-1][1:] + [prow[i][0] for i in range(NT - 1, 0, -1)]
    strap(m, edge, 0.012, 0.004, "BRASS", closed=True, off=0.016, solid=False, maxd=0.12)
    # forehead spike
    sp0 = prow[2][NS // 2]
    _, spn = snap(sp0, 0.0)
    spn = spn or HEAD_F
    tube(m, [sp0, sp0 + spn * 0.03, sp0 + spn * 0.075], 0.011, "BRASS", sides=5, up=V(1, 0, 0), r_fn=lambda i: (0.016, 0.010, 0.002)[i])
    n_head = len(m.tags)
    m.tag = "crinet"
    # ---- crinet: overlapping steel plates along the crest of the neck
    for k in range(7):
        y = -1.12 + 0.065 * k * 1.0
        zt = top_z(0.0, y) or 1.7
        cc = V(0, y, zt - 0.20)
        rr = []
        for dy, lift in ((-0.04, 0.0), (0.045, 0.014)):
            r_ = []
            for ang in range(-70, 71, 20):
                d = V(math.sin(math.radians(ang)), 0, math.cos(math.radians(ang)))
                h, n = ray(cc + V(0, dy, 0) + d * 0.7, -d)
                if h is None:
                    continue
                r_.append(h + d * (0.020 + lift))
            rr.append(r_)
        if len(rr[0]) == len(rr[1]) and len(rr[0]) > 2:
            for j in range(len(rr[0]) - 1):
                m.face((rr[0][j], rr[1][j], rr[1][j + 1], rr[0][j + 1]), "STEEL")
    neck_bones = ["neck_1", "neck_2", "neck_3", "neck_4", "withers", "head"]
    skip = {"mane", "tail"}

    def wf(co, tag):
        if tag == "head":
            return {"head": 1.0}
        if tag == "crinet":
            return bone_dist_weights(co, neck_bones, 2, 3.0)
        d = surface_weights(co, None)
        d = {b: w for b, w in d.items() if not b.startswith("mane") and not b.startswith("tail_") and not b.startswith("ear")}
        if not d:
            d = {"spine_3": 1.0}
        return d
    return m.finish("horse_tack_barding", wf)
