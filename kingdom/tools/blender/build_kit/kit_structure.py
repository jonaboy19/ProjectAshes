"""Structural kit pieces (walls, floors, roofs, stairs, defences). Godot coordinates, see kitlib.py"""
import math
from kitlib import *

REG = {}
def piece(f):
    REG[f.__name__] = f; return f

S2 = math.sqrt(0.5)
PI = math.pi
WIN = (-0.4, 0.4, 1.2, 2.2)
DOOR = (-0.55, 0.55, 0.0, 2.2)
LOGWIN = (-0.4, 0.4, 1.2, 2.1)      # log walls are built from 0.3 m layers
LOGDOOR = (-0.55, 0.55, 0.0, 2.4)

def rects(op, H=3.0):
    if op is None: return [(-1, 1, 0, H)]
    ox0, ox1, oy0, oy1 = op
    r = [(-1, ox0, 0, H), (ox1, 1, 0, H)]
    if oy0 > 0: r.append((ox0, ox1, 0, oy0))
    if oy1 < H: r.append((ox0, ox1, oy1, H))
    return r

def stone_field(p, rect, zin, zout, m, mat='kit_stone', rowh=0.5, colw=0.66, jit=0.012):
    x0, x1, y0, y1 = rect
    r = int(math.floor(y0 / rowh + 1e-6))
    while r * rowh < y1 - 1e-6:
        ya = max(y0, r * rowh); yb = min(y1, (r + 1) * rowh)
        if yb - ya > 0.06:
            off = 0.33 if r % 2 == 0 else 0.0
            cuts = [x0]
            n = math.ceil((x0 + 0.12 - off) / colw)
            while True:
                xc = off + n * colw
                if xc > x1 - 0.12: break
                cuts.append(xc); n += 1
            cuts.append(x1)
            for i in range(len(cuts) - 1):
                a, b = cuts[i], cuts[i + 1]
                if b - a < 0.1: continue
                zo = zout + p.rng.random() * jit
                ia = 0.012 if i > 0 else 0.006
                ib = 0.012 if i < len(cuts) - 2 else 0.006
                p.bx(a + ia, b - ib, ya + 0.01, yb - 0.01, zin, zo, mat, m, skip=('nz',))
        r += 1

def both_faces(p, rect, zin, zout, **kw):
    stone_field(p, rect, zin, zout, I, **kw)
    stone_field(p, rect, zin, zout, RY(PI), **kw)

def shutters(p):
    for sx in (-1, 1):
        a, b = (0.52, 0.92) if sx > 0 else (-0.92, -0.52)
        p.bx(a, b, 1.2, 2.2, 0.13, 0.17, 'kit_plank')
        for yy in (1.42, 1.98):
            p.bx(a, b, yy - 0.04, yy + 0.04, 0.17, 0.19, 'kit_iron')

# --------------------------------------------------------------- walls
def plaster_wall(p, op, H=3.0):
    for (x0, x1, y0, y1) in rects(op, H): p.bx(x0, x1, y0, y1, -0.08, 0.08, 'kit_plaster')
    p.post(-1, -0.8, -0.12, 0.12, 0, H, 'kit_timber'); p.post(0.8, 1, -0.12, 0.12, 0, H, 'kit_timber')
    p.bx(-0.8, 0.8, H - 0.2, H, -0.12, 0.12, 'kit_timber')
    if op is None:
        p.bx(-0.8, 0.8, 0, 0.2, -0.12, 0.12, 'kit_timber')
        p.beam((-0.85, 0.15, 0), (0.85, 2.85, 0), 0.18, 0.24, 'kit_timber', up=(0, 0, 1))
        return
    ox0, ox1, oy0, oy1 = op
    if oy0 == 0:   # door
        p.bx(-0.8, ox0 - 0.18, 0, 0.2, -0.12, 0.12, 'kit_timber'); p.bx(ox1 + 0.18, 0.8, 0, 0.2, -0.12, 0.12, 'kit_timber')
        p.bx(ox0 - 0.18, ox0, 0, oy1, -0.13, 0.13, 'kit_timber'); p.bx(ox1, ox1 + 0.18, 0, oy1, -0.13, 0.13, 'kit_timber')
        p.bx(ox0 - 0.18, ox1 + 0.18, oy1, oy1 + 0.2, -0.13, 0.13, 'kit_timber')
        p.beam((-0.5, 2.4, 0), (0.5, 2.8, 0), 0.14, 0.24, 'kit_timber', up=(0, 0, 1))
    else:          # window
        p.bx(-0.8, 0.8, 0, 0.2, -0.12, 0.12, 'kit_timber')
        p.bx(ox0 - 0.12, ox0, oy0, oy1, -0.13, 0.13, 'kit_timber'); p.bx(ox1, ox1 + 0.12, oy0, oy1, -0.13, 0.13, 'kit_timber')
        p.bx(ox0 - 0.12, ox1 + 0.12, oy1, oy1 + 0.15, -0.13, 0.13, 'kit_timber')
        p.bx(ox0 - 0.14, ox1 + 0.14, oy0 - 0.1, oy0, -0.2, 0.2, 'kit_timber')
        p.beam((-0.38, 2.35, 0), (0.38, 2.8, 0), 0.12, 0.24, 'kit_timber', up=(0, 0, 1))
        p.beam((-0.38, 0.2, 0), (0.38, 1.1, 0), 0.12, 0.24, 'kit_timber', up=(0, 0, 1))
        shutters(p)

