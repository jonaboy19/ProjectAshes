"""Market goods kit: ~50 small props from the CC0 Quaternius Fantasy Props MegaKit
and Ultimate Food pack, re-authored for the game:

  * every piece shares ONE 1024 px atlas (market_goods_atlas.png): the four Quaternius trim
    sheets, tinted to the warm painted palette and tiled 3x3 so the pieces' out-of-range UVs
    (trim repeats) still sample the right texture, plus a white swatch for the flat-colour
    food pieces (their colour lives in COLOR_0),
  * per-vertex colour is baked in COLOR_0 (linear); the game material multiplies it with the atlas,
  * scaled to chunky, readable real-world sizes; origin at the bottom centre ('base') or the
    hanging point at the top centre ('top'); heavy pieces are decimated (<= ~1200 tris),
  * exported as ONE glb (no materials) with one named mesh per piece:
    kingdom/assets/market_goods/market_goods.glb  + market_goods_atlas.png + pieces.json.

Sources are copied (selected files only) into kingdom/assets/market_goods/source/ (gdignored)
with the CC0 licence texts by copy_sources() below.

Run: /tmp/claude-0/bpyenv/bin/python make_market_goods.py [--preview]     (bpy, Blender 5.x)
"""
import bpy, bmesh, os, sys, json, math, shutil
from mathutils import Vector, Matrix
from PIL import Image, ImageEnhance

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
KING = os.path.join(ROOT, "kingdom")
Q = os.path.join(KING, "assets", "incoming", "quaternius")
FP = os.path.join(Q, "fantasy-props-megakit")
FOOD = os.path.join(Q, "ultimate-food")
OUT = os.path.join(KING, "assets", "market_goods")
SRC = os.path.join(OUT, "source")

