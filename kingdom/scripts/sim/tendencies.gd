extends RefCounted
## Hidden childhood tendencies: quiet leanings (0..1) that repeated activities
## and childhood choices nudge over time. Never shown as numbers to the
## player — only as soft text (describe()) for the pack menu.
##
## Pure data (serialisable), no scene tree.
##
## Usage (Life):
##   var tendencies := preload("res://scripts/sim/tendencies.gd").new()
##   tendencies.record("hunted", 1.0)          # hooked from Life.record(action, amount)
##   tendencies.nudge_many({"martial": 0.05})  # childhood event choices
##   tendencies.describe()                     # -> soft text for the pack menu
##   tendencies.leading_element()              # element leaning, for the Blessing
##   Save/load: tendencies.serialize() / tendencies.deserialize(d)

## Non-elemental leanings.
const KEYS := ["martial", "craft", "trade", "faith", "scholarship", "wilderness",
	"farming", "leadership", "mischief", "compassion"]
## Elemental leanings (matches skills.gd / magicules.gd elements).
const ELEMENTS := ["fire", "water", "wind", "earth", "lightning", "qi"]

## Existing RALifePath action tags (see life_path.gd's suggested tags and
## village_services.gd / life.gd's record() calls) mapped to the tendencies
## and element leanings they quietly nudge.
const ACTION_MAP := {
	"adventured": {"martial": 0.03, "wilderness": 0.02},
	"hunted": {"wilderness": 0.05, "martial": 0.02},
	"fished": {"wilderness": 0.02, "farming": 0.01, "water": 0.02},
	"worked": {"craft": 0.02, "trade": 0.01},
	"farmed": {"farming": 0.05, "earth": 0.01},
	"helped_farmer": {"farming": 0.04, "compassion": 0.01},
	"helped_parent": {"compassion": 0.03},
	"traded": {"trade": 0.04},
	"haggled": {"trade": 0.02},
	"sold": {"trade": 0.02},
	"bought": {"trade": 0.01},
	"studied": {"scholarship": 0.05},
	"read": {"scholarship": 0.03},
	"trained_sword": {"martial": 0.05},
	"trained_fist": {"martial": 0.05},
	"sparred": {"martial": 0.03},
	"meditated": {"faith": 0.02, "scholarship": 0.01, "qi": 0.02},
	"prayed": {"faith": 0.05},
	"visited_shrine": {"faith": 0.04},
	"crafted": {"craft": 0.05},
	"smithed": {"craft": 0.05, "fire": 0.02},
	"guarded": {"martial": 0.03, "leadership": 0.02},
	"patrolled": {"martial": 0.02, "leadership": 0.01},
	"stole": {"mischief": 0.06},
	"sneaked": {"mischief": 0.04},
	"lockpicked": {"mischief": 0.04},
	"healed": {"compassion": 0.05, "faith": 0.01, "water": 0.01},
	"gathered_herbs": {"wilderness": 0.02, "compassion": 0.01},
	"explored": {"wilderness": 0.04},
	"explored_forest": {"wilderness": 0.05},
	"explored_ruins": {"wilderness": 0.03, "scholarship": 0.02},
	"tamed": {"wilderness": 0.04, "compassion": 0.02},
	"performed": {"leadership": 0.02},
	"told_story": {"leadership": 0.01, "scholarship": 0.01},
	"gave_gift": {"compassion": 0.02},
	"named": {"compassion": 0.02, "wilderness": 0.02},
	"helped_villager": {"compassion": 0.03, "leadership": 0.01},
}

const DESCRIPTIONS := {
	"martial": "You're drawn to the soldiers' drills.",
	"craft": "You like watching things get made with your hands.",
	"trade": "You have a knack for haggling and counting coin.",
	"faith": "The old stories and the temple bell stay with you.",
	"scholarship": "You'd rather ask why than just do.",
	"wilderness": "The wild edge of the world calls to you.",
	"farming": "There's comfort in dirt under your nails.",
	"leadership": "Other children seem to fall in line behind you.",
	"mischief": "Trouble finds you, or you find it.",
	"compassion": "You notice when someone's hurting before anyone else does.",
}

## key/element -> 0..1. Everyone starts middling: nothing determined yet.
var values: Dictionary = {}
var elements: Dictionary = {}


func _init() -> void:
	for k: String in KEYS:
		values[k] = 0.35
	for e: String in ELEMENTS:
		elements[e] = 0.4


func nudge(key: String, amount: float) -> void:
	if values.has(key):
		values[key] = clampf(float(values[key]) + amount, 0.0, 1.0)
	elif elements.has(key):
		elements[key] = clampf(float(elements[key]) + amount, 0.0, 1.0)


func nudge_many(deltas: Dictionary) -> void:
	for k: String in deltas:
		nudge(k, float(deltas[k]))


## Hook for Life.record(tag, weight): quietly nudges whatever ACTION_MAP maps
## `tag` to. Unmapped tags nudge nothing (safe to call for every record()).
func record(tag: String, weight := 1.0) -> void:
	var m: Dictionary = ACTION_MAP.get(tag, {})
	if m.is_empty():
		return
	var w := clampf(weight, 0.0, 3.0)
	for k: String in m:
		nudge(k, float(m[k]) * w)


func value(key: String) -> float:
	if values.has(key):
		return float(values[key])
	return float(elements.get(key, 0.0))


## The `count` highest non-elemental leanings, as [[key, value], ...], best first.
func top(count := 3) -> Array:
	var rows := []
	for k: String in values:
		rows.append([k, float(values[k])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return rows.slice(0, count)


## The strongest element leaning (ties broken by declaration order).
func leading_element() -> String:
	var best := ELEMENTS[0]
	var best_v := -1.0
	for e: String in ELEMENTS:
		if float(elements.get(e, 0.0)) > best_v:
			best_v = float(elements[e])
			best = e
	return best


## Soft, non-numeric text for the pack menu: the strongest leanings that have
## actually risen above the baseline, or a neutral line for an early life.
func describe() -> String:
	var lines := PackedStringArray()
	for row: Array in top(3):
		if float(row[1]) > 0.45:
			var line := String(DESCRIPTIONS.get(String(row[0]), ""))
			if line != "":
				lines.append(line)
	if lines.is_empty():
		return "Still finding your feet in the world."
	return "\n".join(lines)


func serialize() -> Dictionary:
	return {"values": values.duplicate(), "elements": elements.duplicate()}


func deserialize(d: Dictionary) -> void:
	var v: Dictionary = d.get("values", {})
	for k: String in v:
		if values.has(k):
			values[k] = float(v[k])
	var e: Dictionary = d.get("elements", {})
	for k: String in e:
		if elements.has(k):
			elements[k] = float(e[k])
