"""mixamo_to_ual.py - Mixamo FBX clips -> Quaternius UAL (65-bone) clip-library GLB.

Shared batch tool (owner Mixamo downloads: locomotion set S3.1c and the owner_set). Blender 5.2, background is fine:

  blender -b --python tools/anim/mixamo_to_ual.py -- --src <dir with .fbx> --out <library.glb>
          [--clips <spec.json>]        per-clip spec (name, file, loop, inplace, ...); default: every .fbx in --src,
                                       one-shot, named Mx_<File_Name>
          [--root-motion keep|strip]   keep (default): horizontal travel goes to the `root` bone track (Assets._ual_for
                                       disables it for incoming/animations*, so clips play in place and the capsule
                                       owns travel); strip: no root track at all
          [--foot-lock on|off]         default on: pins planted feet (see FOOT LOCK)
          [--only <substring>]         retarget a subset
          [--report <file.json>]       per-clip QA numbers (default <out>.mixamo.json)
          [--rig mixamo|meshy|meshy_bvh|meshy_fbx]  source skeleton: Mixamo FBX (default), Meshy rigged GLB (clip spec gives
                                       "file" = the .glb and "action"), Meshy text-to-motion BVH

Raw Mixamo FBX never go into the repo (licence: no raw redistribution); only the retargeted GLB does.

METHOD (the retarget core is kingdom/tools/anim/retarget_bvh.py, shared with the CMU / free-library pipeline):
  * direction-matched rest: each UAL bone's rest is re-aimed along the Mixamo bone direction (Mixamo T-pose vs UAL
    A-pose), then every frame applies the source WORLD-space rotation delta (pose * rest^-1) onto that matched rest,
    parents first. Fingers are mapped too (Mixamo has full hands), so grips and fists come through.
  * scale: pelvis travel scaled by UAL leg length / Mixamo leg length (hip_scale in the report); floor fix puts the
    lowest planted foot at the UAL rest foot height; contact lift keeps every joint above the floor (no penetration).
  * facing: heading "start" (hip + shoulder line of the first 0.3 s faces UAL forward).
  * loops: Mixamo cycles are native; the duplicated last frame is dropped (loop_native) so the seam is exact.
  * keys: Douglas-Peucker reduction (0.3 deg / 2 mm), linear interpolation, 30 fps.
POST PASSES (this file, on the baked actions):
  * inplace_z (per clip, e.g. ladder climb): linear vertical travel removed from the pelvis.
  * CONTACT IK (default on, contact_ik=false to skip): hands / finger tips clamped above the floor with two-bone arm IK,
    lift max-filtered and smoothed (no pops). Per-clip lock_vel / lock_wander tune the foot lock.
  * knee_lift (per clip): per-frame smoothed pelvis raise keeping the knees KNEE_MARGIN above the floor (kneeling).
  * shift_m (per clip): constant horizontal pelvis shift [x, y] (Blender world, -y = character forward).
  * reverse (per clip): the baked take played backwards.
  * lift_m (per clip): constant pelvis height offset after measuring mesh contact (kneel/sit/lie poses).
  * FOOT LOCK: per foot, frames where the ball AND ankle are within 4 cm of the clip floor and move < 0.25 m/s for
    >= 4 frames are a plant; the ankle is pinned (x/y; z never below the plant-start height) with an analytic two-bone IK on thigh/calf (knee stays in its plane), the foot keeps its world rotation,
    5-frame smoothstep blend in/out; the pin is the median ankle position of the plant, plants whose source foot
    wanders > 6 cm (pivots, shuffles) are left alone. Before/after slip is reported (stance slide mean/max m/s, worst penetration).

MAPPING (UAL bone <- Mixamo bone); every UAL bone not listed follows its parent (root, *_leaf, twist-free chain):
"""
import json
import math
import os
import runpy
import sys
import tempfile

MX = "mixamorig:"
BODY = {
    "pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1", "spine_03": "Spine2",
    "neck_01": "Neck", "Head": "Head",
}
for _s, _S in (("l", "Left"), ("r", "Right")):
    BODY.update({
        "clavicle_" + _s: _S + "Shoulder", "upperarm_" + _s: _S + "Arm", "lowerarm_" + _s: _S + "ForeArm",
        "hand_" + _s: _S + "Hand",
        "thigh_" + _s: _S + "UpLeg", "calf_" + _s: _S + "Leg", "foot_" + _s: _S + "Foot", "ball_" + _s: _S + "ToeBase",
    })
    for _f, _F in (("thumb", "Thumb"), ("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Pinky")):
        for _i in (1, 2, 3):
            BODY["%s_0%d_%s" % (_f, _i, _s)] = "%sHand%s%d" % (_S, _F, _i)
MAP = {k: MX + v for k, v in BODY.items()}

# Meshy rigs (2026-10-28 run): the rigged-character GLB export (24 bones, no fingers) and the text-to-motion BVH
# (78 bones, fingers with a metacarpal: Index1 = metacarpal, so UAL index_01..03 <- Index2..4).
MESHY_GLB = {"pelvis": "Hips", "spine_01": "Spine02", "spine_02": "Spine01", "spine_03": "Spine", "neck_01": "neck",
             "Head": "Head"}
