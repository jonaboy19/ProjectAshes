import bpy
from mathutils import Vector
print("OBJS", [(o.name,o.type,o.parent.name if o.parent else None) for o in bpy.data.objects if not o.name.startswith("WGT")])
arm=bpy.data.objects["HorseSkeleton"]
print("ARMW", arm.matrix_world.translation, arm.scale)
for b in arm.data.bones:
    print("BONE %-14s par=%-10s h=(%.3f,%.3f,%.3f) t=(%.3f,%.3f,%.3f) d=%d"%(b.name,b.parent.name if b.parent else "-",*b.head_local,*b.tail_local,b.use_deform))
h=bpy.data.objects["Horse_LOD0"]
xs=[v.co for v in h.data.vertices]
print("BB",[ (min(c[i] for c in xs),max(c[i] for c in xs)) for i in range(3)])
print("tris",sum(len(p.vertices)-2 for p in h.data.polygons), "attrs",[(a.name,a.data_type,a.domain) for a in h.data.attributes], "uv",len(h.data.uv_layers),"mods",[m.type for m in h.modifiers], "vg", len(h.vertex_groups), "mats", len(h.data.materials))
import bpy
print(bpy.app.version_string)
