"""Mobile LOD0 (+LOD1) for one raw Meshy GLB: rescale, ground at bottom-centre, voxel remesh,
decimate, single baked texture, metallic 0 / rough 0.9. Successor of bake_lod.py for the
meshy_free batch (adds scale/origin, smooth option, LOD1 via decimating LOD0 with a half-res texture).

Usage (headless Blender 5.x):
  blender -b --python tools/meshy/optimize_free.py -- <src.glb> <out_prefix> <tris> <tex_px> <mode:h|w> <meters> [across=170] [smooth=0] [lod1_ratio=0] [variant=vox|solid|dec]

  mode h: scale so height (Z after import, Y-up in glTF) == meters;  w: longest side == meters.
  out: <out_prefix>_lod0.glb and (when lod1_ratio>0) <out_prefix>_lod1.glb
"""
import bpy, sys, os, math, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
src, prefix, target, tex, mode, meters = args[0], args[1], int(args[2]), int(args[3]), args[4], float(args[5])
across = float(args[6]) if len(args) > 6 else 170.0
smooth = int(args[7]) if len(args) > 7 else 0
lod1_ratio = float(args[8]) if len(args) > 8 else 0.0
variant = args[9] if len(args) > 9 else 'vox'   # vox | solid (solidify thin sheets first) | dec (no remesh, collapse only)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.context.view_layer.objects.active = meshes[0]
for o in bpy.data.objects:
    o.select_set(o in meshes)
if len(meshes) > 1:
    bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
hi.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def tris(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)


def bounds(o):
    pts = [mathutils.Vector(c) for c in o.bound_box]
    return (mathutils.Vector([min(p[i] for p in pts) for i in range(3)]),
            mathutils.Vector([max(p[i] for p in pts) for i in range(3)]))


# Scale + ground: bottom-centre origin.
mn, mx = bounds(hi)
size = mx - mn
ref = size.z if mode == 'h' else max(size)
s = meters / ref
hi.scale = (s, s, s)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
mn, mx = bounds(hi)
hi.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
src_tris = tris(hi)

# Diffuse-colour bake turns metallic / transmissive surfaces black: flatten them to plain base colour first.
for m in hi.data.materials:
    if not m or not m.use_nodes:
        continue
    for n in m.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            for name, val in (("Metallic", 0.0), ("Transmission Weight", 0.0), ("Alpha", 1.0)):
                sock = n.inputs.get(name)
                if sock is not None:
                    for l in list(sock.links):
                        m.node_tree.links.remove(l)
                    sock.default_value = val

lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "lod"
bpy.context.scene.collection.objects.link(lo)
voxel = max(hi.dimensions) / across
lo.data.materials.clear()
bpy.context.view_layer.objects.active = lo
for o in bpy.data.objects:
    o.select_set(o == lo)
if variant == 'solid':
    sm = lo.modifiers.new("sol", 'SOLIDIFY')
    sm.thickness = voxel * 1.6; sm.offset = 0.0; sm.use_even_offset = True
    bpy.ops.object.modifier_apply(modifier="sol")
    # solidify can throw spikes at degenerate faces: drop vertices outside the source bounding box.
    import bmesh
    lo_mn, lo_mx = bounds(hi)
    pad = voxel * 3.0
    bm = bmesh.new(); bm.from_mesh(lo.data)
    bad = [v for v in bm.verts if any(v.co[i] < lo_mn[i] - pad or v.co[i] > lo_mx[i] + pad for i in range(3))]
    bmesh.ops.delete(bm, geom=bad, context='VERTS')
    bm.to_mesh(lo.data); bm.free()
if variant != 'dec':
    rm = lo.modifiers.new("vox", 'REMESH')
    rm.mode = 'VOXEL'; rm.voxel_size = voxel; rm.use_smooth_shade = False
    bpy.ops.object.modifier_apply(modifier="vox")
shell = tris(lo)
for attempt in range(6):
    if tris(lo) <= target * 1.03:
        break
    d = lo.modifiers.new("dec", 'DECIMATE')
    d.ratio = max(0.01, target / tris(lo))
    d.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")


def shade(o):
    bpy.context.view_layer.objects.active = o
    for x in bpy.data.objects:
        x.select_set(x == o)
    if smooth:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(45))
    else:
        bpy.ops.object.shade_flat()


shade(lo)
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
bk.cage_extrusion = voxel * (0.6 if variant == 'dec' else 2.0)
bk.max_ray_distance = voxel * (2.0 if variant == 'dec' else 6.0)
bk.margin = 6
for o in bpy.data.objects:
    o.select_set(o in (hi, lo))
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'})
img.pack()


def export(o, path):
    for x in bpy.data.objects:
        x.select_set(x == o)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
                              export_image_format='JPEG', export_jpeg_quality=85)
    print("BAKED", os.path.basename(path), "src", src_tris, "shell", shell, "->", tris(o), f"{tex}px", os.path.getsize(path) // 1024, "KB")


os.makedirs(os.path.dirname(prefix), exist_ok=True)
lo.name = os.path.basename(prefix) + "_lod0"
export(lo, prefix + "_lod0.glb")
if lod1_ratio > 0:
    l1 = lo.copy(); l1.data = lo.data.copy(); l1.name = os.path.basename(prefix) + "_lod1"
    bpy.context.scene.collection.objects.link(l1)
    bpy.context.view_layer.objects.active = l1
    for x in bpy.data.objects:
        x.select_set(x == l1)
    d = l1.modifiers.new("dec", 'DECIMATE'); d.ratio = lod1_ratio; d.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
    shade(l1)
    img1 = img.copy(); img1.scale(max(128, tex // 2), max(128, tex // 2)); img1.pack()
    m1 = mat.copy(); m1.node_tree.nodes[[n.name for n in m1.node_tree.nodes if n.type == 'TEX_IMAGE'][0]].image = img1
    l1.data.materials.clear(); l1.data.materials.append(m1)
    export(l1, prefix + "_lod1.glb")
