"""Stage 2: author the new wolf clips on the rebuilt base and export the GLB.
blender -b --python author.py -- <base.blend> <out.glb> [clip_name ...]      (no names = every clip in clips.CLIPS)
Writes <out.glb> plus <out>_rootmotion.json (per clip: fps, per-frame [forward m, left m, yaw rad], events)."""
import sys, os, json, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wlib import *
from wrig import *
import gait
import clips as C

args = sys.argv[sys.argv.index('--') + 1:]
base, out = os.path.abspath(args[0]), os.path.abspath(args[1])
want = args[2:]
bpy.ops.wm.open_mainfile(filepath=base)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
bpy.context.scene.render.fps = 30
if arm.animation_data:
    arm.animation_data.action = None
for pb in arm.pose.bones:
    pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
bpy.context.view_layer.update()
# rest sole height (rig units) -> planted paw targets sit that much lower than the rest paw joint
ps = paw_sets(mesh, arm)
P = mesh_world_np(mesh)
sole0 = min(P[idx][:, 2].min() for idx in ps.values()) / arm.matrix_world.to_scale()[0]
print("SOLE0 rig units", sole0, "metres", sole0 * arm.matrix_world.to_scale()[0])
pv = {k: [tuple(mesh.data.vertices[i].co) for i in ps[k]] for k in ps}
E = gait.Engine(arm, sole0, pv)
names = want or list(C.CLIPS)
import lock, clips3
if any(n in names for n in ("walk", "run", "run_turn_l", "run_turn_r")):
    for orig in ("walk", "run"):
        if orig in bpy.data.actions: bpy.data.actions[orig].name = orig + "_orig"
    for orig in ("walk_orig", "run_orig"):
        clips3.SRC[orig] = lock.sample(E, arm, mesh, ps, bpy.data.actions[orig])
    arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0)
arm.animation_data_create()
report = {}
meta = {}
for nm in names:
    clip = C.CLIPS[nm](E)
    n = int(round(clip.T * 30))
    ad = arm.animation_data
    act = bpy.data.actions.new(nm)
    ad.action = act
    frames = []
    planted = []
    worst = 0.0
    prevq = {}
    for i in range(n + 1):
        t = i / 30.0
        Fd = clip.fn(t)
        planted.append(Fd.get('planted', {}))
        B, miss = E.pose(Fd)
        worst = max(worst, miss)
        if miss > 0.02: print(f"MISS {nm} f{i} t={t:.2f} {miss:.3f}")
        frames.append(B)
    # which bones actually move
    moving_loc = set(); moving_rot = set()
    for B in frames:
        for b, (loc, rot) in B.items():
            if loc.length > 1e-5: moving_loc.add(b)
            if abs(rot.w) < 0.999999: moving_rot.add(b)
    for i, B in enumerate(frames):
        for b, (loc, rot) in B.items():
            pb = arm.pose.bones[b]; pb.rotation_mode = 'QUATERNION'
            if b in moving_rot:
                q = rot.copy()
                if b in prevq and prevq[b].dot(q) < 0: q.negate()
                prevq[b] = q
                pb.rotation_quaternion = q; pb.keyframe_insert('rotation_quaternion', frame=i)
            if b in moving_loc:
                pb.location = loc; pb.keyframe_insert('location', frame=i)
    ad.action = None
    act.use_fake_user = True
    # first == last for loops
    if clip.loop:
        d = max((frames[0][b][0] - frames[-1][b][0]).length + (frames[0][b][1].rotation_difference(frames[-1][b][1])).angle for b in frames[0])
        print(f"LOOPCHK {nm} max first/last diff {d:.5f}")
    rm = []
    if clip.world is not None:
        for i in range(n + 1):
            rm.append([round(x, 5) for x in clip.world.root_motion(i / 30.0)])
    meta[nm] = dict(T=clip.T, frames=n, loop=clip.loop, events=clip.events, root_motion=rm, notes=clip.notes, planted=planted)
    print(f"CLIP {nm} T={clip.T:.2f}s frames={n} ik_miss_max={worst:.4f} rig-units ({worst*E.s*100:.1f} cm) bones_rot={len(moving_rot)} bones_loc={len(moving_loc)}")
# NLA tracks for every action (old + new) so the exporter writes them all
for a in bpy.data.actions:
    if a.name.startswith("Action") and a.name not in names: pass
for a in list(bpy.data.actions):
    a.use_fake_user = True

for a in bpy.data.actions:
    add_nla(arm, a.name, a)
arm.animation_data.action = None
meta_path = out.replace('.glb', '_rootmotion.json')
json.dump(meta, open(meta_path, 'w'))
mesh_objs = [mesh, arm]

bpy.context.view_layer.objects.active = arm
export(out, [arm, mesh])
print("EXPORTED", out)
