class_name FrontierPresence
extends Node3D
## Gives the frontier simulation a body near the player: runestones (with a
## glow that follows their strength) and wolf packs spawned from dens within
## range. Killed wolves are culled from their den in the ecology.

const RUNESTONE := "res://assets/generated/runestone.glb"
const PACK_RANGE := 260.0
const DESPAWN_RANGE := 360.0

var focus := Vector3.ZERO
var _stone_nodes: Dictionary = {}     # stone id -> {node, light}
var _packs: Dictionary = {}           # den id -> Array[Wolf]
var _timer := 0.0


func _ready() -> void:
	for s in Frontier.runestones.stones:
		_build_stone(s)
	Frontier.runestones.stone_changed.connect(_refresh_stone)


func _build_stone(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = s["name"].replace(" ", "")
	var p: Vector2 = s["pos"]
	root.position = Vector3(p.x, WorldGen.height(p.x, p.y) - 0.1, p.y)
	root.rotation.y = atan2(-p.x, -p.y)
	var model: Node3D = (load(RUNESTONE) as PackedScene).instantiate()
	model.scale = Vector3.ONE * 1.25
	root.add_child(model)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.85, 1.0)
	light.omni_range = 9.0
	light.position = Vector3(0, 2.2, 0)
	root.add_child(light)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.7
	cyl.height = 4.0
	shape.shape = cyl
	shape.position.y = 2.0
	body.add_child(shape)
	root.add_child(body)
	add_child(root)
	_stone_nodes[s["id"]] = {"node": root, "light": light}
	_refresh_stone(s)


func _refresh_stone(s: Dictionary) -> void:
	if not _stone_nodes.has(s["id"]):
		return
	var strength := Frontier.runestones.strength(s)
	var light: OmniLight3D = _stone_nodes[s["id"]]["light"]
	light.light_energy = 0.2 + strength * 1.6
	light.visible = strength > 0.05


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p := Vector2(focus.x, focus.z)
	for den in Frontier.ecology.dens:
		var id: int = den["id"]
		var d := p.distance_to(den["pos"])
		if den["alive"] and d < PACK_RANGE and not _packs.has(id):
			_spawn_pack(den)
		elif _packs.has(id) and d > DESPAWN_RANGE:
			for w in _packs[id]:
				if is_instance_valid(w):
					w.queue_free()
			_packs.erase(id)


func _spawn_pack(den: Dictionary) -> void:
	var list: Array = []
	var count := mini(int(den["population"]), RAMonsterEcology.SPECIES[den["species"]]["pack"])
	for i in count:
		var w := Wolf.new()
		w.den_id = den["id"]
		w.home = den["pos"]
		w.territory = den["territory"]
		add_child(w)
		var q: Vector2 = den["pos"] + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
		w.died.connect(func(dead_wolf: Wolf) -> void:
			Frontier.ecology.cull(dead_wolf.den_id, 1))
		list.append(w)
	_packs[den["id"]] = list
