#!/usr/bin/env python3
"""Build kingdom/data/anim/motion_tags.json: one normalised tag index over every NPC clip.

Design: docs/plans/NPC_MOTION_RULES.md section 3.7 rule C1 (package M2). The reader is
scripts/living_world/clip_picker.gd.

Sources (read only):
  kingdom/assets/incoming/animations/**/*.life.json   the LIFE sidecars (category, tags, props, loop, layer, speed)
  kingdom/assets/incoming/animations/aaa/*.clips.json AAA mocap clip lists (length, loop)
  kingdom/data/anim/aaa_clips.json                    which AAA clips are wired, under which game name
  kingdom/data/living_world/vat_bake.json             clips baked for the far (VAT) crowd tier

Axes per clip: verb, posture, prop, mood, layer, intensity (0-1), vat (baked yes/no); plus phase
(loop / once / enter / exit), weight, tags, wired, speed_mps, seconds, category, library.

Inference order, first hit wins per axis: HAND table (the untagged Work / Mixamo5 / Meshy / Mixamo_Farm
libraries plus anything the keywords get wrong) -> keywords over the clip name and sidecar tags ->
the category default. Deterministic: sorted keys, no timestamps.

  python3 kingdom/tools/anim/life/tag_clips.py            write the index
  python3 kingdom/tools/anim/life/tag_clips.py --check    exit 1 if the file on disk is stale or invalid
"""
import argparse
import glob
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ANIM_GLOB = os.path.join(KINGDOM, "assets", "incoming", "animations", "**", "*.life.json")
AAA_WIRING = os.path.join(KINGDOM, "data", "anim", "aaa_clips.json")
VAT_BAKE = os.path.join(KINGDOM, "data", "living_world", "vat_bake.json")
OUT = os.path.join(KINGDOM, "data", "anim", "motion_tags.json")

POSTURES = ["stand", "sit", "kneel", "crouch", "lie"]
MOODS = ["calm", "happy", "sad", "angry", "afraid"]
LAYERS = ["full", "upper"]
PHASES = ["loop", "once", "enter", "exit"]
VERBS = [
    "idle", "fidget", "look", "weather", "stretch", "lean", "watch", "walk", "run", "march", "carry", "push",
    "lift", "pick", "talk", "listen", "argue", "greet", "wave", "point", "nod", "shrug", "laugh", "bow", "hug",
    "handshake", "comfort", "cry", "whisper", "salute", "thank", "react", "flinch", "hammer", "saw", "chop",
    "dig", "plant", "harvest", "hoe", "milk", "water", "feed", "sweep", "scrub", "hang", "stir", "cook", "forge",
    "mine", "fish", "draw_water", "sit", "sleep", "wake", "kneel", "pray", "mourn", "warm", "eat", "drink",
    "toast", "cheer", "play_music", "read", "write", "sell", "trade", "browse", "bartend", "inspect", "guard",
    "exercise", "play", "strike", "parry", "dodge", "stagger", "hit_react", "cast", "climb", "jump",
]

# category defaults: (verb, posture, mood). Used when neither HAND nor a keyword decides.
CATEGORY = {
    "work/farm": ("hoe", "stand", "calm"), "work/wood": ("chop", "stand", "calm"),
    "work/smith": ("forge", "stand", "calm"), "work/carpentry": ("hammer", "stand", "calm"),
    "work/craft": ("hammer", "stand", "calm"), "work/cook": ("cook", "stand", "calm"),
    "work/chore": ("sweep", "stand", "calm"), "work/chores": ("sweep", "stand", "calm"),
    "work/laundry": ("scrub", "stand", "calm"), "work/fish": ("fish", "stand", "calm"),
    "work/mine": ("mine", "stand", "calm"), "work/forage": ("pick", "crouch", "calm"),
    "work/market": ("sell", "stand", "calm"), "work/shop": ("sell", "stand", "calm"),
    "work/trade": ("trade", "stand", "calm"), "work/guard": ("guard", "stand", "calm"),
    "work/tavern": ("bartend", "stand", "calm"), "work/inspect": ("inspect", "kneel", "calm"),
    "carry/full": ("carry", "stand", "calm"), "carry/upper": ("carry", "stand", "calm"),
    "carry/barrow": ("push", "stand", "calm"),
    "walk/style": ("walk", "stand", "calm"),
    "rest/sit": ("sit", "sit", "calm"), "rest/sleep": ("sleep", "lie", "calm"),
    "rest/lean": ("lean", "stand", "calm"), "rest/fire": ("warm", "kneel", "calm"),
    "rest": ("idle", "kneel", "calm"),
    "social/talk": ("talk", "stand", "calm"), "social/argue": ("argue", "stand", "angry"),
    "social/react": ("react", "stand", "calm"), "social/pair": ("greet", "stand", "calm"),
    "social/tavern": ("drink", "sit", "happy"), "social/mourn": ("mourn", "stand", "sad"),
    "social/music": ("play_music", "stand", "calm"), "social/market": ("browse", "stand", "calm"),
    "ritual/pray": ("pray", "stand", "calm"), "ritual/kneel": ("kneel", "kneel", "calm"),
    "kid/play": ("play", "stand", "happy"),
    "ambient": ("look", "stand", "calm"), "ambient/fidget": ("fidget", "stand", "calm"),
    "ambient/react": ("look", "stand", "calm"), "ambient/weather": ("weather", "stand", "calm"),
    "ambient/read": ("read", "stand", "calm"), "ambient/write": ("write", "sit", "calm"),
    "ambient/eat": ("eat", "stand", "calm"),
    "eat": ("eat", "sit", "calm"), "music": ("play_music", "stand", "calm"),
}
POSTURE_TOKENS = [
    ({"sleep", "bed"}, "lie"),
    ({"kneel", "kneeling"}, "kneel"),
    ({"squat", "crouch"}, "crouch"),
    ({"sit", "seated", "stool", "bench", "chair", "doze", "ground", "floor"}, "sit"),
]
MOOD_TOKENS = [
    ({"argue", "quarrel", "angry"}, "angry"),
    ({"sad", "cry", "grief", "mourn", "mourning", "tired"}, "sad"),
    ({"happy", "laugh", "cheer", "funny", "festival", "excited", "skip", "toast", "cheers"}, "happy"),
]
LOUD = {"chop", "hammer", "forge", "mine", "run", "cheer", "argue", "strike", "saw"}
CALM_VERBS = {"idle", "fidget", "look", "listen", "lean", "watch", "sit", "sleep", "kneel", "pray", "warm", "read",
              "write", "nod", "weather", "stretch"}

