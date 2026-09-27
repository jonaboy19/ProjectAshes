import bpy, sys, os
argv = sys.argv[sys.argv.index("--") + 1:]
def arm_of(p):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=p)
    new = [o for o in bpy.data.objects if o not in before and o.type == "ARMATURE"]
    return new[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
a = arm_of(argv[0]); b = arm_of(argv[1])
print("world scale", a.matrix_world.to_scale(), b.matrix_world.to_scale())
worst = []
for bn in a.data.bones:
    name = bn.name
    other = b.data.bones.get(name) or b.data.bones.get(name.lower()) or b.data.bones.get(name.capitalize())
    if not other:
        print("MISSING in B:", name); continue
    qa = bn.matrix_local.to_quaternion(); qb = other.matrix_local.to_quaternion()
    ang = qa.rotation_difference(qb).angle * 57.2958
    d = (bn.head_local - other.head_local).length
    worst.append((ang, d, name))
worst.sort(reverse=True)
worst=[w for w in worst if "leaf" not in w[2]]
for w in worst[:12]: print("rot %.2f deg  pos %.4f  %s" % w)
print("mean rot", sum(w[0] for w in worst)/len(worst))
