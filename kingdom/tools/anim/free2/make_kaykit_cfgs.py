# Generates the retarget configs for the KayKit (CC0) Rig_Medium clips that are NOT in animations_free.
# python make_kaykit_cfgs.py   -> writes cfg_kk_<category>.json next to this file
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
STAGE = os.environ.get("ANIM_SRC2", r"C:/Users/Jonna/Documents/ProjectAshes_art_staging/anim_raw2")
MAP = {"pelvis":"hips","spine_01":"spine","spine_02":"chest","Head":"head",
 "upperarm_l":"upperarm.l","lowerarm_l":"lowerarm.l","hand_l":"wrist.l",
 "upperarm_r":"upperarm.r","lowerarm_r":"lowerarm.r","hand_r":"wrist.r",
 "thigh_l":"upperleg.l","calf_l":"lowerleg.l","foot_l":"foot.l","ball_l":"toes.l",
 "thigh_r":"upperleg.r","calf_r":"lowerleg.r","foot_r":"foot.r","ball_r":"toes.r"}
BASE = {"source_type":"blend","blend":STAGE+"/kaykit_medium.blend","source_armature":"Armature","source_fps":30,
 "ual":"../../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb",
 "smooth":0.0,"fingers":"relaxed","check_directions":True,
 "finger_poses":{"relaxed":["Idle_Loop",0.0],"fist":["Punch_Jab",0.4]},"map":MAP}
