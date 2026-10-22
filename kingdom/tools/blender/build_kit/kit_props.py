"""Crafting / furniture / dressing pieces of the build kit. Godot coordinates, see kitlib.py"""
import math
from kitlib import *

REG = {}
def piece(f):
    REG[f.__name__] = f; return f
PI = math.pi

@piece
def forge(p):
    # stone hearth 2 x 1.6, chimney hood to 2.6 m
    p.bx(-1, 1, 0, 0.85, -0.8, 0.8, 'kit_stone')
    for sg in (-1, 1):
        p.bx(-1.0, 1.0, 0.0, 0.85, sg * 0.8 - 0.0, sg * 0.8, 'kit_stone')
    for i, y in enumerate((0.0, 0.28, 0.56)):
        for j in range(3):
            x = -0.67 + j * 0.67 + (0.33 if i % 2 else 0)
            if x > 0.85: continue
            p.bx(x - 0.3, x + 0.3, y + 0.02, y + 0.26, 0.8, 0.86, 'kit_stone', skip=('nz',))
    p.bx(-1.04, 1.04, 0.85, 0.95, -0.84, 0.84, 'kit_stone')
    p.bx(-0.75, 0.75, 0.95, 1.0, -0.5, 0.35, 'kit_coal')
    p.ell(T(0.2, 1.0, -0.1), 0.2, 0.12, 0.2, 8, 3, 'kit_coal', half=True)
    p.bx(-1.0, 1.0, 0.95, 2.0, -0.8, -0.5, 'kit_stone')      # back wall
    for sx in (-1, 1):
        p.post(sx * 0.9 - 0.08, sx * 0.9 + 0.08, 0.62, 0.78, 0.95, 1.85, 'kit_timber', c=0.02)
    p.bx(-1.0, 1.0, 1.75, 1.9, 0.55, 0.85, 'kit_timber')
    p.frust(0, -0.2, 0.98, 0.62, 0.3, 0.3, 1.9, 2.35, 'kit_stone', dz1=-0.2)
    p.bx(-0.28, 0.28, 2.35, 2.6, -0.58, -0.02, 'kit_stone')
    p.bx(-0.34, 0.34, 2.55, 2.62, -0.64, 0.04, 'kit_stone')
    # bellows
    p.frust(1.35, 0.1, 0.3, 0.22, 0.18, 0.12, 0.35, 0.65, 'kit_plank', dx1=-0.15)
    p.bx(1.0, 1.2, 0.35, 0.55, 0.05, 0.15, 'kit_iron') if False else None
    p.cyl(T(1.45, 0.55, 0.1) @ RZ(PI / 2), 0.04, 0.5, 6, 'kit_iron')
    p.bx(1.0, 1.65, 0.28, 0.36, -0.12, 0.32, 'kit_timber')
    p.bx(1.58, 1.64, 0.36, 0.5, -0.1, 0.3, 'kit_plank')
    p.bx(1.25, 1.55, 0.58, 0.64, 0.0, 0.2, 'kit_cloth')

@piece
def anvil(p):
    p.cyl(T(0, 0, 0), 0.32, 0.5, 8, 'kit_log', r2=0.28)
    p.bx(-0.26, 0.26, 0.5, 0.6, -0.17, 0.17, 'kit_iron')
    p.bx(-0.13, 0.13, 0.6, 0.74, -0.1, 0.1, 'kit_iron')
    p.bx(-0.38, 0.28, 0.74, 0.9, -0.15, 0.15, 'kit_iron')
    p.cyl(T(0.28, 0.82, 0) @ RZ(-PI / 2), 0.08, 0.34, 8, 'kit_iron', r2=0.02, rz=0.07)

@piece
def workbench(p):
    p.bx(-1, 1, 0.78, 0.9, -0.45, 0.45, 'kit_plank')
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.post(sx * 0.88 - 0.07, sx * 0.88 + 0.07, sz * 0.34 - 0.07, sz * 0.34 + 0.07, 0, 0.78, 'kit_timber', c=0.02)
    p.bx(-0.9, 0.9, 0.2, 0.28, -0.4, 0.4, 'kit_plank')
    p.bx(-0.95, -0.62, 0.9, 1.02, 0.1, 0.4, 'kit_iron')               # vice
    p.bx(-0.95, -0.62, 0.9, 1.0, 0.4, 0.46, 'kit_iron')
    p.cyl(T(-0.78, 0.93, 0.46) @ RX(PI / 2), 0.025, 0.28, 6, 'kit_iron')
    p.beam((-0.2, 0.95, 0.2), (0.35, 0.95, 0.1), 0.05, 0.03, 'kit_iron', up=(0, 1, 0))      # saw blade
    p.bx(0.35, 0.5, 0.9, 1.0, 0.04, 0.16, 'kit_plank')
    p.bx(0.1, 0.5, 0.9, 0.95, -0.3, -0.2, 'kit_plank')        # plank
    p.bx(0.6, 0.9, 0.9, 0.96, -0.12, -0.04, 'kit_plank')      # hammer handle
    p.bx(0.82, 0.92, 0.94, 1.04, -0.15, 0.0, 'kit_iron')
    p.bx(0.45, 0.62, 0.9, 1.0, 0.05, 0.22, 'kit_plank')       # plane

