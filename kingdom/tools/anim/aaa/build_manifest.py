"""Writes kingdom/data/anim/aaa_clips.json: every clip of the 10 staged AAA packs (assets/incoming/animations/aaa) with the
wiring decision made from frame-sheet review (docs/anim/aaa_wiring/review/*). Statuses: add (wired by AaaClips), cmp (a game
clip already does the job: wired only when "promote": true after a side-by-side), skip (not wired; "why" says why).
Run:  python kingdom/tools/anim/aaa/build_manifest.py
Promoted cmp clips are listed in promote.json next to this script (game names).
"""
import json, os, glob

HERE = os.path.dirname(os.path.abspath(__file__))
KING = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
AAA = os.path.join(KING, "assets", "incoming", "animations", "aaa")
OUT = os.path.join(KING, "data", "anim", "aaa_clips.json")

D = {}


def d(pack, clip, status, as_=None, role="", layer="full", why="", **extra):
    entry = dict(status=status, role=role, why=why, layer=layer, **extra)
    if as_:
        entry["as"] = as_
    D.setdefault(pack, {})[clip] = entry


# --- Locomotion
P = "Locomotion"
d(P, "Walk_Natural", "skip", why="plain walk with hands held in front (104_02); LivingWorld already has 11 Life_Walk_* styles")
d(P, "Run_Natural", "skip", why="flailing-arm run (143_01, 0.8 s); same range as Knight_Shield_Rush_Charge; no NPC charge consumer")
d(P, "Run_Stop_Plant", "skip", why="P5 Loco_RunStop_L/R are tuned and phase-matched; not compared")
d(P, "Run_Quick_Stop", "skip", why="127_05 family (crouched skid), uncertain")
d(P, "Run_Turn_Bank_L", "skip", why="real content is a banked run turn (sheet p01) but no NPC run-turn consumer exists; parked")
d(P, "March_Soldier_Loop", "cmp", "Soldier_March", "soldier", why="same 138_01 take as Life_Walk_March; CMP sheet p20", loop=True)
d(P, "Jump_Leap_Takeoff", "skip", why="P7 jump set is tuned; name shadowed")
d(P, "Jump_Land_Soft_Mocap", "skip", why="same name as the existing Jump_Land_Soft before the rename (existing wins); P7 jump set is tuned")
d(P, "Vault_Hurdle_Mocap", "add", "Vault_Run", "player", why="sheet p01: a real hurdle (crouch, leap, tuck); player auto-vault at >= run_min_speed")
d(P, "Ladder_Climb_Mocap", "cmp", "Ladder_Climb_Up_Mocap", "player", why="CMP vs authored Ladder_Climb_Up, sheet p15", loop=True)
d(P, "Sword_Slash_Combo_A", "skip", why="02_07 0.5-3.8 s: duplicate of Sword_Light_Attack_01+02 in one clip")
d(P, "Sword_Slash_Combo_B", "skip", why="02_07 4.2-7.5 s: duplicate of Sword_Light_Attack_03 + Heavy_Charge_Chop")
d(P, "Hit_React_Chest_Mocap", "add", "Villager_Hit_Chest", "villager", why="sheet p13: stumbling step back, hands up; villager.gd take_damage one-shot")
d(P, "Combat_Duck_Dodge", "skip", why="no soldier evade logic to consume it; parked")
d(P, "Combat_Shield_Block", "skip", why="3.5 s one-shot gesture (144_07); Idle_Shield exists")
# --- Combat_Adv
P = "Combat_Adv"
d(P, "Parry_High_Deflect", "add", "Duel_Parry_High", "soldier", why="sheet p07: raised-forearm deflect; soldier block reaction", trim=[0.9, 2.1])
d(P, "Parry_Sword_Riposte", "add", "Duel_Riposte", "soldier", why="sheet p07: parry then counter thrust (final thrust)", trim=[2.1, 3.4])
d(P, "Combat_Fencing_Lunge", "add", "Duel_Lunge", "soldier", why="sheet p07: forward lunge with front arm extended; bandit / guard thrust move", trim=[0.9, 2.3])
d(P, "Combat_Shield_Bash_Stagger", "skip", why="sheet p08: arm sweep to the side, no forward bash")
d(P, "Combat_Dodge_Sidestep_L", "skip", why="sheet p08: 0.05 m travel, hand gestures, not a sidestep (144_11)")
d(P, "Combat_Dodge_Sidestep_R", "skip", why="same as Sidestep_L")
# --- Combat_Chains
P = "Combat_Chains"
d(P, "Sword_Light_Attack_01", "add", "Bandit_Light_1", "soldier", why="sheet p09: two-hand overhead chop")
d(P, "Sword_Light_Attack_02", "add", "Bandit_Light_2", "soldier", why="sheet p09: forward-leaning chop")
d(P, "Sword_Light_Attack_03", "add", "Bandit_Light_3", "soldier", why="sheet p09: cross-body slash")
d(P, "Sword_Light_Attack_04", "skip", why="sheet p10: dance-like lunge with arms out (087_01), no strike")
d(P, "Sword_Heavy_Charge_Chop", "add", "Bandit_Heavy_Chop", "soldier", why="sheet p10: wind-up with hands raised, overhead chop; drops the Knight_Decapitation duplicate")
d(P, "Sword_Sprint_Dash_Attack", "skip", why="sheet p04: crouched skid with arms up, no strike (127_05)")
d(P, "Sword_Roll_Counter_Poke", "skip", why="sheet p04: ground crawl (140_01), no poke")
d(P, "Sword_Plunge_Aerial_Attack", "skip", why="duplicate of Assassin_Aerial_Drop_Impale (140_01 1.8-3.0); prone content")
d(P, "Parry_Left_Deflect", "cmp", "Guard_Deflect_L", "soldier", why="144_07 gesture take; sheet p14")
d(P, "Parry_Right_Deflect", "skip", why="identical source range to Parry_Left_Deflect (144_07 0.24-1.4)")
d(P, "Guard_Break_Stumble", "add", "Guard_Break", "soldier", why="sheet p10: stumbling back with hands up; replaces Block_Hit on a guard break")
d(P, "Blade_Clash_Lock", "skip", why="sheet p13: arm gesture, no block impact (144_07)")
d(P, "Combat_Roll_Forward", "skip", why="roll is tuned; 140_01 content is a prone get-up")
d(P, "Combat_Backstep_Hop", "skip", why="sheet p04: a running stride (127_15), not a backstep")
# --- Combat_Classes
P = "Combat_Classes"
d(P, "Knight_Greatshield_Guard_Stance", "skip", why="duplicate of Parry_Left_Deflect range (144_07), marked loop but one-shot")
d(P, "Knight_Shield_Rush_Charge", "skip", why="duplicate of Run_Natural (143_01 0.0-0.8)")
d(P, "Knight_Pommel_Strike_Stun", "skip", why="duplicate of Sword_Light_Attack_01 (02_07 0.5-1.7); class-flavoured name")
d(P, "Knight_Decapitation_Execution", "skip", why="duplicate of Sword_Heavy_Charge_Chop; IP-flavoured name")
d(P, "Assassin_Shadow_Crouch_Creep", "skip", why="sheet p06: upright walk (104_02), not a crouch; Crouch_Fwd is better")
d(P, "Assassin_Throat_Slit_Sneak", "skip", why="02_07 1.7-3.2: overlaps Sword_Light_Attack_02")
d(P, "Assassin_Ledge_Pull_Down", "skip", why="140_01 prone get-up content")
d(P, "Assassin_Aerial_Drop_Impale", "skip", why="duplicate of Sword_Plunge_Aerial_Attack")
d(P, "Assassin_Smoke_Vanish_Drop", "skip", why="duplicate of Cast_Chantless_Blink_Step (127_05 0.4-1.6)")
# --- Combat_Knockbacks
P = "Combat_Knockbacks"
d(P, "Knockback_Heavy_Slide_Brake", "skip", why="127_05 skid family, duplicate content")
d(P, "Knockback_Airborne_Blowback", "skip", why="ragdoll owns launches; floor_fix -0.12")
d(P, "Knockback_3Step_Stumble_Recoil", "cmp", "Stagger_Back_Mocap", "soldier", why="CMP vs authored Stagger_Back, sheet p14")
d(P, "Guard_Impact_Heavy_Stagger", "skip", why="duplicate of Blade_Clash_Lock (144_07 1.8-3.4)")
# --- Combat_Reactions
P = "Combat_Reactions"
d(P, "Hit_React_Head_Flinch_R", "add", "Hit_Head_R", "soldier", layer="upper", why="sheet p13: head-snap rock with guard hands up; light-hit alternative")
d(P, "Hit_React_Head_Flinch_L", "add", "Hit_Head_L", "soldier", layer="upper", why="same 14_01 6.0-7.4 range as _R (not a true mirror); kept so L/R picks exist")
d(P, "Hit_React_Gut_Wind_Knockout", "skip", why="duplicate of Guard_Break_Stumble (14_03 3.2-4.5)")
d(P, "Hit_React_Leg_Sweep_Trip", "skip", why="foot 6.7 cm below floor (min_foot_m -0.067)")
d(P, "Knockdown_Hard_Landing", "skip", why="sheet p04: standing idle then a lean, not a knockdown (090_17)")
d(P, "Knockdown_Ground_Lie_Idle", "skip", why="min foot 0.49 m (airborne window), not a lie idle")
d(P, "Knockdown_Roll_Getup", "skip", why="sheet p05: prone-to-crouch get-up only valid face-down; ragdoll.gd owns the get-up and has no orientation hook")
d(P, "Wall_Impact_Splat_Bounce", "skip", why="sheet p04: jump with a flip (090_16), not a wall hit; floor_fix -0.13. Wall hit uses Hit_Heavy_Front")
# --- Combat_Weapons
P = "Combat_Weapons"
d(P, "2H_Greatsword_Overhead_Chop", "add", "GS_Overhead", "soldier", why="sheet p11: KayKit two-hand chop; scale matches on the villager rig")
d(P, "2H_Greatsword_Slash_Horizontal", "add", "GS_Slash", "soldier", why="sheet p11")
d(P, "2H_Greatsword_Spin_Cleave", "add", "GS_Spin", "soldier", why="sheet p11")
d(P, "2H_Greatsword_Thrust_Lunge", "add", "GS_Thrust", "soldier", why="KayKit two-hand stab")
d(P, "2H_Greatsword_Guard_Block", "add", "GS_Guard", "soldier", why="KayKit two-hand block")
d(P, "DualDaggers_Flurry_Chop", "skip", why="parked: sheet p12 fine, but no dual-dagger enemy exists")
d(P, "DualDaggers_Cross_Slice", "skip", why="parked (see Flurry_Chop)")
d(P, "DualDaggers_Thrust_Stab", "skip", why="parked (see Flurry_Chop)")
d(P, "Bow_Draw_Mocap", "skip", why="authored bow set (the pack name Bow_Draw collided with the existing clip, renamed _Mocap)")
d(P, "Bow_Aim_Idle_Loop", "skip", why="authored bow set")
d(P, "Bow_Release_Recoil", "skip", why="authored bow set")
# --- LivingWorld
P = "LivingWorld"
d(P, "Tavern_Sit_Idle", "add", "Life_AAA_Sit_Idle", "villager", why="sheet p16: seated idle", loop=True, life="rest/sit")
d(P, "Tavern_Sit_LegSwing", "add", "Life_AAA_Sit_LegSwing", "villager", why="sheet p16: seated, legs swinging, higher seat", loop=True, life="rest/sit")
d(P, "Tavern_Sit_Fidget_Ponder", "add", "Life_AAA_Sit_Ponder", "villager", why="sheet p16: seated, leaning forward on a knee", loop=True, life="rest/sit")
d(P, "Tavern_Stand_To_Sit", "skip", why="sheet p17: foot-on-step pose, no seat contact")
d(P, "Tavern_Sit_To_Stand", "skip", why="sheet p17: bends forward standing, no rise from a seat")
d(P, "Tavern_Chug_Beer", "skip", why="same BVH as Life_Mocap_Chug (79_33)")
d(P, "Tavern_Eat_Dinner", "skip", why="same BVH as Life_Mocap_Eat_Table (79_12)")
d(P, "Tavern_Drunk_Stumble", "cmp", "Life_AAA_Drunk_Stumble", "villager", why="CMP vs Life_Walk_Drunk, sheet p21", loop=True, life="walk/style")
d(P, "Social_Laugh_Banter", "skip", why="sheet p17: boxing-like gestures; the life lib already found 13_14 is not a laugh")
d(P, "Social_Handshake", "skip", why="single-person 79_06; Life_Mocap_Handshake_A/B pair exists")
d(P, "Village_Bard_Violin", "skip", why="same BVH as Life_Mocap_Fiddle (79_17)")
d(P, "Peasant_Grief_Mourn", "skip", why="same BVH as Life_Mocap_Comfort_A (22_03)")
d(P, "Blacksmith_Hammer_Anvil", "skip", why="same BVH as Life_Mocap_Hammer_Nail (62_07)")
d(P, "Woodcutter_Chop_Axe", "skip", why="same BVH as Life_Mocap_Chop_Wood (79_01)")
d(P, "Peasant_Sweep_Floor", "skip", why="same BVH as Life_Mocap_Sweep (79_55)")
d(P, "Peasant_Dig_Ground", "skip", why="same BVH as Life_Mocap_Dig (79_04)")
d(P, "Peasant_Rake_Leaves", "skip", why="same BVH as Life_Mocap_Rake (79_87)")
d(P, "Worker_Carry_Cargo", "skip", why="sheet p18: walking with open arms, no load held (70_01); Life_Mocap_Carry_Heavy exists")
d(P, "Worker_Move_Heavy_Box", "skip", why="same BVH as Life_Mocap_Move_Box (79_25)")
d(P, "River_Fishing_Cast_Reel", "skip", why="same BVH as Life_Mocap_Fish (79_34)")
d(P, "NPC_Direct_Point_Wave", "skip", why="sheet p18: dance-like shrugs with arms up (13_27); the life lib replaced it with Life_Mocap_Direct_Wave")
d(P, "Vendor_Wave_Greeting", "skip", why="same BVH as Life_Mocap_Direct_Wave (14_24)")
d(P, "Market_Trade_Inspect", "skip", why="same BVH as Life_Mocap_Buy (79_16)")
d(P, "Guard_Look_Around_Scan", "skip", why="same BVH as Life_Mocap_Look_Around (139_01)")
d(P, "Standing_Shift_Weight_Idle", "skip", why="same BVH as Life_Mocap_Shift_Weight (139_02)")
d(P, "Cold_Shiver_Campfire", "skip", why="same BVH as Life_Mocap_Cold (79_68)")
d(P, "Wounded_Limp_Walk", "cmp", "Life_AAA_Limp_Walk", "villager", why="CMP vs Life_Walk_Limp, sheet p20", loop=True, life="walk/style")
d(P, "Brawler_Tavern_Jab", "skip", why="sheet p18: bouncing guard-up gestures, no jab (14_01 1.0-4.5)")
# --- Magic_Chantless
P = "Magic_Chantless"
for c, w in [("Cast_Chantless_Palm_Blast", "02_07 sword take, relabelled"), ("Cast_Chantless_Telekinesis_Lift", "087_01 dance take, relabelled"),
             ("Cast_Chantless_Barrier_Conjure", "144_07 parry gesture, relabelled"), ("Cast_Chantless_Ground_Eruption", "140_01 prone get-up, relabelled"),
             ("Cast_Chantless_Siphon_Drain", "02_07 sword take, relabelled"), ("Cast_Chantless_Blink_Step", "127_05 skid, relabelled")]:
    d(P, c, "skip", why="not casting: " + w)