def stone_wall(p, op, H=3.0, rowh=0.5):
    for rc in rects(op, H):
        x0, x1, y0, y1 = rc
        p.bx(x0, x1, y0, y1, -0.08, 0.08, 'kit_stone')
        both_faces(p, rc, 0.08, 0.12, rowh=rowh)
    if op is None: return
    ox0, ox1, oy0, oy1 = op
    p.bx(ox0 - 0.12, ox1 + 0.12, oy1, oy1 + 0.18, -0.14, 0.14, 'kit_timber')   # lintel
    if oy0 == 0:
        p.bx(ox0 - 0.1, ox0, 0, oy1, -0.13, 0.13, 'kit_timber'); p.bx(ox1, ox1 + 0.1, 0, oy1, -0.13, 0.13, 'kit_timber')
    else:
        p.bx(ox0 - 0.14, ox1 + 0.14, oy0 - 0.1, oy0, -0.17, 0.17, 'kit_stone')
        shutters(p)

def log_wall(p, op=None):
    for k in range(10):
        yc = 0.15 + 0.3 * k; ya, yb = yc - 0.15, yc + 0.15
        segs = [(-1.15, 1.15)]
        if op and ya >= op[2] - 1e-6 and yb <= op[3] + 1e-6:
            segs = [(-1.15, op[0] - 0.2), (op[1] + 0.2, 1.15)]
        for a, b in segs:
            p.cyl(T(a, yc, 0) @ RZ(-PI / 2), 0.15, b - a, 8, 'kit_log', rz=0.12)
    if op:
        ox0, ox1, oy0, oy1 = op
        p.post(ox0 - 0.2, ox0, -0.12, 0.12, oy0, oy1, 'kit_timber', c=0.02); p.post(ox1, ox1 + 0.2, -0.12, 0.12, oy0, oy1, 'kit_timber', c=0.02)
        if oy0 > 0: p.bx(ox0 - 0.2, ox1 + 0.2, oy0 - 0.06, oy0, -0.16, 0.16, 'kit_timber')

@piece
def wall_plaster(p): plaster_wall(p, None)
@piece
def wall_plaster_window(p): plaster_wall(p, WIN)
@piece
def wall_plaster_door(p): plaster_wall(p, DOOR)
@piece
def wall_stone(p): stone_wall(p, None)
@piece
def wall_stone_window(p): stone_wall(p, WIN)
@piece
def wall_stone_door(p): stone_wall(p, DOOR)
@piece
def wall_log(p): log_wall(p, None)
@piece
def wall_log_window(p): log_wall(p, LOGWIN)
@piece
def wall_log_door(p): log_wall(p, LOGDOOR)

@piece
def wall_half_stone(p):
    rc = (-1, 1, 0, 1.1)
    p.bx(-1, 1, 0, 1.1, -0.08, 0.08, 'kit_stone')
    both_faces(p, rc, 0.08, 0.12, rowh=0.55)
    p.bx(-1, 1, 1.1, 1.2, -0.16, 0.16, 'kit_stone')

