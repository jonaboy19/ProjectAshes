extends RefCounted
## Optional adapter from region-simulation `event(kind: StringName, data)` signals
## to the shared journal. Dependencies are injected so this file adds no autoload
## or region-simulation preload coupling. Owners should call dispose() at teardown.

const MAX_BINDINGS := 128
const MAX_SYNC_SCAN := 256
const MAX_MODULE_LENGTH := 24
const MAX_KIND_LENGTH := 30

var _journal: Object
var _clock: Callable
var _bindings: Dictionary = {} # module -> {WeakRef, connection Callable, generation}
var _generation := 0
var _accepted := 0
var _rejected := 0


func configure(journal: Object, absolute_hours: Callable) -> void:
	unbind_all()
	_journal = journal if journal != null and journal.has_method("publish") else null
	_clock = absolute_hours if absolute_hours.is_valid() else Callable()


func bind_sim(module_ref: Variant, sim: Object) -> bool:
	_prune_dead_bindings()
	if not (module_ref is String or module_ref is StringName):
		return false
	var module := String(module_ref).strip_edges().to_lower()
	if not _valid_name(module, MAX_MODULE_LENGTH) or sim == null or not is_instance_valid(sim):
		return false
	if not sim.has_signal("event"):
		return false
	if _bindings.has(module):
		var prior: Dictionary = _bindings[module]
		var prior_sim: Object = (prior["sim_ref"] as WeakRef).get_ref()
		if prior_sim == sim:
			return true
		_unbind_module(module)
	if _bindings.size() >= MAX_BINDINGS:
		return false
	_generation += 1
	var callback := Callable(self, "_on_sim_event").bind(module, _generation)
	if not sim.is_connected("event", callback):
		var connection_error: Error = sim.connect("event", callback)
		if connection_error != OK:
			return false
	_bindings[module] = {"sim_ref": weakref(sim), "callback": callback, "generation": _generation}
	return true


func unbind_sim(module_ref: Variant) -> void:
	if module_ref is String or module_ref is StringName:
		_unbind_module(String(module_ref).strip_edges().to_lower())


## Reconcile one sim per module. Removed/replaced sims are disconnected by identity.
func sync(registry: Dictionary) -> void:
	var desired: Dictionary = {}
	var scanned := 0
	var scan_truncated := registry.size() > MAX_SYNC_SCAN
	for key: Variant in registry:
		if scanned >= MAX_SYNC_SCAN:
			scan_truncated = true
			break
		scanned += 1
		if (key is String or key is StringName) and registry[key] is Object and is_instance_valid(registry[key]):
			var module := String(key).strip_edges().to_lower()
			if _valid_name(module, MAX_MODULE_LENGTH) and (registry[key] as Object).has_signal("event"):
				desired[module] = registry[key]
	if not scan_truncated:
		for module: String in _bindings.keys():
			var old: Dictionary = _bindings[module]
			var old_sim: Object = (old["sim_ref"] as WeakRef).get_ref()
			if not desired.has(module) or old_sim != desired[module]:
				_unbind_module(module)
	for module: String in desired:
		# bind_sim is idempotent and also replaces a changed live instance when
		# a truncated registry prevents the complete removal pass above.
		bind_sim(module, desired[module])


func metrics() -> Dictionary:
	_prune_dead_bindings()
	return {"bindings": _bindings.size(), "accepted": _accepted, "rejected": _rejected}


func reset() -> void:
	unbind_all()
	_accepted = 0
	_rejected = 0


## Disconnect signal sources before releasing an owning scene/service.
func dispose() -> void:
	reset()
	_journal = null
	_clock = Callable()


func unbind_all() -> void:
	for module: String in _bindings.keys():
		_unbind_module(module)


func _on_sim_event(kind_value: Variant, data_value: Variant, module: String, generation: int) -> void:
	if not _bindings.has(module) or int(_bindings[module].get("generation", -1)) != generation:
		return # A queued signal from a replaced binding must not cross generations.
	if not (kind_value is String or kind_value is StringName) or not _valid_name(String(kind_value).to_lower(), MAX_KIND_LENGTH):
		_rejected += 1
		return
	if (not data_value is Dictionary or _journal == null or not is_instance_valid(_journal)
			or not _journal.has_method("publish") or not _clock.is_valid()):
		_rejected += 1
		return
	var module_sim: Object = (_bindings[module]["sim_ref"] as WeakRef).get_ref()
	if module_sim == null or not is_instance_valid(module_sim):
		_rejected += 1
		return
	var raw_data: Dictionary = data_value
	if raw_data.size() > 511:
		_rejected += 1
		return
	var actor_ref := ""
	var target_ref := ""
	if raw_data.has("actor_ref"):
		if not raw_data["actor_ref"] is String:
			_rejected += 1
			return
		actor_ref = String(raw_data["actor_ref"])
	if raw_data.has("target_ref"):
		if not raw_data["target_ref"] is String:
			_rejected += 1
			return
		target_ref = String(raw_data["target_ref"])
	if not _has_property(module_sim, "day_f"):
		_rejected += 1
		return
	var day_value: Variant = module_sim.get("day_f")
	if not (day_value is int or day_value is float) or not is_finite(float(day_value)):
		_rejected += 1
		return
	var hour_value: Variant = _clock.call()
	if not (hour_value is int or hour_value is float) or not is_finite(float(hour_value)):
		_rejected += 1
		return
	var payload: Dictionary = {}
	for key: Variant in raw_data:
		if not key is String:
			_rejected += 1
			return
		if key != "actor_ref" and key != "target_ref" and key != "region_day_f":
			payload[key] = raw_data[key]
	payload["region_day_f"] = float(day_value)
	var event_type := "region1.%s.%s" % [module, String(kind_value).to_lower()]
	if event_type.length() > 64:
		_rejected += 1
		return
	var result: Variant = _journal.call("publish", event_type, actor_ref, target_ref,
		float(hour_value), payload)
	if result is Dictionary and bool(result.get("ok", false)):
		_accepted += 1
	else:
		_rejected += 1


func _unbind_module(module: String) -> void:
	if not _bindings.has(module):
		return
	var binding: Dictionary = _bindings[module]
	var sim: Object = (binding["sim_ref"] as WeakRef).get_ref()
	var callback: Callable = binding["callback"]
	if sim != null and is_instance_valid(sim) and sim.has_signal("event") and sim.is_connected("event", callback):
		sim.disconnect("event", callback)
	_bindings.erase(module)


func _prune_dead_bindings() -> void:
	for module: String in _bindings.keys():
		var binding: Dictionary = _bindings[module]
		var sim: Object = (binding["sim_ref"] as WeakRef).get_ref()
		if sim == null or not is_instance_valid(sim):
			_bindings.erase(module)


func _valid_name(value: String, max_length: int) -> bool:
	if value.is_empty() or value.length() > max_length:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 122) or code == 95):
			return false
	return true


func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false