MESHY_BVH = {"pelvis": "Hips", "spine_01": "Spine1", "spine_02": "Spine2", "spine_03": "Chest", "neck_01": "Neck1",
             "Head": "Head"}
for _s, _S in (("l", "Left"), ("r", "Right")):
    for _m in (MESHY_GLB, MESHY_BVH):
        _m.update({"clavicle_" + _s: _S + "Shoulder", "upperarm_" + _s: _S + "Arm", "lowerarm_" + _s: _S + "ForeArm",
                   "hand_" + _s: _S + "Hand", "foot_" + _s: _S + "Foot", "ball_" + _s: _S + "ToeBase"})
    MESHY_GLB.update({"thigh_" + _s: _S + "UpLeg", "calf_" + _s: _S + "Leg"})
    MESHY_BVH.update({"thigh_" + _s: _S + "Leg", "calf_" + _s: _S + "Shin"})
    for _i in (1, 2, 3):
        MESHY_BVH["thumb_0%d_%s" % (_i, _s)] = "%sHandThumb%d" % (_S, _i)
        for _f, _F in (("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Pinky")):
            MESHY_BVH["%s_0%d_%s" % (_f, _i, _s)] = "%sHand%s%d" % (_S, _F, _i + 1)
# Meshy text-to-motion PRIME export (2026-10-28): FBX with an SMPL-H skeleton (52 bones, Pelvis / L_Hip ... / L_Wrist +
# 3-segment fingers), cm units (scale 0.01), +90 deg X, 30 fps, includes Meshy's skinned preview mesh (dropped on import).
SMPLH = {"pelvis": "Pelvis", "spine_01": "Spine1", "spine_02": "Spine2", "spine_03": "Spine3", "neck_01": "Neck", "Head": "Head"}
for _s, _S in (("l", "L"), ("r", "R")):
    SMPLH.update({"clavicle_" + _s: _S + "_Collar", "upperarm_" + _s: _S + "_Shoulder", "lowerarm_" + _s: _S + "_Elbow",
                  "hand_" + _s: _S + "_Wrist", "thigh_" + _s: _S + "_Hip", "calf_" + _s: _S + "_Knee",
                  "foot_" + _s: _S + "_Ankle", "ball_" + _s: _S + "_Foot"})
    for _i in (1, 2, 3):
        for _f, _F in (("thumb", "Thumb"), ("index", "Index"), ("middle", "Middle"), ("ring", "Ring"), ("pinky", "Pinky")):
            SMPLH["%s_0%d_%s" % (_f, _i, _s)] = "%s_%s%d" % (_S, _F, _i)
RIGS = {"mixamo": ("fbx", MAP), "meshy": ("gltf", MESHY_GLB), "meshy_bvh": ("bvh", MESHY_BVH), "meshy_fbx": ("fbx", SMPLH)}

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HAND_MARGIN = 0.035      # hand joint centre above the floor (palm thickness)
TIP_MARGIN = 0.012       # finger joints above the floor
KNEE_MARGIN = 0.06       # knee joint centre above the floor (knee_lift clips: kneeling)
ELBOW_MARGIN = 0.05      # elbow joint above the floor when the arm IK swings the bend plane
TOE_MARGIN = 0.03        # ball joint / toe tip above the floor (toe_floor clips)
ANKLE_MARGIN = 0.06      # ankle joint above the floor when the shin rests on it
RETARGET = os.path.join(REPO, "kingdom", "tools", "anim", "retarget_bvh.py")
UAL = os.path.join(REPO, "kingdom", "assets", "incoming", "quaternius", "universal-animation-library",
                   "Unreal-Godot", "UAL1_Standard.glb")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"root-motion": "keep", "foot-lock": "on", "only": "", "clips": "", "report": "", "rig": "mixamo"}
    i = 0
    while i < len(argv):
        k = argv[i].lstrip("-")
        a[k] = argv[i + 1]
        i += 2
    if "src" not in a or "out" not in a:
        print(__doc__)
        raise SystemExit("need --src and --out")
    return a


def fbx_frames(path):
    """Frame count of a Mixamo FBX without importing it twice (import is cheap enough; done once per clip)."""
    import bpy
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    f0, f1 = arm.animation_data.action.frame_range
    return int(round(f1 - f0)) + 1