# name: (source, target longest side in metres or None to keep native scale x boost, origin, extra)
#   source "fp:<Name>" = fantasy-props glTF, "food:<Name>" = ultimate-food FBX, "gen:<kind>" = generated.
#   NB: Godot's glTF importer turns node names ending in "_wheel", "-col" etc. into special nodes: avoid those suffixes.
#   extra: dict(rx=degrees about X, boost=uniform scale multiplier, tris=decimate target, size=longest side m)
PIECES = {
    # --- produce, crates and barrels
    "crate_apples":   ("fp:FarmCrate_Apple", "base", dict()),
    "crate_carrots":  ("fp:FarmCrate_Carrot", "base", dict()),
    "crate_empty":    ("fp:FarmCrate_Empty", "base", dict()),
    "crate_wood":     ("fp:Crate_Wooden", "base", dict()),
    "barrel_apples":  ("fp:Barrel_Apples", "base", dict()),
    "bucket_wood":    ("fp:Bucket_Wooden_1", "base", dict(boost=1.1)),
    "bucket_metal":   ("fp:Bucket_Metal", "base", dict(boost=1.1)),
    "sack_grain":     ("fp:Bag", "base", dict(boost=0.9)),
    "pouch":          ("fp:Pouch_Large", "base", dict(boost=1.8, tris=140)),
    "cage_small":     ("fp:Cage_Small", "base", dict()),
    "stool":          ("fp:Stool", "base", dict()),
    "bench":          ("fp:Bench", "base", dict(boost=0.75)),
    "rope_coil":      ("fp:Rope_1", "base", dict(boost=1.0)),
    # --- pottery, tableware, bottles
    "vase_big":       ("fp:Vase_2", "base", dict(boost=0.85)),
    "vase_tall":      ("fp:Vase_4", "base", dict(boost=1.1)),
    "pot_iron":       ("fp:Pot_1", "base", dict(boost=0.8)),
    "cauldron":       ("fp:Cauldron", "base", dict(boost=0.65)),
    "mug":            ("fp:Mug", "base", dict(boost=1.6)),
    "chalice":        ("fp:Chalice", "base", dict(boost=1.5)),
    "plate":          ("fp:Table_Plate", "base", dict(boost=1.3)),
    "bottle":         ("fp:Bottle_1", "base", dict(boost=1.25)),
    "potion_a":       ("fp:Potion_1", "base", dict(boost=1.7)),
    "potion_b":       ("fp:Potion_2", "base", dict(boost=1.45)),
    "potion_c":       ("fp:Potion_4", "base", dict(boost=1.5)),
    "bottles_row":    ("fp:SmallBottles_1", "base", dict(boost=1.7)),
    # --- candles, books, scrolls
    "candle_a":       ("fp:Candle_1", "base", dict(boost=2.0)),
    "candle_b":       ("fp:Candle_2", "base", dict(boost=1.8)),
    "candlestick":    ("fp:CandleStick", "base", dict(boost=1.5)),
    "books_small_a":  ("fp:BookGroup_Small_1", "base", dict(boost=1.25)),
    "books_small_b":  ("fp:BookGroup_Small_2", "base", dict(boost=1.25)),
    "book_stack_a":   ("fp:Book_Stack_1", "base", dict(boost=1.4)),
    "book_stack_b":   ("fp:Book_Stack_2", "base", dict(boost=1.4, tris=200)),
    "scroll":         ("fp:Scroll_1", "base", dict(boost=1.5, tris=160)),
    # --- tools and hardware
    "axe":            ("fp:Axe_Bronze", "base", dict(rx=90, boost=0.9)),
    "pickaxe":        ("fp:Pickaxe_Bronze", "base", dict(rx=90, boost=0.8)),
    "shield":         ("fp:Shield_Wooden", "base", dict(rx=90, tris=260, boost=0.9)),
    "torch":          ("fp:Torch_Metal", "top", dict(rx=90, boost=1.0, size=0.5)),
    "lantern_hang":   ("fp:Lantern_Wall", "top", dict(rx=-90, tris=300, size=0.55)),
    "peg_rack":       ("fp:Peg_Rack", "base", dict(rx=90, boost=1.0)),
    # --- food (Ultimate Food, flat colours)
    "bread":          ("food:Bread", "base", dict(size=0.36)),
    "cheese_slices":  ("food:Cheese_Singles", "base", dict(size=0.28)),
    "fish":           ("food:Fish", "base", dict(size=0.46, tris=90)),
    "fish_hang":      ("food:Fish", "top", dict(size=0.44, rx=90, tris=90)),
    "apple_red":      ("food:Apple", "base", dict(size=0.14)),
    "apple_green":    ("food:Apple_Green", "base", dict(size=0.14)),
    "orange":         ("food:Orange", "base", dict(size=0.13)),
    "tomato":         ("food:Tomato", "base", dict(size=0.13)),
    "pumpkin":        ("food:Pumpkin", "base", dict(size=0.36)),
    "cabbage":        ("food:Lettuce_Whole", "base", dict(size=0.3)),
    "sausage_hang":   ("food:Sausage_Cooked", "top", dict(size=0.5, rx=90)),
    "chicken_leg":    ("food:ChickenLeg", "base", dict(size=0.3)),
    "jar":            ("food:Jar_Large", "base", dict(size=0.24)),
    "wine_bottle":    ("food:Bottle1", "base", dict(size=0.4)),
    # --- generated (plain primitives, CC0 by us): cheese wheel and wedge
    "cheese_round":   ("gen:cheese_round", "base", dict()),
    "cheese_wedge":   ("gen:cheese_wedge", "base", dict()),
    "bread_round":    ("gen:bread_round", "base", dict()),
}

ATLAS = 1024
TILE = 160            # one trim sheet, downscaled; the atlas holds it tiled 3x3 (u,v in [-1, 2))
REGION = TILE * 3
TRIMS = {             # material name -> (png, atlas col, atlas row)
    "MI_Trim_Props": ("T_Trim_Props_BaseColor.png", 0, 0),
    "MI_Trim_Furniture": ("T_Trim_Furniture_BaseColor.png", 1, 0),
    "MI_Trim_Cloth": ("T_Trim_Cloth_BaseColor.png", 0, 1),
    "MI_Trim_Metal": ("T_Trim_Metal_BaseColor.png", 1, 1),
}
SWATCH = (REGION * 2 + 8, 8, 32)   # x, y, size of the white swatch (px)
FLAT_PAGE = (0.92, 0.86, 0.70)     # Scroll pages etc. (materials without a trim texture)


