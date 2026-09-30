import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(bpy.data.filepath or __file__))) if False else r"C:\Users\Jonna\Documents\PA_wt_horse\kingdom\tools\anim\horse")
import hx_common as X, horse_coats as HC
arm, lod0 = X.open_rig()
HC.build_all(lod0)
X.setup_scene_render(1400, 800)
X.ground()
import math
names = HC.COAT_ORDER
objs=[]
for i,c in enumerate(names):
    img = X.load_png(os.path.join(X.OUT,"horse_coat_%s.png"%c), "img_"+c)
    m = X.textured_material("m_"+c, img)
    o = lod0.copy(); o.data = lod0.data.copy(); bpy.context.scene.collection.objects.link(o)
    o.parent=None
    for mod in list(o.modifiers): o.modifiers.remove(mod)
    o.data.materials.clear(); o.data.materials.append(m)
    o.location=((i%3)*2.6-2.6, -(i//3)*4.2, 0)
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True); bpy.context.view_layer.objects.active=o
    bpy.ops.object.shade_smooth()
lod0.hide_render=True
X.camera((0,-14,4.2),(0,-2.0,0.9),lens=60)
X.render(r"C:\Users\Jonna\AppData\Local\Temp\hx_coats.png")
