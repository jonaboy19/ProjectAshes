"""Build the Quaternius-based animals (CC0) into mobile-ready GLBs sharing one palette atlas.
Run: blender -b --python build_quaternius.py -- <incoming_dir> <out_dir> [species ...]"""
import bpy, bmesh, sys, os, math, json, mathutils
sys.path.insert(0, os.path.dirname(__file__))
import animlib as L

args = sys.argv[sys.argv.index("--") + 1:]
INC, OUT = args[0], args[1]
ONLY = set(args[2:])
UAA = os.path.join(INC, "quaternius/ultimate-animated-animals/glTF")

UAA_ANIMS = {"Idle": "Idle", "Idle_2": "Idle_Alt", "Idle_Headlow": "Idle_HeadLow", "Idle_2_HeadLow": "Idle_HeadLow",
             "Walk": "Walk", "Gallop": "Run", "Eating": "Eat", "Death": "Death",
             "Attack_Headbutt": "Attack", "Attack": "Attack", "Attack_Kick": "Attack_Kick",
             "Idle_HitReact1": "Hit", "Idle_HitReact2": "Hit_Alt", "Gallop_Jump": "Jump", "Jump_toIdle": "Jump_Land",
             "Jump_ToIdle": "Jump_Land"}
EYES = {"Eye_Black": "black", "Eyes_Black": "black", "Eye_Dark": "black", "Eyes_Pupil": "black", "Eyes": "black",
        "Eye_White": "eye_white", "Eyes_White": "eye_white", "Hooves": "hoof", "Horns": "horn"}

def M(**kw):
    d = dict(EYES); d.update(kw); return d

SPECIES = {
 "horse_riding": dict(src="Horse.gltf", shoulder=1.6, cmap=M(Main="bay", Main_Dark="bay_dark", Main_Light="chestnut", Hair="mane_black", Muzzle="face_dark")),
 "horse_grey":   dict(src="Horse_White.gltf", shoulder=1.55, cmap=M(Main="grey_horse", Main_Light="grey_dark", Hair="cream", Muzzle="grey_dark")),
 "horse_draft":  dict(src="Horse.gltf", shoulder=1.75, width=1.22, cmap=M(Main="chestnut", Main_Dark="bay", Main_Light="cream", Hair="cream", Muzzle="face_dark")),
 "donkey":       dict(src="Donkey.gltf", shoulder=1.15, cmap=M(Main="donkey", Main_Dark="face_dark", Main_Light="donkey_lt", Hair="mane_black", Muzzle="donkey_lt")),
 "cow":          dict(src="Cow.gltf", shoulder=1.4, cmap=M(Main="cow_brown", Main_Light="cow_white", Muzzle="muzzle")),
 "ox":           dict(src="Bull.gltf", shoulder=1.3, cmap=M(Main="ox_dark", Main_Light="cow_brown", Muzzle="face_dark")),
 "deer":         dict(src="Deer.gltf", shoulder=1.0, cmap=M(Main="deer", Main_Light="deer_lt", Main_Dark="face_dark", Eye_Lighter="eye_white")),
 "goat":         dict(src="Deer.gltf", shoulder=0.72, cmap=M(Main="goat", Main_Light="white", Main_Dark="goat_brown", Eye_Lighter="eye_white"), kit="goat"),
 "stag":         dict(src="Stag.gltf", shoulder=1.3, cmap={"Material": "deer", "Material.001": "hoof", "Material.003": "deer_lt", "Material.010": "bay_dark", "Material.011": "black"}, objdefault={"Stag_Horns": "antler"}),
 "fox":          dict(src="Fox.gltf", shoulder=0.4, cmap=M(Main="fox", Main_Light="fox_lt", Grey="fox_dark", Black="fox_dark")),
 "dog":          dict(src="ShibaInu.gltf", shoulder=0.55, cmap=M(Main="dog_tan", Main_Light="dog_lt", Black="dog_dark")),
 "sheepdog":     dict(src="Husky.gltf", shoulder=0.55, cmap={"Material": "face_dark", "Material.001": "white", "Material.002": "black", "Material.003": "white", "Material.006": "black"}),
}

