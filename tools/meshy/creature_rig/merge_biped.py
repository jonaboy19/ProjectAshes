import bpy, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from common import *
a = sys.argv[sys.argv.index('--')+1:]
name, height, rigdir, outdir = a[0], float(a[1]), a[2], a[3]
clips = [c.split('=') for c in a[4:]]   # clipname=file
reset(30)
objs, acts = import_new(os.path.join(rigdir, f"{name}_rigged.glb"))
arm = [o for o in objs if o.type == 'ARMATURE'][0]
mesh = [o for o in objs if o.type == 'MESH'][0]
for ac in acts: bpy.data.actions.remove(ac)
if arm.animation_data: arm.animation_data.action = None
for clip, f in clips:
    o2, a2 = import_new(os.path.join(rigdir, f))
    assert len(a2) == 1, (f, a2)
    ac = a2[0]
    # some Meshy clips (e.g. Idle) key a uniform Hips scale (~1.18) that inflates the whole character: drop scale channels
    for lay in ac.layers:
        for st in lay.strips:
            for cb in st.channelbags:
                for fc in [fc for fc in cb.fcurves if fc.data_path.endswith("scale")]:
                    cb.fcurves.remove(fc)
    # shift to start at frame 0
    fr0 = ac.frame_range[0]
    add_nla(arm, clip, ac, start=fr0)
    for o in o2:
        if o.animation_data: o.animation_data.action = None
        bpy.data.objects.remove(o)
bpy.data.orphans_purge(do_recursive=True)
# scale to height in rest pose
arm.data.pose_position = 'REST'
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
mn, mx = world_bbox([mesh], dg)
k = height / (mx.z - mn.z)
arm.scale = arm.scale * k
arm.location.z -= mn.z * k
bpy.context.view_layer.update()
mn, mx = world_bbox([mesh], bpy.context.evaluated_depsgraph_get())
print("REST_BBOX", name, [round(x,3) for x in mn], [round(x,3) for x in mx])
arm.data.pose_position = 'POSE'
mesh.name = name; arm.name = name + "_rig"
if arm.animation_data:
    for t in list(arm.animation_data.nla_tracks): arm.animation_data.nla_tracks.remove(t)
    arm.animation_data.action = None
for ac in bpy.data.actions:
    ac.slots[0].name_display = arm.name
    print("ACT", ac.name, ac.slots[0].identifier, tuple(ac.frame_range))
sys.path.insert(0, os.path.dirname(__file__))
from groundfix import fix_ground
fix_ground(arm, mesh, "Hips", tol=0.004*height*10/4)
for tag, t, px in (("", 15000, 1024), ("_lod1", 5000, 512)):
    n = decimate_to(mesh, t); cap_images(px)
    print("TIER", name, tag or "lod0", n, px)
    export(os.path.join(outdir, f"{name}{tag}.glb"), [arm, mesh])
