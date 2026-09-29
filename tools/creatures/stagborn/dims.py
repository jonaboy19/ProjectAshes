import bpy, sys, os
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(sys.argv[-1]))
m = [o for o in bpy.data.objects if o.type == 'MESH' and len(o.vertex_groups) > 5][0]
vs = [m.matrix_world @ v.co for v in m.data.vertices]
print("DIM", [round(min(v[i] for v in vs), 2) for i in range(3)], [round(max(v[i] for v in vs), 2) for i in range(3)], "tris", sum(len(p.vertices) - 2 for p in m.data.polygons), "bones", len([b for b in bpy.data.objects if b.type == 'ARMATURE'][0].data.bones))
