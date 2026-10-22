"""Stone-kit infrastructure: parts -> chart UV packing -> painted albedo / normal / emissive atlas -> glb.
Headless Blender 5.x. Charts are planar projections in part-local metres with correct tangent handedness,
so normal maps can be derived straight from painted height maps (no high-poly bake needed)."""
import bpy, bmesh, math, os, sys, zlib, struct, random
import numpy as np
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(__file__))
import paint as P


# ---------------------------------------------------------------- geometry
def superellipse(n, a, b, p=4.0, off=0.0):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n + off
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / p), c), b * math.copysign(abs(s) ** (2 / p), s)))
    return pts


class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.parts = []

    def ring_solid(self, rings, cap_top=True, cap_bottom=True):
        """rings: list of list of (x,y,z), same count, CCW seen from above."""
        bm = self.bm
        vr = [[bm.verts.new(p) for p in r] for r in rings]
        n = len(vr[0])
        fs = []
        for j in range(len(vr) - 1):
            for i in range(n):
                fs.append(bm.faces.new((vr[j][i], vr[j][(i + 1) % n], vr[j + 1][(i + 1) % n], vr[j + 1][i])))
        if cap_top:
            fs.append(bm.faces.new(vr[-1]))
        if cap_bottom:
            fs.append(bm.faces.new(vr[0][::-1]))
        return fs, [v for r in vr for v in r]

    def finish_part(self, name, faces, chart_fn, transform=None, meta=None):
        """triangulate, compute chart key + part-local coords per loop, then transform the verts."""
        bm = self.bm
        start = len(bm.faces) - len(faces)
        bmesh.ops.triangulate(bm, faces=faces)
        bm.faces.ensure_lookup_table()
        fl = [bm.faces[i] for i in range(start, len(bm.faces))]
        info = []
        for f in fl:
            f.normal_update()
            key, coords = chart_fn(f)
            info.append((f, key, coords))
        vs = list({v for f in fl for v in f.verts})
        if transform is not None:
            bmesh.ops.transform(bm, matrix=transform, verts=vs)
        self.parts.append(dict(name=name, faces=info, verts=vs, meta=meta or {}))


def box_chart(f):
    """Dominant-axis chart, tangent-correct (u right, v up when viewed from outside)."""
    n = f.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    s = 1 if n[ax] >= 0 else -1
    if ax == 1:
        key = 'B' if s > 0 else 'F'
    elif ax == 0:
        key = 'R' if s > 0 else 'L'
    else:
        key = 'T' if s > 0 else 'D'
    co = []
    for l in f.loops:
        x, y, z = l.vert.co
        if key == 'F':
            u, v = x, z
        elif key == 'B':
            u, v = -x, z
        elif key == 'R':
            u, v = y, z
        elif key == 'L':
            u, v = -y, z
        elif key == 'T':
            u, v = x, y
        else:
            u, v = x, -y
        co.append((u, v))
    return key, co


def cyl_chart_factory(rref):
    def fn(f):
        n = f.normal
        if abs(n.z) > 0.5:
            return 'T', [(l.vert.co.x, l.vert.co.y) for l in f.loops]
        c = f.calc_center_median()
        cth = math.atan2(c.y, c.x)
        co = []
        for l in f.loops:
            th = math.atan2(l.vert.co.y, l.vert.co.x)
            d = (th - cth + math.pi) % (2 * math.pi) - math.pi
            co.append(((cth + d) * rref, l.vert.co.z))
        return 'C', co
    return fn


def rock_chart(f):
    key, co = box_chart(f)
    c0 = f.calc_center_median()
    cu = sum(c[0] for c in co) / len(co)
    cv = sum(c[1] for c in co) / len(co)
    h = (int(abs(c0.x) * 977 + abs(c0.y) * 613 + abs(c0.z) * 331) % 1000) / 1000.0
    h2 = (int(abs(c0.x) * 233 + abs(c0.y) * 719 + abs(c0.z) * 883) % 1000) / 1000.0
    ox, oy = 0.3 + 0.4 * h, 0.3 + 0.4 * h2
    return 'G', [(ox + (u - cu), oy + (v - cv)) for (u, v) in co]


