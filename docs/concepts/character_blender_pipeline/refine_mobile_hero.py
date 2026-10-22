import bpy,json
from pathlib import Path
p=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(p/'hero_refined_rigged.blend'))
for o in bpy.context.scene.objects:
 if o.type=='MESH' and ('head_3' in o.name or 'hands_default' in o.name):
  bpy.context.view_layer.objects.active=o
  dec=o.modifiers.new('Mobile face and hand budget','DECIMATE');dec.ratio=.45;dec.use_collapse_triangulate=True
  bpy.ops.object.modifier_apply(modifier=dec.name)
triangles=0;meshes=[]
for o in bpy.context.scene.objects:
 if o.type=='MESH':
  o.data.calc_loop_triangles();n=len(o.data.loop_triangles);triangles+=n
  meshes.append({'name':o.name,'triangles':n,'vertex_groups':len(o.vertex_groups)})
if triangles>6000:raise RuntimeError('Mobile candidate exceeds 6000 triangles')
bpy.ops.export_scene.gltf(filepath=str(p/'hero_refined_mobile.glb'),export_format='GLB',export_animations=False)
(p/'hero_refined_mobile.metrics.json').write_text(json.dumps({'triangles':triangles,'meshes':meshes,'armatures':len([o for o in bpy.context.scene.objects if o.type=='ARMATURE']),'animations_exported':False},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(p/'hero_refined_mobile.blend'))
