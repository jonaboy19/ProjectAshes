class_name TournamentSystem
extends Node
## Manages the Grand Tournaments across the Arenas of Valencious.
## Supports bracketed combat, champion AI rosters, betting odds, spectator hype,
## and progression through Bronze, Silver, Gold, and Mythic championship tiers.

signal tournament_started(arena_name: String, tier: String)
signal match_commenced(fighter_a: Dictionary, fighter_b: Dictionary)
signal match_concluded(winner: Dictionary, loser: Dictionary)
signal tournament_won(champion: Dictionary, prize_gold: int, prize_title: String)

enum Tier { BRONZE, SILVER, GOLD, MYTHIC }

const TIERS := {
	Tier.BRONZE: {
		"name": "Novice Trial",
		"min_level": 5,
		"entry_fee": 25,
		"purse_gold": 250,
		"reward_title": "Arena Challenger",
		"reward_item": "weapon_iron_broadsword_master"
	},
	Tier.SILVER: {
		"name": "Knight's Joust",
		"min_level": 15,
		"entry_fee": 100,
		"purse_gold": 1000,
		"reward_title": "Knight of the Sand",
		"reward_item": "armor_caldric_knight_plate"
	},
	Tier.GOLD: {
		"name": "Champions' Clash",
		"min_level": 30,
		"entry_fee": 500,
		"purse_gold": 5000,
		"reward_title": "Grand Champion",
		"reward_item": "weapon_obsidian_sunblade"
	},
	Tier.MYTHIC: {
		"name": "Clash of the Immortals",
		"min_level": 50,
		"entry_fee": 2500,
		"purse_gold": 25000,
		"reward_title": "Blade of Valencious",
		"reward_item": "relic_crown_dragon_crest"
	}
}

## Master roster of NPC tournament contenders
const FIGHTERS := [
	{
		"id": "gareth",
		"name": "Sir Gareth the Iron Wall",
		"race": "human",
		"class": "paladin",
		"tier": Tier.SILVER,
		"combat_style": "sword_and_shield",
		"hp": 850,
		"armor": 45,
		"quote": "My shield stands unbroken for the Crown of Valencious!"
	},
	{
		"id": "sylas",
		"name": "Sylas Obsidian Fang",
		"race": "dark_elf",
		"class": "shadow_blade",
		"tier": Tier.GOLD,
		"combat_style": "dual_daggers",
		"hp": 680,
		"armor": 22,
		"quote": "Blink once, and the duel is already over."
	},
	{
		"id": "gromkar",
		"name": "Gromkar Bonecleaver",
		"race": "orc",
		"class": "berserker",
		"tier": Tier.GOLD,
		"combat_style": "two_handed_axe",
		"hp": 1200,
		"armor": 30,
		"quote": "Tuskridge blood never surrenders!"
	},
	{
		"id": "li_tian",
		"name": "Elder Li Tian",
		"race": "human",
		"class": "mist_swordsman",
		"tier": Tier.GOLD,
		"combat_style": "jian_flow",
		"hp": 750,
		"armor": 18,
		"quote": "The sword follows the wind; the wind leaves no trace."
	},
	{
		"id": "elowen",
		"name": "Lady Elowen the Spellblade",
		"race": "high_elf",
		"class": "spellblade",
		"tier": Tier.MYTHIC,
		"combat_style": "arcane_rapier",
		"hp": 920,
		"armor": 35,
		"quote": "Arcane truth yields to neither steel nor sorcery alone."
	},
	{
		"id": "drogath",
		"name": "Drogath Stonefist",
		"race": "dwarf",
		"class": "magma_hammer",
		"tier": Tier.SILVER,
		"combat_style": "warhammer",
		"hp": 1050,
		"armor": 50,
		"quote": "By the forges of Gundarak, taste dwarven iron!"
	}
]

var active_tournament: Dictionary = {}
var current_round := 0
var player_wager := 0
var wager_fighter_id := ""

## Initializes a tournament in the specified arena
func start_tournament(arena_name: String, tier: Tier) -> Dictionary:
	var info: Dictionary = TIERS[tier]
	active_tournament = {
		"arena": arena_name,
		"tier": tier,
		"info": info,
		"round": 1,
		"brackets": _generate_bracket(tier),
		"is_active": true
	}
	tournament_started.emit(arena_name, info["name"])
	return active_tournament

## Generates 8-fighter bracket seeded by tier
func _generate_bracket(tier: Tier) -> Array[Dictionary]:
	var eligible: Array[Dictionary] = []
	for f: Dictionary in FIGHTERS:
		if f["tier"] <= tier:
			eligible.append(f.duplicate())
	
	# Pad with arena gladiators if needed
	while eligible.size() < 8:
		eligible.append({
			"id": "gladiator_%d" % eligible.size(),
			"name": "Veteran Gladiator %d" % eligible.size(),
			"race": "human",
			"class": "warrior",
			"tier": tier,
			"combat_style": "sword_and_shield",
			"hp": 500 + int(tier) * 200,
			"armor": 20 + int(tier) * 10,
			"quote": "The sands demand blood!"
		})
	eligible.shuffle()
	return eligible

## Places a wager on an upcoming combatant
func place_wager(fighter_id: String, amount_gold: int) -> bool:
	if not active_tournament.get("is_active", false):
		return false
	player_wager = amount_gold
	wager_fighter_id = fighter_id
	return true

## Simulates or runs match between two fighters
func resolve_match(fighter_a: Dictionary, fighter_b: Dictionary) -> Dictionary:
	match_commenced.emit(fighter_a, fighter_b)
	# Combat calculation factoring HP and Armor rating
	var score_a := float(fighter_a["hp"]) * (1.0 + float(fighter_a["armor"]) / 100.0)
	var score_b := float(fighter_b["hp"]) * (1.0 + float(fighter_b["armor"]) / 100.0)
	var total := score_a + score_b
	var roll := randf() * total
	
	var winner: Dictionary = fighter_a if roll < score_a else fighter_b
	var loser: Dictionary = fighter_b if roll < score_a else fighter_a
	
	match_concluded.emit(winner, loser)
	return winner