# ---------------------------------------------------------------- packing
def pack(charts, W, H, gap=4):
    """charts: key -> (w_m, h_m, ppm). Returns (rects {key:(x,y,w,h)} rows from top, scale)."""
    scale = 1.0
    for _ in range(60):
        items = []
        for k, (wm, hm, ppm) in charts.items():
            items.append((k, max(6, int(math.ceil(wm * ppm * scale))), max(6, int(math.ceil(hm * ppm * scale)))))
        items.sort(key=lambda t: -t[2])
        rects = {}
        x = y = 0
        rowh = 0
        ok = True
        for k, w, h in items:
            if w > W or h > H:
                ok = False
                break
            if x + w > W:
                x = 0
                y += rowh + gap
                rowh = 0
            if y + h > H:
                ok = False
                break
            rects[k] = (x, y, w, h)
            x += w + gap
            rowh = max(rowh, h)
        if ok:
            return rects, scale
        scale *= 0.95
    raise RuntimeError("pack failed")


# ---------------------------------------------------------------- png io
def write_png(path, arr):
    arr = np.ascontiguousarray(arr.astype(np.uint8))
    h, w = arr.shape[:2]
    c = arr.shape[2] if arr.ndim == 3 else 1
    raw = np.concatenate([np.zeros((h, 1), np.uint8), arr.reshape(h, -1)], 1).tobytes()
    ct = {1: 0, 3: 2, 4: 6}[c]

    def chunk(t, d):
        cr = zlib.crc32(t + d) & 0xffffffff
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", cr)
    with open(path, 'wb') as fh:
        fh.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0))
                 + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def to8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def down2(a):
    return (a[0::2, 0::2] + a[1::2, 0::2] + a[0::2, 1::2] + a[1::2, 1::2]) * 0.25


def save_jpg(png_path, jpg_path, q=90):
    img = bpy.data.images.load(png_path)
    sc = bpy.context.scene
    sc.render.image_settings.file_format = 'JPEG'
    sc.render.image_settings.quality = q
    sc.render.image_settings.color_mode = 'RGB'
    img.save_render(jpg_path, scene=sc)
    bpy.data.images.remove(img)


# ---------------------------------------------------------------- materials / export
def make_material(name, albedo_path, normal_path, emis_path, emis_strength=1.0, rough=0.92):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial')
    bs = nt.nodes.new('ShaderNodeBsdfPrincipled')
    nt.links.new(bs.outputs['BSDF'], out.inputs['Surface'])
    bs.inputs['Roughness'].default_value = rough
    bs.inputs['Metallic'].default_value = 0.0

    def tex(path, cs):
        t = nt.nodes.new('ShaderNodeTexImage')
        t.image = bpy.data.images.load(path)
        t.image.colorspace_settings.name = cs
        return t
    ta = tex(albedo_path, 'sRGB')
    nt.links.new(ta.outputs['Color'], bs.inputs['Base Color'])
    if normal_path:
        tn = tex(normal_path, 'Non-Color')
        nm = nt.nodes.new('ShaderNodeNormalMap')
        nt.links.new(tn.outputs['Color'], nm.inputs['Color'])
        nt.links.new(nm.outputs['Normal'], bs.inputs['Normal'])
    if emis_path:
        te = tex(emis_path, 'sRGB')
        nt.links.new(te.outputs['Color'], bs.inputs['Emission Color'])
        bs.inputs['Emission Strength'].default_value = emis_strength
    return m


def export_glb(obj, path):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
              export_image_format='AUTO', export_materials='EXPORT', export_cameras=False, export_lights=False,
              export_vertex_color='ACTIVE', export_active_vertex_color_when_no_material=True)
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError:
        kw.pop('export_vertex_color', None)
        kw.pop('export_active_vertex_color_when_no_material', None)
        bpy.ops.export_scene.gltf(**kw)


def tri_total(obj):
    me = obj.data
    me.calc_loop_triangles()
    return len(me.loop_triangles)
