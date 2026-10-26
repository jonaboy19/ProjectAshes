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

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RETARGET = os.path.join(REPO, "kingdom", "tools", "anim", "retarget_bvh.py")
UAL = os.path.join(REPO, "kingdom", "assets", "incoming", "quaternius", "universal-animation-library",
                   "Unreal-Godot", "UAL1_Standard.glb")


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    a = {"root-motion": "keep", "foot-lock": "on", "only": "", "clips": "", "report": ""}
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
        if c.get("loop") and c.get("loop_native", True) and "end" not in c:
            # Mixamo cycles repeat frame 1 as the last frame: drop it so the seam is exact
            n = fbx_frames(os.path.join(src, c["file"]))
            c["loop_native"] = True
            c["start"] = c.get("start", 0.0)
            c["end"] = (n - 2) / 30.0
        out_clips.append(c)
    cfg = {
        "source_type": "fbx", "fbx_dir": src, "source_fps": 30, "ual": UAL, "out": os.path.abspath(a["out"]),
        "map": MAP, "no_match": ["pelvis"], "heading": "start", "smooth": 0.0, "fingers": None,
        "check_directions": True, "root_motion_track": a["root-motion"] == "keep", "contact": True,
        "clips": out_clips,
    }
    return cfg


# ----------------------------------------------------------------------------- post passes (Blender)
def post(g, cfg, foot_lock):
    import bpy
    import numpy as np
    from mathutils import Vector, Matrix
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
                plant = [low[t] and vel[t] < 0.25 for t in range(n)]
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
                    if max((A[s][f].xy - pin.xy).length for f in range(s0, s1 + 1)) > 0.06:
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
