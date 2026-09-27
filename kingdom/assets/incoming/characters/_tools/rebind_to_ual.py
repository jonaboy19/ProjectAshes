# Re-rig any humanoid mesh onto the Quaternius UAL skeleton (exact UAL1 rest
# orientations, the same skeleton as the MakeHuman villagers in
# kingdom/assets/generated/characters/), so every UAL-library clip plays on it.
#
# usage: blender -b --python rebind_to_ual.py -- <config.json>
# config:
#  source: .blend/.glb/.fbx         ual: UAL1_Standard.glb
#  map: {ual_bone: source_bone}      (joint positions; weights too in "map" mode)
#  weights: "map" | "auto"           map = rename the source vertex groups via `map`
#                                    auto = Blender bone-heat weights on a fitted rig
#  merge: {src_group: ual_bone}      extra renames for map mode (heel -> foot ...)
#  split: {src_group: [ual bones bottom->top]}  split a group by vertex height
#  variants: [{name, show: regex of mesh names}]  one GLB per variant
#  out_dir, prefix, autotex (bool), max_tex (1024), hip_height (UAL pelvis height)
#  apose (bool): also keep nothing; posing is always into the UAL T-pose.
import bpy, sys, os, re, json, math
from mathutils import Vector, Matrix, Quaternion
cfg = json.load(open(sys.argv[sys.argv.index("--") + 1:][0], encoding="utf-8"))
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import autotex

src = cfg["source"]; ext = os.path.splitext(src)[1].lower()
if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    (bpy.ops.import_scene.fbx if ext == ".fbx" else bpy.ops.import_scene.gltf)(filepath=src)
sc = bpy.context.scene
sc.unit_settings.scale_length = 1.0
def unexclude(lc):
    lc.exclude = False; lc.hide_viewport = False; lc.collection.hide_viewport = False
    for c in lc.children:
        unexclude(c)
unexclude(bpy.context.view_layer.layer_collection)
for o in sc.objects:
    o.hide_set(False); o.hide_viewport = False
S = cfg.get("source_armature") and bpy.data.objects[cfg["source_armature"]] or \
    max([o for o in sc.objects if o.type == "ARMATURE"], key=lambda o: len(o.data.bones))
S.data.pose_position = "REST"
for pb in S.pose.bones:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
bpy.context.view_layer.update()
bmap = cfg["map"]

# ---- import UAL twice: Tmp (fitted to source rest) and Final ----------------
def import_ual(name):
    before = set(bpy.data.objects); ba = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=cfg["ual"])
    new = [o for o in bpy.data.objects if o not in before]
    arm = [o for o in new if o.type == "ARMATURE"][0]
    for o in new:
        if o is not arm:
            bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        if a not in ba:
            bpy.data.actions.remove(a)
    if arm.animation_data:
        arm.animation_data_clear()
    arm.name = name
    return arm
FINAL = import_ual("UAL_Final")
TMP = import_ual("UAL_Tmp")
UALREST = {b.name: (FINAL.matrix_world @ b.head_local, FINAL.matrix_world @ b.tail_local) for b in FINAL.data.bones}
ual_parent = {b.name: (b.parent.name if b.parent else None) for b in FINAL.data.bones}
ual_children = {b.name: [c.name for c in b.children] for b in FINAL.data.bones}
order = []
def walk(n):
    order.append(n)
    for c in ual_children[n]:
        walk(c)
for n, p in ual_parent.items():
    if p is None:
        walk(n)

Smw = S.matrix_world
def s_head(b): return Smw @ S.data.bones[b].head_local
def s_tail(b): return Smw @ S.data.bones[b].tail_local
mapped = {u: s for u, s in bmap.items() if s in S.data.bones}
# global ratio: source pelvis height / UAL pelvis height
r_glob = s_head(mapped["pelvis"]).z / UALREST["pelvis"][0].z if mapped.get("pelvis") else 1.0

# joint positions for the Tmp rig in the source rest pose
def first_mapped_desc(n):
    for c in ual_children[n]:
        if c in mapped:
            return c
        d = first_mapped_desc(c)
        if d:
            return d
    return None
pos = {}
for n in order:
    if n in mapped:
        pos[n] = s_head(mapped[n]); continue
    p = ual_parent[n]
    a = p
    while a and a not in mapped:
        a = ual_parent[a]
    d = first_mapped_desc(n)
    if a and d:
        A, D = UALREST[a][0], UALREST[d][0]; P = UALREST[n][0]
        t = max(0.0, min(1.0, (P - A).dot(D - A) / max((D - A).length_squared, 1e-9)))
        pos[n] = pos[a].lerp(s_head(mapped[d]), t)
    elif p:
        pos[n] = pos[p] + (UALREST[n][0] - UALREST[p][0]) * r_glob
    else:
        pos[n] = UALREST[n][0] * r_glob

