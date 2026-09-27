"""Clean far LOD for a Meshy building: voxel remesh + decimate + texture bake.

Usage (headless Blender 5.x):
  blender -b --python tools/meshy/bake_lod.py -- <src_lod0.glb> <out.glb> <triangles> <texture_px> [voxels_across=160]

Plain collapse decimation shreds Meshy meshes (loose shingle/thatch islands, thin
awnings): holes, spikes and scrambled normals that read as shiny metal in game
(inn/healer LOD1 before 2026-09-27). This instead builds a closed shell at a
voxel size of (largest side / voxels_across), decimates that (collapse behaves on
a closed manifold), gives it fresh UVs and bakes the LOD0 colours onto it, so
the silhouette and colours hold at any triangle budget. Metallic 0, rough 0.9.
Check with tools/meshy/compare_lods.py.
"""
import bpy, sys, os, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
src, out, target, tex = args[0], args[1], int(args[2]), int(args[3])
across = float(args[4]) if len(args) > 4 else 160.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.context.view_layer.objects.active = meshes[0]
for o in bpy.data.objects:
    o.select_set(o in meshes)
if len(meshes) > 1:
    bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


# Low shell: copy, voxel remesh, decimate.
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "lod"
bpy.context.scene.collection.objects.link(lo)
dims = hi.dimensions
voxel = max(dims) / across
for m in list(lo.data.materials):
    pass
lo.data.materials.clear()
rm = lo.modifiers.new("vox", 'REMESH')
rm.mode = 'VOXEL'; rm.voxel_size = voxel; rm.use_smooth_shade = False
bpy.context.view_layer.objects.active = lo
for o in bpy.data.objects:
    o.select_set(o == lo)
bpy.ops.object.modifier_apply(modifier="vox")
shell = tris(lo)
for attempt in range(6):
    if tris(lo) <= target * 1.03:
        break
    d = lo.modifiers.new("dec", 'DECIMATE')
    d.ratio = max(0.01, target / tris(lo))
    d.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
bpy.ops.object.shade_flat()

# UVs + bake target.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.004, area_weight=0.0)
bpy.ops.object.mode_set(mode='OBJECT')
img = bpy.data.images.new("lod_bake", tex, tex)
mat = bpy.data.materials.new("lod_baked"); mat.use_nodes = True
nt = mat.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Metallic"].default_value = 0.0
bsdf.inputs["Roughness"].default_value = 0.9
tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img
nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
nt.nodes.active = tn
lo.data.materials.append(mat)

sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 4
try:
    sc.cycles.device = 'GPU'
except Exception:
    pass
bk = sc.render.bake
bk.use_pass_direct = False; bk.use_pass_indirect = False; bk.use_pass_color = True
bk.use_selected_to_active = True
bk.cage_extrusion = voxel * 2.0
bk.max_ray_distance = voxel * 6.0
bk.margin = 4
for o in bpy.data.objects:
    o.select_set(o in (hi, lo))
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})

# Export the low shell alone, texture as JPEG.
img.filepath_raw = out.replace(".glb", "_bake.png"); img.file_format = 'PNG'
for o in bpy.data.objects:
    o.select_set(o == lo)
bpy.ops.export_scene.gltf(filepath=out, use_selection=True, export_format='GLB',
                          export_image_format='JPEG', export_jpeg_quality=88)
print("BAKED", os.path.basename(out), "src", tris(hi), "shell", shell, "->", tris(lo), f"{tex}px voxel {voxel:.3f}", os.path.getsize(out) // 1024, "KB")