# --------------------------------------------------------------- foundations / floors
@piece
def foundation_stone(p):
    p.bx(-0.96, 0.96, -0.5, 0.42, -0.96, 0.96, 'kit_stone')
    p.bx(-1, 1, 0.42, 0.5, -1, 1, 'kit_stone')
    for k in range(4):
        m = RY(k * PI / 2)
        rc = (-1, 1, -0.5, 0.42) if k % 2 == 0 else (-0.92, 0.92, -0.5, 0.42)
        stone_field(p, rc, 0.92, 1.0, m, rowh=0.5, colw=0.66)

@piece
def foundation_timber(p):
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.post(sx * 0.8 - 0.15, sx * 0.8 + 0.15, sz * 0.8 - 0.15, sz * 0.8 + 0.15, -0.5, 0.4, 'kit_timber', c=0.04)
    for sz in (-1, 1):
        p.bx(-0.65, 0.65, -0.5, 0.2, sz * 0.9 - 0.04, sz * 0.9 + 0.04, 'kit_plank')
        p.bx(-1, 1, 0.2, 0.4, sz * 0.9 - 0.1, sz * 0.9 + 0.1, 'kit_timber')
    for sx in (-1, 1):
        p.bx(sx * 0.9 - 0.04, sx * 0.9 + 0.04, -0.5, 0.2, -0.65, 0.65, 'kit_plank')
        p.bx(sx * 0.9 - 0.1, sx * 0.9 + 0.1, 0.2, 0.4, -0.8, 0.8, 'kit_timber')
    p.post(-0.15, 0.15, -0.15, 0.15, -0.5, 0.4, 'kit_timber', c=0.04)
    p.bx(-1, 1, 0.38, 0.5, -1, 1, 'kit_plank')

@piece
def floor_plank(p):
    for i in range(5):
        x0 = -1 + 0.4 * i
        p.bx(x0 + 0.006, x0 + 0.394, -0.07, 0, -1, 1, 'kit_plank')
    for z in (-0.7, 0.7):
        p.bx(-1, 1, -0.15, -0.07, z - 0.1, z + 0.1, 'kit_timber')

@piece
def floor_jetty(p):
    for i in range(5):
        x0 = -1 + 0.4 * i
        p.bx(x0 + 0.006, x0 + 0.394, -0.07, 0, -1.4, 1, 'kit_plank')
    p.bx(-1, 1, -0.22, 0, -1.5, -1.4, 'kit_timber')
    for z in (-1.2, -0.45, 0.5):
        p.bx(-1, 1, -0.15, -0.07, z - 0.1, z + 0.1, 'kit_timber')
    for x in (-0.55, 0.55):
        pts = [(-1.45, -0.15), (-0.9, -0.15), (-0.9, -0.85), (-1.1, -0.5)]
        p.ext('zy', pts, x - 0.08, x + 0.08, 'kit_timber')
        p.bx(x - 0.1, x + 0.1, -0.3, -0.15, -1.5, -1.38, 'kit_timber')

@piece
def stairs_wood(p):
    n = 12; dz = 4.0 / n
    for k in range(1, n + 1):
        zhi = 2 - dz * (k - 1); zlo = 2 - dz * k; yt = 0.25 * k
        p.bx(-0.9, 0.9, yt - 0.06, yt, zlo, zhi + 0.03, 'kit_plank')
        p.bx(-0.9, 0.9, 0.25 * (k - 1), yt - 0.06, zhi - 0.03, zhi, 'kit_plank', skip=('nz',))
    for sx in (-1, 1):
        p.beam((sx * 0.94, 0.03, 1.8), (sx * 0.94, 2.88, -2.0), 0.12, 0.3, 'kit_timber', up=(0, 1, 0))
    x = 0.93
    p.post(x - 0.07, x + 0.07, 1.78, 1.92, 0, 1.1, 'kit_timber', c=0.02)
    p.post(x - 0.07, x + 0.07, -1.97, -1.83, 2.9, 3.95, 'kit_timber', c=0.02)
    p.beam((x, 1.06, 1.85), (x, 3.875, -1.9), 0.1, 0.09, 'kit_timber', up=(1, 0, 0))
    for z in (1.1, 0.3, -0.5, -1.2):
        yt = 0.75 * (2 - z)
        p.bx(x - 0.025, x + 0.025, yt, yt + 0.95, z - 0.025, z + 0.025, 'kit_timber')

@piece
def pillar_wood(p):
    p.post(-0.15, 0.15, -0.15, 0.15, 0, 3, 'kit_timber', c=0.04)
    p.bx(-0.2, 0.2, 0, 0.12, -0.2, 0.2, 'kit_timber'); p.bx(-0.2, 0.2, 2.86, 3.0, -0.2, 0.2, 'kit_timber')

