"""Task A: re-material Meshy props with real-scan CC0 materials (Rising Ashes AAA prop pass, 2026-10-28).

For each prop: import the Meshy GLB -> clean (merge by distance, drop loose bits and degenerate faces, recalc normals)
-> scale to the real size (RULES[name]["size"]) with the origin at the feet -> decimate to the budget if over it
-> classify every face into a material part from Meshy's painted base colour (HSV) + height/radius (per-prop rules,
   smoothed by a neighbour majority vote) -> CC0 material per part (refine_lib.LIB) -> new smart-UV 'bake_uv'
-> Cycles bake to one albedo / ORM / normal set (1K, 2K for well and market stall) with edge wear, cavity grime,
   ground mud and colour variation -> GLB in kingdom/assets/props_refined/<name>/ (+ LICENSE.txt)
-> gate renders: the Meshy original and the refined prop from the same gameplay camera (side-by-side JPG).

Usage (one Blender at a time):
  tools/external/blender.sh tools/blender/props/refine_meshy.py -- [names...] [--debug] [--work DIR]
  --debug renders only the per-face classification (flat colours) to check the rules.
"""
import bpy, bmesh, sys, os, math, colorsys, shutil
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refine_lib as RL

SRC = r"C:\Users\Jonna\Documents\ProjectAshes_art_staging\downloads\meshy\props_2026-10-28"
OUT = os.path.join(RL.ASSETS, "props_refined")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
DEBUG = "--debug" in argv
WORK = argv[argv.index("--work") + 1] if "--work" in argv else r"C:\Users\Jonna\Tools\_scratch\refine"
ISLAND_VOTE = 1.01   # disabled: Meshy shells are fused (cart = 2 islands), the vote only erased small parts
NAMES = [a for a in argv if not a.startswith("--") and a != WORK]


# ------------------------------------------------------------------ per-prop rules
# f = dict(h, s, v (sRGB HSV of Meshy's albedo), z (0..1 of height), r (0..1 horizontal radius), x, y (metres))
def cls_cart(f):
    if f["v"] < 0.16:
        return "iron"
    if f["s"] > 0.16 and f["v"] > 0.45 and f["z"] > 0.66:
        return "meshy_burlap"
    return "wood_grey"


def cls_well(f):
    if f["v"] < 0.17 and f["z"] < 0.6:
        return "iron"
    if f["z"] < 0.36 and f["r"] > 0.42:
        return "stone"
    if f["z"] < 0.36 and f["r"] < 0.32 and f["s"] > 0.45:
        return "iron"                # bucket hoops (painted orange-brown)
    if f["r"] < 0.2 and 0.35 < f["z"] < 0.78 and f["v"] > 0.45:
        return "rope"
    if f["z"] < 0.36:
        return "wood_oak"            # the bucket staves
    if f["z"] > 0.74:
        return "wood_grey"           # shingles + roof frame
    return "wood_oak"


def cls_crates(f):
    if f["v"] < 0.2:
        return "iron"
    return "wood_oak"


def cls_table(f):
    if f["v"] > 0.75 and f["s"] < 0.25:
        return "meshy"               # the candle
    return "wood_dark"


def cls_hearth(f):
    if f["s"] > 0.35 and 0.2 < f["z"] < 0.6 and f["r"] < 0.45 and f["v"] > 0.2:
        return "iron"                # copper-painted cauldron -> blackened iron
    if f["z"] < 0.3 and f["s"] > 0.28 and f["r"] < 0.6:
        return "bark"                # the logs
    if f["z"] > 0.84 and f["s"] > 0.12:
        return "plaster"             # the smoke hood: lime-plastered, soot-stained (Meshy painted it flat brown)
    if f["z"] > 0.66 and f["s"] > 0.12:
        return "wood_dark"           # mantel beam
    if f["v"] < 0.2:
        return "stone_soot"
    return "stone"


def cls_stall(f):
    if f["z"] > 0.62 and f["s"] > 0.35 and 0.06 < f["h"] < 0.2 and f["v"] > 0.35:
        return "canvas"
    if f["s"] > 0.45 and f["v"] > 0.3:
        return "meshy"               # produce (apples, pears)
    if 0.04 < f["h"] < 0.14 and f["s"] > 0.18 and f["v"] > 0.45 and f["z"] < 0.45:
        return "meshy_burlap"        # sacks
    if f["v"] < 0.12:
        return "iron"
    return "wood_grey"


def cls_pouch(f):
    return "meshy_leather"           # Meshy's stitched dark leather is good: keep it, add grain + wear


