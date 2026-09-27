# Retarget humanoid clips from any source rig onto the Quaternius UAL skeleton
# (exact UAL1 rest orientations, which the MakeHuman villagers in
# kingdom/assets/generated/characters/ also use), then export a GLB that has the
# UAL armature + mannequin mesh + the retargeted clips, so it can simply be
# appended to Assets.UAL_FILES in scripts/world/assets.gd.
#
# usage: blender -b --python retarget_to_ual.py -- <config.json>
# config: {"source": path(.glb/.gltf/.fbx/.blend), "ual": path to UAL1_Standard.glb,
#          "out": out.glb, "map": {"ual_bone": "source_bone", ...},
#          "include": regex (optional), "exclude": regex (optional),
#          "rename": {"src action": "NewName"} (optional), "strip_prefix": "..." (optional),
#          "loop": regex of NEW names that loop (gets _Loop suffix, Godot strips it and loops),
#          "prefix": "" (optional prefix for new clip names),
#          "root_motion": false (keep pelvis horizontal travel? default false = in place)}
#
# Method: for every frame, each mapped bone gets the source bone's world-space
# rotation change from its (direction-matched) rest; unmapped bones follow
# their parent rigidly. The pelvis height is scaled by the hip-height ratio.
import bpy, sys, json, re, os, math
from mathutils import Matrix, Quaternion, Vector

cfg = json.load(open(sys.argv[sys.argv.index("--") + 1:][0], encoding="utf-8"))
src_path = cfg["source"]

# ---- load source ----------------------------------------------------------
ext = os.path.splitext(src_path)[1].lower()
if ext == ".blend":
    bpy.ops.wm.open_mainfile(filepath=src_path)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src_path)
    else:
        bpy.ops.import_scene.gltf(filepath=src_path)
scene = bpy.context.scene
src_actions = list(bpy.data.actions)
src_arm = [o for o in scene.objects if o.type == "ARMATURE"]
src_arm = cfg.get("source_armature") and bpy.data.objects[cfg["source_armature"]] or max(src_arm, key=lambda o: len(o.data.bones))
# Drop constraints/drivers that could fight the action (IK rigs).
for pb in src_arm.pose.bones:
    for c in list(pb.constraints):
        if cfg.get("keep_constraints"):
            break
        pb.constraints.remove(c)

# ---- load target (UAL) ----------------------------------------------------
before = set(bpy.data.objects)
before_actions = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=cfg["ual"])
new_objs = [o for o in bpy.data.objects if o not in before]
tgt_arm = [o for o in new_objs if o.type == "ARMATURE"][0]
for a in list(bpy.data.actions):
    if a not in before_actions:
        bpy.data.actions.remove(a)
if tgt_arm.animation_data:
    tgt_arm.animation_data.action = None
    for tr in list(tgt_arm.animation_data.nla_tracks):
        tgt_arm.animation_data.nla_tracks.remove(tr)
tgt_arm.name = "Armature"

bmap = cfg["map"]  # ual -> source
src_mw = src_arm.matrix_world.copy()
tgt_mw = tgt_arm.matrix_world.copy()
src_mw_rot = src_mw.to_quaternion()
tgt_mw_rot = tgt_mw.to_quaternion()

def facing(arm, foot, ball, mw):
    b1 = arm.data.bones.get(foot); b2 = arm.data.bones.get(ball)
    if not b1 or not b2:
        return None
    d = (mw @ b2.head_local) - (mw @ b1.head_local)
    d.z = 0
    return d.normalized()

# Align source facing to target facing (yaw only).
yaw = Quaternion()
fs = facing(src_arm, bmap.get("foot_l"), bmap.get("ball_l"), src_mw)
ft = facing(tgt_arm, "foot_l", "ball_l", tgt_mw)
if fs and ft and fs.length > 0 and ft.length > 0:
    yaw = fs.rotation_difference(ft)
    print("facing yaw deg", math.degrees(yaw.angle))

def world_rest_rot(arm, mw_rot, bname):
    return mw_rot @ arm.data.bones[bname].matrix_local.to_quaternion()

def world_dir(arm, mw, bname):
    b = arm.data.bones[bname]
    return ((mw @ b.tail_local) - (mw @ b.head_local)).normalized()

# Direction-matched target rest (world): rotate each mapped target bone so its
# direction matches the source bone's rest direction, parents first.
tb = tgt_arm.data.bones
order = []
def walk(b):
    order.append(b.name)
    for c in b.children:
        walk(c)
for r in [b for b in tb if b.parent is None]:
    walk(r)

rest_t = {n: world_rest_rot(tgt_arm, tgt_mw_rot, n) for n in order}
matched = {}
for n in order:
    b = tb[n]
    s = bmap.get(n)
    if s and s in src_arm.data.bones and cfg.get("match_directions", True) and "leaf" not in n:
        dt = world_dir(tgt_arm, tgt_mw, n)
        ds = yaw @ world_dir(src_arm, src_mw, s)
        matched[n] = dt.rotation_difference(ds) @ rest_t[n]
    elif b.parent is not None:
        p = b.parent.name
        matched[n] = matched[p] @ (rest_t[p].inverted() @ rest_t[n])
    else:
        matched[n] = rest_t[n]

src_rest = {s: yaw @ world_rest_rot(src_arm, src_mw_rot, s) for s in bmap.values() if s in src_arm.data.bones}
missing = [s for s in bmap.values() if s not in src_arm.data.bones]
if missing:
    print("WARNING source bones missing:", missing)

