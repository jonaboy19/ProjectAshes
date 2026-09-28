extends RefCounted
## Attack tokens: shared close-attack slots per target, so a pack or a camp takes
## turns instead of every body biting at once (docs/concepts/
## COMBAT_PRESSURE_AND_READABILITY.md). Enemies that are fighting a target call
## engage() every think; only slot holders may close in and strike, the rest
## circle or hold at range. Slots lapse on their own if a holder forgets them, and
## a fresh slot is never handed out within STAGGER of the last one, so attack
## starts arrive one after another. Static state, preloaded (no class_name).
##
## Cap: 1 slot for a lone attacker, 2 while up to four are engaged, 3 beyond that
## (the 7-goblin warren). Callers may lower it further (wolves pass 2).

const HOLD_TIME := 4.0        # seconds before an unreleased slot lapses
const ENGAGED_TIME := 1.5     # an engage() mark lasts this long
const STAGGER := 0.6          # minimum seconds between two grants on one target
const STRIKE_GAP := 0.45      # minimum seconds between two swings starting on one target

static var _slots := {}       # target id -> {attacker id: expires at}
static var _engaged := {}     # target id -> {attacker id: expires at}
static var _last_grant := {}  # target id -> time of the last grant
static var _last_strike := {} # target id -> time the last swing started


static func _now() -> float:
	return Time.get_ticks_msec() * 0.001


static func _prune(table: Dictionary, target_id: int, now: float) -> Dictionary:
	var entry: Dictionary = table.get(target_id, {})
	for id in entry.keys():
		if float(entry[id]) < now or not is_instance_id_valid(id):
			entry.erase(id)
	if entry.is_empty():
		table.erase(target_id)
	else:
		table[target_id] = entry
	return entry


## Marks `attacker` as fighting `target` (counts toward the slot cap).
static func engage(attacker: Object, target: Object) -> void:
	if attacker == null or target == null:
		return
	var tid := target.get_instance_id()
	var entry: Dictionary = _engaged.get(tid, {})
	entry[attacker.get_instance_id()] = _now() + ENGAGED_TIME
	_engaged[tid] = entry


static func engaged_count(target: Object) -> int:
	if target == null:
		return 0
	return _prune(_engaged, target.get_instance_id(), _now()).size()


static func cap_for(engaged: int, max_cap := 3) -> int:
	var cap := 1 if engaged <= 1 else (2 if engaged <= 4 else 3)
	return clampi(cap, 1, max_cap)


## True if `attacker` holds (or has just been granted) a slot on `target`.
static func request(attacker: Object, target: Object, max_cap := 3) -> bool:
	if attacker == null or target == null:
		return false
	var now := _now()
	var tid := target.get_instance_id()
	var aid := attacker.get_instance_id()
	var slots := _prune(_slots, tid, now)
	if slots.has(aid):
		return true
	var cap := cap_for(maxi(engaged_count(target), 1), max_cap)
	if slots.size() >= cap or now - float(_last_grant.get(tid, -100.0)) < STAGGER:
		return false
	slots[aid] = now + HOLD_TIME
	_slots[tid] = slots
	_last_grant[tid] = now
	return true


## A slot holder asks this right before winding up, so two holders never start
## their swings on the same beat. True claims the beat.
static func try_strike(target: Object) -> bool:
	if target == null:
		return false
	var now := _now()
	var tid := target.get_instance_id()
	if now - float(_last_strike.get(tid, -100.0)) < STRIKE_GAP:
		return false
	_last_strike[tid] = now
	return true


static func holds(attacker: Object, target: Object) -> bool:
	if attacker == null or target == null:
		return false
	return _prune(_slots, target.get_instance_id(), _now()).has(attacker.get_instance_id())


## Gives up every slot and engage mark `attacker` has (hit reaction, death,
## yield, flee, lost target, finished turn).
static func release(attacker: Object) -> void:
	if attacker == null:
		return
	var aid := attacker.get_instance_id()
	for table: Dictionary in [_slots, _engaged]:
		for tid in table.keys():
			var entry: Dictionary = table[tid]
			entry.erase(aid)
			if entry.is_empty():
				table.erase(tid)


## Ends only the slot (the attacker is still engaged and will circle).
static func yield_slot(attacker: Object) -> void:
	if attacker == null:
		return
	var aid := attacker.get_instance_id()
	for tid in _slots.keys():
		var entry: Dictionary = _slots[tid]
		entry.erase(aid)
		if entry.is_empty():
			_slots.erase(tid)


## Contact test at the impact beat: target still valid and alive, within
## `reach`, in front of the attacker (about 70 degrees either side of its +Z
## facing) and not behind world geometry. One short ray, only when a blow lands.
static func can_hit(attacker: Node3D, target: Node3D, reach: float, world_mask := 1) -> bool:
	if attacker == null or not is_instance_valid(target) or not target.is_inside_tree() or not attacker.is_inside_tree():
		return false
	if bool(target.get("dead")):
		return false
	var to := target.global_position - attacker.global_position
	if to.length() > reach:
		return false
	var flat := Vector3(to.x, 0.0, to.z)
	if flat.length() > 0.35:
		var fwd := attacker.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.001 and fwd.normalized().dot(flat.normalized()) < 0.35:
			return false
	var from := attacker.global_position + Vector3.UP * 0.7
	var dest := target.global_position + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, dest, world_mask)
	if attacker is CollisionObject3D:
		q.exclude = [(attacker as CollisionObject3D).get_rid()]
	var hit := attacker.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == target


static func clear() -> void:
	_slots.clear()
	_engaged.clear()
	_last_grant.clear()
	_last_strike.clear()
