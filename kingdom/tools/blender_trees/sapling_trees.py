"""Realistic broadleaf trees with the installed Sapling Tree Gen extension (best tool first, owner 2026-10-28).
  set TREE_ONLY=oak_0 & blender -b -P kingdom/tools/blender_trees/sapling_trees.py -- <out_dir>
Per tree: a Sapling preset (quaking_aspen / small_maple / white_birch) tuned toward Lake District oak / beech / ash (crown shape,
height, leaf density), trunk curves converted to mesh with the Poly Haven CC0 bark_brown_02, Sapling's leaf quads re-UV'd onto the
generated leaf-cluster atlas (alpha cut, double-sided), LOD1/LOD2 by Decimate (and fewer, larger cards), exported as glTF with
shared textures/ and LOD0/LOD1/LOD2 children like make_trees.py, so RealSlice / RealInstancer pick them up unchanged.
"""
import ast, bpy, math, os, random, sys
OUT = sys.argv[sys.argv.index("--") + 1]
PRESETS = os.path.expandvars(r"%APPDATA%\Blender Foundation\Blender\5.2\extensions\user_default\sapling_tree_gen\presets")
BARK = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "cc0", "textures", "bark_brown_02"))
ATLAS = os.path.join(OUT, "leaf_atlas.png")       # written by make_trees.py (kept)

# name -> (preset, overrides)
TREES = {
    "oak":   ("small_maple.py",   dict(scale=12.0, scaleV=2.0, leaves=55, leafScale=0.42, leafScaleX=1.0, baseSize=0.22, shape="1", levels=3)),
    "beech": ("quaking_aspen.py", dict(scale=15.0, scaleV=2.0, leaves=45, leafScale=0.4, leafScaleX=1.0, baseSize=0.25, shape="2", levels=3)),
    # conifers (real-world instancer: spruce_a/b, pine_scots); needles use the same atlas, darker blue-green
    "pine":   ("douglas_fir.py", dict(scale=14.0, scaleV=2.0, leafScale=0.34, leaves=70, levels=3)),   # small_pine came out bare
    "spruce": ("douglas_fir.py", dict(scale=17.0, scaleV=2.5, leafScale=0.32, leaves=80, levels=3)),
    "ash":   ("white_birch.py",   dict(scale=16.0, scaleV=2.5, leaves=40, leafScale=0.38, leafScaleX=1.0, baseSize=0.35, levels=3)),
}


def load_preset(fn):
    src = open(os.path.join(PRESETS, fn), encoding="utf-8").read()
    body = src[src.index("{"):]
    return ast.literal_eval(body)


