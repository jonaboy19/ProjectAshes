# Measure the reference gait loops the transition clips must blend with (UAL Walk / Jog / Sprint / Idle).
#   blender -b -P analyze_loops.py -- <out.json>
# For each loop: length, the root travel per cycle, natural speed measured from the stance foot (world speed of the ball
# while it is planted = the speed the body must travel for zero sliding), foot-plant windows (frames), cadence, and the
# per-frame pose of a few bones (for phase matching of the transition clips).
import bpy, sys, os, json, math
import numpy as np
from mathutils import Vector

out = os.path.abspath(sys.argv[sys.argv.index("--") + 1])
HERE = os.path.dirname(os.path.abspath(__file__))
UAL = os.path.normpath(os.path.join(HERE, "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=UAL)
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
acts = {a.name: a for a in bpy.data.actions}
sc = bpy.context.scene
arm.animation_data_create()
L = {}
for name in ("Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Idle_Loop", "Walk_Formal_Loop", "Jump_Start", "Jump_Loop", "Jump_Land", "Roll"):
    a = acts[name]
    arm.animation_data.action = a
    arm.animation_data.action_slot = a.slots[0]
    f0, f1 = a.frame_range
    n = int(round(f1 - f0))
    fps = sc.render.fps
    rows = []
    for f in range(n + 1):
        sc.frame_set(int(f0) + f)
        pb = arm.pose.bones
        w = lambda b: arm.matrix_world @ pb[b].head
        rows.append({k: np.array(w(k)) for k in ("root", "pelvis", "foot_l", "foot_r", "ball_l", "ball_r", "Head")})
    dur = n / fps
    # root travel across the cycle (y forward is -Y in Blender space for UAL)
    rt = rows[-1]["root"] - rows[0]["root"]
    pt = rows[-1]["pelvis"] - rows[0]["pelvis"]
    info = {"frames": n + 1, "fps": fps, "seconds": round(dur, 3), "root_travel_xyz": [round(float(x), 3) for x in rt],
            "pelvis_travel_xyz": [round(float(x), 3) for x in pt]}
    # stance: ball (or foot) low and slow relative to the pelvis-following body... use height only + relative speed
    for side in ("l", "r"):
        z = np.array([r["ball_" + side][2] for r in rows]); zf = np.array([r["foot_" + side][2] for r in rows])
        info["ball_z_" + side] = [round(float(x), 3) for x in z]
        info["foot_z_" + side] = [round(float(x), 3) for x in zf]
        info["foot_rel_y_" + side] = [round(float(r["foot_" + side][1] - r["pelvis"][1]), 3) for r in rows]
        info["foot_rel_x_" + side] = [round(float(r["foot_" + side][0] - r["pelvis"][0]), 3) for r in rows]
        info["pelvis_y"] = [round(float(r["pelvis"][1]), 3) for r in rows]
        info["root_y"] = [round(float(r["root"][1]), 3) for r in rows]
    L[name] = info
    print(name, info["seconds"], "root travel", info["root_travel_xyz"], "pelvis", info["pelvis_travel_xyz"])
json.dump(L, open(out, "w"))
