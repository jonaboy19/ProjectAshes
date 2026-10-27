class_name HazardField
extends RefCounted
## S5 hazard points for NPC steering (docs/plans/NPC_MOTION_RULES.md): puddle and mud decals, campfires, fire incidents, dung.
## Fixed storage like NpcWorld: no allocation after the first use, register / unregister / query are O(MAX).
##
##   var h := HazardField.register(Vector2(x, z), HazardField.Kind.PUDDLE)      # radius defaults per kind, -1 when full
##   HazardField.unregister(h)                                                  # stale handles are ignored
##   var n := HazardField.query(here, reach, HazardField.scratch)               # slot indices into scratch[0..n-1]
##   HazardField.slot_x(i) / slot_z(i) / slot_radius(i) / slot_kind(i)
## A handle is slot | generation << 8, so a handle of a freed slot never unregisters the next occupant.

enum Kind { PUDDLE, MUD, FIRE, DUNG }
const MAX := 64
## Default avoid radius per kind (m): 0.8 to 2.0 per the design table. Fire follows NpcWorld.FIRE_DANGER_NEAR.
const KIND_RADIUS := [0.8, 1.2, 2.0, 0.8]

static var scratch := PackedInt32Array()     # caller buffer for query(): sized MAX on first use
static var _x := PackedFloat32Array()
static var _z := PackedFloat32Array()
static var _r := PackedFloat32Array()
static var _kind := PackedByteArray()
static var _live := PackedByteArray()
static var _gen := PackedInt32Array()
static var _until := PackedFloat64Array()    # 0 = permanent
static var _count := 0


static func _ensure() -> void:
	if _x.size() == MAX:
		return
	_x.resize(MAX)
	_z.resize(MAX)
	_r.resize(MAX)
	_kind.resize(MAX)
	_live.resize(MAX)
	_gen.resize(MAX)
	_until.resize(MAX)
	scratch.resize(MAX)


## Registers a hazard; returns a handle, or -1 when all MAX slots are in use. `radius` < 0 uses the default of the kind.
## `until_s` > 0 makes it expire at that clock time (prune()).
static func register(at: Vector2, kind: int = Kind.PUDDLE, radius := -1.0, until_s := 0.0) -> int:
	_ensure()
	for i in MAX:
		if _live[i] == 0:
			_x[i] = at.x
			_z[i] = at.y
			_kind[i] = kind
			_r[i] = radius if radius > 0.0 else float(KIND_RADIUS[clampi(kind, 0, KIND_RADIUS.size() - 1)])
			_until[i] = until_s
			_live[i] = 1
			_gen[i] += 1
			_count += 1
			return i | ((_gen[i] & 0xFFFFFF) << 8)
	return -1


static func unregister(handle: int) -> bool:
	if handle < 0 or _x.size() != MAX:
		return false
	var i := handle & 0xFF
	if _live[i] == 0 or (_gen[i] & 0xFFFFFF) != (handle >> 8):
		return false
	_live[i] = 0
	_count -= 1
	return true


## Frees every hazard whose expiry time has passed.
static func prune(now_s: float) -> int:
	if _x.size() != MAX:
		return 0
	var freed := 0
	for i in MAX:
		if _live[i] == 1 and _until[i] > 0.0 and now_s >= _until[i]:
			_live[i] = 0
			_count -= 1
			freed += 1
	return freed


static func clear() -> void:
	if _x.size() != MAX:
		return
	_live.fill(0)
	_count = 0


static func count() -> int:
	return _count


## Fills out[0..n-1] with the slots of the live hazards whose avoid circle (radius + reach) contains `at`; returns n.
static func query(at: Vector2, reach: float, out: PackedInt32Array) -> int:
	if _count == 0:
		return 0
	var n := 0
	for i in MAX:
		if _live[i] == 0:
			continue
		var rr := _r[i] + reach
		var dx := at.x - _x[i]
		var dz := at.y - _z[i]
		if dx * dx + dz * dz <= rr * rr and n < out.size():
			out[n] = i
			n += 1
	return n


## True when `at` is inside a hazard's own circle (not its reach margin).
static func inside(at: Vector2) -> bool:
	if _count == 0:
		return false
	for i in MAX:
		if _live[i] == 0:
			continue
		var dx := at.x - _x[i]
		var dz := at.y - _z[i]
		if dx * dx + dz * dz < _r[i] * _r[i]:
			return true
	return false


static func slot_x(i: int) -> float:
	return _x[i]


static func slot_z(i: int) -> float:
	return _z[i]


static func slot_radius(i: int) -> float:
	return _r[i]


static func slot_kind(i: int) -> int:
	return _kind[i]
