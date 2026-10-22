class_name LivingEvents
extends RefCounted
## Tiny world event bus for glances and reactions: an anvil clang, a cart rattling by, a shout, a door, the
## player sprinting past. Ring buffer of the last 32 events; each lives `ttl` seconds. Cost: emit O(1),
## nearest() scans 32 entries (LifeAmbience calls it once per think tick per person).
##
##   LivingEvents.emit("clang", anvil_pos, 14.0)
##   var e := LivingEvents.nearest(my_pos, last_seen_serial)   # {} or {kind, pos, radius, serial, age}

const SIZE := 32
static var _buf: Array = []
static var _serial := 0


static func emit(kind: String, pos: Vector3, radius := 12.0, ttl := 1.5) -> void:
	if _buf.size() < SIZE:
		_buf.resize(SIZE)
	_serial += 1
	_buf[_serial % SIZE] = {"kind": kind, "pos": pos, "radius": radius, "serial": _serial,
		"t": Time.get_ticks_msec() / 1000.0, "ttl": ttl}


## The newest live event within its radius of pos that is newer than `after` ({} when none).
static func nearest(pos: Vector3, after := -1) -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	var best := {}
	for e in _buf:
		if e == null:
			continue
		var d: Dictionary = e
		if int(d["serial"]) <= after or now - float(d["t"]) > float(d["ttl"]):
			continue
		var r := float(d["radius"])
		if (d["pos"] as Vector3).distance_squared_to(pos) > r * r:
			continue
		if best.is_empty() or int(d["serial"]) > int(best["serial"]):
			best = d
	return best


static func clear() -> void:
	_buf.clear()