# ---------------------------------------------------------------------------------------------------
# HAND table. Keys are clip names; values override verb, posture, prop, mood, intensity, weight, phase
# or add a style tag. Covers the libraries that ship without tags (Work, Mixamo5, Meshy, Mixamo_Farm)
# plus the tagged ones whose names the category default would get wrong.
# ---------------------------------------------------------------------------------------------------
def _h(verb, intensity, **kw):
    d = {"verb": verb, "intensity": intensity}
    d.update(kw)
    return d


HAND = {
    # --- Work (author_life.py, no tags) ---
    "Life_Farm_Hoe": _h("hoe", 0.55), "Life_Farm_Sow": _h("plant", 0.4), "Life_Farm_Harvest": _h("harvest", 0.55),
    "Life_Farm_Milk_Cow": _h("milk", 0.35, posture="sit"), "Life_Farm_Feed_Chickens": _h("feed", 0.35),
    "Life_Smith_Hammer": _h("forge", 0.9), "Life_Smith_Quench": _h("forge", 0.5), "Life_Smith_Bellows": _h("forge", 0.5),
    "Life_Carp_Saw": _h("saw", 0.65), "Life_Carp_Nail": _h("hammer", 0.75),
    "Life_Wood_Chop": _h("chop", 0.9), "Life_Wood_Place_Log": _h("lift", 0.5),
    "Life_Fish_Idle_Rod": _h("fish", 0.15, weight=2.0), "Life_Fish_Cast": _h("fish", 0.5), "Life_Fish_Reel": _h("fish", 0.5),
    "Life_Cook_Stir": _h("stir", 0.4), "Life_Cook_Chop": _h("cook", 0.55),
    "Life_Chore_Laundry_Scrub": _h("scrub", 0.5, posture="kneel"), "Life_Chore_Laundry_Wring": _h("scrub", 0.4, posture="kneel"),
    "Life_Chore_Hang_Washing": _h("hang", 0.35), "Life_Chore_Sweep": _h("sweep", 0.4),
    "Life_Chore_Well_Crank": _h("draw_water", 0.5), "Life_Chore_Well_Lift_Bucket": _h("draw_water", 0.55, phase="once"),
    "Life_Carry_Sheaf_Upper": _h("carry", 0.4), "Life_Carry_Plank_Upper": _h("carry", 0.4),
    "Life_Carry_Bucket_Upper": _h("carry", 0.4), "Life_Carry_Two_Buckets_Upper": _h("carry", 0.5),
    "Life_Carry_Sack_Upper": _h("carry", 0.4), "Life_Carry_Crate_Upper": _h("carry", 0.4),
    "Life_Carry_Basket_Upper": _h("carry", 0.4),
    "Life_Carry_Pick_Up": _h("lift", 0.45), "Life_Carry_Put_Down": _h("lift", 0.45), "Life_Cart_Push": _h("push", 0.6),
    # --- Mixamo5 (work_set5, no tags) ---
    "Life_Mx5_Talk_General": _h("talk", 0.45), "Life_Mx5_Talk_Explain": _h("talk", 0.6),
    "Life_Mx5_Talk_Funny": _h("talk", 0.75, mood="happy"),
    "Life_Mx5_Argue_A": _h("argue", 0.85, mood="angry"), "Life_Mx5_Argue_B": _h("argue", 0.8, mood="angry"),
    "Life_Mx5_Agree_Nod": _h("nod", 0.3),
    "Life_Mx5_Lean_Wall_Leg_Up": _h("lean", 0.15), "Life_Mx5_Lean_Wall_Shoulder": _h("lean", 0.15),
    "Life_Mx5_Sit_Cross_Legged": _h("sit", 0.1, posture="sit"), "Life_Mx5_Sit_Reclined": _h("sit", 0.1, posture="sit"),
    "Life_Mx5_Sit_Laughing": _h("laugh", 0.7, posture="sit", mood="happy"),
    "Life_Mx5_Sit_Cheer_Talk": _h("cheer", 0.75, posture="sit", mood="happy"),
    "Life_Mx5_Sit_Down_Drink": _h("drink", 0.35, posture="sit", mood="happy", phase="once"),
    "Life_Mx5_Look_Around_A": _h("look", 0.2), "Life_Mx5_Look_Around_B": _h("look", 0.2),
    "Life_Mx5_Dig": _h("dig", 0.65), "Life_Mx5_Bench_Work": _h("hammer", 0.6), "Life_Mx5_Overhead_Strike": _h("chop", 0.85),
    "Life_Mx5_Bartend_Pour": _h("bartend", 0.4),
    "Life_Mx5_Shoulder_Carry_Idle": _h("carry", 0.2), "Life_Mx5_Shoulder_Carry_Walk": _h("carry", 0.5),
    "Life_Mx5_Kneel_Down": _h("kneel", 0.35, posture="kneel", phase="enter"),
    "Life_Mx5_Kneel_To_Stand": _h("kneel", 0.35, posture="kneel", phase="exit"),
    "Life_Mx5_Kneel_Inspect": _h("inspect", 0.2, posture="kneel"), "Life_Mx5_Kneel_Warm_Hands": _h("warm", 0.15, posture="kneel"),
    "Life_Mx5_Bass_Guitar": _h("play_music", 0.55),
    # --- Meshy (text-to-motion, no tags) ---
    "Life_Mz_Chop_Wood": _h("chop", 0.9), "Life_Mz_Smith_Hammer": _h("forge", 0.9),
    "Life_Mz_Plant_Kneel": _h("plant", 0.4, posture="kneel"), "Life_Mz_Laundry_Scrub": _h("scrub", 0.5, posture="kneel"),
    "Life_Mz_Stir_Cauldron": _h("stir", 0.4), "Life_Mz_Sweep": _h("sweep", 0.4), "Life_Mz_Mine_Pickaxe": _h("mine", 0.9),
    "Life_Mz_Nail_Bench": _h("hammer", 0.65), "Life_Mz_Sleep_Bed": _h("sleep", 0.05, posture="lie"),
    "Life_Mz_Wake_Bed": _h("wake", 0.3, posture="lie", phase="exit"), "Life_Mz_Eat_Seated": _h("eat", 0.2, posture="sit"),
    "Life_Mz_Milk_Stool": _h("milk", 0.35, posture="sit"), "Life_Mz_Scythe": _h("harvest", 0.65),
    "Life_Mz_Wheelbarrow_Walk": _h("push", 0.55), "Life_Mz_Lute": _h("play_music", 0.5),
    "Life_Mz_Kneel_Down": _h("pray", 0.3, posture="kneel", phase="enter"),
    "Life_Mz_Forge_Glowing": _h("forge", 0.5), "Life_Mz_Butcher": _h("cook", 0.65),
    "Life_Mz_Tankard_Laugh": _h("laugh", 0.7, mood="happy"), "Life_Mz_Carry_Sack_Walk": _h("carry", 0.5),
    # --- Mixamo_Farm (farming pack, tag "farm" only) ---
    "Life_Mx2_Milk_Cow": _h("milk", 0.35, posture="sit"), "Life_Mx2_Dig_Plant": _h("dig", 0.5, posture="kneel"),
    "Life_Mx2_Plant_Plant": _h("plant", 0.4, posture="kneel"), "Life_Mx2_Pull_Plant_B": _h("harvest", 0.5, posture="crouch"),
    "Life_Mx2_Pick_Fruit_B": _h("harvest", 0.4), "Life_Mx2_Pick_Fruit_C": _h("harvest", 0.4),
    "Life_Mx2_Water": _h("water", 0.4), "Life_Mx2_Kneel_Idle": _h("kneel", 0.1, posture="kneel"),
    "Life_Mx2_Plant_Tree": _h("plant", 0.5, posture="crouch", phase="once"),
    "Life_Mx2_Box_Idle": _h("carry", 0.15), "Life_Mx2_Box_Walk_Arc": _h("carry", 0.5),
    "Life_Mx2_Holding_Idle": _h("carry", 0.15), "Life_Mx2_Holding_Walk": _h("carry", 0.5),
    "Life_Mx2_Wheelbarrow_Idle": _h("push", 0.15), "Life_Mx2_Wheelbarrow_Walk": _h("push", 0.55),
    "Life_Mx2_Wheelbarrow_Dump": _h("push", 0.6, phase="once"),
    # --- tagged libraries where the keywords need help ---
    "Life_Mx_Dig_Plant": _h("dig", 0.5, posture="kneel"), "Life_Mx_Pick_Fruit": _h("harvest", 0.4),
    "Life_Mx_Plant_Kneel": _h("plant", 0.4, posture="kneel"), "Life_Mx_Plant_Tree": _h("plant", 0.5, posture="crouch", phase="once"),
    "Life_Mx_Pull_Plant": _h("harvest", 0.5, posture="crouch"), "Life_Mx_Pick_Ground": _h("pick", 0.4, posture="crouch", phase="once"),
    "Life_Mx_Pick_Up": _h("lift", 0.45), "Life_Mx_Lift_Heavy": _h("lift", 0.65), "Life_Mx_Carry_Box_Walk": _h("carry", 0.5),
    "Life_Mx_Wheelbarrow_Walk": _h("push", 0.55), "Life_Mx_Fish_Idle": _h("fish", 0.15, weight=2.0),
    "Life_Mx_Chop_Wood": _h("chop", 0.9), "Life_Mx_Scythe": _h("harvest", 0.65), "Life_Mx_Milk_Cow": _h("milk", 0.35, posture="sit"),
    "Life_Mx_Fish_Cast_Reel": _h("fish", 0.5),
    "Life_Mx_Sit_Chair": _h("sit", 0.1, posture="sit"), "Life_Mx_Sit_Floor": _h("sit", 0.1, posture="sit"),
    "Life_Mx_Sit_Chair_Talk": _h("talk", 0.45, posture="sit"),
    "Life_Mx_Stand_To_Sit": _h("sit", 0.3, posture="sit", phase="enter"), "Life_Mx_Sit_To_Stand": _h("sit", 0.3, posture="sit", phase="exit"),
    "Life_Mx_Sleep_Bed": _h("sleep", 0.05, posture="lie"), "Life_Mx_Get_Up_Back": _h("wake", 0.3, posture="lie", phase="exit"),
    "Life_Mx_Drink": _h("drink", 0.4, posture="stand"), "Life_Mx_Talk_Chat": _h("talk", 0.45),
    "Life_Mx_Pray_Kneel": _h("pray", 0.1, posture="kneel"), "Life_Mx_Lute": _h("play_music", 0.55), "Life_Mx_Fiddle": _h("play_music", 0.6),
    "Life_Mx_Salute": _h("salute", 0.4), "Life_Mx_Thankful": _h("thank", 0.4, mood="happy"),
    "Life_Mx_Tell_Secret": _h("whisper", 0.25), "Life_Mx_Plank_Start": _h("exercise", 0.7, posture="crouch"),
    "Life_Mx_Wave": _h("wave", 0.5),
    "Life_Mocap_Chop_Wood": _h("chop", 0.8, phase="once"), "Life_Mocap_Dig": _h("dig", 0.65, phase="once"),
    "Life_Mocap_Rake": _h("hoe", 0.5, phase="once"), "Life_Mocap_Plant": _h("plant", 0.4, posture="crouch", phase="once"),
    "Life_Mocap_Sweep": _h("sweep", 0.45, phase="once"), "Life_Mocap_Carry_Heavy": _h("carry", 0.6),
    "Life_Mocap_Move_Box": _h("lift", 0.55), "Life_Mocap_Pick_Place": _h("pick", 0.4, posture="crouch"),
    "Life_Mocap_Slice": _h("cook", 0.5), "Life_Mocap_Fish": _h("fish", 0.5),
    "Life_Mocap_Chug": _h("drink", 0.6, mood="happy"), "Life_Mocap_Drink": _h("drink", 0.3, posture="stand"),
    "Life_Mocap_Eat_Table": _h("eat", 0.3, posture="sit"), "Life_Mocap_Eat_Soup": _h("eat", 0.3, posture="sit"),
    "Life_Mocap_Comfort_A": _h("comfort", 0.3, posture="sit", mood="sad"), "Life_Mocap_Comfort_B": _h("comfort", 0.3, posture="kneel", mood="sad"),
    "Life_Mocap_Converse_A": _h("talk", 0.5), "Life_Mocap_Converse_B": _h("listen", 0.35),
    "Life_Mocap_Directions": _h("point", 0.5), "Life_Mocap_Teach": _h("talk", 0.6),
    "Life_Mocap_Direct_Wave": _h("wave", 0.55), "Life_Mocap_Wave_Hello": _h("wave", 0.5),
    "Life_Mocap_Laugh": _h("laugh", 0.7, mood="happy"), "Life_Mocap_Cry": _h("cry", 0.5, mood="sad"),
    "Life_Mocap_Sad": _h("react", 0.3, mood="sad"), "Life_Mocap_Happy": _h("cheer", 0.8, mood="happy"),
    "Life_Mocap_Cold": _h("weather", 0.4, mood="afraid"),
    "Life_Mocap_Look_Around": _h("look", 0.2), "Life_Mocap_Shift_Weight": _h("idle", 0.15),
    "Life_Mocap_Stretch_Yawn": _h("stretch", 0.35), "Life_Mocap_Fiddle": _h("play_music", 0.6),
    "Life_Mocap_Sit_Stool_Enter": _h("sit", 0.3, posture="sit", phase="enter"),
    "Life_Mocap_Sit_Stool_Exit": _h("sit", 0.3, posture="sit", phase="exit"),
    "Life_Mocap_Sit_Stool_Idle": _h("sit", 0.1, posture="sit"),
    "Life_Mocap_Hopscotch": _h("play", 0.8), "Life_Mocap_Tag_Bluff": _h("play", 0.8), "Life_Mocap_Skip": _h("play", 0.7),
    "Life_Mocap_Quarrel_A": _h("argue", 0.85, mood="angry"), "Life_Mocap_Quarrel_B": _h("argue", 0.85, mood="angry"),
    "Life_Mocap_Buy": _h("trade", 0.35), "Life_Mocap_Pay": _h("trade", 0.35),
    "Life_Mocap_Saw": _h("saw", 0.65), "Life_Mocap_Hammer_Nail": _h("hammer", 0.75), "Life_Mocap_Stir": _h("stir", 0.4),
    "Life_Cmu_Stir": _h("stir", 0.4), "Life_Cmu_Saw": _h("saw", 0.65), "Life_Cmu_Hammer_Nail": _h("hammer", 0.75),
    "Life_Mocap_Handshake_A": _h("handshake", 0.35), "Life_Mocap_Handshake_B": _h("handshake", 0.35),
    "Life_Walk_Drunk": _h("walk", 0.45, style="drunk"), "Life_Walk_Limp": _h("walk", 0.35, mood="sad", style="injured"),
    "Life_Walk_Elder": _h("walk", 0.2, style="elder"), "Life_Walk_Cane": _h("walk", 0.2, style="elder"),
    "Life_Walk_Sad": _h("walk", 0.3, mood="sad"), "Life_Walk_Happy": _h("walk", 0.65, mood="happy"),
    "Life_Walk_Tired": _h("walk", 0.25, mood="sad", style="tired"), "Life_Walk_Brisk": _h("walk", 0.75, style="brisk"),
    "Life_Walk_Careful": _h("walk", 0.3, mood="afraid", style="careful"), "Life_Walk_March": _h("march", 0.7, style="march"),
    "Life_Walk_Proud": _h("walk", 0.5, style="proud"), "Life_Guard_Patrol_Walk": _h("march", 0.6, style="march"),
    "Life_Guard_Look_Out": _h("look", 0.3), "Life_Guard_Attention": _h("guard", 0.2), "Life_Guard_Lean_Spear": _h("guard", 0.1),
    "Life_Market_Call_Out": _h("sell", 0.85), "Life_Market_Hand_Over": _h("trade", 0.4), "Life_Market_Arrange": _h("sell", 0.35),
    "Life_Market_Browse": _h("browse", 0.25),
    "Life_Shop_Counter_Lean": _h("lean", 0.1), "Life_Shop_Wipe": _h("sweep", 0.35), "Life_Shop_Tally": _h("write", 0.2),
    "Life_Read_Stand": _h("read", 0.1), "Life_Read_Sit": _h("read", 0.1, posture="sit"),
    "Life_Write_Desk": _h("write", 0.15, posture="sit"),
    "Life_Tavern_Drink": _h("drink", 0.4, posture="stand"), "Life_Tavern_Toast": _h("toast", 0.7, posture="stand"),
    "Life_Tavern_Cheer": _h("cheer", 0.85, posture="stand"), "Life_Tavern_Lean_Bar": _h("lean", 0.15, posture="stand"),
    "Life_Tavern_Sit_Drink": _h("drink", 0.4, posture="sit"),
    "Life_Music_Lute": _h("play_music", 0.55), "Life_Music_Lute_Sit": _h("play_music", 0.5, posture="sit"),
    "Life_Music_Flute": _h("play_music", 0.5),
    "Life_Eat_Bread_Stand": _h("eat", 0.2, posture="stand"), "Life_Eat_Bowl_Sit": _h("eat", 0.2, posture="sit"),
    "Life_Rest_Sit_Bench": _h("sit", 0.1), "Life_Rest_Sit_Ground": _h("sit", 0.1), "Life_Rest_Sit_Chair": _h("sit", 0.1),
    "Life_Rest_Doze_Bench": _h("sleep", 0.05, posture="sit"), "Life_Rest_Sleep_Ground": _h("sleep", 0.05, posture="lie"),
    "Life_Pray_Stand": _h("pray", 0.1, posture="stand"), "Life_Pray_Kneel": _h("pray", 0.1, posture="kneel"),
    "Life_Social_Mourn_Kneel": _h("mourn", 0.2, posture="kneel"), "Life_Social_Mourn_Stand": _h("mourn", 0.2, posture="stand"),
    "Life_Talk_Explain": _h("talk", 0.6), "Life_Talk_Emphatic": _h("talk", 0.9), "Life_Talk_Casual": _h("talk", 0.3),
    "Life_Talk_Gossip": _h("talk", 0.3), "Life_Talk_Listen_Nod": _h("listen", 0.25), "Life_Talk_Listen_Hips": _h("listen", 0.2),
    "Life_Social_Argue_A": _h("argue", 0.85, mood="angry"), "Life_Social_Argue_B": _h("argue", 0.8, mood="angry"),
    "Life_Social_Laugh": _h("laugh", 0.65, mood="happy"), "Life_Social_Laugh_Slap": _h("laugh", 0.8, mood="happy"),
    "Life_Social_Point_Directions": _h("point", 0.5), "Life_Social_Wave_Greet": _h("wave", 0.5), "Life_Social_Wave_Far": _h("wave", 0.7),
    "Life_Social_Shrug": _h("shrug", 0.3), "Life_Social_Nod": _h("nod", 0.25), "Life_Social_Shake_Head": _h("react", 0.3),
    "Life_Social_Bow": _h("bow", 0.3),
    "Life_Social_Hug_A": _h("hug", 0.4, mood="happy"), "Life_Social_Hug_B": _h("hug", 0.4, mood="happy"),
    "Life_Social_Handshake_A": _h("handshake", 0.35), "Life_Social_Handshake_B": _h("handshake", 0.35),
    "Life_Kid_Run_Play": _h("run", 0.95, mood="happy"), "Life_Kid_Chase_Chicken": _h("run", 0.85, mood="happy"),
    "Life_Kid_Skip": _h("walk", 0.7, mood="happy"), "Life_Kid_Tag_Touch": _h("play", 0.8),
    "Life_Kid_Hopscotch": _h("play", 0.75), "Life_Kid_Clap_Jump": _h("play", 0.8),
    "Life_Ambient_Look_Around": _h("look", 0.2), "Life_Ambient_Scratch_Head": _h("fidget", 0.2),
    "Life_Ambient_Shift_Weight": _h("idle", 0.15), "Life_Ambient_Stretch_Morning": _h("stretch", 0.4),
    "Life_Ambient_Yawn": _h("stretch", 0.3), "Life_Ambient_Check_Sky": _h("weather", 0.2),
    "Life_Ambient_Shade_Eyes": _h("weather", 0.2), "Life_Ambient_Wipe_Brow": _h("weather", 0.25),
    "Life_Ambient_Rub_Arms": _h("weather", 0.3, mood="afraid"), "Life_Ambient_Glance_L": _h("look", 0.15),
    "Life_Ambient_Glance_R": _h("look", 0.15), "Life_Ambient_Rain_Hunch_Upper": _h("weather", 0.3, mood="sad"),
    "Life_AAA_Sit_Idle": _h("sit", 0.1), "Life_AAA_Sit_LegSwing": _h("sit", 0.3, mood="happy"),
    "Life_AAA_Sit_Ponder": _h("sit", 0.2),
}

