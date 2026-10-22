"""Contact sheets + snap test for the build kit.
blender -b --factory-startup --python render_sheet.py -- <build_kit_dir> <out_dir> [sheets|snap|all] [lod0|lod1]"""
import bpy, sys, os, math, glob, json
import numpy as np
from mathutils import Vector, Matrix, Euler

argv = sys.argv[sys.argv.index('--') + 1:]
KIT, OUT = os.path.abspath(argv[0]), os.path.abspath(argv[1])
MODE = argv[2] if len(argv) > 2 else 'all'
LOD = argv[3] if len(argv) > 3 else 'lod0'
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.makedirs(OUT, exist_ok=True)
S = bpy.context.scene

def reset():
    for o in list(bpy.data.objects): bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes): bpy.data.meshes.remove(m)

def engine():
    for e in ('BLENDER_EEVEE', 'BLENDER_EEVEE_NEXT'):
        try:
            S.render.engine = e; return
        except TypeError: pass
engine()
try: S.eevee.taa_render_samples = 24
except Exception: pass
S.view_settings.view_transform = 'Standard'
S.render.image_settings.file_format = 'PNG'
S.render.film_transparent = False
w = bpy.data.worlds.new('w'); w.use_nodes = True; S.world = w
bg = w.node_tree.nodes['Background']; bg.inputs[0].default_value = (0.5, 0.48, 0.45, 1); bg.inputs[1].default_value = 0.55

def make_sun(energy=3.2):
    ld = bpy.data.lights.new('sun', 'SUN'); ld.energy = energy; ld.color = (1.0, 0.9, 0.74); ld.angle = 0.1
    o = bpy.data.objects.new('sun', ld); S.collection.objects.link(o)
    d = Vector((-0.5, -0.55, 0.85)).normalized()
    o.rotation_euler = d.to_track_quat('Z', 'Y').to_euler()
    return o

_ground_mat = None
def ground(z):
    global _ground_mat
    if _ground_mat is None:
        _ground_mat = bpy.data.materials.new('ground'); _ground_mat.use_nodes = True
        _ground_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.36, 0.34, 0.31, 1)
        _ground_mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 1.0
    me = bpy.data.meshes.new('g')
    me.from_pydata([(-200, -200, 0), (200, -200, 0), (200, 200, 0), (-200, 200, 0)], [], [(0, 1, 2, 3)])
    o = bpy.data.objects.new('ground', me); S.collection.objects.link(o); o.location.z = z
    me.materials.append(_ground_mat)
    return o

_label_mat = None
def label(text, cam, scale):
    global _label_mat
    if _label_mat is None:
        _label_mat = bpy.data.materials.new('lab'); _label_mat.use_nodes = True
        n = _label_mat.node_tree.nodes; n.clear()
        em = n.new('ShaderNodeEmission'); em.inputs[0].default_value = (0.04, 0.03, 0.03, 1); em.inputs[1].default_value = 1
        out = n.new('ShaderNodeOutputMaterial'); _label_mat.node_tree.links.new(em.outputs[0], out.inputs[0])
    cu = bpy.data.curves.new('t', 'FONT'); cu.body = text; cu.size = 0.075 * scale; cu.align_x = 'CENTER'
    o = bpy.data.objects.new('t', cu); S.collection.objects.link(o)
    o.parent = cam; o.location = (0, -0.465 * scale, -3.0)
    cu.materials.append(_label_mat)
    return o

def backface_all():
    for m in bpy.data.materials:
        m.use_backface_culling = True

def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == 'MESH']
    for o in new:
        if o.type != 'MESH': o.parent = None
    return meshes, new

def bbox(meshes):
    mn = Vector((1e9,) * 3); mx = Vector((-1e9,) * 3)
    for o in meshes:
        for c in o.bound_box:
            v = o.matrix_world @ Vector(c)
            for i in range(3): mn[i] = min(mn[i], v[i]); mx[i] = max(mx[i], v[i])
    return mn, mx

def frame_camera(cam, mn, mx, az=35, el=28, pad=1.15, shift=0.03):
    c = (mn + mx) / 2
    a = math.radians(az); e = math.radians(el)
    d = Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    rot = (-d).to_track_quat('-Z', 'Y'); cam.rotation_euler = rot.to_euler()
    R = rot.to_matrix(); right = R @ Vector((1, 0, 0)); up = R @ Vector((0, 1, 0))
    lo = [1e9, 1e9]; hi = [-1e9, -1e9]
    for i in range(8):
        p = Vector((mx.x if i & 1 else mn.x, mx.y if i & 2 else mn.y, mx.z if i & 4 else mn.z)) - c
        for k, ax in enumerate((right, up)):
            v = p.dot(ax); lo[k] = min(lo[k], v); hi[k] = max(hi[k], v)
    wd = hi[0] - lo[0]; ht = hi[1] - lo[1]
    sc = max(wd, ht) * pad
    mid = right * ((lo[0] + hi[0]) / 2) + up * ((lo[1] + hi[1]) / 2 - shift * sc)
    cam.location = c + mid + d * 60
    cam.data.type = 'ORTHO'; cam.data.ortho_scale = sc; cam.data.clip_end = 400
    return sc

def new_cam():
    cd = bpy.data.cameras.new('cam'); o = bpy.data.objects.new('cam', cd); S.collection.objects.link(o); S.camera = o
    return o

def render_png(path, w, h):
    S.render.resolution_x = w; S.render.resolution_y = h; S.render.resolution_percentage = 100
    S.render.filepath = path; bpy.ops.render.render(write_still=True)