def build_cfg(a):
    src = os.path.abspath(a["src"])
    if a["clips"]:
        spec = json.load(open(a["clips"], encoding="utf-8"))
        clips = spec["clips"] if isinstance(spec, dict) else spec
    else:
        clips = [{"name": "Mx_" + os.path.splitext(f)[0].replace(" ", "_"), "file": f}
                 for f in sorted(os.listdir(src)) if f.lower().endswith(".fbx")]
    if a["only"]:
        clips = [c for c in clips if a["only"].lower() in (c["name"] + c["file"]).lower()]
    out_clips = []
    for c in clips:
        c = dict(c)
        c.setdefault("heading", "start")
        c.setdefault("inplace", "smooth")
        if c.get("loop") and a["rig"] != "mixamo":
            c.setdefault("loop_native", False)         # Meshy cycles are not frame-exact: find loop points + crossfade
        if c.get("loop") and c.get("loop_native", True) and "end" not in c:
            # Mixamo cycles repeat frame 1 as the last frame: drop it so the seam is exact
            n = fbx_frames(os.path.join(src, c["file"]))
            c["loop_native"] = True
            c["start"] = c.get("start", 0.0)
            c["end"] = (n - 2) / 30.0
        out_clips.append(c)
    st, bmap = RIGS[a["rig"]]
    if st == "gltf":
        import bpy
        for c in out_clips:
            c.setdefault("glb", os.path.join(src, c.get("file", "")))
            if not c.get("action"):
                # Meshy rigged export: one clip per file, take its (first) action name
                bpy.ops.wm.read_factory_settings(use_empty=True)
                before = set(bpy.data.actions)
                bpy.ops.import_scene.gltf(filepath=c["glb"])
                new = [x.name for x in bpy.data.actions if x not in before]
                c["action"] = new[0] if new else ""
    has_fingers = any(k.startswith("index_") for k in bmap)
    cfg = {
        "source_type": st, "fbx_dir": src, "bvh_dir": src, "source_fps": 30, "ual": UAL, "out": os.path.abspath(a["out"]),
        "map": bmap, "no_match": ["pelvis"] + (["Head", "ball_l", "ball_r"] + [k for k in bmap if k.endswith(("_03_l", "_03_r"))] if a["rig"] == "meshy_fbx" else []), "heading": "start", "smooth": 0.0 if st == "fbx" else 0.04,
        "fingers": None if has_fingers else "relaxed", "finger_poses": {} if has_fingers else {"relaxed": ["Idle_Loop", 0.0]},
        "check_directions": True, "root_motion_track": a["root-motion"] == "keep", "contact": True,
        "clips": out_clips,
        "fbx_auto_orient": a["rig"] == "meshy_fbx",
    }
    return cfg