# --------------------------------------------------------------- roofs (slope frame: u along x, s up the slope, n outward)
SL = Matrix(((1, 0, 0, 0), (0, S2, S2, -0.3), (0, -S2, S2, 1.3), (0, 0, 0, 1)))
SLEN = 2.3 * math.sqrt(2)

def roof_courses(p, mat, rows, step, rowlen, tilew, thick, lift, base_mat='kit_timber'):
    p.roof = True
    p.bx(-1.05, 1.05, 0, SLEN, -0.2, -0.04, base_mat, SL)
    for k in range(rows):
        s0 = k * step; s1 = min(s0 + rowlen, SLEN)
        if s1 - s0 < 0.1: break
        n = int(round(2.1 / tilew))
        off = 0.0 if k % 2 == 0 else tilew / 2
        edges = [-1.05]
        e = -1.05 + (off if off else tilew)
        while e < 1.05 - 0.05:
            edges.append(e); e += tilew
        edges.append(1.05)
        for i in range(len(edges) - 1):
            a, b = edges[i] + 0.008, edges[i + 1] - 0.008
            if b - a < 0.05: continue
            pts = [(-thick, s0), (lift, s0), (0.0, s1), (-thick, s1)]
            p.ext('zy', pts, a, b, mat, SL)

@piece
def roof_slate(p): roof_courses(p, 'kit_slate', 8, 0.41, 0.5, 0.525, 0.05, 0.05)

@piece
def roof_shingle(p): roof_courses(p, 'kit_shingle', 9, 0.37, 0.48, 0.35, 0.05, 0.06)

@piece
def roof_thatch(p):
    p.roof = True
    L = SLEN
    pts = [(-0.35, L), (-0.35, 0.25), (-0.30, 0.04), (-0.18, -0.05), (-0.04, -0.03), (0.03, 0.15),
           (0.07, 0.8), (0.08, 1.6), (0.06, 2.5), (0.0, L)]
    p.ext('zy', pts, -1.05, 1.05, 'kit_thatch', SL)
    for i in range(10):
        u0 = -1.05 + i * 0.21
        slo = -0.12 - 0.1 * p.rng.random()
        p.bx(u0, u0 + 0.17, slo, 0.12, -0.32, -0.06, 'kit_thatch', SL)
    for s in (1.1, 2.1):
        p.bx(-1.05, 1.05, s, s + 0.07, 0.0, 0.12, 'kit_thatch', SL)

@piece
def roof_ridge_thatch(p):
    pts = [(-0.58, 1.55), (-0.5, 1.95), (-0.25, 2.2), (0.25, 2.2), (0.5, 1.95), (0.58, 1.55), (0.42, 1.6), (0, 1.96), (-0.42, 1.6)]
    p.ext('zy', pts, -1.0, 1.0, 'kit_thatch')
    for x in (-0.6, 0.0, 0.6):
        p.bx(x - 0.03, x + 0.03, 1.5, 1.72, 0.55, 0.6, 'kit_timber')
        p.bx(x - 0.03, x + 0.03, 1.5, 1.72, -0.6, -0.55, 'kit_timber')

def ridge_wood(p, mat):
    for sg in (-1, 1):
        pts = [(0, 2.0), (sg * 0.55, 1.45), (sg * 0.55, 1.58), (0, 2.14)]
        if sg < 0: pts = pts[::-1]
        p.ext('zy', pts, -1.0, 1.0, mat)
    p.bx(-1.0, 1.0, 2.1, 2.2, -0.08, 0.08, mat)

@piece
def roof_ridge_slate(p): ridge_wood(p, 'kit_slate')
@piece
def roof_ridge_shingle(p): ridge_wood(p, 'kit_shingle')

# --------------------------------------------------------------- gables
TRI = [(-1, 0), (1, 0), (-1, 2)]

@piece
def gable_plaster(p):
    p.ext('xy', TRI, -0.08, 0.08, 'kit_plaster')
    p.bx(-1, 1, 0, 0.2, -0.12, 0.12, 'kit_timber'); p.bx(-1, -0.8, 0.2, 2, -0.12, 0.12, 'kit_timber')
    p.beam((0.85, 0.15, 0), (-0.85, 1.85, 0), 0.2, 0.24, 'kit_timber', up=(0, 0, 1))
    p.beam((-0.8, 1.0, 0), (-0.05, 0.2, 0), 0.14, 0.24, 'kit_timber', up=(0, 0, 1))

