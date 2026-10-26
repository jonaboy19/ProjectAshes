class_name CorpseLoot
extends RefCounted
## "Search" for the bodies takedown.gd and death leave behind. A body (any Node3D) gets a small deterministic loot
## table rolled from its key; searching pays it out once (Life.give + Game.add_gold) and the body is then bare.
## Pure rolling (`roll`) is separate from the world effect (`search`) so tests can check both.
##
## Table: {"gold": [min, max], "items": [[item_id, chance 0..1, min, max], ...]}.

const CIVILIAN := {"gold": [0, 5], "items": [["bread", 0.35, 1, 1], ["apple", 0.3, 1, 2]]}
const GUARD := {"gold": [3, 14], "items": [["bread", 0.5, 1, 2]]}

## Keys already searched (a body is searched once, also across a KO wake-up and a second knock-out).
static var looted := {}


static func reset() -> void:
	looted.clear()


## Deterministic roll: same key and table, same loot. Returns {gold: int, items: [[id, qty], ...]}.
static func roll(key: String, table: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["corpse", key])
	var g: Array = table.get("gold", [0, 0])
	var out := {"gold": rng.randi_range(int(g[0]), int(g[1])), "items": []}
	for e: Array in table.get("items", []):
		if rng.randf() < float(e[1]):
			(out["items"] as Array).append([String(e[0]), rng.randi_range(int(e[2]), int(e[3]))])
	return out


## Makes `body` searchable under `key` (once per key). `can` (Callable() -> bool) says when the body is still a
## body, e.g. not woken up. Returns the component.
static func attach(body: Node3D, key: String, table: Dictionary = CIVILIAN, can := Callable()) -> Interactable:
	var existing := Interactable.component_of(body)
	if existing != null:
		existing.enabled = true
		return existing
	return Interactable.attach(body, {"id": "corpse/" + key, "verb": "Search", "target": "Body", "range": 2.4,
		"can": func(_p: Node) -> bool: return not looted.has(key) and (not can.is_valid() or bool(can.call())),
		"do": func(p: Node) -> void:
			search(key, table, p)
			if is_instance_valid(body):
				Interactable.set_active(body, false)})   # a searched body leaves the picker (and stops blocking talk targets)


## Pays the roll out. Returns the loot dictionary ({} when the body was already searched).
static func search(key: String, table: Dictionary, _player: Node = null) -> Dictionary:
	if looted.has(key):
		return {}
	looted[key] = true
	var loot := roll(key, table)
	var parts := PackedStringArray()
	if int(loot["gold"]) > 0:
		Game.add_gold(int(loot["gold"]))
		parts.append("%d gold" % int(loot["gold"]))
	for e: Array in loot["items"]:
		Life.give(String(e[0]), int(e[1]))
		parts.append("%s ×%d" % [Life.item_name(String(e[0])), int(e[1])])
	Game.say("You search the body: %s." % (", ".join(parts) if not parts.is_empty() else "nothing of value"))
	return loot


# --- animal carcasses (READY_V1 C10) ----------------------------------------------------------------------------

## Makes an animal carcass skinnable: hold the button to butcher it for meat, hide and antler (sim/hunting.gd; the haul
## scales with the player's hunting mastery). A pooled body is reused, so each death gets a fresh component and key.
## The body must have `dead` true for the prompt to show; the Interactable leaves the picker once skinned.
static func attach_animal(body: Node3D, kind: String) -> Interactable:
	if not Hunting.can_skin(kind):
		return null
	var old := Interactable.component_of(body)
	if old != null:
		old.free()
	var serial := int(body.get_meta("skin_serial", 0)) + 1
	body.set_meta("skin_serial", serial)
	var key := "animal/%d/%d" % [body.get_instance_id(), serial]
	return Interactable.attach(body, {"id": "carcass/" + key, "verb": "Skin", "target": kind.capitalize() + " carcass",
		"range": 2.6, "hold_time": Hunting.HOLD_SECONDS,
		"can": func(_p: Node) -> bool: return not looted.has(key) and bool(body.get("dead")),
		"do": func(p: Node) -> void:
			skin_animal(kind, key, p)
			if is_instance_valid(body):
				Interactable.set_active(body, false)})


## Pays the skinning out. Returns the Hunting.skin result ({} when this carcass was already skinned).
static func skin_animal(kind: String, key: String, _player: Node = null) -> Dictionary:
	if looted.has(key):
		return {}
	looted[key] = true
	var res := Hunting.skin(kind, key, Life, WorldSim.day)
	Game.say(String(res["text"]))
	Life.on_haul_skinned(res["items"])
	return res
