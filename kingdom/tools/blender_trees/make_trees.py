"""Procedural broadleaf trees for the benchmark slice (owner: no lollipop trees). Blender 5.2, run headless:
  blender -b -P kingdom/tools/blender_trees/make_trees.py -- <out_dir>
Per species (oak, ash, beech) and 2 seeds: a recursive branch skeleton (trunk + 3 orders, gravitropism, taper) skinned as
tapered tube meshes with the Poly Haven CC0 bark_brown_02 material, leaf cards (crossed quads, 1-1.6 m) clustered on the outer
twigs with a generated alpha leaf-cluster atlas (leaf_atlas.png, written by this script with numpy), plus LOD1 (half cards, coarse
tubes) and LOD2 (a few big crown cards). Exports <species>_<n>.glb with LOD0/LOD1/LOD2 children (Terrain3D / MultiMesh ready).
"""
import bpy, bmesh, math, os, random, sys
import numpy as np
from mathutils import Vector, Matrix, Quaternion

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "."
os.makedirs(OUT, exist_ok=True)
BARK = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "cc0", "textures", "bark_brown_02"))

SPECIES = {
    # height, trunk radius, crown start (share of height), branch angle (deg), spread, orders, leaf colour (rgb 0-1), leaves per twig
    "oak":   dict(h=14.0, r=0.45, crown=0.16, ang=62, spread=0.85, kids=(9, 4, 3), leaf=(0.30, 0.38, 0.16), cards=9, gravi=-0.05),
    "ash":   dict(h=17.0, r=0.36, crown=0.28, ang=40, spread=0.55, kids=(8, 4, 3), leaf=(0.34, 0.42, 0.17), cards=7, gravi=0.15),
    "beech": dict(h=16.0, r=0.40, crown=0.2, ang=50, spread=0.70, kids=(9, 4, 3), leaf=(0.28, 0.40, 0.15), cards=9, gravi=0.08),
}


