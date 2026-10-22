class_name RAStationIdentity
extends RefCounted
## Runtime identity for craft stations. Stable refs describe a layout slot;
## generations distinguish successive live owners of that slot.

signal descriptor_invalidated(ref: String, generation: int)

var _serial := 0
var _owners: Dictionary = {}       # owner ref -> {instance_id, generation}
var _records: Dictionary = {}      # descriptor ref -> {owner_ref, owner_id, generation}


func register_station(owner: Object, owner_ref: String, kind: String, slot: int) -> Dictionary:
	var stable_owner_ref := owner_ref
	if stable_owner_ref.is_empty():
		stable_owner_ref = "ephemeral:%d" % owner.get_instance_id() if owner != null else "adhoc:%d" % (_serial + 1)
	var owner_id := owner.get_instance_id() if owner != null else 0
	var owner_record: Dictionary = _owners.get(stable_owner_ref, {})
	if not owner_record.is_empty():
		var previous_id := int(owner_record["instance_id"])
		var previous_generation := int(owner_record["generation"])
		if previous_id != owner_id and previous_id != 0 and is_instance_id_valid(previous_id):
			return {"ok": false, "error": "owner_conflict", "ref": "", "generation": 0}
		if previous_id == owner_id:
			var current_ref := _station_ref(stable_owner_ref, kind, slot)
			var existing: Dictionary = _records.get(current_ref, {})
			if not existing.is_empty() and int(existing.get("generation", -1)) == previous_generation:
				return {"ok": true, "error": "", "ref": current_ref, "generation": previous_generation}
			return _store_descriptor(owner, stable_owner_ref, owner_id, previous_generation, kind, slot)
		_invalidate_owner(stable_owner_ref, previous_id, previous_generation)
	_serial += 1
	return _store_descriptor(owner, stable_owner_ref, owner_id, _serial, kind, slot)


func _store_descriptor(owner: Object, owner_ref: String, owner_id: int, generation: int,
		kind: String, slot: int) -> Dictionary:
	var ref := _station_ref(owner_ref, kind, slot)
	_owners[owner_ref] = {"instance_id": owner_id, "generation": generation}
	_records[ref] = {"owner_ref": owner_ref, "owner_id": owner_id, "generation": generation}
	if owner is Node and not (owner as Node).tree_exiting.is_connected(_on_owner_tree_exiting.bind(owner_ref, owner_id, generation)):
		(owner as Node).tree_exiting.connect(_on_owner_tree_exiting.bind(owner_ref, owner_id, generation), CONNECT_ONE_SHOT)
	return {"ok": true, "error": "", "ref": ref, "generation": generation}


func _station_ref(owner_ref: String, kind: String, slot: int) -> String:
	return "%s:%s:%d" % [owner_ref, kind, slot]


func is_live(ref: String, generation: int) -> bool:
	if not _records.has(ref):
		return false
	var record: Dictionary = _records[ref]
	if int(record.get("generation", -1)) != generation:
		return false
	var owner_id := int(record.get("owner_id", 0))
	if owner_id != 0 and not is_instance_id_valid(owner_id):
		_invalidate_owner(String(record["owner_ref"]), owner_id, generation)
		return false
	return true


func invalidate_all() -> void:
	var owners: Array = _owners.keys()
	for owner_ref: String in owners:
		var record: Dictionary = _owners[owner_ref]
		_invalidate_owner(owner_ref, int(record["instance_id"]), int(record["generation"]))
	_owners.clear()
	_records.clear()


func _on_owner_tree_exiting(owner_ref: String, owner_id: int, generation: int) -> void:
	_invalidate_owner(owner_ref, owner_id, generation)


func _invalidate_owner(owner_ref: String, owner_id: int, generation: int) -> void:
	var owner_record: Dictionary = _owners.get(owner_ref, {})
	if not owner_record.is_empty() and int(owner_record.get("instance_id", -1)) == owner_id \
			and int(owner_record.get("generation", -1)) == generation:
		_owners.erase(owner_ref)
	for ref: String in _records.keys():
		var record: Dictionary = _records[ref]
		if String(record.get("owner_ref", "")) == owner_ref \
				and int(record.get("owner_id", -1)) == owner_id \
				and int(record.get("generation", -1)) == generation:
			_records.erase(ref)
			descriptor_invalidated.emit(ref, generation)
