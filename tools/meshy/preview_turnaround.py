"""Usage: blender -b --python tools/meshy/preview_turnaround.py -- <model.glb> <out.png>  (4-angle strip)"""
# Render a model from 4 angles into one strip, auto-framed.
import bpy, sys, math, mathutils
f, out = sys.argv[-2:]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc=bpy.context.scene
bpy.ops.import_scene.gltf(filepath=f)
ms=[o for o in sc.objects if o.type=='MESH']
pts=[o.matrix_world@mathutils.Vector(c) for o in ms for c in o.bound_box]
mn=mathutils.Vector([min(p[i] for p in pts) for i in range(3)]); mx=mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
ctr=(mn+mx)/2; rad=(mx-mn).length/2
w=bpy.data.worlds.new("w"); sc.world=w; w.use_nodes=True
bg=w.node_tree.nodes["Background"]; bg.inputs[0].default_value=(0.78,0.85,0.95,1); bg.inputs[1].default_value=1.1
sun=bpy.data.objects.new("sun",bpy.data.lights.new("sun",'SUN')); sun.data.energy=3.0; sun.rotation_euler=(math.radians(50),0,math.radians(30)); sc.collection.objects.link(sun)
cam=bpy.data.objects.new("cam",bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera=cam; cam.data.lens=50
sc.render.engine='BLENDER_EEVEE' if 'BLENDER_EEVEE' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x=700; sc.render.resolution_y=600; sc.view_settings.view_transform='Standard'
import os
tiles=[]
for i,ang in enumerate([-35,55,145,235]):
    a=math.radians(ang); dist=rad*2.9
    cam.location=ctr+mathutils.Vector((math.sin(a)*dist,-math.cos(a)*dist,rad*1.0))
    cam.rotation_euler=(ctr-cam.location).to_track_quat('-Z','Y').to_euler()
    p=out.replace(".png",f"_{i}.png"); sc.render.filepath=p; bpy.ops.render.render(write_still=True); tiles.append(p)
# stitch
imgs=[bpy.data.images.load(p) for p in tiles]
W,H=imgs[0].size; big=bpy.data.images.new("strip",W*len(imgs),H)
import array
buf=[0.0]*(W*len(imgs)*H*4)
for k,im in enumerate(imgs):
    px=list(im.pixels)
    for y in range(H):
        s=y*W*4; d=(y*W*len(imgs)+k*W)*4
        buf[d:d+W*4]=px[s:s+W*4]
big.pixels=buf; big.filepath_raw=out; big.file_format='PNG'; big.save()
for p in tiles: os.remove(p)
print("DONE",out)
