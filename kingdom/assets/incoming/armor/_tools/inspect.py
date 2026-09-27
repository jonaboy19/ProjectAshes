# Blender headless inspector: prints one JSON line per input file.
# blender -b --factory-startup --python inspect.py -- out.jsonl file1 file2 ...
import bpy, sys, json, os

args = sys.argv[sys.argv.index("--") + 1:]
out_path, files = args[0], args[1:]


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load(path):
    path = os.path.abspath(path)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".dae":
        bpy.ops.wm.collada_import(filepath=path)
    elif ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path); return
        with bpy.data.libraries.load(path, link=False) as (src, dst):
            dst.objects = list(src.objects)
        for o in dst.objects:
            if o is not None and o.type in ("MESH", "ARMATURE", "EMPTY"):
                bpy.context.scene.collection.objects.link(o)
    else:
        raise RuntimeError("unsupported " + ext)


def tris(o):
    dg = bpy.context.evaluated_depsgraph_get()
    m = o.evaluated_get(dg).to_mesh()
    n = sum(len(p.vertices) - 2 for p in m.polygons)
    o.evaluated_get(dg).to_mesh_clear()
    return n


with open(out_path, "a", encoding="utf-8") as fo:
    for f in files:
        rec = {"file": f}
        try:
            clear()
            load(f)
            meshes = []
            for o in bpy.context.scene.objects:
                if o.type != "MESH":
                    continue
                arm = None
                for md in o.modifiers:
                    if md.type == "ARMATURE" and md.object:
                        arm = md.object.name
                if arm is None and o.parent and o.parent.type == "ARMATURE":
                    arm = o.parent.name
                meshes.append({"name": o.name, "tris": tris(o), "skinned": bool(arm and len(o.vertex_groups) > 0),
                               "armature": arm, "vgroups": len(o.vertex_groups),
                               "mats": [s.material.name for s in o.material_slots if s.material]})
            arms = []
            for o in bpy.context.scene.objects:
                if o.type == "ARMATURE":
                    b = [x.name for x in o.data.bones]
                    arms.append({"name": o.name, "bones": len(b), "sample": b[:12]})
            imgs = [{"name": i.name, "size": list(i.size)} for i in bpy.data.images if i.size[0] > 0]
            # bounds
            import mathutils
            mn = mathutils.Vector((1e9,) * 3); mx = -mn
            for o in bpy.context.scene.objects:
                if o.type == "MESH":
                    for c in o.bound_box:
                        w = o.matrix_world @ mathutils.Vector(c)
                        mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
            rec.update({"tris": sum(m["tris"] for m in meshes), "meshes": meshes, "armatures": arms,
                        "images": imgs, "size": [round(v, 3) for v in (mx - mn)] if meshes else None,
                        "anims": len(bpy.data.actions)})
        except Exception as e:
            rec["error"] = str(e)
        fo.write(json.dumps(rec) + "\n")
        fo.flush()
