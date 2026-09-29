# COPY of ../polish/render_clips.py with the props matched to author_traversal_v2.py (ladder rungs at 0.3k, wall holds on the
# four limb lines, stirrups) and RC_W / RC_H environment variables for the tile size.
# Render stop-motion frames + metrics for every clip of a UAL-skeleton clip GLB, in Blender (no Godot).
#   blender -b -P render_clips.py -- <clips.glb> <out_dir> [--clips=A,B] [--fps=12] [--metrics-only]
# Puts the clips on the Quaternius mannequin (UAL1_Standard.glb), workbench render, two views per frame
# (side: the character faces screen-right, and front), camera follows the pelvis over a ruled floor
# (1 m thick lines, 0.5 m thin lines), so sliding feet show against the grid.
# Output: <out_dir>/<clip>/_v/s########.png + f########.png (side / front) and <out_dir>/metrics.json.
import bpy, sys, os, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GLB = os.path.abspath(argv[0]); OUT = os.path.abspath(argv[1])
opt = {}
for a in argv[2:]:
    if a.startswith("--"):
        k, _, v = a[2:].partition("=")
        opt[k] = v or "1"
ONLY = opt["clips"].split(",") if "clips" in opt else None
FPS_R = opt.get("fps")
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))
W, H = int(os.environ.get('RC_W', 240)), int(os.environ.get('RC_H', 330))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
bpy.ops.import_scene.gltf(filepath=UAL)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for o in [o for o in bpy.data.objects if o.type == "MESH" and o.name != "Mannequin"]:
    bpy.data.objects.remove(o)
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
before_o = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
acts = {a.name: a for a in bpy.data.actions}
for a in acts.values():
    a.use_fake_user = True
for o in list(bpy.data.objects):
    if o not in before_o:
        bpy.data.objects.remove(o)
arm.animation_data_create()
mann = bpy.data.objects["Mannequin"]


def assign(act):
    # bones without a track in the new clip keep the pose of the previous clip in Blender: reset them to rest first
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.scale = (1, 1, 1)
    arm.animation_data.action = act
    if act is not None and len(act.slots):
        arm.animation_data.action_slot = act.slots[0]


def mk_obj(name, verts, faces, color):
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces)
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob); ob.color = color
    return ob


S = 30.0
floor = mk_obj("floor", [(-S, -S, 0), (S, -S, 0), (S, S, 0), (-S, S, 0)], [(0, 1, 2, 3)], (0.62, 0.72, 0.55, 1))
v, f = [], []


def strip(x0, y0, x1, y1, z=0.002):
    i = len(v); v.extend([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]); f.append((i, i + 1, i + 2, i + 3))


k = -30.0
while k <= 30.0:
    w = 0.012 if abs(k - round(k)) < 1e-6 else 0.006
    strip(k - w, -S, k + w, S); strip(-S, k - w, S, k + w)
    k += 0.5
lines = mk_obj("lines", v, f, (0.16, 0.22, 0.14, 1))
mann.color = (0.98, 0.78, 0.55, 1)
sc.render.engine = "BLENDER_WORKBENCH"
sh = sc.display.shading
sh.light = "STUDIO"; sh.color_type = "OBJECT"; sh.show_shadows = True; sh.shadow_intensity = 0.55
sh.show_object_outline = True; sh.object_outline_color = (0.05, 0.05, 0.05)
sc.display.render_aa = "8"
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.66, 0.80, 0.95)
sc.render.resolution_x, sc.render.resolution_y = W, H
sc.render.image_settings.file_format = "PNG"


def mk_cam(name):
    cd = bpy.data.cameras.new(name); cd.type = "ORTHO"; cd.clip_end = 200
    co = bpy.data.objects.new(name, cd); sc.collection.objects.link(co)
    return co


camS, camF = mk_cam("camS"), mk_cam("camF")