def load_px(path):
    im = bpy.data.images.load(path); im.colorspace_settings.name = 'Non-Color'
    a = np.empty(im.size[0] * im.size[1] * 4, dtype=np.float32); im.pixels.foreach_get(a)
    r = a.reshape(im.size[1], im.size[0], 4).copy(); bpy.data.images.remove(im); return r

def save_jpg(arr, path, q=82):
    h, w = arr.shape[:2]
    im = bpy.data.images.new('sheet', w, h, alpha=False); im.colorspace_settings.name = 'Non-Color'
    im.pixels.foreach_set(arr.reshape(-1)); im.update()
    S.render.image_settings.file_format = 'JPEG'; S.render.image_settings.quality = q
    S.render.image_settings.color_management = 'OVERRIDE'
    S.render.image_settings.view_settings.view_transform = 'Standard'
    S.render.image_settings.display_settings.display_device = 'sRGB'
    im.save_render(path, scene=S)
    bpy.data.images.remove(im)
    S.render.image_settings.file_format = 'PNG'
    print('saved', path, os.path.getsize(path))

def sheet(ids, name, cols, tile=320):
    tmp = os.path.join(OUT, '_tile.png')
    rows = (len(ids) + cols - 1) // cols
    big = np.zeros((rows * tile, cols * tile, 4), np.float32); big[..., 3] = 1
    big[...] = (0.5, 0.48, 0.45, 1)
    for n, pid in enumerate(ids):
        reset(); make_sun(); cam = new_cam()
        meshes, _ = import_glb(os.path.join(KIT, '%s_%s.glb' % (pid, LOD)))
        backface_all()
        mn, mx = bbox(meshes); ground(mn.z)
        sc = frame_camera(cam, mn, mx)
        label(pid, cam, sc)
        render_png(tmp, tile, tile)
        t = load_px(tmp)
        r, c = divmod(n, cols)
        big[(rows - 1 - r) * tile:(rows - r) * tile, c * tile:(c + 1) * tile] = t
    save_jpg(big, os.path.join(OUT, name))
    try: os.remove(tmp)
    except OSError: pass

def ids_in(prefix_filter):
    out = []
    for f in sorted(glob.glob(os.path.join(KIT, '*_lod0.glb'))):
        pid = os.path.basename(f)[:-9]
        if prefix_filter(pid): out.append(pid)
    return out

def snap():
    reset(); make_sun(3.6); cam = new_cam()
    cache = {}
    def get(pid):
        if pid not in cache:
            meshes, _ = import_glb(os.path.join(KIT, pid + '_lod0.glb')); cache[pid] = meshes[0]
            meshes[0].hide_render = True
        return cache[pid]
    objs = []
    def put(pid, x, y, z, ry=0.0):
        src = get(pid); o = src.copy(); S.collection.objects.link(o); o.hide_render = False
        g = Matrix.Translation((x, -z, y)) @ Matrix.Rotation(ry, 4, 'Z')
        o.matrix_world = g; objs.append(o)
    PI = math.pi
    fy = 0.5; y1 = 0.5; y2 = 3.5; yr = 6.5
    cells = [(cx, cz) for cx in (-2, 0, 2) for cz in (-1, 1)]
    for cx, cz in cells:
        put('foundation_stone', cx, 0, cz); put('floor_plank', cx, fy, cz)
        if cz > 0: put('floor_jetty', cx, y2, cz, PI)
        else: put('floor_plank', cx, y2, cz)
    for yb, upper in ((y1, False), (y2, True)):
        for cx in (-2, 0, 2):
            if not upper:
                front = 'wall_plaster_door' if cx == 0 else 'wall_plaster_window'
            else:
                front = 'wall_plaster_window'
            put(front, cx, yb, 2.0)
            put('wall_plaster_window' if (cx == 2 and upper) else 'wall_plaster', cx, yb, -2.0, PI)
        for sx in (-1, 1):
            for cz in (-1, 1):
                put('wall_plaster_window' if (cz == 1 and not upper) else 'wall_plaster', sx * 3.0, yb, cz, PI / 2)
    put('door_wood', 0, y1, 2.0)
    for cx in (-2, 0, 2):
        put('roof_slate', cx, yr, 1.0); put('roof_slate', cx, yr, -1.0, PI)
        put('roof_ridge_slate', cx, yr, 0.0)
    for sx in (-1, 1):
        put('gable_plaster', sx * 3.0, yr, 1.0, -PI / 2); put('gable_plaster', sx * 3.0, yr, -1.0, PI / 2)
    backface_all()
    g = ground(0.0)
    gm = bpy.data.materials.new('grass'); gm.use_nodes = True
    gm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.2, 0.3, 0.1, 1); gm.use_backface_culling = False
    g.data.materials.clear(); g.data.materials.append(gm)
    mn, mx = bbox([o for o in objs])
    tmp = os.path.join(OUT, '_snap.png'); parts = []
    for az in (32, -148 + 360):
        sc = frame_camera(cam, mn, mx, az=az, el=26, pad=1.08)
        render_png(tmp, 800, 800); parts.append(load_px(tmp))
    save_jpg(np.concatenate(parts, axis=1), os.path.join(OUT, 'kit_snap_test.jpg'))
    os.remove(tmp)

if MODE in ('sheets', 'all'):
    import kit_props, kit_structure
    props = set(kit_props.REG.keys()); stru = set(kit_structure.REG.keys())
    sheet(ids_in(lambda p: p in stru), 'kit_sheet_structure.jpg', 5)
    sheet(ids_in(lambda p: p in props), 'kit_sheet_props.jpg', 5)
    sheet(ids_in(lambda p: p.startswith('meshy_')), 'kit_sheet_meshy.jpg', 5)
if MODE in ('snap', 'all'):
    snap()
