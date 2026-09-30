"""GLB -> OBJ (geometry only, all meshes merged, triangulated) for tools that only read OBJ/PLY (Instant Meshes).
  tools/external/blender.sh tools/external/glb_to_obj.py -- in.glb out.obj
Prints the triangle count. Also: OBJ -> GLB with  ... glb_to_obj.py -- --back in.obj out.glb
"""
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
back = a[0] == "--back"
if back:
    a = a[1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
if not back:
    bpy.ops.import_scene.gltf(filepath=a[0])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in bpy.context.scene.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    # bake world transform into the mesh so the OBJ is in scene space
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    m = o.modifiers.new("tri", "TRIANGULATE")
    bpy.ops.object.modifier_apply(modifier=m.name)
    print("TRIS", len(o.data.polygons), "VERTS", len(o.data.vertices))
    bpy.ops.wm.obj_export(filepath=a[1], export_selected_objects=True, export_uv=False, export_normals=False, export_materials=False)
else:
    bpy.ops.wm.obj_import(filepath=a[0])
    o = bpy.context.selected_objects[0]
    m = o.modifiers.new("tri", "TRIANGULATE")
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)
    print("TRIS", len(o.data.polygons), "VERTS", len(o.data.vertices))
    bpy.ops.export_scene.gltf(filepath=a[1], export_format="GLB")
