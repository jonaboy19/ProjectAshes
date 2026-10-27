"""MPFB (MakeHuman) body builder, CHARACTER_PLAN.md step 2-3 (pilot: the Ashford villager man).
Builds a human from MPFB macro targets, the game_engine rig (Unreal bone names = the UAL names the game uses), a CC0 skin,
eyebrows, eyes, hair and CC0 clothes (MakeHuman asset packs installed in the MPFB user data dir, see docs/plans/DOWNLOADS.md),
then exports a skinned GLB and a preview render.
Usage: blender -b --python tools/blender/mpfb/build_body.py -- <out.glb> [--preset villager_man] [--preview out.png]
Stage 1 (this file): geometry, rig, weights, materials as MPFB sets them up. Texture baking to the game budget and LODs are
stage 2 (bake_lod.py).
"""
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else "mpfb_body.glb"
PRESET = argv[argv.index("--preset") + 1] if "--preset" in argv else "villager_man"
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else ""

import addon_utils
for mod in ("bl_ext.user_default.mpfb",):
    addon_utils.enable(mod, default_set=True)
from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.locationservice import LocationService

DATA = LocationService.get_user_data()

PRESETS = {
    # macro targets 0..1 (MPFB): gender 1 = male; age 0.5 = 25 y; a lean working man; European
    "villager_man": {
        "macro": {"gender": 1.0, "age": 0.56, "muscle": 0.6, "weight": 0.45, "proportions": 0.55, "height": 0.5,
                  "cupsize": 0.5, "firmness": 0.5, "race": {"asian": 0.0, "caucasian": 1.0, "african": 0.0}},
        "skin": "skins/middleage_caucasian_male/middleage_caucasian_male.mhmat",
        "eyebrows": "eyebrows/eyebrow004/eyebrow004.mhclo",
        "eyes": "eyes/low-poly/low-poly.mhclo",
        "eye_mat": "eyes/materials/brown.mhmat",
        "hair": "hair/short02/short02.mhclo",
        "clothes": ["clothes/rehmanpolanski_viking_tunic/rehmanpolanski_viking_tunic.mhclo",
                    "clothes/rehmanpolanski_viking_pants/rehmanpolanski_viking_pants.mhclo",
                    "clothes/rehmanpolanski_viking_boots/rehmanpolanski_viking_boots.mhclo"],
    },
}


def path(rel):
    p = os.path.join(DATA, rel)
    if not os.path.isfile(p):
        raise FileNotFoundError(p)
    return p


bpy.ops.wm.read_factory_settings(use_empty=True)
pre = PRESETS[PRESET]
basemesh = HumanService.create_human(macro_detail_dict=pre["macro"], scale=0.1)
basemesh.name = "MPFB_" + PRESET
rig = HumanService.add_builtin_rig(basemesh, "game_engine", import_weights=True)
HumanService.set_character_skin(path(pre["skin"]), basemesh, skin_type="GAMEENGINE")
HumanService.add_mhclo_asset(path(pre["eyebrows"]), basemesh, asset_type="Eyebrows", subdiv_levels=0)
if pre.get("eyes"):
    HumanService.add_mhclo_asset(path(pre["eyes"]), basemesh, asset_type="Eyes", subdiv_levels=0, alternative_materials=None)
HumanService.add_mhclo_asset(path(pre["hair"]), basemesh, asset_type="Hair", subdiv_levels=0)
for c in pre["clothes"]:
    HumanService.add_mhclo_asset(path(c), basemesh, asset_type="Clothes", subdiv_levels=0)

objs = [o for o in bpy.data.objects if o.type == "MESH"]
tris = 0
for o in objs:
    dg = bpy.context.evaluated_depsgraph_get()
    me = o.evaluated_get(dg).to_mesh()
    tris += sum(len(p.vertices) - 2 for p in me.polygons)
    o.evaluated_get(dg).to_mesh_clear()
print("MPFB objects", [o.name for o in bpy.data.objects], "tris", tris)
if rig:
    print("MPFB bones", len(rig.data.bones), [b.name for b in rig.data.bones][:12])

if os.environ.get("MPFB_NO_EXPORT"):
    pass
elif PREVIEW:
    scn = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scn.collection.objects.link(cam)
    cam.location = (1.6, -3.4, 1.15)
    cam.rotation_euler = (math.radians(86), 0, math.radians(25))
    cam.data.lens = 60
    scn.camera = cam
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(30))
    scn.collection.objects.link(sun)
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scn.render.resolution_x = 700
    scn.render.resolution_y = 1000
    scn.world = bpy.data.worlds.new("W")
    scn.world.color = (0.55, 0.58, 0.62)
    scn.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)
    print("MPFB preview", PREVIEW)

if not os.environ.get("MPFB_NO_EXPORT"):
  bpy.ops.object.select_all(action="SELECT")
  bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True, export_skins=True,
                          export_animations=False, use_selection=True)
  print("MPFB_DONE", OUT)
