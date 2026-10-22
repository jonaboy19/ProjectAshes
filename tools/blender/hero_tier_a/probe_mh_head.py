"""Probe: MakeHuman player_young head region (components, bounds) for the Tier-A head build.
tools/external/blender.sh tools/blender/hero_tier_a/probe_mh_head.py -- <glb>"""
import bpy, sys, bmesh
from mathutils import Vector

glb = sys.argv[sys.argv.index("--") + 1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=glb)
mesh = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
print("ARM bones", len(arm.data.bones), [b.name for b in arm.data.bones][:70])
print("OBJS", [(o.name,o.type,len(o.data.vertices) if o.type=="MESH" else 0) for o in bpy.data.objects]); print("VG", [g.name for g in mesh.vertex_groups][:12])
gi = {g.index: g.name for g in mesh.vertex_groups}
me = mesh.data
headw = {}
for v in me.vertices:
    w = 0.0
    for g in v.groups:
        if gi[g.group] in ("Head",):
            w += g.weight
    headw[v.index] = w
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
seen = set()
comps = []
for v in bm.verts:
    if v.index in seen or headw[v.index] < 0.5:
        continue
    stack = [v]; comp = []
    seen.add(v.index)
    while stack:
        a = stack.pop(); comp.append(a)
        for e in a.link_edges:
            b = e.other_vert(a)
            if b.index not in seen and headw[b.index] > 0.0:
                seen.add(b.index); stack.append(b)
    comps.append(comp)
M = mesh.matrix_world
for c in sorted(comps, key=len, reverse=True)[:20]:
    pts = [M @ v.co for v in c]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    nf = len({f.index for v in c for f in v.link_faces})
    print("COMP verts=%d faces=%d min=%s max=%s" % (len(c), nf, tuple(round(x, 3) for x in mn), tuple(round(x, 3) for x in mx)))
print("UVS", [u.name for u in me.uv_layers], "MATS", [m.name for m in me.materials])
hb = arm.data.bones["Head"]
print("HEAD bone head", arm.matrix_world @ hb.head_local, "tail", arm.matrix_world @ hb.tail_local)
