import json,struct,pathlib
p=pathlib.Path('hero_source.glb'); data=p.read_bytes(); n,t=struct.unpack_from('<II',data,12); doc=json.loads(data[20:20+n]);
for key in ('extensionsRequired','extensionsUsed'):
 if key in doc: doc[key]=[x for x in doc[key] if x!='KHR_node_visibility']
for node in doc.get('nodes',[]):
 ext=node.get('extensions',{})
 if ext.get('KHR_node_visibility',{}).get('visible') is False: node.pop('mesh',None)
 ext.pop('KHR_node_visibility',None)
 if not ext: node.pop('extensions',None)
j=json.dumps(doc,separators=(',',':')).encode(); j+=b' '*((-len(j))%4); tail=data[20+n:]; out=struct.pack('<III',0x46546c67,2,20+len(j)+len(tail))+struct.pack('<II',len(j),0x4e4f534a)+j+tail;p.with_name('hero_source_blender.glb').write_bytes(out)

