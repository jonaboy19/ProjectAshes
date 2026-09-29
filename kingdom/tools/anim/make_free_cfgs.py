# Writes tools/anim/cfg_free_<category>.json for retarget_bvh.py from the clip table below.
# The table is the single source of truth for the free clip library
# (assets/incoming/animations_free/): clip name, CMU take, trim window (seconds), options,
# suggested use. `build_free_readme.py` reads the same table.
#
#   python tools/anim/make_free_cfgs.py            (plain python 3, no Blender needed)
#
# Row: (name, take "SS_NN", start_s, end_s, opts, use)
#   opts: mirror=True (left/right flip), heading="strike|mean|start|none" (default strike: the
#   strongest hand/foot reach is aimed +forward), loop=True, fingers="fist|relaxed|flat", inplace="smooth|linear|none",
#   heading_deg=<extra yaw>, smooth=<sec>.
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
UAL = "../../assets/incoming/quaternius/universal-animation-library/Unreal-Godot/UAL1_Standard.glb"
OUT = "../../assets/incoming/animations_free/%s/UAL_Free_%s.glb"
CMU_MAP = {"pelvis": "Hips", "spine_01": "LowerBack", "spine_02": "Spine", "spine_03": "Spine1", "neck_01": "Neck",
           "Head": "Head", "clavicle_l": "LeftShoulder", "upperarm_l": "LeftArm", "lowerarm_l": "LeftForeArm",
           "hand_l": "LeftHand", "clavicle_r": "RightShoulder", "upperarm_r": "RightArm", "lowerarm_r": "RightForeArm",
           "hand_r": "RightHand", "thigh_l": "LeftUpLeg", "calf_l": "LeftLeg", "foot_l": "LeftFoot", "ball_l": "LeftToeBase",
           "thigh_r": "RightUpLeg", "calf_r": "RightLeg", "foot_r": "RightFoot", "ball_r": "RightToeBase"}
FINGER_POSES = {"relaxed": ["Idle_Loop", 0.0], "fist": ["Punch_Jab", 0.4]}

M = dict(mirror=True)
L = dict(loop=True)

