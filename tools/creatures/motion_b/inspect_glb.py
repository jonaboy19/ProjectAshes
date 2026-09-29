import bpy, sys
a = sys.argv[sys.argv.index('--')+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
arm=[o for o in bpy.data.objects if o.type=='ARMATURE'][0]
print("ARM",arm.name,tuple(arm.scale),tuple(arm.location),tuple(arm.rotation_euler), arm.parent)
for m in bpy.data.objects:
    print("OBJ",m.name,m.type,m.parent.name if m.parent else None)
print("BONES",[ (b.name, b.parent.name if b.parent else None) for b in arm.data.bones])
for ac in bpy.data.actions:
    n=0; kp=0
    for lay in ac.layers:
        for st in lay.strips:
            for cb in st.channelbags:
                n+=len(cb.fcurves); kp+=sum(len(f.keyframe_points) for f in cb.fcurves)
    print("ACT",ac.name,tuple(ac.frame_range),n,"fcurves",kp,"keys", [s.identifier for s in ac.slots])