def tail_dir(n):
    if n in mapped:
        return (s_tail(mapped[n]) - s_head(mapped[n])).normalized()
    kids = [c for c in ual_children[n] if "leaf" not in c]
    if kids:
        v = pos[kids[0]] - pos[n]
        if v.length > 1e-6:
            return v.normalized()
    p = ual_parent[n]
    return (UALREST[n][1] - UALREST[n][0]).normalized()

bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = TMP; TMP.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
inv = TMP.matrix_world.inverted()
for n in order:
    eb = TMP.data.edit_bones[n]
    L = max((UALREST[n][1] - UALREST[n][0]).length * r_glob, 0.005)
    eb.head = inv @ pos[n]
    eb.tail = inv @ (pos[n] + tail_dir(n) * L)
bpy.ops.object.mode_set(mode="OBJECT")

# ---- meshes: weights onto Tmp ------------------------------------------------
all_show = re.compile("|".join("(%s)" % v["show"] for v in cfg["variants"]))
meshes = [o for o in sc.objects if o.type == "MESH" and all_show.search(o.name)]
for o in meshes:
    if cfg.get("autotex"):
        autotex.fix(o)
    # bake object transform, keep existing armature deform info
    for m in list(o.modifiers):
        if m.type != "ARMATURE":
            o.modifiers.remove(m)
if cfg["weights"] == "map":
    inv_map = {s: u for u, s in mapped.items()}
    inv_map.update(cfg.get("merge", {}))
    for o in meshes:
        for sgrp, bones in cfg.get("split", {}).items():
            g = o.vertex_groups.get(sgrp)
            if not g:
                continue
            zs = [pos[b].z for b in bones]
            tgt = [o.vertex_groups.get(b) or o.vertex_groups.new(name=b) for b in bones]
            mw = o.matrix_world
            for v in o.data.vertices:
                w = next((x.weight for x in v.groups if x.group == g.index), 0.0)
                if w <= 0:
                    continue
                z = (mw @ v.co).z
                # piecewise-linear blend between consecutive bones by height
                if z <= zs[0]:
                    parts = {0: 1.0}
                elif z >= zs[-1]:
                    parts = {len(zs) - 1: 1.0}
                else:
                    i = max(j for j in range(len(zs)) if zs[j] <= z)
                    t = (z - zs[i]) / max(zs[i + 1] - zs[i], 1e-6)
                    parts = {i: 1 - t, i + 1: t}
                for i, f in parts.items():
                    tgt[i].add([v.index], w * f, "ADD")
            o.vertex_groups.remove(g)
        for g in list(o.vertex_groups):
            new = inv_map.get(g.name)
            if new is None:
                continue
            ex = o.vertex_groups.get(new)
            if ex and ex != g:
                for v in o.data.vertices:
                    for x in v.groups:
                        if x.group == g.index:
                            ex.add([v.index], x.weight, "ADD")
                o.vertex_groups.remove(g)
            else:
                g.name = new
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.parent = None
        mwc = o.matrix_world.copy(); o.matrix_world = mwc
        md = o.modifiers.new("UAL", "ARMATURE"); md.object = TMP
else:
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        mwc = o.matrix_world.copy(); o.parent = None; o.matrix_world = mwc
        o.vertex_groups.clear()
        o.select_set(True)
    for b in TMP.data.bones:
        b.use_deform = "leaf" not in b.name and b.name != "root"
    bpy.context.view_layer.objects.active = TMP; TMP.select_set(True)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for o in meshes:
        print("auto weights", o.name, len(o.vertex_groups))
        for rx, bone in cfg.get("rigid", {}).items():
            if re.search(rx, o.name):
                o.vertex_groups.clear(); g = o.vertex_groups.new(name=bone)
                g.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
                print("rigid", o.name, "->", bone)

# ---- pose Tmp into the UAL T-pose (directions), bake meshes -----------------
TMP.data.pose_position = "POSE"
bpy.context.view_layer.objects.active = TMP
for n in order:
    if "leaf" in n or ual_parent[n] is None or (n == "pelvis"):
        continue
    pb = TMP.pose.bones[n]
    bpy.context.view_layer.update()
    M = TMP.matrix_world @ pb.matrix
    cur = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
    want = (UALREST[n][1] - UALREST[n][0]).normalized()
    q = cur.rotation_difference(want)
    h = M.to_translation()
    Mn = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ M
    pb.matrix = TMP.matrix_world.inverted() @ Mn