TABLE = {
 "martial_arts_unarmed": [
  ("MA_Punch_Cross_R_Head_A", "13_18", 0.26, 2.32, {}, "straight rear-hand punch to the head, boxing step-in"),
  ("MA_Punch_Cross_R_Head_B", "14_03", 0.33, 2.93, {}, "straight rear-hand punch to the head, slower wind-up"),
  ("MA_Punch_Cross_R_Head_C", "15_13", 14.22, 16.09, {}, "quick straight rear-hand punch"),
  ("MA_Punch_Cross_L_Head", "13_18", 0.26, 2.32, M, "southpaw mirror of Cross_R_Head_A"),
  ("MA_Punch_Jab_L_Head_A", "15_13", 63.9, 65.49, {}, "quick lead-hand jab to the head"),
  ("MA_Punch_Jab_L_Head_B", "15_13", 67.39, 69.32, {}, "lead-hand jab, longer recovery"),
  ("MA_Punch_Jab_R_Head", "15_13", 63.9, 65.49, M, "southpaw mirror of Jab_L_Head_A"),
  ("MA_Punch_Cross_R_Body", "15_13", 5.54, 7.29, {}, "straight rear-hand punch to the body"),
  ("MA_Punch_Jab_L_Body", "15_13", 54.0, 55.67, {}, "lead-hand jab to the body"),
  ("MA_Punch_Heavy_R_A", "15_13", 12.59, 14.22, {}, "right hook to the head"),
  ("MA_Punch_Heavy_R_B", "15_13", 32.67, 34.87, {}, "right hook, heavier"),
  ("MA_Punch_Heavy_R_C", "15_13", 42.73, 44.37, {}, "right hook, tight"),
  ("MA_Punch_Heavy_L_A", "15_13", 12.59, 14.22, M, "left hook (mirror of Hook_R_A)"),
  ("MA_Punch_Heavy_L_B", "15_13", 32.67, 34.87, M, "left hook (mirror of Hook_R_B)"),
  ("MA_Punch_Heavy_R_D", "15_13", 16.09, 18.06, {}, "right uppercut"),
  ("MA_Punch_Heavy_R_E", "14_01", 6.03, 7.7, {}, "right uppercut, short"),
  ("MA_Punch_Heavy_L_C", "15_13", 16.09, 18.06, M, "left uppercut (mirror)"),
  ("MA_Punch_Heavy_L_D", "14_01", 6.03, 7.7, M, "left uppercut, short (mirror)"),
  ("MA_Punch_Heavy_R_Body", "14_01", 36.4, 38.57, {}, "right hook to the body"),
  ("MA_Kick_Front_R_Quick", "143_24", 1.92, 3.52, {}, "knee strike then step"),
 ],
 "combos": [
  ("MA_Combo_JabCross", "14_01", 14.97, 16.75, {}, "2-hit: lead jab then rear cross"),
  ("MA_Combo_JabCross_Southpaw", "14_01", 14.97, 16.75, M, "2-hit mirror"),
  ("MA_Combo_CrossCross", "13_18", 7.33, 9.69, {}, "2-hit straight punches"),
  ("MA_Combo_StraightStraight", "14_01", 4.14, 6.74, {}, "2-hit straight punches, advancing"),
  ("MA_Combo_BodyHeadHead", "143_23", 0.6, 3.9, {}, "3-hit: body jab, cross, jab"),
  ("MA_Combo_HeavyJab", "14_01", 18.83, 20.82, {}, "2-hit: uppercut then jab"),
  ("MA_Combo_HeavyHeavy", "14_01", 22.91, 25.65, {}, "2-hit: uppercut then hook"),
  ("MA_Combo_StraightHeavy", "14_03", 28.18, 31.14, {}, "2-hit: straight then uppercut"),
  ("MA_Combo_HeavyStraight", "15_13", 24.27, 26.16, {}, "2-hit: hook then straight"),
  ("MA_Combo_HeavyStraightHeavy", "17_10", 17.2, 20.5, {}, "3-hit: uppercut, straight, hook"),
  ("MA_Combo_Flurry_5Hit", "79_08", 0.5, 3.7, {}, "5-hit boxing flurry"),
  ("MA_Combo_Flurry_Long", "80_10", 0.6, 5.6, {}, "12-hit alternating flurry, finisher / super move"),
  ("MA_Combo_PunchKick", "141_14", 0.79, 4.81, {}, "punches into a kick"),
 ],
 "kicks": [
  ("MA_Kick_Front_R_Low", "144_05", 0.31, 2.16, {}, "front snap kick, low (shin / knee height)"),
  ("MA_Kick_Front_R_Mid", "144_05", 3.94, 5.83, {}, "front kick, waist height"),
  ("MA_Kick_Front_R_High", "144_05", 19.92, 22.09, {}, "front kick, chest height"),
  ("MA_Kick_Front_L_Low", "144_09", 0.31, 2.4, {}, "front snap kick, low, left leg"),
  ("MA_Kick_Front_L_Mid", "144_09", 4.4, 6.55, {}, "front kick, waist height, left leg"),
  ("MA_Kick_Front_L_High", "144_09", 15.36, 17.58, {}, "front kick, chest height, left leg"),
  ("MA_Kick_Jump_R", "75_16", 1.6, 2.86, {}, "running jump kick"),
  ("MA_Kick_Jump_L", "75_16", 1.6, 2.86, M, "running jump kick, mirrored"),
  ("MA_Kick_JumpHigh_A", "90_05", 0.9, 3.6, dict(heading="start"), "high jump kick with arms up"),
  ("MA_Kick_JumpHigh_B", "90_06", 1.6, 4.2, dict(heading="start"), "high jump kick, other leg"),
  ("MA_Kick_Swing_R", "74_05", 0.5, 2.7, {}, "full-swing kick"),
 ],
 "defense": [
  ("MA_Block_L_A", "144_07", 0.24, 1.42, dict(heading="mean"), "left-arm block, stance shift"),
  ("MA_Block_L_B", "144_07", 3.07, 3.88, dict(heading="mean"), "left-arm block, short"),
  ("MA_Block_L_C", "144_07", 16.37, 17.42, dict(heading="mean"), "left-arm high block"),
  ("MA_Block_R_A", "144_26", 0.31, 1.44, dict(heading="mean"), "right-arm block, stance shift"),
  ("MA_Block_R_B", "144_26", 2.87, 4.42, dict(heading="mean"), "right-arm block, long"),
  ("MA_Guard_Boxing", "13_18", 4.7, 7.2, dict(loop=True, heading="mean"), "boxing guard with footwork bounce (idle in combat)"),
  ("MA_Dodge_Duck", "77_09", 1.0, 4.4, dict(heading="mean"), "duck under a flying object"),
  ("MA_Evade_AttackerCover", "76_03", 0.3, 2.6, dict(heading="mean"), "cover the head and shuffle away from an attacker"),
 ],
 "acrobatics": [
  ("MA_Acro_HandSpinKick", "87_01", 0.4, 4.2, dict(heading="start"), "drop to the hands, spin and kick out"),
  ("MA_Acro_Cartwheel_A", "144_01", 1.44, 4.21, dict(heading="start"), "cartwheel"),
  ("MA_Acro_Cartwheel_B", "144_01", 8.42, 11.07, dict(heading="start"), "cartwheel"),
  ("MA_Acro_Cartwheel_C", "144_01", 14.02, 16.92, dict(heading="start"), "cartwheel"),
  ("MA_Acro_Cartwheel_D", "49_06", 0.3, 3.9, dict(heading="start"), "cartwheel from a walk-up"),
  ("MA_Acro_Cartwheel_E", "88_09", 0.5, 3.4, dict(heading="start"), "stretch and cartwheel"),
  ("MA_Acro_Backflip_A", "88_01", 0.2, 1.67, dict(heading="start"), "standing backflip"),
  ("MA_Acro_Backflip_B", "87_03", 0.5, 2.03, dict(heading="start"), "standing backflip, softer"),
  ("MA_Acro_Backflip_C", "87_04", 0.4, 1.9, dict(heading="start"), "standing backflip"),
  ("MA_Acro_Somersault_Back", "90_01", 2.0, 5.5, dict(heading="start"), "backward somersault"),
  ("MA_Acro_Handspring", "90_11", 0.0, 1.4, dict(heading="start"), "handspring"),
  ("MA_Acro_FrontHandFlip_A", "90_14", 2.0, 4.5, dict(heading="start"), "front hand flip"),
  ("MA_Acro_FrontHandFlip_B", "90_15", 2.0, 5.0, dict(heading="start"), "front hand flip"),
  ("MA_Acro_SideFlip", "90_08", 0.5, 2.8, dict(heading="start"), "side flip"),
  ("MA_Acro_FlipForward_Hands", "90_09", 0.8, 2.5, dict(heading="start"), "flip forward onto hands"),
  ("MA_Acro_BackflipBackOnHands", "88_08", 0.3, 2.4, dict(heading="start"), "crouch and flip backward on hands"),
  ("MA_Acro_Flip_A", "85_01", 1.0, 6.5, dict(heading="start"), "jump twist into a flip"),
  ("MA_Acro_HandstandKicks", "85_05", 1.5, 11.0, dict(heading="start"), "handstand with leg kicks"),
  ("MA_Acro_KickFlip", "85_06", 4.9, 7.5, dict(heading="start"), "kick flip"),
  ("MA_Acro_MonkeyBackflip", "90_19", 1.5, 6.0, dict(heading="start"), "monkey backflip"),
 ],
 "reactions": [
  ("Fall_Forward_Knockdown", "90_16", 2.2, 4.2, dict(heading="start"), "trip and fall forward onto the face"),
  ("Fall_Slip_Back", "90_17", 1.0, 5.0, dict(heading="start"), "slip and fall on the back"),
  ("Fall_RugPull_Back", "90_18", 0.6, 2.6, dict(heading="start"), "feet swept away, fall flat on the back"),
  ("Fall_BackflipTwist", "90_13", 2.0, 5.5, dict(heading="start"), "failed backflip, lands prone"),
  ("GetUp_FaceDown_A", "140_01", 1.6, 6.6, dict(heading="start"), "get up from face down"),
  ("GetUp_FaceDown_B", "139_16", 1.2, 5.2, dict(heading="start"), "get up from face down, faster"),
  ("GetUp_Side", "140_03", 1.5, 8.0, dict(heading="start"), "get up lying on the side"),
  ("GetUp_Back_A", "140_08", 1.2, 7.5, dict(heading="start"), "get up from lying on the back"),
  ("GetUp_Back_B", "140_09", 1.2, 7.0, dict(heading="start"), "get up from lying on the back, alternate"),
 ],
 "casting": [
  ("Cast_Slam_Overhead", "79_01", 0.6, 3.3, dict(heading="strike"), "two-handed overhead chop: ground slam / earth AOE"),
  ("Cast_Push_Palm_A", "02_05", 0.8, 2.6, {}, "palm strike forward: wind push / force blast"),
  ("Cast_Push_Palm_B", "02_05", 8.0, 10.0, {}, "palm strike forward, second take"),
  ("Cast_Throw_1H", "141_11", 2.4, 5.4, {}, "overhand throw: projectile / fireball toss"),
  ("Cast_Aura_Raise_Arms", "144_30", 0.4, 4.6, dict(heading="mean"), "arms sweep overhead: buff / aura / channel"),
  ("Cast_Aura_Raise_Arms_B", "144_30", 21.0, 27.2, dict(heading="mean"), "arms sweep overhead, second take"),
 ],
}

