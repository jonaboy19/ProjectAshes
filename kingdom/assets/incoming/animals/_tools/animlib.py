"""Helpers shared by the Rising Ashes animal pipeline (Blender 5.2, headless).
Import -> clean -> reduce bones -> repaint with shared palette atlas -> scale -> export GLB."""
import bpy, bmesh, math, os, sys, json, mathutils
sys.path.insert(0, os.path.dirname(__file__))
import palette as PAL

ATLAS_NAME = "animals_atlas"

# ---------------------------------------------------------------- import / clean
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def import_any(path):
    ext = os.path.splitext(path)[1].lower()
    before = set(bpy.data.objects)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path, ignore_leaf_bones=True)
        for a in bpy.data.actions:  # FBX actions also key the armature object itself -> drop
            cb = channelbag(a)
            if cb:
                for fc in list(cb.fcurves):
                    if not fc.data_path.startswith("pose.bones"):
                        cb.fcurves.remove(fc)
    elif ext == ".blend":
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = src.objects
            dst.actions = src.actions
        for o in dst.objects:
            if o and o.type in ("MESH", "ARMATURE", "EMPTY"):
                bpy.context.scene.collection.objects.link(o)
        for a in bpy.data.actions:
            a.use_fake_user = True
    else:
        bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]

def armature():
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    return arms[0] if arms else None

def skinned_meshes(arm):
    out = []
    for o in bpy.context.scene.objects:
        if o.type != "MESH":
            continue
        if o.parent == arm or any(m.type == "ARMATURE" and m.object == arm for m in o.modifiers):
            out.append(o)
    return out

def clean_strays(arm, keep=()):
    """Remove every object that is not the armature or a mesh bound to it."""
    shapes = set()
    for pb in arm.pose.bones:
        if pb.custom_shape: shapes.add(pb.custom_shape); pb.custom_shape = None
    for o in shapes:
        bpy.data.objects.remove(o, do_unlink=True)
    keep = set(keep) | {arm} | set(skinned_meshes(arm))
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)

def bone_parented_to_skin(arm):
    """Meshes parented to a bone (e.g. antlers) -> weight 1.0 to that bone + armature modifier."""
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.parent == arm and o.parent_type == "BONE":
            bname = o.parent_bone
            mw = o.matrix_world.copy()
            o.parent_type = "OBJECT"; o.parent_bone = ""
            o.matrix_world = mw
            vg = o.vertex_groups.new(name=bname)
            vg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
            if not any(m.type == "ARMATURE" for m in o.modifiers):
                m = o.modifiers.new("Armature", "ARMATURE"); m.object = arm

# ---------------------------------------------------------------- actions
def channelbag(action):
    if not action.layers or not action.layers[0].strips or not action.slots:
        return None
    return action.layers[0].strips[0].channelbag(action.slots[0])

def fcurves(action):
    cb = channelbag(action)
    return list(cb.fcurves) if cb else []

def ensure_actions_listed(arm):
    """Make every action on the armature (NLA or assigned) a fake-user action."""
    for a in bpy.data.actions:
        a.use_fake_user = True

def remove_bone_curves(bones):
    for a in list(bpy.data.actions):
        cb = channelbag(a)
        if not cb:
            continue
        for fc in list(cb.fcurves):
            for b in bones:
                if fc.data_path.startswith('pose.bones["%s"]' % b):
                    cb.fcurves.remove(fc); break

def rename_actions(mapping, drop_others=False, prefix_strip=True):
    for a in list(bpy.data.actions):
        n = a.name.split("|")[-1] if prefix_strip else a.name
        if n in mapping:
            a.name = "__tmp__" + mapping[n]
        elif drop_others:
            bpy.data.actions.remove(a)
        else:
            a.name = "__tmp__" + n
    for a in list(bpy.data.actions):
        if a.name.startswith("__tmp__"):
            a.name = a.name[7:]

def clear_nla(arm):
    if arm.animation_data:
        for t in list(arm.animation_data.nla_tracks):
            arm.animation_data.nla_tracks.remove(t)
        arm.animation_data.action = None

# ---------------------------------------------------------------- bones
def merge_bones(arm, merge):
    """merge = {bone_to_remove: bone_that_receives_weights_or_None}"""
    meshes = skinned_meshes(arm)
    for m in meshes:
        for b, tgt in merge.items():
            src = m.vertex_groups.get(b)
            if not src:
                continue
            if tgt:
                dst = m.vertex_groups.get(tgt) or m.vertex_groups.new(name=tgt)
                for v in m.data.vertices:
                    for g in v.groups:
                        if g.group == src.index and g.weight > 0:
                            dst.add([v.index], g.weight, "ADD")
            m.vertex_groups.remove(src)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm.data.edit_bones
    for b in merge:
        if b in eb:
            e = eb[b]
            for c in list(e.children):
                c.parent = e.parent
            eb.remove(e)
    bpy.ops.object.mode_set(mode="OBJECT")
    remove_bone_curves(list(merge))