@piece
def loom(p):
    for sx in (-1, 1):
        p.post(sx * 0.8 - 0.07, sx * 0.8 + 0.07, -0.07, 0.07, 0, 1.6, 'kit_plank', c=0.02)
        p.bx(sx * 0.8 - 0.06, sx * 0.8 + 0.06, 0, 0.1, -0.45, 0.45, 'kit_timber')
    p.bx(-0.85, 0.85, 1.45, 1.6, -0.08, 0.08, 'kit_timber')
    p.bx(-0.85, 0.85, 0.25, 0.37, -0.08, 0.08, 'kit_timber')
    p.bx(-0.75, 0.75, 0.62, 0.7, 0.05, 0.22, 'kit_plank')      # beater
    for i in range(18):
        x = -0.68 + i * 0.08
        p.bx(x - 0.012, x + 0.012, 0.7, 1.45, -0.005, 0.005, 'kit_cloth')
    p.bx(-0.7, 0.7, 0.37, 0.62, -0.015, 0.015, 'kit_cloth')
    p.bx(-0.3, 0.1, 0.95, 1.0, 0.02, 0.08, 'kit_plank')        # shuttle

@piece
def oven(p):
    p.bx(-0.85, 0.85, 0, 0.5, -0.85, 0.85, 'kit_stone')
    p.bx(-0.9, 0.9, 0.5, 0.58, -0.9, 0.9, 'kit_stone')
    p.ell(T(0, 0.58, 0), 0.8, 0.75, 0.8, 12, 5, 'kit_clay', half=True)
    p.bx(-0.4, 0.4, 0.58, 1.0, 0.55, 0.92, 'kit_clay')
    p.cyl(T(0, 1.0, 0.55) @ RX(PI / 2), 0.4, 0.37, 10, 'kit_clay', caps=(True, True))
    p.bx(-0.26, 0.26, 0.58, 0.9, 0.9, 0.94, 'kit_coal')
    p.cyl(T(0, 0.9, 0.9) @ RX(PI / 2), 0.26, 0.04, 10, 'kit_coal')
    p.cyl(T(0, 1.15, -0.3), 0.17, 0.55, 8, 'kit_clay', r2=0.14)
    p.tube(T(0, 1.68, -0.3), 0.09, 0.19, 0.07, 8, 'kit_clay')

@piece
def sawhorse_bench(p):
    for sx in (-0.55, 0.55):
        p.bx(sx - 0.07, sx + 0.07, 0.72, 0.84, -0.45, 0.45, 'kit_timber')
        for sz in (-1, 1):
            for sd in (-1, 1):
                p.beam((sx + sd * 0.16, 0.0, sz * 0.4), (sx, 0.76, sz * 0.12), 0.08, 0.08, 'kit_timber', up=(0, 0, 1))
        p.beam((sx, 0.3, -0.3), (sx, 0.3, 0.3), 0.06, 0.05, 'kit_plank')
    p.bx(-0.85, 0.85, 0.84, 0.9, -0.2, 0.2, 'kit_plank')
    p.bx(-0.85, 0.85, 0.84, 0.9, 0.2, 0.42, 'kit_plank')
    p.cyl(T(-0.8, 0.98, 0.0) @ RZ(-PI / 2), 0.11, 1.4, 8, 'kit_log')
    p.beam((0.2, 1.12, -0.18), (0.55, 1.12, -0.18), 0.1, 0.01, 'kit_iron', up=(0, 0, 1))
    p.bx(0.55, 0.7, 1.06, 1.16, -0.2, -0.16, 'kit_plank')

