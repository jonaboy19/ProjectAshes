extends RefCounted
## Dirty-flagged save containers. Each container is a named serialize function (player, inventory, each realm
## module, region overlays, ...). snapshot() calls serialize ONLY for containers marked dirty since the last
## snapshot and reuses the cached dictionary for the rest, so an autosave tick costs what changed, not the whole
## world. SaveManager skips a focus-loss autosave entirely when nothing is dirty (see save_manager.gd).
##
## var c := SaveContainers.new()
## c.register("inventory", func() -> Dictionary: return inventory.serialize())
## c.mark_dirty("inventory")            # whenever it changes
## var data := c.snapshot()             # {"inventory": {...}, ...}
##
## A container with no cache yet is always serialized (first snapshot is complete). Cached dictionaries are
## handed out by reference: callers stringify them, they must not mutate them.

var _fns := {}
var _cache := {}
var _dirty := {}
## Names serialized by the last snapshot (diagnostics and tests).
var last_rebuilt: Array = []


func register(container: String, fn: Callable) -> void:
	_fns[container] = fn
	_dirty[container] = true


func unregister(container: String) -> void:
	_fns.erase(container)
	_cache.erase(container)
	_dirty.erase(container)


func names() -> Array:
	return _fns.keys()


func mark_dirty(container: String) -> void:
	if _fns.has(container):
		_dirty[container] = true


func mark_all() -> void:
	for k: String in _fns:
		_dirty[k] = true


func is_dirty(container: String) -> bool:
	return bool(_dirty.get(container, false))


func any_dirty() -> bool:
	for k: Variant in _dirty:
		if _dirty[k]:
			return true
	return false


func dirty_names() -> Array:
	var out: Array = []
	for k: String in _fns:
		if _dirty.get(k, false):
			out.append(k)
	return out


func snapshot() -> Dictionary:
	last_rebuilt = []
	var out := {}
	for k: String in _fns:
		if _dirty.get(k, true) or not _cache.has(k):
			var v: Variant = (_fns[k] as Callable).call()
			_cache[k] = v if v is Dictionary else {}
			_dirty[k] = false
			last_rebuilt.append(k)
		out[k] = _cache[k]
	return out
