extends RefCounted
## Region 1 progression spine (package C13): the end-of-region power targets and the Rift gate, as pure static rules over
## data/region1/progression_spine.json. No state, no scene access. The balance run and tests/test_balance_r1.gd measure against
## `targets()`; the main quest (r1_main.json, step a5_rifts_edge) opens only when `rift_gate()` says so (the story director
## passes soul_tier, gear_tier and level in its condition context; dialogue_runner.gd understands min_soul_tier / min_gear_tier /
## min_level). Preload; no class_name.

const PATH := "res://data/region1/progression_spine.json"
const CORE_SLOTS: Array[String] = ["main_hand", "body", "head", "legs", "feet", "off_hand"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data


static func targets() -> Dictionary:
	return data().get("targets", {})


static func gate() -> Dictionary:
	return data().get("rift_gate", {})


## Mean tier of the six core slots worn, rounded to nearest with .5 going down (tier 2 is a mostly-iron kit, tier 3 needs steel). `tier_of` is a Callable(item_id) -> int (Crafting.item_info(id).tier in the game).
static func gear_tier(worn: Dictionary, tier_of: Callable) -> int:
	var sum := 0.0
	for s: String in CORE_SLOTS:
		var id := String((worn.get(s, {}) as Dictionary).get("id", "")) if worn.get(s) is Dictionary else String(worn.get(s, ""))
		if id != "":
			sum += float(tier_of.call(id))
	return int(ceil(sum / float(CORE_SLOTS.size()) - 0.5))


## The gear tier of the player's equipment object (scripts/sim/equipment.gd).
static func player_gear_tier(equipment: Object) -> int:
	var Crafting: GDScript = load("res://scripts/sim/crafting.gd")
	var worn: Dictionary = equipment.get("slots")
	return gear_tier(worn, func(id: String) -> int: return int(Crafting.call("item_info", id).get("tier", 0)))


## Whether the Rift's Edge may open. `state`: {story_done (bool, a4_five_hearts), soul_tier, gear_tier, level}.
## -> {open, missing: PackedStringArray, lines: [{text, met}], hint}
static func rift_gate(state: Dictionary) -> Dictionary:
	var g := gate()
	var lines: Array = []
	var missing := PackedStringArray()
	var checks := [
		["The five hearts are lit", bool(state.get("story_done", false))],
		["Soul tier %d or more (have %d)" % [int(g.get("min_soul_tier", 3)), int(state.get("soul_tier", 0))], int(state.get("soul_tier", 0)) >= int(g.get("min_soul_tier", 3))],
		["Gear tier %d or more (have %d)" % [int(g.get("min_gear_tier", 2)), int(state.get("gear_tier", 0))], int(state.get("gear_tier", 0)) >= int(g.get("min_gear_tier", 2))],
		["Level %d or more (have %d)" % [int(g.get("min_level", 12)), int(state.get("level", 1))], int(state.get("level", 1)) >= int(g.get("min_level", 12))],
	]
	for c: Array in checks:
		lines.append({"text": String(c[0]), "met": bool(c[1])})
		if not bool(c[1]):
			missing.append(String(c[0]))
	return {"open": missing.is_empty(), "missing": missing, "lines": lines, "hint": String(g.get("hint", ""))}


## The same gate without the story requirement (the quest step carries that itself): power only.
static func power_ready(soul_tier: int, gear_tier_: int, level: int) -> bool:
	var g := gate()
	return soul_tier >= int(g.get("min_soul_tier", 3)) and gear_tier_ >= int(g.get("min_gear_tier", 2)) and level >= int(g.get("min_level", 12))


## Does a run summary (balance_sim.gd summary()) meet the end-of-region targets? -> {ok, checks: [{name, ok, have, want}]}
static func evaluate(sm: Dictionary) -> Dictionary:
	var t := targets()
	var checks: Array = []
	var house_day := int((sm.get("first_day", {}) as Dictionary).get("house", 1 << 20))
	checks.append({"name": "first house within %d days" % int(t["first_house_day_max"]), "ok": house_day <= int(t["first_house_day_max"]), "have": house_day, "want": "<= %d" % int(t["first_house_day_max"])})
	var rt: Array = t["soul_tier"]
	checks.append({"name": "soul tier %d-%d" % [int(rt[0]), int(rt[1])], "ok": int(sm.get("soul_tier", 0)) >= int(rt[0]) and int(sm.get("soul_tier", 0)) <= int(rt[1]), "have": int(sm.get("soul_tier", 0)), "want": "%d-%d" % [int(rt[0]), int(rt[1])]})
	var cr: Array = t["career_rank"]
	checks.append({"name": "career rank %d-%d" % [int(cr[0]), int(cr[1])], "ok": int(sm.get("career_rank", 0)) >= int(cr[0]) and int(sm.get("career_rank", 0)) <= int(cr[1]), "have": int(sm.get("career_rank", 0)), "want": "%d-%d" % [int(cr[0]), int(cr[1])]})
	var gt: Array = t["gear_tier"]
	checks.append({"name": "gear tier %d" % int(gt[0]), "ok": int(sm.get("gear_tier", 0)) >= int(gt[0]) and int(sm.get("gear_tier", 0)) <= int(gt[1]), "have": int(sm.get("gear_tier", 0)), "want": "%d-%d" % [int(gt[0]), int(gt[1])]})
	checks.append({"name": "level %d+" % int(t["level_min"]), "ok": int(sm.get("level", 1)) >= int(t["level_min"]), "have": int(sm.get("level", 1)), "want": ">= %d" % int(t["level_min"])})
	var top_day := int((sm.get("first_day", {}) as Dictionary).get("rank_top", 1 << 20))
	checks.append({"name": "top rank not before day %d" % int(t["top_rank_day_min"]), "ok": top_day >= int(t["top_rank_day_min"]), "have": top_day if top_day < (1 << 20) else -1, "want": ">= %d (or never)" % int(t["top_rank_day_min"])})
	checks.append({"name": "fed", "ok": float(sm.get("fed_share", 0.0)) >= float(t["fed_share_min"]), "have": snappedf(float(sm.get("fed_share", 0.0)), 0.01), "want": ">= %.2f" % float(t["fed_share_min"])})
	var ok := true
	for c: Dictionary in checks:
		ok = ok and bool(c["ok"])
	return {"ok": ok, "checks": checks}