def uaa_reduce(arm, keep_tail=3):
    """Ultimate Animated Animals rigs: drop IK/pole/foot helpers, ear tips and tail tips -> <= 30 bones."""
    names = [b.name for b in arm.data.bones]
    merge = {}
    for side in ("L", "R"):
        for n in ("PoleTargetBack.", "PoleTarget."):
            if n + side in names: merge[n + side] = None
        for n, tgt in (("FF.", "FrontLowerLeg."), ("IKFrontLeg.", "FrontLowerLeg."),
                       ("FFB.", "BackLowerLeg."), ("IKBackLeg.", "BackLowerLeg.")):
            if n + side in names: merge[n + side] = tgt + side
        for k in (4, 3):
            if "Ear%d.%s" % (k, side) in names: merge["Ear%d.%s" % (k, side)] = "Ear2.%s" % side
    tails = sorted([n for n in names if n.startswith("Tail") and n[4:].isdigit()], key=lambda s: int(s[4:]))
    for t in tails[keep_tail:]:
        merge[t] = tails[keep_tail - 1]
    merge_bones(arm, merge)

# ---------------------------------------------------------------- meshes
def join_meshes(arm):
    ms = skinned_meshes(arm)
    if len(ms) <= 1:
        return ms[0] if ms else None
    bpy.ops.object.select_all(action="DESELECT")
    for m in ms: m.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active

def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)

def decimate_to(obj, target):
    n = tri_count(obj)
    if n <= target:
        return
    m = obj.modifiers.new("Dec", "DECIMATE"); m.ratio = target / n * 0.98
    # decimate must come before armature
    while obj.modifiers.find("Dec") > 0:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier="Dec")

def mat_color_srgb(mat):
    c = (0.5, 0.5, 0.5)
    if mat and mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                inp = n.inputs["Base Color"]
                c = tuple(inp.default_value[:3])
                if inp.is_linked:
                    src = inp.links[0].from_node
                    for i in src.inputs:
                        if i.type == "RGBA" and not i.is_linked:
                            c = tuple(i.default_value[:3])
    elif mat:
        c = tuple(mat.diffuse_color[:3])
    lin2s = lambda x: 12.92 * x if x <= 0.0031308 else 1.055 * (x ** (1 / 2.4)) - 0.055
    return tuple(lin2s(max(0, x)) for x in c)

def nearest_palette(rgb):
    best, bd = None, 9
    for n, hx in PAL.PALETTE:
        p = PAL.hex2rgb(hx)
        d = sum((p[i] - rgb[i]) ** 2 for i in range(3))
        if d < bd: best, bd = n, d
    return best

