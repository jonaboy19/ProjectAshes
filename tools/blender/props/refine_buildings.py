"""Buildings batch: re-material old Meshy buildings (meshy_keep) with real-scan CC0 stone / plaster / timber / slate / thatch,
real scale, decimated to <= 40k tris (props 15k) with the lost geometry baked back as a high->low normal (whiteout-blended
with the material normal), one 2K texture set (1K for small props). Output: kingdom/assets/props_refined/buildings/<name>/.

Same steps as refine_meshy.py (import -> scale -> decimate -> clean -> classify -> CC0 materials -> smart UV -> bake -> GLB ->
gate renders of the Meshy original and the refined GLB, with a 1.75 m figure for scale).
Usage: tools/external/blender.sh tools/blender/props/refine_buildings.py -- [codes...] [--preview] [--work DIR]
  --preview renders only the scaled Meshy original + the 1.75 m figure (to pick variants and check scale).
"""
import bpy, bmesh, sys, os, math, glob, shutil
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import refine_lib as RL
import refine_meshy as RM

KEEP = r"C:\Users\Jonna\Documents\ProjectAshes_art_staging\meshy_keep"
OUT = os.path.join(RL.ASSETS, "props_refined", "buildings")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
PREVIEW = "--preview" in argv
WORK = argv[argv.index("--work") + 1] if "--work" in argv else r"C:\Users\Jonna\Tools\_scratch\refine"
CODES = [a for a in argv if not a.startswith("--") and a != WORK]

# ------------------------------------------------------------------ building materials (all CC0 Poly Haven scans on disk)
_B = dict(rough=0.0, wear=0.2, grime=0.75, mud=0.6, detail=0.35)
RL.LIB.update({
    "b_ashlar":  dict(kind="scan", tex="stone_wall_04", tile=3.0, sat=0.55, val=0.78, tint=(0.97, 0.95, 0.90), bump=0.8,
                      edge=(0.7, 0.68, 0.64), moss=0.25, **_B),
    "b_rubble":  dict(kind="scan", tex="old_stone_wall", tile=2.6, sat=0.6, val=0.82, tint=(0.95, 0.93, 0.88), bump=0.9,
                      edge=(0.7, 0.68, 0.64), moss=0.3, **_B),
    "b_rustic":  dict(kind="scan", tex="rustic_stone_wall", tile=2.6, sat=0.55, val=0.85, tint=(0.95, 0.93, 0.9), bump=0.9,
                      edge=(0.72, 0.7, 0.66), moss=0.25, **_B),
    "b_dark":    dict(kind="scan", tex="castle_wall_slates", tile=2.6, sat=0.35, val=0.62, tint=(0.92, 0.92, 0.92), bump=0.9,
                      edge=(0.5, 0.5, 0.48), moss=0.35, **_B),
    "b_brick":   dict(kind="scan", tex="castle_brick_07", tile=2.2, sat=0.75, val=0.8, tint=(0.95, 0.9, 0.86), bump=0.8,
                      edge=(0.6, 0.45, 0.38), moss=0.2, **_B),
    "b_plaster": dict(kind="scan", tex="worn_mossy_plasterwall", tile=3.0, sat=0.6, val=0.88, tint=(0.98, 0.95, 0.88), bump=0.5,
                      edge=(0.85, 0.82, 0.76), **_B),
    "b_timber":  dict(kind="scan", tex="rough_wood", tile=1.5, sat=1.0, val=0.42, tint=(0.85, 0.66, 0.48), bump=0.5,
                      edge=(0.45, 0.36, 0.28), **_B),
    "b_slate":   dict(kind="scan", tex="roof_slates_02", tile=2.5, sat=0.5, val=0.75, tint=(0.95, 0.96, 1.0), bump=1.0,
                      edge=(0.55, 0.55, 0.55), moss=0.35, roof=True, **_B),
    "b_shingle": dict(kind="scan", tex="roof_slates_02", tile=2.2, sat=0.6, val=0.62, tint=(0.95, 0.80, 0.62), bump=1.0,
                      edge=(0.5, 0.42, 0.34), moss=0.35, roof=True, **_B),
    "b_tile":    dict(kind="scan", tex="clay_roof_tiles", tile=2.5, sat=0.55, val=0.75, tint=(0.95, 0.88, 0.82), bump=1.0,
                      edge=(0.6, 0.45, 0.38), moss=0.35, roof=True, **_B),
    "b_thatch":  dict(kind="scan", tex="thatch_roof_angled", tile=2.5, sat=0.9, val=0.9, tint=(1.0, 0.9, 0.7), bump=1.0,
                      edge=(0.6, 0.52, 0.38), moss=0.3, roof=True, **_B),
    "b_boards":  dict(kind="scan", tex="old_planks_02", tile=2.0, sat=0.8, val=0.45, tint=(0.85, 0.72, 0.58), bump=0.7,
                      edge=(0.45, 0.4, 0.34), **_B),
    "b_ground":  dict(kind="scan", tex="cobblestone_floor_13", tile=3.0, sat=0.8, val=0.85, tint=(1, 1, 1), bump=1.0,
                      edge=(0.6, 0.55, 0.5), **_B),
})
for k in ("b_ashlar", "b_rubble", "b_rustic", "b_dark", "b_brick", "b_plaster", "b_timber", "b_slate", "b_shingle", "b_tile",
          "b_thatch", "b_ground", "b_boards"):
    RL.COLOR_DEBUG[k] = (0.5, 0.5, 0.5)


