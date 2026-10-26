"""Writes cfg_loco_gaits.json: steady in-place gait loops at 2.0 / 2.7 / 3.4 / 4.5 m/s (CMU takes picked by hip-speed plateau scans,
docs/anim/loco_gaits.md) so the locomotion blend space has a clip near every speed between Walk (1.05) and Jog_Fwd (6.24).
  LOCO_SRC=<dir containing cmu/*.bvh> blender -b -P tools/anim/retarget_bvh.py -- tools/anim/loco/cfg_loco_gaits.json"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
base = json.load(open(os.path.join(HERE, "../cfg_free_acrobatics.json")))
cfg = {k: v for k, v in base.items() if k != "clips"}
cfg.update({
    "bvh_dir": "${LOCO_SRC}/cmu",
    "ual": "../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb",
    "out": "../../../assets/incoming/animations_free2/loco_transitions/UAL_Loco_Gaits.glb",
    "heading": "start", "smooth": 0.02, "check_directions": False, "fingers": "relaxed",
})
def gait(name, file, start, end):
    return dict(name=name, file=file, start=start, end=end, loop=True, loop_min=0.5, loop_search=0.04, loop_blend=0.04,
                heading="start", smooth=0.02, fingers="relaxed")
# windows = exactly ONE gait cycle (consecutive same-foot forward-most foot positions, docs/anim/loco_gaits.md), so the loop needs no crossfade
cfg["clips"] = [
    gait("Walk_Brisk", "143_32.bvh", 4.500, 5.075),   # 2.03 m/s (CMU), 0.575 s cycle
    gait("Jog_Mid", "35_20.bvh", 0.242, 0.975),       # 3.40 m/s run/jog, 0.733 s
    gait("Run_Mid", "127_08.bvh", 0.333, 0.967),      # 4.52 m/s run, 0.634 s
]
json.dump(cfg, open(os.path.join(HERE, "cfg_loco_gaits.json"), "w"), indent=1)
print("wrote cfg_loco_gaits.json", len(cfg["clips"]))
