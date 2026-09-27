"""Street composite preview for the village building set: imports the built
GLBs and lines six houses up along a street (with a market stall and fence
runs) to check that the palette/layout variants keep a row from looking
copy-pasted.

Run: python3 make_village_street_preview.py <dir with the .glb files> <out.png>
(build_village_assets.py calls this after building the set).
"""
import os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from ra_kit import render_preview

SRC, PNG = sys.argv[1], sys.argv[2]
# (asset, x offset along the street, y offset, rotation about Z)
ROW = [("village_house_a", 0.0), ("village_house_b_4", 8.2), ("village_house_d", 15.6), ("village_house_c_3", 23.6),
       ("village_house_a_4", 32.4), ("village_house_d_4", 39.2)]
EXTRA = [("village_stall", 12.0, -6.0, 0.0), ("village_stall_3", 36.0, -6.2, 0.15),
         ("flower_bed", 4.0, -3.9, 0.0), ("planter_box", 20.0, -4.4, 0.0), ("flower_bed", 28.4, -4.6, 0.2),
         ("planter_box", 43.0, -4.5, 0.0)]
FENCE = [(x, -3.9) for x in (-3.0, 0.0)] + [(x, -3.9) for x in (27.0, 30.0)]

bpy.ops.wm.read_factory_settings(use_empty=True)
objs = []


def place(name, x, y=0.0, rz=0.0):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    for o in new:
        o.location = (o.location.x + x, o.location.y + y, o.location.z)
        o.rotation_euler.z += rz
        objs.append(o)


for n, x in ROW:
    place(n, x)
for n, x, y, rz in EXTRA:
    place(n, x, y, rz)
for x, y in FENCE:
    place("fence_section", x, y)

# the imported materials already multiply base colour by COLOR_0; join into one object for the renderer
bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
ob = bpy.context.active_object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
render_preview(ob, PNG, "ground", cam_dir=(0.08, -1.5, 0.5), fit=0.76, focus_z=7.0)