# UAL base clips every body already has (the VAT sets lean on them; the FAR tier resolves to these)
BASE = {
    "Idle": ("idle", "stand", 0.1), "Walk": ("walk", "stand", 0.4),
    "Idle_Talking": ("talk", "stand", 0.4), "Sitting_Idle": ("sit", "sit", 0.1),
}

# AAA mocap packs (aaa/*.clips.json). Combat/traversal packs: keywords over the raw name, first rule wins.
# The LivingWorld pack is civilian mocap and goes through the life keywords (AAA_LIFE_WORDS extends them).
AAA_VERB_RULES = [
    ({"attack", "slash", "chop", "thrust", "lunge", "riposte", "cleave", "flurry", "stab", "slice", "combo", "strike",
      "execution", "impale", "poke", "bash", "rush", "charge", "bow", "release", "draw"}, "strike"),
    ({"stagger", "knockback", "knockdown", "impact"}, "stagger"),
    ({"parry", "deflect", "block", "guard"}, "parry"),
    ({"flinch", "hit", "react"}, "hit_react"),
    ({"cast", "chantless"}, "cast"),
    ({"ladder", "climb", "mantle", "shimmy"}, "climb"),
    ({"vault", "hurdle", "jump", "leap", "land", "slide"}, "jump"),
    ({"dodge", "roll", "backstep", "sidestep", "duck"}, "dodge"),
    ({"run", "sprint"}, "run"),
    ({"march"}, "march"),
    ({"walk", "creep"}, "walk"),
]
AAA_FALLBACK_VERB = "strike"
AAA_LIFE_WORDS = {
    "stumble": "walk", "limp": "walk", "jab": "strike", "shiver": "weather", "violin": "play_music",
    "grief": "mourn", "banter": "laugh", "greeting": "wave", "vendor": "wave", "trade": "trade", "cargo": "carry",
    "box": "lift", "chug": "drink", "dinner": "eat", "beer": "drink", "scan": "look", "shift": "idle",
    "legswing": "sit", "ponder": "sit", "stand": "sit", "ground": "dig", "leaves": "hoe", "floor": "sweep",
    "blacksmith": "forge", "woodcutter": "chop", "fishing": "fish", "direct": "wave",
}
# AAA clips whose name misleads the keywords
AAA_HAND = {
    "Guard_Break": "stagger", "Guard_Deflect_L": "parry", "Duel_Riposte": "strike",
    "Sloped_Roof_Tile_Slide": "jump", "Guard_Look_Around_Scan": "look", "Assassin_Smoke_Vanish_Drop": "dodge",
    "Assassin_Ledge_Pull_Down": "strike", "Villager_Hit_Chest": "hit_react", "Hit_Head_L": "hit_react",
}

