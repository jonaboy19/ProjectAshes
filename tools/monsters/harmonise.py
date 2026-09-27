# Harmonise a CC0 low-poly animated monster with the painterly Rising Ashes creatures.
# Blender 5.2 headless:
#   blender -b --python tools/monsters/harmonise.py -- tools/monsters/specs/<name>.json
# Steps: import (FBX/glTF) -> drop props/eyes -> proportion tweak -> prune bones (<= 40)
# -> rename clips (idle/walk/run/attack/hit/death) -> real-world scale, feet at 0, face -Y like the wolf
# -> subdivide + decimate to LOD0 budget -> new UVs -> bake a hand-painted 512 px texture
# (palette or graded atlas colour, mottling, cavity AO, top light, foot-to-head gradient, optional
# Rift glow as an emissive texture) -> LOD1 (2.5k, 256 px) -> GLB (no Draco) + stats JSON.
import bpy, bmesh, sys, os, json, math, re
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshy", "creature_rig"))
from common import tris, world_bbox, decimate_to

spec = json.load(open(sys.argv[-1]))
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(REPO, spec["src"])
OUT = os.path.join(REPO, spec["out_dir"]); os.makedirs(OUT, exist_ok=True)
NAME = spec["name"]
MAX_BONES = spec.get("max_bones", 40)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---------- import ----------
before = set(bpy.data.objects); acts_before = set(bpy.data.actions)
if SRC.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=SRC, ignore_leaf_bones=True, automatic_bone_orientation=False)
else:
    sc.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=SRC)
objs = [o for o in bpy.data.objects if o not in before]
arm = [o for o in objs if o.type == 'ARMATURE'][0]
meshes = [o for o in objs if o.type == 'MESH']
print("FPS", sc.render.fps)
for o in list(meshes):
    if any(re.search(p, o.name) for p in spec.get("drop_meshes", [])) or (o.parent is None and not o.vertex_groups):
        meshes.remove(o); bpy.data.objects.remove(o)
objs = [o for o in bpy.data.objects if o in objs]
for o in list(objs):
    if o.type not in ('MESH', 'ARMATURE') and not o.children:
        bpy.data.objects.remove(o)
# join meshes
if len(meshes) > 1:
    for o in bpy.data.objects: o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
mesh = meshes[0]; mesh.name = NAME
if mesh.parent != arm:
    mw = mesh.matrix_world.copy(); mesh.parent = arm; mesh.matrix_world = mw
if not any(m.type == 'ARMATURE' for m in mesh.modifiers):
    mesh.modifiers.new("Armature", 'ARMATURE').object = arm
for m in mesh.modifiers:
    if m.type == 'ARMATURE': m.object = arm

# ---------- clips ----------
all_acts = [a for a in bpy.data.actions if a not in acts_before]
def find_act(key):
    if key is None: return None
    for a in all_acts:
        if a.name.split('|')[-1] == key: return a
    for a in all_acts:
        if a.name.split('|')[-1].lower().endswith(key.lower()): return a
    raise SystemExit("clip not found: %s in %s" % (key, [a.name for a in all_acts]))
clipmap = {k: find_act(v) for k, v in spec["clips"].items() if isinstance(v, str)}
aliases = {k: v["alias"] for k, v in spec["clips"].items() if isinstance(v, dict) and "alias" in v}

def act_fcurves(a):
    try:
        return list(a.fcurves)
    except Exception:
        out = []
        for layer in a.layers:
            for st in layer.strips:
                for slot in a.slots:
                    cb = st.channelbag(slot)
                    if cb: out += list(cb.fcurves)
        return out

def remove_bone_curves(a, bone):
    tag = 'pose.bones["%s"]' % bone
    try:
        for fc in [f for f in a.fcurves if f.data_path.startswith(tag)]: a.fcurves.remove(fc)
        return
    except Exception:
        pass
    for layer in a.layers:
        for st in layer.strips:
            for slot in a.slots:
                cb = st.channelbag(slot)
                if cb:
                    for fc in [f for f in cb.fcurves if f.data_path.startswith(tag)]: cb.fcurves.remove(fc)

def set_action(a, frame=None):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = a
    if a is not None and a.slots:
        try: ad.action_slot = a.slots[0]
        except Exception: pass
    if frame is not None: sc.frame_set(int(frame))
    bpy.context.view_layer.update()

# FBX clips also key the armature OBJECT (location/rotation/scale). Bake the idle value into the object
# and strip those object channels, so our scale/placement survives and every clip shares one root.
if clipmap.get("idle"):
    set_action(clipmap["idle"], clipmap["idle"].frame_range[0])
    keep_mw = arm.matrix_world.copy()
    def strip_obj_curves(a):
        def rm(coll):
            for fc in [f for f in coll if not f.data_path.startswith("pose.bones")]: coll.remove(fc)
        try:
            rm(a.fcurves); return
        except Exception: pass
        for layer in a.layers:
            for st in layer.strips:
                for slot in a.slots:
                    cb = st.channelbag(slot)
                    if cb: rm(cb.fcurves)
    for a in all_acts: strip_obj_curves(a)
    set_action(None); arm.matrix_world = keep_mw; bpy.context.view_layer.update()
    print("ARM", [round(v, 3) for v in arm.scale], [round(v, 3) for v in arm.rotation_euler])

