extends RefCounted
## What the animation QA tests: every character / creature / animal type the game
## loads, the clips the game plays on it, and the movement speeds the game code
## drives those clips at. Keep this in sync with the game code it mirrors:
##   humanoids  -> Assets.MH_LOOKS / Assets.mh_character()   (scripts/world/assets.gd)
##   player     -> Player.WALK/RUN + CharacterAnimator blend points (scripts/actors/player.gd, character_animator.gd)
##   soldiers   -> Soldier.WALK/RUN (scripts/army/soldier.gd)
##   villagers  -> Villager._process: 1.6 m/s, x3 when > 4 m behind (scripts/population/villager.gd)
##   goblins    -> CampMonster.SPECIES (scripts/actors/monster.gd)
##   wolf       -> Wolf._physics_process "want" speeds (scripts/actors/wolf.gd)
##   animals    -> Critter.KINDS (scripts/actors/critter.gd)
##   Meshy creatures (ai3d/meshy/creatures) are ready for integration but not wired yet.

const G6 := "res://assets/incoming/characters/g6-ual/"
const CDMIR := "res://assets/incoming/characters/cdmir-ual/"
const ARMORED := "res://assets/incoming/ai3d/meshy/armored/"
const QCHAR := "res://assets/incoming/quaternius/ultimate-animated-character/glTF/"
const QWOLF := "res://assets/incoming/quaternius/ultimate-animated-animals/glTF/Wolf.gltf"
const CREATURES := "res://assets/incoming/ai3d/meshy/creatures/"
const ANIMALS := "res://assets/incoming/animals/"

## clip -> kind. Kinds: loco (looping locomotion), loop (looping, stationary),
## once (one-shot), death, sit, jump. "game" = the game plays it today (else it is
## a candidate clip the game could use for sprint / talk / work).
const UAL_CLIPS := {
	"Idle": {"kind": "loop", "game": true},
	"Walking_A": {"kind": "loco", "game": true},
	"Running_A": {"kind": "loco", "game": true},
	"Sprint": {"kind": "loco", "game": false},
	"Walk_Carry": {"kind": "loco", "game": false},
	"Walk_Formal": {"kind": "loco", "game": false},
	"Crouch_Fwd": {"kind": "loco", "game": false},
	"Blocking": {"kind": "loop", "game": true},
	"2H_Melee_Idle": {"kind": "loop", "game": true},
	"1H_Melee_Attack_Chop": {"kind": "once", "game": true, "upper": true},
	"1H_Melee_Attack_Slice_Diagonal": {"kind": "once", "game": true, "upper": true},
	"1H_Melee_Attack_Slice_Horizontal": {"kind": "once", "game": true, "upper": true},
	"1H_Melee_Attack_Stab": {"kind": "once", "game": true, "upper": true},
	"Block_Hit": {"kind": "once", "game": true, "upper": true},
	"Dodge_Forward": {"kind": "once", "game": true},
	"Hit_A": {"kind": "once", "game": true, "upper": true},
	"Hit_B": {"kind": "once", "game": true},
	"Death_A": {"kind": "death", "game": true},
	"Death_B": {"kind": "death", "game": true},
	"Sitting_Idle": {"kind": "sit", "game": true},
	"Sitting_Talking": {"kind": "sit", "game": false},
	"Cheer": {"kind": "once", "game": true},
	"Idle_Talking": {"kind": "loop", "game": false},
	"Interact": {"kind": "once", "game": true},
	"Farm_Harvest": {"kind": "once", "game": false},
	"Farm_Watering": {"kind": "once", "game": false},
	"TreeChopping": {"kind": "once", "game": false},
	"Fixing_Kneeling": {"kind": "once", "game": false},
	"PickUp_Table": {"kind": "once", "game": false},
	"Jump": {"kind": "jump", "game": false},
}
## Strips rendered for every humanoid; the extra list only for the representatives.
const UAL_STRIPS := ["Idle", "Walking_A", "Running_A", "1H_Melee_Attack_Chop", "Hit_A", "Death_A"]
const UAL_STRIPS_EXTRA := ["Sprint", "Blocking", "1H_Melee_Attack_Stab", "Block_Hit", "Dodge_Forward", "Hit_B", "Death_B",
	"Sitting_Idle", "Idle_Talking", "Farm_Harvest", "TreeChopping", "Fixing_Kneeling", "Walk_Carry", "Cheer"]
const UAL_REPS := ["player_young", "villager_woman_a", "cdmir_monk", "g6_m_blacksmith_apron", "guard", "orc_warchief"]