# keyword inference for clips the HAND table does not list (new clips): token -> verb, in name order
VERB_WORDS = {
    "scythe": "harvest", "harvest": "harvest", "sickle": "harvest", "hoe": "hoe", "rake": "hoe", "sow": "plant",
    "plant": "plant", "dig": "dig", "milk": "milk", "hammer": "hammer", "nail": "hammer", "saw": "saw", "chop": "chop",
    "stir": "stir", "forge": "forge", "anvil": "forge", "pickaxe": "mine", "mine": "mine", "fish": "fish",
    "well": "draw_water", "scrub": "scrub", "laundry": "scrub", "sweep": "sweep", "broom": "sweep", "water": "water",
    "cook": "cook", "carry": "carry", "wheelbarrow": "push", "cart": "push", "lift": "lift", "pick": "pick",
    "pray": "pray", "mourn": "mourn", "kneel": "kneel", "sleep": "sleep", "sit": "sit", "drink": "drink", "eat": "eat",
    "toast": "toast", "cheer": "cheer", "lute": "play_music", "fiddle": "play_music", "flute": "play_music",
    "read": "read", "write": "write", "guard": "guard", "lean": "lean", "argue": "argue", "listen": "listen",
    "talk": "talk", "nod": "nod", "shrug": "shrug", "hug": "hug", "handshake": "handshake", "bow": "bow",
    "laugh": "laugh", "wave": "wave", "point": "point", "stretch": "stretch", "yawn": "stretch", "glance": "look",
    "look": "look", "march": "march", "run": "run", "walk": "walk", "skip": "walk", "idle": "idle",
}
NAME_PREFIX = re.compile(r"^(Life_(Mx5|Mx2|Mx|Mz|Mocap|Cmu|AAA|Social)_|Life_)")


