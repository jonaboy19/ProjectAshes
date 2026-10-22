# Driver for the horse asset stage (idempotent, re-runnable after the lead rebuilds source/horse_rig.blend):
#   blender -b --factory-startup --python kingdom/tools/anim/horse/horse_export.py [-- --no-previews]
# 1. opens horse_rig.blend (never saved back), 2. unwraps Horse_LOD0 + bakes six coat textures (horse_coats.py),
# 3. builds LOD1/LOD2, 4. exports horse_riding.glb, 5. builds tack + cart and exports one GLB each (horse_tack.py, hx_cart.py),
# 6. writes atlas + .tres materials, 7. renders previews into docs/anim/horses/, 8. re-imports the GLBs as a sanity check.
import bpy, os, sys, math, subprocess, tempfile
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hx_common as X
import horse_coats as HC
import horse_tack as T
import hx_atlas as A
import hx_cart as CART
from hx_common import V

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEWS = "--no-previews" not in ARGV
STATS = {}
TACK = ["saddle", "bridle", "reins", "saddlebags", "cart_harness", "barding"]


# ------------------------------------------------------------------ LODs
def limit4(ob):
    X.limit_normalize(ob, 4)


def make_lod(src, name, ratio):
    ob = src.copy()
    ob.data = src.data.copy()
    ob.name = name
    ob.data.name = name
    bpy.context.scene.collection.objects.link(ob)
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    if ratio < 0.999:
        dm = ob.modifiers.new("dec", "DECIMATE")
        dm.decimate_type = "COLLAPSE"
        dm.ratio = ratio
        dm.use_collapse_triangulate = True
        X.select_only(ob)
        bpy.ops.object.modifier_apply(modifier="dec")
    limit4(ob)
    for n in ("regions", "region"):
        a = ob.data.color_attributes.get(n) if n == "regions" else ob.data.attributes.get(n)
        if a is not None:
            (ob.data.color_attributes if n == "regions" else ob.data.attributes).remove(a)
    arm = bpy.data.objects["HorseSkeleton"]
    ob.parent = arm
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_world = Matrix.Identity(4)
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def tune_lod(src, name, target):
    """binary search the decimate ratio so the triangle count is close to target"""
    lo, hi = 0.05, 1.0
    best = None
    for _ in range(7):
        mid = (lo + hi) / 2
        ob = make_lod(src, "tmp_lod", mid)
        t = X.tris(ob)
        bpy.data.objects.remove(ob)
        if abs(t - target) < 0.03 * target:
            break
        if t > target:
            hi = mid
        else:
            lo = mid
    return make_lod(src, name, mid)