def crate(p, cx, cy, cz, s, rot=0.0):
    m = T(cx, cy, cz) @ RY(rot); h = s / 2
    p.bx(-h + 0.03, h - 0.03, -h + 0.03, h - 0.03, -h + 0.03, h - 0.03, 'kit_plank', m)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.bx(sx * (h - 0.05) - 0.05, sx * (h - 0.05) + 0.05, -h, h, sz * (h - 0.05) - 0.05, sz * (h - 0.05) + 0.05, 'kit_timber', m)
    for sg in (-1, 1):
        p.bx(-h, h, h - 0.1, h, sg * h - (0.0 if sg < 0 else 0.06), sg * h + (0.06 if sg < 0 else 0.0), 'kit_timber', m)
        p.bx(sg * h - (0.0 if sg < 0 else 0.06), sg * h + (0.06 if sg < 0 else 0.0), h - 0.1, h, -h, h, 'kit_timber', m)

@piece
def storage_crates(p):
    crate(p, -0.5, 0.425, -0.1, 0.85); crate(p, 0.5, 0.425, 0.0, 0.85, 0.12); crate(p, -0.05, 1.275, -0.05, 0.85, -0.2)
    p.ell(T(0.1, 0, 0.78) @ RY(0.4), 0.38, 0.62, 0.3, 8, 5, 'kit_cloth')
    p.ell(T(0.1, 0.5, 0.78) @ RY(0.4), 0.2, 0.16, 0.16, 8, 3, 'kit_cloth')
    p.bx(-0.1, 0.1, 0.55, 0.6, 0.72, 0.85, 'kit_timber') if False else None

@piece
def bed_simple(p):
    for sx in (-1, 1):
        for sz in (-1, 1):
            h = 0.95 if sx < 0 else 0.55
            p.post(sx * 0.95 - 0.06, sx * 0.95 + 0.06, sz * 0.45 - 0.06, sz * 0.45 + 0.06, 0, h, 'kit_timber', c=0.02)
    p.bx(-1, -0.89, 0.35, 0.9, -0.5, 0.5, 'kit_plank')         # headboard
    p.bx(0.89, 1, 0.3, 0.6, -0.5, 0.5, 'kit_plank')
    for sz in (-1, 1): p.bx(-0.95, 0.95, 0.22, 0.4, sz * 0.45 - 0.03, sz * 0.45 + 0.03, 'kit_plank')
    p.bx(-0.95, 0.95, 0.24, 0.3, -0.45, 0.45, 'kit_timber')
    p.bx(-0.9, 0.9, 0.3, 0.46, -0.42, 0.42, 'kit_hay')
    p.bx(-0.2, 0.9, 0.46, 0.5, -0.46, 0.46, 'kit_cloth')
    p.bx(-0.2, 0.9, 0.3, 0.46, 0.42, 0.46, 'kit_cloth')
    p.bx(-0.2, 0.9, 0.3, 0.46, -0.46, -0.42, 'kit_cloth')
    p.ell(T(-0.62, 0.46, 0), 0.22, 0.12, 0.34, 8, 3, 'kit_cloth')

@piece
def table_bench(p):
    p.bx(-1, 1, 0.72, 0.8, -0.4, 0.4, 'kit_plank')
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.beam((sx * 0.7, 0, sz * 0.36), (sx * 0.7, 0.72, sz * 0.12), 0.1, 0.08, 'kit_timber', up=(1, 0, 0))
        p.bx(sx * 0.7 - 0.05, sx * 0.7 + 0.05, 0.62, 0.72, -0.2, 0.2, 'kit_timber')
    p.bx(-0.7, 0.7, 0.22, 0.3, -0.04, 0.04, 'kit_timber')
    for sz in (-1, 1):
        zc = sz * 0.72
        p.bx(-0.9, 0.9, 0.42, 0.48, zc - 0.15, zc + 0.15, 'kit_plank')
        for sx in (-1, 1):
            p.bx(sx * 0.7 - 0.05, sx * 0.7 + 0.05, 0, 0.42, zc - 0.12, zc + 0.12, 'kit_timber')