# ---- optional obstacle props for the traversal clips (--props): sizes match the handoff (author_traversal.py)
def box(name, x0, x1, y0, y1, z0, z1, color):
    v = [(x, y, z) for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    fcs = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return mk_obj(name, v, fcs, color)


WOOD = (0.62, 0.42, 0.22, 1); STONE = (0.62, 0.6, 0.55, 1); IRON = (0.35, 0.35, 0.4, 1)


def add_props(clip):
    o = []
    if clip.startswith("Vault"):
        o.append(box("vbox", -0.9, 0.9, -1.4, -0.9, 0.0, 0.92, WOOD))
    elif clip.startswith("Ladder"):
        for sx in (-0.27, 0.27):
            o.append(box("rail", sx - 0.03, sx + 0.03, -0.34, -0.28, 0.0, 12.0, WOOD))
        z = 0.0
        while z < 12:                       # rungs every 0.3 m at z = 0.3k (author_traversal_v2 climb geometry)
            o.append(box("rung", -0.27, 0.27, -0.33, -0.29, z - 0.02, z + 0.02, STONE)); z += 0.3
    elif clip.startswith("Wall_Climb"):
        o.append(box("wall", -1.2, 1.2, -0.50, -0.36, -3.0, 12.0, STONE))
        # holds on the four limb lines (clips_climb.WALL): every 0.5 m per line; hands x +-0.30 (1.75 / 1.50 + 0.5k), feet x +-0.22 (0.10 / 0.34 + 0.5k)
        for x, z0, hand in ((0.30, 1.75, True), (-0.30, 1.50, True), (0.22, 0.10, False), (-0.22, 0.34, False)):
            k = -8
            while z0 + 0.5 * k < 12:
                zz = z0 + 0.5 * k
                if hand:
                    o.append(box("hold", x - 0.05, x + 0.05, -0.36, -0.30, zz - 0.03, zz + 0.03, WOOD))
                else:
                    o.append(box("hold", x - 0.05, x + 0.05, -0.36, -0.30, zz - 0.065, zz - 0.015, WOOD))
                k += 1
    elif clip.startswith("Ledge"):
        o.append(box("ledge", -3.0, 3.0, -0.9, -0.20, -1.0, 2.12, STONE))
    elif clip.startswith("Ride"):
        o.append(box("horse_body", -0.26, 0.26, -0.95, 0.85, 0.62, 1.02, (0.45, 0.28, 0.16, 1)))     # barrel 0.52 wide, back at 1.02, saddle to 1.12
        o.append(box("horse_neck", -0.12, 0.12, -1.25, -0.85, 1.0, 1.55, (0.45, 0.28, 0.16, 1)))
        o.append(box("horse_head", -0.10, 0.10, -1.55, -1.2, 1.2, 1.45, (0.4, 0.25, 0.14, 1)))
        for lx in (-0.18, 0.18):
            for ly in (-0.75, 0.6):
                o.append(box("horse_leg", lx - 0.05, lx + 0.05, ly - 0.05, ly + 0.05, 0.0, 0.62, (0.4, 0.25, 0.14, 1)))
        o.append(box("saddle", -0.15, 0.15, -0.3, 0.2, 1.02, 1.12, (0.25, 0.12, 0.08, 1)))     # saddle top 1.12 (handoff)
        for sx in (-1, 1):                  # stirrup tread under the ball of the foot (0.37, -0.10, 0.665) + strap
            o.append(box("stirrup", sx * 0.37 - 0.06, sx * 0.37 + 0.06, -0.16, -0.04, 0.625, 0.645, IRON))
            o.append(box("strap", sx * 0.37 - 0.01, sx * 0.37 + 0.01, -0.11, -0.09, 0.645, 1.12, IRON))
    return o


def wpos(n, tail=False):
    pb = arm.pose.bones[n]
    return arm.matrix_world @ (pb.tail if tail else pb.head)


TRACK = ["pelvis", "Head", "hand_l", "hand_r", "foot_l", "foot_r", "ball_l", "ball_r", "lowerarm_l", "lowerarm_r", "calf_l", "calf_r", "spine_03"]


def metrics(name, act, nf):
    rows = []
    for f in range(nf + 1):
        sc.frame_set(f)
        r = {n: wpos(n) for n in TRACK}
        r["root"] = wpos("root")
        r["thigh_l"] = wpos("thigh_l"); r["thigh_r"] = wpos("thigh_r")
        r["ankle_l"] = wpos("foot_l"); r["ankle_r"] = wpos("foot_r")
        rows.append(r)
    m = {}
    m["frames"] = nf + 1; m["seconds"] = round(nf / 30, 2)
    allz = [min(r["ball_l"].z, r["ball_r"].z, r["foot_l"].z, r["foot_r"].z) for r in rows]
    m["min_foot_z"] = round(min(allz), 3)
    m["min_foot_frame"] = allz.index(min(allz))
    m["pelvis_z_min"] = round(min(r["pelvis"].z for r in rows), 2)
    m["pelvis_z_max"] = round(max(r["pelvis"].z for r in rows), 2)
    m["pelvis_z0"] = round(rows[0]["pelvis"].z, 2); m["pelvis_z_end"] = round(rows[-1]["pelvis"].z, 2)

    def hipy(r):
        d = r["thigh_l"] - r["thigh_r"]
        return math.degrees(math.atan2(d.y, d.x))
    m["hip_yaw_start"] = round(hipy(rows[0])); m["hip_yaw_end"] = round(hipy(rows[-1]))
    p0, p1 = rows[0]["pelvis"], rows[-1]["pelvis"]
    m["pelvis_travel"] = [round(p1.x - p0.x, 2), round(p1.y - p0.y, 2)]
    r0, r1 = rows[0]["root"], rows[-1]["root"]
    m["root_travel"] = [round(r1.x - r0.x, 2), round(r1.y - r0.y, 2), round(r1.z - r0.z, 2)]
    slide = {"l": 0, "r": 0}; maxsl = 0.0
    for s in ("l", "r"):
        for i in range(1, len(rows)):
            a, b = rows[i - 1], rows[i]
            if a["ball_" + s].z < 0.07 and b["ball_" + s].z < 0.07:
                sp = math.hypot(b["ball_" + s].x - a["ball_" + s].x, b["ball_" + s].y - a["ball_" + s].y) * 30
                if sp > 0.15:
                    slide[s] += 1; maxsl = max(maxsl, sp)
    m["slide_frames"] = slide; m["slide_max_mps"] = round(maxsl, 2)
    planted = sum(1 for r in rows if r["ball_l"].z < 0.07 or r["ball_r"].z < 0.07)
    m["planted_frac"] = round(planted / len(rows), 2)
    jm = 0; jn = ""; jf = 0
    for i in range(1, len(rows)):
        for n in TRACK:
            d = (rows[i][n] - rows[i - 1][n]).length
            if d > jm: jm, jn, jf = d, n, i
    m["max_jump_m"] = round(jm, 3); m["max_jump"] = "%s@%d" % (jn, jf)

    def rel(r): return {n: r[n] - Vector((r["pelvis"].x, r["pelvis"].y, 0)) for n in TRACK}
    a, b = rel(rows[0]), rel(rows[-1])
    m["loop_gap_m"] = round(max((a[n] - b[n]).length for n in TRACK), 3)

    def straight(r, s):
        l1 = (arm.pose.bones["calf_" + s].head - arm.pose.bones["thigh_" + s].head).length
        l2 = (arm.pose.bones["foot_" + s].head - arm.pose.bones["calf_" + s].head).length
        return (r["ankle_" + s] - r["thigh_" + s]).length / (l1 + l2)
    st = [min(straight(r, "l"), straight(r, "r")) for r in rows if r["ball_l"].z < 0.07 and r["ball_r"].z < 0.07]
    m["leg_straight_min"] = round(min(st), 2) if st else None
    m["leg_straight_mean"] = round(sum(st) / len(st), 2) if st else None
    m["extent_z"] = [round(min(min(r[n].z for n in TRACK) for r in rows), 2), round(max(max(r[n].z for n in TRACK) for r in rows), 2)]
    return m, rows


def render_clip(name, nf, rows, fps_r, base_dir, props=()):
    zs = [r[n].z for r in rows for n in TRACK]
    zmin, zmax = min(min(zs), 0.0), max(zs)
    span = max(2.3, (zmax - zmin) + 0.55)
    cz = (zmin + zmax) / 2 + 0.05
    cz = max(cz, span / 2 - 0.15)
    px = [r["pelvis"].x for r in rows]; py = [r["pelvis"].y for r in rows]

    def smooth(a, k=6):
        o = []
        for i in range(len(a)):
            lo, hi = max(0, i - k), min(len(a), i + k + 1); o.append(sum(a[lo:hi]) / (hi - lo))
        return o
    sx, sy = smooth(px), smooth(py)
    for c in (camS, camF):
        c.data.ortho_scale = span
    camS.data.clip_start = 19.4 if props else 0.1      # side view of a prop clip is a cut-away at x = -0.6
    TILT = 16
    camS.rotation_euler = (math.radians(90 - TILT), 0, math.radians(-90))
    camF.rotation_euler = (math.radians(90 - TILT), 0, 0)
    tmp = os.path.join(base_dir, name, "_v"); os.makedirs(tmp, exist_ok=True)
    n_out = int(math.floor(nf / 30 * fps_r + 1e-6)) + 1
    if "frames" in opt:                                  # --frames=17,20,24: render exactly these source frames (file index = frame number)
        todo = [(int(x), float(x)) for x in opt["frames"].split(",")]
    else:
        todo = [(i, min(nf, i * 30.0 / fps_r)) for i in range(n_out)]
    for i, fr in todo:
        sc.frame_set(int(round(fr)))
        k = min(len(rows) - 1, int(round(fr)))
        camS.location = Vector((0, sy[k], cz)) - camS.matrix_basis.to_3x3() @ Vector((0, 0, -20)); camF.location = Vector((sx[k], 0, cz)) - camF.matrix_basis.to_3x3() @ Vector((0, 0, -20))
        for tag, cam in (("s", camS), ("f", camF)):
            sc.camera = cam
            for pobj in props:
                pobj.display_type = "SOLID" if tag == "s" else "WIRE"
                pobj.hide_render = (tag == "f" and pobj.name.startswith(("wall", "ledge", "horse_neck", "horse_head")))   # do not hide the rider behind big blocks
            sc.render.filepath = os.path.join(tmp, "%s%08d.png" % (tag, i))
            bpy.ops.render.render(write_still=True)
    return n_out


def main():
    res = {}
    os.makedirs(OUT, exist_ok=True)
    for name, act in acts.items():
        if ONLY and name not in ONLY:
            continue
        assign(act)
        pr = add_props(name) if "props" in opt else []
        fr = act.frame_range
        nf = int(round(fr[1] - fr[0]))
        m, rows = metrics(name, act, nf)
        res[name] = m
        if "metrics-only" not in opt:
            fps_r = float(FPS_R) if FPS_R else max(5.0, min(15.0, 24.0 / max(m["seconds"], 0.1)))
            m["sheet_fps"] = fps_r
            render_clip(name, nf, rows, fps_r, OUT, pr)
        for o in pr:
            bpy.data.objects.remove(o)
        print("DONE", name, m["seconds"], m["min_foot_z"], m["slide_max_mps"], flush=True)
    json.dump(res, open(os.path.join(OUT, "metrics.json"), "w"), indent=1)


main()
