# Benchmark slice: import the gated Meshy props (coordinator batch 2026-10-28) for Ashford.
# blender -b --factory-startup -P import_meshy_props.py -- <src_dir> <out_dir>
# Per prop: join, uniform scale to the README size (largest horizontal side), origin at the feet (centre of the base),
# textures downsized (1K props, 2K for stall / well), colour fixes from the coordinator's gate, LOD1 = 35 % decimate.
import bpy, sys, os, colorsys
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
PROPS = {   # name: (largest horizontal size m, texture px)
    "cart": (2.2, 1024), "well": (1.8, 2048), "crate_stack": (1.4, 1024),
    "trestle_table": (2.0, 1024), "hearth": (1.8, 1024), "market_stall": (2.5, 2048),
}


def hsv_arrays(px):
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    mx = np.max(px[..., :3], axis=-1)
    mn = np.min(px[..., :3], axis=-1)
    d = mx - mn + 1e-6
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6.0
    s = np.where(mx > 0, d / (mx + 1e-6), 0)
    return h, s, mx


def fix_colours(name, img):
    w, hgt = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(hgt, w, 4)
    h, s, v = hsv_arrays(px)
    rgb = px[..., :3]
    lum = (rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[..., None]
    if name == "hearth":
        copper = (h > 0.0) & (h < 0.11) & (s > 0.45) & (v > 0.2)            # copper cauldron -> black iron
        rgb[copper] = (lum[copper] * 0.35 + 0.03) * np.array([1.0, 1.0, 1.05], dtype=np.float32)
        hood = (h > 0.03) & (h < 0.13) & (s > 0.18) & (s <= 0.45) & (v > 0.3)   # brown hood -> grey-white plaster
        rgb[hood] = rgb[hood] * 0.25 + (lum[hood] * 0.45 + 0.38) * np.array([0.98, 0.96, 0.92], dtype=np.float32) * 0.75
    if name == "market_stall":
        och = (h > 0.06) & (h < 0.17) & (s > 0.35)                         # ochre canopy: -35 % saturation, a little darker
        rgb[och] = (lum[och] + (rgb[och] - lum[och]) * 0.65) * 0.92
    px[..., :3] = np.clip(rgb, 0, 1)
    img.pixels[:] = px.ravel()


for name, (size, tex) in PROPS.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    for o in list(bpy.context.scene.objects):          # drop empties left by the importer (keep the mesh's world transform)
        if o != ob and o.type != "MESH":
            pass
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vs = [v.co for v in ob.data.vertices]
    mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    k = size / max(mx.x - mn.x, mx.y - mn.y)
    centre = Vector(((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mn.z))
    for v in ob.data.vertices:
        v.co = (v.co - centre) * k
    for img in bpy.data.images:
        if img.size[0] > tex:
            img.scale(tex, tex)
        if "base" in img.name.lower() or "color" in img.name.lower() or img.name.lower().endswith("_0"):
            if name in ("hearth", "market_stall"):
                fix_colours(name, img)
        img.pack()
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), use_selection=False, export_format="GLB",
                              export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
    tris0 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("lod", "DECIMATE")
    dec.ratio = 0.35
    bpy.ops.object.modifier_apply(modifier="lod")
    tris1 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + "_lod1.glb"), use_selection=False, export_format="GLB",
                              export_yup=True, export_image_format="JPEG", export_jpeg_quality=80)
    print("PROP", name, "scale", round(k, 3), "size", [round((mx[i] - mn[i]) * k, 2) for i in range(3)], "tris", tris0, tris1)
print("PROPS_DONE")
