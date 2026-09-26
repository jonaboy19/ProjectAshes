"""Village-square composite preview: the well in the middle of a flagstone
square, lamp posts, the market cart and hand cart, a signpost, the bell tower
closing the far side, and the existing Blender village houses, inn and stall
around it, to check that the new landmarks and props sit naturally with the
houses.

Run: python3 make_village_square_preview.py <dir with the .glb files> <out.png>
(build_town_assets.py calls this after building the set).
"""
import os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from town_kit import TK, palette, WALLSTONE
from ra_kit import render_preview, hexc, vary, mix

SRC, PNG = sys.argv[1], sys.argv[2]

# paved square (built with the kit so it shares the look), then the assets are imported around it
k = TK("VillageSquareGround", seed=5, pal=palette(stone="field"))
k.flagstones(-9.0, 9.0, -9.0, 9.5, 0.03, size=(0.9, 0.6),
             color_fn=lambda: vary(mix(random.choice(WALLSTONE), hexc("7a7468"), 0.6), 0.05), base=False)
k.box((19.0, 19.5, 0.04), (0, 0.25, 0.0), k.M("Matte"), hexc("4a4540"), var=0, grime=False)
ground = k.build_object()      # kept separate: its colour attribute differs from the imported meshes'
objs = []

# (asset, x, y, rotation about Z); houses face -Y by default, rz=+pi/2 turns the front to +X
PLACE = [
    ("village_well", 0.0, 0.5, 0.3),
    ("bell_tower", 0.0, 15.0, 0.0),
    ("village_house_c", -9.5, 14.0, 0.0),
    ("village_inn", 11.5, 15.0, 0.0),
    ("village_house_a", -13.0, 3.5, math.pi / 2),
    ("village_house_d_2", -13.5, -5.5, math.pi / 2),
    ("village_house_b", 13.5, 3.0, -math.pi / 2),
    ("village_stall", 6.0, -5.5, -0.35),
    ("lamp_post", 3.2, 3.6, math.radians(215)),
    ("lamp_post", -3.4, -2.6, math.radians(35)),
    ("lamp_post", -7.6, 8.4, math.radians(-40)),
    ("market_cart", -3.2, -5.2, -0.35),
    ("hand_cart", -4.8, 3.4, 2.2),
    ("signpost", -7.8, -9.0, 0.2),
    ("woodpile", -17.5, 9.0, math.pi / 2),
    ("haystack", 18.0, -6.0, 0.0),
]
for name, x, y, rz in PLACE:
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    for o in [o for o in bpy.data.objects if o not in before and o.type == "MESH"]:
        o.rotation_euler.z += rz
        o.location = (o.location.x + x, o.location.y + y, o.location.z)
        objs.append(o)

bpy.ops.object.select_all(action="DESELECT")
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
ob = bpy.context.active_object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
render_preview(ob, PNG, "ground", cam_dir=(0.35, -1.5, 0.6), fit=0.56, focus_z=3.0)