# KayKit Character Animations 1.1 (CC0), Rig_Medium glTF actions -> UAL. Row: (name, glb suffix, action, opts, use)
KK_DIR = "../../assets/incoming/kaykit/character-animations/Animations/gltf/Rig_Medium/Rig_Medium_"
KK_MAP = {"pelvis": "hips", "spine_01": "spine", "spine_03": "chest", "Head": "head",
          "upperarm_l": "upperarm.l", "lowerarm_l": "lowerarm.l", "hand_l": "hand.l",
          "upperarm_r": "upperarm.r", "lowerarm_r": "lowerarm.r", "hand_r": "hand.r",
          "thigh_l": "upperleg.l", "calf_l": "lowerleg.l", "foot_l": "foot.l", "ball_l": "toes.l",
          "thigh_r": "upperleg.r", "calf_r": "lowerleg.r", "foot_r": "foot.r", "ball_r": "toes.r"}
KK_TABLE = {
 "casting_kaykit": [
  ("Cast_Raise_Charge", "CombatRanged", "Ranged_Magic_Raise", {}, "raise a hand and hold: charge / channel start, lightning call"),
  ("Cast_Shoot_1H", "CombatRanged", "Ranged_Magic_Shoot", {}, "one-hand projectile cast"),
  ("Cast_Spell_Short", "CombatRanged", "Ranged_Magic_Spellcasting", {}, "quick two-hand cast"),
  ("Cast_Spell_Long", "CombatRanged", "Ranged_Magic_Spellcasting_Long", {}, "long two-hand incantation, beam / big spell"),
  ("Cast_Summon", "CombatRanged", "Ranged_Magic_Summon", {}, "crouch, sweep arms up: summon / raise earth"),
  ("Cast_Throw_Orb", "General", "Throw", {}, "overhand throw: grenade, fireball toss"),
 ],
 "weapons": [
  ("Weapon_1H_Chop", "CombatMelee", "Melee_1H_Attack_Chop", {}, "1H sword overhead chop"),
  ("Weapon_1H_Chop_Jump", "CombatMelee", "Melee_1H_Attack_Jump_Chop", {}, "1H jump chop (plunge attack)"),
  ("Weapon_1H_Slice_Diagonal", "CombatMelee", "Melee_1H_Attack_Slice_Diagonal", {}, "1H diagonal slash"),
  ("Weapon_1H_Slice_Horizontal", "CombatMelee", "Melee_1H_Attack_Slice_Horizontal", {}, "1H horizontal slash"),
  ("Weapon_1H_Stab", "CombatMelee", "Melee_1H_Attack_Stab", {}, "1H thrust"),
  ("Weapon_2H_Chop", "CombatMelee", "Melee_2H_Attack_Chop", {}, "2H / staff overhead chop"),
  ("Weapon_2H_Slice", "CombatMelee", "Melee_2H_Attack_Slice", {}, "2H / staff sweep"),
  ("Weapon_2H_Spin", "CombatMelee", "Melee_2H_Attack_Spin", {}, "2H spin attack (staff / greatsword)"),
  ("Weapon_2H_Spinning", "CombatMelee", "Melee_2H_Attack_Spinning", {}, "2H fast spin"),
  ("Weapon_2H_Stab", "CombatMelee", "Melee_2H_Attack_Stab", {}, "spear / staff thrust"),
  ("Weapon_Block", "CombatMelee", "Melee_Block", {}, "raise a weapon or shield to block"),
  ("Weapon_Block_Attack", "CombatMelee", "Melee_Block_Attack", {}, "shield bash / counter after block"),
  ("Weapon_Block_Hit", "CombatMelee", "Melee_Block_Hit", {}, "block reaction when hit"),
  ("Weapon_DW_Chop", "CombatMelee", "Melee_Dualwield_Attack_Chop", {}, "dual-wield chop"),
  ("Weapon_DW_Slice", "CombatMelee", "Melee_Dualwield_Attack_Slice", {}, "dual-wield slash"),
  ("Weapon_DW_Stab", "CombatMelee", "Melee_Dualwield_Attack_Stab", {}, "dual-wield thrust"),
  ("MA_KK_Kick", "CombatMelee", "Melee_Unarmed_Attack_Kick", dict(fingers="fist"), "stylised unarmed kick"),
  ("MA_KK_Punch", "CombatMelee", "Melee_Unarmed_Attack_Punch_A", dict(fingers="fist"), "stylised unarmed punch"),
  ("MA_KK_Idle_Loop", "CombatMelee", "Melee_Unarmed_Idle", dict(fingers="fist", loop=True), "unarmed fighting stance"),
  ("Hit_KK_A", "General", "Hit_A", {}, "flinch"),
  ("Hit_KK_B", "General", "Hit_B", {}, "heavier flinch"),
 ],
}