# ----------------------------------------------------------------------------- post passes (Blender)
def post(g, cfg, foot_lock):
    import bpy
    import numpy as np
    from mathutils import Vector, Matrix, Quaternion
    scene = bpy.context.scene
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
    tgt = g["tgt"]
    made = g["made"]
    assign = g["assign"]
    ad = tgt.animation_data
    ad.use_nla = False
    pb = tgt.pose.bones
    mw = tgt.matrix_world
    spec = {c["name"] + ("_Loop" if c.get("loop") else ""): c for c in cfg["clips"]}
    rest_ball = (mw @ tgt.data.bones["ball_l"].head_local).z
    report = {}

    def upd():
        bpy.context.view_layer.update()

    def sample(n):
        A, B, F, P = {}, {}, {}, []
        for f in range(n):
            scene.frame_set(f)
            for s in ("l", "r"):
                A.setdefault(s, []).append((mw @ pb["foot_" + s].head).copy())
                B.setdefault(s, []).append((mw @ pb["ball_" + s].head).copy())
            P.append((mw @ pb["pelvis"].head).copy())
        return A, B, P

    def stance_stats(A, B, floor):
        """Planted-foot slip: frames where the ball is within 3 cm of the floor, speed of the ball (m/s)."""
        sl = []
        pen = 0.0
        for s in ("l", "r"):
            for t in range(1, len(B[s])):
                pen = max(pen, rest_ball - 0.0 - B[s][t].z) if B[s][t].z < rest_ball else pen
                if B[s][t].z - floor < 0.03 and B[s][t - 1].z - floor < 0.03:
                    d = (B[s][t].xy - B[s][t - 1].xy).length * 30.0
                    sl.append(d)
        if not sl:
            return 0.0, 0.0, 0, pen
        sl = np.array(sl)
        return float(sl.mean()), float(sl.max()), len(sl), pen

    def fcurves_of(act):
        if hasattr(act, "fcurves") and len(getattr(act, "fcurves", [])):
            return list(act.fcurves)
        out = []
        for layer in getattr(act, "layers", []):
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    out.extend(bag.fcurves)
        return out

    def quat_continuity(act):
        """Keys written per frame by the IK passes can land in the opposite quaternion hemisphere of their neighbour;
        flip them so every consumer (linear or slerp) takes the short way."""
        groups = {}
        for fc in fcurves_of(act):
            if fc.data_path.endswith("rotation_quaternion"):
                groups.setdefault(fc.data_path, {})[fc.array_index] = fc
        for path, g4 in groups.items():
            if len(g4) != 4:
                continue
            frames = sorted({kp.co[0] for fc in g4.values() for kp in fc.keyframe_points})
            prev = None
            for fr in frames:
                q = [g4[i].evaluate(fr) for i in range(4)]
                if prev is not None and sum(a * b for a, b in zip(q, prev)) < 0:
                    for i in range(4):
                        for kp in g4[i].keyframe_points:
                            if abs(kp.co[0] - fr) < 1e-3:
                                kp.co[1] = -kp.co[1]
                    q = [-x for x in q]
                prev = q
            for fc in g4.values():
                fc.update()

    def two_bone(up, lo, en, mt, mc, mf, T, mid_min=None, swing=None, probe=False):
        """Analytic two-bone IK in armature space: end joint to T, middle joint stays in its bend plane, end keeps its rotation."""
        hip, knee, ank = mt.translation, mc.translation, mf.translation
        la, lb = (knee - hip).length, (ank - knee).length
        d = min((T - hip).length, (la + lb) * 0.9995)
        u = (T - hip).normalized()
        v = (knee - hip) - u * (knee - hip).dot(u)
        if v.length < 1e-6:
            return False
        v.normalize()
        ca_ = max(-1.0, min(1.0, (la * la + d * d - lb * lb) / (2 * la * d)))
        al = math.acos(ca_)
        knee2 = hip + (u * math.cos(al) + v * math.sin(al)) * la
        if swing is not None:
            if abs(swing) > 1e-4:
                vv = Quaternion(u, swing) @ v
                knee2 = hip + (u * math.cos(al) + vv * math.sin(al)) * la
        elif mid_min is not None and (mw @ knee2).z < mid_min:
            # the middle joint (elbow) would go through the floor: swing the bend plane about the limb axis to the
            # nearest orientation that keeps it above mid_min
            best = None
            for k in range(1, 37):
                for sgn in (1, -1):
                    q = Quaternion(u, sgn * math.radians(5 * k))
                    vv = q @ v
                    kk = hip + (u * math.cos(al) + vv * math.sin(al)) * la
                    if (mw @ kk).z >= mid_min:
                        best = kk
                        break
                if best is not None:
                    break
            if best is not None:
                knee2 = best
                if probe:
                    return sgn * math.radians(5 * k)
        if probe:
            return 0.0
        T2 = hip + u * d
        r1 = (knee - hip).rotation_difference(knee2 - hip)
        r2 = (r1 @ (ank - knee)).rotation_difference(T2 - knee2)
        pb[up].matrix = Matrix.Translation(hip) @ (r1.to_matrix().to_4x4() @ mt.to_3x3().to_4x4()); upd()
        pb[lo].matrix = Matrix.Translation(knee2) @ ((r2 @ r1).to_matrix().to_4x4() @ mc.to_3x3().to_4x4()); upd()
        pb[en].matrix = Matrix.Translation(T2) @ mf.to_3x3().to_4x4(); upd()
        return True

    def key_bones(names, f):
        for nm in names:
            pb[nm].keyframe_insert("rotation_quaternion", frame=f)
            if nm == "pelvis":
                pb[nm].keyframe_insert("location", frame=f)

    for name, act in made:
        c = spec.get(name, {})
        assign(tgt, act)
        n = int(round(act.frame_range[1])) + 1
        rec = {}
        if c.get("reverse"):
            # play the take backwards (e.g. sit-to-stand built from stand-to-sit so it starts exactly on the sit pose)
            for fc in fcurves_of(act):
                pts = [(kp.co[0], kp.co[1]) for kp in fc.keyframe_points]
                for kp, (x, y) in zip(fc.keyframe_points, reversed(pts)):
                    kp.co = ((n - 1) - x, y)
                    kp.handle_left = kp.co
                    kp.handle_right = kp.co
                fc.update()
            rec["reversed"] = True
        # bake every frame of the bones the passes edit, so a per-frame edit never bleeds into the interpolation of the next
        # frame (sparse Douglas-Peucker keys + sequential edits used to accumulate: the old lift_m bug)
        BAKE = ["pelvis"] + [b + "_" + s for s in ("l", "r") for b in ("thigh", "calf", "foot", "upperarm", "lowerarm", "hand")]
        if c.get("toe_floor"):
            BAKE += ["ball_l", "ball_r"]
        snap = []
        for f in range(n):
            scene.frame_set(f)
            snap.append({b: (pb[b].rotation_quaternion.copy(), pb[b].location.copy()) for b in BAKE})
        for f in range(n):
            for b in BAKE:
                pb[b].rotation_quaternion, pb[b].location = snap[f][b]
                pb[b].keyframe_insert("rotation_quaternion", frame=f)
                if b == "pelvis":
                    pb[b].keyframe_insert("location", frame=f)
        # --- vertical in-place (ladder): remove the linear pelvis z ramp
        if c.get("inplace_z"):
            P0 = [None] * n
            for f in range(n):
                scene.frame_set(f)
                P0[f] = pb["pelvis"].matrix.copy()
            dz = (mw.inverted().to_3x3() @ Vector((0, 0, 1)))
            rise = (mw @ P0[-1].translation).z - (mw @ P0[0].translation).z
            for f in range(n):
                scene.frame_set(f)
                m = P0[f].copy()
                m.translation = m.translation - dz * (rise * f / max(1, n - 1)) / mw.to_scale().z
                pb["pelvis"].matrix = m
                pb["pelvis"].keyframe_insert("location", frame=f)
            rec["inplace_z_removed_m"] = round(rise, 3)
        # --- constant vertical offset (lift_m > 0 raises, < 0 lowers): knees / buttocks resting on the floor, lying poses
        # --- yaw_deg (+ yaw_shift [x, y] m): rotate / move the whole take about the vertical axis in the root bone's frame
        # (what the exported clip and the game, root track off, see): put a pair of clips (sleep loop + get-out-of-bed exit)
        # in one frame where the exit ends standing over the root facing forward
        if c.get("yaw_deg"):
            Rz = (Matrix.Translation(Vector((*[float(x) for x in c.get("yaw_shift", [0.0, 0.0])], 0.0)))
                  @ Matrix.Rotation(math.radians(float(c["yaw_deg"])), 4, "Z"))
            mats = []
            for f in range(n):
                scene.frame_set(f)
                Rt = (mw @ pb["root"].matrix) if "root" in pb else mw.copy()
                Rf = Matrix.Translation(Rt.translation) @ Matrix.Rotation(Rt.to_euler().z, 4, "Z")
                mats.append((Rf, mw @ pb["pelvis"].matrix))
            for f in range(n):
                scene.frame_set(f)
                Rf, Mp = mats[f]
                pb["pelvis"].matrix = mw.inverted() @ (Rf @ Rz @ Rf.inverted() @ Mp)
                pb["pelvis"].keyframe_insert("location", frame=f)
                pb["pelvis"].keyframe_insert("rotation_quaternion", frame=f)
            rec["yaw_deg"] = c["yaw_deg"]
            rec["yaw_shift"] = c.get("yaw_shift")
        if c.get("shift_m"):
            # constant horizontal pelvis shift (Blender world x, y): end-align transitions onto the loop they lead into
            sx_, sy_ = c["shift_m"]
            dv = (mw.inverted().to_3x3() @ Vector((sx_, sy_, 0.0)))
            mats = []
            for f in range(n):
                scene.frame_set(f)
                mats.append(pb["pelvis"].matrix.copy())
            for f in range(n):
                scene.frame_set(f)
                m = mats[f].copy()
                m.translation = m.translation + dv
                pb["pelvis"].matrix = m
                pb["pelvis"].keyframe_insert("location", frame=f)
            rec["shift_m"] = c["shift_m"]
        if c.get("lift_m"):
            dz = (mw.inverted().to_3x3() @ Vector((0, 0, 1))) / mw.to_scale().z
            mats = []
            for f in range(n):
                scene.frame_set(f)
                mats.append(pb["pelvis"].matrix.copy())
            for f in range(n):
                scene.frame_set(f)
                m = mats[f].copy()
                m.translation = m.translation + dz * float(c["lift_m"])
                pb["pelvis"].matrix = m
                pb["pelvis"].keyframe_insert("location", frame=f)
            rec["lift_m"] = c["lift_m"]
        # --- lift_ramp [[frame, dz], ...]: piecewise pelvis height offset (smoothstep between keys), e.g. a get-out-of-bed
        # take recorded on a higher bed: lower the lying part onto our bed height and ease back to 0 once the feet are down
        if c.get("lift_ramp"):
            kk = sorted((int(a), float(b)) for a, b in c["lift_ramp"])
            def ramp(f):
                if f <= kk[0][0]:
                    return kk[0][1]
                for (f0, d0), (f1, d1) in zip(kk, kk[1:]):
                    if f <= f1:
                        w = (f - f0) / max(1, f1 - f0)
                        w = w * w * (3 - 2 * w)
                        return d0 + (d1 - d0) * w
                return kk[-1][1]
            dz = (mw.inverted().to_3x3() @ Vector((0, 0, 1))) / mw.to_scale().z
            mats = []
            for f in range(n):
                scene.frame_set(f)
                mats.append(pb["pelvis"].matrix.copy())
            for f in range(n):
                scene.frame_set(f)
                m = mats[f].copy()
                m.translation = m.translation + dz * ramp(f)
                pb["pelvis"].matrix = m
                pb["pelvis"].keyframe_insert("location", frame=f)
            rec["lift_ramp"] = c["lift_ramp"]
        # --- knee/shin floor contact: per-frame pelvis raise so the knee joints stay KNEE_MARGIN above the floor
        if c.get("knee_lift"):
            dz = (mw.inverted().to_3x3() @ Vector((0, 0, 1))) / mw.to_scale().z
            need = []
            for f in range(n):
                scene.frame_set(f)
                kz = min((mw @ pb["calf_" + s].head).z for s in ("l", "r"))
                az = min((mw @ pb["foot_" + s].head).z for s in ("l", "r"))      # ankle: the shin lies on the floor
                need.append(max(0.0, KNEE_MARGIN - kz, ANKLE_MARGIN - az))
            rr = 4
            mxn = [max(need[max(0, t - rr): t + rr + 1]) for t in range(n)]
            sm = [sum(mxn[max(0, t - 3): t + 4]) / len(mxn[max(0, t - 3): t + 4]) for t in range(n)]
            lift = [max(a, b) for a, b in zip(sm, need)]
            mats = []
            for f in range(n):
                scene.frame_set(f)
                mats.append(pb["pelvis"].matrix.copy())
            for f in range(n):
                scene.frame_set(f)
                m = mats[f].copy()
                m.translation = m.translation + dz * lift[f]
                pb["pelvis"].matrix = m
                pb["pelvis"].keyframe_insert("location", frame=f)
            rec["knee_lift_max"] = round(max(lift), 3)
        A, B, P = sample(n)
        floor = min(min(b.z for b in B["l"]), min(b.z for b in B["r"]))
        rec["before"] = [round(x, 3) for x in stance_stats(A, B, floor)[:2]]
        locked = 0
        if foot_lock and not c.get("no_foot_lock") and c.get("foot_lock", True):
            for s in ("l", "r"):
                th, ca, fo = "thigh_" + s, "calf_" + s, "foot_" + s
                low = [(A[s][t].z - min(a.z for a in A[s]) < 0.04) and (B[s][t].z - floor < 0.04) for t in range(n)]
                vel = [0.0] + [((A[s][t].xy - A[s][t - 1].xy).length + (B[s][t].xy - B[s][t - 1].xy).length) * 15.0
                               for t in range(1, n)]
                plant = [low[t] and vel[t] < float(c.get("lock_vel", 0.25)) for t in range(n)]
                segs, t = [], 0
                while t < n:
                    if plant[t]:
                        e = t
                        while e + 1 < n and plant[e + 1]:
                            e += 1
                        if e - t + 1 >= 4:
                            segs.append((t, e))
                        t = e + 1
                    else:
                        t += 1
                for (s0, s1) in segs:
                    xs = sorted(A[s][f].x for f in range(s0, s1 + 1)); ys = sorted(A[s][f].y for f in range(s0, s1 + 1))
                    pin = Vector((xs[len(xs) // 2], ys[len(ys) // 2], A[s][s0].z))
                    if max((A[s][f].xy - pin.xy).length for f in range(s0, s1 + 1)) > float(c.get("lock_wander", 0.06)):
                        continue          # the source foot really travels (pivot / shuffle): not a plant, leave it
                    R = 5
                    lo, hi = max(0, s0 - R), min(n - 1, s1 + R)
                    # sample original pose matrices over the window first
                    orig = {}
                    for f in range(lo, hi + 1):
                        scene.frame_set(f)
                        orig[f] = {k: pb[k].matrix.copy() for k in (th, ca, fo)}
                    for f in ([lo - 1] if lo > 0 else []) + ([hi + 1] if hi < n - 1 else []):
                        scene.frame_set(f)
                        key_bones((th, ca, fo), f)
                    for f in range(lo, hi + 1):
                        if f < s0:
                            w = (f - lo + 1) / (R + 1)
                        elif f > s1:
                            w = (hi - f + 1) / (R + 1)
                        else:
                            w = 1.0
                        w = w * w * (3 - 2 * w)
                        scene.frame_set(f)
                        cur = A[s][f]
                        want = cur.lerp(Vector((pin.x, pin.y, max(cur.z, pin.z) if f >= s0 else cur.z)), w)
                        T = mw.inverted() @ want
                        mt, mc, mf = orig[f][th], orig[f][ca], orig[f][fo]
                        hip, knee, ank = mt.translation, mc.translation, mf.translation
                        la, lb = (knee - hip).length, (ank - knee).length
                        d = min((T - hip).length, (la + lb) * 0.9995)
                        u = (T - hip).normalized()
                        v = (knee - hip) - u * (knee - hip).dot(u)
                        if v.length < 1e-6:
                            continue
                        v.normalize()
                        ca_ = max(-1.0, min(1.0, (la * la + d * d - lb * lb) / (2 * la * d)))
                        al = math.acos(ca_)
                        knee2 = hip + (u * math.cos(al) + v * math.sin(al)) * la
                        T2 = hip + u * d
                        r1 = (knee - hip).rotation_difference(knee2 - hip)
                        r2 = (r1 @ (ank - knee)).rotation_difference(T2 - knee2)
                        mt2 = Matrix.Translation(hip) @ (r1.to_matrix().to_4x4() @ mt.to_3x3().to_4x4())
                        mc2 = Matrix.Translation(knee2) @ ((r2 @ r1).to_matrix().to_4x4() @ mc.to_3x3().to_4x4())
                        mf2 = Matrix.Translation(T2) @ mf.to_3x3().to_4x4()
                        pb[th].matrix = mt2; upd()
                        pb[ca].matrix = mc2; upd()
                        pb[fo].matrix = mf2; upd()
                        key_bones((th, ca, fo), f)
                        locked += 1
            for fc in act.fcurves if hasattr(act, "fcurves") else []:
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"
        # --- contact IK: hands (and finger tips) never below the floor. Per-frame two-bone IK on upperarm/lowerarm with the
        # hand's world rotation kept; the needed lift is max-filtered over +-0.13 s and smoothed so the arm never pops.
        if c.get("contact_ik", True):
            hm = float(c.get("hand_margin_extra", 0.0))   # game characters' arms reach lower than the UAL mannequin's
            for s in ("l", "r"):
                up, lo, en = "upperarm_" + s, "lowerarm_" + s, "hand_" + s
                tips = [fb + "_0%d_" % i + s for fb in ("thumb", "index", "middle", "ring", "pinky") for i in (1, 2, 3) if fb + "_0%d_" % i + s in pb]
                need = []
                for f in range(n):
                    scene.frame_set(f)
                    hz = (mw @ pb[en].head).z
                    tz = min(min((mw @ pb[t].head).z, (mw @ pb[t].tail).z) for t in tips) if tips else hz
                    need.append(max(0.0, HAND_MARGIN + hm - hz, TIP_MARGIN + hm - tz))
                if max(need) < 0.003:
                    continue
                rr = int(c.get("ik_smooth", 4))
                mxn = [max(need[max(0, t - rr): t + rr + 1]) for t in range(n)]
                h2 = max(2, rr // 2)
                sm = [sum(mxn[max(0, t - h2): t + h2 + 1]) / len(mxn[max(0, t - h2): t + h2 + 1]) for t in range(n)]
                lift = [max(a, b) for a, b in zip(sm, need)]
                fixed = 0
                # pass 1: elbow swing angle each frame needs (0 = keep the bend plane); smoothed so the elbow glides
                sw = [0.0] * n
                for f in range(n):
                    if lift[f] > 0.0005:
                        scene.frame_set(f)
                        mu, ml, me = pb[up].matrix.copy(), pb[lo].matrix.copy(), pb[en].matrix.copy()
                        T = mw.inverted() @ ((mw @ me.translation) + Vector((0, 0, lift[f])))
                        sw[f] = two_bone(up, lo, en, mu, ml, me, T, mid_min=ELBOW_MARGIN + hm, probe=True) or 0.0
                ext = []
                for t in range(n):
                    win = sw[max(0, t - rr * 2): t + rr * 2 + 1]
                    ext.append(max(win, key=abs))
                sws = [sum(ext[max(0, t - rr): t + rr + 1]) / len(ext[max(0, t - rr): t + rr + 1]) for t in range(n)]
                for f in range(n):
                    scene.frame_set(f)
                    if lift[f] > 0.0005 or abs(sws[f]) > 1e-4:
                        mu, ml, me = pb[up].matrix.copy(), pb[lo].matrix.copy(), pb[en].matrix.copy()
                        T = mw.inverted() @ ((mw @ me.translation) + Vector((0, 0, lift[f])))
                        if two_bone(up, lo, en, mu, ml, me, T, swing=sws[f]):
                            fixed += 1
                    key_bones((up, lo, en), f)
                rec["hand_ik_" + s] = [fixed, round(max(need), 3)]
        # --- toe_floor: kneel / crouch takes whose foot points into the ground (Meshy SMPL-H has no usable toe bone, so
        # ball_* stays at rest): pitch the foot about the ankle until the ball joint is TOE_MARGIN above the floor, then
        # the toe about the ball joint until its tip is - the toes tuck instead of stabbing through the floor
        if c.get("toe_floor"):
            # two passes: per frame the pitch each bone needs (radians, about its own horizontal axis), then a max filter +
            # moving average so the correction eases in and out (a raw per-frame clamp popped the toes on/off)
            def lat_axis(bn):
                return ((mw @ pb[bn].matrix).to_3x3() @ Vector((1, 0, 0))).normalized()     # the bone's own side axis: stable
            def need_pitch(bn, H, Tp):
                # signed angle about the bone's side axis that lifts the tip to TOE_MARGIN (smallest |angle|), 0 when clear
                if Tp.z >= TOE_MARGIN:
                    return 0.0
                k = lat_axis(bn)
                v = Tp - H
                for step in range(1, 121):
                    for sg in (1.0, -1.0):
                        a = sg * step * 0.01
                        if H.z + (Matrix.Rotation(a, 3, k) @ v).z >= TOE_MARGIN:
                            return a
                return 0.0
            def apply_pitch(bn, H, ang):
                if abs(ang) <= 1e-5:
                    return
                R = Matrix.Rotation(ang, 4, lat_axis(bn))
                pb[bn].matrix = mw.inverted() @ (Matrix.Translation(H) @ R @ Matrix.Translation(-H) @ (mw @ pb[bn].matrix))
                upd()
            def ease(raw):
                # keep the sign, ease the size in and out (max filter + moving average on |angle|)
                sgn = [1.0 if a >= 0 else -1.0 for a in raw]
                mag = [abs(a) for a in raw]
                rr = 5
                mx = [max(mag[max(0, t - rr): t + rr + 1]) for t in range(n)]
                sm = [max(mag[t], sum(mx[max(0, t - 4): t + 5]) / len(mx[max(0, t - 4): t + 5])) for t in range(n)]
                last = 1.0
                for t in range(n):                       # each frame keeps its own direction (carried through clear frames)
                    if raw[t] != 0.0:
                        last = sgn[t]
                    sgn[t] = last
                return [g * m for g, m in zip(sgn, sm)]
            fixed = 0
            for s in ("l", "r"):
                fo, ba = "foot_" + s, "ball_" + s
                raw = []
                for f in range(n):
                    scene.frame_set(f)
                    raw.append(need_pitch(fo, mw @ pb[fo].head, mw @ pb[ba].head))
                af = ease(raw)
                for f in range(n):
                    scene.frame_set(f)
                    apply_pitch(fo, mw @ pb[fo].head, af[f])
                    key_bones((fo,), f)
                raw = []
                for f in range(n):
                    scene.frame_set(f)
                    raw.append(need_pitch(ba, mw @ pb[ba].head, mw @ pb[ba].tail))
                ab = ease(raw)
                for f in range(n):
                    scene.frame_set(f)
                    apply_pitch(ba, mw @ pb[ba].head, ab[f])
                    key_bones((ba,), f)
                fixed += sum(1 for a, b in zip(af, ab) if a != 0 or b != 0)
            rec["toe_floor_frames"] = fixed
        # loops: the passes above edit legs/arms per frame, which can open the loop seam again; blend the last
        # SEAM frames of every edited bone back onto frame 0 (smoothstep) so last == first
        if c.get("loop") and (locked or c.get("knee_lift") or c.get("lift_m") or c.get("toe_floor")):
            K = min(int(c.get("seam_blend", 8)), n // 3)
            first = {}
            scene.frame_set(0)
            for b in BAKE:
                first[b] = (pb[b].rotation_quaternion.copy(), pb[b].location.copy())
            for j in range(K):
                f = n - K + j
                w = (j + 1) / K
                w = w * w * (3 - 2 * w)
                scene.frame_set(f)
                for b in BAKE:
                    q0, l0 = first[b]
                    q = pb[b].rotation_quaternion.copy()
                    if q.dot(q0) < 0:
                        q0 = -q0
                    pb[b].rotation_quaternion = q.slerp(q0, w)
                    pb[b].location = pb[b].location.lerp(l0, w)
                for b in BAKE:
                    pb[b].keyframe_insert("rotation_quaternion", frame=f)
                    if b == "pelvis":
                        pb[b].keyframe_insert("location", frame=f)
        quat_continuity(act)
        low = {}
        for f in range(0, n, 2):
            scene.frame_set(f)
            for b in pb:
                if "leaf" in b.name or b.name == "root":
                    continue
                z = min((mw @ b.head).z, (mw @ b.tail).z)
                if z < low.get(b.name, 9.0):
                    low[b.name] = z
        rec["lowest_joints"] = [(k, round(v, 3)) for k, v in sorted(low.items(), key=lambda kv: kv[1])[:4]]
        A2, B2, _ = sample(n)
        st = stance_stats(A2, B2, floor)
        rec["after"] = [round(x, 3) for x in st[:2]]
        rec["stance_frames"] = st[2]
        rec["locked_frames"] = locked
        # hand drift relative to pelvis between first and last frame (loop seam of the arms, weapon alignment hint)
        scene.frame_set(0)
        h0 = [(mw @ pb["hand_" + s].head) - (mw @ pb["pelvis"].head) for s in ("l", "r")]
        scene.frame_set(n - 1)
        h1 = [(mw @ pb["hand_" + s].head) - (mw @ pb["pelvis"].head) for s in ("l", "r")]
        rec["hand_seam_cm"] = round(max((h0[i] - h1[i]).length for i in (0, 1)) * 100, 1)
        rec["frames"] = n
        report[name] = rec
        print("POST", name, json.dumps(rec))
    assign(tgt, None)
    ad.use_nla = True
    return report


def export(g, out):
    import bpy
    bpy.ops.object.select_all(action="DESELECT")
    tgt = g["tgt"]
    tgt.select_set(True)
    for o in bpy.data.objects:
        if o.parent == tgt:
            o.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=False, export_optimize_animation_size=False,
                              export_draco_mesh_compression_enable=False, export_materials="NONE",
                              export_apply=False, export_yup=True, export_def_bones=False,
                              export_anim_single_armature=True, export_reset_pose_bones=True)


def main():
    a = parse_args()
    cfg = build_cfg(a)
    tmp = os.path.join(tempfile.gettempdir(), "mixamo_to_ual_%d.json" % os.getpid())
    json.dump(cfg, open(tmp, "w", encoding="utf-8"), indent=1)
    sys.argv = [RETARGET, "--", tmp]
    g = runpy.run_path(RETARGET, run_name="__retarget__")
    rep = post(g, cfg, a["foot-lock"] == "on")
    export(g, cfg["out"])
    base = {r["name"] + ("_Loop" if r["loop"] else ""): r for r in g["report"]}
    for k, v in rep.items():
        v.update({kk: base.get(k, {}).get(kk) for kk in ("source", "seconds", "floor_fix_m", "contact_lift_m",
                                                         "min_foot_m", "travel_m", "hip_scale", "loop")})
    rpath = a["report"] or cfg["out"] + ".mixamo.json"
    json.dump({"map": BODY, "clips": rep}, open(rpath, "w", encoding="utf-8"), indent=1)
    os.remove(tmp)
    print("MIXAMO_TO_UAL done", cfg["out"], len(rep), "clips; report", rpath)


if __name__ == "__main__":
    main()