@piece
def gable_stone(p):
    p.ext('xy', TRI, -0.08, 0.08, 'kit_stone')
    r = 0
    while r * 0.5 < 1.9:
        ya = r * 0.5; yb = min(ya + 0.5, 2.0)
        xe = 1 - yb - 0.02
        if xe < -0.85: break
        cuts = [-1]; off = 0.33 if r % 2 == 0 else 0.0
        c = off - 0.66 * 2
        while c < xe:
            if c > -0.88: cuts.append(c)
            c += 0.66
        cuts.append(xe)
        for i in range(len(cuts) - 1):
            a, b = cuts[i], cuts[i + 1]
            if b - a < 0.12: continue
            for sg in (1, -1):
                if sg > 0: p.bx(a + 0.01, b - 0.01, ya + 0.01, yb - 0.01, 0.08, 0.12 + p.rng.random() * 0.01, 'kit_stone', skip=('nz',))
                else: p.bx(a + 0.01, b - 0.01, ya + 0.01, yb - 0.01, -0.12, -0.08, 'kit_stone', skip=('pz',))
        r += 1
    p.beam((0.9, 0.1, 0), (-0.9, 1.9, 0), 0.16, 0.26, 'kit_stone', up=(0, 0, 1))

@piece
def gable_log(p):
    for k in range(7):
        yc = 0.15 + 0.3 * k; xe = 1 - (yc + 0.15)
        if xe < -0.8: break
        p.cyl(T(-1.1, yc, 0) @ RZ(-PI / 2), 0.15, xe + 1.1 + 0.05, 8, 'kit_log', rz=0.12)

# --------------------------------------------------------------- doors, gates, fences
@piece
def door_wood(p):
    for i in range(5):
        x0 = -0.52 + i * 0.21
        p.bx(x0 + 0.004, x0 + 0.206, 0, 2.15 - 0.02 * (i % 2), -0.04, 0.04, 'kit_plank')
    for y in (0.4, 1.1, 1.75):
        p.bx(-0.52, 0.45, y - 0.05, y + 0.05, 0.04, 0.055, 'kit_iron')
        p.bx(-0.52, -0.3, y - 0.07, y + 0.07, 0.04, 0.062, 'kit_iron')
        p.bx(-0.52, 0.45, y - 0.05, y + 0.05, -0.055, -0.04, 'kit_iron')
    p.cyl(T(0.33, 1.0, 0.055) @ RX(PI / 2), 0.07, 0.03, 8, 'kit_iron')
    p.torus(T(0.33, 0.9, 0.09) @ RX(PI / 2), 0.07, 0.016, 8, 4, 'kit_iron')

@piece
def gate_wood_double(p):
    for sx in (-1, 1):
        p.post(sx * 1.85 - 0.15, sx * 1.85 + 0.15, -0.15, 0.15, 0, 3.2, 'kit_timber', c=0.04)
        p.bx(sx * 1.85 - 0.19, sx * 1.85 + 0.19, 3.0, 3.2, -0.19, 0.19, 'kit_timber')
    p.bx(-1.85, 1.85, 2.98, 3.2, -0.1, 0.1, 'kit_timber')
    for sx in (-1, 1):
        for i in range(6):
            a = 0.02 + i * 0.28
            x0, x1 = (a, a + 0.28) if sx > 0 else (-a - 0.28, -a)
            x0 += 0.17 * 0 + (0.002); x1 -= 0.002
            if sx > 0: x0 = max(x0, 0.02)
            p.bx(x0, min(x1, 1.7) if sx > 0 else x1, 0.03, 2.95 - 0.03 * (i % 2), -0.06, 0.06, 'kit_plank')
        for y in (0.45, 1.5, 2.55):
            xa, xb = (0.02, 1.7) if sx > 0 else (-1.7, -0.02)
            p.bx(xa, xb, y - 0.09, y + 0.09, 0.06, 0.08, 'kit_iron')
            p.bx(xa, xb, y - 0.09, y + 0.09, -0.08, -0.06, 'kit_iron')
        p.torus(T(sx * 0.3, 1.2, 0.11) @ RX(PI / 2), 0.1, 0.02, 8, 4, 'kit_iron')