# ------------------------------------------------------------------ export
def gltf_export(path, objs, arm=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs + ([arm] if arm else []):
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm or objs[0]
    props = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_def_bones=False,
              export_animations=False, export_skins=True, export_apply=False, export_materials="EXPORT",
              export_image_format="AUTO", export_vertex_color="NONE", export_cameras=False, export_lights=False,
              export_optimize_animation_size=False, export_leaf_bone=False)
    kw = {k: v for k, v in kw.items() if k in props}
    bpy.ops.export_scene.gltf(**kw)
    X.log("exported", os.path.basename(path), os.path.getsize(path) // 1024, "KB")


# ------------------------------------------------------------------ clipping check
def body_bvh_eval(src):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = src.evaluated_get(dg)
    me = ev.to_mesh()
    reg = me.attributes.get("region")
    verts = [v.co.copy() for v in me.vertices]
    polys = [tuple(p.vertices) for p in me.polygons if reg is None or reg.data[p.index].value != 7]
    bv = BVHTree.FromPolygons(verts, polys)
    ev.to_mesh_clear()
    return bv


def clip_report(src, pieces, label):
    bv = body_bvh_eval(src)
    dg = bpy.context.evaluated_depsgraph_get()
    out = {}
    for o in pieces:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        worst, n = 0.0, 0
        for v in me.vertices:
            r = bv.find_nearest(v.co, 0.25)
            if r[0] is None:
                continue
            d = (v.co - r[0]).dot(r[1])
            if d < -0.004:
                n += 1
                worst = max(worst, -d)
        ev.to_mesh_clear()
        out[o.name] = (n, worst)
    X.log("CLIP", label, " ".join("%s:%dv/%.0fmm" % (k.replace("horse_tack_", ""), n, w * 1000) for k, (n, w) in out.items()))
    return out


POSES = {
    "neck_down": {"neck_1": (25, 0, 0), "neck_2": (8, 0, 0), "neck_3": (8, 0, 0), "head": (10, 0, 0)},
    "fore_flex": {"humerus_L": (-35, 0, 0), "forearm_L": (60, 0, 0), "cannon_F_L": (-70, 0, 0), "thigh_R": (30, 0, 0),
                  "gaskin_R": (-40, 0, 0), "cannon_H_R": (50, 0, 0)},
}


# ------------------------------------------------------------------ preview scene
def clone_horse(arm, meshes, pose, tf, tag):
    """copy armature + skinned meshes (+ shared data), moved by tf (Matrix); returns (arm, meshes)"""
    a2 = arm.copy()
    a2.name = "hx_" + tag + "_arm"
    a2.data = arm.data
    bpy.context.scene.collection.objects.link(a2)
    a2.matrix_world = tf
    a2.hide_render = False
    a2.hide_viewport = False
    out = []
    for o in meshes:
        c = o.copy()
        c.data = o.data.copy()
        c.name = "hx_%s_%s" % (tag, o.name)
        bpy.context.scene.collection.objects.link(c)
        c.hide_render = False
        c.hide_viewport = False
        c.parent = a2
        c.matrix_parent_inverse = Matrix.Identity(4)
        for m in c.modifiers:
            if m.type == "ARMATURE":
                m.object = a2
        out.append(c)
    return a2, out


def label_image(path, labels, size=None):
    """draw text labels with PIL (system python); labels = [(x, y, text)] in pixels"""
    import json
    js = json.dumps(labels)
    code = ("import sys,json\nfrom PIL import Image,ImageDraw,ImageFont\np=sys.argv[1]\nL=json.loads(sys.argv[2])\n"
            "im=Image.open(p).convert('RGB')\nd=ImageDraw.Draw(im)\n"
            "try:\n f=ImageFont.truetype('arial.ttf',26)\nexcept Exception:\n f=ImageFont.load_default()\n"
            "for x,y,t in L:\n w=d.textlength(t,font=f)\n d.rectangle([x-w/2-8,y-4,x+w/2+8,y+34],fill=(40,30,30))\n d.text((x-w/2,y),t,fill=(255,240,210),font=f)\n"
            "im.save(p)\n")
    try:
        subprocess.run(["py", "-3", "-c", code, path, js], check=True)
    except Exception as e:
        X.log("label failed", e)


def project(pt):
    from bpy_extras.object_utils import world_to_camera_view
    sc = bpy.context.scene
    co = world_to_camera_view(sc, sc.camera, pt)
    return co.x * sc.render.resolution_x, (1 - co.y) * sc.render.resolution_y


def hide_originals(objs):
    for o in objs:
        o.hide_render = True
        o.hide_viewport = True


def previews(arm, src, lods, tack_objs, cart, coat_imgs, tack_mat):
    os.makedirs(X.DOCS, exist_ok=True)
    allobjs = [src] + list(lods) + list(tack_objs.values()) + [cart]
    hide_originals(allobjs)
    arm.hide_render = True
    sc = X.setup_scene_render(1800, 820)
    X.ground(size=80, color=(0.50, 0.60, 0.28))
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.85
    coat_mats = {c: X.textured_material("pv_" + c, coat_imgs[c], 0.75) for c in coat_imgs}
    # ---- coats lineup: 2 rows x 3, 3/4 view
    tmp = tempfile.gettempdir()
    lab = []
    order = HC.COAT_ORDER
    lod0 = lods[0]
    cams = []
    for i, c in enumerate(order):
        col, row = i % 3, i // 3
        loc = Vector(((col - 1) * 4.6, row * 4.6, 0))
        tf = Matrix.Translation(loc) @ Matrix.Rotation(math.radians(-38), 4, "Z")
        a2, ms = clone_horse(arm, [lod0], {}, tf, "coat%d" % i)
        ms[0].data.materials.clear()
        ms[0].data.materials.append(coat_mats[c])
        lab.append((loc + Vector((0, 0, 0.0)), c))
    X.camera((0.0, -17.0, 6.0), (0, 2.6, 0.7), lens=55)
    p = os.path.join(X.DOCS, "coats_lineup.png")
    X.render(p)
    label_image(p, [(*project(l + Vector((0, 0.3, 0))), n) for l, n in lab])
    for o in [o for o in bpy.data.objects if o.name.startswith("hx_coat")]:
        bpy.data.objects.remove(o)
    # ---- tack lineup
    sc.render.resolution_x, sc.render.resolution_y = 1800, 1000
    sets = [
        ("bay", ["saddle", "bridle", "reins"], "saddle + bridle + reins", None),
        ("grey", ["saddle", "bridle", "reins", "saddlebags"], "+ saddlebags", None),
        ("chestnut", ["bridle", "cart_harness"], "cart harness + cart", True),
        ("warhorse", ["barding", "bridle", "saddle", "reins"], "barded warhorse", None),
    ]
    pos4 = [(-3.2, 0.0), (3.0, 0.0), (-3.6, 5.6), (3.6, 5.6)]
    lab = []
    for i, (coat, pcs, text, cart_on) in enumerate(sets):
        loc = Vector((pos4[i][0], pos4[i][1], 0))
        tf = Matrix.Translation(loc) @ Matrix.Rotation(math.radians(-35), 4, "Z")
        meshes = [lod0] + [tack_objs[k] for k in pcs]
        a2, ms = clone_horse(arm, meshes, {}, tf, "tack%d" % i)
        ms[0].data = ms[0].data
        ms[0].data.materials.clear()
        ms[0].data.materials.append(coat_mats[coat]) if False else None
        # own copy of the lod0 data so each horse has its coat
        ms[0].data = lod0.data.copy()
        ms[0].data.materials.clear()
        ms[0].data.materials.append(coat_mats[coat])
        lab.append((loc, text))
        if cart_on:
            c2 = cart.copy()
            c2.data = cart.data
            c2.name = "hx_cart_inst"
            bpy.context.scene.collection.objects.link(c2)
            c2.matrix_world = tf @ Matrix.Translation((0, 2.05, 0))
            c2.hide_render = False
    X.camera((0.0, -13.5, 5.4), (0.0, 2.9, 0.8), lens=38)
    p = os.path.join(X.DOCS, "tack_lineup.png")
    X.render(p)
    label_image(p, [(*project(l + Vector((0, 0.3, 0))), n) for l, n in lab])
    for o in [o for o in bpy.data.objects if o.name.startswith("hx_tack") or o.name.startswith("hx_cart")]:
        bpy.data.objects.remove(o)
    # ---- LODs side by side
    sc.render.resolution_x, sc.render.resolution_y = 1800, 640
    lab = []
    bay = coat_mats["bay"]
    for i, l in enumerate(lods):
        loc = Vector(((i - 1) * 3.6, 0, 0))
        tf = Matrix.Translation(loc) @ Matrix.Rotation(math.radians(90), 4, "Z")
        a2, ms = clone_horse(arm, [l], {}, tf, "lod%d" % i)
        ms[0].data.materials.clear()
        ms[0].data.materials.append(bay)
        lab.append((loc, "LOD%d  %d tris" % (i, X.tris(l))))
    X.camera((0, -13.0, 1.2), (0, 0, 0.95), lens=40)
    p = os.path.join(X.DOCS, "lods.png")
    X.render(p)
    label_image(p, [(*project(l + Vector((0, 0, -0.0))), n) for l, n in lab])
    for o in [o for o in bpy.data.objects if o.name.startswith("hx_lod")]:
        bpy.data.objects.remove(o)


# ------------------------------------------------------------------ re-import sanity check
def sanity(paths):
    ok = True
    for p in paths:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=p)
        arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
        meshes = [o for o in bpy.data.objects if o.type == "MESH"]
        nb = sum(len(a.data.bones) for a in arms)
        skinned = [m.name for m in meshes if any(md.type == "ARMATURE" for md in m.modifiers) and len(m.vertex_groups) > 0]
        X.log("SANITY", os.path.basename(p), "armatures", [a.name for a in arms], "bones", nb, "meshes", [m.name for m in meshes],
              "skinned", len(skinned), "/", len(meshes), "anims", len(bpy.data.actions))
        if arms and nb != 66:
            ok = False
    return ok


