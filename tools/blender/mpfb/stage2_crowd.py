"""MPFB pilot stage 2 (CHARACTER_PLAN.md steps 3-4): game-ready crowd body from build_body.py.
  1. build the MPFB human (build_body.py preset, no export)
  2. clothing look: the tunic's own texture is replaced by undyed brown wool (no mail panel) with worn grime: hem dirt,
     sweat darkening under the arms and at the collar; pants/boots get mud toward the feet
  3. hidden body faces under the clothes removed (MPFB mask modifiers applied), helper geometry dropped
  4. bound to the EXACT Quaternius UAL skeleton (tools/meshy/armored_rig method): the MPFB rig is posed bone by bone into the
     UAL rest directions, the mesh baked in that pose, and the UAL armature fitted by translation only, so rest rotations are
     bit-identical to UAL and every UAL / Mixamo-retargeted clip plays unchanged (bone names already match; Root->root,
     head->Head; leaf bones come with the UAL armature)
  5. decimated per part to the crowd budget (LOD0 ~8k; the head is protected), base colour baked to one 1K texture per part
  6. GLB: <out>.glb (LOD0). Godot generates LOD1/2 (auto LOD on import).
Usage: blender -b --python tools/blender/mpfb/stage2_crowd.py -- <out.glb> [--preset villager_man] [--budget 8000] [--preview p.png]
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0]
BUDGET = int(argv[argv.index("--budget") + 1]) if "--budget" in argv else 8000
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else ""
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
UAL = os.path.join(REPO, "kingdom", "assets", "incoming", "quaternius", "universal-animation-library", "Unreal-Godot", "UAL1_Standard.glb")

# ---- 1. build --------------------------------------------------------------------------------------------------------
os.environ["MPFB_NO_EXPORT"] = "1"
exec(compile(open(os.path.join(HERE, "build_body.py"), encoding="utf-8").read(), "build_body.py", "exec"))
sc = bpy.context.scene
RIG = [o for o in sc.objects if o.type == "ARMATURE"][0]
MESHES = [o for o in sc.objects if o.type == "MESH"]
BODY = [o for o in MESHES if o.name == "MPFB_" + PRESET][0]


def part(o):
    n = o.name.lower()
    for k in ("tunic", "pants", "boots", "eyebrow", "short", "hair", "low-poly", "eye"):
        if k in n:
            return {"short": "hair", "low-poly": "eyes", "eye": "eyes"}.get(k, k)
    return "body"


# ---- 2. clothing look ------------------------------------------------------------------------------------------------
def grime_material(o, base_rgb=None, keep_tex=True, hem=0.62, mud=0.0, sweat=True):
    """Principled material: base = the part's own texture (or a flat wool colour) x procedural wool noise x grime masks.
    Masks use object-space Z (metres, feet at 0): hem dirt below `hem`, mud below `mud`, sweat at armpit/collar height."""
    src = o.data.materials[0] if o.data.materials else None
    tex_img = None
    if src and src.use_nodes and keep_tex:
        for nd in src.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image and "normal" not in nd.image.name.lower():
                tex_img = nd.image
                break
    m = bpy.data.materials.new(o.name + "_worn")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs[0])
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 160.0
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    blot = nt.nodes.new("ShaderNodeTexNoise")
    blot.inputs["Scale"].default_value = 9.0
    blot.inputs["Detail"].default_value = 3.0
    nt.links.new(tc.outputs["Object"], blot.inputs["Vector"])
    if tex_img is not None:
        base = nt.nodes.new("ShaderNodeTexImage")
        base.image = tex_img
        base_out = base.outputs["Color"]
    else:
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*base_rgb, 1.0)
        base_out = rgb.outputs[0]
    # wool fibre variation
    fib = nt.nodes.new("ShaderNodeMapRange")
    fib.inputs["To Min"].default_value = 0.72
    fib.inputs["To Max"].default_value = 1.06
    nt.links.new(noise.outputs["Fac"], fib.inputs["Value"])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(base_out, mul.inputs[6])
    nt.links.new(fib.outputs["Result"], mul.inputs[7])
    out = mul.outputs[2]
    # dirt: hem (below `hem` m) + blotches, darker and browner
    def darken(col_in, mask_out, rgb_dirt, strength):
        mx = nt.nodes.new("ShaderNodeMix")
        mx.data_type = "RGBA"
        mx.blend_type = "MULTIPLY"
        sc_ = nt.nodes.new("ShaderNodeMath")
        sc_.operation = "MULTIPLY"
        sc_.inputs[1].default_value = strength
        nt.links.new(mask_out, sc_.inputs[0])
        nt.links.new(sc_.outputs[0], mx.inputs["Factor"])
        nt.links.new(col_in, mx.inputs[6])
        mx.inputs[7].default_value = (*rgb_dirt, 1.0)
        return mx.outputs[2]
    hm = nt.nodes.new("ShaderNodeMapRange")
    hm.inputs["From Min"].default_value = hem + 0.18
    hm.inputs["From Max"].default_value = hem - 0.05
    nt.links.new(sep.outputs["Z"], hm.inputs["Value"])
    hb = nt.nodes.new("ShaderNodeMath")
    hb.operation = "MULTIPLY"
    nt.links.new(hm.outputs["Result"], hb.inputs[0])
    bl = nt.nodes.new("ShaderNodeMapRange")
    bl.inputs["From Min"].default_value = 0.35
    bl.inputs["From Max"].default_value = 0.7
    bl.inputs["To Min"].default_value = 0.55
    nt.links.new(blot.outputs["Fac"], bl.inputs["Value"])
    nt.links.new(bl.outputs["Result"], hb.inputs[1])
    out = darken(out, hb.outputs[0], (0.30, 0.24, 0.17), 1.0)
    if mud > 0.0:
        md = nt.nodes.new("ShaderNodeMapRange")
        md.inputs["From Min"].default_value = mud
        md.inputs["From Max"].default_value = 0.02
        nt.links.new(sep.outputs["Z"], md.inputs["Value"])
        out = darken(out, md.outputs["Result"], (0.30, 0.24, 0.17), 0.9)
    if sweat:
        # a band at armpit height (about 1.25-1.40 m on a 1.78 m man) and the collar
        sw = nt.nodes.new("ShaderNodeMapRange")
        sw.interpolation_type = "SMOOTHSTEP"
        sw.inputs["From Min"].default_value = 1.18
        sw.inputs["From Max"].default_value = 1.32
        nt.links.new(sep.outputs["Z"], sw.inputs["Value"])
        sw2 = nt.nodes.new("ShaderNodeMapRange")
        sw2.inputs["From Min"].default_value = 1.32
        sw2.inputs["From Max"].default_value = 1.42
        sw2.inputs["To Min"].default_value = 1.0
        sw2.inputs["To Max"].default_value = 0.0
        nt.links.new(sep.outputs["Z"], sw2.inputs["Value"])
        band = nt.nodes.new("ShaderNodeMath")
        band.operation = "MULTIPLY"
        nt.links.new(sw.outputs["Result"], band.inputs[0])
        nt.links.new(sw2.outputs["Result"], band.inputs[1])
        out = darken(out, band.outputs[0], (0.6, 0.55, 0.48), 0.5)
    nt.links.new(out, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    o.data.materials.clear()
    o.data.materials.append(m)
    for poly in o.data.polygons:
        poly.material_index = 0      # one material now: faces of the old mail / sleeve slots must not keep a stale index


for o in MESHES:
    p = part(o)
    if p == "tunic":
        grime_material(o, base_rgb=(0.205, 0.150, 0.098), keep_tex=False, hem=0.62)     # undyed brown wool, no mail panel
    elif p == "pants":
        grime_material(o, keep_tex=True, hem=0.25, mud=0.35, sweat=False)
    elif p == "boots":
        grime_material(o, keep_tex=True, hem=0.12, mud=0.25, sweat=False)

# ---- 3. apply masks (hidden body faces) -------------------------------------------------------------------------------
for o in MESHES:
    bpy.context.view_layer.objects.active = o
    if o.data.shape_keys:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)     # the MPFB targets, baked at their current values
    for md in list(o.modifiers):
        if md.type in ("MASK", "SUBSURF") or (md.type not in ("ARMATURE",)):
            try:
                if md.type == "SUBSURF":
                    o.modifiers.remove(md)
                else:
                    bpy.ops.object.modifier_apply(modifier=md.name)
            except RuntimeError as e:
                print("MPFB2 modifier", o.name, md.name, e)

# ---- 4. bind to the exact UAL skeleton ---------------------------------------------------------------------------------
before = set(bpy.data.objects)
ba = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=UAL)
new = [o for o in bpy.data.objects if o not in before]
FINAL = [o for o in new if o.type == "ARMATURE"][0]
for o in new:
    if o is not FINAL:
        bpy.data.objects.remove(o, do_unlink=True)
for a in list(bpy.data.actions):
    if a not in ba:
        bpy.data.actions.remove(a)
if FINAL.animation_data:
    FINAL.animation_data_clear()
U = {b.name: (FINAL.matrix_world @ b.head_local, FINAL.matrix_world @ b.tail_local) for b in FINAL.data.bones}
NAMEMAP = {"Root": "root", "head": "Head"}
order = []
def walk(b):
    order.append(b.name)
    for c in b.children:
        walk(c)
for b in RIG.data.bones:
    if b.parent is None:
        walk(b)
RIG.data.pose_position = "POSE"
bpy.context.view_layer.objects.active = RIG
for n in order:
    un = NAMEMAP.get(n, n)
    if un not in U or n in ("Root", "pelvis"):
        continue
    pb = RIG.pose.bones[n]
    bpy.context.view_layer.update()
    Mx = RIG.matrix_world @ pb.matrix
    cur = (Mx.to_3x3() @ Vector((0, 1, 0))).normalized()
    want = (U[un][1] - U[un][0]).normalized()
    q = cur.rotation_difference(want)
    h = Mx.to_translation()
    pb.matrix = RIG.matrix_world.inverted() @ (Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ Mx)
bpy.context.view_layer.update()
posed = {NAMEMAP.get(n, n): RIG.matrix_world @ RIG.pose.bones[n].head for n in order}
for o in MESHES:
    bpy.context.view_layer.objects.active = o
    arm_md = [m for m in o.modifiers if m.type == "ARMATURE"]
    if arm_md:
        bpy.ops.object.modifier_apply(modifier=arm_md[0].name)
    for vg in o.vertex_groups:
        if vg.name in NAMEMAP:
            vg.name = NAMEMAP[vg.name]
# scale so the pelvis matches UAL's, centre on it
kk = U["pelvis"][0].z / posed["pelvis"].z
off = Vector((U["pelvis"][0].x - posed["pelvis"].x * kk, U["pelvis"][0].y - posed["pelvis"].y * kk, 0.0))
S_ = Matrix.Translation(off) @ Matrix.Scale(kk, 4)
for o in MESHES:
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix()
    o.parent = None
    o.data.transform(S_)
fitp = {n: S_ @ v for n, v in posed.items()}
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = FINAL
FINAL.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
finv = FINAL.matrix_world.inverted()
for eb in FINAL.data.edit_bones:
    if eb.name in fitp and eb.parent is not None:
        v = eb.tail - eb.head
        h = finv @ fitp[eb.name]
        eb.head = h
        eb.tail = h + v          # translation only: rest orientation stays exactly UAL
bpy.ops.object.mode_set(mode="OBJECT")
bpy.data.objects.remove(RIG, do_unlink=True)
for o in MESHES:
    o.parent = FINAL
    o.matrix_parent_inverse = FINAL.matrix_world.inverted()
    md = o.modifiers.new("Armature", "ARMATURE")
    md.object = FINAL
FINAL.name = "Armature"
FINAL.data.name = "Armature"

# ---- 4b. hidden body faces: a body vertex whose outward normal ray hits a garment within OCCL_DIST is covered; faces with
# every vertex covered are deleted (no poke-through in the run / ladder / sit clips, and fewer tris to spend). The same for
# pants under the tunic.
from mathutils.bvhtree import BVHTree
OCCL_DIST = 0.06


def bvh_of(objs):
    bm_ = bmesh.new()
    for o in objs:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        me_ = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me_)
        tmp.free()
        bm_.from_mesh(me_)
        bpy.data.meshes.remove(me_)
    t = BVHTree.FromBMesh(bm_)
    bm_.free()
    return t


def cull(target, covers):
    if not covers:
        return 0
    tree = bvh_of(covers)
    bm_ = bmesh.new()
    bm_.from_mesh(target.data)
    mw = target.matrix_world
    hidden = set()
    keep_groups = {target.vertex_groups[n].index for n in target.vertex_groups.keys()
                   if n.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_", "Head", "neck_"))}
    dl = target.data.vertices
    for v in bm_.verts:
        if any(g.group in keep_groups and g.weight > 0.3 for g in dl[v.index].groups):
            continue                                       # hands, neck and head are never culled (sleeve ends, collar)
        p = mw @ v.co
        n = (mw.to_3x3() @ v.normal).normalized()
        hit = tree.ray_cast(p + n * 0.002, n, OCCL_DIST)
        if hit[0] is not None:
            hidden.add(v.index)
    dead = [f for f in bm_.faces if all(v.index in hidden for v in f.verts)]
    bmesh.ops.delete(bm_, geom=dead, context="FACES")
    bm_.to_mesh(target.data)
    bm_.free()
    return len(dead)


garments = [o for o in MESHES if part(o) in ("tunic", "pants", "boots")]
body_o = [o for o in MESHES if part(o) == "body"][0]
print("MPFB2 culled body faces", cull(body_o, garments))
for o in MESHES:
    if part(o) == "pants":
        print("MPFB2 culled pants faces", cull(o, [g for g in garments if part(g) in ("tunic", "boots")]))

# ---- 5. decimate + bake ------------------------------------------------------------------------------------------------
SHARE = {"body": 0.33, "tunic": 0.26, "pants": 0.10, "boots": 0.09, "hair": 0.13, "eyebrow": 0.02, "eyes": 0.03}


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


total0 = sum(tris(o) for o in MESHES)
for o in MESHES:
    t = tris(o)
    want = BUDGET * SHARE.get(part(o), 0.05)
    if t > want:
        bpy.context.view_layer.objects.active = o
        d = o.modifiers.new("Dec", "DECIMATE")
        d.ratio = max(want / t, 0.02)
        d.use_symmetry = part(o) == "body"       # garments are not mirror-symmetric: symmetric collapse tore holes in one sleeve
        d.symmetry_axis = "X"
        if part(o) == "body" and "Head" in o.vertex_groups:
            # two passes so the face keeps its silhouette: the body below the neck collapses hard (most of it is hidden
            # by clothes anyway), the head only to HEAD_TRIS
            hg = o.vertex_groups["Head"].index
            prot = {o.vertex_groups[n].index for n in o.vertex_groups.keys() if n.startswith(("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"))}
            gb = o.vertex_groups.new(name="DecBody")
            gh = o.vertex_groups.new(name="DecHead")
            nh = 0
            for v in o.data.vertices:
                w = 0.0
                for g in v.groups:
                    if g.group == hg or g.group in prot:
                        w = max(w, g.weight)
                if w < 0.3:
                    gb.add([v.index], 1.0, "REPLACE")
                else:
                    gh.add([v.index], 1.0, "REPLACE")
                    nh += 1
            head_t = int(t * nh / max(len(o.data.vertices), 1))
            HEAD_TRIS = int(want * 0.72)          # head + hands
            d.vertex_group = "DecBody"
            d.ratio = max((want - HEAD_TRIS) / max(t - head_t, 1), 0.02)
            d2 = o.modifiers.new("Dec2", "DECIMATE")
            d2.vertex_group = "DecHead"
            d2.ratio = min(max(HEAD_TRIS / max(head_t, 1), 0.05), 1.0)
            d2.use_symmetry = True
            d2.symmetry_axis = "X"
            while o.modifiers.find("Dec2") > 1:
                bpy.ops.object.modifier_move_up(modifier="Dec2")
        print("MPFB2 dec", o.name, "t", t, "want", int(want), "ratio", round(d.ratio, 3), "mods", [m.type for m in o.modifiers])
        while o.modifiers.find("Dec") > 0:
            bpy.ops.object.modifier_move_up(modifier="Dec")
        bpy.ops.object.modifier_apply(modifier="Dec")
        if "Dec2" in o.modifiers:
            while o.modifiers.find("Dec2") > 0:
                bpy.ops.object.modifier_move_up(modifier="Dec2")
            bpy.ops.object.modifier_apply(modifier="Dec2")
        print("MPFB2 after", o.name, tris(o))
total1 = sum(tris(o) for o in MESHES)
print("MPFB2 tris", total0, "->", total1, {o.name: tris(o) for o in MESHES})

sc.render.engine = "CYCLES"
sc.cycles.samples = 8
sc.cycles.device = "CPU"
for o in MESHES:
    if not o.data.materials or not o.data.uv_layers:
        continue
    if part(o) in ("hair", "eyebrow", "eyes"):
        # alpha-card parts keep their own texture (a diffuse bake drops the alpha: the brows became a dark band)
        src_img = None
        for nd in o.data.materials[0].node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image and "normal" not in nd.image.name.lower():
                src_img = nd.image
                break
        if src_img is not None:
            im2 = src_img.copy()
            im2.name = o.name + "_tex"
            if max(im2.size) > 1024:
                im2.scale(1024, 1024)
            im2.pack()
            nm = bpy.data.materials.new(o.name + "_game")
            nm.use_nodes = True
            b2 = nm.node_tree.nodes["Principled BSDF"]
            t2 = nm.node_tree.nodes.new("ShaderNodeTexImage")
            t2.image = im2
            nm.node_tree.links.new(t2.outputs["Color"], b2.inputs["Base Color"])
            nm.node_tree.links.new(t2.outputs["Alpha"], b2.inputs["Alpha"])
            b2.inputs["Roughness"].default_value = 0.7
            try:
                nm.surface_render_method = "DITHERED"
            except Exception:
                pass
            o.data.materials.clear()
            o.data.materials.append(nm)
            for poly in o.data.polygons:
                poly.material_index = 0
            print("MPFB2 kept texture", o.name)
            continue
    img = bpy.data.images.new(o.name + "_bc", 1024, 1024)
    m = o.data.materials[0]
    unique_uv = part(o) in ("tunic", "pants", "boots")
    if unique_uv:
        # MakeHuman garments mirror / overlap UV islands (both sleeves on one island, the mail panel shared): bake into a fresh
        # non-overlapping layout. The source texture keeps reading the original map (render-active), the bake writes the new one.
        src_uv = o.data.uv_layers.active.name
        o.data.uv_layers[src_uv].active_render = True
        nu = o.data.uv_layers.new(name="BakeUV")
        o.data.uv_layers.active = nu
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.01)
        bpy.ops.object.mode_set(mode="OBJECT")
        for nd in m.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and not nd.inputs["Vector"].is_linked:
                uvn = m.node_tree.nodes.new("ShaderNodeUVMap")
                uvn.uv_map = src_uv
                m.node_tree.links.new(uvn.outputs["UV"], nd.inputs["Vector"])
    nt = m.node_tree
    tn = nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    nt.nodes.active = tn
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    sc.render.bake.margin = 4
    try:
        bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"})
    except RuntimeError as e:
        print("MPFB2 bake", o.name, e)
        continue
    img.pack()
    if unique_uv:
        o.data.uv_layers.remove(o.data.uv_layers[src_uv])
        o.data.uv_layers["BakeUV"].active_render = True
    nm = bpy.data.materials.new(o.name + "_game")
    nm.use_nodes = True
    b2 = nm.node_tree.nodes["Principled BSDF"]
    t2 = nm.node_tree.nodes.new("ShaderNodeTexImage")
    t2.image = img
    nm.node_tree.links.new(t2.outputs["Color"], b2.inputs["Base Color"])
    b2.inputs["Roughness"].default_value = 0.82 if part(o) != "body" else 0.55
    b2.inputs["Metallic"].default_value = 0.0
    if part(o) in ("hair", "eyebrow"):
        nm.node_tree.links.new(t2.outputs["Alpha"], b2.inputs["Alpha"])
        nm.blend_method = "CLIP" if hasattr(nm, "blend_method") else nm.blend_method
    o.data.materials.clear()
    o.data.materials.append(nm)
    for poly in o.data.polygons:
        poly.material_index = 0
    print("MPFB2 baked", o.name)

if PREVIEW:
    sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    cam = bpy.data.objects.new("Cam2", bpy.data.cameras.new("Cam2"))
    sc.collection.objects.link(cam)
    cam.location = (1.4, -3.2, 1.0)
    cam.rotation_euler = (math.radians(86), 0, math.radians(24))
    cam.data.lens = 55
    sc.camera = cam
    sun = bpy.data.objects.new("Sun2", bpy.data.lights.new("Sun2", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(-30))
    sc.collection.objects.link(sun)
    sc.world = sc.world or bpy.data.worlds.new("W2")
    sc.world.color = (0.5, 0.52, 0.55)
    sc.render.resolution_x = 700
    sc.render.resolution_y = 1000
    sc.render.filepath = PREVIEW
    bpy.ops.render.render(write_still=True)

bpy.ops.object.select_all(action="DESELECT")
FINAL.select_set(True)
for o in MESHES:
    o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False, export_yup=True,
                          export_skins=True, export_apply=False, export_image_format="JPEG", export_jpeg_quality=88)
print("MPFB2_DONE", OUT, "tris", total1)
