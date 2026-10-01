"""Render side+front PNG sequences of clips FROM A GLB (verifies the export).
blender -b --python render.py -- <glb> <out_root> <res_w> <clip:step[:treadmill_mps]> ...
Frames: <out_root>/<clip>/side/frame%08d.png and front/. Blender fps is 30 so frame = t*30."""
import bpy, sys, os, math, mathutils
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_lib import *
args = sys.argv[sys.argv.index('--') + 1:]
glb = os.path.abspath(args[0]); root = os.path.abspath(args[1]); rw = int(args[2]); specs = args[3:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
sc, cam = setup_scene((rw, int(rw * 0.78)))
bpy.ops.import_scene.gltf(filepath=glb)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
for o in list(bpy.data.objects):
    if o.type == 'MESH' and o.name.startswith('Icosphere'): bpy.data.objects.remove(o)
ms = [o for o in sc.objects if o.type == 'MESH' and o.name != 'ground']
acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
arm.animation_data_create()
workbench_style(sc); activate_albedo()
grid = [o for o in sc.objects if o.type == 'MESH' and o.name.startswith('Cube')]
gy0 = [o.location.y for o in grid]
h = None
for spec in specs:
    p = spec.split(":"); clip = p[0]
    if clip not in acts: continue
    a = acts[clip]; nfr = int(round(a.frame_range[1])) - int(round(a.frame_range[0])) + 1
    step = (1 if nfr <= 46 else 2) if p[1] == "auto" else int(p[1])
    if os.environ.get("RC_STEP"): step = int(os.environ["RC_STEP"])
    tm = float(p[2]) if len(p) > 2 else 0.0
    pass
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    zt = 0.0; yl = 0.0
    for f in range(f0, f1 + 1, 4):
        sc.frame_set(f); mn, mx = bbox(ms); zt = max(zt, mx.z); yl = max(yl, mx.y - mn.y, mx.x - mn.x)
    h = max(zt, yl * 0.8)
    ctr = mathutils.Vector((0, 0, zt * 0.47))
    for view, yaw in (("side", 90), ("front", 28)):
        aim(cam, ctr, yaw, h * (2.0 if view == "side" else 2.15), 8)
        outd = f"{root}/{clip}/{view}"; os.makedirs(outd, exist_ok=True)
        n = 0
        for f in range(f0, f1 + 1, step):
            sc.frame_set(f); n += 1
            if tm:
                sh = (tm * (f - f0) / 30.0) % 1.0
                for o, y0 in zip(grid, gy0):
                    if o.scale.y < 1 and o.scale.x > 1: o.location.y = y0 - sh
            sc.render.filepath = f"{outd}/frame{n:08d}.png"; bpy.ops.render.render(write_still=True)
        print("FRAMES", clip, view, n, "range", f0, f1); open(f"{root}/{clip}/step.txt", "w").write(str(step))
