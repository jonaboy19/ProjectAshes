# Horse RIDER clips on the Quaternius UAL skeleton (hand-authored IK key poses, synced to the horse clips of Horse_Anims.glb).
#
#   BL="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
#   "$BL" -b --factory-startup -P author_rider.py -- <out.glb> [Horse_Ride_Walk,Horse_Ride_Trot,...]
#   "C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" ../../glb_reduce_anim.py <out.glb> --rot-deg 0.08 --pos-m 0.0005
#   "$BL" -b --factory-startup -P render_rider.py -- <out.glb> <dir> --metrics      (world-space check: stirrups / grips / horse mesh
#                                                                                   penetration, merged into <out.glb>.clips.json)
#   "$BL" -b --factory-startup -P render_rider.py -- <out.glb> <dir> --clips=A,B    (side + 3/4 frames for contact sheets)
#
# Output: kingdom/assets/generated/horses/UAL_Horse_Rider.glb (UAL Armature + stub mesh, one NLA track per clip, loops end in _Loop)
# and UAL_Horse_Rider.glb.clips.json (per clip: name, glb_name, loop, frames, fps, synced_to, layer, upper_bones, events, contacts,
# root_delta_m, ik residuals, grip / stirrup misses, pelvis clearance; render_rider.py --metrics adds the world-space checks).
#
# SYNC: a clip whose synced_to is a horse clip has exactly that clip's frame count. The rider is authored in rider clip space (horse
# at rest, horse root = origin) and in game is moved rigidly by the saddle delta D(t) = saddle_pose(t) * saddle_rest^-1 (horse
# root space; source/rider_tracks.json), playing at the same normalised time as the horse clip. Hands follow the per-frame rein grips
# (already in clip space), feet sit on the (rigid) stirrups. World-stabilised parts (two-point pelvis / torso, calm heads) are authored
# against a low-passed D and mapped back with D^-1 (rider_lib.seat_pose).
import os, sys, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from rider_lib import *
import rider_lib as RL
sys.path.insert(0, os.path.normpath(os.path.join(HERE, "..", "..", "traversal")))
import author_traversal_v2 as V2          # export() (its own clip modules register into trav_lib.CLIPS, unused here)
import clips_gaits
import clips_special
import clips_ground
import clips_upper

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1].split(",") if len(argv) > 1 and argv[1] else None


def residuals(name, poses, diag, m, S_grip):
    """IK misses (wrist / ankle effectors), rein-grip miss (palm centre vs the horse's rein grip, frames where hands_on_grips),
    stirrup miss (ball of the foot vs the stirrup tread), pelvis clearance above the seat top (seated frames)."""
    ik = {}
    grip_miss = {"l": (0.0, 0), "r": (0.0, 0)}
    stir_miss = {"l": (0.0, 0), "r": (0.0, 0)}
    clear = (9.0, 0)
    hog = m.get("hands_on_grips", False)
    fis = m.get("feet_in_stirrups", False)
    seated = m.get("seated", False)
    for f, (P, row) in enumerate(zip(poses, diag)):
        for k, e in row["err"].items():
            if e > ik.get(k, (0.0, 0))[0]:
                ik[k] = (e, f)
        for s in "lr":
            want_g = _frames_ok(hog, f)
            if want_g and S_grip is not None:
                G = P.t["hand_" + s] + P.abs["hand_" + s] @ HAND_AXIS[s] * GRIP_OFF
                e = (G - S_grip[s][f]).length + row["err"].get("hand_" + s, 0.0)
                if e > grip_miss[s][0]:
                    grip_miss[s] = (e, f)
            if _frames_ok(fis, f):
                B = P.t["foot_" + s] + P.abs["foot_" + s] @ BALL_OFF
                e = (B - STIR[s]).length + row["err"].get("foot_" + s, 0.0)
                if e > stir_miss[s][0]:
                    stir_miss[s] = (e, f)
        if _frames_ok(seated, f):
            c = row["pelvis"].z - SADDLE_TOP
            if c < clear[0]:
                clear = (c, f)
    r = lambda t: [round(t[0], 4), t[1]]
    out = {"ik_max_err_m": {k: r(v) for k, v in ik.items()}}
    if hog:
        out["rein_grip_miss_m"] = {k: r(v) for k, v in grip_miss.items()}
    if fis:
        out["stirrup_miss_m"] = {k: r(v) for k, v in stir_miss.items()}
    if seated and clear[0] < 9:
        out["pelvis_clearance_min_m"] = r(clear)
    return out


def _frames_ok(spec, f):
    if spec is True:
        return True
    if not spec:
        return False
    if isinstance(spec, str):
        if "11-22" in spec:
            return f >= 11
        return False
    return any(a <= f <= b for a, b in spec)


if __name__ == "__main__":
    A.pole_calibrate()
    upper = RL.upper_bones()
    report, made = [], []
    for name, fn in RL.CLIPS.items():
        if ONLY and name not in ONLY:
            continue
        poses, m = fn()
        S_grip = None
        if m.get("synced_to"):
            S = Sync(m["synced_to"], frames=m.get("source_frames"))
            assert len(poses) == S.n, (name, len(poses), S.n)
            S_grip = S.grip
        elif m.get("hands_on_grips"):
            S_grip = {s: [GRIP_REST[s]] * len(poses) for s in "lr"}
        act, diag = TL.bake2(name, poses)
        res = residuals(name, poses, diag, m, S_grip)
        made.append((name, act))
        r0, r1 = poses[0].root, poses[-1].root
        e = {"name": name, "glb_name": name + ("_Loop" if m["loop"] else ""), "loop": bool(m["loop"]), "frames": len(poses), "fps": 30,
             "seconds": round((len(poses) - 1) / 30.0, 3), "synced_to": m.get("synced_to"), "layer": m.get("layer", "full"),
             "root_delta_m": [round(r1.x - r0.x, 3), round(r1.y - r0.y, 3), round(r1.z - r0.z, 3)]}
        if m.get("source_frames"):
            e["horse_source_frames"] = m["source_frames"]
        if e["layer"] == "upper":
            e["upper_bones"] = upper
        for k in ("events", "contacts", "notes", "start_stand_point", "start_yaw_deg", "end_stand_point", "end_yaw_deg", "end_ground_point",
                  "hands_on_grips", "feet_in_stirrups", "seated", "split_of", "weapon", "aim_dir_clip"):
            if k in m:
                e[k] = m[k]
        e.update(res)
        report.append(e)
        print("CLIP", name, len(poses), json.dumps(res), flush=True)
    if not ONLY:
        pass
    V2.export(made, report, OUT)
