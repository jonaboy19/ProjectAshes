"""Quaternius farm (sheep, pig), Animal Pack Vol.2 (cat), rat and river fish -> GLBs on the shared atlas.
blender -b --python build_other.py -- <incoming_dir> <sources_dir> <out_dir> [species ...]"""
import bpy, sys, os, math, json, mathutils
sys.path.insert(0, os.path.dirname(__file__))
import animlib as L

args = sys.argv[sys.argv.index("--") + 1:]
INC, SRC, OUT = args[0], args[1], args[2]
ONLY = set(args[3:])
FARM = os.path.join(INC, "quaternius/lowpoly-animated-animals/FBX")
X, Y, Z = (1, 0, 0), (0, 1, 0), (0, 0, 1)
report = {}

def finish(name, arm, extra=None):
    st = L.stats(arm)
    if extra: st.update(extra)
    out = os.path.join(OUT, name + ".glb")
    L.export_glb(out, arm)
    st["kb"] = round(os.path.getsize(out) / 1024)
    report[name] = st
    print("BUILT", name, json.dumps(st))

def eat_keys(neck, head, deg_n=35, deg_h=25, chew=6, n=48):
    ks = [(1, {}, {})]
    down = {neck: [(X, deg_n)], head: [(X, deg_h)]}
    ks.append((10, down, {}))
    for i, f in enumerate(range(16, n - 8, 6)):
        ks.append((f, {neck: [(X, deg_n)], head: [(X, deg_h + (chew if i % 2 else -chew))]}, {}))
    ks.append((n - 6, down, {}))
    ks.append((n, {}, {}))
    return ks

def death_keys(root, drop, extra=None, roll=88):
    """roll onto the side (around the forward axis) and settle"""
    extra = extra or {}
    k2 = {root: [(Y, roll * 0.4)]}; k2.update({b: [(a, d * 0.5)] for b, (a, d) in extra.items()})
    k3 = {root: [(Y, roll)]}; k3.update({b: [(a, d)] for b, (a, d) in extra.items()})
    return [(1, {}, {}), (8, k2, {root: (0, 0, -drop * 0.3)}), (18, k3, {root: (0, 0, -drop)}), (40, k3, {root: (0, 0, -drop)})]

# ------------------------------------------------------------------ farm sheep / pig
def farm(name, fbx, cmap, height):
    L.reset()
    L.import_any(os.path.join(FARM, "Cow.fbx"))
    cow = L.armature()
    cow_leg = (cow.data.bones["FrontUpLeg.R"].length + cow.data.bones["FrontLowLeg.R"].length)
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions): a.name = "COW_" + a.name.split("|")[-1]; a.use_fake_user = True
    L.import_any(os.path.join(FARM, fbx))
    arm = L.armature(); L.clean_strays(arm)
    leg = arm.data.bones["FrontUpLeg.R"].length + arm.data.bones["FrontLowLeg.R"].length
    L.copy_actions_from(None, arm, {"COW_Walk": "Walk", "COW_Run": "Run", "COW_Death": "Death", "COW_WalkSlow": "Walk_Slow"},
                        loc_scale=leg / cow_leg, skip=("Tail",))
    for a in list(bpy.data.actions):
        if a.name.startswith("COW_"): bpy.data.actions.remove(a)
    L.rename_actions({"Idle": "Idle", "Jump": "Jump", "Walk": "Walk", "Run": "Run", "Death": "Death", "Walk_Slow": "Walk_Slow"})
    for o in L.skinned_meshes(arm): L.paint(o, cmap)
    obj = L.join_meshes(arm)
    L.fit(arm, [obj], height=height)
    L.clear_nla(arm)
    L.proc_action(arm, "Eat", eat_keys("Neck", "Head", 40, 30))
    finish(name, arm)