def warm(img: Image.Image, sat=1.22, gamma=0.84, tint=(1.05, 1.0, 0.90), lift=1.0):
    """Push a scanned-looking trim toward the warm, saturated painted palette."""
    img = img.convert("RGB")
    img = ImageEnhance.Color(img).enhance(sat)
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y]
            r = 255 * ((r / 255.0) ** gamma) * lift * tint[0]
            g = 255 * ((g / 255.0) ** gamma) * lift * tint[1]
            b = 255 * ((b / 255.0) ** gamma) * lift * tint[2]
            px[x, y] = (min(255, int(r)), min(255, int(g)), min(255, int(b)))
    return img


def build_atlas():
    atlas = Image.new("RGB", (ATLAS, ATLAS), (255, 255, 255))
    tex = os.path.join(FP, "Textures")
    lifts = {"MI_Trim_Props": 1.05, "MI_Trim_Furniture": 1.25, "MI_Trim_Cloth": 1.12, "MI_Trim_Metal": 1.25}
    for name, (fn, c, r) in TRIMS.items():
        im = Image.open(os.path.join(tex, fn)).convert("RGB").resize((TILE, TILE), Image.LANCZOS)
        if name == "MI_Trim_Furniture":     # scanned-looking dark wood: keep it a natural warm brown, not orange
            im = warm(im, sat=1.0, gamma=0.9, tint=(1.03, 0.98, 0.92), lift=lifts[name])
        else:
            im = warm(im, lift=lifts[name])
        if name == "MI_Trim_Metal":       # the source is a pale pink-grey albedo (meant for metallic=1): paint dull iron/brass
            g = im.convert("L")
            gp = g.load()
            out = Image.new("RGB", im.size)
            op = out.load()
            ip = im.load()
            for y in range(im.height):
                for x in range(im.width):
                    l = gp[x, y] / 255.0
                    l = 0.08 + 0.40 * l
                    r0, g0, b0 = ip[x, y]
                    warm_k = max(0.0, (r0 - b0) / 255.0) * 2.0      # brass/bronze hints stay
                    op[x, y] = (min(255, int(255 * l * (0.92 + 0.5 * warm_k))), min(255, int(255 * l * (0.86 + 0.25 * warm_k))), min(255, int(255 * l * (0.80 - 0.15 * warm_k))))
            im = out
        for i in range(3):
            for j in range(3):
                atlas.paste(im, (c * REGION + i * TILE, r * REGION + j * TILE))
    atlas.save(os.path.join(OUT, "market_goods_atlas.png"))
    return atlas


