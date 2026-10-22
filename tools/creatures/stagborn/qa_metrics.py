"""Per-clip metrics from an exported GLB: duration, hoof floor contact, stance speed (implied ground speed), drift, loop seam.
blender -b --python qa_metrics.py -- <glb> [out.json]"""
import bpy, sys, os, json, math
import mathutils
args = sys.argv[sys.argv.index('--') + 1:]
glb = os.path.abspath(args[0])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.vertex_groups) > 5][0]
arm.animation_data_create()
HOOF = ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]
res = {}
dg = bpy.context.evaluated_depsgraph_get()
for a in sorted(bpy.data.actions, key=lambda x: x.name):
    nm = a.name.split('|')[-1]
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    rows = []; minz = []; ext = []; cen = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        pos = [arm.matrix_world @ arm.pose.bones[h].tail for h in HOOF]
        rows.append([(p.y, p.z) for p in pos])
        ev = mesh.evaluated_get(dg); me = ev.to_mesh()
        zs = [v.co.z for v in me.vertices]; ys = [v.co.y for v in me.vertices]
        minz.append(min(zs)); ext.append((min(ys), max(ys))); cen.append((sum(v.co.x for v in me.vertices) / len(me.vertices), sum(ys) / len(ys)))
        ev.to_mesh_clear()
    dur = (f1 - f0) / 30.0
    z0 = [min(r[i][1] for r in rows) for i in range(4)]
    # stance: foot within 2.5 cm of its own lowest point; implied ground speed = -dy/dt while planted
    speeds = []
    for i in range(4):
        v = []
        for k in range(1, len(rows)):
            if rows[k][i][1] < z0[i] + 0.025 and rows[k - 1][i][1] < z0[i] + 0.025:
                v.append((rows[k][i][0] - rows[k - 1][i][0]) * 30.0)
        speeds.append(sum(v) / len(v) if v else None)
    valid = [s for s in speeds if s is not None]
    seam = max(abs(rows[0][i][0] - rows[-1][i][0]) + abs(rows[0][i][1] - rows[-1][i][1]) for i in range(4))
    res[nm] = dict(frames=f1 - f0 + 1, seconds=round(dur, 3), mesh_min_z=round(min(minz), 3), mesh_min_z_start=round(minz[0], 3),
                   stance_speed_mps=[None if s is None else round(s, 2) for s in speeds],
                   ground_speed=round(sum(valid) / len(valid), 2) if valid else None,
                   hoof_seam_gap_m=round(seam, 3), body_y_shift=round(rows[-1][0][0] - rows[0][0][0], 3), center_shift_xy=[round(cen[-1][0] - cen[0][0], 2), round(cen[-1][1] - cen[0][1], 2)])
    print("METRIC", nm, json.dumps(res[nm]))
if len(args) > 1:
    json.dump(res, open(os.path.abspath(args[1]), 'w'), indent=1)