def name_words(name):
    return [t for t in re.split(r"[^a-z0-9]+", NAME_PREFIX.sub("", name).lower()) if t]


def infer_verb(name, cat_verb):
    for w in name_words(name):
        if w in VERB_WORDS:
            return VERB_WORDS[w]
    return cat_verb


def infer_posture(words, cat_posture):
    ws = set(words)
    for keys, val in POSTURE_TOKENS:
        if keys & ws:
            return val
    return cat_posture


def infer_mood(words, cat_mood):
    ws = set(words)
    for keys, val in MOOD_TOKENS:
        if keys & ws:
            return val
    return cat_mood


def infer_phase(name, loop):
    low = name.lower()
    if low.endswith("_enter"):
        return "enter"
    if low.endswith("_exit"):
        return "exit"
    return "loop" if loop else "once"


def infer_intensity(verb):
    return 0.2 if verb in CALM_VERBS else 0.8 if verb in LOUD else 0.5


def life_entry(name, e, lib, vat_clips):
    cat = e.get("category", "")
    cverb, cposture, cmood = CATEGORY.get(cat) or CATEGORY.get(cat.split("/")[0]) or ("idle", "stand", "calm")
    tags = [t for t in e.get("tags", []) if t not in ("cmu", "mocap", "pantomime", "loop", "in_place")]
    words = name_words(name) + tags
    hand = HAND.get(name)
    if hand is None:
        parent = re.sub(r"_(Enter|Exit)$", "", name)
        hand = {k: v for k, v in HAND.get(parent, {}).items() if k != "phase"} if parent != name else {}
    verb = hand.get("verb") or infer_verb(name, cverb)
    props = [p["id"] if isinstance(p, dict) else p for p in e.get("props", [])]
    loop = bool(e.get("loop"))
    style_tags = {hand["style"]} if hand.get("style") else set()
    return {
        "verb": verb,
        "posture": hand.get("posture") or infer_posture(words, cposture),
        "prop": hand.get("prop") or (props[0] if props else "none"),
        "mood": hand.get("mood") or infer_mood(words, cmood),
        "layer": e.get("layer", "full"),
        "intensity": hand.get("intensity", infer_intensity(verb)),
        "vat": name in vat_clips,
        "phase": hand.get("phase") or infer_phase(name, loop),
        "weight": hand.get("weight", 1.0),
        "wired": True,
        "loop": loop,
        "seconds": round(float(e.get("seconds", 0.0)), 3),
        "speed_mps": round(float(e.get("speed_mps") or 0.0), 3),
        "category": cat,
        "library": lib,
        "tags": sorted(set(tags) | style_tags),
    }


