extends RefCounted
## Usage-driven evolution of elemental abilities: not a level-up screen, but a
## record of *how* an element has actually been used. A smith's fire is not a
## soldier's fire (docs/RISING_ASHES_LIFE_SIM_DESIGN.md, pillar 4): enough uses
## of an element in one context (forge, combat, hearth, heal, hunt, meditate,
## technique...) evolves it into a named variant with its own passive
## modifiers, defined in data/soul/evolutions.json. Using two contexts of the
## same element heavily enough can trigger a rare second-stage mutation that
## fuses both into one.
##
## Pure data/rules (RefCounted, no nodes), serialisable.
##
## INTEGRATION (Life; not wired yet — see the soul_hooks report):
##   var evolution := preload("res://scripts/sim/skill_evolution.gd").new()
##   evolution.record_use("fire", "forge", WorldSim.day)   # e.g. from crafting.crafted
##   for evo in evolution.newly_available(): Game.say("Your %s has become %s." % [...])
##   Save: snapshot["skill_evolution"] = evolution.serialize()

signal evolved(evo: Dictionary)

const DATA_PATH := "res://data/soul/evolutions.json"
const ELEMENTS := ["fire", "water", "earth", "wind", "lightning", "qi"]

## element -> Array[{context, uses, id, name, flavour, modifiers}]
var _variants: Dictionary = {}
## Array[{element, contexts, uses, id, name, flavour, modifiers}]
var _mutations: Array = []
## id -> def (variant or mutation), for lookup and save/restore.
var _by_id: Dictionary = {}

## "element:context" -> use count.
var uses: Dictionary = {}
## unlocked id -> {..def.., day}
var unlocked: Dictionary = {}
## Unlocked defs not yet shown to the player; drained by newly_available().
var _pending: Array = []


func _init(load_data := true) -> void:
	if load_data:
		_load()


func _load() -> void:
	var d: Variant = _read_json(DATA_PATH)
	if not d is Dictionary:
		return
	var evs: Dictionary = d.get("evolutions", {})
	for el: String in evs:
		var list: Array = []
		for def: Dictionary in (evs[el] as Array):
			var dd := def.duplicate(true)
			dd["element"] = el
			list.append(dd)
			_by_id[String(dd["id"])] = dd
		_variants[el] = list
	for def: Dictionary in (d.get("mutations", []) as Array):
		var dd := def.duplicate(true)
		_mutations.append(dd)
		_by_id[String(dd["id"])] = dd


static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _key(element: String, context: String) -> String:
	return "%s:%s" % [element, context]


func use_count(element: String, context: String) -> int:
	return int(uses.get(_key(element, context), 0))


## Records one use of `element` in `context` (e.g. "fire" cast while at the
## forge, or while fighting). Evolves the element into a context variant once
## its threshold is met, and checks for a rare cross-context mutation.
## Returns {element, context, uses, newly_unlocked: Array[Dictionary]}.
func record_use(element: String, context: String, day: int) -> Dictionary:
	var key := _key(element, context)
	uses[key] = int(uses.get(key, 0)) + 1
	var gained := []
	for def: Dictionary in (_variants.get(element, []) as Array):
		var id := String(def["id"])
		if String(def.get("context", "")) != context or unlocked.has(id):
			continue
		if int(uses[key]) >= int(def.get("uses", 999999)):
			_unlock(def, day)
			gained.append(def)
	for def: Dictionary in _mutations:
		var id := String(def["id"])
		if String(def.get("element", "")) != element or unlocked.has(id):
			continue
		var contexts: Array = def.get("contexts", [])
		if not contexts.has(context):
			continue
		var ready := true
		for c: String in contexts:
			if int(uses.get(_key(element, c), 0)) < int(def.get("uses", 999999)):
				ready = false
				break
		if ready:
			_unlock(def, day)
			gained.append(def)
	return {"element": element, "context": context, "uses": int(uses[key]), "newly_unlocked": gained}


func _unlock(def: Dictionary, day: int) -> void:
	var entry := def.duplicate(true)
	entry["day"] = day
	unlocked[String(def["id"])] = entry
	_pending.append(entry)
	evolved.emit(entry)


## Evolutions unlocked so far, id -> def (with "day" unlocked).
func evolutions() -> Dictionary:
	return unlocked.duplicate(true)


## Drains and returns evolutions unlocked since the last call (for a HUD toast
## or the soul screen's "new" badge).
func newly_available() -> Array:
	var out := _pending.duplicate(true)
	_pending.clear()
	return out


## Combined passive modifiers of every unlocked evolution and mutation, summed
## per key (e.g. modifiers().get("forge_quality", 0.0)).
func modifiers() -> Dictionary:
	var out := {}
	for id: String in unlocked:
		var mods: Dictionary = (unlocked[id] as Dictionary).get("modifiers", {})
		for k: String in mods:
			out[k] = float(out.get(k, 0.0)) + float(mods[k])
	return out


func serialize() -> Dictionary:
	return {"version": 1, "uses": uses.duplicate(), "unlocked": unlocked.keys(),
		"pending": _pending.map(func(d: Dictionary) -> String: return String(d["id"]))}


func deserialize(d: Dictionary) -> void:
	uses.clear()
	for k: String in (d.get("uses", {}) as Dictionary):
		uses[k] = int(d["uses"][k])
	unlocked.clear()
	for id: Variant in d.get("unlocked", []):
		var sid := String(id)
		if _by_id.has(sid):
			var entry: Dictionary = (_by_id[sid] as Dictionary).duplicate(true)
			entry["day"] = 0
			unlocked[sid] = entry
	_pending.clear()
	for id: Variant in d.get("pending", []):
		var sid := String(id)
		if unlocked.has(sid):
			_pending.append(unlocked[sid])
