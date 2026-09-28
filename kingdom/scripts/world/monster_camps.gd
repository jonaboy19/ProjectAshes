class_name MonsterCamps
extends Node3D
## CampMonster settlements from data/world/first_region.json: the goblin warren and
## the orc village. Props are placed once; residents get bodies while the
## player is within range (like wolf packs) and lose them far away.
## Residents fight as a group but take turns: CampMonster shares attack tokens,
## so only two or three swing at the player at a time while the rest circle.

const PACK := "res://assets/incoming/3dassets-dev-ai/medieval-mmo-starter-realm/"
const GEN := "res://assets/generated/"
const SPAWN_RANGE := 260.0
const DESPAWN_RANGE := 420.0

var focus := Vector3.ZERO
var _camps: Array[Dictionary] = []   # {place, species, roster: [[species, n]], root, residents: Array}
var _timer := 0.0


func _ready() -> void:
	for pl: Dictionary in Life.lore.places_in_region():
		match String(pl.get("kind", "")):
			"goblin_warren":
				_add_camp(pl, "goblin", [["goblin", 7]])
			"orc_village":
				# Five orcs and the warchief's troll (Meshy troll, 3 m) guarding the hold.
				_add_camp(pl, "orc", [["orc", 5], ["troll", 1]])


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, WorldGen.height(p.x, p.y), p.y)


func _model(paths: Array, height := 0.0) -> Node3D:
	for path: String in paths:
		if ResourceLoader.exists(path):
			var n: Node3D = Assets.scene(path).instantiate()
			if height > 0.0:
				var box := Assets.visual_aabb(n)
				n.scale = Vector3.ONE * (height / maxf(box.size.y, 0.01))
			return n
	return null


func _place(root: Node3D, paths: Array, at: Vector2, yaw: float, height := 0.0) -> void:
	var n := _model(paths, height)
	if n == null:
		return
	root.add_child(n)
	n.global_position = _ground(at) - Vector3(0, 0.05, 0)
	n.rotation.y = yaw


func _add_camp(pl: Dictionary, species: String, roster: Array) -> void:
	var c: Vector2 = pl["pos"]
	var r := float(pl.get("radius", 30.0))
	var root := Node3D.new()
	root.name = String(pl.get("id", species))
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pl.get("id", species))
	if species == "goblin":
		_place(root, [PACK + "cave-mouth.glb"], c + Vector2(0, -r * 0.7), 0.0, 6.0)
		for i in 5:
			var a := TAU * i / 5.0 + rng.randf_range(-0.2, 0.2)
			_place(root, [PACK + "goblin-tent.glb"], c + Vector2(cos(a), sin(a)) * r * 0.55, -a + PI * 0.5, 3.0)
		_place(root, [PACK + "goblin-totem.glb"], c + Vector2(3, 3), 0.3, 3.2)
		_place(root, [PACK + "campfire-with-spit.glb"], c, 0.0, 1.2)
	else:
		for i in 6:
			var a := TAU * i / 6.0 + rng.randf_range(-0.15, 0.15)
			_place(root, [GEN + "orc_hut.glb", PACK + "goblin-tent.glb"], c + Vector2(cos(a), sin(a)) * r * 0.55, -a, 5.0)
		var seg := int(ceil(TAU * r / 5.8))     # 6 m palisade sections, slight overlap
		for i in seg:
			if i == 0 or i == seg - 1:
				continue   # gate gap facing east
			var a := TAU * i / seg
			_place(root, [GEN + "orc_palisade.glb"], c + Vector2(cos(a), sin(a)) * r, -a + PI * 0.5, 0.0)
		_place(root, [GEN + "orc_totem.glb", PACK + "goblin-totem.glb"], c, 0.0, 4.5)
		# The chief (Meshy orc warchief on the UAL rig) holds court by the totem.
		var chief := Assets.character("Orc_Warchief", 2.2, [])
		root.add_child(chief)
		var cp := c + Vector2(3.0, -2.0)
		chief.global_position = _ground(cp)
		chief.rotation.y = atan2(-3.0, 2.0)
		var ap := Assets.animation_player(chief)
		if ap:
			ap.play("Idle" if ap.has_animation("Idle") else ap.get_animation_list()[0])
		var tag := Label3D.new()
		var chief_info: Dictionary = pl.get("chief", {})
		tag.text = "%s · %s" % [chief_info.get("name", "Orc Warchief"), chief_info.get("title", "Warchief")]
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.008
		tag.font_size = 30
		tag.outline_size = 8
		tag.modulate = Color("ffb070")
		tag.position.y = 2.6
		chief.add_child(tag)
		_place(root, [PACK + "campfire-with-spit.glb"], c + Vector2(5, 4), 0.0, 1.4)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.light_energy = 1.4
	fire.omni_range = 12.0
	root.add_child(fire)
	fire.global_position = _ground(c) + Vector3(0, 1.5, 0)
	_camps.append({"place": pl, "species": species, "roster": roster, "root": root, "residents": []})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p := Vector2(focus.x, focus.z)
	for camp in _camps:
		var c: Vector2 = camp["place"]["pos"]
		var d := p.distance_to(c)
		var res: Array = camp["residents"]
		if d < SPAWN_RANGE and res.is_empty():
			_spawn(camp)
		elif d > DESPAWN_RANGE and not res.is_empty():
			for m in res:
				if is_instance_valid(m) and (m as CampMonster).named == "":
					m.queue_free()
			res.clear()


## Spawns residents now (used by screenshots).
func spawn_all_near(p: Vector3) -> void:
	focus = p
	_timer = 0.0
	_process(0.0)


func _spawn(camp: Dictionary) -> void:
	var c: Vector2 = camp["place"]["pos"]
	var r := float(camp["place"].get("radius", 30.0))
	for entry: Array in camp["roster"]:
		for i in int(entry[1]):
			var m := CampMonster.new()
			m.species = entry[0]
			m.home = c
			m.home_radius = r * (0.45 if entry[0] == "troll" else 0.8)
			add_child(m)
			if m.is_queued_for_deletion():
				continue        # model not available
			m.died.connect(func(dead_m: CampMonster) -> void: Life.on_monster_killed(dead_m.species))
			var q := c + Vector2(randf_range(-r, r), randf_range(-r, r)) * 0.5
			m.global_position = _ground(q)
			(camp["residents"] as Array).append(m)
