class_name TameTarget
extends RefCounted
## READY_V1 C8 taming. A wild wolf or Stagborn elk beaten below CALM_BELOW of its health shows "Calm"; the prompt is a
## hold whose length the creature's trust and fear set (a beaten, already-wary beast calms fastest). Each finished hold
## is one followers.calm_step; a second success makes it yours, as a follower (walks beside you) or a guard (holds a
## post, feeds guard_bonus -> raids). Creatures are only read (health, species, dead), never edited: a tamed beast is
## taken off the wild AI from outside (TamedPet). Pure rules are static so tests need no scene.

## World species -> followers.gd SPECIES key. Anything not here can never be tamed (Warden, goblins, wraiths ...).
const SPECIES_MAP := {"wolf": "wolf", "stagborn_elk": "stag"}
const NEVER := ["stagborn_warden", "goblin", "orc", "troll", "rift_wraith", "bandit"]
const CALM_BELOW := 0.35
const HOLD_MAX := 4.0
const HOLD_MIN := 1.0

## Interaction ids already attached to a body live on the node itself; this counts calm-ids for stable save keys.
static var _serial := 0


static func never_tamable(species: String) -> bool:
	return NEVER.has(species) or not SPECIES_MAP.has(species)


static func fear_of(health: float, max_health: float) -> float:
	return clampf(1.0 - health / maxf(max_health, 1.0), 0.0, 1.0)


## True when `health`/`max_health` of `species` is calmable right now (alive, beaten, tameable kind).
static func calmable_stats(species: String, health: float, max_health: float, dead := false) -> bool:
	if dead or never_tamable(species) or health <= 0.0:
		return false
	return health <= max_health * CALM_BELOW


static func calmable(body: Node) -> bool:
	if body == null or not is_instance_valid(body) or body.has_meta("tamed") or body.is_in_group("tamed_pet"):
		return false
	var sp = body.get("species")
	if sp == null:
		return false
	return calmable_stats(String(sp), float(body.get("health")), float(body.get("max_health")), bool(body.get("dead")))


## Seconds the player must hold; trust and fear both shorten it.
static func hold_seconds(trust: float, fear: float) -> float:
	return clampf(3.0 - 1.5 * trust - 1.0 * fear, HOLD_MIN, HOLD_MAX)


static func _fm() -> RefCounted:
	var hub = Life.get("realm") if Life != null else null
	return hub.mod("followers") if hub != null else null


static func creature_id(body: Node) -> String:
	if not body.has_meta("calm_id"):
		_serial += 1
		body.set_meta("calm_id", "wild_%s_%d_%d" % [String(body.get("species")), WorldSim.day, _serial])
	return String(body.get_meta("calm_id"))


## Makes `body` calmable (Interactable component). Returns it.
static func attach(body: Node3D) -> Interactable:
	var existing := Interactable.component_of(body)
	if existing != null:
		existing.enabled = true
		return existing
	return Interactable.attach(body, {"id": "calm/%d" % body.get_instance_id(), "verb": "Calm", "target": _name_of(body),
		"range": 2.8, "hold_time": HOLD_MAX, "priority": 2,
		"can": func(_p: Node) -> bool: return calmable(body),
		"do": func(p: Node) -> void: calm(body, p)})


static func _name_of(body: Node) -> String:
	return String(body.get("species")).replace("_", " ").capitalize()


## Keeps the hold length honest for the current trust and fear.
static func refresh(body: Node3D) -> void:
	var c := Interactable.component_of(body)
	if c == null or not (c.can_fn.is_valid() and bool(c.can_fn.call(null))):
		return
	var fm := _fm()
	var cr: Dictionary = fm.creature(creature_id(body)) if fm != null else {}
	c.hold_time = hold_seconds(float(cr.get("trust", 0.0)), fear_of(float(body.get("health")), float(body.get("max_health"))))


## One finished hold. Returns the calm_step result ({} when there is nothing to calm).
static func calm(body: Node3D, _player: Node = null) -> Dictionary:
	var fm := _fm()
	if fm == null or not calmable(body):
		return {}
	var sp := String(body.get("species"))
	var cid := creature_id(body)
	if fm.creature(cid).is_empty():
		fm.start_taming(cid, String(SPECIES_MAP[sp]))
	var res: Dictionary = fm.calm_step(cid, fear_of(float(body.get("health")), float(body.get("max_health"))), WorldSim.day)
	Game.say(String(res.get("msg", "")))
	match String(res.get("status", "")):
		"tamed":
			TamedPet.adopt(body, fm, cid)
		"fled":
			var c := Interactable.component_of(body)
			if c != null:
				c.enabled = false
	return res