def head_region(obj, bone="Head"):
    vg = obj.vertex_groups.get(bone)
    mw = obj.matrix_world
    pts = [mw @ v.co for v in obj.data.vertices if any(g.group == vg.index and g.weight > 0.5 for g in v.groups)]
    mn = mathutils.Vector(map(min, *pts)); mx = mathutils.Vector(map(max, *pts))
    return mn, mx

def add_part(obj, verts_world, faces, bone, colour, t=0.6):
    """append geometry (world coords) to obj, weighted 100% to bone, painted with palette colour."""
    me = obj.data; inv = obj.matrix_world.inverted()
    bm = bmesh.new(); bm.from_mesh(me)
    uvl = bm.loops.layers.uv.get("atlas")
    dl = bm.verts.layers.deform.verify()
    gi = obj.vertex_groups[bone].index
    nv = [bm.verts.new(inv @ mathutils.Vector(v)) for v in verts_world]
    for v in nv: v[dl][gi] = 1.0
    for f in faces:
        try:
            face = bm.faces.new([nv[i] for i in f])
        except ValueError:
            continue
        face.smooth = False
        for i, lp in enumerate(face.loops):
            lp[uvl].uv = L.PAL.uv_for(colour, t + 0.3 * (lp.vert.co.z > 0))
    bm.normal_update(); bm.to_mesh(me); bm.free()

def horn(base, side, length, radius, up, back):
    """curved 5-sided horn: returns verts, faces"""
    verts, faces = [], []
    seg = 4; ring = 5
    for s in range(seg + 1):
        t = s / seg
        r = radius * (1 - t) + 0.001
        cx = base[0] + side * length * 0.25 * t
        cy = base[1] + back * length * (t ** 1.6)
        cz = base[2] + up * length * math.sin(t * 1.3)
        for k in range(ring):
            a = 2 * math.pi * k / ring
            verts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.8, cz + r * math.sin(a) * 0.3))
    for s in range(seg):
        for k in range(ring):
            a = s * ring + k; b = s * ring + (k + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    return verts, faces

def kit_goat(obj):
    mn, mx = head_region(obj)
    w = mx.x - mn.x; d = mx.y - mn.y; h = mx.z - mn.z
    for side in (-1, 1):
        base = (side * w * 0.18, mn.y + d * 0.55, mx.z - h * 0.12)
        v, f = horn(base, side, h * 0.75, w * 0.11, 1.0, d * 0.9 / (h * 0.75))
        add_part(obj, v, f, "Head", "horn")
    # beard: small downward pyramid under the chin
    cx, cy, cz = 0.0, mn.y + d * 0.18, mn.z + h * 0.05
    r = w * 0.08; L_ = h * 0.35
    v = [(cx - r, cy - r, cz), (cx + r, cy - r, cz), (cx + r, cy + r, cz), (cx - r, cy + r, cz), (cx, cy + r * 0.5, cz - L_)]
    add_part(obj, v, [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)], "Head", "goat_brown", 0.2)

report = {}
for name, cfg in SPECIES.items():
    if ONLY and name not in ONLY:
        continue
    L.reset()
    L.import_any(os.path.join(UAA, cfg["src"]))
    arm = L.armature()
    L.bone_parented_to_skin(arm)
    L.clean_strays(arm)
    L.uaa_reduce(arm)
    for o in L.skinned_meshes(arm):
        default = cfg.get("objdefault", {}).get(o.name)
        L.paint(o, {} if default else cfg.get("cmap", {}), default=default,
                vc_candidates=cfg.get("vc"), remap=cfg.get("remap"))
    obj = L.join_meshes(arm)
    if cfg.get("width"):
        mw = obj.matrix_world; inv = mw.inverted()
        for v in obj.data.vertices:
            w = mw @ v.co; w.x *= cfg["width"]; v.co = inv @ w
    if cfg.get("kit") == "goat":
        kit_goat(obj)
    L.rename_actions(UAA_ANIMS)
    size = L.fit(arm, [obj], shoulder=("Neck1", cfg["shoulder"] * 0.88))
    st = L.stats(arm); st["size_m"] = [round(x, 2) for x in size]
    out = os.path.join(OUT, name + ".glb")
    L.export_glb(out, arm)
    st["kb"] = round(os.path.getsize(out) / 1024)
    report[name] = st
    print("BUILT", name, json.dumps(st))
json.dump(report, open(os.path.join(OUT, "_build_quaternius.json"), "w"), indent=1)