def palisade_logs(p, x0, x1, n, rmin=0.14, hmin=3.2, hmax=3.6, tip=0.4):
    step = (x1 - x0) / n; r = step / 2 - 0.003
    for i in range(n):
        h = hmin + (hmax - hmin) * ((i * 37 + 11) % 7) / 6.0
        x = x0 + step * (i + 0.5)
        p.cyl(T(x, 0, 0), r, h - tip, 8, 'kit_log', caps=(True, False))
        p.cyl(T(x, h - tip, 0), r, tip, 8, 'kit_log', r2=0.0, caps=(False, False))

@piece
def palisade(p):
    palisade_logs(p, -1, 1, 7)
    for y in (1.0, 2.2):
        p.bx(-1, 1, y, y + 0.14, 0.13, 0.22, 'kit_timber')

@piece
def palisade_gate(p):
    for sx in (-1, 1):
        p.cyl(T(sx * 1.82, 0, 0), 0.18, 3.9, 8, 'kit_log', caps=(True, False))
        p.cyl(T(sx * 1.82, 3.9, 0), 0.18, 0.5, 8, 'kit_log', r2=0.0, caps=(False, False))
    p.bx(-1.8, 1.8, 3.0, 3.3, -0.15, 0.15, 'kit_timber')
    for sx in (-1, 1):
        for i in range(5):
            x = sx * (0.18 + i * 0.32)
            p.cyl(T(x, 0.02, 0.05), 0.15, 2.7 + 0.08 * (i % 2), 8, 'kit_log')
        xa, xb = (0.02, 1.7) if sx > 0 else (-1.7, -0.02)
        for y in (0.6, 2.0):
            p.bx(xa, xb, y, y + 0.14, 0.2, 0.3, 'kit_timber')
            p.bx(xa, xb, y, y + 0.14, -0.14, -0.04 if False else -0.1, 'kit_timber')
        p.torus(T(sx * 0.35, 1.2, 0.34) @ RX(PI / 2), 0.1, 0.02, 8, 4, 'kit_iron')

@piece
def fence_rail(p):
    for sx in (-1, 1):
        p.post(sx * 0.75 - 0.07, sx * 0.75 + 0.07, -0.07, 0.07, 0, 1.1, 'kit_log', c=0.02)
    for i, y in enumerate((0.3, 0.62, 0.94)):
        z = 0.085 if i % 2 == 0 else -0.085
        p.bx(-1.0, 1.0, y - 0.05, y + 0.05, z - 0.045, z + 0.045, 'kit_log')

@piece
def fence_wattle(p):
    for i in range(9):
        x = -0.96 + i * 0.24
        p.bx(x - 0.03, x + 0.03, 0, 1.0 - 0.04 * (i % 2), -0.03, 0.03, 'kit_log')
    for row in range(5):
        y = 0.12 + row * 0.2
        for j in range(4):
            z = 0.045 if (j + row) % 2 == 0 else -0.045
            p.bx(-1.0 + j * 0.5, -0.5 + j * 0.5, y, y + 0.1, z - 0.025, z + 0.025, 'kit_plank')

# --------------------------------------------------------------- stone defence
@piece
def stone_wall_curtain(p):
    p.bx(-1, 1, 0, 3.9, -0.56, 0.56, 'kit_stone')
    for r in range(6):
        ya = r * 0.65; yb = ya + 0.65
        for sg in (1, -1):
            m = I if sg > 0 else RY(PI)
            stone_field(p, (-1, 1, ya, yb), 0.56, 0.6, m, rowh=0.65, colw=0.66)
    p.bx(-1, 1, 3.8, 3.9, -0.64, 0.64, 'kit_stone')
    for x in (-0.5, 0.5):
        p.bx(x - 0.3, x + 0.3, 3.9, 4.5, 0.3, 0.64, 'kit_stone')

