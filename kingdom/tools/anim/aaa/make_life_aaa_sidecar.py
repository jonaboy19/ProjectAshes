"""Writes animations/life/UAL_Life_AAA.glb.life.json (LivingWorld sidecar, schema of make_life_cmu_sidecar.py) and renames the
clips in UAL_Life_AAA.glb.clips.json to match the GLB.  UAL_Life_AAA.glb itself is UAL_AAA_LivingWorld.glb reduced with
tools/anim/glb_edit_clips.py (keep the 3 reviewed sit clips, rename to Life_AAA_*_Loop).
Run:  python kingdom/tools/anim/aaa/make_life_aaa_sidecar.py
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
LIFE = os.path.join(KING, "assets", "incoming", "animations", "life")
GLB = os.path.join(LIFE, "UAL_Life_AAA.glb")
RENAME = {"Tavern_Sit_Idle": "Life_AAA_Sit_Idle", "Tavern_Sit_LegSwing": "Life_AAA_Sit_LegSwing", "Tavern_Sit_Fidget_Ponder": "Life_AAA_Sit_Ponder"}
CLIPS = json.load(open(GLB + ".clips.json"))
rep = []
for c in CLIPS:
    if c["name"] in RENAME:
        c["name"] = RENAME[c["name"]]
    if c["name"].startswith("Life_AAA_"):
        rep.append(c)
CLIPS = rep
json.dump(CLIPS, open(GLB + ".clips.json", "w"), indent=1)
NOTES = {
    "Life_AAA_Sit_Idle": ("seated idle on a stool or bench, seat ~0.45 m (pelvis 0.47-0.49 m); play the bench / stool Enter first", "CMU 13_04 2.5-7.0 s",
                          "Life_Mocap_Sit_Stool_Enter", "Life_Mocap_Sit_Stool_Exit", ["sit", "idle"]),
    "Life_AAA_Sit_LegSwing": ("seated, legs swinging, pelvis 0.78-0.93 m: needs a HIGH seat (~0.8 m); no such smart-object slot exists yet, so it is unused", "CMU 14_29 2.5-7.5 s",
                              None, None, ["sit", "high", "legswing"]),
    "Life_AAA_Sit_Ponder": ("seated, leaning forward on a knee (thinking), seat ~0.45 m (pelvis 0.46-0.50 m)", "CMU 13_05 2.0-6.5 s",
                            "Life_Mocap_Sit_Stool_Enter", "Life_Mocap_Sit_Stool_Exit", ["sit", "ponder", "fidget"]),
}
out = {"library": "res://assets/incoming/animations/life/UAL_Life_AAA.glb", "fps": 30,
       "notes": ["Source: CMU Graphics Lab Motion Capture Database (free for commercial use; see animations/cmu_mocap/LICENSE), BVH by Bruce Hahne / cgspeed; retargeted onto the Quaternius UAL rig (CC0).",
                 "Derived from animations/aaa/UAL_AAA_LivingWorld.glb: only the 3 sit clips that passed frame-sheet review (docs/anim/aaa_wiring/review/p16) are kept; the rest of that pack repeats BVHs UAL_Life_Mocap.glb already has or is not what its name says.",
                 "Rebuild: cp UAL_AAA_LivingWorld.glb UAL_Life_AAA.glb; python tools/anim/glb_edit_clips.py edit UAL_Life_AAA.glb <edits>; python tools/anim/aaa/make_life_aaa_sidecar.py"],
       "clips": {}}
for c in CLIPS:
    n = c["name"]
    note, src, enter, exit_, tags = NOTES[n]
    out["clips"][n] = {"category": "rest/sit", "loop": True, "layer": "full", "props": [], "enter": enter, "exit": exit_, "blend_in": 0.25, "blend_out": 0.3,
                       "events": {"loop_seam": [int(c["frames"]) - 1]}, "anchor": None, "note": note, "speed_mps": 0.0, "pair": None, "ik_l_on_prop": None,
                       "mask_from": None, "tags": ["cmu", "mocap"] + tags, "source": src, "frames": c["frames"], "seconds": c["seconds"]}
with open(GLB + ".life.json", "w", encoding="utf-8", newline="\n") as fh:
    json.dump(out, fh, indent=1)
    fh.write("\n")
print("sidecar:", list(out["clips"]))