# ---------- rest-pose mesh edits (eyes, proportions) ----------
arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
def mats_of(o): return [s.material.name if s.material else "" for s in o.material_slots]
if spec.get("delete_mats"):
    bm = bmesh.new(); bm.from_mesh(mesh.data)
    names = mats_of(mesh)
    kill = [f for f in bm.faces if any(re.fullmatch(p, names[f.material_index]) for p in spec["delete_mats"])]
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(mesh.data); bm.free()
if spec.get("delete_uv_boxes"):
    # delete faces whose atlas UV centre falls in any [u0,v0,u1,v1] box (googly eyes baked into atlas packs)
    bm = bmesh.new(); bm.from_mesh(mesh.data); uv = bm.loops.layers.uv.active
    kill = []
    for f in bm.faces:
        c = sum((l[uv].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
        if any(b[0] <= c.x <= b[2] and b[1] <= c.y <= b[3] for b in spec["delete_uv_boxes"]): kill.append(f)
    print("UVBOX delete faces", len(kill))
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(mesh.data); bm.free()

def descendants(bname):
    b = arm.data.bones[bname]; return [b.name] + [c.name for c in b.children_recursive]
if spec.get("delete_atlas_colors"):
    # delete faces (limited to a bone's vertex group) whose atlas colour matches one of the listed sRGB colours
    dac = spec["delete_atlas_colors"]
    img = None
    for s in mesh.material_slots:
        if s.material and s.material.use_nodes:
            n = next((n for n in s.material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None)
            if n: img = n.image; break
    W, Hh = img.size; px = list(img.pixels)
    def samp(u, v):
        x = min(W - 1, max(0, int((u % 1.0) * W))); y = min(Hh - 1, max(0, int((v % 1.0) * Hh)))
        i = (y * W + x) * 4; c = px[i:i + 3]
        return [((x_ ** (1 / 2.4)) * 1.055 - 0.055) if x_ > 0.0031308 else x_ * 12.92 for x_ in c]
    gi = {vg.index for vg in mesh.vertex_groups if vg.name in set(descendants(dac["bone"]))}
    bm = bmesh.new(); bm.from_mesh(mesh.data); uv = bm.loops.layers.uv.active; dl = bm.verts.layers.deform.active
    kill = []
    for f in bm.faces:
        if not all(any(g in gi and w > 0.5 for g, w in l.vert[dl].items()) for l in f.loops): continue
        c = sum((l[uv].uv for l in f.loops), Vector((0, 0))) / len(f.loops)
        col = samp(c.x, c.y)
        if any(sum((a - b) ** 2 for a, b in zip(col, t)) ** 0.5 < dac.get("tol", 0.12) for t in dac["colors"]): kill.append(f)
    print("COLKILL faces", len(kill))
    bmesh.ops.delete(bm, geom=kill, context='FACES')
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context='VERTS')
    bm.to_mesh(mesh.data); bm.free()
if spec.get("atlas_remap"):
    # recolour the source atlas in memory: [[src_srgb, dst_srgb], ...] (tolerance 0.1)
    def _lin(c): return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]
    imgs = {n.image for s in mesh.material_slots if s.material and s.material.use_nodes
            for n in s.material.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image}
    if spec.get("atlas_image"): imgs.add(bpy.data.images.load(os.path.join(REPO, spec["atlas_image"]), check_existing=True))
    for img in imgs:
        px = list(img.pixels); n = 0
        for i in range(0, len(px), 4):
            for src, dst in spec["atlas_remap"]:
                s = _lin(src)
                if sum((px[i + k] - s[k]) ** 2 for k in range(3)) ** 0.5 < 0.06:
                    d = _lin(dst); px[i:i + 3] = d; n += 1; break
        img.pixels = px; print("REMAP", img.name, n)
to_mesh = mesh.matrix_world.inverted() @ arm.matrix_world
for adj in spec.get("proportions", []):
    group = set(adj["groups"]) if adj.get("groups") else set(descendants(adj["bone"]))
    gidx = {vg.index for vg in mesh.vertex_groups if vg.name in group}
    piv = to_mesh @ arm.data.bones[adj["bone"]].head_local
    s = adj["scale"]; off = Vector(adj.get("offset", (0, 0, 0)))
    for v in mesh.data.vertices:
        tot = sum(g.weight for g in v.groups); w = sum(g.weight for g in v.groups if g.group in gidx)
        if tot <= 0 or w <= 0: continue
        w = min(1.0, w / tot)
        target = piv + (v.co - piv) * s + off
        v.co = v.co.lerp(target, w)
if spec.get("mesh_scale"):
    # non-uniform bulk/slim of the body in rest pose, about the armature origin (e.g. slim a cartoon belly)
    sx, sy, sz = spec["mesh_scale"]
    for v in mesh.data.vertices: v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))