def leaf_atlas(path, rng):
    """1024^2 RGBA: 2x2 cells of leaf clusters (ellipse leaves with a darker centre line), olive greens, alpha cut."""
    n = 1024
    img = np.zeros((n, n, 4), np.float32)
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    for cell in range(4):
        cx0, cy0 = (cell % 2) * 512, (cell // 2) * 512
        for _ in range(140):
            cx = cx0 + 256 + rng.gauss(0, 120)
            cy = cy0 + 256 + rng.gauss(0, 120)
            if not (cx0 + 30 < cx < cx0 + 482 and cy0 + 30 < cy < cy0 + 482):
                continue
            a = rng.uniform(0, math.pi)
            L, W = rng.uniform(26, 46), rng.uniform(11, 19)
            x0, x1, y0, y1 = int(cx - 50), int(cx + 50), int(cy - 50), int(cy + 50)
            sx, sy = xx[y0:y1, x0:x1] - cx, yy[y0:y1, x0:x1] - cy
            u = sx * math.cos(a) + sy * math.sin(a)
            v = -sx * math.sin(a) + sy * math.cos(a)
            m = (u / L) ** 2 + (v / W) ** 2 < 1.0
            shade = rng.uniform(0.75, 1.15)
            base = np.array([0.40, 0.50, 0.21]) * shade   # a touch lighter: crowns read near-black at distance in Godot + rng.uniform(-0.03, 0.03)
            vein = np.abs(v) < 1.2
            col = np.where(vein[..., None], base * 0.75, base * (0.9 + 0.2 * (u[..., None] / L)))
            sub = img[y0:y1, x0:x1]
            sub[m, :3] = col[m]
            sub[m, 3] = 1.0
    img = np.clip(img, 0, 1)
    im = bpy.data.images.new("leaf_atlas", n, n, alpha=True)
    im.pixels.foreach_set(np.flipud(img).ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    return im


def bark_material():
    m = bpy.data.materials.new("bark")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(BARK, "bark_brown_02_diff_2k.jpg"))
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeTexImage")
    nrm.image = bpy.data.images.load(os.path.join(BARK, "bark_brown_02_nor_gl_2k.jpg"))
    nrm.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


def leaf_material(atlas):
    m = bpy.data.materials.new("leaves")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = atlas
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = 0.7
    m.use_backface_culling = False   # double-sided leaf cards (glTF doubleSided)
    m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    return m


def grow(sp, rng):
    """Branch list: (start Vector, end Vector, r0, r1, order). Twig tips collected for leaves."""
    branches, tips = [], []
    def rec(p, d, length, r, order):
        steps = 4 if order < 2 else 3
        pts = [p]
        dd = d.copy()
        for s in range(steps):
            j = 0.05 if order == 0 else 0.18
            dd = (dd + Vector((rng.gauss(0, j), rng.gauss(0, j), sp["gravi"] if order else 0.05))).normalized()
            pts.append(pts[-1] + dd * (length / steps))
        for s in range(steps):
            t0, t1 = s / steps, (s + 1) / steps
            branches.append((pts[s], pts[s + 1], r * (1 - 0.7 * t0), r * (1 - 0.7 * t1), order))
        if order >= 2:
            tips.append((pts[-1], dd))
            tips.append((pts[len(pts) // 2], dd))
        if order >= 3:
            return
        kids = sp["kids"][order]
        for k in range(kids):
            t = (sp["crown"] if order == 0 else 0.25) + (1 - (sp["crown"] if order == 0 else 0.25)) * (k + rng.random()) / kids
            idx = min(int(t * steps), steps - 1)
            q = pts[idx].lerp(pts[idx + 1], t * steps - idx)
            az = 2 * math.pi * (k / kids) + rng.uniform(-0.6, 0.6) + order * 1.1
            ang = math.radians(sp["ang"] + rng.uniform(-12, 12))
            side = Vector((math.cos(az), math.sin(az), 0))
            nd = (dd * math.cos(ang) + side * math.sin(ang) * (0.6 + 0.6 * sp["spread"])).normalized()
            nl = length * (0.55 if order == 0 else 0.6) * (1.15 - 0.5 * t) * rng.uniform(0.85, 1.15)
            rec(q, nd, nl, r * (1 - 0.7 * t) * 0.55, order + 1)
    rec(Vector((0, 0, 0)), Vector((0, 0, 1)), sp["h"] * 0.75, sp["r"], 0)
    return branches, tips


def tube_mesh(name, branches, sides, min_order_r=0.0):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    for a, b, r0, r1, order in branches:
        if r0 < min_order_r:
            continue
        axis = (b - a)
        L = axis.length
        if L < 1e-4:
            continue
        q = Vector((0, 0, 1)).rotation_difference(axis.normalized())
        ring0, ring1 = [], []
        for i in range(sides):
            ang = 2 * math.pi * i / sides
            off = q @ Vector((math.cos(ang), math.sin(ang), 0))
            ring0.append(bm.verts.new(a + off * r0))
            ring1.append(bm.verts.new(b + off * r1))
        for i in range(sides):
            j = (i + 1) % sides
            f = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
            for loop, uv in zip(f.loops, [(i / sides, 0), ((i + 1) / sides, 0), ((i + 1) / sides, L / 2), (i / sides, L / 2)]):
                loop[uv_layer].uv = uv
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def card_mesh(name, tips, rng, per_tip, size):
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    for p, d in tips:
        for c in range(per_tip):
            cell = rng.randrange(4)
            u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
            s = size * rng.uniform(0.8, 1.25)
            centre = p + Vector((rng.gauss(0, 0.6), rng.gauss(0, 0.6), rng.gauss(0, 0.4)))
            rot = Quaternion(Vector((0, 0, 1)), rng.uniform(0, 2 * math.pi)) @ Quaternion(Vector((1, 0, 0)), rng.uniform(-0.6, 0.6))
            for cross in range(2):
                r2 = rot @ Quaternion(Vector((0, 0, 1)), cross * math.pi / 2)
                corners = [r2 @ Vector((x * s / 2, 0, z * s / 2)) + centre for x, z in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                vs = [bm.verts.new(c) for c in corners]
                f = bm.faces.new(vs)
                for loop, uv in zip(f.loops, [(u0, v0), (u0 + 0.5, v0), (u0 + 0.5, v0 + 0.5), (u0, v0 + 0.5)]):
                    loop[uv_layer].uv = uv
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return me


def obj(name, meshes_mats):
    """One object with several material slots (merged meshes)."""
    objs = []
    for me, mat in meshes_mats:
        o = bpy.data.objects.new(name + "_" + mat.name, me)
        o.data.materials.append(mat)
        bpy.context.scene.collection.objects.link(o)
        objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def main():
    rng = random.Random(1066)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    atlas = leaf_atlas(os.path.join(OUT, "leaf_atlas.png"), rng)
    bark, leaves = bark_material(), leaf_material(atlas)
    for sp_name, sp in SPECIES.items():
        for n in range(2):
            for o in list(bpy.context.scene.objects):
                bpy.data.objects.remove(o)
            branches, tips = grow(sp, rng)
            lod0 = obj("LOD0", [(tube_mesh("b0", branches, 8), bark), (card_mesh("l0", tips, rng, sp["cards"], 1.5), leaves)])
            lod1 = obj("LOD1", [(tube_mesh("b1", branches, 5, 0.03), bark), (card_mesh("l1", tips[::2], rng, sp["cards"], 2.2), leaves)])
            # LOD2: trunk + a handful of big crown cards
            big = [(t[0], t[1]) for t in tips[::max(1, len(tips) // 14)]]
            lod2 = obj("LOD2", [(tube_mesh("b2", [b for b in branches if b[4] == 0], 4), bark), (card_mesh("l2", big, rng, 2, 5.5), leaves)])
            root = bpy.data.objects.new(f"{sp_name}_{n}", None)
            bpy.context.scene.collection.objects.link(root)
            for o in (lod0, lod1, lod2):
                o.parent = root
            path = os.path.join(OUT, f"{sp_name}_{n}.glb")
            # shared textures/ (one bark + one atlas for all trees; a .glb per tree embedded 6 MB each)
            path = path[:-4] + ".gltf"
            bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures", use_selection=False, export_apply=True)
            tri = sum(len(p.vertices) - 2 for p in lod0.data.polygons)
            print("TREE", path, "tips", len(tips), "lod0 tris", tri)


main()