def make_kk(cat, rows):
    clips = []
    for name, f, action, o, use in rows:
        c = {"name": name, "glb": KK_DIR + f + ".glb", "action": action, "fingers": o.get("fingers", "relaxed")}
        if o.get("loop"): c["loop"] = True
        clips.append(c)
    folder = "casting" if cat.startswith("casting") else cat
    return {"source_type": "gltf", "source_fps": 30, "scale_mode": "height", "ual": UAL,
            "out": OUT % (folder, cat.title().replace("_", "")), "smooth": 0, "fingers": "relaxed",
            "finger_poses": FINGER_POSES, "map": KK_MAP, "check_directions": False, "heading": "none", "clips": clips}

def make(cat, rows):
    clips = []
    for name, take, a, b, o, use in rows:
        c = {"name": name, "file": "%03d/%s.bvh" % (int(take.split("_")[0]), take), "start": a, "end": b,
             "fingers": o.get("fingers", "fist"), "inplace_sigma": o.get("inplace_sigma", 0.5), "smooth": o.get("smooth", 0.012)}
        for k in ("mirror", "loop", "heading", "heading_deg", "inplace"):
            if k in o: c[k] = o[k]
        clips.append(c)
    return {"source_type": "bvh", "bvh_dir": "${ANIM_SRC}/cmu-mocap/data", "ual": UAL,
            "out": OUT % (cat, cat.title().replace("_", "")), "smooth": 0.012, "fingers": "relaxed",
            "finger_poses": FINGER_POSES, "map": CMU_MAP, "check_directions": True, "heading": "strike", "clips": clips}

if __name__ == "__main__":
    n = 0
    for cat, rows in TABLE.items():
        json.dump(make(cat, rows), open(os.path.join(HERE, "cfg_free_%s.json" % cat), "w"), indent=1)
        n += len(rows)
    m = 0
    for cat, rows in KK_TABLE.items():
        json.dump(make_kk(cat, rows), open(os.path.join(HERE, "cfg_free_%s.json" % cat), "w"), indent=1)
        m += len(rows)
    print("wrote", len(TABLE) + len(KK_TABLE), "configs,", n, "CMU clips,", m, "KayKit clips")
