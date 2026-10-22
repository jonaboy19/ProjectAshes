extends RefCounted
## Budgeted pose-volume validation over an immutable candidate snapshot.
## Host must revalidate world/support version before commit. Never advances actor.
const Clearance = preload("res://traversal_pose_clearance.gd")
var _samples: Array = []
var _probes: Array = []
var _alignment := Transform3D.IDENTITY
var _exclude: Array[RID] = []
var _mask := 1
var _frame := 0
var _probe := 0
var active := false
var result: Dictionary = {}

func begin(samples: Array, probes: Array, alignment: Transform3D, exclude: Array[RID] = [], mask := 1) -> bool:
	if active or samples.is_empty() or probes.is_empty() or samples.size() > 180 or probes.size() > 16:
		return false
	for sample: Variant in samples:
		if not sample is Dictionary or not sample.get("body_points") is Dictionary:
			return false
	for probe: Variant in probes:
		if not probe is Array or probe.size() != 3 or not probe[0] is String or not probe[1] is String:
			return false
		if not (probe[2] is float or probe[2] is int):
			return false
		if not is_finite(float(probe[2])) or float(probe[2]) <= 0.0:
			return false
	_samples = samples.duplicate(true)
	_probes = probes.duplicate(true)
	_alignment = alignment
	_exclude = exclude.duplicate()
	_mask = mask
	_frame = 0
	_probe = 0
	active = true
	result = {"status": "pending", "queries": 0}
	return true

func step(space: PhysicsDirectSpaceState3D, budget := 16) -> Dictionary:
	if not active:
		return result.duplicate(true)
	var helper = Clearance.new()
	var used := 0
	while active and used < clampi(budget, 1, 32):
		var probe: Array = _probes[_probe]
		var query = helper.segment_query(_samples[_frame], probe[0], probe[1], float(probe[2]))
		used += 1
		if query == null:
			active = false
			result.status = "invalid_pose"
			result.frame = _frame
			result.segment = "%s>%s" % [probe[0], probe[1]]
			break
		query.transform = _alignment * query.transform
		query.exclude = _exclude
		query.collision_mask = _mask
		result.queries = int(result.queries) + 1
		if not space.intersect_shape(query, 1).is_empty():
			active = false
			result.status = "blocked"
			result.frame = _frame
			result.segment = "%s>%s" % [probe[0], probe[1]]
			break
		_probe += 1
		if _probe == _probes.size():
			_probe = 0
			_frame += 1
			if _frame == _samples.size():
				active = false
				result.status = "sampled_clear"
	# 'sampled_clear' is deliberately not commit approval: rotation sweeps,
	# full standing restore and host/world revalidation remain mandatory.
	var output := result.duplicate(true)
	output["queries_this_step"] = used
	return output

func cancel() -> void:
	active = false
	_samples.clear()
	_probes.clear()
	result = {"status": "cancelled", "queries": int(result.get("queries", 0))}