static func subjects() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# --- UAL humanoids, loaded exactly like the game: Assets.mh_character(file, height)
	var ual := [
		["player_young", "player_young", 1.8, "villagers"],
		["villager_man_a", "villager_man_a", 1.7, "villagers"], ["villager_man_b", "villager_man_b", 1.7, "villagers"],
		["villager_woman_a", "villager_woman_a", 1.7, "villagers"], ["villager_woman_b", "villager_woman_b", 1.7, "villagers"],
		["elder_man", "elder_man", 1.7, "villagers"], ["elder_woman", "elder_woman", 1.7, "villagers"],
		["father", "father", 1.8, "villagers"], ["mother", "mother", 1.64, "villagers"],
		["child_boy", "child_boy", 1.25, "villagers"], ["child_girl", "child_girl", 1.2, "villagers"],
		["g6_m_villager_tunic", G6 + "g6_m_villager_tunic", 1.7, "villagers"], ["g6_f_villager_tunic", G6 + "g6_f_villager_tunic", 1.7, "villagers"],
		["g6_m_worker_apron", G6 + "g6_m_worker_apron", 1.7, "villagers"], ["g6_f_worker_apron", G6 + "g6_f_worker_apron", 1.7, "villagers"],
		["g6_m_hunter_leather", G6 + "g6_m_hunter_leather", 1.7, "villagers"], ["g6_f_hunter_leather", G6 + "g6_f_hunter_leather", 1.7, "villagers"],
		["g6_m_blacksmith_apron", G6 + "g6_m_blacksmith_apron", 1.74, "villagers"], ["g6_f_blacksmith_apron", G6 + "g6_f_blacksmith_apron", 1.7, "villagers"],
		["cdmir_monk", CDMIR + "cdmir_monk", 1.74, "villagers"], ["cdmir_old_lady", CDMIR + "cdmir_old_lady", 1.74, "villagers"],
		["guard", ARMORED + "guard", 1.75, "armored"], ["knight", ARMORED + "knight", 1.75, "armored"],
		["mercenary", ARMORED + "mercenary", 1.75, "armored"], ["bandit", ARMORED + "bandit", 1.75, "armored"],
		["noble", ARMORED + "noble", 1.75, "armored"], ["orc_warchief", ARMORED + "orc_warchief", 2.2, "armored"],
	]
	for u in ual:
		var strips: Array = UAL_STRIPS.duplicate()
		if UAL_REPS.has(u[0]):
			strips.append_array(UAL_STRIPS_EXTRA)
		out.append({"id": u[0], "kind": "ual", "file": u[1], "height": u[2], "group": u[3],
			"clips": UAL_CLIPS, "strips": strips, "biped": true, "face": 1.0,
			"feet": [["foot_l", "ball_l"], ["foot_r", "ball_r"]]})
	# --- Quaternius goblins / orcs (CampMonster): scaled to height by visual AABB.
	var gob_clips := {"Idle": {"kind": "loop", "game": true}, "Walk": {"kind": "loco", "game": true},
		"Run": {"kind": "loco", "game": true}, "SwordSlash": {"kind": "once", "game": true},
		"Punch": {"kind": "once", "game": true}, "RecieveHit": {"kind": "once", "game": true},
		"SitDown": {"kind": "sit", "game": true}, "StandUp": {"kind": "sit", "game": true},
		"Death": {"kind": "death", "game": true}}
	var gob_strips := ["Idle", "Walk", "Run", "SwordSlash", "Punch", "RecieveHit", "SitDown", "Death"]
	out.append({"id": "q_goblin_male", "kind": "qmonster", "file": QCHAR + "Goblin_Male.gltf", "height": 1.1,
		"group": "creatures", "clips": gob_clips, "strips": gob_strips, "biped": true, "face": 1.0,
		"loops": ["Idle", "Walk", "Run"], "feet": [["Foot.L"], ["Foot.R"]]})
	out.append({"id": "q_goblin_female", "kind": "qmonster", "file": QCHAR + "Goblin_Female.gltf", "height": 1.1,
		"group": "creatures", "clips": gob_clips, "strips": ["Idle", "Walk", "Run"], "biped": true, "face": 1.0,
		"loops": ["Idle", "Walk", "Run"], "feet": [["Foot.L"], ["Foot.R"]]})
	out.append({"id": "q_orc", "kind": "qmonster", "file": QCHAR + "Goblin_Male.gltf", "height": 2.05,
		"group": "creatures", "clips": gob_clips, "strips": ["Walk", "Run", "SwordSlash"], "biped": true, "face": 1.0,
		"tint": Color(0.62, 0.72, 0.5), "loops": ["Idle", "Walk", "Run"], "feet": [["Foot.L"], ["Foot.R"]]})
	# --- Quaternius wolf (Wolf): 0.85 m at the shoulder.
	var wolf_clips := {"Idle": {"kind": "loop", "game": true}, "Walk": {"kind": "loco", "game": true},
		"Gallop": {"kind": "loco", "game": true}, "Attack": {"kind": "once", "game": true},
		"Idle_HitReact1": {"kind": "once", "game": true}, "Death": {"kind": "death", "game": true}}
	out.append({"id": "q_wolf", "kind": "qwolf", "file": QWOLF, "height": 0.85, "group": "creatures",
		"clips": wolf_clips, "strips": wolf_clips.keys(), "biped": false, "face": 1.0,
		"loops": ["Idle", "Walk", "Gallop", "Idle_2"], "feet": []})
	# --- Meshy creatures (ready, not yet wired): native metres, facing -Z.
	for c in ["goblin", "orc", "troll", "wolf", "boar", "bear", "spider", "wyvern"]:
		var clips := {"idle": {"kind": "loop", "game": false}, "walk": {"kind": "loco", "game": false},
			"run": {"kind": "loco", "game": false}, "attack": {"kind": "once", "game": false},
			"hit": {"kind": "once", "game": false}, "death": {"kind": "death", "game": false}}
		if c == "orc":
			clips["attack_charged"] = {"kind": "once", "game": false}
		if c == "troll":
			clips["slam"] = {"kind": "once", "game": false}
		if c == "spider":
			clips.erase("run")
		if c == "wyvern":
			clips.erase("run")
			clips["flap"] = {"kind": "jump", "game": false}
		var feet: Array = []
		if c in ["goblin", "orc", "troll"]:
			feet = [["LeftFoot", "LeftToeBase"], ["RightFoot", "RightToeBase"]]
		elif c == "wyvern":
			feet = [["foot_L"], ["foot_R"]]
		elif c == "spider":
			for side in ["L", "R"]:
				for i in range(1, 5):
					feet.append(["tarsus_%s%d" % [side, i]])
		out.append({"id": "meshy_" + c, "kind": "meshy", "file": CREATURES + c + ".glb", "height": 0.0,
			"group": "creatures", "clips": clips, "strips": clips.keys(), "biped": c in ["goblin", "orc", "troll"],
			"face": 0.0, "loops": ["idle", "walk", "run"], "feet": feet})
	# --- Animals (Critter.KINDS): native size, Idle/Walk/Run/Eat forced to loop.
	for kind: String in CRITTERS:
		var cfg: Array = CRITTERS[kind]
		var clips := {"Idle": {"kind": "loop", "game": true}, "Walk": {"kind": "loco", "game": true},
			"Run": {"kind": "loco", "game": true}, "Eat": {"kind": "loop", "game": true}}
		out.append({"id": "animal_" + kind, "kind": "critter", "file": ANIMALS + String(cfg[0]), "height": 0.0,
			"group": "animals", "clips": clips, "strips": ["Idle", "Walk", "Run", "Eat"], "biped": false, "face": 1.0,
			"loops": ["Idle", "Walk", "Run", "Eat", "Walk_Slow"], "feet": []})
	return out