@piece
def road_cobble_tile(p):
    p.bx(-1, 1, -0.04, 0.0, -1, 1, 'kit_dirt')
    n = 6; c = 2.0 / n
    for i in range(n):
        for j in range(n):
            ox = 0.0 if j % 2 == 0 else c * 0.5
            x0 = -1 + i * c + ox; x1 = x0 + c
            z0 = -1 + j * c; z1 = z0 + c
            x0 = max(x0, -1); x1 = min(x1, 1)
            if x1 - x0 < 0.1: continue
            g = 0.018
            cx = (x0 + x1) / 2; cz = (z0 + z1) / 2
            hx = (x1 - x0) / 2 - g; hz = (z1 - z0) / 2 - g
            jx = (p.rng.random() - 0.5) * 0.03
            p.frust(cx, cz, hx, hz, hx * 0.82, hz * 0.82, 0.0, 0.04, 'kit_cobble', dx1=jx)
        if ox_needed(i, n):
            pass
    # half stones at the staggered edge
    for j in range(1, n, 2):
        z0 = -1 + j * c
        x0 = -1; x1 = -1 + c * 0.5
        p.frust((x0 + x1) / 2, z0 + c / 2, (x1 - x0) / 2 - 0.018, c / 2 - 0.018, ((x1 - x0) / 2 - 0.018) * 0.82, (c / 2 - 0.018) * 0.82, 0.0, 0.04, 'kit_cobble')

def ox_needed(i, n): return False

@piece
def road_dirt_tile(p):
    N = 8
    def h(x, z):
        rut = 0.022 * math.exp(-((abs(x) - 0.5) / 0.14) ** 2)
        w = min(1.0, (1 - abs(x)) * 4) * min(1.0, (1 - abs(z)) * 4)
        noise = 0.006 * math.sin(x * 5.3 + z * 3.1) * w
        return 0.03 - rut + noise
    vs = []
    for j in range(N + 1):
        for i in range(N + 1):
            x = -1 + 2 * i / N; z = -1 + 2 * j / N
            vs.append((x, h(x, z), z))
    fs = []
    for j in range(N):
        for i in range(N):
            a = j * (N + 1) + i
            fs.append([a, a + 1, a + N + 2, a + N + 1][::-1])
    nv = len(vs)
    vs += [(v[0], -0.01, v[2]) for v in vs]
    edge = [(j * (N + 1) + i) for j in range(N + 1) for i in range(N + 1) if i in (0, N) or j in (0, N)]
    # skirt: loop around the border
    loop = [i for i in range(N + 1)] + [(j + 1) * (N + 1) - 1 for j in range(N)] + [N * (N + 1) + i for i in range(N - 1, -1, -1)] + [j * (N + 1) for j in range(N - 1, 0, -1)]
    for k in range(len(loop)):
        a = loop[k]; b = loop[(k + 1) % len(loop)]
        fs.append([a, b, b + nv, a + nv])
    fs.append([ (j * (N + 1) + i) + nv for j in range(N, -1, -1) for i in range(N + 1)][:0] or [loop[k] + nv for k in range(len(loop))])
    p.prim(vs, fs, 'kit_dirt')

@piece
def hay_cart(p):
    # length along Z (-1.8 .. 1.2), width 1.3, wheels on the X sides
    p.bx(-0.65, 0.65, 0.5, 0.58, -1.0, 1.2, 'kit_plank')
    for sx in (-1, 1):
        p.bx(sx * 0.65 - (0.0 if sx > 0 else -0.06), sx * 0.65 + (0.06 if sx > 0 else 0.0), 0.58, 0.95, -1.0, 1.2, 'kit_plank')
        p.beam((sx * 0.45, 0.5, -1.8), (sx * 0.45, 0.62, -0.4), 0.09, 0.09, 'kit_timber', up=(1, 0, 0))
        p.bx(sx * 0.5 - 0.05, sx * 0.5 + 0.05, 0.38, 0.5, -0.9, 1.1, 'kit_timber')
    p.bx(-0.65, 0.65, 0.58, 0.95, 1.14, 1.2, 'kit_plank')
    p.bx(-0.65, 0.65, 0.58, 0.95, -1.0, -0.94, 'kit_plank')
    p.cyl(T(-0.85, 0.5, 0.15) @ RZ(-PI / 2), 0.05, 1.7, 8, 'kit_timber')
    for sx in (-1, 1):
        wm = T(sx * 0.78, 0.5, 0.15) @ RZ(-PI / 2)
        p.tube(wm, 0.4, 0.5, 0.07, 12, 'kit_timber')
        p.cyl(wm, 0.1, 0.1, 8, 'kit_timber')
        for k in range(6):
            a = k * PI / 3
            p.beam((sx * 0.8, 0.5, 0.15), (sx * 0.8, 0.5 + 0.42 * math.cos(a), 0.15 + 0.42 * math.sin(a)), 0.07, 0.07, 'kit_plank', up=(1, 0, 0))
        p.tube(wm, 0.46, 0.52, 0.09, 12, 'kit_iron')
    p.ell(T(0, 0.9, 0.1), 0.78, 0.7, 1.15, 10, 5, 'kit_hay', half=True)
    p.ell(T(0, 0.9, -0.5), 0.55, 0.62, 0.6, 8, 4, 'kit_hay', half=True)
    p.ell(T(0.1, 0.9, 0.85), 0.5, 0.55, 0.5, 8, 4, 'kit_hay', half=True)
    p.bx(-0.04, 0.04, 0.0, 0.5, 1.1, 1.18, 'kit_timber') if False else None

