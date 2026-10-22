"""Render PNG sequences of clips from an exported GLB (verifies the export, not just the .blend).
blender -b --python render_clip.py -- <glb> <out_root> <res_w> <clip:view:step> [<clip:view:step> ...]
view: side|front|three|back ; step: 1 = every 30 fps frame, 2 = every 2nd (15 fps).
Frames go to <out_root>/<clip>/frame_00001.png"""
import bpy, sys, os, math, mathutils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_lib import *
args = sys.argv[sys.argv.index('--') + 1:]
glb = os.path.abspath(args[0]); root = os.path.abspath(args[1]); rw = int(args[2]); specs = args[3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
sc, cam = setup_scene((rw, int(rw * 0.72)))
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
ms = [o for o in sc.objects if o.type == 'MESH' and o.name != 'ground']
acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
arm.animation_data_create()
workbench_style(sc); activate_albedo()
bb = None
for spec in specs:
    clip, view, step = spec.split(':'); step = int(step)
    a = acts[clip]
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    sc.frame_set(f0)
    if bb is None:
        mn, mx = bbox(ms); bb = (mn, mx)
    mn, mx = bb
    h = mx.z
    ctr = mathutils.Vector((0, (mn.y + mx.y) / 2, h * 0.42))
    size = max(mx.y - mn.y, h)
    yaw = {"side": 90, "front": 28, "three": 55, "back": 200}[view]
    dm = float(os.environ.get('RC_DIST', '2.2')); aim(cam, ctr, yaw, size * (dm if view == "side" else dm * 1.1), 8)
    outd = f"{root}/{clip}"; os.makedirs(outd, exist_ok=True)
    n = 0
    tm = float(os.environ.get('RC_TREADMILL', '0'))          # ground scrolls backwards at tm m/s: planted feet stay on their grid cell
    grid = [o for o in sc.objects if o.type == 'MESH' and o.name.startswith('Cube')]
    gy0 = [o.location.y for o in grid]
    for f in range(f0, f1 + 1, step):
        sc.frame_set(f); n += 1
        if tm:
            sh = (tm * (f - f0) / 30.0) % 1.0
            for o, y0 in zip(grid, gy0):
                if o.scale.y < 1 and o.scale.x > 1: o.location.y = y0 + sh
        sc.render.filepath = f"{outd}/frame{n:08d}.png"; bpy.ops.render.render(write_still=True)
    print("FRAMES", clip, n, "range", f0, f1)