## Copy of Critter.KINDS (file, walk speed, run speed): scripts/actors/critter.gd:10.
const CRITTERS := {
	"chicken": ["procedural/chicken.glb", 0.6, 2.2], "rooster": ["procedural/rooster.glb", 0.6, 2.2],
	"duck": ["procedural/duck.glb", 0.5, 1.8], "goose": ["procedural/goose.glb", 0.55, 1.8],
	"pigeon": ["procedural/pigeon.glb", 0.4, 1.6], "crow": ["procedural/crow.glb", 0.4, 1.6],
	"rabbit": ["procedural/rabbit.glb", 0.7, 5.0], "dog": ["quaternius/dog.glb", 1.1, 4.0],
	"sheepdog": ["quaternius/sheepdog.glb", 1.1, 4.0], "cat": ["quaternius/cat.glb", 0.5, 2.5],
	"cat_ginger": ["quaternius/cat_ginger.glb", 0.5, 2.5], "cow": ["quaternius/cow.glb", 0.7, 2.0],
	"ox": ["quaternius/ox.glb", 0.7, 2.0], "sheep": ["quaternius/sheep.glb", 0.6, 2.4],
	"pig": ["quaternius/pig.glb", 0.6, 2.2], "goat": ["quaternius/goat.glb", 0.7, 2.8],
	"horse": ["quaternius/horse_riding.glb", 0.9, 5.0], "horse_grey": ["quaternius/horse_grey.glb", 0.9, 5.0],
	"horse_draft": ["quaternius/horse_draft.glb", 0.8, 4.0], "donkey": ["quaternius/donkey.glb", 0.7, 3.0],
	"deer": ["quaternius/deer.glb", 0.9, 7.0], "stag": ["quaternius/stag.glb", 0.9, 7.0],
	"fox": ["quaternius/fox.glb", 0.8, 5.0],
}


