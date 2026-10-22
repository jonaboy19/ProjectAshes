"""Low-poly stone shapes: chiselled monolith (superellipse section, taper, collars, lean, twist, slanted crown),
lathe dais, rough rocks. All deterministic (sine jitter) so LOD1 follows the same silhouette."""
import math, bmesh
from mathutils import Vector, Matrix
import stonekit as SK


def _lerp(a, b, t):
    return a + (b - a) * t


def profile_interp(prof, t):
    for i in range(len(prof) - 1):
        t0, s0 = prof[i]
        t1, s1 = prof[i + 1]
        if t <= t1:
            k = 0 if t1 == t0 else (t - t0) / (t1 - t0)
            return _lerp(s0, s1, k)
    return prof[-1][1]


def refine_profile(prof, extra):
    """insert `extra` evenly spaced t-values (LOD0 gets a denser silhouette than LOD1)."""
    ts = sorted(set([p[0] for p in prof] + [i / (extra) for i in range(extra + 1)]))
    return [(t, profile_interp(prof, t)) for t in ts]


def monolith(b, name, H, a, bd, prof, n=20, extra=0, p=4.0, lean=0.0, twist=0.0, cut=0.0, cut_phi=0.0,
             jit=0.05, seed=0.0, transform=None, chart_fn=None, meta=None, cap_top=True):
    prof = refine_profile(prof, extra) if extra else prof
    sec = SK.superellipse(n, a, bd, p)
    rings = []
    for (t, s) in prof:
        ring = []
        for i, (x0, y0) in enumerate(sec):
            th = 2 * math.pi * i / n
            j = 1 + jit * (math.sin(3 * th + seed + t * 4.1) * 0.6 + math.sin(5 * th + seed * 1.7 + t * 9.0) * 0.4)
            x, y = x0 * s * j, y0 * s * j
            tw = twist * t
            xr = x * math.cos(tw) - y * math.sin(tw)
            yr = x * math.sin(tw) + y * math.cos(tw)
            z = H * t
            if cut:
                w = max(0.0, (t - 0.78) / 0.22) ** 1.2
                z -= cut * H * w * (0.5 + 0.5 * math.cos(th - cut_phi))
            xr += lean * H * (t ** 1.5)
            ring.append((xr, yr, z))
        rings.append(ring)
    fs, vs = b.ring_solid(rings, cap_top=cap_top, cap_bottom=False)
    b.finish_part(name, fs, chart_fn or SK.box_chart, transform, meta)


def lathe(b, name, profile, N=24, jit=0.02, seed=0.0, chart_fn=None, transform=None, meta=None, cap_top=True):
    rings = []
    for (r, z) in profile:
        ring = []
        for i in range(N):
            th = 2 * math.pi * i / N
            j = 1 + jit * (math.sin(3 * th + seed + z * 3) * 0.6 + math.sin(7 * th + seed * 2.3) * 0.4)
            ring.append((r * j * math.cos(th), r * j * math.sin(th), z))
        rings.append(ring)
    fs, vs = b.ring_solid(rings, cap_top=cap_top, cap_bottom=False)
    b.finish_part(name, fs, chart_fn or SK.box_chart, transform, meta)


def rock(b, name, size, sub=2, seed=0.0, squash=0.7, transform=None, meta=None):
    bm = b.bm
    n0 = len(bm.faces)
    res = bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=0.5)
    vs = res['verts']
    for v in vs:
        c = v.co
        j = 1 + 0.28 * (math.sin(c.x * 9 + seed) * 0.5 + math.sin(c.y * 7 + seed * 1.3) * 0.3 + math.sin(c.z * 8 + seed * 0.7) * 0.2)
        v.co = Vector((c.x * j * size[0], c.y * j * size[1], (c.z * j * size[2]) * 1.0))
    # flatten bottom so rocks sit
    for v in vs:
        v.co.z = max(v.co.z, -size[2] * 0.25)
    bm.faces.ensure_lookup_table()
    fs = [bm.faces[i] for i in range(n0, len(bm.faces))]
    # icosphere faces are triangles; wrap in finish_part (triangulate is a no-op)
    b.finish_part(name, fs, SK.rock_chart, transform, meta)


def xform(pos=(0, 0, 0), yaw=0.0, tilt_x=0.0, tilt_y=0.0, scale=1.0):
    m = Matrix.Translation(pos) @ Matrix.Rotation(yaw, 4, 'Z') @ Matrix.Rotation(tilt_y, 4, 'Y') @ Matrix.Rotation(tilt_x, 4, 'X')
    if scale != 1.0:
        m = m @ Matrix.Scale(scale, 4)
    return m
