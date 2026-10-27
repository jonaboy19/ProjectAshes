extends RefCounted
## One queue for loading scenes/resources without a hitch (WP-05). Preload, no class_name:
##   const ThreadedLoader := preload("res://scripts/core/threaded_loader.gd")
##   ThreadedLoader.request("res://scenes/interiors/house_interior.tscn", func(path, res): ...)
##
## Backend-agnostic: callers only see request()/request_many()/defer() and a callback on the main thread.
##   MAIN_BUDGETED  (default) the load itself runs on the main thread, at most one resource per poll and only while the
##                  frame budget is not spent (polling stops after BUDGET_MS). A 40 ms scene is still 40 ms, but it is
##                  its own frame, behind a door swing / loading veil, never stacked with the room's _ready.
##   THREADED       ResourceLoader.load_threaded_request(), polled with load_threaded_get_status(). ONLY for resources on
##                  the safe list (no meshes / materials): docs/qa/stability.md, the random 0xC0000005 crash was a worker
##                  thread loading a mesh while the main thread created materials. Anything else falls back to MAIN_BUDGETED
##                  even when THREADED is selected, so the flag cannot reintroduce that crash.
## Scenes (PackedScene) are cached through Assets.scene(), so a second request is answered on the next poll for free.
## `load_now()` is the one deliberate blocking call, for tests and tools, never for a transition.

enum Backend { MAIN_BUDGETED, THREADED }

const BUDGET_MS := 8.0
## Extensions that carry no mesh/material and may use a worker thread when Backend.THREADED is selected.
const THREAD_SAFE_EXT := ["ogg", "wav", "mp3", "json", "res_audio", "txt", "csv"]

static var backend := Backend.MAIN_BUDGETED
static var _queue: Array = []          # [{path, type, cbs: Array[Callable], threaded: bool, t0: int}]
static var _by_path: Dictionary = {}   # path -> entry
static var _deferred: Array = []       # Callables run within the budget
static var _hooked := false
static var stats := {"requests": 0, "completed": 0, "cache_hits": 0, "threaded": 0, "main": 0, "max_step_ms": 0.0, "blocking": 0}


## Calls cb(path, resource_or_null) on the main thread once `path` is loaded. Never blocks the caller.
static func request(path: String, cb: Callable = Callable(), type_hint := "") -> void:
	stats["requests"] += 1
	if _by_path.has(path):
		if cb.is_valid():
			(_by_path[path]["cbs"] as Array).append(cb)
		return
	var e := {"path": path, "type": type_hint, "cbs": [cb] if cb.is_valid() else [], "threaded": false, "t0": Time.get_ticks_msec(), "cached": false}
	if _cached(path) != null:
		e["cached"] = true
	elif backend == Backend.THREADED and _thread_safe(path):
		if ResourceLoader.load_threaded_request(path, type_hint) == OK:
			e["threaded"] = true
	_by_path[path] = e
	_queue.append(e)
	_hook()


## cb(results: Dictionary path -> resource) once every path is in.
static func request_many(paths: Array, cb: Callable) -> void:
	var left := {}
	var out := {}
	for p: Variant in paths:
		left[String(p)] = true
	if left.is_empty():
		cb.call(out)
		return
	for p: String in left.keys():
		request(p, func(path: String, res: Variant) -> void:
			out[path] = res
			left.erase(path)
			if left.is_empty():
				cb.call(out))


## Runs `c` in a later poll, inside the frame budget (for work that is not a load, e.g. building a floor).
static func defer(c: Callable) -> void:
	_deferred.append(c)
	_hook()


## True when `path` can be handed out right now without any load.
static func is_ready(path: String) -> bool:
	return _cached(path) != null


## The resource if it is already cached, else null. Never loads.
static func cached(path: String) -> Variant:
	return _cached(path)


static func pending() -> int:
	return _queue.size() + _deferred.size()


## Advance the queue: at most BUDGET_MS (checked between items, one load per call minimum). Returns items finished.
static func poll(budget_ms := BUDGET_MS) -> int:
	var t0 := Time.get_ticks_usec()
	var done := 0
	while not _queue.is_empty() or not _deferred.is_empty():
		var step0 := Time.get_ticks_usec()
		if not _queue.is_empty():
			var e: Dictionary = _queue[0]
			if bool(e["threaded"]):
				var st := ResourceLoader.load_threaded_get_status(e["path"])
				if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					# look at the others instead of waiting on this one
					_queue.push_back(_queue.pop_front())
					if _all_in_progress():
						break
					continue
				var res: Variant = ResourceLoader.load_threaded_get(e["path"]) if st == ResourceLoader.THREAD_LOAD_LOADED else null
				stats["threaded"] += 1
				_finish(e, res)
			else:
				var res2: Variant = _cached(e["path"])
				if res2 == null:
					res2 = _main_load(e["path"], e["type"])
					stats["main"] += 1
				else:
					stats["cache_hits"] += 1
				_finish(e, res2)
			_queue.erase(e)
		else:
			var c: Callable = _deferred.pop_front()
			if c.is_valid():
				c.call()
		done += 1
		stats["max_step_ms"] = maxf(float(stats["max_step_ms"]), (Time.get_ticks_usec() - step0) / 1000.0)
		if (Time.get_ticks_usec() - t0) / 1000.0 >= budget_ms:
			break
	return done


## The deliberate blocking load (tests, tools, boot). Counted in stats["blocking"] so a transition using it shows up.
static func load_now(path: String, type_hint := "") -> Variant:
	stats["blocking"] += 1
	var c: Variant = _cached(path)
	return c if c != null else _main_load(path, type_hint)


static func reset() -> void:
	_queue.clear()
	_by_path.clear()
	_deferred.clear()
	backend = Backend.MAIN_BUDGETED
	stats = {"requests": 0, "completed": 0, "cache_hits": 0, "threaded": 0, "main": 0, "max_step_ms": 0.0, "blocking": 0}


# --- internals ----------------------------------------------------------------------------------------------------

static func _all_in_progress() -> bool:
	for e: Dictionary in _queue:
		if not bool(e["threaded"]) or ResourceLoader.load_threaded_get_status(e["path"]) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
	return _deferred.is_empty()


static func _thread_safe(path: String) -> bool:
	return String(path.get_extension()).to_lower() in THREAD_SAFE_EXT


static func _cached(path: String) -> Variant:
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		var s: Variant = _assets().get("_scenes")
		if s is Dictionary and (s as Dictionary).has(path):
			return (s as Dictionary)[path]
	if ResourceLoader.has_cached(path):
		return ResourceLoader.load(path)     # already in memory: returns the cached reference, no disk read
	return null


static func _assets() -> Variant:
	return preload("res://scripts/world/assets.gd")


static func _main_load(path: String, type_hint: String) -> Variant:
	if path.ends_with(".tscn") or path.ends_with(".scn"):
		return (_assets() as GDScript).call("scene", path)       # cached for the session
	return ResourceLoader.load(path, type_hint)


static func _finish(e: Dictionary, res: Variant) -> void:
	_by_path.erase(e["path"])
	stats["completed"] += 1
	if res == null:
		push_warning("ThreadedLoader: cannot load %s" % e["path"])
	for c: Callable in e["cbs"]:
		if c.is_valid():
			c.call(e["path"], res)


static func _hook() -> void:
	if _hooked:
		return
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		(loop as SceneTree).process_frame.connect(func() -> void: poll())
		_hooked = true
