import bpy, sys
sys.path.insert(0, r"C:\Users\Jonna\Documents\PA_wt_horse\kingdom\tools\anim\horse")
import hx_common as X
from mathutils.bvhtree import BVHTree
from mathutils import Vector
arm, lod0 = X.open_rig()
bv = BVHTree.FromObject(lod0, bpy.context.evaluated_depsgraph_get())
def ext(y,z):  # x extent at (y,z)
    h=bv.ray_cast(Vector((1,y,z)),Vector((-1,0,0)))
    return None if h[0] is None else round(h[0].x,3)
def top(x,y):
    h=bv.ray_cast(Vector((x,y,3)),Vector((0,0,-1)))
    return None if h[0] is None else round(h[0].z,3)
def bot(x,y):
    h=bv.ray_cast(Vector((x,y,-1)),Vector((0,0,1)))
    return None if h[0] is None else round(h[0].z,3)
print("PROBE barrel top/bot at x=0")
for y in (-0.7,-0.5,-0.4,-0.3,-0.24,-0.1,0.0,0.1,0.2,0.3,0.5,0.7,0.85):
    print("PROBE y=%.2f top=%s bot=%s"%(y,top(0,y),bot(0,y)), "xext@z", {z:ext(y,z) for z in (1.4,1.3,1.2,1.1,1.0,0.9)})
print("PROBE head")
for y in (-1.1,-1.15,-1.2,-1.25,-1.3,-1.35,-1.4,-1.45):
    print("PROBE y=%.2f top=%s bot=%s"%(y,top(0,y),bot(0,y)), "xext@z", {z:ext(y,z) for z in (1.9,1.8,1.7,1.6,1.5,1.45,1.4)})
print("PROBE neck")
for y in (-0.7,-0.8,-0.9,-1.0,-1.1):
    print("PROBE y=%.2f top=%s bot=%s"%(y,top(0,y),bot(0,y)), "xext@z", {z:ext(y,z) for z in (1.9,1.8,1.7,1.6,1.5,1.4,1.3)})