# (source action, new name, loop?, extra)
L = True
CATS = {
 "life_sim": [
  ("Chop","Work_Chop_Tree",0,{}),("Chopping","Work_Chop_Tree",L,{}),
  ("Dig","Work_Dig",0,{}),("Digging","Work_Dig",L,{}),
  ("Pickaxe","Work_Mine",0,{}),("Pickaxing","Work_Mine",L,{}),
  ("Hammer","Work_Hammer",0,{}),("Hammering","Work_Hammer",L,{}),
  ("Saw","Work_Saw",0,{}),("Sawing","Work_Saw",L,{}),
  ("Lockpick","Lockpick",0,{}),("Lockpicking","Lockpick",L,{}),
  ("Work_A","Work_Bench_A",0,{}),("Work_B","Work_Bench_B",0,{}),("Work_C","Work_Bench_C",0,{}),
  ("Working_A","Work_Bench_A",L,{}),("Working_B","Work_Bench_B",L,{}),("Working_C","Work_Bench_C",L,{}),
  ("Holding_A","Hold_Item_A",L,{}),("Holding_B","Hold_Item_B",L,{}),("Holding_C","Hold_Item_C",L,{}),
  ("Fishing_Cast","Fishing_Cast",0,{}),("Fishing_Idle","Fishing_Idle",L,{}),("Fishing_Bite","Fishing_Bite",0,{}),
  ("Fishing_Tug","Fishing_Tug",0,{}),("Fishing_Reeling","Fishing_Reel",L,{}),
  ("Fishing_Struggling","Fishing_Struggle",0,{}),("Fishing_Catch","Fishing_Catch",0,{}),
  ("Cheering","Emote_Cheer",L,{}),("Waving","Emote_Wave",L,{}),
  ("Interact","Interact_Reach",0,{}),("PickUp","Pick_Up_Ground",0,{}),("Use_Item","Use_Item_Kay",0,{}),
 ],
 "combat_reactions": [
  ("Hit_A","Hit_React_A",0,{}),("Hit_B","Hit_React_B",0,{}),
  # Death_A (Kay_Death_Fall_A) rejected in review: rigid plank, hips hover 0.36 m above the floor. Kay_Death_Fall_B is trimmed to 2.1 s,
  # the Dodge_* clips get pelvis_untravel (travel was carried twice), Attack_2H_Spin_Long trimmed to 0.3-1.9 s: see glb_edit_clips.py.
  ("Death_B","Death_Fall_B",0,{"floor":"none"}),
  ("Melee_Block","Block_Raise",0,{}),("Melee_Blocking","Block_Hold",L,{}),
  ("Melee_Block_Hit","Block_Impact",0,{}),("Melee_Block_Attack","Block_Counter",0,{}),
  ("Melee_2H_Idle","Stance_2H_Idle",L,{}),("Melee_Unarmed_Idle","Stance_Fists_Idle",L,{"fingers":"fist"}),
  ("Dodge_Forward","Dodge_Fwd",0,{}),("Dodge_Backward","Dodge_Back",0,{}),
  ("Dodge_Left","Dodge_L",0,{}),("Dodge_Right","Dodge_R",0,{}),
  ("Melee_2H_Attack_Spin","Attack_2H_Spin_Long",0,{"fingers":"fist"}),
 ],
 "movement_ext": [
  ("Crouching","Crouch_Idle",L,{}),("Sneaking","Sneak_Walk",L,{}),
  ("Walking_Backwards","Walk_Back",L,{}),
  ("Running_Strafe_Left","Run_Strafe_L",L,{}),("Running_Strafe_Right","Run_Strafe_R",L,{}),
  ("Walking_A","Walk_Kay_A",L,{}),("Walking_B","Walk_Kay_B",L,{}),("Walking_C","Walk_Kay_C_Casual",L,{}),
  ("Running_A","Run_Kay_A",L,{}),("Running_B","Run_Kay_B",L,{}),
  ("Jump_Start","Jump_Start_Kay",0,{}),("Jump_Idle","Jump_Air_Kay",L,{}),("Jump_Land","Jump_Land_Kay",0,{}),
  ("Jump_Full_Short","Jump_Short_Kay",0,{}),("Jump_Full_Long","Jump_Long_Kay",0,{}),
  ("Idle_A","Idle_Kay_A",L,{}),("Idle_B","Idle_Kay_B",L,{}),
 ],
 "ranged": [
  ("Ranged_Bow_Idle","Bow_Idle",L,{"fingers":"fist"}),("Ranged_Bow_Aiming_Idle","Bow_Aim_Idle",L,{"fingers":"fist"}),
  ("Ranged_Bow_Draw","Bow_Draw",0,{"fingers":"fist"}),("Ranged_Bow_Release","Bow_Release",0,{"fingers":"fist"}),
  ("Ranged_Bow_Draw_Up","Bow_Draw_Up",0,{"fingers":"fist"}),("Ranged_Bow_Release_Up","Bow_Release_Up",0,{"fingers":"fist"}),
  ("Running_HoldingBow","Run_Holding_Bow",L,{"fingers":"fist"}),
  ("Ranged_1H_Aiming","Pistol_Aim",L,{"fingers":"fist"}),("Ranged_1H_Shoot","Pistol_Shoot",0,{"fingers":"fist"}),("Ranged_1H_Reload","Pistol_Reload",0,{"fingers":"fist"}),
  ("Ranged_2H_Aiming","Rifle_Aim",L,{"fingers":"fist"}),("Ranged_2H_Shoot","Rifle_Shoot",0,{"fingers":"fist"}),("Ranged_2H_Reload","Rifle_Reload",0,{"fingers":"fist"}),
  ("Running_HoldingRifle","Run_Holding_Rifle",L,{"fingers":"fist"}),
 ],
 "undead": [
  ("Skeletons_Idle","Undead_Idle",L,{}),("Skeletons_Walking","Undead_Walk",L,{}),
  ("Skeletons_Taunt","Undead_Taunt",0,{}),("Skeletons_Taunt_Longer","Undead_Taunt_Long",0,{}),
  ("Skeletons_Awaken_Standing","Undead_Awaken_Stand",0,{}),("Skeletons_Awaken_Floor","Undead_Awaken_Floor",0,{"floor":"none"}),
  ("Skeletons_Death","Undead_Collapse",0,{"floor":"none"}),("Skeletons_Death_Resurrect","Undead_Resurrect",0,{"floor":"none"}),
  ("Skeletons_Spawn_Ground","Undead_Rise_Ground",0,{"floor":"none"}),
 ],
}
for cat, items in CATS.items():
    cfg = dict(BASE)
    cfg["out"] = "../../../assets/incoming/animations_free2/kaykit_%s/UAL_Kay_%s.glb" % (cat, cat)
    clips, used = [], set()
    for src, name, loop, extra in items:
        # the *_ing loop variants: keep the one-shot name unique by suffixing
        nm = "Kay_" + name
        if (nm, loop) in used: nm += "_B"
        used.add((nm, loop))
        c = {"name": nm, "action": src, "floor_limit": 0.3}
        if loop: c.update({"loop": True, "loop_native": True, "inplace": "linear"})
        c.update(extra)
        clips.append(c)
    cfg["clips"] = clips
    json.dump(cfg, open(os.path.join(HERE, "cfg_kk_%s.json" % cat), "w"), indent=1)
    print(cat, len(clips))
