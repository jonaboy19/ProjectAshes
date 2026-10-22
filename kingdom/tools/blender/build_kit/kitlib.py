"""Geometry helpers for the Rising Ashes modular build kit.
All pieces are authored in GODOT coordinates (x right, y up, z back; forward = -Z).
Vertices are converted to Blender Z-up at creation: bl = (x, -z, y); the glTF exporter converts back."""
import bpy, bmesh, math, random, zlib
from mathutils import Vector, Matrix

I = Matrix.Identity(4)
def T(x=0, y=0, z=0): return Matrix.Translation((x, y, z))
def RX(a): return Matrix.Rotation(a, 4, 'X')
def RY(a): return Matrix.Rotation(a, 4, 'Y')
def RZ(a): return Matrix.Rotation(a, 4, 'Z')
def deg(a): return math.radians(a)

COLORS = {
    'kit_plaster': '#efe3c8', 'kit_timber': '#4a3222', 'kit_plank': '#8a6a48', 'kit_log': '#6e5238',
    'kit_stone': '#9a9488', 'kit_cobble': '#8e8a80', 'kit_thatch': '#c9a35a', 'kit_slate': '#5d6878',
    'kit_shingle': '#7a5638', 'kit_iron': '#3a3a3e', 'kit_cloth': '#b8463a', 'kit_clay': '#b06a48',
    'kit_dirt': '#6b5440', 'kit_hay': '#d8b860', 'kit_coal': '#2a2420'}

