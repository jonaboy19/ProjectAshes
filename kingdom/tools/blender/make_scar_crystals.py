"""Region 1 L4: scar-crystal clusters built from CC0 meshy_free crystals.

    blender -b --python make_scar_crystals.py

Each cluster = one source crystal (meshy_free/magic/*_lod0.glb) with its pedestal cropped away,
decimated, then instanced 5x with different scales and outward tilts and joined into ONE mesh with ONE
emissive material (the source texture doubles as the emission map, so the crystal glows in its own colours).
Ground level is the crop plane: the bases sink into the earth.

-> kingdom/assets/incoming/region1/rift/crystals/scar_crystal_{a,b,c}_lod{0,1}.glb
Budget (prop): LOD0 <= 4k tris / 512 px, LOD1 <= 1.2k / 256 px.
"""
import bpy, bmesh, os, sys, math, random
import numpy as np
from mathutils import Vector, Euler
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r1_common as C

OUT = os.path.join(C.R1, "rift", "crystals")
SRC = os.path.join(C.MESHY_FREE, "magic")

# name, source, crop z (m), per-instance target tris, tint (h shift, sat add) or None, layout seed
VARIANTS = [
    ("scar_crystal_a", "crystal_purple_pedestal_lod0.glb", 0.74, 700, None, 11),
    ("scar_crystal_b", "crystal_cyan_pedestal_lod0.glb", 0.52, 700, None, 23),
    ("scar_crystal_c", "crystal_ice_shard_lod0.glb", 0.32, 700, (0.74, 0.22), 37),
]
# (dx, dy, scale, tilt deg, yaw deg): one tall central crystal, satellites around it
LAYOUT = [(0.0, 0.0, 1.25, 4, 20), (0.42, 0.10, 0.85, 24, 15), (-0.36, 0.22, 0.95, 20, 200),
          (0.05, -0.44, 0.7, 30, 100), (-0.18, -0.30, 0.55, 34, 300)]


def crop_below(obj, zcut):
    bm = bmesh.new(); bm.from_mesh(obj.data)
    kill = [f for f in bm.faces if all(v.co.z < zcut for v in f.verts)]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # drop loose bits below the plane
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    for v in bm.verts:                       # cap: clamp the remaining low verts to the plane -> flat cut
        if v.co.z < zcut:
            v.co.z = zcut
    bm.to_mesh(obj.data); bm.free()


def build(name, src, zcut, tris, tint, seed, lod):
    C.reset()
    random.seed(seed)
    base = C.import_glb(os.path.join(SRC, src))[0]
    crop_below(base, zcut)
    # shift so the crop plane sits at z = 0 (bury 4 cm)
    for v in base.data.vertices:
        v.co.z -= zcut + 0.12
    C.decimate_to(base, tris if lod == 0 else int(tris * 0.3))
    img = C.tex_images(base)[0]
    if tint:
        a, (H, S, V) = C.get_hsv(img)
        H2 = np.full_like(H, tint[0]); S2 = np.clip(S + tint[1], 0, 1)
        C.set_rgb(img, a, C.hsv2rgb(H2, S2, np.clip(V * 1.05, 0, 1)))
    C.shrink_textures(base, 512 if lod == 0 else 256)
    # single emissive material: texture drives base colour AND emission (subtle, not a lamp)
    mat = base.data.materials[0]
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = [n for n in nt.nodes if n.type == 'TEX_IMAGE'][0]
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 0.55
    mat.name = "RiftCrystal"
    insts = []
    for i, (dx, dy, sc, tilt, yaw) in enumerate(LAYOUT):
        o = base if i == 0 else base.copy()
        if i:
            o.data = base.data.copy() if False else base.data
            bpy.context.scene.collection.objects.link(o)
        jitter = random.uniform(-6, 6)
        o.scale = (sc, sc, sc)
        o.location = (dx, dy, 0.0)
        # tilt away from the centre
        ang = math.atan2(dy, dx) if (dx or dy) else 0.0
        o.rotation_euler = Euler((math.radians(tilt) * math.sin(ang) * -1 if (dx or dy) else math.radians(tilt),
                                  math.radians(tilt) * math.cos(ang) if (dx or dy) else 0, math.radians(yaw + jitter)), 'ZYX')
        insts.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in insts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = insts[0]
    bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.scale = (1.5, 1.5, 1.5)           # scar crystals are 1.5-2 m tall
    C.apply_transforms(obj)
    # keep every crystal above the crop: nothing below z=-0.05 (tilting can dip a base)
    n = C.tri_count([obj])
    if lod == 1:
        C.decimate_to(obj, 1100)
        n = C.tri_count([obj])
    C.export(os.path.join(OUT, f"{name}_lod{lod}.glb"), [obj])
    bb = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    size = tuple(round(max(p[i] for p in bb) - min(p[i] for p in bb), 2) for i in range(3))
    print("CRYSTAL", name, lod, "tris", n, "size", size)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for (name, src, zcut, tris, tint, seed) in VARIANTS:
        for lod in (0, 1):
            build(name, src, zcut, tris, tint, seed, lod)
