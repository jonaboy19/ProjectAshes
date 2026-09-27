# Convert / clean / scale armor pieces to mobile-ready GLB (Blender 5.2 headless).
# blender -b --factory-startup --python build.py -- manifest.json report.jsonl
# Manifest: list of entries, paths relative to the manifest's "root":
#  {"src": "...", "out": "...glb",
#   "objects": [names to keep] | "exclude": [names],      (optional)
#   "rigid": true      -> unparent from bones, drop armature (attachable prop, e.g. helmet)
#   "fit": {"axis": "x|y|z|max", "size": metres} | "scale": f,
#   "origin": "bottom|center|keep" (rigid only, default bottom),
#   "max_tris": 3000, "max_tex": 1024,
#   "tex": "image path wired into every material's base colour",
#   "harmonise": true  -> tone flat material colours toward the warm natural palette,
#   "anims": false}
import bpy, sys, json, os, colorsys, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
man = json.load(open(argv[0], encoding="utf-8"))
report = argv[1]
root_dir = man["root"]


def P(p):
    return os.path.join(root_dir, p)


def load(path, want=None):
    path = os.path.abspath(path)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = [n for n in src.objects]
            dst.images = [n for n in src.images]
        for o in dst.objects:
            if o is not None and o.type in ("MESH", "ARMATURE"):
                bpy.context.scene.collection.objects.link(o)
    for o in list(bpy.context.scene.objects):
        if o.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(o)


def principled(m):
    if not m.use_nodes or not m.node_tree:
        m.use_nodes = True
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    return None


