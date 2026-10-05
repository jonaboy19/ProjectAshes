extends RefCounted
## EffectSet: the timed effects on one actor (burns, slows, buffs, wards...), keyed by `family` with a stacking
## rule per effect (Ryzom-style effect families, own implementation):
##   refresh              same family: keep one entry, restart its timer (never shorten), take the new numbers
##   replace_if_stronger  same family: a stronger magnitude replaces it, equal refreshes, weaker is rejected
##   stack                same family: up to `max_stacks` independent entries (each ticks on its own timer);
##                        beyond the cap the entry with the least time left is refreshed instead
## Entries are plain dictionaries so the set serialises as JSON. Pure data, no scene access, deterministic.
##
## Entry: {family, type, rule, max_stacks, magnitude, duration, left, tick, tick_left, stats, source, tags}
## Types: dot / hot tick `magnitude` damage / healing every `tick` seconds; ward / absorb hold a damage pool in
## `magnitude`; buff / debuff / aura carry `stats` ({"damage_taken": -0.3, ...}); the crowd-control types
## (slow, stun, fear, blind, pull, reveal) only mark a state.
## Tick it from any tier: tick(dt) steps in slices of at most TICK seconds and returns the events.

const TICK := 0.5
const AbilityDef := preload("res://scripts/abilities/ability_def.gd")

var active: Array = []


## Applies one effect row. `eff` needs type; family defaults to the type; magnitude may be derived by the caller.
## -> {action: added|refreshed|replaced|stacked|rejected, stacks: int}
func apply(eff: Dictionary, source := "") -> Dictionary:
	var type := String(eff.get("type", ""))
	var family := String(eff.get("family", type))
	var rule := String(eff.get("rule", AbilityDef.DEFAULT_RULE.get(type, "refresh")))
	var mag := float(eff.get("magnitude", 0.0))
	var dur := float(eff.get("duration", 0.0))
	var entry := {"family": family, "type": type, "rule": rule, "max_stacks": int(eff.get("max_stacks", 1)),
		"magnitude": mag, "duration": dur, "left": dur, "tick": float(eff.get("tick", TICK)),
		"tick_left": float(eff.get("tick", TICK)), "stats": (eff.get("stats", {}) as Dictionary).duplicate(),
		"source": source, "tags": (eff.get("tags", []) as Array).duplicate()}
	var same: Array = []
	for e: Dictionary in active:
		if e["family"] == family:
			same.append(e)
	if same.is_empty():
		active.append(entry)
		return {"action": "added", "stacks": 1}
	match rule:
		"stack":
			var cap := maxi(1, int(entry["max_stacks"]))
			if same.size() < cap:
				active.append(entry)
				return {"action": "stacked", "stacks": same.size() + 1}
			var oldest: Dictionary = same[0]
			for e: Dictionary in same:
				if float(e["left"]) < float(oldest["left"]):
					oldest = e
			_overwrite(oldest, entry)
			return {"action": "refreshed", "stacks": same.size()}
		"replace_if_stronger":
			var cur: Dictionary = same[0]
			if mag > float(cur["magnitude"]) + 0.0001:
				active[active.find(cur)] = entry
				return {"action": "replaced", "stacks": 1}
			if absf(mag - float(cur["magnitude"])) <= 0.0001:
				cur["left"] = maxf(float(cur["left"]), dur)
				cur["duration"] = maxf(float(cur["duration"]), dur)
				return {"action": "refreshed", "stacks": 1}
			return {"action": "rejected", "stacks": 1}
		_:
			_overwrite(same[0], entry, true)
			return {"action": "refreshed", "stacks": 1}


func _overwrite(old: Dictionary, entry: Dictionary, keep_longer := false) -> void:
	var left := maxf(float(old["left"]), float(entry["left"])) if keep_longer else float(entry["left"])
	for k: String in entry:
		old[k] = entry[k]
	old["left"] = left
	old["duration"] = maxf(float(old["duration"]), left) if keep_longer else float(entry["duration"])


