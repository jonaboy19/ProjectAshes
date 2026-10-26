"""Writes cfg_loco_mixamo.json: the Mixamo locomotion set (staging/downloads/mixamo, no skin, 30 fps) retargeted onto UAL.
Raw FBX are not in the repo (Mixamo licence: no raw redistribution); only the retargeted game clips are.
  MIXAMO_SRC=<dir with the .fbx> blender -b -P tools/anim/retarget_bvh.py -- tools/anim/loco/cfg_loco_mixamo.json"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
base = json.load(open(os.path.join(HERE, "../cfg_cmu.json")))
cfg = {k: v for k, v in base.items() if k not in ("clips", "bvh_dir", "map")}
mx = lambda n: "mixamorig:" + n
cfg["map"] = {"pelvis": mx("Hips"), "spine_01": mx("Spine"), "spine_02": mx("Spine1"), "spine_03": mx("Spine2"), "neck_01": mx("Neck"),
              "Head": mx("Head")}
for side, S in (("l", "Left"), ("r", "Right")):
    cfg["map"].update({"clavicle_" + side: mx(S + "Shoulder"), "upperarm_" + side: mx(S + "Arm"), "lowerarm_" + side: mx(S + "ForeArm"),
                       "hand_" + side: mx(S + "Hand"), "thigh_" + side: mx(S + "UpLeg"), "calf_" + side: mx(S + "Leg"),
                       "foot_" + side: mx(S + "Foot"), "ball_" + side: mx(S + "ToeBase")})
cfg.update({"source_type": "fbx", "fbx_dir": "${MIXAMO_SRC}", "source_fps": 30,
            "ual": "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb",
            "out": "../../../assets/incoming/animations_free2/loco_transitions/UAL_Loco_Mixamo.glb",
            "heading": "start", "smooth": 0.0, "check_directions": False, "fingers": "relaxed"})
def loop(name, file, last):   # in-place loops: the Mixamo cycle is native; drop the duplicated last frame
    return dict(name=name, file=file, start=0.0, end=(last - 2) / 30.0, loop=True, loop_native=True, inplace="linear", heading="start")
def shot(name, file, **kw):
    d = dict(name=name, file=file, heading="start", inplace="smooth"); d.update(kw); return d
cfg["clips"] = [
    loop("Mx_Walk_Careful", "careful_walk_inplace.fbx", 139), loop("Mx_Walk_Standard", "standard_walk_inplace.fbx", 36),
    loop("Mx_Walk_Unarmed", "unarmed_walk_fwd_inplace.fbx", 42), loop("Mx_Run_Slow", "slow_run_inplace.fbx", 23),
    loop("Mx_Jog", "jogging_inplace.fbx", 78), loop("Mx_Run_Medium", "medium_run_inplace.fbx", 18),
    loop("Mx_Run_Standard", "standard_run_inplace.fbx", 23), loop("Mx_Run_Fast", "fast_run_inplace.fbx", 17),
    loop("Mx_SnS_Walk", "sns_walk_fwd_inplace.fbx", 34), loop("Mx_SnS_WalkBack", "sns_walk_back_inplace.fbx", 39),
    loop("Mx_SnS_Run", "sns_run_inplace.fbx", 22), loop("Mx_Strafe_R", "walk_strafe_right_inplace.fbx", 45),
    dict(loop("Mx_Strafe_L", "walk_strafe_right_inplace.fbx", 45), mirror=True),
    shot("Mx_WalkStart", "start_walking.fbx"), shot("Mx_WalkStop", "walk_to_stop_root.fbx"), shot("Mx_RunStop", "run_to_stop_root.fbx"),
    shot("Mx_RunTurn_R", "run_turn_right_root.fbx", yaw_root=False), dict(shot("Mx_RunTurn_L", "run_turn_right_root.fbx"), mirror=True),
]
json.dump(cfg, open(os.path.join(HERE, "cfg_loco_mixamo.json"), "w"), indent=1)
print("wrote cfg_loco_mixamo.json", len(cfg["clips"]))