# hip height ratio
tp = tgt_mw @ tb["pelvis"].head_local
sp_name = bmap.get("pelvis")
sp = src_mw @ src_arm.data.bones[sp_name].head_local
k = tp.z / sp.z if sp.z else 1.0
print("hip scale", k)

inc = re.compile(cfg["include"]) if cfg.get("include") else None
exc = re.compile(cfg["exclude"]) if cfg.get("exclude") else None
loop_re = re.compile(cfg["loop"]) if cfg.get("loop") else None
rename = cfg.get("rename", {})

for pb in tgt_arm.pose.bones:
    pb.rotation_mode = "QUATERNION"
if not src_arm.animation_data:
    src_arm.animation_data_create()
if not tgt_arm.animation_data:
    tgt_arm.animation_data_create()

made = []
for act in src_actions:
    if inc and not inc.search(act.name):
        continue
    if exc and exc.search(act.name):
        continue
    name = rename.get(act.name, act.name)
    if cfg.get("strip_prefix") and name.startswith(cfg["strip_prefix"]):
        name = name[len(cfg["strip_prefix"]):]
    name = re.sub(r"[^A-Za-z0-9_]+", "_", name).strip("_")
    name = cfg.get("prefix", "") + name
    base_name = name
    if loop_re and loop_re.search(base_name) and not name.endswith("_Loop"):
        name += "_Loop"
    src_arm.animation_data.action = act
    if hasattr(src_arm.animation_data, "action_slot") and len(act.slots):
        src_arm.animation_data.action_slot = act.slots[0]
    f0, f1 = int(math.floor(act.frame_range[0])), int(math.ceil(act.frame_range[1]))
    new = bpy.data.actions.new("__rt__" + name)
    new.use_fake_user = True
    tgt_arm.animation_data.action = new
    prev = {}
    pelvis0 = None
    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        want = {}
        for n in order:
            b = tb[n]
            s = bmap.get(n)
            if s and s in src_rest:
                cur = yaw @ src_mw_rot @ src_arm.pose.bones[s].matrix.to_quaternion()
                want[n] = cur @ src_rest[s].inverted() @ matched[n]
            elif b.parent is not None:
                p = b.parent.name
                want[n] = want[p] @ (matched[p].inverted() @ matched[n])
            else:
                want[n] = tgt_mw_rot  # root stays at rest
        for n in order:
            b = tb[n]
            pb = tgt_arm.pose.bones[n]
            rest_b = b.matrix_local.to_quaternion()
            m_b = tgt_mw_rot.inverted() @ want[n]  # armature space
            if b.parent is not None:
                rest_p = b.parent.matrix_local.to_quaternion()
                m_p = tgt_mw_rot.inverted() @ want[b.parent.name]
                q = rest_b.inverted() @ rest_p @ m_p.inverted() @ m_b
            else:
                q = rest_b.inverted() @ m_b
            q.normalize()
            if n in prev:
                q.make_compatible(prev[n])
            prev[n] = q
            pb.rotation_quaternion = q
            pb.keyframe_insert("rotation_quaternion", frame=f - f0)
            if n == "pelvis":
                sw = yaw @ (src_mw @ src_arm.pose.bones[sp_name].head)
                if pelvis0 is None:
                    pelvis0 = sw.copy()
                pos = Vector((sw.x, sw.y, sw.z)) * k
                if not cfg.get("root_motion", False):
                    # in place: keep the sway around the first frame, drop travel
                    pos.x = tp.x + (sw.x - pelvis0.x) * k
                    pos.y = tp.y + (sw.y - pelvis0.y) * k
                # armature-space target head position -> basis location
                pos_arm = tgt_mw.inverted() @ pos
                parent_rest = b.parent.matrix_local if b.parent else Matrix()
                # pose of parent (root) is rest, so: head = parent_rest @ (parent_rest^-1 @ rest) @ basis
                local = b.matrix_local.inverted() @ pos_arm
                pb.location = local
                pb.keyframe_insert("location", frame=f - f0)
    made.append((name, f1 - f0, new))
    print("retargeted", act.name, "->", name, f1 - f0 + 1, "frames")

# ---- export target only ------------------------------------------------------
tgt_arm.animation_data.action = None
for pb in tgt_arm.pose.bones:
    pb.rotation_quaternion = Quaternion(); pb.location = Vector()
bpy.ops.object.select_all(action="DESELECT")
keep = [tgt_arm] + [o for o in new_objs if o.type == "MESH"]
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = tgt_arm
# Only our actions should be exported: remove all source actions.
src_arm.animation_data.action = None
for a in src_actions:
    try:
        bpy.data.actions.remove(a)
    except Exception:
        pass
# Rename to the final names and put each on its own NLA track (one glTF animation per track).
tgt_arm.animation_data.action = None
for name, _, a in made:
    a.name = name
    tr = tgt_arm.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 0, a)
    tr.mute = False
for name, _, a in made[:2]:
    cbs = [cb for L in a.layers for s in L.strips for cb in s.channelbags]
    print("DEBUG", name, [s.identifier for s in a.slots], sum(len(cb.fcurves) for cb in cbs), [len(f.keyframe_points) for cb in cbs for f in cb.fcurves][:5])
bpy.ops.export_scene.gltf(filepath=cfg["out"], export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_draco_mesh_compression_enable=False,
                          export_apply=False, export_yup=True)
print("EXPORTED", cfg["out"], len(made), "clips")
json.dump([[m[0], m[1]] for m in made], open(cfg["out"] + ".clips.json", "w"), indent=0)
