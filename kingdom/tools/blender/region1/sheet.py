"""Grid contact sheet of GLBs: blender -b --python sheet.py -- out.png cols cell_m glb1 glb2 ...
Each cell is cell_m metres wide; objects are scaled uniformly to fit."""
import bpy, sys, os, math, mathutils
sys.path.insert(0, os.path.dirname(__file__))
import r1lib as L
a = L.args(); out = a[0]; cols = int(a[1]); cell = float(a[2]); files = a[3:]
sc = L.reset(); L.engine(sc); L.color_mgmt(sc); L.storybook_world(sc); L.sun(sc)
L.ground(sc, 400)
rows = math.ceil(len(files) / cols)
for i, f in enumerate(files):
    r, c = divmod(i, cols)
    objs = L.import_glb(f)
    roots = [o for o in objs if o.parent is None]
    mn, mx = L.bbox(objs)
    s = min(cell * 0.62 / max(mx.x - mn.x, mx.y - mn.y), cell * 0.75 / max(mx.z - mn.z, 0.01), 1.0 if False else 99)
    cx = (c - (cols - 1) / 2) * cell; cy = -(r - (rows - 1) / 2) * cell
    for o in roots:
        o.scale = o.scale * s
        o.location = mathutils.Vector((cx, cy, 0)) + (o.location - mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))) * s
    L.text(sc, os.path.basename(f).replace('_lod0.glb', '').replace('.glb', ''), (cx, cy - cell * 0.42, 0.02), size=cell * 0.07, rot=(0, 0, 0))
W = cols * cell; H = rows * cell
el = math.radians(float(os.environ.get("SHEET_EL","42"))); d = max(W * float(os.environ.get("SHEET_D", "1.2")), H * 1.9) + 3
L.camera(sc, (0, -d * math.cos(el), d * math.sin(el)), (0, 0, cell * 0.15), lens=float(os.environ.get("SHEET_LENS","38")))
L.render(sc, out, int(os.environ.get("SHEET_W","1200")), int(int(os.environ.get("SHEET_W","1200"))*float(os.environ.get("SHEET_R","0.66"))), samples=24)