def load_vat():
    clips = set()
    with open(VAT_BAKE, encoding="utf-8") as f:
        for lst in json.load(f).get("clip_sets", {}).values():
            for item in lst:
                clips.update(item.split("+"))
    return clips


def aaa_entries(life_names, vat_clips):
    out = {}
    with open(AAA_WIRING, encoding="utf-8") as f:
        wiring = json.load(f)["packs"]
    for pack, clips in sorted(wiring.items()):
        pk = os.path.basename(pack)
        info = {}
        cpath = os.path.join(KINGDOM, "assets", "incoming", "animations", "aaa", pk + ".clips.json")
        if os.path.exists(cpath):
            with open(cpath, encoding="utf-8") as f:
                info = {c["name"]: c for c in json.load(f)}
        for raw, w in sorted(clips.items()):
            name = w.get("as") or raw
            if name in life_names:
                continue  # the LIFE sidecar already tags it (life wins)
            words = set(name_words("Life_" + raw))
            verb = AAA_HAND.get(name) or AAA_HAND.get(raw)
            if not verb and pk.startswith("UAL_AAA_LivingWorld"):
                verb = next((VERB_WORDS.get(t) or AAA_LIFE_WORDS.get(t) for t in name_words("Life_" + raw)
                             if t in VERB_WORDS or t in AAA_LIFE_WORDS), None)
            if not verb:
                verb = next((v for keys, v in AAA_VERB_RULES if keys & words), AAA_FALLBACK_VERB)
            c = info.get(raw, {})
            loop = bool(w.get("loop", c.get("loop", False)))
            role = w.get("role", "")
            fight = verb in ("strike", "parry", "stagger", "hit_react", "dodge") and not pk.startswith("UAL_AAA_LivingWorld")
            out[name] = {
                "verb": verb, "posture": "stand", "prop": "none", "mood": "angry" if fight else "calm",
                "layer": w.get("layer", "full"), "intensity": 0.9 if fight else 0.6,
                "vat": name in vat_clips, "phase": "loop" if loop else "once", "weight": 1.0,
                "wired": w.get("status") == "add", "loop": loop,
                "seconds": round(float(c.get("seconds", 0.0)), 3), "speed_mps": 0.0,
                "category": "aaa/" + (role or "unwired"), "library": pk, "tags": sorted({"aaa", role} - {""}),
            }
    return out


