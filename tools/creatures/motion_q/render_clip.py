"""Render PNG sequences of clips FROM AN EXPORTED GLB (verifies the export, not the .blend).
blender -b --python render_clip.py -- <glb> <out_root> <res_w> <clip:view:step> [<clip:view:step> ...]
view: side | front | top | three | back ; step: 1 = every 30 fps frame, 2 = every 2nd (15 fps), ...
Env: RC_FRAMES=0,5,9  render only these clip frames
     RC_TREADMILL=<m/s>  scroll the grid backwards so planted feet must stay on their grid cell
     RC_DIST=<k>         camera distance factor (default 2.2)
Frames go to <out_root>/<clip>_<view>/frame00000001.png (frame n = clip frame (n-1)*step)."""
import bpy, sys, os, math, mathutils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_lib import *
args = sys.argv[sys.argv.index('--') + 1:]
glb = os.path.abspath(args[0]); root = os.path.abspath(args[1]); rw = int(args[2]); specs = args[3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
sc, cam = setup_scene((rw, int(rw * 0.72)))
bpy.ops.import_scene.gltf(filepath=glb)
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere') and o.parent is None: bpy.data.objects.remove(o)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
ms = [o for o in sc.objects if o.type == 'MESH' and o.name != 'ground' and not o.name.startswith('Cube')]
acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
arm.animation_data_create()
workbench_style(sc); activate_albedo()
grid = [o for o in sc.objects if o.type == 'MESH' and o.name.startswith('Cube')]
gy0 = [o.location.y for o in grid]
tm = float(os.environ.get('RC_TREADMILL', '0'))
dm = float(os.environ.get('RC_DIST', '2.2'))
for spec in specs:
    clip, view, step = spec.split(':'); step = int(step)
    a = acts[clip]
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    # camera frame: union bbox over a few frames of the clip (attacks lunge, the wasp hovers)
    mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
    for f in range(f0, f1 + 1, max(1, (f1 - f0) // 6)):
        sc.frame_set(f); a0, a1 = bbox(ms)
        mn = mathutils.Vector([min(mn[i], a0[i]) for i in range(3)]); mx = mathutils.Vector([max(mx[i], a1[i]) for i in range(3)])
    h = max(mx.z, 0.1)
    ctr = mathutils.Vector((0, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2 if mn.z > 0.3 else h * 0.45))
    size = max(mx.y - mn.y, mx.z - mn.z, 0.5)
    yaw, elev = {"side": (270, 6), "front": (28, 8), "three": (235, 14), "back": (200, 8), "top": (270, 80)}[view]
    aim(cam, ctr, yaw, size * (dm if view in ("side", "top") else dm * 1.1), elev)
    outd = f"{root}/{clip}_{view}"; os.makedirs(outd, exist_ok=True)
    n = 0
    fl = [int(x) for x in os.environ['RC_FRAMES'].split(',')] if os.environ.get('RC_FRAMES') else list(range(f0, f1 + 1, step))
    for f in fl:
        sc.frame_set(f); n += 1
        if tm:
            sh = (tm * (f - f0) / 30.0) % 1.0
            for o, y0 in zip(grid, gy0):
                if o.scale.y < 1 and o.scale.x > 1: o.location.y = y0 + sh
        sc.render.filepath = f"{outd}/frame{n:08d}.png"; bpy.ops.render.render(write_still=True)
    print("FRAMES", clip, view, n, "range", f0, f1)
