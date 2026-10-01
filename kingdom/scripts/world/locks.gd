extends RefCounted
## Locks as data, not nodes: `{lock_id, key_id, level 0..5, locked}` shared by doors, chests and gates, so one key
## family works for every object that names the same lock_id. Keys are items (an inventory id equal to the lock's
## key_id); households hold their lot's key, guards a master key for public buildings.
## The locked flag persists through WorldState under "lock/<lock_id>" (delta from the lock's default).
## Static registry, pure data. Design: docs/research/MINING_PERCEPTION_INTERACTION.md 2.7 and 4.6.

const WorldState := preload("res://scripts/world/world_state.gd")

const MAX_LEVEL := 5
const KEY_ITEM_PREFIX := "key_"

## lock_id -> {key_id: String, level: int, locked: bool, default_locked: bool, public: bool, attempts: int}
static var _locks := {}


static func reset() -> void:
	_locks.clear()


## Declare a lock (idempotent). The saved locked flag, when present, wins over `locked` (applied silently).
static func define(lock_id: String, key_id := "", level := 1, locked := true, is_public := false, ws: RefCounted = null) -> void:
	if lock_id == "":
		return
	var store := ws if ws != null else WorldState.shared()
	var def := {"locked": locked}
	var st: Dictionary = store.call("get_state", "lock/" + lock_id, def)
	_locks[lock_id] = {"key_id": key_id if key_id != "" else lock_id, "level": clampi(level, 0, MAX_LEVEL),
		"locked": bool(st["locked"]), "default_locked": locked, "public": is_public, "attempts": 0}


static func has_lock(lock_id: String) -> bool:
	return _locks.has(lock_id)


static func is_locked(lock_id: String) -> bool:
	return _locks.has(lock_id) and bool((_locks[lock_id] as Dictionary)["locked"])


static func key_of(lock_id: String) -> String:
	return String((_locks.get(lock_id, {}) as Dictionary).get("key_id", ""))


static func level_of(lock_id: String) -> int:
	return int((_locks.get(lock_id, {}) as Dictionary).get("level", 0))


static func set_locked(lock_id: String, on: bool, persist := true, ws: RefCounted = null) -> void:
	if not _locks.has(lock_id):
		return
	var l: Dictionary = _locks[lock_id]
	l["locked"] = on
	if persist:
		var store := ws if ws != null else WorldState.shared()
		store.call("set_state", "lock/" + lock_id, {"locked": on}, {"locked": bool(l["default_locked"])})


## Who is trying: carried key ids, master key (guards, for `public` locks only), lockpick tool, skill 0..10.
static func holder(keys: Array = [], master := false, lockpick := false, skill := 0.0) -> Dictionary:
	return {"keys": keys, "master": master, "lockpick": lockpick, "skill": skill}


static func has_key(h: Dictionary, lock_id: String) -> bool:
	if not _locks.has(lock_id):
		return true
	var l: Dictionary = _locks[lock_id]
	if bool(h.get("master", false)) and bool(l["public"]):
		return true
	return (h.get("keys", []) as Array).has(String(l["key_id"]))


## Unlock with a key (no noise). Returns true when the lock is open afterwards.
static func unlock(lock_id: String, h: Dictionary) -> bool:
	if not _locks.has(lock_id):
		return true
	if not is_locked(lock_id):
		return true
	if not has_key(h, lock_id):
		return false
	set_locked(lock_id, false)
	return true


## Chance 0..1 that one lockpick attempt works: falls with level, rises with skill.
static func pick_chance(level: int, skill: float) -> float:
	return clampf(0.9 - 0.16 * float(level) + 0.05 * skill, 0.04, 0.95)


## One deterministic pick attempt (hash of lock id and attempt number, no randf). Level 0 always opens.
## Returns {ok, noise: Perception.Sound.LOCKPICK, wear: 0..1 tool wear on failure}.
static func try_pick(lock_id: String, h: Dictionary) -> Dictionary:
	if not _locks.has(lock_id) or not is_locked(lock_id):
		return {"ok": true, "noise": -1, "wear": 0.0}
	if not bool(h.get("lockpick", false)):
		return {"ok": false, "noise": -1, "wear": 0.0, "reason": "You need a lockpick."}
	var l: Dictionary = _locks[lock_id]
	var attempt := int(l["attempts"])
	l["attempts"] = attempt + 1
	var chance := pick_chance(int(l["level"]), float(h.get("skill", 0.0)))
	var roll := float(absi(hash([lock_id, attempt])) % 1000) / 1000.0
	var ok := int(l["level"]) == 0 or roll < chance
	if ok:
		set_locked(lock_id, false)
	return {"ok": ok, "noise": 4, "wear": 0.0 if ok else 0.25}


## The player's holder: key items in Life.inventory (ids starting with "key_" or equal to a lock's key_id),
## lockpick = an item "lockpick" in the inventory. Safe without Life (tests): returns an empty holder.
static func player_holder() -> Dictionary:
	var keys: Array = []
	var pick := false
	var loop := Engine.get_main_loop()
	var life: Node = (loop as SceneTree).root.get_node_or_null("Life") if loop is SceneTree else null
	if life != null and "inventory" in life and life.get("inventory") != null:
		var inv: Object = life.get("inventory")
		if inv.has_method("get_items"):
			for it: Variant in inv.call("get_items"):
				var proto: Variant = it.call("get_prototype") if it is Object and (it as Object).has_method("get_prototype") else null
				if proto == null:
					continue
				var pid := String(proto.call("get_prototype_id"))
				if pid.begins_with(KEY_ITEM_PREFIX):
					keys.append(pid)
				elif pid == "lockpick":
					pick = true
	return holder(keys, false, pick, 0.0)