RULES = {
    "cart":          dict(fn=cls_cart, size=("longest", 2.2), budget=15000, tex=1024),
    "well":          dict(fn=cls_well, size=("height", 2.3), budget=15000, tex=2048),
    "crate_stack":   dict(fn=cls_crates, size=("height", 1.2), budget=8000, tex=1024),
    "trestle_table": dict(fn=cls_table, size=("height", 0.78), budget=8000, tex=1024),
    "hearth":        dict(fn=cls_hearth, size=("height", 2.0), budget=15000, tex=1024),
    "market_stall":  dict(fn=cls_stall, size=("height", 2.3), budget=15000, tex=2048),
    "belt_pouch":    dict(fn=cls_pouch, size=("longest", 0.2), budget=5000, tex=1024),
}


# ------------------------------------------------------------------ steps
def import_meshy(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + ".glb"))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    ob = RL.join(obs, name)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    ob.data.uv_layers[0].name = "meshy_uv"
    base = None
    for n in ob.data.materials[0].node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.outputs["Color"].links and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links):
            base = n.image
    RL.apply_all(ob)
    return ob, base


def clean(ob, recalc=True):
    me = ob.data
    diag = Vector(ob.dimensions).length
    bm = bmesh.new()
    bm.from_mesh(me)
    n0 = len(bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=diag * 0.0004)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=diag * 1e-5)
    # loose bits: tiny disconnected islands (AI debris) and loose verts/edges
    seen = set()
    kill = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, island = [f], []
        seen.add(f.index)
        while stack:
            g = stack.pop()
            island.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        pts = [v.co for g in island for v in g.verts]
        d = (Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts))) -
             Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))).length
        if len(island) < 24 and d < diag * 0.015:
            kill.extend(island)
    bmesh.ops.delete(bm, geom=list(set(kill)), context="FACES")
    loose_e = [e for e in bm.edges if not e.link_faces]
    bmesh.ops.delete(bm, geom=loose_e, context="EDGES")
    loose_v = [v for v in bm.verts if not v.link_edges]
    bmesh.ops.delete(bm, geom=loose_v, context="VERTS")
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    print("CLEAN", ob.name, n0, "->", len(me.polygons), "faces; removed islands faces", len(set(kill)), flush=True)


def scale_to_size(ob, rule):
    kind, val = rule
    RL.origin_to_feet(ob)
    d = ob.dimensions
    if kind == "longest":
        s = val / max(d)
    elif kind == "height":
        s = val / d.z
    else:   # base_width: width of the lowest 30 % of the mesh (the well ring, not the roof overhang)
        lo = [v.co for v in ob.data.vertices if v.co.z < d.z * 0.3]
        w = max(max(v.x for v in lo) - min(v.x for v in lo), max(v.y for v in lo) - min(v.y for v in lo))
        s = val / w
    ob.scale = (s, s, s)
    RL.apply_all(ob)
    RL.origin_to_feet(ob)
    print("SCALE", ob.name, round(s, 3), "dims", tuple(round(x, 2) for x in ob.dimensions), flush=True)