## Movement-speed checks: who plays which locomotion clip at which ground speed.
## "blend": the CharacterAnimator BlendSpace1D points [idle 0, walk at run*0.5, run at run]
## (clips play at their own speed; the blend weight follows the character speed).
static func speed_cases() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var player_blend := [["Idle", 0.0], ["Walking_A", 3.5], ["Running_A", 7.0]]      # CharacterAnimator.new(body, RUN=7.0)
	out.append({"agent": "Player walk (Player.WALK)", "subject": "player_young", "speed": 4.2, "blend": player_blend,
		"src": "scripts/actors/player.gd:24 WALK := 4.2; character_animator.gd:39-41 blend points"})
	out.append({"agent": "Player run (Player.RUN)", "subject": "player_young", "speed": 7.0, "blend": player_blend,
		"src": "scripts/actors/player.gd:25 RUN := 7.0"})
	out.append({"agent": "Player blocking (WALK*0.5)", "subject": "player_young", "speed": 2.1, "blend": player_blend,
		"src": "scripts/actors/player.gd:186"})
	var soldier_blend := [["Idle", 0.0], ["Walking_A", 2.9], ["Running_A", 5.8]]
	out.append({"agent": "Soldier walk (Soldier.WALK)", "subject": "guard", "speed": 3.6, "blend": soldier_blend,
		"src": "scripts/army/soldier.gd:10 WALK := 3.6"})
	out.append({"agent": "Soldier run (Soldier.RUN)", "subject": "guard", "speed": 5.8, "blend": soldier_blend,
		"src": "scripts/army/soldier.gd:11 RUN := 5.8"})
	out.append({"agent": "Villager walk", "subject": "villager_man_a", "speed": 1.6, "clip": "Walking_A",
		"src": "scripts/population/villager.gd:48 (1.6 m/s, Walking_A)"})
	out.append({"agent": "Villager catch-up (x3)", "subject": "villager_man_a", "speed": 4.8, "clip": "Walking_A",
		"src": "scripts/population/villager.gd:48 (x3.0 when > 4 m away, still Walking_A)"})
	out.append({"agent": "Goblin walk", "subject": "q_goblin_male", "speed": 1.4, "clip": "Walk", "src": "scripts/actors/monster.gd:15 walk 1.4"})
	out.append({"agent": "Goblin follow (walk*1.6)", "subject": "q_goblin_male", "speed": 2.24, "clip": "Walk", "src": "scripts/actors/monster.gd:149"})
	out.append({"agent": "Goblin run", "subject": "q_goblin_male", "speed": 5.2, "clip": "Run", "src": "scripts/actors/monster.gd:15 run 5.2"})
	out.append({"agent": "Orc walk", "subject": "q_orc", "speed": 1.3, "clip": "Walk", "src": "scripts/actors/monster.gd:17 walk 1.3"})
	out.append({"agent": "Orc run", "subject": "q_orc", "speed": 4.6, "clip": "Run", "src": "scripts/actors/monster.gd:17 run 4.6"})
	out.append({"agent": "Wolf roam", "subject": "q_wolf", "speed": 1.6, "clip": "Walk", "src": "scripts/actors/wolf.gd:58"})
	out.append({"agent": "Wolf stalk (Walk clip)", "subject": "q_wolf", "speed": 3.5, "clip": "Walk", "src": "scripts/actors/wolf.gd:62 + :86 (Walk below 4.5 m/s)"})
	out.append({"agent": "Wolf attack run", "subject": "q_wolf", "speed": 7.5, "clip": "Gallop", "src": "scripts/actors/wolf.gd:67"})
	out.append({"agent": "Wolf flee", "subject": "q_wolf", "speed": 8.0, "clip": "Gallop", "src": "scripts/actors/wolf.gd:71"})
	for kind: String in CRITTERS:
		var cfg: Array = CRITTERS[kind]
		out.append({"agent": kind.capitalize() + " walk", "subject": "animal_" + kind, "speed": float(cfg[1]), "clip": "Walk",
			"src": "scripts/actors/critter.gd KINDS[\"%s\"][1]" % kind})
		out.append({"agent": kind.capitalize() + " run", "subject": "animal_" + kind, "speed": float(cfg[2]), "clip": "Run",
			"src": "scripts/actors/critter.gd KINDS[\"%s\"][2]" % kind})
	return out