def build():
    vat_clips = load_vat()
    clips = {}
    for path in sorted(glob.glob(ANIM_GLOB, recursive=True)):
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        lib = os.path.basename(path).replace(".glb.life.json", "")
        for name, e in sorted(data.get("clips", {}).items()):
            clips[name] = life_entry(name, e, lib, vat_clips)
    life_names = set(clips)
    clips.update(aaa_entries(life_names, vat_clips))
    for name, (verb, posture, inten) in BASE.items():
        clips[name] = {
            "verb": verb, "posture": posture, "prop": "none", "mood": "calm", "layer": "full",
            "intensity": inten, "vat": name in vat_clips, "phase": "loop", "weight": 1.0, "wired": True,
            "loop": True, "seconds": 0.0, "speed_mps": 0.0, "category": "base", "library": "UAL", "tags": ["base"],
        }
    props = sorted({c["prop"] for c in clips.values()} - {"none"})
    return {
        "_doc": "Generated by kingdom/tools/anim/life/tag_clips.py - do not edit by hand (overrides live in the HAND "
                "table there). Reader: scripts/living_world/clip_picker.gd. Design: docs/plans/NPC_MOTION_RULES.md 3.7 C1.",
        "version": 1,
        "axes": {
            "verb": VERBS, "posture": POSTURES, "prop": ["none"] + props, "mood": MOODS, "layer": LAYERS,
            "phase": PHASES,
        },
        "clips": dict(sorted(clips.items())),
    }