def atlas_material():
    mat = bpy.data.materials.get(ATLAS_NAME)
    if mat:
        return mat
    img = bpy.data.images.get(ATLAS_NAME)
    if not img:
        img = bpy.data.images.new(ATLAS_NAME, PAL.ATLAS, PAL.ATLAS, alpha=False)
        img.colorspace_settings.name = "sRGB"
        img.pixels = PAL.build_pixels()
        img.file_format = "PNG"
        img.pack()
    mat = bpy.data.materials.new(ATLAS_NAME)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = [n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"][0]
    tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img; tex.interpolation = "Linear"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.92
    bsdf.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    return mat

def face_vcolors(obj):
    """per-face average sRGB of the first colour attribute, or None"""
    me = obj.data
    if not me.color_attributes:
        return None
    ca = me.color_attributes[0]
    lin2s = lambda x: 12.92 * x if x <= 0.0031308 else 1.055 * (max(x, 0) ** (1 / 2.4)) - 0.055
    out = []
    for p in me.polygons:
        acc = [0.0, 0.0, 0.0]
        idxs = p.loop_indices if ca.domain == "CORNER" else [me.loops[li].vertex_index for li in p.loop_indices]
        for i in idxs:
            c = ca.data[i].color
            for k in range(3): acc[k] += c[k]
        n = len(idxs)
        out.append(tuple(lin2s(acc[k] / n) for k in range(3)))
    return out

def nearest_of(rgb, cands):
    best, bd = cands[0], 9
    for n in cands:
        p = PAL.hex2rgb(dict(PAL.PALETTE)[n])
        d = sum((p[i] - rgb[i]) ** 2 for i in range(3))
        if d < bd: best, bd = n, d
    return best

def paint(obj, colour_map, default=None, face_rule=None, grad=(0.55, 0.45), vc_candidates=None, remap=None):
    """Assign every face a palette cell (by old material name -> palette name) and a gradient V.
    colour_map: {material_name_substring: palette_name}; unknown materials use nearest palette colour.
    face_rule(face_center_world, normal_world, old_mat_name) -> palette name or None (override)."""
    me = obj.data
    mats = [s.material for s in obj.material_slots]
    names = []
    for m in mats:
        nm = None
        if m:
            for k, v in colour_map.items():
                if k == m.name or (k.endswith("*") and m.name.startswith(k[:-1])):
                    nm = v; break
        if nm is None:
            nm = default or nearest_palette(mat_color_srgb(m))
        names.append(nm)
    mw = obj.matrix_world
    zs = [(mw @ v.co).z for v in me.vertices]
    zmin, zmax = min(zs), max(zs); h = max(zmax - zmin, 1e-6)
    uvl = me.uv_layers.get("atlas") or me.uv_layers.new(name="atlas")
    nrm = mw.to_3x3().inverted().transposed()
    wh, wn = grad
    vcols = face_vcolors(obj) if vc_candidates else None
    for p in me.polygons:
        pal = names[p.material_index] if names else default
        if vcols:
            mc = mat_color_srgb(mats[p.material_index]) if mats and mats[p.material_index] else (1, 1, 1)
            src = tuple(vcols[p.index][k] * (mc[k] if mc[k] < 0.7 else 1.0) for k in range(3))
            pal = nearest_of(src, vc_candidates)
        if remap and pal in remap:
            pal = remap[pal]
        if face_rule:
            c = mw @ p.center; nw = (nrm @ p.normal).normalized()
            r = face_rule(c, nw, mats[p.material_index].name if mats and mats[p.material_index] else "")
            if r: pal = r
        nz = (nrm @ p.normal).normalized().z
        for li in p.loop_indices:
            vz = (zs[me.loops[li].vertex_index] - zmin) / h
            t = wh * vz + wn * (0.5 + 0.5 * nz)
            uvl.data[li].uv = PAL.uv_for(pal, t)
    # make atlas the only UV map / material
    for l in list(me.uv_layers):
        if l.name != "atlas": me.uv_layers.remove(l)
    me.materials.clear(); me.materials.append(atlas_material())
    for p in me.polygons:
        p.material_index = 0; p.use_smooth = False

# ---------------------------------------------------------------- transforms
def rest_bounds(arm, meshes):
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    mn = mathutils.Vector((1e9,) * 3); mx = -mn
    for o in meshes:
        oe = o.evaluated_get(dg); me = oe.to_mesh()
        for v in me.vertices:
            w = oe.matrix_world @ v.co
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
        oe.to_mesh_clear()
    arm.data.pose_position = "POSE"
    return mn, mx

def bone_z(arm, bone):
    arm.data.pose_position = "REST"; bpy.context.view_layer.update()
    z = (arm.matrix_world @ arm.data.bones[bone].head_local).z
    arm.data.pose_position = "POSE"; bpy.context.view_layer.update()
    return z

def fit(arm, meshes, height=None, length=None, yaw_deg=0.0, width_scale=1.0, shoulder=None):
    """Scale the armature object so rest-pose height (or body length) matches metres, feet on z=0,
    centred on the origin, facing -Y (glTF +Z)."""
    if yaw_deg:
        arm.rotation_mode = "XYZ"
        arm.rotation_euler.z += math.radians(yaw_deg)
    bpy.context.view_layer.update()
    mn, mx = rest_bounds(arm, meshes)
    size = mx - mn
    if shoulder:
        s = shoulder[1] / (bone_z(arm, shoulder[0]) - mn.z)
    else:
        s = (height / size.z) if height else (length / max(size.x, size.y))
    arm.scale = arm.scale * s
    if width_scale != 1.0:
        arm.scale.x *= width_scale
    bpy.context.view_layer.update()
    mn, mx = rest_bounds(arm, meshes)
    arm.location -= mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    bpy.context.view_layer.update()
    mn, mx = rest_bounds(arm, meshes)
    return mx - mn

# ---------------------------------------------------------------- export / stats
def export_glb(path, arm):
    clear_nla(arm)
    ensure_actions_listed(arm)
    idle = bpy.data.actions.get("Idle")
    if idle:
        arm.animation_data_create()
        arm.animation_data.action = idle
        if idle.slots: arm.animation_data.action_slot = idle.slots[0]
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    for m in skinned_meshes(arm): m.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
        export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_draco_mesh_compression_enable=False, export_image_format="AUTO",
        export_yup=True, export_apply=False, export_materials="EXPORT",
        export_force_sampling=True, export_optimize_animation_size=True, export_def_bones=True)

