class_name RaceEvolutionSystem
extends Node
## High-level simulation system for Monster Naming & Racial Evolution
## Inspired by donghua xianxia cultivation and Tensura (Slime) monster naming metaphysics.
## Naming a monster or unawakened being forms a soul corridor, consumes magicules from the namer,
## and triggers biological metamorphosis, unlocking humanoid refinement, elevated stats, and unique racial arts.

signal naming_completed(namer: Node, target: Node, assigned_name: String, magicules_spent: int)
signal naming_backlash(namer: Node, exhaustion_turns: int, mana_drain_percent: float)
signal evolution_started(target: Node, from_race: String, to_race: String)
signal evolution_completed(target: Node, final_race: String, unlocked_traits: Array)

## Minimum player/caster level required before having sufficient soul density to name monsters
const MIN_NAMER_LEVEL := 10

## Base magicule costs per evolution tier
const TIER_MAGICULE_COSTS := {
	1: 350,    # Feral to Named Minion (e.g. Goblin -> Hobgoblin, Skeleton -> Wight)
	2: 1200,   # Named Minion to Champion (e.g. Lizardfolk -> Dragonnewt, Beastkin -> Greater)
	3: 4500,   # Champion to Warlord / High Noble (e.g. High Orc -> Orc Warlord)
	4: 15000,  # Sovereign / Disaster Class (e.g. Dragon Sovereign, Nether Lich)
	5: 45000   # Calamity / Ascendant True Deity
}

## Scale adjustments per race (Height multiplier applied to Character model root)
const RACE_HEIGHT_SCALES := {
	"halfling": 0.65,
	"gnome": 0.70,
	"goblin": 0.68,
	"hobgoblin": 1.05,
	"dwarf": 0.78,
	"human": 1.00,
	"half_breed": 1.00,
	"elf": 1.08,
	"dark_elf": 1.06,
	"tiefling": 1.02,
	"aasimar": 1.05,
	"beastkin": 1.02,
	"serpentkin": 1.05,
	"avian": 1.04,
	"lizardfolk": 0.95,
	"draken": 1.15,
	"ork": 1.22,
	"high_ork": 1.30,
	"ork_warlord": 1.45,
	"undead": 1.00,
	"giant": 3.20,
	"frost_titan": 4.50
}

## Stat multipliers gained upon evolving
const EVOLUTION_STAT_BUFFS := {
	"hobgoblin": {"max_hp": 2.2, "atk": 1.8, "speed": 1.15, "poise": 2.0},
	"dragonnewt": {"max_hp": 3.0, "atk": 2.4, "speed": 1.30, "poise": 2.5, "flight": true},
	"high_ork": {"max_hp": 2.5, "atk": 2.0, "speed": 1.05, "poise": 2.8},
	"ork_warlord": {"max_hp": 4.0, "atk": 3.2, "speed": 1.10, "poise": 4.0},
	"wight": {"max_hp": 1.8, "atk": 1.6, "speed": 1.20, "poise": 1.5},
	"death_knight": {"max_hp": 3.5, "atk": 2.8, "speed": 1.15, "poise": 3.5},
	"greater_beastkin": {"max_hp": 2.0, "atk": 1.9, "speed": 1.35, "poise": 1.8},
	"deepforged_dwarf": {"max_hp": 2.4, "atk": 2.1, "speed": 0.95, "poise": 3.5},
	"high_elf": {"max_hp": 1.8, "magic": 2.6, "speed": 1.25, "poise": 1.4},
	"shadow_weaver": {"max_hp": 1.9, "magic": 2.4, "speed": 1.40, "poise": 1.5}
}

## Evaluates whether a namer can bestow a name on a target entity
func can_name_target(namer_data: Dictionary, target_data: Dictionary) -> Dictionary:
	var namer_lvl: int = namer_data.get("level", 1)
	var namer_magic: int = namer_data.get("current_magicules", 0)
	var target_race: String = target_data.get("race", "goblin")
	var is_already_named: bool = target_data.get("is_named", false)

	if is_already_named:
		return {"allowed": false, "reason": "Target already possesses a true soul name."}

	if namer_lvl < MIN_NAMER_LEVEL:
		return {"allowed": false, "reason": "Namer requires at least Level %d to establish a soul corridor." % MIN_NAMER_LEVEL}

	var required_cost: int = calculate_naming_cost(target_race, target_data.get("level", 1))
	if namer_magic < required_cost:
		return {"allowed": false, "reason": "Insufficient magicules. Requires %d, have %d." % [required_cost, namer_magic]}

	return {"allowed": true, "cost": required_cost}

