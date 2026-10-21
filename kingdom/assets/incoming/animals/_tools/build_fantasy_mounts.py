"""Build Rising Ashes Exclusive Fantasy Mounts (Draco-Horse & Abyssal Equine).
Run: blender -b --python build_fantasy_mounts.py -- <incoming_dir> <out_dir>"""
import bpy, bmesh, sys, os, math, json, mathutils
sys.path.insert(0, os.path.dirname(__file__))
import animlib as L

args = sys.argv[sys.argv.index("--") + 1:]
INC, OUT = args[0], args[1]
UAA = os.path.join(INC, "quaternius/ultimate-animated-animals/glTF")
os.makedirs(OUT, exist_ok=True)

UAA_ANIMS = {
    "Idle": "Idle", "Idle_2": "Idle_Alt", "Idle_Headlow": "Idle_HeadLow", "Idle_2_HeadLow": "Idle_HeadLow",
    "Walk": "Walk", "Gallop": "Run", "Eating": "Eat", "Death": "Death",
    "Attack_Headbutt": "Attack", "Attack": "Attack", "Attack_Kick": "Attack_Kick",
    "Idle_HitReact1": "Hit", "Idle_HitReact2": "Hit_Alt", "Gallop_Jump": "Jump", "Jump_toIdle": "Jump_Land",
    "Jump_ToIdle": "Jump_Land"
}
EYES = {"Eye_Black": "black", "Eyes_Black": "black", "Eye_Dark": "black", "Eyes_Pupil": "black", "Eyes": "black",
        "Eye_White": "eye_white", "Eyes_White": "eye_white", "Hooves": "hoof", "Horns": "horn"}

def M(**kw):
    d = dict(EYES); d.update(kw); return d

def head_region(obj, bone="Head"):
    vg = obj.vertex_groups.get(bone)
    mw = obj.matrix_world
    pts = [mw @ v.co for v in obj.data.vertices if any(g.group == vg.index and g.weight > 0.5 for g in v.groups)]
    mn = mathutils.Vector(map(min, *pts)); mx = mathutils.Vector(map(max, *pts))
    return mn, mx

def add_part(obj, verts_world, faces, bone, colour, t=0.6):
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

def draco_horn(base, side, length, radius, up=1.0, back=1.2):
    verts, faces = [], []
    seg = 5; ring = 5
    for s in range(seg + 1):
        t = s / seg
        r = radius * (1.0 - t) + 0.002
        cx = base[0] + side * length * 0.35 * t
        cy = base[1] + back * length * (t ** 1.4)
        cz = base[2] + up * length * math.sin(t * 1.2)
        for k in range(ring):
            a = 2 * math.pi * k / ring
            verts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.8, cz + r * math.sin(a) * 0.4))
    for s in range(seg):
        for k in range(ring):
            a = s * ring + k; b = s * ring + (k + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    return verts, faces

def add_dorsal_spines(obj, bone="Neck1", colour="rooster_gold", count=4):
    vg = obj.vertex_groups.get(bone)
    if not vg: return
    mw = obj.matrix_world
    pts = [mw @ v.co for v in obj.data.vertices if any(g.group == vg.index and g.weight > 0.4 for g in v.groups)]
    if not pts: return
    mn = mathutils.Vector(map(min, *pts)); mx = mathutils.Vector(map(max, *pts))
    mid_x = (mn.x + mx.x) * 0.5
    for i in range(count):
        frac = (i + 0.5) / count
        cy = mn.y + (mx.y - mn.y) * frac
        cz = mx.z + 0.02
        h = 0.12 + 0.05 * math.sin(frac * math.pi)
        w = 0.035
        v = [
            (mid_x - w, cy - w, cz),
            (mid_x + w, cy - w, cz),
            (mid_x + w, cy + w, cz),
            (mid_x - w, cy + w, cz),
            (mid_x, cy, cz + h)
        ]
        f = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
        add_part(obj, v, f, bone, colour, 0.7)

def kit_draco(obj):
    mn, mx = head_region(obj)
    w = mx.x - mn.x; d = mx.y - mn.y; h = mx.z - mn.z
    # Twin swept dragon horns
    for side in (-1, 1):
        base = (side * w * 0.22, mn.y + d * 0.65, mx.z - h * 0.08)
        v, f = draco_horn(base, side, h * 0.95, w * 0.14, up=1.1, back=d * 1.1 / (h * 0.95))
        add_part(obj, v, f, "Head", "rooster_gold")
    # Dorsal crest spines along neck
    add_dorsal_spines(obj, "Neck1", "rooster_gold", 4)

def kit_abyssal(obj):
    mn, mx = head_region(obj)
    w = mx.x - mn.x; d = mx.y - mn.y; h = mx.z - mn.z
    # Single celestial/abyssal spire horn
    base = (0.0, mn.y + d * 0.7, mx.z - h * 0.05)
    v, f = draco_horn(base, 0.0, h * 1.1, w * 0.12, up=1.3, back=-0.2)
    add_part(obj, v, f, "Head", "eye_white")
    add_dorsal_spines(obj, "Neck1", "crow_sheen", 3)

FANTASY_SPECIES = {
    "horse_draco": dict(
        src="Horse.gltf",
        shoulder=1.70,
        width=1.15,
        cmap=M(Main="ox_dark", Main_Dark="black", Main_Light="comb_red", Hair="rooster_tail", Muzzle="black"),
        kit="draco"
    ),
    "horse_abyssal": dict(
        src="Horse_White.gltf",
        shoulder=1.65,
        width=1.05,
        cmap=M(Main="crow", Main_Dark="black", Main_Light="crow_sheen", Hair="pigeon_dark", Muzzle="black"),
        kit="abyssal"
    ),
    "horse_armored_destrier": dict(
        src="Horse.gltf",
        shoulder=1.80,
        width=1.28,
        cmap=M(Main="bay_dark", Main_Dark="black", Main_Light="grey_horse", Hair="mane_black", Muzzle="grey_dark"),
        kit="draco"
    )
}

report = {}
for name, cfg in FANTASY_SPECIES.items():
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
    if cfg.get("kit") == "draco":
        kit_draco(obj)
    elif cfg.get("kit") == "abyssal":
        kit_abyssal(obj)
    L.rename_actions(UAA_ANIMS)
    size = L.fit(arm, [obj], shoulder=("Neck1", cfg["shoulder"] * 0.88))
    st = L.stats(arm); st["size_m"] = [round(x, 2) for x in size]
    out = os.path.join(OUT, name + ".glb")
    L.export_glb(out, arm)
    st["kb"] = round(os.path.getsize(out) / 1024)
    report[name] = st
    print("BUILT FANTASY MOUNT:", name, json.dumps(st))

json.dump(report, open(os.path.join(OUT, "_build_fantasy_mounts.json"), "w"), indent=2)
print("ALL FANTASY MOUNTS BUILT SUCCESSFULLY")