# ---------- bone pruning (<= MAX_BONES) ----------
def weight_sums():
    s = {vg.name: 0.0 for vg in mesh.vertex_groups}
    idx = {vg.index: vg.name for vg in mesh.vertex_groups}
    for v in mesh.data.vertices:
        for g in v.groups: s[idx[g.group]] += g.weight
    return s
def merge_group(src, dst):
    vs = mesh.vertex_groups.get(src)
    if vs is None: return
    vd = mesh.vertex_groups.get(dst) or mesh.vertex_groups.new(name=dst)
    for v in mesh.data.vertices:
        for g in v.groups:
            if g.group == vs.index and g.weight > 0: vd.add([v.index], g.weight, 'ADD')
    mesh.vertex_groups.remove(vs)
removed = []
explicit = spec.get("prune_bones", [])
while True:
    bones = arm.data.bones
    if len(bones) <= MAX_BONES and not [b for b in explicit if b in bones]: break
    ws = weight_sums()
    cand = [b for b in bones if b.name in explicit] or [b for b in bones if not b.children and b.parent]
    victim = min(cand, key=lambda b: ws.get(b.name, 0.0))
    vname, pname = victim.name, victim.parent.name
    merge_group(vname, pname)
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects: o.select_set(o == arm)
    bpy.ops.object.mode_set(mode='EDIT')
    arm.data.edit_bones.remove(arm.data.edit_bones[vname])
    bpy.ops.object.mode_set(mode='OBJECT')
    for a in all_acts: remove_bone_curves(a, vname)
    removed.append(vname)
print("PRUNED", removed, "bones now", len(arm.data.bones))

# ---------- synthesise missing hit (short recoil) ----------
synth = []
def synth_clip(name, cfg):
    # Procedural clip for packs that lack it. Starts from the idle pose; per-bone local rotations and an
    # optional world-space root pivot/drop, driven by an amount curve "keys": [[seconds, amount], ...].
    from mathutils import Quaternion
    base = clipmap["idle"]
    set_action(base, base.frame_range[0])
    arm.data.pose_position = 'POSE'; bpy.context.view_layer.update()
    pose = {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.rotation_euler.copy(), pb.scale.copy()) for pb in arm.pose.bones}
    base_mn, _ = world_bbox([mesh], bpy.context.evaluated_depsgraph_get())
    root = cfg.get("root")
    if root:
        rpb = arm.pose.bones[root["bone"]]
        root_w = arm.matrix_world @ rpb.matrix
    a = bpy.data.actions.new(name)
    set_action(a)
    fps = sc.render.fps
    keys = cfg.get("keys", [[0, 0], [0.12, 1], [0.45, 0]])
    for t, amt in keys:
        f = 1 + round(fps * t)
        for pb in arm.pose.bones:
            loc, q, e, s = pose[pb.name]
            pb.location = loc; pb.rotation_quaternion = q; pb.rotation_euler = e; pb.scale = s
        bpy.context.view_layer.update()
        if root:
            piv = root_w.translation.copy()
            if root.get("pivot") == "ground": piv.z = base_mn.z
            R = Matrix.Rotation(math.radians(root["deg"]) * amt, 4, Vector(root.get("axis_world", (1, 0, 0))))
            drop = (piv.z - base_mn.z) * root.get("drop", 0.0) * amt
            M = Matrix.Translation(piv + Vector((0, 0, -drop))) @ R @ Matrix.Translation(-piv) @ root_w
            rpb.matrix = arm.matrix_world.inverted() @ M
            bpy.context.view_layer.update()
        for rb in cfg.get("bones", []):
            pb = arm.pose.bones.get(rb["bone"])
            if pb is None: continue
            ax = Vector(rb.get("axis", (1, 0, 0))); ang = math.radians(rb.get("deg", -14)) * amt
            if pb.rotation_mode == 'QUATERNION':
                pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(ax, ang)
            else:
                pb.rotation_euler = (pb.rotation_euler.to_matrix() @ Matrix.Rotation(ang, 3, ax)).to_euler(pb.rotation_mode)
        if root and cfg.get("ground"):
            bpy.context.view_layer.update()
            gmn, _ = world_bbox([mesh], bpy.context.evaluated_depsgraph_get())
            dz = base_mn.z - gmn.z
            if amt > 0 and abs(dz) > 1e-4:
                Mw = arm.matrix_world @ rpb.matrix
                rpb.matrix = arm.matrix_world.inverted() @ (Matrix.Translation((0, 0, dz)) @ Mw)
                bpy.context.view_layer.update()
        for pb in arm.pose.bones:
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion" if pb.rotation_mode == 'QUATERNION' else "rotation_euler", frame=f)
            pb.keyframe_insert("scale", frame=f)
    return a