def rules(stone="b_rubble", roof="b_slate", plaster="b_plaster", timber="b_timber", roof_z=0.4, dark="b_timber", base_z=0.0,
          dark_walls=None, base_cls=None, timber_s=0.22):
    """Generic building classifier: sloped up-facing faces high up -> roof; green -> keep (ivy); lit windows -> keep;
    light low-sat -> plaster; saturated brown -> timber; very dark -> dark class; everything else -> stone."""
    def fn(f):
        if 0.17 < f["h"] < 0.45 and f["s"] > 0.25 and f["v"] > 0.12:
            return "meshy"                                    # ivy / plants
        if roof and f["z"] > roof_z and 0.3 < f["nz"] < 0.97:
            return roof
        if 0.06 < f["h"] < 0.17 and f["s"] > 0.55 and f["v"] > 0.7 and abs(f["nz"]) < 0.3:
            return "meshy"                                    # lit windows, lanterns (vertical faces only)
        if base_cls and f["z"] < 0.06 and f["nz"] > 0.85:
            return base_cls                                   # porch / plinth slab
        if f["z"] < base_z:
            return stone
        if f["v"] < 0.11:
            return dark
        if dark_walls and f["v"] < 0.32 and f["s"] < 0.45:
            return dark_walls                                 # dark weathered board walls
        if (f["h"] < 0.035 or f["h"] > 0.95) and f["s"] > 0.35 and 0.15 < f["v"] < 0.7:
            return "b_brick"                                  # chimneys
        if plaster and f["s"] < 0.4 and f["v"] > 0.5:
            return plaster
        if timber and f["h"] < 0.14 and f["s"] > timber_s and f["v"] < 0.55:
            return timber
        return stone
    return fn


# cluttered multi-million-tri props: pre-simplified with gltfpack (meshoptimizer, robust on fragment soup where Blender's
# collapse stalls):  gltfpack -i <src> -o <work>/simpl/<code>.glb -noq -si 0.006..0.0075 -sa
SIMPL = {"1004153510": "P99", "1004153633": "P112"}


def find(stamp, original=False):
    if not original and stamp in SIMPL:
        p = os.path.join(WORK, "simpl", SIMPL[stamp] + ".glb")
        if os.path.exists(p):
            return p
    return glob.glob(os.path.join(KEEP, "*", "*%s*.glb" % stamp))[0]