@piece
def laundry_line(p):
    for sx in (-1, 1):
        p.post(sx * 2 - 0.07, sx * 2 + 0.07, -0.07, 0.07, 0, 2.5, 'kit_log', c=0.02)
        p.bx(sx * 2 - 0.12, sx * 2 + 0.12, 2.35, 2.43, -0.05, 0.05, 'kit_log')
    pts = []
    n = 10
    for i in range(n + 1):
        x = -2 + 4 * i / n
        pts.append((x, 2.4 - 0.28 * (1 - (x / 2) ** 2)))
    for i in range(n):
        p.beam((pts[i][0], pts[i][1], 0), (pts[i + 1][0], pts[i + 1][1], 0), 0.02, 0.02, 'kit_hay')
    for (cx, w, hh) in ((-1.35, 0.55, 0.7), (-0.5, 0.45, 0.55), (0.45, 0.6, 0.75), (1.3, 0.5, 0.6)):
        y = 2.4 - 0.28 * (1 - (cx / 2) ** 2)
        p.bx(cx - w / 2, cx + w / 2, y - hh, y, -0.012, 0.012, 'kit_cloth')

@piece
def shop_sign_bracket(p):
    # origin = wall mount point of the arm (place ~2.5 m up); wall plane z=0, arm sticks out along +Z
    p.bx(-0.05, 0.05, -0.3, 0.3, -0.04, 0.0, 'kit_iron')
    p.bx(-0.04, 0.04, -0.04, 0.04, 0, 1.0, 'kit_iron')
    p.beam((0, -0.28, -0.0), (0, -0.02, 0.8), 0.04, 0.04, 'kit_iron', up=(1, 0, 0))
    p.torus(T(0, 0.0, 1.05) @ RZ(PI / 2) , 0.05, 0.015, 8, 4, 'kit_iron')
    for sx in (-0.34, 0.34):
        p.bx(sx - 0.01, sx + 0.01, -0.28, -0.04, 0.78, 0.8, 'kit_iron')
    p.bx(-0.45, 0.45, -0.88, -0.28, 0.76, 0.84, 'kit_plank')
    p.bx(-0.45, 0.45, -0.88, -0.84, 0.74, 0.86, 'kit_timber'); p.bx(-0.45, 0.45, -0.32, -0.28, 0.74, 0.86, 'kit_timber')
    p.bx(-0.38, 0.38, -0.78, -0.4, 0.84, 0.855, 'kit_cloth'); p.bx(-0.38, 0.38, -0.78, -0.4, 0.745, 0.76, 'kit_cloth')
    p.cyl(T(0, -0.6, 0.855) @ RX(PI / 2), 0.15, 0.02, 8, 'kit_clay')

@piece
def barrel_cluster(p):
    def barrel(x, z, s=1.0):
        h = 0.9
        p.cyl(T(x, 0, z), 0.3 * s, h / 2, 10, 'kit_plank', r2=0.4 * s)
        p.cyl(T(x, h / 2, z), 0.4 * s, h / 2, 10, 'kit_plank', r2=0.3 * s, caps=(False, False))
        p.cyl(T(x, h - 0.01, z), 0.3 * s, 0.03, 10, 'kit_log', caps=(False, True))
        for y, r in ((0.12, 0.34), (0.3, 0.395), (0.6, 0.395), (0.78, 0.34)):
            p.tube(T(x, y - 0.03, z), r * s - 0.02, r * s + 0.025, 0.06, 10, 'kit_iron')
    barrel(-0.42, 0.1); barrel(0.42, 0.02); barrel(0.0, -0.62)

@piece
def mud_puddle(p):
    pts = []
    n = 16
    for i in range(n):
        a = 2 * PI * i / n
        r = 1.0 + 0.12 * math.sin(3 * a + 0.7) + 0.08 * math.sin(5 * a + 2.0)
        pts.append((0.83 * r * math.cos(a), 0.58 * r * math.sin(a)))
    p.ext('xz', pts, 0.0, 0.02, 'kit_dirt')