for cname in ("hit", "death"):
    c = spec["clips"].get(cname)
    if isinstance(c, dict) and "synth" in c:
        clipmap[cname] = synth_clip(cname, c["synth"]); synth.append(cname); all_acts.append(clipmap[cname])

# ---------- alias clips (copy, same timing) ----------
for k, src in aliases.items():
    c = clipmap[src].copy(); clipmap[k] = c; all_acts.append(c)

# rename / drop
keep = set(clipmap.values())
for a in list(all_acts):
    if a not in keep:
        bpy.data.actions.remove(a)
for k, a in clipmap.items():
    a.name = k; a.use_fake_user = True

# ---------- scale, feet to 0, facing ----------
arm.data.pose_position = 'POSE'
set_action(clipmap["idle"], clipmap["idle"].frame_range[0])
arm.rotation_mode = 'XYZ'
arm.rotation_euler.z += math.radians(spec.get("yaw", 0))
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
mn, mx = world_bbox([mesh], dg)
axis = {"x": 0, "y": 1, "z": 2}[spec.get("measure", "z")]
cur = (mx - mn)[axis]
k = spec["size"] / cur
arm.scale = arm.scale * k
bpy.context.view_layer.update()
mn, mx = world_bbox([mesh], bpy.context.evaluated_depsgraph_get())
arm.location.x -= (mn.x + mx.x) / 2; arm.location.y -= (mn.y + mx.y) / 2
arm.location.z += spec.get("hover", 0.0) - mn.z
bpy.context.view_layer.update()
mn, mx = world_bbox([mesh], bpy.context.evaluated_depsgraph_get())
print("SIZE", [round(v, 3) for v in (mx - mn)], "minz", round(mn.z, 3))

# ---------- geometry budget ----------
arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
for o in bpy.data.objects: o.select_set(o == mesh)
bpy.context.view_layer.objects.active = mesh
t0 = tris(mesh)
lod0 = spec.get("lod0", 8000)
if spec.get("subdiv", 0):
    m = mesh.modifiers.new("sub", 'SUBSURF'); m.levels = spec["subdiv"]; m.render_levels = spec["subdiv"]
    m.quality = 3
    bpy.ops.object.modifier_move_to_index(modifier="sub", index=0)
    bpy.ops.object.modifier_apply(modifier="sub")
t1 = decimate_to(mesh, lod0)
bpy.ops.object.shade_smooth()
print("TRIS", t0, "->", t1)
# limit to 4 influences and normalise
bpy.ops.object.vertex_group_limit_total(group_select_mode='ALL', limit=4)
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

# ---------- UVs ----------
orig_uv = mesh.data.uv_layers.active.name if mesh.data.uv_layers else None
bake_uv = mesh.data.uv_layers.new(name="paint")
mesh.data.uv_layers.active = bake_uv
bpy.ops.object.mode_set(mode='EDIT'); bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.012, area_weight=0.0, correct_aspect=True, scale_to_bounds=True)
bpy.ops.uv.pack_islands(margin=0.008, rotate=True)
bpy.ops.object.mode_set(mode='OBJECT')

# ---------- painted bake materials ----------
# painted eyes: find the two lateral surface points of the head group (rest pose, world space)
EYES = []
if spec.get("eyes"):
    ecfg = spec["eyes"]; grp = set(descendants(ecfg["bone"]))
    gi = {vg.index for vg in mesh.vertex_groups if vg.name in grp}
    dgv = bpy.context.evaluated_depsgraph_get(); ev = mesh.evaluated_get(dgv); me_ = ev.to_mesh()
    pts = []
    for v, vo in zip(me_.vertices, mesh.data.vertices):
        tot = sum(g.weight for g in vo.groups); w = sum(g.weight for g in vo.groups if g.group in gi)
        if tot > 0 and w / tot > 0.6: pts.append(mesh.matrix_world @ v.co)
    ev.to_mesh_clear()
    FR = Matrix.Rotation(math.radians({"-y": 0, "+x": -90, "-x": 90, "+y": 180}[ecfg.get("front", "-y")]), 4, "Z")
    pts = [FR @ p for p in pts]
    hmn = Vector([min(p[i] for p in pts) for i in range(3)]); hmx = Vector([max(p[i] for p in pts) for i in range(3)])
    ty = hmn.y + ecfg.get("fwd", 0.35) * (hmx.y - hmn.y); tz = hmn.z + ecfg.get("up", 0.6) * (hmx.z - hmn.z)
    tol = ecfg.get("tol", 0.12) * max(hmx.y - hmn.y, hmx.z - hmn.z)
    for side in (-1, 1):
        c = [p for p in pts if abs(p.y - ty) < tol and abs(p.z - tz) < tol and p.x * side > 0]
        if c:
            p = max(c, key=lambda p: p.x * side); EYES.append(p)
    if ecfg.get("spread"):
        EYES = []
        cx = (hmn.x + hmx.x) / 2; hw = (hmx.x - hmn.x) / 2
        for side in (-1, 1):
            tx = cx + side * ecfg["spread"] * hw
            c = [p for p in pts if abs(p.x - tx) < tol and abs(p.z - tz) < tol]
            if c: EYES.append(min(c, key=lambda p: p.y))
    EYES = [FR.inverted() @ p for p in EYES]
    print("EYES", [[round(x, 3) for x in p] for p in EYES], "head bbox", [round(x, 3) for x in hmn], [round(x, 3) for x in hmx])