# code: (file stamp, out name, size rule, rules, tri budget, texture)
B = {
    "B07": ("0929060050", "church_parish_grim", ("height", 8.0), rules("b_dark", "b_slate", None, roof_z=0.45, timber_s=0.45), 40000, 2048),
    "B16": ("0929055910", "church_brick_spire", ("height", 20.0), rules("b_brick", "b_slate", None, roof_z=0.3, timber=None), 40000, 2048),
    "B28": ("0929055925", "chapel_stone_small", ("longest", 10.0), rules("b_rubble", "b_slate", "b_plaster", roof_z=0.4), 40000, 2048),
    "B10": ("0929052321", "castle_gate_towers", ("longest", 16.0), rules("b_ashlar", "b_slate", None, roof_z=0.8, dark="iron", timber_s=0.38), 40000, 2048),
    "B26": ("0929052228", "castle_gate_ivy", ("longest", 16.0), rules("b_ashlar", "b_slate", None, roof_z=0.8, dark="iron"), 40000, 2048),
    "B04": ("0929052336", "castle_gate_long", ("longest", 20.0), rules("b_ashlar", "b_slate", None, roof_z=0.8, dark="iron"), 40000, 2048),
    "B15": ("0929052344", "tower_octagon", ("longest", 9.0), rules("b_ashlar", "b_slate", None, roof_z=0.8), 40000, 2048),
    "B42": ("0929071751", "tower_square", ("height", 12.0), rules("b_rubble", "b_slate", None, roof_z=0.8), 40000, 2048),
    "B43": ("0929065600", "house_two_storey_dormer", ("height", 10.0), rules("b_rubble", "b_shingle", "b_plaster", roof_z=0.45), 40000, 2048),
    "B44": ("0929065608", "house_tall_timber", ("height", 12.0), rules("b_rubble", "b_tile", "b_plaster", roof_z=0.55), 40000, 2048),
    "B14": ("0929055719", "blacksmith_thatch", ("height", 7.5), rules("b_rubble", "b_thatch", "b_plaster", roof_z=0.4), 40000, 2048),
    "B52": ("1004153110", "house_tudor_stone_base", ("height", 9.0), rules("b_rubble", "b_shingle", "b_plaster", roof_z=0.45, timber_s=0.3), 40000, 2048),
    "B53": ("1004153116", "house_tudor_corner", ("height", 9.0), rules("b_rubble", "b_shingle", "b_plaster", roof_z=0.45, timber_s=0.3), 40000, 2048),
    "B54": ("1004153113", "row_half_timbered", ("longest", 20.0), rules("b_rubble", "b_tile", "b_plaster", roof_z=0.5), 40000, 2048),
    "B70": ("1004153209", "tavern_dark_roof", ("height", 10.0), rules("b_rubble", "b_slate", "b_plaster", roof_z=0.45, dark_walls="b_boards", base_cls="b_boards"), 40000, 2048),
    "B60": ("1004152428", "cottage_thatch", ("height", 6.5), rules("b_rubble", "b_thatch", "b_plaster", roof_z=0.4), 40000, 2048),
    "P99": ("1004153510", "campfire_cooking", ("longest", 2.4), None, 15000, 1024),
    "P112": ("1004153633", "tent_canvas_shop", ("longest", 5.5), None, 15000, 2048),
}


def cls_campfire(f):
    if 0.17 < f["h"] < 0.45 and f["s"] > 0.25:
        return "meshy"
    if f["v"] < 0.13:
        return "iron"                                         # cauldron, tripod, pots
    if f["s"] > 0.55 and f["v"] > 0.55:
        return "meshy"                                        # flames / embers keep their paint
    if f["s"] < 0.15 and f["z"] < 0.2:
        return "stone"                                        # fire ring stones
    return "bark"


def cls_tent(f):
    if f["z"] > 0.35 and f["v"] > 0.45 and f["s"] < 0.45:
        return "canvas"
    if f["v"] < 0.2:
        return "bark"                                         # dark poles / shadows painted in
    if 0.02 < f["h"] < 0.14 and f["s"] > 0.3:
        return "bark"                                         # poles and logs
    if f["s"] > 0.35:
        return "meshy"                                        # goods
    return "canvas"


B["P99"] = B["P99"][:3] + (cls_campfire,) + B["P99"][4:]
B["P112"] = B["P112"][:3] + (cls_tent,) + B["P112"][4:]


WELD = {"P99": 0.002, "P112": 0.002}      # cluttered props: weld harder (thin pieces are separate shells)