def trim_uv(mat_name, u, v):
    """Blender (u, v) of a trim material -> atlas uv (Blender convention, v up)."""
    if mat_name in TRIMS:
        _, c, r = TRIMS[mat_name]
        x = c * REGION + (u + 1.0) * TILE
        y = r * REGION + (2.0 - v) * TILE
    else:
        x = SWATCH[0] + SWATCH[2] * 0.5
        y = SWATCH[1] + SWATCH[2] * 0.5
    return (x / ATLAS, 1.0 - y / ATLAS)


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_piece(src):
    kind, name = src.split(":")
    if kind == "fp":
        bpy.ops.import_scene.gltf(filepath=os.path.join(FP, "Exports", "glTF", name + ".gltf"))
    elif kind == "food":
        bpy.ops.import_scene.fbx(filepath=os.path.join(FOOD, "FBX", name + ".fbx"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    return meshes


def mat_colour(m):
    if m and m.use_nodes:
        for nd in m.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                return tuple(nd.inputs["Base Color"].default_value)[:3]
    return (0.8, 0.8, 0.8)


def flat_boost(c):
    """The flat food colours are dark (linear values): lift and saturate toward the painted look."""
    r, g, b = c
    l = 0.2126 * r + 0.7152 * g + 0.0722 * b
    s = 1.5
    r, g, b = [max(0.0, l + (x - l) * s) for x in (r, g, b)]
    k = 1.5 if l < 0.25 else (1.25 if l < 0.5 else 1.0)
    return (min(1.0, r * k * 1.04), min(1.0, g * k), min(1.0, b * k * 0.92))


def bake_piece(objs):
    """Join the meshes, remap UVs into the atlas, write COLOR_0 per corner; returns one object."""
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    me = ob.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active
    old = None
    for a in me.color_attributes:
        old = a
        break
    cols = {}
    if old is not None:
        if old.domain == "POINT":
            for i, d in enumerate(old.data):
                cols[("p", i)] = tuple(d.color)[:3]
        else:
            for i, d in enumerate(old.data):
                cols[("c", i)] = tuple(d.color)[:3]
    new_cols = []
    for poly in me.polygons:
        mat = me.materials[poly.material_index] if poly.material_index < len(me.materials) else None
        mname = mat.name.split(".")[0] if mat else ""
        is_food_flat = TRIM_OF.get(mname, mname) not in TRIMS and "Page" not in mname and "Banner" not in mname
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            if is_food_flat:
                c = flat_boost(mat_colour(mat))
                uv = trim_uv("", 0, 0)
            elif "Page" in mname or "Banner" in mname:
                c = FLAT_PAGE
                uv = trim_uv("", 0, 0)
            else:
                base = mname
                if "Vertex" in (mat.name if mat else ""):
                    c0 = cols.get(("c", li)) or cols.get(("p", vi)) or (1.0, 1.0, 1.0)
                else:
                    c0 = (1.0, 1.0, 1.0)
                c = tuple(c0)
                u, v = uvl.data[li].uv
                uv = trim_uv(TRIM_OF.get(base, base), u, v)
            uvl.data[li].uv = uv
            new_cols.append(c)
    # rebuild the colour attribute (corner domain)
    while me.color_attributes:
        me.color_attributes.remove(me.color_attributes[0])
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for i, c in enumerate(new_cols):
        ca.data[i].color = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = ca
    me.materials.clear()
    return ob


# Vertex-tinted trim variants use the same texture as their base material.
TRIM_OF = {"MI_Trim_Props_Vertex": "MI_Trim_Props", "MI_Trim_Metal_Vertex": "MI_Trim_Metal",
           "MI_Trim_Furniture_Vertex": "MI_Trim_Furniture", "MI_Trim_Cloth_Vertex": "MI_Trim_Cloth"}


def gen_piece(kind):
    bm = bmesh.new()
    if kind == "cheese_round":
        bmesh.ops.create_cone(bm, cap_ends=True, segments=14, radius1=0.16, radius2=0.16, depth=0.09)
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.045))
        col = (0.95, 0.62, 0.16)
    elif kind == "cheese_wedge":
        # a triangular prism wedge
        pts = [(0, 0), (0.17, -0.06), (0.17, 0.06)]
        vs = [bm.verts.new((x, y, 0)) for x, y in pts] + [bm.verts.new((x, y, 0.08)) for x, y in pts]
        bm.faces.new(vs[0:3][::-1])
        bm.faces.new(vs[3:6])
        for i in range(3):
            j = (i + 1) % 3
            bm.faces.new((vs[i], vs[j], vs[j + 3], vs[i + 3]))
        col = (1.0, 0.72, 0.2)
    else:  # bread_round: a boule
        bmesh.ops.create_uvsphere(bm, u_segments=12, v_segments=6, radius=0.14)
        for v in bm.verts:
            v.co.z *= 0.6
        bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, 0.08))
        col = (0.85, 0.5, 0.2)
    me = bpy.data.meshes.new(kind)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(kind, me)
    bpy.context.scene.collection.objects.link(ob)
    uvl = me.uv_layers.new(name="UVMap")
    for l in uvl.data:
        l.uv = trim_uv("", 0, 0)
    ca = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for d in ca.data:
        d.color = (col[0], col[1], col[2], 1.0)
    me.color_attributes.active_color = ca
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    return ob


