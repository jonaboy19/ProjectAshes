"""Stage 1: import CC0 Quaternius UAA Stag, clean rig, scale to metres, merge antlers into the skin. Saves base.blend
blender -b --python s1_base.py -- <Stag.gltf> <out.blend> <scale>"""
import bpy, sys, mathutils
src, out, S = sys.argv[-3], sys.argv[-2], float(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
D = bpy.data
for o in list(D.objects):
    if o.name.startswith("Icosphere"): D.objects.remove(o)
arm = [o for o in D.objects if o.type == 'ARMATURE'][0]
body = D.objects["Stag"]; horns = D.objects["Stag_Horns"]
# horns: bone-parented -> skin to Head with weight 1
mw = horns.matrix_world.copy()
horns.parent = None; horns.matrix_world = mw
horns.parent = arm; horns.matrix_parent_inverse = arm.matrix_world.inverted()
vg = horns.vertex_groups.new(name="Head")
vg.add([v.index for v in horns.data.vertices], 1.0, 'REPLACE')
m = horns.modifiers.new("Armature", 'ARMATURE'); m.object = arm
# helper bones: merge any weights into nearest deform parent then delete
helpers = [b.name for b in arm.data.bones if b.name.startswith(("IK", "FF", "PoleTarget"))]
print("helpers", helpers)
merge_to = {"FF.L": "FrontLowerLeg.L", "FF.R": "FrontLowerLeg.R", "FFB.L": "BackLowerLeg.L", "FFB.R": "BackLowerLeg.R"}
for o in (body,):
    for h in helpers:
        if h in o.vertex_groups:
            tgt = merge_to.get(h)
            g = o.vertex_groups[h]
            n = 0
            for v in o.data.vertices:
                for ge in v.groups:
                    if ge.group == g.index and ge.weight > 0 and tgt:
                        o.vertex_groups[tgt].add([v.index], ge.weight, 'ADD'); n += 1
            print("merged", h, "->", tgt, n)
            o.vertex_groups.remove(g)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for h in helpers:
    eb = arm.data.edit_bones.get(h)
    if eb: arm.data.edit_bones.remove(eb)
bpy.ops.object.mode_set(mode='OBJECT')
# drop unwanted actions' helper channels + unused actions
keep = {"Idle", "Idle_2", "Idle_Headlow", "Eating", "Walk", "Gallop", "Attack_Headbutt", "Attack_Kick", "Idle_HitReact1", "Idle_HitReact2", "Death"}
for a in list(D.actions):
    if a.name not in keep: D.actions.remove(a)
NB = len(body.data.polygons)
# join antlers into skin
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); horns.select_set(True); bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
# scale: bones in edit mode + mesh verts (no object scale)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for eb in arm.data.edit_bones:
    eb.head = eb.head * S; eb.tail = eb.tail * S
bpy.ops.object.mode_set(mode="OBJECT")
for v in body.data.vertices: v.co *= S
for a in D.actions:
    for fc in [f for l in a.layers for s in l.strips for cb in s.channelbags for f in cb.fcurves]:
        if fc.data_path.endswith("location"):
            for kp in fc.keyframe_points:
                kp.co.y *= S; kp.handle_left.y *= S; kp.handle_right.y *= S
body["n_body_polys"] = NB
body.name = "mesh"; arm.name = "Armature"
bpy.ops.wm.save_as_mainfile(filepath=out)
vs = [v.co for v in body.data.vertices]
print("SIZE z", min(v.z for v in vs), max(v.z for v in vs), "y", min(v.y for v in vs), max(v.y for v in vs))
print("tris", sum(len(p.vertices) - 2 for p in body.data.polygons), "actions", [a.name for a in D.actions])