# --- Traversal_Rooftops
P = "Traversal_Rooftops"
d(P, "Wall_Climb_Mantle", "skip", why="the vault clip again (127_25 0.3-1.8)")
d(P, "Roof_Gap_Leap_Roll", "skip", why="sheet p05: prone crawl-up (140_01), not a landing roll")
d(P, "Roof_Ridge_Balance_Walk", "skip", why="plain bent-arm walk (104_02); arms-out comes from the hand IK")
d(P, "Sloped_Roof_Tile_Slide", "skip", why="sheet p05: a hopping run (127_05), not a slide; UAL2 Slide_Loop is used")
d(P, "Ladder_Climb_Down_Loop", "skip", why="same 13_33 take as the up clip (climbs up), not a descent")
d(P, "Ledge_Shimmy_L_Mocap", "skip", why="a banked running turn (127_15), 2.45 m travel in 1.1 s, not a shimmy (renamed _Mocap: it collided with the authored Ledge_Shimmy_L)")
d(P, "Ledge_Shimmy_R_Mocap", "skip", why="same range as Ledge_Shimmy_L_Mocap")

PROMOTE = set()
pj = os.path.join(HERE, "promote.json")
if os.path.exists(pj):
    PROMOTE = set(json.load(open(pj)))

packs = {}
total = 0
for f in sorted(glob.glob(os.path.join(AAA, "UAL_AAA_*.glb"))):
    short = os.path.basename(f)[len("UAL_AAA_"):-4]
    res = "res://assets/incoming/animations/aaa/" + os.path.basename(f)
    clips = json.load(open(f + ".clips.json"))
    entry = {}
    for c in clips:
        n = c["name"]
        if n not in D.get(short, {}):
            raise SystemExit("no decision for %s/%s" % (short, n))
        e = dict(D[short][n])
        e["loop"] = bool(e.pop("loop", False)) if e["status"] != "skip" else False
        e["mirror_of"] = None
        if e["status"] == "cmp" and e.get("as") in PROMOTE:
            e["promote"] = True
        e["source"] = "%s %s" % (c["source"], c.get("range_s") or "")
        entry[n] = e
        total += 1
    extra = set(D.get(short, {})) - {c["name"] for c in clips}
    if extra:
        raise SystemExit("decisions for unknown clips %s/%s" % (short, extra))
    packs[res] = entry
doc = {"_doc": "AAA mocap wiring manifest (kingdom/tools/anim/aaa/build_manifest.py). status add = wired by AaaClips.merge_into under `as`; "
               "cmp = a game clip already exists, wired only with promote=true; skip = not wired (why). Frame-sheet review: docs/anim/aaa_wiring/review/.",
       "packs": packs}
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(doc, fh, indent=1)
    fh.write("\n")
cnt = {}
for p in packs.values():
    for e in p.values():
        cnt[e["status"]] = cnt.get(e["status"], 0) + 1
print(total, "clips", cnt)