def mat_bark():
    m = bpy.data.materials.new("bark")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(BARK, "bark_brown_02_diff_2k.jpg"))
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
    n = nt.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(os.path.join(BARK, "bark_brown_02_nor_gl_2k.jpg"))
    n.image.colorspace_settings.name = "Non-Color"
    nm = nt.nodes.new("ShaderNodeNormalMap"); nt.links.new(n.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.9
    return m


def mat_leaf():
    m = bpy.data.materials.new("leaves")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = bpy.data.images.load(ATLAS)
    nt.links.new(t.outputs["Color"], b.inputs["Base Color"]); nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
    m.use_backface_culling = False
    try:
        m.surface_render_method = "DITHERED"
    except Exception:
        pass
    return m


def mat_needles():
    m = mat_leaf()
    m.name = "needles"
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    t = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
    mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"; mix.inputs["Factor"].default_value = 1.0
    mix.inputs[7].default_value = (0.5, 0.62, 0.52, 1.0)
    nt.links.new(t.outputs["Color"], mix.inputs[6]); nt.links.new(mix.outputs[2], b.inputs["Base Color"])
    return m


def remap_leaf_uvs(me, rng):
    """Sapling gives each leaf face a full 0..1 UV; put every face on a random 2x2 atlas cell (leaf clusters)."""
    # one UV layer named like the trunk's, or the join drops the leaf UVs (all leaves sampled atlas pixel 0,0 = transparent)
    while len(me.uv_layers) > 1:
        me.uv_layers.remove(me.uv_layers[-1])
    uv = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    uv.name = "UVMap"
    for poly in me.polygons:
        cell = rng.randrange(4)
        u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
        corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for k, li in enumerate(poly.loop_indices):
            cu, cv = corners[k % 4]
            uv.data[li].uv = (u0 + cu * 0.5, v0 + cv * 0.5)


def build(name, preset, over, seed):
    rng = random.Random(seed)
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o)
    p = load_preset(preset)
    p.update(over)
    p.update(dict(seed=seed, showLeaves=True, useArm=False, leafShape="rect", bevel=True, makeMesh=False))
    p = {k: v for k, v in p.items() if k not in ("do_update", "limitImport", "chooseSet", "presetName", "overwrite", "prevent_cycle", "leafDupliObj")}
    try:
        bpy.ops.curve.tree_add(**p)
    except TypeError as e:
        bad = str(e).split('"')[1] if '"' in str(e) else None
        print("PARAM", e)
        p.pop(bad, None)
        bpy.ops.curve.tree_add(**p)
    trunk = next(o for o in bpy.context.scene.objects if o.type == "CURVE")
    leaves = next((o for o in bpy.context.scene.objects if o.type == "MESH"), None)
    print("OBJS", [(o.name, o.type, len(o.data.polygons) if o.type == "MESH" else 0) for o in bpy.context.scene.objects])
    if leaves:
        print("LEAFAREA", sum(p.area for p in leaves.data.polygons) / max(1, len(leaves.data.polygons)), "dims", tuple(round(x, 1) for x in leaves.dimensions), "trunk dims", tuple(round(x, 1) for x in trunk.dimensions))
    bpy.ops.object.select_all(action="DESELECT")
    trunk.select_set(True); bpy.context.view_layer.objects.active = trunk
    bpy.ops.object.convert(target="MESH")
    trunk = bpy.context.view_layer.objects.active
    trunk.data.materials.clear(); trunk.data.materials.append(BARK_M)
    bpy.ops.object.shade_smooth()
    # bark UVs: a cylindrical-ish projection is enough at gameplay distance
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cylinder_project(scale_to_bounds=False); bpy.ops.object.mode_set(mode="OBJECT")
    if leaves:
        leaves.parent = None
        remap_leaf_uvs(leaves.data, rng)
        leaves.data.materials.clear(); leaves.data.materials.append(NEEDLE_M if name.startswith(("pine", "spruce")) else LEAF_M)
    lods = []
    for li, (dec, keep) in enumerate([(0.045, 0.45), (0.015, 0.2), (0.005, 0.06)]):   # budget: ~25k / 6k / 1.5k tris
        parts = []
        for src in ([trunk, leaves] if leaves else [trunk]):
            o = src.copy(); o.data = src.data.copy(); bpy.context.scene.collection.objects.link(o)
            if src is trunk:
                md = o.modifiers.new("dec", "DECIMATE"); md.ratio = dec
            if src is leaves:
                import bmesh
                bm = bmesh.new(); bm.from_mesh(o.data)
                drop = [f for f in bm.faces if rng.random() > keep]
                bmesh.ops.delete(bm, geom=drop, context="FACES")
                grow = 1.0 / math.sqrt(keep)          # fewer, larger cards keep the crown's coverage
                for f in bm.faces:
                    c = f.calc_center_median()
                    for v in f.verts:
                        v.co = c + (v.co - c) * grow
                bm.to_mesh(o.data); bm.free()
            parts.append(o)
        bpy.ops.object.select_all(action="DESELECT")
        for o in parts:
            o.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        for o in parts:
            for m in o.modifiers:
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.modifier_apply(modifier=m.name)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        j.name = "LOD%d" % li
        lods.append(j)
    for o in (trunk, leaves):
        if o:
            bpy.data.objects.remove(o)
    root = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(root)
    for o in lods:
        o.parent = root
    path = os.path.join(OUT, name + ".gltf")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures", use_selection=False, export_apply=True)
    tris = sum(len(p.vertices) - 2 for p in lods[0].data.polygons)
    print("TREE", path, "lod0 tris", tris)


bpy.ops.wm.read_factory_settings(use_empty=True)
import addon_utils
addon_utils.enable("bl_ext.user_default.sapling_tree_gen", default_set=True)
BARK_M, LEAF_M = mat_bark(), mat_leaf()
NEEDLE_M = mat_needles()
only = os.environ.get("TREE_ONLY", "")
for sp, (preset, over) in TREES.items():
    for n in range(2):
        nm = f"{sp}_{n}"
        if only and only != nm:
            continue
        build(nm, preset, over, 11 + n * 7 + len(sp))
