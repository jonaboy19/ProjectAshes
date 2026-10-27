# List objects / meshes of an FBX (blender -b -P inspect_fbx.py -- <file.fbx>)
import bpy, sys
f = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=f)
for ob in bpy.context.scene.objects:
    if ob.type == "MESH":
        bb = [ob.matrix_world @ v.co for v in ob.data.vertices]
        mn = [min(v[i] for v in bb) for i in range(3)]
        mx = [max(v[i] for v in bb) for i in range(3)]
        print("OBJ", ob.name, len(ob.data.vertices), [round(x, 2) for x in mn], [round(x, 2) for x in mx], [m.name for m in ob.data.materials])
