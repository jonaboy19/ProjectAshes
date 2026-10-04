import bpy,json
from pathlib import Path
base=Path(__file__).parent
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(base/'hero_source_blender.glb'))
changes=[]
for o in list(bpy.context.scene.objects):
 if o.type!='MESH':continue
 bpy.context.view_layer.objects.active=o
 if 'head_3' in o.name or 'hands_default' in o.name:
  before=len(o.data.polygons)
  sub=o.modifiers.new('Controlled face and hand refinement','SUBSURF');sub.levels=1
  bpy.ops.object.modifier_apply(modifier=sub.name)
  for p in o.data.polygons:p.use_smooth=True
  changes.append({'mesh':o.name,'faces_before':before,'faces_after':len(o.data.polygons),'weighted_vertices':len(o.vertex_groups)})
 for mat in o.data.materials:
  if mat and mat.use_nodes:
   bs=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
   if bs:
    bs.inputs['Roughness'].default_value=.82 if 'head' in o.name or 'hand' in o.name else (.67 if 'boots' in o.name else .9)
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
triangles=0
for o in meshes:o.data.calc_loop_triangles();triangles+=len(o.data.loop_triangles)
if triangles>15000:raise RuntimeError('Hero candidate over triangle cap')
bpy.ops.wm.save_as_mainfile(filepath=str(base/'hero_refined_rigged.blend'))
bpy.ops.export_scene.gltf(filepath=str(base/'hero_refined_rigged.glb'),export_format='GLB')
(base/'hero_refined_rigged.metrics.json').write_text(json.dumps({'triangles':triangles,'changes':changes,'mesh_count':len(meshes),'armatures':len([o for o in bpy.context.scene.objects if o.type=='ARMATURE'])},indent=2))