# ------------------------------------------------------------------ cat (Animal Pack Vol.2)
def cat(name, body):
    L.reset()
    L.import_any(os.path.join(SRC, "quaternius-animal-pack-vol2/FBX/Cat.fbx"))
    arm = L.armature(); L.clean_strays(arm)
    L.merge_bones(arm, {b: None for b in ("IKFrontRight", "IKFrontLeft", "IKBackRight", "IKBackLeft")})
    L.rename_actions({"Idle": "Idle", "Walking": "Walk"})
    for o in L.skinned_meshes(arm):
        L.paint(o, {"Grey": body, "White": "white" if body != "white" else "cat_grey", "Pink": "pink_ear", "Black": "black"})
    obj = L.join_meshes(arm)
    L.fit(arm, [obj], height=0.30, yaw_deg=-90)
    L.clear_nla(arm)
    L.copy_action_scaled("Walk", "Run", 0.5)
    L.proc_action(arm, "Eat", eat_keys("Bone.002", "Bone.003", 30, 25))
    L.proc_action(arm, "Death", death_keys("Bone", 0.12, {"Bone.002": (X, -15), "Bone.004": (Z, 30)}))
    finish(name, arm)

# ------------------------------------------------------------------ rat
def rat(name):
    L.reset()
    L.import_any(os.path.join(SRC, "polypizza-quaternius/Rat_iltq5bVNaV.glb"))
    arm = L.armature(); L.clean_strays(arm)
    L.merge_bones(arm, {"Tail7": "Tail5", "Tail6": "Tail5"})
    L.rename_actions({"Rat_Idle": "Idle", "Rat_Walk": "Walk", "Rat_Run": "Run", "Rat_Death": "Death", "Rat_Attack": "Attack", "Rat_Jump": "Jump"})
    for o in L.skinned_meshes(arm): L.paint(o, {"Grey": "rat", "Pink": "rat_pink"})
    obj = L.join_meshes(arm)
    L.decimate_to(obj, 1450)
    L.fit(arm, [obj], length=0.42)
    L.clear_nla(arm)
    L.proc_action(arm, "Eat", eat_keys("Neck", "Head", 20, 25))
    finish(name, arm)

# ------------------------------------------------------------------ river fish
def fish(name, fbx, cmap, length):
    L.reset()
    L.import_any(os.path.join(SRC, "quaternius-animated-fish/FBX", fbx))
    arm = L.armature(); L.clean_strays(arm)
    L.rename_actions({"Swim": "Swim", "Swim.001": "Swim"})
    for o in L.skinned_meshes(arm): L.paint(o, cmap, grad=(0.75, 0.25))
    obj = L.join_meshes(arm)
    face = arm.matrix_world @ arm.data.bones["Face"].head_local
    root = arm.matrix_world @ arm.data.bones["Root"].head_local
    yaw = 0
    d = face - root
    if abs(d.x) > abs(d.y): yaw = -90 if d.x > 0 else 90
    elif d.y > 0: yaw = 180
    L.fit(arm, [obj], length=length, yaw_deg=yaw)
    L.clear_nla(arm)
    swim = bpy.data.actions["Swim"]
    L.copy_action_scaled("Swim", "Swim_Fast", 0.5)
    rb = arm.data.bones[0].name
    L.proc_action(arm, "Death", [(1, {}, {}), (12, {rb: [(Y, 100)]}, {rb: (0, 0, 0.05)}), (30, {rb: [(Y, 180)]}, {rb: (0, 0, 0.1)})])
    L.rename_actions({"Swim": "Idle", "Swim_Fast": "Swim_Fast", "Death": "Death"}, prefix_strip=False)
    bpy.data.actions["Idle"].copy().name = "Swim"
    bpy.data.actions["Swim"].use_fake_user = True
    finish(name, arm)

JOBS = {
 "sheep": lambda: farm("sheep", "Sheep.fbx", {"White": "wool", "Black": "face_dark"}, 1.05),
 "pig": lambda: farm("pig", "Pig.fbx", {"*": "pig_pink"}, 0.85),
 "cat": lambda: cat("cat", "cat_grey"),
 "cat_ginger": lambda: cat("cat_ginger", "cat_ginger"),
 "rat": lambda: rat("rat"),
 "fish_trout": lambda: fish("fish_trout", "Fish1.fbx", {"Top": "trout", "Bottom": "trout_belly", "Fins": "fin"}, 0.4),
 "fish_carp": lambda: fish("fish_carp", "Fish3.fbx", {"*": "carp"}, 0.5),
}
for k, job in JOBS.items():
    if ONLY and k not in ONLY: continue
    job()
old = {}
p = os.path.join(OUT, "_build_other.json")
if os.path.exists(p): old = json.load(open(p))
old.update(report); json.dump(old, open(p, "w"), indent=1)
