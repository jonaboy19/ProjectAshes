import bpy
from mathutils import Vector, Matrix
def clip_minz(arm, mesh, ac, step=2):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = ac; ad.action_slot = ac.slots[0]
    sc = bpy.context.scene; res = []
    f0, f1 = int(ac.frame_range[0]), int(ac.frame_range[1])
    for f in range(f0, f1 + 1, step):
        sc.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get()
        ev = mesh.evaluated_get(dg); me = ev.to_mesh()
        mw = ev.matrix_world
        res.append(min((mw @ v.co).z for v in me.vertices)); ev.to_mesh_clear()
    return res
def shift_root(arm, ac, bone, dz_world, ramp=False):
    b = arm.data.bones[bone]
    d_arm = arm.matrix_world.inverted().to_3x3() @ Vector((0, 0, dz_world))
    d_loc = b.matrix_local.to_3x3().inverted() @ d_arm
    for lay in ac.layers:
        for st in lay.strips:
            for cb in st.channelbags:
                for fc in cb.fcurves:
                    if fc.data_path == f'pose.bones["{bone}"].location':
                        f0, f1 = ac.frame_range
                        for k in fc.keyframe_points:
                            w = 1.0
                            if ramp:
                                t = min(1, max(0, (k.co[0] - f0) / max(1, f1 - f0)))
                                w = t * t * (3 - 2 * t)
                            dd = d_loc[fc.array_index] * w
                            k.co[1] += dd; k.handle_left[1] += dd; k.handle_right[1] += dd
                        fc.update()
def fix_ground(arm, mesh, root, skip=("death",), tol=0.01):
    for ac in list(bpy.data.actions):
        m = clip_minz(arm, mesh, ac)
        s = sorted(m); med = s[len(s)//2]
        # contact level: the lower-quartile of per-frame minima should sit on 0
        q = s[len(s)//4]
        print("GROUND", ac.name, "min %.3f q25 %.3f med %.3f max %.3f" % (s[0], q, med, s[-1]))
        if ac.name in skip:
            if abs(m[-1]) > tol:
                shift_root(arm, ac, root, -m[-1], ramp=True)
                m2 = clip_minz(arm, mesh, ac)
                print("  FIXED(ramp)", ac.name, "end %.3f min %.3f" % (m2[-1], min(m2)))
            continue
        if abs(q) > tol:
            shift_root(arm, ac, root, -q)
            m2 = sorted(clip_minz(arm, mesh, ac))
            print("  FIXED", ac.name, "min %.3f q25 %.3f" % (m2[0], m2[len(m2)//4]))
    arm.animation_data.action = None
