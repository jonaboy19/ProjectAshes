r"""Tier-A hero head builder (skill ashes-hero-character).

Input : a MakeHuman character on the UAL skeleton (kingdom/assets/generated/characters/player_young.glb).
Output: <out>/hero_head_tier_a.glb  - skinned to the SAME UAL bone names (Head / neck_01 / spine_03), MakeHuman rest:
          FaceSkin   head+neck skin, Catmull-Clark x1, own 'Face' UV (1024 baked albedo with AO), vertex colour
                     R = flush (nose / cheeks / ears / lips), G = cavity AO, B = lip mask;
                     shape keys Blink_L, Blink_R, Smile, Jaw_Open, Brow_Up
          Eyes       two UV spheres (iris at the +front pole, UV radius 0.5 = limbus) for hero_eye.gdshader
          Lashes     upper-lid alpha cards; Brows: alpha cards on the brow ridge
          HairCap    scalp shell (hair base colour) + HairCards: 3 layers of curved alpha cards (UV.y root->tip)
        <out>/hero_face_albedo.png (1024), <out>/hero_hair_strands.png (512), <out>/hero_lash_brow.png (256)
Godot side: scripts/actors/hero_tier_a.gd retargets the MH rest onto the hero's G6 skeleton at load (no bone changes).

tools/external/blender.sh tools/blender/hero_tier_a/build_head.py -- <player_young.glb> <out_dir> [--preview]
"""
import bpy, bmesh, sys, os, math, random
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
PREVIEW = "--preview" in argv
os.makedirs(OUT, exist_ok=True)
random.seed(7)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=SRC)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
body = max([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
for o in list(bpy.data.objects):
    if o.type == "MESH" and o != body:
        bpy.data.objects.remove(o)
atlas_img = None
for n in body.data.materials[0].node_tree.nodes:
    if n.type == "TEX_IMAGE" and "albedo" in n.image.name.lower():
        atlas_img = n.image
print("ATLAS", atlas_img.name if atlas_img else None, atlas_img.size[:] if atlas_img else None)

HEAD_GROUPS = ("Head", "neck_01")
gi = {g.index: g.name for g in body.vertex_groups}
me = body.data


def hw(v):
    return sum(g.weight for g in v.groups if gi[g.group] in HEAD_GROUPS)


# ---- 1. split: skin faces of head + neck, eyes, MH hair strands -------------------------------------------------
# glTF splits vertices at UV seams: weld first so the skin is one connected surface (UVs stay per-loop)
bm0 = bmesh.new()
bm0.from_mesh(me)
bmesh.ops.remove_doubles(bm0, verts=bm0.verts, dist=0.0002)
bm0.to_mesh(me)
bm0.free()
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
headv = {v.index: hw(me.vertices[v.index]) for v in bm.verts}
seen, comps = set(), []
for v in bm.verts:
    if v.index in seen or headv[v.index] < 0.5:
        continue
    st, comp = [v], []
    seen.add(v.index)
    while st:
        a = st.pop(); comp.append(a)
        for e in a.link_edges:
            b = e.other_vert(a)
            if b.index not in seen and headv[b.index] > 0.0:
                seen.add(b.index); st.append(b)
    comps.append(comp)
comps.sort(key=len, reverse=True)
skin_seed = comps[0]                       # face/head skin (largest component)
# MakeHuman has NO skin behind the face (the hair proxy covers it): its hair-cap component is our skull/scalp shell
def _ext(c):
    return (max(v.co.y for v in c), max(v.co.z for v in c))
cap_comp = max([c for c in comps[1:] if len(c) > 100 and _ext(c)[0] > -0.12], key=len)
cap_ids = {v.index for v in cap_comp}
cbm = bm.copy()
cbm.verts.ensure_lookup_table()
bmesh.ops.delete(cbm, geom=[f for f in cbm.faces if not all(v.index in cap_ids for v in f.verts)], context="FACES")
bmesh.ops.delete(cbm, geom=[v for v in cbm.verts if not v.link_faces], context="VERTS")
if cbm.verts.layers.deform.active is not None:
    cbm.verts.layers.deform.remove(cbm.verts.layers.deform.active)
cap = bpy.data.objects.new("HairCap", bpy.data.meshes.new("HairCap"))
cbm.to_mesh(cap.data)
cbm.free()
bpy.context.scene.collection.objects.link(cap)
print("CAP verts", len(cap.data.vertices))
eyes = []
for c in comps:
    pts = [v.co for v in c]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = mx - mn
    if 40 <= len(c) <= 80 and size.x < 0.05 and size.z < 0.05 and mn.y < -0.2:
        eyes.append(((mn + mx) * 0.5, max(size.x, size.z) * 0.5))
# two eyeballs: the larger of each side's pair (cornea + ball overlap)
eye_l = max([e for e in eyes if e[0].x > 0], key=lambda e: e[1])
eye_r = max([e for e in eyes if e[0].x < 0], key=lambda e: e[1])
print("EYES", eye_l, eye_r)
# skin = connected skin component grown through the whole body, cut where head+neck weight < 0.35
skin_ids = set()
st = list(skin_seed)
for v in st:
    skin_ids.add(v.index)
while st:
    a = st.pop()
    for e in a.link_edges:
        b = e.other_vert(a)
        if b.index not in skin_ids and headv[b.index] >= 0.35:
            skin_ids.add(b.index); st.append(b)
del_faces = [f for f in bm.faces if not all(v.index in skin_ids for v in f.verts)]
bmesh.ops.delete(bm, geom=del_faces, context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
face = body.copy()
face.data = me.copy()
face.name = "FaceSkin"
bpy.context.scene.collection.objects.link(face)
bm.to_mesh(face.data)
bm.free()
bpy.data.objects.remove(body)
print("FACE verts", len(face.data.vertices), "faces", len(face.data.polygons))

# ---- 2. smooth: Catmull-Clark x1 (keeps weights + atlas UV) ------------------------------------------------------
bpy.context.view_layer.objects.active = face
face.select_set(True)
sub = face.modifiers.new("sub", "SUBSURF")
sub.levels = 1
sub.render_levels = 1
sub.uv_smooth = "PRESERVE_BOUNDARIES"
# move the subsurf above the armature modifier so it can be applied
while face.modifiers.find("sub") > 0:
    bpy.ops.object.modifier_move_up(modifier="sub")
bpy.ops.object.modifier_apply(modifier="sub")
dec = face.modifiers.new("dec", "DECIMATE")       # CC on MH triangles x6 -> collapse back to ~5k tris (mobile budget)
dec.ratio = 0.5
while face.modifiers.find("dec") > 0:
    bpy.ops.object.modifier_move_up(modifier="dec")
bpy.ops.object.modifier_apply(modifier="dec")
me = face.data
gi = {g.index: g.name for g in face.vertex_groups}
M = face.matrix_world
P = [M @ v.co for v in me.vertices]
hb = arm.data.bones["Head"]
head_pos = arm.matrix_world @ hb.head_local
ec = (eye_l[0] + eye_r[0]) * 0.5            # mid-eye point (object space = world here)
er = (eye_l[1] + eye_r[1]) * 0.5
front_y = min(p.y for p in P)                 # nose tip y (most forward)
nose_tip = min(P, key=lambda p: p.y)
print("NOSE", nose_tip, "EC", ec, "ER", er)

# ---- 3. vertex colour masks: R flush, G cavity, B lips -------------------------------------------------------------
vc = me.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
mouth = Vector((0.0, nose_tip.y + 0.012, nose_tip.z - 0.045))
def gauss(d, s):
    return math.exp(-(d * d) / (2 * s * s))
lip_vals = {}
for poly in me.polygons:
    for li in poly.loop_indices:
        vi = me.loops[li].vertex_index
        p = P[vi]
        flush = 0.0
        flush += 0.9 * gauss((p - nose_tip).length, 0.014)                                    # nose tip
        for sx in (-1, 1):
            cheek = Vector((sx * 0.042, nose_tip.y + 0.03, nose_tip.z - 0.005))
            flush += 0.7 * gauss((p - cheek).length, 0.018)
            ear = Vector((sx * 0.075, head_pos.y + 0.005, ec.z - 0.01))
            flush += 0.8 * gauss((Vector((p.x, p.y, p.z)) - ear).length, 0.022) * (1.0 if abs(p.x) > 0.06 else 0.0)
        lip = gauss(abs(p.x) / 1.6, 0.017) * gauss(p.z - mouth.z, 0.006) * (1.0 if p.y < mouth.y + 0.01 else 0.0)
        flush = min(1.0, flush + 0.3 * lip)
        vc.data[li].color = (flush, 1.0, min(1.0, lip * 1.4), 1.0)

# ---- 4. shape keys: blink L/R, smile, jaw open, brow up ------------------------------------------------------------
face.shape_key_add(name="Basis")
def key(name, fn):
    k = face.shape_key_add(name=name, from_mix=False)
    for i, v in enumerate(me.vertices):
        d = fn(P[i])
        if d is not None:
            k.data[i].co = v.co + d
for side, (c, r) in (("L", eye_l), ("R", eye_r)):
    def blink(p, c=c, r=r):
        q = p - c
        if abs(q.x) > r * 1.55 or q.z < -r * 0.05 or q.z > r * 1.5 or q.y > 0.004:
            return None
        fx = max(0.0, 1.0 - (abs(q.x) / (r * 1.55)) ** 2)
        fz = max(0.0, 1.0 - max(0.0, q.z - r * 0.7) / (r * 0.8))
        # slide the upper lid down over the ball: target height just below the eye centre, kept on a sphere r*1.06
        tz = -r * 0.12
        nz = q.z + (tz - q.z) * fx * fz
        ny = -math.sqrt(max(0.0, (r * 1.08) ** 2 - q.x * q.x - nz * nz))
        tgt = Vector((q.x, min(q.y, ny) if fx * fz > 0.5 else q.y + (ny - q.y) * fx * fz * 0.6, nz))
        return (tgt - q) * (fx * fz)
    key("Blink_" + side, blink)
def smile(p):
    q = p - mouth
    if q.y > 0.02 or abs(q.z) > 0.03:
        return None
    w = gauss(abs(q.x) - 0.024, 0.012) * gauss(q.z, 0.014)
    return Vector((0.006 * (1 if q.x > 0 else -1), 0.003, 0.005)) * w
key("Smile", smile)
jaw_pivot = Vector((0.0, head_pos.y - 0.01, mouth.z + 0.02))
def jaw(p):
    if p.z > mouth.z - 0.002 or p.y > head_pos.y + 0.02:
        return None
    w = min(1.0, (mouth.z - 0.002 - p.z) / 0.012) * gauss(max(0.0, abs(p.x) - 0.03), 0.02)
    rot = Matrix.Rotation(math.radians(9.0) * w, 3, "X")
    q = p - jaw_pivot
    return (rot @ q) - q
key("Jaw_Open", jaw)
def brow(p):
    q = p - ec
    if q.z < er * 0.9 or q.z > 0.06 or q.y > 0.01:
        return None
    return Vector((0, 0, 0.004)) * gauss(abs(q.x) - 0.035, 0.025) * gauss(q.z - 0.025, 0.015)
key("Brow_Up", brow)

# ---- 5. new Face UV + baked albedo (atlas -> 1024) * AO --------------------------------------------------------
atlas_uv = me.uv_layers[0].name
me.uv_layers.new(name="Face")
me.uv_layers.active = me.uv_layers["Face"]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=0.01, scale_to_bounds=True)
bpy.ops.object.mode_set(mode="OBJECT")
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 64
img_alb = bpy.data.images.new("hero_face_albedo", 1024, 1024)
img_ao = bpy.data.images.new("hero_face_ao", 1024, 1024)
mat = bpy.data.materials.new("FaceBake")
mat.use_nodes = True
nt = mat.node_tree
for n in list(nt.nodes):
    nt.nodes.remove(n)
uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = atlas_uv
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = atlas_img
nt.links.new(uvn.outputs[0], tex.inputs[0])
em = nt.nodes.new("ShaderNodeEmission")
nt.links.new(tex.outputs[0], em.inputs[0])
outn = nt.nodes.new("ShaderNodeOutputMaterial")
nt.links.new(em.outputs[0], outn.inputs[0])
tgt = nt.nodes.new("ShaderNodeTexImage"); tgt.image = img_alb
nt.nodes.active = tgt
face.data.materials.clear()
face.data.materials.append(mat)
bpy.ops.object.select_all(action="DESELECT")
face.select_set(True)
bpy.context.view_layer.objects.active = face
# bake with the face in rest (armature modifier off)
for m in face.modifiers:
    m.show_render = False
    m.show_viewport = False
sc.render.bake.margin = 8
bpy.ops.object.bake(type="EMIT", uv_layer="Face")
tgt.image = img_ao
nt.nodes.active = tgt
sc.cycles.samples = 128
bpy.ops.object.bake(type="AO", uv_layer="Face")
for img, nm in ((img_alb, "hero_face_albedo_raw.png"), (img_ao, "hero_face_ao.png")):
    img.filepath_raw = os.path.join(OUT, nm)
    img.file_format = "PNG"
    img.save()
for m in face.modifiers:
    m.show_render = True
    m.show_viewport = True
face.data.materials.clear()
fm = bpy.data.materials.new("HeroFace")
face.data.materials.append(fm)
# remove the atlas UV so the export has one UV (Face) -> Godot UV
me.uv_layers.remove(me.uv_layers[atlas_uv])

# ---- helpers for parts bound to the Head bone ---------------------------------------------------------------------
bvh = BVHTree.FromObject(face, bpy.context.evaluated_depsgraph_get())
bvh_cap = BVHTree.FromObject(cap, bpy.context.evaluated_depsgraph_get())
def bind_head(ob, w=1.0):
    vg = ob.vertex_groups.new(name="Head")
    vg.add(list(range(len(ob.data.vertices))), w, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    ob.parent = arm
def new_obj(name, verts, faces, uvs=None, mat_name=None):
    m = bpy.data.meshes.new(name)
    m.from_pydata([tuple(v) for v in verts], [], faces)
    if uvs:
        ul = m.uv_layers.new(name="UV")
        for poly in m.polygons:
            for li in poly.loop_indices:
                ul.data[li].uv = uvs[m.loops[li].vertex_index]
    m.update()
    ob = bpy.data.objects.new(name, m)
    bpy.context.scene.collection.objects.link(ob)
    m.materials.append(bpy.data.materials.new(mat_name or name))
    bind_head(ob)
    return ob
def surf(p, d):
    hit = bvh.ray_cast(p - d * 0.2, d, 0.4)
    return hit[0], hit[1]

# ---- 6. eyes: UV spheres, iris at the front (-Y) pole ------------------------------------------------------------
ev, ef, euv = [], [], []
for c, r in (eye_l, eye_r):
    base = len(ev)
    R, S = 10, 16
    for i in range(R + 1):
        th = math.pi * i / R               # 0 = front pole
        for j in range(S):
            ph = 2 * math.pi * j / S
            d = Vector((math.sin(th) * math.cos(ph), -math.cos(th), math.sin(th) * math.sin(ph)))
            ev.append(c + Vector((0, r * 0.2, 0)) + d * r * 0.85)   # recessed a little behind the lids
            rr = th / math.pi                 # 0 at the iris centre, 1 at the back
            euv.append((0.5 + 0.5 * rr * math.cos(ph), 0.5 + 0.5 * rr * math.sin(ph)))
    for i in range(R):
        for j in range(S):
            a = base + i * S + j; b = base + i * S + (j + 1) % S
            ef.append((a, a + S, b + S, b) if True else None)
eyes_ob = new_obj("Eyes", ev, ef, euv, "HeroEye")

# ---- 7. lashes + brows: alpha cards laid on the skin --------------------------------------------------------------
lv, lf, luv = [], [], []
def strip(points, normals, width, v0, v1, lift):
    base = len(lv)
    n = len(points)
    for i, (p, nrm) in enumerate(zip(points, normals)):
        u = i / (n - 1)
        lv.append(p); luv.append((u, v0))
        lv.append(p + nrm * width + Vector((0, 0, lift))); luv.append((u, v1))
    for i in range(n - 1):
        a = base + 2 * i
        lf.append((a, a + 2, a + 3, a + 1))
for sx, (c, r) in ((1, eye_l), (-1, eye_r)):
    pts, nr = [], []
    for k in range(9):
        a = math.radians(-70 + 140 * k / 8)
        q = c + Vector((math.sin(a) * r * 1.08 * sx, -math.cos(a) * r * 0.55 - r * 0.62, r * 0.42 + math.cos(a) * r * 0.32))
        pts.append(q)
        nr.append(Vector((math.sin(a) * 0.25 * sx, -0.85, 0.45)).normalized())
    strip(pts, nr, 0.0075, 0.0, 0.5, 0.0)            # lashes: top half of the lash/brow texture
    bp, bn = [], []
    for k in range(8):
        x = sx * (0.012 + 0.048 * k / 7)
        z = c.z + r * 1.05 + 0.007 * math.sin(math.pi * (k / 7) * 0.9) - 0.004 * (k / 7)
        hit, nrm = surf(Vector((x, c.y - 0.06, z)), Vector((0, 1, 0)))
        if hit is None:
            hit, nrm = Vector((x, c.y - 0.02, z)), Vector((0, -1, 0))
        bp.append(hit + nrm * 0.0012)
        bn.append(Vector((0, 0, 1)).cross(Vector((sx, 0, 0))).normalized() * 0 + Vector((0, -0.3, 1)).normalized())
    strip(bp, bn, 0.0095 if True else 0, 0.5, 1.0, 0.0)  # brows: bottom half
lash_ob = new_obj("LashesBrows", lv, lf, luv, "HeroLashBrow")

# ---- 8. hair: scalp cap + 3 layers of curved cards ---------------------------------------------------------------
crown = Vector((0.0, head_pos.y + 0.01, ec.z + 0.105))
hair_line_z = ec.z + r * 0 + 0.045                     # forehead hairline above the brows
def on_scalp(d):
    o = crown - Vector((0, 0, 0.03))
    hit, nrm, _, _ = bvh_cap.ray_cast(o + d * 0.3, -d, 0.4)
    if hit is not None and nrm.dot(d) < 0:
        nrm = -nrm
    return hit, nrm
hv, hf, huv = [], [], []
cards = 0
skull_c = Vector((0.0, head_pos.y - 0.01, ec.z + 0.015))
def card(root, nrm, flow, length, width, layer, uoff):
    global cards
    side = flow.cross(nrm).normalized()
    base = len(hv)
    segs = 4
    for s in range(segs + 1):
        t = s / segs
        # curve: start along the scalp, then fall with gravity, lifted off the surface by layer
        p = root + flow * length * t + Vector((0, 0, -0.35 * length * t * t))
        # comb onto the skull: snap to the cap surface + a per-layer offset (roots -> 80 %), the tips fall free
        off = 0.0025 + 0.0035 * layer + 0.002 * math.sin(t * math.pi)
        q = p - skull_c
        hit, hn, _, _ = bvh_cap.ray_cast(skull_c + q.normalized() * 0.3, -q.normalized(), 0.4)
        if hit is not None:
            if hn.dot(q) < 0:
                hn = -hn
            if t <= 0.8 or (p - skull_c).length < (hit - skull_c).length + off:
                p = hit + hn * off
        w = width * (1.0 - 0.55 * t)
        hv.append(p - side * w * 0.5); huv.append((uoff, t))
        hv.append(p + side * w * 0.5); huv.append((uoff + 0.25, t))
    for s in range(segs):
        a = base + 2 * s
        hf.append((a, a + 2, a + 3, a + 1))
    cards += 1
for layer, (n, ln0, ln1, wd) in enumerate(((90, 0.06, 0.09, 0.026), (80, 0.07, 0.11, 0.024), (50, 0.06, 0.1, 0.02))):
    k = 0; tries = 0
    while k < n and tries < 4000:
        tries += 1
        th = random.uniform(0, math.pi * 0.62); ph = random.uniform(0, 2 * math.pi)
        d = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
        hit, nrm = on_scalp(d)
        if hit is None:
            continue
        if hit.y < ec.y + 0.03 and hit.z < hair_line_z:          # keep the forehead + face clear
            continue
        if abs(hit.x) > 0.06 and hit.z < ec.z + 0.005 and hit.y < head_pos.y + 0.02:   # leave the ears visible
            continue
        if hit.z < ec.z - 0.03:                                  # nape line
            continue
        out = (hit - crown); out.z = 0
        flow = (out.normalized() * 0.75 + Vector((0, 0, -0.6))).normalized() if out.length > 0.005 else Vector((0, 0.3, -1)).normalized()
        if hit.y < ec.y + 0.05:                                   # fringe falls forward-down and sideways
            flow = Vector((0.8, -0.35, -0.55)).normalized()       # swept to the hero's left, clear of the eyes
        flow = (flow - nrm * flow.dot(nrm)).normalized()
        card(hit, nrm, flow, random.uniform(ln0, ln1) * (0.55 if hit.y < ec.y + 0.05 else 1.0), wd, layer, random.choice((0.0, 0.25, 0.5, 0.75)))
        k += 1
hair_ob = new_obj("HairCards", hv, hf, huv, "HeroHair")
# scalp cap: the MH hair-cap shell, smoothed once, hair base colour (hides the open back of the head)
for v in cap.data.vertices:
    v.co += v.normal * 0.001
cap.data.materials.clear()
cap.data.materials.append(bpy.data.materials.new("HeroHairCap"))
bind_head(cap)
print("CARDS", cards)

# ---- 9. export ---------------------------------------------------------------------------------------------------
for o in bpy.data.objects:
    o.select_set(o.type in ("MESH", "ARMATURE"))
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
print("TRIS total", tris, {o.name: sum(len(p.vertices) - 2 for p in o.data.polygons) for o in bpy.data.objects if o.type == "MESH"})
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hero_head_tier_a.glb"), export_format="GLB", use_selection=True,
                          export_animations=False, export_morph=True, export_skins=True, export_materials="PLACEHOLDER",
                          export_apply=False)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "hero_head_tier_a.blend"))
print("DONE")
