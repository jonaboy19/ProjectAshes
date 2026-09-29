"""Stage 3: rename/author clips, build LOD1, export GLBs.
blender -b --python s3_export.py -- <variant elk|warden> <char.blend> <out_dir>"""
import bpy, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
variant, blend, outd = sys.argv[-3:]
blend = os.path.abspath(blend); outd = os.path.abspath(outd); os.makedirs(outd, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=blend)
for im in bpy.data.images:
    if im.filepath:
        p = os.path.join(os.path.dirname(blend), os.path.basename(im.filepath_raw))
        if os.path.exists(p): im.filepath = p; im.reload()
D = bpy.data; sc = bpy.context.scene
W = variant == "warden"
arm = D.objects["Armature"]; mesh = D.objects["mesh"]
name = f"stagborn_{'warden' if W else 'elk'}"
mesh.name = name; mesh.data.name = name; arm.name = "Armature"

sc.render.fps = 30
import clips
clips.build(variant, arm)          # renames stock actions and authors the new ones (attack, roar, ...)
keep = clips.KEEP[variant]
for a in list(D.actions):
    if a.name not in keep: D.actions.remove(a)
for a in D.actions: a.use_fake_user = True
if arm.animation_data: arm.animation_data.action = None
print("CLIPS", sorted((a.name, round((a.frame_range[1] - a.frame_range[0]) / 30.0, 2)) for a in D.actions))

def export(path, objs):
    for o in D.objects: o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88,
                              export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True,
                              export_draco_mesh_compression_enable=False, export_apply=False, export_anim_single_armature=True,
                              export_def_bones=False, export_optimize_animation_size=False)
    print("EXPORTED", path, os.path.getsize(path) // 1024, "KB")

tris0 = sum(len(p.vertices) - 2 for p in mesh.data.polygons)
export(f"{outd}/{name}.glb", [mesh, arm])

# LOD1: decimated copy, 512 px textures
lod = mesh.copy(); lod.data = mesh.data.copy(); lod.name = name + "_lod1"
sc.collection.objects.link(lod)
mesh.hide_set(True); mesh.hide_viewport = True
target = 2000 if not W else 4600
mod = lod.modifiers.new("dec", 'DECIMATE'); mod.ratio = min(1.0, target / tris0); mod.use_collapse_triangulate = True
bpy.context.view_layer.objects.active = lod
for o in D.objects: o.select_set(o == lod)
bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
bpy.ops.object.modifier_apply(modifier="dec")
mat = lod.data.materials[0].copy(); lod.data.materials[0] = mat
for n in mat.node_tree.nodes:
    if n.type == 'TEX_IMAGE' and n.image:
        im = D.images.load(os.path.join(os.path.dirname(blend), os.path.basename(n.image.filepath_raw))); im.scale(512, 512)
        im.filepath_raw = f"{outd}/{name}_{('a' if 'albedo' in n.image.name else 'e')}_512.png"; im.file_format = 'PNG'; im.save(); im.colorspace_settings.name = 'sRGB'
        n.image = im
tris1 = sum(len(p.vertices) - 2 for p in lod.data.polygons)
# keep modifiers list: the copy still has the Armature modifier
export(f"{outd}/{name}_lod1.glb", [lod, arm])
for f in os.listdir(outd):
    if f.endswith("_512.png"): os.remove(f"{outd}/{f}")
print("TRIS", tris0, tris1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(os.path.dirname(blend), f"final_{variant}.blend"))
