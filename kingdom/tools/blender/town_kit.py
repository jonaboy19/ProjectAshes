"""Town / landmark kit for Rising Ashes (bpy, Blender 5.x).

Extends village_kit.VK (same palettes, materials and look as the Blender
village houses and the adventurer guild) with the parts stone landmarks and
fortifications need:

- stone_face():  coursed masonry face (one quad per block, gaps over a dark
  core) that understands ARCHED and POINTED openings as well as rectangles:
  blocks are cut to the curve so the voussoir ring sits cleanly on them.
- stone_ring():  the same masonry wrapped around a (optionally battered)
  cylinder, for round towers, the well and stair turrets.
- flagstones():  a horizontal paved surface (wall-walks, plazas, well apron).
- arch_ring() / vault():  voussoirs and the barrel-vault soffit of passages.
- merlons() / ring_merlons():  crenellations (two courses over a dark core).
- tile_face() / pyramid_roof() / hip_roof() / cone_roof():  roofs made of
  individual tiles/shingles in courses, for any trapezoid / triangle face and
  for cones (turret roofs).
- lathe():  surfaces of revolution (bells, finials, buckets, lantern caps).
- quads():  raw coloured polygons.

Everything uses the Kit frame stack, so all helpers work inside
`with k.side(...)` wall frames (face = XZ plane at y=0, outward = -Y).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from village_kit import VK, palette, variant_arg, IRON, MORTAR, GLASS_C, STONE, ROOF, H
from ra_kit import Kit, hexc, vary, mix
import bmesh
from mathutils import Vector, Matrix

DRESSED = hexc("c8bfae")
LIMESTONE = H("bdb29c", "b0a58e", "c7bda8", "a99e88", "c2b69c", "b5a88f")
WALLSTONE = H("8a8378", "968e80", "7d776d", "9c9383", "736e66", "8e8577", "857e72")


def arch_top(cx, R, spring, Rp=None):
    """z of the intrados (or, with R/Rp grown by the ring, of the extrados) of a
    round (Rp=None) or two-centred pointed arch of half-span R."""
    Rp = R if Rp is None else Rp
    off = Rp - R

    def f(x):
        d = x - cx
        if abs(d) >= R:
            return spring
        c = off if d < 0 else -off      # each half's centre sits on the opposite side
        return spring + math.sqrt(max(0.0, Rp * Rp - (d - c) ** 2))
    return f


def rect_hole(x0, z0, x1, z1):
    return dict(x0=x0, x1=x1, z0=z0, top=lambda x, z1=z1: z1, zmax=z1, curved=False)


def arch_hole(cx, w, z0, spring, ring=0.0, pointed=0.0):
    """Opening of width w (x centred on cx) from z0, straight jambs to `spring`,
    then a round (pointed=0) or pointed arch. `ring` grows the cut outwards
    (the voussoir ring width) so the masonry stops at the extrados."""
    R = w / 2
    Rp = R * (1 + pointed)
    top = arch_top(cx, R + ring, spring, Rp + ring)
    return dict(x0=cx - R - ring, x1=cx + R + ring, z0=z0, top=top, zmax=top(cx), curved=True)


class TK(VK):
    # ------------------------------------------------------------ colours
    def dressed(self, amt=0.35):
        return mix(self.stone(), DRESSED, amt)

    # ------------------------------------------------------------ raw polys
    def quads(self, polys, cols, mat, grime=True, smooth=None):
        t = bmesh.new()
        lay = t.faces.layers.int.new("cid")
        for i, pp in enumerate(polys):
            vs = [t.verts.new(p) for p in pp]
            try:
                f = t.faces.new(vs)
            except ValueError:
                continue
            f[lay] = i
        self._merge(t, mat, (1, 1, 1), None, smooth, 0.0, lambda f: cols[f[lay]], grime)

    # ------------------------------------------------------------ masonry layout
    def _layout(self, w, h, holes=(), bw=0.9, bh=0.45, gap=0.03, push=0.035, stagger=True, top_fn=None,
                breaks=(), rows=None, color_fn=None, sub=None, x0=None):
        """2D block layout on x in [x0, x0+w], z in [0, h]. Returns pieces
        (xa, xb, z_bl, z_br, z_tl, z_tr, y_a, y_b, colour); blocks crossing a
        curved opening are split into narrow pieces cut to the arch."""
        color_fn = color_fn or self.stone
        X0 = -w / 2 if x0 is None else x0
        X1 = X0 + w
        n = rows or max(1, round(h / bh))
        bh = h / n
        g = gap / 2
        out = []
        for r in range(n):
            z0, z1 = r * bh, (r + 1) * bh
            zc = (z0 + z1) / 2
            xs = [X0]
            x = X0 + bw * (random.uniform(0.35, 0.75) if (stagger and r % 2) else random.uniform(0.8, 1.2))
            while x < X1 - bw * 0.4:
                xs.append(x)
                x += bw * random.uniform(0.7, 1.3)
            xs.append(X1)
            for i in range(len(xs) - 1):
                a, b = xs[i], xs[i + 1]
                rel = [hl for hl in holes if hl["x0"] < b and hl["x1"] > a and hl["z0"] < z1 and hl["zmax"] > z0]
                hard = {a, b}
                cuts = {a, b}
                for hl in rel:
                    for c in (hl["x0"], hl["x1"]):
                        if a < c < b:
                            cuts.add(c)
                            hard.add(c)
                    if hl["curved"]:
                        lo, hi = max(a, hl["x0"]), min(b, hl["x1"])
                        m = max(1, math.ceil((hi - lo) / max(0.2, bw * 0.25)))
                        for j in range(1, m):
                            cuts.add(lo + (hi - lo) * j / m)
                for c in breaks:
                    if a < c < b:
                        cuts.add(c)
                if sub:
                    m = max(1, math.ceil((b - a) / sub))
                    for j in range(1, m):
                        cuts.add(a + (b - a) * j / m)
                cuts = sorted(cuts)
                col = color_fn()
                y0 = -random.uniform(0.0, push)
                tilt = random.uniform(-0.012, 0.012) / max(0.2, b - a)
                for p, q in zip(cuts[:-1], cuts[1:]):
                    xc = (p + q) / 2
                    hl = next((hh for hh in rel if hh["x0"] < xc < hh["x1"]), None)
                    bl = br = z0
                    tl = tr = z1
                    if hl is not None:
                        if zc < hl["z0"]:
                            tl = tr = min(z1, hl["z0"])
                        else:
                            bl, br = max(z0, hl["top"](p)), max(z0, hl["top"](q))
                            if bl >= z1 - 0.04 and br >= z1 - 0.04:
                                continue
                            bl, br = min(bl, z1 - 0.04), min(br, z1 - 0.04)
                    if top_fn is not None:
                        tl, tr = min(tl, top_fn(p)), min(tr, top_fn(q))
                        if tl <= bl + 0.04 and tr <= br + 0.04:
                            continue
                        tl, tr = max(tl, bl + 0.02), max(tr, br + 0.02)
                    if tl - bl < 0.03 and tr - br < 0.03:
                        continue
                    pa = p + (g if p in hard else 0.0)
                    qb = q - (g if q in hard else 0.0)
                    if qb - pa < 0.03:
                        continue
                    out.append((pa, qb, bl + (g if bl == z0 else 0.0), br + (g if br == z0 else 0.0),
                                tl - g, tr - g, y0 + tilt * (pa - a), y0 + tilt * (qb - a), col))
        return out

    def stone_face(self, w, h, loc=(0, 0, 0), rot=(0, 0, 0), holes=(), mat=None, grime=True, **kw):
        """Masonry face in the XZ plane (x centred on loc, z from loc.z up to +h)
        facing -Y. `holes` from rect_hole()/arch_hole() in face coords (z from 0)."""
        pieces = self._layout(w, h, holes, **kw)
        self.push(loc, rot)
        polys, cols = [], []
        for pa, qb, bl, br, tl, tr, ya, yb, c in pieces:
            polys.append(((pa, ya, bl), (qb, yb, br), (qb, yb, tr), (pa, ya, tl)))
            cols.append(c)
        self.quads(polys, cols, mat or self.M("Matte"), grime=grime)
        self.pop()

    def stone_ring(self, cx, cy, r, z0, z1, holes=(), r_top=None, inward=False, mat=None, start=math.pi / 2,
                   seg_len=None, grime=True, **kw):
        """Masonry wrapped round a vertical cylinder of radius r (tapering to
        r_top at z1). u (arc length) starts at angle `start` (default: the
        back, +Y) and runs counter-clockwise, so the front (-Y) is at u=pi*r.
        Use ang_u() to place holes. inward=True faces the centre (well shaft)."""
        C = 2 * math.pi * r
        h = z1 - z0
        rt = r if r_top is None else r_top
        seg_len = seg_len or max(0.3, r * 0.26)
        pieces = self._layout(C, h, holes, x0=0.0, sub=seg_len, **kw)
        polys, cols = [], []
        sgn = -1 if inward else 1

        def P(u, z, y):
            rr = r + (rt - r) * (z / h) - sgn * y
            a = start + u / r
            return (cx + math.cos(a) * rr, cy + math.sin(a) * rr, z0 + z)
        for pa, qb, bl, br, tl, tr, ya, yb, c in pieces:
            pp = [P(pa, bl, ya), P(qb, br, yb), P(qb, tr, yb), P(pa, tl, ya)]
            polys.append(tuple(reversed(pp)) if inward else tuple(pp))
            cols.append(c)
        self.quads(polys, cols, mat or self.M("Matte"), grime=grime)

    @staticmethod
    def ang_u(r, ang, start=math.pi / 2):
        """Arc-length coordinate of angle `ang` for stone_ring (same start)."""
        return ((ang - start) % math.tau) * r

    def flagstones(self, x0, x1, y0, y1, z, size=(0.7, 0.5), color_fn=None, base=True, base_c=None, gap=0.04,
                   mat=None, grime=False):
        """Paved horizontal rectangle (top at z) of irregular slabs over a dark bed."""
        w, d = x1 - x0, y1 - y0
        color_fn = color_fn or (lambda: vary(mix(self.stone(), hexc("6c6862"), 0.25), 0.1))
        pieces = self._layout(w, d, (), bw=size[0], bh=size[1], gap=gap, push=0.0, color_fn=color_fn, x0=x0)
        polys, cols = [], []
        for pa, qb, bl, br, tl, tr, ya, yb, c in pieces:
            dz = random.uniform(-0.012, 0.012)
            polys.append(((pa, y0 + bl, z + dz), (qb, y0 + br, z + dz), (qb, y0 + tr, z + dz), (pa, y0 + tl, z + dz)))
            cols.append(c)
        self.quads(polys, cols, mat or self.M("Matte"), grime=grime)
        if base:
            self.box((w, d, 0.1), ((x0 + x1) / 2, (y0 + y1) / 2, z - 0.06), self.M("Matte"),
                     base_c or hexc("3b3732"), var=0, grime=False)

    # ------------------------------------------------------------ arches
    def arch_ring(self, cx, spring, R, ring=0.32, depth=0.36, y=0.0, n=None, Rp=None, color_fn=None, key=True,
                  mat=None):
        """Voussoirs of a round/pointed arch in the XZ plane (wall frame), centred
        at depth y. Rp > R makes it pointed (two-centred)."""
        color_fn = color_fn or (lambda: self.dressed())
        Rp = R if Rp is None else Rp
        off = Rp - R
        n = n or max(5, int(math.pi * (R + ring / 2) / 0.42)) | 1

        def pts_at(t, rad_add):
            # t in [0,1] across the arch, left springer -> right springer
            if Rp == R:
                a = math.pi * (1 - t)
                return (cx + math.cos(a) * (R + rad_add), spring + math.sin(a) * (R + rad_add))
            amax = math.acos(off / Rp)            # angle of the apex seen from each centre
            if t <= 0.5:
                a = math.pi - amax * (t / 0.5)
                c = cx + off
            else:
                a = amax - amax * ((t - 0.5) / 0.5)
                c = cx - off
            return (c + math.cos(a) * (Rp + rad_add), spring + math.sin(a) * (Rp + rad_add))
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            ex = 0.1 if (key and i == n // 2) else 0.0
            pts = [pts_at(t0, 0), pts_at(t0, ring + ex), pts_at(t1, ring + ex), pts_at(t1, 0)]
            self.prism(pts, depth, (0, y, 0), mat or self.M("Matte"), color_fn(), var=0, bevel=0.0)

    def vault(self, cx, R, spring, y0, y1, n=12, nd=None, Rp=None, color_fn=None, mat=None):
        """Barrel-vault soffit of a passage from y0 to y1 (wall frame), faces inward."""
        color_fn = color_fn or (lambda: mix(self.stone(), MORTAR, 0.25))
        Rp = R if Rp is None else Rp
        off = Rp - R
        f = arch_top(cx, R, spring, Rp)
        xs = [cx - R + 2 * R * i / n for i in range(n + 1)]
        nd = nd or max(1, round((y1 - y0) / 0.6))
        polys, cols = [], []
        for j in range(nd):
            ya, yb = y0 + (y1 - y0) * j / nd, y0 + (y1 - y0) * (j + 1) / nd
            for i in range(n):
                xa, xb = xs[i], xs[i + 1]
                za, zb = f(xa), f(xb)
                polys.append(((xa, ya, za), (xa, yb, za), (xb, yb, zb), (xb, ya, zb)))
                cols.append(color_fn())
        self.quads(polys, cols, mat or self.M("Matte"), grime=False)

    # ------------------------------------------------------------ battlements
    def merlon(self, xc, y, z, mw, th, h, rz=0.0, cap=True):
        """One merlon centred at (xc, y+th/2): a lower course and a slightly
        proud capping course, so the joint reads as a shadow line."""
        MA = self.M("Matte")
        self.push((xc, y + th / 2, z), (0, 0, rz))
        h1 = h * random.uniform(0.45, 0.55)
        self.box((mw - 0.03, th - 0.03, h1), (0, 0, h1 / 2), MA, self.stone(), var=0, grime=False)
        top_h = h - h1
        self.box((mw + (0.03 if cap else 0), th + (0.03 if cap else 0), top_h), (0, 0, h1 + top_h / 2), MA,
                 mix(self.stone(), hexc("a8a192"), 0.25) if cap else self.stone(), var=0, grime=False)
        self.pop()

    def merlons(self, x0, x1, z, h=1.0, th=0.5, mw=1.0, cw=0.6, y=0.0, start=None, slits=False):
        """Row of merlons along x in the wall frame, outer face at y. The pattern
        starts with a half crenel at x0 unless `start` (first merlon centre) is given."""
        period = mw + cw
        xc = x0 + cw / 2 + mw / 2 if start is None else start
        while xc + mw / 2 <= x1 + 1e-4:
            self.merlon(xc, y, z, mw, th, h)
            if slits and mw >= 0.9 and (slits is True or random.random() < slits):
                self.box((0.07, 0.02, h * 0.7), (xc, y - 0.012, z + h * 0.42), self.M("Matte"), hexc("1d1b19"),
                         var=0, grime=False)
            xc += period

    def ring_merlons(self, cx, cy, r, z, n, h=1.0, th=0.5, fill=0.6, phase=0.0, skip=()):
        """n merlons around a circle (outer face at radius r)."""
        seg = math.tau / n
        mw = 2 * r * math.sin(seg * fill / 2)
        for i in range(n):
            if i in skip:
                continue
            a = phase + i * seg
            x, y = cx + math.cos(a) * (r - th / 2), cy + math.sin(a) * (r - th / 2)
            self.push((x, y, z), (0, 0, a + math.pi / 2))
            self.merlon(0, -th / 2, 0, mw, th, h)
            self.pop()

    def slit(self, x, z0, h=1.0, w=0.12, y=0.0):
        """Arrow slit with dressed jambs (wall frame)."""
        MA = self.M("Matte")
        self.quad(w, h, (x, y - 0.045, z0 + h / 2), MA, hexc("1b1917"), var=0, grime=False)
        for sx in (-1, 1):
            self.box((0.22, 0.1, h + 0.1), (x + sx * (w / 2 + 0.11), y - 0.02, z0 + h / 2), MA, self.dressed(0.12),
                     var=0)
        self.box((w + 0.52, 0.11, 0.14), (x, y - 0.02, z0 + h + 0.07), MA, self.dressed(0.12), var=0)

    def ring_slit(self, cx, cy, r, ang, z0, h=1.0):
        self.push((cx + math.cos(ang) * r, cy + math.sin(ang) * r, 0), (0, 0, ang + math.pi / 2))
        self.slit(0, z0, h)
        self.pop()

    def corbels(self, cx, cy, r, z, n, drop=0.6, out=0.35, w=0.3, steps=2):
        """Ring of stepped stone corbels under an overhanging parapet/storey."""
        MA = self.M("Matte")
        for i in range(n):
            a = i * math.tau / n
            self.push((cx + math.cos(a) * r, cy + math.sin(a) * r, z), (0, 0, a + math.pi / 2))
            c = self.dressed(0.25)
            if steps > 1:
                self.box((w, out * 0.55, drop * 0.5), (0, -out * 0.55 / 2 + 0.05, -drop * 0.75), MA, c, var=0)
            self.box((w, out, drop * 0.5), (0, -out / 2 + 0.05, -drop * 0.25), MA, vary(c, 0.04), var=0)
            self.pop()

    # ------------------------------------------------------------ roofs
    def tile_face(self, lim, run, rise, mat, color_fn, tile_w=(0.35, 0.6), course=0.38, th=0.035, loc=(0, 0, 0),
                  rot=(0, 0, 0), gap=0.012, jag=0.05, butt_dark=0.72, droop=0.0, deck_mat=None,
                  deck_color=(0.3, 0.2, 0.12), deck_th=0.1):
        """Like Kit.shingle_side but the slope's x extent varies with height:
        lim(f) -> (x0, x1) at slope fraction f (0 eave .. 1 top). Makes hip ends,
        pyramid faces and spire faces."""
        a = math.atan2(rise, run)
        L = math.hypot(run, rise)
        d = Vector((0, math.cos(a), math.sin(a)))
        nrm = Vector((0, -math.sin(a), math.cos(a)))
        base = Vector((0, -run, 0))

        def P(u, s, n):
            return Vector((u, 0, 0)) + base + d * s + nrm * n
        polys, cols = [], []
        n_c = max(1, math.ceil(L / course))
        cl = L / n_c
        for i in range(n_c):
            s_lo = i * cl
            s_hi = min(L + 0.02, (i + 1) * cl + cl * 0.55)
            xa0, xa1 = lim(s_lo / L)
            xb0, xb1 = lim(min(1.0, s_hi / L))
            if xa1 - xa0 < 0.05:
                break
            # tiles laid across the lower edge; the row narrows toward its top edge
            u = xa0
            while u < xa1 - 0.03:
                w = random.uniform(*tile_w)
                u2 = min(xa1, u + w)
                if xa1 - u2 < 0.12:
                    u2 = xa1
                sl = s_lo - random.uniform(0.0, jag)
                lift = random.uniform(-0.006, 0.01)
                n_lo = 2 * th + lift - droop * random.random()
                n_hi = th * 0.3
                # top corners follow the narrowing (clamped to the row limits at s_hi)
                fa = (u - xa0) / max(1e-4, xa1 - xa0)
                fb = (u2 - xa0) / max(1e-4, xa1 - xa0)
                ut0 = xb0 + (xb1 - xb0) * fa
                ut1 = xb0 + (xb1 - xb0) * fb
                g = gap
                c = color_fn(i / max(1, n_c - 1))
                v = [P(u + g, sl, n_lo), P(u2 - g, sl, n_lo + random.uniform(-0.006, 0.006)),
                     P(ut1 - g * 0.5, s_hi, n_hi), P(ut0 + g * 0.5, s_hi, n_hi)]
                polys.append(v)
                cols.append(c)
                bottom = -0.06 if i == 0 else 0.0
                polys.append((P(u + g, sl, bottom), P(u2 - g, sl, bottom), v[1], v[0]))
                cols.append(tuple(x * butt_dark for x in c))
                u = u2
        self.push(loc, rot)
        self.quads(polys, cols, mat, grime=False)
        if deck_mat:
            e0, e1 = lim(0.0)
            t0, t1 = lim(1.0)
            q = [P(e0, 0, -0.005), P(e1, 0, -0.005), P(t1, L, -0.005), P(t0, L, -0.005)]
            q2 = [p - nrm * deck_th for p in q]
            polys = [q, list(reversed(q2)), (q2[0], q2[1], q[1], q[0]), (q2[1], q2[2], q[2], q[1]),
                     (q2[3], q2[0], q[0], q[3])]
            self.quads(polys, [deck_color] * 5, deck_mat, grime=False)
        self.pop()

    def hip_roof(self, cx, cy, hx, hy, z0, rise, mat, color_fn, over=0.5, ridge_c=None, **kw):
        """Four-sided hipped roof over the rectangle cx+-hx, cy+-hy from eave z0
        (eaves overhang `over`). Ridge along the longer axis. Returns ridge z."""
        ex, ey = hx + over, hy + over
        short = min(ex, ey)
        W = self.M("Wood")
        dc = kw.pop("deck_color", self.timber())
        faces = [(ex, ey, 0.0), (ey, ex, math.pi / 2), (ex, ey, math.pi), (ey, ex, -math.pi / 2)]
        for half_len, run, rz in faces:
            # face whose eave runs along local x with half length half_len, depth `run` to the ridge line
            ridge_half = max(0.0, half_len - short)
            r_ = short
            self.push((cx, cy, z0), (0, 0, rz))
            self.tile_face(lambda f, hl=half_len, rh=ridge_half: (-hl + (hl - rh) * f, hl - (hl - rh) * f),
                           r_, rise, mat, color_fn, loc=(0, -(run - r_), 0), deck_mat=W,
                           deck_color=dc, **kw)
            self.pop()
        rc = ridge_c or mix(self.p["roof"][0], (0, 0, 0), 0.3)
        # hips
        for sx in (-1, 1):
            for sy in (-1, 1):
                a = (cx + sx * ex, cy + sy * ey, z0 + 0.08)
                b = (cx + sx * max(0.0, ex - short), cy + sy * max(0.0, ey - short), z0 + rise + 0.08)
                self.bar(a, b, 0.2, 0.12, self.M("Roof"), rc, up=(0, 0, 1), bevel=0.02)
        if abs(ex - ey) > 0.05:
            if ex > ey:
                self.bar((cx - (ex - short), cy, z0 + rise + 0.08), (cx + (ex - short), cy, z0 + rise + 0.08), 0.22,
                         0.14, self.M("Roof"), rc, up=(0, 0, 1), bevel=0.02)
            else:
                self.bar((cx, cy - (ey - short), z0 + rise + 0.08), (cx, cy + (ey - short), z0 + rise + 0.08), 0.22,
                         0.14, self.M("Roof"), rc, up=(0, 0, 1), bevel=0.02)
        return z0 + rise

    def pyramid_roof(self, cx, cy, hx, z0, rise, mat, color_fn, over=0.4, hip_c=None, **kw):
        """Square pyramid / spire roof over cx+-hx, cy+-hx from eave z0."""
        e = hx + over
        W = self.M("Wood")
        dc = kw.pop("deck_color", self.timber())
        for rz in (0.0, math.pi / 2, math.pi, -math.pi / 2):
            self.push((cx, cy, z0), (0, 0, rz))
            self.tile_face(lambda f: (-e * (1 - f), e * (1 - f)), e, rise, mat, color_fn, deck_mat=W, deck_color=dc,
                           **kw)
            self.pop()
        hc = hip_c or mix(self.p["roof"][0], (0, 0, 0), 0.3)
        for sx in (-1, 1):
            for sy in (-1, 1):
                self.bar((cx + sx * e, cy + sy * e, z0 + 0.07), (cx, cy, z0 + rise + 0.07), 0.16, 0.1, self.M("Roof"),
                         hc, up=(0, 0, 1), bevel=0.015)
        return z0 + rise

    def cone_roof(self, cx, cy, r0, z0, h, mat, color_fn, tile_w=0.42, course=0.36, th=0.03, butt_dark=0.72,
                  deck_c=None, stop_r=0.22, droop=0.01):
        """Conical roof of tile courses (eave radius r0 at z0, apex at z0+h)."""
        L = math.hypot(r0, h)
        ca, sa = h / L, r0 / L         # normal = (ca*cos, ca*sin, sa)
        polys, cols = [], []

        def P(s, t, n):
            rr = r0 * (1 - s / L)
            return (cx + math.cos(t) * rr + math.cos(t) * ca * n, cy + math.sin(t) * rr + math.sin(t) * ca * n,
                    z0 + h * s / L + sa * n)
        n_c = max(1, math.ceil(L / course))
        cl = L / n_c
        for i in range(n_c):
            s_lo = i * cl
            s_hi = min(L - 0.01, (i + 1) * cl + cl * 0.55)
            rr = r0 * (1 - s_lo / L)
            if rr < stop_r:
                break
            nt = max(5, round(math.tau * rr / tile_w))
            ph = random.uniform(0, math.tau)
            for j in range(nt):
                t0 = ph + j * math.tau / nt
                t1 = ph + (j + 1) * math.tau / nt
                gt = 0.012 / max(rr, 0.1)
                sl = s_lo - random.uniform(0, 0.03)
                nl = 2 * th + random.uniform(-0.005, 0.01) - droop * random.random()
                v = [P(sl, t0 + gt, nl), P(sl, t1 - gt, nl), P(s_hi, t1 - gt, th * 0.3), P(s_hi, t0 + gt, th * 0.3)]
                c = color_fn(i / max(1, n_c - 1))
                polys.append(v)
                cols.append(c)
                b = -0.06 if i == 0 else 0.0
                polys.append((P(sl, t0 + gt, b), P(sl, t1 - gt, b), v[1], v[0]))
                cols.append(tuple(x * butt_dark for x in c))
        self.quads(polys, cols, mat, grime=False)
        # deck cone underneath (covers gaps, gives the eave its underside)
        self.cyl(r0 - 0.02, h - 0.05, (cx, cy, z0 - 0.08), self.M("Wood"), deck_c or self.timber(), segs=16, r2=0.02,
                 smooth=None, caps=True, var=0, grime=False)
        return z0 + h

    # ------------------------------------------------------------ lathe
    def lathe(self, prof, loc, mat, color, segs=12, smooth=45, rot=(0, 0, 0), color_fn=None, grime=False, var=0.04,
              vfn=None, vcol=None):
        """Surface of revolution of profile [(r, z), ...] around local Z. A point
        with r=0 closes the surface there. Profile order bottom->top gives an
        outward surface; going back down (r decreasing) gives the inside.
        vfn(Vector) -> Vector deforms vertices (noise, lean); vcol(Vector) ->
        sRGB colour paints per vertex (streaks) instead of a flat colour."""
        t = bmesh.new()
        rings = []
        for r, z in prof:
            if r <= 1e-5:
                rings.append([t.verts.new((0, 0, z))])
            else:
                rings.append([t.verts.new((math.cos(a) * r, math.sin(a) * r, z))
                              for a in (j / segs * math.tau for j in range(segs))])
        for i in range(len(rings) - 1):
            A, B = rings[i], rings[i + 1]
            for j in range(segs):
                j2 = (j + 1) % segs
                if len(A) == 1 and len(B) == 1:
                    continue
                if len(A) == 1:
                    t.faces.new((A[0], B[j], B[j2]))
                elif len(B) == 1:
                    t.faces.new((A[j], A[j2], B[0]))
                else:
                    t.faces.new((A[j], A[j2], B[j2], B[j]))
        if vfn is not None:
            for v in t.verts:
                v.co = Vector(vfn(v.co.copy()))
        c = vary(color, var) if var else color
        if vcol is not None:
            vl = t.verts.layers.float_color.new("vc")
            for v in t.verts:
                v[vl] = (*vcol(v.co), 1.0)
            self._merge(t, mat, c, self.xf(loc, rot), smooth, 0.0, None, grime,
                        loop_fn=lambda l: tuple(l.vert[vl])[:3])
            return
        self._merge(t, mat, c, self.xf(loc, rot), smooth, 0.02, color_fn, grime)

    # ------------------------------------------------------------ small details
    def cross(self, loc, h=1.0, mat=None, color=None, w=0.12):
        MT = mat or self.M("Metal")
        c = color or IRON
        x, y, z = loc
        self.box((w, w, h), (x, y, z + h / 2), MT, c, var=0, grime=False)
        self.box((h * 0.55, w, w), (x, y, z + h * 0.68), MT, c, var=0, grime=False)

    def banner_pole(self, x, y, z, h=3.0, color=hexc("9b1d24"), trim=hexc("d4a63a"), rz=0.0, flag_len=1.6,
                    flag_h=0.9, wave=0.18):
        """Pole with a swallow-tailed pennant that waves along +X (rotated by rz)."""
        MT, CL = self.M("Metal"), self.M("Cloth")
        self.cyl(0.05, h, (x, y, z), self.M("Wood"), hexc("4a3020"), segs=6, grime=False)
        self.sphere(0.09, (x, y, z + h + 0.04), MT, trim, subdiv=1, grime=False)
        self.push((x, y, z + h - 0.12), (0, 0, rz))
        nu, nv = 8, 3

        def sag(u, v):
            return (0, math.sin(u * 5.0 + v * 0.6) * wave * u, -0.1 * u * u)

        def col(u, v):
            if v < 0.14 or v > 0.86:
                return trim
            return vary(color, 0.03)
        # swallowtail by pulling the middle of the free edge in
        self.sheet(((0.04, 0, -flag_h), (flag_len, 0, -flag_h * 0.8), (0.04, 0, 0), (flag_len, 0, 0)), nu, nv, CL,
                   col, sag_fn=lambda u, v: (
                       -0.45 * flag_len * u ** 3 * (1 - abs(v - 0.5) * 2) * 0.6 + 0, *sag(u, v)[1:]),
                   smooth=60)
        self.pop()

    # ------------------------------------------------------------ church windows
    @staticmethod
    def lancet_geom(w, h, pointed):
        R = w / 2
        Rp = R * (1 + pointed)
        off = Rp - R
        rise = math.sqrt(Rp * Rp - off * off)
        return R, Rp, rise

    def lancet_hole(self, x, z0, w, h, pointed=0.7, ring=0.22):
        """Opening for lancet(): z0 is relative to the stone_face base."""
        R, Rp, rise = self.lancet_geom(w, h, pointed)
        return arch_hole(x, w, z0 - 0.02, z0 + h - rise, ring=ring, pointed=pointed)

    def lancet(self, x, z0, w, h, pointed=0.7, ring=0.22, depth=0.16, color_fn=None, bars=True, sill=True,
               cheap=False, fill="glass"):
        """Round-headed (pointed=0) or pointed window in the wall frame: voussoirs,
        dressed jamb stones filling the reveal, a sill and leaded glass set back.
        cheap=True uses one jamb stone per side and fewer voussoirs (big
        buildings); fill="louvre" puts slatted boards behind (belfries)."""
        color_fn = color_fn or (lambda: self.dressed(0.3))
        MA = self.M("Matte")
        R, Rp, rise = self.lancet_geom(w, h, pointed)
        spring = z0 + h - rise
        self.arch_ring(x, spring, R, ring=ring, depth=0.34, y=0.02, Rp=Rp if pointed else None, color_fn=color_fn,
                       n=(5 if w < 1.6 else 9) if cheap else (7 if w < 1.2 else 9))
        nj = 1 if cheap else max(2, round((spring - z0) / 0.45))
        for r in range(nj):
            wd = ring + (0.08 if r % 2 == 0 else -0.02) - (0.04 if cheap else 0.0)
            hh = (spring - z0) / nj
            for sx in (-1, 1):
                self.box((wd, 0.34, hh - 0.025), (x + sx * (R + wd / 2), 0.02, z0 + (r + 0.5) * hh), MA, color_fn(),
                         var=0)
        if sill:
            self.box((w + 2 * ring + 0.12, 0.42, 0.13), (x, -0.02, z0 - 0.06), MA, color_fn(), var=0)
        top = arch_top(x, R, spring, Rp)
        n = 6 if cheap else 10
        pts = [(x - R, z0), (x + R, z0)] + [(x + R - 2 * R * i / n, top(x + R - 2 * R * i / n)) for i in range(n + 1)]
        if fill == "louvre":
            self.quads([[(px, 0.3, pz) for px, pz in pts]], [hexc("1c1a18")], MA, grime=False)
            nb = max(3, int((spring - z0) / (0.5 if cheap else 0.26)))
            for j in range(nb):
                zz = z0 + 0.15 + j * (spring - z0 - 0.1) / nb
                self.box((w, 0.26, 0.04), (x, 0.16, zz), self.M("Wood"), vary(hexc("5e4a38"), 0.08),
                         rot=(0.6, 0, 0), var=0, grime=False)
            return spring
        self.quads([[(px, depth, pz) for px, pz in pts]], [vary(GLASS_C, 0.06)], self.M("Glass"), grime=False)
        if bars:
            MT = self.M("Metal")
            nz = max(2, round(h / 0.4)) if not cheap else 2
            for j in range(1, nz):
                zz = z0 + j * h / nz
                if zz > top(x) - 0.08:
                    continue
                half = R if zz <= spring else max(0.0, R - (zz - spring) * 0.9 * R / max(rise, 0.1))
                self.box((2 * half, 0.02, 0.025), (x, depth - 0.02, zz), MT, IRON, var=0, grime=False)
            self.box((0.025, 0.02, top(x) - z0), (x, depth - 0.02, (top(x) + z0) / 2), MT, IRON, var=0, grime=False)
        return spring

    def rose_hole(self, x, zc, r):
        """Opening for rose(): zc relative to the stone_face base."""
        return rect_hole(x - r + 0.02, zc - r + 0.02, x + r - 0.02, zc + r - 0.02)

    def rose(self, x, zc, r, spokes=8, color=None):
        """Round window with a moulded ring, spoked tracery and a hub (wall frame).
        The ring (0.45 r wide) covers the corners of rose_hole()."""
        MA = self.M("Matte")
        c = color or mix(self.stone(), DRESSED, 0.4)
        self.cyl(r + 0.02, 0.02, (x, 0.16, zc), self.M("Glass"), GLASS_C, rot=(math.pi / 2, 0, 0), segs=20,
                 smooth=None, grime=False)
        self.ring(r, r * 1.45, 0.34, (x, 0.02, zc), MA, c, segs=16)
        self.ring(r * 0.3, r * 0.42, 0.16, (x, 0.08, zc), MA, c, segs=12)
        for i in range(spokes // 2):
            self.box((2 * r, 0.12, 0.08), (x, 0.1, zc), MA, c, rot=(0, i * math.pi / (spokes // 2), 0), var=0)

    def buttress(self, x0, x1, y_out, z_steps, color_fn=None, top_c=None, bw=0.55, bh=0.42):
        """Stepped wall buttress in the wall frame: spans x0..x1 on the face,
        z_steps = [(z_top, projection), ...] from the ground up, each stage with
        a sloped weathering on top. Built of coursed stone on its three faces."""
        color_fn = color_fn or self.stone
        MA = self.M("Matte")
        w = x1 - x0
        xc = (x0 + x1) / 2
        z0 = 0.0
        for zt, proj in z_steps:
            self.box((w - 0.1, proj, zt - z0), (xc, -proj / 2 + 0.05, (z0 + zt) / 2), MA, MORTAR, var=0, grime=False)
            self.stone_face(w, zt - z0, loc=(xc, -proj, z0), bw=bw, bh=bh, color_fn=color_fn)
            for sx in (-1, 1):
                self.stone_face(proj, zt - z0, loc=(xc + sx * w / 2, -proj / 2, z0), rot=(0, 0, sx * math.pi / 2),
                                bw=bw, bh=bh, color_fn=color_fn)
            # weathering: sloped dressed cap
            tc = top_c or self.dressed(0.3)
            self.prism([(-proj - 0.04, 0.0), (0.0, 0.0), (0.0, proj * 0.75 + 0.1), (-proj - 0.04, 0.1)], w + 0.06,
                       (xc, 0, zt), MA, tc, rot=(0, 0, math.pi / 2), var=0)
            z0 = zt
