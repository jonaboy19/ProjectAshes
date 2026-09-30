"""blender -b --python inspect_glb.py -- <glb>  : list armature, bones, clips, bbox, tris"""
import bpy, sys, mathutils
glb = sys.argv[sys.argv.index('--')+1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
print("ARM", arm.name, tuple(arm.scale), tuple(arm.rotation_euler), "parent", arm.parent)
tris=0
for o in bpy.data.objects:
    if o.type=='MESH':
        tris+=sum(len(p.vertices)-2 for p in o.data.polygons); print("MESH",o.name,len(o.data.vertices),o.parent.name if o.parent else None, tuple(o.scale))
print("TRIS",tris)
print("BONES",len(arm.data.bones))
for b in arm.data.bones: print("  ",b.name,"<-",b.parent.name if b.parent else None, "deform" if b.use_deform else "-", tuple(round(x,3) for x in b.head_local), tuple(round(x,3) for x in b.tail_local))
for a in bpy.data.actions:
    print("ACT",a.name,tuple(a.frame_range), len(a.fcurves) if hasattr(a,'fcurves') else '?')
