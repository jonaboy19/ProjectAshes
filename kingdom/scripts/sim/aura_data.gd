extends RefCounted
## AR-1: loader for kingdom/data/aura/*.json. Cached per file; a missing or broken file yields {} so callers use their defaults.

const DIR := "res://data/aura/"
static var _cache: Dictionary = {}


static func table(name: String) -> Dictionary:
	if _cache.has(name):
		return _cache[name]
	var out: Dictionary = {}
	var path := DIR + name + ".json"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				out = v
	_cache[name] = out
	return out


static func reload() -> void:
	_cache.clear()


static func curve() -> Dictionary:
	return table("aura_curve")
