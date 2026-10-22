# Per-frame motion scan of every clip in a UAL-skeleton clip GLB (Blender, no Godot):
# world-space bone head position delta per 30 fps frame (also with the root motion removed = character space) and local-rotation delta per frame, for all body bones (no fingers).
#   blender -b -P scan_motion.py -- <clips.glb> <out.json> [--clips=A,B] [--top=4]
# Prints the worst offenders per clip. Thresholds of the polish pass: 0.12 m and 35 deg per frame (except intentional whips).
import bpy, sys, os, json, math
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
GLB = os.path.abspath(argv[0]); OUT = os.path.abspath(argv[1])
opt = dict((a[2:].partition("=")[0], a[2:].partition("=")[2]) for a in argv[2:] if a.startswith("--"))
ONLY = opt["clips"].split(",") if opt.get("clips") else None
TOP = int(opt.get("top", 4))
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.fps = 30
bpy.ops.import_scene.gltf(filepath=UAL)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
for a in list(bpy.data.actions):
    bpy.data.actions.remove(a)
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GLB)
acts = {a.name: a for a in bpy.data.actions}
for o in list(bpy.data.objects):
    if o not in before:
        bpy.data.objects.remove(o)
arm.animation_data_create()
FING = ("thumb", "index", "middle", "ring", "pinky")
BONES = [b.name for b in arm.data.bones if not b.name.startswith(FING)]
res = {}
for name, act in acts.items():
    if ONLY and name not in ONLY:
        continue
    for pb in arm.pose.bones:
        pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
    arm.animation_data.action = act
    if len(act.slots):
        arm.animation_data.action_slot = act.slots[0]
    f0, f1 = act.frame_range
    n = int(round(f1 - f0))
    P, Q = [], []
    for f in range(n + 1):
        sc.frame_set(int(f0) + f)
        P.append({b: (arm.matrix_world @ arm.pose.bones[b].head).copy() for b in BONES})
        Q.append({b: arm.pose.bones[b].rotation_quaternion.copy() for b in BONES})
    pos, rot, rel = [], [], []
    for f in range(1, n + 1):
        dr = P[f]["root"] - P[f - 1]["root"]        # root motion of this frame (removed for the character-space numbers)
        for b in BONES:
            dv = P[f][b] - P[f - 1][b]
            pos.append((dv.length, b, f))
            rel.append(((dv - dr).length, b, f))
            q = Q[f][b].dot(Q[f - 1][b])
            a = math.degrees(2 * math.acos(min(1.0, abs(q))))
            rot.append((a, b, f))
    pos.sort(reverse=True); rot.sort(reverse=True); rel.sort(reverse=True)
    # exclude the root bone (carries the travel) from the joint-position ranking, keep pelvis
    posj = [x for x in pos if x[1] != "root"]
    relj = [x for x in rel if x[1] != "root"]
    res[name] = {"frames": n + 1,
                 "rel": [(round(d, 3), b, f) for d, b, f in relj[:TOP]],
                 "rel_over_0.12": sorted(set((b, f) for d, b, f in relj if d > 0.12), key=lambda x: x[1])[:20],
                 "pos": [(round(d, 3), b, f) for d, b, f in posj[:TOP]],
                 "rot": [(round(d, 1), b, f) for d, b, f in rot[:TOP]],
                 "pos_over_0.12": sorted(set((b, f) for d, b, f in posj if d > 0.12), key=lambda x: x[1])[:20],
                 "rot_over_35": sorted(set((b, f) for d, b, f in rot if d > 35 and b != "root"), key=lambda x: x[1])[:20]}
    GROUPS = {"knee(calf)": ("calf_l", "calf_r"), "elbow(lowerarm)": ("lowerarm_l", "lowerarm_r"), "hip(thigh)": ("thigh_l", "thigh_r"),
              "shoulder(upperarm)": ("upperarm_l", "upperarm_r"), "trunk(pelvis,spine,neck,head)": ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head"),
              "hand": ("hand_l", "hand_r"), "foot": ("foot_l", "foot_r")}
    grp = {}
    for gname, bl in GROUPS.items():
        w = max([x for x in posj if x[1] in bl], default=(0, "", 0)); c = max([x for x in relj if x[1] in bl], default=(0, "", 0))
        r = max([x for x in rot if x[1] in bl], default=(0, "", 0))
        grp[gname] = {"world_m": [round(w[0], 3), w[1], w[2]], "charspace_m": [round(c[0], 3), c[1], c[2]], "rot_deg": [round(r[0], 1), r[1], r[2]]}
    res[name]["groups"] = grp
    res[name]["n_frames_over_limit"] = {"charspace_0.12m": len(set(f for d, b, f in relj if d > 0.12)), "rot_35deg": len(set(f for d, b, f in rot if d > 35 and b != "root"))}
    res[name]["pelvis_z_range_m"] = [round(min(P[f]["pelvis"].z - P[f]["root"].z for f in range(n + 1)), 3), round(max(P[f]["pelvis"].z - P[f]["root"].z for f in range(n + 1)), 3)]
    if name.endswith("_Loop"):                        # loop point: last frame vs first frame, root travel removed
        gp = max(((P[n][b] - P[n]["root"]) - (P[0][b] - P[0]["root"])).length for b in BONES if b != "root")
        gr = max(math.degrees(2 * math.acos(min(1.0, abs(Q[n][b].dot(Q[0][b]))))) for b in BONES if b != "root")
        res[name]["loop_gap_cm"] = round(100 * gp, 2)
        res[name]["loop_gap_deg"] = round(gr, 2)
    print("SCAN %-22s world %s | charspace %s | rot %s" % (name, res[name]["pos"][:2], res[name]["rel"][:2], res[name]["rot"][:2]), flush=True)
# world-locked contact windows from the sidecar: drift of the wrist (hand_*) / ball of the foot (ball_*) head, largest distance from the mean, in cm
side = GLB + ".clips.json"
if os.path.exists(side):
    rows = dict((r["name"], r) for r in json.load(open(side)))
    for name, act in acts.items():
        base = name[:-5] if name.endswith("_Loop") else name
        if (ONLY and name not in ONLY) or base not in rows or "contacts" not in rows[base]:
            continue
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        arm.animation_data.action = act
        if len(act.slots):
            arm.animation_data.action_slot = act.slots[0]
        drift = []
        for bone, f0, f1 in rows[base]["contacts"]:
            pts = []
            for f in range(f0, f1 + 1):
                sc.frame_set(f)
                pts.append((arm.matrix_world @ arm.pose.bones[bone].head).copy())
            m = sum(pts, Vector()) / len(pts)
            drift.append([bone, f0, f1, round(100 * max((p - m).length for p in pts), 2)])
        res[name]["contact_drift_cm"] = drift
        print("CONTACT %-22s max drift %.2f cm  %s" % (name, max(d[3] for d in drift), [d for d in drift if d[3] > 1.0]), flush=True)
json.dump(res, open(OUT, "w"), indent=1)