## Advances every effect by `dt` seconds. Mirrors the old per-burn timers: the timer runs down, the entry expires
## the moment it reaches zero, otherwise a tick fires every `tick` seconds.
## -> [{kind: "dot"|"hot"|"expire", family, amount: int, source, type}]
func tick(dt: float) -> Array:
	var events: Array = []
	var left := dt
	while left > 0.0001:
		var step := minf(left, TICK)
		left -= step
		for e: Dictionary in active.duplicate():
			if float(e["duration"]) <= 0.0:
				continue                       # permanent until removed (auras, wards without a timer)
			e["left"] = float(e["left"]) - step
			e["tick_left"] = float(e["tick_left"]) - step
			if float(e["left"]) <= 0.0:
				active.erase(e)
				events.append({"kind": "expire", "family": e["family"], "type": e["type"], "amount": 0, "source": e["source"]})
				continue
			if float(e["tick_left"]) <= 0.0:
				e["tick_left"] = float(e["tick"])
				if e["type"] == "dot" or e["type"] == "hot":
					events.append({"kind": String(e["type"]), "family": e["family"], "type": e["type"],
						"amount": maxi(1, int(round(float(e["magnitude"])))), "source": e["source"]})
	return events


# --- queries ---------------------------------------------------------------------

func has(family: String) -> bool:
	for e: Dictionary in active:
		if e["family"] == family:
			return true
	return false


func has_type(type: String) -> bool:
	for e: Dictionary in active:
		if e["type"] == type:
			return true
	return false


func count(family: String) -> int:
	var n := 0
	for e: Dictionary in active:
		if e["family"] == family:
			n += 1
	return n


func families() -> Array:
	var out: Array = []
	for e: Dictionary in active:
		if not out.has(e["family"]):
			out.append(e["family"])
	return out


## Sum of one stat over every effect carrying it ({"speed": -0.2, ...}).
func stat(key: String) -> float:
	var v := 0.0
	for e: Dictionary in active:
		v += float((e["stats"] as Dictionary).get(key, 0.0))
	return v


func is_stunned() -> bool:
	return has_type("stun")


## Move-speed multiplier from slows (the strongest slow counts; magnitude is the slowed fraction, default 0.5).
func speed_factor() -> float:
	var slow := 0.0
	for e: Dictionary in active:
		if e["type"] == "slow":
			slow = maxf(slow, float(e["magnitude"]) if float(e["magnitude"]) > 0.0 else 0.5)
	return clampf(1.0 - slow, 0.1, 1.0) + stat("speed")


## Counters are checked before damage: the damage_taken stat first (floor 10 percent), then wards / absorbs soak
## from their pools. -> {amount: int left to apply, absorbed: int}
func mitigate(amount: float, element := "") -> Dictionary:
	var k := clampf(1.0 + stat("damage_taken"), 0.1, 2.0)
	var left := amount * k
	var soaked := 0.0
	for e: Dictionary in active.duplicate():
		if e["type"] != "ward" and e["type"] != "absorb":
			continue
		var only: Array = e["tags"]
		if not only.is_empty() and element != "" and not only.has(element):
			continue
		var take := minf(left, float(e["magnitude"]))
		e["magnitude"] = float(e["magnitude"]) - take
		left -= take
		soaked += take
		if float(e["magnitude"]) <= 0.001:
			active.erase(e)
	return {"amount": int(round(left)), "absorbed": int(round(soaked))}


func dispel(family: String) -> int:
	var n := 0
	for e: Dictionary in active.duplicate():
		if e["family"] == family:
			active.erase(e)
			n += 1
	return n


func clear() -> void:
	active.clear()


func serialize() -> Array:
	return active.duplicate(true)


func deserialize(rows: Array) -> void:
	active.clear()
	for r: Variant in rows:
		var e: Dictionary = (r as Dictionary).duplicate(true)
		for k: String in ["magnitude", "duration", "left", "tick", "tick_left"]:
			e[k] = float(e.get(k, 0.0))
		e["max_stacks"] = int(e.get("max_stacks", 1))
		e["family"] = String(e.get("family", e.get("type", "")))
		e["type"] = String(e.get("type", ""))
		e["rule"] = String(e.get("rule", "refresh"))
		e["source"] = String(e.get("source", ""))
		e["stats"] = e.get("stats", {})
		e["tags"] = e.get("tags", [])
		active.append(e)
