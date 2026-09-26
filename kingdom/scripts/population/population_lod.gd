class_name PopulationLOD
extends Node3D
## Gives simulated people a body near the player:
##   within FULL_RANGE (nearest MAX_FULL)  -> animated character with a name tag
##   within SPRITE_RANGE                   -> directional sprite in a MultiMesh
##   beyond                                -> data only (WorldSim)

const FULL_RANGE := 45.0
const SPRITE_RANGE := 220.0
const MAX_FULL := 24
const MAX_SPRITES := 300
const MAX_SPAWNS_PER_TICK := 3
## Job index -> look id (see Main._bake_looks).
const JOB_LOOK := ["peasant", "worker", "merchant", "guard", "worker", "peasant"]
const LOOK_MODEL := {
	"peasant": ["Rogue_Hooded", []],
	"worker": ["Barbarian", []],
	"merchant": ["Mage", []],
	"guard": ["Knight", ["Knight_Helmet", "1H_Sword"]],
}

var focus := Vector3.ZERO
var full_count := 0
var sprite_count := 0

var _full: Dictionary = {}        # person id -> Villager
var _multimeshes: Dictionary = {} # look -> MultiMesh
var _timer := 0.0


func setup(baker: ImpostorBaker) -> void:
	for look: String in LOOK_MODEL:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ImpostorBaker.quad()
		mm.instance_count = MAX_SPRITES
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = baker.materials.get(look)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1500, 10000))
		add_child(mmi)
		_multimeshes[look] = mm


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		refresh()


func refresh() -> void:
	var p2 := Vector2(focus.x, focus.z)
	var ids := WorldSim.people_near(p2, SPRITE_RANGE)
	var dists := []
	for i in ids:
		if WorldSim.is_indoors(i):
			continue
		dists.append([WorldSim.pos[i].distance_squared_to(p2), i])
	dists.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	var want_full := {}
	for entry in dists:
		if want_full.size() >= MAX_FULL or entry[0] > FULL_RANGE * FULL_RANGE:
			break
		want_full[entry[1]] = true
	for id in _full.keys():
		if not want_full.has(id):
			_full[id].queue_free()
			_full.erase(id)
	var spawned := 0
	for id in want_full:
		if not _full.has(id) and spawned < MAX_SPAWNS_PER_TICK:
			_full[id] = _spawn(id)
			spawned += 1
	full_count = _full.size()
	var nearest_id: int = dists[0][1] if not dists.is_empty() and dists[0][0] < 36.0 else -1
	for id in _full:
		(_full[id] as Villager).show_tag = id == nearest_id

	var used := {}
	for look in _multimeshes:
		used[look] = 0
	for entry in dists:
		var id: int = entry[1]
		if _full.has(id):
			continue
		var look: String = JOB_LOOK[WorldSim.job[id]]
		var n: int = used[look]
		if n >= MAX_SPRITES:
			continue
		var pp: Vector2 = WorldSim.pos[id]
		var heading: Vector2 = WorldSim.target[id] - pp
		var yaw := atan2(heading.x, heading.y) if heading.length() > 0.1 else float(id % 628) / 100.0
		var t := Transform3D(Basis(Vector3.UP, yaw), Vector3(pp.x, WorldGen.height(pp.x, pp.y), pp.y))
		(_multimeshes[look] as MultiMesh).set_instance_transform(n, t)
		used[look] = n + 1
	sprite_count = 0
	for look in _multimeshes:
		(_multimeshes[look] as MultiMesh).visible_instance_count = used[look]
		sprite_count += used[look]


func _spawn(id: int) -> Villager:
	var look: String = JOB_LOOK[WorldSim.job[id]]
	var model: Array = LOOK_MODEL[look]
	var keep: Array[String] = []
	keep.assign(model[1])
	var v := Villager.create(id, model[0], keep)
	add_child(v)
	return v