bpy.context.view_layer.update()
posed = {n: TMP.matrix_world @ TMP.pose.bones[n].head for n in order}
for o in meshes:
    bpy.context.view_layer.objects.active = o
    for m in o.modifiers:
        if m.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=m.name)
    # bake the object transform into the vertices
    o.data.transform(o.matrix_world); o.matrix_world = Matrix()

# ---- scale to UAL hip height and build the final fitted skeleton --------------
k = UALREST["pelvis"][0].z / posed["pelvis"].z
off = Vector((UALREST["pelvis"][0].x - posed["pelvis"].x * k, UALREST["pelvis"][0].y - posed["pelvis"].y * k, 0))
S_ = Matrix.Translation(off) @ Matrix.Scale(k, 4)
print("DBG k", k, posed["pelvis"], posed["Head"], [(o.name, max((o.matrix_world @ Vector(c)).z for c in o.bound_box), min((o.matrix_world @ Vector(c)).z for c in o.bound_box)) for o in meshes])
for o in meshes:
    o.data.transform(S_)
fit = {n: S_ @ posed[n] for n in order}
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = FINAL; FINAL.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
finv = FINAL.matrix_world.inverted()
for n in order:
    if ual_parent[n] is None:
        continue
    eb = FINAL.data.edit_bones[n]
    v = eb.tail - eb.head
    h = finv @ fit[n]
    eb.head = h; eb.tail = h + v  # translation only: rest orientation stays exactly UAL
bpy.ops.object.mode_set(mode="OBJECT")
for o in meshes:
    for m in list(o.modifiers):
        o.modifiers.remove(m)
    o.parent = FINAL
    o.matrix_parent_inverse = FINAL.matrix_world.inverted()
    md = o.modifiers.new("Armature", "ARMATURE"); md.object = FINAL
    # drop empty/unknown groups
    for g in list(o.vertex_groups):
        if g.name not in FINAL.data.bones:
            o.vertex_groups.remove(g)
bpy.data.objects.remove(TMP, do_unlink=True)

# recolour images toward the warm painted palette (multiply)
for rx, rgb in cfg.get("tint_images", {}).items():
    for img in bpy.data.images:
        if img.size[0] and re.search(rx, os.path.basename(img.filepath) or img.name):
            px = list(img.pixels)
            for c in range(3):
                px[c::4] = [v * rgb[c] for v in px[c::4]]
            img.pixels = px; img.pack(); print("tinted", img.name)
# textures <= max_tex
mt = cfg.get("max_tex", 1024)
for img in bpy.data.images:
    if img.size[0] > mt or img.size[1] > mt:
        f = mt / max(img.size)
        img.scale(max(1, int(img.size[0] * f)), max(1, int(img.size[1] * f)))
        img.pack()

for o in list(sc.objects):
    if o.type == "MESH" and o not in meshes and (o.parent == FINAL or re.match(r"^(Icosphere|Mannequin)", o.name)):
        bpy.data.objects.remove(o, do_unlink=True)
FINAL.name = "Armature"; FINAL.data.name = "Armature"
# mesh names must not collide with bone names (Godot would rename the bone)
for o in meshes:
    if o.name in FINAL.data.bones or o.name.lower() in [b.name.lower() for b in FINAL.data.bones]:
        o["orig"] = o.name; o.name = "Mesh_" + o.name
# ---- export variants ----
os.makedirs(cfg["out_dir"], exist_ok=True)
report = []
dg = bpy.context.evaluated_depsgraph_get()
for v in cfg["variants"]:
    rx = re.compile(v["show"])
    parts = [o for o in meshes if rx.search(o.get("orig", o.name))]
    if not parts:
        print("EMPTY variant", v["name"]); continue
    bpy.ops.object.select_all(action="DESELECT")
    FINAL.select_set(True)
    for o in parts:
        o.select_set(True)
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in parts)
    out = os.path.join(cfg["out_dir"], cfg.get("prefix", "") + v["name"] + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=False,
                              export_draco_mesh_compression_enable=False, export_yup=True,
                              export_image_format="AUTO")
    h = max((o.matrix_world @ Vector(c)).z for o in parts for c in o.bound_box)
    report.append(dict(name=v["name"], file=os.path.basename(out), tris=tris, parts=[o.name for o in parts],
                       height_model_units=round(h, 3), max_tex=max([max(i.size) for i in bpy.data.images if i.users] + [0])))
    print("VARIANT", json.dumps(report[-1]))
json.dump(report, open(os.path.join(cfg["out_dir"], cfg.get("prefix", "") + "report.json"), "w"), indent=1)