def human(at):
    """1.75 m figure for scale checks (not exported)."""
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=1.75, location=(at.x, at.y, 0.875))
    h = bpy.context.active_object
    h.name = "Scale175"
    m = bpy.data.materials.new("ScaleFig")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.6, 0.12, 0.08, 1)
    h.data.materials.append(m)
    return h


def process(code):
    stamp, name, size, fn, budget, tex = B[code]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=find(stamp))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    ob = RL.join(obs, name)
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    ob.data.uv_layers[0].name = "meshy_uv"
    base = None
    for n in ob.data.materials[0].node_tree.nodes:
        if n.type == "TEX_IMAGE" and any(l.to_socket.name == "Base Color" for l in n.outputs["Color"].links):
            base = n.image
    RL.apply_all(ob)
    RM.scale_to_size(ob, size)
    mn, mx = RL.bbox_of([ob])
    gate = os.path.join(WORK, "gate_b")
    os.makedirs(gate, exist_ok=True)
    fig = human(Vector((mx.x + 0.6, mn.y + 0.5, 0)))
    if PREVIEW:
        RL.render_view([ob, fig], os.path.join(gate, f"{code}_{name}_A_meshy.jpg"), res=(640, 480))
        return
    t0 = RL.tri_count(ob)
    high = None
    if t0 > budget * 1.3:
        high = ob.copy()
        high.data = ob.data.copy()
        high.name = name + "_high"
        bpy.context.scene.collection.objects.link(high)
        high.data.materials.clear()
        high.hide_render = True
    orig = ob.copy()
    orig.data = (high.data if high else ob.data).copy()
    orig.name = name + "_meshy"
    bpy.context.scene.collection.objects.link(orig)
    # keep the Meshy material on the original copy for the side-by-side
    orig.data.materials.clear()
    orig.data.materials.append(ob.data.materials[0])
    orig.hide_render = True
    if code in WELD:
        RM.weld(ob, WELD[code])
    RM.decimate(ob, budget)
    if RL.tri_count(ob) > budget * 1.1:                        # collapse stalls on fragment soup: second pass
        RM.decimate(ob, budget)
    RM.clean(ob)
    labels, classes = RM.classify(ob, base, fn)
    RL.MESHY_NRM = None
    RM.assign(ob, labels, classes, base)
    RL.smart_uv(ob, angle=60.0, margin=0.002)
    tmp = os.path.join(WORK, "bake_" + name)
    diag = (mx - mn).length
    fm = RL.bake_asset(ob, tex, tmp, name, samples=16, high=high, extrusion=diag * 0.004, ray=diag * 0.012)
    RL.finalize_materials(ob, fm)
    folder = os.path.join(OUT, name)
    RL.export_glb(ob, os.path.join(folder, name + ".glb"))
    RL.write_license(folder, name, f"Geometry: derived from Meshy AI output generated on the project owner's Meshy account "
                                   f"(meshy_keep {code}, {os.path.basename(find(stamp, True))}); rescaled to real size, decimated "
                                   f"({t0} -> {RL.tri_count(ob)} tris, detail baked back as a normal map), re-UV'd and re-materialed.")
    bpy.data.objects.remove(ob)
    if high:
        bpy.data.objects.remove(high)
    for g in list(bpy.data.node_groups):
        bpy.data.node_groups.remove(g)
    bpy.ops.import_scene.gltf(filepath=os.path.join(folder, name + ".glb"))
    new = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    orig.hide_render = False
    RL.render_view([orig, fig], os.path.join(gate, f"{code}_{name}_A_meshy.jpg"), res=(640, 480))
    RL.render_view(new + [fig], os.path.join(gate, f"{code}_{name}_B_refined.jpg"), res=(640, 480))
    with open(os.path.join(WORK, "stats_b.txt"), "a") as f:
        mn2, mx2 = RL.bbox_of(new)
        f.write(f"{code}_{name}\t{sum(RL.tri_count(o) for o in new)}\t{tex}\t{tuple(round(x, 1) for x in (mx2 - mn2))}\n")
    shutil.rmtree(tmp, ignore_errors=True)


for c in (CODES or list(B)):
    try:
        process(c)
    except Exception as e:
        import traceback
        traceback.print_exc()
        print("FAILED", c, e, flush=True)
print("DONE")
