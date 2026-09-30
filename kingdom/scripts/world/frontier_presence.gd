class_name FrontierPresence
extends Node3D
## Gives the frontier simulation a body near the player: runestones (ring,
## waystones and every roadside stone alike, with a glow that follows their
## condition) and wolf packs spawned from dens within range. Killed wolves are
## culled from their den in the ecology. Deep in the wilds at night, far from
## any road or coverage, this is also where the rare "you should leave" apex
## encounter is rolled and given a body.

const RUNESTONE := "res://assets/generated/runestone.glb"
## Meshy runestone with glowing channels (local session); the Blender one is the fallback.
const RUNESTONE_MESHY := "res://assets/incoming/ai3d/meshy/landmark_runestone_lod0.glb"
const RUNESTONE_MESHY_FAR := "res://assets/incoming/ai3d/meshy/landmark_runestone_lod1.glb"
const RUNESTONE_HEIGHT := 3.4
## Packs get bodies when the player nears their territory and lose them well past it.
const PACK_MARGIN := 120.0
const DESPAWN_MARGIN := 260.0
## Runestones now line whole roads (scores of them across the map), so they get
## the same near-the-player spawn ring as everything else instead of all
## existing at once.
const STONE_BUILD := 200.0
const STONE_FREE := 320.0
## Deep wilderness, night, rare: an apex predator the player should flee, not fight.
const APEX_CHECK_INTERVAL := 25.0
const APEX_MIN_ROAD_DISTANCE := 140.0
const APEX_CHANCE := 0.03
const APEX_SPAWN_RANGE := Vector2(45.0, 70.0)
const APEX_LIFETIME := 100.0

var focus := Vector3.ZERO
var _stone_nodes: Dictionary = {}     # stone id -> {node, light, tween}
var _packs: Dictionary = {}           # den id -> Array[Wolf]
var _timer := 0.0
var _apex_timer := 0.0
var _apex_active := false


func _ready() -> void:
	Frontier.runestones.stone_changed.connect(_refresh_stone)


func _build_stone(s: Dictionary) -> void:
	var root := Node3D.new()
	root.name = s["name"].replace(" ", "")
	var p: Vector2 = s["pos"]
	root.position = Vector3(p.x, WorldGen.height(p.x, p.y) - 0.1, p.y)
	root.rotation.y = atan2(-p.x, -p.y)
	if ResourceLoader.exists(RUNESTONE_MESHY):
		for i in 2:
			var path := RUNESTONE_MESHY if i == 0 else RUNESTONE_MESHY_FAR
			if not ResourceLoader.exists(path):
				continue
			var m: Node3D = Assets.scene(path).instantiate()
			var box := Assets.visual_aabb(m)
			var k := RUNESTONE_HEIGHT / maxf(box.size.y, 0.01)
			m.scale = Vector3.ONE * k
			m.position.y = -box.position.y * k - 0.05
			for g in m.find_children("*", "GeometryInstance3D", true, false):
				var gi := g as GeometryInstance3D
				gi.visibility_range_begin = 0.0 if i == 0 else 60.0
				gi.visibility_range_end = 60.0 if i == 0 else 500.0
			root.add_child(m)
	else:
		var model: Node3D = Assets.scene(RUNESTONE).instantiate()
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
	var entry: Dictionary = _stone_nodes[s["id"]]
	var light: OmniLight3D = entry["light"]
	var cond := Frontier.runestones.condition_name(s)
	var strength := Frontier.runestones.strength(s)
	if entry.get("tween") is Tween and (entry["tween"] as Tween).is_valid():
		(entry["tween"] as Tween).kill()
	match cond:
		"dark":
			light.visible = false
		"cracked":
			# A slow flicker (a tween, not a per-frame flag) rather than a steady glow.
			light.visible = true
			var t := create_tween().set_loops()
			t.tween_property(light, "light_energy", 0.15 + strength * 0.4, 0.35)
			t.tween_property(light, "light_energy", 0.6 + strength * 1.2, 0.55)
			entry["tween"] = t
		_:
			light.visible = true
			light.light_energy = 0.2 + strength * 1.6


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p := Vector2(focus.x, focus.z)
	for s in Frontier.runestones.stones:
		var d := p.distance_to(s["pos"])
		if d < STONE_BUILD and not _stone_nodes.has(s["id"]):
			_build_stone(s)
		elif d > STONE_FREE and _stone_nodes.has(s["id"]):
			_free_stone(s["id"])
	for den in Frontier.ecology.dens:
		var id: int = den["id"]
		var dd := p.distance_to(den["pos"])
		var terr: float = den["territory"]
		if den["alive"] and dd < terr + PACK_MARGIN and not _packs.has(id):
			_spawn_pack(den)
		elif _packs.has(id) and dd > terr + DESPAWN_MARGIN:
			for w in _packs[id]:
				if is_instance_valid(w):
					w.queue_free()
			_packs.erase(id)
	_apex_timer -= 1.0
	if _apex_timer <= 0.0:
		_apex_timer = APEX_CHECK_INTERVAL
		_maybe_apex_encounter(p)