def hex2lin(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return [(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c] + [1.0]

_matcache = {}
def get_mat(name):
    if name in _matcache: return _matcache[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    col = hex2lin(COLORS[name]); bsdf.inputs['Base Color'].default_value = col
    bsdf.inputs['Roughness'].default_value = 0.9
    m.diffuse_color = col
    _matcache[name] = m
    return m

class P:
    def __init__(s, name):
        s.name = name; s.bm = bmesh.new(); s.slots = []; s.roof = False
        s.rng = random.Random(zlib.crc32(name.encode()))
    def mi(s, mat):
        if mat not in COLORS: raise ValueError('bad material ' + mat)
        if mat not in s.slots: s.slots.append(mat)
        return s.slots.index(mat)
    def prim(s, vs, fs, mat, m=I, recalc=True):
        mi = s.mi(mat); bv = []
        for v in vs:
            g = m @ Vector(v); bv.append(s.bm.verts.new((g.x, -g.z, g.y)))
        faces = []
        for f in fs:
            try:
                fc = s.bm.faces.new([bv[i] for i in f]); fc.material_index = mi; faces.append(fc)
            except ValueError:
                pass
        if recalc and faces: bmesh.ops.recalc_face_normals(s.bm, faces=faces)
        return faces
    # axis aligned box, min/max form. skip: any of 'px','nx','py','ny','pz','nz'
    def bx(s, x0, x1, y0, y1, z0, z1, mat, m=I, skip=()):
        v = {}
        for ix, x in enumerate((x0, x1)):
            for iy, y in enumerate((y0, y1)):
                for iz, z in enumerate((z0, z1)): v[(ix, iy, iz)] = (x, y, z)
        keys = list(v.keys()); idx = {k: i for i, k in enumerate(keys)}; vs = [v[k] for k in keys]
        F = {'px': [(1,0,0),(1,1,0),(1,1,1),(1,0,1)], 'nx': [(0,0,0),(0,0,1),(0,1,1),(0,1,0)],
             'py': [(0,1,0),(0,1,1),(1,1,1),(1,1,0)], 'ny': [(0,0,0),(1,0,0),(1,0,1),(0,0,1)],
             'pz': [(0,0,1),(1,0,1),(1,1,1),(0,1,1)], 'nz': [(0,0,0),(0,1,0),(1,1,0),(1,0,0)]}
        fs = [[idx[k] for k in F[n]] for n in F if n not in skip]
        return s.prim(vs, fs, mat, m, recalc=False)
    def cbx(s, cx, cy, cz, sx, sy, sz, mat, m=I, skip=()):
        return s.bx(cx - sx/2, cx + sx/2, cy - sy/2, cy + sy/2, cz - sz/2, cz + sz/2, mat, m, skip)
    # beam from p0 to p1; w across (side), h across (up); box occupies [-w/2,w/2]x[-h/2,h/2]x[0,L]
    def beam(s, p0, p1, w, h, mat, up=(0, 1, 0), m=I, ext0=0, ext1=0):
        p0 = Vector(p0); p1 = Vector(p1); f = (p1 - p0); L = f.length; f.normalize()
        u = Vector(up)
        if abs(f.dot(u)) > 0.98: u = Vector((1, 0, 0))
        sd = u.cross(f).normalized(); u2 = f.cross(sd).normalized()
        B = Matrix(((sd.x, u2.x, f.x, p0.x), (sd.y, u2.y, f.y, p0.y), (sd.z, u2.z, f.z, p0.z), (0, 0, 0, 1)))
        return s.bx(-w/2, w/2, -h/2, h/2, -ext0, L + ext1, mat, m @ B)
    def ext(s, plane, pts, a0, a1, mat, m=I):
        n = len(pts); vs = []
        for a in (a0, a1):
            for (p, q) in pts:
                vs.append((p, q, a) if plane == 'xy' else ((a, q, p) if plane == 'zy' else (p, a, q)))
        fs = [list(range(n)), list(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n; fs.append([i, j, n + j, n + i])
        return s.prim(vs, fs, mat, m)
    def cyl(s, m, r, h, segs, mat, r2=None, rz=None, caps=(True, True), rot=0.0):
        if r2 is None: r2 = r
        rz = r if rz is None else rz
        rz2 = rz * (r2 / r) if r else 0
        vs = []; fs = []
        for i in range(segs):
            a = rot + 2 * math.pi * i / segs; vs.append((r * math.cos(a), 0, rz * math.sin(a)))
        apex = r2 < 1e-6
        if apex: vs.append((0, h, 0))
        else:
            for i in range(segs):
                a = rot + 2 * math.pi * i / segs; vs.append((r2 * math.cos(a), h, rz2 * math.sin(a)))
        for i in range(segs):
            j = (i + 1) % segs
            if apex: fs.append([i, j, segs])
            else: fs.append([i, j, segs + j, segs + i])
        if caps[0]: fs.append(list(range(segs))[::-1])
        if caps[1] and not apex: fs.append(list(range(segs, 2 * segs)))
        return s.prim(vs, fs, mat, m)
    def tube(s, m, rin, rout, h, segs, mat, rot=0.0):
        vs = []; fs = []
        for (r, y) in ((rin, 0), (rout, 0), (rout, h), (rin, h)):
            for i in range(segs):
                a = rot + 2 * math.pi * i / segs; vs.append((r * math.cos(a), y, r * math.sin(a)))
        for k in range(4):
            k2 = (k + 1) % 4
            for i in range(segs):
                j = (i + 1) % segs; fs.append([k * segs + i, k * segs + j, k2 * segs + j, k2 * segs + i])
        return s.prim(vs, fs, mat, m)
    def ell(s, m, rx, ry, rz, segs, rings, mat, half=False):
        vs = [(0, ry, 0)]; fs = []
        lim = math.pi / 2 if half else math.pi
        for k in range(1, rings + 1):
            ph = lim * k / rings
            if (not half) and k == rings: break
            for i in range(segs):
                a = 2 * math.pi * i / segs
                vs.append((rx * math.sin(ph) * math.cos(a), ry * math.cos(ph), rz * math.sin(ph) * math.sin(a)))
        nr = len(vs) - 1; nrings = nr // segs
        for i in range(segs):
            j = (i + 1) % segs; fs.append([0, 1 + j, 1 + i])
        for k in range(nrings - 1):
            for i in range(segs):
                j = (i + 1) % segs
                fs.append([1 + k * segs + i, 1 + k * segs + j, 1 + (k + 1) * segs + j, 1 + (k + 1) * segs + i])
        if half:
            fs.append([1 + (nrings - 1) * segs + i for i in range(segs)][::-1])
        else:
            vs.append((0, -ry, 0)); b = len(vs) - 1
            for i in range(segs):
                j = (i + 1) % segs
                fs.append([b, 1 + (nrings - 1) * segs + i, 1 + (nrings - 1) * segs + j])
        return s.prim(vs, fs, mat, m)
    def frust(s, cx, cz, hx0, hz0, hx1, hz1, y0, y1, mat, m=I, dx1=0, dz1=0):
        vs = [(cx - hx0, y0, cz - hz0), (cx + hx0, y0, cz - hz0), (cx + hx0, y0, cz + hz0), (cx - hx0, y0, cz + hz0),
              (cx + dx1 - hx1, y1, cz + dz1 - hz1), (cx + dx1 + hx1, y1, cz + dz1 - hz1),
              (cx + dx1 + hx1, y1, cz + dz1 + hz1), (cx + dx1 - hx1, y1, cz + dz1 + hz1)]
        fs = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
        return s.prim(vs, fs, mat, m)
    def torus(s, m, R, r, sa, sb, mat):
        vs = []; fs = []
        for i in range(sa):
            a = 2 * math.pi * i / sa
            for j in range(sb):
                b = 2 * math.pi * j / sb
                rr = R + r * math.cos(b)
                vs.append((rr * math.cos(a), r * math.sin(b), rr * math.sin(a)))
        for i in range(sa):
            i2 = (i + 1) % sa
            for j in range(sb):
                j2 = (j + 1) % sb
                fs.append([i * sb + j, i2 * sb + j, i2 * sb + j2, i * sb + j2])
        return s.prim(vs, fs, mat, m)
    def post(s, x0, x1, z0, z1, y0, y1, mat, c=0.03, m=I):
        pts = [(x0 + c, z0), (x1 - c, z0), (x1, z0 + c), (x1, z1 - c), (x1 - c, z1), (x0 + c, z1), (x0, z1 - c), (x0, z0 + c)]
        return s.ext('xz', pts, y0, y1, mat, m)
    # ---------- finalize ----------
    def build(s):
        bm = s.bm
        bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        uv = bm.loops.layers.uv.verify()
        for f in bm.faces:
            n = f.normal; gx, gy, gz = n.x, n.z, -n.y   # godot normal
            for l in f.loops:
                c = l.vert.co; x, y, z = c.x, c.z, -c.y
                ax, ay, az = abs(gx), abs(gy), abs(gz)
                if s.roof and ax < 0.3 and ay > 0.3 and az > 0.3:
                    u, v = x, (y - z) * 0.70710678
                elif ay >= ax and ay >= az: u, v = x, z
                elif ax >= az: u, v = z, y
                else: u, v = x, y
                l[uv].uv = (u * 0.5, v * 0.5)
            f.smooth = False
        me = bpy.data.meshes.new(s.name); bm.to_mesh(me)
        ob = bpy.data.objects.new(s.name, me); bpy.context.scene.collection.objects.link(ob)
        for mname in s.slots: me.materials.append(get_mat(mname))
        for f in me.polygons: f.use_smooth = False
        ob.data.update()
        tris = len(me.polygons)
        mn = [1e9] * 3; mx = [-1e9] * 3
        for v in me.vertices:
            g = (v.co.x, v.co.z, -v.co.y)
            for i in range(3): mn[i] = min(mn[i], g[i]); mx[i] = max(mx[i], g[i])
        bm.free()
        return ob, tris, mn, mx

def export(ob, path):
    for o in bpy.context.scene.objects: o.select_set(False)
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_apply=True,
                              export_yup=True, export_materials='EXPORT', export_normals=True,
                              export_cameras=False, export_lights=False, export_animations=False,
                              export_image_format='NONE')
