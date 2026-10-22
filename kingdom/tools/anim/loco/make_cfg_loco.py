"""Writes cfg_loco.json (the clip windows for the locomotion-transition + jump library).
python make_cfg_loco.py   -> cfg_loco.json next to this file. Edit the CLIPS table, not the json.
Windows are in source seconds (CMU BVH, 120 fps); "speed" > 1 plays the take faster; "warp" is [[src_s, out_s], ...]
relative to the window start. See README.md for every key."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
base = json.load(open(os.path.join(HERE, "../cfg_free_acrobatics.json")))
cfg = {k: v for k, v in base.items() if k != "clips"}
cfg.update({
    "bvh_dir": "${LOCO_SRC}/cmu",
    "ual": "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb",
    "out": "../../../assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb",
    "heading": "start",
    "smooth": 0.02,
    "check_directions": False,
    "ref_loops": ["Walk_Loop", "Jog_Fwd_Loop", "Sprint_Loop", "Idle_Loop", "Roll"],
})

JOG = "Jog_Fwd_Loop"
CLIPS = [
    # ---- starts / stops
    dict(name="Loco_WalkStart_F", file="16_31.bvh", start=0.55, end=2.3, speed=1.3,
         match_exit=dict(loop="Walk_Loop", range=[1.7, 2.6]), entry_loop="Idle_Loop", exit_loop="Walk_Loop"),
    dict(name="Loco_RunStart_F", file="16_55.bvh", start=0.08, end=1.45, speed=1.25,
         match_exit=dict(loop=JOG, range=[0.9, 1.45]), entry_loop="Idle_Loop", exit_loop=JOG),
    dict(name="Loco_RunStop_L", file="127_17.bvh", start=0.05, end=1.5, speed=1.45,
         match_entry=dict(loop=JOG, range=[0.05, 0.4], side="L"), entry_loop=JOG, exit_loop="Idle_Loop"),
    dict(name="Loco_RunStop_R", file="127_18.bvh", start=0.05, end=1.5, speed=1.45,
         match_entry=dict(loop=JOG, range=[0.05, 0.4], side="R"), entry_loop=JOG, exit_loop="Idle_Loop"),
    dict(name="Loco_WalkStop", file="16_33.bvh", start=0.7, end=2.4, speed=1.2,
         match_entry=dict(loop="Walk_Loop", range=[0.6, 1.2]), entry_loop="Walk_Loop", exit_loop="Idle_Loop"),
    dict(name="Loco_Sprint_Stop_Skid", file="127_19.bvh", start=0.15, end=1.5, speed=1.35,
         match_entry=dict(loop="Sprint_Loop", range=[0.12, 0.5]), entry_loop="Sprint_Loop", exit_loop="Idle_Loop",
         events=dict(skid_frames=[11, 20], skid_note="feet braking on the ground: spawn dust on these frames")),
    # ---- turns in place (heading change on the root bone)
    dict(name="Loco_TurnInPlace_90_L", file="36_03.bvh", start=10.0, end=11.2, speed=1.6, yaw_root=True,
         entry_loop="Idle_Loop", exit_loop="Idle_Loop"),
    dict(name="Loco_TurnInPlace_90_R", file="36_03.bvh", start=3.45, end=4.6, speed=1.6, yaw_root=True,
         entry_loop="Idle_Loop", exit_loop="Idle_Loop"),
    dict(name="Loco_TurnInPlace_180", file="36_02.bvh", start=9.65, end=11.9, speed=2.0, yaw_root=True,
         entry_loop="Idle_Loop", exit_loop="Idle_Loop"),
    dict(name="Loco_TurnInPlace_180_R", file="36_09.bvh", start=7.55, end=9.35, speed=2.0, yaw_root=True,
         entry_loop="Idle_Loop", exit_loop="Idle_Loop"),
    # ---- 180 pivot from a run: brake (Run Stop Run take) -> turn on the spot -> first strides (Run start take, facing back)
    dict(name="Loco_Pivot180_Run_L", yaw_root=True, xfade_frames=[3, 3], entry_loop=JOG, exit_loop=JOG,
         segments=[dict(file="127_17.bvh", start=0.3, end=0.85, speed=1.5, match_entry=dict(loop=JOG, range=[0.2, 0.5], side="L")),
                   dict(file="36_02.bvh", start=10.35, end=11.75, speed=2.6),
                   dict(file="16_55.bvh", start=0.08, end=0.95, speed=1.4, heading_deg=180)]),
    dict(name="Loco_Pivot180_Run_R", yaw_root=True, xfade_frames=[3, 3], entry_loop=JOG, exit_loop=JOG, mirror=True,
         segments=[dict(file="127_17.bvh", start=0.3, end=0.85, speed=1.5, match_entry=dict(loop=JOG, range=[0.2, 0.5], side="R")),
                   dict(file="36_02.bvh", start=10.35, end=11.75, speed=2.6),
                   dict(file="16_55.bvh", start=0.08, end=0.95, speed=1.4, heading_deg=180)]),
    # ---- jump set
    dict(name="Jump_Start", file="13_42.bvh", start=0.6, end=1.58, air_z=True, floor="start",
         warp=[[0, 0], [0.5, 0.15], [0.7, 0.22], [0.93, 0.30]], entry_loop="Idle_Loop"),
    dict(name="Jump_Rise", loop=True, pingpong=True, loop_seconds=0.8, file="13_41.bvh", start=1.55, end=1.75,
         air_z=1.0, floor="none", travel_fit=False, inplace="none"),
    dict(name="Jump_Fall", loop=True, pingpong=True, loop_seconds=0.8, file="82_04.bvh", start=2.2, end=2.45,
         air_z=1.0, floor="none", travel_fit=False, inplace="none"),
    dict(name="Jump_Land_Soft", file="16_05.bvh", start=1.45, end=2.5, air_z=True, speed=1.15, exit_loop="Idle_Loop",
         events=dict(touchdown_frame=4)),
    dict(name="Jump_Land_Hard", file="82_04.bvh", start=2.3, end=3.9, air_z=True, speed=1.15, exit_loop="Idle_Loop",
         events=dict(touchdown_frame=6)),
    dict(name="Jump_Land_Roll", xfade_frames=[4], exit_loop="Idle_Loop", events=dict(touchdown_frame=4, roll_start_frame=12), segments=[
        dict(file="82_04.bvh", start=2.38, end=2.85, air_z=True, speed=1.25),
        dict(ual="Roll", start=0.0, speed=1.0)]),
    dict(name="Jump_Running_Start", file="127_27.bvh", start=0.12, end=0.62, air_z=True, speed=1.2, heading="mean", events=dict(takeoff_frame=12),
         entry_loop=JOG),
    dict(name="Jump_Land_Running", file="127_27.bvh", start=0.95, end=1.9, air_z=True, speed=1.2, heading="mean", events=dict(touchdown_frame=2),
         exit_loop=JOG),
]
cfg["clips"] = CLIPS
out = os.path.join(HERE, "cfg_loco.json")
json.dump(cfg, open(out, "w"), indent=1)
print("wrote", out, len(CLIPS), "clips")
