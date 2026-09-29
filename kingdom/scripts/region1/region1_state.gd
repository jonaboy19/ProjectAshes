class_name Region1State
extends RefCounted
## Static registry of Region 1 save providers (hook H2 in Life.snapshot/restore) and of
## the live sims the Region1Root ticks. Nothing here needs a scene tree.
##
## A module registers once, when it is created:
##     Region1State.register(&"wardlines", snapshot_cb, restore_cb, 1, migrate_cb)
## or, for a `Region1Sim`, just `Region1State.register_sim(sim)`.
##
## Save shape (JSON-safe, stored under the key "region1" of Life's snapshot):
##     {"version": 1, "modules": {"wardlines": {"v": 1, "data": {...}}, ...}}
## - Data for modules that are not registered (yet) is kept verbatim and written back, so
##   an old build or a not-yet-merged package never destroys another module's save data.
##   If such a module registers later, it receives its data at that moment.
## - A registered module absent from the save gets `restore({})` = "reset to defaults".
## - A save older than the module's `version` is upgraded one step at a time through
##   `migrate_cb(from_version, data) -> data`. Newer saves are passed through best-effort.

const SAVE_VERSION := 1

static var _providers: Dictionary = {}   # StringName -> {snapshot, restore, version, migrate}
static var _sims: Dictionary = {}        # StringName -> Region1Sim
static var _orphans: Dictionary = {}     # String -> {"v": int, "data": Dictionary}, kept verbatim
## Bumped by every restore(): the root re-anchors its clock so a loaded game does not
## fast-forward the sims by the day difference.
static var restore_serial := 0


static func register(mod: StringName, snapshot_cb: Callable, restore_cb: Callable,
		version: int = 1, migrate_cb: Callable = Callable()) -> void:
	_providers[mod] = {"snapshot": snapshot_cb, "restore": restore_cb,
		"version": version, "migrate": migrate_cb}
	var k := String(mod)
	if _orphans.has(k):   # saved data was waiting for this module
		var entry: Dictionary = _orphans[k]
		_orphans.erase(k)
		_apply(mod, entry)


## Register a sim for both ticking and saving. Replaces a previous sim of the same name.
static func register_sim(s: Region1Sim) -> void:
	_sims[s.module_name] = s
	register(s.module_name, s.serialize, s.deserialize, s.state_version, s.migrate)


static func unregister(mod: StringName) -> void:
	_providers.erase(mod)
	_sims.erase(mod)


static func has(mod: StringName) -> bool:
	return _providers.has(mod)


static func sim(mod: StringName) -> Region1Sim:
	return _sims.get(mod) as Region1Sim


static func sims() -> Dictionary:
	return _sims


static func modules() -> Array:
	var a := _providers.keys()
	a.sort()
	return a


## Forget everything (tests, new game). Orphans go too.
static func clear() -> void:
	_providers.clear()
	_sims.clear()
	_orphans.clear()


static func snapshot() -> Dictionary:
	var mods: Dictionary = _orphans.duplicate(true)
	for mod: StringName in _providers:
		var p: Dictionary = _providers[mod]
		var cb: Callable = p["snapshot"]
		if not cb.is_valid():
			continue   # its owner was freed: skip rather than crash the save
		mods[String(mod)] = {"v": int(p["version"]), "data": cb.call()}
	return {"version": SAVE_VERSION, "modules": mods}


static func restore(d: Dictionary) -> void:
	restore_serial += 1
	var saved: Dictionary = d.get("modules", {}) if d else {}
	_orphans.clear()
	for k in saved:
		if not _providers.has(StringName(k)):
			_orphans[String(k)] = saved[k]
	for mod: StringName in _providers:
		var cb: Callable = _providers[mod]["restore"]
		if not cb.is_valid():
			continue
		var entry: Dictionary = saved.get(String(mod), {})
		if entry.is_empty():
			cb.call({})
		else:
			_apply(mod, entry)


static func _apply(mod: StringName, entry: Dictionary) -> void:
	var p: Dictionary = _providers[mod]
	var cb: Callable = p["restore"]
	if not cb.is_valid():
		return
	var v := int(entry.get("v", 1))
	var data: Dictionary = entry.get("data", {})
	var target := int(p["version"])
	var mig: Callable = p["migrate"]
	while v < target:
		if mig.is_valid():
			data = mig.call(v, data)
		v += 1
	cb.call(data)