H = max(0.05, (mx - mn).z); Z0 = mn.z
pal = spec.get("palette", {}); default = spec.get("default_color", [0.5, 0.45, 0.4])
grade = spec.get("grade")  # for atlas packs: {"sat":0.6,"val":0.8,"tint":[r,g,b],"tint_mix":0.4}
glow = spec.get("glow")    # {"mats": [...regex] or "all", "color":[r,g,b], "mask":"noise"|"full"|"cavity", "strength":2}
paint = spec.get("paint", {})
def lin(c): return [((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c]

def build_bake_mat(src_mat, for_glow):
    nm = src_mat.name if src_mat else "none"
    m = bpy.data.materials.new("bake_" + nm + ("_glow" if for_glow else ""))
    m.use_nodes = True; nt = m.node_tree; N = nt.nodes; L = nt.links
    for n in list(N): N.remove(n)
    out = N.new("ShaderNodeOutputMaterial"); em = N.new("ShaderNodeEmission"); L.new(em.outputs[0], out.inputs[0])
    tc = N.new("ShaderNodeTexCoord"); geo0 = N.new("ShaderNodeNewGeometry"); geoP = geo0.outputs["Position"]
    # base colour
    key = next((k for k in pal if re.fullmatch(k, nm)), None)
    if key is not None or not grade:
        base = N.new("ShaderNodeRGB"); base.outputs[0].default_value = lin(pal.get(key, default)) + [1]
        base_out = base.outputs[0]
    else:
        img_node = None
        if src_mat and src_mat.use_nodes:
            img_node = next((n for n in src_mat.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image), None)
        if img_node is None and spec.get("atlas_image"):
            class _N: pass
            img_node = _N(); img_node.image = bpy.data.images.load(os.path.join(REPO, spec["atlas_image"]), check_existing=True)
        if img_node:
            it = N.new("ShaderNodeTexImage"); it.image = img_node.image; it.interpolation = 'Closest'
            uvn = N.new("ShaderNodeUVMap"); uvn.uv_map = orig_uv; L.new(uvn.outputs[0], it.inputs[0])
            col = it.outputs[0]
        else:
            rgb = N.new("ShaderNodeRGB")
            bc = src_mat.diffuse_color if src_mat else (0.5, 0.5, 0.5, 1)
            try:
                bsdf = next(n for n in src_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'); bc = bsdf.inputs[0].default_value
            except Exception: pass
            rgb.outputs[0].default_value = bc; col = rgb.outputs[0]
        hsv = N.new("ShaderNodeHueSaturation"); hsv.inputs["Saturation"].default_value = grade.get("sat", 0.6)
        hsv.inputs["Value"].default_value = grade.get("val", 0.85); hsv.inputs["Hue"].default_value = 0.5 + grade.get("hue", 0.0)
        L.new(col, hsv.inputs["Color"])
        mixt = N.new("ShaderNodeMix"); mixt.data_type = 'RGBA'; mixt.blend_type = grade.get("tint_blend", 'MULTIPLY')
        mixt.inputs[0].default_value = grade.get("tint_mix", 0.4)
        L.new(hsv.outputs[0], mixt.inputs[6]); mixt.inputs[7].default_value = lin(grade.get("tint", [1, 0.9, 0.75])) + [1]
        base_out = mixt.outputs[2]
    if for_glow:
        is_glow = glow and glow.get("color") and (glow.get("mats") == "all" or any(re.fullmatch(p, nm) for p in glow.get("mats", [])))
        gout = None
        if is_glow:
            gcol = N.new("ShaderNodeRGB"); gcol.outputs[0].default_value = lin(glow["color"]) + [1]
            if glow.get("mask", "full") == "full":
                gout = gcol.outputs[0]
            else:  # veins: a thin band of a noise field
                nz = N.new("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = glow.get("scale", 3.0) / H
                nz.inputs["Detail"].default_value = 4; L.new(geoP, nz.inputs["Vector"])
                ramp = N.new("ShaderNodeValToRGB"); L.new(nz.outputs[0], ramp.inputs[0])
                lo, hi = glow.get("band", [0.47, 0.53]); el = ramp.color_ramp.elements
                el[0].position = lo; el[0].color = (0, 0, 0, 1); el[1].position = hi; el[1].color = (0, 0, 0, 1)
                e3 = el.new((lo + hi) / 2); e3.color = (1, 1, 1, 1)
                mul = N.new("ShaderNodeMix"); mul.data_type = 'RGBA'; mul.blend_type = 'MULTIPLY'; mul.inputs[0].default_value = 1
                L.new(ramp.outputs[0], mul.inputs[6]); L.new(gcol.outputs[0], mul.inputs[7]); gout = mul.outputs[2]
        if gout is None:
            blk = N.new("ShaderNodeRGB"); blk.outputs[0].default_value = (0, 0, 0, 1); gout = blk.outputs[0]
        ecfg = spec.get("eyes", {})
        if ecfg.get("glow"):
            for ep in EYES:
                d = N.new("ShaderNodeVectorMath"); d.operation = 'DISTANCE'; L.new(geoP, d.inputs[0]); d.inputs[1].default_value = ep
                re_ = N.new("ShaderNodeMapRange"); L.new(d.outputs["Value"], re_.inputs[0])
                re_.inputs[1].default_value = ecfg.get("r", 0.012) * 0.5; re_.inputs[2].default_value = ecfg.get("r", 0.012)
                re_.inputs[3].default_value = 1.0; re_.inputs[4].default_value = 0.0
                me2 = N.new("ShaderNodeMix"); me2.data_type = 'RGBA'; L.new(re_.outputs[0], me2.inputs[0])
                L.new(gout, me2.inputs[6]); me2.inputs[7].default_value = lin(ecfg["glow"]) + [1]; gout = me2.outputs[2]
        L.new(gout, em.inputs[0])
        return m
    # painterly modulation ------------------------------------------------
    # 1) large mottling
    n1 = N.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = paint.get("mottle_scale", 2.5) / H
    n1.inputs["Detail"].default_value = 3; n1.inputs["Roughness"].default_value = 0.55
    L.new(geoP, n1.inputs["Vector"])
    r1 = N.new("ShaderNodeMapRange"); L.new(n1.outputs[0], r1.inputs[0])
    a = paint.get("mottle", 0.22); r1.inputs[1].default_value = 0.3; r1.inputs[2].default_value = 0.7
    r1.inputs[3].default_value = 1 - a; r1.inputs[4].default_value = 1 + a * 0.6
    # 2) fine brush grain
    n2 = N.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = paint.get("grain_scale", 14.0) / H
    n2.inputs["Detail"].default_value = 6; L.new(geoP, n2.inputs["Vector"])
    r2 = N.new("ShaderNodeMapRange"); L.new(n2.outputs[0], r2.inputs[0]); g = paint.get("grain", 0.12)
    r2.inputs[1].default_value = 0.35; r2.inputs[2].default_value = 0.65; r2.inputs[3].default_value = 1 - g; r2.inputs[4].default_value = 1 + g * 0.5
    # 3) foot-to-head gradient (darker feet)
    sep = N.new("ShaderNodeSeparateXYZ"); L.new(geoP, sep.inputs[0])
    # object-space z -> world through the mesh transform is ~ the armature scale; normalise with a map range on world Z
    geo = N.new("ShaderNodeNewGeometry"); sepw = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Position"], sepw.inputs[0])
    r3 = N.new("ShaderNodeMapRange"); L.new(sepw.outputs[2], r3.inputs[0])
    r3.inputs[1].default_value = Z0; r3.inputs[2].default_value = Z0 + H
    r3.inputs[3].default_value = paint.get("foot_dark", 0.62); r3.inputs[4].default_value = paint.get("head_light", 1.08)
    # 4) painted top light: normal.z
    sepn = N.new("ShaderNodeSeparateXYZ"); L.new(geo.outputs["Normal"], sepn.inputs[0])
    r4 = N.new("ShaderNodeMapRange"); L.new(sepn.outputs[2], r4.inputs[0])
    r4.inputs[1].default_value = -1; r4.inputs[2].default_value = 1
    r4.inputs[3].default_value = paint.get("under_dark", 0.72); r4.inputs[4].default_value = paint.get("top_light", 1.12)
    # 5) cavity AO
    ao = N.new("ShaderNodeAmbientOcclusion"); ao.inputs["Distance"].default_value = H * paint.get("ao_dist", 0.08); ao.samples = 16
    r5 = N.new("ShaderNodeMapRange"); L.new(ao.outputs["AO"], r5.inputs[0])
    r5.inputs[3].default_value = paint.get("ao_min", 0.45); r5.inputs[4].default_value = 1.0
    # 6) edge wear highlight (pointiness)
    r6 = N.new("ShaderNodeMapRange"); L.new(geo.outputs["Pointiness"], r6.inputs[0])
    r6.inputs[1].default_value = 0.5; r6.inputs[2].default_value = 0.56
    r6.inputs[3].default_value = 1.0; r6.inputs[4].default_value = 1.0 + paint.get("edge", 0.18)
    cur = base_out
    # 0) accent colour patches (e.g. grey-brown fur variation, lichen on bone)
    acc = paint.get("accent", {})
    akey = next((k for k in acc if re.fullmatch(k, nm)), None)
    if akey is not None:
        na = N.new("ShaderNodeTexNoise"); na.inputs["Scale"].default_value = paint.get("accent_scale", 3.0) / H
        na.inputs["Detail"].default_value = 4; L.new(geoP, na.inputs["Vector"])
        ra = N.new("ShaderNodeMapRange"); L.new(na.outputs[0], ra.inputs[0])
        ra.inputs[1].default_value = 0.42; ra.inputs[2].default_value = 0.62; ra.inputs[4].default_value = paint.get("accent_mix", 0.8)
        ma = N.new("ShaderNodeMix"); ma.data_type = 'RGBA'; L.new(ra.outputs[0], ma.inputs[0])
        L.new(cur, ma.inputs[6]); ma.inputs[7].default_value = lin(acc[akey]) + [1]; cur = ma.outputs[2]
    # 0b) directional brush strokes / fur: noise squashed along the stroke axis
    if paint.get("strokes", 0) > 0:
        ax = {"x": 0, "y": 1, "z": 2}[paint.get("stroke_axis", "y")]
        sv = [paint.get("stroke_across", 40.0) / H] * 3; sv[ax] = paint.get("stroke_along", 4.0) / H
        vm = N.new("ShaderNodeVectorMath"); vm.operation = 'MULTIPLY'; vm.inputs[1].default_value = sv
        L.new(geoP, vm.inputs[0])
        ns = N.new("ShaderNodeTexNoise"); ns.inputs["Scale"].default_value = 1.0; ns.inputs["Detail"].default_value = 5
        ns.inputs["Distortion"].default_value = paint.get("stroke_wobble", 0.6)
        L.new(vm.outputs[0], ns.inputs["Vector"])
        rs = N.new("ShaderNodeMapRange"); L.new(ns.outputs[0], rs.inputs[0]); s_ = paint["strokes"]
        rs.inputs[1].default_value = 0.3; rs.inputs[2].default_value = 0.7
        rs.inputs[3].default_value = 1 - s_; rs.inputs[4].default_value = 1 + s_
        ms_ = N.new("ShaderNodeMix"); ms_.data_type = 'RGBA'; ms_.blend_type = 'MULTIPLY'; ms_.inputs[0].default_value = 1
        L.new(cur, ms_.inputs[6]); L.new(rs.outputs[0], ms_.inputs[7]); cur = ms_.outputs[2]
    for r in (r1, r2, r3, r4, r5, r6):
        mm = N.new("ShaderNodeMix"); mm.data_type = 'RGBA'; mm.blend_type = 'MULTIPLY'; mm.inputs[0].default_value = 1
        L.new(cur, mm.inputs[6]); L.new(r.outputs[0], mm.inputs[7]); cur = mm.outputs[2]
    for ep in EYES:
        ecfg = spec["eyes"]
        d = N.new("ShaderNodeVectorMath"); d.operation = 'DISTANCE'; L.new(geoP, d.inputs[0]); d.inputs[1].default_value = ep
        re_ = N.new("ShaderNodeMapRange"); L.new(d.outputs["Value"], re_.inputs[0])
        re_.inputs[1].default_value = ecfg.get("r", 0.012) * 0.8; re_.inputs[2].default_value = ecfg.get("r", 0.012)
        re_.inputs[3].default_value = 1.0; re_.inputs[4].default_value = 0.0
        me2 = N.new("ShaderNodeMix"); me2.data_type = 'RGBA'; L.new(re_.outputs[0], me2.inputs[0])
        L.new(cur, me2.inputs[6]); me2.inputs[7].default_value = lin(ecfg.get("color", [0.03, 0.02, 0.02])) + [1]; cur = me2.outputs[2]
    # 7) cool/warm split: shadows toward a cool colour (hand-painted look)
    if paint.get("shadow_tint"):
        st = N.new("ShaderNodeMix"); st.data_type = 'RGBA'; st.blend_type = 'MIX'
        inv = N.new("ShaderNodeMath"); inv.operation = 'SUBTRACT'; inv.inputs[0].default_value = 1.0
        L.new(ao.outputs["AO"], inv.inputs[1])
        k2 = N.new("ShaderNodeMath"); k2.operation = 'MULTIPLY'; k2.inputs[1].default_value = paint.get("shadow_mix", 0.5)
        L.new(inv.outputs[0], k2.inputs[0]); L.new(k2.outputs[0], st.inputs[0])
        L.new(cur, st.inputs[6]); st.inputs[7].default_value = lin(paint["shadow_tint"]) + [1]; cur = st.outputs[2]
    L.new(cur, em.inputs[0])
    return m

src_mats = [s.material for s in mesh.material_slots] or [None]
if not mesh.material_slots: mesh.data.materials.append(None)
TEX = spec.get("tex", 512)
def bake(for_glow, img_name):
    img = bpy.data.images.new(img_name, TEX, TEX, alpha=False)
    for i, sm in enumerate(src_mats):
        bm_ = build_bake_mat(sm, for_glow)
        tn = bm_.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = img; bm_.node_tree.nodes.active = tn
        mesh.material_slots[i].material = bm_
    sc.render.engine = 'CYCLES'; sc.cycles.samples = 16; sc.cycles.device = 'CPU'
    sc.render.bake.margin = 6; sc.render.bake.use_clear = True
    for o in bpy.data.objects: o.select_set(o == mesh)
    bpy.context.view_layer.objects.active = mesh
    mesh.data.uv_layers.active = mesh.data.uv_layers["paint"]
    bpy.ops.object.bake(type='EMIT')
    return img
col_img = bake(False, NAME + "_paint")
HAS_GLOW = bool(glow) or bool(spec.get("eyes", {}).get("glow"))
glow = glow or {}
glow_img = bake(True, NAME + "_glow") if HAS_GLOW else None

# ---------- final material ----------
def final_mat(nm, cimg, gimg):
    m = bpy.data.materials.new(nm); m.use_nodes = True; nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED')
    t = nt.nodes.new("ShaderNodeTexImage"); t.image = cimg
    uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "paint"; nt.links.new(uvn.outputs[0], t.inputs[0])
    nt.links.new(t.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.85); bsdf.inputs["Metallic"].default_value = 0
    if gimg is not None:
        t2 = nt.nodes.new("ShaderNodeTexImage"); t2.image = gimg; nt.links.new(uvn.outputs[0], t2.inputs[0])
        nt.links.new(t2.outputs[0], bsdf.inputs["Emission Color"]); bsdf.inputs["Emission Strength"].default_value = glow.get("strength", 1.5)
    nt.nodes.active = t
    return m
fm = final_mat(NAME, col_img, glow_img)
mesh.data.materials.clear(); mesh.data.materials.append(fm)
for p in mesh.data.polygons: p.material_index = 0
# drop the old atlas UV so only "paint" is exported
for uvl in [u for u in mesh.data.uv_layers if u.name != "paint"]: mesh.data.uv_layers.remove(uvl)
for img in bpy.data.images:
    if img.users == 0 and img not in (col_img, glow_img): bpy.data.images.remove(img)
col_img.pack();
if glow_img: glow_img.pack()

# ---------- LOD1 ----------
lod1 = mesh.copy(); lod1.data = mesh.data.copy(); lod1.name = NAME + "_lod1"; sc.collection.objects.link(lod1)
for o in bpy.data.objects: o.select_set(o == lod1)
bpy.context.view_layer.objects.active = lod1
t_l1 = decimate_to(lod1, spec.get("lod1", 2500))
c1 = col_img.copy(); c1.name = NAME + "_lod1_paint"; c1.scale(TEX // 2, TEX // 2); c1.pack()
g1 = None
if glow_img: g1 = glow_img.copy(); g1.name = NAME + "_lod1_glow"; g1.scale(TEX // 2, TEX // 2); g1.pack()
lod1.data.materials.clear(); lod1.data.materials.append(final_mat(NAME + "_lod1", c1, g1))

# ---------- export ----------
arm.data.pose_position = 'POSE'
ad = arm.animation_data
if ad:
    ad.action = None
    for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
arm.name = NAME + "_rig"
def export(path, m):
    for o in bpy.data.objects: o.select_set(o in (arm, m))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
        export_image_format='JPEG', export_jpeg_quality=90, export_animation_mode='ACTIONS',
        export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
        export_anim_single_armature=True, export_def_bones=False, export_all_influences=False,
        export_force_sampling=True, export_optimize_animation_size=True)
    print("EXPORTED", path, os.path.getsize(path) // 1024, "KB")
p0 = os.path.join(OUT, NAME + ".glb"); p1 = os.path.join(OUT, NAME + "_lod1.glb")
export(p0, mesh); export(p1, lod1)
clips = {k: round((a.frame_range[1] - a.frame_range[0]) / sc.render.fps, 2) for k, a in clipmap.items()}
stats = {"name": NAME, "src": spec["src"], "tris_lod0": tris(mesh), "tris_lod1": tris(lod1), "bones": len(arm.data.bones),
         "tex": TEX, "fps": sc.render.fps, "clips": clips, "synthesised": synth, "aliases": aliases, "pruned_bones": removed,
         "size_m": [round(v, 2) for v in (mx - mn)], "hover": spec.get("hover", 0.0)}
SD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stats"); os.makedirs(SD, exist_ok=True)
json.dump(stats, open(os.path.join(SD, NAME + ".json"), "w"), indent=1)
print("STATS", json.dumps(stats))
