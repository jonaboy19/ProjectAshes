extends RefCounted
## F10: a bonded Soulbeast makes nearby wild wolves wary of its player. One static record (no per-wolf scan, no
## allocation): the companion publishes its position each think, wolf.gd asks wary_factor(own position).
## Preloaded (no class_name).

const RADIUS := 30.0
const WARY := 0.55          # wolf aggro / stalk range multiplier inside the aura

static var _owner_id := 0
static var _pos := Vector2.INF
static var _on := false


## The companion (re)publishes itself; `on` false withdraws it (downed, unbonded).
static func set_companion(who: Node3D, on: bool) -> void:
	if who == null:
		return
	if on:
		_owner_id = who.get_instance_id()
		_pos = Vector2(who.global_position.x, who.global_position.z)
		_on = true
	elif _owner_id == who.get_instance_id():
		_on = false


static func clear(who: Object = null) -> void:
	if who == null or who.get_instance_id() == _owner_id:
		_on = false
		_pos = Vector2.INF
		_owner_id = 0


static func active() -> bool:
	return _on


## 1.0 normally; WARY when a bonded Soulbeast is within RADIUS of `at` (x, z).
static func wary_factor(at: Vector3) -> float:
	if not _on:
		return 1.0
	return WARY if Vector2(at.x, at.z).distance_squared_to(_pos) < RADIUS * RADIUS else 1.0
