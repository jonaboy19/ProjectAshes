# Blender headless: inspect a character file -> JSON line (tris, bones, actions, textures, height).
# usage: blender -b --python inspect.py -- <file> <out.jsonl> [label]
import bpy, sys, json, os
argv = sys.argv[sys.argv.index("--") + 1:]
path, out = argv[0], argv[1]
label = argv[2] if len(argv) > 2 else os.path.basename(path)

def load(p):
    ext = os.path.splitext(p)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=p)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if ext in (".glb", ".gltf"):
            bpy.ops.import_scene.gltf(filepath=p)
        elif ext == ".fbx":
            bpy.ops.import_scene.fbx(filepath=p)

load(path)
dg = bpy.context.evaluated_depsgraph_get()
tris = 0; meshes = []
for o in bpy.context.scene.objects:
    if o.type != "MESH" or o.hide_render:
        continue
    ev = o.evaluated_get(dg); me = ev.to_mesh()
    t = sum(len(p.vertices) - 2 for p in me.polygons)
    tris += t; meshes.append([o.name, t]); ev.to_mesh_clear()
arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
bones = {a.name: [b.name for b in a.data.bones] for a in arms}
deform = {a.name: sum(1 for b in a.data.bones if b.use_deform) for a in arms}
imgs = [[i.name, list(i.size)] for i in bpy.data.images if i.size[0] > 0]
acts = [[a.name, round(a.frame_range[1] - a.frame_range[0], 1)] for a in bpy.data.actions]
# height from world bbox of meshes
import mathutils
zs = []
for o in bpy.context.scene.objects:
    if o.type == "MESH" and not o.hide_render:
        for c in o.bound_box:
            zs.append((o.matrix_world @ mathutils.Vector(c)).z)
h = (max(zs) - min(zs)) if zs else 0
rec = dict(label=label, file=path, tris=tris, meshes=meshes, armatures=bones, deform=deform,
           images=imgs, max_tex=max([max(s) for _, s in imgs], default=0), actions=acts, n_actions=len(acts), height=round(h, 3))
with open(out, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec) + "\n")
print("OK", label, tris, {k: len(v) for k, v in bones.items()}, len(acts))