def stats(arm):
    ms = skinned_meshes(arm)
    return {"tris": sum(tri_count(m) for m in ms), "bones": len(arm.data.bones),
            "anims": sorted(a.name for a in bpy.data.actions)}

# ---------------------------------------------------------------- procedural animation
def new_action(arm, name):
    old = bpy.data.actions.get(name)
    if old: bpy.data.actions.remove(old)
    arm.animation_data_create()
    a = bpy.data.actions.new(name); a.use_fake_user = True
    arm.animation_data.action = a
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return a

def key_pose(arm, frame, pose, loc=None):
    """pose = {bone: (rx, ry, rz) degrees in bone-local XYZ euler}; loc = {bone: (x,y,z) local}"""
    for pb in arm.pose.bones:
        e = pose.get(pb.name)
        q = mathutils.Euler([math.radians(x) for x in e], "XYZ").to_quaternion() if e else mathutils.Quaternion()
        pb.rotation_quaternion = q
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        l = (loc or {}).get(pb.name)
        pb.location = mathutils.Vector(l) if l else mathutils.Vector()
        pb.keyframe_insert("location", frame=frame)

def copy_action_scaled(src_name, dst_name, time_scale):
    src = bpy.data.actions[src_name]
    dst = src.copy(); dst.name = dst_name; dst.use_fake_user = True
    for fc in fcurves(dst):
        for k in fc.keyframe_points:
            k.co.x *= time_scale; k.handle_left.x *= time_scale; k.handle_right.x *= time_scale
    return dst

def cyclic(action):
    for fc in fcurves(action):
        if not any(m.type == "CYCLES" for m in fc.modifiers):
            pass  # glTF bakes keys; loops are set in Godot import (loop_mode)

# ---------------------------------------------------------------- world-space procedural posing
def local_quat(arm, bone, rots):
    """rots: list of (world_axis Vector/tuple, degrees) -> pose-bone local quaternion (rest-relative)."""
    rest = (arm.matrix_world @ arm.data.bones[bone].matrix_local).to_3x3().normalized()
    q = mathutils.Quaternion()
    for ax, deg in rots:
        la = (rest.inverted() @ mathutils.Vector(ax)).normalized()
        q = mathutils.Quaternion(la, math.radians(deg)) @ q
    return q

def local_loc(arm, bone, world_vec):
    rest = (arm.matrix_world @ arm.data.bones[bone].matrix_local)
    m3 = rest.to_3x3()
    v = m3.inverted() @ mathutils.Vector(world_vec)
    return v

def proc_action(arm, name, keys):
    """keys: list of (frame, {bone: [(axis,deg),...]}, {bone: world_offset}) ; unspecified bones = rest."""
    a = new_action(arm, name)
    for frame, rots, locs in keys:
        for pb in arm.pose.bones:
            pb.rotation_quaternion = local_quat(arm, pb.name, rots[pb.name]) if pb.name in rots else mathutils.Quaternion()
            pb.location = local_loc(arm, pb.name, locs[pb.name]) if locs and pb.name in locs else mathutils.Vector()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("location", frame=frame)
    arm.animation_data.action = None
    return a

def copy_actions_from(src_actions, arm, rename, loc_scale=1.0, skip=()):
    """Retarget actions by bone name (same-template rigs). Location curves scaled."""
    names = {b.name for b in arm.data.bones}
    for src_name, dst_name in rename.items():
        src = bpy.data.actions.get(src_name)
        if not src: continue
        dst = src.copy(); dst.name = dst_name; dst.use_fake_user = True
        cb = channelbag(dst)
        for fc in list(cb.fcurves):
            bn = fc.data_path.split('"')[1] if '"' in fc.data_path else None
            if bn is None or bn not in names or any(bn.startswith(s) for s in skip):
                cb.fcurves.remove(fc); continue
            if fc.data_path.endswith("location") and loc_scale != 1.0:
                for k in fc.keyframe_points:
                    k.co.y *= loc_scale; k.handle_left.y *= loc_scale; k.handle_right.y *= loc_scale