def bbox(ob):
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx


def decimate(ob, target):
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if target and tris > target:
        md = ob.modifiers.new("dec", "DECIMATE")
        md.ratio = max(0.05, target / tris)
        md.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=md.name)


def extract_pieces():
    """Import and bake every piece in its own scene, returning [(name, verts/faces/uv/col data)]."""
    results = {}
    for name, (src, origin, ex) in PIECES.items():
        clear()
        if src.startswith("gen:"):
            ob = gen_piece(src[4:])
        else:
            meshes = import_piece(src)
            if not meshes:
                print("NO MESH", name)
                continue
            ob = bake_piece(meshes)
        ob.name = name
        bpy.context.view_layer.objects.active = ob
        # orientation
        rx = ex.get("rx", 0)
        if rx:
            ob.rotation_euler = (math.radians(rx), 0, 0)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mn, mx = bbox(ob)
        size = max((mx - mn)[i] for i in range(3))
        if "size" in ex:
            s = ex["size"] / max(size, 1e-5)
        else:
            s = ex.get("boost", 1.0)
        ob.scale = (s, s, s)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        mn, mx = bbox(ob)
        longest = max((mx - mn)[i] for i in range(3))
        # mobile budget: small goods <= 100 tris, everything else <= 260 unless a piece asks otherwise
        cap = ex.get("tris", 100 if longest < 0.3 else 260)
        decimate(ob, cap)
        mn, mx = bbox(ob)
        cx, cy = (mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5
        oz = mn.z if origin == "base" else mx.z
        ob.location = (-cx, -cy, -oz)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        me = ob.data
        me.calc_loop_triangles()
        tris = len(me.loop_triangles)
        mn, mx = bbox(ob)
        # snapshot as plain data (survives the next clear)
        uv = me.uv_layers.active.data
        ca = me.color_attributes.active_color.data
        verts = [tuple(v.co) for v in me.vertices]
        loops = [(l.vertex_index, tuple(uv[i].uv), tuple(ca[i].color)) for i, l in enumerate(me.loops)]
        polys = [[li for li in p.loop_indices] for p in me.polygons]
        results[name] = dict(verts=verts, loops=loops, polys=polys, tris=tris, size=[round(mx[i] - mn[i], 3) for i in range(3)], origin=origin)
        print("PIECE", name, tris, results[name]["size"])
    return results


def mesh_from(name, d):
    """Rebuild a mesh from the plain snapshot (faces keep their loop order, so per-loop data lines up)."""
    me = bpy.data.meshes.new(name)
    faces = [[d["loops"][li][0] for li in p] for p in d["polys"]]
    me.from_pydata(d["verts"], [], faces)
    me.uv_layers.new(name="UVMap")
    me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    uvl = me.uv_layers[0]        # fetched after both are created: adding an attribute invalidates older handles
    ca = me.color_attributes[0]
    for i, l in enumerate(d["loops"]):
        uvl.data[i].uv = l[1]
        ca.data[i].color = l[2]
    me.color_attributes.active_color = ca
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    return me


def assemble_and_export(results):
    clear()
    col = bpy.context.scene.collection
    for name, d in results.items():
        me = mesh_from(name, d)
        ob = bpy.data.objects.new(name, me)
        col.objects.link(ob)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "market_goods.glb"), export_format="GLB",
                              export_materials="NONE", export_vertex_color="ACTIVE",
                              export_apply=True, export_yup=True, export_cameras=False, export_lights=False)
    meta = {k: dict(tris=v["tris"], size=v["size"], origin=v["origin"], src=PIECES[k][0]) for k, v in results.items()}
    json.dump(meta, open(os.path.join(OUT, "pieces.json"), "w"), indent=1, sort_keys=True)
    print("TOTAL pieces", len(results), "tris", sum(v["tris"] for v in results.values()))