## Calculates exact magicule cost based on race and current potency
func calculate_naming_cost(race_id: String, target_level: int) -> int:
	var tier: int = 1
	match race_id:
		"goblin", "skeleton", "lizardfolk":
			tier = 1
		"beastkin", "ork", "dwarf", "halfling":
			tier = 2
		"draken", "tiefling", "elf", "dark_elf", "aasimar":
			tier = 3
		"giant", "aetherborn":
			tier = 4
		_:
			tier = 1

	var base_cost: int = TIER_MAGICULE_COSTS.get(tier, 500)
	var level_scaling: float = 1.0 + (float(target_level) * 0.05)
	return int(base_cost * level_scaling)

## Performs the naming ceremony: consumes magicules, rolls for exhaustion backlash,
## triggers metamorphosis, and assigns the new soul name.
func bestow_name(namer: Node, target: Node, assigned_name: String, namer_data: Dictionary, target_data: Dictionary) -> Dictionary:
	var validation: Dictionary = can_name_target(namer_data, target_data)
	if not validation.get("allowed", false):
		return {"success": false, "reason": validation.get("reason", "Unknown failure")}

	var cost: int = validation.get("cost", 500)
	var max_mana: int = namer_data.get("max_magicules", 1000)
	var current_mana: int = namer_data.get("current_magicules", 1000)

	# Deduct magicules
	current_mana -= cost
	namer_data["current_magicules"] = max(0, current_mana)

	# Check for Magicule Depletion Backlash (naming takes >65% of max mana pool)
	var ratio_spent: float = float(cost) / float(max(1, max_mana))
	if ratio_spent >= 0.65 or current_mana == 0:
		var exhaustion_turns: int = int(ratio_spent * 10)
		naming_backlash.emit(namer, exhaustion_turns, ratio_spent)
		if namer.has_method("apply_status_effect"):
			namer.apply_status_effect("magic_exhaustion_coma", exhaustion_turns * 6.0)

	# Set Target Name and Soul Corridor Link
	target_data["name"] = assigned_name
	target_data["is_named"] = true
	target_data["named_by"] = namer_data.get("id", "player")
	target_data["loyalty"] = 100 # Absolute devotion

	naming_completed.emit(namer, target, assigned_name, cost)

	# Automatically trigger first evolution tier if eligible
	var current_race: String = target_data.get("race", "goblin")
	var evolved_race: String = get_named_evolution_target(current_race)
	if evolved_race != "":
		execute_evolution(target, target_data, evolved_race)

	return {"success": true, "new_name": assigned_name, "evolved_to": evolved_race, "magic_spent": cost}

## Returns the natural evolution resulting immediately from naming
func get_named_evolution_target(race_id: String) -> String:
	match race_id:
		"goblin":
			return "hobgoblin"
		"lizardfolk":
			return "draken" # Metamorphoses into humanoid Dragonnewt
		"skeleton":
			return "undead" # Restores soul awareness as Wight
		"ork":
			return "high_ork"
		"beastkin":
			return "greater_beastkin"
		_:
			return ""

## Executes physical and statistical metamorphosis on an evolving entity
func execute_evolution(target_node: Node, target_data: Dictionary, new_race_id: String) -> void:
	var old_race: String = target_data.get("race", "unknown")
	evolution_started.emit(target_node, old_race, new_race_id)

	target_data["race"] = new_race_id

	# Apply stat buffs
	var buffs: Dictionary = EVOLUTION_STAT_BUFFS.get(new_race_id, {})
	for stat_key in buffs.keys():
		if stat_key == "flight":
			target_data["can_glide"] = true
		elif target_data.has(stat_key):
			target_data[stat_key] = target_data[stat_key] * buffs[stat_key]

	# Apply height scaling to 3D node
	if target_node is Node3D:
		var target_scale: float = RACE_HEIGHT_SCALES.get(new_race_id, 1.0)
		var current_scale: Vector3 = target_node.scale
		# Smooth lerp or instant scale depending on presence of tween
		var tween := target_node.create_tween()
		if tween:
			tween.tween_property(target_node, "scale", Vector3(target_scale, target_scale, target_scale), 1.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		else:
			target_node.scale = Vector3(target_scale, target_scale, target_scale)

	# Trigger visual evolution VFX burst if node supports it
	if target_node.has_method("play_vfx"):
		target_node.play_vfx("evolution_golden_chrysalis")

	var unlocked_traits: Array = buffs.keys()
	evolution_completed.emit(target_node, new_race_id, unlocked_traits)
