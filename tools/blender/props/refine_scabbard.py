"""Texture the player worker's arming-sword scabbard (tools/blender/props/build_scabbard.py, geometry and frame are theirs)
with the refine pipeline: dark brown_leather over the core, rusty_metal_02 wrought-iron throat and chape, a slightly lighter
belt-frog leather, edge wear / grime baked into one 1K set. The scabbard's frame is kept exactly (origin = sword grip centre,
blade along +Y in glTF) so the rig's hip socket places it as before.
Usage: tools/external/blender.sh tools/blender/props/refine_scabbard.py -- [<out.glb>]
"""
import bpy, sys, os, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refine_lib as RL

HERE = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = r"C:\Users\Jonna\Tools\_scratch\refine"
OUT = argv[0] if argv else os.path.join(RL.ASSETS, "props_refined", "scabbard_arming", "scabbard_arming.glb")
RAW = os.path.join(WORK, "scabbard_raw.glb")

# 1) run their builder unchanged into a scratch GLB
sys.argv = [sys.argv[0], "--", RAW]
exec(compile(open(os.path.join(HERE, "build_scabbard.py"), encoding="utf-8").read(), "build_scabbard.py", "exec"), {"__name__": "__main__"})

# 2) re-import, map their flat materials to scan classes
RL.LIB["scab_leather"] = dict(RL.LIB["leather"], val=0.32, sat=0.85, wear=0.45, grime=0.5)     # dark, worn at the edges
RL.LIB["frog_leather"] = dict(RL.LIB["leather"], val=0.42, sat=0.9, wear=0.35, grime=0.4)
MAP = {"ScabbardLeather": "scab_leather", "FrogLeather": "frog_leather", "ScabbardIron": "iron"}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=RAW)
ob = RL.join([o for o in bpy.context.scene.objects if o.type == "MESH"], "scabbard_arming")
mats = {}
me = ob.data
new = []
for slot in me.materials:
    base = slot.name.split(".")[0]
    cls = MAP.get(base, "scab_leather")
    if cls not in mats:
        mats[cls] = RL.make_material(cls)
    new.append(mats[cls])
idx = [p.material_index for p in me.polygons]
me.materials.clear()
for m in new:
    me.materials.append(m)
for p, i in zip(me.polygons, idx):
    p.material_index = i
RL.smart_uv(ob, angle=60.0, margin=0.004)
tmp = os.path.join(WORK, "bake_scabbard")
fm = RL.bake_asset(ob, 1024, tmp, "scabbard_arming")
RL.finalize_materials(ob, fm)
RL.export_glb(ob, OUT)
RL.write_license(os.path.dirname(OUT), "scabbard_arming", "Geometry: tools/blender/props/build_scabbard.py (project-owned, player worker); "
                 "materials: Poly Haven CC0 brown_leather + rusty_metal_02 (committed by the coordinator, fbf4e24a9).")
bpy.data.objects.remove(ob)
for g in list(bpy.data.node_groups):
    bpy.data.node_groups.remove(g)
bpy.ops.import_scene.gltf(filepath=OUT)
newobs = [o for o in bpy.context.selected_objects if o.type == "MESH"]
# lying the 95 cm scabbard on its side reads best at prop-sheet scale: yaw/pitch chosen for a 3/4 view along its length
RL.render_view(newobs, os.path.join(WORK, "gate", "scabbard_arming_B_refined.jpg"), res=(480, 640), yaw=60, pitch=12)
with open(os.path.join(WORK, "stats.txt"), "a") as f:
    mn, mx = RL.bbox_of(newobs)
    f.write(f"scabbard_arming\t{sum(RL.tri_count(o) for o in newobs)}\t1024\t{tuple(round(x, 2) for x in (mx - mn))}\n")
shutil.rmtree(tmp, ignore_errors=True)
os.remove(RAW)
print("DONE")