def copy_sources():
    """Selected originals only (glTF + bin, FBX) and the trim textures, gdignored, with licences."""
    os.makedirs(SRC, exist_ok=True)
    open(os.path.join(SRC, ".gdignore"), "w").close()
    gl = os.path.join(SRC, "fantasy-props-megakit")
    fd = os.path.join(SRC, "ultimate-food")
    os.makedirs(os.path.join(gl, "glTF"), exist_ok=True)
    os.makedirs(os.path.join(gl, "Textures"), exist_ok=True)
    os.makedirs(fd, exist_ok=True)
    for name, (src, _, _) in PIECES.items():
        kind, n = src.split(":") if ":" in src else ("", "")
        if kind == "fp":
            for ext in (".gltf", ".bin"):
                shutil.copy2(os.path.join(FP, "Exports", "glTF", n + ext), os.path.join(gl, "glTF", n + ext))
        elif kind == "food":
            shutil.copy2(os.path.join(FOOD, "FBX", n + ".fbx"), os.path.join(fd, n + ".fbx"))
    for fn in TRIMS.values():
        shutil.copy2(os.path.join(FP, "Textures", fn[0]), os.path.join(gl, "Textures", fn[0]))
    shutil.copy2(os.path.join(FP, "License_Standard.txt"), os.path.join(gl, "License_Standard.txt"))
    shutil.copy2(os.path.join(FOOD, "License.txt"), os.path.join(fd, "License.txt"))


def preview(results):
    """Contact sheet (Cycles CPU): every piece on a grid with the shared atlas material."""
    clear()
    scn = bpy.context.scene
    mat = bpy.data.materials.new("goods")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(OUT, "market_goods_atlas.png"))
    tex.image.colorspace_settings.name = "sRGB"
    tex.interpolation = "Linear"
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(tex.outputs["Color"], mul.inputs[6])
    nt.links.new(attr.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    names = sorted(results)
    cols = 9
    for i, name in enumerate(names):
        d = results[name]
        me = mesh_from(name, d)
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        scn.collection.objects.link(ob)
        # normalise display size so tiny pieces are visible: scale to fit a 0.55 m cell, keep true-size note in name
        s = 0.5 / max(max(d["size"]), 0.05)
        ob.scale = (s, s, s)
        ob.location = ((i % cols) * 0.9, -(i // cols) * 0.95, 0)
        f = bpy.data.curves.new("t" + name, "FONT")
        f.body = name
        t = bpy.data.objects.new("t" + name, f)
        t.data.size = 0.055
        t.location = ((i % cols) * 0.9 - 0.3, -(i // cols) * 0.95 - 0.12, 0)
        t.data.materials.append(bpy.data.materials.new("txt"))
        scn.collection.objects.link(t)
    rows = (len(names) + cols - 1) // cols
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = cols * 0.7 + 0.2
    co = bpy.data.objects.new("cam", cam)
    scn.collection.objects.link(co)
    th = math.radians(55)
    cx, cy = (cols - 1) * 0.35, -(rows - 1) * 0.35
    co.location = (cx, cy - 10.0 * math.sin(th), 10.0 * math.cos(th))
    co.rotation_euler = (th, 0, 0)
    scn.camera = co
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.0
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), math.radians(10), math.radians(30))
    scn.collection.objects.link(so)
    scn.world = bpy.data.worlds.new("w")
    scn.world.use_nodes = True
    scn.world.node_tree.nodes["Background"].inputs[0].default_value = (0.75, 0.82, 0.95, 1)
    scn.world.node_tree.nodes["Background"].inputs[1].default_value = 1.1
    scn.render.engine = "CYCLES"
    scn.cycles.samples = 24
    scn.cycles.device = "CPU"
    scn.render.resolution_x = 2000
    scn.render.resolution_y = int(2000 * (rows * 0.7 + 0.4) / (cols * 0.7 + 0.2))
    scn.render.filepath = os.path.join(ROOT, "docs", "kingdom", "blender_previews", "market_goods_sheet.png")
    os.makedirs(os.path.dirname(scn.render.filepath), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", scn.render.filepath)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    build_atlas()
    copy_sources()
    res = extract_pieces()
    assemble_and_export(res)
    if "--preview" in sys.argv:
        preview(res)
