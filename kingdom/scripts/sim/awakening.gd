extends RefCounted
## The age-12 Blessing / Awakening: a cultural ceremony, not a class pick. The
## outcome is rolled once, weighted by the character's hidden tendencies
## (RATendencies) and their parents' culture, into a primary element, a
## strength tier, a rare dual affinity, or no Blessing at all (its own hidden
## path). See docs/RISING_ASHES_LIFE_SIM_DESIGN.md, "12 Blessing / Awakening".
##
## Pure data/rules (deterministic, own seeded rng, serialisable).
##
## Usage (Life):
##   var awakening := preload("res://scripts/sim/awakening.gd").new()
##   var r := awakening.roll(tendencies, culture_id, WorldSim.SEED, life_path.full_name(), WorldSim.day)
##   for f in awakening.flags(): life_path.set_flag(f)
##   Save/load: awakening.serialize() / awakening.deserialize(d)

## Matches skills.gd / magicules.gd / tendencies.gd elements.
const ELEMENTS := ["fire", "water", "wind", "earth", "lightning", "qi"]
const TIERS := ["faint", "common", "strong", "exceptional"]
## Tier weights (rolled independently of the element itself).
const TIER_WEIGHTS := [0.30, 0.45, 0.20, 0.05]
## Roughly the design's "about 6%" and "about 4%".
const NONE_CHANCE := 0.06
const DUAL_CHANCE := 0.04

## Culture id -> element it leans toward (data/world/cultures.json "element").
const CULTURE_ELEMENT := {
	"caldric": "earth", "seirune": "water", "ongur": "wind", "solenne": "fire",
	"urrokai": "earth", "shenlu": "lightning", "veyl": "earth", "durrow": "fire",
}
## The first technique of each element tree (data/skills/<element>.json, tier 1),
## granted on a Blessing (see skills.gd's `grant()`, which bypasses gating).
const FIRST_TECHNIQUE := {
	"fire": "fire_ember_orb", "water": "water_whip", "wind": "wind_blade",
	"earth": "earth_stone_bullet", "lightning": "lightning_spark", "qi": "qi_gathering",
}

var done := false
var element := ""
var tier := ""
## Second element on a rare dual affinity ("" otherwise).
var dual := ""
var none := false
var day := -1
var _rng := RandomNumberGenerator.new()


func has_happened() -> bool:
	return done


## Rolls the outcome once (subsequent calls return the same result). Seeded
## from the world seed and the character's full name, so it is deterministic
## per save but differs between characters and worlds.
func roll(tendencies: Object, culture_id: String, world_seed: int, character: String, cal_day: int) -> Dictionary:
	if done:
		return result()
	_rng.seed = hash([world_seed, character, "awakening"])
	done = true
	day = cal_day
	if _rng.randf() < NONE_CHANCE:
		none = true
		return result()
	var el_leaning: Dictionary = {}
	if tendencies != null:
		var v: Variant = tendencies.get("elements")
		if v is Dictionary:
			el_leaning = v
	var weights := {}
	for e: String in ELEMENTS:
		weights[e] = 0.3 + float(el_leaning.get(e, 0.4)) * 1.5
	var culture_el := String(CULTURE_ELEMENT.get(culture_id, ""))
	if weights.has(culture_el):
		weights[culture_el] = float(weights[culture_el]) * 1.6
	element = _weighted_pick_dict(weights)
	if _rng.randf() < DUAL_CHANCE:
		var rest := {}
		for e: String in weights:
			if e != element:
				rest[e] = weights[e]
		dual = _weighted_pick_dict(rest)
	tier = _weighted_pick_array(TIERS, TIER_WEIGHTS)
	return result()


func _weighted_pick_dict(weights: Dictionary) -> String:
	var total := 0.0
	for k: String in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return weights.keys()[0] if not weights.is_empty() else ELEMENTS[0]
	var r := _rng.randf() * total
	var acc := 0.0
	var last := ""
	for k: String in weights:
		acc += maxf(0.0, float(weights[k]))
		last = k
		if r <= acc:
			return k
	return last


func _weighted_pick_array(keys: Array, weights: Array) -> String:
	var total := 0.0
	for w in weights:
		total += float(w)
	var r := _rng.randf() * total
	var acc := 0.0
	for i in keys.size():
		acc += float(weights[i])
		if r <= acc:
			return String(keys[i])
	return String(keys[keys.size() - 1])


func result() -> Dictionary:
	return {"done": done, "element": element, "tier": tier, "dual": dual, "none": none, "day": day}


## Flags to set on RALifePath ("blessing:<element>", "blessing_tier:<tier>",
## "blessing_dual" and a second "blessing:<element>" on a dual, or
## "blessing:none" for the hidden no-Blessing path).
func flags() -> Array[String]:
	var out: Array[String] = []
	if not done:
		return out
	if none:
		out.append("blessing:none")
		return out
	out.append("blessing:" + element)
	out.append("blessing_tier:" + tier)
	if dual != "":
		out.append("blessing:" + dual)
		out.append("blessing_dual")
	return out


## A first technique to grant (skills.gd grant(), which bypasses gating), or "".
func first_technique(el := "") -> String:
	return String(FIRST_TECHNIQUE.get(el if el != "" else element, ""))


func serialize() -> Dictionary:
	return {"done": done, "element": element, "tier": tier, "dual": dual, "none": none,
		"day": day, "rng": str(_rng.state)}


func deserialize(d: Dictionary) -> void:
	done = bool(d.get("done", false))
	element = String(d.get("element", ""))
	tier = String(d.get("tier", ""))
	dual = String(d.get("dual", ""))
	none = bool(d.get("none", false))
	day = int(d.get("day", -1))
	if d.has("rng"):
		_rng.state = String(d["rng"]).to_int()
