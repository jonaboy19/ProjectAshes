import bpy, sys, json, os
d = sys.argv[sys.argv.index("--") + 1]
m = json.load(open(os.path.join(d, "_meshy_manifest_lod0.json")))
for k, v in m.items():
    p = os.path.join(d, k + "_lod1.glb")
    if not os.path.isfile(p): continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=p)
    v["tris_lod1"] = sum(len(q.vertices) - 2 for o in bpy.context.scene.objects if o.type == 'MESH' for q in o.data.polygons)
json.dump(m, open(os.path.join(d, "_meshy_manifest.json"), "w"), indent=1, sort_keys=True)
