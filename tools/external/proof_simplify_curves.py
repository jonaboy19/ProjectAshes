"""Proof: Simplify Curves+ (graph.simplify) reduces a baked 240-key mocap-like curve.
Run: tools/external/blender.sh tools/external/proof_simplify_curves.py -- <out_dir>
"""
import sys, os, bpy, math, random
sys.path.insert(0, os.path.dirname(__file__))
import bl_common as C

C.clear_scene()
C.enable("bl_ext.user_default.simplify_curves_plus")
ob = bpy.data.objects.new("e", None)
bpy.context.scene.collection.objects.link(ob)
bpy.context.view_layer.objects.active = ob
random.seed(1)
for f in range(1, 241):
    ob.location.x = math.sin(f / 20.0) * 2 + random.uniform(-0.01, 0.01)
    ob.keyframe_insert("location", index=0, frame=f)
def fcs(o):
    a = o.animation_data.action
    return [fc for l in a.layers for s in l.strips for cb in s.channelbags for fc in cb.fcurves]
before = len(fcs(ob)[0].keyframe_points)
print("KEYS before", before)
print("POLL", bpy.ops.graph.simplify.poll())
bpy.ops.graph.simplify(error=0.03)
after = len(fcs(ob)[0].keyframe_points)
print("KEYS after", after)
assert after < before