def weld(ob, frac=0.0003):
    """glTF import splits vertices at every UV seam / hard edge: a 1M+ Meshy mesh is then mostly loose triangles and the
    collapse decimator shatters it. Weld first (UVs live on loops, so they survive)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    n0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=Vector(ob.dimensions).length * frac)
    bm.to_mesh(ob.data)
    print("WELD", ob.name, n0, "->", len(bm.verts), flush=True)
    bm.free()


def decimate(ob, budget):
    t = RL.tri_count(ob)
    if t <= budget:
        return
    weld(ob)
    md = ob.modifiers.new("dec", "DECIMATE")
    md.ratio = budget / t * 0.98
    md.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="dec")
    print("DECIMATE", ob.name, t, "->", RL.tri_count(ob), flush=True)


def classify(ob, base_img, fn):
    me = ob.data
    W, H = base_img.size
    px = np.empty(W * H * 4, dtype=np.float32)
    base_img.pixels.foreach_get(px)
    px = px.reshape(H, W, 4)
    uv = me.uv_layers["meshy_uv"].data
    zmax = ob.dimensions.z
    rmax = max(ob.dimensions.x, ob.dimensions.y) / 2
    labels = []
    for p in me.polygons:
        cols = []
        uvs = [uv[li].uv for li in p.loop_indices]
        c = sum((Vector(u) for u in uvs), Vector((0, 0))) / len(uvs)
        for u in uvs + [c, c]:
            uu = (u + c) / 2 if u is not c else c          # sample between centroid and corners (avoid seam bleed)
            x = int(min(max(uu.x, 0), 0.9999) * W)
            y = int(min(max(uu.y, 0), 0.9999) * H)
            cols.append(px[y, x, :3])
        r, g, b = np.median(np.array(cols), axis=0)
        h, s, v = colorsys.rgb_to_hsv(r, g, b)
        co = p.center
        f = dict(h=h, s=s, v=v, z=co.z / zmax, r=math.hypot(co.x, co.y) / rmax, x=co.x, y=co.y, nz=p.normal.z)
        labels.append(fn(f))
    # majority smoothing over edge neighbours (2 passes) to kill speckle at painted seams
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    nbrs = [[h.index for e in f.edges for h in e.link_faces if h.index != f.index] for f in bm.faces]
    bm.free()
    for _ in range(2):
        new = list(labels)
        for i, nb in enumerate(nbrs):
            if not nb:
                continue
            cnt = {}
            for j in nb:
                cnt[labels[j]] = cnt.get(labels[j], 0) + 1
            best = max(cnt, key=cnt.get)
            if best != labels[i] and cnt[best] >= max(2, len(nb) * 0.66):
                new[i] = best
        labels = new
    # island vote: a connected shell that is mostly one part becomes all that part (painted-light planks were read as sacks)
    seen = [False] * len(labels)
    n_isl = 0
    for i in range(len(labels)):
        if seen[i]:
            continue
        stack, isl = [i], []
        seen[i] = True
        while stack:
            k = stack.pop()
            isl.append(k)
            for j in nbrs[k]:
                if not seen[j]:
                    seen[j] = True
                    stack.append(j)
        n_isl += 1
        cnt = {}
        for k in isl:
            cnt[labels[k]] = cnt.get(labels[k], 0) + 1
        best = max(cnt, key=cnt.get)
        if cnt[best] >= len(isl) * ISLAND_VOTE and len(isl) < len(labels) * 0.6:
            for k in isl:
                labels[k] = best
    print("ISLANDS", ob.name, n_isl, flush=True)
    classes = sorted(set(labels))
    stats = {c: labels.count(c) for c in classes}
    print("CLASSES", ob.name, stats, flush=True)
    return labels, classes


def assign(ob, labels, classes, base_img, debug=False):
    me = ob.data
    me.materials.clear()
    for c in classes:
        if debug:
            m = bpy.data.materials.new("D_" + c)
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*RL.COLOR_DEBUG[c], 1)
        else:
            m = RL.make_material(c, meshy_img=base_img)
        me.materials.append(m)
    for p, l in zip(me.polygons, labels):
        p.material_index = classes.index(l)
    for p in me.polygons:
        p.use_smooth = True
    # keep Meshy's normals smooth but hard-edged at real creases
    try:
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.shade_auto_smooth(angle=math.radians(50))
    except Exception as e:
        print("autosmooth skipped", e)


def replace_hood(ob):
    """hearth: delete Meshy's boulder-shaped 'hood' (the plaster class) and model a lime-plastered smoke hood + flue that sits on
    the mantel shelf against the back wall, up to a 3.0 m ceiling."""
    me = ob.data
    hood_i = [i for i, m in enumerate(me.materials) if m and m.name.startswith("M_plaster")]
    soot_i = [i for i, m in enumerate(me.materials) if m and m.name.startswith("M_stone_soot")]
    bm = bmesh.new()
    bm.from_mesh(me)
    soot_c = [f.calc_center_median() for f in bm.faces if f.material_index in soot_i]
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in hood_i], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    vs = [v.co for v in me.vertices]
    top = max(v.z for v in vs)
    shelf = [v for v in vs if v.z > top - 0.06]
    x0, x1 = min(v.x for v in shelf), max(v.x for v in shelf)
    y0, y1 = min(v.y for v in shelf), max(v.y for v in shelf)
    yc_all = (min(v.y for v in vs) + max(v.y for v in vs)) / 2
    back_sign = 1.0 if (sum(c.y for c in soot_c) / max(1, len(soot_c))) > yc_all else -1.0
    back = y1 if back_sign > 0 else y0
    W, D = x1 - x0, y1 - y0
    xc = (x0 + x1) / 2
    print("HOOD shelf top", round(top, 3), "W", round(W, 2), "D", round(D, 2), "back_sign", back_sign, flush=True)
    z0 = top - 0.004
    zt = 3.0
    rings_def = [(z0, W * 0.90, D * 0.78), (z0 + 0.04, W * 0.94, D * 0.80), (z0 + 0.08, W * 0.94, D * 0.80), (z0 + 0.10, W * 0.90, D * 0.78),
                 (z0 + 0.80, 0.62, 0.48), (z0 + 0.84, 0.66, 0.50), (z0 + 0.88, 0.62, 0.48), (zt, 0.60, 0.46)]
    hb = bmesh.new()
    rows = []
    ch = 0.015
    for z, w, d in rings_def:
        yc = back - back_sign * d / 2
        hw, hd = w / 2, d / 2
        pts = [(-hw + ch, -hd), (hw - ch, -hd), (hw, -hd + ch), (hw, hd - ch), (hw - ch, hd), (-hw + ch, hd), (-hw, hd - ch), (-hw, -hd + ch)]
        rows.append([hb.verts.new((xc + x, yc + y, z)) for x, y in pts])
    for i in range(len(rows) - 1):
        for j in range(8):
            hb.faces.new((rows[i][j], rows[i][(j + 1) % 8], rows[i + 1][(j + 1) % 8], rows[i + 1][j]))
    hb.faces.new(list(reversed(rows[0])))
    hb.faces.new(rows[-1])
    bmesh.ops.recalc_face_normals(hb, faces=hb.faces)
    # subdivide so the bake/AO has some resolution and the plaster can bulge a little (hand-applied lime)
    bmesh.ops.subdivide_edges(hb, edges=hb.edges, cuts=2, use_grid_fill=True)
    from mathutils import noise as mnoise
    for v in hb.verts:
        v.co += v.normal * 0.006 * mnoise.noise(v.co * 4.0)
    hm = bpy.data.meshes.new("hood")
    hb.to_mesh(hm)
    hb.free()
    hm.uv_layers.new(name="meshy_uv")
    RL.LIB["plaster_hood"]["soot"] = (z0 + 0.02, z0 + 0.38)
    hm.materials.append(RL.make_material("plaster_hood"))
    for p in hm.polygons:
        p.use_smooth = False
    ho = bpy.data.objects.new("hood", hm)
    bpy.context.scene.collection.objects.link(ho)
    return RL.join([ob, ho], ob.name)


def process(name):
    rule = RULES[name]
    ob, base = import_meshy(name)
    clean(ob)
    scale_to_size(ob, rule["size"])
    # the untouched-original copy for the side-by-side (same scale, Meshy material)
    orig = ob.copy()
    orig.data = ob.data.copy()
    orig.name = name + "_meshy"
    bpy.context.scene.collection.objects.link(orig)
    decimate(ob, rule["budget"])
    labels, classes = classify(ob, base, rule["fn"])
    gate = os.path.join(WORK, "gate")
    os.makedirs(gate, exist_ok=True)
    if DEBUG:
        assign(ob, labels, classes, base, debug=True)
        RL.render_view([ob], os.path.join(gate, f"{name}_classes.jpg"), res=(480, 360))
        return
    nrm = os.path.join(WORK, "deepbump", name + "_nrm.png")
    RL.MESHY_NRM = None
    if os.path.exists(nrm):
        RL.MESHY_NRM = bpy.data.images.load(nrm)
        RL.MESHY_NRM.colorspace_settings.name = "Non-Color"
    assign(ob, labels, classes, base)
    if name == "hearth":
        ob = replace_hood(ob)
    RL.smart_uv(ob)
    tmp = os.path.join(WORK, "bake_" + name)
    fm = RL.bake_asset(ob, rule["tex"], tmp, name)
    RL.finalize_materials(ob, fm)
    folder = os.path.join(OUT, name)
    RL.export_glb(ob, os.path.join(folder, name + ".glb"))
    RL.write_license(folder, name, "Geometry: derived from Meshy AI output generated on the project owner's Meshy account "
                                   "(meshy-7.1, 2026-10-28 batch, see ProjectAshes_art_staging/downloads/meshy/props_2026-10-28/README.md); "
                                   "cleaned, rescaled, re-UV'd and re-materialed in Blender.")
    # gate: re-import the exported GLB (what Godot will get) next to the Meshy original
    bpy.data.objects.remove(ob)
    for g in list(bpy.data.node_groups):      # the importer builds its own 'glTF Material Output' group
        bpy.data.node_groups.remove(g)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name + ".glb"))
    new = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    RL.render_view([orig], os.path.join(gate, f"{name}_A_meshy.jpg"))
    RL.render_view(new, os.path.join(gate, f"{name}_B_refined.jpg"))
    with open(os.path.join(WORK, "stats.txt"), "a") as f:
        f.write(f"{name}\t{sum(RL.tri_count(o) for o in new)}\t{rule['tex']}\t{tuple(round(x, 2) for x in new[0].dimensions)}\n")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    for n in (NAMES or list(RULES)):
        process(n)
    print("DONE")