func _free_stone(id: int) -> void:
	var entry: Dictionary = _stone_nodes[id]
	if entry.get("tween") is Tween and (entry["tween"] as Tween).is_valid():
		(entry["tween"] as Tween).kill()
	if is_instance_valid(entry["node"]):
		entry["node"].queue_free()
	_stone_nodes.erase(id)


## The rare, distant thing that should make the player leave rather than fight:
## far from any road or runestone, only in the deepest, loneliest hours.
func _maybe_apex_encounter(p: Vector2) -> void:
	if _apex_active:
		return
	if Frontier.danger_mult(WorldSim.time_of_day) < 3.0:
		return
	if Frontier.runestones.coverage(p) > 0.02 or WorldGen.road_distance(p.x, p.y) < APEX_MIN_ROAD_DISTANCE:
		return
	if randf() > APEX_CHANCE:
		return
	var ang := randf() * TAU
	var dist := randf_range(APEX_SPAWN_RANGE.x, APEX_SPAWN_RANGE.y)
	var pos := p + Vector2(cos(ang), sin(ang)) * dist
	if Frontier.runestones.coverage(pos) > 0.02 or WorldGen.road_distance(pos.x, pos.y) < APEX_MIN_ROAD_DISTANCE * 0.7:
		return
	_apex_active = true
	Game.say("Something enormous moves in the trees.")
	var beast := Wolf.new()
	beast.species = "bear"
	beast.home = pos
	beast.territory = 320.0
	add_child(beast)
	beast.global_position = Vector3(pos.x, WorldGen.height(pos.x, pos.y), pos.y)
	beast.scale = Vector3.ONE * 1.7          # scaled up: this is not an ordinary bear
	if Audio.has_sound("bear_roar"):
		Audio.play_sfx("bear_roar", beast.global_position, 3.0, 0.0)
	beast.died.connect(func(_w: Wolf) -> void: _apex_active = false)
	get_tree().create_timer(APEX_LIFETIME).timeout.connect(func() -> void:
		if is_instance_valid(beast):
			beast.queue_free()
		_apex_active = false)


func _spawn_pack(den: Dictionary) -> void:
	var list: Array = []
	var count := mini(int(den["population"]), RAMonsterEcology.SPECIES[den["species"]]["pack"])
	for i in count:
		var w := Wolf.new()
		# Apex and Rift-tainted dens reuse the closest body until they get their own models.
		var sp := Frontier.ecology.variant_for(String(den["species"]), den["pos"])   # Region1 hook H4: Scar cells make rift variants
		w.species = {"troll": "bear", "wyvern": "bear", "bear": "bear", "corrupted_wolf": "wolf"}.get(sp, sp)
		if sp == "troll" or sp == "wyvern":
			w.scale = Vector3.ONE * 1.9
		elif sp == "corrupted_wolf":
			w.scale = Vector3.ONE * 1.2
		w.den_id = den["id"]
		w.home = den["pos"]
		w.territory = den["territory"]
		add_child(w)
		var q: Vector2 = den["pos"] + Vector2(randf_range(-8, 8), randf_range(-8, 8))
		w.global_position = Vector3(q.x, WorldGen.height(q.x, q.y), q.y)
		if sp == "corrupted_wolf":
			w.set_meta("rift", true)
			RiftVariants.apply_creature(w, "wolf")   # violet fur (L4 rift kit)
		w.died.connect(func(dead_wolf: Wolf) -> void:
			Frontier.ecology.cull(dead_wolf.den_id, 1)
			Life.on_wolf_killed(dead_wolf.global_position, dead_wolf.den_id, "rift_wolf" if dead_wolf.has_meta("rift") else ""))
		list.append(w)
	_packs[den["id"]] = list
