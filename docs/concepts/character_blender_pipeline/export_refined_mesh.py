import bpy,json
from pathlib import Path
p=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(p/'hero_refined_rigged.blend'))
bpy.ops.export_scene.gltf(filepath=str(p/'hero_refined_rigged.glb'),export_format='GLB',export_animations=False)
tris=0
for o in bpy.context.scene.objects:
 if o.type=='MESH':o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
(p/'hero_refined_rigged.metrics.json').write_text(json.dumps({'triangles':tris,'armatures':len([o for o in bpy.context.scene.objects if o.type=='ARMATURE']),'animations_exported':False},indent=2))
