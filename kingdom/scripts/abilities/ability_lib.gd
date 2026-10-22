extends RefCounted
## AbilityLib: every ability the game knows as a normalised AbilityDef, by id. Two sources, one vocabulary:
##   - the legacy skills.gd trees (data/skills/*.json), converted with AbilityDef.from_technique so the player's
##     techniques keep their exact numbers;
##   - the path trees (data/powers/*.json), loaded by PowerTrees.
## NPC casters (data/powers/npc_casters.json) and the technique caster both resolve ids through here.

const AbilityDef := preload("res://scripts/abilities/ability_def.gd")
const PowerTrees := preload("res://scripts/abilities/power_trees.gd")
const Skills := preload("res://scripts/sim/skills.gd")

static var _legacy: Dictionary = {}
static var _legacy_loaded := false


static func _load_legacy() -> void:
	if _legacy_loaded:
		return
	var s: RefCounted = Skills.new()
	for id: String in s.techniques:
		_legacy[id] = AbilityDef.from_technique(s.techniques[id])
	_legacy_loaded = true


static func reload() -> void:
	_legacy = {}
	_legacy_loaded = false
	PowerTrees.load_all(true)


static func get_def(id: String) -> Dictionary:
	if PowerTrees.has_technique(id):
		return PowerTrees.ability(id)
	_load_legacy()
	return _legacy.get(id, {})


static func has_def(id: String) -> bool:
	return not get_def(id).is_empty()


static func legacy_ids() -> Array:
	_load_legacy()
	return _legacy.keys()


static func path_ids() -> Array:
	return PowerTrees.technique_ids()


## Every definition problem across both sources.
static func validate_all() -> Array[String]:
	var errs: Array[String] = []
	_load_legacy()
	for id: String in _legacy:
		errs.append_array(AbilityDef.validate(_legacy[id]))
	for id: String in PowerTrees.technique_ids():
		errs.append_array(AbilityDef.validate(PowerTrees.ability(id)))
	return errs
