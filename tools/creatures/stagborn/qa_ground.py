"""Per clip: lowest hoof (bone tail) height, lowest head/antler vertex height, lowest vertex overall, stance speeds.
blender -b --python qa_ground.py -- <glb> [clip ...]"""
import bpy, sys, os
args = sys.argv[sys.argv.index('--') + 1:]
glb = os.path.abspath(args[0]); only = set(args[1:])
bpy.ops.wm.read_factory_settings(use_empty=True); bpy.context.scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
mesh = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.vertex_groups) > 5][0]
arm.animation_data_create()
HOOF = ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]
sc.frame_set(0)
rest = [v.co.z for v in mesh.data.vertices]; zmax = max(rest)
hv = [i for i, z in enumerate(rest) if z > 0.42 * zmax]      # head, upper neck and antlers (rest pose)
for a in sorted(bpy.data.actions, key=lambda x: x.name):
    nm = a.name.split('|')[-1]
    if only and nm not in only: continue
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]
    f0, f1 = int(round(a.frame_range[0])), int(round(a.frame_range[1]))
    hz = []; headz = []; allz = []; rows = []
    for f in range(f0, f1 + 1):
        sc.frame_set(f); dg = bpy.context.evaluated_depsgraph_get()
        pos = [arm.matrix_world @ arm.pose.bones[h].tail for h in HOOF]
        rows.append([(p.y, p.z) for p in pos]); hz.append(min(p.z for p in pos))
        ev = mesh.evaluated_get(dg); me = ev.to_mesh()
        headz.append(min(me.vertices[i].co.z for i in hv)); allz.append(min(v.co.z for v in me.vertices)); ev.to_mesh_clear()
    z0 = [min(r[i][1] for r in rows) for i in range(4)]; sp = []
    for i in range(4):
        v = [(rows[k][i][0] - rows[k-1][i][0]) * 30 for k in range(1, len(rows)) if rows[k][i][1] < z0[i] + 0.025 and rows[k-1][i][1] < z0[i] + 0.025]
        sp.append(round(sum(v) / len(v), 2) if v else None)
    # max within-stance deviation from constant speed (cm)
    dev = []
    for i in range(4):
        v = [(rows[k][i][0] - rows[k-1][i][0]) * 30 for k in range(1, len(rows)) if rows[k][i][1] < z0[i] + 0.025 and rows[k-1][i][1] < z0[i] + 0.025]
        dev.append(round((max(v) - min(v)) if v else 0, 2))
    print("GROUND %-12s frames %3d hoof_min_z %.3f (max over cycle %.3f) head_min_z %.3f all_min_z %.3f stance %s spread %s" % (nm, f1 - f0 + 1, min(hz), max(hz), min(headz), min(allz), sp, dev))