def validate(doc):
    errs = []
    ax = doc["axes"]
    for name, c in doc["clips"].items():
        for axis in ("verb", "posture", "prop", "mood", "layer", "phase"):
            if c.get(axis) not in ax[axis]:
                errs.append("%s: %s=%r not in vocabulary" % (name, axis, c.get(axis)))
        if not 0.0 <= c.get("intensity", -1) <= 1.0:
            errs.append("%s: intensity out of range" % name)
        if c.get("weight", 0) <= 0:
            errs.append("%s: weight must be > 0" % name)
        if not isinstance(c.get("vat"), bool):
            errs.append("%s: vat must be a bool" % name)
    gone = sorted(n for n in HAND if n not in doc["clips"])
    if gone:
        errs.append("HAND rows for clips that no longer exist: %s" % ", ".join(gone))
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="exit 1 when the file on disk is stale or invalid")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    doc = build()
    errs = validate(doc)
    if errs:
        print("\n".join(errs), file=sys.stderr)
        return 1
    text = json.dumps(doc, indent=1) + "\n"
    if args.check:
        have = open(args.out, encoding="utf-8").read() if os.path.exists(args.out) else ""
        if have != text:
            print("motion_tags.json is stale: run tag_clips.py", file=sys.stderr)
            return 1
        print("motion_tags.json up to date (%d clips)" % len(doc["clips"]))
        return 0
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    verbs = {c["verb"] for c in doc["clips"].values()}
    print("wrote %s: %d clips, %d verbs" % (os.path.relpath(args.out, KINGDOM), len(doc["clips"]), len(verbs)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