def fix_material(m, tex=None, harmonise=False, tex_map=None, mat_colors=None):
    if tex_map and m.name in tex_map:
        t = tex_map[m.name]
        tex = t if t not in bpy.data.images else None
        if tex is None:
            b0 = principled(m); tn = m.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = bpy.data.images[t]
            m.node_tree.links.new(tn.outputs["Color"], b0.inputs["Base Color"])
    b = principled(m)
    if b is None:
        return
    nt = m.node_tree
    if any(n.type in ("FRAME", "BSDF_DIFFUSE") for n in nt.nodes):
        # legacy Blender-Internal conversion: rebuild a clean Principled tree
        imgs = [n.image for n in nt.nodes if n.type == "TEX_IMAGE" and n.image]
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
        b.inputs["Base Color"].default_value = tuple(m.diffuse_color)
        if imgs:
            tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = imgs[0]
            nt.links.new(tn.outputs["Color"], b.inputs["Base Color"])
    # old Blender-Internal conversions keep a Diffuse BSDF on the active output: route the Principled BSDF instead
    outs = [n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"]
    diff = [n for n in nt.nodes if n.type == "BSDF_DIFFUSE"]
    if outs:
        for o in outs[1:]:
            nt.nodes.remove(o)
        nt.links.new(b.outputs["BSDF"], outs[0].inputs["Surface"])
        outs[0].is_active_output = True
    for d in diff:
        nt.nodes.remove(d)
    # drop dangling image nodes (missing files)
    for n in list(nt.nodes):
        if n.type == "TEX_IMAGE" and (n.image is None or (n.image.size[0] == 0 and not n.image.packed_file)):
            nt.nodes.remove(n)
    bc = b.inputs["Base Color"]
    if tex:
        img = bpy.data.images.load(os.path.abspath(tex), check_existing=True)
        tn = nt.nodes.new("ShaderNodeTexImage"); tn.image = img
        nt.links.new(tn.outputs["Color"], bc)
    if not bc.is_linked:
        # images packed in old Blender-Internal files are unconnected: wire the first usable one
        c = list(bc.default_value)
        d = list(m.diffuse_color)
        if c[:3] == [0.8, 0.8, 0.8] and d[:3] != [0.8, 0.8, 0.8]:
            bc.default_value = d
        if mat_colors:
            for k, v in mat_colors.items():
                if m.name.split(".")[0] == k or k == "*":
                    bc.default_value = (*v, 1)
        if harmonise:
            r, g, bb = bc.default_value[:3]
            h, s, v = colorsys.rgb_to_hsv(r, g, bb)
            if s < 0.35 or (0.45 < h < 0.7 and s < 0.6 and v < 0.6):  # greys / steel-blue -> neutral warm steel
                h, s = 0.09, min(s, 0.08)
            else:                 # bright toy colours -> natural, slightly saturated
                s = min(s * 0.8, 0.72); v = min(v, 0.78)
            bc.default_value = (*colorsys.hsv_to_rgb(h, s, v), 1)
    if not b.inputs["Alpha"].is_linked:
        b.inputs["Alpha"].default_value = 1.0
        try:
            m.surface_render_method = "DITHERED"; m.blend_method = "OPAQUE"
        except Exception:
            pass
    b.inputs["Roughness"].default_value = max(b.inputs["Roughness"].default_value, 0.55)


def mesh_tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def bbox(objs):
    mn = mathutils.Vector((1e18,) * 3); mx = -mn
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
    return mn, mx


out_f = open(report, "a", encoding="utf-8")
for e in man["entries"]:
    rec = {"out": e["out"], "src": e["src"]}
    try:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        load(P(e["src"]))
        sc = bpy.context.scene
        meshes = [o for o in sc.objects if o.type == "MESH"]
        keep = meshes
        if "objects" in e:
            keep = [o for o in meshes if o.name in e["objects"] or o.name.split(".")[0] in e["objects"]]
        if "exclude" in e:
            keep = [o for o in keep if o.name not in e["exclude"]]
        keep = [o for o in keep if not o.hide_render or e.get("objects")]
        for o in meshes:
            if o not in keep:
                bpy.data.objects.remove(o)
        for o in list(sc.objects):
            if o.type == "EMPTY" and not o.children:
                bpy.data.objects.remove(o)
        if not keep:
            raise RuntimeError("no meshes kept")
        for o in sc.objects:
            if o.type == "ARMATURE":
                o.data.pose_position = "REST"
            if o.animation_data and not e.get("anims"):
                o.animation_data_clear()
        if not e.get("anims"):
            for a in list(bpy.data.actions):
                bpy.data.actions.remove(a)
        bpy.context.view_layer.update()
        rigid = e.get("rigid", False)
        if rigid:
            for o in keep:
                mw = o.matrix_world.copy()
                o.parent = None
                o.matrix_world = mw
                for md in list(o.modifiers):
                    if md.type == "ARMATURE":
                        o.modifiers.remove(md)
                o.vertex_groups.clear()
            for o in list(sc.objects):
                if o.type in ("ARMATURE", "EMPTY"):
                    bpy.data.objects.remove(o)
        skinned = any(md.type == "ARMATURE" for o in keep for md in o.modifiers)
        if e.get("harmonise"):
            for o in keep:
                for ca in o.data.color_attributes:
                    for d in ca.data:
                        r, g, bb, a = d.color
                        h, s_, v = colorsys.rgb_to_hsv(r, g, bb)
                        if s_ < 0.35 or (0.45 < h < 0.7 and s_ < 0.6 and v < 0.6):
                            h, s_ = 0.09, min(s_, 0.08)
                        else:
                            s_ = min(s_ * 0.8, 0.72); v = min(v, 0.78)
                        d.color = (*colorsys.hsv_to_rgb(h, s_, v), a)
        # materials
        for m in bpy.data.materials:
            tm = e.get("tex_map")
            tm = {k: (v if v in bpy.data.images else P(v)) for k, v in tm.items()} if tm else None
            fix_material(m, P(e["tex"]) if e.get("tex") else None, e.get("harmonise", False), tm, e.get("mat_colors"))
        if e.get("flat_color"):
            fm = bpy.data.materials.new("steel"); fm.use_nodes = True
            principled(fm).inputs["Base Color"].default_value = (*e["flat_color"], 1)
            principled(fm).inputs["Metallic"].default_value = 0.6
            for o in keep:
                o.data.materials.clear(); o.data.materials.append(fm)
        if e.get("rot"):
            import math
            R = mathutils.Euler([math.radians(a) for a in e["rot"]]).to_matrix().to_4x4()
            for o in [o for o in sc.objects if o.parent is None]:
                o.matrix_world = R @ o.matrix_world
        # apply transforms so bbox is in world space
        bpy.ops.object.select_all(action="SELECT")
        bpy.context.view_layer.objects.active = keep[0]
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        mn, mx = bbox([o for o in keep if o.name.split(".")[0] == e["fit_ref"]] if e.get("fit_ref") else keep)
        size = mx - mn
        s = e.get("scale", 1.0)
        if "fit" in e:
            ax = e["fit"]["axis"]
            dim = max(size) if ax == "max" else size["xyz".index(ax)]
            s = e["fit"]["size"] / max(dim, 1e-9)
        tops = [o for o in sc.objects if o.parent is None]
        for o in tops:
            o.matrix_world = mathutils.Matrix.Scale(s, 4) @ o.matrix_world
        bpy.context.view_layer.update()
        mn, mx = bbox(keep)
        if rigid and e.get("origin", "bottom") != "keep":
            c = (mn + mx) / 2
            piv = mathutils.Vector((c.x, c.y, mn.z if e.get("origin", "bottom") == "bottom" else c.z))
            for o in tops:
                o.location -= piv
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.transform_apply(location=rigid, rotation=True, scale=True)
        if e.get("keep_materials"):
            import bmesh
            for o in keep:
                bm = bmesh.new(); bm.from_mesh(o.data)
                names = [ms.material.name.split(".")[0] if ms.material else "" for ms in o.material_slots]
                dead = [f for f in bm.faces if names and names[f.material_index] not in e["keep_materials"]]
                bmesh.ops.delete(bm, geom=dead, context="FACES")
                bm.to_mesh(o.data); bm.free()
            for o in list(keep):
                if len(o.data.polygons) == 0:
                    keep.remove(o); bpy.data.objects.remove(o)
        if rigid and len(keep) > 1 and e.get("join", True):
            bpy.ops.object.select_all(action="DESELECT")
            for o in keep:
                o.select_set(True)
            bpy.context.view_layer.objects.active = keep[0]
            bpy.ops.object.join()
            keep = [bpy.context.view_layer.objects.active]
        # decimate
        tot = sum(mesh_tris(o) for o in keep)
        mt = e.get("max_tris", 3000)
        if tot > mt:
            for o in keep:
                d = o.modifiers.new("dec", "DECIMATE"); d.ratio = mt / tot * 0.97
                bpy.context.view_layer.objects.active = o
                if not skinned:
                    bpy.ops.object.modifier_apply(modifier="dec")
                else:
                    # keep armature modifier first-applied order: move decimate to top then apply
                    bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
                    bpy.ops.object.modifier_apply(modifier="dec")
        # textures
        mt_px = e.get("max_tex", 1024)
        imgs = []
        for img in bpy.data.images:
            if img.size[0] == 0:
                continue
            w, h = img.size
            if max(w, h) > mt_px:
                f = mt_px / max(w, h)
                img.scale(max(1, int(w * f)), max(1, int(h * f)))
            imgs.append(list(img.size))
        if e.get("harmonise"):
            import numpy as np
            used = {n.image for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image}
            for img in used:
                if img.size[0] == 0 or "normal" in img.name.lower():
                    continue
                px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
                img.pixels.foreach_get(px)
                px = px.reshape(-1, 4)
                rgb = px[:, :3]
                lum = (rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32))[:, None]
                rgb = lum + (rgb - lum) * 0.72
                rgb *= np.array([1.03, 1.0, 0.95], dtype=np.float32)
                px[:, :3] = np.clip(rgb, 0, 0.86)
                img.pixels.foreach_set(px.ravel())
                img.update()
                try:
                    img.pack()
                except Exception:
                    pass
        outp = P(e["out"])
        os.makedirs(os.path.dirname(outp), exist_ok=True)
        bpy.ops.export_scene.gltf(filepath=outp, export_format="GLB", export_apply=True,
                                  export_animations=bool(e.get("anims")), export_draco_mesh_compression_enable=False,
                                  export_image_format=e.get("img_format", "AUTO"), export_jpeg_quality=85, export_yup=True)
        mn, mx = bbox(keep)
        rec.update({"tris": sum(mesh_tris(o) for o in keep), "skinned": skinned, "images": imgs,
                    "size": [round(v, 3) for v in (mx - mn)],
                    "bones": max([len(o.data.bones) for o in sc.objects if o.type == "ARMATURE"] or [0]),
                    "kb": round(os.path.getsize(outp) / 1024)})
    except Exception as ex:
        import traceback
        rec["error"] = str(ex) + " " + traceback.format_exc()[-300:]
    out_f.write(json.dumps(rec) + "\n"); out_f.flush()
