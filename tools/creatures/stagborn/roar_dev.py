"""Dev harness: open char_warden.blend, author ONLY the roar, measure antler clearance vs body per frame.
blender -b --python roar_dev.py -- <char_warden.blend> [outjson]"""
import bpy, sys, os, math, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ["CLIPS_ONLY"] = "roar"
blend = sys.argv[sys.argv.index('--') + 1]
bpy.ops.wm.open_mainfile(filepath=os.path.abspath(blend))
import clips, importlib
D = bpy.data; arm = D.objects["Armature"]; mesh = D.objects["mesh"]
bpy.context.scene.render.fps = 30
clips.build("warden", arm)
from mathutils import kdtree
me0 = mesh.data
hg = mesh.vertex_groups["Head"].index
hw = {}
for v in me0.vertices:
    for g in v.groups:
        if g.group == hg: hw[v.index] = g.weight
hb = arm.data.bones["Head"]
# antler verts: heavily head-weighted and well above head bone head in rest pose
ant = [i for i, w in hw.items() if w > 0.9 and me0.vertices[i].co.z > hb.head_local.z + 0.12 or (w > 0.9 and abs(me0.vertices[i].co.x) > 0.35)]
body = [v.index for v in me0.vertices if hw.get(v.index, 0) < 0.2]
print("ANT", len(ant), "BODY", len(body))
from mathutils.bvhtree import BVHTree
bodyset = set(body); antset = set(ant)
def clearance(action):
    """per frame: signed distance (m) from the worst antler vertex to the body surface (negative = inside the body)"""
    arm.animation_data.action = action
    if action.slots: arm.animation_data.action_slot = action.slots[0]
    f0 = int(action.frame_range[0]); f1 = int(action.frame_range[1]); res = []
    for f in range(f0, f1 + 1):
        bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
        ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); m = ev.to_mesh()
        m.calc_loop_triangles()
        verts = [v.co.copy() for v in m.vertices]
        tris = [tuple(t.vertices) for t in m.loop_triangles if all(i in bodyset for i in t.vertices)]
        bvh = BVHTree.FromPolygons(verts, tris)
        best = 9
        pts = [verts[i] for i in ant] + [(verts[e.vertices[0]] + verts[e.vertices[1]]) * 0.5 for e in m.edges if e.vertices[0] in antset and e.vertices[1] in antset]
        for co in pts:
            loc, nor, idx, d = bvh.find_nearest(co)
            if loc is None: continue
            sd = d
            if sd < best: best = sd
        res.append(round(best, 3)); ev.to_mesh_clear()
    return res
out = {}
for nm in ("idle", "roar"):
    a = D.actions.get(nm)
    if a: out[nm] = clearance(a); print("CLR", nm, out[nm])
if len(sys.argv) > sys.argv.index('--') + 2: json.dump(out, open(sys.argv[-1], "w"))
# export a GLB for rendering
if os.environ.get("RD_GLB"):
    for a in list(D.actions):
        if a.name not in ("roar", "idle"): D.actions.remove(a)
    for a in D.actions: a.use_fake_user = True
    arm.animation_data.action = None
    for o in D.objects: o.select_set(o in (mesh, arm))
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.export_scene.gltf(filepath=os.environ["RD_GLB"], use_selection=True, export_format='GLB', export_image_format='JPEG',
        export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True, export_anim_single_armature=True,
        export_def_bones=False, export_optimize_animation_size=False)
