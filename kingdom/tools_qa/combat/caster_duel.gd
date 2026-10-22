extends SceneTree
## Headless caster duel arena: NPC casters through the shared AbilityRunner against melee fighters and each other.
## Run:  $G --headless --path . -s res://tools_qa/combat/caster_duel.gd -- [--n=200] [--seed=1] [--only=label,label]
## Same seed, same numbers. Library: tools_qa/combat/caster_duel_lib.gd (also used by tests/test_npc_casting.gd).

const Lib := preload("res://tools_qa/combat/caster_duel_lib.gd")

## [label, a, b]  (a/b: NpcCaster id from data/powers/npc_casters.json or NpcFighter archetype)
const MATCHUPS := [
	["mage_vs_bandit", "bandit_mage", "bandit"],
	["mage_vs_goblin", "bandit_mage", "goblin"],
	["disciple_vs_bandit", "sect_disciple", "bandit"],
	["knight_vs_bandit", "knight_captain", "bandit"],
	["knight_vs_guard", "knight_captain", "guard"],
	["mage_vs_disciple", "bandit_mage", "sect_disciple"],
	["disciple_vs_knight", "sect_disciple", "knight_captain"],
	["veteran_vs_knight", "veteran_mage", "knight_captain"],
]


func _init() -> void:
	var n := 200
	var seed_base := 1
	var only := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--seed="):
			seed_base = int(a.substr(7))
		elif a.begins_with("--only="):
			only = a.substr(7)
	print("caster duel arena: n=%d seed=%d dt=%.2f" % [n, seed_base, Lib.DT])
	print("%-20s %6s %6s %6s %7s %6s %6s %7s %7s %7s" % ["matchup", "A win%", "B win%", "draw%", "TTK(s)", "A hp%", "B hp%", "A cast", "B cast", "brkn/d"])
	for m: Array in MATCHUPS:
		if only != "" and not (String(m[0]) in only.split(",")):
			continue
		var lib := Lib.new()
		var r: Dictionary = lib.run(String(m[1]), String(m[2]), n, seed_base)
		print("%-20s %6.1f %6.1f %6.1f %7.1f %6.1f %6.1f %7.2f %7.2f %7.2f" % [m[0], r["a_win"], r["b_win"], r["draw"], r["ttk"],
			r["a_hp"], r["b_hp"], r["a_casts"], r["b_casts"], float(r["a_broken"]) + float(r["b_broken"])])
		var used: Dictionary = r["abilities"]
		var parts: Array = []
		for k: String in used:
			parts.append("%s=%.1f" % [k, float(used[k]) / n])
		print("    casts/duel: " + ", ".join(PackedStringArray(parts)))
	quit(0)
