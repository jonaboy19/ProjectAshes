import bpy,json,math
from pathlib import Path
from mathutils import Vector
p=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(p/'hero_refined_mobile.blend'))
o=bpy.data.objects['HeroOutfit'];mesh=o.data;color=mesh.color_attributes['Color'];edges={}
for poly in mesh.polygons:
 loops=list(poly.loop_indices)
 for k,li in enumerate(loops):
  lj=loops[(k+1)%len(loops)];a=mesh.loops[li].vertex_index;b=mesh.loops[lj].vertex_index
  va=mesh.vertices[a].co;vb=mesh.vertices[b].co
  key=tuple(sorted((tuple(round(x,5) for x in va),tuple(round(x,5) for x in vb))))
  c=color.data[li].color
  if key not in edges:edges[key]=[0,a,b,poly.normal.copy(),tuple(c)]
  edges[key][0]+=1
eligible=[]
for count,a,b,n,c in edges.values():
 va=mesh.vertices[a].co;vb=mesh.vertices[b].co
 if count==1 and c[0]>c[1]*1.3 and .65<(va.z+vb.z)*.5<1.55 and (va-vb).length>.02:
  eligible.append((a,b,n))
verts=[];faces=[];weights=[]
for a,b,n in sorted(eligible,key=lambda e:(mesh.vertices[e[0]].co-mesh.vertices[e[1]].co).length,reverse=True):
 va=mesh.vertices[a].co;vb=mesh.vertices[b].co;delta=vb-va;length=delta.length;tangent=delta.normalized();side=n.cross(tangent).normalized()
 for distance in [i*.015+.005 for i in range(max(1,int(length/.015)))]:
  if distance+.008>length or len(faces)>=240:break
  t=(distance+.004)/length;center=va+delta*t+n*.0015
  corners=[center-tangent*.004-side*.00085,center+tangent*.004-side*.00085,center+tangent*.004+side*.00085,center-tangent*.004+side*.00085]
  ws={}
  for v,f in [(mesh.vertices[a],1-t),(mesh.vertices[b],t)]:
   for g in v.groups:ws[g.group]=ws.get(g.group,0)+g.weight*f
  ix=len(verts);verts.extend(corners);weights.extend([ws]*4);faces.extend([(ix,ix+1,ix+2),(ix,ix+2,ix+3)])
me=bpy.data.meshes.new('LeatherStitches');me.from_pydata(verts,[],faces);me.update()
st=bpy.data.objects.new('LeatherStitches',me);bpy.context.collection.objects.link(st);st.matrix_world=o.matrix_world.copy()
me.materials.append(o.data.materials[0])
col=me.color_attributes.new(name='Color',type='FLOAT_COLOR',domain='CORNER')
for d in col.data:d.color=(.38,.25,.12,1)
for g in o.vertex_groups:st.vertex_groups.new(name=g.name)
for i,ws in enumerate(weights):
 for g,w in ws.items():
  if w>.0001:st.vertex_groups[g].add([i],w,'REPLACE')
bpy.ops.object.select_all(action='DESELECT');o.select_set(True);st.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.join()
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
 if obj.type=='ARMATURE' or (obj.type=='MESH' and len(obj.vertex_groups)>0):obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(p/'hero_leather_detail.glb'),export_format='GLB',export_animations=False,use_selection=True)
bpy.ops.wm.save_as_mainfile(filepath=str(p/'hero_leather_detail.blend'))
(p/'hero_leather_detail.metrics.json').write_text(json.dumps({'stitched_boundary_edges':len(eligible),'stitch_triangles':len(faces),'geometry_offset_metres':.0015,'stitch_width_metres':.0017,'stitch_length_metres':.008,'production_status':'review candidate'},indent=2))