# ------------------------------------------------------------------ main
def main():
    os.makedirs(X.OUT, exist_ok=True)
    arm, src = X.open_rig()
    src.name = "Horse_src"
    paths, D = HC.build_all(src)
    coat_imgs = {c: X.load_png(paths[c], "horse_coat_" + c) for c in HC.COAT_ORDER}
    # tack needs the region attribute -> build it before the LOD copies strip it
    A.write_atlas()
    atlas = X.load_png(os.path.join(X.OUT, "horse_tack_atlas.png"), "horse_tack_atlas")
    tack_mat = X.textured_material("horse_tack", atlas, 0.7)
    tack_mat.use_backface_culling = False
    T.setup(arm, src)
    tack_objs = {}
    for n in TACK:
        ob = getattr(T, "build_" + n)()
        X.set_material(ob, tack_mat)
        ob.name = "horse_tack_" + n
        tack_objs[n] = ob
        STATS["tack_" + n] = X.tris(ob)
    cart = CART.build_cart()
    X.set_material(cart, tack_mat)
    STATS["cart"] = X.tris(cart)
    # clipping in rest + two test poses (body + hair-less BVH, posed evaluation)
    pieces = [tack_objs[k] for k in ("saddle", "bridle", "saddlebags", "cart_harness", "barding")]
    clip_report(src, pieces, "rest")
    for pn, pd in POSES.items():
        X.pose(arm, pd)
        clip_report(src, pieces, pn)
    X.pose(arm, {})
    # LODs
    lod0 = make_lod(src, "Horse_LOD0", 1.0)
    lod1 = tune_lod(src, "Horse_LOD1", int(X.tris(src) * 0.45))
    lod2 = tune_lod(src, "Horse_LOD2", 1000)
    lods = [lod0, lod1, lod2]
    STATS["lods"] = [X.tris(o) for o in lods]
    coat_mat = X.textured_material("horse_coat", coat_imgs["bay"], 0.75)
    for o in lods:
        X.set_material(o, coat_mat)
    src.hide_viewport = True
    # exports
    gltf_export(os.path.join(X.OUT, "horse_riding.glb"), lods, arm)
    for n, ob in tack_objs.items():
        gltf_export(os.path.join(X.OUT, "horse_tack_%s.glb" % n), [ob], arm)
    gltf_export(os.path.join(X.OUT, "horse_cart.glb"), [cart])
    if PREVIEWS:
        previews(arm, src, lods, tack_objs, cart, coat_imgs, tack_mat)
    outs = [os.path.join(X.OUT, f) for f in ["horse_riding.glb"] + ["horse_tack_%s.glb" % n for n in TACK] + ["horse_cart.glb"]]
    X.log("STATS", STATS)
    sanity(outs)


if __name__ == "__main__":
    main()