@piece
def stone_tower(p):
    N = 12
    p.cyl(T(0, 0, 0), 1.7, 7.0, N, 'kit_stone')
    for r in range(10):
        y0 = r * 0.7
        for j in range(N):
            ang = 2 * PI * j / N + (PI / N if r % 2 else 0)
            zo = 1.95 + p.rng.random() * 0.03
            p.bx(1.66, zo, y0 + 0.02, y0 + 0.68, -0.5, 0.5, 'kit_stone', RY(ang), skip=('nx',))
    p.cyl(T(0, 7.0, 0), 1.75, 0.3, N, 'kit_stone', r2=2.05)
    p.tube(T(0, 7.3, 0), 1.7, 2.05, 0.3, N, 'kit_stone')
    for j in range(10):
        ang = 2 * PI * j / 10
        p.bx(1.72, 2.03, 7.6, 8.0, -0.3, 0.3, 'kit_stone', RY(ang))
    for (ang, y) in ((0.3, 2.5), (2.4, 2.5), (4.4, 2.5), (1.2, 4.4), (3.3, 4.4), (5.3, 4.4), (0.2, 6.2), (3.4, 6.2)):
        p.bx(1.93, 2.0, y - 0.35, y + 0.35, -0.06, 0.06, 'kit_coal', RY(ang))

@piece
def stone_tower_roof(p):
    H = 4.5; R = 2.6; n = 5; seg = H / n
    for i in range(n):
        y0 = i * seg; y1 = y0 + seg
        rb = R * (1 - y0 / H) + 0.1; rt = R * (1 - y1 / H)
        p.cyl(T(0, y0, 0), rb, seg, 16, 'kit_slate', r2=rt, caps=(i == 0, False))
    p.cyl(T(0, H - 0.12, 0), 0.06, 0.42, 6, 'kit_iron')

def arch_hw(y, spr=2.2, hw=1.3, c=0.104):
    if y <= spr: return hw
    R = hw + c; dy = y - spr
    if dy >= 1.4: return 0.0
    return -c + math.sqrt(max(R * R - dy * dy, 0))

@piece
def stone_wall_gatehouse(p):
    SPR, HW, C, R = 2.2, 1.3, 0.104, 1.404
    dys = [0, 0.35, 0.7, 1.05, 1.4]
    right = [(-C + math.sqrt(max(R * R - d * d, 0)), SPR + d) for d in dys]; right[-1] = (0.0, 3.6)
    left = [(-x, y) for (x, y) in right][::-1]
    top = 5.2
    poly = [(-2, 0), (-HW, 0)] + left + right[::-1][0:0] + right[::-1][1:] + [(HW, 0), (2, 0), (2, top), (-2, top)]
    # left arc listed from apex downwards in `left`; rebuild in correct order: springing -> apex -> springing
    left_up = [(-x, y) for (x, y) in right]
    right_down = right[::-1][1:]
    poly = [(-2, 0), (-HW, 0)] + left_up + right_down + [(HW, 0), (2, 0), (2, top), (-2, top)]
    p.ext('xy', poly, -0.94, 0.94, 'kit_stone')
    # voussoir ring
    outer = []
    for (x, y) in right:
        nx, ny = (x + C) / R, (y - SPR) / R
        outer.append((x + nx * 0.4, y + ny * 0.4))
    for sg in (1, -1):
        for i in range(len(right) - 1):
            a, b = right[i], right[i + 1]; oa, ob = outer[i], outer[i + 1]
            q = [(a[0] * sg, a[1]), (b[0] * sg, b[1]), (ob[0] * sg, ob[1]), (oa[0] * sg, oa[1])]
            for (z0, z1) in ((0.9, 1.0), (-1.0, -0.9)):
                p.ext('xy', q if sg > 0 else q[::-1], z0, z1, 'kit_stone')
    # jamb blocks beside the passage
    for sg in (1, -1):
        for (z0, z1) in ((0.9, 1.0), (-1.0, -0.9)):
            x0, x1 = sorted((sg * HW, sg * (HW + 0.4)))
            p.bx(x0, x1, 0, SPR, z0, z1, 'kit_stone')
    # brick plates outside the ring
    rowh = 0.52
    for r in range(10):
        ya = r * rowh; yb = ya + rowh
        W = (arch_hw(ya) + 0.42) if ya < 4.0 else 0.0
        rcs = [(-2, -W, ya, yb), (W, 2, ya, yb)] if W > 0 else [(-2, 2, ya, yb)]
        for rc in rcs:
            if rc[1] - rc[0] < 0.1: continue
            for sg in (1, -1):
                stone_field(p, rc, 0.94, 1.0, I if sg > 0 else RY(PI), rowh=rowh, colw=0.66)
    p.bx(-2, 2, 5.1, 5.2, -1.04, 1.04, 'kit_stone')
    for x in (-1.6, -0.55, 0.55, 1.6):
        p.bx(x - 0.35, x + 0.35, 5.2, 6.0, 0.5, 1.04, 'kit_stone')
